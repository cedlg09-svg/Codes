-- HateQoL_UI_Final.lua
-- Single-page 300x300 UI, stacked layout, area refresh on world select, panels (🥚/🛠️) placeholders
-- Paste into a NEW LocalScript and run in Delta (or as a LocalScript)

local ok, mainErr = pcall(function()

    -- ==== CONFIG / TIMINGS ====
    local SAFE_DELAY_BETWEEN_ASSIGN = 0.18
    local JOIN_DELAY = 0.06
    local CHANGE_DELAY = 0.04
    local MAIN_LOOP_DELAY = 0.8
    local EQUIP_WAIT = 0.45
    local RETARGET_DELAY = 0.3

    -- ==== WORLDS TABLE (static) ====
    local WorldsTable = {
        ["Spawn"] = {"Shop","Town","Forest","Beach","Mine","Winter","Glacier","Desert","Volcano","Cave","Tech Entry","VIP"},
        ["Fantasy"] = {"Fantasy Shop","Enchanted Forest","Portals","Ancient Island","Samurai Island","Candy Island","Haunted Island","Hell Island","Heaven Island","Heaven's Gate"},
        ["Tech"] = {"Tech Shop","Tech City","Dark Tech","Steampunk","Steampunk Chest Area","Alien Lab","Alien Forest","Giant Alien Chest","Glitch","Hacker Portal"},
        ["Void"] = {"The Void"},
        ["Axolotl Ocean"] = {"Axolotl Ocean","Axolotl Deep Ocean","Axolotl Cave"},
        ["Pixel"] = {"Pixel Forest","Pixel Kyoto","Pixel Alps","Pixel Vault"},
        ["Cat"] = {"Cat Paradise","Cat Backyard","Cat Taiga","Cat Throne Room"}
    }

    -- ==== SERVICES ====
    local Players = game:GetService("Players")
    local UserInput = game:GetService("UserInputService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local Workspace = game:GetService("Workspace")

    local LocalPlayer = Players.LocalPlayer
    assert(LocalPlayer, "LocalPlayer nil - run as LocalScript")
    local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

    local Network = ReplicatedStorage:FindFirstChild("Network")
    if not Network then
        warn("[HateQoL] ReplicatedStorage.Network not found. Remotes may be missing.")
    end

    -- ==== SAFE REMOTE CALLER ====
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
        local ok, _ = pcall(function() r:InvokeServer() end)
        return ok
    end

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

    -- ==== STATE ====
    local SelectedWorld = "Spawn"
    local SelectedArea = "Town"
    local Enabled = false
    local trackedPets = {}       -- list of pet UIDs (equipped)
    local petToTarget = {}      -- petUID -> targetId
    local targetToPet = {}      -- targetId -> petUID
    local petCooldowns = {}     -- petUID -> tick when allowed to reassign

    -- helper: get equipped UIDs (prefer save)
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
        -- fallback to pickTopN
        return pickTopNFromSave()
    end

    -- ===== ASSIGNMENT HELPERS (one pet per breakable limited to SelectedWorld/SelectedArea) =====
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

    -- Blatant: assign all equipped pets to nearest breakables ignoring area (all pets -> nearest)
    local function TargetNearestAll(coins)
        if not coins then return end
        local petUIDs = GetEquippedPetUIDs()
        if #petUIDs == 0 then return end
        -- build list of breakables
        local pts = {}
        for id, item in pairs(coins) do
            if type(item)=="table" and item.p and typeof(item.p)=="Vector3" then
                table.insert(pts, {id = id, pos = item.p})
            end
        end
        if #pts==0 then return end
        -- nearest function
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        for _, uid in ipairs(petUIDs) do
            -- skip if already assigned
            if not petToTarget[uid] then
                local bestId, bestDist = nil, math.huge
                for _, v in ipairs(pts) do
                    if not targetToPet[v.id] then
                        local d = (hrp.Position - v.pos).Magnitude
                        if d < bestDist then bestDist = d; bestId = v.id end
                    end
                end
                if bestId then
                    pcall(function() AssignPetToBreakable(uid, bestId) end)
                    task.wait(SAFE_DELAY_BETWEEN_ASSIGN)
                end
            end
        end
    end

    -- ==== UI helpers ====
    local function new(class, props)
        local obj = Instance.new(class)
        if props then
            for k,v in pairs(props) do
                if k == "Parent" then obj.Parent = v else
                    pcall(function() obj[k] = v end)
                end
            end
        end
        return obj
    end

    -- Simplified dropdown widget (now works with UIListLayout stacking)
    local function makeDropdown(parent, labelText, options, onSelect)
        options = options or {}
        local container = new("Frame", {Parent = parent, Size = UDim2.new(1, -20, 0, 18 + 28), BackgroundTransparency = 1})
        local label = new("TextLabel", {
            Parent = container, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.new(0, 0, 0, 0),
            BackgroundTransparency = 1, Text = labelText, Font = Enum.Font.SourceSans, TextSize = 14,
            TextColor3 = Color3.fromRGB(230,230,230), TextXAlignment = Enum.TextXAlignment.Left
        })
        local btn = new("TextButton", {
            Parent = container, Size = UDim2.new(1, 0, 0, 28), Position = UDim2.new(0, 0, 0, 18),
            Text = tostring(options[1] or "None"), Font = Enum.Font.SourceSans, TextSize = 14,
            BackgroundColor3 = Color3.fromRGB(22,22,22), TextColor3 = Color3.fromRGB(240,240,240), AutoButtonColor = true
        })
        new("UICorner", {Parent = btn, CornerRadius = UDim.new(0,6)})
        local menu = new("Frame", {Parent = container, Position = UDim2.new(0, 0, 0, 18+28), Size = UDim2.new(1, 0, 0, 0), BackgroundColor3 = Color3.fromRGB(18,18,18), Visible = false})
        new("UICorner", {Parent = menu, CornerRadius = UDim.new(0,6)})
        local layout = new("UIListLayout", {Parent = menu, Padding = UDim.new(0,4)})

        local function populate(list)
            for _,c in ipairs(menu:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
            for _, opt in ipairs(list) do
                local item = new("TextButton", {
                    Parent = menu, Size = UDim2.new(1, -8, 0, 20), Position = UDim2.new(0, 4, 0, 0),
                    Text = tostring(opt), BackgroundTransparency = 1, Font = Enum.Font.SourceSans, TextSize = 14, TextColor3 = Color3.new(1,1,1)
                })
                item.MouseButton1Click:Connect(function()
                    btn.Text = tostring(opt)
                    menu.Visible = false
                    pcall(onSelect, opt)
                end)
            end
            -- set menu height
            local h = math.min(#list * 24, 180)
            menu.Size = UDim2.new(1, 0, 0, h)
        end

        populate(options)

        btn.MouseButton1Click:Connect(function()
            menu.Visible = not menu.Visible
        end)

        return {
            Container = container,
            Button = btn,
            Menu = menu,
            SetOptions = function(newList) populate(newList or {}) end,
            SetValue = function(v) btn.Text = tostring(v or "None") end,
            GetValue = function() return btn.Text end
        }
    end

    -- ==== BUILD UI: main 300x300 single-page stacked layout ====
    local screenGui = new("ScreenGui", {Parent = PlayerGui, Name = "HateQoL_UI", ResetOnSpawn = false})
    local mainFrame = new("Frame", {
        Parent = screenGui, Size = UDim2.new(0, 300, 0, 300), Position = UDim2.new(0, 8, 0, 8),
        BackgroundColor3 = Color3.fromRGB(18,18,18), BorderSizePixel = 0
    })
    new("UICorner", {Parent = mainFrame, CornerRadius = UDim.new(0,8)})

    -- vertical layout container
    local mainLayout = new("UIListLayout", {Parent = mainFrame, Padding = UDim.new(0,8), SortOrder = Enum.SortOrder.LayoutOrder})
    local mainPadding = new("UIPadding", {Parent = mainFrame, PaddingTop = UDim.new(0,8), PaddingLeft = UDim.new(0,8), PaddingRight = UDim.new(0,8)})

    -- Top labels container (status & time & broken)
    local labelsFrame = new("Frame", {Parent = mainFrame, Size = UDim2.new(1,0,0,40), BackgroundTransparency = 1})
    local labelsLayout = new("UIListLayout", {Parent = labelsFrame, Padding = UDim.new(0,2), FillDirection = Enum.FillDirection.Vertical, SortOrder = Enum.SortOrder.LayoutOrder})
    local statusLabel = new("TextLabel", {Parent = labelsFrame, Size = UDim2.new(1,0,0,18), BackgroundTransparency = 1, Text = "Status: Idle", Font = Enum.Font.SourceSans, TextSize = 14, TextColor3 = Color3.fromRGB(220,220,220), TextXAlignment = Enum.TextXAlignment.Left})
    local timeLabel = new("TextLabel", {Parent = labelsFrame, Size = UDim2.new(1,0,0,18), BackgroundTransparency = 1, Text = "Time: --:--:--", Font = Enum.Font.SourceSans, TextSize = 12, TextColor3 = Color3.fromRGB(160,160,160), TextXAlignment = Enum.TextXAlignment.Left})
    local brokenCount = 0
    local brokenLabel = new("TextLabel", {Parent = labelsFrame, Size = UDim2.new(1,0,0,18), BackgroundTransparency = 1, Text = "Broken: 0", Font = Enum.Font.SourceSans, TextSize = 12, TextColor3 = Color3.fromRGB(160,160,160), TextXAlignment = Enum.TextXAlignment.Left})
    labelsLayout.Parent = labelsFrame

    -- Buttons container (stacked vertical, but we'll create top emoji row first)
    local buttonsFrame = new("Frame", {Parent = mainFrame, Size = UDim2.new(1,0,0,96), BackgroundTransparency = 1})
    local buttonsLayout = new("UIListLayout", {Parent = buttonsFrame, Padding = UDim.new(0,6), SortOrder = Enum.SortOrder.LayoutOrder})
    buttonsLayout.FillDirection = Enum.FillDirection.Vertical

    -- Emoji tab row (two square buttons side-by-side)
    local tabsRow = new("Frame", {Parent = buttonsFrame, Size = UDim2.new(1,0,0,44), BackgroundTransparency = 1})
    local tabsLayout = new("UIListLayout", {Parent = tabsRow, FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0,8), HorizontalAlignment = Enum.HorizontalAlignment.Left})
    local tabsPadding = new("UIPadding", {Parent = tabsRow, PaddingLeft = UDim.new(0,4), PaddingTop = UDim.new(0,6)})
    local eggBtn = new("TextButton", {Parent = tabsRow, Size = UDim2.new(0,40,0,40), Text = "🥚", Font = Enum.Font.SourceSansBold, TextSize = 22, BackgroundColor3 = Color3.fromRGB(30,30,30), TextColor3 = Color3.fromRGB(255,255,255)})
    new("UICorner", {Parent = eggBtn, CornerRadius = UDim.new(0,6)})
    local toolsBtn = new("TextButton", {Parent = tabsRow, Size = UDim2.new(0,40,0,40), Text = "🛠️", Font = Enum.Font.SourceSansBold, TextSize = 18, BackgroundColor3 = Color3.fromRGB(30,30,30), TextColor3 = Color3.fromRGB(255,255,255)})
    new("UICorner", {Parent = toolsBtn, CornerRadius = UDim.new(0,6)})

    -- main action buttons (Pick Best, Start toggle, Blatant)
    local pickBtn = new("TextButton", {Parent = buttonsFrame, Size = UDim2.new(1,0,0,34), Text = "Pick Best Pets", Font = Enum.Font.SourceSansBold, TextSize = 14, BackgroundColor3 = Color3.fromRGB(38,38,38), TextColor3 = Color3.fromRGB(240,240,240)})
    new("UICorner", {Parent = pickBtn, CornerRadius = UDim.new(0,6)})
    local startBtn = new("TextButton", {Parent = buttonsFrame, Size = UDim2.new(1,0,0,34), Text = "Start", Font = Enum.Font.SourceSansBold, TextSize = 14, BackgroundColor3 = Color3.fromRGB(34,139,34), TextColor3 = Color3.fromRGB(240,240,240)})
    new("UICorner", {Parent = startBtn, CornerRadius = UDim.new(0,6)})
    local blatantBtn = new("TextButton", {Parent = buttonsFrame, Size = UDim2.new(1,0,0,30), Text = "Blatant Farm (All Pets -> Nearest)", Font = Enum.Font.SourceSans, TextSize = 12, BackgroundColor3 = Color3.fromRGB(45,45,45), TextColor3 = Color3.fromRGB(240,240,240)})
    new("UICorner", {Parent = blatantBtn, CornerRadius = UDim.new(0,6)})

    -- Dropdowns container (stacked)
    local controlsFrame = new("Frame", {Parent = mainFrame, Size = UDim2.new(1,0,0,140), BackgroundTransparency = 1})
    local controlsLayout = new("UIListLayout", {Parent = controlsFrame, Padding = UDim.new(0,6), SortOrder = Enum.SortOrder.LayoutOrder})
    local controlsPadding = new("UIPadding", {Parent = controlsFrame, PaddingLeft = UDim.new(0,0), PaddingRight = UDim.new(0,0), PaddingTop = UDim.new(0,4)})

    -- make world & area & target dropdowns (stacked)
    local worldDropdown = makeDropdown(controlsFrame, "World", (function()
        local t = {}
        for k,_ in pairs(WorldsTable) do table.insert(t, k) end
        table.sort(t); return t
    end)(), function(selected)
        SelectedWorld = tostring(selected)
        -- refresh area dropdown immediately and auto-select first area
        local areas = WorldsTable[SelectedWorld] or {}
        areaDropdown.SetOptions(areas)
        if #areas > 0 then
            areaDropdown.SetValue(areas[1])
            SelectedArea = areas[1]
        else
            areaDropdown.SetValue("None")
            SelectedArea = ""
        end
        -- clear assignments to force retarget into new area
        petToTarget = {}
        targetToPet = {}
        petCooldowns = {}
        statusLabel.Text = ("Status: Selected %s - %s"):format(SelectedWorld, SelectedArea)
    end)

    local areaDropdown = makeDropdown(controlsFrame, "Area", WorldsTable[SelectedWorld], function(selected)
        SelectedArea = tostring(selected)
        petToTarget = {}
        targetToPet = {}
        petCooldowns = {}
        statusLabel.Text = ("Status: Selected %s - %s"):format(SelectedWorld, SelectedArea)
    end)

    local targetDropdown = makeDropdown(controlsFrame, "Target Type", {"Nearest","Strongest","Random","All"}, function(v)
        statusLabel.Text = ("Target mode: %s"):format(tostring(v))
    end)

    -- Ensure area matches initial world
    do
        local initAreas = WorldsTable[worldDropdown.Button.Text] or {}
        areaDropdown.SetOptions(initAreas)
        areaDropdown.SetValue(initAreas[1] or "None")
        SelectedWorld = worldDropdown.Button.Text
        SelectedArea = areaDropdown.Button.Text
    end

    -- Panels area: placeholders (only one visible at a time)
    local panelsFrame = new("Frame", {Parent = mainFrame, Size = UDim2.new(1,0,0,48), BackgroundTransparency = 1})
    local panelsPadding = new("UIPadding", {Parent = panelsFrame, PaddingTop = UDim.new(0,4)})
    local eggPanel = new("Frame", {Parent = panelsFrame, Size = UDim2.new(1,0,0,48), BackgroundColor3 = Color3.fromRGB(22,22,22), Visible = false})
    new("UICorner", {Parent = eggPanel, CornerRadius = UDim.new(0,6)})
    local eggLabel = new("TextLabel", {Parent = eggPanel, Size = UDim2.new(1,-8,0,48), Position = UDim2.new(0,4,0,0), BackgroundTransparency = 1, Text = "Egg Tools Placeholder\n(Remove Hatch Animation etc.)", Font = Enum.Font.SourceSans, TextSize = 13, TextColor3 = Color3.fromRGB(220,220,220), TextWrapped = true})

    local toolsPanel = new("Frame", {Parent = panelsFrame, Size = UDim2.new(1,0,0,48), BackgroundColor3 = Color3.fromRGB(22,22,22), Visible = false})
    new("UICorner", {Parent = toolsPanel, CornerRadius = UDim.new(0,6)})
    local toolsLabel = new("TextLabel", {Parent = toolsPanel, Size = UDim2.new(1,-8,0,48), Position = UDim2.new(0,4,0,0), BackgroundTransparency = 1, Text = "Upgrade Tools Placeholder\n(Auto Fuse / Auto Rainbow / Auto Gold)", Font = Enum.Font.SourceSans, TextSize = 13, TextColor3 = Color3.fromRGB(220,220,220), TextWrapped = true})

    -- toggle logic for emoji buttons (only one panel visible at a time; toggle)
    local function ShowPanel(panel)
        eggPanel.Visible = false
        toolsPanel.Visible = false
        if panel then panel.Visible = true end
    end
    eggBtn.MouseButton1Click:Connect(function()
        if eggPanel.Visible then
            ShowPanel(nil)
        else
            ShowPanel(eggPanel)
        end
    end)
    toolsBtn.MouseButton1Click:Connect(function()
        if toolsPanel.Visible then
            ShowPanel(nil)
        else
            ShowPanel(toolsPanel)
        end
    end)

    -- ==== BEHAVIORS: buttons ====
    pickBtn.MouseButton1Click:Connect(function()
        statusLabel.Text = "Status: Equipping best pets..."
        task.spawn(function()
            local chosen = pickTopNFromSave()
            if #chosen == 0 then
                statusLabel.Text = "Status: No pets found."
                return
            end
            trackedPets = chosen
            for _, uid in ipairs(trackedPets) do
                local ok, res = EquipPet(uid)
                if not ok then warn("[HateQoL] EquipPet failed for", uid, res) end
                task.wait(0.06)
            end
            task.wait(EQUIP_WAIT)
            statusLabel.Text = ("Status: Equipped %d pets"):format(#trackedPets)
        end)
    end)

    startBtn.MouseButton1Click:Connect(function()
        Enabled = not Enabled
        startBtn.Text = Enabled and "Stop" or "Start"
        startBtn.BackgroundColor3 = Enabled and Color3.fromRGB(178,34,34) or Color3.fromRGB(34,139,34)
        statusLabel.Text = Enabled and ("Status: Farming (%s - %s)"):format(SelectedWorld, SelectedArea) or "Status: Stopped"
    end)

    blatantBtn.MouseButton1Click:Connect(function()
        statusLabel.Text = "Status: Blatant farm (assigning all pets to nearest)..."
        task.spawn(function()
            local coins = GetCoinsRaw()
            if coins then TargetNearestAll(coins) end
            task.wait(0.2)
            statusLabel.Text = ("Status: Blatant assigned (%s)"):format(os.date("%X"))
        end)
    end)

    -- draggable support (title drag)
    local dragging, dragInput, dragStart, startPos
    title.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = mainFrame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    title.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)
    UserInput.InputChanged:Connect(function(input)
        if input == dragInput and dragging and dragStart and startPos then
            local delta = input.Position - dragStart
            mainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)

    -- small API helpers to update labels
    local API = {}
    function API.SetTimeText()
        timeLabel.Text = "Time: " .. os.date("%H:%M:%S")
    end
    function API.SetStatusText(t)
        statusLabel.Text = tostring(t)
    end
    function API.IncBroken()
        brokenCount = brokenCount + 1
        brokenLabel.Text = "Broken: "..tostring(brokenCount)
    end
    function API.SetBroken(n)
        brokenCount = tonumber(n) or brokenCount
        brokenLabel.Text = "Broken: "..tostring(brokenCount)
    end

    -- auto-time / broken counter updater
    task.spawn(function()
        while true do
            task.wait(1)
            pcall(API.SetTimeText)
            if Enabled then
                -- increment for visual test; in actual farming increments only when we detect disappearance
                -- keep this minimal here
            end
        end
    end)

    -- ==== MAIN FARM LOOP ====
    task.spawn(function()
        while true do
            if Enabled then
                -- ensure trackedPets equipped
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
                    pcall(function() statusLabel.Text = "Status: Waiting for coins..." end)
                    task.wait(1)
                else
                    -- show explicit selected area in status
                    pcall(function() statusLabel.Text = ("Status: Farming (%s - %s)"):format(tostring(SelectedWorld), tostring(SelectedArea)) end)

                    -- clear stale assignments
                    FreeStaleAssignments(coins)

                    -- assign pets only for selected area
                    FillAssignments(coins)

                    -- if a pet assignment causes a breakable removed, it will be freed and reassigned next loop
                    -- collect orbs
                    pcall(function() ClaimOrbs({}) end)

                    -- collect lootbags to player
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
            task.wait(MAIN_LOOP_DELAY)
        end
    end)

    print("[HateQoL] UI loaded and autofarm running (when started).")

end) -- end pcall

if not ok then
    warn("[HateQoL] Startup error:", mainErr)
else
    print("[HateQoL] Script executed successfully.")
end
