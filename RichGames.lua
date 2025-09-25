-- PSX AutoFarm — Final: Simple UI + Area-only + One-pet-per-breakable + Minimize + Save position
-- Paste into a NEW LocalScript and run

local ok, mainErr = pcall(function()

    -- ==== CONFIG ====
    local SAFE_DELAY_BETWEEN_ASSIGN = 0.18
    local JOIN_DELAY = 0.06
    local CHANGE_DELAY = 0.04
    local MAIN_LOOP_DELAY = 0.8
    local EQUIP_WAIT = 0.45
    local RETARGET_DELAY = 0.3

    local SAVE_FILENAME = "PSX_AutoFarm_UI_Pos.json" -- stored if writefile/readfile available

    -- ==== WORLDS TABLE ====
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
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local Workspace = game:GetService("Workspace")
    local HttpService = game:GetService("HttpService")
    local LocalPlayer = Players.LocalPlayer
    assert(LocalPlayer, "LocalPlayer nil - run as LocalScript")
    local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

    local Network = ReplicatedStorage:FindFirstChild("Network")
    if not Network then
        warn("[AutoFarm] ReplicatedStorage.Network not found. Remotes may be missing.")
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

    -- Helper: choose equipped pet UIDs (prefer save flags)
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
        -- fallback: return pickTopNFromSave (it will return top equipped or best)
        local top = pickTopNFromSave()
        if #top > 0 then return top end
        return {}
    end

    -- === ASSIGNMENT HELPERS (one pet per breakable) ===
    local function AssignPetToBreakable(petUID, breakId)
        if not petUID or not breakId then return false end
        -- Use safe delayed remote calls
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

    -- ==== GUI HELPERS ====
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
        btn.BackgroundColor3 = Color3.fromRGB(60,60,60)
        btn.AutoButtonColor = true
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0,6)

        local menu = Instance.new("Frame", parent)
        menu.Size = UDim2.new(0, width, 0, math.min(#options*24, 200))
        menu.Position = UDim2.new(0, posX, 0, posY + 46)
        menu.Visible = false
        menu.BackgroundColor3 = Color3.fromRGB(40,40,40)
        Instance.new("UICorner", menu).CornerRadius = UDim.new(0,6)
        local layout = Instance.new("UIListLayout", menu)
        layout.Padding = UDim.new(0,4)

        local function populate(opts)
            for _, c in ipairs(menu:GetChildren()) do
                if not c:IsA("UIListLayout") then c:Destroy() end
            end
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
        btn.MouseButton1Click:Connect(function()
            menu.Visible = not menu.Visible
        end)

        return {
            Button = btn,
            Menu = menu,
            Label = label,
            SetOptions = function(newOptions)
                populate(newOptions)
            end
        }
    end

    -- ===== SAVE / LOAD UI POS =====
    local function canWriteFile()
        return type(writefile) == "function" and type(readfile) == "function"
    end

    local function save_ui_position(data)
        if not canWriteFile() then return false end
        pcall(function()
            local json = HttpService:JSONEncode(data)
            writefile(SAVE_FILENAME, json)
        end)
        return true
    end

    local function load_ui_position()
        if not canWriteFile() then return nil end
        local ok, dat = pcall(function()
            local content = readfile(SAVE_FILENAME)
            return HttpService:JSONDecode(content)
        end)
        if ok and type(dat) == "table" then
            return dat
        end
        return nil
    end

    -- ==== GUI CREATION (simple clean small) ====
    local function CreateGUI()
        -- create screengui
        local screenGui = Instance.new("ScreenGui")
        screenGui.Name = "PSX_AutoFarm_GUI_Simple"
        screenGui.ResetOnSpawn = false
        screenGui.Parent = PlayerGui

        -- frame
        local frame = Instance.new("Frame", screenGui)
        frame.Size = UDim2.new(0, 320, 0, 220)
        frame.Position = UDim2.new(0.5, -160, 0.5, -110)
        frame.BackgroundColor3 = Color3.fromRGB(30,30,30)
        frame.ZIndex = 50
        Instance.new("UICorner", frame).CornerRadius = UDim.new(0,8)

        -- try restore saved position
        local saved = load_ui_position()
        if saved and type(saved) == "table" and saved.x and saved.y then
            pcall(function()
                frame.Position = UDim2.new(saved.scaleX or 0, saved.x, saved.scaleY or 0, saved.y)
            end)
        end

        -- title bar (draggable only by this)
        local titleBar = Instance.new("Frame", frame)
        titleBar.Size = UDim2.new(1, 0, 0, 30)
        titleBar.Position = UDim2.new(0, 0, 0, 0)
        titleBar.BackgroundTransparency = 0.12
        titleBar.BackgroundColor3 = Color3.fromRGB(22,22,22)
        titleBar.ZIndex = 51
        Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0,8)

        local title = Instance.new("TextLabel", titleBar)
        title.Size = UDim2.new(1, -48, 1, 0)
        title.Position = UDim2.new(0, 8, 0, 0)
        title.BackgroundTransparency = 1
        title.Font = Enum.Font.SourceSansBold
        title.TextSize = 16
        title.TextColor3 = Color3.new(1,1,1)
        title.Text = "PSX AutoFarm"

        -- minimize button (option A: small "-")
        local minBtn = Instance.new("TextButton", titleBar)
        minBtn.Size = UDim2.new(0, 36, 0, 22)
        minBtn.Position = UDim2.new(1, -44, 0, 4)
        minBtn.AnchorPoint = Vector2.new(0, 0)
        minBtn.Text = "—"
        minBtn.Font = Enum.Font.SourceSansBold
        minBtn.TextSize = 18
        minBtn.BackgroundTransparency = 0.2
        minBtn.TextColor3 = Color3.new(1,1,1)
        Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0,6)

        -- content container (everything below title bar)
        local content = Instance.new("Frame", frame)
        content.Size = UDim2.new(1, -16, 1, -46)
        content.Position = UDim2.new(0, 8, 0, 34)
        content.BackgroundTransparency = 1

        -- Buttons at top inside content
        local pickBtn = Instance.new("TextButton", content)
        pickBtn.Size = UDim2.new(0.48, -8, 0, 36)
        pickBtn.Position = UDim2.new(0, 0, 0, 0)
        pickBtn.Text = "Pick Best Pets"
        pickBtn.Font = Enum.Font.SourceSansBold
        pickBtn.BackgroundColor3 = Color3.fromRGB(70,130,180)
        pickBtn.TextColor3 = Color3.new(1,1,1)
        Instance.new("UICorner", pickBtn).CornerRadius = UDim.new(0,6)

        local startBtn = Instance.new("TextButton", content)
        startBtn.Size = UDim2.new(0.48, -8, 0, 36)
        startBtn.Position = UDim2.new(0, 156, 0, 0)
        startBtn.Text = "Start"
        startBtn.Font = Enum.Font.SourceSansBold
        startBtn.BackgroundColor3 = Color3.fromRGB(34,139,34)
        startBtn.TextColor3 = Color3.new(1,1,1)
        Instance.new("UICorner", startBtn).CornerRadius = UDim.new(0,6)

        -- Dropdowns (5px below buttons)
        local worldDropdown, areaDropdown
        -- compute dropdown positions relative to content (buttons top y=0, height=36 -> bottom 36 -> +5 -> 41)
        local ddY = 36 + 5

        worldDropdown = makeDropdown(content, 0, ddY, 150, "World", (function()
            local t = {}
            for k,_ in pairs(WorldsTable) do table.insert(t, k) end
            table.sort(t)
            return t
        end)(), function(selected)
            SelectedWorld = selected
            local areas = WorldsTable[SelectedWorld] or {}
            if areaDropdown then
                areaDropdown.SetOptions(areas)
                if #areas > 0 then
                    SelectedArea = areas[1]
                    areaDropdown.Button.Text = areas[1]
                else
                    SelectedArea = ""
                    areaDropdown.Button.Text = "None"
                end
            end
            -- reset assignments so pets retarget into new area
            petToTarget = {}
            targetToPet = {}
            petCooldowns = {}
        end)

        areaDropdown = makeDropdown(content, 160, ddY, 150, "Area", WorldsTable[SelectedWorld] or {}, function(selected)
            SelectedArea = selected
            -- clear assignments when area changes
            petToTarget = {}
            targetToPet = {}
            petCooldowns = {}
        end)

        -- status label at bottom of frame
        local status = Instance.new("TextLabel", frame)
        status.Size = UDim2.new(1, -20, 0, 36)
        status.Position = UDim2.new(0, 10, 1, -44)
        status.BackgroundTransparency = 1
        status.TextColor3 = Color3.new(1,1,1)
        status.TextWrapped = true
        status.Font = Enum.Font.SourceSans
        status.TextSize = 14
        status.Text = "Status: Idle"

        -- draggable by title bar only
        do
            local dragging = false
            local dragStart = nil
            local startPos = nil
            titleBar.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 then
                    dragging = true
                    dragStart = input.Position
                    startPos = frame.Position
                    input.Changed:Connect(function()
                        if input.UserInputState == Enum.UserInputState.End then
                            dragging = false
                            -- save position on drag end
                            pcall(function()
                                local pos = frame.Position
                                local data = {
                                    x = pos.X.Offset,
                                    y = pos.Y.Offset,
                                    scaleX = pos.X.Scale,
                                    scaleY = pos.Y.Scale
                                }
                                save_ui_position(data)
                            end)
                        end
                    end)
                end
            end)
            titleBar.InputChanged:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseMovement then
                    local moveInput = input
                    -- connect global input changed
                    game:GetService("UserInputService").InputChanged:Connect(function(i)
                        if dragging and i == moveInput and dragStart and startPos then
                            local delta = i.Position - dragStart
                            frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
                        end
                    end)
                end
            end)
        end

        -- minimize / expand behavior (collapse into small title bar)
        local collapsed = false
        local prevSize = frame.Size
        local prevContentVisible = true
        minBtn.MouseButton1Click:Connect(function()
            if not collapsed then
                -- collapse: shrink frame to titleBar height only
                prevSize = frame.Size
                content.Visible = false
                status.Visible = false
                frame.Size = UDim2.new(frame.Size.X.Scale, frame.Size.X.Offset, 0, 34)
                collapsed = true
            else
                -- expand
                frame.Size = prevSize
                content.Visible = true
                status.Visible = true
                collapsed = false
            end
            -- save position/size
            pcall(function()
                local pos = frame.Position
                local data = {
                    x = pos.X.Offset,
                    y = pos.Y.Offset,
                    scaleX = pos.X.Scale,
                    scaleY = pos.Y.Scale
                }
                save_ui_position(data)
            end)
        end)

        -- titleBar click also toggles expand/collapse if collapsed
        titleBar.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 and collapsed then
                -- expand back
                frame.Size = prevSize
                content.Visible = true
                status.Visible = true
                collapsed = false
            end
        end)

        -- Button behaviors
        pickBtn.MouseButton1Click:Connect(function()
            status.Text = "Status: Equipping best pets..."
            local chosen = pickTopNFromSave()
            if #chosen == 0 then
                status.Text = "Status: No pets found."
                return
            end
            trackedPets = chosen
            for _, uid in ipairs(trackedPets) do
                local ok, res = EquipPet(uid)
                if not ok then warn("[AutoFarm] EquipPet failed for", uid, res) end
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

        return {
            Gui = screenGui,
            Frame = frame,
            Status = status,
            WorldDropdown = worldDropdown,
            AreaDropdown = areaDropdown
        }
    end

    local ui = CreateGUI()

    -- ==== MAIN LOOP ====
    task.spawn(function()
        while true do
            if Enabled then
                -- ensure pets equipped (if none)
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
                    if ui and ui.Status then ui.Status.Text = "Status: Waiting for coins..." end
                    task.wait(1)
                else
                    -- update status label (explicit with selected)
                    if ui and ui.Status then ui.Status.Text = ("Status: Farming (%s - %s)"):format(tostring(SelectedWorld), tostring(SelectedArea)) end

                    -- free stale assignments if breakables disappear
                    FreeStaleAssignments(coins)

                    -- fill assignments (one pet per breakable) for selected area only
                    FillAssignments(coins)

                    -- collect orbs
                    pcall(function() ClaimOrbs({}) end)

                    -- collect lootbags to player
                    pcall(function()
                        local things = Workspace:FindFirstChild("__THINGS") or Workspace:FindFirstChild("__things")
                        if things and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                            local bags = things:FindFirstChild("Lootbags")
                            if bags then
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

    print("[AutoFarm] Loaded - simple GUI ready. Pick Best Pets -> Start.")

end)

if not ok then
    warn("[AutoFarm] Startup error:", mainErr)
else
    print("[AutoFarm] Script executed successfully!")
end
