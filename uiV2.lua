-- Hate'sQoL + Autofarm combined (single-file)
-- Paste into a NEW LocalScript and run with Delta executor

local ok, mainErr = pcall(function()

-- =========================
-- Minimal Rayfield-like UI (Hate'sQoL) - implements Refresh on dropdowns
-- (keeps API similar: CreateWindow -> CreateFolder -> Label, Button, Toggle, Dropdown, Box, DestroyGui)
-- =========================

local HatesQoL = {}
HatesQoL.__index = HatesQoL

function HatesQoL.CreateWindow(title)
    local gui = Instance.new("ScreenGui")
    gui.Name = "HatesQoL_Root"
    gui.ResetOnSpawn = false
    gui.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")

    local win = {}
    win._gui = gui
    win._title = title or "Hate'sQoL"
    function win:CreateFolder(name)
        local folder = {}
        folder._parent = gui
        folder._name = name or "Folder"
        -- Build a simple panel per folder (we'll place all in a single panel stacked)
        -- For minimal API compatibility, we store children and provide methods below
        folder._objs = {}
        function folder:Label(txt, opts) 
            local lbl = Instance.new("TextLabel", gui)
            lbl.Size = UDim2.new(0,300,0,18)
            lbl.BackgroundTransparency = 1
            lbl.Position = UDim2.new(0,8,0,8 + #gui:GetChildren()*22)
            lbl.Text = tostring(txt or "")
            lbl.Font = Enum.Font.SourceSans
            lbl.TextSize = (opts and opts.TextSize) or 14
            lbl.TextColor3 = (opts and opts.TextColor) or Color3.new(1,1,1)
            table.insert(self._objs, lbl)
            return lbl
        end
        function folder:Button(text, cb)
            local btn = Instance.new("TextButton", gui)
            btn.Size = UDim2.new(0,140,0,28)
            btn.BackgroundColor3 = Color3.fromRGB(20,20,20)
            btn.Position = UDim2.new(0,8,0,8 + #self._objs*34)
            btn.Text = text or "Button"
            btn.Font = Enum.Font.SourceSansBold
            btn.TextSize = 14
            btn.TextColor3 = Color3.new(1,1,1)
            local corner = Instance.new("UICorner", btn); corner.CornerRadius = UDim.new(0,6)
            btn.MouseButton1Click:Connect(function() pcall(function() cb() end) end)
            table.insert(self._objs, btn)
            return btn
        end
        function folder:Toggle(text, cb)
            local frame = Instance.new("Frame", gui)
            frame.Size = UDim2.new(0,300,0,28)
            frame.BackgroundTransparency = 1
            frame.Position = UDim2.new(0,8,0,8 + #self._objs*34)
            local lbl = Instance.new("TextLabel", frame)
            lbl.Size = UDim2.new(0.7,0,1,0); lbl.Position = UDim2.new(0,0,0,0)
            lbl.BackgroundTransparency = 1; lbl.Text = text or "Toggle"; lbl.Font = Enum.Font.SourceSans; lbl.TextSize=14; lbl.TextColor3=Color3.new(1,1,1)
            local btn = Instance.new("TextButton", frame)
            btn.Size = UDim2.new(0.28,0,0.9,0); btn.Position = UDim2.new(0.72,6,0.05,0)
            btn.Text = "Off"; btn.Font = Enum.Font.SourceSans; btn.TextSize = 13; btn.TextColor3 = Color3.new(1,1,1); btn.BackgroundColor3 = Color3.fromRGB(30,30,30)
            local corner = Instance.new("UICorner", btn); corner.CornerRadius = UDim.new(0,6)
            local state = false
            btn.MouseButton1Click:Connect(function()
                state = not state
                btn.Text = state and "On" or "Off"
                pcall(function() cb(state) end)
            end)
            table.insert(self._objs, frame)
            return {
                Set = function(v) state = v; btn.Text = state and "On" or "Off" end
            }
        end
        function folder:Box(label, kind, cb)
            local frame = Instance.new("Frame", gui)
            frame.Size = UDim2.new(0,300,0,28)
            frame.BackgroundTransparency = 1
            frame.Position = UDim2.new(0,8,0,8 + #self._objs*34)
            local lbl = Instance.new("TextLabel", frame)
            lbl.Size = UDim2.new(0.4,0,1,0); lbl.Position = UDim2.new(0,0,0,0)
            lbl.BackgroundTransparency = 1; lbl.Text = label or "Box"; lbl.Font = Enum.Font.SourceSans; lbl.TextSize=14; lbl.TextColor3=Color3.new(1,1,1)
            local tb = Instance.new("TextBox", frame)
            tb.Size = UDim2.new(0.58,0,1,0); tb.Position = UDim2.new(0.42,6,0,0)
            tb.Text = ""; tb.Font = Enum.Font.SourceSans; tb.TextSize = 14; tb.TextColor3 = Color3.new(1,1,1)
            tb.FocusLost:Connect(function(enter) if enter then pcall(function() cb(tb.Text) end) end end)
            table.insert(self._objs, frame)
            return tb
        end
        function folder:Dropdown(label, items, multi, cb)
            -- simple dropdown with SetOptions + Refresh
            local frame = Instance.new("Frame", gui)
            frame.Size = UDim2.new(0,300,0,54)
            frame.BackgroundTransparency = 1
            frame.Position = UDim2.new(0,8,0,8 + #self._objs*34)
            local lbl = Instance.new("TextLabel", frame)
            lbl.Size = UDim2.new(1,0,0,18); lbl.Position = UDim2.new(0,0,0,0); lbl.BackgroundTransparency = 1
            lbl.Text = label or "Select"; lbl.Font=Enum.Font.SourceSans; lbl.TextSize=13; lbl.TextColor3=Color3.new(1,1,1)
            local btn = Instance.new("TextButton", frame)
            btn.Size = UDim2.new(1,0,0,28); btn.Position = UDim2.new(0,0,0,24)
            btn.Text = (items[1] or "None"); btn.Font=Enum.Font.SourceSans; btn.TextSize=14; btn.BackgroundColor3=Color3.fromRGB(24,24,24); btn.TextColor3=Color3.new(1,1,1)
            local menu = Instance.new("Frame", frame)
            menu.Size = UDim2.new(1,0,0,0); menu.Position = UDim2.new(0,0,0,24+28)
            menu.BackgroundColor3 = Color3.fromRGB(18,18,18); menu.Visible = false
            local layout = Instance.new("UIListLayout", menu); layout.Padding = UDim.new(0,4)
            local function populate(list)
                for _,c in ipairs(menu:GetChildren()) do if not c:IsA("UIListLayout") then c:Destroy() end end
                for i,v in ipairs(list) do
                    local opt = Instance.new("TextButton", menu)
                    opt.Size = UDim2.new(1,-8,0,20); opt.Position = UDim2.new(0,4,0,0)
                    opt.BackgroundTransparency = 1
                    opt.Text = tostring(v); opt.Font = Enum.Font.SourceSans; opt.TextSize = 13; opt.TextColor3 = Color3.new(1,1,1)
                    opt.MouseButton1Click:Connect(function()
                        btn.Text = tostring(v)
                        menu.Visible = false
                        pcall(function() cb(v) end)
                    end)
                end
                menu.Size = UDim2.new(1,0,0, math.min(#list*24, 8*24))
            end
            populate(items or {})
            btn.MouseButton1Click:Connect(function() menu.Visible = not menu.Visible end)
            table.insert(self._objs, frame)
            local obj = {}
            function obj.SetOptions(newList) populate(newList) end
            function obj.GetValue() return btn.Text end
            function obj.SetValue(v) btn.Text = v end
            function obj.Refresh() populate(items or {}) end
            return obj
        end

        function folder:DestroyGui()
            for _,c in ipairs(gui:GetChildren()) do pcall(function() c:Destroy() end) end
        end

        return folder
    end

    return win
end

-- =========================
-- End Library
-- =========================

-- ====================================
-- Now the Autofarm logic using the library API
-- ====================================

-- CONFIG
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

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer
assert(LocalPlayer, "LocalPlayer nil - run as LocalScript")

local Network = ReplicatedStorage:FindFirstChild("Network")
if not Network then warn("[HateAF] ReplicatedStorage.Network not found.") end

local function CallRemote(name, args) args = args or {} if not Network then return false,"Network" end local r = Network:FindFirstChild(name) if not r then return false,("Remote not found: %s"):format(tostring(name)) end if r.ClassName=="RemoteFunction" then local ok,res=pcall(function() return r:InvokeServer(table.unpack(args)) end) return ok,res elseif r.ClassName=="RemoteEvent" then local ok,res=pcall(function() r:FireServer(table.unpack(args)) end) return ok,res else return false,("Bad class: %s"):format(r.ClassName) end end

local function GetSave() local ok,res = CallRemote("Get Custom Save", {}) if ok then return res end return nil end
local function GetCoinsRaw() local ok,res = CallRemote("Get Coins", {}) if ok then return res end local ok2,res2 = CallRemote("Coins: Get Test", {}) if ok2 then return res2 end return nil end
local function EquipPet(uid) return CallRemote("Equip Pet", {uid}) end
local function JoinCoin(id, pets) return CallRemote("Join Coin", {id, pets}) end
local function ChangePetTarget(uid, ttype, id) return CallRemote("Change Pet Target", {uid, ttype, id}) end
local function FarmCoin(id, uid) return CallRemote("Farm Coin", {id, uid}) end
local function ClaimOrbs(arg) return CallRemote("Claim Orbs", {arg or {}}) end
local function EquipBestPetsRemote() if not Network then return false end local r = Network:FindFirstChild("Equip Best Pets") if not r then return false end local ok = pcall(function() r:InvokeServer() end) return ok end

-- utils
local function safe_delay(t,f) if type(t)=="number" and type(f)=="function" then task.delay(t,f) end end
local function safeNumber(x) if type(x)=="number" then return x elseif type(x)=="string" then return tonumber(x) or 0 end return 0 end

local function buildPetListFromSave(save)
    if not save then return {} end
    local petsTbl = save.Pets or save.pets or {}
    local out = {}
    for k,v in pairs(petsTbl) do
        if type(v)=="table" then v.uid = v.uid or k table.insert(out, v) end
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

-- state
local SelectedWorld = "Spawn"
local SelectedArea = WorldsTable["Spawn"] and WorldsTable["Spawn"][1] or ""
local Enabled = false
local Mode = "Normal"
local SlowMode = false
local TargetType = "Any"

local trackedPets = {}
local petToTarget = {}
local targetToPet = {}
local petCooldowns = {}
local brokenCount = 0
local startTime = 0

-- Equipped pet helper
local function GetEquippedPetUIDs()
    local uids = {}
    local save = GetSave()
    if save and save.Pets then
        for _,petData in pairs(save.Pets) do
            if type(petData)=="table" and petData.uid then
                local isEq = false
                if petData.equipped==true or petData.eq==true or petData.equip==true then isEq = true end
                if petData[1]==true or petData["1"]==true then isEq = true end
                if isEq then table.insert(uids, petData.uid) end
            end
        end
        if #uids>0 then return uids end
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
    for uid, tid in pairs(petToTarget) do
        if not present[tid] then ClearAssignmentForPet(uid) end
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
        for i=1,count do
            pcall(function() AssignPetToBreakable(freePets[i], available[i].id, false) end)
            task.wait(SAFE_DELAY_BETWEEN_ASSIGN)
        end
    elseif mode=="Safe" then
        local count = math.min(#freePets, #available, 2)
        for i=1,count do
            pcall(function() AssignPetToBreakable(freePets[i], available[i].id, true) end)
            task.wait(0.25 + math.random(0,300)/1000)
        end
    elseif mode=="Blatant" then
        local iPet,iAvail=1,1
        while iPet<=#freePets and iAvail<=#available do
            pcall(function() AssignPetToBreakable(freePets[iPet], available[iAvail].id, false) end)
            iPet=iPet+1; iAvail=iAvail+1
            task.wait(0.01)
        end
    end
end

local function TargetNearestInArea(coins)
    if not coins or not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then return end
    local hrp = LocalPlayer.Character.HumanoidRootPart
    local bestId,bestDist = nil, math.huge
    for id,data in pairs(coins) do
        if type(data)=="table" then
            local w = tostring(data.w or data.world or "")
            local a = tostring(data.a or data.area or "")
            if w==tostring(SelectedWorld) and a==tostring(SelectedArea) and matchesTargetType(TargetType,data) then
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
    local bestId,bestDist = nil, math.huge
    for id,data in pairs(coins) do
        if type(data)=="table" and matchesTargetType(TargetType,data) then
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

-- disable egg animation one-shot
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

-- Anti-AFK
do
    local vu = game:GetService("VirtualUser")
    Players.LocalPlayer.Idled:Connect(function()
        vu:Button2Down(Vector2.new(0,0), workspace.CurrentCamera)
        task.wait(1)
        vu:Button2Up(Vector2.new(0,0), workspace.CurrentCamera)
    end)
end

-- =========================
-- Build UI with Hate'sQoL lib
-- =========================

local uiLib = HatesQoL.CreateWindow("Hate'sQoL")

-- main folder for controls
local main = uiLib:CreateFolder("Main")

local statusLabel = main:Label("Status: Idle", {TextSize=14, TextColor=Color3.fromRGB(220,220,220)})

local pickBtn = main:Button("Pick Best Pets", function()
    statusLabel.Text = "Equipping best pets..."
    local chosen = pickTopNFromSave()
    if #chosen==0 then statusLabel.Text = "No pets found." return end
    trackedPets = chosen
    for _,uid in ipairs(trackedPets) do pcall(function() EquipPet(uid) end); task.wait(0.06) end
    task.wait(EQUIP_WAIT)
    statusLabel.Text = ("Equipped %d pets"):format(#trackedPets)
end)

local startBtn = main:Button("Start/Stop Autofarm", function()
    Enabled = not Enabled
    if Enabled then
        startTime = tick()
        statusLabel.Text = ("Autofarm started (%s - %s)"):format(SelectedWorld, SelectedArea)
    else
        statusLabel.Text = "Autofarm stopped"
    end
end)

local remoteEquipBtn = main:Button("Equip Best (Remote)", function()
    local ok = EquipBestPetsRemote()
    statusLabel.Text = ok and "Remote equip requested." or "Remote equip failed."
end)

local modeLabel = main:Label("Mode (choose one):")
local normalBtn = main:Button("Normal Mode", function() Mode="Normal"; petToTarget={}; targetToPet={}; petCooldowns={}; statusLabel.Text="Mode: Normal" end)
local safeBtn = main:Button("Safe Mode (Stealth)", function() Mode="Safe"; petToTarget={}; targetToPet={}; petCooldowns={}; statusLabel.Text="Mode: Safe" end)
local blatantBtn = main:Button("Blatant Mode", function() Mode="Blatant"; petToTarget={}; targetToPet={}; petCooldowns={}; statusLabel.Text="Mode: Blatant" end)
local nearestAreaBtn = main:Button("Nearest (Area)", function() Mode="NearestArea"; statusLabel.Text="Mode: NearestArea" end)
local nearestGlobalBtn = main:Button("Nearest (Global)", function() Mode="NearestGlobal"; statusLabel.Text="Mode: NearestGlobal" end)

local slowToggle = main:Toggle("Slow Mode", function(v) SlowMode = v end)

local targetDD = main:Dropdown("Target Type", {"Any","Coins","Diamonds","Chests","Breakables"}, false, function(v) TargetType = tostring(v); statusLabel.Text = "Target Type: "..TargetType end)

-- World & Area dropdowns
local worldList = {}
for k,_ in pairs(WorldsTable) do table.insert(worldList,k) end
table.sort(worldList)

local worldDD = main:Dropdown("World", worldList, false, function(sel)
    SelectedWorld = tostring(sel or "")
    local areas = WorldsTable[SelectedWorld] or {}
    areaDD.SetOptions(areas)
    if #areas>0 then areaDD.SetValue(areas[1]); SelectedArea = areas[1] else areaDD.SetValue("None"); SelectedArea = "" end
    petToTarget={}; targetToPet={}; petCooldowns={}
    statusLabel.Text = ("Selected World: %s | Area: %s"):format(SelectedWorld, SelectedArea)
end)

local areaDD = main:Dropdown("Area", WorldsTable[SelectedWorld] or {}, false, function(sel)
    SelectedArea = tostring(sel or "")
    petToTarget={}; targetToPet={}; petCooldowns={}
    statusLabel.Text = ("Selected Area: %s"):format(SelectedArea)
end)

local refreshAreasBtn = main:Button("Refresh Areas", function()
    local areas = WorldsTable[SelectedWorld] or {}
    areaDD.SetOptions(areas)
    if #areas>0 then areaDD.SetValue(areas[1]); SelectedArea = areas[1] else areaDD.SetValue("None"); SelectedArea = "" end
    statusLabel.Text = "Areas refreshed."
end)

local quickNearestBtn = main:Button("Target Nearest (one-shot)", function()
    local coins = GetCoinsRaw()
    if coins then
        if Mode=="NearestGlobal" then TargetNearestGlobal(coins) else TargetNearestInArea(coins) end
        statusLabel.Text = "Nearest target assigned (one-shot)."
    else statusLabel.Text = "No coins data" end
end)

local blatantOneShotBtn = main:Button("Blatant One-shot", function()
    local coins = GetCoinsRaw()
    if coins then FillAssignmentsGeneric(coins, "Blatant"); statusLabel.Text="Blatant attempted" else statusLabel.Text="No coins" end
end)

local eggBtn = main:Button("Disable Egg Animation (one-shot)", function()
    local ok = disableEggAnimationOnce()
    statusLabel.Text = ok and "Egg animation disabled" or "Egg animation already disabled"
end)

-- Always-visible restore button: created as small GUI element
local floatGui = Instance.new("ScreenGui", game:GetService("Players").LocalPlayer.PlayerGui)
floatGui.Name = "HatesQoL_FloatGui"
local floatBtn = Instance.new("TextButton", floatGui)
floatBtn.Size = UDim2.new(0,120,0,24)
floatBtn.Position = UDim2.new(0,6,0,6)
floatBtn.AnchorPoint = Vector2.new(0,0)
floatBtn.Text = "Hate's QoL"
floatBtn.Font = Enum.Font.SourceSansBold
floatBtn.TextSize = 14
floatBtn.BackgroundColor3 = Color3.fromRGB(18,18,18)
floatBtn.TextColor3 = Color3.new(1,1,1)
local round = Instance.new("UICorner", floatBtn); round.CornerRadius = UDim.new(0,6)

-- restore/hide frame (we used simple non-docking GUI, so show/hide main's ScreenGui children)
local rootGui = game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("HatesQoL_Root")
if rootGui then
    floatBtn.MouseButton1Click:Connect(function()
        for _,c in ipairs(rootGui:GetChildren()) do c.Visible = not c.Visible end
    end)
end

-- status/time updater
task.spawn(function()
    while true do
        pcall(function()
            local elapsed = (startTime>0) and math.floor(tick()-startTime) or 0
            local tstr = string.format("%02d:%02d", math.floor(elapsed/60), elapsed%60)
            statusLabel.Text = ("Status: %s | World: %s | Area: %s | Pets: %d | Broken: %d | Time: %s"):format((Enabled and "Farming" or "Idle"), SelectedWorld, SelectedArea, #trackedPets, brokenCount, tstr)
        end)
        task.wait(0.65)
    end
end)

-- main loop
task.spawn(function()
    while true do
        if Enabled then
            if #trackedPets==0 then
                trackedPets = pickTopNFromSave()
                for _,uid in ipairs(trackedPets) do pcall(function() EquipPet(uid) end); task.wait(0.06) end
                task.wait(EQUIP_WAIT)
            end
            local coins = GetCoinsRaw()
            if coins then
                FreeStaleAssignments(coins)
                if Mode=="NearestArea" then
                    TargetNearestInArea(coins)
                elseif Mode=="NearestGlobal" then
                    TargetNearestGlobal(coins)
                else
                    FillAssignmentsGeneric(coins, Mode or "Normal")
                end
                pcall(function() ClaimOrbs({}) end)
                -- lootbags auto-collect
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

print("[HateAF] HatesQoL + Autofarm loaded successfully.")

end) -- pcall

if not ok then
    warn("[HateAF] Startup error:", mainErr)
else
    print("[HateAF] Script executed without immediate error.")
end
