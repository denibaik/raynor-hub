--[[
    ╔══════════════════════════════════════════╗
    ║        🐣 RAYNOR HUB v1.0               ║
    ║     Naik Hewan Peliharaan  | raynorqt    ║
    ╚══════════════════════════════════════════╝
--]]

-- ⚡ Kill semua instance lama saat inject ulang
if _G.RaynorHubKill then _G.RaynorHubKill() end
local _alive = true
_G.RaynorHubKill = function() _alive = false end

local Players          = game:GetService("Players")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer      = Players.LocalPlayer
local RS               = game:GetService("ReplicatedStorage")
local BasketDropRE     = RS.Remotes.Game.BasketDrop
local Basket           = LocalPlayer:WaitForChild("Basket")

-- ============================================================
--  CONFIG
-- ============================================================
local EGG_OPTIONS = {
    { name = "Blackhole Egg", icon = "🌑", active = true },
    { name = "Solaris Egg",   icon = "☀️",  active = true },
    { name = "Volcanic Egg",  icon = "🌋", active = true },
    { name = "Cherub Egg",    icon = "👼", active = true },
    { name = "Galaxy Egg",    icon = "🌌", active = true },
    { name = "Bloom Egg",     icon = "🌸", active = true },
}

local DROP_OFFSET = Vector3.new(4, 0, 0)
local LOOP_DELAY  = 2.0
local HOLD_BUFFER = 0.5

-- ============================================================
--  STATE
-- ============================================================
local jokiEnabled  = false
local jokiTarget   = nil
local currentMode  = "self"   -- "self" | "joki"
local dropdownOpen = false
local busy         = false
local myPlotCenter = nil  -- cache posisi plot sendiri

-- ============================================================
--  HELPERS
-- ============================================================

-- Cari posisi tengah plot milik LocalPlayer
local function GetMyPlotCenter()
    if myPlotCenter then return myPlotCenter end
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return nil end

    local plotList = plots:GetChildren()

    for _, plot in ipairs(plotList) do
        local bp = plot:FindFirstChild("Baseplate")
        if bp then
            -- Prioritas 1: ObjectValue Data.Owner (paling akurat & tidak delay)
            local data = plot:FindFirstChild("Data")
            local ownerVal = data and data:FindFirstChild("Owner")
            if ownerVal and ownerVal.Value == LocalPlayer then
                myPlotCenter = bp.Position
                return myPlotCenter
            end
        end
    end

    -- Prioritas 2: fallback ke attribute (kalau ObjectValue belum ter-set)
    for _, plot in ipairs(plotList) do
        local bp = plot:FindFirstChild("Baseplate")
        if bp then
            local ownerAttr = plot:GetAttribute("NestsOwnerLoaded") or plot:GetAttribute("Owner")
            if tostring(ownerAttr) == tostring(LocalPlayer.UserId) then
                myPlotCenter = bp.Position
                return myPlotCenter
            end
        end
    end

    -- Prioritas 3: fallback kalau hanya ada 1 plot di map
    if #plotList == 1 then
        local bp = plotList[1]:FindFirstChild("Baseplate")
        if bp then
            myPlotCenter = bp.Position
            return myPlotCenter
        end
    end

    return nil
end


local function TeleportTo(pos)
    local hrp = LocalPlayer.Character
        and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if hrp then hrp.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0)) end
end

local function GetActiveEggs()
    local t = {}
    for _, e in ipairs(EGG_OPTIONS) do
        if e.active then t[e.name] = true end
    end
    return t
end

local function FindPickupableEgg()
    local whitelist = GetActiveEggs()
    local rendered  = workspace:FindFirstChild("RenderedEggs")
    if not rendered then return nil, nil, nil end

    for _, obj in pairs(rendered:GetChildren()) do
        if not whitelist[obj.Name] then continue end

        -- Cari PP di semua descendant (bukan hanya FindFirstChild)
        local bestPP, bestPos = nil, nil
        for _, d in pairs(obj:GetDescendants()) do
            if d:IsA("ProximityPrompt") and d.Enabled then
                local pos
                pcall(function()
                    -- Prioritas: parent BasePart → pivot model → child BasePart
                    if d.Parent:IsA("BasePart") then
                        pos = d.Parent.Position
                    else
                        pos = obj:GetPivot().Position
                    end
                end)
                if not pos then
                    pcall(function()
                        for _, part in pairs(obj:GetDescendants()) do
                            if part:IsA("BasePart") then
                                pos = part.Position
                                break
                            end
                        end
                    end)
                end
                if pos then
                    bestPP  = d
                    bestPos = pos
                    break
                end
            end
        end

        if bestPP and bestPos then
            return obj, bestPP, bestPos
        end
    end
    return nil, nil, nil
end


-- ============================================================
--  DESTROY OLD GUIs
-- ============================================================
for _, name in ipairs({"JokiEggGUI", "JokiEggMiniBtn", "RaynorHubGUI", "RaynorHubMini"}) do
    local old = LocalPlayer.PlayerGui:FindFirstChild(name)
    if old then old:Destroy() end
end

-- ============================================================
--  BUILD GUI — MAIN
-- ============================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name           = "RaynorHubGUI"
ScreenGui.ResetOnSpawn   = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent         = LocalPlayer.PlayerGui

-- Main Frame
local Main = Instance.new("Frame", ScreenGui)
Main.Name             = "Main"
Main.Size             = UDim2.new(0, 290, 0, 430)
Main.Position         = UDim2.new(0.5, -145, 0.5, -215)
Main.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
Main.BorderSizePixel  = 0
Main.Active           = true
Main.Draggable        = true
Instance.new("UICorner", Main).CornerRadius = UDim.new(0, 8)
local mainStroke = Instance.new("UIStroke", Main)
mainStroke.Color = Color3.fromRGB(255, 140, 0); mainStroke.Thickness = 1.5

-- ── Resize Handle (bottom-right corner) ───────────────────────
local MIN_SIZE = Vector2.new(260, 320)
local MAX_SIZE = Vector2.new(600, 800)

local ResizeHandle = Instance.new("TextButton", Main)
ResizeHandle.Name             = "ResizeHandle"
ResizeHandle.Size             = UDim2.new(0, 18, 0, 18)
ResizeHandle.Position         = UDim2.new(1, -18, 1, -18)
ResizeHandle.BackgroundColor3 = Color3.fromRGB(255, 140, 0)
ResizeHandle.BackgroundTransparency = 0.3
ResizeHandle.BorderSizePixel  = 0
ResizeHandle.Text             = "◢"
ResizeHandle.TextColor3       = Color3.new(1, 1, 1)
ResizeHandle.TextSize         = 12
ResizeHandle.Font             = Enum.Font.GothamBold
ResizeHandle.ZIndex           = 25
ResizeHandle.AutoButtonColor  = false
Instance.new("UICorner", ResizeHandle).CornerRadius = UDim.new(0, 4)

do
    local resizing = false
    local startPos, startSize

    ResizeHandle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            resizing  = true
            startPos  = input.Position
            startSize = Main.AbsoluteSize
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if not resizing then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement
            and input.UserInputType ~= Enum.UserInputType.Touch then return end

        local delta = input.Position - startPos
        local newW = math.clamp(startSize.X + delta.X, MIN_SIZE.X, MAX_SIZE.X)
        local newH = math.clamp(startSize.Y + delta.Y, MIN_SIZE.Y, MAX_SIZE.Y)
        Main.Size = UDim2.new(0, newW, 0, newH)
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            resizing = false
        end
    end)
end

-- ── Title Bar ────────────────────────────────────────────────
local TitleBar = Instance.new("Frame", Main)
TitleBar.Size             = UDim2.new(1, 0, 0, 40)
TitleBar.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
TitleBar.BorderSizePixel  = 0
Instance.new("UICorner", TitleBar).CornerRadius = UDim.new(0, 8)
local fix = Instance.new("Frame", TitleBar)
fix.Size = UDim2.new(1,0, 0.5,0); fix.Position = UDim2.new(0,0,0.5,0)
fix.BackgroundColor3 = Color3.fromRGB(25,25,30); fix.BorderSizePixel = 0

local TitleIcon = Instance.new("TextLabel", TitleBar)
TitleIcon.Size = UDim2.new(0,30,1,0); TitleIcon.Position = UDim2.new(0,8,0,0)
TitleIcon.BackgroundTransparency = 1; TitleIcon.Text = "🐣"
TitleIcon.TextSize = 18; TitleIcon.Font = Enum.Font.GothamBold

local TitleLabel = Instance.new("TextLabel", TitleBar)
TitleLabel.Size = UDim2.new(1,-80,1,0); TitleLabel.Position = UDim2.new(0,38,0,0)
TitleLabel.BackgroundTransparency = 1; TitleLabel.Text = "Raynor Hub"
TitleLabel.TextColor3 = Color3.new(1,1,1); TitleLabel.TextSize = 14
TitleLabel.Font = Enum.Font.GothamBold; TitleLabel.TextXAlignment = Enum.TextXAlignment.Left

local SubLabel = Instance.new("TextLabel", TitleBar)
SubLabel.Size = UDim2.new(1,-80,0,14); SubLabel.Position = UDim2.new(0,38,0,23)
SubLabel.BackgroundTransparency = 1; SubLabel.Text = "Auto Egg Hunter"
SubLabel.TextColor3 = Color3.fromRGB(140,140,160); SubLabel.TextSize = 10
SubLabel.Font = Enum.Font.Gotham; SubLabel.TextXAlignment = Enum.TextXAlignment.Left

-- Minimize button
local MinBtn = Instance.new("TextButton", TitleBar)
MinBtn.Size = UDim2.new(0,26,0,26); MinBtn.Position = UDim2.new(1,-62,0,7)
MinBtn.BackgroundColor3 = Color3.fromRGB(50,120,200); MinBtn.BorderSizePixel = 0
MinBtn.Text = "–"; MinBtn.TextColor3 = Color3.new(1,1,1)
MinBtn.TextSize = 14; MinBtn.Font = Enum.Font.GothamBold
Instance.new("UICorner", MinBtn).CornerRadius = UDim.new(0,6)

-- Close button
local CloseBtn = Instance.new("TextButton", TitleBar)
CloseBtn.Size = UDim2.new(0,26,0,26); CloseBtn.Position = UDim2.new(1,-32,0,7)
CloseBtn.BackgroundColor3 = Color3.fromRGB(200,50,50); CloseBtn.BorderSizePixel = 0
CloseBtn.Text = "✕"; CloseBtn.TextColor3 = Color3.new(1,1,1)
CloseBtn.TextSize = 12; CloseBtn.Font = Enum.Font.GothamBold
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0,6)
CloseBtn.MouseButton1Click:Connect(function()
    -- ⚠️ Matikan loop auto SEBELUM destroy GUI, kalau tidak RunAuto tetap
    -- jalan di background tanpa GUI (zombie thread).
    jokiEnabled = false
    busy = false
    _G.RaynorHubKill()
    ScreenGui:Destroy()
    local mg = LocalPlayer.PlayerGui:FindFirstChild("RaynorHubMini")
    if mg then mg:Destroy() end
end)

-- ── Floating Mini Button — ScreenGui terpisah ────────────────
local MiniGui = Instance.new("ScreenGui")
MiniGui.Name           = "RaynorHubMini"
MiniGui.ResetOnSpawn   = false
MiniGui.DisplayOrder   = 999
MiniGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
MiniGui.Enabled        = false
MiniGui.Parent         = LocalPlayer.PlayerGui

local MiniBtn = Instance.new("TextButton", MiniGui)
MiniBtn.Size             = UDim2.new(0, 54, 0, 54)
MiniBtn.Position         = UDim2.new(0, 12, 0.5, -27)
MiniBtn.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
MiniBtn.BorderSizePixel  = 0
MiniBtn.Text             = "🐣"
MiniBtn.TextSize         = 26
MiniBtn.Font             = Enum.Font.GothamBold
MiniBtn.Active           = true
MiniBtn.Draggable        = true
Instance.new("UICorner", MiniBtn).CornerRadius = UDim.new(1, 0)
local miniStroke = Instance.new("UIStroke", MiniBtn)
miniStroke.Color = Color3.fromRGB(255,140,0); miniStroke.Thickness = 2.5

local function SetMinimized(state)
    Main.Visible    = not state
    MiniGui.Enabled = state
end
-- 🔵 Tombol – (minimize): sembunyikan GUI utama, tampilkan floating button
MinBtn.MouseButton1Click:Connect(function() SetMinimized(true) end)
-- 🐣 Floating button: tampilkan kembali GUI utama
MiniBtn.MouseButton1Click:Connect(function() SetMinimized(false) end)

-- ── Scrollable Content ────────────────────────────────────────
local ScrollFrame = Instance.new("ScrollingFrame", Main)
ScrollFrame.Size               = UDim2.new(1,-16,1,-50)
ScrollFrame.Position           = UDim2.new(0,8,0,46)
ScrollFrame.BackgroundTransparency = 1
ScrollFrame.BorderSizePixel    = 0
ScrollFrame.ScrollBarThickness = 3
ScrollFrame.ScrollBarImageColor3 = Color3.fromRGB(255,140,0)
ScrollFrame.CanvasSize         = UDim2.new(0,0,0,0)
ScrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
ScrollFrame.ClipsDescendants   = true

local ContentLayout = Instance.new("UIListLayout", ScrollFrame)
ContentLayout.SortOrder = Enum.SortOrder.LayoutOrder
ContentLayout.Padding   = UDim.new(0,6)
Instance.new("UIPadding", ScrollFrame).PaddingTop = UDim.new(0,4)

local function MakeSection(text, order)
    local l = Instance.new("TextLabel", ScrollFrame)
    l.Size = UDim2.new(1,0,0,16); l.BackgroundTransparency = 1
    l.Text = text; l.TextColor3 = Color3.fromRGB(255,140,0)
    l.TextSize = 11; l.Font = Enum.Font.GothamBold
    l.TextXAlignment = Enum.TextXAlignment.Left; l.LayoutOrder = order
    return l
end

local function MakeDivider(order)
    local f = Instance.new("Frame", ScrollFrame)
    f.Size = UDim2.new(1,0,0,1)
    f.BackgroundColor3 = Color3.fromRGB(45,45,60)
    f.BorderSizePixel = 0; f.LayoutOrder = order
end

-- =============================================================
--  SECTION 0: MODE SELECTOR
-- =============================================================
MakeSection("Mode", 0)

local ModeRow = Instance.new("Frame", ScrollFrame)
ModeRow.Size = UDim2.new(1,0,0,36)
ModeRow.BackgroundTransparency = 1
ModeRow.LayoutOrder = 1

local modeLayout = Instance.new("UIListLayout", ModeRow)
modeLayout.FillDirection = Enum.FillDirection.Horizontal
modeLayout.Padding = UDim.new(0, 6)

-- Mode button styling
local modeBtns = {}
local function MakeModeBtn(text, icon, modeKey, order)
    local btn = Instance.new("TextButton", ModeRow)
    btn.Size = UDim2.new(0.5, -3, 1, 0)
    btn.BackgroundColor3 = modeKey == currentMode
        and Color3.fromRGB(255,140,0)
        or  Color3.fromRGB(30,30,42)
    btn.Text = icon.."  "..text
    btn.TextColor3 = modeKey == currentMode
        and Color3.new(1,1,1)
        or  Color3.fromRGB(160,160,180)
    btn.TextSize = 12; btn.Font = Enum.Font.GothamBold
    btn.BorderSizePixel = 0
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0,6)
    modeBtns[modeKey] = btn
    return btn
end

local SelfBtn = MakeModeBtn("Self",  "👤", "self", 0)
local JokiBtn = MakeModeBtn("Joki",  "🚚", "joki", 1)

-- PlayerSection reference (need forward declaration)
local PlayerSection, TargetRow, RefreshBtn

local function SetMode(mode)
    currentMode = mode
    -- Update button styles
    for key, btn in pairs(modeBtns) do
        if key == mode then
            btn.BackgroundColor3 = Color3.fromRGB(255,140,0)
            btn.TextColor3       = Color3.new(1,1,1)
        else
            btn.BackgroundColor3 = Color3.fromRGB(30,30,42)
            btn.TextColor3       = Color3.fromRGB(160,160,180)
        end
    end
    -- Tampilkan / sembunyikan Select Player section
    if PlayerSection then
        PlayerSection.Visible = (mode == "joki")
        TargetRow.Visible     = (mode == "joki")
        RefreshBtn.Visible    = (mode == "joki")
    end
end

SelfBtn.MouseButton1Click:Connect(function() SetMode("self") end)
JokiBtn.MouseButton1Click:Connect(function() SetMode("joki") end)

MakeDivider(2)

-- =============================================================
--  SECTION 1: SELECT PLAYER  (hanya untuk mode Joki)
-- =============================================================
PlayerSection = MakeSection("Select Player", 3)

-- Target row
TargetRow = Instance.new("Frame", ScrollFrame)
TargetRow.Size = UDim2.new(1,0,0,32)
TargetRow.BackgroundTransparency = 1
TargetRow.LayoutOrder = 4

local TargetLbl = Instance.new("TextLabel", TargetRow)
TargetLbl.Size = UDim2.new(0,95,1,0); TargetLbl.BackgroundTransparency = 1
TargetLbl.Text = "Target Player"; TargetLbl.TextColor3 = Color3.fromRGB(180,180,200)
TargetLbl.TextSize = 12; TargetLbl.Font = Enum.Font.Gotham
TargetLbl.TextXAlignment = Enum.TextXAlignment.Left

local DropBtn = Instance.new("TextButton", TargetRow)
DropBtn.Size = UDim2.new(0,176,1,0); DropBtn.Position = UDim2.new(0,98,0,0)
DropBtn.BackgroundColor3 = Color3.fromRGB(30,30,40)
DropBtn.Text = "Select Option  ▾"; DropBtn.TextColor3 = Color3.fromRGB(160,160,180)
DropBtn.TextSize = 11; DropBtn.Font = Enum.Font.Gotham; DropBtn.BorderSizePixel = 0
Instance.new("UICorner", DropBtn).CornerRadius = UDim.new(0,6)
local dropStroke = Instance.new("UIStroke", DropBtn)
dropStroke.Color = Color3.fromRGB(60,60,80); dropStroke.Thickness = 1

-- Dropdown list (floating)
local DropList = Instance.new("Frame", Main)
DropList.Size = UDim2.new(0,176,0,0); DropList.Position = UDim2.new(0,110,0,148)
DropList.BackgroundColor3 = Color3.fromRGB(22,22,32); DropList.BorderSizePixel = 0
DropList.ClipsDescendants = true; DropList.ZIndex = 20
Instance.new("UICorner", DropList).CornerRadius = UDim.new(0,6)
local dlStroke = Instance.new("UIStroke", DropList)
dlStroke.Color = Color3.fromRGB(255,140,0); dlStroke.Thickness = 1; dlStroke.ZIndex = 21
local DLL = Instance.new("UIListLayout", DropList); DLL.SortOrder = Enum.SortOrder.LayoutOrder

local function PopulateDropdown()
    for _, c in pairs(DropList:GetChildren()) do
        if not c:IsA("UIListLayout") then c:Destroy() end
    end
    local others = {}
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then table.insert(others, p) end
    end
    if #others == 0 then
        local n = Instance.new("TextLabel", DropList)
        n.Size = UDim2.new(1,0,0,30); n.BackgroundTransparency = 1
        n.Text = "  (Tidak ada player)"; n.TextColor3 = Color3.fromRGB(120,120,140)
        n.TextSize = 11; n.Font = Enum.Font.Gotham
        n.TextXAlignment = Enum.TextXAlignment.Left
        return
    end
    for _, p in ipairs(others) do
        local item = Instance.new("TextButton", DropList)
        item.Size = UDim2.new(1,0,0,30)
        item.BackgroundColor3 = Color3.fromRGB(22,22,32)
        item.Text = "  "..p.Name; item.TextColor3 = Color3.fromRGB(220,220,240)
        item.TextSize = 11; item.Font = Enum.Font.Gotham
        item.TextXAlignment = Enum.TextXAlignment.Left
        item.BorderSizePixel = 0; item.ZIndex = 22
        item.MouseEnter:Connect(function() item.BackgroundColor3 = Color3.fromRGB(40,40,60) end)
        item.MouseLeave:Connect(function() item.BackgroundColor3 = Color3.fromRGB(22,22,32) end)
        item.MouseButton1Click:Connect(function()
            jokiTarget = p
            DropBtn.Text = p.Name.."  ▾"; DropBtn.TextColor3 = Color3.new(1,1,1)
            dropStroke.Color = Color3.fromRGB(255,140,0)
            TweenService:Create(DropList, TweenInfo.new(0.15), {Size=UDim2.new(0,176,0,0)}):Play()
            dropdownOpen = false
        end)
    end
end

DropBtn.MouseButton1Click:Connect(function()
    if not dropdownOpen then
        PopulateDropdown()
        local count = 0
        for _, c in pairs(DropList:GetChildren()) do
            if not c:IsA("UIListLayout") then count += 1 end
        end
        TweenService:Create(DropList, TweenInfo.new(0.15), {Size=UDim2.new(0,176,0,math.min(count*30,120))}):Play()
        dropdownOpen = true
    else
        TweenService:Create(DropList, TweenInfo.new(0.15), {Size=UDim2.new(0,176,0,0)}):Play()
        dropdownOpen = false
    end
end)

RefreshBtn = Instance.new("TextButton", ScrollFrame)
RefreshBtn.Size = UDim2.new(1,0,0,34); RefreshBtn.BackgroundColor3 = Color3.fromRGB(220,120,0)
RefreshBtn.Text = "🔄  Refresh Players"; RefreshBtn.TextColor3 = Color3.new(1,1,1)
RefreshBtn.TextSize = 12; RefreshBtn.Font = Enum.Font.GothamBold
RefreshBtn.BorderSizePixel = 0; RefreshBtn.LayoutOrder = 5
Instance.new("UICorner", RefreshBtn).CornerRadius = UDim.new(0,6)
RefreshBtn.MouseButton1Click:Connect(function()
    PopulateDropdown()
    RefreshBtn.BackgroundColor3 = Color3.fromRGB(255,165,0)
    task.wait(0.15); RefreshBtn.BackgroundColor3 = Color3.fromRGB(220,120,0)
end)

MakeDivider(6)

-- =============================================================
--  SECTION 2: SELECT EGGS
-- =============================================================
MakeSection("Select Eggs", 7)

-- All / None buttons
local QuickRow = Instance.new("Frame", ScrollFrame)
QuickRow.Size = UDim2.new(1,0,0,26); QuickRow.BackgroundTransparency = 1; QuickRow.LayoutOrder = 8
local qL = Instance.new("UIListLayout", QuickRow)
qL.FillDirection = Enum.FillDirection.Horizontal; qL.Padding = UDim.new(0,6)

local eggCheckboxes = {}

local function UpdateAllCheckboxes(state)
    for _, opt in ipairs(EGG_OPTIONS) do opt.active = state end
    for _, cb in pairs(eggCheckboxes) do
        cb.box.BackgroundColor3 = state and Color3.fromRGB(255,140,0) or Color3.fromRGB(30,30,40)
        cb.check.Visible = state
    end
end

for _, lbl in ipairs({"✅ All", "❌ None"}) do
    local btn = Instance.new("TextButton", QuickRow)
    btn.Size = UDim2.new(0,76,1,0); btn.BackgroundColor3 = Color3.fromRGB(35,35,48)
    btn.Text = lbl; btn.TextColor3 = Color3.fromRGB(200,200,220)
    btn.TextSize = 11; btn.Font = Enum.Font.GothamBold; btn.BorderSizePixel = 0
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0,5)
    btn.MouseButton1Click:Connect(function() UpdateAllCheckboxes(lbl == "✅ All") end)
end

-- Egg grid
local EggGrid = Instance.new("Frame", ScrollFrame)
EggGrid.Name = "EggGrid"; EggGrid.Size = UDim2.new(1,0,0,0)
EggGrid.AutomaticSize = Enum.AutomaticSize.Y
EggGrid.BackgroundTransparency = 1; EggGrid.LayoutOrder = 9

local gridLayout = Instance.new("UIGridLayout", EggGrid)
gridLayout.CellSize = UDim2.new(0.5,-4,0,34); gridLayout.CellPadding = UDim2.new(0,6,0,6)
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder; gridLayout.FillDirectionMaxCells = 2

for i, opt in ipairs(EGG_OPTIONS) do
    local cell = Instance.new("Frame", EggGrid)
    cell.BackgroundColor3 = Color3.fromRGB(26,26,36)
    cell.BorderSizePixel = 0; cell.LayoutOrder = i
    Instance.new("UICorner", cell).CornerRadius = UDim.new(0,6)

    local box = Instance.new("Frame", cell)
    box.Size = UDim2.new(0,18,0,18); box.Position = UDim2.new(0,8,0.5,-9)
    box.BackgroundColor3 = opt.active and Color3.fromRGB(255,140,0) or Color3.fromRGB(30,30,40)
    box.BorderSizePixel = 0
    Instance.new("UICorner", box).CornerRadius = UDim.new(0,4)
    local bs = Instance.new("UIStroke", box); bs.Color = Color3.fromRGB(80,80,100); bs.Thickness = 1

    local check = Instance.new("TextLabel", box)
    check.Size = UDim2.new(1,0,1,0); check.BackgroundTransparency = 1
    check.Text = "✓"; check.TextColor3 = Color3.new(1,1,1)
    check.TextSize = 12; check.Font = Enum.Font.GothamBold; check.Visible = opt.active

    local nameLbl = Instance.new("TextLabel", cell)
    nameLbl.Size = UDim2.new(1,-36,1,0); nameLbl.Position = UDim2.new(0,32,0,0)
    nameLbl.BackgroundTransparency = 1
    nameLbl.Text = opt.icon.." "..opt.name:gsub(" Egg","")
    nameLbl.TextColor3 = Color3.fromRGB(210,210,230)
    nameLbl.TextSize = 11; nameLbl.Font = Enum.Font.Gotham
    nameLbl.TextXAlignment = Enum.TextXAlignment.Left
    nameLbl.TextTruncate = Enum.TextTruncate.AtEnd

    local btn = Instance.new("TextButton", cell)
    btn.Size = UDim2.new(1,0,1,0); btn.BackgroundTransparency = 1
    btn.Text = ""; btn.BorderSizePixel = 0

    table.insert(eggCheckboxes, {box=box, check=check})

    btn.MouseButton1Click:Connect(function()
        opt.active = not opt.active
        box.BackgroundColor3 = opt.active and Color3.fromRGB(255,140,0) or Color3.fromRGB(30,30,40)
        check.Visible = opt.active
    end)
    btn.MouseEnter:Connect(function() cell.BackgroundColor3 = Color3.fromRGB(36,36,52) end)
    btn.MouseLeave:Connect(function() cell.BackgroundColor3 = Color3.fromRGB(26,26,36) end)
end

MakeDivider(10)

-- =============================================================
--  STATUS + TOGGLE
-- =============================================================
local StatusLbl = Instance.new("TextLabel", ScrollFrame)
StatusLbl.Size = UDim2.new(1,0,0,18); StatusLbl.BackgroundTransparency = 1
StatusLbl.Text = "⏸  Status: OFF"; StatusLbl.TextColor3 = Color3.fromRGB(140,140,160)
StatusLbl.TextSize = 11; StatusLbl.Font = Enum.Font.Gotham
StatusLbl.TextXAlignment = Enum.TextXAlignment.Left; StatusLbl.LayoutOrder = 11

local ToggleBtn = Instance.new("TextButton", ScrollFrame)
ToggleBtn.Size = UDim2.new(1,0,0,38); ToggleBtn.BackgroundColor3 = Color3.fromRGB(50,50,68)
ToggleBtn.Text = "▶  Start"; ToggleBtn.TextColor3 = Color3.fromRGB(200,200,220)
ToggleBtn.TextSize = 13; ToggleBtn.Font = Enum.Font.GothamBold
ToggleBtn.BorderSizePixel = 0; ToggleBtn.LayoutOrder = 12
Instance.new("UICorner", ToggleBtn).CornerRadius = UDim.new(0,6)

-- Bottom padding
local pad = Instance.new("Frame", ScrollFrame)
pad.Size = UDim2.new(1,0,0,4); pad.BackgroundTransparency = 1; pad.LayoutOrder = 99

-- Apply initial mode (default: self → hide player section)
SetMode("self")

-- ============================================================
--  JOKI LOGIC
-- ============================================================
local function SetStatus(text, color)
    StatusLbl.Text = text
    StatusLbl.TextColor3 = color or Color3.fromRGB(140,140,160)
end

local function RunAuto()
    while jokiEnabled and _alive do
        task.wait(LOOP_DELAY)
        if not jokiEnabled or not _alive then break end

        if busy then continue end

        -- Validasi egg tersedia
        if not next(GetActiveEggs()) then
            SetStatus("⚠  Pilih egg dulu!", Color3.fromRGB(255,180,0))
            continue
        end

        -- Validasi target (hanya joki mode)
        if currentMode == "joki" and (not jokiTarget or not jokiTarget.Parent) then
            SetStatus("⚠  Pilih target dulu!", Color3.fromRGB(255,180,0))
            continue
        end

        -- Kalau basket sudah ada isi
        if #Basket:GetChildren() > 0 then
            busy = true
            if currentMode == "joki" then
                SetStatus("🚀  Antar ke "..jokiTarget.Name.."...", Color3.fromRGB(100,200,255))
                local tHRP = jokiTarget.Character
                    and jokiTarget.Character:FindFirstChild("HumanoidRootPart")
                if tHRP then
                    TeleportTo(tHRP.Position + DROP_OFFSET)
                    task.wait(0.7); BasketDropRE:FireServer(); task.wait(0.3)
                    if #Basket:GetChildren() == 0 then
                        SetStatus("✅  Drop ke "..jokiTarget.Name, Color3.fromRGB(80,220,80))
                    else
                        SetStatus("⚠  Drop gagal?", Color3.fromRGB(255,180,0))
                    end
                end
            else
                -- Self mode: teleport ke plot sendiri dan drop
                local plotPos = GetMyPlotCenter()
                if plotPos then
                    SetStatus("🏡  Menuju plot sendiri...", Color3.fromRGB(100,200,255))
                    TeleportTo(plotPos); task.wait(0.8)
                    BasketDropRE:FireServer(); task.wait(0.5)
                    if #Basket:GetChildren() == 0 then
                        SetStatus("✅  Egg ditanam di plot!", Color3.fromRGB(80,220,80))
                    else
                        SetStatus("⚠  Slot penuh? Egg di-drop.", Color3.fromRGB(255,180,0))
                    end
                else
                    SetStatus("⚠  Plot tidak ditemukan!", Color3.fromRGB(255,80,80))
                end
            end
            busy = false
            continue
        end

        -- Cari egg di peta
        local egg, pp, pos = FindPickupableEgg()
        if not egg then
            SetStatus("🔍  Mencari egg di peta...", Color3.fromRGB(140,140,160))
            continue
        end

        busy = true
        SetStatus("🥚  "..egg.Name.." ditemukan!", Color3.fromRGB(255,200,0))
        print("[RaynorHub] Found: "..egg.Name.." PP.Enabled="..tostring(pp.Enabled).." Pos="..tostring(pos))

        -- Teleport & pickup dengan retry
        local picked = false
        local offsets = {
            Vector3.new(2, 1, 2),
            Vector3.new(-2, 1, 2),
            Vector3.new(0, 1, 3),
            Vector3.new(3, 1, 0),
            Vector3.new(0, 2, 0),  -- tepat di atas (untuk egg di high ground)
        }

        for attempt = 1, #offsets do
            -- Cek PP masih ada dan enabled
            if not pp or not pp.Parent or not pp.Enabled then
                -- PP hilang (diambil orang lain) — cari egg baru
                SetStatus("⚠  "..egg.Name.." diambil orang lain!", Color3.fromRGB(255,180,0))
                break
            end

            -- Recalculate posisi PP (mungkin egg bergerak)
            pcall(function()
                if pp.Parent:IsA("BasePart") then
                    pos = pp.Parent.Position
                end
            end)

            local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if hrp then hrp.CFrame = CFrame.new(pos + offsets[attempt]) end
            task.wait(0.5)

            -- Cek jarak setelah teleport
            local dist = 999
            pcall(function()
                dist = (hrp.Position - pos).Magnitude
            end)
            SetStatus("🎯  Attempt "..attempt.." jarak="..math.floor(dist).."s", Color3.fromRGB(200,200,100))
            print("[RaynorHub] Attempt "..attempt.." dist="..math.floor(dist).." offset="..tostring(offsets[attempt]))

            local ok = pcall(function() fireproximityprompt(pp) end)
            if not ok then
                SetStatus("❌  fireproximityprompt error", Color3.fromRGB(255,80,80))
                task.wait(0.3)
                continue
            end
            task.wait(pp.HoldDuration + HOLD_BUFFER)

            if #Basket:GetChildren() > 0 then
                picked = true
                print("[RaynorHub] ✅ Picked up "..egg.Name.." on attempt "..attempt)
                break
            end
            task.wait(0.3)
        end

        if not picked then
            SetStatus("❌  "..egg.Name.." gagal pickup (PP disabled/taken)", Color3.fromRGB(255,80,80))
            print("[RaynorHub] ❌ Failed to pick up "..egg.Name)
            busy = false; continue
        end


        if currentMode == "joki" then
            -- Antar ke target player
            SetStatus("🚀  Antar ke "..jokiTarget.Name.."...", Color3.fromRGB(100,200,255))
            local tHRP = jokiTarget.Character
                and jokiTarget.Character:FindFirstChild("HumanoidRootPart")
            if tHRP then
                TeleportTo(tHRP.Position + DROP_OFFSET); task.wait(0.7)
                BasketDropRE:FireServer(); task.wait(0.3)
                if #Basket:GetChildren() == 0 then
                    SetStatus("✅  "..egg.Name.." → "..jokiTarget.Name, Color3.fromRGB(80,220,80))
                else
                    SetStatus("⚠  Drop mungkin gagal", Color3.fromRGB(255,180,0))
                end
            else
                SetStatus("⚠  Target tidak ada karakter", Color3.fromRGB(255,180,0))
                BasketDropRE:FireServer()
            end
        else
            -- Self mode: teleport ke plot sendiri, lalu drop → server auto-plant ke slot
            local plotPos = GetMyPlotCenter()
            if plotPos then
                SetStatus("🏡  Menuju plot sendiri...", Color3.fromRGB(100,200,255))
                TeleportTo(plotPos); task.wait(0.8)
                BasketDropRE:FireServer(); task.wait(0.5)
                if #Basket:GetChildren() == 0 then
                    SetStatus("✅  "..egg.Name.." ditanam di plot!", Color3.fromRGB(80,220,80))
                else
                    -- Mungkin slot plot penuh, drop di sini saja
                    SetStatus("⚠  Slot plot penuh? Egg di-drop.", Color3.fromRGB(255,180,0))
                    BasketDropRE:FireServer()
                end
            else
                SetStatus("⚠  Plot tidak ditemukan!", Color3.fromRGB(255,80,80))
            end
        end


        busy = false
    end
end

ToggleBtn.MouseButton1Click:Connect(function()
    -- Validasi mode joki butuh target
    if currentMode == "joki" and not jokiTarget then
        SetStatus("⚠  Pilih target dulu!", Color3.fromRGB(255,180,0))
        for i=1,3 do
            ToggleBtn.Position=UDim2.new(0,3,0,0); task.wait(0.05)
            ToggleBtn.Position=UDim2.new(0,-3,0,0); task.wait(0.05)
        end
        ToggleBtn.Position=UDim2.new(0,0,0,0)
        return
    end
    if not next(GetActiveEggs()) then
        SetStatus("⚠  Pilih egg dulu!", Color3.fromRGB(255,180,0))
        return
    end

    jokiEnabled = not jokiEnabled
    if jokiEnabled then
        ToggleBtn.BackgroundColor3 = Color3.fromRGB(200,50,50)
        local modeLabel = currentMode == "self" and "Self" or "→ "..jokiTarget.Name
        ToggleBtn.Text = "⏹  Stop"
        ToggleBtn.TextColor3 = Color3.new(1,1,1)
        SetStatus("🟢  ON ["..modeLabel.."]", Color3.fromRGB(80,220,80))
        task.spawn(RunAuto)
    else
        ToggleBtn.BackgroundColor3 = Color3.fromRGB(50,50,68)
        ToggleBtn.Text = "▶  Start"
        ToggleBtn.TextColor3 = Color3.fromRGB(200,200,220)
        SetStatus("⏸  Status: OFF", Color3.fromRGB(140,140,160))
        busy = false
    end
end)

PopulateDropdown()
print("[RaynorHub v1.0] ✅ GUI loaded!")
