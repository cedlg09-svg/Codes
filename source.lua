-- HatesQOL.lua
-- Minimal Rayfield-like UI replacement with Dropdown:Refresh + dynamic update helpers
-- Paste/host this file raw and load with loadstring(game:HttpGet(URL))()

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
assert(LocalPlayer, "HatesQOL must be run as LocalScript")

local Hates = {}
Hates.__index = Hates
Hates.Version = "1.0"

-- root ScreenGui
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "HatesQOL_Root"
screenGui.ResetOnSpawn = false
screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

-- helpers
local function newFrame(parent, size, pos, color)
    local f = Instance.new("Frame")
    f.Size = size or UDim2.new(0,300,0,200)
    f.Position = pos or UDim2.new(0,0,0,0)
    f.BackgroundColor3 = color or Color3.fromRGB(20,20,20)
    f.BorderSizePixel = 0
    f.Parent = parent
    local c = Instance.new("UICorner", f); c.CornerRadius = UDim.new(0,6)
    return f
end

local function newLabel(parent, txt, size, pos)
    local l = Instance.new("TextLabel")
    l.Size = size or UDim2.new(1,0,0,18)
    l.Position = pos or UDim2.new(0,0,0,0)
    l.BackgroundTransparency = 1
    l.Font = Enum.Font.SourceSans
    l.TextSize = 14
    l.TextColor3 = Color3.new(1,1,1)
    l.Text = tostring(txt or "")
    l.TextWrapped = true
    l.Parent = parent
    function l:Update(t) self.Text = tostring(t) end
    return l
end

local function newButton(parent, txt, size, pos)
    local b = Instance.new("TextButton")
    b.Size = size or UDim2.new(0,120,0,28)
    b.Position = pos or UDim2.new(0,0,0,0)
    b.Font = Enum.Font.SourceSansBold
    b.TextSize = 13
    b.Text = tostring(txt or "Button")
    b.BackgroundColor3 = Color3.fromRGB(30,30,30)
    b.TextColor3 = Color3.new(1,1,1)
    b.Parent = parent
    Instance.new("UICorner", b).CornerRadius = UDim.new(0,6)
    function b:SetText(t) self.Text = tostring(t) end
    return b
end

local function newTextBox(parent, placeholder, size, pos)
    local tb = Instance.new("TextBox")
    tb.Size = size or UDim2.new(0,140,0,28)
    tb.Position = pos or UDim2.new(0,0,0,0)
    tb.PlaceholderText = tostring(placeholder or "")
    tb.Font = Enum.Font.SourceSans
    tb.TextSize = 14
    tb.TextColor3 = Color3.new(1,1,1)
    tb.BackgroundColor3 = Color3.fromRGB(28,28,28)
    tb.Parent = parent
    Instance.new("UICorner", tb).CornerRadius = UDim.new(0,6)
    return tb
end

-- Public API: CreateWindow -> CreateFolder -> AddX
function Hates.CreateWindow(title)
    title = tostring(title or "Hate's QOL")
    local win = {}
    win._title = title

    local frame = newFrame(screenGui, UDim2.new(0,360,0,280), UDim2.new(0,6,0,6), Color3.fromRGB(18,18,18))
    local header = newFrame(frame, UDim2.new(1,0,0,32), UDim2.new(0,0,0,0), Color3.fromRGB(14,14,14))
    local titleLbl = newLabel(header, " "..title, UDim2.new(1,-40,0,28), UDim2.new(0,8,0,2))
    titleLbl.Font = Enum.Font.SourceSansBold
    titleLbl.TextSize = 16
    titleLbl.TextXAlignment = Enum.TextXAlignment.Left

    local closeBtn = newButton(header, "—", UDim2.new(0,34,0,22), UDim2.new(1,-44,0,4))
    closeBtn.TextSize = 18
    closeBtn.MouseButton1Click:Connect(function()
        frame.Visible = not frame.Visible
    end)

    local content = Instance.new("ScrollingFrame", frame)
    content.Name = "Content"
    content.Size = UDim2.new(1, -16, 1, -48)
    content.Position = UDim2.new(0,8,0,40)
    content.BackgroundTransparency = 1
    content.ScrollBarThickness = 6
    local layout = Instance.new("UIListLayout", content)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0,6)

    win.ScreenGui = screenGui
    win.Frame = frame
    win.Content = content

    function win:CreateFolder(name)
        local folder = {}
        local section = newFrame(content, UDim2.new(1,0,0,24), UDim2.new(0,0,0,0), Color3.fromRGB(20,20,20))
        section.AutomaticSize = Enum.AutomaticSize.Y
        section.Padding = Instance.new("UIPadding", section)
        section.Padding.PaddingTop = UDim.new(0,6)
        section.Padding.PaddingBottom = UDim.new(0,6)

        local headerLbl = newLabel(section, " "..tostring(name or "Folder"), UDim2.new(1,0,0,20), UDim2.new(0,6,0,0))
        headerLbl.Font = Enum.Font.SourceSansBold
        headerLbl.TextSize = 14
        headerLbl.TextXAlignment = Enum.TextXAlignment.Left

        local inner = Instance.new("Frame", section)
        inner.Size = UDim2.new(1,-12,0,0)
        inner.Position = UDim2.new(0,6,0,24)
        inner.BackgroundTransparency = 1
        inner.AutomaticSize = Enum.AutomaticSize.Y
        local inLayout = Instance.new("UIListLayout", inner)
        inLayout.SortOrder = Enum.SortOrder.LayoutOrder
        inLayout.Padding = UDim.new(0,6)

        -- AddLabel
        function folder:AddLabel(text, opts)
            local opt = newLabel(inner, text, UDim2.new(1,0,0,18))
            if opts and opts.TextSize then opt.TextSize = opts.TextSize end
            if opts and opts.TextColor then opt.TextColor3 = opts.TextColor end
            function opt:Update(t) self.Text = tostring(t) end
            return opt
        end

        -- AddButton
        function folder:AddButton(text, cb)
            local btn = newButton(inner, text, UDim2.new(1,0,0,28))
            btn.MouseButton1Click:Connect(function() pcall(cb) end)
            function btn:SetText(t) btn.Text = tostring(t) end
            return btn
        end

        -- AddToggle
        function folder:AddToggle(text, cb)
            local container = Instance.new("Frame", inner)
            container.Size = UDim2.new(1,0,0,28); container.BackgroundTransparency = 1
            local lbl = newLabel(container, text, UDim2.new(0.7,0,1,0), UDim2.new(0,8,0,0)); lbl.TextXAlignment = Enum.TextXAlignment.Left
            local toggleBtn = newButton(container, "Off", UDim2.new(0.28,0,0,20), UDim2.new(0.72,6,0,4)); toggleBtn.TextSize = 12
            local state = false
            toggleBtn.MouseButton1Click:Connect(function()
                state = not state; toggleBtn.Text = state and "On" or "Off"; pcall(cb, state)
            end)
            local obj = {}
            function obj:Set(v) state = v; toggleBtn.Text = state and "On" or "Off" end
            return obj
        end

        -- AddBox
        function folder:AddBox(label, kind, cb)
            local f = Instance.new("Frame", inner); f.Size = UDim2.new(1,0,0,28); f.BackgroundTransparency = 1
            local lbl = newLabel(f, label, UDim2.new(0.4,0,1,0), UDim2.new(0,8,0,0)); lbl.TextXAlignment = Enum.TextXAlignment.Left
            local tb = newTextBox(f, "", UDim2.new(0.58,0,1,0), UDim2.new(0.42,6,0,0))
            tb.FocusLost:Connect(function(enter) if enter then pcall(cb, tb.Text) end end)
            return tb
        end

        -- AddDropdown (with Refresh)
        function folder:AddDropdown(label, items, multi, cb)
            local wrap = Instance.new("Frame", inner); wrap.Size = UDim2.new(1,0,0,54); wrap.BackgroundTransparency = 1
            local l = newLabel(wrap, label, UDim2.new(1,0,0,18), UDim2.new(0,6,0,0)); l.TextXAlignment = Enum.TextXAlignment.Left
            local btn = newButton(wrap, (items and items[1]) or "None", UDim2.new(1,0,0,28), UDim2.new(0,6,0,24))
            local menu = newFrame(wrap, UDim2.new(1,-12,0,0), UDim2.new(0,6,0,52), Color3.fromRGB(16,16,16))
            menu.Visible = false; menu.ClipsDescendants = true
            local menuLayout = Instance.new("UIListLayout", menu); menuLayout.Padding = UDim.new(0,4)

            local current = {}
            local function populate(list)
                -- clear
                for _,c in ipairs(menu:GetChildren()) do if not c:IsA("UIListLayout") then c:Destroy() end end
                current = {}
                for i,v in ipairs(list or {}) do
                    local opt = Instance.new("TextButton", menu)
                    opt.Size = UDim2.new(1,-8,0,20); opt.Position = UDim2.new(0,4,0,0)
                    opt.BackgroundTransparency = 1
                    opt.Text = tostring(v); opt.Font = Enum.Font.SourceSans; opt.TextSize = 13; opt.TextColor3 = Color3.new(1,1,1)
                    opt.MouseButton1Click:Connect(function()
                        btn.Text = tostring(v); menu.Visible = false; pcall(cb, v)
                    end)
                    table.insert(current, v)
                end
                menu.Size = UDim2.new(1,-12,0, math.min(#list * 22, 8*22))
            end

            populate(items or {})

            btn.MouseButton1Click:Connect(function() menu.Visible = not menu.Visible end)

            local dd = {}
            function dd.SetOptions(list) populate(list or {}) end
            function dd.SetValue(v) btn.Text = tostring(v or "") end
            function dd.GetValue() return btn.Text end
            function dd.Refresh(newList, autoSelectFirst)
                if newList ~= nil then populate(newList) end
                if autoSelectFirst and current[1] then btn.Text = tostring(current[1]) end
            end
            return dd
        end

        -- AddSlider (minimal)
        function folder:AddSlider(label, opts, cb)
            local f = Instance.new("Frame", inner); f.Size = UDim2.new(1,0,0,34); f.BackgroundTransparency = 1
            local l = newLabel(f, label, UDim2.new(1,0,0,18), UDim2.new(0,6,0,0))
            local s = newButton(f, tostring(opts and opts.min or 0), UDim2.new(1,0,0,12), UDim2.new(0,6,0,18))
            s.MouseButton1Click:Connect(function() local v = tonumber(opts and opts.min) or 0; pcall(cb, v) end)
            return s
        end

        -- AddBind (minimal)
        function folder:AddBind(label, key, cb)
            local f = Instance.new("Frame", inner); f.Size = UDim2.new(1,0,0,28); f.BackgroundTransparency = 1
            local l = newLabel(f, label, UDim2.new(0.6,0,1,0), UDim2.new(0,6,0,0)); l.TextXAlignment = Enum.TextXAlignment.Left
            local b = newButton(f, tostring(key.Name or key), UDim2.new(0.34,0,0,20), UDim2.new(0.66,6,0,4))
            b.MouseButton1Click:Connect(function() pcall(cb) end)
            return b
        end

        function folder:DestroyGui() pcall(function() screenGui:Destroy() end) end

        -- compatibility aliases
        folder.Label = folder.AddLabel
        folder.Button = folder.AddButton
        folder.Toggle = folder.AddToggle
        folder.Dropdown = folder.AddDropdown
        folder.Box = folder.AddBox
        folder.Slider = folder.AddSlider
        folder.Bind = folder.AddBind

        return folder
    end

    return Hates.CreateWindow and Hates.CreateWindow or function(t) return Hates end
end

-- return a loader function that returns the API
local api = {}
function api.CreateWindow(...) return Hates.CreateWindow(...) end

-- expose minimal top-level API (compatibility)
local ret = {}
ret.CreateWindow = function(...) return Hates.CreateWindow(...) end
ret.Version = "HatesQOL-1.0"

return ret
