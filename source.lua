-- Hate's QoL (patched Rayfield) - source.lua
-- Renamed/extended Rayfield-like minimal UI library
-- Exposes Hates.CreateWindow(...)
-- Theme: glossy jet black + dark gray highlights, white text

local Hates = {}
Hates.Version = "HatesQoL-Extended-1.0"

-- Services
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

-- Helpers
local function safe_parent()
    -- prefer CoreGui, fallback to PlayerGui (if allowed)
    if CoreGui and CoreGui:IsA("Instance") then
        return CoreGui
    end
    local plr = Players.LocalPlayer
    if plr and plr:FindFirstChild("PlayerGui") then
        return plr.PlayerGui
    end
    return workspace
end

local function add_uicorner(inst, radius)
    radius = radius or 6
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius)
    c.Parent = inst
    return c
end

local function new_textlabel(parent, props)
    props = props or {}
    local t = Instance.new("TextLabel")
    t.BackgroundTransparency = props.BackgroundTransparency or 1
    t.Size = props.Size or UDim2.new(1,0,0,18)
    t.Position = props.Position or UDim2.new(0,0,0,0)
    t.Font = props.Font or Enum.Font.SourceSans
    t.TextSize = props.TextSize or 14
    t.TextColor3 = props.TextColor or Color3.fromRGB(255,255,255)
    t.Text = tostring(props.Text or "")
    t.TextWrapped = props.TextWrapped or false
    t.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
    t.TextYAlignment = props.TextYAlignment or Enum.TextYAlignment.Center
    t.BorderSizePixel = 0
    t.Parent = parent
    return t
end

local function new_button(parent, props)
    props = props or {}
    local b = Instance.new("TextButton")
    b.Size = props.Size or UDim2.new(0,120,0,28)
    b.Position = props.Position or UDim2.new(0,0,0,0)
    b.BackgroundColor3 = props.BackgroundColor or Color3.fromRGB(40,40,40)
    b.TextColor3 = props.TextColor or Color3.fromRGB(255,255,255)
    b.Font = props.Font or Enum.Font.SourceSansBold
    b.TextSize = props.TextSize or 14
    b.Text = tostring(props.Text or "Button")
    b.AutoButtonColor = true
    b.BorderSizePixel = 0
    add_uicorner(b, 6)
    b.Parent = parent
    return b
end

-- Make GUI draggable (basic)
local function make_draggable(gui)
    if not gui or not gui:IsA("GuiObject") then return end
    local dragging, dragStart, startPos, dragInput
    gui.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = gui.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    gui.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            dragInput = input
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging and dragStart and startPos then
            local delta = input.Position - dragStart
            gui.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
end

-- Dropdown builder with Refresh
local function build_dropdown(parent, width, x, y, labelText, items, callback)
    items = items or {}
    local label = new_textlabel(parent, {
        Size = UDim2.new(0, width, 0, 18),
        Position = UDim2.new(0, x, 0, y),
        Text = labelText or "Select",
        TextSize = 14,
        TextColor = Color3.fromRGB(240,240,240),
    })

    local btn = new_button(parent, {
        Size = UDim2.new(0, width, 0, 26),
        Position = UDim2.new(0, x, 0, y + 18),
        Text = items[1] or "None",
        BackgroundColor = Color3.fromRGB(30,30,30),
    })

    local menu = Instance.new("Frame", parent)
    menu.Size = UDim2.new(0, width, 0, math.min(#items * 24, 200))
    menu.Position = UDim2.new(0, x, 0, y + 46)
    menu.BackgroundColor3 = Color3.fromRGB(22,22,22)
    menu.BorderSizePixel = 0
    add_uicorner(menu, 6)
    menu.Visible = false

    local layout = Instance.new("UIListLayout", menu)
    layout.Padding = UDim.new(0,4)
    layout.SortOrder = Enum.SortOrder.LayoutOrder

    local function populate(list)
        for _,c in ipairs(menu:GetChildren()) do
            if c:IsA("TextButton") then c:Destroy() end
        end
        for _, opt in ipairs(list) do
            local o = Instance.new("TextButton", menu)
            o.Size = UDim2.new(1, -8, 0, 20)
            o.Position = UDim2.new(0,4,0,0)
            o.BackgroundTransparency = 1
            o.Text = tostring(opt)
            o.Font = Enum.Font.SourceSans
            o.TextSize = 14
            o.TextColor3 = Color3.fromRGB(255,255,255)
            o.AutoButtonColor = true
            o.BorderSizePixel = 0
            o.MouseButton1Click:Connect(function()
                btn.Text = tostring(opt)
                menu.Visible = false
                if type(callback) == "function" then
                    pcall(callback, opt)
                end
            end)
        end
        local count = #list
        if count < 1 then count = 1 end
        menu.Size = UDim2.new(0, width, 0, math.min(count * 24, 200))
    end

    btn.MouseButton1Click:Connect(function()
        menu.Visible = not menu.Visible
    end)

    populate(items)

    local obj = {
        Button = btn,
        Menu = menu,
        Label = label,
        Items = items,
        Callback = callback
    }

    function obj.Refresh(newItems, autoFirst)
        if type(newItems) ~= "table" then newItems = {} end
        obj.Items = newItems
        populate(obj.Items)
        if autoFirst and #obj.Items > 0 then
            btn.Text = tostring(obj.Items[1])
            if type(obj.Callback) == "function" then
                pcall(obj.Callback, obj.Items[1])
            end
        end
    end

    function obj.Set(v)
        btn.Text = tostring(v or "")
        if type(obj.Callback) == "function" then pcall(obj.Callback, v) end
    end

    function obj.Get()
        return btn.Text
    end

    return obj
end

-- Label builder (Update)
local function build_label(parent, text, opts)
    opts = opts or {}
    local lbl = new_textlabel(parent, {
        Size = opts.Size or UDim2.new(1,-12,0,18),
        Position = opts.Position or UDim2.new(0,8,0,0),
        Text = text or "",
        TextSize = opts.TextSize or 14,
        TextColor = opts.TextColor or Color3.fromRGB(255,255,255),
        TextWrapped = true
    })
    local obj = {}
    function obj.Update(t)
        pcall(function() lbl.Text = tostring(t or "") end)
    end
    function obj.Raw() return lbl end
    function obj.Destroy() pcall(function() lbl:Destroy() end) end
    return obj
end

-- Button builder (Update)
local function build_btn(parent, text, cb, opts)
    opts = opts or {}
    local b = new_button(parent, {Text = text or "Button", BackgroundColor = opts.BackgroundColor})
    b.Parent = parent
    local obj = {}
    b.MouseButton1Click:Connect(function() if type(cb) == "function" then pcall(cb) end end)
    function obj.Update(t) pcall(function() b.Text = tostring(t or "") end) end
    function obj.Destroy() pcall(function() b:Destroy() end) end
    return obj
end

-- Toggle builder
local function build_toggle(parent, label, default, cb)
    local container = Instance.new("Frame", parent)
    container.Size = UDim2.new(1, -12, 0, 28)
    container.BackgroundTransparency = 1
    add_uicorner(container, 6)

    local lbl = new_textlabel(container, {Size = UDim2.new(0.64,0,1,0), Position = UDim2.new(0,4,0,0), Text = label or "", TextSize = 14})
    local tb = new_button(container, {Size = UDim2.new(0.34,-8,1,0), Position = UDim2.new(0.64,4,0,0), Text = (default and "ON" or "OFF"), BackgroundColor = (default and Color3.fromRGB(34,139,34) or Color3.fromRGB(80,80,80))})
    local state = not not default
    tb.MouseButton1Click:Connect(function()
        state = not state
        tb.Text = state and "ON" or "OFF"
        tb.BackgroundColor3 = state and Color3.fromRGB(34,139,34) or Color3.fromRGB(80,80,80)
        if type(cb) == "function" then pcall(cb, state) end
    end)
    local obj = {}
    function obj.Get() return state end
    function obj.Set(v) state = not not v; tb.Text = state and "ON" or "OFF"; tb.BackgroundColor3 = state and Color3.fromRGB(34,139,34) or Color3.fromRGB(80,80,80) end
    function obj.Destroy() pcall(function() container:Destroy() end) end
    return obj
end

-- TextBox builder
local function build_box(parent, labelText, cb)
    local container = Instance.new("Frame", parent)
    container.Size = UDim2.new(1, -12, 0, 28)
    container.BackgroundTransparency = 1

    local lbl = new_textlabel(container, {Size = UDim2.new(0.28,0,1,0), Position = UDim2.new(0,4,0,0), Text = labelText or "", TextSize = 14})
    local box = Instance.new("TextBox", container)
    box.Size = UDim2.new(0.70, -12, 1, 0)
    box.Position = UDim2.new(0.30, 4, 0, 0)
    box.Text = ""
    box.Font = Enum.Font.SourceSans
    box.TextSize = 14
    box.BackgroundColor3 = Color3.fromRGB(30,30,30)
    box.TextColor3 = Color3.fromRGB(255,255,255)
    add_uicorner(box, 6)
    box.ClearTextOnFocus = false
    box.Changed:Connect(function()
        if type(cb) == "function" then pcall(cb, box.Text) end
    end)
    local obj = {}
    function obj.Get() return box.Text end
    function obj.Set(v) box.Text = tostring(v or "") end
    function obj.Destroy() pcall(function() container:Destroy() end) end
    return obj
end

-- Window / Folder API
function Hates.CreateWindow(title)
    local parent = safe_parent()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = ("HatesQOL_%d"):format(math.random(1000,9999))
    screenGui.ResetOnSpawn = false
    screenGui.Parent = parent

    local frame = Instance.new("Frame", screenGui)
    frame.Size = UDim2.new(0,420,0,360)
    frame.Position = UDim2.new(0,8,0,36) -- top-left-ish
    frame.BackgroundColor3 = Color3.fromRGB(18,18,18)
    frame.BorderSizePixel = 0
    add_uicorner(frame, 8)

    local titleLbl = new_textlabel(frame, {Size = UDim2.new(1,-16,0,28), Position = UDim2.new(0,8,0,8), Text = tostring(title or "Hate's QoL"), Font = Enum.Font.SourceSansBold, TextSize = 18, TextColor = Color3.fromRGB(255,255,255)})

    -- minimize button (native), and restore icon
    local minBtn = Instance.new("TextButton", frame)
    minBtn.Size = UDim2.new(0,28,0,24)
    minBtn.Position = UDim2.new(1,-36,0,8)
    minBtn.Text = "—"
    minBtn.Font = Enum.Font.SourceSansBold
    minBtn.TextSize = 18
    minBtn.BackgroundTransparency = 0.15
    minBtn.BackgroundColor3 = Color3.fromRGB(34,34,34)
    minBtn.TextColor3 = Color3.fromRGB(255,255,255)
    add_uicorner(minBtn, 6)

    local content = Instance.new("ScrollingFrame", frame)
    content.Name = "HatesContent"
    content.Size = UDim2.new(1,-20,1,-56)
    content.Position = UDim2.new(0,10,0,44)
    content.BackgroundTransparency = 1
    content.CanvasSize = UDim2.new(0,0,0,0)
    content.AutomaticCanvasSize = Enum.AutomaticSize.Y
    content.ScrollBarThickness = 6
    content.BorderSizePixel = 0

    local listLayout = Instance.new("UIListLayout", content)
    listLayout.Padding = UDim.new(0,8)
    listLayout.SortOrder = Enum.SortOrder.LayoutOrder

    local padding = Instance.new("UIPadding", content)
    padding.PaddingLeft = UDim.new(0,6)
    padding.PaddingTop = UDim.new(0,4)
    padding.PaddingRight = UDim.new(0,6)

    -- restore icon
    local icon = Instance.new("TextButton", screenGui)
    icon.Name = "HatesQOL_MinIcon"
    icon.Size = UDim2.new(0,100,0,36)
    icon.Position = UDim2.new(0, frame.AbsolutePosition.X + frame.AbsoluteSize.X - 120, 0, frame.AbsolutePosition.Y)
    icon.Text = "Hate's QoL"
    icon.Font = Enum.Font.SourceSansBold
    icon.TextSize = 14
    icon.BackgroundColor3 = Color3.fromRGB(14,14,14)
    icon.TextColor3 = Color3.fromRGB(255,255,255)
    add_uicorner(icon, 8)
    icon.Visible = false

    minBtn.MouseButton1Click:Connect(function()
        frame.Visible = false
        icon.Visible = true
        pcall(function()
            local pos = frame.AbsolutePosition
            icon.Position = UDim2.new(0, pos.X + frame.AbsoluteSize.X - 120, 0, pos.Y)
        end)
    end)
    icon.MouseButton1Click:Connect(function()
        frame.Visible = true
        icon.Visible = false
    end)

    -- make draggable
    pcall(function() make_draggable(frame) end)

    local window = {
        ScreenGui = screenGui,
        Frame = frame,
        Content = content,
        Title = titleLbl,
        Icon = icon
    }

    function window:CreateFolder(name)
        local folder = Instance.new("Frame", self.Content)
        folder.Size = UDim2.new(1,0,0,36)
        folder.BackgroundTransparency = 0
        folder.BackgroundColor3 = Color3.fromRGB(22,22,22)
        folder.BorderSizePixel = 0
        add_uicorner(folder, 6)

        local header = new_textlabel(folder, {Size = UDim2.new(1,-12,0,28), Position = UDim2.new(0,8,0,4), Text = tostring(name or "Folder"), Font = Enum.Font.SourceSansBold, TextSize = 16, TextColor = Color3.fromRGB(255,255,255)})
        header.LayoutOrder = 1

        local inner = Instance.new("Frame", folder)
        inner.Name = "FolderInner"
        inner.Size = UDim2.new(1,-12,0,8)
        inner.Position = UDim2.new(0,6,0,36)
        inner.BackgroundTransparency = 1

        local innerLayout = Instance.new("UIListLayout", inner)
        innerLayout.Padding = UDim.new(0,8)
        innerLayout.SortOrder = Enum.SortOrder.LayoutOrder

        local api = {}

        function api:Label(text, opts)
            opts = opts or {}
            local lbl = Instance.new("TextLabel", inner)
            lbl.Size = opts.Size or UDim2.new(1,-8,0,opts.Height or 18)
            lbl.BackgroundTransparency = 1
            lbl.Font = opts.Font or Enum.Font.SourceSans
            lbl.TextSize = opts.TextSize or 14
            lbl.TextColor3 = opts.TextColor or Color3.fromRGB(255,255,255)
            lbl.Text = tostring(text or "")
            lbl.TextWrapped = true
            lbl.LayoutOrder = 1
            local o = {}
            function o.Update(t) pcall(function() lbl.Text = tostring(t or "") end) end
            function o.Destroy() pcall(function() lbl:Destroy() end) end
            return o
        end

        function api:Button(text, cb, opts)
            opts = opts or {}
            local btn = new_button(inner, {Size = opts.Size or UDim2.new(0,140,0,30), Text = text or "Button", BackgroundColor = opts.BackgroundColor or Color3.fromRGB(40,40,40)})
            btn.Parent = inner
            btn.LayoutOrder = 2
            local obj = {}
            btn.MouseButton1Click:Connect(function() if type(cb) == "function" then pcall(cb) end end)
            function obj.Update(t) pcall(function() btn.Text = tostring(t or "") end) end
            function obj.Destroy() pcall(function() btn:Destroy() end) end
            return obj
        end

        function api:Dropdown(label, items, multi, cb)
            local dd = build_dropdown(inner, 220, 6, 6, label or "Select", items or {}, cb)
            dd.Button.Parent = inner
            dd.Label.Parent = inner
            dd.Menu.Parent = inner
            dd.Button.LayoutOrder = 3
            dd.Label.LayoutOrder = 3
            dd.Menu.LayoutOrder = 4
            return dd
        end

        function api:Toggle(label, cb, default)
            local t = build_toggle(inner, label or "Toggle", default, cb)
            t._holder.LayoutOrder = 5
            return t
        end

        function api:Box(label, kind, cb)
            local b = build_box(inner, label or "Box", cb)
            b._holder = b -- compatibility
            local holder = Instance.new("Frame", inner)
            holder.Size = UDim2.new(1,0,0,28)
            holder.BackgroundTransparency = 1
            holder.LayoutOrder = 6
            return b
        end

        function api:Slider(label, params, cb)
            -- placeholder; keep minimal to avoid missing API
            local container = Instance.new("Frame", inner)
            container.Size = UDim2.new(1,-12,0,36)
            container.BackgroundTransparency = 1
            container.LayoutOrder = 7
            -- callback zero initially
            pcall(function() if type(cb) == "function" then cb(params and params.min or 0) end end)
            local s = {}
            function s.Set() end
            function s.Destroy() pcall(function() container:Destroy() end) end
            return s
        end

        function api:Bind() end
        function api:ColorPicker() end

        function api:Clear()
            -- remove inner children (except layout)
            for _,c in ipairs(inner:GetChildren()) do
                if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then
                    c:Destroy()
                end
            end
        end

        function api:Destroy()
            pcall(function() folder:Destroy() end)
        end

        return api
    end

    function window:Destroy() pcall(function() screenGui:Destroy() end) end
    function window:SetTitle(t) pcall(function() titleLbl.Text = tostring(t or "") end) end

    return window
end

return Hates
