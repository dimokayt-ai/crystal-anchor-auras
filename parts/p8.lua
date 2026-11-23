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

local function pickAttackTool(preferMace)
	local list = SOURCES.attack or {}
	local best, bestMace = nil, nil
	for _, s in ipairs(list) do
		if s.type == "tool" and s.inst and s.inst.Parent then
			local n = lowerRU(s.name or "")
			if n:find("mace", 1, true) or n:find("булава", 1, true) then
				bestMace = s
			elseif not best then
				best = s
			end
		end
	end
	if preferMace and bestMace then return bestMace end
	return bestMace or best or pickSource("attack")
end

local function doSwingAt(pos, preferMace)
	local src = pickAttackTool(preferMace)
	if not src then return false end
	if src.type == "tool" then
		local ok = ensureEquipped(src.inst)
		if not ok then return false end
		if CONFIG.KillAura.aimCamera then aimCamera(pos) end
		pcall(function() src.inst:Activate() end)
		virtualClick(pos)
		return true
	end
	if src.type == "remoteEvent" then
		return pcall(function() src.inst:FireServer(pos) end)
	end
	return activateSource(src, "attack", { model = player.Character, root = getOwnRoot() }, pos, CONFIG.KillAura)
end

task.spawn(function()
	while true do
		if not alive() then return end
		if STATE.killaura.enabled then
			local own = getOwnRoot()
			if own then
				local s = {
					range = CONFIG.KillAura.range or 18,
					priority = CONFIG.KillAura.priority or "Nearest",
					filter = CONFIG.KillAura.filter or "All",
					requireLoS = CONFIG.KillAura.requireLoS,
					finishHP = 0.3, multi = false,
				}
				local t = selectTarget(s, own)
				STATE.killaura.target = t and t.name or nil
				if t then
					local pos = t.root.Position
					local preferMace = STATE.mace.enabled
					doSwingAt(pos, preferMace)
					STATE.killaura.shots = STATE.killaura.shots + 1
					task.wait((CONFIG.KillAura.delay or 0.08) + math.random() * (CONFIG.KillAura.jitter or 0.02))
				else
					task.wait(0.12)
				end
			else
				task.wait(0.2)
			end
		else
			task.wait(0.15)
		end
	end
end)

task.spawn(function()
	-- Mace Helper: при падении рядом с целью — удар булавой
	while true do
		if not alive() then return end
		if STATE.mace.enabled then
			local char = player.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local root = getOwnRoot()
			if hum and root then
				local vy = root.AssemblyLinearVelocity.Y
				local falling = vy < -10
				if not falling and hum.FloorMaterial ~= Enum.Material.Air and (os.clock() - (STATE.mace.lastJump or 0)) > 0.8 then
					-- прыжок, если рядом есть цель
					local t = selectTarget({ range = CONFIG.MaceHelper.range or 20, priority = "Nearest", filter = "All", finishHP = 0.3 }, root)
					if t then
						hum:ChangeState(Enum.HumanoidStateType.Jumping)
						pcall(function() root.AssemblyLinearVelocity = Vector3.new(root.AssemblyLinearVelocity.X, CONFIG.MaceHelper.jumpPower or 60, root.AssemblyLinearVelocity.Z) end)
						STATE.mace.lastJump = os.clock()
						task.wait(CONFIG.MaceHelper.fallAttackDelay or 0.15)
					else
						task.wait(0.1)
					end
				elseif falling then
					local t = selectTarget({ range = CONFIG.MaceHelper.range or 20, priority = "Nearest", filter = "All", finishHP = 0.3 }, root)
					if t then
						doSwingAt(t.root.Position, true)
					end
					task.wait(0.05)
				else
					task.wait(0.08)
				end
			else
				task.wait(0.2)
			end
		else
			task.wait(0.2)
		end
	end
end)

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
		local anyOn = STATE.crystal.enabled or STATE.anchor.enabled or STATE.killaura.enabled or STATE.mace.enabled
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
print("[Auras] шаг 1/4: HUD готов — жми Z (кристалл) / G (анчор) / L (лог)")

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

