-- Hate's Quality of Life (Full) - Rayfield UI + Autofarm
-- Paste into a NEW LocalScript and run (LocalScript required)

local ok, mainErr = pcall(function()

    ----------------- CONFIG -----------------
    local JOIN_DELAY = 0.06
    local CHANGE_DELAY = 0.04
    local MAIN_LOOP_DELAY = 0.8
    local SAFE_LOOP_DELAY = 2.0
    local EQUIP_WAIT = 0.45
    local RETARGET_DELAY = 0.3
    local MAX_ASSIGN_PER_CYCLE = 6
    local MAX_ASSIGN_PER_CYCLE_SAFE = 2

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

    ----------------- SERVICES -----------------
    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local Workspace = game:GetService("Workspace")
    local UserInputService = game:GetService("UserInputService")
    local LocalPlayer = Players.LocalPlayer
    assert(LocalPlayer, "LocalPlayer nil - run as LocalScript")
    local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

    local Network = ReplicatedStorage:FindFirstChild("Network")
    if not Network then warn("[Hate AutoFarm] ReplicatedStorage.Network missing - remotes may be missing") end

    ----------------- SAFE REMOTES -----------------
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

    ----------------- UTIL -----------------
    local function safe_delay(t,f) if type(t)=="number" and type(f)=="function" then task.delay(t,f) end end
    local function safeNumber(x) if type(x)=="number" then return x elseif type(x)=="string" then return tonumber(x) or 0 end return 0 end
    local function trim(s) return tostring(s):match("^%s*(.-)%s*$") or "" end

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
        for i=1, math.min(maxEquip, #all) do
            if all[i] and all[i].uid then table.insert(chosen, all[i].uid) end
        end
        return chosen
    end

    ----------------- STATE -----------------
    local SelectedWorld = "Spawn"
    local SelectedArea = "Town"
    local TargetNearestType = "Any"

    local Enabled = false      -- Normal autofarm
    local SafeEnabled = false  -- Safe mode
    local BlatantEnabled = false -- Blatant mode
    local NearestEnabled = false -- Target nearest

    local trackedPets = {}
    local petToTarget = {}
    local targetToPet = {}
    local petCooldowns = {}
    local blatantlyAssignedTargets = {}

    ----------------- ASSIGN HELPERS -----------------
    local function ClearAssignmentForPet(uid)
        if not uid then return end
        local t = petToTarget[uid]
        if t then petToTarget[uid] = nil; targetToPet[t] = nil end
        petCooldowns[uid] = tick() + RETARGET_DELAY
    end

    local function FreeStaleAssignments(coins)
        local present = {}
        if coins then for id,_ in pairs(coins) do present[id] = true end end
        for uid, tid in pairs(petToTarget) do
            if not present[tid] then ClearAssignmentForPet(uid) end
        end
        for tId,_ in pairs(blatantlyAssignedTargets) do
            if not present[tId] then blatantlyAssignedTargets[tId] = nil end
        end
    end

    local function GetAvailableBreakablesInArea(coins)
        local out = {}
        if not coins then return out end
        for id, item in pairs(coins) do
            if type(item) == "table" then
                local w = item.w or item.world
                local a = item.a or item.area
                if tostring(w) == tostring(SelectedWorld) and tostring(a):lower() == tostring(SelectedArea):lower() then
                    if not targetToPet[id] then table.insert(out, {id = id, data = item}) end
                end
            end
        end
        return out
    end

    local function AssignPetToBreakable(petUID, breakId, safeMode)
        if not petUID or not breakId then return false end
        if safeMode then
            local j = JOIN_DELAY + math.random(80,220)/1000
            local c = CHANGE_DELAY + math.random(80,220)/1000
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

    local function FillAssignments_NormalOrSafe(coins, safeMode)
        local petUIDs = (function()
            local u = {}
            local save = GetSave()
            if save and save.Pets then
                for _, p in pairs(save.Pets) do
                    if type(p)=="table" and p.uid and (p.equipped==true or p.eq==true or p[1]==true or p["1"]==true) then table.insert(u,p.uid) end
                end
            end
            if #u==0 then return pickTopNFromSave() end
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

        local available = GetAvailableBreakablesInArea(coins)
        if #available == 0 then return end

        local maxPerCycle = safeMode and MAX_ASSIGN_PER_CYCLE_SAFE or MAX_ASSIGN_PER_CYCLE
        local count = math.min(maxPerCycle, #freePets, #available)
        for i=1,count do
            local pet = freePets[i]
            local target = available[i]
            if pet and target and target.id then
                pcall(function() AssignPetToBreakable(pet, target.id, safeMode) end)
                task.wait(safeMode and (0.12 + math.random(0,120)/1000) or (0.02 + math.random(0,40)/1000))
            end
        end
    end

    local function FillAssignments_Blatant(coins)
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
        local available = GetAvailableBreakablesInArea(coins)
        if #available == 0 then return end

        local iPet, iAvail = 1,1
        while iPet <= #freePets and iAvail <= #available do
            local pet = freePets[iPet]; local target = available[iAvail]
            if pet and target and target.id and not blatantlyAssignedTargets[target.id] then
                pcall(function()
                    AssignPetToBreakable(pet, target.id, false)
                    blatantlyAssignedTargets[target.id] = true
                end)
                iPet = iPet + 1; iAvail = iAvail + 1
                task.wait(0.01)
            else
                iAvail = iAvail + 1
            end
        end
    end

    local function matchesTargetType(targetType, coinData)
        if not targetType or targetType == "Any" then return true end
        if not coinData then return false end
        local name = tostring(coinData.n or coinData.name or ""):lower()
        if targetType == "Coins" then return name:find("coin") or name:find("coins") end
        if targetType == "Diamonds" then return name:find("diamond") or name:find("gem") or name:find("ruby") end
        if targetType == "Chests" then return name:find("chest") or name:find("crate") or name:find("vault") end
        if targetType == "Breakables" then return not (name:find("orb") or name=="") end
        return true
    end

    local function TargetNearest_All(coins)
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

    ----------------- RAYFIELD LOADER -----------------
    local Rayfield = nil
    local successLoad, resLoad = pcall(function()
        return loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
    end)
    if successLoad and type(resLoad) == "table" then Rayfield = resLoad end
    if not Rayfield then
        local ok2, res2 = pcall(function()
            return loadstring(game:HttpGet("https://raw.githubusercontent.com/Exunys/Rayfield/main/source.lua"))()
        end)
        if ok2 and type(res2) == "table" then Rayfield = res2 end
    end
    if not Rayfield then warn("[Hate AutoFarm] Rayfield loader failed - GUI won't be created") end

    ----------------- BUILD UI -----------------
    local UI = {}
    local areaDropdownObj, worldDropdownObj, targetTypeDropdownObj, eggDropdownObj
    local toggleObjects = {}

    if Rayfield then
        local Window = Rayfield:CreateWindow({
            Name = "Hate's Quality of Life",
            LoadingTitle = "Hate's QOL",
            LoadingSubtitle = "Autofarm",
            ConfigurationSaving = {Enabled = true, FolderName = "HateQOL", FileName = "config"},
            KeySystem = false
        })

        -- tabs
        local TabAF = Window:CreateTab("Autofarm")
        local TabTarget = Window:CreateTab("Targeting")
        local TabStatus = Window:CreateTab("Status")
        local TabExtras = Window:CreateTab("Extras")

        -- Autofarm toggles (mutually exclusive)
        local tStart = TabAF:CreateToggle({Name="Auto Farm (Normal)", CurrentValue=false, Flag="auto_normal", Callback=function(val)
            if val then
                -- turn off others
                SafeEnabled = false; BlatantEnabled = false
                pcall(function() toggleObjects.safe:Set(false) end)
                pcall(function() toggleObjects.blatant:Set(false) end)
            end
            Enabled = val
        end})
        toggleObjects.normal = tStart

        local tSafe = TabAF:CreateToggle({Name="Safe Mode", CurrentValue=false, Flag="auto_safe", Callback=function(val)
            if val then
                Enabled = false; BlatantEnabled = false
                pcall(function() toggleObjects.normal:Set(false) end)
                pcall(function() toggleObjects.blatant:Set(false) end)
            end
            SafeEnabled = val
        end})
        toggleObjects.safe = tSafe

        local tBlatant = TabAF:CreateToggle({Name="Blatant Mode", CurrentValue=false, Flag="auto_blatant", Callback=function(val)
            if val then
                Enabled = false; SafeEnabled = false
                pcall(function() toggleObjects.normal:Set(false) end)
                pcall(function() toggleObjects.safe:Set(false) end)
            end
            BlatantEnabled = val
        end})
        toggleObjects.blatant = tBlatant

        TabAF:CreateButton({Name="Pick & Equip Best", Callback=function()
            local chosen = pickTopNFromSave()
            if #chosen == 0 then Rayfield:Notify({Title="Equip", Content="No pets found.", Duration=3}) return end
            trackedPets = chosen
            for _, uid in ipairs(trackedPets) do pcall(function() EquipPet(uid) end); task.wait(0.06) end
            task.wait(EQUIP_WAIT)
            Rayfield:Notify({Title="Equip", Content=("Equipped %d pets"):format(#trackedPets), Duration=2})
        end})

        TabAF:CreateButton({Name="Stop All", Callback=function()
            Enabled = false; SafeEnabled = false; BlatantEnabled = false; NearestEnabled = false
            pcall(function() toggleObjects.normal:Set(false) end)
            pcall(function() toggleObjects.safe:Set(false) end)
            pcall(function() toggleObjects.blatant:Set(false) end)
            pcall(function() toggleObjects.nearest:Set(false) end)
            petToTarget = {}; targetToPet = {}; petCooldowns = {}; blatantlyAssignedTargets = {}
            Rayfield:Notify({Title="Stop", Content="All modes stopped", Duration=2})
        end})

        -- Target Nearest section in targeting tab
        local tNearest = TabTarget:CreateToggle({Name="Target Nearest (All Pets)", CurrentValue=false, Flag="target_nearest", Callback=function(val)
            if val then
                -- pause other farm modes
                Enabled, SafeEnabled, BlatantEnabled = false, false, false
                pcall(function() toggleObjects.normal:Set(false) end)
                pcall(function() toggleObjects.safe:Set(false) end)
                pcall(function() toggleObjects.blatant:Set(false) end)
            end
            NearestEnabled = val
        end})
        toggleObjects.nearest = tNearest

        targetTypeDropdownObj = TabTarget:CreateDropdown({Name="Target Type", Options=TargetTypeOptions, CurrentOption="Any", Flag="target_type", Callback=function(opt)
            TargetNearestType = opt
        end})

        -- World / Area dynamic dropdowns (Targeting tab)
        worldDropdownObj = TabTarget:CreateDropdown({
            Name = "World",
            Options = (function() local t={} for k,_ in pairs(WorldsTable) do table.insert(t,k) end; table.sort(t); return t end)(),
            CurrentOption = SelectedWorld,
            Flag = "world_select",
            Callback = function(opt)
                SelectedWorld = opt or SelectedWorld
                -- update area dropdown options dynamically
                local areas = WorldsTable[SelectedWorld] or {}
                local current = areas[1] or ""
                pcall(function()
                    -- Rayfield dropdown object should support Set or SetOptions
                    if areaDropdownObj and areaDropdownObj.Set then
                        areaDropdownObj:Set({Options = areas, CurrentOption = current})
                    elseif areaDropdownObj and areaDropdownObj.UpdateOptions then
                        areaDropdownObj:UpdateOptions(areas)
                    else
                        TabTarget.Flags["area_select"] = current
                    end
                end)
                SelectedArea = current
            end
        })

        areaDropdownObj = TabTarget:CreateDropdown({
            Name = "Area",
            Options = (WorldsTable[SelectedWorld] or {}),
            CurrentOption = SelectedArea,
            Flag = "area_select",
            Callback = function(opt)
                SelectedArea = opt or SelectedArea
                -- clear assignments so pets retarget into new area
                petToTarget = {}; targetToPet = {}; petCooldowns = {}
            end
        })

        -- Status tab
        local statusLabel = TabStatus:CreateLabel(("Status: Idle\nMode: None\nWorld/Area: %s - %s\nPets Equipped: 0"):format(tostring(SelectedWorld), tostring(SelectedArea)))
        UI.StatusLabel = statusLabel

        -- Extras tab: placeholders + auto hatch
        TabExtras:CreateSection("Auto Upgrade (placeholders)")
        TabExtras:CreateLabel("Auto Fuse (placeholder)")
        TabExtras:CreateLabel("Auto Gold (placeholder)")
        TabExtras:CreateLabel("Auto Rainbow (placeholder)")
        TabExtras:CreateLabel("Auto Dark Matter (placeholder)")

        TabExtras:CreateSection("Auto Hatch (Eggs)")
        eggDropdownObj = TabExtras:CreateDropdown({Name="Egg Type", Options={"Refresh to load"}, CurrentOption="", Flag="egg_select", Callback=function(opt) end})
        TabExtras:CreateButton({Name="Refresh Egg List", Callback=function()
            -- try to detect eggs in ReplicatedStorage or produce a default list
            local list = {}
            local eggsRoot = ReplicatedStorage:FindFirstChild("Eggs") or ReplicatedStorage:FindFirstChild("EggsFolder") or ReplicatedStorage
            if eggsRoot then
                for _,child in ipairs(eggsRoot:GetChildren()) do
                    if child.Name and #tostring(child.Name)>0 then table.insert(list, child.Name) end
                end
            end
            if #list == 0 then table.insert(list, "Starter Egg"); table.insert(list, "Valentines Egg") end
            pcall(function() if eggDropdownObj and eggDropdownObj.Set then eggDropdownObj:Set({Options = list, CurrentOption = list[1]}) end end)
            Rayfield:Notify({Title="Egg List", Content=("Loaded %d entries"):format(#list), Duration=2})
        end})
        local eggAmountBox = TabExtras:CreateTextBox({Name="Amount to Open", Value="1", Flag="egg_amount", Callback=function(val end})
        local tEggToggle = TabExtras:CreateToggle({Name="Start Auto Hatch", CurrentValue=false, Flag="auto_hatch", Callback=function(val)
            -- stub: toggle; actual hatch routine runs in background loop below if enabled
        end})

        -- hotkey to toggle Rayfield window
        Window:CreateKeybind({Name="Toggle UI (RightControl)", CurrentKeybind=Enum.KeyCode.RightControl, HoldToInteract=false, Callback=function() pcall(function() Window:Toggle() end) end})

        -- store references
        UI.Window = Window
        UI.Rayfield = Rayfield
        UI.WorldDropdown = worldDropdownObj
        UI.AreaDropdown = areaDropdownObj
        UI.TargetDropdown = targetTypeDropdownObj
        UI.EggDropdown = eggDropdownObj
        UI.ToggleObjects = toggleObjects
    end -- if Rayfield

    ----------------- Mobile restore button (always visible when minimized) -----------------
    local restoreGui = Instance.new("ScreenGui")
    restoreGui.Name = "HateRestoreGui"
    restoreGui.ResetOnSpawn = false
    restoreGui.Parent = PlayerGui

    local restoreBtn = Instance.new("TextButton")
    restoreBtn.Size = UDim2.new(0, 34, 0, 34)
    restoreBtn.Position = UDim2.new(0, 6, 0, 42)
    restoreBtn.AnchorPoint = Vector2.new(0,0)
    restoreBtn.Text = "H"
    restoreBtn.Font = Enum.Font.SourceSansBold
    restoreBtn.TextSize = 18
    restoreBtn.BackgroundColor3 = Color3.fromRGB(10,10,10)
    restoreBtn.TextColor3 = Color3.new(1,1,1)
    restoreBtn.Name = "HateRestoreBtn"
    restoreBtn.Parent = restoreGui
    restoreBtn.AutoButtonColor = true

    -- draggable restoreBtn
    do
        local dragging, dragInput, dragStart, startPos
        restoreBtn.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = true; dragStart = input.Position; startPos = restoreBtn.Position
                input.Changed:Connect(function() if input.UserInputState == Enum.UserInputState.End then dragging = false end end)
            end
        end)
        restoreBtn.InputChanged:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseMovement then dragInput = input end end)
        UserInputService.InputChanged:Connect(function(input)
            if input == dragInput and dragging and dragStart and startPos then
                local delta = input.Position - dragStart
                restoreBtn.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            end
        end)
    end

    restoreBtn.MouseButton1Click:Connect(function()
        if UI and UI.Window and UI.Window.Toggle then pcall(function() UI.Window:Toggle() end) else print("[Hate AutoFarm] Rayfield window toggle not available") end
    end)

    ----------------- ANTI-AFK (non-evasive) -----------------
    do
        local vu = nil
        pcall(function() vu = game:GetService("VirtualUser") end)
        if vu then
            Players.LocalPlayer.Idled:Connect(function()
                vu:Button2Down(Vector2.new(0,0)); task.wait(0.1); vu:Button2Up(Vector2.new(0,0))
            end)
        else
            Players.LocalPlayer.Idled:Connect(function()
                pcall(function()
                    local uis = game:GetService("UserInputService")
                    uis.MouseIconEnabled = not uis.MouseIconEnabled
                    task.wait(0.05)
                    uis.MouseIconEnabled = not uis.MouseIconEnabled
                end)
            end)
        end
    end

    ----------------- BACKGROUND LOOP -----------------
    task.spawn(function()
        while true do
            -- update status label (Rayfield)
            pcall(function()
                if UI and UI.StatusLabel then
                    local mode = "None"
                    if Enabled then mode = "Normal" elseif SafeEnabled then mode = "Safe" elseif BlatantEnabled then mode = "Blatant" elseif NearestEnabled then mode = "Nearest" end
                    local petsCount = #trackedPets
                    UI.StatusLabel:SetText(("Status: %s\nMode: %s\nWorld/Area: %s - %s\nPets Equipped: %d"):format( (Enabled or SafeEnabled or BlatantEnabled or NearestEnabled) and "Farming" or "Idle", mode, tostring(SelectedWorld), tostring(SelectedArea), petsCount ) )
                end
            end)

            -- if Nearest enabled, pause other modes and run nearest
            if NearestEnabled then
                -- ensure pets equipped
                if #trackedPets == 0 then
                    trackedPets = pickTopNFromSave()
                    for _, uid in ipairs(trackedPets) do pcall(function() EquipPet(uid) end); task.wait(0.06) end
                    task.wait(EQUIP_WAIT)
                end
                local coins = GetCoinsRaw()
                if coins then FreeStaleAssignments(coins) end
                if coins then TargetNearest_All(coins) end
                pcall(function() ClaimOrbs({}) end)
                task.wait(0.45 + math.random(0,200)/1000)
                continue
            end

            -- Normal mode
            if Enabled then
                if #trackedPets == 0 then
                    trackedPets = pickTopNFromSave()
                    for _, uid in ipairs(trackedPets) do pcall(function() EquipPet(uid) end); task.wait(0.06) end
                    task.wait(EQUIP_WAIT)
                end
                local coins = GetCoinsRaw()
                if coins then
                    FreeStaleAssignments(coins)
                    FillAssignments_NormalOrSafe(coins, false)
                    pcall(function() ClaimOrbs({}) end)
                end
            end

            -- Safe mode
            if SafeEnabled then
                if #trackedPets == 0 then
                    trackedPets = pickTopNFromSave()
                    for _, uid in ipairs(trackedPets) do pcall(function() EquipPet(uid) end); task.wait(0.09 + math.random(0,80)/1000) end
                    task.wait(EQUIP_WAIT + 0.1)
                end
                local coins = GetCoinsRaw()
                if coins then
                    FreeStaleAssignments(coins)
                    FillAssignments_NormalOrSafe(coins, true)
                    pcall(function() ClaimOrbs({}) end)
                end
                task.wait(SAFE_LOOP_DELAY + math.random(0,200)/1000)
            end

            -- Blatant mode
            if BlatantEnabled then
                if #trackedPets == 0 then
                    trackedPets = pickTopNFromSave()
                    for _, uid in ipairs(trackedPets) do pcall(function() EquipPet(uid) end); task.wait(0.04) end
                    task.wait(EQUIP_WAIT)
                end
                local coins = GetCoinsRaw()
                if coins then
                    FreeStaleAssignments(coins)
                    FillAssignments_Blatant(coins)
                    pcall(function() ClaimOrbs({}) end)
                end
                task.wait(0.30 + math.random(0,200)/1000)
            end

            -- Auto Hatch runner (simple)
            -- if the toggle exists, find egg type and amount and call Buy Egg remote repeatedly (basic)
            -- NOTE: This is a generic handler and may require adaptation to your game's remotes.
            pcall(function()
                if Rayfield and TabExtras and TabExtras.Flags and TabExtras.Flags["auto_hatch"] then
                    local hatchOn = TabExtras.Flags["auto_hatch"]
                    if hatchOn then
                        local egg = TabExtras.Flags["egg_select"] or (eggDropdownObj and eggDropdownObj:GetCurrentOption and eggDropdownObj:GetCurrentOption()) or nil
                        local amt = tonumber(TabExtras.Flags["egg_amount"]) or 1
                        if egg and amt > 0 then
                            -- try to find Buy Egg remote
                            local rem = Network and Network:FindFirstChild("Buy Egg")
                            if rem and rem.ClassName == "RemoteFunction" then
                                -- spawn a small task so we don't lock the main loop
                                task.spawn(function()
                                    for i=1, amt do
                                        pcall(function() rem:InvokeServer(egg, false, true) end)
                                        task.wait(0.25 + math.random(0,200)/1000)
                                    end
                                end)
                            end
                        end
                    end
                end
            end)

            task.wait(MAIN_LOOP_DELAY + math.random(0,200)/1000)
        end
    end)

    print("[Hate AutoFarm] Script loaded. Rayfield UI created (if loader succeeded).")

end)

if not ok then
    warn("[Hate AutoFarm] Startup error:", mainErr)
else
    print("[Hate AutoFarm] Script executed successfully!")
end
