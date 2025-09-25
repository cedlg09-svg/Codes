-- PSX AutoFarm — Safe + Area-only + One pet per breakable + Wally v3 UI + Minimize (Hate)
-- Paste into a NEW LocalScript and run

local ok, mainErr = pcall(function()

    -- CONFIG
    local SAFE_DELAY_BETWEEN_ASSIGN = 0.18
    local JOIN_DELAY = 0.06
    local CHANGE_DELAY = 0.04
    local MAIN_LOOP_DELAY = 0.8
    local EQUIP_WAIT = 0.45
    local RETARGET_DELAY = 0.3

    -- Worlds/areas table (your list)
    local WorldsTable = {
        ["Spawn"] = {"Shop","Town","Forest","Beach","Mine","Winter","Glacier","Desert","Volcano","Cave","Tech Entry","VIP"},
        ["Fantasy"] = {"Fantasy Shop","Enchanted Forest","Portals","Ancient Island","Samurai Island","Candy Island","Haunted Island","Hell Island","Heaven Island","Heaven's Gate"},
        ["Tech"] = {"Tech Shop","Tech City","Dark Tech","Steampunk","Steampunk Chest Area","Alien Lab","Alien Forest","Giant Alien Chest","Glitch","Hacker Portal"},
        ["Void"] = {"The Void"},
        ["Axolotl Ocean"] = {"Axolotl Ocean","Axolotl Deep Ocean","Axolotl Cave"},
        ["Pixel"] = {"Pixel Forest","Pixel Kyoto","Pixel Alps","Pixel Vault"},
        ["Cat"] = {"Cat Paradise","Cat Backyard","Cat Taiga","Cat Throne Room"}
    }

    -- SERVICES
    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local Workspace = game:GetService("Workspace")
    local LocalPlayer = Players.LocalPlayer
    assert(LocalPlayer, "LocalPlayer nil - run as LocalScript")
    local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

    print("[AutoFarm] start - environment OK")

    local Network = ReplicatedStorage:FindFirstChild("Network")
    if not Network then warn("[AutoFarm] ReplicatedStorage.Network not found. Remotes may be missing.") end

    -- SAFE Remote caller (no vararg at top-level)
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

    -- Remote wrappers
    local function GetSave() local ok,res = CallRemote("Get Custom Save", {}) if ok then return res end return nil end
    local function GetCoinsRaw() local ok,res = CallRemote("Get Coins", {}) if ok then return res end local ok2,res2 = CallRemote("Coins: Get Test", {}) if ok2 then return res2 end return nil end
    local function EquipPet(uid) return CallRemote("Equip Pet", {uid}) end
    local function JoinCoin(id, pets) return CallRemote("Join Coin", {id, pets}) end
    local function ChangePetTarget(uid, ttype, id) return CallRemote("Change Pet Target", {uid, ttype, id}) end
    local function FarmCoin(id, uid) return CallRemote("Farm Coin", {id, uid}) end
    local function ClaimOrbs(arg) return CallRemote("Claim Orbs", {arg or {}}) end
    local function EquipBestPetsRemote()
        local r = Network and Network:FindFirstChild("Equip Best Pets")
        if not r then return false end
        local ok, _ = pcall(function() r:InvokeServer() end)
        return ok
    end

    -- UTILITIES
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

    -- STATE
    local SelectedWorld = "Spawn"
    local SelectedArea = "Town"
    local Enabled = false
    local trackedPets = {}       -- list of pet UIDs (equipped)
    local petToTarget = {}      -- petUID -> targetId
    local targetToPet = {}      -- targetId -> petUID
    local petCooldowns = {}     -- petUID -> tick when allowed to reassign

    -- Helper: get equipped UIDs (prefers save)
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
        -- fallback: try pickTopNFromSave (will return all if no equipped flagged)
        local top = pickTopNFromSave()
        if #top > 0 then return top end
        return {}
    end

    -- Core assignment helpers (one pet per breakable)
    local function AssignPetToBreakable(petUID, breakId)
        if not petUID or not breakId then return false end
        -- Call JoinCoin, ChangePetTarget, FarmCoin safely via CallRemote helper
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
        if coins then for id, _ in pairs(coins) do present[id] = true end end
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
        -- get currently equipped pet UIDs
        local petUIDs = GetEquippedPetUIDs()
        if #petUIDs == 0 then return end

        -- build list of free pets (not assigned & off cooldown)
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

    -- === UI using Wally v3 library ===
    -- We'll create functions to (re)build the UI and to destroy it (minimize).
    local libraryLoadString = "https://raw.githubusercontent.com/bloodball/-back-ups-for-libs/main/wall%20v3"
    local wallyLibrary = nil
    local currentWindowFolder = nil
    local currentGuiState = { created = false }

    local function CreateWallyUI()
        -- load library
        local success, libOrErr = pcall(function()
            return loadstring(game:HttpGet(libraryLoadString))()
        end)
        if not success or not libOrErr then
            warn("[AutoFarm] Failed to load Wally UI library:", libOrErr)
            return false
        end
        wallyLibrary = libOrErr

        -- create window + folder
        local w = wallyLibrary:CreateWindow("PSX AutoFarm")
        local tab = w:CreateFolder("Main")

        -- world dropdown list (sorted)
        local worlds = {}
        for k,_ in pairs(WorldsTable) do table.insert(worlds, k) end
        table.sort(worlds)

        local areas_for_selected = WorldsTable[SelectedWorld] or {}

        -- NOTE: Wally's dropdown lacks a documented runtime 'SetOptions' method in examples,
        -- therefore when world changes we will rebuild the UI by destroying and recreating.
        tab:Dropdown("World", worlds, true, function(choice)
            SelectedWorld = choice
            -- pick first area for that world
            local a = WorldsTable[SelectedWorld] or {}
            SelectedArea = a[1] or ""
            -- rebuild UI so Area dropdown updates (destroy & recreate)
            if currentGuiState.created then
                pcall(function() tab:DestroyGui() end) -- try to clean
                -- tiny delay to allow destruction
                task.wait(0.05)
                currentGuiState.created = false
                -- recreate
                CreateWallyUI()
            end
        end)

        -- area dropdown (populate from SelectedWorld)
        local areaOpts = WorldsTable[SelectedWorld] or {}
        tab:Dropdown("Area", areaOpts, true, function(choice)
            SelectedArea = choice
        end)

        tab:Button("Pick Best Pets", function()
            local chosen = pickTopNFromSave()
            if #chosen == 0 then
                print("[AutoFarm] No pets found to equip.")
                return
            end
            trackedPets = chosen
            for _, uid in ipairs(trackedPets) do
                local ok, res = EquipPet(uid)
                if not ok then warn("[AutoFarm] EquipPet failed for", uid, res) end
                task.wait(0.06)
            end
            task.wait(EQUIP_WAIT)
            print(("[AutoFarm] Equipped %d pets"):format(#trackedPets))
        end)

        tab:Toggle("AutoFarm (Start/Stop)", function(state)
            Enabled = state
            print("[AutoFarm] Enabled set to", tostring(Enabled))
        end)

        tab:Button("Equip Best (Remote)", function()
            local ok = EquipBestPetsRemote()
            if ok then
                print("[AutoFarm] Equip Best remote called.")
                task.wait(0.65)
                trackedPets = GetEquippedPetUIDs()
            else
                warn("[AutoFarm] Equip Best remote missing/failed.")
            end
        end)

        tab:Button("Destroy UI (minimize)", function()
            -- destroy Wally UI and show icon (minimize)
            pcall(function() tab:DestroyGui() end)
            currentGuiState.created = false
            -- icon will be created by CreateMinimizeIcon() below if needed
        end)

        -- small status label
        tab:Label(("World: %s | Area: %s | Farming: %s"):format(tostring(SelectedWorld), tostring(SelectedArea), Enabled and "Yes" or "No"), {
            TextSize = 14;
            TextColor = Color3.fromRGB(255,255,255);
            BgColor = Color3.fromRGB(50,50,50);
        })

        currentGuiState.created = true
        return true
    end

    -- Minimize icon (recreates UI on click)
    local minimizeIcon = nil
    local function CreateMinimizeIcon()
        if minimizeIcon and minimizeIcon.Parent then return end
        local screenGui = Instance.new("ScreenGui")
        screenGui.Name = "PSX_AutoFarm_MinIcon_GUI"
        screenGui.Parent = PlayerGui

        local icon = Instance.new("TextButton", screenGui)
        icon.Name = "PSX_AutoFarm_MinIcon"
        icon.Size = UDim2.new(0,90,0,36)
        icon.Position = UDim2.new(0, 10, 0, 10)
        icon.AnchorPoint = Vector2.new(0,0)
        icon.Text = "Hate"
        icon.Font = Enum.Font.SourceSansBold
        icon.TextSize = 16
        icon.TextColor3 = Color3.new(1,1,1)
        icon.BackgroundColor3 = Color3.fromRGB(40,40,40)
        Instance.new("UICorner", icon).CornerRadius = UDim.new(0,6)
        icon.Active = true
        icon.Draggable = true

        icon.MouseButton1Click:Connect(function()
            -- recreate Wally UI
            -- remove icon
            pcall(function() screenGui:Destroy() end)
            minimizeIcon = nil
            CreateWallyUI()
        end)

        minimizeIcon = screenGui
    end

    -- Initial UI creation
    CreateWallyUI()
    -- ensure minimize icon exists but hidden (we only show icon if UI destroyed via DestroyGui)
    -- We'll leave icon creation for when the user calls "Destroy UI (minimize)" or when UI auto-recreates.

    -- If user destroyed the Wally UI directly (via destroy button), create the icon to allow restore
    -- To keep things simple: we will monitor currentGuiState.created every 0.5s, and if not created and icon missing, create icon.
    task.spawn(function()
        while true do
            if not currentGuiState.created and not minimizeIcon then
                -- create icon so user can restore UI
                CreateMinimizeIcon()
            end
            task.wait(0.6)
        end
    end)

    -- MAIN LOOP: area-only + one pet per breakable
    task.spawn(function()
        while true do
            if Enabled then
                -- ensure trackedPets are equipped
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
                    task.wait(1)
                else
                    -- update GUI status label in Wally if possible by recreating label next cycle (we keep internal state)
                    -- free stale assignments
                    FreeStaleAssignments(coins)

                    -- fill assignments (one pet per breakable) but only within selected area
                    FillAssignments(coins)

                    -- collect orbs & lootbags safely
                    pcall(function() ClaimOrbs({}) end)
                    -- try collect lootbags
                    do
                        local things = Workspace:FindFirstChild("__THINGS") or Workspace:FindFirstChild("__things")
                        if things then
                            local bags = things:FindFirstChild("Lootbags")
                            if bags and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                                for _, bag in ipairs(bags:GetChildren()) do
                                    if bag and bag:IsA("BasePart") then
                                        pcall(function() bag.CFrame = LocalPlayer.Character.HumanoidRootPart.CFrame end)
                                    end
                                end
                            end
                        end
                    end
                end
            end
            task.wait(MAIN_LOOP_DELAY)
        end
    end)

    print("[AutoFarm] Safe + Area-only AutoFarm loaded. Use the Wally UI: Pick Best, set World/Area, toggle AutoFarm. Minimize via 'Destroy UI (minimize)'. Click the 'Hate' icon to restore the UI.")

end) -- pcall

if not ok then
    warn("[AutoFarm] Startup error:", mainErr)
else
    print("[AutoFarm] Script executed successfully!")
end
