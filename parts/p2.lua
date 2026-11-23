	chargeTime = 0,          -- пауза между установкой и зарядом/ударом (0 = сразу)
	maxCharges = 4,         -- сколько раз закинуть светокамень (до полного заряда анчора)
	aimCamera = false,
	toolClickMode = "Both",  -- клик по позиции, как при ручной установке
	placeClick = "Right",    -- ПКМ = ставить
	equipDelay = 0.05,
	argIndex = 1,               -- как и у кристалла: без ротации аргов
}

CONFIG.KillAura = {
	enabled = false,
	range = 20,
	delay = 0,              -- максимально быстро
	jitter = 0,
	priority = "Nearest",
	filter = "All",
	requireLoS = false,
	aimCamera = true,
	smoothAim = 0.35,       -- 0..1, чем больше — тем резче; 0.35 = плавно
	toolClickMode = "Activate", -- без лишних кликов мышью = быстрее и без дёрганий
	equipDelay = 0,
}

CONFIG.MaceHelper = {
	enabled = false,
	range = 20,
	jumpPower = 60,
	fallAttackDelay = 0.15, -- когда начинать бить после прыжка (на падении)
	onlyMace = false,       -- true = бить только если в руках/инвентаре есть Mace
}

-- =================================================================
-- 3. ПРЕСЕТЫ ПОВЕДЕНИЯ (H — смена)
--    Любое поле здесь переопределяет базовые настройки обеих аур.
-- =================================================================
CONFIG.Presets = {
	{
		name = "Агрессивный",
		range = 80, delay = 0.06, jitter = 0.03,
		priority = "Nearest", filter = "All", positionMode = "Root",
		multi = true,
	},
	{
		name = "Сбалансированный",
		range = 60, delay = 0.15, jitter = 0.08,
		priority = "Nearest", filter = "All", positionMode = "Ring",
		disengageHP = 0.25,
	},
	{
		name = "Только PvP (игроки)",
		range = 55, delay = 0.1, jitter = 0.05,
		priority = "Nearest", filter = "Players", positionMode = "Root",
	},
	{
		name = "Только мобы",
		range = 55, delay = 0.1, jitter = 0.05,
		priority = "Nearest", filter = "Mobs", positionMode = "Feet",
	},
	{
		name = "Спам",
		range = 50, delay = 0.03, jitter = 0,
		priority = "Nearest", filter = "All", positionMode = "Root",
		multi = true,
	},
}

-- =================================================================
-- 4. ХЕЛПЕРЫ
-- =================================================================
local CURRENT_SETTINGS -- текущие настройки активной ауры (задаются в главном цикле)

-- Нижний регистр с учётом кириллицы (string.lower кириллицу не трогает)
local function lowerRU(s)
	s = string.lower(s)
	s = string.gsub(s, "\208[\144-175]", function(c)
		return "\209" .. string.char(string.byte(c, 2) - 16)
	end)
	s = string.gsub(s, "\208\129", "\209\145") -- Ё -> ё
	return s
end

local function lowerList(list)
	local out = {}
	for _, v in ipairs(list or {}) do
		out[#out + 1] = lowerRU(tostring(v))
	end
	return out
end

-- Списки в нижнем регистре (вычисляется один раз)
local P = {
	Enemy   = lowerList(CONFIG.Targeting.EnemyNamePatterns),
	Boss    = lowerList(CONFIG.Targeting.BossNamePatterns),
	Elite   = lowerList(CONFIG.Targeting.EliteNamePatterns),
	Friend  = lowerList(CONFIG.Targeting.FriendlyNamePatterns),
	Crystal = lowerList({ "crystal", "кристалл", "cryst", "end_crystal" }),
	Anchor  = lowerList({ "anchor", "анчор", "якорь", "respawn_anchor" }),
	Charge  = lowerList({ "заряд", "fuel", "топливо", "glowstone", "светокамень", "камень света" }), -- БЕЗ "charge": иначе фаерболлы/заряды оружия ловятся
	Block   = lowerList({ "obsidian", "обсидиан", "block", "блок", "tnt", "тнт", "build", "place" }),
	Attack  = lowerList({ "sword", "меч", "katana", "blade", "axe", "топор", "weapon", "attack", "swing", "hit", "удар" }),
	Remotes = lowerList({ "remot", "event", "net", "network", "comm" }),
	Exact = {
		crystal = lowerList(CONFIG.Exact.Crystal),
		anchor  = lowerList(CONFIG.Exact.Anchor),
		charge  = lowerList(CONFIG.Exact.Charge),
		block   = lowerList(CONFIG.Exact.Block),
		attack  = lowerList(CONFIG.Exact.Attack),
	},
}

local function containsAny(loweredName, list)
	for _, p in ipairs(list) do
		if loweredName:find(p, 1, true) then return true end
	end
	return false
end

local function nameMatches(name, loweredList)
	if type(name) ~= "string" then return false end
	return containsAny(lowerRU(name), loweredList)
end

local function isExact(name, phase)
	local l = P.Exact[phase]
	if not l then return false end
	local n = lowerRU(tostring(name))
	for _, v in ipairs(l) do
		if n == v then return true end
	end
	return false
end

-- Чтение числа: атрибут -> Value-объект
local function readNumber(model, keys)
	for _, k in ipairs(keys) do
		local v = model:GetAttribute(k)
		if type(v) == "number" then return v end
	end
	for _, k in ipairs(keys) do
		local c = model:FindFirstChild(k)
		if c and (c:IsA("NumberValue") or c:IsA("IntValue")) then
			return c.Value
		end
	end
	return nil
end

local function hasAnyTag(inst, tags)
	for _, tag in ipairs(tags or {}) do
		local ok, res = pcall(CollectionService.HasTag, CollectionService, inst, tag)
		if ok and res then return true end
	end
	return false
end

local function getOwnRoot()
	local char = player.Character
	if not char then return nil end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum and hum.RootPart then return hum.RootPart end
	return char:FindFirstChild("HumanoidRootPart")
end

local function myHpRatio()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and hum.MaxHealth > 0 then
		return hum.Health / hum.MaxHealth
	end
	return nil
end

-- Экипировка инструмента (должен быть в Backpack)
local function ensureEquipped(tool)
	local char = player.Character
	if not char or not tool or not tool.Parent then return false, false end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return false, false end
	if tool.Parent == char then return true, false end
	local backpack = player:FindFirstChild("Backpack")
	if tool.Parent ~= backpack then return false, false end
	local ok = pcall(function() hum:EquipTool(tool) end)
	if not ok then return false, false end
	local delay = CURRENT_SETTINGS and CURRENT_SETTINGS.equipDelay or 0
	if delay and delay > 0 then task.wait(delay) end
	return true, true
end

-- Опциональный поворот камеры к точке (smooth = 0..1, 1 = мгновенно)
local function aimCamera(pos, smooth)
	local cam = workspace.CurrentCamera
	local root = getOwnRoot()
	if not cam or not root or not pos then return end
	if (pos - cam.CFrame.Position).Magnitude < 0.5 then return end
	local ok = pcall(function()
		local from = cam.CFrame.Position
		local targetCF = CFrame.lookAt(from, pos)
		local a = tonumber(smooth)
		if a and a > 0 and a < 1 then
			cam.CFrame = cam.CFrame:Lerp(targetCF, a)
		else
			cam.CFrame = targetCF
		end
	end)
	return ok
end

-- Клик мышью по экранной позиции точки (VirtualUser) — ЛКМ (сломать/удар)
local function virtualClick(worldPos)
	local cam = workspace.CurrentCamera
	if not cam then return false end
	local vp = cam:WorldToViewportPoint(worldPos)
	local ok = pcall(function()
		VirtualUser:CaptureController()
		VirtualUser:ClickButton1(Vector2.new(vp.X, vp.Y))
	end)
	return ok
end

-- ПКМ по точке: в этих играх ПКМ = установка, ЛКМ = сломать
local function pressRightClick(worldPos)
	local cam = workspace.CurrentCamera
	local sx, sy = 0, 0
	if cam then
		local vs = cam.ViewportSize
		sx, sy = vs.X / 2, vs.Y / 2
		-- Для установки нужно целиться в ПОВЕРХНОСТЬ (блок), а не в воздух.
		-- Пускаем луч от камеры через точку мира и кликаем туда, где он попадёт в блок.
		local hitPos = nil
		if worldPos then
			local okr, rayRes = pcall(function()
				local origin = cam.CFrame.Position
