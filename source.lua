-- HatesQOL UI Library (source.lua)
-- Minimal Rayfield-like API (CreateWindow, CreateFolder, Button, Dropdown, Label, Toggle, etc.)
-- Namespaced as `Hates`
-- Return `Hates` at the end.

local Hates = {}
Hates.Version = "HatesQOL-1.0"

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local LocalPlayer = Players.LocalPlayer

-- Utility
local function isDescendant(parent, child)
    if not parent or not child then return false end
    return child:IsDescendantOf(parent)
end

local function addUICorner(inst, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius or 6)
    c.Parent = inst
    return c
end

local function sanitizeText(t) return tostring(t or "") end

-- Where to parent screens: prefer CoreGui but if on studio use PlayerGui
local function getScreenParent()
    -- try CoreGui first (executors often allow)
    if CoreGui and typeof(CoreGui) == "Instance" then
        return CoreGui
    end
    if LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui") then
        return LocalPlayer.PlayerGui
    end
    -- fallback to Workspace
    return workspace
end

-- Make draggable generic helper (simple)
local function makeDraggable(frame)
    if not frame or not frame:IsA("GuiObject") then return end
    local UserInputService = game:GetService("UserInputService")
    local dragging, dragInput, dragStart, startPos

    frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    frame.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            dragInput = input
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging and dragStart and startPos then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
end

-- Basic element factories
local function newTextLabel(parent, props)
    props = props or {}
    local lbl = Instance.new("TextLabel")
    lbl.BackgroundTransparency = 1
    lbl.Size = props.Size or UDim2.new(1, 0, 0, 18)
    lbl.Position = props.Position or UDim2.new(0, 0, 0, 0)
    lbl.Font = props.Font or Enum.Font.SourceSans
    lbl.TextSize = props.TextSize or 14
    lbl.TextColor3 = props.TextColor or Color3.new(1,1,1)
    lbl.Text = props.Text or ""
    lbl.TextWrapped = props.TextWrapped or false
    lbl.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
    lbl.TextYAlignment = props.TextYAlignment or Enum.TextYAlignment.Center
    lbl.Parent = parent
    return lbl
end

local function newButton(parent, props)
    props = props or {}
    local btn = Instance.new("TextButton")
    btn.Size = props.Size or UDim2.new(0, 120, 0, 28)
    btn.Position = props.Position or UDim2.new(0, 0, 0, 0)
    btn.BackgroundColor3 = props.BackgroundColor or Color3.fromRGB(60,60,60)
    btn.TextColor3 = props.TextColor or Color3.new(1,1,1)
    btn.Font = props.Font or Enum.Font.SourceSansBold
    btn.TextSize = props.TextSize or 14
    btn.Text = props.Text or "Button"
    btn.AutoButtonColor = true
    addUICorner(btn, 6)
    btn.Parent = parent
    return btn
end

local function newFrame(parent, props)
    props = props or {}
    local f = Instance.new("Frame")
    f.Size = props.Size or UDim2.new(0, 200, 0, 120)
    f.Position = props.Position or UDim2.new(0, 0, 0, 0)
    f.BackgroundColor3 = props.BackgroundColor or Color3.fromRGB(30,30,30)
    f.BorderSizePixel = 0
    f.Parent = parent
    return f
end

-- Dropdown building helper (returns object with Refresh)
local function buildDropdown(parent, width, x, y, labelText, items, callback)
    local lbl = newTextLabel(parent, {Size = UDim2.new(0, width, 0, 18), Position = UDim2.new(0, x, 0, y), Text = labelText, TextSize = 14})
    lbl.BackgroundTransparency = 1

    local btn = newButton(parent, {Size = UDim2.new(0, width, 0, 26), Position = UDim2.new(0, x, 0, y+18), Text = items[1] or "None", BackgroundColor = Color3.fromRGB(50,50,50)})
    btn.AutoButtonColor = true

    local menu = Instance.new("Frame", parent)
    menu.Size = UDim2.new(0, width, 0, math.min(#items*22, 200))
    menu.Position = UDim2.new(0, x, 0, y + 46)
    menu.BackgroundColor3 = Color3.fromRGB(40,40,40)
    menu.Visible = false
    menu.BorderSizePixel = 0
    addUICorner(menu, 6)

    local layout = Instance.new("UIListLayout", menu)
    layout.Padding = UDim.new(0,4)
    layout.SortOrder = Enum.SortOrder.LayoutOrder

    local function populate(list)
        -- clear old
        for _,c in ipairs(menu:GetChildren()) do
            if c:IsA("TextButton") then c:Destroy() end
        end
        for _, opt in ipairs(list or {}) do
            local obtn = Instance.new("TextButton", menu)
            obtn.Size = UDim2.new(1, -8, 0, 20)
            obtn.Position = UDim2.new(0, 4, 0, 0)
            obtn.BackgroundTransparency = 1
            obtn.Text = tostring(opt)
            obtn.Font = Enum.Font.SourceSans
            obtn.TextSize = 14
            obtn.TextColor3 = Color3.new(1,1,1)
            obtn.AutoButtonColor = true
            obtn.MouseButton1Click:Connect(function()
                btn.Text = tostring(opt)
                menu.Visible = false
                if type(callback) == "function" then
                    pcall(callback, opt)
                end
            end)
        end
        -- adjust size
        local count = #list
        if count < 1 then count = 1 end
        menu.Size = UDim2.new(0, width, 0, math.min(count*24, 200))
    end

    btn.MouseButton1Click:Connect(function()
        menu.Visible = not menu.Visible
    end)

    -- initial populate
    populate(items)

    local obj = {
        Button = btn,
        Menu = menu,
        Label = lbl,
        _items = items,
        _callback = callback
    }

    function obj.Refresh(newItems, autoSelectFirst)
        obj._items = newItems or {}
        populate(obj._items)
        if autoSelectFirst and #obj._items > 0 then
            btn.Text = tostring(obj._items[1])
            if type(callback) == "function" then
                pcall(callback, obj._items[1])
            end
        end
    end

    function obj.SetValue(val)
        btn.Text = tostring(val)
        if type(callback) == "function" then pcall(callback, val) end
    end

    return obj
end

-- Label object with Update
local function buildLabel(parent, text, opts)
    opts = opts or {}
    local label = newTextLabel(parent, {Size = opts.Size or UDim2.new(1, -8, 0, 18), Position = opts.Position or UDim2.new(0, 8, 0, 0), Text = text or "", TextSize = opts.TextSize or 14, TextColor = opts.TextColor or Color3.new(1,1,1), TextWrapped = opts.TextWrapped or true})
    local obj = {}
    function obj.Update(newText)
        label.Text = tostring(newText or "")
    end
    function obj.Destroy()
        label:Destroy()
    end
    return obj
end

-- Button wrapper exposing SetText
local function buildButton(parent, text, callback, opts)
    opts = opts or {}
    local btn = newButton(parent, {Size = opts.Size or UDim2.new(0, 120, 0, 28), Position = opts.Position, Text = text or "Button", BackgroundColor = opts.BackgroundColor or Color3.fromRGB(60,60,60)})
    local obj = {}
    btn.MouseButton1Click:Connect(function()
        if type(callback) == "function" then pcall(callback) end
    end)
    function obj.SetText(s)
        if btn and btn.Parent then
            btn.Text = tostring(s or "")
        end
    end
    function obj.Destroy()
        if btn and btn.Parent then btn:Destroy() end
    end
    return obj, btn
end

-- Toggle wrapper
local function buildToggle(parent, labelText, default, callback, opts)
    opts = opts or {}
    local container = Instance.new("Frame", parent)
    container.Size = opts.Size or UDim2.new(0, 160, 0, 28)
    container.BackgroundTransparency = 1

    local lbl = newTextLabel(container, {Size = UDim2.new(0.65, 0, 1, 0), Position = UDim2.new(0, 4, 0, 0), Text = labelText, TextSize = 14})
    local btn = newButton(container, {Size = UDim2.new(0.32, -8, 1, 0), Position = UDim2.new(0.68, 4, 0, 0), Text = (default and "ON" or "OFF"), BackgroundColor = (default and Color3.fromRGB(34,139,34) or Color3.fromRGB(120,120,120))})

    local state = default and true or false
    btn.MouseButton1Click:Connect(function()
        state = not state
        btn.Text = state and "ON" or "OFF"
        btn.BackgroundColor3 = state and Color3.fromRGB(34,139,34) or Color3.fromRGB(120,120,120)
        if type(callback) == "function" then pcall(callback, state) end
    end)

    local obj = {}
    function obj.Set(stateVal)
        state = not not stateVal
        btn.Text = state and "ON" or "OFF"
        btn.BackgroundColor3 = state and Color3.fromRGB(34,139,34) or Color3.fromRGB(120,120,120)
    end
    function obj.Get()
        return state
    end
    function obj.Destroy()
        container:Destroy()
    end
    return obj
end

-- Simple slider (no styling complexity)
local function buildSlider(parent, labelText, minV, maxV, precise, callback)
    local container = Instance.new("Frame", parent)
    container.Size = UDim2.new(0, 200, 0, 36)
    container.BackgroundTransparency = 1

    local lbl = newTextLabel(container, {Size = UDim2.new(0.5, 0, 0, 18), Position = UDim2.new(0, 4, 0, 0), Text = labelText})
    local valText = newTextLabel(container, {Size = UDim2.new(0.5, -8, 0, 18), Position = UDim2.new(0.5, 4, 0, 0), Text = tostring(minV), TextXAlignment = Enum.TextXAlignment.Right})

    local sliderBg = Instance.new("Frame", container)
    sliderBg.Size = UDim2.new(1, -8, 0, 8)
    sliderBg.Position = UDim2.new(0, 4, 0, 20)
    sliderBg.BackgroundColor3 = Color3.fromRGB(50,50,50)
    addUICorner(sliderBg, 6)

    local fill = Instance.new("Frame", sliderBg)
    fill.Size = UDim2.new(0, 0, 1, 0)
    fill.Position = UDim2.new(0,0,0,0)
    fill.BackgroundColor3 = Color3.fromRGB(70,130,180)
    addUICorner(fill, 6)

    local dragging = false
    local UserInputService = game:GetService("UserInputService")
    sliderBg.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local rel = math.clamp((input.Position.X - sliderBg.AbsolutePosition.X) / sliderBg.AbsoluteSize.X, 0, 1)
            fill.Size = UDim2.new(rel, 0, 1, 0)
            local val = minV + (maxV - minV) * rel
            if not precise then val = math.floor(val) end
            valText.Text = tostring(val)
            if type(callback) == "function" then pcall(callback, val) end
        end
    end)

    local obj = {}
    function obj.Set(val)
        local ratio = math.clamp((val - minV) / (maxV - minV), 0, 1)
        fill.Size = UDim2.new(ratio, 0, 1, 0)
        valText.Text = tostring(val)
    end
    function obj.Destroy() container:Destroy() end
    return obj
end

-- Bind (keybind) simple impl
local function buildBind(parent, labelText, defaultKey, callback)
    local container = Instance.new("Frame", parent)
    container.Size = UDim2.new(0, 200, 0, 28)
    container.BackgroundTransparency = 1
    local lbl = newTextLabel(container, {Size = UDim2.new(0.6, 0, 1, 0), Position = UDim2.new(0,4,0,0), Text = labelText})
    local keyBtn = newButton(container, {Size = UDim2.new(0.36, -8, 1, 0), Position = UDim2.new(0.64, 4, 0,0), Text = tostring(defaultKey or "C")})
    local boundKey = defaultKey or "C"
    local UserInputService = game:GetService("UserInputService")
    keyBtn.MouseButton1Click:Connect(function()
        keyBtn.Text = "Press key..."
        local conn
        conn = UserInputService.InputBegan:Connect(function(input, gpe)
            if not gpe and input.KeyCode then
                boundKey = tostring(input.KeyCode):gsub("Enum.KeyCode.", "")
                keyBtn.Text = boundKey
                if type(callback) == "function" then pcall(callback, boundKey) end
                conn:Disconnect()
            end
        end)
    end)
    return {
        Set = function(k) boundKey = k; keyBtn.Text = tostring(k) end,
        Get = function() return boundKey end,
        Destroy = function() container:Destroy() end
    }
end

-- Color picker stub (returns color but UI simplified)
local function buildColorPicker(parent, labelText, default, callback)
    local container = Instance.new("Frame", parent)
    container.Size = UDim2.new(0, 200, 0, 28)
    container.BackgroundTransparency = 1
    local lbl = newTextLabel(container, {Size = UDim2.new(0.6,0,1,0), Position = UDim2.new(0,4,0,0), Text = labelText})
    local btn = newButton(container, {Size = UDim2.new(0.36,-8,1,0), Position = UDim2.new(0.64,4,0,0), Text = "Pick"})
    btn.MouseButton1Click:Connect(function()
        -- rudimentary: toggle between white/black/custom
        local col = Color3.fromRGB(255,255,255)
        if default then col = default else col = Color3.fromRGB(255,255,255) end
        if type(callback) == "function" then pcall(callback, col) end
    end)
    return {
        Set = function(c) default = c end,
        Destroy = function() container:Destroy() end
    }
end

-- Box (input) simple
local function buildBox(parent, labelText, kind, callback)
    local container = Instance.new("Frame", parent)
    container.Size = UDim2.new(0, 220, 0, 28)
    container.BackgroundTransparency = 1
    local lbl = newTextLabel(container, {Size = UDim2.new(0.3,0,1,0), Position = UDim2.new(0,4,0,0), Text = labelText})
    local box = Instance.new("TextBox", container)
    box.Size = UDim2.new(0.66, -8, 1, 0)
    box.Position = UDim2.new(0.34, 4, 0, 0)
    box.Text = ""
    box.ClearTextOnFocus = false
    box.Font = Enum.Font.SourceSans
    box.TextSize = 14
    addUICorner(box, 6)
    box.Changed:Connect(function()
        if type(callback) == "function" then pcall(callback, box.Text) end
    end)
    return {
        Set = function(v) box.Text = tostring(v) end,
        Get = function() return box.Text end,
        Destroy = function() container:Destroy() end
    }
end

-- Window & Folder construction
function Hates.CreateWindow(title)
    local parent = getScreenParent()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = ("HatesQOL_%s"):format(tostring(math.random(1000,9999)))
    screenGui.ResetOnSpawn = false
    screenGui.Parent = parent

    local frame = newFrame(screenGui, {Size = UDim2.new(0, 420, 0, 340), Position = UDim2.new(0, 8, 0, 40), BackgroundColor = Color3.fromRGB(24,24,24)})
    addUICorner(frame, 8)

    local titleLbl = newTextLabel(frame, {Size = UDim2.new(1, -16, 0, 28), Position = UDim2.new(0,8,0,6), Text = tostring(title or "HatesQOL"), Font = Enum.Font.SourceSansBold, TextSize = 18, TextColor = Color3.new(1,1,1), TextXAlignment = Enum.TextXAlignment.Left})

    local minBtn = Instance.new("TextButton", frame)
    minBtn.Size = UDim2.new(0, 32, 0, 24)
    minBtn.Position = UDim2.new(1, -40, 0, 6)
    minBtn.Text = "—"
    minBtn.Font = Enum.Font.SourceSansBold
    minBtn.TextSize = 18
    minBtn.BackgroundTransparency = 0.2
    minBtn.TextColor3 = Color3.new(1,1,1)
    addUICorner(minBtn, 6)

    -- content area (scrollable)
    local content = Instance.new("ScrollingFrame", frame)
    content.Size = UDim2.new(1, -20, 1, -48)
    content.Position = UDim2.new(0, 10, 0, 44)
    content.BackgroundTransparency = 1
    content.ScrollBarThickness = 6
    content.CanvasSize = UDim2.new(0, 0, 0, 0)
    local uiLayout = Instance.new("UIListLayout", content)
    uiLayout.Padding = UDim.new(0, 8)
    uiLayout.SortOrder = Enum.SortOrder.LayoutOrder

    -- mini icon (visible when minimized)
    local icon = Instance.new("TextButton", screenGui)
    icon.Name = "HatesQOL_MinIcon"
    icon.Size = UDim2.new(0, 96, 0, 32)
    icon.Position = UDim2.new(0, frame.AbsolutePosition.X + frame.AbsoluteSize.X - 120, 0, frame.AbsolutePosition.Y)
    icon.AnchorPoint = Vector2.new(0,0)
    icon.Text = "Hate's QoL"
    icon.Font = Enum.Font.SourceSansBold
    icon.TextSize = 14
    icon.BackgroundColor3 = Color3.fromRGB(28,28,28)
    icon.TextColor3 = Color3.new(1,1,1)
    icon.Visible = false
    addUICorner(icon, 8)

    -- show/hide behavior
    minBtn.MouseButton1Click:Connect(function()
        frame.Visible = false
        icon.Visible = true
        -- place icon near previous pos
        local pos = frame.AbsolutePosition
        icon.Position = UDim2.new(0, pos.X + frame.AbsoluteSize.X - 120, 0, pos.Y)
    end)
    icon.MouseButton1Click:Connect(function()
        frame.Visible = true
        icon.Visible = false
    end)

    -- make draggable
    pcall(function()
        makeDraggable(frame)
    end)

    local windowObj = {
        ScreenGui = screenGui,
        Frame = frame,
        Content = content,
        TitleLabel = titleLbl,
        Icon = icon
    }

    -- Folder factory
    function windowObj:CreateFolder(name)
        local folderFrame = Instance.new("Frame", content)
        folderFrame.Size = UDim2.new(1, 0, 0, 36)
        folderFrame.BackgroundTransparency = 0
        folderFrame.BackgroundColor3 = Color3.fromRGB(28,28,28)
        folderFrame.BorderSizePixel = 0
        addUICorner(folderFrame, 6)
        folderFrame.LayoutOrder = 10

        local header = newTextLabel(folderFrame, {Size = UDim2.new(1, -8, 0, 28), Position = UDim2.new(0, 8, 0, 4), Text = tostring(name), Font = Enum.Font.SourceSansBold, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left})
        header.Parent = folderFrame

        -- internal content holder
        local inner = Instance.new("Frame", folderFrame)
        inner.Size = UDim2.new(1, -12, 0, 6)
        inner.Position = UDim2.new(0, 6, 0, 36)
        inner.BackgroundTransparency = 1
        inner.LayoutOrder = 11

        local folder = {}
        -- add Label
        function folder:Label(text, options)
            options = options or {}
            local lab = buildLabel(folderFrame, text or "", options)
            -- place under folder content
            lab._instance = lab
            lab._parent = folderFrame
            lab._obj = lab
            -- put it in content by reparenting to content and adjusting layout order
            lab.Update = lab.Update
            -- add direct parented label to content
            lab._instance = nil -- not needed
            -- actually create a visual label inside folderFrame
            local labelGui = Instance.new("TextLabel", folderFrame)
            labelGui.Size = UDim2.new(1, -16, 0, 18)
            labelGui.Position = UDim2.new(0, 8, 0, 36 + (#folderFrame:GetChildren()*0))
            labelGui.BackgroundTransparency = 1
            labelGui.Font = Enum.Font.SourceSans
            labelGui.TextSize = options.TextSize or 14
            labelGui.TextColor3 = options.TextColor or Color3.new(1,1,1)
            labelGui.Text = text or ""
            labelGui.TextWrapped = true

            local obj = {}
            function obj.Update(t) labelGui.Text = tostring(t or "") end
            function obj.Destroy() labelGui:Destroy() end
            return obj
        end

        -- add Button
        function folder:Button(text, cb, options)
            local opts = options or {}
            local b = newButton(folderFrame, {Size = opts.Size or UDim2.new(0, 120, 0, 28), Position = opts.Position or nil, Text = text or "Button", BackgroundColor = opts.BackgroundColor})
            -- reparent to folderFrame so layout keeps
            b.Parent = folderFrame
            b.LayoutOrder = 20
            local obj = {}
            b.MouseButton1Click:Connect(function()
                if type(cb) == "function" then pcall(cb) end
            end)
            function obj.SetText(s) if b and b.Parent then b.Text = tostring(s or "") end end
            function obj.Destroy() if b and b.Parent then b:Destroy() end end
            return obj
        end

        -- add Dropdown
        function folder:Dropdown(label, items, multi, cb)
            local dd = buildDropdown(folderFrame, 200, 8, 64, label, items or {}, cb)
            -- ensure parent is folderFrame
            dd.Button.Parent = folderFrame
            dd.Label.Parent = folderFrame
            dd.Menu.Parent = folderFrame
            dd.Button.LayoutOrder = 30
            local obj = dd
            return obj
        end

        -- add Toggle
        function folder:Toggle(label, cb, default)
            local t = buildToggle(folderFrame, label, default, cb)
            tFrame = t -- reference
            -- move into folder frame
            return t
        end

        -- add Slider
        function folder:Slider(label, params, cb)
            local s = buildSlider(folderFrame, label, params.min or 0, params.max or 100, params.precise or false, cb)
            return s
        end

        -- add Bind
        function folder:Bind(label, default, cb)
            return buildBind(folderFrame, label, default, cb)
        end

        -- add ColorPicker
        function folder:ColorPicker(label, default, cb)
            return buildColorPicker(folderFrame, label, default, cb)
        end

        -- add Box
        function folder:Box(label, kind, cb)
            return buildBox(folderFrame, label, kind, cb)
        end

        -- Destroy folder
        function folder:Destroy()
            folderFrame:Destroy()
        end

        return folder
    end

    function windowObj:Destroy()
        if screenGui and screenGui.Parent then screenGui:Destroy() end
    end

    -- convenience top-level functions on window
    function windowObj:SetTitle(t)
        if titleLbl then titleLbl.Text = tostring(t) end
    end

    return windowObj
end

-- Expose Hates as library
return Hates
