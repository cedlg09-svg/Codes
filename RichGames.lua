-- Hate's Autofarm — Full Version with Safe Mode
local ok, mainErr = pcall(function()
    -- ==== CONFIG ====
    local JOIN_DELAY = 0.06
    local CHANGE_DELAY = 0.04
    local MAIN_LOOP_DELAY = 0.8
    local SAFE_LOOP_DELAY = 2.5 -- slower for safe mode
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

    local function CallRemote(name, args)
        args = args or {}
        if not Network then return false end
        local r = Network:FindFirstChild(name)
        if not r then return false end
        if r.ClassName == "RemoteFunction" then
            local ok,res = pcall(function() return r:InvokeServer(table.unpack(args)) end)
            return ok,res
        elseif r.ClassName == "RemoteEvent" then
            local ok,res = pcall(function() r:FireServer(table.unpack(args)) end)
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
        local r = Network:FindFirstChild("Equip Best Pets")
        if not r then return false end
        local ok,_=pcall(function() r:InvokeServer() end)
        return ok
    end

    local SelectedWorld = "Spawn"
    local SelectedArea = "Town"
    local Enabled = false
    local SafeMode = false
    local trackedPets = {}
    local petToTarget,targetToPet,petCooldowns = {},{},{}

    local function pickTopNFromSave(n)
        local save = GetSave()
        if not save then return {} end
        local maxEquip = tonumber(save.MaxEquipped or save["P MaxEquipped"] or save["PMaxEquipped"]) or 8
        if n then maxEquip = n end
        local all = save.Pets or {}
        local out = {}
        for _,p in pairs(all) do
            if type(p)=="table" and p.uid then table.insert(out,p) end
        end
        table.sort(out,function(a,b) return (a.s or a.power or 0)>(b.s or b.power or 0) end)
        local chosen = {}
        for i=1,math.min(maxEquip,#out) do table.insert(chosen,out[i].uid) end
        return chosen
    end

    local function GetEquippedPetUIDs()
        local uids = {}
        local save = GetSave()
        if save and save.Pets then
            for _,p in pairs(save.Pets) do
                if type(p)=="table" and p.uid then
                    if p.equipped or p.eq or p.equip or p[1]==true then table.insert(uids,p.uid) end
                end
            end
            if #uids>0 then return uids end
        end
        local top = pickTopNFromSave()
        if #top>0 then return top end
        return {}
    end

    local function AssignPetToBreakable(petUID,breakId)
        if not petUID or not breakId then return false end
        task.spawn(function()
            JoinCoin(breakId,{petUID})
            task.wait(JOIN_DELAY)
            ChangePetTarget(petUID,"Coin",breakId)
            task.wait(CHANGE_DELAY)
            FarmCoin(breakId,petUID)
        end)
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
        local present = {}
        if coins then for id,_ in pairs(coins) do present[id]=true end end
        for petUID,tid in pairs(petToTarget) do if not present[tid] then ClearAssignmentForPet(petUID) end end
    end

    local function GetAvailableBreakables(coins)
        local avail = {}
        if not coins then return avail end
        for id,item in pairs(coins) do
            if type(item)=="table" then
                local w,a=item.w or item.world,item.a or item.area
                if tostring(w)==tostring(SelectedWorld) and tostring(a)==tostring(SelectedArea) then
                    if not targetToPet[id] then table.insert(avail,{id=id,data=item}) end
                end
            end
        end
        return avail
    end

    local function FillAssignments(coins)
        local petUIDs=GetEquippedPetUIDs()
        if #petUIDs==0 then return end
        local freePets={}
        for _,uid in ipairs(petUIDs) do
            if not petToTarget[uid] and tick()>= (petCooldowns[uid] or 0) then table.insert(freePets,uid) end
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

    local function makeDropdown(parent,posX,posY,width,labelText,options,onSelect)
        local label = Instance.new("TextLabel",parent)
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
        screenGui.Name="HatesAutoFarmGUI"
        local frame=Instance.new("Frame",screenGui)
        frame.Size=UDim2.new(0,320,0,220)
        frame.Position=UDim2.new(0,5,0,5)
        frame.BackgroundColor3=Color3.fromRGB(20,20,20)
        Instance.new("UICorner",frame).CornerRadius=UDim.new(0,8)

        local title=Instance.new("TextLabel",frame)
        title.Size=UDim2.new(1,0,0,26)
        title.Position=UDim2.new(0,0,0,6)
        title.BackgroundTransparency=1
        title.Font=Enum.Font.SourceSansBold
        title.TextSize=16
        title.TextColor3=Color3.new(1,1,1)
        title.Text="Hate's Autofarm"

        local pickBtn=Instance.new("TextButton",frame)
        pickBtn.Size=UDim2.new(0.48,-8,0,36)
        pickBtn.Position=UDim2.new(0,10,0,40)
        pickBtn.Text="Pick Best Pets"
        pickBtn.Font=Enum.Font.SourceSansBold
        pickBtn.BackgroundColor3=Color3.fromRGB(70,130,180)
        pickBtn.TextColor3=Color3.new(1,1,1)
        Instance.new("UICorner",pickBtn).CornerRadius=UDim.new(0,6)

        local startBtn=Instance.new("TextButton",frame)
        startBtn.Size=UDim2.new(0.48,-8,0,36)
        startBtn.Position=UDim2.new(0,168,0,40)
        startBtn.Text="Start"
        startBtn.Font=Enum.Font.SourceSansBold
        startBtn.BackgroundColor3=Color3.fromRGB(34,139,34)
        startBtn.TextColor3=Color3.new(1,1,1)
        Instance.new("UICorner",startBtn).CornerRadius=UDim.new(0,6)

        local worldDropdown=makeDropdown(frame,10,81,140,"World",(function() local t={} for k,_ in pairs(WorldsTable) do table.insert(t,k) end table.sort(t) return t end)(),function(selected)
            SelectedWorld=selected
            local areas=WorldsTable[SelectedWorld] or {}
            areaDropdown.SetOptions(areas)
            if #areas>0 then SelectedArea=areas[1] areaDropdown.Button.Text=areas[1] else SelectedArea="" areaDropdown.Button.Text="None" end
            petToTarget,targetToPet,petCooldowns={}, {}, {}
        end)

        local areaDropdown=makeDropdown(frame,168,81,140,"Area",WorldsTable[SelectedWorld] or {},function(selected)
            SelectedArea=selected
            petToTarget,targetToPet,petCooldowns={}, {}, {}
        end)

        local safeBtn=Instance.new("TextButton",frame)
        safeBtn.Size=UDim2.new(0.48,-8,0,26)
        safeBtn.Position=UDim2.new(0,10,0,120)
        safeBtn.Text="Safe Start"
        safeBtn.Font=Enum.Font.SourceSansBold
        safeBtn.BackgroundColor3=Color3.fromRGB(100,149,237)
        safeBtn.TextColor3=Color3.new(1,1,1)
        Instance.new("UICorner",safeBtn).CornerRadius=UDim.new(0,6)

        local status=Instance.new("TextLabel",frame)
        status.Size=UDim2.new(1,-20,0,48)
        status.Position=UDim2.new(0,10,0,160)
        status.BackgroundTransparency=1
        status.TextColor3=Color3.new(1,1,1)
        status.TextWrapped=true
        status.Font=Enum.Font.SourceSans
        status.TextSize=14
        status.Text="Status: Idle"

        local minBtn=Instance.new("TextButton",screenGui)
        minBtn.Size=UDim2.new(0,20,0,20)
        minBtn.Position=UDim2.new(0,0,0,0)
        minBtn.Text="–"
        minBtn.Font=Enum.Font.SourceSansBold
        minBtn.BackgroundColor3=Color3.fromRGB(30,30,30)
        minBtn.TextColor3=Color3.new(1,1,1)
        Instance.new("UICorner",minBtn).CornerRadius=UDim.new(0,4)
        minBtn.MouseButton1Click:Connect(function()
            frame.Visible=false
            minBtn.Visible=false
            local restoreBtn=Instance.new("TextButton",screenGui)
            restoreBtn.Size=UDim2.new(0,50,0,20)
            restoreBtn.Position=UDim2.new(0,5,0,5)
            restoreBtn.Text="Hate"
            restoreBtn.Font=Enum.Font.SourceSansBold
            restoreBtn.BackgroundColor3=Color3.fromRGB(30,30,30)
            restoreBtn.TextColor3=Color3.new(1,1,1)
            Instance.new("UICorner",restoreBtn).CornerRadius=UDim.new(0,4)
            restoreBtn.MouseButton1Click:Connect(function()
                frame.Visible=true
                minBtn.Visible=true
                restoreBtn:Destroy()
            end)
        end)

        pickBtn.MouseButton1Click:Connect(function()
            status.Text="Status: Equipping best pets..."
            trackedPets=pickTopNFromSave()
            for _,uid in ipairs(trackedPets) do
                pcall(function() EquipPet(uid) end)
                task.wait(0.06)
            end
            task.wait(EQUIP_WAIT)
            status.Text=("Status: Equipped %d pets"):format(#trackedPets)
        end)

        startBtn.MouseButton1Click:Connect(function()
            Enabled=not Enabled
            SafeMode=false
            if Enabled then
                startBtn.Text="Stop"
                startBtn.BackgroundColor3=Color3.fromRGB(178,34,34)
                status.Text=("Status: Farming (%s - %s)"):format(tostring(SelectedWorld),tostring(SelectedArea))
            else
                startBtn.Text="Start"
                startBtn.BackgroundColor3=Color3.fromRGB(34,139,34)
                status.Text="Status: Stopped"
            end
        end)

        safeBtn.MouseButton1Click:Connect(function()
            Enabled=not Enabled
            SafeMode=true
            if Enabled then
                safeBtn.Text="Stop Safe"
                status.Text=("Status: Safe Farming (%s - %s)"):format(tostring(SelectedWorld),tostring(SelectedArea))
            else
                safeBtn.Text="Safe Start"
                status.Text="Status: Stopped"
            end
        end)

        return {Gui=screenGui,Frame=frame,Status=status,WorldDropdown=worldDropdown,AreaDropdown=areaDropdown}
    end

    local ui=CreateGUI()

    task.spawn(function()
        while true do
            if Enabled then
                local pets=trackedPets
                if #pets==0 then
                    pets=pickTopNFromSave()
                    for _,uid in ipairs(pets) do pcall(function() EquipPet(uid) end) task.wait(0.06) end
                    task.wait(EQUIP_WAIT)
                end

                local coins=GetCoinsRaw()
                if not coins then
                    ui.Status.Text="Status: Waiting for coins..."
                    task.wait(1)
                else
                    ui.Status.Text=("Status: %s Farming (%s - %s)"):format(SafeMode and "Safe" or "Regular",SelectedWorld,SelectedArea)
                    FreeStaleAssignments(coins)
                    FillAssignments(coins)
                    pcall(function() ClaimOrbs({}) end)
                end
            end
            task.wait(SafeMode and SAFE_LOOP_DELAY or MAIN_LOOP_DELAY)
        end
    end)

    print("[Hate AutoFarm] GUI Loaded. Pick Pets -> Start / Safe Start.")
end)

if not ok then warn("[Hate AutoFarm] Error:",mainErr) else print("[Hate AutoFarm] Loaded successfully!") end
