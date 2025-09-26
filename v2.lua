-- Hate's QoL - Final (Rayfield UI, World->Area refresh, status/time/broken count, egg animation remover)
-- Paste into a NEW LocalScript and run

local ok, mainErr = pcall(function()

    -- ===== CONFIG =====
    local SAFE_DELAY_BETWEEN_ASSIGN = 0.18
    local JOIN_DELAY = 0.06
    local CHANGE_DELAY = 0.04
    local MAIN_LOOP_DELAY = 0.8
    local EQUIP_WAIT = 0.45
    local RETARGET_DELAY = 0.3

    -- Worlds table (static)
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

    -- ===== SERVICES =====
    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local Workspace = game:GetService("Workspace")
    local LocalPlayer = Players.LocalPlayer
    assert(LocalPlayer, "LocalPlayer nil - run as LocalScript")
    local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

    local Network = ReplicatedStorage:FindFirstChild("Network")
    if not Network then warn("[Hate AF] ReplicatedStorage.Network not found.") end

    -- ===== REMOTE CALL WRAPPER (safe) =====
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
            if type(v) == "table" then v.uid = v.uid or k; table.insert(out, v) end
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
        for i=1, math.min(maxEquip, #all) do if all[i] and all[i].uid then table.insert(chosen, all[i].uid) end end
        return chosen
    end

    -- ===== STATE =====
    local SelectedWorld = "Spawn"
    local SelectedArea = (WorldsTable["Spawn"] and WorldsTable["Spawn"][1]) or ""
    local TargetNearestType = "Any"
    local Mode = "None" -- "None","Normal","Safe","Blatant","Nearest"
    local trackedPets = {}
    local petToTarget = {}
    local targetToPet = {}
    local petCooldowns = {}
    local brokenCount = 0

    -- normalize selection (Rayfield sometimes returns table)
    local function normalizeSelection(val)
        if type(val) == "table" then return tostring(val[1] or "") end
        return tostring(val or "")
    end

    -- ===== ASSIGN HELPERS =====
    local function ClearAssignment(uid)
        if not uid then return end
        local t = petToTarget[uid]
        if t then
            petToTarget[uid] = nil
            targetToPet[t] = nil
            brokenCount = brokenCount + 1
        end
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
        for id,data in pairs(coins) do
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

    local function AssignPetToBreakable(uid, breakId, safeMode)
        if not uid or not breakId then return false end
        if safeMode then
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

    local function FillAssignmentsGeneric(coins, mode)
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

        if mode == "Normal" then
            local count = math.min(#freePets, #avail)
            for i=1,count do pcall(function() AssignPetToBreakable(freePets[i], avail[i].id, false) end); task.wait(SAFE_DELAY_BETWEEN_ASSIGN) end
        elseif mode == "Safe" then
            local count = math.min(#freePets, #avail, 2)
            for i=1,count do pcall(function() AssignPetToBreakable(freePets[i], avail[i].id, true) end); task.wait(0.3 + math.random(0,300)/1000) end
        elseif mode == "Blatant" then
            local iPet,iAvail = 1,1
            while iPet <= #freePets and iAvail <= #avail do
                pcall(function() AssignPetToBreakable(freePets[iPet], avail[iAvail].id, false) end)
                iPet = iPet + 1; iAvail = iAvail + 1
                task.wait(0.01)
            end
        end
    end

    local function TargetNearestAll(coins)
        if not coins then return end
        if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then return end
        local hrp = LocalPlayer.Character.HumanoidRootPart
        local bestId, bestDist = nil, math.huge
        for id,data in pairs(coins) do
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

    -- ===== ANTI AFK =====
    pcall(function()
        local vu = game:GetService("VirtualUser")
        Players.LocalPlayer.Idled:Connect(function()
            vu:Button2Down(Vector2.new(0,0), workspace.CurrentCamera)
            task.wait(1)
            vu:Button2Up(Vector2.new(0,0), workspace.CurrentCamera)
        end)
    end)

    -- ===== RAYFIELD LOAD =====
    local Rayfield = nil
    do
        local ok, lib = pcall(function()
            return loadstring(game:HttpGet("https://raw.githubusercontent.com/SiriusSoftwareLtd/Rayfield/main/source.lua"))()
        end)
        if ok and type(lib) == "table" then
            Rayfield = lib
        else
            warn("[Hate AF] Rayfield failed to load - UI won't appear.")
        end
    end

    -- Keep track if egg animation disabled (one-shot)
    local eggAnimDisabled = false
    local function disableEggAnimationOnce()
        if eggAnimDisabled then return false end
        eggAnimDisabled = true
        -- best-effort: find OpenEgg in GC and override
        pcall(function()
            for i,v in pairs(getgc(true) or {}) do
                if type(v) == "table" and rawget(v, "OpenEgg") then
                    pcall(function() v.OpenEgg = function() return end end)
                end
            end
        end)
        return true
    end

    -- run the egg disable once at startup (per request: run once and cannot be turned off)
    pcall(function() disableEggAnimationOnce() end)

    -- ===== UI BUILD (Rayfield) =====
    local ui = {}
    if Rayfield then
        local Window = Rayfield:CreateWindow({
            Name = "Hate's QoL", -- this will also be the minimized/restore button text
            LoadingTitle = "Hate AF",
            LoadingSubtitle = "Autofarm Suite",
            ConfigurationSaving = { Enabled = false },
            Discord = { Enabled = false },
            KeySystem = false
        })

        -- Tabs / Windows
        local MainTab = Window:CreateTab("Hate' Quality Of Life")
        local UpgradesTab = Window:CreateTab("Upgrades")
        local EggTab = Window:CreateTab("Egg Management")

        -- Status section (auto-updating)
        local StatusSection = MainTab:CreateSection("Status")
        local statusLabel = MainTab:CreateLabel(("Mode: %s | World: %s | Area: %s | Pets: %d | Broken: %d | %s"):format(
            tostring(Mode), tostring(SelectedWorld), tostring(SelectedArea), #trackedPets, brokenCount, os.date("%X")
        ))

        -- Controls section (buttons)
        local ControlsSection = MainTab:CreateSection("Controls")
        MainTab:CreateButton({Name = "Pick Best Pets", Callback = function()
            trackedPets = pickTopNFromSave()
            for _,u in ipairs(trackedPets) do pcall(function() EquipPet(u) end); task.wait(0.06) end
            task.wait(EQUIP_WAIT)
            pcall(function() statusLabel:Refresh(("Mode: %s | World: %s | Area: %s | Pets: %d | Broken: %d | %s"):format(
                tostring(Mode), tostring(SelectedWorld), tostring(SelectedArea), #trackedPets, brokenCount, os.date("%X")
            )) end)
        end})

        MainTab:CreateButton({Name = "Equip Best (remote)", Callback = function()
            local ok = EquipBestPetsRemote()
            if ok then task.wait(0.6) end
        end})

        -- Modes (mutually exclusive toggles)
        local ModeSection = MainTab:CreateSection("Modes")
        local toggles = {}
        local function setMode(newMode)
            Mode = newMode or "None"
            petToTarget = {}; targetToPet = {}; petCooldowns = {}; brokenCount = brokenCount -- keep count
            -- ensure UI toggles reflect exclusivity
            for k,v in pairs(toggles) do
                if k ~= newMode and v and type(v.Set) == "function" then pcall(function() v:Set(false) end) end
            end
            pcall(function() statusLabel:Refresh(("Mode: %s | World: %s | Area: %s | Pets: %d | Broken: %d | %s"):format(
                tostring(Mode), tostring(SelectedWorld), tostring(SelectedArea), #trackedPets, brokenCount, os.date("%X")
            )) end)
        end

        toggles["Normal"] = MainTab:CreateToggle({Name="Normal Mode", CurrentValue=false, Flag = "ModeNormal", Callback=function(val) if val then setMode("Normal") else if Mode == "Normal" then setMode("None") end end end})
        toggles["Safe"] = MainTab:CreateToggle({Name="Safe Mode", CurrentValue=false, Flag = "ModeSafe", Callback=function(val) if val then setMode("Safe") else if Mode == "Safe" then setMode("None") end end end})
        toggles["Blatant"] = MainTab:CreateToggle({Name="Blatant Mode", CurrentValue=false, Flag = "ModeBlatant", Callback=function(val) if val then setMode("Blatant") else if Mode == "Blatant" then setMode("None") end end end})

        -- Target Nearest section (separate)
        local NearestSection = MainTab:CreateSection("Target Nearest (All Pets)")
        local nearestToggle = MainTab:CreateToggle({Name = "Target Nearest (All Pets) - Toggle (mutually exclusive)", CurrentValue = false, Callback = function(val)
            if val then
                setMode("Nearest")
            else
                if Mode == "Nearest" then setMode("None") end
            end
        end})
        local targetTypeDropdown = MainTab:CreateDropdown({
            Name = "Target Type",
            Options = TargetTypeOptions,
            CurrentOption = TargetNearestType,
            Callback = function(opt) TargetNearestType = normalizeSelection(opt) end
        })

        -- Area selection (World -> Area)
        local AreaSection = MainTab:CreateSection("World & Area")
        -- build world list
        local worldList = {}
        for k,_ in pairs(WorldsTable) do table.insert(worldList, k) end
        table.sort(worldList)

        -- placeholders so we can recreate area dropdown if needed
        local worldDropdown, areaDropdown

        worldDropdown = MainTab:CreateDropdown({
            Name = "Select World",
            Options = worldList,
            CurrentOption = SelectedWorld,
            Callback = function(selected)
                selected = normalizeSelection(selected)
                SelectedWorld = selected
                -- refresh areas for this world
                local areas = WorldsTable[SelectedWorld] or {"None"}
                SelectedArea = areas[1] or ""
                -- try Rayfield .Set API first
                if areaDropdown and type(areaDropdown.Set) == "function" then
                    pcall(function() areaDropdown:Set(areas) end)
                    pcall(function() areaDropdown:Set(SelectedArea) end)
                elseif areaDropdown and type(areaDropdown.Refresh) == "function" then
                    -- some Rayfield variants have Refresh
                    pcall(function() areaDropdown:Refresh(areas, true) end)
                else
                    -- recreate dropdown fallback
                    if areaDropdown and type(areaDropdown.Destroy) == "function" then pcall(function() areaDropdown:Destroy() end) end
                    areaDropdown = MainTab:CreateDropdown({
                        Name = "Select Area",
                        Options = areas,
                        CurrentOption = SelectedArea,
                        Callback = function(a) SelectedArea = normalizeSelection(a) end
                    })
                end
                petToTarget = {}; targetToPet = {}; petCooldowns = {}
                pcall(function() statusLabel:Refresh(("Mode: %s | World: %s | Area: %s | Pets: %d | Broken: %d | %s"):format(
                    tostring(Mode), tostring(SelectedWorld), tostring(SelectedArea), #trackedPets, brokenCount, os.date("%X")
                )) end)
            end
        })

        areaDropdown = MainTab:CreateDropdown({
            Name = "Select Area",
            Options = WorldsTable[SelectedWorld] or {},
            CurrentOption = SelectedArea,
            Callback = function(a)
                a = normalizeSelection(a)
                SelectedArea = a
                petToTarget = {}; targetToPet = {}; petCooldowns = {}
                pcall(function() statusLabel:Refresh(("Mode: %s | World: %s | Area: %s | Pets: %d | Broken: %d | %s"):format(
                    tostring(Mode), tostring(SelectedWorld), tostring(SelectedArea), #trackedPets, brokenCount, os.date("%X")
                )) end)
            end
        })

        -- Upgrades window (placeholders)
        UpgradesTab:CreateSection("Auto Upgrades (placeholders)")
        UpgradesTab:CreateButton({Name = "Auto Fuse (placeholder)", Callback = function() warn("Auto Fuse placeholder") end})
        UpgradesTab:CreateButton({Name = "Auto Rainbow (placeholder)", Callback = function() warn("Auto Rainbow placeholder") end})
        UpgradesTab:CreateButton({Name = "Auto Gold (placeholder)", Callback = function() warn("Auto Gold placeholder") end})
        UpgradesTab:CreateButton({Name = "Auto Dark Matter (placeholder)", Callback = function() warn("Auto DM placeholder") end})

        -- Egg Management window
        EggTab:CreateSection("Egg Management")
        EggTab:CreateButton({Name = "Disable Egg Hatching Animation (one-shot)", Callback = function()
            local ok = disableEggAnimationOnce()
            if ok then warn("[Hate AF] Egg animation disabled (one-shot)") else warn("[Hate AF] Egg animation already disabled") end
        end})
        EggTab:CreateDropdown({Name = "Egg Type (placeholder)", Options = {"Valentines Egg","Default Egg","Event Egg"}, CurrentOption = "Valentines Egg", Callback = function(_) end})
        EggTab:CreateBox({Name = "Amount to Open (placeholder)", Type = "number", Callback = function(_) end})

        -- expose some ui handles
        ui.Window = Window
        ui.WorldDropdown = worldDropdown
        ui.AreaDropdown = areaDropdown
        ui.StatusLabel = statusLabel
        ui.TargetDropdown = targetTypeDropdown
    else
        warn("[Hate AF] Rayfield not available; UI disabled.")
    end

    -- ===== BACKGROUND LOOP =====
    task.spawn(function()
        while true do
            -- update status label if available
            if ui and ui.StatusLabel and type(ui.StatusLabel.Refresh) == "function" then
                pcall(function()
                    ui.StatusLabel:Refresh(("Mode: %s | World: %s | Area: %s | Pets: %d | Broken: %d | %s"):format(
                        tostring(Mode), tostring(SelectedWorld), tostring(SelectedArea), #trackedPets, brokenCount, os.date("%X")
                    ))
                end)
            end

            local coins = nil
            if Mode ~= "None" then coins = GetCoinsRaw() or {} end

            if Mode == "Nearest" then
                if #trackedPets == 0 then trackedPets = pickTopNFromSave(); for _, uid in ipairs(trackedPets) do pcall(function() EquipPet(uid) end); task.wait(0.06) end; task.wait(EQUIP_WAIT) end
                if coins then FreeStaleAssignments(coins); TargetNearestAll(coins); pcall(function() ClaimOrbs({}) end) end
                task.wait(0.45 + math.random(0,200)/1000)
            elseif Mode == "Normal" then
                if #trackedPets == 0 then trackedPets = pickTopNFromSave(); for _, uid in ipairs(trackedPets) do pcall(function() EquipPet(uid) end); task.wait(0.06) end; task.wait(EQUIP_WAIT) end
                if coins then FreeStaleAssignments(coins); FillAssignmentsGeneric(coins, "Normal"); pcall(function() ClaimOrbs({}) end) end
                task.wait(MAIN_LOOP_DELAY)
            elseif Mode == "Safe" then
                if #trackedPets == 0 then trackedPets = pickTopNFromSave(); for _, uid in ipairs(trackedPets) do pcall(function() EquipPet(uid) end); task.wait(0.09 + math.random(0,100)/1000) end; task.wait(EQUIP_WAIT) end
                if coins then FreeStaleAssignments(coins); FillAssignmentsGeneric(coins, "Safe"); pcall(function() ClaimOrbs({}) end) end
                task.wait(MAIN_LOOP_DELAY + 0.6 + math.random(0,300)/1000)
            elseif Mode == "Blatant" then
                if #trackedPets == 0 then trackedPets = pickTopNFromSave(); for _, uid in ipairs(trackedPets) do pcall(function() EquipPet(uid) end); task.wait(0.04) end; task.wait(EQUIP_WAIT) end
                if coins then FreeStaleAssignments(coins); FillAssignmentsGeneric(coins, "Blatant"); pcall(function() ClaimOrbs({}) end) end
                task.wait(0.25 + math.random(0,200)/1000)
            else
                task.wait(0.8)
            end
        end
    end)

    print("[Hate AF] Loaded successfully. Rayfield name set to 'Hate''s QoL'.")

end) -- end pcall

if not ok then
    warn("[Hate AF] Startup error:", mainErr)
else
    print("[Hate AF] Script executed successfully!")
end
