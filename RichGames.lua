-- PSX AutoFarm (Revised) - Draggable GUI, World/Area dropdowns, Minimize, Pick & Equip Best, Auto farm all breakables
-- Paste into a NEW LocalScript and run with your executor

local ok, mainErr = pcall(function()

    -- ==== STATIC WORLDS TABLE (from your list) ====
    local WorldsTable = {
        ["Spawn"] = {"Shop","Town","Forest","Beach","Mine","Winter","Glacier","Desert","Volcano","Cave","Tech Entry","VIP"},
        ["Fantasy"] = {"Fantasy Shop","Enchanted Forest","Portals","Ancient Island","Samurai Island","Candy Island","Haunted Island","Hell Island","Heaven Island","Heaven's Gate"},
        ["Tech"] = {"Tech Shop","Tech City","Dark Tech","Steampunk","Steampunk Chest Area","Alien Lab","Alien Forest","Giant Alien Chest","Glitch","Hacker Portal"},
        ["Void"] = {"The Void"},
        ["Axolotl Ocean"] = {"Axolotl Ocean","Axolotl Deep Ocean","Axolotl Cave"},
        ["Pixel"] = {"Pixel Forest","Pixel Kyoto","Pixel Alps","Pixel Vault"},
        ["Cat"] = {"Cat Paradise","Cat Backyard","Cat Taiga","Cat Throne Room"}
    }

    -- ==== CONFIG ====
    local SAFE_DELAY_BETWEEN_ASSIGN = 0.12
    local JOIN_DELAY = 0.06
    local CHANGE_DELAY = 0.04
    local MAIN_LOOP_DELAY = 0.8
    local EQUIP_WAIT = 0.45

    -- ==== SERVICES ====
    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local Workspace = game:GetService("Workspace")
    local LocalPlayer = Players.LocalPlayer
    assert(LocalPlayer, "LocalPlayer nil - run as LocalScript")
    local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

    -- ==== SAFE REMOTE CALLER ====
    local Network = ReplicatedStorage:FindFirstChild("Network")
    if not Network then
        warn("[AutoFarm] ReplicatedStorage.Network not found. Remotes may be missing.")
    end

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

    -- Remote helpers
    local function GetSave() local ok,res = CallRemote("Get Custom Save", {}) if ok then return res end return nil end
    local function GetCoinsRaw() local ok,res = CallRemote("Get Coins", {}) if ok then return res end local ok2,res2 = CallRemote("Coins: Get Test", {}) if ok2 then return res2 end return nil end
    local function EquipPet(uid) return CallRemote("Equip Pet", {uid}) end
    local function JoinCoin(id, pets) return CallRemote("Join Coin", {id, pets}) end
    local function ChangePetTarget(uid, ttype, id) return CallRemote("Change Pet Target", {uid, ttype, id}) end
    local function FarmCoin(id, uid) return CallRemote("Farm Coin", {id, uid}) end
    local function ClaimOrbs(arg) return CallRemote("Claim Orbs", {arg or {}}) end

    -- ==== UTILITIES ====
    local function safe_delay(t, f) if type(t)=="number" and type(f)=="function" then task.delay(t, f) end end
    local function safeNumber(x) if type(x)=="number" then return x end if type(x)=="string" then return tonumber(x) or 0 end return 0 end

    local function buildPetListFromSave(save)
        if not save then return {} end
        local petsTbl = save.Pets or save.pets or {}
        local out = {}
        for k, v in pairs(petsTbl) do
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
    local Enabled = false
    local trackedPets = {}       -- list of UIDs currently equipped/tracked
    local petToTarget = {}       -- uid -> breakId
    local targetToPet = {}       -- breakId -> uid
    local petCooldowns = {}      -- uid -> timestamp until can be reassigned
    local SelectedWorld = "Spawn"
    local SelectedArea = "Town"

    -- ==== ASSIGN HELPERS ====
    local function clearAssignment(uid)
        if not uid then return end
        local t = petToTarget[uid]
        if t then
            petToTarget[uid] = nil
            targetToPet[t] = nil
        end
        petCooldowns[uid] = tick() + 0.35
    end

    local function freeStaleAssignments(coins)
        local present = {}
        if coins then for id, _ in pairs(coins) do present[id] = true end end
        for uid, id in pairs(petToTarget) do
            if not present[id] then
                clearAssignment(uid)
            end
        end
    end

    local function getNearestBreakableForPositionFiltered(coins, pos, usedTargets, world, area)
        local bestId, bestDist = nil, math.huge
        for id, data in pairs(coins) do
            if type(data) == "table" and not usedTargets[id] then
                if tostring(data.w) == tostring(world) and tostring(data.a) == tostring(area) then
                    local p = data.p
                    if p and typeof(p) == "Vector3" then
                        local d = (pos - p).Magnitude
                        if d < bestDist then bestDist = d; bestId = id end
                    end
                end
            end
        end
        return bestId
    end

    local function assignAllTrackedToNearestFiltered(coins, world, area)
        if not coins then return end
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        local used = {}
        for id, _ in pairs(targetToPet) do used[id] = true end

        for _, uid in ipairs(trackedPets) do
            if not petToTarget[uid] and (petCooldowns[uid] or 0) <= tick() then
                local nearestId = getNearestBreakableForPositionFiltered(coins, hrp.Position, used, world, area)
                if nearestId then
                    safe_delay(0, function() JoinCoin(nearestId, {uid}) end)
                    safe_delay(JOIN_DELAY, function() ChangePetTarget(uid, "Coin", nearestId) end)
                    safe_delay(JOIN_DELAY + CHANGE_DELAY, function() FarmCoin(nearestId, uid) end)
                    petToTarget[uid] = nearestId
                    targetToPet[nearestId] = uid
                    petCooldowns[uid] = tick()
                    used[nearestId] = true
                    task.wait(SAFE_DELAY_BETWEEN_ASSIGN)
                end
            end
        end
    end

    -- ==== COLLECTION ====
    local function collectOrbsAndBags()
        pcall(function() ClaimOrbs({}) end)
        local things = Workspace:FindFirstChild("__THINGS") or Workspace:FindFirstChild("__things")
        if not things then return end
        local bags = things:FindFirstChild("Lootbags")
        if not bags then return end
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        for _, bag in ipairs(bags:GetChildren()) do
            if bag and bag:IsA("BasePart") then
                pcall(function() bag.CFrame = hrp.CFrame end)
            end
        end
    end

    -- ==== GUI helpers ====
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

        for _, opt in ipairs(options) do
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

        btn.MouseButton1Click:Connect(function()
            menu.Visible = not menu.Visible
        end)

        return {
            Button = btn,
            Menu = menu,
            Label = label,
            SetOptions = function(newOptions)
                for _, c in ipairs(menu:GetChildren()) do if not (c:IsA("UIListLayout")) then c:Destroy() end end
                for _, opt in ipairs(newOptions) do
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
                menu.Size = UDim2.new(0, width, 0, math.min(#newOptions*24, 200))
            end
        }
    end

    -- draggable
    local function makeDraggable(frame)
        local dragging, dragInput, dragStart, startPos
        frame.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = true
                dragStart = input.Position
                startPos = frame.Position
                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then
                        dragging = false
                    end
                end)
            end
        end)
        frame.InputChanged:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseMovement then
                dragInput = input
            end
        end)
        game:GetService("UserInputService").InputChanged:Connect(function(input)
            if input == dragInput and dragging and dragStart and startPos then
                local delta = input.Position - dragStart
                frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            end
        end)
    end

    -- ==== GUI ====
    local function CreateGUI()
        local screenGui = Instance.new("ScreenGui")
        screenGui.Name = "PSX_AutoFarm_GUI"
        screenGui.ResetOnSpawn = false
        screenGui.Parent = PlayerGui

        local frame = Instance.new("Frame", screenGui)
        frame.Size = UDim2.new(0, 360, 0, 220)
        frame.Position = UDim2.new(0.5, -180, 0.5, -110)
        frame.BackgroundColor3 = Color3.fromRGB(28,28,28)
        Instance.new("UICorner", frame).CornerRadius = UDim.new(0,8)

        makeDraggable(frame)

        local title = Instance.new("TextLabel", frame)
        title.Size = UDim2.new(1, -16, 0, 28)
        title.Position = UDim2.new(0, 8, 0, 8)
        title.BackgroundTransparency = 1
        title.Font = Enum.Font.SourceSansBold
        title.TextSize = 18
        title.TextColor3 = Color3.new(1,1,1)
        title.Text = "PSX AutoFarm"

        local minimizeBtn = Instance.new("TextButton", frame)
        minimizeBtn.Size = UDim2.new(0, 28, 0, 24)
        minimizeBtn.Position = UDim2.new(1, -36, 0, 8)
        minimizeBtn.Text = "—"
        minimizeBtn.Font = Enum.Font.SourceSansBold
        minimizeBtn.TextSize = 18
        minimizeBtn.BackgroundColor3 = Color3.fromRGB(180,180,180)
        minimizeBtn.TextColor3 = Color3.new(0,0,0)
        Instance.new("UICorner", minimizeBtn).CornerRadius = UDim.new(0,6)

        local openBtn = Instance.new("TextButton", screenGui)
        openBtn.Size = UDim2.new(0, 40, 0, 28)
        openBtn.Position = UDim2.new(0, 10, 0, 10)
        openBtn.Text = "AF"
        openBtn.Visible = false
        openBtn.BackgroundColor3 = Color3.fromRGB(40,40,40)
        openBtn.TextColor3 = Color3.new(1,1,1)
        Instance.new("UICorner", openBtn).CornerRadius = UDim.new(0,6)
        openBtn.ZIndex = 999

        -- Dropdowns and buttons
        local worldDropdown = makeDropdown(frame, 12, 44, 160, "World", (function()
            local t = {}
            for k, _ in pairs(WorldsTable) do table.insert(t, k) end
            table.sort(t)
            return t
        end)(), function(selected)
            SelectedWorld = selected
            local areas = WorldsTable[selected] or {}
            areaDropdown.SetOptions(areas)
            if #areas > 0 then
                SelectedArea = areas[1]
                areaDropdown.Button.Text = areas[1]
            else
                SelectedArea = ""
                areaDropdown.Button.Text = "None"
            end
            petToTarget = {}
            targetToPet = {}
            petCooldowns = {}
        end)

        local pickBtn = Instance.new("TextButton", frame)
        pickBtn.Size = UDim2.new(0, 168, 0, 92)
        pickBtn.Position = UDim2.new(0, 12, 0, 92)
        pickBtn.Text = "Pick & Equip Best"
        pickBtn.Font = Enum.Font.SourceSansBold
        pickBtn.BackgroundColor3 = Color3.fromRGB(70,130,180)
        pickBtn.TextColor3 = Color3.new(1,1,1)
        Instance.new("UICorner", pickBtn).CornerRadius = UDim.new(0,6)

        local startBtn = Instance.new("TextButton", frame)
        startBtn.Size = UDim2.new(0, 168, 0, 92)
        startBtn.Position = UDim2.new(0, 180, 0, 92)
        startBtn.Text = "Start"
        startBtn.Font = Enum.Font.SourceSansBold
        startBtn.BackgroundColor3 = Color3.fromRGB(34,139,34)
        startBtn.TextColor3 = Color3.new(1,1,1)
        Instance.new("UICorner", startBtn).CornerRadius = UDim.new(0,6)

        local areaDropdown = makeDropdown(frame, 12, 140, 336, "Area", WorldsTable[SelectedWorld] or {}, function(selected)
            SelectedArea = selected
            petToTarget = {}
            targetToPet = {}
            petCooldowns = {}
        end)

        local statusLabel = Instance.new("TextLabel", frame)
        statusLabel.Size = UDim2.new(1, -16, 0, 28)
        statusLabel.Position = UDim2.new(0, 8, 0, 188)
        statusLabel.BackgroundTransparency = 1
        statusLabel.Font = Enum.Font.SourceSans
        statusLabel.TextSize = 14
        statusLabel.TextColor3 = Color3.new(1,1,1)
        statusLabel.Text = "Status: Idle"

        -- minimize behavior
        minimizeBtn.MouseButton1Click:Connect(function()
            frame.Visible = false
            openBtn.Visible = true
        end)
        openBtn.MouseButton1Click:Connect(function()
            frame.Visible = true
            openBtn.Visible = false
        end)

        -- pick button behavior
        pickBtn.MouseButton1Click:Connect(function()
            statusLabel.Text = "Status: Equipping best pets..."
            local chosen = pickTopNFromSave()
            if #chosen == 0 then
                statusLabel.Text = "Status: No pets found."
                return
            end
            trackedPets = chosen
            for _, uid in ipairs(trackedPets) do
                local ok, res = EquipPet(uid)
                if not ok then warn("[AutoFarm] EquipPet failed for", uid, res) end
                task.wait(0.06)
            end
            task.wait(EQUIP_WAIT)
            statusLabel.Text = ("Status: Equipped %d pets"):format(#trackedPets)
        end)

        -- start/stop
        startBtn.MouseButton1Click:Connect(function()
            Enabled = not Enabled
            if Enabled then
                startBtn.Text = "Stop"
                startBtn.BackgroundColor3 = Color3.fromRGB(178,34,34)
                statusLabel.Text = "Status: Farming - selecting targets..."
                petToTarget = {}
                targetToPet = {}
                petCooldowns = {}
            else
                startBtn.Text = "Start"
                startBtn.BackgroundColor3 = Color3.fromRGB(34,139,34)
                statusLabel.Text = "Status: Stopped"
            end
        end)

        return {
            Gui = screenGui,
            Frame = frame,
            Status = statusLabel,
            WorldDropdown = worldDropdown,
            AreaDropdown = areaDropdown
        }
    end

    local ui = CreateGUI()

    -- ==== MAIN LOOP ====
    task.spawn(function()
        while true do
            if Enabled then
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
                    local firstW, firstA = nil, nil
                    for id, data in pairs(coins) do
                        if type(data) == "table" and data.w and data.a then
                            firstW, firstA = tostring(data.w), tostring(data.a)
                            break
                        end
                    end
                    if firstW and firstA then
                        ui.Status.Text = ("Status: Farming: %s - %s"):format(firstW, firstA)
                    else
                        ui.Status.Text = "Status: Farming: Unknown area"
                    end

                    freeStaleAssignments(coins)
                    assignAllTrackedToNearestFiltered(coins, SelectedWorld, SelectedArea)
                    assignAllTrackedToNearestFiltered(coins, SelectedWorld, SelectedArea)
                    collectOrbsAndBags()
                end
            end
            task.wait(MAIN_LOOP_DELAY)
        end
    end)

    print("[AutoFarm] ✅ Loaded. Use the GUI: Pick & Equip Best -> Start.")

end)

if not ok then
    warn("[AutoFarm] Startup error:", mainErr)
else
    print("[AutoFarm] Script executed successfully!")
end
