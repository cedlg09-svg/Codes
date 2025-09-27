-- HateAF_Fluent_Integrated.lua
-- Paste into NEW LocalScript and run (Delta-safe)
-- Loads external Fluent UI, provides an always-visible 50x50 toggle button (top-center),
-- remembers last tab, and integrates autofarm logic (area-only, one pet per breakable, modes).

-- Delta-safe bootstrap (avoid line1 errors; prevent server execution)
if not game or not game:IsLoaded() then repeat task.wait() until game and game:IsLoaded() end
local RunService = game:GetService("RunService")
if RunService:IsServer() then return end

local ok, mainErr = pcall(function()
    -- ============ CONFIG ============
    local FLUENT_URL = "https://raw.githubusercontent.com/dawid-scripts/Fluent/releases/latest/download/main.lua"
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

    -- ============ SERVICES & STATE ============
    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local Workspace = game:GetService("Workspace")
    local UserInput = game:GetService("UserInputService")
    local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()
    local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

    local Network = ReplicatedStorage:FindFirstChild("Network")
    if not Network then warn("[HateAF] ReplicatedStorage.Network not found. Remotes may be missing.") end

    local SelectedWorld = "Spawn"
    local SelectedArea = WorldsTable["Spawn"] and WorldsTable["Spawn"][1] or ""
    local TargetType = "Any"
    local Mode = "None" -- Normal, Safe, Blatant, NearestArea, NearestGlobal
    local Enabled = false
    local SlowMode = false

    local trackedPets = {}
    local petToTarget = {}
    local targetToPet = {}
    local petCooldowns = {}
    local brokenCount = 0
    local startTime = 0

    -- ============ REMOTE HELPERS ============
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

    -- ============ UTILITIES ============
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

    -- ============ ASSIGN / FARM HELPERS ============
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

    -- ============ EGG ANIMATION DISABLE (one-shot) ============
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

    -- ============ ANTI-AFK (one-shot) ============
    pcall(function()
        local vu = game:GetService("VirtualUser")
        Players.LocalPlayer.Idled:Connect(function()
            vu:Button2Down(Vector2.new(0,0), workspace.CurrentCamera)
            task.wait(1)
            vu:Button2Up(Vector2.new(0,0), workspace.CurrentCamera)
        end)
    end)

    -- ============ LOAD FLUENT UI & BUILD INTERFACE ============
    local FluentLib = nil
    local loadOk, loadErr = pcall(function()
        FluentLib = loadstring(game:HttpGet(FLUENT_URL, true))()
    end)
    if not loadOk or not FluentLib then
        warn("[HateAF] Failed to load Fluent UI library:", loadErr)
    end

    -- helper to try find the Fluent ScreenGui for toggling visibility (many libs parent to PlayerGui or CoreGui)
    local function findFluentScreenGui(windowTitle)
        -- search PlayerGui, CoreGui
        local function findIn(root)
            for _, child in ipairs(root:GetChildren()) do
                if child:IsA("ScreenGui") then
                    -- try to detect by title label text inside gui
                    for _, d in ipairs(child:GetDescendants()) do
                        if d:IsA("TextLabel") and tostring(d.Text or ""):find(windowTitle, 1, true) then
                            return child
                        end
                    end
                end
            end
            return nil
        end
        local g = findIn(PlayerGui)
        if g then return g end
        local core = game:GetService("CoreGui")
        g = findIn(core)
        if g then return g end
        return nil
    end

    -- Build UI with Fluent if available; otherwise minimal fallback
    local Window, Tabs, StatusLabel
    local lastTabIndex = 1
    if FluentLib and type(FluentLib.CreateWindow) == "function" then
        -- create window
        Window = FluentLib:CreateWindow({
            Title = "Hate's QoL",
            SubTitle = "Hate AF",
            Size = UDim2.fromOffset(720, 480),
            Acrylic = false,
            Theme = "Dark"
        })

        -- build tabs
        Tabs = {
            Main = Window:AddTab({ Title = "Main", Icon = "" }),
            Targeting = Window:AddTab({ Title = "Targeting", Icon = "" }),
            Egg = Window:AddTab({ Title = "Egg", Icon = "" }),
            Upgrades = Window:AddTab({ Title = "Upgrades", Icon = "" })
        }

        -- Status label (top of Main)
        Tabs.Main:AddParagraph({ Title = "Status", Content = "Status: Idle\nTime: 00:00\nBroken: 0" })
        StatusLabel = Tabs.Main -- we'll update via SetContent on Main's paragraph if available

        -- Main tab content: buttons (left) and world/area/target (right)
        Tabs.Main:AddButton({
            Title = "Pick Best Pets",
            Description = "Equip best pets from save",
            Callback = function()
                local ok = pcall(function()
                    local chosen = pickTopNFromSave()
                    if #chosen == 0 then
                        -- update status
                        pcall(function() Tabs.Main:AddParagraph({ Title = "Status", Content = "No pets found." }) end)
                        return
                    end
                    trackedPets = chosen
                    for _, uid in ipairs(trackedPets) do pcall(function() EquipPet(uid) end); task.wait(0.06) end
                end)
            end
        })

        Tabs.Main:AddButton({
            Title = "Equip Best (Remote)",
            Description = "Ask server to equip best pets",
            Callback = function()
                local ok = EquipBestPetsRemote()
                pcall(function() Tabs.Main:AddParagraph({ Title = "Status", Content = ok and "Requested remote equip." or "Remote equip failed." }) end)
            end
        })

        -- Mode section: create toggles using AddToggle if present
        local modes = {"Normal","Safe","Blatant","NearestArea","NearestGlobal"}
        for _, m in ipairs(modes) do
            Tabs.Main:AddToggle(m, {
                Text = m,
                Default = false
            }, function(state)
                if state then
                    Mode = m
                    -- ensure other toggles off: best-effort (Fluent might provide API to set toggles directly)
                    -- we simply track Mode variable; UI stay as chosen
                else
                    if Mode == m then Mode = "None" end
                end
            end)
        end

        Tabs.Main:AddToggle("SlowMode", { Text = "Slow Mode", Default = false }, function(s) SlowMode = s end)

        -- right-side controls: world/area/target; Fluent AddDropdown returns object with SetValue available
        local worldList = {}
        for k,_ in pairs(WorldsTable) do table.insert(worldList, k) end
        table.sort(worldList)

        Tabs.Main:AddDropdown("World", worldList, false, function(v)
            SelectedWorld = tostring(v or "")
            local areas = WorldsTable[SelectedWorld] or {}
            local first = areas[1]
            SelectedArea = first or ""
            -- refresh area dropdown:
            -- attempt to find area dropdown object and SetValue
            -- Fluent dropdown set handled by API's OnChanged callback; we will re-create area dropdown below
        end)

        -- We'll add Area dropdown after World so we can reference it
        Tabs.Main:AddDropdown("Area", WorldsTable[SelectedWorld] or {}, false, function(v)
            SelectedArea = tostring(v or "")
        end)

        Tabs.Main:AddDropdown("Target Type", TargetTypeOptions, false, function(v)
            TargetType = tostring(v or "Any")
        end)

        Tabs.Main:AddButton({ Title = "Refresh Areas", Description = "Reload areas for selected world", Callback = function()
            -- find world selection (we'll re-generate area dropdown in the simplest safe way by re-adding dropdown)
            -- Fluent doesn't always expose direct API to mutate options; best-effort: re-create or set Value if API present
            -- We'll attempt to set Area via selecting first area in WorldsTable
            local areas = WorldsTable[SelectedWorld] or {}
            SelectedArea = areas[1] or ""
            pcall(function() Tabs.Main:AddParagraph({ Title = "Status", Content = ("Areas refreshed. First area: %s"):format(SelectedArea) }) end)
        end })

        Tabs.Targeting:AddDropdown("Target Mode", {"Nearest","Strongest","Random","All"}, false, function(choice)
            -- set targeting sub-mode (Nearest uses Mode toggles anyway)
            pcall(function() Tabs.Targeting:AddParagraph({ Title = "Targeting", Content = ("Mode: %s"):format(choice) }) end)
        end)

        Tabs.Egg:AddButton({ Title = "Disable Egg Hatching Animation (one-shot)", Description = "Try to disable via getgc", Callback = function()
            local ok = disableEggAnimationOnce()
            pcall(function() Tabs.Egg:AddParagraph({ Title = "Egg", Content = ok and "Egg animation removed." or "Already disabled." }) end)
        end })

        Tabs.Upgrades:AddLabel = Tabs.Upgrades.AddLabel or function(_,t) Tabs.Upgrades:AddParagraph({ Title = t, Content = "" }) end
        Tabs.Upgrades:AddLabel("Auto Fuse (placeholder)")
        Tabs.Upgrades:AddLabel("Auto Gold (placeholder)")
        Tabs.Upgrades:AddLabel("Auto Rainbow (placeholder)")
        Tabs.Upgrades:AddLabel("Auto Dark Matter (placeholder)")

        -- select first tab by default
        Window:SelectTab(1)
    else
        -- fallback minimal UI if Fluent failed: create small ScreenGui and basic controls
        local gui = Instance.new("ScreenGui", PlayerGui)
        gui.Name = "HateQoL_Fallback"
        local frame = Instance.new("Frame", gui)
        frame.Size = UDim2.new(0,400,0,300)
        frame.Position = UDim2.new(0,8,0,36)
        frame.BackgroundColor3 = Color3.fromRGB(18,18,18)
        Instance.new("UICorner", frame).CornerRadius = UDim.new(0,6)
        local lab = Instance.new("TextLabel", frame)
        lab.Size = UDim2.new(1, -16, 0, 20)
        lab.Position = UDim2.new(0,8,0,6)
        lab.BackgroundTransparency = 1
        lab.Text = "Hate's QoL (Fallback)"
        lab.TextColor3 = Color3.new(1,1,1)
        -- VERY minimal because Fluent missing
        warn("[HateAF] Fluent UI not available; fallback UI created (limited).")
    end

    -- ============ ALWAYS-VISIBLE TOGGLE BUTTON (50x50 top-center) ============
    local toggleGui = Instance.new("ScreenGui", PlayerGui)
    toggleGui.Name = "HateQoL_Toggle"
    toggleGui.ResetOnSpawn = false
    local toggleBtn = Instance.new("TextButton", toggleGui)
    toggleBtn.Size = UDim2.new(0,50,0,50)
    toggleBtn.Position = UDim2.new(0.5, -25, 0, 6) -- top-center
    toggleBtn.AnchorPoint = Vector2.new(0.5, 0)
    toggleBtn.Text = "Hate"
    toggleBtn.Font = Enum.Font.SourceSansBold
    toggleBtn.TextSize = 16
    toggleBtn.TextColor3 = Color3.new(1,1,1)
    toggleBtn.BackgroundColor3 = Color3.fromRGB(20,20,20)
    toggleBtn.ZIndex = 9999
    Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0,6)

    -- helper to find the Fluent ScreenGui inserted by the library (by window title)
    local function resolveFluentGui()
        local title = "Hate's QoL"
        local sg = findFluentScreenGui(title)
        return sg
    end

    local function setFluentVisible(visible)
        -- attempt to hide/show Fluent's ScreenGui if found; else attempt Window:Hide / Window:Show if available
        local sg = resolveFluentGui()
        if sg then
            sg.Enabled = visible
            return true
        end
        -- try Window API
        if Window then
            if visible and type(Window.Show) == "function" then
                pcall(Window.Show, Window)
                return true
            elseif not visible and type(Window.Hide) == "function" then
                pcall(Window.Hide, Window)
                return true
            end
            -- many libs don't have show/hide; try toggling container property if present
            if Window.Container and Window.Container.Parent and Window.Container.Visible ~= nil then
                Window.Container.Visible = visible
                return true
            end
        end
        return false
    end

    local currentlyVisible = true
    toggleBtn.MouseButton1Click:Connect(function()
        currentlyVisible = not currentlyVisible
        setFluentVisible(currentlyVisible)
        -- when showing, restore last tab if Fluent exposes SelectTab
        if currentlyVisible and Window and type(Window.SelectTab) == "function" and lastTabIndex then
            pcall(function() Window:SelectTab(lastTabIndex) end)
        end
    end)

    -- track tab selection for remembering lastTabIndex (best-effort)
    if Window and type(Window.AddTab) ~= "nil" then
        -- Fluent does not necessarily provide tab selection hook in same API - attempt to attach to Window.SelectTab method calls:
        local oldSelect = Window.SelectTab
        if type(oldSelect) == "function" then
            Window.SelectTab = function(self, idx)
                lastTabIndex = idx or lastTabIndex
                return pcall(oldSelect, self, idx)
            end
        end
    end

    -- ============ STATUS / UPDATER ============
    local function updateStatusLabel()
        local elapsed = (startTime>0) and math.floor(tick()-startTime) or 0
        local tstr = string.format("%02d:%02d", math.floor(elapsed/60), elapsed%60)
        local s = ("Mode:%s | World:%s | Area:%s | Pets:%d | Broken:%d | Time:%s"):format(Mode, SelectedWorld, SelectedArea, #trackedPets, brokenCount, tstr)
        -- try to update Fluent paragraph: simplistic attempt by adding a paragraph (Fluent will handle duplicates)
        if FluentLib and Window and Window.AddTab then
            pcall(function()
                -- attempt to change main tab paragraph content using known API (best-effort)
                -- Not all Fluent versions expose a direct 'SetContent' function; fallback: add paragraph (harmless)
                Window:SelectTab(1)
                Tabs.Main:AddParagraph({ Title = "Status", Content = s })
            end)
        else
            -- fallback: print
            -- (In fallback UI we created nothing dynamic.)
        end
    end

    task.spawn(function()
        while true do
            pcall(updateStatusLabel)
            task.wait(0.8)
        end
    end)

    -- ============ MAIN FARM LOOP ============
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

    -- expose console message
    print("[HateAF] Fluent UI loaded (if available). Toggle button top-center created. Autofarm core running (disabled by default).")
end)

if not ok then
    warn("[HateAF] Startup error:", mainErr)
else
    print("[HateAF] Script executed successfully!")
end
