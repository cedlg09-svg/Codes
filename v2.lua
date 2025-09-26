-- Delta-safe bootstrap (prevents line 1 errors / server execution)
if not game or not game:IsLoaded() then repeat task.wait() until game and game:IsLoaded() end
local RunService = game:GetService("RunService")
if RunService:IsServer() then return end

-- Main wrapper to protect startup errors
local ok, mainErr = pcall(function()
    -- ========================
    -- Hate AF - UI V2 + Autofarm
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

    -- ==== MINIMAL UI (dark, not external lib) ====
    local UI = {}
    do
        local function new(cls, props, parent)
            local o = Instance.new(cls)
            if props then for k,v in pairs(props) do if k=="Parent" then o.Parent = v else pcall(function() o[k] = v end) end end end
            if parent then o.Parent = parent end
            return o
        end

        function UI:CreateWindow(title, w,h, pos)
            local gui = new("ScreenGui", {Name = "HateAF_UI_V2", ResetOnSpawn=false}, PlayerGui)
            local frame = new("Frame", {
                Size=UDim2.new(0,w or 380,0,h or 300),
                Position = pos or UDim2.new(0,8,0,36),
                BackgroundColor3 = Color3.fromRGB(12,12,12),
                BorderSizePixel = 0
            }, gui)
            new("UICorner",{Parent=frame, CornerRadius=UDim.new(0,6)})
            local titleLbl = new("TextLabel", {
                Size=UDim2.new(1,-12,0,22), Position=UDim2.new(0,6,0,6),
                BackgroundTransparency=1, Font=Enum.Font.SourceSansBold, TextSize=15, TextColor3=Color3.new(1,1,1), Text=title or ""
            }, frame)
            return {Gui=gui, Frame=frame, Title=titleLbl}
        end

        function UI:CreateButton(win, text, pos, size, cb)
            local btn = new("TextButton", {Size=size or UDim2.new(0.46,-12,0,30), Position=pos, Text=text, Font=Enum.Font.SourceSansBold, TextColor3=Color3.new(1,1,1), BackgroundColor3=Color3.fromRGB(24,24,24)}, win.Frame)
            new("UICorner",{Parent=btn, CornerRadius=UDim.new(0,6)})
            btn.MouseButton1Click:Connect(function() pcall(cb) end)
            return btn
        end

        function UI:CreateToggle(win, text, pos, cb, default)
            local btn = new("TextButton", {Size=UDim2.new(0,88,0,26), Position=pos, Text=(text or "") .. (default and " [On]" or " [Off]"), Font=Enum.Font.SourceSans, BackgroundColor3=Color3.fromRGB(24,24,24), TextColor3=Color3.new(1,1,1)}, win.Frame)
            new("UICorner",{Parent=btn, CornerRadius=UDim.new(0,6)})
            local state = (default==true)
            btn.MouseButton1Click:Connect(function() state = not state; btn.Text = (text or "") .. (state and " [On]" or " [Off]"); pcall(function() cb(state) end) end)
            return {Button=btn, Set=function(v) state=v; btn.Text = (text or "") .. (state and " [On]" or " [Off]") end}
        end

        function UI:CreateDropdown(win, labelText, pos, width, options, cb)
            local lbl = new("TextLabel", {Size=UDim2.new(0,width,0,16), Position=pos, BackgroundTransparency=1, Font=Enum.Font.SourceSans, TextSize=13, TextColor3=Color3.new(1,1,1), Text=labelText}, win.Frame)
            local btn = new("TextButton", {Size=UDim2.new(0,width,0,24), Position=UDim2.new(0,pos.X.Offset,0,pos.Y.Offset+16), Text=options[1] or "None", Font=Enum.Font.SourceSans, BackgroundColor3=Color3.fromRGB(20,20,20), TextColor3=Color3.new(1,1,1)}, win.Frame)
            new("UICorner",{Parent=btn, CornerRadius=UDim.new(0,6)})
            local menu = new("Frame", {Size=UDim2.new(0,width,0,math.min(#options*20,200)), Position=UDim2.new(0,pos.X.Offset,0,pos.Y.Offset+44), BackgroundColor3=Color3.fromRGB(18,18,18), Visible=false, Parent=win.Frame})
            new("UICorner",{Parent=menu, CornerRadius=UDim.new(0,6)})
            local layout = Instance.new("UIListLayout", menu) layout.Padding = UDim.new(0,4)
            local function populate(list)
                for _,c in ipairs(menu:GetChildren()) do if not c:IsA("UIListLayout") then c:Destroy() end end
                for i,v in ipairs(list) do
                    local b = Instance.new("TextButton", menu)
                    b.Size = UDim2.new(1,-8,0,18); b.Position = UDim2.new(0,4,0,0)
                    b.Text = v; b.BackgroundTransparency = 1; b.Font = Enum.Font.SourceSans; b.TextColor3 = Color3.new(1,1,1); b.TextSize = 13; b.AutoButtonColor = true
                    b.MouseButton1Click:Connect(function() btn.Text = v; menu.Visible = false; pcall(function() cb(v) end) end)
                end
                menu.Size = UDim2.new(0, width, 0, math.min(#list*22,200))
            end
            populate(options or {})
            btn.MouseButton1Click:Connect(function() menu.Visible = not menu.Visible end)
            return {SetOptions=function(new) populate(new) end, SetText=function(t) btn.Text=t end, Button=btn}
        end

        function UI:CreateLabel(win, txt, pos, size)
            local lbl = new("TextLabel", {Size=size or UDim2.new(1,-12,0,18), Position=pos, BackgroundTransparency=1, Font=Enum.Font.SourceSans, TextSize=13, TextColor3=Color3.new(1,1,1), Text=txt or ""}, win.Frame)
            return lbl
        end
    end

    -- ==== BUILD WINDOWS / LAYOUT ====
    local main = UI:CreateWindow("Hate's Autofarm — V2", 420, 340, UDim2.new(0,8,0,36))
    local upgrades = UI:CreateWindow("Upgrades (placeholders)", 320, 200, UDim2.new(0,440,0,36))
    local eggs = UI:CreateWindow("Egg Management", 320, 200, UDim2.new(0,440,0,244))
    upgrades.Frame.Visible = false; eggs.Frame.Visible = false

    -- draggable main frame (optional - as requested earlier)
    do
        local frame = main.Frame
        frame.Active = true
        local dragging, dragStart, startPos
        frame.InputBegan:Connect(function(inp)
            if inp.UserInputType==Enum.UserInputType.MouseButton1 then
                dragging=true; dragStart=inp.Position; startPos=frame.Position
                inp.Changed:Connect(function() if inp.UserInputState==Enum.UserInputState.End then dragging=false end end)
            end
        end)
        frame.InputChanged:Connect(function(inp)
            if inp.UserInputType==Enum.UserInputType.MouseMovement and dragging and dragStart and startPos then
                local delta = inp.Position - dragStart
                frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            end
        end)
    end

    -- floating top-left button (visible when minimized)
    local floatBtn = Instance.new("TextButton", PlayerGui)
    floatBtn.Name = "HatesQoL_Float"
    floatBtn.Size = UDim2.new(0,100,0,26)
    floatBtn.Position = UDim2.new(0,8,0,8)
    floatBtn.Text = "Hate's QoL"
    floatBtn.Font = Enum.Font.SourceSansBold
    floatBtn.TextSize = 14
    floatBtn.BackgroundColor3 = Color3.fromRGB(18,18,18)
    floatBtn.TextColor3 = Color3.new(1,1,1)
    floatBtn.ZIndex = 9999
    Instance.new("UICorner", floatBtn).CornerRadius = UDim.new(0,6)
    floatBtn.Visible = false
    floatBtn.MouseButton1Click:Connect(function() floatBtn.Visible=false; main.Frame.Visible=true end)

    -- minimize top-right (20x20)
    local minBtn = Instance.new("TextButton", main.Frame)
    minBtn.Size = UDim2.new(0,20,0,20); minBtn.Position = UDim2.new(1,-26,0,6); minBtn.Text="–"; minBtn.Font=Enum.Font.SourceSansBold; minBtn.TextColor3=Color3.new(1,1,1); minBtn.BackgroundColor3=Color3.fromRGB(18,18,18)
    Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0,6)
    minBtn.MouseButton1Click:Connect(function() main.Frame.Visible=false; floatBtn.Visible=true end)

    -- status label
    local statusLabel = UI:CreateLabel(main, ("Mode:%s | World:%s | Area:%s | Pets:%d | Broken:%d | Time:%s"):format(Mode, SelectedWorld, SelectedArea, #trackedPets, brokenCount, "0s"), UDim2.new(0,8,0,30))

    -- buttons row (top)
    local pickBtn = UI:CreateButton(main, "Pick Best Pets", UDim2.new(0,8,0,56), UDim2.new(0.46,-12,0,34), function()
        statusLabel.Text = "Equipping best pets..."
        local chosen = pickTopNFromSave()
        if #chosen == 0 then statusLabel.Text = "No pets found"; return end
        trackedPets = chosen
        for _, uid in ipairs(trackedPets) do pcall(function() EquipPet(uid) end); task.wait(0.06) end
        task.wait(EQUIP_WAIT)
        statusLabel.Text = ("Equipped %d pets"):format(#trackedPets)
    end)

    local equipRemoteBtn = UI:CreateButton(main, "Equip Best (Remote)", UDim2.new(0,220,0,56), UDim2.new(0.46,-12,0,34), function()
        local ok = EquipBestPetsRemote()
        statusLabel.Text = ok and "Requested remote equip." or "Remote equip failed."
    end)

    -- mode toggles and slow toggle
    local modeToggles = {}
    local function mkMode(text, x,y, modeVal)
        local t = UI:CreateToggle(main, text, UDim2.new(0,x,0,y), function(on)
            if on then
                Mode = modeVal
                for _,other in ipairs(modeToggles) do if other.Name ~= text then other.Set(false) end end
            else
                if Mode == modeVal then Mode = "None" end
            end
        end, false)
        t.Name = text; table.insert(modeToggles, t)
        return t
    end
    mkMode("Normal", 8, 102, "Normal")
    mkMode("Safe", 108, 102, "Safe")
    mkMode("Blatant", 208, 102, "Blatant")
    mkMode("NearestArea", 8, 138, "NearestArea")
    mkMode("NearestGlobal", 136, 138, "NearestGlobal")
    local slowT = UI:CreateToggle(main, "Slow Mode", UDim2.new(0,264,0,102), function(s) SlowMode = s end, false)

    -- target type dropdown (right side)
    local targetDD = UI:CreateDropdown(main, "Target Type", UDim2.new(0,272,0,138), 136, TargetTypeOptions, function(v) TargetType = tostring(v or "Any") end)

    -- world / area dropdowns (5px below buttons)
    local worldOpts = (function() local t={} for k,_ in pairs(WorldsTable) do table.insert(t,k) end table.sort(t) return t end)()
    local worldDD = UI:CreateDropdown(main, "World", UDim2.new(0,8,0,180), 200, worldOpts, function(sel)
        SelectedWorld = tostring(sel or "")
        local areas = WorldsTable[SelectedWorld] or {}
        areaDD.SetOptions(areas)
        if #areas > 0 then SelectedArea = areas[1]; areaDD.SetText(SelectedArea) else SelectedArea = ""; areaDD.SetText("None") end
        petToTarget = {}; targetToPet = {}; petCooldowns = {}
    end)
    worldDD.SetText(SelectedWorld)

    local areaDD = UI:CreateDropdown(main, "Area", UDim2.new(0,220,0,180), 188, WorldsTable[SelectedWorld] or {}, function(sel)
        SelectedArea = tostring(sel or "")
        petToTarget = {}; targetToPet = {}; petCooldowns = {}
    end)
    areaDD.SetText(SelectedArea)

    local refreshBtn = UI:CreateButton(main, "Refresh Areas", UDim2.new(0,220,0,214), UDim2.new(0.46,-12,0,28), function()
        local areas = WorldsTable[SelectedWorld] or {}
        areaDD.SetOptions(areas)
        if #areas>0 then areaDD.SetText(areas[1]); SelectedArea = areas[1] else areaDD.SetText("None"); SelectedArea = "" end
        statusLabel.Text = "Areas refreshed"
    end)

    local startBtn = UI:CreateButton(main, "Start", UDim2.new(0,8,0,246), UDim2.new(1,-16,0,32), function()
        Enabled = not Enabled
        startBtn.Text = Enabled and "Stop" or "Start"
        startBtn.BackgroundColor3 = Enabled and Color3.fromRGB(178,34,34) or Color3.fromRGB(34,139,34)
        if Enabled then startTime = tick() else startTime = 0 end
    end)

    local eggBtn = UI:CreateButton(main, "Egg Management", UDim2.new(0,8,0,288), UDim2.new(0.46,-12,0,28), function() eggs.Frame.Visible = not eggs.Frame.Visible end)
    local upgradesBtn = UI:CreateButton(main, "Upgrades", UDim2.new(0,220,0,288), UDim2.new(0.46,-12,0,28), function() upgrades.Frame.Visible = not upgrades.Frame.Visible end)

    -- eggs window: disable egg animation button (one-shot)
    UI:CreateLabel(eggs, "Egg Management", UDim2.new(0,8,0,24))
    UI:CreateButton(eggs, "Disable Egg Animation (one-shot)", UDim2.new(0,8,0,56), UDim2.new(1,-16,0,28), function()
        local ok = disableEggAnimationOnce()
        eggs.Title.Text = ok and "Egg animation disabled" or "Egg animation already disabled"
    end)

    -- upgrades placeholders
    UI:CreateLabel(upgrades, "Auto Fuse (placeholder)", UDim2.new(0,8,0,32))
    UI:CreateLabel(upgrades, "Auto Gold (placeholder)", UDim2.new(0,8,0,56))
    UI:CreateLabel(upgrades, "Auto Rainbow (placeholder)", UDim2.new(0,8,0,80))
    UI:CreateLabel(upgrades, "Auto Dark Matter (placeholder)", UDim2.new(0,8,0,104))

    -- ==== STATUS UPDATER ====
    task.spawn(function()
        while true do
            pcall(function()
                local elapsed = (startTime>0) and math.floor(tick()-startTime) or 0
                local tstr = string.format("%02d:%02d", math.floor(elapsed/60), elapsed%60)
                statusLabel.Text = ("Mode:%s | World:%s | Area:%s | Pets:%d | Broken:%d | Time:%s"):format(Mode, SelectedWorld, SelectedArea, #trackedPets, brokenCount, tstr)
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

    print("[HateAF] UI V2 loaded. Open the panel or press the floating button if minimized.")
end)

if not ok then
    warn("[HateAF] Startup error:", mainErr)
else
    print("[HateAF] Script executed successfully!")
end
