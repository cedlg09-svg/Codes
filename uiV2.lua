-- Safe Fluent + Farming UI
local success, Fluent = pcall(function()
    return loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
end)
if not success or not Fluent then warn("Fluent failed to load") return end

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()
local Workspace = game:GetService("Workspace")

-- Farming helpers
local Enabled = false
local SelectedWorld, SelectedArea = "Spawn", "Spawn"
local TargetType = "Any"
local WorldsTable = {
    Spawn = {"Shop","Town","Forest"},
    Fantasy = {"Fantasy Shop","Enchanted Forest"}
}
local TargetTypeOptions = {"Any","Coins","Diamonds","Chests"}

local function GetCoinsRaw()
    local Network = ReplicatedStorage:FindFirstChild("Network")
    if not Network then return {} end
    local ok,res = pcall(function()
        local r = Network:FindFirstChild("Get Coins")
        if r then return r:InvokeServer() end
        return {}
    end)
    return ok and res or {}
end

-- ==== UI ====
local Window = Fluent:CreateWindow({
    Title = "HateAF Fluent UI",
    SubTitle = "Autofarm Test",
    TabWidth = 160,
    Size = UDim2.new(0,500,0,450),
    Acrylic = false,
    Theme = "Dark"
})

local Tabs = {
    Main = Window:AddTab({ Title = "Main" }),
    Eggs = Window:AddTab({ Title = "Egg Management" })
}

-- Main Tab
Tabs.Main:AddParagraph({
    Title = "Status",
    Content = "Autofarm inactive"
})

-- Mode Toggles
local ToggleNormal = Tabs.Main:AddToggle("Normal", {Title="Normal Farm", Default=false})
local ToggleSafe = Tabs.Main:AddToggle("Safe", {Title="Safe Farm", Default=false})

-- Dropdowns
local WorldDD = Tabs.Main:AddDropdown("World", {Title="World", Values={"Spawn","Fantasy"}, Multi=false, Default="Spawn"})
local AreaDD = Tabs.Main:AddDropdown("Area", {Title="Area", Values=WorldsTable["Spawn"], Multi=false, Default="Shop"})
local TargetDD = Tabs.Main:AddDropdown("TargetType", {Title="Target", Values=TargetTypeOptions, Multi=false, Default="Any"})

WorldDD:OnChanged(function(val)
    SelectedWorld = val
    AreaDD:SetValues(WorldsTable[val] or {})
    AreaDD:SetValue(WorldsTable[val][1] or "")
end)

AreaDD:OnChanged(function(val)
    SelectedArea = val
end)

TargetDD:OnChanged(function(val)
    TargetType = val
end)

Tabs.Main:AddButton({
    Title = "Refresh Areas",
    Callback = function()
        AreaDD:SetValues(WorldsTable[SelectedWorld] or {})
        AreaDD:SetValue(WorldsTable[SelectedWorld][1] or "")
    end
})

Tabs.Main:AddButton({
    Title = "Start/Stop Farm",
    Callback = function()
        Enabled = not Enabled
        print("Farming Enabled:", Enabled)
    end
})

-- Egg Tab
Tabs.Eggs:AddParagraph({Title="Egg Management", Content="Egg UI placeholder"})
Tabs.Eggs:AddButton({Title="Disable Egg Animation", Callback=function()
    print("Egg animation disabled")
end})

-- ==== FARM LOOP ====
task.spawn(function()
    while true do
        if Enabled then
            local coins = GetCoinsRaw()
            if coins then
                -- Example: target all coins in selected area
                for id,data in pairs(coins) do
                    if data.a == SelectedArea and (TargetType=="Any" or data.n:find(TargetType)) then
                        -- Simulate joining coin
                        print("Farming coin:", id, data.n)
                    end
                end
            end
        end
        task.wait(1)
    end
end)

Fluent:Notify({Title="HateAF", Content="UI & Farm Loaded", Duration=5})
