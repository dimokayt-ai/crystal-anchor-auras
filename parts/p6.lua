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
