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
		local args, idx, key = nextArgs(phase, t, pos, s, src)
		local ok = pcall(function()
			src.inst:FireServer(table.unpack(args))
		end)
		if ok then SRC_ARG_OK[key] = idx end
		return ok

	elseif src.type == "remoteFunction" then
		local args, idx, key = nextArgs(phase, t, pos, s, src)
		local ok = invokeRF(src.inst, args, s.rfTimeout or 2)
		if ok then SRC_ARG_OK[key] = idx end
		return ok

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

	-- наводка как киллаура: плавно в ту же точку
	if s.aimCamera ~= false then
		aimCamera(pos, s.smoothAim or CONFIG.KillAura.smoothAim or 0.35)
	end

	-- один обсидиан на точку, потом только кристаллы сверху
	if s.placeBlock then
		local last = STATE.crystal.blockPos
		local sameSpot = last and (last - pos).Magnitude < 1.5
		local fresh = STATE.crystal.blockAt and (os.clock() - STATE.crystal.blockAt) < (s.blockReuse or 4)
		if not (sameSpot and fresh) then
			local bsrc = pickSource("block")
			if bsrc then
				activateSource(bsrc, "block", t, pos, s)
				STATE.crystal.blockPos = pos
				STATE.crystal.blockAt = os.clock()
				local bd = s.blockDelay
				if bd == nil then bd = 0 end
				if bd > 0 then task.wait(bd) end
			end
		end
	end

	local ok = activateSource(src, "crystal", t, pos, s)
	STATE.crystal.shots = STATE.crystal.shots + 1
	logAction({ kind = "crystal", ok = ok, src = src.name, pos = { pos.X, pos.Y, pos.Z }, target = t.name })
	if ok and s.twoPhase and s.twoPhaseMode ~= "none" then
		local td = s.twoPhaseDelay
		if td == nil then td = 0 end
		if td > 0 then task.wait(td) end
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
	local ct = s.chargeTime
	if ct == nil then ct = 0 end

	if seq == "place_charge_attack" then
		activateSource(src, "anchor", t, pos, s) -- 1) поставить анчор
		if ct > 0 then task.wait(ct) end
		local csrc = pickSource("charge")
		if csrc then
			-- 2) закидывать светокамень до конца (maxCharges раз), пока не взорвётся
			local maxC = math.max(1, tonumber(s.maxCharges) or 4)
			for i = 1, maxC do
				activateSource(csrc, "charge", t, pos, s)
				if ct > 0 then task.wait(ct) end
			end
		end
		-- 3) ударить по анчору -> взрыв
		local atk = pickSource("attack")
		if atk and atk.type == "tool" and ensureEquipped(atk.inst) then
			if s.aimCamera then aimCamera(pos) end
			pcall(function() atk.inst:Activate() end)
		else
			-- нет оружия — ещё раз ПКМ по анчору (в некоторых играх это подрывает)
			activateSource(src, "anchor", t, pos, s)
		end
	elseif seq == "charge_then_use" then
		local csrc = pickSource("charge")
		if csrc then
			activateSource(csrc, "charge", t, pos, s)
