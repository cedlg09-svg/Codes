-- HateAF_UI_Test.lua
-- LocalScript (Delta) - UI V2 (instant panels)
-- Paste into NEW LocalScript and run in Delta

-- Bootstrap protection (avoid "line 1" errors and server execution)
if not game or not game:IsLoaded() then repeat task.wait() until game and game:IsLoaded() end
local RunService = game:GetService("RunService")
if RunService:IsServer() then return end

local ok, mainErr = pcall(function()

    -- ===== Services & Setup =====
    local Players = game:GetService("Players")
    local UserInput = game:GetService("UserInputService")
    local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()
    local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

    -- ===== Configs =====
    local WINDOW_W, WINDOW_H = 300, 300
    local FLOAT_BTN_SIZE = 50 -- 50x50 top-right
    local WorldsTable = {
        ["Spawn"] = {"Shop","Town","Forest","Beach","Mine","Winter","Glacier","Desert","Volcano","Cave","Tech Entry","VIP"},
        ["Fantasy"] = {"Fantasy Shop","Enchanted Forest","Portals","Ancient Island","Samurai Island","Candy Island","Haunted Island","Hell Island","Heaven Island","Heaven's Gate"},
        ["Tech"] = {"Tech Shop","Tech City","Dark Tech","Steampunk","Steampunk Chest Area","Alien Lab","Alien Forest","Giant Alien Chest","Glitch","Hacker Portal"},
        ["Void"] = {"The Void"},
        ["Axolotl Ocean"] = {"Axolotl Ocean","Axolotl Deep Ocean","Axolotl Cave"},
        ["Pixel"] = {"Pixel Forest","Pixel Kyoto","Pixel Alps","Pixel Vault"},
        ["Cat"] = {"Cat Paradise","Cat Backyard","Cat Taiga","Cat Throne Room"}
    }

    -- ===== Small helpers =====
    local function new(cls, props, parent)
        local o = Instance.new(cls)
        if props then
            for k,v in pairs(props) do
                if k == "Parent" then o.Parent = v else
                    pcall(function() o[k] = v end)
                end
            end
        end
        if parent then o.Parent = parent end
        return o
    end

    -- ===== Dropdown widget with SetOptions/SetText =====
    local function makeDropdown(parent, x, y, w, labelText, options, onSelect)
        options = options or {}
        local label = new("TextLabel", {
            Parent = parent, Position = UDim2.new(0, x, 0, y),
            Size = UDim2.new(0, w, 0, 16),
            BackgroundTransparency = 1,
            Text = labelText,
            Font = Enum.Font.SourceSans,
            TextSize = 13,
            TextColor3 = Color3.fromRGB(230,230,230),
            TextXAlignment = Enum.TextXAlignment.Left
        })
        local btn = new("TextButton", {
            Parent = parent, Position = UDim2.new(0, x, 0, y+16),
            Size = UDim2.new(0, w, 0, 26),
            Text = tostring(options[1] or "None"),
            Font = Enum.Font.SourceSans,
            TextSize = 13,
            BackgroundColor3 = Color3.fromRGB(22,22,22),
            TextColor3 = Color3.fromRGB(240,240,240),
            AutoButtonColor = true
        })
        new("UICorner", { Parent = btn, CornerRadius = UDim.new(0,6) })

        local menu = new("Frame", {
            Parent = parent,
            Position = UDim2.new(0, x, 0, y + 16 + 26 + 6),
            Size = UDim2.new(0, w, 0, math.min(#options*20, 200)),
            BackgroundColor3 = Color3.fromRGB(18,18,18),
            Visible = false
        })
        new("UICorner", {Parent = menu, CornerRadius = UDim.new(0,6)})
        local layout = new("UIListLayout", {Parent = menu})
        layout.Padding = UDim.new(0,4)

        local function populate(list)
            for _,c in ipairs(menu:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
            for _,opt in ipairs(list) do
                local item = new("TextButton", {
                    Parent = menu,
                    Size = UDim2.new(1, -8, 0, 18),
                    Position = UDim2.new(0, 4, 0, 0),
                    Text = tostring(opt),
                    BackgroundTransparency = 1,
                    Font = Enum.Font.SourceSans,
                    TextSize = 13,
                    TextColor3 = Color3.fromRGB(240,240,240),
                    AutoButtonColor = true
                })
                item.MouseButton1Click:Connect(function()
                    btn.Text = tostring(opt)
                    menu.Visible = false
                    pcall(onSelect, opt)
                end)
            end
            menu.Size = UDim2.new(0, w, 0, math.min(#list*22,200))
        end

        populate(options)

        btn.MouseButton1Click:Connect(function()
            menu.Visible = not menu.Visible
        end)

        -- close the menu when clicked outside
        UserInput.InputBegan:Connect(function(inp)
            if (inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch) and menu.Visible then
                local pos = UserInput:GetMouseLocation()
                local mp = menu.AbsolutePosition; local ms = menu.AbsoluteSize
                local bp = btn.AbsolutePosition; local bs = btn.AbsoluteSize
                local inMenu = (pos.X >= mp.X and pos.X <= mp.X+ms.X and pos.Y >= mp.Y and pos.Y <= mp.Y+ms.Y)
                local onBtn = (pos.X >= bp.X and pos.X <= bp.X+bs.X and pos.Y >= bp.Y and pos.Y <= bp.Y+bs.Y)
                if not (inMenu or onBtn) then menu.Visible = false end
            end
        end)

        return {
            Label = label,
            Button = btn,
            Menu = menu,
            SetOptions = function(newList) populate(newList or {}) end,
            SetText = function(t) btn.Text = tostring(t or "None") end,
            GetText = function() return btn.Text end
        }
    end

    -- ===== UI build =====
    local screenGui = new("ScreenGui", {Parent = PlayerGui, Name = "HateAF_UI_V2", ResetOnSpawn = false})
    local frame = new("Frame", {
        Parent = screenGui,
        Size = UDim2.new(0, WINDOW_W, 0, WINDOW_H),
        Position = UDim2.new(0, 8, 0, 36),
        BackgroundColor3 = Color3.fromRGB(12,12,12),
        BorderSizePixel = 0
    })
    new("UICorner", {Parent = frame, CornerRadius = UDim.new(0,8)})

    -- Title row
    local title = new("TextLabel", {
        Parent = frame,
        Size = UDim2.new(1, -12, 0, 26),
        Position = UDim2.new(0, 6, 0, 6),
        BackgroundTransparency = 1,
        Text = "Hate's QoL — Hate's Autofarm",
        Font = Enum.Font.SourceSansBold,
        TextSize = 15,
        TextColor3 = Color3.fromRGB(245,245,245),
        TextXAlignment = Enum.TextXAlignment.Left
    })

    -- Close/hide inside window (top-right small)
    local innerMin = new("TextButton", {
        Parent = frame, Size = UDim2.new(0,20,0,20),
        Position = UDim2.new(1, -26, 0, 6), Text = "–",
        Font = Enum.Font.SourceSansBold, TextSize = 16,
        BackgroundColor3 = Color3.fromRGB(20,20,20), TextColor3 = Color3.new(1,1,1)
    })
    new("UICorner", {Parent = innerMin, CornerRadius = UDim.new(0,6)})

    -- Status horizontal (just under title)
    local statusY = 36
    local statusLabel = new("TextLabel", {
        Parent = frame, Position = UDim2.new(0,8,0,statusY),
        Size = UDim2.new(1, -16, 0, 18),
        BackgroundTransparency = 1,
        Font = Enum.Font.SourceSans, TextSize = 12,
        TextColor3 = Color3.fromRGB(220,220,220),
        Text = "Mode: None | World: Spawn | Area: Town | Pets: 0 | Broken: 0 | Time: 00:00"
    })

    -- Left column buttons (stacked vertically)
    local btnLeftX, btnLeftW = 8, 120
    local topButtonsY = 60
    local pickBtn = new("TextButton", {
        Parent = frame, Position = UDim2.new(0, btnLeftX, 0, topButtonsY), Size = UDim2.new(0, btnLeftW, 0, 30),
        Text = "Pick Best Pets", Font = Enum.Font.SourceSansBold, TextSize = 13,
        BackgroundColor3 = Color3.fromRGB(28,28,28), TextColor3 = Color3.fromRGB(240,240,240)
    })
    new("UICorner", {Parent = pickBtn, CornerRadius = UDim.new(0,6)})

    local remoteEquipBtn = new("TextButton", {
        Parent = frame, Position = UDim2.new(0, btnLeftX, 0, topButtonsY + 36), Size = UDim2.new(0, btnLeftW, 0, 30),
        Text = "Equip Best (Remote)", Font = Enum.Font.SourceSans, TextSize = 13,
        BackgroundColor3 = Color3.fromRGB(28,28,28), TextColor3 = Color3.fromRGB(240,240,240)
    })
    new("UICorner", {Parent = remoteEquipBtn, CornerRadius = UDim.new(0,6)})

    local blatantBtn = new("TextButton", {
        Parent = frame, Position = UDim2.new(0, btnLeftX, 0, topButtonsY + 72), Size = UDim2.new(0, btnLeftW, 0, 30),
        Text = "Blatant Farm", Font = Enum.Font.SourceSans, TextSize = 13,
        BackgroundColor3 = Color3.fromRGB(28,28,28), TextColor3 = Color3.fromRGB(240,240,240)
    })
    new("UICorner", {Parent = blatantBtn, CornerRadius = UDim.new(0,6)})

    -- Right column: dropdowns stacked vertically, 5px below buttons
    local rightX, rightW = 140, WINDOW_W - 8 - 140
    local ddStartY = topButtonsY -- aligned horizontally with first button
    local worldDD = makeDropdown(frame, rightX, ddStartY, rightW, "World", (function()
        local t = {}
        for k,_ in pairs(WorldsTable) do table.insert(t,k) end
        table.sort(t)
        return t
    end)(), function(sel)
        -- immediate refresh of Area dropdown and auto-select first area
        local areas = WorldsTable[sel] or {}
        areaDD.SetOptions(areas)
        areaDD.SetText(areas[1] or "None")
        SelectedWorld = sel
        SelectedArea = areas[1] or ""
        -- clear assignments (placeholders)
        statusLabel.Text = ("Mode: %s | World: %s | Area: %s"):format(tostring(Mode), tostring(SelectedWorld), tostring(SelectedArea))
    end)

    local areaDD = makeDropdown(frame, rightX, ddStartY + 64, rightW, "Area", WorldsTable["Spawn"] or {}, function(sel)
        SelectedArea = sel
        statusLabel.Text = ("Mode: %s | World: %s | Area: %s"):format(tostring(Mode), tostring(SelectedWorld), tostring(SelectedArea))
    end)

    -- Target Type below area
    local targetDD = makeDropdown(frame, rightX, ddStartY + 128, rightW, "Target Type", {"Any","Coins","Diamonds","Chests","Breakables"}, function(sel)
        TargetType = sel
    end)

    -- Refresh areas button (right column, below target)
    local refreshBtn = new("TextButton", {
        Parent = frame, Position = UDim2.new(0, rightX, 0, ddStartY + 192), Size = UDim2.new(0, rightW, 0, 26),
        Text = "Refresh Areas", Font = Enum.Font.SourceSans, TextSize = 13,
        BackgroundColor3 = Color3.fromRGB(26,26,26), TextColor3 = Color3.fromRGB(230,230,230)
    })
    new("UICorner", {Parent = refreshBtn, CornerRadius = UDim.new(0,6)})

    -- Start (big) button across bottom
    local startBtn = new("TextButton", {
        Parent = frame, Position = UDim2.new(0, 8, 0, WINDOW_H - 48), Size = UDim2.new(1, -16, 0, 36),
        Text = "Start", Font = Enum.Font.SourceSansBold, TextSize = 14,
        BackgroundColor3 = Color3.fromRGB(34,139,34), TextColor3 = Color3.new(1,1,1)
    })
    new("UICorner", {Parent = startBtn, CornerRadius = UDim.new(0,6)})

    -- Egg Management window (instant), placed near main
    local eggsGui = new("ScreenGui", {Parent = PlayerGui, Name = "HateAF_Eggs", ResetOnSpawn=false})
    local eggsWin = new("Frame", {
        Parent = eggsGui, Size = UDim2.new(0, 260, 0, 180),
        Position = UDim2.new(0, WINDOW_W + 24, 0, 36),
        BackgroundColor3 = Color3.fromRGB(14,14,14)
    })
    new("UICorner", {Parent = eggsWin, CornerRadius = UDim.new(0,8)})
    eggsGui.Enabled = false -- hidden initially

    local eggsTitle = new("TextLabel", {
        Parent = eggsWin, Size = UDim2.new(1, -12, 0, 24), Position = UDim2.new(0,6,0,6),
        BackgroundTransparency = 1, Text = "🥚 Egg Management", Font = Enum.Font.SourceSansBold, TextSize = 14, TextColor3 = Color3.fromRGB(240,240,240)
    })

    local disableEggBtn = new("TextButton", {
        Parent = eggsWin, Position = UDim2.new(0,8,0,44), Size = UDim2.new(1,-16,0,28),
        Text = "Disable Hatch Animation (one-shot)", Font = Enum.Font.SourceSans, TextSize = 13,
        BackgroundColor3 = Color3.fromRGB(26,26,26), TextColor3 = Color3.fromRGB(230,230,230)
    })
    new("UICorner", {Parent = disableEggBtn, CornerRadius = UDim.new(0,6)})

    local eggsClose = new("TextButton", {Parent = eggsWin, Position = UDim2.new(1, -28, 0, 6), Size=UDim2.new(0,20,0,20), Text="×", BackgroundColor3=Color3.fromRGB(26,26,26), Font=Enum.Font.SourceSansBold, TextColor3=Color3.fromRGB(240,240,240)})
    new("UICorner", {Parent = eggsClose, CornerRadius = UDim.new(0,6)})

    eggsClose.MouseButton1Click:Connect(function() eggsGui.Enabled = false end)

    -- Floating always-visible button (top-right)
    local float = new("TextButton", {
        Parent = PlayerGui,
        Size = UDim2.new(0, FLOAT_BTN_SIZE, 0, FLOAT_BTN_SIZE),
        Position = UDim2.new(1, -FLOAT_BTN_SIZE - 8, 0, 8),
        Text = "Hate's\nQoL",
        Font = Enum.Font.SourceSansBold, TextSize = 14,
        BackgroundColor3 = Color3.fromRGB(18,18,18), TextColor3 = Color3.fromRGB(230,230,230),
        AutoButtonColor = true
    })
    new("UICorner", {Parent = float, CornerRadius = UDim.new(0,8)})
    float.ZIndex = 9999

    innerMin.MouseButton1Click:Connect(function()
        frame.Visible = false
        float.Visible = true
    end)
    float.MouseButton1Click:Connect(function()
        frame.Visible = true
        float.Visible = false
    end)

    -- Egg management toggle from main
    disableEggBtn.MouseButton1Click:Connect(function()
        -- placeholder: caller to disable egg animation once
        -- integrate your earlier "getgc" approach if desired but note: messing with game's internal memory can cause problems.
        eggsTitle.Text = "🥚 Egg Management — Disabled (placeholder)"
    end)
    -- Button on main to show eggs window instantly
    local eggsToggleBtn = new("TextButton", {
        Parent = frame, Position = UDim2.new(0, 8, 0, WINDOW_H - 80), Size = UDim2.new(0.46, -12, 0, 28),
        Text = "Egg Management", Font = Enum.Font.SourceSans, TextSize = 13, BackgroundColor3 = Color3.fromRGB(26,26,26), TextColor3 = Color3.fromRGB(240,240,240)
    })
    new("UICorner", {Parent = eggsToggleBtn, CornerRadius = UDim.new(0,6)})
    eggsToggleBtn.MouseButton1Click:Connect(function()
        eggsGui.Enabled = not eggsGui.Enabled
    end)

    -- Upgrades placeholder toggle
    local upgradesToggleBtn = new("TextButton", {
        Parent = frame, Position = UDim2.new(0, WINDOW_W/2 + 4, 0, WINDOW_H - 80), Size = UDim2.new(0.46, -12, 0, 28),
        Text = "Upgrades", Font = Enum.Font.SourceSans, TextSize = 13, BackgroundColor3 = Color3.fromRGB(26,26,26), TextColor3 = Color3.fromRGB(240,240,240)
    })
    new("UICorner", {Parent = upgradesToggleBtn, CornerRadius = UDim.new(0,6)})

    -- ===== Demo / placeholder behaviours =====
    local SelectedWorld = "Spawn"
    local SelectedArea = WorldsTable["Spawn"] and WorldsTable["Spawn"][1] or ""
    local Mode = "None"
    local TargetType = "Any"
    local PetsCount = 0
    local BrokenCount = 0
    local StartTime = 0
    local Running = false

    -- pick best pets placeholder
    pickBtn.MouseButton1Click:Connect(function()
        statusLabel.Text = "Equipping best pets..."
        task.spawn(function()
            task.wait(0.6)
            PetsCount = 6 -- simulated
            statusLabel.Text = ("Mode:%s | World:%s | Area:%s | Pets:%d | Broken:%d | Time:00:00"):format(Mode, SelectedWorld, SelectedArea, PetsCount, BrokenCount)
        end)
    end)

    remoteEquipBtn.MouseButton1Click:Connect(function()
        -- placeholder to call remote equip best; integrate your safe remote invocation here
        statusLabel.Text = "Requested remote equip (placeholder)"
    end)

    blatantBtn.MouseButton1Click:Connect(function()
        Mode = "Blatant"
        statusLabel.Text = ("Mode:%s | World:%s | Area:%s | Pets:%d | Broken:%d | Time:00:00"):format(Mode, SelectedWorld, SelectedArea, PetsCount, BrokenCount)
        task.spawn(function()
            task.wait(0.25)
            statusLabel.Text = "Blatant mode set (placeholder)"
        end)
    end)

    refreshBtn.MouseButton1Click:Connect(function()
        local areas = WorldsTable[worldDD.Button.Text] or {}
        areaDD.SetOptions(areas)
        if #areas>0 then areaDD.SetText(areas[1]); SelectedArea = areas[1] else areaDD.SetText("None"); SelectedArea = "" end
        statusLabel.Text = ("Areas refreshed for %s"):format(worldDD.Button.Text)
    end)

    startBtn.MouseButton1Click:Connect(function()
        Running = not Running
        startBtn.Text = Running and "Stop" or "Start"
        startBtn.BackgroundColor3 = Running and Color3.fromRGB(178,34,34) or Color3.fromRGB(34,139,34)
        if Running then StartTime = tick() else StartTime = 0 end
    end)

    -- update loop for status/time
    task.spawn(function()
        while true do
            pcall(function()
                local elapsed = (StartTime>0) and math.floor(tick()-StartTime) or 0
                local tstr = string.format("%02d:%02d", math.floor(elapsed/60), elapsed%60)
                statusLabel.Text = ("Mode:%s | World:%s | Area:%s | Pets:%d | Broken:%d | Time:%s"):format(tostring(Mode), tostring(worldDD.Button.Text), tostring(areaDD.Button.Text), PetsCount, BrokenCount, tstr)
            end)
            task.wait(0.7)
        end
    end)

    -- Make main window draggable by title bar
    do
        local dragging = false
        local dragStart, startPos
        title.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = true
                dragStart = input.Position
                startPos = frame.Position
                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then dragging = false end
                end)
            end
        end)
        UserInput.InputChanged:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) and dragStart and startPos then
                local delta = input.Position - dragStart
                frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
                -- keep float button top-right (optional)
                float.Position = UDim2.new(1, -FLOAT_BTN_SIZE - 8, 0, 8)
            end
        end)
    end

    -- innerMin already hides the main window; float brings it back

    -- ensure initial area dropdown reflects selected world
    do
        local initialWorld = worldDD.Button.Text
        local areas = WorldsTable[initialWorld] or {}
        areaDD.SetOptions(areas)
        areaDD.SetText(areas[1] or "None")
    end

    print("[HateAF_UI_Test] UI loaded successfully. (Instant panels - no animation)")

end)

if not ok then
    warn("[HateAF_UI_Test] Startup error:", mainErr)
else
    print("[HateAF_UI_Test] Script executed successfully.")
end
