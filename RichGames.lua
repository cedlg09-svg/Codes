-- PSX AutoFarm (Safe + World/Area GUI + Minimize)
local ok, mainErr = pcall(function()

    -- ==== CONFIG ====
    local SAFE_DELAY_BETWEEN_ASSIGN = 0.18
    local JOIN_DELAY = 0.06
    local CHANGE_DELAY = 0.04
    local MAIN_LOOP_DELAY = 0.8
    local EQUIP_WAIT = 0.45
    local AUTO_LOOP_DELAY = 0.8
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

    local SelectedWorld = "Spawn"
    local SelectedArea = "Town"

    -- ==== SERVICES ====
    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local LocalPlayer = Players.LocalPlayer
    local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
    local Workspace = game:GetService("Workspace")

    local Network = ReplicatedStorage:FindFirstChild("Network")

    -- ==== HELPER: Remote Calls ====
    local function CallRemote(name, argsTable)
        argsTable = argsTable or {}
        if not Network then return false,"Network missing" end
        local r = Network:FindFirstChild(name)
        if not r then return false,"Remote not found: "..tostring(name) end
        if r.ClassName=="RemoteFunction" then
            local ok,res=pcall(function() return r:InvokeServer(table.unpack(argsTable)) end)
            return ok,res
        elseif r.ClassName=="RemoteEvent" then
            local ok,res=pcall(function() r:FireServer(table.unpack(argsTable)) end)
            return ok,res
        else
            return false,"Unexpected class: "..r.ClassName
        end
    end

    local function GetSave() local ok,res=CallRemote("Get Custom Save",{}); if ok then return res end return nil end
    local function GetCoinsRaw() local ok,res=CallRemote("Get Coins",{}); if ok then return res end; local ok2,res2=CallRemote("Coins: Get Test",{}); if ok2 then return res2 end return nil end
    local function EquipPet(uid) return CallRemote("Equip Pet",{uid}) end
    local function JoinCoin(id,pets) return CallRemote("Join Coin",{id,pets}) end
    local function ChangePetTarget(uid,ttype,id) return CallRemote("Change Pet Target",{uid,ttype,id}) end
    local function FarmCoin(id,uid) return CallRemote("Farm Coin",{id,uid}) end
    local function ClaimOrbs(arg) return CallRemote("Claim Orbs",{arg or {}}) end

    local function safe_delay(t,f) if type(t)=="number" and type(f)=="function" then task.delay(t,f) end end
    local function safeNumber(x) if type(x)=="number" then return x elseif type(x)=="string" then return tonumber(x) or 0 end return 0 end

    local function buildPetListFromSave(save)
        if not save then return {} end
        local petsTbl = save.Pets or save.pets or {}
        local out = {}
        for k,v in pairs(petsTbl) do if type(v)=="table" then v.uid=v.uid or k; table.insert(out,v) end end
        return out
    end

    local function sortByPowerDesc(list)
        table.sort(list,function(a,b) return safeNumber(a.s or a.power or a.p or 0) > safeNumber(b.s or b.power or b.p or 0) end)
    end

    local function pickTopNFromSave(n)
        local save = GetSave()
        if not save then return {} end
        local maxEquip = tonumber(save.MaxEquipped or save["P MaxEquipped"] or save["PMaxEquipped"]) or 8
        if n then maxEquip=n end
        local all=buildPetListFromSave(save)
        sortByPowerDesc(all)
        local chosen={}
        for i=1,math.min(maxEquip,#all) do if all[i] and all[i].uid then table.insert(chosen,all[i].uid) end end
        return chosen
    end

    -- ==== STATE ====
    local Enabled=false
    local trackedPets={}
    local petToTarget={} -- petUID -> targetId
    local targetToPet={} -- targetId -> petUID
    local petCooldowns={} -- petUID -> tick

    -- ==== GUI: World/Area + Minimize ====
    local function CreateGUI()
        local screenGui = Instance.new("ScreenGui", PlayerGui)
        screenGui.Name = "PSX_AutoFarm_GUI"

        local frame = Instance.new("Frame", screenGui)
        frame.Size = UDim2.new(0,520,0,340)
        frame.Position = UDim2.new(0.12,0,0.12,0)
        frame.BackgroundColor3 = Color3.fromRGB(24,24,24)
        frame.Active = true
        frame.Draggable = true
        Instance.new("UICorner", frame).CornerRadius=UDim.new(0,8)

        local title = Instance.new("TextLabel", frame)
        title.Size=UDim2.new(1,-20,0,28)
        title.Position=UDim2.new(0,10,0,8)
        title.BackgroundTransparency=1
        title.Font=Enum.Font.SourceSansBold
        title.TextSize=18
        title.TextColor3=Color3.new(1,1,1)
        title.Text="PSX AutoFarm — Safe Pets Only"

        local worldBtn = Instance.new("TextButton", frame)
        worldBtn.Size=UDim2.new(0.34,-8,0,36)
        worldBtn.Position=UDim2.new(0,10,0,44)
        worldBtn.Font=Enum.Font.SourceSans
        worldBtn.TextSize=14
        worldBtn.Text="World: "..SelectedWorld
        worldBtn.BackgroundColor3=Color3.fromRGB(70,130,180)
        worldBtn.TextColor3=Color3.new(1,1,1)
        Instance.new("UICorner", worldBtn).CornerRadius=UDim.new(0,6)

        local areaBtn = Instance.new("TextButton", frame)
        areaBtn.Size=UDim2.new(0.34,-8,0,36)
        areaBtn.Position=UDim2.new(0,10,0,92)
        areaBtn.Font=Enum.Font.SourceSans
        areaBtn.TextSize=14
        areaBtn.Text="Area: "..SelectedArea
        areaBtn.BackgroundColor3=Color3.fromRGB(100,149,237)
        areaBtn.TextColor3=Color3.new(1,1,1)
        Instance.new("UICorner", areaBtn).CornerRadius=UDim.new(0,6)

        local listFrame = Instance.new("Frame", frame)
        listFrame.Size=UDim2.new(0.58,-12,0,240)
        listFrame.Position=UDim2.new(0.40,8,0,44)
        listFrame.BackgroundColor3=Color3.fromRGB(18,18,18)
        Instance.new("UICorner", listFrame).CornerRadius=UDim.new(0,6)
        listFrame.Visible=false
        local listLayout = Instance.new("UIListLayout", listFrame)
        listLayout.Padding=UDim.new(0,6)
        listLayout.SortOrder=Enum.SortOrder.LayoutOrder

        local function ClearList()
            for _,c in ipairs(listFrame:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
        end

        local function ShowWorlds()
            ClearList()
            listFrame.Visible=true
            for w,_ in pairs(WorldsTable) do
                local btn = Instance.new("TextButton", listFrame)
                btn.Size=UDim2.new(1,-12,0,28)
                btn.BackgroundColor3=Color3.fromRGB(70,130,180)
                btn.TextColor3=Color3.new(1,1,1)
                btn.Font=Enum.Font.SourceSans
                btn.TextSize=14
                btn.Text=w
                Instance.new("UICorner", btn).CornerRadius=UDim.new(0,6)
                btn.MouseButton1Click:Connect(function()
                    SelectedWorld=w
                    worldBtn.Text="World: "..SelectedWorld
                    local areas = WorldsTable[SelectedWorld] or {}
                    SelectedArea=areas[1] or ""
                    areaBtn.Text="Area: "..SelectedArea
                    listFrame.Visible=false
                end)
            end
        end

        local function ShowAreas()
            ClearList()
            listFrame.Visible=true
            local areas = WorldsTable[SelectedWorld] or {}
            for _,a in ipairs(areas) do
                local btn = Instance.new("TextButton", listFrame)
                btn.Size=UDim2.new(1,-12,0,28)
                btn.BackgroundColor3=Color3.fromRGB(100,149,237)
                btn.TextColor3=Color3.new(1,1,1)
                btn.Font=Enum.Font.SourceSans
                btn.TextSize=14
                btn.Text=a
                Instance.new("UICorner", btn).CornerRadius=UDim.new(0,6)
                btn.MouseButton1Click:Connect(function()
                    SelectedArea=a
                    areaBtn.Text="Area: "..SelectedArea
                    listFrame.Visible=false
                end)
            end
        end

        worldBtn.MouseButton1Click:Connect(ShowWorlds)
        areaBtn.MouseButton1Click:Connect(ShowAreas)

        local pickBtn = Instance.new("TextButton", frame)
        pickBtn.Size=UDim2.new(0.22,-6,0,36)
        pickBtn.Position=UDim2.new(0.10,6,0,148)
        pickBtn.Text="Pick Best Pets"
        pickBtn.Font=Enum.Font.SourceSansBold
        pickBtn.TextSize=14
        pickBtn.BackgroundColor3=Color3.fromRGB(70,130,180)
        pickBtn.TextColor3=Color3.new(1,1,1)
        Instance.new("UICorner", pickBtn).CornerRadius=UDim.new(0,6)

        local toggleBtn = Instance.new("TextButton", frame)
        toggleBtn.Size=UDim2.new(0.18,-6,0,36)
        toggleBtn.Position=UDim2.new(0.34,6,0,148)
        toggleBtn.Text="Start"
        toggleBtn.Font=Enum.Font.SourceSansBold
        toggleBtn.TextSize=14
        toggleBtn.BackgroundColor3=Color3.fromRGB(34,139,34)
        toggleBtn.TextColor3=Color3.new(1,1,1)
        Instance.new("UICorner", toggleBtn).CornerRadius=UDim.new(0,6)

        local statusLabel = Instance.new("TextLabel", frame)
        statusLabel.Size=UDim2.new(1,-20,0,80)
        statusLabel.Position=UDim2.new(0,10,0,196)
        statusLabel.BackgroundTransparency=1
        statusLabel.Font=Enum.Font.SourceSans
        statusLabel.TextSize=14
        statusLabel.TextColor3=Color3.fromRGB(220,220,220)
        statusLabel.Text = string.format("World: %s | Area: %s | Farming: %s",SelectedWorld,SelectedArea,Enabled and "Yes" or "No")

        pickBtn.MouseButton1Click:Connect(function()
            trackedPets = pickTopNFromSave()
            for _,uid in ipairs(trackedPets) do pcall(function() EquipPet(uid) end); task.wait(0.06) end
            task.wait(EQUIP_WAIT)
            statusLabel.Text = string.format("Equipped %d pets",#trackedPets)
        end)

        toggleBtn.MouseButton1Click:Connect(function()
            Enabled = not Enabled
            toggleBtn.Text = Enabled and "Stop" or "Start"
            toggleBtn.BackgroundColor3 = Enabled and Color3.fromRGB(178,34,34) or Color3.fromRGB(34,139,34)
            statusLabel.Text = string.format("World: %s | Area: %s | Farming: %s",SelectedWorld,SelectedArea,Enabled and "Yes" or "No")
        end)

        -- minimize icon
        local icon = Instance.new("TextButton", screenGui)
        icon.Size=UDim2.new(0,90,0,36)
        icon.Position=UDim2.new(0, frame.AbsolutePosition.X+frame.AbsoluteSize.X-100,0,frame.AbsolutePosition.Y)
        icon.Text="Hate"
        icon.Font=Enum.Font.SourceSansBold
        icon.TextSize=16
        icon.BackgroundColor3=Color3.fromRGB(40,40,40)
        Instance.new("UICorner", icon).CornerRadius=UDim.new(0,6)
        icon.Visible=false
        icon.Active=true
        icon.Draggable=true
        icon.MouseButton1Click:Connect(function() icon.Visible=false; frame.Visible=true end)

        local minBtn = Instance.new("TextButton", frame)
        minBtn.Size=UDim2.new(0,38,0,24)
        minBtn.Position=UDim2.new(1,-44,0,6)
        minBtn.Text="🔽"
        minBtn.Font=Enum.Font.SourceSansBold
        minBtn.TextSize=18
        minBtn.BackgroundTransparency=0.2
        minBtn.TextColor3=Color3.new(1,1,1)
        Instance.new("UICorner", minBtn).CornerRadius=UDim.new(0,6)
        minBtn.MouseButton1Click:Connect(function() frame.Visible=false; icon.Visible=true; icon.Position=UDim2.new(0,frame.AbsolutePosition.X+frame.AbsoluteSize.X-100,0,frame.AbsolutePosition.Y) end)

        return {Status=statusLabel}
    end

    local ui = CreateGUI()

    -- ==== Farming Loop ====
    task.spawn(function()
        while true do
            if Enabled then
                if #trackedPets==0 then
                    trackedPets = pickTopNFromSave()
                    for _,uid in ipairs(trackedPets) do pcall(function() EquipPet(uid) end); task.wait(0.06) end
                    task.wait(EQUIP_WAIT)
                end

                local coins = GetCoinsRaw()
                if coins then
                    -- update status for GUI world/area
                    local firstW,firstA=nil,nil
                    for id,data in pairs(coins) do
                        if type(data)=="table" and data.w and data.a then firstW,firstA=tostring(data.w),tostring(data.a); break end
                    end
                    if firstW and firstA then ui.Status.Text = ("Farming: %s - %s"):format(firstW,firstA) end

                    -- assign pets to coins
                    for id,data in pairs(coins) do
                        if type(data)=="table" then
                            for _,uid in ipairs(trackedPets) do
                                safe_delay(0,function() JoinCoin(id,{uid}) end)
                                safe_delay(JOIN_DELAY,function() ChangePetTarget(uid,"Coin",id) end)
                                safe_delay(JOIN_DELAY+CHANGE_DELAY,function() FarmCoin(id,uid) end)
                                task.wait(SAFE_DELAY_BETWEEN_ASSIGN)
                            end
                        end
                    end

                    pcall(function() ClaimOrbs({}) end)
                end
            end
            task.wait(MAIN_LOOP_DELAY)
        end
    end)

    print("[AutoFarm] Safe + World/Area GUI loaded. Pick Best Pets then Start.")

end)

if not ok then warn("[AutoFarm] Startup error:",mainErr) end
