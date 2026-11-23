
	placeBlock = true,          -- сначала ставить блок (обсидиан) под кристалл
	blockDelay = 0.12,          -- пауза между блоком и кристаллом
	twoPhase = true,           -- поставить кристалл -> ударить/взорвать
	twoPhaseMode = "swing",    -- swing | findAndSwing | none
	twoPhaseDelay = 0.12,      -- пауза между постановкой и ударом
	aimCamera = false,         -- поворачивать камеру к точке (нужно в некоторых играх)
	toolClickMode = "Both",  -- Activate | VirtualClick | Both (Both = клик по позиции цели)
	equipDelay = 0.05,         -- пауза после экипировки инструмента
	argIndex = 1,               -- 1 = фикс. арги (без ротации: ротация заставляла игру доставать пушку/фаербол); nil = ротация
}

CONFIG.Anchor = {
	enabled = false,
	range = 60,
	delay = 0.3,
	jitter = 0.15,
	positionMode = "Below",
	priority = "Nearest",
	filter = "All",
	multi = false,
	requireLoS = false,
	finishHP = 0.3,
	disengageHP = nil,
	aggroOnly = false,
	aggroRadius = 25,

	sequence = "auto",      -- auto | single | charge_then_use | use_twice | place_charge_attack
	autoDouble = true,      -- в auto: нет заряда => активировать дважды (поставить -> подорвать)
	chargeTime = 0.6,       -- пауза между установкой и подрывом/зарядом
	aimCamera = false,
	toolClickMode = "Both",  -- клик по позиции, как при ручной установке
	equipDelay = 0.05,
	argIndex = 1,               -- как и у кристалла: без ротации аргов
}

-- =================================================================
-- 3. ПРЕСЕТЫ ПОВЕДЕНИЯ (H — смена)
--    Любое поле здесь переопределяет базовые настройки обеих аур.
-- =================================================================
CONFIG.Presets = {
	{
		name = "Сбалансированный",
		range = 60, delay = 0.15, jitter = 0.08,
		priority = "Nearest", filter = "All", positionMode = "Ring",
		disengageHP = 0.25,
	},
	{
		name = "Агрессивный",
		range = 80, delay = 0.06, jitter = 0.03,
		priority = "Nearest", filter = "All", positionMode = "Root",
		multi = true,
	},
	{
		name = "Фарм (добивание)",
		range = 45, delay = 0.1, jitter = 0.05,
		priority = "Finisher", finishHP = 0.35, filter = "Mobs",
		positionMode = "Feet",
	},
	{
		name = "Охота на боссов",
		range = 70, delay = 0.12, jitter = 0.06,
		priority = "BossFirst", filter = "Bosses", positionMode = "Below",
	},
	{
		name = "Танк-хант (криты по толстым)",
		range = 60, delay = 0.12, jitter = 0.06,
		priority = "HighestHP", filter = "Mobs", positionMode = "Root",
	},
	{
		name = "Оборона (только рядом)",
		range = 35, delay = 0.1, jitter = 0.05,
		priority = "Nearest", filter = "All", positionMode = "Feet",
		aggroOnly = true, aggroRadius = 22,
	},
	{
		name = "Стелс (редко, но мимо стен)",
		range = 90, delay = 0.5, jitter = 0.25,
		priority = "Random", filter = "All", positionMode = "Behind",
		requireLoS = true,
	},
	{
		name = "Безопасный (отступ при HP)",
		range = 40, delay = 0.25, jitter = 0.1,
		priority = "Nearest", filter = "All", positionMode = "Ring",
		disengageHP = 0.5,
	},
	{
		name = "Только PvP",
		range = 55, delay = 0.1, jitter = 0.05,
		priority = "Nearest", filter = "Players", positionMode = "Root",
	},
	{
		name = "Только мобы",
		range = 55, delay = 0.1, jitter = 0.05,
		priority = "Nearest", filter = "Mobs", positionMode = "Feet",
	},
	{
		name = "Гибрид PvP + мобы",
		range = 65, delay = 0.12, jitter = 0.06,
		priority = "Threat", filter = "All", positionMode = "Ring",
	},
	{
		name = "Спам",
		range = 50, delay = 0.03, jitter = 0,
		priority = "Nearest", filter = "All", positionMode = "Root",
		multi = true,
	},
	{
		name = "Осторожный (анти-детект)",
		range = 45, delay = 0.4, jitter = 0.25,
		priority = "Nearest", filter = "All", positionMode = "Ring",
		requireLoS = true, disengageHP = 0.3,
	},
	{
		name = "Случайный хаос",
		range = 60, delay = 0.18, jitter = 0.12,
		priority = "Random", filter = "All", positionMode = "Ring",
		multi = true,
	},
	{
		name = "Только боссы/элита",
		range = 75, delay = 0.1, jitter = 0.05,
		priority = "BossFirst", filter = "Bosses", positionMode = "Below",
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
	Charge  = lowerList({ "charge", "заряд", "fuel", "топливо", "glowstone", "светокамень", "камень света" }),
	Block   = lowerList({ "obsidian", "обсидиан", "block", "блок", "tnt", "тнт" }),
	Attack  = lowerList({ "sword", "меч", "katana", "blade", "axe", "топор", "weapon" }),
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