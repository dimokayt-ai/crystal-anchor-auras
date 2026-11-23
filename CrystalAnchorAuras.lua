--[[
	=================================================================
	CRYSTAL AURA + ANCHOR AURA  —  клиентский LocalScript (Roblox)
	=================================================================
	Клавиши:
		Z  — вкл/выкл Crystal Aura
		G  — вкл/выкл Anchor Aura
		X / B — запасные клавиши (Z / G)
		H  — смена пресета поведения
		K  — смена найденного источника (если их несколько)
		J  — вкл/выкл HUD

	Скрипт САМ СКАНИРУЕТ игру и ищет, чем ауры могут пользоваться:
		- Tool'ы в рюкзаке/в руках (+ шаблоны в ReplicatedStorage)
		- RemoteEvent / RemoteFunction
		- ProximityPrompt
		- ModuleScript'ы с функциями (place / detonate / use / ...)
	Каждый источник получает score (уверенность), текущий переключается на K.

	Всё ТОЛЬКО на клиенте: скрипт лишь нажимает/вызывает то, что уже есть
	в твоей игре. Урон и взрывы — на стороне твоей игры.

	Куда вставлять: StarterPlayer > StarterPlayerScripts > LocalScript
	=================================================================
]]

-- НЕ ждём game.Loaded: у части экзекьюторов IsLoaded() всегда false,
-- и Wait() виснет намертво -> "тишина". Первый маркер выполнения:
print("[Auras] скрипт выполняется...")

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local VirtualUser       = game:GetService("VirtualUser")

local player = Players.LocalPlayer
if not player then
	warn("[Auras] Не клиент! Этот скрипт должен быть LocalScript.")
	return
end

-- =================================================================
-- XENO / EXECUTOR BOOTSTRAP
-- =================================================================
local GENV = (type(getgenv) == "function" and getgenv()) or _G
GENV.AURA_TOKEN = (GENV.AURA_TOKEN or 0) + 1
local TOKEN = GENV.AURA_TOKEN
local function alive() return GENV.AURA_TOKEN == TOKEN end

-- отключить прошлый запуск (иначе 2 подключения = F/G переключаются дважды
-- и выглядит так, будто скрипт "не реагирует")
if type(GENV.AURA_CONNS) == "table" then
	for _, c in ipairs(GENV.AURA_CONNS) do
		pcall(function() c:Disconnect() end)
	end
end
GENV.AURA_CONNS = {}
pcall(function()
	local pg = player:FindFirstChild("PlayerGui")
	local old = pg and pg:FindFirstChild("AuraHUD")
	if old then old:Destroy() end
end)

-- любая ошибка запуска -> красный текст на экране (чтобы видеть причину)
local function showFatal(err)
	warn("[Auras] ОШИБКА ЗАПУСКА:\n" .. tostring(err))
	pcall(function()
		local pg = player:FindFirstChild("PlayerGui")
		if not pg then return end
		local old = pg:FindFirstChild("AurasFatal")
		if old then old:Destroy() end
		local sg = Instance.new("ScreenGui")
		sg.Name = "AurasFatal"
		sg.ResetOnSpawn = false
		sg.Parent = pg
		local l = Instance.new("TextLabel")
		l.Size = UDim2.new(1, -20, 0, 190)
		l.Position = UDim2.fromOffset(10, 140)
		l.BackgroundColor3 = Color3.fromRGB(120, 10, 10)
		l.BackgroundTransparency = 0.15
		l.TextColor3 = Color3.fromRGB(255, 220, 220)
		l.Font = Enum.Font.Code
		l.TextSize = 14
		l.TextWrapped = true
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.TextYAlignment = Enum.TextYAlignment.Top
		l.Text = "[Auras] ОШИБКА ЗАПУСКА (пришли этот текст):\n" .. tostring(err)
		l.Parent = sg
	end)
end

-- всё дальше — под общей защитой: ЛЮБАЯ ошибка выполнения уйдёт
-- на красный экран и в консоль, а не пропадёт молча
local __ok, __err = xpcall(function()

-- =================================================================
-- 1. КОНФИГ
-- =================================================================
local CONFIG = {
	Keys = {
		ToggleCrystal = Enum.KeyCode.Z,   -- Crystal Aura (F обычно занят игрой)
		ToggleCrystalAlt = Enum.KeyCode.X,-- запасная клавиша кристалла
		ToggleAnchor  = Enum.KeyCode.G,   -- Anchor Aura
		ToggleAnchorAlt = Enum.KeyCode.B, -- запасная клавиша анчора
		CyclePreset   = Enum.KeyCode.H,   -- смена пресета
		CycleSource   = Enum.KeyCode.K,   -- смена источника
		ToggleHUD     = Enum.KeyCode.J,   -- показать/скрыть HUD
	},

	Scan = {
		Interval      = 0.5,   -- как часто обновлять список целей (сек)
		FullInterval  = 2.0,   -- полный обход workspace (сек)
		SourceRescan  = 5.0,   -- перескан источников: tools/remotes (сек)
		CloneTemplates    = true,  -- клонировать ТОЛЬКО аурные шаблоны (End Crystal/Anchor/Glowstone/Block), мечи не трогает
		CloneAttack       = false, -- НЕ клонировать мечи/топоры/оружия (иначе спам в инвентарь!)
		CloneFromWorkspace = false, -- искать шаблоны Tool в workspace (дубли!)
		DumpAll           = true,  -- вывести ВСЕ инструменты/ремоуты игры в консоль (диагностика)
		RequireModules    = false, -- НЕ require чужие ModuleScript'ы (могут ломать игру/текстуры)
	},

	-- Точные имена из DUMP твоей игры (заполнены по реальному дампу)
	Exact = {
		Crystal = { "End Crystal", "EndCrystal", "end_crystal", "Crystal", "Кристалл" },
		Anchor  = { "Anchor", "Анчор", "Якорь" }, -- ТОЛЬКО Tool! (RespawnAnchor-ремоут больше не используется)
		Charge  = { "Glowstone", "AnchorCharge", "Заряд", "Светокамень" }, -- без простого "Charge" (иначе ловит Fire Charge/Orbital Strike Charge!)
		Block   = { "Block", "Cobblestone", "Obsidian", "Обсидиан", "Блок" },
		Attack  = { "Sword", "Katana", "Меч", "Blade", "Axe", "Netherite Sword", "Attack", "Swing" },
	},

	Targeting = {
		Tags = { "Enemy", "Mob", "Boss", "Targetable", "NPC", "Aggro" }, -- CollectionService теги врагов
		FriendlyTags = { "Friendly", "Ally", "Pet", "ShopNPC", "Passive" },
		TeamCheck = true,       -- не атаковать свою команду
		SkipOwner = true,       -- не атаковать то, что принадлежит тебе (атрибут OwnerId/Owner)
		AllowNoHealth = true,   -- атаковать мобов без системы HP, если имя/тег совпал

		-- РАСПОЗНАВАНИЕ ВРАГОВ (дохуя вариантов, EN + RU)
		EnemyNamePatterns = {
			-- EN
			"enemy", "mob", "npc", "hostile", "monster", "boss", "elite",
			"zombie", "husk", "drowned", "skeleton", "stray", "wither",
			"piglin", "zoglin", "pillager", "vindicator", "evoker", "ravager",
			"witch", "spider", "creeper", "slime", "magma_cube", "blaze",
			"ghast", "enderman", "guardian", "shulker", "phantom", "warden",
			"raider", "undead", "fiend", "demon", "goblin", "orc", "troll",
			"ghoul", "wraith", "bandit", "brigand", "assassin", "dark_knight",
			"mob_", "npc_", "boss_", "mini_boss", "enemy_",
			-- RU
			"враг", "моб", "монстр", "босс", "элита", "зомби", "скелет",
			"пиглин", "иллджер", "паук", "крипер", "слайм", "нежить",
			"агрессив", "ворог", "чудовище", "разбойник", "рыцарь тьмы",
		},
		BossNamePatterns = {
			"boss", "босс", "king", "король", "lord", "лорд", "elite",
			"элита", "mini_boss", "miniboss", "warden", "dragon", "дракон",
			"titan", "титан", "overlord", "чемпион", "champion",
		},
		EliteNamePatterns = { "elite", "элита", "mini_boss", "miniboss", "вариант" },
		FriendlyNamePatterns = {
			"friendly", "merchant", "vendor", "торговец", "pet", "helper",
			"ally", "союзник", "shop", "passive", "дружелюб", "мирный",
		},
		BossHPThreshold = 1500,   -- MaxHealth >= этого => босс
		SkipAttributes = {        -- атрибуты => цель пропускается
			Invulnerable = true, God = true, Godmode = true,
			Dead = true, ["无敌"] = true, ["НеТаргетить"] = true,
		},
	},

	-- Режимы позиционирования (куда целиться/ставить)
	-- Root | Feet | Below | Above | Behind | Own | Ring
	PositionModes = { "Root", "Feet", "Below", "Above", "Behind", "Own", "Ring" },
	RingRadius = 3,

	-- Варианты аргов для RemoteEvent/RemoteFunction (ротация)
	-- ArgIndex в настройках ауры = номер (1..7), nil = ротация
}

-- =================================================================
-- 2. НАСТРОЙКИ АУР (базовые; пресеты их переопределяют)
-- =================================================================
CONFIG.Crystal = {
	enabled = false,
	range = 60,
	delay = 0.15,          -- базовая задержка между выстрелами (сек)
	jitter = 0.08,         -- рандом к задержке (анти-детект ритма)
	positionMode = "Ring", -- Root | Feet | Below | Above | Behind | Own | Ring
	priority = "Nearest",  -- Nearest | LowestHP | HighestHP | BossFirst | Finisher | Random | Threat
	filter = "All",        -- All | Players | Mobs | Bosses | NonBoss
	multi = false,         -- true = перебирать всех целей по кругу
	requireLoS = false,    -- требовать прямую видимость (рейкаст)
	finishHP = 0.3,        -- для Finisher: добивать только ниже этого % HP
	disengageHP = nil,     -- ниже этого % своего HP аура выключается
	aggroOnly = false,     -- бить только цели ближе aggroRadius
	aggroRadius = 25,

	placeBlock = true,          -- сначала ставить блок (обсидиан) под кристалл
	blockDelay = 0,             -- пауза между блоком и кристаллом (0 = сразу, кадр-в-кадр)
	twoPhase = true,           -- поставить кристалл -> ударить/взорвать
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
		if worldPos then
			local okv, vp = pcall(function() return cam:WorldToViewportPoint(worldPos) end)
			-- точка перед камерой и в экране — кликаем по ней, иначе в центр
			if okv and vp and vp.Z > 0 and vp.X >= 0 and vp.X <= vs.X and vp.Y >= 0 and vp.Y <= vs.Y then
				sx, sy = vp.X, vp.Y
			end
		end
	end
	-- 1) VirtualInputManager: кнопка 1 = правая (надёжнее всего в экзекьюторах)
	local ok = pcall(function()
		local VIM = game:GetService("VirtualInputManager")
		VIM:SendMouseButtonEvent(sx, sy, 1, true, game, 1)
		task.wait(0.03)
		VIM:SendMouseButtonEvent(sx, sy, 1, false, game, 1)
	end)
	if ok then return true end
	-- 2) хелперы экзекьютора
	if type(mouse2click) == "function" and pcall(mouse2click) then return true end
	if type(mouse2down) == "function" and type(mouse2up) == "function" then
		if pcall(mouse2down) then
			task.wait(0.03)
			pcall(mouse2up)
			return true
		end
	end
	-- 3) последний шанс: тот же VirtualUser, но Button2Down/Up
	return pcall(function()
		VirtualUser:CaptureController()
		VirtualUser:Button2Down(Vector2.new(sx, sy))
		task.wait(0.03)
		VirtualUser:Button2Up(Vector2.new(sx, sy))
	end)
end

-- Прямая видимость до цели
local losParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Exclude

local function hasLoS(fromPos, targetEntry)
	local char = player.Character
	losParams.FilterDescendantsInstances = { char }
	local toPos = targetEntry.root.Position
	local hit = workspace:Raycast(fromPos, toPos - fromPos, losParams)
	if not hit then return true end
	local h = hit.Instance
	local m = targetEntry.model
	if h == targetEntry.root then return true end
	if m:IsA("BasePart") then return h == m end
	local ok, res = pcall(function() return m:IsAncestorOf(h) end)
	return ok and res
end

-- =================================================================
-- 5. СОСТОЯНИЕ
-- =================================================================
local STATE = {
	crystal = { enabled = false, shots = 0, target = nil },
	anchor  = { enabled = false, shots = 0, target = nil },
	warn = nil,       -- текст предупреждения (например, низкое HP)
	warnAt = 0,
}

local PRESET_IDX    = 1
local MULTI_IDX     = 1
local SOURCE_INDEX  = { crystal = 1, anchor = 1, charge = 1, block = 1, attack = 1 }
local ARG_INDEX     = { crystal = 1, anchor = 1, charge = 1, block = 1 }
local FN_INDEX      = { crystal = 1, anchor = 1, charge = 1, block = 1 }

local SOURCES = { crystal = {}, anchor = {}, charge = {}, attack = {} }
local TARGETS = {}

-- =================================================================
-- 6. СКАНЕР ИСТОЧНИКОВ (чем именно ауры могут пользоваться)
-- =================================================================
local function classify(name)
	local n = lowerRU(tostring(name or ""))
	if containsAny(n, P.Exact.crystal) then return "crystal" end
	if containsAny(n, P.Exact.charge)  then return "charge"  end
	if containsAny(n, P.Exact.anchor)  then return "anchor"  end
	if containsAny(n, P.Exact.block)   then return "block"   end
	if containsAny(n, P.Charge) then return "charge" end
	if containsAny(n, P.Anchor) then return "anchor" end
	if containsAny(n, P.Crystal) then return "crystal" end
	if containsAny(n, P.Block) then return "block" end
	if containsAny(n, P.Attack) then return "attack" end
	return nil
end

local function scoreSource(name, srcType, exact)
	local sc = 0
	if exact then sc = sc + 100 end
	if srcType == "tool" then sc = sc + 25
	elseif srcType == "remoteEvent" then sc = sc + 20
	elseif srcType == "remoteFunction" then sc = sc + 15
	elseif srcType == "prompt" then sc = sc + 10
	elseif srcType == "module" then sc = sc + 5 end
	return sc
end

local function findToolByName(name)
	local backpack = player:FindFirstChild("Backpack")
	local char = player.Character
	local n = lowerRU(name)
	for _, container in ipairs({ backpack, char }) do
		if container then
			for _, c in container:GetChildren() do
				if c:IsA("Tool") and lowerRU(c.Name) == n then return c end
			end
		end
	end
	return nil
end

local function rescanSources()
	local backpack = player:FindFirstChild("Backpack")
	local char = player.Character
	local lists = { crystal = {}, anchor = {}, charge = {}, block = {}, attack = {} }
	local seen = {}

	local function add(phase, src)
		if not phase or not lists[phase] then return end
		-- анчор: ТОЛЬКО Tool (никаких RemoteEvent/промптов/модулей)
		if phase == "anchor" and src.type ~= "tool" then return end
		if seen[src.inst] then return end
		seen[src.inst] = true
		src.score = scoreSource(src.name, src.type, src.exact)
		table.insert(lists[phase], src)
	end

	local function considerTool(tool, live)
		local phase = classify(tool.Name)
		if not phase then return end
		if live then
			add(phase, { type = "tool", inst = tool, name = tool.Name, exact = isExact(tool.Name, phase) })
			return
		end
		-- шаблон: клонируем в рюкзак (если разрешено и такого ещё нет)
		if not CONFIG.Scan.CloneTemplates then return end
		if phase == "attack" and not CONFIG.Scan.CloneAttack then return end -- без спама оружием
		if findToolByName(tool.Name) then return end
		if not live and tool.Parent == workspace and not CONFIG.Scan.CloneFromWorkspace then return end
		local ok, clone = pcall(function() return tool:Clone() end)
		if not ok or not clone then return end
		clone.Parent = backpack
		print(("[Auras] Шаблон склонирован в рюкзак: %s"):format(clone.Name))
		add(phase, { type = "tool", inst = clone, name = clone.Name, exact = isExact(clone.Name, phase) })
	end

	-- 1) живые Tool'ы
	for _, container in ipairs({ backpack, char }) do
		if container then
			for _, d in container:GetChildren() do
				if d:IsA("Tool") then considerTool(d, true) end
			end
		end
	end

	-- 2) шаблоны Tool'ы в ReplicatedStorage (+ workspace, если включено)
	local function scanToolTemplates(root)
		if not root then return end
		for _, d in root:GetDescendants() do
			if d:IsA("Tool") then considerTool(d, false) end
		end
	end
	scanToolTemplates(ReplicatedStorage)
	pcall(function() scanToolTemplates(game:GetService("StarterPack")) end) -- Tool'ы на старте (анчор может лежать тут)
	if CONFIG.Scan.CloneFromWorkspace then scanToolTemplates(workspace) end

	-- 3) RemoteEvent / RemoteFunction / ProximityPrompt / ModuleScript
	local function scanServices(root)
		if not root then return end
		for _, d in root:GetDescendants() do
			if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") then
				local phase = classify(d.Name)
				if phase then
					local t = d:IsA("RemoteEvent") and "remoteEvent" or "remoteFunction"
					add(phase, { type = t, inst = d, name = d.Name, exact = isExact(d.Name, phase) })
				end
			elseif d:IsA("ProximityPrompt") then
				local label = tostring(d.ActionText or "") .. " " .. tostring(d.ObjectText or "")
				local phase = classify(label)
				if phase then
					add(phase, {
						type = "prompt", inst = d,
						name = (d.ActionText ~= "" and d.ActionText) or d.Name,
						exact = isExact(label, phase),
					})
				end
			elseif d:IsA("ModuleScript") then
				local phase = classify(d.Name)
				if phase and CONFIG.Scan.RequireModules then
					local ok, mod = pcall(require, d)
					if ok and type(mod) == "table" then
						local fns = {}
						for k, v in pairs(mod) do
							if type(v) == "function" then fns[#fns + 1] = tostring(k) end
						end
						if #fns > 0 then
							add(phase, {
								type = "module", inst = d, mod = mod, fns = fns,
								name = d.Name, exact = isExact(d.Name, phase),
							})
						end
					end
				end
			end
		end
	end
	scanServices(ReplicatedStorage)
	scanServices(workspace)

	for phase, list in pairs(lists) do
		table.sort(list, function(a, b) return a.score > b.score end)
		SOURCES[phase] = list
		if (SOURCE_INDEX[phase] or 1) > #list then SOURCE_INDEX[phase] = 1 end
	end
end

local function sourceReport()
	for _, phase in ipairs({ "crystal", "anchor", "charge", "block", "attack" }) do
		local names = {}
		for _, s in ipairs(SOURCES[phase]) do
			names[#names + 1] = s.type .. ":" .. s.name
		end
		print(("[Auras] %-7s → %d | %s"):format(phase, #SOURCES[phase], table.concat(names, ", ")))
	end
end

local function sourceValid(src)
	if not src or not src.inst then return false end
	local ok, res = pcall(function() return src.inst.Parent ~= nil end)
	return ok and res
end

local function pickSource(phase)
	local list = SOURCES[phase]
	if not list or #list == 0 then return nil end
	local start = SOURCE_INDEX[phase] or 1
	for i = 0, #list - 1 do
		local idx = ((start - 1 + i) % #list) + 1
		if sourceValid(list[idx]) then
			SOURCE_INDEX[phase] = idx
			return list[idx]
		end
	end
	return nil
end

-- ДИАГНОСТИКА: всё, что игра предлагает (инструменты, ремоуты, структура)
local function dumpWorld()
	pcall(function()
		local tools, re, rf = {}, {}, {}
		local function scan(root)
			if not root then return end
			for _, d in root:GetDescendants() do
				if d:IsA("Tool") then
					tools[#tools + 1] = d.Name
				elseif d:IsA("RemoteEvent") then
					re[#re + 1] = d.Name
				elseif d:IsA("RemoteFunction") then
					rf[#rf + 1] = d.Name
				end
			end
		end
		scan(ReplicatedStorage)
		scan(player:FindFirstChild("Backpack"))
		scan(player.Character)

		local parts = {}
		parts[#parts + 1] = ("ИТОГО Tool=%d RemoteEvent=%d RemoteFunction=%d"):format(#tools, #re, #rf)
		local function add(tag, arr)
			for _, n in ipairs(arr) do parts[#parts + 1] = tag .. ": " .. n end
		end
		add("Tool", tools)
		add("RemoteEvent", re)
		add("RemoteFunction", rf)

		-- структура ReplicatedStorage (2 уровня) — видно системы предметов
		for _, d in ReplicatedStorage:GetChildren() do
			parts[#parts + 1] = "RS: " .. d.Name .. " (" .. d.ClassName .. ")"
			if d:IsA("Folder") or d:IsA("Model") then
				local kids = d:GetChildren()
				for i = 1, math.min(#kids, 30) do
					parts[#parts + 1] = "   └ " .. kids[i].Name .. " (" .. kids[i].ClassName .. ")"
				end
				if #kids > 30 then
					parts[#parts + 1] = "   └ ...ещё " .. (#kids - 30)
				end
			end
		end

		-- печать в консоль (первые 150 строк)
		for i = 1, math.min(#parts, 150) do
			print("[Auras] DUMP " .. parts[i])
		end
		if #parts > 150 then
			print(("[Auras] DUMP ...ещё %d строк — они в буфере обмена"):format(#parts - 150))
		end

		-- копируем ВСЁ в буфер обмена: жмёшь Ctrl+V и вставляешь мне
		if type(setclipboard) == "function" then
			if pcall(setclipboard, "[Auras DUMP]\n" .. table.concat(parts, "\n")) then
				print("[Auras] DUMP скопирован в буфер обмена — вставь мне (Ctrl+V)")
			end
		end
	end)
end

-- =================================================================
-- 7. СКАНЕР ЦЕЛЕЙ (гуманоиды и не только)
-- =================================================================
local function buildEntry(model)
	if not model or model == player.Character then return nil end

	-- humanoid: прямой потомок или глубоко внутри (вложенные риги)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		humanoid = model:FindFirstChildWhichIsA("Humanoid", true)
	end

	-- корень: много вариантов (R15, R6, кастомные риги, Part-мобы)
	local root = nil
	if humanoid and humanoid.RootPart then root = humanoid.RootPart end
	if not root then root = model:FindFirstChild("HumanoidRootPart") end
	if not root then root = model:FindFirstChild("Torso") end
	if not root then root = model:FindFirstChild("RootPart") end
	if not root then root = model:FindFirstChild("UpperTorso") end
	if not root then root = model.PrimaryPart end
	if not root and humanoid then root = humanoid:FindFirstChildWhichIsA("BasePart", true) end
	if not root then root = model:FindFirstChildWhichIsA("BasePart", true) end
	if not root and model:IsA("BasePart") then root = model end -- Part-моб (сама деталь с HP)
	if not root then return nil end

	-- HP: humanoid -> атрибуты -> Value-объекты
	local health, maxHealth = nil, nil
	if humanoid then
		health = humanoid.Health
		maxHealth = humanoid.MaxHealth
	end
	if health == nil then health = readNumber(model, { "Health", "HP", "health", "hp" }) end
	if maxHealth == nil then maxHealth = readNumber(model, { "MaxHealth", "MaxHP", "Health", "HP" }) end
	if maxHealth and health and health > maxHealth then maxHealth = health end

	local pc = Players:GetPlayerFromCharacter(model)
	local isPlayer = pc ~= nil

	-- "узнается ли цель как враг": humanoid ИЛИ hp ИЛИ имя/тег
	local recognized = humanoid ~= nil
		or health ~= nil
		or nameMatches(model.Name, P.Enemy)
		or hasAnyTag(model, CONFIG.Targeting.Tags)

	-- босс: имя | атрибут | тег | огромный MaxHealth
	local isBoss = nameMatches(model.Name, P.Boss)
		or model:GetAttribute("IsBoss") == true
		or model:GetAttribute("IsBoss") == 1
		or model:GetAttribute("Boss") == true
		or hasAnyTag(model, { "Boss", "boss" })
		or (maxHealth ~= nil and maxHealth >= CONFIG.Targeting.BossHPThreshold)

	local isElite = nameMatches(model.Name, P.Elite) or hasAnyTag(model, { "Elite", "elite" })

	return {
		model = model,
		root = root,
		humanoid = humanoid,
		health = health,
		maxHealth = maxHealth,
		isPlayer = isPlayer,
		player = pc,
		isBoss = isBoss,
		isElite = isElite,
		recognized = recognized,
		name = model.Name,
	}
end

local function consider(inst, out, seen)
	local model = nil
	if inst:IsA("Model") then
		model = inst
	elseif inst:IsA("Humanoid") then
		model = inst.Parent
	elseif inst:IsA("BasePart") then
		-- "Part-моб": сама деталь с атрибутом Health/HP
		local hp = inst:GetAttribute("Health") or inst:GetAttribute("HP")
		if type(hp) == "number" then model = inst end
	end
	if not model then return end
	if model == workspace then return end
	if not (model:IsA("Model") or model:IsA("BasePart")) then return end
	if seen[model] then return end
	seen[model] = true
	local e = buildEntry(model)
	if e then out[#out + 1] = e end
end

local function rescanTargets(full)
	local out, seen = {}, {}
	pcall(function()
		for _, d in workspace:GetChildren() do
			consider(d, out, seen)
		end
		if full then
			for _, d in workspace:GetDescendants() do
				if d:IsA("Model") or d:IsA("Humanoid") or d:IsA("BasePart") then
					consider(d, out, seen)
				end
			end
		end
	end)

	-- дедупликация по корню (вложенные модели одного моба)
	local byRoot, dedup = {}, {}
	for _, e in ipairs(out) do
		if e.root then
			if not byRoot[e.root] then
				byRoot[e.root] = true
				dedup[#dedup + 1] = e
			end
		else
			dedup[#dedup + 1] = e
		end
	end
	TARGETS = dedup
end

-- =================================================================
-- 8. ВЫБОР ЦЕЛИ
-- =================================================================
local function getSettings(kind)
	local base = (kind == "crystal") and CONFIG.Crystal or CONFIG.Anchor
	local preset = CONFIG.Presets[PRESET_IDX] or {}
	local s = {}
	for k, v in pairs(base) do s[k] = v end
	for k, v in pairs(preset) do
		if k ~= "name" then s[k] = v end
	end
	return s
end

local function passFilter(e, filter)
	if filter == "Players" then return e.isPlayer end
	if filter == "Mobs" then return not e.isPlayer end
	if filter == "Bosses" then return e.isBoss or e.isElite end
	if filter == "NonBoss" then return not (e.isBoss or e.isElite) end
	return true -- All
end

local function isValidTarget(e, s, ownRoot)
	local tc = CONFIG.Targeting
	local model = e.model

	if model == player.Character then return false end
	if e.isPlayer and e.player == player then return false end

	-- своя команда
	if tc.TeamCheck and e.isPlayer and e.player then
		if player.Team and e.player.Team == player.Team then return false end
	end

	-- дружественные по имени / тегу
	if nameMatches(model.Name, P.Friend) then return false end
	if hasAnyTag(model, tc.FriendlyTags) then return false end

	-- пропуск по атрибутам (бессмертие и т.п.)
	for attr, val in pairs(tc.SkipAttributes) do
		if model:GetAttribute(attr) == val then return false end
	end

	-- свои призывы/петы
	if tc.SkipOwner then
		local own = model:GetAttribute("OwnerId")
			or model:GetAttribute("OwnerUserId")
			or model:GetAttribute("Owner")
		if own == player.UserId or own == player then return false end
	end

	-- живость
	if e.health and e.health <= 0 then return false end
	if e.humanoid and e.humanoid.Health <= 0 then return false end
	if not e.root or not e.root.Parent then return false end

	-- "необычные гуманоиды" без HP: пускаем только если имя/тег совпал
	if not e.humanoid and not e.health and not e.recognized then
		if not tc.AllowNoHealth then return false end
	end

	if not passFilter(e, s.filter) then return false end

	local dist = (e.root.Position - ownRoot.Position).Magnitude
	if dist > (s.range or 60) then return false end

	if s.aggroOnly and dist > (s.aggroRadius or 25) then return false end
	if s.requireLoS and not hasLoS(ownRoot.Position, e) then return false end

	return true, dist
end

local function selectTarget(s, ownRoot)
	local cands = {}
	for _, e in ipairs(TARGETS) do
		local ok, dist = isValidTarget(e, s, ownRoot)
		if ok then
			e._dist = dist
			cands[#cands + 1] = e
		end
	end
	if #cands == 0 then return nil end

	local prio = s.priority or "Nearest"

	if prio == "Random" then
		return cands[math.random(#cands)]
	end

	if prio == "Finisher" then
		local th = s.finishHP or 0.3
		local fin = {}
		for _, e in ipairs(cands) do
			local ratio = (e.health and e.maxHealth and e.maxHealth > 0)
				and (e.health / e.maxHealth) or 1
			if ratio <= th then fin[#fin + 1] = e end
		end
		if #fin == 0 then return nil end
		table.sort(fin, function(a, b)
			return (a.health or 0) < (b.health or 0)
		end)
		cands = fin
	elseif prio == "LowestHP" then
		table.sort(cands, function(a, b)
			return (a.health or math.huge) < (b.health or math.huge)
		end)
	elseif prio == "HighestHP" then
		table.sort(cands, function(a, b)
			return (a.health or 0) > (b.health or 0)
		end)
	elseif prio == "BossFirst" then
		table.sort(cands, function(a, b)
			local ba = (a.isBoss or a.isElite) and 0 or 1
			local bb = (b.isBoss or b.isElite) and 0 or 1
			if ba ~= bb then return ba < bb end
			return a._dist < b._dist
		end)
	elseif prio == "Threat" then
		-- ближе + толще = выше приоритет
		table.sort(cands, function(a, b)
			local sa = a._dist - math.min(a.maxHealth or 0, 20000) * 0.002
			local sb = b._dist - math.min(b.maxHealth or 0, 20000) * 0.002
			return sa < sb
		end)
	else -- Nearest
		table.sort(cands, function(a, b) return a._dist < b._dist end)
	end

	if s.multi then
		MULTI_IDX = (MULTI_IDX % #cands) + 1
		return cands[MULTI_IDX]
	end
	return cands[1]
end

-- Куда именно ставить/целиться
local function resolvePosition(s, t)
	local mode = s.positionMode or "Root"
	local p = t.root.Position
	local look = t.root.CFrame.LookVector
	if mode == "Feet" then return p - Vector3.new(0, 3, 0) end
	if mode == "Below" then return p - Vector3.new(0, 5, 0) end
	if mode == "Above" then return p + Vector3.new(0, 4, 0) end
	if mode == "Behind" then return p - look * 2.5 end
	if mode == "Own" then
		local own = getOwnRoot()
		return own and own.Position or p
	end
	if mode == "Ring" then
		local a = math.random() * math.pi * 2
		local r = math.random() * (CONFIG.RingRadius or 3)
		return p + Vector3.new(math.cos(a) * r, -2, math.sin(a) * r)
	end
	return p -- Root
end

-- =================================================================
-- 9. АКТИВАЦИЯ ИСТОЧНИКОВ (дохуя вариантов)
-- =================================================================
local ARG_VARIANTS = {
	function(t, pos) return { pos } end,
	function(t, pos) return { t.model } end,
	function(t, pos) return { t.model, pos } end,
	function(t, pos) return { pos, t.model } end,
	function(t, pos) return { t.root } end,
	function(t, pos) return { pos, t.root } end,
	function(t, pos) return {} end,
}

local function nextArgs(phase, t, pos, s)
	local idx = s.argIndex
	if not idx then
		idx = ARG_INDEX[phase] or 1
		ARG_INDEX[phase] = (idx % #ARG_VARIANTS) + 1
	end
	local v = ARG_VARIANTS[((idx - 1) % #ARG_VARIANTS) + 1]
	return v(t, pos)
end

local function invokeRF(rf, args, timeout)
	timeout = timeout or 2
	local done, result = false, false
	task.spawn(function()
		local ok = pcall(function() return rf:InvokeServer(table.unpack(args)) end)
		result = ok
		done = true
	end)
	local t0 = os.clock()
	while not done and os.clock() - t0 < timeout do
		task.wait(0.05)
	end
	return done and result
end

local function activateSource(src, phase, t, pos, s)
	if not sourceValid(src) then return false end

	if src.type == "tool" then
		local ok = ensureEquipped(src.inst)
		if not ok then return false end
		local mode = s.toolClickMode or "Activate"
		if s.aimCamera then aimCamera(pos) end
		-- СТАВИТЬ (кристалл/анчор/блок/заряд) = ПКМ; ЛКМ в этой игре ломает!
		-- Удар (фаза attack) остаётся ЛКМ — его и нужно ломать/подрывать.
		local placePhase = (phase == "crystal" or phase == "anchor" or phase == "block" or phase == "charge")
		if placePhase and (s.placeClick or "Right") == "Right" then
			return pressRightClick(pos)
		end
		if mode == "VirtualClick" or mode == "Both" then
			virtualClick(pos)
		end
		local fired = pcall(function() src.inst:Activate() end)
		if not fired and mode == "VirtualClick" then
			fired = pcall(function() src.inst:Activate() end)
		end
		return fired

	elseif src.type == "remoteEvent" then
		local args = nextArgs(phase, t, pos, s)
		return pcall(function()
			src.inst:FireServer(table.unpack(args))
		end)

	elseif src.type == "remoteFunction" then
		local args = nextArgs(phase, t, pos, s)
		return invokeRF(src.inst, args, s.rfTimeout or 2)

	elseif src.type == "prompt" then
		local ok = pcall(function() src.inst:InputHoldBegin() end)
		if not ok then return false end
		local hold = src.inst.HoldDuration or 0.5
		if hold > 0 then task.wait(math.min(hold, 3)) end
		pcall(function() src.inst:InputHoldEnd() end)
		return true

	elseif src.type == "module" then
		if not src.mod then
			local ok, mod = pcall(require, src.inst)
			if ok and type(mod) == "table" then src.mod = mod end
		end
		if not src.mod or not src.fns or #src.fns == 0 then return false end
		local idx = ((FN_INDEX[phase] or 0) % #src.fns) + 1
		FN_INDEX[phase] = idx
		local fn = src.mod[src.fns[idx]]
		if type(fn) ~= "function" then return false end
		-- пробуем варианты: fn(args...) -> fn(mod, args...) -> fn()
		for _ = 1, #ARG_VARIANTS do
			local args = nextArgs(phase, t, pos, s)
			if pcall(fn, table.unpack(args)) then return true end
			if pcall(fn, src.mod, table.unpack(args)) then return true end
		end
		return pcall(fn)
	end
	return false
end

-- Поиск только что поставленного кристалла (для добивания)
local CRYSTAL_FIND_CACHE = { at = 0, part = nil }
local function findPlacedCrystal(pos)
	local now = os.clock()
	if now - CRYSTAL_FIND_CACHE.at < 0.35 then
		return CRYSTAL_FIND_CACHE.part
	end
	local best, bestD = nil, 8
	pcall(function()
		for _, d in workspace:GetDescendants() do
			if d:IsA("BasePart") or d:IsA("Model") then
				local n = lowerRU(d.Name)
				if containsAny(n, P.Crystal) then
					local cp = nil
					if d:IsA("BasePart") then
						cp = d.Position
					elseif d.PrimaryPart then
						cp = d.PrimaryPart.Position
					end
					if cp then
						local dist = (cp - pos).Magnitude
						if dist < bestD then best, bestD = d, dist end
					end
				end
			end
		end
	end)
	CRYSTAL_FIND_CACHE = { at = now, part = best }
	return best
end

-- Удар/подрыв после постановки кристалла
local function hitPlaced(s, t, pos)
	local target = pos
	if s.twoPhaseMode == "findAndSwing" then
		local part = findPlacedCrystal(pos)
		if part then
			target = part:IsA("BasePart") and part.Position
				or (part.PrimaryPart and part.PrimaryPart.Position) or pos
		end
	end
	local atk = pickSource("attack")
	if atk and atk.type == "tool" then
		local ok = ensureEquipped(atk.inst)
		if ok then
			if s.aimCamera then aimCamera(target) end
			local mode = s.toolClickMode or "Activate"
			if mode == "VirtualClick" or mode == "Both" then virtualClick(target) end
			return pcall(function() atk.inst:Activate() end)
		end
	-- фолбэк: бьём тем же инструментом
	elseif s.toolClickMode ~= "none" then
		local src = pickSource("crystal")
		if src and src.type == "tool" then
			local ok = ensureEquipped(src.inst)
			if ok then
				if s.aimCamera then aimCamera(target) end
				return pcall(function() src.inst:Activate() end)
			end
		end
	end
	return false
end

local function fireCrystal(s, t, pos)
	local src = pickSource("crystal")
	if not src then return false end
	-- фаза блока: сначала ставим обсидиан/блок под кристалл
	if s.placeBlock then
		local bsrc = pickSource("block")
		if bsrc then
			activateSource(bsrc, "block", t, pos, s)
			task.wait(s.blockDelay or 0.12)
		end
	end
	local ok = activateSource(src, "crystal", t, pos, s)
	STATE.crystal.shots = STATE.crystal.shots + 1
	if ok and s.twoPhase and s.twoPhaseMode ~= "none" then
		task.wait(s.twoPhaseDelay or 0.12)
		hitPlaced(s, t, pos)
	end
	return ok
end

local function fireAnchor(s, t, pos)
	local src = pickSource("anchor")
	if not src then return false end
	local seq = s.sequence or "auto"
	if seq == "auto" then
		if #SOURCES.charge > 0 and #SOURCES.attack > 0 then
			seq = "place_charge_attack" -- поставить -> зарядить светокамнем -> ударить (взрыв)
		elseif #SOURCES.charge > 0 then
			seq = "charge_then_use"
		elseif s.autoDouble then
			seq = "use_twice"
		else
			seq = "single"
		end
	end
	local ct = s.chargeTime or 0.6

	if seq == "place_charge_attack" then
		activateSource(src, "anchor", t, pos, s) -- 1) поставить анчор
		task.wait(ct)
		local csrc = pickSource("charge")
		if csrc then
			activateSource(csrc, "charge", t, pos, s) -- 2) зарядить светокамнем
			task.wait(ct)
		end
		-- 3) ударить по анчору -> взрыв
		local atk = pickSource("attack")
		if atk and atk.type == "tool" and ensureEquipped(atk.inst) then
			if s.aimCamera then aimCamera(pos) end
			pcall(function() atk.inst:Activate() end)
		else
			activateSource(src, "anchor", t, pos, s)
		end
	elseif seq == "charge_then_use" then
		local csrc = pickSource("charge")
		if csrc then
			activateSource(csrc, "charge", t, pos, s)
			task.wait(ct)
		end
		activateSource(src, "anchor", t, pos, s)
	elseif seq == "use_twice" then
		activateSource(src, "anchor", t, pos, s)
		task.wait(ct)
		activateSource(src, "anchor", t, pos, s)
	else
		activateSource(src, "anchor", t, pos, s)
	end
	STATE.anchor.shots = STATE.anchor.shots + 1
	return true
end

-- =================================================================
-- 10. HUD
-- =================================================================
local HUD = {}

local function buildHUD()
	local pg = player:WaitForChild("PlayerGui", 10)
	if not pg then return end

	local sg = Instance.new("ScreenGui")
	sg.Name = "AuraHUD"
	sg.ResetOnSpawn = false
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	sg.Parent = pg

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromOffset(300, 210)
	frame.Position = UDim2.fromOffset(12, 12)
	frame.BackgroundColor3 = Color3.fromRGB(18, 18, 26)
	frame.BackgroundTransparency = 0.25
	frame.BorderSizePixel = 0
	frame.Parent = sg
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)
	local stroke = Instance.new("UIStroke", frame)
	stroke.Color = Color3.fromRGB(130, 100, 255)
	stroke.Transparency = 0.4

	-- HUD можно перетаскивать за любую точку (мышь/палец)
	do
		local dragging, dragStart, startPos
		frame.InputBegan:Connect(function(input)
			local t = input.UserInputType
			if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
				dragging = true
				dragStart = input.Position
				startPos = frame.Position
			end
		end)
		frame.InputEnded:Connect(function(input)
			local t = input.UserInputType
			if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
				dragging = false
			end
		end)
		UserInputService.InputChanged:Connect(function(input)
			if not dragging then return end
			if not frame.Parent then dragging = false return end
			local t = input.UserInputType
			if t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.Touch then
				local delta = input.Position - dragStart
				frame.Position = UDim2.new(
					startPos.X.Scale, startPos.X.Offset + delta.X,
					startPos.Y.Scale, startPos.Y.Offset + delta.Y)
			end
		end)
	end

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -16, 0, 24)
	title.Position = UDim2.fromOffset(8, 6)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 15
	title.TextColor3 = Color3.fromRGB(195, 165, 255)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "CRYSTAL / ANCHOR AURAS"
	title.Parent = frame

	local function line(y, key)
		local l = Instance.new("TextLabel")
		l.Size = UDim2.new(1, -16, 0, 18)
		l.Position = UDim2.fromOffset(8, y)
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.Gotham
		l.TextSize = 13
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.TextColor3 = Color3.fromRGB(225, 225, 235)
		l.Text = ""
		l.Parent = frame
		HUD[key] = l
		return l
	end

	line(36, "crystal")
	line(56, "anchor")
	line(80, "preset")
	line(100, "srcC")
	line(120, "srcA")
	line(144, "target")
	line(164, "info")
	line(184, "warn")
	HUD.gui = sg
end

local function updateHUD()
	if not HUD.gui or not HUD.gui.Parent then return end

	HUD.crystal.Text = ("[Z] Кристалл: %s   выстрелов: %d"):format(
		STATE.crystal.enabled and "ВКЛ" or "выкл", STATE.crystal.shots)
	HUD.crystal.TextColor3 = STATE.crystal.enabled
		and Color3.fromRGB(120, 255, 160) or Color3.fromRGB(140, 140, 150)

	HUD.anchor.Text = ("[G] Анчор:    %s   выстрелов: %d"):format(
		STATE.anchor.enabled and "ВКЛ" or "выкл", STATE.anchor.shots)
	HUD.anchor.TextColor3 = STATE.anchor.enabled
		and Color3.fromRGB(120, 255, 160) or Color3.fromRGB(140, 140, 150)

	HUD.preset.Text = ("Пресет: %s  (H)"):format(CONFIG.Presets[PRESET_IDX].name)

	local cs = pickSource("crystal")
	HUD.srcC.Text = ("Кристалл источник: %s  (K)"):format(
		cs and (cs.type .. " / " .. cs.name) or "НЕ НАЙДЕН")
	HUD.srcC.TextColor3 = cs and Color3.fromRGB(225, 225, 235)
		or Color3.fromRGB(255, 120, 120)

	local as = pickSource("anchor")
	HUD.srcA.Text = ("Анчор источник:    %s  (K)"):format(
		as and (as.type .. " / " .. as.name) or "НЕ НАЙДЕН")
	HUD.srcA.TextColor3 = as and Color3.fromRGB(225, 225, 235)
		or Color3.fromRGB(255, 120, 120)

	local tgt = STATE.crystal.target or STATE.anchor.target
	if tgt and tgt.root and tgt.root.Parent then
		local own = getOwnRoot()
		local d = own and math.floor((tgt.root.Position - own.Position).Magnitude) or 0
		local hp = tgt.health and math.floor(tgt.health) or "?"
		local mx = tgt.maxHealth and math.floor(tgt.maxHealth) or "?"
		HUD.target.Text = ("Цель: %s  [%d м]  HP %s/%s%s"):format(
			tgt.name, d, hp, mx,
			(tgt.isBoss and "  [БОСС]") or (tgt.isElite and "  [ЭЛИТА]") or "")
	else
		HUD.target.Text = "Цель: —"
	end

	HUD.info.Text = ("Источников: C:%d A:%d бл:%d зар:%d уд:%d | цель(ей): %d | J — HUD"):format(
		#SOURCES.crystal, #SOURCES.anchor, #SOURCES.block, #SOURCES.charge, #SOURCES.attack, #TARGETS)

	if STATE.warn and os.clock() - STATE.warnAt < 5 then
		HUD.warn.Text = STATE.warn
		HUD.warn.TextColor3 = Color3.fromRGB(255, 90, 90)
	else
		HUD.warn.Text = ""
	end
end

-- =================================================================
-- 11. КЛАВИШИ
-- =================================================================
GENV.AURA_CONNS[#GENV.AURA_CONNS + 1] = UserInputService.InputBegan:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
	-- gpe НЕ проверяем: игры часто перехватывают наши клавиши (gpe=true),
	-- из-за этого раньше ничего не реагировало. Реагируем, только если
	-- открыт чат / поле ввода текста.
	if UserInputService:GetFocusedTextBox() then return end
	local kc = input.KeyCode
	local K = CONFIG.Keys

	if kc == K.ToggleCrystal or kc == K.ToggleCrystalAlt then
		STATE.crystal.enabled = not STATE.crystal.enabled
		STATE.crystal.shots = 0
		STATE.crystal.target = nil
		print(("[Auras] Crystal Aura: %s"):format(STATE.crystal.enabled and "ВКЛ" or "выкл"))
	elseif kc == K.ToggleAnchor or kc == K.ToggleAnchorAlt then
		STATE.anchor.enabled = not STATE.anchor.enabled
		STATE.anchor.shots = 0
		STATE.anchor.target = nil
		print(("[Auras] Anchor Aura: %s"):format(STATE.anchor.enabled and "ВКЛ" or "выкл"))
	elseif kc == K.CyclePreset then
		PRESET_IDX = (PRESET_IDX % #CONFIG.Presets) + 1
		MULTI_IDX = 1
		STATE.warn = nil
		print(("[Auras] Пресет: %s"):format(CONFIG.Presets[PRESET_IDX].name))
	elseif kc == K.CycleSource then
		for _, phase in ipairs({ "crystal", "anchor", "charge", "block", "attack" }) do
			local n = #SOURCES[phase]
			if n > 0 then
				SOURCE_INDEX[phase] = ((SOURCE_INDEX[phase] or 1) % n) + 1
			end
		end
		sourceReport()
	elseif kc == K.ToggleHUD and HUD.gui then
		HUD.gui.Enabled = not HUD.gui.Enabled
	end
end)

-- =================================================================
-- 12. ГЛАВНЫЕ ЦИКЛЫ
-- =================================================================
local function setWarn(msg)
	STATE.warn = msg
	STATE.warnAt = os.clock()
end

local function auraLoop(kind)
	while true do
		if not alive() then return end
		local st = STATE[kind]
		local s = getSettings(kind)
		CURRENT_SETTINGS = s

		if st.enabled then
			-- отступ при низком HP
			local ratio = myHpRatio()
			if s.disengageHP and ratio and ratio < s.disengageHP then
				st.enabled = false
				setWarn(("HP %.0f%% < %.0f%% — %s аура выключена"):format(
					ratio * 100, s.disengageHP * 100,
					kind == "crystal" and "Crystal" or "Anchor"))
			else
				local ownRoot = getOwnRoot()
				if ownRoot then
					local t = selectTarget(s, ownRoot)
					st.target = t
					if t then
						local pos = resolvePosition(s, t)
						local ok = pcall(function()
							if kind == "crystal" then
								fireCrystal(s, t, pos)
							else
								fireAnchor(s, t, pos)
							end
						end)
						if not ok then
							-- ошибка активации → пробуем следующий источник
							local n = #SOURCES[kind]
							if n > 1 then
								SOURCE_INDEX[kind] = ((SOURCE_INDEX[kind] or 1) % n) + 1
							end
						end
						task.wait((s.delay or 0.15) + math.random() * (s.jitter or 0))
					else
						task.wait(0.12)
					end
				else
					task.wait(0.3)
				end
			end
		else
			st.target = nil
			task.wait(0.1)
		end
	end
end

task.spawn(function()
	local ok, err = xpcall(function() auraLoop("crystal") end, debug.traceback)
	if not ok then showFatal(err) end
end)
task.spawn(function()
	local ok, err = xpcall(function() auraLoop("anchor") end, debug.traceback)
	if not ok then showFatal(err) end
end)

-- сканы: работают только пока включена хоть одна аура (иначе спим — оптимизация)
task.spawn(function()
	local tFull, tSrc = 0, 0
	while true do
		if not alive() then return end
		local anyOn = STATE.crystal.enabled or STATE.anchor.enabled
		if anyOn then
			local now = os.clock()
			local full = (now - tFull) >= CONFIG.Scan.FullInterval
			if full then tFull = now end
			pcall(rescanTargets, full)
			if (now - tSrc) >= CONFIG.Scan.SourceRescan then
				tSrc = now
				pcall(rescanSources)
				pcall(sourceReport)
			end
			task.wait(CONFIG.Scan.Interval)
		else
			task.wait(0.5) -- всё выключено: ничего не сканируем и не трогаем
		end
	end
end)

-- HUD-апдейт
task.spawn(function()
	while true do
		if not alive() then return end
		pcall(updateHUD)
		task.wait(0.2)
	end
end)

-- =================================================================
-- 13. СТАРТ (ПЛАВНЫЙ: по шагам с паузами, ничего не рвётся разом)
-- =================================================================
pcall(function() VirtualUser:CaptureController() end)
do
	local ok, err = xpcall(buildHUD, debug.traceback)
	if not ok then showFatal(err) end
end
pcall(updateHUD)
print("[Auras] шаг 1/4: HUD готов — жми Z (кристалл) / G (анчор)")

task.delay(0.4, function()
	pcall(rescanTargets, true)
	print("[Auras] шаг 2/4: целей найдено: " .. #TARGETS)
	task.delay(0.4, function()
		pcall(rescanSources)
		pcall(sourceReport)
		print("[Auras] шаг 3/4: источники просканированы")
		task.delay(0.5, function()
			if CONFIG.Scan.DumpAll then pcall(dumpWorld) end
			print(("[Auras] шаг 4/4: старт завершён. Пресетов: %d | Z/G/H/K/J"):format(#CONFIG.Presets))
		end)
	end)
end)

end, showFatal)
if not __ok then showFatal(__err) end
