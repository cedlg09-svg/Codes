-- Delta-safe bootstrap (prevents line 1 errors / server execution)
if not game or not game:IsLoaded() then repeat task.wait() until game and game:IsLoaded() end
local RunService = game:GetService("RunService")
if RunService:IsServer() then return end

-- Main wrapper to protect startup errors
local ok, mainErr = pcall(function()
    -- ========================
    -- Hate AF - UI replaced with Fluent (keeps logic intact)
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

    -- ==== FLUENT UI LOADING (with fallback to old UI) ====
    local Fluent = nil
    local Window = nil
    local Tabs = nil
    local fluentScreenGui = nil -- we will attempt to detect the ScreenGui created by Fluent
    local fallbackUsed = false

    -- helper to detect new ScreenGui created by Fluent
    local function detectNewScreenGui(before)
        for _,child in ipairs(PlayerGui:GetChildren()) do
            if child:IsA("ScreenGui") and not before[child] then
                return child
            end
        end
        return nil
    end

    -- record before
    local beforeGUIs = {}
    for _,g in ipairs(PlayerGui:GetChildren()) do beforeGUIs[g] = true end

    -- try load Fluent (from release)
    local okLoad, loadRes = pcall(function()
        return loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
    end)
    if okLoad and loadRes then
        Fluent = loadRes
    else
        Fluent = nil
    end

    -- Minimal compatibility wrappers for Fluent methods we use (if present)
    if Fluent then
        -- Create Window
        local successWindow, win = pcall(function()
            return Fluent:CreateWindow({
                Title = "Hate's Autofarm — V2 " .. (Fluent.Version or ""),
                SubTitle = "Hate AF",
                TabWidth = 160,
                Size = UDim2.fromOffset(640, 420),
                Acrylic = false,
                Theme = "Dark",
                MinimizeKey = Enum.KeyCode.LeftControl
            })
        end)
        if successWindow and win then
            Window = win
            -- Add tabs
            Tabs = {}
            Tabs.Main = Window:AddTab({ Title = "Main", Icon = "home" })
            Tabs.Eggs = Window:AddTab({ Title = "Eggs", Icon = "box" })
            Tabs.Upgrades = Window:AddTab({ Title = "Upgrades", Icon = "sparkles" })
            -- detect created ScreenGui
            task.defer(function()
                task.wait(0.05)
                fluentScreenGui = detectNewScreenGui(beforeGUIs)
            end)
        else
            Fluent = nil
        end
    end

    -- fallback old UI builder (used if Fluent doesn't load)
    local OldUI = {}
    do
        local function new(cls, props, parent)
            local o = Instance.new(cls)
            if props then for k,v in pairs(props) do if k=="Parent" then o.Parent = v else pcall(function() o[k] = v end) end end end
            if parent then o.Parent = parent end
            return o
        end

        function OldUI:CreateWindow(title, w,h, pos)
            local gui = new("ScreenGui", {Name = "HateAF_UI_Fallback", ResetOnSpawn=false}, PlayerGui)
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

        function OldUI:CreateButton(win, text, pos, size, cb)
            local btn = new("TextButton", {Size=size or UDim2.new(0.46,-12,0,30), Position=pos, Text=text, Font=Enum.Font.SourceSansBold, TextColor3=Color3.new(1,1,1), BackgroundColor3=Color3.fromRGB(24,24,24)}, win.Frame)
            new("UICorner",{Parent=btn, CornerRadius=UDim.new(0,6)})
            btn.MouseButton1Click:Connect(function() pcall(cb) end)
            return btn
        end

        function OldUI:CreateToggle(win, text, pos, cb, default)
            local btn = new("TextButton", {Size=UDim2.new(0,88,0,26), Position=pos, Text=(text or "") .. (default and " [On]" or " [Off]"), Font=Enum.Font.SourceSans, BackgroundColor3=Color3.fromRGB(24,24,24), TextColor3=Color3.new(1,1,1)}, win.Frame)
            new("UICorner",{Parent=btn, CornerRadius=UDim.new(0,6)})
            local state = (default==true)
            btn.MouseButton1Click:Connect(function() state = not state; btn.Text = (text or "") .. (state and " [On]" or " [Off]"); pcall(function() cb(state) end) end)
            return {Button=btn, Set=function(v) state=v; btn.Text = (text or "") .. (state and " [On]" or " [Off]") end}
        end

        function OldUI:CreateDropdown(win, labelText, pos, width, options, cb)
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

        function OldUI:CreateLabel(win, txt, pos, size)
            local lbl = new("TextLabel", {Size=size or UDim2.new(1,-12,0,18), Position=pos, BackgroundTransparency=1, Font=Enum.Font.SourceSans, TextSize=13, TextColor3=Color3.new(1,1,1), Text=txt or ""}, win.Frame)
            return lbl
        end
    end

    -- Build UI either with Fluent (preferred) or fallback
    local ui = {}
    local statusLabelUpdater = nil

    if Fluent and Window and Tabs then
        -- FLUENT UI BUILD
        local MainTab = Tabs.Main
        local EggsTab = Tabs.Eggs
        local UpgradesTab = Tabs.Upgrades

        -- We will attempt to use common Fluent element APIs. If the exact function signatures differ,
        -- Fluent users typically provide similar AddButton/AddToggle/AddDropdown/AddLabel APIs.
        -- We protect-callbacks with pcall.

        -- Status label: We'll put a simple text item in Main tab (Fluent: AddLabel or AddParagraph)
        local statusText = "Mode:None | World:Spawn | Area:" .. tostring(SelectedArea) .. " | Pets:0 | Broken:0 | Time:00:00"
        local statusElem = nil
        pcall(function()
            -- many Fluent examples provide AddLabel or AddParagraph; try AddLabel then AddParagraph then AddButton fallback
            if MainTab.AddLabel then
                statusElem = MainTab:AddLabel({Title = statusText})
            elseif MainTab:AddParagraph then
                statusElem = MainTab:AddParagraph({Title = statusText})
            end
        end)

        local function setStatusText(t)
            -- attempt to update label via likely fields
            pcall(function()
                if statusElem and statusElem.Set then
                    statusElem:Set(t)
                    return
                elseif statusElem and statusElem.Update then
                    statusElem:Update(t)
                    return
                elseif statusElem and statusElem.Title then
                    statusElem.Title = t
                    return
                elseif fluentScreenGui then
                    -- fallback: find any TextLabel descendant with matching text and update
                    for _,v in ipairs(fluentScreenGui:GetDescendants()) do
                        if v:IsA("TextLabel") and tostring(v.Text):sub(1,5) == "Mode:" then
                            v.Text = t
                            return
                        end
                    end
                end
            end)
        end
        statusLabelUpdater = setStatusText
        setStatusText(statusText)

        -- Helper to create mode toggle behaviour (mutually exclusive)
        local modeButtons = {}
        local function addModeButton(title, modeVal)
            pcall(function()
                if MainTab.AddToggle then
                    local el = MainTab:AddToggle({ Title = title, Default = (Mode == modeVal), Callback = function(on)
                        if on then
                            Mode = modeVal
                            -- turn others off
                            for _,btn in ipairs(modeButtons) do
                                if btn and btn.Set and btn.Title ~= title then pcall(function() btn.Set(false) end) end
                            end
                        else
                            if Mode == modeVal then Mode = "None" end
                        end
                    end })
                    el.Title = title
                    table.insert(modeButtons, el)
                else
                    -- fallback: AddButton that toggles text
                    local btn = MainTab:AddButton({ Title = title, Callback = function()
                        if Mode == modeVal then Mode = "None"; pcall(function() btn:SetTitle(title) end)
                        else Mode = modeVal; pcall(function() btn:SetTitle(title .. " [On]") end) end
                    end })
                    table.insert(modeButtons, btn)
                end
            end)
        end

        -- Add controls to Main
        pcall(function()
            -- Buttons row
            if MainTab.AddButton then
                MainTab:AddButton({ Title = "Pick Best Pets", Callback = function()
                    local chosen = pickTopNFromSave()
                    if #chosen == 0 then
                        if Fluent and Fluent:Notify then Fluent:Notify({Title="HateAF", Content="No pets found", Duration=4}) end
                        return
                    end
                    trackedPets = chosen
                    for _, uid in ipairs(trackedPets) do pcall(function() EquipPet(uid) end); task.wait(0.06) end
                    task.wait(EQUIP_WAIT)
                    if Fluent and Fluent:Notify then Fluent:Notify({Title="HateAF", Content=("Equipped %d pets"):format(#trackedPets), Duration=4}) end
                end})

                MainTab:AddButton({ Title = "Equip Best (Remote)", Callback = function()
                    local ok = EquipBestPetsRemote()
                    if Fluent and Fluent:Notify then Fluent:Notify({Title="HateAF", Content = ok and "Requested remote equip." or "Remote equip failed.", Duration=4}) end
                end})
            end

            -- Mode toggles
            addModeButton("Normal", "Normal")
            addModeButton("Safe", "Safe")
            addModeButton("Blatant", "Blatant")
            addModeButton("NearestArea", "NearestArea")
            addModeButton("NearestGlobal", "NearestGlobal")

            -- Slow Mode toggle
            if MainTab.AddToggle then
                MainTab:AddToggle({ Title = "Slow Mode", Default = SlowMode, Callback = function(v) SlowMode = v end })
            end

            -- Target type dropdown
            if MainTab.AddDropdown then
                MainTab:AddDropdown({ Title = "Target Type", List = TargetTypeOptions, Default = TargetType, Callback = function(v) TargetType = tostring(v or "Any") end })
            else
                -- fallback: small input
                if MainTab.AddInput then MainTab:AddInput({ Title = "Target Type (text)", Default = TargetType, Finished = false, Callback = function(v) TargetType = tostring(v or "Any") end }) end
            end

            -- World / Area dropdowns
            local worldOpts = (function() local t={} for k,_ in pairs(WorldsTable) do table.insert(t,k) end table.sort(t) return t end)()
            if MainTab.AddDropdown then
                MainTab:AddDropdown({ Title = "World", List = worldOpts, Default = SelectedWorld, Callback = function(sel)
                    SelectedWorld = tostring(sel or "")
                    local areas = WorldsTable[SelectedWorld] or {}
                    if MainTab.AddDropdown then
                        -- Recreate area dropdown by adding new one (simple approach)
                        -- NOTE: many Fluent dropdowns support dynamic update, but to keep compatibility we just set SelectedArea here:
                        if #areas>0 then SelectedArea = areas[1] else SelectedArea = "" end
                    end
                    petToTarget = {}; targetToPet = {}; petCooldowns = {}
                end})
                MainTab:AddDropdown({ Title = "Area", List = WorldsTable[SelectedWorld] or {}, Default = SelectedArea, Callback = function(sel)
                    SelectedArea = tostring(sel or "")
                    petToTarget = {}; targetToPet = {}; petCooldowns = {}
                end})
            end

            -- Refresh Areas button
            if MainTab.AddButton then
                MainTab:AddButton({ Title = "Refresh Areas", Callback = function()
                    local areas = WorldsTable[SelectedWorld] or {}
                    if #areas>0 then SelectedArea = areas[1] else SelectedArea = "" end
                    if Fluent and Fluent:Notify then Fluent:Notify({Title="HateAF", Content="Areas refreshed", Duration=3}) end
                end})
            end

            -- Start/Stop big button
            if MainTab.AddButton then
                MainTab:AddButton({ Title = "Start / Stop", Callback = function()
                    Enabled = not Enabled
                    if Enabled then startTime = tick() else startTime = 0 end
                    if Fluent and Fluent:Notify then Fluent:Notify({Title="HateAF", Content = Enabled and "Autofarm started" or "Autofarm stopped", Duration=3}) end
                end})
            end
        end)

        -- Eggs tab
        pcall(function()
            if EggsTab.AddLabel then EggsTab:AddLabel({ Title = "Egg Management" }) end
            if EggsTab.AddButton then
                EggsTab:AddButton({ Title = "Disable Egg Animation (one-shot)", Callback = function()
                    local ok = disableEggAnimationOnce()
                    if Fluent and Fluent:Notify then Fluent:Notify({Title="HateAF", Content = ok and "Egg animation disabled" or "Already disabled", Duration=4}) end
                end})
            end
        end)

        -- Upgrades tab (placeholders)
        pcall(function()
            if UpgradesTab.AddLabel then UpgradesTab:AddLabel({ Title = "Auto Fuse (placeholder)" }) end
            if UpgradesTab.AddLabel then UpgradesTab:AddLabel({ Title = "Auto Gold (placeholder)" }) end
            if UpgradesTab.AddLabel then UpgradesTab:AddLabel({ Title = "Auto Rainbow (placeholder)" }) end
            if UpgradesTab.AddLabel then UpgradesTab:AddLabel({ Title = "Auto Dark Matter (placeholder)" }) end
        end)

        -- Select first tab if method present
        pcall(function() if Window.SelectTab then Window:SelectTab(1) end end)

    else
        -- FALLBACK: build original minimal UI (keeps same behavior if Fluent missing)
        fallbackUsed = true
        local mainWin = OldUI:CreateWindow("Hate's Autofarm — V2", 420, 340, UDim2.new(0,8,0,36))
        local upgradesWin = OldUI:CreateWindow("Upgrades (placeholders)", 320, 200, UDim2.new(0,440,0,36))
        local eggsWin = OldUI:CreateWindow("Egg Management", 320, 200, UDim2.new(0,440,0,244))
        upgradesWin.Frame.Visible = false; eggsWin.Frame.Visible = false

        -- draggable main frame
        do
            local frame = mainWin.Frame
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

        -- status label
        local statusLabel = OldUI:CreateLabel(mainWin, ("Mode:%s | World:%s | Area:%s | Pets:%d | Broken:%d | Time:%s"):format(Mode, SelectedWorld, SelectedArea, #trackedPets, brokenCount, "0s"), UDim2.new(0,8,0,30))

        -- replicate main UI buttons/toggles/dropdowns (same as original, using OldUI helpers)
        local pickBtn = OldUI:CreateButton(mainWin, "Pick Best Pets", UDim2.new(0,8,0,56), UDim2.new(0.46,-12,0,34), function()
            statusLabel.Text = "Equipping best pets..."
            local chosen = pickTopNFromSave()
            if #chosen == 0 then statusLabel.Text = "No pets found"; return end
            trackedPets = chosen
            for _, uid in ipairs(trackedPets) do pcall(function() EquipPet(uid) end); task.wait(0.06) end
            task.wait(EQUIP_WAIT)
            statusLabel.Text = ("Equipped %d pets"):format(#trackedPets)
        end)

        local equipRemoteBtn = OldUI:CreateButton(mainWin, "Equip Best (Remote)", UDim2.new(0,220,0,56), UDim2.new(0.46,-12,0,34), function()
            local ok = EquipBestPetsRemote()
            statusLabel.Text = ok and "Requested remote equip." or "Remote equip failed."
        end)

        -- mode toggles (mutually exclusive)
        local modeToggles = {}
        local function mkMode(text, x,y, modeVal)
            local t = OldUI:CreateToggle(mainWin, text, UDim2.new(0,x,0,y), function(on)
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
        local slowT = OldUI:CreateToggle(mainWin, "Slow Mode", UDim2.new(0,264,0,102), function(s) SlowMode = s end, false)

        local targetDD = OldUI:CreateDropdown(mainWin, "Target Type", UDim2.new(0,272,0,138), 136, TargetTypeOptions, function(v) TargetType = tostring(v or "Any") end)

        local worldOpts = (function() local t={} for k,_ in pairs(WorldsTable) do table.insert(t,k) end table.sort(t) return t end)()
        local worldDD = OldUI:CreateDropdown(mainWin, "World", UDim2.new(0,8,0,180), 200, worldOpts, function(sel)
            SelectedWorld = tostring(sel or "")
            local areas = WorldsTable[SelectedWorld] or {}
            areaDD.SetOptions(areas)
            if #areas > 0 then SelectedArea = areas[1]; areaDD.SetText(SelectedArea) else SelectedArea = ""; areaDD.SetText("None") end
            petToTarget = {}; targetToPet = {}; petCooldowns = {}
        end)
        worldDD.SetText(SelectedWorld)

        local areaDD = OldUI:CreateDropdown(mainWin, "Area", UDim2.new(0,220,0,180), 188, WorldsTable[SelectedWorld] or {}, function(sel)
            SelectedArea = tostring(sel or "")
            petToTarget = {}; targetToPet = {}; petCooldowns = {}
        end)
        areaDD.SetText(SelectedArea)

        local refreshBtn = OldUI:CreateButton(mainWin, "Refresh Areas", UDim2.new(0,220,0,214), UDim2.new(0.46,-12,0,28), function()
            local areas = WorldsTable[SelectedWorld] or {}
            areaDD.SetOptions(areas)
            if #areas>0 then areaDD.SetText(areas[1]); SelectedArea = areas[1] else areaDD.SetText("None"); SelectedArea = "" end
            statusLabel.Text = "Areas refreshed"
        end)

        local startBtn = OldUI:CreateButton(mainWin, "Start", UDim2.new(0,8,0,246), UDim2.new(1,-16,0,32), function()
            Enabled = not Enabled
            startBtn.Text = Enabled and "Stop" or "Start"
            startBtn.BackgroundColor3 = Enabled and Color3.fromRGB(178,34,34) or Color3.fromRGB(34,139,34)
            if Enabled then startTime = tick() else startTime = 0 end
        end)

        local eggBtn = OldUI:CreateButton(mainWin, "Egg Management", UDim2.new(0,8,0,288), UDim2.new(0.46,-12,0,28), function() eggsWin.Frame.Visible = not eggsWin.Frame.Visible end)
        local upgradesBtn = OldUI:CreateButton(mainWin, "Upgrades", UDim2.new(0,220,0,288), UDim2.new(0.46,-12,0,28), function() upgradesWin.Frame.Visible = not upgradesWin.Frame.Visible end)

        -- eggs window button
        OldUI:CreateLabel(eggsWin, "Egg Management", UDim2.new(0,8,0,24))
        OldUI:CreateButton(eggsWin, "Disable Egg Animation (one-shot)", UDim2.new(0,8,0,56), UDim2.new(1,-16,0,28), function()
            local ok = disableEggAnimationOnce()
            eggsWin.Title.Text = ok and "Egg animation disabled" or "Egg animation already disabled"
        end)

        -- upgrades placeholders
        OldUI:CreateLabel(upgradesWin, "Auto Fuse (placeholder)", UDim2.new(0,8,0,32))
        OldUI:CreateLabel(upgradesWin, "Auto Gold (placeholder)", UDim2.new(0,8,0,56))
        OldUI:CreateLabel(upgradesWin, "Auto Rainbow (placeholder)", UDim2.new(0,8,0,80))
        OldUI:CreateLabel(upgradesWin, "Auto Dark Matter (placeholder)", UDim2.new(0,8,0,104))

        -- status updater for fallback
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
    end

    -- ==== TOP-MIDDLE "Open" TOGGLE BUTTON (outside Fluent) ====
    -- This button shows/hides the Fluent UI ScreenGui (if present) or fallback GUI
    local openBtn = Instance.new("TextButton")
    openBtn.Name = "HateAF_OpenButton"
    openBtn.Parent = PlayerGui
    openBtn.Size = UDim2.new(0,100,0,28)
    openBtn.Position = UDim2.new(0.5, -50, 0, 8) -- top-middle as requested
    openBtn.Text = "Open"
    openBtn.Font = Enum.Font.SourceSansBold
    openBtn.TextSize = 16
    openBtn.BackgroundColor3 = Color3.fromRGB(24,24,24)
    openBtn.TextColor3 = Color3.new(1,1,1)
    openBtn.ZIndex = 9999
    local uic = Instance.new("UICorner", openBtn); uic.CornerRadius = UDim.new(0,6)

    local uiVisible = true
    local function setUIVisible(v)
        uiVisible = v and true or false
        -- If Fluent ScreenGui detected, toggle it
        if fluentScreenGui and fluentScreenGui.Parent then
            pcall(function()
                fluentScreenGui.Enabled = uiVisible -- many modern ScreenGuis support .Enabled
                fluentScreenGui.Parent = uiVisible and PlayerGui or (not uiVisible and nil) or fluentScreenGui.Parent
                if not fluentScreenGui.Enabled and not fluentScreenGui.Parent then fluentScreenGui.Parent = uiVisible and PlayerGui or fluentScreenGui.Parent end
            end)
        else
            -- fallback: try to find a fallback GUI created earlier
            pcall(function()
                local fallback = PlayerGui:FindFirstChild("HateAF_UI_Fallback")
                if fallback then
                    fallback.Enabled = uiVisible
                end
            end)
        end
        -- Update button text
        openBtn.Text = uiVisible and "Open" or "Open"
        -- (Keep text "Open" per your request; we still can indicate visible via color)
        openBtn.BackgroundColor3 = uiVisible and Color3.fromRGB(34,139,34) or Color3.fromRGB(178,34,34)
    end

    -- ensure initial detection attempt (if Fluent created GUI a bit later)
    task.spawn(function()
        -- wait up to a short time for fluent GUI to appear
        for i=1,20 do
            if not fluentScreenGui then
                fluentScreenGui = detectNewScreenGui(beforeGUIs)
            end
            if fluentScreenGui then break end
            task.wait(0.05)
        end
        -- default visible true
        setUIVisible(true)
    end)

    openBtn.MouseButton1Click:Connect(function()
        setUIVisible(not uiVisible)
    end)

    -- ==== STATUS UPDATER (for Fluent mode setStatusText or fallback) ====
    task.spawn(function()
        while true do
            pcall(function()
                local elapsed = (startTime>0) and math.floor(tick()-startTime) or 0
                local tstr = string.format("%02d:%02d", math.floor(elapsed/60), elapsed%60)
                local statusStr = ("Mode:%s | World:%s | Area:%s | Pets:%d | Broken:%d | Time:%s"):format(Mode, SelectedWorld, SelectedArea, #trackedPets, brokenCount, tstr)
                if statusLabelUpdater then
                    pcall(function() statusLabelUpdater(statusStr) end)
                else
                    -- fallback: try to update fallback label if present
                    pcall(function()
                        local fallback = PlayerGui:FindFirstChild("HateAF_UI_Fallback")
                        if fallback then
                            for _,lbl in ipairs(fallback:GetDescendants()) do
                                if lbl:IsA("TextLabel") and tostring(lbl.Text):sub(1,5) == "Mode:" then
                                    lbl.Text = statusStr
                                end
                            end
                        end
                    end)
                end
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

    print("[HateAF] Fluent UI loaded (or fallback used). Open button created at top-middle.")
end)

if not ok then
    warn("[HateAF] Startup error:", mainErr)
else
    print("[HateAF] Script executed successfully!")
end
