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
-- Варианты аргументов. Для ремоутов типа BuildingAction/ItemAction пробуем
-- форматы, типичные для воксельных игр; для остальных — общие.
local function buildArgVariants(phase, t, pos, src)
	local name = lowerRU((src and src.name) or "")
	local variants = {}
	local function add(v) variants[#variants + 1] = v end

	if name:find("build", 1, true) or name:find("place", 1, true) or name:find("block", 1, true) then
		-- BuildingAction-подобные: (action, pos, item) / (pos, item) / (cf, item)
		local item = (phase == "crystal" and "End Crystal")
			or (phase == "anchor" and "Anchor")
			or (phase == "charge" and "Glowstone")
			or (phase == "block" and "Block") or "Block"
		local cf = CFrame.new(pos)
		add({ "Place", pos, item })
		add({ "Place", cf, item })
		add({ "place", pos, item })
		add({ "Place", pos })
		add({ pos, item })
		add({ cf, item })
		add({ item, pos })
		add({ pos })
	end

	if name:find("itemaction", 1, true) or name:find("use", 1, true) then
		add({ "Use", pos })
		add({ "use", pos })
		add({ pos })
		add({ t.model })
	end

	-- общие
	add({ pos })
	add({ t.model })
	add({ t.model, pos })
	add({ pos, t.model })
	add({ t.root })
	add({ pos, t.root })
	add({ CFrame.new(pos) })
	add({})
	return variants
