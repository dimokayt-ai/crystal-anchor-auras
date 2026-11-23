	end
	STATE.anchor.shots = STATE.anchor.shots + 1
	logAction({ kind = "anchor", seq = seq, src = src.name, charge = (pickSource("charge") or {}).name, pos = { pos.X, pos.Y, pos.Z }, target = t.name })
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

	HUD.crystal.Text = ("[Z] Кристалл: %s   попыток: %d"):format(
		STATE.crystal.enabled and "ВКЛ" or "выкл", STATE.crystal.shots)
	HUD.crystal.TextColor3 = STATE.crystal.enabled
		and Color3.fromRGB(120, 255, 160) or Color3.fromRGB(140, 140, 150)

	HUD.anchor.Text = ("[G] Анчор:    %s   попыток: %d"):format(
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

	HUD.info.Text = ("C:%d A:%d бл:%d зар:%d уд:%d | целей:%d | N Kill:%s M Mace:%s | JHUD Lлог"):format(
		#SOURCES.crystal, #SOURCES.anchor, #SOURCES.block, #SOURCES.charge, #SOURCES.attack, #TARGETS,
		STATE.killaura.enabled and "ВКЛ" or "выкл",
		STATE.mace.enabled and "ВКЛ" or "выкл")

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
