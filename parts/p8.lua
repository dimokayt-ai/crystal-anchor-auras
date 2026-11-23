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
GENV.AURA_CONNS[#GENV.AURA_CONNS + 1] = UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	local kc = input.KeyCode
	local K = CONFIG.Keys

	if kc == K.ToggleCrystal then
		STATE.crystal.enabled = not STATE.crystal.enabled
		STATE.crystal.shots = 0
		STATE.crystal.target = nil
		print(("[Auras] Crystal Aura: %s"):format(STATE.crystal.enabled and "ВКЛ" or "выкл"))
	elseif kc == K.ToggleAnchor then
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
