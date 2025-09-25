-- PSX AutoFarm (safe, no varargs usage) - paste into NEW LocalScript and run in Delta

local ok, mainErr = pcall(function()

    -- ==== CONFIG ====
    local SAFE_DELAY_BETWEEN_ASSIGN = 0.18
    local JOIN_DELAY = 0.06
    local CHANGE_DELAY = 0.04
    local MAIN_LOOP_DELAY = 0.8
    local EQUIP_WAIT = 0.45

    -- ==== SERVICES ====
    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local LocalPlayer = Players.LocalPlayer
    assert(LocalPlayer, "LocalPlayer nil")
    local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
    local Workspace = game:GetService("Workspace")

    print("[AutoFarm] start - environment OK")

    local Network = ReplicatedStorage:FindFirstChild("Network")
    if not Network then
        warn("[AutoFarm] ReplicatedStorage.Network not found. Remotes may be missing.")
    else
        print("[AutoFarm] Found ReplicatedStorage.Network")
    end

    -- ==== Helper: call remote by name with explicit args table (no varargs usage at definition)
    local function CallRemote(name, argsTable)
        argsTable = argsTable or {}
        if not Network then
            return false, "Network missing"
        end
        local r = Network:FindFirstChild(name)
        if not r then
            return false, ("Remote not found: %s"):format(tostring(name))
        end

        if r.ClassName == "RemoteFunction" then
            -- pass argsTable items as varargs *inside* the function (safe)
            local ok, res = pcall(function()
                return r:InvokeServer(table.unpack(argsTable))
            end)
            if ok then return true, res else return false, res end
        elseif r.ClassName == "RemoteEvent" then
            local ok, res = pcall(function()
                r:FireServer(table.unpack(argsTable))
            end)
            if ok then return true, nil else return false, res end
        else
            return false, ("Remote unexpected class: %s"):format(tostring(r.ClassName))
        end
    end

    -- wrapper helpers (use args table)
    local function GetSave() local ok,res = CallRemote("Get Custom Save", {}) if ok then return res end return nil end
    local function GetCoinsRaw() local ok,res = CallRemote("Get Coins", {}) if ok then return res end local ok2,res2 = CallRemote("Coins: Get Test", {}) if ok2 then return res2 end return nil end
    local function EquipPet(uid) return CallRemote("Equip Pet", {uid}) end
    local function JoinCoin(id, pets) return CallRemote("Join Coin", {id, pets}) end
    local function ChangePetTarget(uid, ttype, id) return CallRemote("Change Pet Target", {uid, ttype, id}) end
    local function FarmCoin(id, uid) return CallRemote("Farm Coin", {id, uid}) end
    local function ClaimOrbs(arg) return CallRemote("Claim Orbs", {arg or {}}) end

    -- safe scheduler
    local function safe_delay(t, f)
        if type(t) == "number" and type(f) == "function" then task.delay(t, f) end
    end

    -- pet utilities
    local function safeNumber(x)
        if type(x)=="number" then return x end
        if type(x)=="string" then return tonumber(x) or 0 end
        return 0
    end

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

    -- state
    local Enabled = false
    local trackedPets = {} -- list of uids

    -- GUI (status includes world/area)
    local function CreateGUI()
        local gui = Instance.new("ScreenGui")
        gui.Name = "PSX_AutoFarm"
        gui.ResetOnSpawn = false
        gui.Parent = PlayerGui

        local frame = Instance.new("Frame", gui)
        frame.Size = UDim2.new(0, 320, 0, 170)
        frame.Position = UDim2.new(0.5, -160, 0.5, -85)
        frame.BackgroundColor3 = Color3.fromRGB(30,30,30)
        Instance.new("UICorner", frame).CornerRadius = UDim.new(0,8)

        local title = Instance.new("TextLabel", frame)
        title.Size = UDim2.new(1, 0, 0, 26)
        title.Position = UDim2.new(0, 0, 0, 6)
        title.BackgroundTransparency = 1
        title.Font = Enum.Font.SourceSansBold
        title.TextSize = 16
        title.TextColor3 = Color3.new(1,1,1)
        title.Text = "PSX AutoFarm"

        local pickBtn = Instance.new("TextButton", frame)
        pickBtn.Size = UDim2.new(0.48, -8, 0, 36)
        pickBtn.Position = UDim2.new(0, 10, 0, 40)
        pickBtn.Text = "Pick Best Pets"
        pickBtn.Font = Enum.Font.SourceSansBold
        pickBtn.BackgroundColor3 = Color3.fromRGB(70,130,180)
        pickBtn.TextColor3 = Color3.new(1,1,1)

        local startBtn = Instance.new("TextButton", frame)
        startBtn.Size = UDim2.new(0.48, -8, 0, 36)
        startBtn.Position = UDim2.new(0, 168, 0, 40)
        startBtn.Text = "Start"
        startBtn.Font = Enum.Font.SourceSansBold
        startBtn.BackgroundColor3 = Color3.fromRGB(34,139,34)
        startBtn.TextColor3 = Color3.new(1,1,1)

        local status = Instance.new("TextLabel", frame)
        status.Size = UDim2.new(1, -20, 0, 52)
        status.Position = UDim2.new(0, 10, 0, 86)
        status.BackgroundTransparency = 1
        status.TextColor3 = Color3.new(1,1,1)
        status.TextWrapped = true
        status.Font = Enum.Font.SourceSans
        status.TextSize = 14
        status.Text = "Status: Idle"

        -- pick button behavior
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

        -- start/stop
        startBtn.MouseButton1Click:Connect(function()
            Enabled = not Enabled
            if Enabled then
                startBtn.Text = "Stop"
                startBtn.BackgroundColor3 = Color3.fromRGB(178,34,34)
                status.Text = "Status: Farming (detecting world/area)..."
            else
                startBtn.Text = "Start"
                startBtn.BackgroundColor3 = Color3.fromRGB(34,139,34)
                status.Text = "Status: Stopped"
            end
        end)

        return {
            Status = status
        }
    end

    local ui = CreateGUI()

    -- main loop: target ALL coins
    task.spawn(function()
        while true do
            if Enabled then
                -- ensure pets equipped
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
                    -- For GUI world/area display: capture first valid coin's w/a
                    local firstW, firstA = nil, nil
                    for id, data in pairs(coins) do
                        if type(data)=="table" and data.w and data.a then
                            firstW, firstA = tostring(data.w), tostring(data.a)
                            break
                        end
                    end
                    if firstW and firstA then
                        ui.Status.Text = ("Farming: %s - %s"):format(firstW, firstA)
                    else
                        ui.Status.Text = "Farming: Unknown area"
                    end

                    -- iterate all coins and send each equipped pet
                    for id, data in pairs(coins) do
                        if type(data) == "table" then
                            -- send each equipped pet to this coin
                            for _, uid in ipairs(trackedPets) do
                                -- use safe delayed calls (no vararg at top-level)
                                safe_delay(0, function() JoinCoin(id, {uid}) end)
                                safe_delay(JOIN_DELAY, function() ChangePetTarget(uid, "Coin", id) end)
                                safe_delay(JOIN_DELAY + CHANGE_DELAY, function() FarmCoin(id, uid) end)
                                task.wait(SAFE_DELAY_BETWEEN_ASSIGN)
                            end
                        end
                    end

                    -- claim orbs / loot
                    pcall(function() ClaimOrbs({}) end)
                end
            end
            task.wait(MAIN_LOOP_DELAY)
        end
    end)

    print("[AutoFarm] Loaded - GUI ready. Pick Best Pets then Start.")

end) -- end pcall

if not ok then
    warn("[AutoFarm] Startup error:", mainErr)
else
    print("[AutoFarm] Script executed successfully!")
end
