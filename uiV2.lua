-- HateAF_UI_Final.lua
-- Single LocalScript: Hate's QoL UI + Autofarm (instant show/hide) - paste in NEW LocalScript
-- Designed to be Delta-safe (LocalScript). No external UI libs required.

-- quick guard: ensure client environment
if not game or not game:IsLoaded() then repeat task.wait() until game and game:IsLoaded() end
local RunService = game:GetService("RunService")
if RunService:IsServer() then return end

local ok, mainErr = pcall(function()

    -- ========== CONFIG ==========
    local SAFE_DELAY_BETWEEN_ASSIGN = 0.18
    local JOIN_DELAY = 0.06
    local CHANGE_DELAY = 0.04
    local MAIN_LOOP_DELAY = 0.8
    local EQUIP_WAIT = 0.45
    local RETARGET_DELAY = 0.3

    local WINDOW_W, WINDOW_H = 450, 450

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

    -- ========== SERVICES ==========
    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local Workspace = game:GetService("Workspace")
    local UserInput = game:GetService("UserInputService")
    local LocalPlayer = Players.LocalPlayer
    assert(LocalPlayer, "LocalPlayer nil - run as LocalScript")
    local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

    local Network = ReplicatedStorage:FindFirstChild("Network")
    if not Network then warn("[HateAF] ReplicatedStorage.Network not found. Remotes may be missing.") end

    -- ========== SAFE REMOTE CALL ========== (no top-level varargs)
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

    -- ========== UTILITIES ==========
    local function safe_delay(t, f) if type(t)=="number" and type(f)=="function" then task.delay(t, f) end end
    local function safeNumber(x) if type(x)=="number" then return x elseif type(x)=="string" then return tonumber(x) or 0 end return 0 end

    local function buildPetListFromSave(save)
        if not save then return {} end
        local petsTbl = save.Pets or save.pets or {}
        local out = {}
        for k,v in pairs(petsTbl) do
            if type(v)=="table" then v.uid = v.uid or k; table.insert(out, v) end
        end
        return out
    end

    local function sortByPowerDesc(list)
        table.sort(list, function(a,b) return safeNumber(a.s or a.power or a.p or 0) > safeNumber(b.s or b.power or b.p or 0) end)
    end

    local function pickTopNFromSave(n)
        local save = GetSave()
        if not save then return {} end
        local maxEquip = tonumber(save.MaxEquipped or save["P MaxEquipped"] or save["PMaxEquipped"]) or 8
        if n then maxEquip = n end
        local all = buildPetListFromSave(save)
        sortByPowerDesc(all)
        local chosen = {}
        for i=1, math.min(maxEquip, #all) do if all[i] and all[i].uid then table.insert(chosen, all[i].uid) end end
        return chosen
    end

    local function GetEquippedPetUIDs()
        local uids = {}
        local save = GetSave()
        if save and save.Pets then
            for _, petData in pairs(save.Pets) do
                if type(petData)=="table" and petData.uid then
                    local isEq = false
                    if petData.equipped == true or petData.eq == true or petData.equip == true then isEq = true end
                    if petData[1] == true or petData["1"] == true then isEq = true end
                    if isEq then table.insert(uids, petData.uid) end
                end
            end
            if #uids>0 then return uids end
        end
        return pickTopNFromSave()
    end

    -- ========== STATE ==========
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

    -- ========== ANTI-AFK (one-shot) ==========
    pcall(function()
        local vu = game:GetService("VirtualUser")
        Players.LocalPlayer.Idled:Connect(function()
            vu:Button2Down(Vector2.new(0,0), workspace.CurrentCamera)
            task.wait(1)
            vu:Button2Up(Vector2.new(0,0), workspace.CurrentCamera)
        end)
    end)

    -- ========== EGG ANIMATION DISABLE (one-shot) ==========
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

    -- ========== TARGET TYPE MATCHER ==========
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

    -- ========== ASSIGNMENT HELPERS ==========
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
        if coins then for id,_ in pairs(coins) do present[id] = true end end
        for uid,id in pairs(petToTarget) do
            if not present[id] then ClearAssignmentForPet(uid) end
        end
    end

    local function GetAvailableBreakablesForArea(coins)
        local available = {}
        if not coins then return available end
        for id,item in pairs(coins) do
            if type(item)=="table" then
                local w = tostring(item.w or item.world or "")
                local a = tostring(item.a or item.area or "")
                if w==tostring(SelectedWorld) and a==tostring(SelectedArea) and not targetToPet[id] and matchesTargetType(TargetType, item) then
                    table.insert(available, {id=id, data=item})
                end
            end
        end
        return available
    end

    local function FillAssignmentsGeneric(coins, mode)
        local petUIDs = GetEquippedPetUIDs()
        if #petUIDs==0 then return end

        local freePets = {}
        for _,uid in ipairs(petUIDs) do
            if not petToTarget[uid] then
                local cd = petCooldowns[uid] or 0
                if tick() >= cd then table.insert(freePets, uid) end
            end
        end
        if #freePets==0 then return end

        local available = GetAvailableBreakablesForArea(coins)
        if #available==0 then return end

        if mode=="Normal" then
            local count = math.min(#freePets, #available)
            for i=1,count do pcall(function() AssignPetToBreakable(freePets[i], available[i].id, false) end); task.wait(SAFE_DELAY_BETWEEN_ASSIGN) end
        elseif mode=="Safe" then
            local count = math.min(#freePets, #available, 2)
            for i=1,count do pcall(function() AssignPetToBreakable(freePets[i], available[i].id, true) end); task.wait(0.25 + math.random(0,300)/1000) end
        elseif mode=="Blatant" then
            local iPet,iAvail = 1,1
            while iPet <= #freePets and iAvail <= #available do
                pcall(function() AssignPetToBreakable(freePets[iPet], available[iAvail].id, false) end)
                iPet = iPet + 1; iAvail = iAvail + 1
                task.wait(0.01)
            end
        end
    end

    -- nearest-target functions
    local function TargetNearestInArea(coins)
        if not coins or not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then return end
        local hrp = LocalPlayer.Character.HumanoidRootPart
        local bestId, bestDist = nil, math.huge
        for id,data in pairs(coins) do
            if type(data)=="table" then
                local w = tostring(data.w or data.world or "")
                local a = tostring(data.a or data.area or "")
                if w==tostring(SelectedWorld) and a==tostring(SelectedArea) and matchesTargetType(TargetType, data) then
                    local p = data.p
                    if p and typeof(p)=="Vector3" then
                        local d = (hrp.Position - p).Magnitude
                        if d < bestDist then bestDist = d; bestId = id end
                    end
                end
            end
        end
        if not bestId then return end
        local petUIDs = GetEquippedPetUIDs()
        for _,uid in ipairs(petUIDs) do
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
        for id,data in pairs(coins) do
            if type(data)=="table" and matchesTargetType(TargetType, data) then
                local p = data.p
                if p and typeof(p)=="Vector3" then
                    local d = (hrp.Position - p).Magnitude
                    if d < bestDist then bestDist = d; bestId = id end
                end
            end
        end
        if not bestId then return end
        local petUIDs = GetEquippedPetUIDs()
        for _,uid in ipairs(petUIDs) do
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

    -- ========== UI BUILD ==========
    local function new(class, props)
        local o = Instance.new(class)
        if props then for k,v in pairs(props) do if k=="Parent" then o.Parent = v else pcall(function() o[k] = v end) end end end
        return o
    end

    -- top-level screenGui
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "HateQoL_UI"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = PlayerGui

    -- main window
    local frame = new("Frame", {
        Parent = screenGui,
        Size = UDim2.new(0, WINDOW_W, 0, WINDOW_H),
        Position = UDim2.new(0, 8, 0, 36),
        BackgroundColor3 = Color3.fromRGB(12,12,12),
        BorderSizePixel = 0
    })
    new("UICorner", {Parent = frame, CornerRadius = UDim.new(0,8)})
    local title = new("TextLabel", {Parent = frame, Size=UDim2.new(1,-12,0,24), Position=UDim2.new(0,6,0,6), BackgroundTransparency=1, Font=Enum.Font.SourceSansBold, TextSize=16, TextColor3=Color3.new(1,1,1), Text="Hate's QoL — Hate's Autofarm", TextXAlignment=Enum.TextXAlignment.Left})

    -- floating always-visible show/hide button (top-right 50x50)
    local floatBtn = new("TextButton", {
        Parent = PlayerGui,
        Name = "HateQoL_Float",
        Size = UDim2.new(0,50,0,50),
        Position = UDim2.new(1,-58,0,8),
        AnchorPoint = Vector2.new(0,0),
        BackgroundColor3 = Color3.fromRGB(20,20,20),
        Text = "Hate",
        Font = Enum.Font.SourceSansBold,
        TextSize = 14,
        TextColor3 = Color3.new(1,1,1),
        ZIndex = 50
    })
    new("UICorner", {Parent = floatBtn, CornerRadius = UDim.new(0,8)})
    floatBtn.Visible = true
    floatBtn.MouseButton1Click:Connect(function()
        frame.Visible = not frame.Visible
    end)

    -- top-middle small min button (instant hide/show)
    local topMin = new("TextButton", {Parent = frame, Size = UDim2.new(0,28,0,20), Position = UDim2.new(0.5,-14,0,6), Text="■", Font=Enum.Font.SourceSansBold, TextColor3=Color3.new(1,1,1), BackgroundColor3=Color3.fromRGB(18,18,18)})
    new("UICorner", {Parent = topMin, CornerRadius = UDim.new(0,6)})
    topMin.MouseButton1Click:Connect(function() frame.Visible = not frame.Visible end)

    -- Status label horizontal at top (below title)
    local statusLabel = new("TextLabel", {Parent = frame, Size = UDim2.new(1,-16,0,18), Position = UDim2.new(0,8,0,34), BackgroundTransparency = 1, Font = Enum.Font.SourceSans, TextSize = 13, TextColor3 = Color3.fromRGB(220,220,220), Text = "Status: Idle", TextXAlignment=Enum.TextXAlignment.Left})

    -- left column buttons (stacked)
    local leftX, leftW = 12, 180
    local function MakeButton(text, y, w)
        local b = new("TextButton", {Parent = frame, Position = UDim2.new(0,leftX,0,y), Size=UDim2.new(0,w or leftW,0,34), Text=text, Font=Enum.Font.SourceSansBold, TextColor3=Color3.new(1,1,1), BackgroundColor3=Color3.fromRGB(28,28,28)})
        new("UICorner", {Parent=b, CornerRadius = UDim.new(0,6)})
        return b
    end

    local pickBtn = MakeButton("Pick Best Pets", 60)
    local equipRemoteBtn = MakeButton("Equip Best (Remote)", 60+44, 180)
    local startBtn = MakeButton("Start", 60+88, 180)
    local blatantBtn = MakeButton("Blatant Farm", 60+132, 180)

    -- mode toggles (we'll display as small buttons to ensure no layout overlap)
    local function MakeToggleBtn(txt, x, y)
        local b = new("TextButton", {Parent = frame, Position = UDim2.new(0,x,0,y), Size=UDim2.new(0,84,0,28), Text=txt.." [Off]", Font=Enum.Font.SourceSans, TextColor3=Color3.new(1,1,1), BackgroundColor3=Color3.fromRGB(24,24,24)})
        new("UICorner", {Parent=b, CornerRadius = UDim.new(0,6)})
        local state = false
        local obj = {Button = b, Set = function(s) state = s; b.Text = txt..(state and " [On]" or " [Off]") end}
        b.MouseButton1Click:Connect(function()
            state = not state
            b.Text = txt..(state and " [On]" or " [Off]")
            if txt == "Safe" then if state then Mode = "Safe" else Mode = "None" end end
            if txt == "Normal" then if state then Mode = "Normal" else Mode = "None" end end
            if txt == "Blatant" then if state then Mode = "Blatant" else Mode = "None" end end
            if txt == "NearestArea" then if state then Mode = "NearestArea" else Mode = "None" end end
            if txt == "NearestGlobal" then if state then Mode = "NearestGlobal" else Mode = "None" end end
        end)
        return obj
    end

    local normalT = MakeToggleBtn("Normal", 210, 60)
    local safeT = MakeToggleBtn("Safe", 210+92, 60)
    local blatantT = MakeToggleBtn("Blatant", 210, 100)
    local nearestAreaT = MakeToggleBtn("NearestArea", 210+92, 100)
    local nearestGlobalT = MakeToggleBtn("NearestGlobal", 210, 140)

    -- slow mode toggle
    local slowBtn = new("TextButton", {Parent = frame, Position = UDim2.new(0,340,0,60), Size = UDim2.new(0,90,0,28), Text="Slow Mode [Off]", Font=Enum.Font.SourceSans, TextColor3=Color3.new(1,1,1), BackgroundColor3=Color3.fromRGB(24,24,24)})
    new("UICorner", {Parent=slowBtn, CornerRadius = UDim.new(0,6)})
    slowBtn.MouseButton1Click:Connect(function()
        SlowMode = not SlowMode
        slowBtn.Text = "Slow Mode ["..(SlowMode and "On" or "Off").."]"
    end)

    -- target type dropdown (right side)
    -- dropdown implementation: top-level popup to avoid overlap:
    local function CreateDropdown(parent, xOffset, yOffset, width, labelText, options, onSelect)
        options = options or {}
        local lbl = new("TextLabel", {Parent = parent, Position = UDim2.new(0,xOffset,0,yOffset), Size = UDim2.new(0,width,0,16), BackgroundTransparency=1, Font=Enum.Font.SourceSans, TextSize=13, TextColor3=Color3.new(1,1,1), Text=labelText})
        local btn = new("TextButton", {Parent = parent, Position = UDim2.new(0,xOffset,0,yOffset+16), Size = UDim2.new(0,width,0,26), Text = tostring(options[1] or "None"), Font=Enum.Font.SourceSans, BackgroundColor3=Color3.fromRGB(22,22,22), TextColor3=Color3.new(1,1,1)})
        new("UICorner", {Parent=btn, CornerRadius = UDim.new(0,6)})

        -- popup will be separate top-level Frame under screenGui to avoid clipping
        local popup = new("Frame", {Parent = screenGui, Size = UDim2.new(0,width,0,math.min(#options*22,220)), BackgroundColor3 = Color3.fromRGB(20,20,20), Visible = false})
        new("UICorner", {Parent=popup, CornerRadius = UDim.new(0,6)})
        local layout = Instance.new("UIListLayout", popup); layout.Padding = UDim.new(0,4)

        local function populate(list)
            for _,c in ipairs(popup:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
            for _,opt in ipairs(list) do
                local it = new("TextButton", {Parent = popup, Size = UDim2.new(1,-8,0,20), Position = UDim2.new(0,4,0,0), Text = tostring(opt), BackgroundTransparency = 1, Font = Enum.Font.SourceSans, TextColor3 = Color3.new(1,1,1), AutoButtonColor = true})
                it.MouseButton1Click:Connect(function()
                    btn.Text = tostring(opt)
                    popup.Visible = false
                    pcall(onSelect, opt)
                end)
            end
            popup.Size = UDim2.new(0,width,0,math.min(#list*22,220))
        end
        populate(options)

        local function placePopup()
            local absPos = btn.AbsolutePosition
            popup.Position = UDim2.new(0, absPos.X, 0, absPos.Y + btn.AbsoluteSize.Y)
            popup.ZIndex = 50
        end

        btn.MouseButton1Click:Connect(function()
            popup.Visible = not popup.Visible
            if popup.Visible then placePopup() end
        end)

        -- click outside closes popup
        UserInput.InputBegan:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
                if popup.Visible then
                    local m = UserInput:GetMouseLocation()
                    local pPos = popup.AbsolutePosition; local pSize = popup.AbsoluteSize
                    local onPopup = (m.X >= pPos.X and m.X <= pPos.X+pSize.X and m.Y >= pPos.Y and m.Y <= pPos.Y+pSize.Y)
                    local bPos = btn.AbsolutePosition; local bSize = btn.AbsoluteSize
                    local onBtn = (m.X >= bPos.X and m.X <= bPos.X+bSize.X and m.Y >= bPos.Y and m.Y <= bPos.Y+bSize.Y)
                    if not (onPopup or onBtn) then popup.Visible = false end
                end
            end
        end)

        return {Label = lbl, Button = btn, Popup = popup, SetOptions = function(list) populate(list or {}) end, SetText = function(t) btn.Text = tostring(t or "None") end, GetValue = function() return btn.Text end}
    end

    -- place dropdowns below buttons by ~5px offset
    local worldOpts = (function() local t={} for k,_ in pairs(WorldsTable) do table.insert(t,k) end table.sort(t); return t end)()
    local worldDD = CreateDropdown(frame, 12, 210, 200, "World", worldOpts, function(sel)
        SelectedWorld = tostring(sel or "")
        local areas = WorldsTable[SelectedWorld] or {}
        areaDD.SetOptions(areas)
        if #areas>0 then SelectedArea = areas[1]; areaDD.SetText(SelectedArea) else SelectedArea = ""; areaDD.SetText("None") end
        -- clear assignments
        petToTarget = {}; targetToPet = {}; petCooldowns = {}
    end)
    worldDD.SetText(SelectedWorld)

    local areaDD = CreateDropdown(frame, 236, 210, 200, "Area", WorldsTable[SelectedWorld] or {}, function(sel)
        SelectedArea = tostring(sel or "")
        petToTarget = {}; targetToPet = {}; petCooldowns = {}
    end)
    areaDD.SetText(SelectedArea)

    local targetDD = CreateDropdown(frame, 236, 260, 200, "Target Type", TargetTypeOptions, function(sel)
        TargetType = tostring(sel or "Any")
    end)
    targetDD.SetText(TargetType)

    -- Refresh Areas button
    local refreshBtn = MakeButton("Refresh Areas", 300, 180)
    refreshBtn.Position = UDim2.new(0, 236, 0, 300)
    refreshBtn.MouseButton1Click:Connect(function()
        local areas = WorldsTable[SelectedWorld] or {}
        areaDD.SetOptions(areas)
        if #areas>0 then areaDD.SetText(areas[1]); SelectedArea = areas[1] else areaDD.SetText("None"); SelectedArea = "" end
        statusLabel.Text = "Areas refreshed"
    end)

    -- egg window (instant show/hide)
    local eggsWin = new("Frame", {Parent = screenGui, Size = UDim2.new(0,320,0,200), Position = UDim2.new(0, WINDOW_W+24, 0, 36), BackgroundColor3 = Color3.fromRGB(14,14,14), Visible = false})
    new("UICorner", {Parent = eggsWin, CornerRadius = UDim.new(0,8)})
    local eggsTitle = new("TextLabel", {Parent = eggsWin, Size = UDim2.new(1,-12,0,28), Position = UDim2.new(0,6,0,6), BackgroundTransparency=1, Font=Enum.Font.SourceSansBold, Text="🥚 Egg Management", TextColor3=Color3.new(1,1,1)})
    local eggBtn = new("TextButton", {Parent = eggsWin, Position = UDim2.new(0,8,0,44), Size=UDim2.new(1,-16,0,28), Text="Disable Hatching Animation (one-shot)", Font=Enum.Font.SourceSans, BackgroundColor3=Color3.fromRGB(24,24,24), TextColor3=Color3.new(1,1,1)})
    new("UICorner", {Parent=eggBtn, CornerRadius=UDim.new(0,6)})
    eggBtn.MouseButton1Click:Connect(function()
        local ok = disableEggAnimationOnce()
        eggsTitle.Text = ok and "🥚 Egg Management — Disabled" or "🥚 Egg Management — Already disabled"
    end)

    -- Upgrades window (placeholders)
    local upWin = new("Frame", {Parent = screenGui, Size = UDim2.new(0,320,0,200), Position = UDim2.new(0, WINDOW_W+24, 0, 244), BackgroundColor3 = Color3.fromRGB(14,14,14), Visible = false})
    new("UICorner", {Parent = upWin, CornerRadius = UDim.new(0,8)})
    new("TextLabel", {Parent = upWin, Size = UDim2.new(1,-12,0,28), Position = UDim2.new(0,6,0,6), BackgroundTransparency=1, Font=Enum.Font.SourceSansBold, Text="🛠️ Upgrades (placeholders)", TextColor3=Color3.new(1,1,1)})
    new("TextLabel", {Parent = upWin, Size = UDim2.new(1,-12,0,20), Position = UDim2.new(0,8,0,44), BackgroundTransparency=1, Font=Enum.Font.SourceSans, Text="Auto Fuse (placeholder)", TextColor3=Color3.new(1,1,1)})
    new("TextLabel", {Parent = upWin, Size = UDim2.new(1,-12,0,20), Position = UDim2.new(0,8,0,68), BackgroundTransparency=1, Font=Enum.Font.SourceSans, Text="Auto Rainbow (placeholder)", TextColor3=Color3.new(1,1,1)})
    new("TextLabel", {Parent = upWin, Size = UDim2.new(1,-12,0,20), Position = UDim2.new(0,8,0,92), BackgroundTransparency=1, Font=Enum.Font.SourceSans, Text="Auto Gold (placeholder)", TextColor3=Color3.new(1,1,1)})

    -- open/close egg/upgrades buttons (below)
    local eggsToggleBtn = MakeButton("Egg Management", 340)
    eggsToggleBtn.Position = UDim2.new(0, 12, 0, 340)
    eggsToggleBtn.MouseButton1Click:Connect(function()
        eggsWin.Visible = not eggsWin.Visible
        if eggsWin.Visible then upWin.Visible = false end
    end)

    local upToggleBtn = MakeButton("Upgrades", 340, 180)
    upToggleBtn.Position = UDim2.new(0, 220, 0, 340)
    upToggleBtn.MouseButton1Click:Connect(function()
        upWin.Visible = not upWin.Visible
        if upWin.Visible then eggsWin.Visible = false end
    end)

    -- ========== BUTTON BEHAVIORS ==========
    pickBtn.MouseButton1Click:Connect(function()
        statusLabel.Text = "Equipping best pets..."
        local chosen = pickTopNFromSave()
        if #chosen == 0 then statusLabel.Text = "Status: No pets found"; return end
        trackedPets = chosen
        for _,uid in ipairs(trackedPets) do pcall(function() EquipPet(uid) end); task.wait(0.06) end
        task.wait(EQUIP_WAIT)
        statusLabel.Text = ("Equipped %d pets"):format(#trackedPets)
    end)

    equipRemoteBtn.MouseButton1Click:Connect(function()
        local ok = EquipBestPetsRemote()
        statusLabel.Text = ok and "Remote equip requested" or "Remote equip failed"
    end)

    startBtn.MouseButton1Click:Connect(function()
        Enabled = not Enabled
        startBtn.Text = Enabled and "Stop" or "Start"
        startBtn.BackgroundColor3 = Enabled and Color3.fromRGB(178,34,34) or Color3.fromRGB(34,139,34)
        if Enabled then startTime = tick() else startTime = 0 end
    end)

    blatantBtn.MouseButton1Click:Connect(function()
        Mode = "Blatant"
        statusLabel.Text = "Mode set to Blatant (button)"
    end)

    -- mode toggles already wired inside MakeToggleBtn (they set Mode variable)

    -- ========== DRAGGABLE MAIN WINDOW ==========
    do
        local dragging, dragStart, startPos
        frame.InputBegan:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = true; dragStart = inp.Position; startPos = frame.Position
                inp.Changed:Connect(function()
                    if inp.UserInputState == Enum.UserInputState.End then dragging = false end
                end)
            end
        end)
        UserInput.InputChanged:Connect(function(inp)
            if dragging and (inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch) and dragStart and startPos then
                local delta = inp.Position - dragStart
                frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
                -- sync eggs/upgrades nearby
                eggsWin.Position = UDim2.new(0, frame.AbsolutePosition.X + frame.AbsoluteSize.X + 16, 0, frame.AbsolutePosition.Y)
                upWin.Position = UDim2.new(0, frame.AbsolutePosition.X + frame.AbsoluteSize.X + 16, 0, frame.AbsolutePosition.Y + 208)
            end
        end)
    end

    -- ensure eggs and upgrades follow default pos
    eggsWin.Position = UDim2.new(0, frame.AbsolutePosition.X + frame.AbsoluteSize.X + 16, 0, frame.AbsolutePosition.Y)
    upWin.Position = UDim2.new(0, frame.AbsolutePosition.X + frame.AbsoluteSize.X + 16, 0, frame.AbsolutePosition.Y + 208)

    -- ========== STATUS UPDATER ==========
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

    -- ========== MAIN FARM LOOP ==========
    task.spawn(function()
        while true do
            if Enabled then
                if #trackedPets == 0 then
                    trackedPets = pickTopNFromSave()
                    for _,uid in ipairs(trackedPets) do pcall(function() EquipPet(uid) end); task.wait(0.06) end
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
                    else
                        -- if no mode selected, default to Normal behavior
                        FillAssignmentsGeneric(coins, "Normal")
                    end

                    pcall(function() ClaimOrbs({}) end)
                    pcall(function()
                        local things = Workspace:FindFirstChild("__THINGS") or Workspace:FindFirstChild("__things")
                        if things then
                            local bags = things:FindFirstChild("Lootbags")
                            if bags and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                                for _, bag in ipairs(bags:GetChildren()) do
                                    if bag and bag:IsA("BasePart") then pcall(function() bag.CFrame = LocalPlayer.Character.HumanoidRootPart.CFrame end) end
                                end
                            end
                        end
                    end)
                end
            end
            task.wait((SlowMode and MAIN_LOOP_DELAY*1.6) or MAIN_LOOP_DELAY)
        end
    end)

    print("[HateAF] UI V2 loaded. Main window at top-left. Use the top-right small 'Hate' button to hide/show.")
end)

if not ok then
    warn("[HateAF] Startup error:", mainErr)
else
    print("[HateAF] Script executed successfully!")
end
