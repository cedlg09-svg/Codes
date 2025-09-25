-- ✅ Simple PSX AutoFarm (All Coins + World+Area GUI)
-- Paste into a NEW LocalScript and run with executor

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
    local LocalPlayer = Players.LocalPlayer
    assert(LocalPlayer, "LocalPlayer nil")
    local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
    local Workspace = game:GetService("Workspace")

    print("[AutoFarm] ✅ Script start - environment OK")

    local Network = ReplicatedStorage:FindFirstChild("Network")
    if not Network then
        warn("[AutoFarm] ❌ ReplicatedStorage.Network not found.")
    else
        print("[AutoFarm] ✅ Found ReplicatedStorage.Network")
    end

    -- ===== SAFE REMOTE CALLER =====
    local function CallRemoteByName(name, ...)
        if not Network then return false, "Network missing" end
        local r = Network:FindFirstChild(name)
        if not r then return false, "Remote not found: " .. tostring(name) end
        if r.ClassName == "RemoteFunction" then
            local ok, res = pcall(function() return r:InvokeServer(...) end)
            return ok, res
        elseif r.ClassName == "RemoteEvent" then
            local ok, _ = pcall(function() r:FireServer(...) end)
            return ok, nil
        end
        return false, "Invalid remote type"
    end

    -- ==== REMOTE HELPERS ====
    local function GetSave()
        local ok, res = CallRemoteByName("Get Custom Save")
        if ok then return res end
    end

    local function GetCoinsRaw()
        local ok, res = CallRemoteByName("Get Coins")
        if ok then return res end
        ok, res = CallRemoteByName("Coins: Get Test")
        if ok then return res end
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
            return safeNumber(a.s or a.power) > safeNumber(b.s or b.power)
        end)
    end

    local function pickTopNFromSave(n)
        local save = GetSave()
        if not save then return {} end
        local maxEquip = tonumber(save.MaxEquipped or save["P MaxEquipped"]) or 8
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

    -- ==== GUI ====
    local function CreateGUI()
        local gui = Instance.new("ScreenGui")
        gui.Name = "PSX_AutoFarm"
        gui.ResetOnSpawn = false
        gui.Parent = PlayerGui

        local frame = Instance.new("Frame", gui)
        frame.Size = UDim2.new(0, 300, 0, 160)
        frame.Position = UDim2.new(0.5, -150, 0.5, -80)
        frame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
        Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

        local title = Instance.new("TextLabel", frame)
        title.Size = UDim2.new(1, 0, 0, 28)
        title.Position = UDim2.new(0, 0, 0, 6)
        title.Text = "⚙️ PSX AutoFarm"
        title.TextColor3 = Color3.new(1, 1, 1)
        title.Font = Enum.Font.SourceSansBold
        title.BackgroundTransparency = 1
        title.TextSize = 18

        local pick = Instance.new("TextButton", frame)
        pick.Size = UDim2.new(0.48, -8, 0, 36)
        pick.Position = UDim2.new(0, 10, 0, 44)
        pick.Text = "Pick Best Pets"
        pick.BackgroundColor3 = Color3.fromRGB(70, 130, 180)
        pick.TextColor3 = Color3.new(1, 1, 1)
        pick.Font = Enum.Font.SourceSansBold

        local start = Instance.new("TextButton", frame)
        start.Size = UDim2.new(0.48, -8, 0, 36)
        start.Position = UDim2.new(0, 152, 0, 44)
        start.Text = "Start"
        start.BackgroundColor3 = Color3.fromRGB(34, 139, 34)
        start.TextColor3 = Color3.new(1, 1, 1)
        start.Font = Enum.Font.SourceSansBold

        local status = Instance.new("TextLabel", frame)
        status.Size = UDim2.new(1, -20, 0, 40)
        status.Position = UDim2.new(0, 10, 0, 100)
        status.Text = "Status: Idle"
        status.TextColor3 = Color3.new(1, 1, 1)
        status.Font = Enum.Font.SourceSans
        status.TextSize = 14
        status.BackgroundTransparency = 1

        pick.MouseButton1Click:Connect(function()
            status.Text = "Status: Equipping best pets..."
            trackedPets = pickTopNFromSave()
            for _, uid in ipairs(trackedPets) do
                pcall(function() EquipPet(uid) end)
                task.wait(0.06)
            end
            task.wait(EQUIP_WAIT)
            status.Text = "Status: Equipped " .. #trackedPets .. " pets"
        end)

        start.MouseButton1Click:Connect(function()
            Enabled = not Enabled
            if Enabled then
                start.Text = "Stop"
                start.BackgroundColor3 = Color3.fromRGB(178, 34, 34)
                status.Text = "Status: Farming all coins..."
            else
                start.Text = "Start"
                start.BackgroundColor3 = Color3.fromRGB(34, 139, 34)
                status.Text = "Status: Stopped"
            end
        end)

        return status
    end

    local statusLabel = CreateGUI()

    -- ==== MAIN FARM LOOP ====
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
                    for id, data in pairs(coins) do
                        if type(data) == "table" and data.w and data.a then
                            statusLabel.Text = string.format("Farming: %s - %s", tostring(data.w), tostring(data.a))
                        end
                        for _, uid in ipairs(trackedPets) do
                            safe_delay(0, function() JoinCoin(id, {uid}) end)
                            safe_delay(JOIN_DELAY, function() ChangePetTarget(uid, "Coin", id) end)
                            safe_delay(JOIN_DELAY + CHANGE_DELAY, function() FarmCoin(id, uid) end)
                            task.wait(SAFE_DELAY_BETWEEN_ASSIGN)
                        end
                    end
                    pcall(function() ClaimOrbs({}) end)
                end
            end
            task.wait(MAIN_LOOP_DELAY)
        end
    end)

    print("[AutoFarm] ✅ Loaded. Click 'Pick Best Pets' then 'Start'.")

end)

if not ok then
    warn("[AutoFarm] ❌ Failed to run:", mainErr)
else
    print("[AutoFarm] ✅ Script executed successfully!")
end
