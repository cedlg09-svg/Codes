-- Hate's QOL (Rayfield-like) - drop-in replacement with Refresh() and dynamic updates
-- Paste this file into a LocalScript and load it with loadstring(...)() or paste directly.

local function CreateHatesQOL()
    local Players = game:GetService("Players")
    local LocalPlayer = Players.LocalPlayer
    assert(LocalPlayer, "Hate's QOL must run as LocalScript")

    local library = {}
    library.__name = "HatesQOL"
    library.Version = "1.0"

    -- root gui
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "HatesQOL_Root"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

    -- helper create basic panel
    local function makeFrame(parent, size, pos, bg)
        local f = Instance.new("Frame", parent)
        f.Size = size
        f.Position = pos
        f.BackgroundColor3 = bg or Color3.fromRGB(20,20,20)
        f.BorderSizePixel = 0
        local c = Instance.new("UICorner", f)
        c.CornerRadius = UDim.new(0,6)
        return f
    end

    local function makeLabel(parent, txt, size, pos)
        local l = Instance.new("TextLabel", parent)
        l.Size = size or UDim2.new(1,0,0,18)
        l.Position = pos or UDim2.new(0,0,0,0)
        l.BackgroundTransparency = 1
        l.Font = Enum.Font.SourceSans
        l.TextSize = 14
        l.TextColor3 = Color3.new(1,1,1)
        l.Text = tostring(txt or "")
        l.TextWrapped = true
        return l
    end

    local function makeButton(parent, txt, size, pos)
        local b = Instance.new("TextButton", parent)
        b.Size = size or UDim2.new(0,120,0,28)
        b.Position = pos or UDim2.new(0,0,0,0)
        b.Font = Enum.Font.SourceSansBold
        b.TextSize = 13
        b.Text = tostring(txt or "Button")
        b.BackgroundColor3 = Color3.fromRGB(30,30,30)
        b.TextColor3 = Color3.new(1,1,1)
        Instance.new("UICorner", b).CornerRadius = UDim.new(0,6)
        return b
    end

    local function makeTextBox(parent, placeholder, size, pos)
        local tb = Instance.new("TextBox", parent)
        tb.Size = size or UDim2.new(0,140,0,28)
        tb.Position = pos or UDim2.new(0,0,0,0)
        tb.PlaceholderText = tostring(placeholder or "")
        tb.Font = Enum.Font.SourceSans
        tb.TextSize = 14
        tb.TextColor3 = Color3.new(1,1,1)
        tb.BackgroundColor3 = Color3.fromRGB(28,28,28)
        Instance.new("UICorner", tb).CornerRadius = UDim.new(0,6)
        return tb
    end

    -- Window API
    function library:CreateWindow(title)
        title = tostring(title or "Hate's QOL")
        local window = {}
        window._title = title

        -- main frame
        local mainFrame = makeFrame(screenGui, UDim2.new(0,360,0,250), UDim2.new(0,0,0,40), Color3.fromRGB(18,18,18))
        local header = makeFrame(mainFrame, UDim2.new(1,0,0,30), UDim2.new(0,0,0,0), Color3.fromRGB(14,14,14))
        local titleLabel = makeLabel(header, title, UDim2.new(1, -40, 1, 0), UDim2.new(0,12,0,0))
        titleLabel.TextXAlignment = Enum.TextXAlignment.Left
        titleLabel.Font = Enum.Font.SourceSansBold
        titleLabel.TextSize = 16

        local closeBtn = makeButton(header, "—", UDim2.new(0,34,0,22), UDim2.new(1,-40,0,4))
        closeBtn.TextSize = 18
        closeBtn.MouseButton1Click:Connect(function() mainFrame.Visible = not mainFrame.Visible end)

        -- content holder
        local content = Instance.new("ScrollingFrame", mainFrame)
        content.Size = UDim2.new(1, -16, 1, -42)
        content.Position = UDim2.new(0,8,0,34)
        content.BackgroundTransparency = 1
        content.ScrollBarThickness = 6
        local layout = Instance.new("UIListLayout", content)
        layout.SortOrder = Enum.SortOrder.LayoutOrder
        layout.Padding = UDim.new(0,6)

        -- keep references for destroying and visibility
        window.ScreenGui = screenGui
        window.Frame = mainFrame
        window.Content = content

        -- CreateFolder (folder acts like a section)
        function window:CreateFolder(name)
            local folder = {}
            folder._name = name or "Folder"
            local sec = makeFrame(content, UDim2.new(1,0,0,28), UDim2.new(0,0,0,0), Color3.fromRGB(20,20,20))
            sec.AutomaticSize = Enum.AutomaticSize.Y
            sec.Padding = Instance.new("UIPadding", sec)
            sec.Padding.PaddingTop = UDim.new(0,6)
            sec.Padding.PaddingBottom = UDim.new(0,6)
            -- title
            local lbl = makeLabel(sec, " " .. tostring(name), UDim2.new(1,0,0,20), UDim2.new(0,6,0,0))
            lbl.TextXAlignment = Enum.TextXAlignment.Left
            lbl.Font = Enum.Font.SourceSansBold
            lbl.TextSize = 14

            -- container for children (stack)
            local inner = Instance.new("Frame", sec)
            inner.Size = UDim2.new(1,-12,0,0)
            inner.Position = UDim2.new(0,6,0,24)
            inner.BackgroundTransparency = 1
            inner.AutomaticSize = Enum.AutomaticSize.Y
            local innerLayout = Instance.new("UIListLayout", inner)
            innerLayout.SortOrder = Enum.SortOrder.LayoutOrder
            innerLayout.Padding = UDim.new(0,6)

            -- expose methods similar to rayfield style: AddLabel, AddButton, AddToggle, AddDropdown, AddBox, AddSlider, AddBind
            function folder:AddLabel(text, opts)
                local L = makeLabel(inner, text, UDim2.new(1,0,0,18))
                if opts and opts.TextSize then L.TextSize = opts.TextSize end
                if opts and opts.TextColor then L.TextColor3 = opts.TextColor end
                function L:Update(newText) self.Text = tostring(newText) end
                return L
            end

            function folder:AddButton(text, callback)
                local btn = makeButton(inner, text, UDim2.new(1,0,0,28))
                btn.MouseButton1Click:Connect(function() pcall(function() callback() end) end)
                function btn:SetText(t) btn.Text = tostring(t) end
                return btn
            end

            function folder:AddToggle(text, callback)
                local f = Instance.new("Frame", inner)
                f.Size = UDim2.new(1,0,0,28)
                f.BackgroundTransparency = 1
                local tLabel = makeLabel(f, text, UDim2.new(0.7,0,1,0), UDim2.new(0,8,0,0))
                tLabel.TextXAlignment = Enum.TextXAlignment.Left
                local toggle = makeButton(f, "Off", UDim2.new(0.28,0,0,20), UDim2.new(0.72,6,0,4))
                toggle.TextSize = 12
                local state = false
                toggle.MouseButton1Click:Connect(function()
                    state = not state
                    toggle.Text = state and "On" or "Off"
                    pcall(function() callback(state) end)
                end)
                local obj = {}
                function obj:Set(v) state = v; toggle.Text = state and "On" or "Off" end
                return obj
            end

            function folder:AddBox(label, type_, callback)
                local fbox = Instance.new("Frame", inner)
                fbox.Size = UDim2.new(1,0,0,28)
                fbox.BackgroundTransparency = 1
                local lbl2 = makeLabel(fbox, label, UDim2.new(0.4,0,1,0), UDim2.new(0,8,0,0))
                lbl2.TextXAlignment = Enum.TextXAlignment.Left
                local tb = makeTextBox(fbox, "", UDim2.new(0.58,0,1,0), UDim2.new(0.42,6,0,0))
                tb.FocusLost:Connect(function(enter) if enter then pcall(function() callback(tb.Text) end) end end)
                return tb
            end

            function folder:AddDropdown(label, items, multi, callback)
                local cont = Instance.new("Frame", inner)
                cont.Size = UDim2.new(1,0,0,54)
                cont.BackgroundTransparency = 1
                local l = makeLabel(cont, label, UDim2.new(1,0,0,18), UDim2.new(0,6,0,0))
                l.TextXAlignment = Enum.TextXAlignment.Left
                local btn = makeButton(cont, (items and items[1]) or "None", UDim2.new(1,0,0,28), UDim2.new(0,6,0,24))
                local menu = makeFrame(cont, UDim2.new(1, -12, 0, 0), UDim2.new(0,6,0,52), Color3.fromRGB(16,16,16))
                menu.Visible = false
                menu.ClipsDescendants = true
                local menuLayout = Instance.new("UIListLayout", menu)
                menuLayout.Padding = UDim.new(0,4)

                local currentItems = {}
                local function populate(list)
                    -- clear
                    for _,c in ipairs(menu:GetChildren()) do if not c:IsA("UIListLayout") then c:Destroy() end end
                    currentItems = {}
                    for i,v in ipairs(list or {}) do
                        local opt = Instance.new("TextButton", menu)
                        opt.Size = UDim2.new(1,-8,0,20); opt.Position = UDim2.new(0,4,0,0)
                        opt.BackgroundTransparency = 1
                        opt.Text = tostring(v); opt.Font = Enum.Font.SourceSans; opt.TextSize = 13; opt.TextColor3 = Color3.new(1,1,1)
                        opt.MouseButton1Click:Connect(function()
                            btn.Text = tostring(v)
                            menu.Visible = false
                            pcall(function() callback(v) end)
                        end)
                        table.insert(currentItems, v)
                    end
                    menu.Size = UDim2.new(1, -12, 0, math.min(#list * 22, 8*22))
                end

                -- initial populate
                populate(items or {})

                btn.MouseButton1Click:Connect(function() menu.Visible = not menu.Visible end)

                local dropdownObj = {}
                function dropdownObj.SetOptions(newList)
                    populate(newList or {})
                end
                function dropdownObj.SetValue(v)
                    btn.Text = tostring(v or "")
                end
                function dropdownObj.GetValue()
                    return btn.Text
                end
                function dropdownObj.Refresh()
                    populate(currentItems)
                    if currentItems[1] then
                        btn.Text = tostring(currentItems[1])
                    end
                end

                return dropdownObj
            end

            function folder:AddSlider(label, opts, cb)
                local frameS = Instance.new("Frame", inner)
                frameS.Size = UDim2.new(1,0,0,34)
                frameS.BackgroundTransparency = 1
                local l = makeLabel(frameS, label, UDim2.new(1,0,0,18), UDim2.new(0,6,0,0))
                local slider = Instance.new("TextButton", frameS)
                slider.Size = UDim2.new(1,0,0,12); slider.Position = UDim2.new(0,6,0,18)
                slider.Text = tostring(opts and opts.min or 0)
                slider.Font = Enum.Font.SourceSans
                slider.TextSize = 12
                slider.BackgroundColor3 = Color3.fromRGB(28,28,28)
                Instance.new("UICorner", slider).CornerRadius = UDim.new(0,6)
                -- simple click slider: not a full implementation, provide callback with numeric value on click
                slider.MouseButton1Click:Connect(function()
                    local val = tonumber(opts and opts.min) or 0
                    pcall(function() cb(val) end)
                end)
                return slider
            end

            function folder:AddBind(label, key, cb)
                local fbind = Instance.new("Frame", inner)
                fbind.Size = UDim2.new(1,0,0,28)
                fbind.BackgroundTransparency = 1
                local l = makeLabel(fbind, label, UDim2.new(0.6,0,1,0), UDim2.new(0,6,0,0))
                l.TextXAlignment = Enum.TextXAlignment.Left
                local btn = makeButton(fbind, tostring(key.Name or key), UDim2.new(0.34,0,0,20), UDim2.new(0.66,6,0,4))
                btn.MouseButton1Click:Connect(function() pcall(function() cb() end) end)
                return btn
            end

            function folder:DestroyGui()
                pcall(function() screenGui:Destroy() end)
            end

            -- alias names for Rayfield compatibility
            folder.Label = folder.AddLabel
            folder.Button = folder.AddButton
            folder.Toggle = folder.AddToggle
            folder.Dropdown = folder.AddDropdown
            folder.Box = folder.AddBox
            folder.Slider = folder.AddSlider
            folder.Bind = folder.AddBind

            -- return folder API
            return folder
        end

        return window
    end

    return library
end

return CreateHatesQOL()
