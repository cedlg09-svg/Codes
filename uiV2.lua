-- Load Fluent UI
local success, Fluent = pcall(function()
    return loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
end)
if not success or not Fluent then warn("Fluent failed to load") return end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()

-- ==== CONFIG ====
local WorldsTable = {
    Spawn = {"Shop","Town","Forest","Beach","Mine"},
    Fantasy = {"Fantasy Shop","Enchanted Forest","Portals"},
    Tech = {"Tech Shop","Tech City","Alien Lab"}
}
local TargetTypeOptions = {"Any","Coins","Diamonds","Chests","Breakables"}

-- ==== STATE ====
local Enabled = false
local SlowMode = false
local Mode = "None"
local SelectedWorld, SelectedArea = "Spawn", WorldsTable["Spawn"][1]
local TargetType = "Any"

-- ==== REMOTES ====
local Network = ReplicatedStorage:FindFirstChild("Network")

local function CallRemote(name,argsTable)
    argsTable = argsTable or {}
    if not Network then return false end
    local r = Network:FindFirstChild(name)
    if not r then return false end
    if r.ClassName == "RemoteFunction" then
        local ok,res = pcall(function() return r:InvokeServer(table.unpack(argsTable)) end)
        return ok,res
    elseif r.ClassName == "RemoteEvent" then
        local ok,res = pcall(function() r:FireServer(table.unpack(argsTable)) end)
        return ok,res
    end
    return false
end

local function GetCoinsRaw()
    local ok,res = CallRemote("Get Coins")
    return ok and res or {}
end

local function EquipPet(uid) CallRemote("Equip Pet",{uid}) end

-- ==== FLUENT UI ====
local Window = Fluent:CreateWindow({
    Title = "HateAF Fluent UI",
    SubTitle = "Autofarm V2",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 500),
    Acrylic = false,
    Theme = "Dark"
})

local Tabs = {
    Main = Window:AddTab({Title="Main"}),
    Eggs = Window:AddTab({Title="Egg Management"}),
    Upgrades = Window:AddTab({Title="Upgrades"})
}

-- ==== MAIN TAB ====
local StatusParagraph = Tabs.Main:AddParagraph({
    Title = "Status",
    Content = "Mode: "..Mode.." | World: "..SelectedWorld.." | Area: "..SelectedArea.." | Enabled: "..tostring(Enabled)
})

-- Mode toggles
local ToggleNormal = Tabs.Main:AddToggle("Normal", {Title="Normal Farm", Default=false})
local ToggleSafe = Tabs.Main:AddToggle("Safe", {Title="Safe Farm", Default=false})
local ToggleBlatant = Tabs.Main:AddToggle("Blatant", {Title="Blatant Farm", Default=false})
local ToggleSlow = Tabs.Main:AddToggle("Slow Mode", {Title="Slow Mode", Default=false})

ToggleNormal:OnChanged(function(val)
    if val then Mode = "Normal" ToggleSafe:SetValue(false) ToggleBlatant:SetValue(false) end
end)
ToggleSafe:OnChanged(function(val)
    if val then Mode = "Safe" ToggleNormal:SetValue(false) ToggleBlatant:SetValue(false) end
end)
ToggleBlatant:OnChanged(function(val)
    if val then Mode = "Blatant" ToggleNormal:SetValue(false) ToggleSafe:SetValue(false) end
end)
ToggleSlow:OnChanged(function(val) SlowMode = val end)

-- Dropdowns
local WorldDD = Tabs.Main:AddDropdown("World",{Title="World", Values={"Spawn","Fantasy","Tech"}, Multi=false, Default="Spawn"})
local AreaDD = Tabs.Main:AddDropdown("Area",{Title="Area", Values=WorldsTable["Spawn"], Multi=false, Default=WorldsTable["Spawn"][1]})
local TargetDD = Tabs.Main:AddDropdown("TargetType",{Title="Target Type", Values=TargetTypeOptions, Multi=false, Default="Any"})

WorldDD:OnChanged(function(val)
    SelectedWorld = val
    local areas = WorldsTable[val] or {}
    AreaDD:SetValues(areas)
    AreaDD:SetValue(areas[1])
    SelectedArea = areas[1]
end)

AreaDD:OnChanged(function(val)
    SelectedArea = val
end)

TargetDD:OnChanged(function(val)
    TargetType = val
end)

Tabs.Main:AddButton({
    Title="Refresh Areas",
    Callback=function()
        local areas = WorldsTable[SelectedWorld] or {}
        AreaDD:SetValues(areas)
        AreaDD:SetValue(areas[1])
        SelectedArea = areas[1]
        StatusParagraph:SetContent("Areas refreshed: "..SelectedArea)
    end
})

Tabs.Main:AddButton({
    Title="Start / Stop Farm",
    Callback=function()
        Enabled = not Enabled
        StatusParagraph:SetContent("Farming Enabled: "..tostring(Enabled))
    end
})

-- ==== EGGS TAB ====
Tabs.Eggs:AddParagraph({Title="Egg Management", Content="Egg window placeholder"})
Tabs.Eggs:AddButton({Title="Disable Egg Animation", Callback=function()
    print("Egg animation disabled")
end})

-- ==== UPGRADES TAB ====
Tabs.Upgrades:AddParagraph({Title="Auto Upgrades", Content="Placeholder labels for auto upgrades"})
Tabs.Upgrades:AddButton({Title="Auto Fuse", Callback=function() print("Auto Fuse triggered") end})
Tabs.Upgrades:AddButton({Title="Auto Gold", Callback=function() print("Auto Gold triggered") end})
Tabs.Upgrades:AddButton({Title="Auto Rainbow", Callback=function() print("Auto Rainbow triggered") end})
Tabs.Upgrades:AddButton({Title="Auto Dark Matter", Callback=function() print("Auto Dark Matter triggered") end})

-- ==== FLOATING SHOW/HIDE BUTTON ====
local floatBtn = Instance.new("TextButton", LocalPlayer:WaitForChild("PlayerGui"))
floatBtn.Size = UDim2.fromOffset(50,50)
floatBtn.Position = UDim2.new(0.5,-25,0,10)
floatBtn.Text = "UI"
floatBtn.BackgroundColor3 = Color3.fromRGB(30,30,30)
floatBtn.TextColor3 = Color3.new(1,1,1)
floatBtn.ZIndex = 9999
floatBtn.AutoButtonColor = true

floatBtn.MouseButton1Click:Connect(function()
    Window.Visible = not Window.Visible
end)

-- ==== FARM LOOP ====
task.spawn(function()
    while true do
        if Enabled then
            local coins = GetCoinsRaw()
            if coins then
                for id,data in pairs(coins) do
                    if data.a == SelectedArea and (TargetType=="Any" or string.find(data.n:lower(),TargetType:lower())) then
                        -- Example: simulate joining coin
                        print("Farming:", id, data.n)
                    end
                end
            end
        end
        StatusParagraph:SetContent("Mode: "..Mode.." | World: "..SelectedWorld.." | Area: "..SelectedArea.." | Enabled: "..tostring(Enabled))
        task.wait(SlowMode and 1.6 or 1)
    end
end)

Fluent:Notify({Title="HateAF", Content="UI and Autofarm Loaded", Duration=5})
