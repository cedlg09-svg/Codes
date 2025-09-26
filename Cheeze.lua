-- Hate's AutoFarm — Final (Area TextBox above World dropdown + Set Area button)
-- Paste into a NEW LocalScript and run

local ok, mainErr = pcall(function()
    -- ===== CONFIG =====
    local JOIN_DELAY = 0.06
    local CHANGE_DELAY = 0.04
    local MAIN_LOOP_DELAY = 0.9
    local SAFE_LOOP_DELAY = 2.0
    local EQUIP_WAIT = 0.45
    local RETARGET_DELAY = 0.3

    local MAX_ASSIGN_PER_CYCLE = 4
    local MAX_ASSIGN_PER_CYCLE_SAFE = 2

    math.randomseed(tick() % 1e6)

    -- ===== WORLDS TABLE (static) =====
    local WorldsTable = {
        ["Spawn"] = {"Shop","Town","Forest","Beach","Mine","Winter","Glacier","Desert","Volcano","Cave","Tech Entry","VIP"},
        ["Fantasy"] = {"Fantasy Shop","Enchanted Forest","Portals","Ancient Island","Samurai Island","Candy Island","Haunted Island","Hell Island","Heaven Island","Heaven's Gate"},
        ["Tech"] = {"Tech Shop","Tech City","Dark Tech","Steampunk","Steampunk Chest Area","Alien Lab","Alien Forest","Giant Alien Chest","Glitch","Hacker Portal"},
        ["Void"] = {"The Void"},
        ["Axolotl Ocean"] = {"Axolotl Ocean","Axolotl Deep Ocean","Axolotl Cave"},
        ["Pixel"] = {"Pixel Forest","Pixel Kyoto","Pixel Alps","Pixel Vault"},
        ["Cat"] = {"Cat Paradise","Cat Backyard","Cat Taiga","Cat Throne Room"}
    }

    -- ===== SERVICES =====
    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local Workspace = game:GetService("Workspace")
    local LocalPlayer = Players.LocalPlayer
    assert(LocalPlayer, "LocalPlayer nil - run as LocalScript")
    local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

    local Network = ReplicatedStorage:FindFirstChild("Network")
    if not Network then
        warn("[Hate AutoFarm] ReplicatedStorage.Network not found. Remotes may be missing.")
    end

    -- ===== SAFE REMOTE HELPER =====
    local function CallRemote(name, args)
        args = args or {}
        if not Network then return false end
        local r = Network:FindFirstChild(name)
        if not r then return false end
        if r.ClassName == "RemoteFunction" then
            local ok, res = pcall(function() return r:InvokeServer(table.unpack(args)) end)
            return ok, res
        elseif r.ClassName == "RemoteEvent" then
            local ok, res = pcall(function() r:FireServer(table.unpack(args)) end)
            return ok, res
        end
        return false
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

    -- ===== UTIL =====
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

    -- ===== STATE =====
    local SelectedWorld = "Spawn"
    local SelectedArea = "Town"
    local Enabled = false        -- normal farm
    local SafeEnabled = false    -- safe farm (slow + stealth)
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
        return pickTopNFromSave()
    end

    -- ===== ASSIGNMENT (one pet per breakable) =====
    local function AssignPetToBreakable(petUID, breakId, safeMode)
        if not petUID or not breakId then return false end
        if safeMode then
            local j = JOIN_DELAY + (math.random(30,120)/1000)
            local c = CHANGE_DELAY + (math.random(30,120)/1000)
            local f = j + c + (math.random(20,80)/1000)
            safe_delay(0, function() JoinCoin(breakId, {petUID}) end)
            safe_delay(j, function() ChangePetTarget(petUID, "Coin", breakId) end)
            safe_delay(f, function() FarmCoin(breakId, petUID) end)
        else
            safe_delay(0, function() JoinCoin(breakId, {petUID}) end)
            safe_delay(JOIN_DELAY, function() ChangePetTarget(petUID, "Coin", breakId) end)
            safe_delay(JOIN_DELAY + CHANGE_DELAY, function() FarmCoin(breakId, petUID) end)
        end

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
                if tostring(w) == tostring(SelectedWorld) and tostring(a):lower() == tostring(SelectedArea):lower() then
                    if not targetToPet[id] then
                        table.insert(available, { id = id, data = item })
                    end
                end
            end
        end
        return available
    end

    local function FillAssignments(coins, safeMode)
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

        local maxPerCycle = safeMode and MAX_ASSIGN_PER_CYCLE_SAFE or MAX_ASSIGN_PER_CYCLE
        local count = math.min(maxPerCycle, #freePets, #available)
        for i = 1, count do
            local pet = freePets[i]
            local target = available[i]
            if pet and target and target.id then
                pcall(function() AssignPetToBreakable(pet, target.id, safeMode) end)
                task.wait(safeMode and (0.25 + math.random(0,150)/1000) or (0.02 + math.random(0,40)/1000))
            end
        end
    end

    -- ===== GUI HELPERS =====
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
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0,6)

        local menu = Instance.new("Frame", parent)
        menu.Size = UDim2.new(0, width, 0, math.min(#options*24, 200))
        menu.Position = UDim2.new(0, posX, 0, posY + 46)
        menu.Visible = false
        menu.BackgroundColor3 = Color3.fromRGB(14,14,14)
        Instance.new("UICorner", menu).CornerRadius = UDim.new(0,6)
        local layout = Instance.new("UIListLayout", menu)
        layout.Padding = UDim.new(0,4)

        local function populate(opts)
            for _, c in ipairs(menu:GetChildren()) do if not c:IsA("UIListLayout") then c:Destroy() end end
            for _, opt in ipairs(opts) do
                local optBtn = Instance.new("TextButton", menu)
                optBtn.Size = UDim2.new(1, -8, 0, 20)
                optBtn.Position = UDim2.new(0, 4, 0, 0)
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
        btn.MouseButton1Click:Connect(function() menu.Visible = not menu.Visible end)

        return {
            Button = btn,
            Menu = menu,
            Label = label,
            SetOptions = function(newOptions) populate(newOptions) end
        }
    end

    -- ===== GUI =====
    local function CreateGUI()
        local screenGui = Instance.new("ScreenGui")
        screenGui.Name = "Hate_AutoFarm_GUI"
        screenGui.ResetOnSpawn = false
        screenGui.Parent = PlayerGui

        local frame = Instance.new("Frame", screenGui)
        frame.Size = UDim2.new(0, 320, 0, 220)
        frame.Position = UDim2.new(0, 5, 0, 36) -- top-left below Roblox settings
        frame.BackgroundColor3 = Color3.fromRGB(0,0,0)
        Instance.new("UICorner", frame).CornerRadius = UDim.new(0,6)

        -- Minimize button 20x20 top-left inside frame
        local minBtn = Instance.new("TextButton", frame)
        minBtn.Size = UDim2.new(0, 20, 0, 20)
        minBtn.Position = UDim2.new(0, 6, 0, 4)
        minBtn.Text = "-"
        minBtn.Font = Enum.Font.SourceSansBold
        minBtn.TextSize = 14
        minBtn.TextColor3 = Color3.new(1,1,1)
        minBtn.BackgroundColor3 = Color3.fromRGB(30,30,30)
        Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0,4)

        local restoreBtn -- created when minimized

        -- Title (aligned near top-center)
        local title = Instance.new("TextLabel", frame)
        title.Size = UDim2.new(1, -40, 0, 26)
        title.Position = UDim2.new(0, 30, 0, 6)
        title.BackgroundTransparency = 1
        title.Font = Enum.Font.SourceSansBold
        title.TextSize = 16
        title.TextColor3 = Color3.new(1,1,1)
        title.Text = "Hate's AutoFarm"

        -- Layout constants
        local leftX = 10
        local rightX = 168
        local topY = 40
        local spacingY = 5

        -- Left column (buttons)
        local pickBtn = Instance.new("TextButton", frame)
        pickBtn.Size = UDim2.new(0, 140, 0, 36)
        pickBtn.Position = UDim2.new(0, leftX, 0, topY)
        pickBtn.Text = "Pick Best Pets"
        pickBtn.Font = Enum.Font.SourceSansBold
        pickBtn.BackgroundColor3 = Color3.fromRGB(30,30,30)
        pickBtn.TextColor3 = Color3.new(1,1,1)
        Instance.new("UICorner", pickBtn).CornerRadius = UDim.new(0,6)

        local startBtn = Instance.new("TextButton", frame)
        startBtn.Size = UDim2.new(0, 140, 0, 36)
        startBtn.Position = UDim2.new(0, leftX, 0, topY + (36 + spacingY))
        startBtn.Text = "Start"
        startBtn.Font = Enum.Font.SourceSansBold
        startBtn.BackgroundColor3 = Color3.fromRGB(34,139,34)
        startBtn.TextColor3 = Color3.new(1,1,1)
        Instance.new("UICorner", startBtn).CornerRadius = UDim.new(0,6)

        local safeFarmBtn = Instance.new("TextButton", frame)
        safeFarmBtn.Size = UDim2.new(0, 140, 0, 26)
        safeFarmBtn.Position = UDim2.new(0, leftX, 0, topY + (36 + spacingY)*2 + 6)
        safeFarmBtn.Text = "Safe Farm: Off"
        safeFarmBtn.Font = Enum.Font.SourceSansBold
        safeFarmBtn.BackgroundColor3 = Color3.fromRGB(30,30,30)
        safeFarmBtn.TextColor3 = Color3.new(1,1,1)
        Instance.new("UICorner", safeFarmBtn).CornerRadius = UDim.new(0,6)

        local setAreaBtn = Instance.new("TextButton", frame)
        setAreaBtn.Size = UDim2.new(0, 140, 0, 26)
        setAreaBtn.Position = UDim2.new(0, leftX, 0, topY + (36 + spacingY)*3 + 12)
        setAreaBtn.Text = "Set Area"
        setAreaBtn.Font = Enum.Font.SourceSansBold
        setAreaBtn.BackgroundColor3 = Color3.fromRGB(30,30,30)
        setAreaBtn.TextColor3 = Color3.new(1,1,1)
        Instance.new("UICorner", setAreaBtn).CornerRadius = UDim.new(0,6)

        -- Right column: Area TextBox above World dropdown
        local areaLabel = Instance.new("TextLabel", frame)
        areaLabel.Size = UDim2.new(0, 140, 0, 18)
        areaLabel.Position = UDim2.new(0, rightX, 0, topY - 4)
        areaLabel.BackgroundTransparency = 1
        areaLabel.Text = "Area (type):"
        areaLabel.TextColor3 = Color3.new(1,1,1)
        areaLabel.Font = Enum.Font.SourceSans
        areaLabel.TextSize = 14

        local areaBox = Instance.new("TextBox", frame)
        areaBox.Size = UDim2.new(0, 140, 0, 26)
        areaBox.Position = UDim2.new(0, rightX, 0, topY + 14)
        areaBox.PlaceholderText = "Type area name (e.g. Beach)"
        areaBox.Text = tostring(SelectedArea)
        areaBox.Font = Enum.Font.SourceSans
        areaBox.TextSize = 14
        areaBox.TextColor3 = Color3.new(1,1,1)
        areaBox.BackgroundColor3 = Color3.fromRGB(20,20,20)
        Instance.new("UICorner", areaBox).CornerRadius = UDim.new(0,6)

        -- World dropdown below textbox
        local worldDropdown = makeDropdown(frame, rightX, topY + (26 + spacingY) + 14, 140, "World", (function()
            local t = {}
            for k,_ in pairs(WorldsTable) do table.insert(t, k) end
            table.sort(t)
            return t
        end)(), function(selected)
            SelectedWorld = selected
            -- When world changes, if the typed area matches one in the table (case-insensitive), keep it; otherwise default to first area
            local areas = WorldsTable[SelectedWorld] or {}
            local typed = tostring(areaBox.Text or ""):lower()
            local matched = false
            for _, a in ipairs(areas) do
                if tostring(a):lower() == typed then
                    SelectedArea = a
                    matched = true
                    break
                end
            end
            if not matched then
                SelectedArea = areas[1] or ""
                areaBox.Text = SelectedArea
            else
                areaBox.Text = SelectedArea
            end
            petToTarget = {}
            targetToPet = {}
            petCooldowns = {}
        end)

        -- Status label bottom
        local status = Instance.new("TextLabel", frame)
        status.Size = UDim2.new(1, -12, 0, 20)
        status.Position = UDim2.new(0, 6, 0, 190)
        status.BackgroundTransparency = 1
        status.Font = Enum.Font.SourceSans
        status.TextSize = 14
        status.TextColor3 = Color3.new(1,1,1)
        status.Text = "Status: Idle"

        -- Minimize / restore behavior
        minBtn.MouseButton1Click:Connect(function()
            frame.Visible = false
            -- create restore button if not present
            if not restoreBtn or not restoreBtn.Parent then
                restoreBtn = Instance.new("TextButton", screenGui)
                restoreBtn.Name = "HateRestore"
                restoreBtn.Size = UDim2.new(0, 20, 0, 20)
                restoreBtn.Position = frame.Position -- same position
                restoreBtn.Text = "H"
                restoreBtn.Font = Enum.Font.SourceSansBold
                restoreBtn.TextSize = 14
                restoreBtn.TextColor3 = Color3.new(1,1,1)
                restoreBtn.BackgroundColor3 = Color3.fromRGB(30,30,30)
                Instance.new("UICorner", restoreBtn).CornerRadius = UDim.new(0,4)
                restoreBtn.MouseButton1Click:Connect(function()
                    frame.Visible = true
                    if restoreBtn and restoreBtn.Parent then restoreBtn:Destroy() end
                end)
            end
        end)

        -- Button behaviours
        pickBtn.MouseButton1Click:Connect(function()
            status.Text = "Status: Equipping best pets..."
            local chosen = pickTopNFromSave()
            if #chosen == 0 then
                status.Text = "Status: No pets found."
                return
            end
            trackedPets = chosen
            for _, uid in ipairs(trackedPets) do
                pcall(function() EquipPet(uid) end)
                task.wait(0.06)
            end
            task.wait(EQUIP_WAIT)
            status.Text = ("Status: Equipped %d pets"):format(#trackedPets)
        end)

        startBtn.MouseButton1Click:Connect(function()
            Enabled = not Enabled
            if Enabled then
                startBtn.Text = "Stop"
                startBtn.BackgroundColor3 = Color3.fromRGB(178,34,34)
                status.Text = ("Status: Farming (%s - %s)"):format(tostring(SelectedWorld), tostring(SelectedArea))
            else
                startBtn.Text = "Start"
                startBtn.BackgroundColor3 = Color3.fromRGB(34,139,34)
                status.Text = "Status: Stopped"
            end
        end)

        safeFarmBtn.MouseButton1Click:Connect(function()
            SafeEnabled = not SafeEnabled
            safeFarmBtn.Text = SafeEnabled and "Safe Farm: On" or "Safe Farm: Off"
            status.Text = SafeEnabled and ("Status: Safe Farm enabled (%s - %s)"):format(tostring(SelectedWorld), tostring(SelectedArea)) or status.Text
        end)

        setAreaBtn.MouseButton1Click:Connect(function()
            local typed = tostring(areaBox.Text or "")
            typed = typed:match("^%s*(.-)%s*$") or typed -- trim
            if typed == "" then
                status.Text = "Status: Enter area name first"
                return
            end
            -- case-insensitive match: if matches existing area under selected world, standardize casing
            local areas = WorldsTable[SelectedWorld] or {}
            local matched = false
            for _, a in ipairs(areas) do
                if tostring(a):lower() == typed:lower() then
                    SelectedArea = a
                    areaBox.Text = a
                    matched = true
                    break
                end
            end
            if not matched then
                -- accept typed value as-is (user typed custom area). We keep it (case-insensitive comparisons used in GetAvailableBreakables)
                SelectedArea = typed
            end
            -- clear assignments so pets retarget into new area
            petToTarget = {}
            targetToPet = {}
            petCooldowns = {}
            status.Text = ("Status: Area set to %s"):format(tostring(SelectedArea))
        end)

        return {
            Gui = screenGui,
            Frame = frame,
            Status = status,
            WorldDropdown = worldDropdown,
            AreaBox = areaBox
        }
    end

    local ui = CreateGUI()

    -- ===== MAIN LOOPS =====
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
                    ui.Status.Text = "Status: Waiting for coins..."
                    task.wait(1)
                else
                    ui.Status.Text = ("Status: Farming (%s - %s)"):format(tostring(SelectedWorld), tostring(SelectedArea))
                    FreeStaleAssignments(coins)
                    FillAssignments(coins, false)
                    pcall(function() ClaimOrbs({}) end)
                    pcall(function()
                        local things = Workspace:FindFirstChild("__THINGS") or Workspace:FindFirstChild("__things")
                        if things then
                            local bags = things:FindFirstChild("Lootbags")
                            if bags and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                                for _, bag in ipairs(bags:GetChildren()) do
                                    if bag and bag:IsA("BasePart") then
                                        pcall(function() bag.CFrame = LocalPlayer.Character.HumanoidRootPart.CFrame end)
                                        task.wait(0.05)
                                    end
                                end
                            end
                        end
                    end)
                end
            end

            if SafeEnabled then
                if #trackedPets == 0 then
                    trackedPets = pickTopNFromSave()
                    for _, uid in ipairs(trackedPets) do
                        pcall(function() EquipPet(uid) end)
                        task.wait(0.09 + math.random(0,80)/1000)
                    end
                    task.wait(EQUIP_WAIT + 0.1)
                end

                local coins = GetCoinsRaw()
                if coins then
                    ui.Status.Text = ("Status: Safe Farming (%s - %s)"):format(tostring(SelectedWorld), tostring(SelectedArea))
                    FreeStaleAssignments(coins)
                    FillAssignments(coins, true)
                    pcall(function() ClaimOrbs({}) end)
                    pcall(function()
                        local things = Workspace:FindFirstChild("__THINGS") or Workspace:FindFirstChild("__things")
                        if things then
                            local bags = things:FindFirstChild("Lootbags")
                            if bags and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                                for _, bag in ipairs(bags:GetChildren()) do
                                    if bag and bag:IsA("BasePart") then
                                        pcall(function() bag.CFrame = LocalPlayer.Character.HumanoidRootPart.CFrame end)
                                        task.wait(0.12 + math.random(0,120)/1000)
                                    end
                                end
                            end
                        end
                    end)
                else
                    ui.Status.Text = "Status: Waiting for coins..."
                end

                task.wait(SAFE_LOOP_DELAY + math.random(0,200)/1000)
            end

            task.wait(MAIN_LOOP_DELAY + math.random(0,200)/1000)
        end
    end)

    print("[Hate AutoFarm] Loaded. Use Pick Best Pets -> Start or enable Safe Farm and Set Area.")
end)

if not ok then
    warn("[Hate AutoFarm] Startup error:", mainErr)
else
    print("[Hate AutoFarm] Script executed successfully!")
end
