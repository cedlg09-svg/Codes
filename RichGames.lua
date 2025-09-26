-- Hate's AutoFarm - Full Version
local ok, mainErr = pcall(function()
    -- ==== CONFIG ====
    local SAFE_DELAY_BETWEEN_ASSIGN = 0.18
    local JOIN_DELAY = 0.06
    local CHANGE_DELAY = 0.04
    local MAIN_LOOP_DELAY = 0.8
    local SAFE_LOOP_DELAY = 1.5
    local EQUIP_WAIT = 0.45
    local RETARGET_DELAY = 0.3

    local WorldsTable = {
        ["Spawn"] = {"Shop","Town","Forest","Beach","Mine","Winter","Glacier","Desert","Volcano","Cave","Tech Entry","VIP"},
        ["Fantasy"] = {"Fantasy Shop","Enchanted Forest","Portals","Ancient Island","Samurai Island","Candy Island","Haunted Island","Hell Island","Heaven Island","Heaven's Gate"},
        ["Tech"] = {"Tech Shop","Tech City","Dark Tech","Steampunk","Steampunk Chest Area","Alien Lab","Alien Forest","Giant Alien Chest","Glitch","Hacker Portal"},
        ["Void"] = {"The Void"},
        ["Axolotl Ocean"] = {"Axolotl Ocean","Axolotl Deep Ocean","Axolotl Cave"},
        ["Pixel"] = {"Pixel Forest","Pixel Kyoto","Pixel Alps","Pixel Vault"},
        ["Cat"] = {"Cat Paradise","Cat Backyard","Cat Taiga","Cat Throne Room"}
    }

    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local Workspace = game:GetService("Workspace")
    local LocalPlayer = Players.LocalPlayer
    local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
    local Network = ReplicatedStorage:FindFirstChild("Network")

    -- ==== SAFE REMOTE CALLER ====
    local function CallRemote(name,args)
        args=args or {}
        if not Network then return false end
        local r = Network:FindFirstChild(name)
        if not r then return false end
        if r.ClassName=="RemoteFunction" then
            local ok,res=pcall(function() return r:InvokeServer(table.unpack(args)) end)
            return ok,res
        elseif r.ClassName=="RemoteEvent" then
            local ok,res=pcall(function() r:FireServer(table.unpack(args)) end)
            return ok,res
        else return false end
    end

    local function GetSave() local ok,res=CallRemote("Get Custom Save") if ok then return res end return nil end
    local function GetCoinsRaw() local ok,res=CallRemote("Get Coins") if ok then return res end return nil end
    local function EquipPet(uid) return CallRemote("Equip Pet",{uid}) end
    local function JoinCoin(id,pets) return CallRemote("Join Coin",{id,pets}) end
    local function ChangePetTarget(uid,ttype,id) return CallRemote("Change Pet Target",{uid,ttype,id}) end
    local function FarmCoin(id,uid) return CallRemote("Farm Coin",{id,uid}) end
    local function ClaimOrbs(arg) return CallRemote("Claim Orbs",{arg or {}}) end
    local function EquipBestPetsRemote()
        if not Network then return false end
        local r=Network:FindFirstChild("Equip Best Pets")
        if not r then return false end
        local ok,_=pcall(function() r:InvokeServer() end)
        return ok
    end

    -- ==== UTILITIES ====
    local function safe_delay(t,f) if type(t)=="number" and type(f)=="function" then task.delay(t,f) end end
    local function safeNumber(x) if type(x)=="number" then return x elseif type(x)=="string" then return tonumber(x) or 0 end return 0 end
    local function buildPetListFromSave(save)
        if not save then return {} end
        local petsTbl = save.Pets or {}
        local out={}
        for k,v in pairs(petsTbl) do
            if type(v)=="table" then v.uid=v.uid or k table.insert(out,v) end
        end
        return out
    end
    local function sortByPowerDesc(list)
        table.sort(list,function(a,b) return safeNumber(a.s or a.power or a.p or 0) > safeNumber(b.s or b.power or b.p or 0) end)
    end
    local function pickTopNFromSave(n)
        local save=GetSave()
        if not save then return {} end
        local maxEquip=tonumber(save.MaxEquipped or 8) or 8
        if n then maxEquip=n end
        local all=buildPetListFromSave(save)
        sortByPowerDesc(all)
        local chosen={}
        for i=1,math.min(maxEquip,#all) do
            if all[i] and all[i].uid then table.insert(chosen,all[i].uid) end
        end
        return chosen
    end

    -- ==== STATE ====
    local SelectedWorld="Spawn"
    local SelectedArea="Town"
    local Enabled=false
    local SafeEnabled=false
    local trackedPets={}
    local trackedPetsSafe={}
    local petToTarget={}
    local targetToPet={}
    local petCooldowns={}

    local function GetEquippedPetUIDs()
        local uids={}
        local save=GetSave()
        if save and save.Pets then
            for _,petData in pairs(save.Pets) do
                if type(petData)=="table" and petData.uid then
                    local isEq=false
                    if petData.equipped==true or petData.eq==true or petData.equip==true then isEq=true end
                    if petData[1]==true or petData["1"]==true then isEq=true end
                    if isEq then table.insert(uids,petData.uid) end
                end
            end
            if #uids>0 then return uids end
        end
        return pickTopNFromSave()
    end

    local function AssignPetToBreakable(petUID,breakId)
        if not petUID or not breakId then return false end
        safe_delay(0,function() JoinCoin(breakId,{petUID}) end)
        safe_delay(JOIN_DELAY,function() ChangePetTarget(petUID,"Coin",breakId) end)
        safe_delay(JOIN_DELAY+CHANGE_DELAY,function() FarmCoin(breakId,petUID) end)
        petToTarget[petUID]=breakId
        targetToPet[breakId]=petUID
        petCooldowns[petUID]=tick()
        return true
    end

    local function ClearAssignmentForPet(petUID)
        if not petUID then return end
        local t=petToTarget[petUID]
        if t then petToTarget[petUID]=nil targetToPet[t]=nil end
        petCooldowns[petUID]=tick()+RETARGET_DELAY
    end

    local function FreeStaleAssignments(coins)
        local present={}
        if coins then for id,_ in pairs(coins) do present[id]=true end end
        for petUID,tid in pairs(petToTarget) do
            if not present[tid] then ClearAssignmentForPet(petUID) end
        end
    end

    local function GetAvailableBreakables(coins)
        local available={}
        if not coins then return available end
        for id,item in pairs(coins) do
            if type(item)=="table" then
                local w=item.w or item.world
                local a=item.a or item.area
                if tostring(w)==tostring(SelectedWorld) and tostring(a)==tostring(SelectedArea) then
                    if not targetToPet[id] then table.insert(available,{id=id,data=item}) end
                end
            end
        end
        return available
    end

    local function FillAssignments(coins)
        local petUIDs=GetEquippedPetUIDs()
        if #petUIDs==0 then return end
        local freePets={}
        for _,uid in ipairs(petUIDs) do
            if not petToTarget[uid] then
                local cd=petCooldowns[uid] or 0
                if tick()>=cd then table.insert(freePets,uid) end
            end
        end
        if #freePets==0 then return end
        local available=GetAvailableBreakables(coins)
        if #available==0 then return end
        local count=math.min(#freePets,#available)
        for i=1,count do
            local pet=freePets[i]
            local target=available[i]
            if pet and target and target.id then pcall(function() AssignPetToBreakable(pet,target.id) end) task.wait(0.02) end
        end
    end

    -- ==== GUI ====
    local function makeDropdown(parent,posX,posY,width,labelText,options,onSelect)
        local label=Instance.new("TextLabel",parent)
        label.Size=UDim2.new(0,width,0,18)
        label.Position=UDim2.new(0,posX,0,posY)
        label.BackgroundTransparency=1
        label.Text=labelText
        label.TextColor3=Color3.new(1,1,1)
        label.Font=Enum.Font.SourceSans
        label.TextSize=14

        local btn=Instance.new("TextButton",parent)
        btn.Size=UDim2.new(0,width,0,26)
        btn.Position=UDim2.new(0,posX,0,posY+18)
        btn.Text=options[1] or "None"
        btn.Font=Enum.Font.SourceSans
        btn.TextSize=14
        btn.TextColor3=Color3.new(1,1,1)
        btn.BackgroundColor3=Color3.fromRGB(60,60,60)
        Instance.new("UICorner",btn).CornerRadius=UDim.new(0,6)

        local menu=Instance.new("Frame",parent)
        menu.Size=UDim2.new(0,width,0,math.min(#options*24,200))
        menu.Position=UDim2.new(0,posX,0,posY+46)
        menu.Visible=false
        menu.BackgroundColor3=Color3.fromRGB(40,40,40)
        Instance.new("UICorner",menu).CornerRadius=UDim.new(0,6)
        local layout=Instance.new("UIListLayout",menu)
        layout.Padding=UDim.new(0,4)

        local function populate(opts)
            for _,c in ipairs(menu:GetChildren()) do if not c:IsA("UIListLayout") then c:Destroy() end end
            for _,opt in ipairs(opts) do
                local optBtn=Instance.new("TextButton",menu)
                optBtn.Size=UDim2.new(1,-8,0,20)
                optBtn.Position=UDim2.new(0,4,0,0)
                optBtn.Text=opt
                optBtn.BackgroundTransparency=1
                optBtn.Font=Enum.Font.SourceSans
                optBtn.TextColor3=Color3.new(1,1,1)
                optBtn.TextSize=14
                optBtn.MouseButton1Click:Connect(function()
                    btn.Text=opt
                    menu.Visible=false
                    onSelect(opt)
                end)
            end
            menu.Size=UDim2.new(0,width,0,math.min(#opts*24,200))
        end
        populate(options)
        btn.MouseButton1Click:Connect(function() menu.Visible=not menu.Visible end)
        return {Button=btn,Menu=menu,Label=label,SetOptions=populate}
    end

    local function CreateGUI()
        local screenGui=Instance.new("ScreenGui",PlayerGui)
        screenGui.Name="HatesAutoFarm"
        screenGui.ResetOnSpawn=false

        local frame=Instance.new("Frame",screenGui)
        frame.Size=UDim2.new(0,320,0,220)
        frame.Position=UDim2.new(0,10,0,36)
        frame.BackgroundColor3=Color3.fromRGB(0,0,0)
        Instance.new("UICorner",frame).CornerRadius=UDim.new(0,8)

        local title=Instance.new("TextLabel",frame)
        title.Size=UDim2.new(1,0,0,26)
        title.Position=UDim2.new(0,0,0,6)
        title.BackgroundTransparency=1
        title.Font=Enum.Font.SourceSansBold
        title.TextSize=16
        title.TextColor3=Color3.new(1,1,1)
        title.Text="Hate's AutoFarm"

        local safeBtn=Instance.new("TextButton",frame)
        safeBtn.Size=UDim2.new(0,140,0,26)
        safeBtn.Position=UDim2.new(0,10,0,36)
        safeBtn.Text="Safe Mode: Off"
        safeBtn.Font=Enum.Font.SourceSans
        safeBtn.TextColor3=Color3.new(1,1,1)
        safeBtn.BackgroundColor3=Color3.fromRGB(40,40,40)
        Instance.new("UICorner",safeBtn).CornerRadius=UDim.new(0,6)
        safeBtn.MouseButton1Click:Connect(function()
            SafeEnabled=not SafeEnabled
            safeBtn.Text="Safe Mode: "..(SafeEnabled and "On" or "Off")
        end)

        local refreshBtn=Instance.new("TextButton",frame)
        refreshBtn.Size=UDim2.new(0,140,0,26)
        refreshBtn.Position=UDim2.new(0,10,0,67)
        refreshBtn.Text="Refresh Area"
        refreshBtn.Font=Enum.Font.SourceSans
        refreshBtn.TextColor3=Color3.new(1,1,1)
        refreshBtn.BackgroundColor3=Color3.fromRGB(60,60,60)
        Instance.new("UICorner",refreshBtn).CornerRadius=UDim.new(0,6)

        local worldDropdown=makeDropdown(frame,10,100,140,"World",(function() local t={} for k,_ in pairs(WorldsTable) do table.insert(t,k) end table.sort(t) return t end)(),function(selected)
            SelectedWorld=selected
            local areas=WorldsTable[SelectedWorld] or {}
            areaDropdown.SetOptions(areas)
            if #areas>0 then SelectedArea=areas[1]; areaDropdown.Button.Text=areas[1] else SelectedArea=""; areaDropdown.Button.Text="None" end
            petToTarget={};targetToPet={};petCooldowns={}
        end)

        local areaDropdown=makeDropdown(frame,168,100,140,"Area",WorldsTable[SelectedWorld] or {},function(selected)
            SelectedArea=selected
            petToTarget={};targetToPet={};petCooldowns={}
        end)

        refreshBtn.MouseButton1Click:Connect(function()
            local areas=WorldsTable[SelectedWorld] or {}
            areaDropdown.SetOptions(areas)
            if #areas>0 then SelectedArea=areas[1]; areaDropdown.Button.Text=areas[1] else SelectedArea=""; areaDropdown.Button.Text="None" end
        end)

        local pickBtn=Instance.new("TextButton",frame)
        pickBtn.Size=UDim2.new(0.48,-8,0,36)
        pickBtn.Position=UDim2.new(0,10,0,140)
        pickBtn.Text="Pick Best Pets"
        pickBtn.Font=Enum.Font.SourceSansBold
        pickBtn.BackgroundColor3=Color3.fromRGB(70,70,70)
        pickBtn.TextColor3=Color3.new(1,1,1)
        Instance.new("UICorner",pickBtn).CornerRadius=UDim.new(0,6)

        local startBtn=Instance.new("TextButton",frame)
        startBtn.Size=UDim2.new(0.48,-8,0,36)
        startBtn.Position=UDim2.new(0,168,0,140)
        startBtn.Text="Start"
        startBtn.Font=Enum.Font.SourceSansBold
        startBtn.BackgroundColor3=Color3.fromRGB(34,139,34)
        startBtn.TextColor3=Color3.new(1,1,1)
        Instance.new("UICorner",startBtn).CornerRadius=UDim.new(0,6)

        local safeStartBtn=Instance.new("TextButton",frame)
        safeStartBtn.Size=UDim2.new(0.48,-8,0,36)
        safeStartBtn.Position=UDim2.new(0,10,0,180)
        safeStartBtn.Text="Safe Farm"
        safeStartBtn.Font=Enum.Font.SourceSansBold
        safeStartBtn.BackgroundColor3=Color3.fromRGB(70,70,70)
        safeStartBtn.TextColor3=Color3.new(1,1,1)
        Instance.new("UICorner",safeStartBtn).CornerRadius=UDim.new(0,6)

        local status=Instance.new("TextLabel",frame)
        status.Size=UDim2.new(1,-20,0,26)
        status.Position=UDim2.new(0,10,0,220-36)
        status.BackgroundTransparency=1
        status.TextColor3=Color3.new(1,1,1)
        status.TextWrapped=true
        status.Font=Enum.Font.SourceSans
        status.TextSize=14
        status.Text="Status: Idle"

        local minBtn=Instance.new("TextButton",frame)
        minBtn.Size=UDim2.new(0,20,0,20)
        minBtn.Position=UDim2.new(1,-24,0,4)
        minBtn.Text="_"
        minBtn.TextSize=14
        minBtn.Font=Enum.Font.SourceSansBold
        minBtn.TextColor3=Color3.new(1,1,1)
        minBtn.BackgroundColor3=Color3.fromRGB(50,50,50)
        Instance.new("UICorner",minBtn).CornerRadius=UDim.new(0,4)
        minBtn.MouseButton1Click:Connect(function() frame.Visible=not frame.Visible end)

        pickBtn.MouseButton1Click:Connect(function()
            status.Text="Status: Equipping best pets..."
            trackedPets=pickTopNFromSave()
            for _,uid in ipairs(trackedPets) do pcall(function() EquipPet(uid) end) task.wait(0.06) end
            task.wait(EQUIP_WAIT)
            status.Text="Status: Equipped "..#trackedPets.." pets"
        end)

        startBtn.MouseButton1Click:Connect(function()
            Enabled=not Enabled
            if Enabled then startBtn.Text="Stop"; startBtn.BackgroundColor3=Color3.fromRGB(178,34,34); status.Text="Status: Farming ("..SelectedWorld.." - "..SelectedArea..")"
            else startBtn.Text="Start"; startBtn.BackgroundColor3=Color3.fromRGB(34,139,34); status.Text="Status: Stopped" end
        end)

        safeStartBtn.MouseButton1Click:Connect(function()
            SafeEnabled=not SafeEnabled
            safeStartBtn.Text=SafeEnabled and "Safe Farm: On" or "Safe Farm"
        end)

        return {Gui=screenGui,Frame=frame,Status=status,WorldDropdown=worldDropdown,AreaDropdown=areaDropdown}
    end

    local ui=CreateGUI()

    -- ==== MAIN LOOP ====
    task.spawn(function()
        while true do
            local coins=GetCoinsRaw()
            if coins then
                if Enabled then
                    FreeStaleAssignments(coins)
                    FillAssignments(coins)
                    pcall(function() ClaimOrbs({}) end)
                end
                if SafeEnabled then
                    task.wait(SAFE_LOOP_DELAY)
                    FreeStaleAssignments(coins)
                    FillAssignments(coins)
                    pcall(function() ClaimOrbs({}) end)
                end
            else
                ui.Status.Text="Status: Waiting for coins..."
            end
            task.wait(MAIN_LOOP_DELAY)
        end
    end)

    print("[AutoFarm] Loaded - GUI ready. Pick Best Pets -> Start.")
end)

if not ok then warn("[AutoFarm] Error:",mainErr) else print("[AutoFarm] Script executed successfully!") end
