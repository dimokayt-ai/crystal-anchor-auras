		l.Size = UDim2.new(1, -36, 0, size + 8)
		l.Position = UDim2.fromOffset(x or 18, y)
		l.BackgroundTransparency = 1
		l.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
		l.TextSize = size
		l.TextColor3 = color
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.Text = ""
		if key then HUD[key] = l end
		return l
	end

	local dot = Instance.new("Frame", frame)
	dot.Size = UDim2.fromOffset(9, 9)
	dot.Position = UDim2.fromOffset(18, 21)
	dot.BackgroundColor3 = Color3.fromRGB(120, 132, 255)
	dot.BorderSizePixel = 0
	Instance.new("UICorner", dot).CornerRadius = UDim.new(0, 5)

	mkText(14, 21, Color3.fromRGB(242, 243, 248), true, nil, 36).Text = "Aura Suite"
	mkText(40, 12, Color3.fromRGB(150, 154, 168), false, nil, 36).Text = "Crystal · Anchor · Combat"

	local sep = Instance.new("Frame", frame)
	sep.Size = UDim2.new(1, -36, 0, 1)
	sep.Position = UDim2.fromOffset(18, 64)
	sep.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	sep.BackgroundTransparency = 0.9
	sep.BorderSizePixel = 0

	local function pill(y, key, dotKey)
		local p = Instance.new("Frame", frame)
		p.Size = UDim2.new(1, -36, 0, 32)
		p.Position = UDim2.fromOffset(18, y)
		p.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		p.BackgroundTransparency = 0.94
		p.BorderSizePixel = 0
		Instance.new("UICorner", p).CornerRadius = UDim.new(0, 10)
		local d = Instance.new("Frame", p)
		d.Size = UDim2.fromOffset(8, 8)
		d.Position = UDim2.fromOffset(12, 12)
		d.BackgroundColor3 = Color3.fromRGB(120, 124, 138)
		d.BorderSizePixel = 0
		Instance.new("UICorner", d).CornerRadius = UDim.new(0, 4)
		HUD[dotKey] = d
		local l = Instance.new("TextLabel", p)
		l.Size = UDim2.new(1, -40, 1, 0)
		l.Position = UDim2.fromOffset(28, 0)
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.Gotham
		l.TextSize = 14
		l.TextColor3 = Color3.fromRGB(238, 239, 245)
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.Text = ""
		HUD[key] = l
	end

	pill(76, "crystal", "dotC")
	pill(116, "anchor", "dotA")

	mkText(160, 13, Color3.fromRGB(170, 174, 190), false, "preset", 18)
	mkText(182, 12, Color3.fromRGB(150, 154, 168), false, "srcC", 18)
	mkText(200, 12, Color3.fromRGB(150, 154, 168), false, "srcA", 18)
	mkText(222, 13, Color3.fromRGB(235, 236, 242), true, "target", 18)

	local hpTrack = Instance.new("Frame", frame)
	hpTrack.Size = UDim2.new(1, -36, 0, 5)
	hpTrack.Position = UDim2.fromOffset(18, 244)
	hpTrack.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	hpTrack.BackgroundTransparency = 0.92
	hpTrack.BorderSizePixel = 0
	Instance.new("UICorner", hpTrack).CornerRadius = UDim.new(0, 3)
	local hpFill = Instance.new("Frame", hpTrack)
	hpFill.Size = UDim2.new(0, 0, 1, 0)
	hpFill.BackgroundColor3 = Color3.fromRGB(86, 214, 148)
	hpFill.BorderSizePixel = 0
	Instance.new("UICorner", hpFill).CornerRadius = UDim.new(0, 3)
	HUD.hpFill = hpFill

	mkText(254, 11, Color3.fromRGB(140, 145, 160), false, "info", 18)
	mkText(274, 11, Color3.fromRGB(255, 105, 110), false, "warn", 18)

	HUD.gui = sg
end

local function updateHUD()
	if not HUD.gui or not HUD.gui.Parent then return end

	HUD.crystal.Text = ("[Z] Кристалл   %s   · %d"):format(
		STATE.crystal.enabled and "ВКЛ" or "выкл", STATE.crystal.shots)
	HUD.crystal.TextColor3 = STATE.crystal.enabled
		and Color3.fromRGB(236, 237, 242) or Color3.fromRGB(160, 162, 172)
	HUD.dotC.BackgroundColor3 = STATE.crystal.enabled
		and Color3.fromRGB(86, 214, 148) or Color3.fromRGB(120, 124, 138)

	HUD.anchor.Text = ("[G] Анчор      %s   · %d"):format(
		STATE.anchor.enabled and "ВКЛ" or "выкл", STATE.anchor.shots)
	HUD.anchor.TextColor3 = STATE.anchor.enabled
		and Color3.fromRGB(236, 237, 242) or Color3.fromRGB(160, 162, 172)
	HUD.dotA.BackgroundColor3 = STATE.anchor.enabled
		and Color3.fromRGB(86, 214, 148) or Color3.fromRGB(120, 124, 138)

	HUD.preset.Text = ("Пресет  %s   · H"):format(CONFIG.Presets[PRESET_IDX].name)

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

	local tgt = STATE.crystal.target or STATE.anchor.target or STATE.killaura.targetObj
	if tgt and tgt.root and tgt.root.Parent then
		local own = getOwnRoot()
		local d = own and math.floor((tgt.root.Position - own.Position).Magnitude) or 0
		local hp = tgt.health and math.floor(tgt.health) or 0
		local mx = tgt.maxHealth and math.floor(tgt.maxHealth) or 0
		HUD.target.Text = ("%s  · %dм  · %s/%s%s"):format(
			tgt.name, d, tostring(hp), tostring(mx),
			(tgt.isBoss and "  BOSS") or (tgt.isElite and "  ELITE") or "")
		local ratio = (mx > 0) and math.clamp(hp / mx, 0, 1) or 0
		HUD.hpFill.Size = UDim2.new(ratio, 0, 1, 0)
		HUD.hpFill.BackgroundColor3 = ratio > 0.5
			and Color3.fromRGB(86, 214, 148)
			or (ratio > 0.25 and Color3.fromRGB(255, 190, 90) or Color3.fromRGB(255, 105, 110))
	else
		HUD.target.Text = "Цель: —"
		HUD.hpFill.Size = UDim2.new(0, 0, 1, 0)
	end

	local learned = 0
	for _ in pairs(ARG_STATS) do learned = learned + 1 end
	HUD.info.Text = ("источники %d/%d/%d/%d/%d · целей %d · N:%s M:%s · обучено %d"):format(
		#SOURCES.crystal, #SOURCES.anchor, #SOURCES.block, #SOURCES.charge, #SOURCES.attack, #TARGETS,
		STATE.killaura.enabled and "on" or "off",
		STATE.mace.enabled and "on" or "off", learned)

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
		if STATE.crystal.enabled then task.spawn(function() pcall(rescanSources); pcall(rescanTargets, true) end) end
		print(("[Auras] Crystal Aura: %s"):format(STATE.crystal.enabled and "ВКЛ" or "выкл"))
	elseif kc == K.ToggleAnchor or kc == K.ToggleAnchorAlt then
		STATE.anchor.enabled = not STATE.anchor.enabled
		STATE.anchor.shots = 0
		STATE.anchor.target = nil
		if STATE.anchor.enabled then task.spawn(function() pcall(rescanSources); pcall(rescanTargets, true) end) end
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
	elseif kc == K.ExportLog then
		exportLog()
		STATE.warn, STATE.warnAt = "Лог скопирован в буфер (" .. #STATE.log .. ")", os.clock()
	elseif kc == K.ToggleKillAura then
		STATE.killaura.enabled = not STATE.killaura.enabled
		STATE.killaura.shots = 0
		print(("[Auras] Kill Aura: %s"):format(STATE.killaura.enabled and "ВКЛ" or "выкл"))
	elseif kc == K.ToggleMace then
		STATE.mace.enabled = not STATE.mace.enabled
		print(("[Auras] Mace Helper: %s"):format(STATE.mace.enabled and "ВКЛ" or "выкл"))
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
						local dly = s.delay; if dly == nil then dly = 0.15 end
						local jit = s.jitter; if jit == nil then jit = 0 end
						local waitT = dly + math.random() * jit
						if waitT > 0 then task.wait(waitT) else RunService.Heartbeat:Wait() end
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
