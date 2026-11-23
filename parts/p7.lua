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
	-- фаза блока: сначала ставим обсидиан/блок под кристалл
	if s.placeBlock then
		local bsrc = pickSource("block")
		if bsrc then
			activateSource(bsrc, "block", t, pos, s)
			task.wait(s.blockDelay or 0.12)
		end
	end
	local ok = activateSource(src, "crystal", t, pos, s)
	STATE.crystal.shots = STATE.crystal.shots + 1
	if ok and s.twoPhase and s.twoPhaseMode ~= "none" then
		task.wait(s.twoPhaseDelay or 0.12)
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
	local ct = s.chargeTime or 0.6

	if seq == "place_charge_attack" then
		activateSource(src, "anchor", t, pos, s) -- 1) поставить анчор
		task.wait(ct)
		local csrc = pickSource("charge")
		if csrc then
			activateSource(csrc, "charge", t, pos, s) -- 2) зарядить светокамнем
			task.wait(ct)
		end
		-- 3) ударить по анчору -> взрыв
		local atk = pickSource("attack")
		if atk and atk.type == "tool" and ensureEquipped(atk.inst) then
			if s.aimCamera then aimCamera(pos) end
			pcall(function() atk.inst:Activate() end)
		else
			activateSource(src, "anchor", t, pos, s)
		end
	elseif seq == "charge_then_use" then
		local csrc = pickSource("charge")
		if csrc then
			activateSource(csrc, "charge", t, pos, s)
			task.wait(ct)
		end
		activateSource(src, "anchor", t, pos, s)
	elseif seq == "use_twice" then
		activateSource(src, "anchor", t, pos, s)
		task.wait(ct)
		activateSource(src, "anchor", t, pos, s)
	else
		activateSource(src, "anchor", t, pos, s)
	end
	STATE.anchor.shots = STATE.anchor.shots + 1
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

	HUD.crystal.Text = ("[Z] Кристалл: %s   выстрелов: %d"):format(
		STATE.crystal.enabled and "ВКЛ" or "выкл", STATE.crystal.shots)
	HUD.crystal.TextColor3 = STATE.crystal.enabled
		and Color3.fromRGB(120, 255, 160) or Color3.fromRGB(140, 140, 150)

	HUD.anchor.Text = ("[G] Анчор:    %s   выстрелов: %d"):format(
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
