-- Hate's Autofarm — Final Full Build
-- Paste into a NEW LocalScript and run in Delta / normal environment

local ok, mainErr = pcall(function()

    -- ======= CONFIG =======
    local SAFE_DELAY_BETWEEN_ASSIGN = 0.18
    local JOIN_DELAY = 0.06
    local CHANGE_DELAY = 0.04
    local MAIN_LOOP_DELAY = 0.8
    local SAFE_EXTRA_DELAY = 0.6
    local EQUIP_WAIT = 0.45
    local RETARGET_DELAY = 0.3

    -- ======= STATIC WORLDS TABLE (your original) =======
    local WorldsTable = {
        ["Spawn"] = {"Shop","Town","Forest","Beach","Mine","Winter","Glacier","Desert","Volcano","Cave","Tech Entry","VIP"},
        ["Fantasy"] = {"Fantasy Shop","Enchanted Forest","Portals","Ancient Island","Samurai Island","Candy Island","Haunted Island","Hell Island","Heaven Island","Heaven's Gate"},
        ["Tech"] = {"Tech Shop","Tech City","Dark Tech","Steampunk","Steampunk Chest Area","Alien Lab","Alien Forest","Giant Alien Chest","Glitch","Hacker Portal"},
        ["Void"] = {"The Void"},
        ["Axolotl Ocean"] = {"Axolotl Ocean","Axolotl Deep Ocean","Axolotl Cave"},
        ["Pixel"] = {"Pixel Forest","Pixel Kyoto","Pixel Alps","Pixel Vault"},
        ["Cat"] = {"Cat Paradise","Cat Backyard","Cat Taiga","Cat Throne Room"}
    }

    local TargetTypeOptions = {"Any","Coins","Diamonds","Chests","Breakables"}

    -- ======= SERVICES & BASIC SETUP =======
    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local Workspace = game:GetService("Workspace")
    local UserInputService = game:GetService("UserInputService")
    local LocalPlayer = Players.LocalPlayer
    assert(LocalPlayer, "LocalPlayer nil - run as LocalScript")
    local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

    local Network = ReplicatedStorage:FindFirstChild("Network")
    if not Network then
        warn("[Hate AutoFarm] ReplicatedStorage.Network not found. Remotes may be missing.")
    end

    -- ======= SAFE REMOTE CALLER (no varargs at top-level) =======
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

    -- ======= UTILITIES =======
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

    -- ======= STATE =======
    local SelectedWorld = "Spawn"
    local SelectedArea = (WorldsTable["Spawn"] and WorldsTable["Spawn"][1]) or ""
    local TargetNearestType = "Any"
    local Mode = "None" -- "None","Normal","Safe","Blatant","Nearest"
    local trackedPets = {}
    local petToTarget = {}
    local targetToPet = {}
    local petCooldowns = {}

    -- ======= ASSIGNMENT HELPERS =======
    local function ClearAssignment(uid)
        if not uid then return end
        local t = petToTarget[uid]
        if t then petToTarget[uid] = nil; targetToPet[t] = nil end
        petCooldowns[uid] = tick() + RETARGET_DELAY
    end

    local function FreeStaleAssignments(coins)
        local present = {}
        if coins then for id,_ in pairs(coins) do present[id] = true end end
        for uid, tid in pairs(petToTarget) do
            if not present[tid] then ClearAssignment(uid) end
        end
    end

    local function matchesTargetType(ttype, coinData)
        if not ttype or ttype == "Any" then return true end
        if not coinData then return false end
        local name = tostring(coinData.n or coinData.name or ""):lower()
        if ttype == "Coins" then return (name:find("coin") ~= nil) end
        if ttype == "Diamonds" then return (name:find("diamond") ~= nil or name:find("gem") ~= nil) end
        if ttype == "Chests" then return (name:find("chest") ~= nil or name:find("crate") ~= nil) end
        if ttype == "Breakables" then return true end
        return true
    end

    local function GetAvailableBreakablesForArea(coins)
        local avail = {}
        if not coins then return avail end
        for id, data in pairs(coins) do
            if type(data) == "table" then
                local w = tostring(data.w or data.world or "")
                local a = tostring(data.a or data.area or "")
                if w == tostring(SelectedWorld) and a == tostring(SelectedArea) and not targetToPet[id] and matchesTargetType(TargetNearestType, data) then
                    table.insert(avail, {id = id, data = data})
                end
            end
        end
        return avail
    end

    local function AssignPetToBreakable(uid, breakId, safe)
        if not uid or not breakId then return false end
        if safe then
            local j = JOIN_DELAY + math.random(80,220)/1000
            local c = CHANGE_DELAY + math.random(80,220)/1000
            safe_delay(0, function() JoinCoin(breakId, {uid}) end)
            safe_delay(j, function() ChangePetTarget(uid, "Coin", breakId) end)
            safe_delay(j + c, function() FarmCoin(breakId, uid) end)
        else
            safe_delay(0, function() JoinCoin(breakId, {uid}) end)
            safe_delay(JOIN_DELAY, function() ChangePetTarget(uid, "Coin", breakId) end)
            safe_delay(JOIN_DELAY + CHANGE_DELAY, function() FarmCoin(breakId, uid) end)
        end
        petToTarget[uid] = breakId
        targetToPet[breakId] = uid
        petCooldowns[uid] = tick()
        return true
    end

    local function FillAssignmentsNormal(coins)
        local petUIDs = (function()
            local u = {}
            local save = GetSave()
            if save and save.Pets then
                for _, p in pairs(save.Pets) do
                    if type(p)=="table" and p.uid then
                        local isEq = false
                        if p.equipped == true or p.eq == true or p[1] == true or p["1"] == true then isEq = true end
                        if isEq then table.insert(u, p.uid) end
                    end
                end
            end
            if #u == 0 then return pickTopNFromSave() end
            return u
        end)()

        if #petUIDs == 0 then return end
        local freePets = {}
        for _, uid in ipairs(petUIDs) do
            if not petToTarget[uid] then
                local cd = petCooldowns[uid] or 0
                if tick() >= cd then table.insert(freePets, uid) end
            end
        end
        if #freePets == 0 then return end

        local avail = GetAvailableBreakablesForArea(coins)
        if #avail == 0 then return end

        local count = math.min(#freePets, #avail)
        for i=1, count do
            local pet = freePets[i]
            local target = avail[i]
            if pet and target and target.id then
                pcall(function() AssignPetToBreakable(pet, target.id, false) end)
                task.wait(SAFE_DELAY_BETWEEN_ASSIGN)
            end
        end
    end

    local function FillAssignmentsSafe(coins)
        local petUIDs = pickTopNFromSave()
        if #petUIDs == 0 then return end
        local freePets = {}
        for _, uid in ipairs(petUIDs) do
            if not petToTarget[uid] then
                local cd = petCooldowns[uid] or 0
                if tick() >= cd then table.insert(freePets, uid) end
            end
        end
        if #freePets == 0 then return end
        local avail = GetAvailableBreakablesForArea(coins)
        if #avail == 0 then return end
        local count = math.min(#freePets, #avail, 2)
        for i=1, count do
            local pet = freePets[i]
            local target = avail[i]
            if pet and target and target.id then
                pcall(function() AssignPetToBreakable(pet, target.id, true) end)
                task.wait(0.3 + math.random(0,300)/1000)
            end
        end
    end

    local function FillAssignmentsBlatant(coins)
        local petUIDs = pickTopNFromSave()
        if #petUIDs == 0 then return end
        local freePets = {}
        for _, uid in ipairs(petUIDs) do
            if not petToTarget[uid] then
                local cd = petCooldowns[uid] or 0
                if tick() >= cd then table.insert(freePets, uid) end
            end
        end
        if #freePets == 0 then return end
        local avail = GetAvailableBreakablesForArea(coins)
        if #avail == 0 then return end
        local iPet, iAvail = 1, 1
        while iPet <= #freePets and iAvail <= #avail do
            local pet = freePets[iPet]; local target = avail[iAvail]
            if pet and target and target.id then
                pcall(function() AssignPetToBreakable(pet, target.id, false) end)
                iPet = iPet + 1; iAvail = iAvail + 1
                task.wait(0.01)
            else
                iAvail = iAvail + 1
            end
        end
    end

    local function TargetNearestAll(coins)
        if not coins then return end
        if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then return end
        local hrp = LocalPlayer.Character.HumanoidRootPart
        local bestId, bestDist = nil, math.huge
        for id, data in pairs(coins) do
            if type(data) == "table" and matchesTargetType(TargetNearestType, data) then
                local p = data.p
                if p and typeof(p) == "Vector3" then
                    local d = (hrp.Position - p).Magnitude
                    if d < bestDist then bestDist = d; bestId = id end
                end
            end
        end
        if not bestId then return end
        local petUIDs = pickTopNFromSave()
        for _, uid in ipairs(petUIDs) do
            if petToTarget[uid] ~= bestId then
                pcall(function()
                    safe_delay(0, function() JoinCoin(bestId, {uid}) end)
                    safe_delay(JOIN_DELAY, function() ChangePetTarget(uid, "Coin", bestId) end)
                    safe_delay(JOIN_DELAY + CHANGE_DELAY, function() FarmCoin(bestId, uid) end)
                    petToTarget[uid] = bestId
                    targetToPet[bestId] = uid
                    petCooldowns[uid] = tick()
                end)
                task.wait(0.03)
            end
        end
    end

    -- ======= GUI HELPERS (small, clean, black) =======
    local function makeDropdown(parent, posX, posY, width, labelText, options, onSelect)
        options = options or {}
        local label = Instance.new("TextLabel", parent)
        label.Size = UDim2.new(0, width, 0, 14)
        label.Position = UDim2.new(0, posX, 0, posY)
        label.BackgroundTransparency = 1
        label.Text = labelText
        label.TextColor3 = Color3.new(1,1,1)
        label.Font = Enum.Font.SourceSans
        label.TextSize = 12

        local btn = Instance.new("TextButton", parent)
        btn.Size = UDim2.new(0, width, 0, 22)
        btn.Position = UDim2.new(0, posX, 0, posY + 14)
        btn.Text = options[1] or "None"
        btn.Font = Enum.Font.SourceSans
        btn.TextSize = 12
        btn.TextColor3 = Color3.new(1,1,1)
        btn.BackgroundColor3 = Color3.fromRGB(20,20,20)
        btn.AutoButtonColor = true
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0,6)

        local menu = Instance.new("Frame", parent)
        menu.Size = UDim2.new(0, width, 0, math.min(#options*20, 200))
        menu.Position = UDim2.new(0, posX, 0, posY + 36)
        menu.Visible = false
        menu.BackgroundColor3 = Color3.fromRGB(12,12,12)
        Instance.new("UICorner", menu).CornerRadius = UDim.new(0,6)
        local layout = Instance.new("UIListLayout", menu)
        layout.Padding = UDim.new(0,4)

        local function populate(opts)
            for _, c in ipairs(menu:GetChildren()) do if not c:IsA("UIListLayout") then c:Destroy() end end
            for _, opt in ipairs(opts) do
                local optBtn = Instance.new("TextButton", menu)
                optBtn.Size = UDim2.new(1, -8, 0, 18)
                optBtn.Position = UDim2.new(0,4,0,0)
                optBtn.Text = opt
                optBtn.BackgroundTransparency = 1
                optBtn.Font = Enum.Font.SourceSans
                optBtn.TextColor3 = Color3.new(1,1,1)
                optBtn.TextSize = 12
                optBtn.AutoButtonColor = true
                optBtn.MouseButton1Click:Connect(function()
                    btn.Text = opt
                    menu.Visible = false
                    onSelect(opt)
                end)
            end
            menu.Size = UDim2.new(0, width, 0, math.min(#opts*22, 200))
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

    -- ======= GUI (top-left, black, minimize 20x20) =======
    local function CreateGUI()
        local screenGui = Instance.new("ScreenGui")
        screenGui.Name = "Hate_AutoFarm_GUI"
        screenGui.ResetOnSpawn = false
        screenGui.Parent = PlayerGui

        local frame = Instance.new("Frame", screenGui)
        frame.Size = UDim2.new(0, 360, 0, 220)
        frame.Position = UDim2.new(0, 10, 0, 36) -- fixed top-left below Roblox top bar
        frame.BackgroundColor3 = Color3.fromRGB(12,12,12)
        Instance.new("UICorner", frame).CornerRadius = UDim.new(0,6)
        frame.Active = true -- for mobile interactions
        -- draggable (user asked to keep draggable earlier and mobile friendly)
        local dragging, dragInput, dragStart, startPos
        frame.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = true
                dragStart = input.Position
                startPos = frame.Position
                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then
                        dragging = false
                    end
                end)
            end
        end)
        frame.InputChanged:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
                dragInput = input
            end
        end)
        UserInputService.InputChanged:Connect(function(input)
            if input == dragInput and dragging and dragStart and startPos then
                local delta = input.Position - dragStart
                frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            end
        end)

        -- Minimize button top-right (20x20)
        local minBtn = Instance.new("TextButton", frame)
        minBtn.Size = UDim2.new(0, 20, 0, 20)
        minBtn.Position = UDim2.new(1, -26, 0, 6)
        minBtn.Text = "▢"
        minBtn.Font = Enum.Font.SourceSansBold
        minBtn.TextSize = 14
        minBtn.BackgroundColor3 = Color3.fromRGB(28,28,28)
        minBtn.TextColor3 = Color3.new(1,1,1)
        Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0,4)

        local title = Instance.new("TextLabel", frame)
        title.Size = UDim2.new(1, -52, 0, 24)
        title.Position = UDim2.new(0, 10, 0, 6)
        title.BackgroundTransparency = 1
        title.Font = Enum.Font.SourceSansBold
        title.TextSize = 14
        title.TextColor3 = Color3.new(1,1,1)
        title.Text = "Hate's Autofarm"

        -- Buttons top row
        local pickBtn = Instance.new("TextButton", frame)
        pickBtn.Size = UDim2.new(0.48, -8, 0, 34)
        pickBtn.Position = UDim2.new(0, 10, 0, 36)
        pickBtn.Text = "Pick Best Pets"
        pickBtn.Font = Enum.Font.SourceSansBold
        pickBtn.BackgroundColor3 = Color3.fromRGB(20,20,20)
        pickBtn.TextColor3 = Color3.new(1,1,1)
        Instance.new("UICorner", pickBtn).CornerRadius = UDim.new(0,6)

        local startBtn = Instance.new("TextButton", frame)
        startBtn.Size = UDim2.new(0.48, -8, 0, 34)
        startBtn.Position = UDim2.new(0, 186, 0, 36)
        startBtn.Text = "Start"
        startBtn.Font = Enum.Font.SourceSansBold
        startBtn.BackgroundColor3 = Color3.fromRGB(20,20,20)
        startBtn.TextColor3 = Color3.new(1,1,1)
        Instance.new("UICorner", startBtn).CornerRadius = UDim.new(0,6)

        -- Mode buttons (small)
        local normalBtn = Instance.new("TextButton", frame)
        normalBtn.Size = UDim2.new(0.30, -6, 0, 22)
        normalBtn.Position = UDim2.new(0, 10, 0, 78)
        normalBtn.Text = "Normal"
        normalBtn.Font = Enum.Font.SourceSans
        normalBtn.BackgroundColor3 = Color3.fromRGB(18,18,18)
        normalBtn.TextColor3 = Color3.new(1,1,1)
        Instance.new("UICorner", normalBtn).CornerRadius = UDim.new(0,6)

        local safeBtn = Instance.new("TextButton", frame)
        safeBtn.Size = UDim2.new(0.30, -6, 0, 22)
        safeBtn.Position = UDim2.new(0, 126, 0, 78)
        safeBtn.Text = "Safe"
        safeBtn.Font = Enum.Font.SourceSans
        safeBtn.BackgroundColor3 = Color3.fromRGB(18,18,18)
        safeBtn.TextColor3 = Color3.new(1,1,1)
        Instance.new("UICorner", safeBtn).CornerRadius = UDim.new(0,6)

        local blatBtn = Instance.new("TextButton", frame)
        blatBtn.Size = UDim2.new(0.30, -6, 0, 22)
        blatBtn.Position = UDim2.new(0, 242, 0, 78)
        blatBtn.Text = "Blatant"
        blatBtn.Font = Enum.Font.SourceSans
        blatBtn.BackgroundColor3 = Color3.fromRGB(18,18,18)
        blatBtn.TextColor3 = Color3.new(1,1,1)
        Instance.new("UICorner", blatBtn).CornerRadius = UDim.new(0,6)

        -- Target Nearest
        local nearestBtn = Instance.new("TextButton", frame)
        nearestBtn.Size = UDim2.new(0.96, -16, 0, 26)
        nearestBtn.Position = UDim2.new(0, 10, 0, 108)
        nearestBtn.Text = "Target Nearest (All Pets)"
        nearestBtn.Font = Enum.Font.SourceSans
        nearestBtn.BackgroundColor3 = Color3.fromRGB(18,18,18)
        nearestBtn.TextColor3 = Color3.new(1,1,1)
        Instance.new("UICorner", nearestBtn).CornerRadius = UDim.new(0,6)

        -- Dropdowns area (5px below the buttons)
        local dropdownY = 142

        local worldDropdown = nil
        local areaDropdown = nil
        local targetDropdown = nil

        worldDropdown = makeDropdown(frame, 10, dropdownY, 160, "World", (function()
            local t = {}
            for k,_ in pairs(WorldsTable) do table.insert(t, k) end
            table.sort(t)
            return t
        end)(), function(selected)
            SelectedWorld = selected or SelectedWorld
            local areas = WorldsTable[SelectedWorld] or {}
            if areaDropdown then
                areaDropdown.SetOptions(areas)
                if #areas > 0 then
                    SelectedArea = areas[1]
                    areaDropdown.Button.Text = areas[1]
                else
                    SelectedArea = ""
                    areaDropdown.Button.Text = "None"
                end
            end
            petToTarget = {}
            targetToPet = {}
            petCooldowns = {}
        end)

        areaDropdown = makeDropdown(frame, 184, dropdownY, 160, "Area", WorldsTable[SelectedWorld] or {}, function(selected)
            SelectedArea = selected or SelectedArea
            petToTarget = {}
            targetToPet = {}
            petCooldowns = {}
        end)

        targetDropdown = makeDropdown(frame, 10, dropdownY + 56, 160, "Target Type", TargetTypeOptions, function(selected)
            TargetNearestType = selected or TargetNearestType
        end)

        -- Egg animation remove toggle & auto-hatch placeholders
        local eggToggle = Instance.new("TextButton", frame)
        eggToggle.Size = UDim2.new(0.48, -8, 0, 26)
        eggToggle.Position = UDim2.new(0, 184, 0, dropdownY + 56)
        eggToggle.Text = "Egg Anim: OFF"
        eggToggle.Font = Enum.Font.SourceSans
        eggToggle.BackgroundColor3 = Color3.fromRGB(18,18,18)
        eggToggle.TextColor3 = Color3.new(1,1,1)
        Instance.new("UICorner", eggToggle).CornerRadius = UDim.new(0,6)
        local eggAnimDisabled = false

        -- Placeholders for Auto Fuse/Gold/Rainbow/DarkMatter/Hatch sections (empty for now)
        local placeholderLabel = Instance.new("TextLabel", frame)
        placeholderLabel.Size = UDim2.new(1, -20, 0, 18)
        placeholderLabel.Position = UDim2.new(0, 10, 0, 188)
        placeholderLabel.BackgroundTransparency = 1
        placeholderLabel.Font = Enum.Font.SourceSans
        placeholderLabel.TextSize = 12
        placeholderLabel.TextColor3 = Color3.new(1,1,1)
        placeholderLabel.Text = "Placeholders: Auto Fuse | Gold | Rainbow | DarkMatter | Auto Hatch (configure later)"

        -- Status label
        local statusLabel = Instance.new("TextLabel", frame)
        statusLabel.Size = UDim2.new(1, -20, 0, 18)
        statusLabel.Position = UDim2.new(0, 10, 0, 206)
        statusLabel.BackgroundTransparency = 1
        statusLabel.Font = Enum.Font.SourceSans
        statusLabel.TextSize = 12
        statusLabel.TextColor3 = Color3.new(1,1,1)
        statusLabel.Text = ("Mode: %s | World: %s | Area: %s | Pets: %d"):format(Mode, SelectedWorld, SelectedArea, #trackedPets)

        -- Restore small button (always visible when minimized)
        local restoreBtn = Instance.new("TextButton", PlayerGui)
        restoreBtn.Name = "HateRestore"
        restoreBtn.Size = UDim2.new(0, 28, 0, 28)
        restoreBtn.Position = UDim2.new(0, 10, 0, 36)
        restoreBtn.Text = "H"
        restoreBtn.Font = Enum.Font.SourceSansBold
        restoreBtn.TextSize = 14
        restoreBtn.BackgroundColor3 = Color3.fromRGB(18,18,18)
        restoreBtn.TextColor3 = Color3.new(1,1,1)
        restoreBtn.Visible = false
        Instance.new("UICorner", restoreBtn).CornerRadius = UDim.new(0,6)

        -- toggle egg animation remover
        eggToggle.MouseButton1Click:Connect(function()
            eggAnimDisabled = not eggAnimDisabled
            eggToggle.Text = eggAnimDisabled and "Egg Anim: ON (Disabled)" or "Egg Anim: OFF"
            if eggAnimDisabled then
                -- best-effort: hook common OpenEgg function via getgc (not guaranteed on all exploits)
                pcall(function()
                    for i,v in pairs(getgc and getgc(true) or {}) do
                        if type(v) == "table" and rawget(v, "OpenEgg") then
                            -- backup if not present
                            if not rawget(v, "_OpenEgg_backup") then v._OpenEgg_backup = v.OpenEgg end
                            v.OpenEgg = function() return end
                        elseif type(v) == "function" then
                            -- some games keep functions directly; try to find by name (best-effort)
                        end
                    end
                end)
            else
                pcall(function()
                    for i,v in pairs(getgc and getgc(true) or {}) do
                        if type(v) == "table" and rawget(v, "_OpenEgg_backup") then
                            v.OpenEgg = v._OpenEgg_backup
                            v._OpenEgg_backup = nil
                        end
                    end
                end)
            end
        end)

        -- ===== button behaviors & mode toggle helper =====
        local function setMode(newMode)
            Mode = newMode or "None"
            -- visual update
            normalBtn.BackgroundColor3 = (Mode == "Normal") and Color3.fromRGB(48,48,48) or Color3.fromRGB(18,18,18)
            safeBtn.BackgroundColor3   = (Mode == "Safe") and Color3.fromRGB(48,48,48) or Color3.fromRGB(18,18,18)
            blatBtn.BackgroundColor3   = (Mode == "Blatant") and Color3.fromRGB(48,48,48) or Color3.fromRGB(18,18,18)
            nearestBtn.BackgroundColor3= (Mode == "Nearest") and Color3.fromRGB(48,48,48) or Color3.fromRGB(18,18,18)
            statusLabel.Text = ("Mode: %s | World: %s | Area: %s | Pets: %d"):format(Mode, SelectedWorld, SelectedArea, #trackedPets)
            petToTarget = {}
            targetToPet = {}
            petCooldowns = {}
        end

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
                if not ok then warn("[Hate AutoFarm] EquipPet failed for", uid, res) end
                task.wait(0.06)
            end
            task.wait(EQUIP_WAIT)
            statusLabel.Text = ("Equipped %d pets"):format(#trackedPets)
        end)

        startBtn.MouseButton1Click:Connect(function()
            if Mode == "None" then setMode("Normal") else setMode("None") end
        end)

        normalBtn.MouseButton1Click:Connect(function() if Mode ~= "Normal" then setMode("Normal") else setMode("None") end end)
        safeBtn.MouseButton1Click:Connect(function() if Mode ~= "Safe" then setMode("Safe") else setMode("None") end end)
        blatBtn.MouseButton1Click:Connect(function() if Mode ~= "Blatant" then setMode("Blatant") else setMode("None") end end)
        nearestBtn.MouseButton1Click:Connect(function() if Mode ~= "Nearest" then setMode("Nearest") else setMode("None") end end)

        minBtn.MouseButton1Click:Connect(function()
            frame.Visible = false
            restoreBtn.Visible = true
        end)

        restoreBtn.MouseButton1Click:Connect(function()
            frame.Visible = true
            restoreBtn.Visible = false
        end)

        -- return GUI handles
        return {
            Gui = screenGui,
            Frame = frame,
            StatusLabel = statusLabel,
            WorldDropdown = worldDropdown,
            AreaDropdown = areaDropdown,
            TargetDropdown = targetDropdown,
            SetMode = setMode
        }
    end

    local ui = CreateGUI()

    -- ======= ANTI-AFK (run once) =======
    pcall(function()
        local vu = game:GetService("VirtualUser")
        Players.LocalPlayer.Idled:Connect(function()
            vu:Button2Down(Vector2.new(0,0), workspace.CurrentCamera)
            task.wait(1)
            vu:Button2Up(Vector2.new(0,0), workspace.CurrentCamera)
        end)
    end)

    -- ======= MAIN BACKGROUND LOOP =======
    task.spawn(function()
        while true do
            -- update live status
            if ui and ui.StatusLabel then
                ui.StatusLabel.Text = ("Mode: %s | World: %s | Area: %s | Pets: %d"):format(Mode, SelectedWorld, SelectedArea, #trackedPets)
            end

            local coins = nil
            if Mode ~= "None" then coins = GetCoinsRaw() or {} end

            if Mode == "Nearest" then
                if #trackedPets == 0 then
                    trackedPets = pickTopNFromSave()
                    for _, uid in ipairs(trackedPets) do pcall(function() EquipPet(uid) end); task.wait(0.06) end
                    task.wait(EQUIP_WAIT)
                end
                if coins then
                    FreeStaleAssignments(coins)
                    TargetNearestAll(coins)
                    pcall(function() ClaimOrbs({}) end)
                end
                task.wait(0.45 + math.random(0,200)/1000)
            elseif Mode == "Normal" then
                if #trackedPets == 0 then
                    trackedPets = pickTopNFromSave()
                    for _, uid in ipairs(trackedPets) do pcall(function() EquipPet(uid) end); task.wait(0.06) end
                    task.wait(EQUIP_WAIT)
                end
                if coins then
                    FreeStaleAssignments(coins)
                    FillAssignmentsNormal(coins)
                    pcall(function() ClaimOrbs({}) end)
                end
                task.wait(MAIN_LOOP_DELAY)
            elseif Mode == "Safe" then
                if #trackedPets == 0 then
                    trackedPets = pickTopNFromSave()
                    for _, uid in ipairs(trackedPets) do pcall(function() EquipPet(uid) end); task.wait(0.09 + math.random(0,100)/1000) end
                    task.wait(EQUIP_WAIT)
                end
                if coins then
                    FreeStaleAssignments(coins)
                    FillAssignmentsSafe(coins)
                    pcall(function() ClaimOrbs({}) end)
                end
                task.wait(MAIN_LOOP_DELAY + SAFE_EXTRA_DELAY + math.random(0,300)/1000)
            elseif Mode == "Blatant" then
                if #trackedPets == 0 then
                    trackedPets = pickTopNFromSave()
                    for _, uid in ipairs(trackedPets) do pcall(function() EquipPet(uid) end); task.wait(0.04) end
                    task.wait(EQUIP_WAIT)
                end
                if coins then
                    FreeStaleAssignments(coins)
                    FillAssignmentsBlatant(coins)
                    pcall(function() ClaimOrbs({}) end)
                end
                task.wait(0.25 + math.random(0,200)/1000)
            else
                task.wait(0.8)
            end
        end
    end)

    print("[Hate AutoFarm] Full script loaded. GUI at top-left. Pick Best Pets -> Start to run.")

end) -- end pcall

if not ok then
    warn("[Hate AutoFarm] Startup error:", mainErr)
else
    print("[Hate AutoFarm] Script executed successfully!")
end
