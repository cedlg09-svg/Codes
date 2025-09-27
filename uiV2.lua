-- Delta-safe bootstrap (prevents line 1 errors / server execution)
if not game or not game:IsLoaded() then repeat task.wait() until game and game:IsLoaded() end
local RunService = game:GetService("RunService")
if RunService:IsServer() then return end

-- Main wrapper to protect startup errors
local ok, mainErr = pcall(function()
    -- ========================
    -- Hate AF - Fluent UI transfer (keeps logic intact)
    -- Paste into NEW Script and run in Delta
    -- ========================

    -- ==== SERVICES & BASIC SETUP ====
    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local Workspace = game:GetService("Workspace")
    local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()
    local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

    -- ==== CONFIG / TABLES ====
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

    local SAFE_DELAY_BETWEEN_ASSIGN = 0.18
    local JOIN_DELAY = 0.06
    local CHANGE_DELAY = 0.04
    local MAIN_LOOP_DELAY = 0.8
    local EQUIP_WAIT = 0.45
    local RETARGET_DELAY = 0.3

    -- ==== STATE ====
    local Network = ReplicatedStorage:FindFirstChild("Network")
    if not Network then warn("[HateAF] ReplicatedStorage.Network not found. Remotes may be missing.") end

    local SelectedWorld = "Spawn"
    local SelectedArea = WorldsTable["Spawn"] and WorldsTable["Spawn"][1] or ""
    local Mode = "None" -- Normal, Safe, Blatant, NearestArea, NearestGlobal
    local TargetType = "Any"
    local Enabled = false
    local SlowMode = false

    local trackedPets = {}
    local petToTarget = {}
    local targetToPet = {}
    local petCooldowns = {}
    local brokenCount = 0
    local startTime = 0

    -- ==== REMOTE HELPERS (safe, no top-level vararg) ====
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
    local function EquipBestPetsRemote() if not Network then return false end local r = Network:FindFirstChild("Equip Best Pets") if not r then return false end local ok = pcall(function() r:InvokeServer() end) return ok end

    -- ==== UTILITIES ====
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

    -- ==== TARGET TYPE HELPER ====
    local function matchesTargetType(ttype, data)
        if not ttype or ttype=="Any" then return true end
        if not data then return false end
        local name = tostring(data.n or data.name or ""):lower()
        if ttype=="Coins" then return (name:find("coin")~=nil) end
        if ttype=="Diamonds" then return (name:find("diamond")~=nil or name:find("gem")~=nil) end
        if ttype=="Chests" then return (name:find("chest")~=nil or name:find("crate")~=nil) end
        if ttype=="Breakables" then return true end
        return true
    end

    -- ==== ASSIGNMENT / FARMING HELPERS ====
    local function AssignPetToBreakable(petUID, breakId, safeMode)
        if not petUID or not breakId then return false end
        if safeMode then
            local j = JOIN_DELAY + math.random(80,220)/1000
            local c = CHANGE_DELAY + math.random(80,220)/1000
            safe_delay(0, function() JoinCoin(breakId, {petUID}) end)
            safe_delay(j, function() ChangePetTarget(petUID, "Coin", breakId) end)
            safe_delay(j+c, function() FarmCoin(breakId, petUID) end)
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
            brokenCount = brokenCount + 1
        end
        petCooldowns[petUID] = tick() + RETARGET_DELAY
    end

    local function FreeStaleAssignments(coins)
        local present = {}
        if coins then for id, _ in pairs(coins) do present[id] = true end end
        for uid, id in pairs(petToTarget) do
            if not present[id] then ClearAssignmentForPet(uid) end
        end
    end

    local function GetAvailableBreakablesForArea(coins)
        local available = {}
        if not coins then return available end
        for id, item in pairs(coins) do
            if type(item) == "table" then
                local w = tostring(item.w or item.world or "")
                local a = tostring(item.a or item.area or "")
                if w == tostring(SelectedWorld) and a == tostring(SelectedArea) and not targetToPet[id] and matchesTargetType(TargetType, item) then
                    table.insert(available, {id = id, data = item})
                end
            end
        end
        return available
    end

    local function FillAssignmentsGeneric(coins, mode)
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

        local available = GetAvailableBreakablesForArea(coins)
        if #available == 0 then return end

        if mode == "Normal" then
            local count = math.min(#freePets, #available)
            for i=1,count do
                pcall(function() AssignPetToBreakable(freePets[i], available[i].id, false) end)
                task.wait(SAFE_DELAY_BETWEEN_ASSIGN)
            end
        elseif mode == "Safe" then
            local count = math.min(#freePets, #available, 2)
            for i=1,count do
                pcall(function() AssignPetToBreakable(freePets[i], available[i].id, true) end)
                task.wait(0.25 + math.random(0,300)/1000)
            end
        elseif mode == "Blatant" then
            local iPet,iAvail = 1,1
            while iPet <= #freePets and iAvail <= #available do
                pcall(function() AssignPetToBreakable(freePets[iPet], available[iAvail].id, false) end)
                iPet = iPet + 1; iAvail = iAvail + 1
                task.wait(0.01)
            end
        end
    end

    local function TargetNearestInArea(coins)
        if not coins or not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then return end
        local hrp = LocalPlayer.Character.HumanoidRootPart
        local bestId, bestDist = nil, math.huge
        for id, data in pairs(coins) do
            if type(data) == "table" then
                local w = tostring(data.w or data.world or "")
                local a = tostring(data.a or data.area or "")
                if w == tostring(SelectedWorld) and a == tostring(SelectedArea) and matchesTargetType(TargetType, data) then
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
                    petToTarget[uid] = bestId; targetToPet[bestId] = uid; petCooldowns[uid] = tick()
                end)
                task.wait(0.03)
            end
        end
    end

    local function TargetNearestGlobal(coins)
        if not coins or not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then return end
        local hrp = LocalPlayer.Character.HumanoidRootPart
        local bestId, bestDist = nil, math.huge
        for id, data in pairs(coins) do
            if type(data) == "table" and matchesTargetType(TargetType, data) then
                local p = data.p
                if p and typeof(p) == "Vector3" then
                    local d = (hrp.Position - p).Magnitude
                    if d < bestDist then bestDist = d; bestId = id end
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
                    petToTarget[uid] = bestId; targetToPet[bestId] = uid; petCooldowns[uid] = tick()
                end)
                task.wait(0.03)
            end
        end
    end

    -- ==== EGG ANIMATION DISABLE ONE-SHOT ====
    local eggDisabled = false
    local function disableEggAnimationOnce()
        if eggDisabled then return false end
        eggDisabled = true
        pcall(function()
            for i,v in pairs(getgc(true) or {}) do
                if type(v)=="table" and rawget(v,"OpenEgg") then
                    pcall(function() v.OpenEgg = function() return end end)
                end
            end
        end)
        return true
    end

    -- ==== ANTI-AFK (one-shot) ====
    pcall(function()
        local vu = game:GetService("VirtualUser")
        Players.LocalPlayer.Idled:Connect(function()
            vu:Button2Down(Vector2.new(0,0), workspace.CurrentCamera)
            task.wait(1)
            vu:Button2Up(Vector2.new(0,0), workspace.CurrentCamera)
        end)
    end)

    -- ==== FLUENT UI (AUTO-LOAD) ====
    -- Provided load line (auto-load Fluent)
    local Fluent = nil
    local fluentScreenGui = nil
    local Window, Tabs = nil, nil
    local statusLabelUpdater = nil

    -- remember existing GUIs to detect Fluent-created ScreenGui
    local beforeGUIs = {}
    for _,g in ipairs(PlayerGui:GetChildren()) do beforeGUIs[g] = true end

    -- load Fluent (your provided auto-load)
    local okFluent, fluentRes = pcall(function()
        return loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
    end)
    if okFluent and fluentRes then
        Fluent = fluentRes
    else
        error("[HateAF] Failed to load Fluent UI. Aborting (fallback removed).")
    end

    -- Create Fluent window & tabs (guard with pcall)
    do
        local suc, res = pcall(function()
            -- CreateWindow signature varies; this is the commonly used one
            Window = Fluent:CreateWindow({
                Title = "Hate's Autofarm — V2",
                SubTitle = "Hate AF",
                Size = UDim2.fromOffset(640, 420),
                TabWidth = 160,
                Acrylic = false,
                Theme = "Dark"
            })
            Tabs = {
                Main = Window:AddTab({ Title = "Main", Icon = "home" }),
                Eggs = Window:AddTab({ Title = "Eggs", Icon = "box" }),
                Upgrades = Window:AddTab({ Title = "Upgrades", Icon = "sparkles" })
            }
        end)
        if not suc then
            error("[HateAF] Fluent window creation failed: " .. tostring(res))
        end
    end

    -- attempt to detect the ScreenGui Fluent added
    local function detectNewScreenGui(before)
        for _,child in ipairs(PlayerGui:GetChildren()) do
            if child:IsA("ScreenGui") and not before[child] then
                return child
            end
        end
        return nil
    end
    -- small defer to allow Fluent to create its GUI
    task.spawn(function()
        for i=1,30 do
            fluentScreenGui = detectNewScreenGui(beforeGUIs)
            if fluentScreenGui then break end
            task.wait(0.03)
        end
    end)

    -- ==== BUILD CONTROLS (TRANSFER EXACT BEHAVIOR) ====
    -- Helper to set status text (best-effort across Fluent versions)
    local function setStatusText(t)
        -- prefer a stored updater
        if statusLabelUpdater then
            pcall(function() statusLabelUpdater(t) end)
            return
        end
        -- otherwise, try to find a TextLabel inside fluentScreenGui that starts with "Mode:"
        if fluentScreenGui then
            pcall(function()
                for _,v in ipairs(fluentScreenGui:GetDescendants()) do
                    if v:IsA("TextLabel") and tostring(v.Text):sub(1,5) == "Mode:" then
                        v.Text = t
                        return
                    end
                end
            end)
        end
    end

    -- MAIN TAB: add buttons / toggles / dropdowns
    do
        local MainTab = Tabs.Main

        -- Status text element
        local initialStatus = ("Mode:%s | World:%s | Area:%s | Pets:%d | Broken:%d | Time:%s"):format(Mode, SelectedWorld, SelectedArea, #trackedPets, brokenCount, "00:00")
        local statusElem = nil
        pcall(function()
            if MainTab.AddLabel then
                statusElem = MainTab:AddLabel({ Title = initialStatus })
                -- store a function to update the label
                if statusElem and statusElem.Set then
                    statusLabelUpdater = function(s) pcall(function() statusElem:Set(s) end) end
                elseif statusElem and statusElem.Update then
                    statusLabelUpdater = function(s) pcall(function() statusElem:Update(s) end) end
                end
            elseif MainTab.AddParagraph then
                statusElem = MainTab:AddParagraph({ Title = initialStatus })
                if statusElem and statusElem.Set then
                    statusLabelUpdater = function(s) pcall(function() statusElem:Set(s) end) end
                end
            end
        end)
        if not statusLabelUpdater then
            -- fallback updater (will search TextLabel)
            statusLabelUpdater = function(s) setStatusText(s) end
        end
        statusLabelUpdater(initialStatus)

        -- Pick Best Pets button
        pcall(function()
            if MainTab.AddButton then
                MainTab:AddButton({ Title = "Pick Best Pets", Callback = function()
                    local chosen = pickTopNFromSave()
                    if #chosen == 0 then
                        if Fluent and Fluent.Notify then Fluent:Notify({Title="HateAF", Content="No pets found", Duration=3}) end
                        return
                    end
                    trackedPets = chosen
                    for _, uid in ipairs(trackedPets) do pcall(function() EquipPet(uid) end); task.wait(0.06) end
                    task.wait(EQUIP_WAIT)
                    if Fluent and Fluent.Notify then Fluent:Notify({Title="HateAF", Content = ("Equipped %d pets"):format(#trackedPets), Duration=3}) end
                end})
            end
        end)

        -- Equip Best (Remote)
        pcall(function()
            if MainTab.AddButton then
                MainTab:AddButton({ Title = "Equip Best (Remote)", Callback = function()
                    local ok = EquipBestPetsRemote()
                    if Fluent and Fluent.Notify then Fluent:Notify({Title="HateAF", Content = ok and "Requested remote equip." or "Remote equip failed.", Duration=3}) end
                end})
            end
        end)

        -- Mode toggles (mutually exclusive). We'll create toggles and keep track of them.
        local modeToggles = {}
        local function setOtherModeToggles(offTitle)
            for _,entry in ipairs(modeToggles) do
                pcall(function()
                    if entry and entry.Set and entry.Title ~= offTitle then
                        entry:Set(false)
                    end
                end)
            end
        end

        local function addModeToggle(title, mVal)
            pcall(function()
                if MainTab.AddToggle then
                    local el = MainTab:AddToggle({ Title = title, Default = (Mode == mVal), Callback = function(on)
                        if on then
                            Mode = mVal
                            setOtherModeToggles(title)
                        else
                            if Mode == mVal then Mode = "None" end
                        end
                    end})
                    -- store basic fields
                    el.Title = title
                    table.insert(modeToggles, el)
                else
                    -- fallback: add as button that toggles state (rare)
                    if MainTab.AddButton then
                        MainTab:AddButton({ Title = title, Callback = function()
                            if Mode == mVal then Mode = "None" else Mode = mVal end
                        end})
                    end
                end
            end)
        end

        addModeToggle("Normal", "Normal")
        addModeToggle("Safe", "Safe")
        addModeToggle("Blatant", "Blatant")
        addModeToggle("NearestArea", "NearestArea")
        addModeToggle("NearestGlobal", "NearestGlobal")

        -- Slow Mode toggle
        pcall(function()
            if MainTab.AddToggle then
                MainTab:AddToggle({ Title = "Slow Mode", Default = SlowMode, Callback = function(v) SlowMode = v end })
            end
        end)

        -- Target Type dropdown
        pcall(function()
            if MainTab.AddDropdown then
                MainTab:AddDropdown({ Title = "Target Type", List = TargetTypeOptions, Default = TargetType, Callback = function(v) TargetType = tostring(v or "Any") end })
            end
        end)

        -- World dropdown
        local worldOpts = (function() local t={} for k,_ in pairs(WorldsTable) do table.insert(t,k) end table.sort(t) return t end)()
        pcall(function()
            if MainTab.AddDropdown then
                MainTab:AddDropdown({ Title = "World", List = worldOpts, Default = SelectedWorld, Callback = function(sel)
                    SelectedWorld = tostring(sel or "")
                    local areas = WorldsTable[SelectedWorld] or {}
                    -- pick first area if exists
                    if #areas > 0 then SelectedArea = areas[1] else SelectedArea = "" end
                    petToTarget = {}; targetToPet = {}; petCooldowns = {}
                end})
                MainTab:AddDropdown({ Title = "Area", List = WorldsTable[SelectedWorld] or {}, Default = SelectedArea, Callback = function(sel)
                    SelectedArea = tostring(sel or "")
                    petToTarget = {}; targetToPet = {}; petCooldowns = {}
                end})
            end
        end)

        -- Refresh Areas
        pcall(function()
            if MainTab.AddButton then
                MainTab:AddButton({ Title = "Refresh Areas", Callback = function()
                    local areas = WorldsTable[SelectedWorld] or {}
                    if #areas > 0 then SelectedArea = areas[1] else SelectedArea = "" end
                    petToTarget = {}; targetToPet = {}; petCooldowns = {}
                    if Fluent and Fluent.Notify then Fluent:Notify({Title="HateAF", Content="Areas refreshed", Duration=2}) end
                end})
            end
        end)

        -- Start / Stop
        pcall(function()
            if MainTab.AddButton then
                MainTab:AddButton({ Title = "Start / Stop", Callback = function()
                    Enabled = not Enabled
                    if Enabled then startTime = tick() else startTime = 0 end
                    if Fluent and Fluent.Notify then Fluent:Notify({Title="HateAF", Content = Enabled and "Autofarm started" or "Autofarm stopped", Duration=2}) end
                end})
            end
        end)
    end

    -- EGGS TAB
    do
        local EggsTab = Tabs.Eggs
        pcall(function()
            if EggsTab.AddLabel then EggsTab:AddLabel({ Title = "Egg Management" }) end
            if EggsTab.AddButton then
                EggsTab:AddButton({ Title = "Disable Egg Animation (one-shot)", Callback = function()
                    local ok = disableEggAnimationOnce()
                    if Fluent and Fluent.Notify then Fluent:Notify({Title="HateAF", Content = ok and "Egg animation disabled" or "Already disabled", Duration=3}) end
                end})
            end
        end)
    end

    -- UPGRADES TAB (placeholders)
    do
        local UpgradesTab = Tabs.Upgrades
        pcall(function()
            if UpgradesTab.AddLabel then UpgradesTab:AddLabel({ Title = "Auto Fuse (placeholder)" }) end
            if UpgradesTab.AddLabel then UpgradesTab:AddLabel({ Title = "Auto Gold (placeholder)" }) end
            if UpgradesTab.AddLabel then UpgradesTab:AddLabel({ Title = "Auto Rainbow (placeholder)" }) end
            if UpgradesTab.AddLabel then UpgradesTab:AddLabel({ Title = "Auto Dark Matter (placeholder)" }) end
        end)
    end

    -- ensure first tab selected if API provides it
    pcall(function() if Window.SelectTab then Window:SelectTab(1) end end)

    -- ==== TOP-MIDDLE "Open" BUTTON (outside Fluent) ====
    local openBtn = Instance.new("TextButton")
    openBtn.Name = "HateAF_OpenButton"
    openBtn.Parent = PlayerGui
    openBtn.Size = UDim2.new(0,100,0,28)
    openBtn.Position = UDim2.new(0.5, -50, 0, 8) -- top-middle
    openBtn.Text = "Open"
    openBtn.Font = Enum.Font.SourceSansBold
    openBtn.TextSize = 16
    openBtn.BackgroundColor3 = Color3.fromRGB(24,24,24)
    openBtn.TextColor3 = Color3.new(1,1,1)
    openBtn.ZIndex = 9999
    local uic = Instance.new("UICorner", openBtn); uic.CornerRadius = UDim.new(0,6)

    -- By default UI is visible upon run (as you requested)
    local uiVisible = true

    local function setUIVisible(v)
        uiVisible = (v == true)
        pcall(function()
            if fluentScreenGui and fluentScreenGui.Parent then
                -- Many Fluent-created ScreenGuis support .Enabled; change both to be safe
                if fluentScreenGui:FindFirstChildWhichIsA then
                    -- try toggling Enabled property
                    if fluentScreenGui.Enabled ~= nil then
                        fluentScreenGui.Enabled = uiVisible
                    end
                end
                -- Ensure parent is PlayerGui when visible
                if uiVisible then
                    fluentScreenGui.Parent = PlayerGui
                else
                    -- Hide by setting Parent to nil may break things in some environments; instead set Enabled false
                    if fluentScreenGui.Enabled ~= nil then
                        fluentScreenGui.Enabled = false
                    else
                        -- as last resort, move to nil
                        fluentScreenGui.Parent = nil
                    end
                end
            else
                -- If detection hasn't happened yet, attempt to detect now
                fluentScreenGui = (function()
                    for _,child in ipairs(PlayerGui:GetChildren()) do
                        if child:IsA("ScreenGui") then
                            -- heuristics: Fluent GUIs often have 'Fluent' or the window title
                            if tostring(child.Name):lower():find("fluent") or tostring(child.Name):lower():find("hate") or tostring(child.Name):lower():find("autofarm") then
                                return child
                            end
                        end
                    end
                    return nil
                end)()
            end
        end)
        -- Update button visual to show active/inactive via color
        if uiVisible then
            openBtn.BackgroundColor3 = Color3.fromRGB(34,139,34)
        else
            openBtn.BackgroundColor3 = Color3.fromRGB(178,34,34)
        end
    end

    openBtn.MouseButton1Click:Connect(function()
        setUIVisible(not uiVisible)
    end)

    -- ensure fluentScreenGui detection completed and set visible (give a short grace period)
    task.spawn(function()
        for i=1,40 do
            if not fluentScreenGui then
                fluentScreenGui = detectNewScreenGui(beforeGUIs)
            end
            if fluentScreenGui then break end
            task.wait(0.03)
        end
        setUIVisible(true) -- visible at run
    end)

    -- ==== STATUS UPDATER ====
    task.spawn(function()
        while true do
            pcall(function()
                local elapsed = (startTime>0) and math.floor(tick()-startTime) or 0
                local tstr = string.format("%02d:%02d", math.floor(elapsed/60), elapsed%60)
                local statusStr = ("Mode:%s | World:%s | Area:%s | Pets:%d | Broken:%d | Time:%s"):format(Mode, SelectedWorld, SelectedArea, #trackedPets, brokenCount, tstr)
                if statusLabelUpdater then
                    pcall(function() statusLabelUpdater(statusStr) end)
                else
                    setStatusText(statusStr)
                end
            end)
            task.wait(0.6)
        end
    end)

    -- ==== MAIN LOOP ====
    task.spawn(function()
        while true do
            if Enabled then
                if #trackedPets == 0 then
                    trackedPets = pickTopNFromSave()
                    for _, uid in ipairs(trackedPets) do pcall(function() EquipPet(uid) end); task.wait(0.06) end
                    task.wait(EQUIP_WAIT)
                end

                local coins = GetCoinsRaw()
                if coins then
                    FreeStaleAssignments(coins)
                    local currentMode = Mode
                    if SlowMode and currentMode == "Blatant" then currentMode = "Normal" end
                    if currentMode == "NearestArea" then
                        TargetNearestInArea(coins)
                    elseif currentMode == "NearestGlobal" then
                        TargetNearestGlobal(coins)
                    elseif currentMode == "Normal" or currentMode == "Safe" or currentMode == "Blatant" then
                        FillAssignmentsGeneric(coins, currentMode)
                    end

                    pcall(function() ClaimOrbs({}) end)
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
            task.wait((SlowMode and MAIN_LOOP_DELAY*1.6) or MAIN_LOOP_DELAY)
        end
    end)

    print("[HateAF] Fluent UI loaded. 'Open' button at top-middle created.")
end)

if not ok then
    warn("[HateAF] Startup error:", mainErr)
else
    print("[HateAF] Script executed successfully!")
end
