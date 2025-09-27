-- Delta-safe UI test (Hate's QoL) - paste into NEW LocalScript
if not game or not game:IsLoaded() then repeat task.wait() until game and game:IsLoaded() end
local RunService = game:GetService("RunService")
if RunService:IsServer() then return end

local ok, err = pcall(function()
    -- ===== CONFIG =====
    local WorldsTable = {
        ["Spawn"] = {"Shop","Town","Forest","Beach","Mine","Winter","Glacier","Desert","Volcano","Cave","Tech Entry","VIP"},
        ["Fantasy"] = {"Fantasy Shop","Enchanted Forest","Portals","Ancient Island","Samurai Island","Candy Island","Haunted Island","Hell Island","Heaven Island","Heaven's Gate"},
        ["Tech"] = {"Tech Shop","Tech City","Dark Tech","Steampunk","Steampunk Chest Area","Alien Lab","Alien Forest","Giant Alien Chest","Glitch","Hacker Portal"},
        ["Void"] = {"The Void"},
        ["Axolotl Ocean"] = {"Axolotl Ocean","Axolotl Deep Ocean","Axolotl Cave"},
        ["Pixel"] = {"Pixel Forest","Pixel Kyoto","Pixel Alps","Pixel Vault"},
        ["Cat"] = {"Cat Paradise","Cat Backyard","Cat Taiga","Cat Throne Room"}
    }

    -- ===== SERVICES =====
    local Players = game:GetService("Players")
    local UserInput = game:GetService("UserInputService")
    local LocalPlayer = Players.LocalPlayer
    assert(LocalPlayer, "LocalPlayer nil - run as LocalScript")
    local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

    -- small helper
    local function new(cls, props, parent)
        local obj = Instance.new(cls)
        if props then
            for k,v in pairs(props) do
                if k == "Parent" then obj.Parent = v else
                    pcall(function() obj[k] = v end)
                end
            end
        end
        if parent and not obj.Parent then obj.Parent = parent end
        return obj
    end

    -- dropdown widget with SetOptions / SetValue
    local function makeDropdown(parent, x, y, width, labelText, options, onSelect)
        options = options or {}
        local label = new("TextLabel", {
            Parent = parent, Position = UDim2.new(0,x,0,y), Size = UDim2.new(0,width,0,16),
            BackgroundTransparency = 1, Text = labelText, Font = Enum.Font.SourceSans, TextSize = 13,
            TextColor3 = Color3.fromRGB(230,230,230), TextXAlignment = Enum.TextXAlignment.Left
        })
        local btn = new("TextButton", {
            Parent = parent, Position = UDim2.new(0,x,0,y+16), Size = UDim2.new(0,width,0,26),
            Text = tostring(options[1] or "None"), Font = Enum.Font.SourceSans, TextSize = 14,
            BackgroundColor3 = Color3.fromRGB(20,20,20), TextColor3 = Color3.fromRGB(240,240,240), AutoButtonColor = true
        })
        new("UICorner",{Parent = btn, CornerRadius = UDim.new(0,6)})
        local menu = new("Frame", {
            Parent = parent, Position = UDim2.new(0,x,0,y+44),
            Size = UDim2.new(0,width,0,math.min(#options*20,200)), BackgroundColor3 = Color3.fromRGB(16,16,16),
            Visible = false
        })
        new("UICorner",{Parent = menu, CornerRadius = UDim.new(0,6)})
        local layout = new("UIListLayout", {Parent = menu})
        layout.Padding = UDim.new(0,4)

        local function populate(list)
            for _,c in ipairs(menu:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
            for i,opt in ipairs(list) do
                local it = new("TextButton", {
                    Parent = menu, Size = UDim2.new(1,-8,0,18), Position = UDim2.new(0,4,0,0),
                    Text = tostring(opt), BackgroundTransparency = 1, Font = Enum.Font.SourceSans,
                    TextColor3 = Color3.new(1,1,1), TextSize = 13, AutoButtonColor = true
                })
                it.MouseButton1Click:Connect(function()
                    btn.Text = tostring(opt)
                    menu.Visible = false
                    pcall(onSelect, opt)
                end)
            end
            menu.Size = UDim2.new(0, width, 0, math.min(#list*22,200))
        end

        populate(options)

        btn.MouseButton1Click:Connect(function() menu.Visible = not menu.Visible end)

        -- hide menu when clicking/tapping outside
        UserInput.InputBegan:Connect(function(inp)
            if (inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch) and menu.Visible then
                local m = UserInput:GetMouseLocation()
                local mp, ms = menu.AbsolutePosition, menu.AbsoluteSize
                local bp, bs = btn.AbsolutePosition, btn.AbsoluteSize
                local inMenu = (m.X >= mp.X and m.X <= mp.X+ms.X and m.Y >= mp.Y and m.Y <= mp.Y+ms.Y)
                local onBtn  = (m.X >= bp.X and m.X <= bp.X+bs.X and m.Y >= bp.Y and m.Y <= bp.Y+bs.Y)
                if not (inMenu or onBtn) then menu.Visible = false end
            end
        end)

        return {
            Button = btn,
            Menu = menu,
            Label = label,
            SetOptions = function(newList) populate(newList or {}) end,
            SetValue = function(val) btn.Text = tostring(val or "None") end,
            GetValue = function() return btn.Text end
        }
    end

    -- ===== BUILD UI =====
    local screenGui = new("ScreenGui", {Parent = PlayerGui, Name = "HatesQoL_TestGUI", ResetOnSpawn=false})
    local frame = new("Frame", {
        Parent = screenGui, Size = UDim2.new(0,300,0,300), Position = UDim2.new(0,8,0,36),
        BackgroundColor3 = Color3.fromRGB(12,12,12), BorderSizePixel = 0
    })
    new("UICorner", {Parent = frame, CornerRadius = UDim.new(0,8)})

    local title = new("TextLabel", {
        Parent = frame, Size = UDim2.new(1,-16,0,26), Position = UDim2.new(0,8,0,6),
        BackgroundTransparency = 1, Text = "Hate's QoL (UI Test)", Font = Enum.Font.SourceSansBold, TextSize = 16, TextColor3 = Color3.fromRGB(230,230,230), TextXAlignment = Enum.TextXAlignment.Left
    })

    -- FLOAT/button when minimized
    local floatBtn = new("TextButton", {
        Parent = PlayerGui, Size = UDim2.new(0,100,0,28), Position = UDim2.new(0,8,0,8),
        Text = "Hate's QoL", Font = Enum.Font.SourceSansBold, TextSize = 14,
        BackgroundColor3 = Color3.fromRGB(16,16,16), TextColor3 = Color3.fromRGB(230,230,230)
    })
    new("UICorner", {Parent = floatBtn, CornerRadius = UDim.new(0,6)})
    floatBtn.Visible = false
    floatBtn.MouseButton1Click:Connect(function() floatBtn.Visible = false; frame.Visible = true end)

    -- minimize (instant) top-right
    local minBtn = new("TextButton", {Parent = frame, Size = UDim2.new(0,20,0,20), Position = UDim2.new(1,-28,0,6), Text="—", Font=Enum.Font.SourceSansBold, TextColor3=Color3.new(1,1,1), BackgroundColor3=Color3.fromRGB(20,20,20)})
    new("UICorner", {Parent = minBtn, CornerRadius = UDim.new(0,6)})
    minBtn.MouseButton1Click:Connect(function() frame.Visible=false; floatBtn.Visible=true end)

    -- left column (buttons)
    local leftX, leftW = 12, 132
    local pickBtn = new("TextButton", {Parent = frame, Position = UDim2.new(0,leftX,0,44), Size = UDim2.new(0,leftW,0,34), Text = "Pick Best Pets", Font = Enum.Font.SourceSansBold, BackgroundColor3 = Color3.fromRGB(24,24,24), TextColor3 = Color3.fromRGB(230,230,230)})
    new("UICorner", {Parent = pickBtn, CornerRadius = UDim.new(0,6)})
    local startBtn = new("TextButton", {Parent = frame, Position = UDim2.new(0,leftX,0,44+44), Size = UDim2.new(0,leftW,0,34), Text = "Start", Font = Enum.Font.SourceSansBold, BackgroundColor3 = Color3.fromRGB(34,139,34), TextColor3 = Color3.fromRGB(230,230,230)})
    new("UICorner", {Parent = startBtn, CornerRadius = UDim.new(0,6)})
    local blatantBtn = new("TextButton", {Parent = frame, Position = UDim2.new(0,leftX,0,44+88), Size = UDim2.new(0,leftW,0,30), Text = "Blatant Farm", Font = Enum.Font.SourceSans, BackgroundColor3 = Color3.fromRGB(28,28,28), TextColor3 = Color3.fromRGB(230,230,230)})
    new("UICorner", {Parent = blatantBtn, CornerRadius = UDim.new(0,6)})

    -- right column (dropdowns) stacked vertically 5px below buttons
    local rightX, rightW = 160, 128
    local worldList = (function() local t={} for k,_ in pairs(WorldsTable) do table.insert(t,k) end table.sort(t) return t end)()
    local worldDD = makeDropdown(frame, rightX, 44, rightW, "World", worldList, function(sel)
        -- immediate area refresh + auto-select first
        local areas = WorldsTable[sel] or {}
        areaDD.SetOptions(areas)
        areaDD.SetValue(areas[1] or "None")
        StatusLabel.Text = ("Selected: %s - %s"):format(tostring(sel), tostring(areas[1] or "None"))
    end)

    local areaDD = makeDropdown(frame, rightX, 44 + 64, rightW, "Area", WorldsTable[worldList[1]] or {}, function(sel)
        StatusLabel.Text = ("Selected: %s - %s"):format(tostring(worldDD.Button.Text), tostring(sel))
    end)

    -- target dropdown
    local targetDD = makeDropdown(frame, rightX, 44 + 128, rightW, "Target Type", {"Any","Coins","Diamonds","Chests","Breakables"}, function(sel)
        StatusLabel.Text = ("Target: %s"):format(tostring(sel))
    end)

    -- status row (top area)
    local StatusLabel = new("TextLabel", {Parent = frame, Position = UDim2.new(0,12,0,120), Size = UDim2.new(1,-24,0,18), BackgroundTransparency = 1, Text = "Status: Idle", Font=Enum.Font.SourceSans, TextSize=13, TextColor3=Color3.fromRGB(220,220,220), TextXAlignment=Enum.TextXAlignment.Left})

    local timeLabel = new("TextLabel", {Parent = frame, Position = UDim2.new(0,12,0,140), Size = UDim2.new(1,-24,0,16), BackgroundTransparency = 1, Text = "Time: 00:00", Font=Enum.Font.SourceSans, TextSize=12, TextColor3=Color3.fromRGB(160,160,160), TextXAlignment=Enum.TextXAlignment.Left})
    local brokenLabel = new("TextLabel", {Parent = frame, Position = UDim2.new(0,12,0,158), Size = UDim2.new(1,-24,0,16), BackgroundTransparency = 1, Text = "Broken: 0", Font=Enum.Font.SourceSans, TextSize=12, TextColor3=Color3.fromRGB(160,160,160), TextXAlignment=Enum.TextXAlignment.Left})

    -- behavior: test toggles and counters
    local running = false
    local broken = 0
    local startTick = 0

    pickBtn.MouseButton1Click:Connect(function()
        StatusLabel.Text = "Status: Equipping best pets..."
        task.spawn(function()
            task.wait(0.6)
            StatusLabel.Text = "Status: Equipped 6 pets (test)"
        end)
    end)

    startBtn.MouseButton1Click:Connect(function()
        running = not running
        startBtn.Text = running and "Stop" or "Start"
        startBtn.BackgroundColor3 = running and Color3.fromRGB(178,34,34) or Color3.fromRGB(34,139,34)
        if running then startTick = tick() else startTick = 0 end
    end)

    blatantBtn.MouseButton1Click:Connect(function()
        StatusLabel.Text = "Status: Blatant farm (test)"
    end)

    -- a small refresh button for areas
    local refreshBtn = new("TextButton", {Parent = frame, Position = UDim2.new(0,160,0,238), Size = UDim2.new(0,128,0,22), Text="Refresh Areas", Font=Enum.Font.SourceSans, BackgroundColor3=Color3.fromRGB(28,28,28), TextColor3=Color3.fromRGB(230,230,230)})
    new("UICorner", {Parent = refreshBtn, CornerRadius = UDim.new(0,6)})
    refreshBtn.MouseButton1Click:Connect(function()
        local sel = worldDD.Button.Text
        local areas = WorldsTable[sel] or {}
        areaDD.SetOptions(areas)
        areaDD.SetValue(areas[1] or "None")
        StatusLabel.Text = "Areas refreshed"
    end)

    -- time / broken updater
    task.spawn(function()
        while true do
            task.wait(1)
            pcall(function()
                local elapsed = (startTick>0) and math.floor(tick()-startTick) or 0
                local mm = math.floor(elapsed/60); local ss = elapsed%60
                timeLabel.Text = ("Time: %02d:%02d"):format(mm, ss)
                if running then
                    broken = broken + 1
                    brokenLabel.Text = "Broken: "..tostring(broken)
                end
            end)
        end
    end)

    print("[HatesQoL TestUI] Loaded - UI test running.")
end)

if not ok then
    warn("[HatesQoL TestUI] Startup error:", err)
else
    print("[HatesQoL TestUI] Script executed successfully.")
end
