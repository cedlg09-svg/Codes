-- Hate's Autofarm (Rayfield UI) - full script
-- Paste into a NEW LocalScript and run (local environment)

local ok, mainErr = pcall(function()

    -- ======= CONFIG =======
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

    -- ======= SERVICES =======
    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local Workspace = game:GetService("Workspace")
    local UserInputService = game:GetService("UserInputService")
    local LocalPlayer = Players.LocalPlayer
    assert(LocalPlayer, "LocalPlayer nil - run as LocalScript")
    local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

    local Network = ReplicatedStorage:FindFirstChild("Network")
    if not Network then
        warn("[Hate AF] ReplicatedStorage.Network not found.")
    end

    -- ======= SAFE REMOTE CALLER =======
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
    local function safe_delay(t, f) if type(t) == "number" and type(f) == "function" then task.delay(t, f) end end
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

    -- ======= ASSIGN HELPERS =======
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
        for i=1,count do
            local pet = freePets[i]; local t = avail[i]
            if pet and t and t.id then pcall(function() AssignPetToBreakable(pet, t.id, false) end); task.wait(SAFE_DELAY_BETWEEN_ASSIGN) end
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
        for i=1,count do local pet = freePets[i]; local t = avail[i]; if pet and t and t.id then pcall(function() AssignPetToBreakable(pet, t.id, true) end); task.wait(0.3 + math.random(0,300)/1000) end end
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
        local iPet,iAvail = 1,1
        while iPet <= #freePets and iAvail <= #avail do
            local pet = freePets[iPet]; local t = avail[iAvail]
            if pet and t and t.id then pcall(function() AssignPetToBreakable(pet, t.id, false) end); iPet=iPet+1; iAvail=iAvail+1; task.wait(0.01) else iAvail=iAvail+1 end
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

    -- ======= ANTI AFK (run once) =======
    pcall(function()
        local vu = game:GetService("VirtualUser")
        Players.LocalPlayer.Idled:Connect(function()
            vu:Button2Down(Vector2.new(0,0), workspace.CurrentCamera)
            task.wait(1)
            vu:Button2Up(Vector2.new(0,0), workspace.CurrentCamera)
        end)
    end)

    -- ======= RAYFIELD UI LOADING =======
    local Rayfield
    local success, lib = pcall(function()
    return loadstring(game:HttpGet("https://raw.githubusercontent.com/SiriusSoftwareLtd/Rayfield/main/source.lua"))()
end)
    if success and type(lib) == "table" then Rayfield = lib else Rayfield = nil warn("[Hate AF] Rayfield failed to load; UI will fallback to simple print/status only.") end

    -- ======= UI & CONTROL HOOKS =======
    local uiHandles = {}
    local function createFallbackUI()
        -- minimal fallback UI (if Rayfield fails) - prints status and exposes simple Buttons
        print("[Hate AF] Rayfield not available — running in fallback mode.")
        -- We'll still allow toggling modes via commands in the output (not ideal but safe)
    end

    if Rayfield then
        local Window = Rayfield:CreateWindow({
            Name = "Hate's Autofarm",
            LoadingTitle = "Hate's Autofarm",
            LoadingSubtitle = "Quality Of Life",
            ConfigurationSaving = {Enabled=false, FolderName=nil, FileName=nil},
            KeySystem = false
        })

        local mainTab = Window:CreateTab("Hate' Quality Of Life")
        local statusSection = mainTab:CreateSection("Status")
        local statusLabel = mainTab:CreateLabel(("Mode: %s | World: %s | Area: %s | Pets: %d"):format(Mode, SelectedWorld, SelectedArea, #trackedPets))
        local controlSection = mainTab:CreateSection("Autofarm Controls")
        local pickBtn = mainTab:CreateButton({Name="Pick Best Pets", Description="", Callback=function() trackedPets = pickTopNFromSave(); for _,u in ipairs(trackedPets) do pcall(function() EquipPet(u) end); task.wait(0.06) end; task.wait(EQUIP_WAIT); statusLabel:Refresh(("Mode: %s | World: %s | Area: %s | Pets: %d"):format(Mode, SelectedWorld, SelectedArea, #trackedPets)) end})
        local equipBtn = mainTab:CreateButton({Name="Equip Best (remote)", Description="", Callback=function() local ok = EquipBestPetsRemote(); if ok then task.wait(0.6) end end})
        -- Mode toggles (mutually exclusive)
        local function setModeUI(newMode)
            Mode = newMode
            statusLabel:Refresh(("Mode: %s | World: %s | Area: %s | Pets: %d"):format(Mode, SelectedWorld, SelectedArea, #trackedPets))
            petToTarget = {}; targetToPet = {}; petCooldowns = {}
        end
        local modeSection = mainTab:CreateSection("Mode")
        local normalToggle = mainTab:CreateToggle({Name="Normal Mode", CurrentValue=false, Flag="NormalMode", Callback=function(v) if v then setModeUI("Normal") else setModeUI("None") end end})
        local safeToggle = mainTab:CreateToggle({Name="Safe Mode", CurrentValue=false, Flag="SafeMode", Callback=function(v) if v then setModeUI("Safe") else setModeUI("None") end end})
        local blatToggle = mainTab:CreateToggle({Name="Blatant Mode", CurrentValue=false, Flag="BlatMode", Callback=function(v) if v then setModeUI("Blatant") else setModeUI("None") end end})
        local nearestToggle = mainTab:CreateToggle({Name="Target Nearest (All Pets)", CurrentValue=false, Callback=function(v) if v then setModeUI("Nearest") else setModeUI("None") end end})

        -- Area selection section
        local areaSection = mainTab:CreateSection("Area Selection")
        local worldList = {}
        for k,_ in pairs(WorldsTable) do table.insert(worldList, k) end
        table.sort(worldList)
        local worldDropdown = mainTab:CreateDropdown({Name="World", Options=worldList, CurrentOption=SelectedWorld, Flag="WorldDD", Callback=function(opt)
            SelectedWorld = opt
            local areas = WorldsTable[SelectedWorld] or {}
            SelectedArea = areas[1] or ""
            -- update area dropdown options (Rayfield supports :UpdateDropdown but API varies; using CreateDropdown replacement)
            -- We'll recreate area dropdown by storing handle and updating Options through Refresh method if present.
            if uiHandles.AreaDropdown and uiHandles.AreaDropdown.UpdateOptions then
                uiHandles.AreaDropdown:UpdateOptions(areas)
                uiHandles.AreaDropdown:Set(areas[1] or "")
            end
            petToTarget = {}; targetToPet = {}; petCooldowns = {}
            statusLabel:Refresh(("Mode: %s | World: %s | Area: %s | Pets: %d"):format(Mode, SelectedWorld, SelectedArea, #trackedPets))
        end})

        -- create area dropdown and hold handle
        uiHandles.AreaDropdown = mainTab:CreateDropdown({Name="Area", Options=WorldsTable[SelectedWorld] or {}, CurrentOption=SelectedArea, Callback=function(opt) SelectedArea = opt; petToTarget = {}; targetToPet = {}; petCooldowns = {}; statusLabel:Refresh(("Mode: %s | World: %s | Area: %s | Pets: %d"):format(Mode, SelectedWorld, SelectedArea, #trackedPets)) end})

        -- Target selection
        uiHandles.TargetDropdown = mainTab:CreateDropdown({Name="Target Type", Options=TargetTypeOptions, CurrentOption=TargetNearestType, Callback=function(opt) TargetNearestType = opt end})

        -- Egg section placeholders
        local eggSection = mainTab:CreateSection("Auto Hatch / Egg Tools")
        local eggToggle = mainTab:CreateToggle({Name="Disable Egg Animation (best-effort)", CurrentValue=false, Callback=function(v)
            -- best-effort hook; non guaranteed
            if v then
                pcall(function()
                    for i,v2 in pairs(getgc and getgc(true) or {}) do
                        if type(v2) == "table" and rawget(v2, "OpenEgg") then
                            if not rawget(v2, "_OpenEgg_backup") then v2._OpenEgg_backup = v2.OpenEgg end
                            v2.OpenEgg = function() return end
                        end
                    end
                end)
            else
                pcall(function()
                    for i,v2 in pairs(getgc and getgc(true) or {}) do
                        if type(v2) == "table" and rawget(v2, "_OpenEgg_backup") then
                            v2.OpenEgg = v2._OpenEgg_backup
                            v2._OpenEgg_backup = nil
                        end
                    end
                end)
            end
        end})

        -- Placeholders area
        local placeholderSection = mainTab:CreateSection("Placeholders")
        placeholderSection:AddLabel("Auto Fuse | Auto Gold | Auto Rainbow | Auto DarkMatter (placeholders)")

        -- Minimize / restore controls (we'll hide Rayfield window by toggling visibility)
        local toggleVisibilityBtn = mainTab:CreateButton({Name="Minimize UI (show restore button)", Callback=function()
            -- Rayfield windows usually have an internal toggle; we'll instead hide the main window container if present
            -- Rayfield provides Close/hide in some forks; best-effort:
            pcall(function() Window:Hide() end)
            -- Create restore button on-screen
            if not PlayerGui:FindFirstChild("HateRestoreBtn") then
                local btn = Instance.new("TextButton", PlayerGui)
                btn.Name = "HateRestoreBtn"
                btn.Size = UDim2.new(0, 28, 0, 28)
                btn.Position = UDim2.new(0, 10, 0, 36)
                btn.Text = "H"
                btn.Font = Enum.Font.SourceSansBold
                btn.BackgroundColor3 = Color3.fromRGB(20,20,20)
                btn.TextColor3 = Color3.new(1,1,1)
                local corner = Instance.new("UICorner", btn); corner.CornerRadius = UDim.new(0,6)
                btn.MouseButton1Click:Connect(function() pcall(function() Window:Show() end); btn:Destroy() end)
            end
        end})

        -- store UI handles
        uiHandles.StatusLabel = statusLabel
        uiHandles.WorldDropdown = worldDropdown
        uiHandles.AreaDropdownHandle = uiHandles.AreaDropdown
        uiHandles.TargetDropdownHandle = uiHandles.TargetDropdown
        uiHandles.Window = Window

    else
        createFallbackUI()
    end

    -- ======= BACKGROUND FARM LOOP =======
    task.spawn(function()
        while true do
            -- update small status if possible
            if uiHandles and uiHandles.StatusLabel and type(uiHandles.StatusLabel.Refresh) == "function" then
                uiHandles.StatusLabel:Refresh(("Mode: %s | World: %s | Area: %s | Pets: %d"):format(Mode, SelectedWorld, SelectedArea, #trackedPets))
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
                task.wait(MAIN_LOOP_DELAY + 0.6 + math.random(0,300)/1000)
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

    print("[Hate AF] Script loaded. Use the Rayfield UI to control modes.")

end) -- end pcall

if not ok then
    warn("[Hate AF] Startup error:", mainErr)
else
    print("[Hate AF] Script executed successfully!")
end
