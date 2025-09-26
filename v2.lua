-- Hate's AutoFarm — FINAL with TargetType dropdown (paste into NEW LocalScript)
local ok, mainErr = pcall(function()
    -- ===== CONFIG =====
    local JOIN_DELAY = 0.06
    local CHANGE_DELAY = 0.04
    local MAIN_LOOP_DELAY = 0.8
    local SAFE_LOOP_DELAY = 2.0
    local EQUIP_WAIT = 0.45
    local RETARGET_DELAY = 0.3

    local MAX_ASSIGN_PER_CYCLE = 4
    local MAX_ASSIGN_PER_CYCLE_SAFE = 2

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

    local TargetTypeOptions = {"Any", "Coins", "Diamonds", "Chests", "Breakables"}

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

    -- ===== SAFE REMOTE CALLER (no top-level varargs) =====
    local function CallRemote(name, argsTable)
        argsTable = argsTable or {}
        if not Network then
            return false, "Network missing"
        end
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

    -- ===== WRAPPERS =====
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
    local TargetNearestType = "Any"

    local Enabled = false        -- Normal farm toggle
    local SafeEnabled = false    -- Safe farm toggle
    local BlatantEnabled = false -- Blatant farm toggle (assign once per spawn)
    local NearestEnabled = false -- Target Nearest toggle (all pets -> nearest, ignores world/area)

    local trackedPets = {}       -- equipped pet UIDs
    local petToTarget = {}       -- uid -> targetId
    local targetToPet = {}       -- targetId -> uid
    local petCooldowns = {}      -- uid -> timestamp allowed to reassign
    local blatantlyAssignedTargets = {} -- keep track for Blatant mode to avoid reassigning same breakable

    -- get equipped pet UIDs primarily from save, fallback to pickTopNFromSave
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

    -- ===== ASSIGNMENT HELPERS =====
    local function ClearAssignmentForPet(uid)
        if not uid then return end
        local t = petToTarget[uid]
        if t then
            petToTarget[uid] = nil
            targetToPet[t] = nil
        end
        petCooldowns[uid] = tick() + RETARGET_DELAY
    end

    local function FreeStaleAssignments(coins)
        local present = {}
        if coins then for id,_ in pairs(coins) do present[id] = true end end
        for uid, tid in pairs(petToTarget) do
            if not present[tid] then
                ClearAssignmentForPet(uid)
            end
        end
        for tId,_ in pairs(blatantlyAssignedTargets) do
            if not present[tId] then blatantlyAssignedTargets[tId] = nil end
        end
    end

    local function GetAvailableBreakablesInArea(coins)
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

    local function GetAllAvailableBreakables(coins)
        local available = {}
        if not coins then return available end
        for id, item in pairs(coins) do
            if type(item) == "table" then
                if not targetToPet[id] then
                    table.insert(available, { id = id, data = item })
                end
            end
        end
        return available
    end

    -- assign one pet to a breakable (safeMode param changes randomization)
    local function AssignPetToBreakable(petUID, breakId, safeMode)
        if not petUID or not breakId then return false end
        if safeMode then
            local j = JOIN_DELAY + (math.random(60,180)/1000)
            local c = CHANGE_DELAY + (math.random(60,180)/1000)
            safe_delay(0, function() JoinCoin(breakId, {petUID}) end)
            safe_delay(j, function() ChangePetTarget(petUID, "Coin", breakId) end)
            safe_delay(j + c, function() FarmCoin(breakId, petUID) end)
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

    -- Fill assignments for Normal/Safe (one pet per breakable, area-respecting)
    local function FillAssignments_NormalOrSafe(coins, safeMode)
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

        local available = GetAvailableBreakablesInArea(coins)
        if #available == 0 then return end

        local maxPerCycle = safeMode and MAX_ASSIGN_PER_CYCLE_SAFE or MAX_ASSIGN_PER_CYCLE
        local count = math.min(maxPerCycle, #freePets, #available)
        for i = 1, count do
            local pet = freePets[i]
            local target = available[i]
            if pet and target and target.id then
                pcall(function() AssignPetToBreakable(pet, target.id, safeMode) end)
                task.wait(safeMode and (0.12 + math.random(0,150)/1000) or (0.02 + math.random(0,40)/1000))
            end
        end
    end

    -- Blatant mode: assign once per spawn, area-respecting, minimal delay
    local function FillAssignments_Blatant(coins)
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

        local available = GetAvailableBreakablesInArea(coins)
        if #available == 0 then return end

        local iPet, iAvail = 1,1
        while iPet <= #freePets and iAvail <= #available do
            local pet = freePets[iPet]
            local target = available[iAvail]
            if pet and target and target.id then
                if not blatantlyAssignedTargets[target.id] then
                    pcall(function()
                        AssignPetToBreakable(pet, target.id, false)
                        blatantlyAssignedTargets[target.id] = true
                    end)
                    task.wait(0.01)
                    iPet = iPet + 1
                    iAvail = iAvail + 1
                else
                    iAvail = iAvail + 1
                end
            else
                break
            end
        end
    end

    -- helper: name/type matching for target type (case-insensitive)
    local function matchesTargetType(targetType, coinData)
        if not targetType or targetType == "Any" then return true end
        if not coinData then return false end
        local name = tostring(coinData.n or coinData.name or ""):lower()
        if targetType == "Coins" then
            return name:find("coin") or name:find("coins")
        elseif targetType == "Diamonds" then
            return name:find("diamond") or name:find("gem") or name:find("ruby")
        elseif targetType == "Chests" then
            return name:find("chest") or name:find("crate") or name:find("vault")
        elseif targetType == "Breakables" then
            -- broad: anything that isn't clearly an orb/collectible
            return not (name:find("orb") or name:find("orb") or name == "")
        end
        return true
    end

    -- Target Nearest: send ALL equipped pets to the single nearest breakable matching TargetNearestType (ignores world/area)
    local function TargetNearest_All(coins)
        if not coins then return end
        if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then return end
        local hrp = LocalPlayer.Character.HumanoidRootPart
        local bestId, bestDist = nil, math.huge
        for id, data in pairs(coins) do
            if type(data) == "table" then
                if matchesTargetType(TargetNearestType, data) then
                    local p = data.p
                    if p and typeof(p) == "Vector3" then
                        local d = (hrp.Position - p).Magnitude
                        if d < bestDist then bestDist = d; bestId = id end
                    end
                end
            end
        end
        if not bestId then return end

        local petUIDs = GetEquippedPetUIDs()
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
        btn.BackgroundColor3 = Color3.fromRGB(18,18,18)
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
            for _, c in ipairs(menu:GetChildren()) do if not c:IsA("UIListLayout") then c:Destroy() end end
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
        btn.MouseButton1Click:Connect(function() menu.Visible = not menu.Visible end)
        return { Button = btn, Menu = menu, Label = label, SetOptions = function(newOptions) populate(newOptions) end }
    end

    -- ===== GUI (top-left, black, not draggable) =====
    local function CreateGUI()
        local screenGui = Instance.new("ScreenGui")
        screenGui.Name = "Hate_AutoFarm_GUI"
        screenGui.ResetOnSpawn = false
        screenGui.Parent = PlayerGui

        local frame = Instance.new("Frame", screenGui)
        frame.Size = UDim2.new(0, 320, 0, 240)
        frame.Position = UDim2.new(0, 5, 0, 36) -- top-left under Roblox menu
        frame.BackgroundColor3 = Color3.fromRGB(0,0,0)
        Instance.new("UICorner", frame).CornerRadius = UDim.new(0,6)

        -- Minimize button 20x20 top-left inside frame
        local minBtn = Instance.new("TextButton", frame)
        minBtn.Size = UDim2.new(0, 20, 0, 20)
        minBtn.Position = UDim2.new(0, 6, 0, 6)
        minBtn.Text = "-"
        minBtn.Font = Enum.Font.SourceSansBold
        minBtn.TextSize = 14
        minBtn.TextColor3 = Color3.new(1,1,1)
        minBtn.BackgroundColor3 = Color3.fromRGB(18,18,18)
        Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0,4)

        local restoreBtn
        local function showRestore()
            if not restoreBtn or not restoreBtn.Parent then
                restoreBtn = Instance.new("TextButton", screenGui)
                restoreBtn.Name = "HateRestore"
                restoreBtn.Size = UDim2.new(0, 20, 0, 20)
                restoreBtn.Position = UDim2.new(0, 5, 0, 36)
                restoreBtn.Text = "H"
                restoreBtn.Font = Enum.Font.SourceSansBold
                restoreBtn.TextSize = 14
                restoreBtn.TextColor3 = Color3.new(1,1,1)
                restoreBtn.BackgroundColor3 = Color3.fromRGB(18,18,18)
                Instance.new("UICorner", restoreBtn).CornerRadius = UDim.new(0,4)
                restoreBtn.MouseButton1Click:Connect(function()
                    frame.Visible = true
                    if restoreBtn and restoreBtn.Parent then restoreBtn:Destroy() end
                end)
            end
        end

        minBtn.MouseButton1Click:Connect(function()
            frame.Visible = false
            showRestore()
        end)

        -- Title
        local title = Instance.new("TextLabel", frame)
        title.Size = UDim2.new(1, -40, 0, 24)
        title.Position = UDim2.new(0, 30, 0, 6)
        title.BackgroundTransparency = 1
        title.Font = Enum.Font.SourceSansBold
        title.TextSize = 16
        title.TextColor3 = Color3.new(1,1,1)
        title.Text = "Hate's Autofarm"

        -- Left buttons column
        local leftX = 10
        local rightX = 168
        local topY = 40
        local spacingY = 6

        local pickBtn = Instance.new("TextButton", frame)
        pickBtn.Size = UDim2.new(0, 140, 0, 36)
        pickBtn.Position = UDim2.new(0, leftX, 0, topY)
        pickBtn.Text = "Pick Best Pets"
        pickBtn.Font = Enum.Font.SourceSansBold
        pickBtn.BackgroundColor3 = Color3.fromRGB(18,18,18)
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

        local safeBtn = Instance.new("TextButton", frame)
        safeBtn.Size = UDim2.new(0, 140, 0, 26)
        safeBtn.Position = UDim2.new(0, leftX, 0, topY + (36 + spacingY)*2 + 4)
        safeBtn.Text = "Safe Farm: Off"
        safeBtn.Font = Enum.Font.SourceSansBold
        safeBtn.BackgroundColor3 = Color3.fromRGB(18,18,18)
        safeBtn.TextColor3 = Color3.new(1,1,1)
        Instance.new("UICorner", safeBtn).CornerRadius = UDim.new(0,6)

        local blatantBtn = Instance.new("TextButton", frame)
        blatantBtn.Size = UDim2.new(0, 140, 0, 26)
        blatantBtn.Position = UDim2.new(0, leftX, 0, topY + (36 + spacingY)*2 + 4 + 30)
        blatantBtn.Text = "Blatant: Off"
        blatantBtn.Font = Enum.Font.SourceSansBold
        blatantBtn.BackgroundColor3 = Color3.fromRGB(18,18,18)
        blatantBtn.TextColor3 = Color3.new(1,1,1)
        Instance.new("UICorner", blatantBtn).CornerRadius = UDim.new(0,6)

        local nearestBtn = Instance.new("TextButton", frame)
        nearestBtn.Size = UDim2.new(0, 140, 0, 26)
        nearestBtn.Position = UDim2.new(0, leftX, 0, topY + (36 + spacingY)*2 + 4 + 60)
        nearestBtn.Text = "Target Nearest: Off"
        nearestBtn.Font = Enum.Font.SourceSansBold
        nearestBtn.BackgroundColor3 = Color3.fromRGB(18,18,18)
        nearestBtn.TextColor3 = Color3.new(1,1,1)
        Instance.new("UICorner", nearestBtn).CornerRadius = UDim.new(0,6)

        local refreshBtn = Instance.new("TextButton", frame)
        refreshBtn.Size = UDim2.new(0, 140, 0, 26)
        refreshBtn.Position = UDim2.new(0, leftX, 0, topY + (36 + spacingY)*4 + 70)
        refreshBtn.Text = "Manual Refresh"
        refreshBtn.Font = Enum.Font.SourceSansBold
        refreshBtn.BackgroundColor3 = Color3.fromRGB(18,18,18)
        refreshBtn.TextColor3 = Color3.new(1,1,1)
        Instance.new("UICorner", refreshBtn).CornerRadius = UDim.new(0,6)

        -- Right column: Area textbox (top), Set Area button, World dropdown, Target Type dropdown
        local areaLabel = Instance.new("TextLabel", frame)
        areaLabel.Size = UDim2.new(0, 140, 0, 18)
        areaLabel.Position = UDim2.new(0, rightX, 0, topY - 6)
        areaLabel.BackgroundTransparency = 1
        areaLabel.Text = "Area (type):"
        areaLabel.TextColor3 = Color3.new(1,1,1)
        areaLabel.Font = Enum.Font.SourceSans
        areaLabel.TextSize = 14

        local areaBox = Instance.new("TextBox", frame)
        areaBox.Size = UDim2.new(0, 140, 0, 26)
        areaBox.Position = UDim2.new(0, rightX, 0, topY + 12)
        areaBox.PlaceholderText = "Type area name (e.g. Beach)"
        areaBox.Text = tostring(SelectedArea)
        areaBox.Font = Enum.Font.SourceSans
        areaBox.TextSize = 14
        areaBox.TextColor3 = Color3.new(1,1,1)
        areaBox.BackgroundColor3 = Color3.fromRGB(12,12,12)
        Instance.new("UICorner", areaBox).CornerRadius = UDim.new(0,6)

        local setAreaBtn = Instance.new("TextButton", frame)
        setAreaBtn.Size = UDim2.new(0, 140, 0, 26)
        setAreaBtn.Position = UDim2.new(0, rightX, 0, topY + 12 + 32)
        setAreaBtn.Text = "Set Area"
        setAreaBtn.Font = Enum.Font.SourceSansBold
        setAreaBtn.BackgroundColor3 = Color3.fromRGB(18,18,18)
        setAreaBtn.TextColor3 = Color3.new(1,1,1)
        Instance.new("UICorner", setAreaBtn).CornerRadius = UDim.new(0,6)

        local worldDropdown = makeDropdown(frame, rightX, topY + 12 + 32 + 34, 140, "World", (function()
            local t = {}
            for k,_ in pairs(WorldsTable) do table.insert(t, k) end
            table.sort(t)
            return t
        end)(), function(selected)
            SelectedWorld = selected
            local areas = WorldsTable[SelectedWorld] or {}
            areaDropdown.SetOptions(areas)
            if #areas > 0 then
                SelectedArea = areas[1]
                areaBox.Text = SelectedArea
                areaDropdown.Button.Text = areas[1]
            else
                SelectedArea = ""
                areaBox.Text = ""
                areaDropdown.Button.Text = "None"
            end
            -- clear assignments
            petToTarget = {}
            targetToPet = {}
            petCooldowns = {}
            blatantlyAssignedTargets = {}
        end)

        -- area dropdown under world for convenience (but areaBox is the primary control)
        local areaDropdown = makeDropdown(frame, rightX, topY + 12 + 32 + 34 + 64, 140, "Areas", WorldsTable[SelectedWorld] or {}, function(selected)
            SelectedArea = selected
            areaBox.Text = selected
            -- clear assignments
            petToTarget = {}
            targetToPet = {}
            petCooldowns = {}
            blatantlyAssignedTargets = {}
        end)

        local targetTypeDropdown = makeDropdown(frame, rightX, topY + 12 + 32 + 34 + 64 + 46 + 6, 140, "Target Type", TargetTypeOptions, function(selected)
            TargetNearestType = selected
        end)

        local status = Instance.new("TextLabel", frame)
        status.Size = UDim2.new(1, -12, 0, 20)
        status.Position = UDim2.new(0, 6, 0, 210)
        status.BackgroundTransparency = 1
        status.Font = Enum.Font.SourceSans
        status.TextSize = 14
        status.TextColor3 = Color3.new(1,1,1)
        status.Text = "Status: Idle"

        -- ===== BUTTON BEHAVIOURS =====
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

        safeBtn.MouseButton1Click:Connect(function()
            SafeEnabled = not SafeEnabled
            safeBtn.Text = SafeEnabled and "Safe Farm: On" or "Safe Farm: Off"
            status.Text = SafeEnabled and ("Status: Safe Farm (%s - %s)"):format(tostring(SelectedWorld), tostring(SelectedArea)) or status.Text
            petToTarget = {}
            targetToPet = {}
            petCooldowns = {}
            blatantlyAssignedTargets = {}
        end)

        blatantBtn.MouseButton1Click:Connect(function()
            BlatantEnabled = not BlatantEnabled
            blatantBtn.Text = BlatantEnabled and "Blatant: On" or "Blatant: Off"
            status.Text = BlatantEnabled and ("Status: Blatant (%s - %s)"):format(tostring(SelectedWorld), tostring(SelectedArea)) or status.Text
            blatantlyAssignedTargets = {}
            petToTarget = {}
            targetToPet = {}
            petCooldowns = {}
        end)

        nearestBtn.MouseButton1Click:Connect(function()
            NearestEnabled = not NearestEnabled
            nearestBtn.Text = NearestEnabled and "Target Nearest: On" or "Target Nearest: Off"
            status.Text = NearestEnabled and ("Status: Target Nearest (%s)"):format(tostring(TargetNearestType)) or status.Text
            if not NearestEnabled then
                petToTarget = {}
                targetToPet = {}
                petCooldowns = {}
            end
        end)

        setAreaBtn.MouseButton1Click:Connect(function()
            local typed = tostring(areaBox.Text or "")
            typed = typed:match("^%s*(.-)%s*$") or typed -- trim
            if typed == "" then
                status.Text = "Status: Enter area name first"
                return
            end
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
                SelectedArea = typed -- allow custom area
            end
            petToTarget = {}
            targetToPet = {}
            petCooldowns = {}
            blatantlyAssignedTargets = {}
            status.Text = ("Status: Area set to %s"):format(tostring(SelectedArea))
        end)

        refreshBtn.MouseButton1Click:Connect(function()
            status.Text = "Status: Manual refresh requested..."
            local ok, err = pcall(function()
                local coins = GetCoinsRaw()
                if coins then
                    FreeStaleAssignments(coins)
                    FillAssignments_NormalOrSafe(coins, false)
                    status.Text = ("Status: Refreshed (%d coins)"):format((function() local c = 0 for k,_ in pairs(coins or {}) do c = c + 1 end return c end)())
                else
                    status.Text = "Status: No coins available to refresh"
                end
            end)
            if not ok then status.Text = "Status: Refresh error" end
        end)

        return {
            Gui = screenGui,
            Frame = frame,
            Status = status,
            AreaBox = areaBox,
            WorldDropdown = worldDropdown,
            TargetTypeDropdown = targetTypeDropdown
        }
    end

    local ui = CreateGUI()

    -- ===== ANTI-AFK (run once) =====
    do
        local vu = nil
        pcall(function() vu = game:GetService("VirtualUser") end)
        if vu then
            Players.LocalPlayer.Idled:Connect(function()
                vu:Button2Down(Vector2.new(0,0))
                task.wait(0.1)
                vu:Button2Up(Vector2.new(0,0))
                print("[Hate AutoFarm] Anti-AFK pressed")
            end)
        else
            Players.LocalPlayer.Idled:Connect(function()
                pcall(function()
                    local uis = game:GetService("UserInputService")
                    uis.MouseIconEnabled = not uis.MouseIconEnabled
                    task.wait(0.05)
                    uis.MouseIconEnabled = not uis.MouseIconEnabled
                end)
                print("[Hate AutoFarm] Anti-AFK fallback triggered")
            end)
        end
    end

    -- ===== MAIN LOOPS =====
    task.spawn(function()
        while true do
            -- Normal farm
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
                if coins then
                    ui.Status.Text = ("Status: Farming (%s - %s)"):format(tostring(SelectedWorld), tostring(SelectedArea))
                    FreeStaleAssignments(coins)
                    FillAssignments_NormalOrSafe(coins, false)
                    pcall(function() ClaimOrbs({}) end)
                else
                    ui.Status.Text = "Status: Waiting for coins..."
                    task.wait(1)
                end
            end

            -- Safe farm
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
                    FillAssignments_NormalOrSafe(coins, true)
                    pcall(function() ClaimOrbs({}) end)
                else
                    ui.Status.Text = "Status: Safe: Waiting for coins..."
                end
                task.wait(SAFE_LOOP_DELAY + math.random(0,200)/1000)
            end

            -- Blatant mode
            if BlatantEnabled then
                if #trackedPets == 0 then
                    trackedPets = pickTopNFromSave()
                    for _, uid in ipairs(trackedPets) do
                        pcall(function() EquipPet(uid) end)
                        task.wait(0.04)
                    end
                    task.wait(EQUIP_WAIT)
                end
                local coins = GetCoinsRaw()
                if coins then
                    ui.Status.Text = ("Status: Blatant (%s - %s)"):format(tostring(SelectedWorld), tostring(SelectedArea))
                    FreeStaleAssignments(coins)
                    FillAssignments_Blatant(coins)
                    pcall(function() ClaimOrbs({}) end)
                else
                    ui.Status.Text = "Status: Blatant: Waiting for coins..."
                end
                task.wait(0.35 + math.random(0,150)/1000)
            end

            -- Target Nearest (ignores world/area)
            if NearestEnabled then
                if #trackedPets == 0 then
                    trackedPets = pickTopNFromSave()
                    for _, uid in ipairs(trackedPets) do
                        pcall(function() EquipPet(uid) end)
                        task.wait(0.06)
                    end
                    task.wait(EQUIP_WAIT)
                end
                local coins = GetCoinsRaw()
                if coins then
                    ui.Status.Text = ("Status: Target Nearest (%s)"):format(tostring(TargetNearestType))
                    FreeStaleAssignments(coins)
                    TargetNearest_All(coins)
                    pcall(function() ClaimOrbs({}) end)
                else
                    ui.Status.Text = "Status: Nearest: Waiting for coins..."
                end
                task.wait(0.45 + math.random(0,200)/1000)
            end

            task.wait(MAIN_LOOP_DELAY + math.random(0,200)/1000)
        end
    end)

    print("[Hate AutoFarm] Loaded. Use Pick Best -> Start / Safe / Blatant / Target Nearest.")
end)

if not ok then
    warn("[Hate AutoFarm] Startup error:", mainErr)
else
    print("[Hate AutoFarm] Script executed successfully!")
end
