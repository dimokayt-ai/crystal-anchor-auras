-- ===================================================================
-- AURA SUITE · Loader — плавная загрузка с GitHub по частям
-- ===================================================================
local Players  = game:GetService("Players")
local Tween    = game:GetService("TweenService")
local Run      = game:GetService("RunService")
local player   = Players.LocalPlayer
if not player then return end

-- убиваем прошлый лоадер, чтобы окна не копились
local G = (type(getgenv) == "function" and getgenv()) or _G
G.AURA_LOADER_TOKEN = (G.AURA_LOADER_TOKEN or 0) + 1
local MY_TOKEN = G.AURA_LOADER_TOKEN

local BASE  = "https://raw.githubusercontent.com/dimokayt-ai/crystal-anchor-auras/main/parts/"
local COUNT = 8
local VER   = "v3"

local WHITE  = Color3.fromRGB(236, 237, 242)
local MUTED  = Color3.fromRGB(152, 156, 168)
local ACCENT = Color3.fromRGB(120, 132, 255)
local GREEN  = Color3.fromRGB(86, 214, 148)
local RED    = Color3.fromRGB(255, 105, 110)
local CARD   = Color3.fromRGB(22, 23, 30)

local sg, card, barFill, barGlow, label, sub, stageLabels, spinner

local function corner(obj, r)
	local c = Instance.new("UICorner", obj)
	c.CornerRadius = UDim.new(0, r or 12)
	return c
end

local function text(parent, str, size, color, weight, y, x, bold)
	local l = Instance.new("TextLabel", parent)
	l.Size = UDim2.new(1, -(x or 48) * 2, 0, size + 8)
	l.Position = UDim2.fromOffset(x or 48, y)
	l.BackgroundTransparency = 1
	l.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
	l.TextSize = size
	l.TextColor3 = color or WHITE
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = str
	return l
end

local function buildUI()
	local pg = player:FindFirstChild("PlayerGui")
	if not pg then return false end
	local old = pg:FindFirstChild("AuraLoaderUI")
	if old then old:Destroy() end

	sg = Instance.new("ScreenGui")
	sg.Name = "AuraLoaderUI"
	sg.ResetOnSpawn = false
	sg.IgnoreGuiInset = true
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	sg.Parent = pg

	-- затемнение фона (как на macOS)
	local dim = Instance.new("Frame", sg)
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.fromRGB(6, 7, 11)
	dim.BackgroundTransparency = 0.45
	dim.BorderSizePixel = 0

	card = Instance.new("Frame", sg)
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Size = UDim2.fromOffset(540, 336)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.BackgroundColor3 = CARD
	card.BackgroundTransparency = 0.06
	card.BorderSizePixel = 0
	card.Parent = sg
	corner(card, 24)
	local stroke = Instance.new("UIStroke", card)
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Transparency = 0.88
	stroke.Thickness = 1

	local grad = Instance.new("UIGradient", card)
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(31, 33, 43)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(15, 16, 22)),
	})
	grad.Rotation = 90

	-- логотип-точка
	local dot = Instance.new("Frame", card)
	dot.Size = UDim2.fromOffset(10, 10)
	dot.Position = UDim2.fromOffset(48, 36)
	dot.BackgroundColor3 = ACCENT
	dot.BorderSizePixel = 0
	corner(dot, 5)

	spinner = Instance.new("Frame", card)
	spinner.Size = UDim2.fromOffset(30, 30)
	spinner.Position = UDim2.fromOffset(474, 26)
	spinner.BackgroundTransparency = 1
	corner(spinner, 15)
	local ring = Instance.new("UIStroke", spinner)
	ring.Color = ACCENT
	ring.Thickness = 3
	ring.Transparency = 0.25
	local rim = Instance.new("Frame", spinner)
	rim.Size = UDim2.fromOffset(7, 7)
	rim.Position = UDim2.fromOffset(12, -3)
	rim.BackgroundColor3 = ACCENT
	rim.BorderSizePixel = 0
	corner(rim, 4)

	text(card, "AURA SUITE", 26, WHITE, true, 30, 48).Size = UDim2.fromOffset(360, 40)
	sub = text(card, "Crystal · Anchor · KillAura  —  " .. VER, 13, MUTED, false, 72, 48)

	-- разделитель
	local sep = Instance.new("Frame", card)
	sep.Size = UDim2.new(1, -96, 0, 1)
	sep.Position = UDim2.fromOffset(48, 108)
	sep.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	sep.BackgroundTransparency = 0.9
	sep.BorderSizePixel = 0

	label = text(card, "Подключение к репозиторию…", 17, WHITE, true, 126, 48)
	label.Size = UDim2.new(1, -96, 0, 26)

	-- прогресс-капсула
	local track = Instance.new("Frame", card)
	track.Size = UDim2.new(1, -96, 0, 8)
	track.Position = UDim2.fromOffset(48, 168)
	track.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	track.BackgroundTransparency = 0.92
	track.BorderSizePixel = 0
	corner(track, 4)

	barFill = Instance.new("Frame", track)
	barFill.Size = UDim2.new(0, 0, 1, 0)
	barFill.BackgroundColor3 = ACCENT
	barFill.BorderSizePixel = 0
	corner(barFill, 4)
	local bg = Instance.new("UIGradient", barFill)
	bg.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(96, 108, 240)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(178, 140, 255)),
	})
	barGlow = bg

	-- этапы
	stageLabels = {}
	local names = { "Подключение", "Загрузка модулей", "Сборка", "Запуск" }
	for i, n in ipairs(names) do
		local row = text(card, "○  " .. n, 13, MUTED, false, 196 + (i - 1) * 28, 48)
		stageLabels[i] = row
	end

	text(card, "Плавная загрузка · GitHub raw", 11, MUTED, false, 304, 48)

	-- анимация спиннера (лёгкая, только пока окно живо)
	task.spawn(function()
		local a = 0
		while sg and sg.Parent and MY_TOKEN == G.AURA_LOADER_TOKEN do
			local dt = Run.RenderStepped:Wait()
			a = (a + dt * 200) % 360
			if spinner and spinner.Parent then spinner.Rotation = a end
			if barGlow then
				barGlow.Offset = Vector2.new(math.sin(os.clock() * 2) * 0.25, 0)
			end
		end
	end)

	return true
end

local function setProgress(p, msg)
	if barFill and barFill.Parent then
		Tween:Create(barFill, TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Size = UDim2.new(math.clamp(p, 0, 1), 0, 1, 0),
		}):Play()
	end
	if label and msg then label.Text = msg end
end

local function stage(i, done, active)
	local l = stageLabels and stageLabels[i]
	if not l then return end
	l.Text = (done and "✓  " or (active and "●  " or "○  ")) .. string.sub(l.Text, 5)
	l.TextColor3 = done and GREEN or (active and ACCENT or MUTED)
end

local function fatal(msg)
	if label then
		label.Text = "Ошибка: " .. tostring(msg)
		label.TextColor3 = RED
	end
	if sub then sub.Text = "Проверь интернет/VPN и нажми Execute ещё раз" end
	setProgress(0)
	for i = 1, 4 do stage(i, false, false) end
end

if not buildUI() then return end

local function fetchPart(i, attempt)
	local url = BASE .. "p" .. i .. ".lua"
	if attempt and attempt > 1 then url = url .. "?v=" .. os.time() .. attempt end
	local ok, data = pcall(function() return game:HttpGet(url) end)
	if ok and type(data) == "string" and #data > 100 and not data:find("^%s*<") then
		return data
	end
	return nil
end

stage(1, true, false)
local parts = {}
local okAll = true
for round = 1, 2 do
	parts = {}
	okAll = true
	for i = 1, COUNT do
		label.Text = ("Загрузка модуля %d из %d…"):format(i, COUNT)
		local data
		for attempt = 1, 3 do
			data = fetchPart(i, attempt)
			if data then break end
			task.wait(0.35 * attempt)
		end
		if not data then okAll = false break end
		parts[i] = data
		setProgress(((i - 1) + (round - 1) * 0.5) / COUNT)
		task.wait(0.07)
	end
	-- проверка целостности: хвост должен содержать конец защитного xpcall
	local tail = parts[COUNT] or ""
	if okAll and (not tail:find("showFatal", 1, true) or #table.concat(parts) < 30000) then
		okAll = false
	end
	if okAll then break end
	if round == 1 then
		label.Text = "Кеш битый — повторяю загрузку…"
		task.wait(0.5)
	end
end

if not okAll then
	fatal("не удалось скачать модули (проверь сеть)")
	return
end

stage(2, true, false)
setProgress(0.97, "Собираю модули…")
stage(3, true, false)
task.wait(0.18)

local src = table.concat(parts, "\n")
local fn, err = loadstring(src)
if not fn then
	fatal("компиляция: " .. tostring(err))
	return
end

stage(4, false, true)
label.Text = "Запуск…"
task.wait(0.16)
local ran, runErr = xpcall(fn, debug.traceback)
if not ran then
	fatal("запуск: " .. tostring(runErr))
	return
end

stage(4, true, false)
label.Text = "Готово"
label.TextColor3 = GREEN
sub.Text = "Z / G / N / M · H — пресеты · L — лог"
setProgress(1)
task.wait(0.75)

if sg and sg.Parent then
	-- мягко уводим карточку вверх и удаляем
	Tween:Create(card, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {
		Position = UDim2.fromScale(0.5, 0.46),
	}):Play()
	task.wait(0.3)
	sg:Destroy()
end
