-- Hate's Autofarm — Final (World/Area refresh fix + status/time + broken count)
-- Paste into NEW LocalScript and run

local ok, mainErr = pcall(function()

    -- ===== CONFIG =====
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

    -- ===== REMOTE HELPER =====
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

    -- ===== UTILITIES =====
    local function safe_delay(t, f) if type(t) == "number" and type(f) == "function" then task.delay(t, f) end end
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

    -- ===== ASSIGN HELPERS =====
    local function normalizeSelection(val)
        if type(val) == "table" then return tostring(val[1] or val) end
        return tostring(val or "")
    end

    local function ClearAssignment(uid)
        if not uid then return end
        local t = petToTarget[uid]
        if t then
            petToTarget[uid] = nil
            targetToPet[t] = nil
            -- count as broken/cleared when target vanished
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

    -- ===== RAYFIELD LOADER (use provided URL) =====
    local Rayfield
    do
        local success, lib = pcall(function()
            return loadstring(game:HttpGet("https://raw.githubusercontent.com/SiriusSoftwareLtd/Rayfield/main/source.lua"))()
        end)
        if success and type(lib) == "table" then Rayfield = lib else Rayfield = nil; warn("[Hate AF] Rayfield failed to load; falling back to simple UI.") end
    end

    -- ===== UI =====
    local ui = {}
    if not Rayfield then
        -- minimal fallback: no interactive UI, just prints and remote triggers
        print("[Hate AF] Rayfield not available — running fallback. Use command-line toggles.")
    else
        local Window = Rayfield:CreateWindow({
            Name = "Hate's Autofarm",
            LoadingTitle = "Hate's Autofarm",
            LoadingSubtitle = "Quality Of Life",
            ConfigurationSaving = {Enabled = false},
            KeySystem = false
        })

        local MainTab = Window:CreateTab("Hate' Quality Of Life")

        -- Status section
        local StatusSection = MainTab:CreateSection("Status")
        local statusLabel = MainTab:CreateLabel(("Mode: %s | World: %s | Area: %s | Pets: %d | Broken: %d | %s"):format(
            tostring(Mode), tostring(SelectedWorld), tostring(SelectedArea), #trackedPets, brokenCount, os.date("%X")
        ))

        -- Controls section (Buttons)
        local ControlsSection = MainTab:CreateSection("Controls")
        local pickBtn = MainTab:CreateButton({Name = "Pick Best Pets", Callback = function()
            trackedPets = pickTopNFromSave()
            for _,u in ipairs(trackedPets) do pcall(function() EquipPet(u) end); task.wait(0.06) end
            task.wait(EQUIP_WAIT)
            statusLabel:Refresh(("Mode: %s | World: %s | Area: %s | Pets: %d | Broken: %d | %s"):format(
                tostring(Mode), tostring(SelectedWorld), tostring(SelectedArea), #trackedPets, brokenCount, os.date("%X")
            ))
        end})
        local equipBtn = MainTab:CreateButton({Name = "Equip Best (remote)", Callback = function()
            local ok = EquipBestPetsRemote()
            if ok then task.wait(0.6) end
        end})

        -- Mode toggles (mutually exclusive)
        local ModeSection = MainTab:CreateSection("Mode")
        local function setMode(newMode)
            Mode = newMode
            petToTarget = {}; targetToPet = {}; petCooldowns = {}
            statusLabel:Refresh(("Mode: %s | World: %s | Area: %s | Pets: %d | Broken: %d | %s"):format(
                tostring(Mode), tostring(SelectedWorld), tostring(SelectedArea), #trackedPets, brokenCount, os.date("%X")
            ))
        end

        local normalToggle = MainTab:CreateToggle({Name="Normal Mode", CurrentValue=false, Callback=function(val) if val then setMode("Normal") else if Mode == "Normal" then setMode("None") end end end})
        local safeToggle = MainTab:CreateToggle({Name="Safe Mode", CurrentValue=false, Callback=function(val) if val then setMode("Safe") else if Mode == "Safe" then setMode("None") end end end})
        local blatToggle = MainTab:CreateToggle({Name="Blatant Mode", CurrentValue=false, Callback=function(val) if val then setMode("Blatant") else if Mode == "Blatant" then setMode("None") end end end})
        local nearestToggle = MainTab:CreateToggle({Name="Target Nearest (All Pets)", CurrentValue=false, Callback=function(val) if val then setMode("Nearest") else if Mode == "Nearest" then setMode("None") end end end})

        -- Area selection section (dynamic refresh)
        local AreaSection = MainTab:CreateSection("Area Selection")
        local worldList = {}
        for k,_ in pairs(WorldsTable) do table.insert(worldList, k) end
        table.sort(worldList)

        -- create placeholders for dropdown handles
        local WorldDropdown, AreaDropdown, TargetDropdown

        WorldDropdown = MainTab:CreateDropdown({
            Name = "Select World",
            Options = worldList,
            CurrentOption = SelectedWorld,
            Callback = function(selected)
                selected = normalizeSelection(selected)
                SelectedWorld = selected
                local areas = WorldsTable[SelectedWorld] or {"None"}
                SelectedArea = areas[1] or ""
                -- Try to refresh area dropdown; Rayfield variants differ, handle a few methods
                if AreaDropdown and type(AreaDropdown.Refresh) == "function" then
                    pcall(function() AreaDropdown:Refresh(areas, true) end)
                elseif AreaDropdown and type(AreaDropdown.UpdateOptions) == "function" then
                    pcall(function() AreaDropdown:UpdateOptions(areas) end)
                    pcall(function() AreaDropdown:Set(areas[1] or "") end)
                else
                    -- fallback: recreate area dropdown
                    if AreaDropdown and AreaDropdown.Destroy then pcall(function() AreaDropdown:Destroy() end) end
                    AreaDropdown = MainTab:CreateDropdown({
                        Name = "Select Area",
                        Options = areas,
                        CurrentOption = SelectedArea,
                        Callback = function(a) SelectedArea = normalizeSelection(a) end
                    })
                end
                petToTarget = {}; targetToPet = {}; petCooldowns = {}
                statusLabel:Refresh(("Mode: %s | World: %s | Area: %s | Pets: %d | Broken: %d | %s"):format(
                    tostring(Mode), tostring(SelectedWorld), tostring(SelectedArea), #trackedPets, brokenCount, os.date("%X")
                ))
            end
        })

        AreaDropdown = MainTab:CreateDropdown({
            Name = "Select Area",
            Options = WorldsTable[SelectedWorld] or {},
            CurrentOption = SelectedArea,
            Callback = function(a)
                a = normalizeSelection(a)
                SelectedArea = a
                petToTarget = {}; targetToPet = {}; petCooldowns = {}
                statusLabel:Refresh(("Mode: %s | World: %s | Area: %s | Pets: %d | Broken: %d | %s"):format(
                    tostring(Mode), tostring(SelectedWorld), tostring(SelectedArea), #trackedPets, brokenCount, os.date("%X")
                ))
            end
        })

        TargetDropdown = MainTab:CreateDropdown({
            Name = "Target Type",
            Options = TargetTypeOptions,
            CurrentOption = TargetNearestType,
            Callback = function(opt) TargetNearestType = normalizeSelection(opt) end
        })

        -- Minimize / Restore
        MainTab:CreateButton({Name = "Minimize UI", Callback = function()
            pcall(function() Window:Hide() end)
            if not PlayerGui:FindFirstChild("HateRestoreBtn") then
                local btn = Instance.new("TextButton", PlayerGui)
                btn.Name = "HateRestoreBtn"
                btn.Size = UDim2.new(0, 20, 0, 20) -- 20x20 px as requested
                btn.Position = UDim2.new(0, 6, 0, 36) -- top-left-ish
                btn.Text = "H"
                btn.Font = Enum.Font.SourceSansBold
                btn.BackgroundColor3 = Color3.fromRGB(12,12,12)
                btn.TextColor3 = Color3.new(1,1,1)
                btn.ZIndex = 9999
                local corner = Instance.new("UICorner", btn); corner.CornerRadius = UDim.new(0,4)
                btn.MouseButton1Click:Connect(function()
                    pcall(function() Window:Show() end)
                    btn:Destroy()
                end)
            end
        end})

        -- save handles
        ui.Window = Window
        ui.WorldDropdown = WorldDropdown
        ui.AreaDropdown = AreaDropdown
        ui.TargetDropdown = TargetDropdown
        ui.StatusLabel = statusLabel
    end

    -- ===== BACKGROUND LOOP =====
    task.spawn(function()
        while true do
            -- update status label each loop if available
            if ui and ui.StatusLabel and type(ui.StatusLabel.Refresh) == "function" then
                ui.StatusLabel:Refresh(("Mode: %s | World: %s | Area: %s | Pets: %d | Broken: %d | %s"):format(
                    tostring(Mode), tostring(SelectedWorld), tostring(SelectedArea), #trackedPets, brokenCount, os.date("%X")
                ))
            end

            local coins = nil
            if Mode ~= "None" then coins = GetCoinsRaw() or {} end

            if Mode == "Nearest" then
                if #trackedPets == 0 then
                    trackedPets = pickTopNFromSave()
                    for _, uid in ipairs(trackedPets) do pcall(function() EquipPet(uid) end); task.wait(0.06) end
                    task.wait(EQUIP_WAIT)
                end
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

    print("[Hate AF] Loaded successfully. World->Area refresh fixed; status/time/broken count active.")

end) -- end pcall

if not ok then
    warn("[Hate AF] Startup error:", mainErr)
else
    print("[Hate AF] Script executed successfully!")
end
