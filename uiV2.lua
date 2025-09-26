-- HateAF_all_in_one.lua
-- Combined: Loads HatesQOL (Rayfield-like), builds UI, and runs autofarm logic.
-- Paste into a NEW LocalScript and run in Delta (LocalScript required).

local ok, mainErr = pcall(function()

    -- ===== CONFIG =====
    local LIB_URL = "https://raw.githubusercontent.com/cedlg09-svg/Codes/refs/heads/main/source.lua"
    local AUTO_LOOP_DELAY = 0.8
    local RETARGET_DELAY = 0.3
    local JOIN_DELAY = 0.06
    local CHANGE_DELAY = 0.04
    local SAFE_DELAY_BETWEEN_ASSIGN = 0.18
    local EQUIP_WAIT = 0.45

    -- ===== SERVICES =====
    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local Workspace = game:GetService("Workspace")
    local RunService = game:GetService("RunService")
    local LocalPlayer = Players.LocalPlayer
    assert(LocalPlayer, "LocalPlayer nil - run as LocalScript")
    local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

    -- ===== ANTI-AFK (run once) =====
    do
        local success, err = pcall(function()
            local vu = game:GetService("VirtualUser")
            if vu and LocalPlayer and LocalPlayer.Idled then
                LocalPlayer.Idled:Connect(function()
                    -- simulate a small input so server doesn't mark AFK
                    vu:Button2Down(Vector2.new(0,0))
                    task.wait(0.5)
                    vu:Button2Up(Vector2.new(0,0))
                end)
            end
        end)
        if not success then warn("[HateAF] Anti-AFK init failed:", err) end
    end

    -- ===== EGG HATCH ANIMATION REMOVER (run once) =====
    do
        local okgc, _ = pcall(function()
            if type(getgc) == "function" then
                for i,v in pairs(getgc(true)) do
                    if type(v) == "table" and rawget(v, "OpenEgg") then
                        pcall(function() rawset(v, "OpenEgg", function(...) return end) end)
                    end
                end
            end
        end)
        if not okgc then
            -- some environments block getgc; ignore silently
        end
    end

    -- ===== NETWORK / REMOTE HELPERS =====
    local Network = ReplicatedStorage:FindFirstChild("Network")
    if not Network then
        warn("[HateAF] ReplicatedStorage.Network not found. Remotes may be missing.")
    end

    local function SafeRemote(name) if not Network then return nil end return Network:FindFirstChild(name) end

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

    -- wrappers
    local function GetSave() local ok,res = CallRemote("Get Custom Save", {}) if ok then return res end return nil end
    local function GetCoinsRaw() local ok,res = CallRemote("Get Coins", {}) if ok then return res end local ok2,res2 = CallRemote("Coins: Get Test", {}) if ok2 then return res2 end return nil end
    local function EquipPet(uid) return CallRemote("Equip Pet", {uid}) end
    local function JoinCoin(id, pets) return CallRemote("Join Coin", {id, pets}) end
    local function ChangePetTarget(uid, ttype, id) return CallRemote("Change Pet Target", {uid, ttype, id}) end
    local function FarmCoin(id, uid) return CallRemote("Farm Coin", {id, uid}) end
    local function ClaimOrbs(arg) return CallRemote("Claim Orbs", {arg or {}}) end
    local function EquipBestPetsRemote() local r=SafeRemote("Equip Best Pets") if not r then return false end local ok, _ = pcall(function() r:InvokeServer() end) return ok end

    -- ===== UTILITIES =====
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

    -- ===== WORLDS TABLE (static, from your list) =====
    local WorldsTable = {
        ["Spawn"] = {"Shop","Town","Forest","Beach","Mine","Winter","Glacier","Desert","Volcano","Cave","Tech Entry","VIP"},
        ["Fantasy"] = {"Fantasy Shop","Enchanted Forest","Portals","Ancient Island","Samurai Island","Candy Island","Haunted Island","Hell Island","Heaven Island","Heaven's Gate"},
        ["Tech"] = {"Tech Shop","Tech City","Dark Tech","Steampunk","Steampunk Chest Area","Alien Lab","Alien Forest","Giant Alien Chest","Glitch","Hacker Portal"},
        ["Void"] = {"The Void"},
        ["Axolotl Ocean"] = {"Axolotl Ocean","Axolotl Deep Ocean","Axolotl Cave"},
        ["Pixel"] = {"Pixel Forest","Pixel Kyoto","Pixel Alps","Pixel Vault"},
        ["Cat"] = {"Cat Paradise","Cat Backyard","Cat Taiga","Cat Throne Room"}
    }

    -- ===== STATE =====
    local SelectedWorld = "Spawn"
    local SelectedArea = "Town"
    local Enabled = false
    local trackedPets = {}       -- list of pet UIDs (equipped)
    local petToTarget = {}      -- petUID -> targetId
    local targetToPet = {}      -- targetId -> petUID
    local petCooldowns = {}     -- petUID -> tick when allowed to reassign
    local BrokenCount = 0
    local StartTime = nil

    -- ===== ASSIGNMENT HELPERS =====
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

    -- ===== TARGET NEAREST (All Pets) - ignores area if requested via separate button =====
    local function GetNearestBreakableForPet(coins, petUID, ignoreArea)
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then return nil end
        local bestId, bestDist = nil, math.huge
        for id, item in pairs(coins) do
            if type(item) == "table" then
                local w = tostring(item.w or item.world)
                local a = tostring(item.a or item.area)
                if ignoreArea or (w == tostring(SelectedWorld) and a == tostring(SelectedArea)) then
                    local pos = item.p
                    if pos and typeof(pos) == "Vector3" then
                        local d = (hrp.Position - pos).Magnitude
                        if d < bestDist and not targetToPet[id] then
                            bestDist = d
                            bestId = id
                        end
                    end
                end
            end
        end
        return bestId
    end

    local function AssignAllPetsToNearest(coins, ignoreArea)
        local petUIDs = pickTopNFromSave()
        if #petUIDs == 0 then return end
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        for _, uid in ipairs(petUIDs) do
            if not petToTarget[uid] and (petCooldowns[uid] or 0) <= tick() then
                local nid = GetNearestBreakableForPet(coins, uid, ignoreArea)
                if nid then
                    pcall(function() AssignPetToBreakable(uid, nid) end)
                    task.wait(0.02)
                end
            end
        end
    end

    -- ===== UI LOAD (HatesQOL) =====
    local lib_ok, Hates = pcall(function() return loadstring(game:HttpGet(LIB_URL, true))() end)
    if not lib_ok or not Hates or type(Hates.CreateWindow) ~= "function" then
        error("[HateAF] Failed to load HatesQOL library from: " .. tostring(LIB_URL))
    end

    -- build UI
    local w = Hates.CreateWindow("Hate's QoL")
    local main = w:CreateFolder("Hate's Autofarm")
    local targetFolder = w:CreateFolder("Targeting")
    local extras = w:CreateFolder("Extras")
    local eggWin = Hates.CreateWindow("Egg Management")
    local eggFolder = eggWin:CreateFolder("Egg Settings")

    -- Status label + counters
    local statusLabel = main:Label("Status: Idle", {TextSize=14, TextColor=Color3.fromRGB(220,220,220)})
    local timeLabel = main:Label("Time: 0s", {TextSize=12})
    local brokenLabel = main:Label("Broken: 0", {TextSize=12})

    -- Buttons (top)
    local pickBtn = main:Button("Pick Best Pets", function()
        statusLabel:Update("Equipping best pets...")
        local chosen = pickTopNFromSave()
        if #chosen == 0 then
            statusLabel:Update("No pets found.")
            return
        end
        trackedPets = chosen
        for _, uid in ipairs(trackedPets) do
            local ok, res = EquipPet(uid)
            if not ok then warn("[HateAF] EquipPet failed for", uid, res) end
            task.wait(0.06)
        end
        task.wait(EQUIP_WAIT)
        statusLabel:Update(("Equipped %d pets"):format(#trackedPets))
    end)

    local startToggle = main:Button("Start/Stop", function()
        Enabled = not Enabled
        if Enabled then
            startToggle:SetText("Stop")
            startToggle:SetText("Stop")
            statusLabel:Update(("Farming: %s - %s"):format(tostring(SelectedWorld), tostring(SelectedArea)))
            StartTime = tick()
            BrokenCount = 0
        else
            startToggle:SetText("Start")
            statusLabel:Update("Stopped")
        end
    end)

    -- Add 'Blatant' and 'Safe' modes (separate buttons)
    local blatantBtn = main:Button("Blatant Mode", function()
        -- assign a flag in extras
        extras._blatant = not extras._blatant
        blatantBtn:SetText(extras._blatant and "Blatant: ON" or "Blatant Mode")
        statusLabel:Update("Blatant mode: " .. tostring(extras._blatant and "ON" or "OFF"))
    end)

    local safeBtn = main:Button("Safe Mode", function()
        extras._safe = not extras._safe
        safeBtn:SetText(extras._safe and "Safe: ON" or "Safe Mode")
        statusLabel:Update("Safe mode: " .. tostring(extras._safe and "ON" or "OFF"))
    end)

    -- Slow/Moderate fast settings for safe mode
    extras._safe = false
    extras._blatant = false

    -- Worlds & Areas dropdowns (below buttons)
    local worldList = {}
    for k,_ in pairs(WorldsTable) do table.insert(worldList, k) end
    table.sort(worldList)
    SelectedWorld = worldList[1] or SelectedWorld
    SelectedArea = (WorldsTable[SelectedWorld] and WorldsTable[SelectedWorld][1]) or SelectedArea

    local worldDD = main:Dropdown("World", worldList, false, function(v)
        SelectedWorld = tostring(v)
        local areas = WorldsTable[SelectedWorld] or {}
        -- refresh area dropdown and auto-select first
        areaDD.Refresh(areas, true)
        SelectedArea = areas[1] or ""
        -- clear assignments so pets retarget into new area immediately
        petToTarget = {}
        targetToPet = {}
        petCooldowns = {}
        statusLabel:Update(("Selected World: %s | Area: %s"):format(SelectedWorld, SelectedArea))
    end)

    local areaDD = main:Dropdown("Area", WorldsTable[SelectedWorld] or {}, false, function(v)
        SelectedArea = tostring(v or "")
        petToTarget = {}
        targetToPet = {}
        petCooldowns = {}
        statusLabel:Update(("Selected Area set: %s"):format(SelectedArea))
    end)
    -- initial populate (auto-select first)
    areaDD.Refresh(WorldsTable[SelectedWorld], true)

    -- Targeting: dropdown for target type (Nearest/Strongest/Random)
    local targetModeDD = targetFolder:Dropdown("Target Mode", {"Nearest","Strongest","Random"}, false, function(choice)
        extras._targetMode = choice
        statusLabel:Update("Target mode: "..tostring(choice))
    end)
    extras._targetMode = "Nearest"

    -- Target nearest (all pets) button (ignores area if chosen)
    local targetNearestBtn = targetFolder:Button("Target Nearest (All Pets)", function()
        -- one-shot: assign all equipped pets to nearest breakable (in selected area)
        statusLabel:Update("Assigning all pets to nearest...")
        local coins = GetCoinsRaw()
        if not coins then statusLabel:Update("No coins data") return end
        AssignAllPetsToNearest(coins, false)
        statusLabel:Update("Assigned nearest (area-respecting)")
    end)

    local targetNearestIgnoreBtn = targetFolder:Button("Target Nearest (Ignore Area)", function()
        statusLabel:Update("Assigning all pets to nearest (ignore area)...")
        local coins = GetCoinsRaw()
        if not coins then statusLabel:Update("No coins data") return end
        AssignAllPetsToNearest(coins, true)
        statusLabel:Update("Assigned nearest (ignored area)")
    end)

    -- Manual Refresh area button
    main:Button("Refresh Areas", function()
        local areas = WorldsTable[SelectedWorld] or {}
        areaDD.Refresh(areas, true)
        statusLabel:Update("Areas refreshed")
    end)

    -- Egg Management buttons (run-once removal already ran at startup; provide button to run again)
    eggFolder:Button("Remove Hatching Animation (Run Once)", function()
        local okgc, _ = pcall(function()
            if type(getgc) == "function" then
                for i,v in pairs(getgc(true)) do
                    if type(v) == "table" and rawget(v, "OpenEgg") then
                        pcall(function() rawset(v, "OpenEgg", function(...) return end) end)
                    end
                end
            end
        end)
        statusLabel:Update("Egg animation removal attempted")
    end)

    -- Placeholders for future windows
    extras:Button("Auto Fuse (Placeholder)", function() statusLabel:Update("Auto Fuse placeholder") end)
    extras:Button("Auto Rainbow (Placeholder)", function() statusLabel:Update("Auto Rainbow placeholder") end)
    extras:Button("Auto Gold (Placeholder)", function() statusLabel:Update("Auto Gold placeholder") end)
    extras:Button("Auto DarkMatter (Placeholder)", function() statusLabel:Update("Auto DarkMatter placeholder") end)

    -- Small status updater loop (time & broken count)
    task.spawn(function()
        while true do
            if StartTime then
                local dur = math.floor(tick() - StartTime)
                timeLabel:Update("Time: " .. tostring(dur) .. "s")
                brokenLabel:Update("Broken: " .. tostring(BrokenCount))
            end
            task.wait(1)
        end
    end)

    -- ===== CORE LOOP =====
    task.spawn(function()
        while true do
            if Enabled then
                -- ensure pets equipped
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
                    statusLabel:Update("Waiting for coins...")
                    task.wait(1)
                else
                    -- update status
                    statusLabel:Update(("Farming: %s - %s | Mode: %s"):format(tostring(SelectedWorld), tostring(SelectedArea), tostring(extras._targetMode or "Nearest")))

                    -- free stale assignments
                    FreeStaleAssignments(coins)

                    -- Decide behavior based on modes
                    if extras._blatant then
                        -- Blatant: assign ALL equipped pets to every breakable (aggressive)
                        local petUIDs = pickTopNFromSave()
                        for id, data in pairs(coins) do
                            if type(data) == "table" then
                                for _, uid in ipairs(petUIDs) do
                                    if uid then
                                        safe_delay(0, function() JoinCoin(id, {uid}) end)
                                        safe_delay(JOIN_DELAY, function() ChangePetTarget(uid, "Coin", id) end)
                                        safe_delay(JOIN_DELAY + CHANGE_DELAY, function() FarmCoin(id, uid) end)
                                        task.wait(0.01)
                                    end
                                end
                            end
                        end
                    elseif extras._safe then
                        -- Safe: slower assignment (more stealthy)
                        FillAssignments(coins)
                        task.wait(SAFE_DELAY_BETWEEN_ASSIGN * 2) -- extra delay
                    else
                        -- Normal: one pet per breakable for selected area
                        FillAssignments(coins)
                    end

                    -- Collect orbs (safe)
                    pcall(function() ClaimOrbs({}) end)

                    -- collect lootbags
                    pcall(function()
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
                    end)
                end
            end
            task.wait(AUTO_LOOP_DELAY)
        end
    end)

    -- Track when a breakable disappears to increment broken count (heuristic)
    task.spawn(function()
        local lastKeys = {}
        while true do
            local coins = GetCoinsRaw()
            local currentKeys = {}
            if coins then for id,_ in pairs(coins) do currentKeys[id] = true end end
            for k,_ in pairs(lastKeys) do
                if not currentKeys[k] then
                    BrokenCount = BrokenCount + 1
                end
            end
            lastKeys = currentKeys
            task.wait(0.7)
        end
    end)

    print("[HateAF] Loaded successfully. UI ready.")

end) -- end pcall

if not ok then
    warn("[HateAF] Startup error:", mainErr)
else
    print("[HateAF] Script executed successfully!")
end
