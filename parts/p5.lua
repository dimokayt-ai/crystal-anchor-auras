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
		add({ "Build", pos, item })
		add({ "build", pos, item })
		add({ "Place", item, pos })
		add({ "Place", item, cf })
		add({ pos, item })
		add({ cf, item })
		add({ item, pos })
		add({ item, cf })
		add({ "Place", pos })
		add({ pos })
		add({ cf })
	end

	if name:find("itemaction", 1, true) or name:find("use", 1, true) then
		add({ "Use", pos })
		add({ "use", pos })
		add({ "Use", t.model })
		add({ "Activate", pos })
		add({ pos })
		add({ t.model })
	end

	if name:find("attack", 1, true) or name:find("hit", 1, true) or name:find("swing", 1, true) then
		add({ t.model })
		add({ t.root })
		add({ pos })
		add({ t.model, pos })
		add({ "Attack", t.model })
		add({})
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
end

-- Память аргументов теперь в ARG_STATS (честная статистика по эффекту), см. секцию 5.

local function nextArgs(phase, t, pos, s, src)
	local vars = buildArgVariants(phase, t, pos, src)
	local key = statKey((src and src.name) or "?", phase)
	local idx

	if s.argIndex then
		idx = s.argIndex -- жёстко закреплён в конфиге
	else
		-- 1 из 6 пробуем новое (исследование), остальное — лучший по реальному эффекту
		local explore = math.random(6) == 1
		local best, bestRate = nil, -1
		for i = 1, #vars do
			local r = statRate(ARG_STATS[key .. "#" .. i])
			if r and r > bestRate then best, bestRate = i, r end
		end
		if explore or not best then
			idx = ARG_INDEX[phase] or 1
			ARG_INDEX[phase] = (idx % #vars) + 1
		else
			idx = best
		end
	end
	idx = ((idx - 1) % #vars) + 1
	return vars[idx], idx, key, #vars
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
			-- ПКМ + Activate: разные игры слушают разные сигналы
			local pok = pressRightClick(pos)
			pcall(function() src.inst:Activate() end)
			return pok, nil, nil
		end
		if mode == "VirtualClick" or mode == "Both" then
			virtualClick(pos)
		end
		local fired = pcall(function() src.inst:Activate() end)
		if not fired and mode == "VirtualClick" then
			fired = pcall(function() src.inst:Activate() end)
		end
		return fired, nil, nil

	elseif src.type == "remoteEvent" then
		local args, idx, key = nextArgs(phase, t, pos, s, src)
		local ok = pcall(function()
			src.inst:FireServer(table.unpack(args))
		end)
		if ok then scheduleEffectCheck(key, idx, t, pos, phase, src.name) end
		return ok, idx, key

	elseif src.type == "remoteFunction" then
		local args, idx, key = nextArgs(phase, t, pos, s, src)
		local ok = invokeRF(src.inst, args, s.rfTimeout or 2)
		if ok then scheduleEffectCheck(key, idx, t, pos, phase, src.name) end
		return ok, idx, key

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
