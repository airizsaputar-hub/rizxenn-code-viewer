-- ============================================================
-- RIZXENN | AUTO PERFECT CAST + AUTO TELEPORT + SKIP ANIMATION
-- UI baru: bisa buka/tutup, support PC & Android, ada animasi
-- PC: tekan RightShift untuk buka/tutup | Android: tap tombol bulat "R"
-- ============================================================
local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local UserInputService   = game:GetService("UserInputService")
local TweenService       = game:GetService("TweenService")
local LP                 = Players.LocalPlayer

-- ================= SETTINGS =================
local Settings = {
    Enabled        = true,
    Mode           = "Zone",     -- "Zone" | "Peak" | "PeakDetect"
    PeakTolerance  = 0.03,
    ZoneMargin     = 2,
    Cooldown       = 0.08,

    AutoTeleport   = true,
    TeleportRadius = 25,         -- re-teleport kalau > radius ini dari zona
    SkipAnim       = true,
    AutoContinue   = true,
    FacingSign     = 1,          -- 1 = hadap +X, -1 = hadap -X (arah ke air)

    ToggleKey      = Enum.KeyCode.RightShift, -- tombol buka/tutup menu (PC)
}
_G.AutoCastSettings = Settings

-- ================= INPUT =================
local VIM, VU
pcall(function() VIM = game:GetService("VirtualInputManager") end)
pcall(function() VU  = game:GetService("VirtualUser") end)

local function fireClick()
    if VIM then
        VIM:SendMouseButtonEvent(0, 0, 0, true,  game, 0)
        task.wait(0.004)
        VIM:SendMouseButtonEvent(0, 0, 0, false, game, 0)
    elseif VU then
        VU:Button1Down(Vector2.new(0, 0))
        task.wait(0.004)
        VU:Button1Up(Vector2.new(0, 0))
    end
end

-- ================= CONFIG LOADER =================
local Config
pcall(function()
    Config = require(game:GetService("ReplicatedStorage").Shared.Config)
end)
if not Config then
    pcall(function()
        local Shared = game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
        local cfg = Shared and Shared:FindFirstChild("Config")
        if cfg and cfg:IsA("ModuleScript") then Config = require(cfg) end
    end)
end
warn("[AutoCast] Config loaded:", Config ~= nil)

-- ================= TELEPORT =================
local function getCastTarget()
    if not Config then return nil end
    local okX, x = pcall(function() return Config.CastLineX end)
    local okZ = pcall(function() return Config.CastZ0 + Config.CastZ1 end)
    if not okX or not x or not okZ then return nil end
    local z = (Config.CastZ0 + Config.CastZ1) / 2

    -- Raycast untuk cari ground height
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = { LP.Character }
    local hit = workspace:Raycast(Vector3.new(x, 500, z), Vector3.new(0, -1000, 0), rayParams)
    local y = hit and (hit.Position.Y + 3) or (Config.WaterY + 5)

    return Vector3.new(x, y, z)
end

local function teleportToCast()
    local char = LP.Character
    if not char then return false, "no character" end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false, "no HRP" end
    local target = getCastTarget()
    if not target then return false, "Config unavailable" end

    local lookDir = Vector3.new(Settings.FacingSign, 0, 0)
    hrp.CFrame = CFrame.lookAt(target, target + lookDir)
    return true
end

local function isFarFromZone()
    local char = LP.Character
    if not char then return false end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    local target = getCastTarget()
    if not target then return false end
    return (hrp.Position - target).Magnitude > Settings.TeleportRadius
end

-- ================= SKIP ANIMATION =================
local CastGuiNames = { CastGui = true, CastScreenOver = true, CastScreenUnder = true }

local function isCastDescendant(inst)
    local p, depth = inst, 0
    while p and p ~= game and depth < 25 do
        if CastGuiNames[p.Name] then return true end
        p = p.Parent
        depth = depth + 1
    end
    return false
end

local oldCreate = TweenService.Create
if oldCreate then
    local ok = pcall(function()
        TweenService.Create = function(self, inst, info, goal)
            if Settings.SkipAnim and info and info.Time > 0
               and isCastDescendant(inst) then
                local newInfo = TweenInfo.new(
                    0,
                    info.EasingStyle,
                    info.EasingDirection,
                    info.RepeatCount,
                    info.Reverses,
                    info.DelayTime
                )
                return oldCreate(self, inst, newInfo, goal)
            end
            return oldCreate(self, inst, info, goal)
        end
    end)
    warn("[AutoCast] TweenService hook:", ok)
end

-- ================= DETEKSI AIM =================
local function getAim()
    local pg = LP:FindFirstChild("PlayerGui")
    if not pg then return nil end
    local gui = pg:FindFirstChild("CastGui")
    if not gui then return nil end
    local aim = gui:FindFirstChild("Aim")
    if not aim or not aim.Visible then return nil end
    local body = aim:FindFirstChild("Body")
    if not body then return nil end
    local marker = body:FindFirstChild("Marker")
    local zone   = body:FindFirstChild("PerfectGlow")
    if not marker or not zone then return nil end
    return { aim = aim, marker = marker, zone = zone }
end

local function markerValueFromY(y)
    return 1 - (y - 9) / 372
end

local lastClick, lastY, lastDir = 0, math.huge, 0

local function modePeak(markerY)
    return markerValueFromY(markerY) >= (1 - Settings.PeakTolerance)
end

local function modeZone(markerY, zone)
    local glowBottom = zone.Position.Y.Offset + zone.Size.Y.Offset
    local perfectLine = glowBottom - 9
    return markerY <= perfectLine + Settings.ZoneMargin
end

local function modePeakDetect(markerY)
    local dir = 0
    if markerY < lastY - 0.4 then dir = 1
    elseif markerY > lastY + 0.4 then dir = -1 end
    local peaked = (lastDir == 1 and dir == -1) and markerValueFromY(markerY) > 0.85
    if dir ~= 0 then lastDir = dir end
    lastY = markerY
    return peaked
end

-- ================= AUTO CONTINUE =================
local function autoContinueTarget()
    if not Settings.AutoContinue then return false end
    local pg = LP:FindFirstChild("PlayerGui")
    local gui = pg and pg:FindFirstChild("CastGui")
    if not gui then return false end

    local reveal = gui:FindFirstChild("Reveal")
    if reveal and reveal.Visible then return true end

    local skip = gui:FindFirstChild("Skip")
    if skip and skip.Visible then return true end

    local slots = gui:FindFirstChild("Slots")
    if slots and slots.Visible then
        local machine = slots:FindFirstChild("Machine")
        local tap = machine and machine:FindFirstChild("Tap")
        if tap and tap.Visible then return true end
    end
    return false
end

-- ================= MAIN LOOP =================
local lastTeleport = 0

RunService.RenderStepped:Connect(function()
    if not Settings.Enabled then return end

    -- Auto teleport (throttled)
    if Settings.AutoTeleport and tick() - lastTeleport > 1 then
        if isFarFromZone() then
            teleportToCast()
        end
        lastTeleport = tick()
    end

    if tick() - lastClick < Settings.Cooldown then return end

    -- Auto continue first (prioritas klik tombol lanjut)
    if Settings.AutoContinue and autoContinueTarget() then
        fireClick()
        lastClick = tick()
        return
    end

    -- Auto perfect cast
    local ctx = getAim()
    if not ctx then return end
    local y = ctx.marker.Position.Y.Offset
    local should = false
    if Settings.Mode == "Peak" then should = modePeak(y)
    elseif Settings.Mode == "Zone" then should = modeZone(y, ctx.zone)
    elseif Settings.Mode == "PeakDetect" then should = modePeakDetect(y) end

    if should then
        fireClick()
        lastClick = tick()
    end
end)

-- ============================================================
-- ======================= UI : RIZXENN =======================
-- ============================================================
local THEME = {
    Bg      = Color3.fromRGB(14, 16, 26),
    Bar     = Color3.fromRGB(20, 23, 36),
    Item    = Color3.fromRGB(28, 32, 48),
    ItemHov = Color3.fromRGB(36, 41, 62),
    Accent  = Color3.fromRGB(0, 200, 255),
    Accent2 = Color3.fromRGB(150, 90, 255),
    On      = Color3.fromRGB(0, 210, 130),
    Off     = Color3.fromRGB(68, 74, 98),
    Text    = Color3.fromRGB(240, 244, 255),
    Sub     = Color3.fromRGB(140, 150, 182),
    Danger  = Color3.fromRGB(220, 70, 90),
    White   = Color3.new(1, 1, 1),
}

local function tween(obj, t, props, style, dir)
    local tw = TweenService:Create(
        obj,
        TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out),
        props
    )
    tw:Play()
    return tw
end

local function new(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props) do o[k] = v end
    o.Parent = parent
    return o
end

local function corner(o, r)
    return new("UICorner", { CornerRadius = UDim.new(0, r) }, o)
end

local function accentGradient(parent, rotation)
    return new("UIGradient", {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, THEME.Accent),
            ColorSequenceKeypoint.new(1, THEME.Accent2),
        }),
        Rotation = rotation or 0,
    }, parent)
end

-- stroke dengan gradient yang berputar pelan
local function spinStroke(parent, thickness)
    local s = new("UIStroke", {
        Thickness = thickness,
        Color = THEME.White,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, parent)
    local g = new("UIGradient", {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0,   THEME.Accent),
            ColorSequenceKeypoint.new(0.5, THEME.Accent2),
            ColorSequenceKeypoint.new(1,   THEME.Accent),
        }),
    }, s)
    TweenService:Create(
        g,
        TweenInfo.new(4, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1),
        { Rotation = 360 }
    ):Play()
    return s
end

-- efek tekan / hover pada tombol
local function buttonFx(btn, base, hover)
    local sc = new("UIScale", { Scale = 1 }, btn)
    btn.MouseEnter:Connect(function() tween(btn, 0.15, { BackgroundColor3 = hover }) end)
    btn.MouseLeave:Connect(function()
        tween(btn, 0.15, { BackgroundColor3 = base })
        tween(sc, 0.1, { Scale = 1 })
    end)
    btn.MouseButton1Down:Connect(function() tween(sc, 0.08, { Scale = 0.95 }) end)
    btn.MouseButton1Up:Connect(function()
        tween(sc, 0.15, { Scale = 1 }, Enum.EasingStyle.Back)
    end)
end

-- drag untuk mouse & touch. onTap dipanggil kalau cuma di-tap (tidak digeser)
local function makeDraggable(handle, target, onTap)
    local dragging, dragInput, startPos, startUI, moved = false, nil, nil, nil, false

    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            moved = false
            startPos = input.Position
            startUI = target.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    if not moved and onTap then onTap() end
                end
            end)
        end
    end)

    handle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and input == dragInput then
            local d = input.Position - startPos
            if d.Magnitude > 6 then moved = true end
            if moved then
                target.Position = UDim2.new(
                    startUI.X.Scale, startUI.X.Offset + d.X,
                    startUI.Y.Scale, startUI.Y.Offset + d.Y
                )
            end
        end
    end)
end

local function buildUI()
    local pg = LP:WaitForChild("PlayerGui")
    for _, n in ipairs({ "AutoCastUI", "RIZXENN" }) do
        local old = pg:FindFirstChild(n)
        if old then old:Destroy() end
    end

    local gui = new("ScreenGui", {
        Name = "RIZXENN",
        ResetOnSpawn = false,
        DisplayOrder = 500,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    }, pg)

    -- ---------- skala otomatis (HP kecil / PC besar) ----------
    local function computeScale()
        local cam = workspace.CurrentCamera
        local vs = cam and cam.ViewportSize or Vector2.new(1280, 720)
        return math.clamp(math.min(vs.X / 420, vs.Y / 500), 0.65, 1)
    end

    -- ---------- WINDOW UTAMA ----------
    local main = new("CanvasGroup", {
        Name = "Main",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(300, 410),
        BackgroundColor3 = THEME.Bg,
        BorderSizePixel = 0,
        GroupTransparency = 1,
        Visible = false,
    }, gui)
    corner(main, 14)
    spinStroke(main, 2)
    local uiScale = new("UIScale", { Scale = computeScale() }, main)

    -- ---------- TITLE BAR ----------
    local bar = new("Frame", {
        Size = UDim2.new(1, 0, 0, 48),
        BackgroundColor3 = THEME.Bar,
        BorderSizePixel = 0,
    }, main)

    local title = new("TextLabel", {
        Position = UDim2.fromOffset(14, 5),
        Size = UDim2.new(1, -70, 0, 24),
        BackgroundTransparency = 1,
        Text = "RIZXENN",
        TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = THEME.White,
        Font = Enum.Font.GothamBlack,
        TextSize = 22,
    }, bar)
    accentGradient(title, 0)

    new("TextLabel", {
        Position = UDim2.fromOffset(14, 29),
        Size = UDim2.new(1, -70, 0, 14),
        BackgroundTransparency = 1,
        Text = "Auto Perfect Cast  •  v2",
        TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = THEME.Sub,
        Font = Enum.Font.Gotham,
        TextSize = 11,
    }, bar)

    local closeBtn = new("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -12, 0.5, 0),
        Size = UDim2.fromOffset(30, 30),
        BackgroundColor3 = THEME.Item,
        Text = "✕",
        TextColor3 = THEME.Text,
        Font = Enum.Font.GothamBold,
        TextSize = 14,
        AutoButtonColor = false,
    }, bar)
    corner(closeBtn, 8)
    buttonFx(closeBtn, THEME.Item, THEME.Danger)

    -- garis aksen di bawah title
    local line = new("Frame", {
        Position = UDim2.fromOffset(0, 48),
        Size = UDim2.new(1, 0, 0, 2),
        BackgroundColor3 = THEME.White,
        BorderSizePixel = 0,
    }, main)
    accentGradient(line, 0)

    makeDraggable(bar, main)

    -- ---------- AREA KONTEN (scroll) ----------
    local scroll = new("ScrollingFrame", {
        Position = UDim2.fromOffset(0, 52),
        Size = UDim2.new(1, 0, 1, -52 - 28),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = THEME.Accent,
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y,
    }, main)
    new("UIListLayout", {
        Padding = UDim.new(0, 8),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, scroll)
    new("UIPadding", {
        PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 10),
        PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 14),
    }, scroll)

    local order = 0
    local function nextOrder() order = order + 1 return order end

    local function addHeader(text)
        new("TextLabel", {
            LayoutOrder = nextOrder(),
            Size = UDim2.new(1, 0, 0, 16),
            BackgroundTransparency = 1,
            Text = text,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextColor3 = THEME.Accent,
            Font = Enum.Font.GothamBold,
            TextSize = 11,
        }, scroll)
    end

    -- ---------- TOGGLE ----------
    local function addToggle(text, get, set)
        local row = new("Frame", {
            LayoutOrder = nextOrder(),
            Size = UDim2.new(1, 0, 0, 40),
            BackgroundColor3 = THEME.Item,
            BorderSizePixel = 0,
        }, scroll)
        corner(row, 9)

        new("TextLabel", {
            Position = UDim2.fromOffset(12, 0),
            Size = UDim2.new(1, -70, 1, 0),
            BackgroundTransparency = 1,
            Text = text,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextColor3 = THEME.Text,
            Font = Enum.Font.GothamMedium,
            TextSize = 13,
        }, row)

        local pill = new("Frame", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -12, 0.5, 0),
            Size = UDim2.fromOffset(42, 22),
            BackgroundColor3 = get() and THEME.On or THEME.Off,
            BorderSizePixel = 0,
        }, row)
        corner(pill, 11)

        local knob = new("Frame", {
            AnchorPoint = Vector2.new(0, 0.5),
            Position = get() and UDim2.new(1, -20, 0.5, 0) or UDim2.new(0, 2, 0.5, 0),
            Size = UDim2.fromOffset(18, 18),
            BackgroundColor3 = THEME.White,
            BorderSizePixel = 0,
        }, pill)
        corner(knob, 9)

        local hit = new("TextButton", {
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Text = "",
            ZIndex = 5,
        }, row)

        hit.MouseEnter:Connect(function() tween(row, 0.15, { BackgroundColor3 = THEME.ItemHov }) end)
        hit.MouseLeave:Connect(function() tween(row, 0.15, { BackgroundColor3 = THEME.Item }) end)
        hit.MouseButton1Click:Connect(function()
            local v = not get()
            set(v)
            tween(pill, 0.2, { BackgroundColor3 = v and THEME.On or THEME.Off })
            tween(knob, 0.25, {
                Position = v and UDim2.new(1, -20, 0.5, 0) or UDim2.new(0, 2, 0.5, 0),
            }, Enum.EasingStyle.Back)
        end)
    end

    addHeader("FITUR")
    addToggle("Auto Cast",     function() return Settings.Enabled end,      function(v) Settings.Enabled = v end)
    addToggle("Teleport",      function() return Settings.AutoTeleport end, function(v) Settings.AutoTeleport = v end)
    addToggle("Skip Animasi",  function() return Settings.SkipAnim end,     function(v) Settings.SkipAnim = v end)
    addToggle("Auto Continue", function() return Settings.AutoContinue end, function(v) Settings.AutoContinue = v end)

    -- ---------- MODE (segmented) ----------
    addHeader("MODE DETEKSI")
    local segRow = new("Frame", {
        LayoutOrder = nextOrder(),
        Size = UDim2.new(1, 0, 0, 34),
        BackgroundTransparency = 1,
    }, scroll)
    new("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        Padding = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, segRow)

    local modes = { "Zone", "Peak", "PeakDetect" }
    local segButtons = {}
    local function refreshModes()
        for name, b in pairs(segButtons) do
            local active = (Settings.Mode == name)
            tween(b, 0.2, {
                BackgroundColor3 = active and THEME.Accent or THEME.Item,
                TextColor3 = active and THEME.Bg or THEME.Text,
            })
        end
    end
    for i, name in ipairs(modes) do
        local b = new("TextButton", {
            LayoutOrder = i,
            Size = UDim2.new(1 / 3, -4, 1, 0),
            BackgroundColor3 = THEME.Item,
            Text = name,
            TextColor3 = THEME.Text,
            Font = Enum.Font.GothamBold,
            TextSize = 12,
            AutoButtonColor = false,
        }, segRow)
        corner(b, 8)
        local sc = new("UIScale", { Scale = 1 }, b)
        b.MouseButton1Down:Connect(function() tween(sc, 0.08, { Scale = 0.94 }) end)
        b.MouseButton1Up:Connect(function() tween(sc, 0.15, { Scale = 1 }, Enum.EasingStyle.Back) end)
        b.MouseLeave:Connect(function() tween(sc, 0.1, { Scale = 1 }) end)
        b.MouseButton1Click:Connect(function()
            Settings.Mode = name
            refreshModes()
        end)
        segButtons[name] = b
    end
    refreshModes()

    new("TextLabel", {
        LayoutOrder = nextOrder(),
        Size = UDim2.new(1, 0, 0, 14),
        BackgroundTransparency = 1,
        Text = "Zone = paling akurat (disarankan)",
        TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = THEME.Sub,
        Font = Enum.Font.Gotham,
        TextSize = 11,
    }, scroll)

    -- ---------- SLIDER TOLERANSI ----------
    addHeader("PRESISI")
    local sliderRow = new("Frame", {
        LayoutOrder = nextOrder(),
        Size = UDim2.new(1, 0, 0, 56),
        BackgroundColor3 = THEME.Item,
        BorderSizePixel = 0,
    }, scroll)
    corner(sliderRow, 9)

    local tolLbl = new("TextLabel", {
        Position = UDim2.fromOffset(12, 6),
        Size = UDim2.new(1, -24, 0, 18),
        BackgroundTransparency = 1,
        Text = string.format("Toleransi (mode Peak): %.3f", Settings.PeakTolerance),
        TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = THEME.Text,
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
    }, sliderRow)

    local track = new("Frame", {
        Position = UDim2.fromOffset(12, 36),
        Size = UDim2.new(1, -24, 0, 8),
        BackgroundColor3 = THEME.Off,
        BorderSizePixel = 0,
    }, sliderRow)
    corner(track, 4)

    local rel0 = math.clamp(Settings.PeakTolerance / 0.1, 0.01, 1)
    local fill = new("Frame", {
        Size = UDim2.new(rel0, 0, 1, 0),
        BackgroundColor3 = THEME.White,
        BorderSizePixel = 0,
    }, track)
    corner(fill, 4)
    accentGradient(fill, 0)

    local sKnob = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(rel0, 0, 0.5, 0),
        Size = UDim2.fromOffset(18, 18),
        BackgroundColor3 = THEME.White,
        BorderSizePixel = 0,
        ZIndex = 3,
    }, track)
    corner(sKnob, 9)
    new("UIStroke", { Color = THEME.Accent, Thickness = 2 }, sKnob)

    local sliding = false
    local function setFromX(x)
        local rel = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0.01, 1)
        Settings.PeakTolerance = rel * 0.1
        fill.Size = UDim2.new(rel, 0, 1, 0)
        sKnob.Position = UDim2.new(rel, 0, 0.5, 0)
        tolLbl.Text = string.format("Toleransi (mode Peak): %.3f", Settings.PeakTolerance)
    end

    local sHit = new("TextButton", {
        Position = UDim2.fromOffset(0, 24),
        Size = UDim2.new(1, 0, 0, 32),
        BackgroundTransparency = 1,
        Text = "",
        ZIndex = 5,
    }, sliderRow)
    sHit.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            sliding = true
            scroll.ScrollingEnabled = false -- biar tidak ikut scroll di HP
            tween(sKnob, 0.1, { Size = UDim2.fromOffset(22, 22) })
            setFromX(input.Position.X)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if sliding and (input.UserInputType == Enum.UserInputType.MouseMovement
                     or input.UserInputType == Enum.UserInputType.Touch) then
            setFromX(input.Position.X)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            if sliding then
                sliding = false
                scroll.ScrollingEnabled = true
                tween(sKnob, 0.15, { Size = UDim2.fromOffset(18, 18) }, Enum.EasingStyle.Back)
            end
        end
    end)

    -- ---------- AKSI ----------
    addHeader("AKSI")
    local tpBtn = new("TextButton", {
        LayoutOrder = nextOrder(),
        Size = UDim2.new(1, 0, 0, 36),
        BackgroundColor3 = THEME.Accent2,
        Text = "Teleport ke Zona Cast",
        TextColor3 = THEME.White,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        AutoButtonColor = false,
    }, scroll)
    corner(tpBtn, 9)
    buttonFx(tpBtn, THEME.Accent2, Color3.fromRGB(175, 120, 255))
    tpBtn.MouseButton1Click:Connect(function()
        local ok, err = teleportToCast()
        tpBtn.Text = ok and "Berhasil!" or ("Gagal: " .. tostring(err))
        task.delay(1.2, function()
            if tpBtn.Parent then tpBtn.Text = "Teleport ke Zona Cast" end
        end)
    end)

    local resetBtn = new("TextButton", {
        LayoutOrder = nextOrder(),
        Size = UDim2.new(1, 0, 0, 32),
        BackgroundColor3 = Color3.fromRGB(80, 44, 54),
        Text = "Reset Posisi Player",
        TextColor3 = THEME.White,
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        AutoButtonColor = false,
    }, scroll)
    corner(resetBtn, 9)
    buttonFx(resetBtn, Color3.fromRGB(80, 44, 54), THEME.Danger)
    resetBtn.MouseButton1Click:Connect(function()
        local char = LP.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then
            hrp.CFrame = hrp.CFrame + Vector3.new(0, 0.5, 0)
        end
    end)

    -- ---------- FOOTER / STATUS ----------
    local footer = new("Frame", {
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.fromScale(0, 1),
        Size = UDim2.new(1, 0, 0, 28),
        BackgroundColor3 = THEME.Bar,
        BorderSizePixel = 0,
    }, main)

    local dot = new("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 12, 0.5, 0),
        Size = UDim2.fromOffset(8, 8),
        BackgroundColor3 = Config and THEME.On or Color3.fromRGB(255, 180, 100),
        BorderSizePixel = 0,
    }, footer)
    corner(dot, 4)
    -- titik berdenyut pelan
    TweenService:Create(
        dot,
        TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
        { BackgroundTransparency = 0.6 }
    ):Play()

    local status = new("TextLabel", {
        Position = UDim2.fromOffset(26, 0),
        Size = UDim2.new(1, -36, 1, 0),
        BackgroundTransparency = 1,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = THEME.Sub,
        Font = Enum.Font.Gotham,
        TextSize = 11,
    }, footer)

    task.spawn(function()
        while gui.Parent do
            local cfg = Config and "Config OK" or "Config tidak ada"
            local run = Settings.Enabled and "AKTIF" or "MATI"
            status.Text = cfg .. "  •  " .. run .. "  •  RightShift"
            task.wait(0.5)
        end
    end)

    -- ---------- TOMBOL BULAT (buka/tutup) ----------
    local bubble = new("TextButton", {
        Name = "Bubble",
        Position = UDim2.fromOffset(16, 90),
        Size = UDim2.fromOffset(48, 48),
        BackgroundColor3 = THEME.Bg,
        Text = "R",
        TextColor3 = THEME.White,
        Font = Enum.Font.GothamBlack,
        TextSize = 22,
        AutoButtonColor = false,
        ZIndex = 10,
    }, gui)
    corner(bubble, 24)
    spinStroke(bubble, 2.5)

    -- ---------- BUKA / TUTUP ----------
    local isOpen = false
    local function setOpen(open)
        if open == isOpen then return end
        isOpen = open
        local sc = computeScale()
        if open then
            main.Visible = true
            uiScale.Scale = sc * 0.8
            main.GroupTransparency = 1
            tween(uiScale, 0.4, { Scale = sc }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
            tween(main, 0.25, { GroupTransparency = 0 })
        else
            local t = tween(uiScale, 0.2, { Scale = sc * 0.8 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
            tween(main, 0.2, { GroupTransparency = 1 })
            t.Completed:Connect(function()
                if not isOpen then main.Visible = false end
            end)
        end
        -- efek "pop" pada tombol bulat
        bubble.Size = UDim2.fromOffset(40, 40)
        tween(bubble, 0.3, { Size = UDim2.fromOffset(48, 48) }, Enum.EasingStyle.Back)
    end

    makeDraggable(bubble, bubble, function() setOpen(not isOpen) end)
    closeBtn.MouseButton1Click:Connect(function() setOpen(false) end)

    UserInputService.InputBegan:Connect(function(input, processed)
        if processed then return end
        if input.KeyCode == Settings.ToggleKey then
            setOpen(not isOpen)
        end
    end)

    -- sesuaikan skala kalau ukuran layar berubah (rotate HP, dll)
    local cam = workspace.CurrentCamera
    if cam then
        cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
            if isOpen then tween(uiScale, 0.2, { Scale = computeScale() }) end
        end)
    end

    -- tampil pertama kali dengan animasi
    task.defer(function() setOpen(true) end)
end

buildUI()
