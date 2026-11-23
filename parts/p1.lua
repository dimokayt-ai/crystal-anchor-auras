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
		ExportLog     = Enum.KeyCode.L,   -- скопировать лог действий (датасет) в буфер
		ToggleKillAura = Enum.KeyCode.N,  -- Kill Aura (авто-удар мечом/мейсом)
		ToggleMace    = Enum.KeyCode.M,   -- Mace Helper (прыжок+удар на падении)
	},

	Scan = {
		Interval      = 0.5,   -- как часто обновлять список целей (сек)
		FullInterval  = 2.0,   -- полный обход workspace (сек)
		SourceRescan  = 5.0,   -- перескан источников: tools/remotes (сек)
		CloneTemplates    = false, -- АВТО-ВЫДАЧА ВЫКЛ: предметы сами не выдаются
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
		TeamCheck = false,      -- false = бить по ВСЕМ игрокам (включая "свою команду")
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
	blockDelay = 0,             -- пауза между блоком и кристаллом (0 = сразу)
	blockReuse = 4,             -- не ставить обсидиан заново N секунд, если точка та же
	twoPhase = true,           -- поставить кристалл -> ударить/взорвать
	twoPhaseMode = "swing",    -- swing | findAndSwing | none
	twoPhaseDelay = 0,         -- пауза между постановкой и ударом (0 = сразу)
	aimCamera = false,         -- без аима, как раньше
	smoothAim = 0.35,
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
