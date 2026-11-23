	twoPhaseMode = "swing",    -- swing | findAndSwing | none
	twoPhaseDelay = 0,         -- пауза между постановкой и ударом (0 = сразу)
	aimCamera = false,         -- поворачивать камеру к точке (нужно в некоторых играх)
	toolClickMode = "Both",  -- Activate | VirtualClick | Both (Both = клик по позиции цели)
	placeClick = "Right",      -- ПКМ = ставить (ЛКМ в этой игре ломает!)
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
	chargeTime = 0,          -- пауза между установкой и зарядом/ударом (0 = сразу)
	maxCharges = 4,         -- сколько раз закинуть светокамень (до полного заряда анчора)
	aimCamera = false,
	toolClickMode = "Both",  -- клик по позиции, как при ручной установке
	placeClick = "Right",    -- ПКМ = ставить
	equipDelay = 0.05,
	argIndex = 1,               -- как и у кристалла: без ротации аргов
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
	Block   = lowerList({ "obsidian", "обсидиан", "block", "блок", "tnt", "тнт" }),
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

-- Опциональный поворот камеры к точке
local function aimCamera(pos)
	local cam = workspace.CurrentCamera
	local root = getOwnRoot()
	if not cam or not root then return end
	local ok = pcall(function()
		cam.CFrame = CFrame.lookAt(cam.CFrame.Position, pos)
	end)
	return ok
end
