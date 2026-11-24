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
		-- игроки сканируются быстро, без полного GetDescendants
		for _, pl in Players:GetPlayers() do
			if pl ~= player and pl.Character then consider(pl.Character, out, seen) end
		end
		if full then
			-- НЕ обходим весь workspace целиком — это главный источник лагов.
			-- Берём только детали в радиусе и теги CollectionService.
			local own = getOwnRoot()
			if own then
				local r = math.min(CONFIG.KillAura.range or 24, CONFIG.Crystal.range or 60) + 8
				local params = RaycastParams.new()
				params.FilterType = Enum.RaycastFilterType.Exclude
				params.FilterDescendantsInstances = { player.Character }
				local parts = workspace:GetPartBoundsInBox(
					CFrame.new(own.Position), Vector3.new(r * 2, r * 2, r * 2), params)
				for _, p in ipairs(parts) do
					consider(p, out, seen)
					if p.Parent then consider(p.Parent, out, seen) end
				end
			end
			for _, tag in ipairs(CONFIG.Targeting.Tags) do
				for _, obj in CollectionService:GetTagged(tag) do consider(obj, out, seen) end
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
	local char = player.Character

	if not model or not model.Parent then return false end
	if char and (model == char or model:IsDescendantOf(char)) then return false end
	if e.isPlayer and e.player == player then return false end
	if e.root and ownRoot and e.root == ownRoot then return false end

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
