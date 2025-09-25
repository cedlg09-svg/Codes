-- Simple PSX AutoFarm (sanitized + safe_delay + error catching)
-- Paste into a NEW LocalScript and run

local ok, mainErr = pcall(function()

    -- ==== CONFIG ====
    local SAFE_DELAY_BETWEEN_ASSIGN = 0.18
    local JOIN_DELAY = 0.06
    local CHANGE_DELAY = 0.04
    local MAIN_LOOP_DELAY = 0.8
    local EQUIP_WAIT = 0.45

    -- ==== SAFE DELAY WRAPPER ====
    local function safe_delay(time, func)
        if type(time) == "number" and type(func) == "function" then
            task.delay(time, func)
        end
    end

    -- ==== SERVICES ====
    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local UserInputService = game:GetService("UserInputService")
    local LocalPlayer = Players.LocalPlayer
    assert(LocalPlayer, "LocalPlayer nil")
    local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
    local Workspace = game:GetService("Workspace")

    -- debug start
    print("[AutoFarm] Script start - basic environment OK")

    local Network = ReplicatedStorage:FindFirstChild("Network")
    if not Network then
        warn("[AutoFarm] ReplicatedStorage.Network not found. Remotes may be missing.")
    else
        print("[AutoFarm] Found ReplicatedStorage.Network")
    end

    -- ===== Helper: safe remote caller =====
    local function CallRemoteByName(name, ...)
        if not Network then return false, ("Network missing: %s"):format(tostring(name)) end
        local r = Network:FindFirstChild(name)
        if not r then return false, ("Remote not found: %s"):format(tostring(name)) end
        local class = r.ClassName
        if class == "RemoteFunction" then
            local ok, res = pcall(function() return r:InvokeServer(...) end)
            if ok then return true, res else return false, res end
        elseif class == "RemoteEvent" then
            local ok, _ = pcall(function() r:FireServer(...) end)
            if ok then return true, nil else return false, "FireServer failed" end
        else
            return false, ("Remote unexpected class: %s"):format(tostring(class))
        end
    end

    local function GetSave()
        local ok, res = CallRemoteByName("Get Custom Save")
        if ok then return res end
        return nil
    end

    local function GetCoinsRaw()
        local ok, res = CallRemoteByName("Get Coins")
        if ok then
            if type(res) == "table" and type(res[1]) == "table" then return res[1] end
            return res
        end
        ok, res = CallRemoteByName("Coins: Get Test")
        if ok then
            if type(res) == "table" and type(res[1]) == "table" then return res[1] end
            return res
        end
        return nil
    end

    local function EquipPet(uid) return CallRemoteByName("Equip Pet", uid) end
    local function JoinCoin(id, pets) return CallRemoteByName("Join Coin", id, pets) end
    local function ChangePetTarget(uid, ttype, id) return CallRemoteByName("Change Pet Target", uid, ttype, id) end
    local function FarmCoin(id, uid) return CallRemoteByName("Farm Coin", id, uid) end
    local function ClaimOrbs(arg) return CallRemoteByName("Claim Orbs", arg) end

    -- ==== UTILITIES ====
    local function safeNumber(x)
        if type(x) == "number" then return x end
        if type(x) == "string" then return tonumber(x) or 0 end
        return 0
    end

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
            local pa = safeNumber(a.s or a.power or a.p or a.strength)
            local pb = safeNumber(b.s or b.power or b.p or b.strength)
            return pa > pb
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
    local trackedPets = {}
    local petToTarget, targetToPet, petCooldowns = {}, {}, {}

    -- ==== ASSIGNMENT HELPERS ====
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
            if not present[id] then clearAssignment(uid) end
        end
    end

    local function getNearestBreakableForPosition(coins, pos, usedTargets)
        local bestId, bestDist = nil, math.huge
        for id, data in pairs(coins) do
            if type(data) == "table" and not usedTargets[id] then
                local p = data.p or data.Position or data.pos
                if p and typeof(p) == "Vector3" then
                    local d = (pos - p).Magnitude
                    if d < bestDist then bestDist = d; bestId = id end
                end
            end
        end
        return bestId
    end

    local function assignAllTrackedToNearest(coins)
        if not coins then return end
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        local used = {}
        for id, _ in pairs(targetToPet) do used[id] = true end

        for _, uid in ipairs(trackedPets) do
            if not petToTarget[uid] and (petCooldowns[uid] or 0) <= tick() then
                local nearestId = getNearestBreakableForPosition(coins, hrp.Position, used)
                if nearestId then
                    -- schedule safe calls instead of direct vararg usage
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

    -- ==== GUI (minimal) ====
    local function CreateGUI()
        local screenGui = Instance.new("ScreenGui")
        screenGui.Name = "PSX_SimpleAutoFarm"
        screenGui.ResetOnSpawn = false
        screenGui.Parent = PlayerGui

        local frame = Instance.new("Frame", screenGui)
        frame.Size = UDim2.new(0, 300, 0, 160)
        frame.Position = UDim2.new(0.5, -150, 0.5, -80)
        frame.BackgroundColor3 = Color3.fromRGB(28,28,28)
        Instance.new("UICorner", frame).CornerRadius = UDim.new(0,8)

        local title = Instance.new("TextLabel", frame)
        title.Size = UDim2.new(1, -20, 0, 28)
        title.Position = UDim2.new(0, 10, 0, 8)
        title.BackgroundTransparency = 1
        title.Font = Enum.Font.SourceSansBold
        title.TextSize = 18
        title.TextColor3 = Color3.new(1,1,1)
        title.Text = "Simple PSX AutoFarm"

        local pickBtn = Instance.new("TextButton", frame)
        pickBtn.Size = UDim2.new(0.48, -8, 0, 36)
        pickBtn.Position = UDim2.new(0, 10, 0, 44)
        pickBtn.Text = "Pick & Equip Best"
        pickBtn.Font = Enum.Font.SourceSans
        pickBtn.TextSize = 14
        pickBtn.BackgroundColor3 = Color3.fromRGB(70,130,180)
        pickBtn.TextColor3 = Color3.new(1,1,1)
        Instance.new("UICorner", pickBtn).CornerRadius = UDim.new(0,6)

        local startBtn = Instance.new("TextButton", frame)
        startBtn.Size = UDim2.new(0.48, -8, 0, 36)
        startBtn.Position = UDim2.new(0, 152, 0, 44)
        startBtn.Text = "Start"
        startBtn.Font = Enum.Font.SourceSansBold
        startBtn.TextSize = 14
        startBtn.BackgroundColor3 = Color3.fromRGB(34,139,34)
        startBtn.TextColor3 = Color3.new(1,1,1)
        Instance.new("UICorner", startBtn).CornerRadius = UDim.new(0,6)

        local status = Instance.new("TextLabel", frame)
        status.Size = UDim2.new(1, -20, 0, 30)
        status.Position = UDim2.new(0, 10, 0, 92)
        status.Text = "Status: Idle"
        status.Font = Enum.Font.SourceSans
        status.TextSize = 14
        status.BackgroundTransparency = 1
        status.TextColor3 = Color3.fromRGB(220,220,220)

        pickBtn.MouseButton1Click:Connect(function()
            status.Text = "Status: Picking best pets..."
            local chosen = pickTopNFromSave()
            if #chosen == 0 then
                status.Text = "Status: No pets found."
                return
            end
            trackedPets = chosen
            for _, uid in ipairs(trackedPets) do
                pcall(function() EquipPet(uid) end)
                task.wait(0.06)
            end
            task.wait(EQUIP_WAIT)
            status.Text = ("Status: Equipped %d pets."):format(#trackedPets)
        end)

        startBtn.MouseButton1Click:Connect(function()
            Enabled = not Enabled
            if Enabled then
                startBtn.Text = "Stop"
                startBtn.BackgroundColor3 = Color3.fromRGB(178,34,34)
                status.Text = "Status: Running"
            else
                startBtn.Text = "Start"
                startBtn.BackgroundColor3 = Color3.fromRGB(34,139,34)
                status.Text = "Status: Stopped"
            end
        end)

        return { Gui = screenGui, Status = status }
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
                if coins then
                    freeStaleAssignments(coins)
                    assignAllTrackedToNearest(coins)
                    collectOrbsAndBags()
                else
                    task.wait(1)
                end
            end
            task.wait(MAIN_LOOP_DELAY)
        end
    end)

    print("[AutoFarm] ✅ Loaded. Click 'Pick & Equip Best' then 'Start'.")

end) -- end pcall main

if not ok then
    -- should not happen but print
    print("[AutoFarm] Failed to run main pcall:", mainErr)
else
    -- if inner pcall errored, it is returned as mainErr
    if not mainErr then
        -- no error
    else
        -- mainErr contains error from pcall; print full traceback if possible
        print("[AutoFarm] pcall returned error:", tostring(mainErr))
    end
end
