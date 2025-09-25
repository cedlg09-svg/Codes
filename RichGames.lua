-- PSX AutoFarm — Final (clean, minimal, area-only, one-per-breakable, collapse -> 5x5)
-- Paste into a NEW LocalScript and run

local ok, mainErr = pcall(function()

    local SAFE_DELAY_BETWEEN_ASSIGN = 0.18
    local JOIN_DELAY = 0.06
    local CHANGE_DELAY = 0.04
    local MAIN_LOOP_DELAY = 0.8
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
    local UserInputService = game:GetService("UserInputService")
    local LocalPlayer = Players.LocalPlayer
    assert(LocalPlayer, "LocalPlayer nil - run as LocalScript")
    local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

    local Network = ReplicatedStorage:FindFirstChild("Network")
    if not Network then warn("[AutoFarm] ReplicatedStorage.Network not found.") end

    local function CallRemote(name, argsTable)
        argsTable = argsTable or {}
        if not Network then return false, "Network missing" end
        local r = Network:FindFirstChild(name)
        if not r then return false, ("Remote not found: %s"):format(tostring(name)) end
        if r.ClassName == "RemoteFunction" then
            local ok, res = pcall(function() return r:InvokeServer(table.unpack(argsTable)) end)
            return ok, res
        elseif r.ClassName == "RemoteEvent" then
            local ok, res = pcall(function() r:FireServer(table.unpack(argsTable)) end)
            return ok, res
        else
            return false, ("Remote unexpected class: %s"):format(tostring(r.ClassName))
        end
    end

    local function GetSave() local ok,res = CallRemote("Get Custom Save", {}) if ok then return res end return nil end
    local function GetCoinsRaw() local ok,res = CallRemote("Get Coins", {}) if ok then return res end local ok2,res2 = CallRemote("Coins: Get Test", {}) if ok2 then return res2 end return nil end
    local function EquipPet(uid) return CallRemote("Equip Pet", {uid}) end
    local function JoinCoin(id, pets) return CallRemote("Join Coin", {id, pets}) end
    local function ChangePetTarget(uid, ttype, id) return CallRemote("Change Pet Target", {uid, ttype, id}) end
    local function FarmCoin(id, uid) return CallRemote("Farm Coin", {id, uid}) end
    local function ClaimOrbs(arg) return CallRemote("Claim Orbs", {arg or {}}) end

    local function EquipBestPetsRemote()
        if not Network then return false end
        local r = Network:FindFirstChild("Equip Best Pets")
        if not r then return false end
        local ok = pcall(function() r:InvokeServer() end)
        return ok
    end

    local function safe_delay(t, f) if type(t)=="number" and type(f)=="function" then task.delay(t, f) end end
    local function safeNumber(x) if type(x)=="number" then return x elseif type(x)=="string" then return tonumber(x) or 0 end return 0 end

    local function buildPetListFromSave(save)
        if not save then return {} end
        local petsTbl = save.Pets or save.pets or {}
        local out = {}
        for k,v in pairs(petsTbl) do
            if type(v) == "table" then
                v.uid = v.uid or k
                table.insert(out, v)
            end
        end
        return out
    end

    local function sortByPowerDesc(list)
        table.sort(list, function(a,b)
            return safeNumber(a.s or a.power or a.p or 0) > safeNumber(b.s or b.power or b.p or 0)
        end)
    end

    local function pickTopNFromSave(n)
        local save = GetSave()
        if not save then return {} end
        local maxEquip = tonumber(save.MaxEquipped or save["P MaxEquipped"] or save["PMaxEquipped"]) or 8
        if n then maxEquip = n end
        local all = buildPetListFromSave(save)
        sortByPowerDesc(all)
        local chosen = {}
        for i=1, math.min(maxEquip, #all) do
            if all[i] and all[i].uid then table.insert(chosen, all[i].uid) end
        end
        return chosen
    end

    local SelectedWorld = "Spawn"
    local SelectedArea = "Town"
    local Enabled = false
    local trackedPets = {}
    local petToTarget = {}
    local targetToPet = {}
    local petCooldowns = {}

    local function GetEquippedPetUIDs()
        local uids = {}
        local save = GetSave()
        if save and save.Pets then
            for _, petData in pairs(save.Pets) do
                if type(petData) == "table" and petData.uid then
                    local isEq = false
                    if petData.equipped == true or petData.eq == true or petData.equip == true then isEq = true end
                    if petData[1] == true or petData["1"] == true then isEq = true end
                    if isEq then table.insert(uids, petData.uid) end
                end
            end
            if #uids > 0 then return uids end
        end
        local top = pickTopNFromSave()
        if #top > 0 then return top end
        return {}
    end

    local function AssignPetToBreakable(petUID, breakId)
        if not petUID or not breakId then return false end
        safe_delay(0, function() JoinCoin(breakId, {petUID}) end)
        safe_delay(JOIN_DELAY, function() ChangePetTarget(petUID, "Coin", breakId) end)
        safe_delay(JOIN_DELAY + CHANGE_DELAY, function() FarmCoin(breakId, petUID) end)
        petToTarget[petUID] = breakId
        targetToPet[breakId] = petUID
        petCooldowns[petUID] = tick()
        return true
    end

    local function ClearAssignmentForPet(petUID)
        if not petUID then return end
        local t = petToTarget[petUID]
        if t then
            petToTarget[petUID] = nil
            targetToPet[t] = nil
        end
        petCooldowns[petUID] = tick() + RETARGET_DELAY
    end

    local function FreeStaleAssignments(coins)
        local present = {}
        if coins then for id,_ in pairs(coins) do present[id] = true end end
        for petUID, tid in pairs(petToTarget) do
            if not present[tid] then
                ClearAssignmentForPet(petUID)
            end
        end
    end

    local function GetAvailableBreakables(coins)
        local available = {}
        if not coins then return available end
        for id, item in pairs(coins) do
            if type(item) == "table" then
                local w = item.w or item.world
                local a = item.a or item.area
                if tostring(w) == tostring(SelectedWorld) and tostring(a) == tostring(SelectedArea) then
                    if not targetToPet[id] then
                        table.insert(available, { id = id, data = item })
                    end
                end
            end
        end
        return available
    end

    local function FillAssignments(coins)
        local petUIDs = GetEquippedPetUIDs()
        if #petUIDs == 0 then return end
        local freePets = {}
        for _, uid in ipairs(petUIDs) do
            if not petToTarget[uid] then
                local cd = petCooldowns[uid] or 0
                if tick() >= cd then table.insert(freePets, uid) end
            end
        end
        if #freePets == 0 then return end
        local available = GetAvailableBreakables(coins)
        if #available == 0 then return end
        local count = math.min(#freePets, #available)
        for i = 1, count do
            local pet = freePets[i]
            local target = available[i]
            if pet and target and target.id then
                pcall(function() AssignPetToBreakable(pet, target.id) end)
                task.wait(0.02)
            end
        end
    end

    local function makeDropdown(parent, posX, posY, width, labelText, options, onSelect)
        local label = Instance.new("TextLabel", parent)
        label.Size = UDim2.new(0, width, 0, 18)
        label.Position = UDim2.new(0, posX, 0, posY)
        label.BackgroundTransparency = 1
        label.Text = labelText
        label.TextColor3 = Color3.new(1,1,1)
        label.Font = Enum.Font.SourceSans
        label.TextSize = 14

        local btn = Instance.new("TextButton", parent)
        btn.Size = UDim2.new(0, width, 0, 26)
        btn.Position = UDim2.new(0, posX, 0, posY + 18)
        btn.Text = options[1] or "None"
        btn.Font = Enum.Font.SourceSans
        btn.TextSize = 14
        btn.TextColor3 = Color3.new(1,1,1)
        btn.BackgroundColor3 = Color3.fromRGB(20,20,20)
        btn.AutoButtonColor = true
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0,6)

        local menu = Instance.new("Frame", parent)
        menu.Size = UDim2.new(0, width, 0, math.min(#options*24, 200))
        menu.Position = UDim2.new(0, posX, 0, posY + 46)
        menu.Visible = false
        menu.BackgroundColor3 = Color3.fromRGB(12,12,12)
        Instance.new("UICorner", menu).CornerRadius = UDim.new(0,6)
        local layout = Instance.new("UIListLayout", menu)
        layout.Padding = UDim.new(0,4)

        local function populate(opts)
            for _, c in ipairs(menu:GetChildren()) do
                if not c:IsA("UIListLayout") then c:Destroy() end
            end
            for _, opt in ipairs(opts) do
                local optBtn = Instance.new("TextButton", menu)
                optBtn.Size = UDim2.new(1, -8, 0, 20)
                optBtn.Position = UDim2.new(0,4,0,0)
                optBtn.Text = opt
                optBtn.BackgroundTransparency = 1
                optBtn.Font = Enum.Font.SourceSans
                optBtn.TextColor3 = Color3.new(1,1,1)
                optBtn.TextSize = 14
                optBtn.AutoButtonColor = true
                optBtn.MouseButton1Click:Connect(function()
                    btn.Text = opt
                    menu.Visible = false
                    onSelect(opt)
                end)
            end
            menu.Size = UDim2.new(0, width, 0, math.min(#opts*24, 200))
        end

        populate(options)
        btn.MouseButton1Click:Connect(function()
            menu.Visible = not menu.Visible
        end)

        return {
            Button = btn,
            Menu = menu,
            Label = label,
            SetOptions = function(newOptions) populate(newOptions) end
        }
    end

    local function CreateGUI()
        local screenGui = Instance.new("ScreenGui")
        screenGui.Name = "PSX_AutoFarm_GUI_Final"
        screenGui.ResetOnSpawn = false
        screenGui.Parent = PlayerGui

        local frame = Instance.new("Frame", screenGui)
        frame.Size = UDim2.new(0, 520, 0, 340)
        frame.Position = UDim2.new(0.12, 0, 0.12, 0)
        frame.BackgroundColor3 = Color3.fromRGB(10,10,10)
        frame.Active = true
        frame.ZIndex = 50
        Instance.new("UICorner", frame).CornerRadius = UDim.new(0,8)

        local titleBar = Instance.new("Frame", frame)
        titleBar.Size = UDim2.new(1, 0, 0, 34)
        titleBar.Position = UDim2.new(0, 0, 0, 0)
        titleBar.BackgroundColor3 = Color3.fromRGB(8,8,8)
        Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0,8)

        local title = Instance.new("TextLabel", titleBar)
        title.Size = UDim2.new(1, -48, 1, 0)
        title.Position = UDim2.new(0, 8, 0, 0)
        title.BackgroundTransparency = 1
        title.Font = Enum.Font.SourceSansBold
        title.TextSize = 16
        title.TextColor3 = Color3.new(1,1,1)
        title.Text = "PSX AutoFarm — One pet per breakable"

        local closeBtn = Instance.new("TextButton", titleBar)
        closeBtn.Size = UDim2.new(0, 36, 0, 24)
        closeBtn.Position = UDim2.new(1, -44, 0, 5)
        closeBtn.Text = "✕"
        closeBtn.Font = Enum.Font.SourceSansBold
        closeBtn.TextSize = 16
        closeBtn.BackgroundTransparency = 0.15
        closeBtn.TextColor3 = Color3.new(1,1,1)
        Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0,6)

        local content = Instance.new("Frame", frame)
        content.Position = UDim2.new(0, 12, 0, 44)
        content.Size = UDim2.new(0, 496, 0, 240)
        content.BackgroundTransparency = 1

        local pickBtn = Instance.new("TextButton", content)
        pickBtn.Size = UDim2.new(0, 220, 0, 36)
        pickBtn.Position = UDim2.new(0, 0, 0, 0)
        pickBtn.Text = "Pick Best Pets"
        pickBtn.Font = Enum.Font.SourceSansBold
        pickBtn.TextSize = 14
        pickBtn.BackgroundColor3 = Color3.fromRGB(18,18,18)
        pickBtn.TextColor3 = Color3.new(1,1,1)
        Instance.new("UICorner", pickBtn).CornerRadius = UDim.new(0,6)

        local startBtn = Instance.new("TextButton", content)
        startBtn.Size = UDim2.new(0, 220, 0, 36)
        startBtn.Position = UDim2.new(0, 232, 0, 0)
        startBtn.Text = "Start"
        startBtn.Font = Enum.Font.SourceSansBold
        startBtn.TextSize = 14
        startBtn.BackgroundColor3 = Color3.fromRGB(18,18,18)
        startBtn.TextColor3 = Color3.new(1,1,1)
        Instance.new("UICorner", startBtn).CornerRadius = UDim.new(0,6)

        local listFrame = Instance.new("Frame", frame)
        listFrame.Size = UDim2.new(0, 280, 0, 200)
        listFrame.Position = UDim2.new(0, 12, 0, 92)
        listFrame.BackgroundColor3 = Color3.fromRGB(6,6,6)
        Instance.new("UICorner", listFrame).CornerRadius = UDim.new(0,6)
        listFrame.Visible = false
        local listLayout = Instance.new("UIListLayout", listFrame)
        listLayout.Padding = UDim.new(0,6)
        listLayout.SortOrder = Enum.SortOrder.LayoutOrder

        local worldBtn = Instance.new("TextButton", frame)
        worldBtn.Size = UDim2.new(0, 220, 0, 36)
        worldBtn.Position = UDim2.new(0, 12, 0, 80)
        worldBtn.Text = "World: " .. tostring(SelectedWorld)
        worldBtn.Font = Enum.Font.SourceSans
        worldBtn.TextSize = 14
        worldBtn.BackgroundColor3 = Color3.fromRGB(16,16,16)
        worldBtn.TextColor3 = Color3.new(1,1,1)
        Instance.new("UICorner", worldBtn).CornerRadius = UDim.new(0,6)

        local areaBtn = Instance.new("TextButton", frame)
        areaBtn.Size = UDim2.new(0, 220, 0, 36)
        areaBtn.Position = UDim2.new(0, 240, 0, 80)
        areaBtn.Text = "Area: " .. tostring(SelectedArea)
        areaBtn.Font = Enum.Font.SourceSans
        areaBtn.TextSize = 14
        areaBtn.BackgroundColor3 = Color3.fromRGB(14,14,14)
        areaBtn.TextColor3 = Color3.new(1,1,1)
        Instance.new("UICorner", areaBtn).CornerRadius = UDim.new(0,6)

        local statusLabel = Instance.new("TextLabel", frame)
        statusLabel.Size = UDim2.new(0.98, -20, 0, 28)
        statusLabel.Position = UDim2.new(0, 12, 1, -40)
        statusLabel.BackgroundTransparency = 1
        statusLabel.Font = Enum.Font.SourceSans
        statusLabel.TextSize = 14
        statusLabel.TextColor3 = Color3.fromRGB(220,220,220)
        statusLabel.Text = string.format("World: %s | Area: %s | Farming: %s", tostring(SelectedWorld), tostring(SelectedArea), tostring(Enabled and "Yes" or "No"))

        local equipBtn = Instance.new("TextButton", frame)
        equipBtn.Size = UDim2.new(0, 140, 0, 26)
        equipBtn.Position = UDim2.new(0, 12, 1, -76)
        equipBtn.Text = "Equip Best (Remote)"
        equipBtn.Font = Enum.Font.SourceSans
        equipBtn.TextSize = 12
        equipBtn.BackgroundColor3 = Color3.fromRGB(16,16,16)
        equipBtn.TextColor3 = Color3.new(1,1,1)
        Instance.new("UICorner", equipBtn).CornerRadius = UDim.new(0,6)

        local function ClearList()
            for _,c in ipairs(listFrame:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
        end

        local function ShowWorlds()
            ClearList()
            listFrame.Visible = true
            for w, _ in pairs(WorldsTable) do
                local btn = Instance.new("TextButton", listFrame)
                btn.Size = UDim2.new(1, -12, 0, 28)
                btn.BackgroundColor3 = Color3.fromRGB(16,16,16)
                btn.TextColor3 = Color3.new(1,1,1)
                btn.Font = Enum.Font.SourceSans
                btn.TextSize = 14
                btn.Text = w
                Instance.new("UICorner", btn).CornerRadius = UDim.new(0,6)
                btn.MouseButton1Click:Connect(function()
                    SelectedWorld = w
                    worldBtn.Text = "World: " .. SelectedWorld
                    local areas = WorldsTable[SelectedWorld] or {}
                    SelectedArea = areas[1] or ""
                    areaBtn.Text = "Area: " .. SelectedArea
                    listFrame.Visible = false
                    petToTarget = {}
                    targetToPet = {}
                    petCooldowns = {}
                    statusLabel.Text = string.format("World: %s | Area: %s | Farming: %s", tostring(SelectedWorld), tostring(SelectedArea), tostring(Enabled and "Yes" or "No"))
                end)
            end
        end

        local function ShowAreas()
            ClearList()
            listFrame.Visible = true
            local areas = WorldsTable[SelectedWorld] or {}
            for _, a in ipairs(areas) do
                local btn = Instance.new("TextButton", listFrame)
                btn.Size = UDim2.new(1, -12, 0, 28)
                btn.BackgroundColor3 = Color3.fromRGB(14,14,14)
                btn.TextColor3 = Color3.new(1,1,1)
                btn.Font = Enum.Font.SourceSans
                btn.TextSize = 14
                btn.Text = a
                Instance.new("UICorner", btn).CornerRadius = UDim.new(0,6)
                btn.MouseButton1Click:Connect(function()
                    SelectedArea = a
                    areaBtn.Text = "Area: " .. SelectedArea
                    listFrame.Visible = false
                    petToTarget = {}
                    targetToPet = {}
                    petCooldowns = {}
                    statusLabel.Text = string.format("World: %s | Area: %s | Farming: %s", tostring(SelectedWorld), tostring(SelectedArea), tostring(Enabled and "Yes" or "No"))
                end)
            end
        end

        worldBtn.MouseButton1Click:Connect(ShowWorlds)
        areaBtn.MouseButton1Click:Connect(ShowAreas)

        pickBtn.MouseButton1Click:Connect(function()
            statusLabel.Text = "Equipping best pets..."
            local chosen = pickTopNFromSave()
            if #chosen == 0 then
                statusLabel.Text = "No pets found."
                return
            end
            trackedPets = chosen
            for _, uid in ipairs(trackedPets) do
                local ok, res = EquipPet(uid)
                if not ok then warn("[AutoFarm] EquipPet failed for", uid, res) end
                task.wait(0.06)
            end
            task.wait(EQUIP_WAIT)
            statusLabel.Text = ("Equipped %d pets"):format(#trackedPets)
        end)

        startBtn.MouseButton1Click:Connect(function()
            Enabled = not Enabled
            startBtn.Text = Enabled and "Stop" or "Start"
            statusLabel.Text = string.format("World: %s | Area: %s | Farming: %s", tostring(SelectedWorld), tostring(SelectedArea), tostring(Enabled and "Yes" or "No"))
        end)

        equipBtn.MouseButton1Click:Connect(function()
            local ok = EquipBestPetsRemote()
            if ok then
                statusLabel.Text = "Called remote Equip Best."
                task.wait(0.6)
                trackedPets = GetEquippedPetUIDs()
            else
                warn("[AutoFarm] Equip Best remote missing/failed.")
            end
        end)

        local icon = Instance.new("TextButton", PlayerGui)
        icon.Name = "PSX_AutoFarm_MinIcon"
        icon.Size = UDim2.new(0, 5, 0, 5)
        icon.Position = frame.Position
        icon.AnchorPoint = Vector2.new(0,0)
        icon.Text = ""
        icon.Font = Enum.Font.SourceSansBold
        icon.TextSize = 10
        icon.TextColor3 = Color3.new(1,1,1)
        icon.BackgroundColor3 = Color3.fromRGB(18,18,18)
        icon.AutoButtonColor = true
        icon.Visible = false
        Instance.new("UICorner", icon).CornerRadius = UDim.new(0,2)
        icon.Active = true
        icon.Draggable = true

        icon.MouseButton1Click:Connect(function()
            icon.Visible = false
            frame.Visible = true
        end)

        do
            local dragging, dragInput, dragStart, startPos = false, nil, nil, nil
            titleBar.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 then
                    dragging = true
                    dragStart = input.Position
                    startPos = frame.Position
                    input.Changed:Connect(function()
                        if input.UserInputState == Enum.UserInputState.End then dragging = false end
                    end)
                end
            end)
            titleBar.InputChanged:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseMovement then dragInput = input end
            end)
            UserInputService.InputChanged:Connect(function(input)
                if input == dragInput and dragging and dragStart and startPos then
                    local delta = input.Position - dragStart
                    frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
                end
            end)
        end

        closeBtn.MouseButton1Click:Connect(function()
            local p = frame.Position
            icon.Position = p
            frame.Visible = false
            icon.Visible = true
            listFrame.Visible = false
        end)

        return { Gui = screenGui, Frame = frame, StatusLabel = statusLabel, Icon = icon }
    end

    local ui = CreateGUI()

    task.spawn(function()
        while true do
            if Enabled then
                if #trackedPets == 0 then
                    trackedPets = pickTopNFromSave()
                    for _, uid in ipairs(trackedPets) do
                        pcall(function() EquipPet(uid) end)
                        task.wait(0.06)
                    end
                    task.wait(EQUIP_WAIT)
                end

                local coins = GetCoinsRaw()
                if not coins then
                    if ui and ui.StatusLabel then ui.StatusLabel.Text = "Waiting for coins..." end
                    task.wait(1)
                else
                    if ui and ui.StatusLabel then ui.StatusLabel.Text = ("World: %s | Area: %s | Farming: %s"):format(tostring(SelectedWorld), tostring(SelectedArea), tostring(Enabled and "Yes" or "No")) end
                    FreeStaleAssignments(coins)
                    FillAssignments(coins)
                    pcall(function() ClaimOrbs({}) end)
                    pcall(function()
                        local things = Workspace:FindFirstChild("__THINGS") or Workspace:FindFirstChild("__things")
                        if things and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                            local bags = things:FindFirstChild("Lootbags")
                            if bags then
                                for _, bag in ipairs(bags:GetChildren()) do
                                    if bag and bag:IsA("BasePart") then
                                        pcall(function() bag.CFrame = LocalPlayer.Character.HumanoidRootPart.CFrame end)
                                    end
                                end
                            end
                        end
                    end)
                end
            end
            task.wait(MAIN_LOOP_DELAY)
        end
    end)

    print("[AutoFarm] loaded.")

end)

if not ok then
    warn("[AutoFarm] Startup error:", mainErr)
else
    print("[AutoFarm] script executed successfully.")
end
