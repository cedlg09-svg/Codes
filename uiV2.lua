-- HatesQOL wrapper loader
-- Loads Rayfield (official) then augments it with Refresh/Update and renames to HatesQOL.
-- Paste into a NEW LocalScript and run in Delta.

local ok, err = pcall(function()

    local RAY_URL = "https://raw.githubusercontent.com/SiriusSoftwareLtd/Rayfield/main/source.lua"
    -- load Rayfield
    local okLib, Ray = pcall(function() return loadstring(game:HttpGet(RAY_URL, true))() end)
    if not okLib or type(Ray) ~= "table" then
        error("Failed to load Rayfield from: "..tostring(RAY_URL).." -- "..tostring(Ray))
    end

    -- Create HatesQOL proxy object that defaults to Ray's methods when not overridden
    local HatesQOL = {}
    setmetatable(HatesQOL, { __index = Ray })

    -- Helper: safely attach Update to label-like API objects
    local function attachLabelUpdate(lblApi)
        if not lblApi then return end
        -- if Rayfield label has :Update already, leave it
        if type(lblApi.Update) == "function" then return end
        -- many Rayfield label objects expose a raw frame (Raw or Label or something). Try a few heuristics:
        local raw = nil
        if type(lblApi.Raw) == "function" then
            pcall(function() raw = lblApi:Raw() end)
        end
        if not raw and lblApi._object then raw = lblApi._object end -- some libs use internal name
        if not raw and lblApi.Label then raw = lblApi.Label end
        -- fallback: if the API itself behaves as a TextLabel
        if not raw and typeof(lblApi) == "Instance" and lblApi:IsA("TextLabel") then raw = lblApi end

        if raw and raw:IsA("TextLabel") then
            lblApi.Update = function(_, txt)
                pcall(function() raw.Text = tostring(txt or "") end)
            end
        else
            -- fallback: try to set text property if exists
            lblApi.Update = function(_, txt)
                pcall(function()
                    if raw and raw.Text ~= nil then raw.Text = tostring(txt or "") end
                end)
            end
        end
    end

    -- Helper: attach Update to button-like API objects
    local function attachButtonUpdate(btnApi)
        if not btnApi then return end
        if type(btnApi.Update) == "function" then return end
        -- try heuristics like label
        local raw = nil
        if type(btnApi.Raw) == "function" then
            pcall(function() raw = btnApi:Raw() end)
        end
        if not raw and btnApi._object then raw = btnApi._object end
        if not raw and btnApi.Button then raw = btnApi.Button end
        if not raw and typeof(btnApi) == "Instance" and btnApi:IsA("TextButton") then raw = btnApi end

        if raw and raw:IsA("TextButton") or (raw and raw:IsA("TextLabel")) then
            btnApi.Update = function(_, txt)
                pcall(function() raw.Text = tostring(txt or "") end)
            end
        else
            btnApi.Update = function(_, txt) pcall(function() end) end
        end
    end

    -- Attach Refresh to dropdown-like objects (expects .Menu Frame and .Button TextButton)
    local function attachDropdownRefresh(dd)
        if not dd then return end
        if type(dd.Refresh) == "function" then return end
        -- Expect dd.Menu is a Frame containing option TextButtons, and dd.Button is the visible TextButton
        local menu = dd.Menu
        local btn = dd.Button
        local cb = dd.Callback
        if not menu or not btn then
            -- try to find using heuristics
            if dd.GetMenu and type(dd.GetMenu) == "function" then
                pcall(function() menu = dd:GetMenu() end)
            end
        end
        dd.Refresh = function(_, newItems, autoSelectFirst)
            newItems = type(newItems) == "table" and newItems or {}
            autoSelectFirst = (autoSelectFirst == nil) and true or not not autoSelectFirst
            -- clear old option buttons
            if menu and menu:GetChildren() then
                for _, c in ipairs(menu:GetChildren()) do
                    if c:IsA("TextButton") then
                        pcall(function() c:Destroy() end)
                    end
                end
            end
            -- create new option buttons
            for i, opt in ipairs(newItems) do
                local optBtn = Instance.new("TextButton")
                optBtn.Size = UDim2.new(1, -8, 0, 20)
                optBtn.Position = UDim2.new(0, 4, 0, 0)
                optBtn.BackgroundTransparency = 1
                optBtn.Font = Enum.Font.SourceSans
                optBtn.Text = tostring(opt)
                optBtn.TextSize = 14
                optBtn.TextColor3 = Color3.fromRGB(255,255,255)
                optBtn.AutoButtonColor = true
                optBtn.BorderSizePixel = 0
                optBtn.LayoutOrder = i
                optBtn.Parent = menu
                optBtn.MouseButton1Click:Connect(function()
                    if btn then
                        pcall(function() btn.Text = tostring(opt) end)
                    end
                    if type(cb) == "function" then
                        pcall(cb, opt)
                    end
                    menu.Visible = false
                end)
            end
            -- resize menu
            if menu then
                local count = math.max(1, #newItems)
                pcall(function() menu.Size = UDim2.new(menu.Size.X.Scale, menu.Size.X.Offset, 0, math.min(count * 24, 200)) end)
            end
            -- auto select first
            if autoSelectFirst and #newItems > 0 then
                if btn then pcall(function() btn.Text = tostring(newItems[1]) end) end
                if type(cb) == "function" then pcall(cb, newItems[1]) end
            end
            -- update dd.Items if present
            pcall(function() dd.Items = newItems end)
        end
    end

    -- Wrap CreateWindow to post-process Folder elements so we add helpers automatically
    HatesQOL.CreateWindow = function(...)
        local window = Ray.CreateWindow(...)
        if not window then return window end

        -- wrap CreateFolder if present
        if type(window.CreateFolder) == "function" then
            local origCreateFolder = window.CreateFolder
            window.CreateFolder = function(...)
                local folder = origCreateFolder(...)
                if not folder then return folder end

                -- patch folder:Label -> attach Update
                local origLabel = folder.Label
                folder.Label = function(text, opts)
                    local lbl = nil
                    if type(origLabel) == "function" then
                        lbl = origLabel(text, opts)
                    end
                    pcall(function() attachLabelUpdate(lbl) end)
                    return lbl
                end

                -- patch folder:Button -> attach Update
                local origButton = folder.Button
                folder.Button = function(text, cb, opts)
                    local b = nil
                    if type(origButton) == "function" then
                        b = origButton(text, cb, opts)
                    end
                    pcall(function() attachButtonUpdate(b) end)
                    return b
                end

                -- patch folder:Dropdown -> attach Refresh
                local origDropdown = folder.Dropdown
                folder.Dropdown = function(text, options, multi, cb)
                    local dd = nil
                    if type(origDropdown) == "function" then
                        dd = origDropdown(text, options or {}, multi, cb)
                    end
                    pcall(function()
                        -- store callback for wrapper use if not present
                        if dd and not dd.Callback and type(cb) == "function" then dd.Callback = cb end
                        attachDropdownRefresh(dd)
                        -- initial Items property
                        if dd and (not dd.Items) then dd.Items = options or {} end
                    end)
                    return dd
                end

                -- patch folder:Box just in case
                local origBox = folder.Box
                folder.Box = function(...)
                    local box = nil
                    if type(origBox) == "function" then box = origBox(...) end
                    return box
                end

                return folder
            end
        end

        return window
    end

    -- Also expose direct shorthand for compatibility
    HatesQOL.Version = Ray.Version or "HatesQOL-Proxy"
    HatesQOL.Original = Ray

    -- Expose in global (optional) for convenience
    _G.HatesQOL = HatesQOL

    -- Simple test: create a small window to verify Refresh & Update
    local test_ok, test_err = pcall(function()
        local w = HatesQOL.CreateWindow("Hate's QoL (proxy test)")
        local f = w:CreateFolder("Autofarm Test")

        local status = f:Label("Status: Idle")
        -- Ensure update works
        if status and type(status.Update) ~= "function" then
            attachLabelUpdate(status)
        end

        local pick = f:Button("Pick Best Pets", function()
            pcall(function() status:Update("Picking best pets...") end)
            task.delay(0.6, function() pcall(function() status:Update("Picked best (test)") end) end)
        end)
        if pick and type(pick.Update) ~= "function" then attachButtonUpdate(pick) end

        local worlds = {"Spawn","Tech","Fantasy"}
        local worldDD = f:Dropdown("World", worlds, false, function(v)
            pcall(function() status:Update("World -> "..tostring(v)) end)
            -- example: refresh areas
            local areas = {}
            if v == "Spawn" then areas = {"Town","Shop","Mine"} end
            if v == "Tech" then areas = {"Tech Shop","Tech City","Dark Tech"} end
            if v == "Fantasy" then areas = {"Fantasy Shop","Enchanted Forest"} end
            -- find the area dropdown created below (we keep reference worldAreaDD)
            pcall(function() if worldAreaDD and worldAreaDD.Refresh then worldAreaDD:Refresh(areas, true) end end)
        end)

        local worldAreaDD = f:Dropdown("Area", {"Town","Shop"}, false, function(a)
            pcall(function() status:Update("Area -> "..tostring(a)) end)
        end)

        -- test refresh after 2s
        task.delay(2, function()
            pcall(function()
                if worldAreaDD and worldAreaDD.Refresh then
                    worldAreaDD:Refresh({"A1","A2","A3"}, true)
                    status:Update("Area refreshed (auto-first)")
                end
            end)
        end)
    end)

    if not test_ok then warn("HatesQOL test ui error:", test_err) end

    print("[HatesQOL] Loaded wrapper (Rayfield augmented). Use `local HatesQOL = _G.HatesQOL` or return value.")
    return HatesQOL
end)

if not ok then
    warn("[HatesQOL loader] Startup error:", err)
else
    print("[HatesQOL loader] Successfully loaded and augmented Rayfield.")
end
