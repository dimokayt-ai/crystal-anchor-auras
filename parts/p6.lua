			if containsAny(lowerRU(obj.Name), P.Crystal) then
				local cp = obj:IsA("BasePart") and obj.Position
					or (obj.PrimaryPart and obj.PrimaryPart.Position) or d.Position
				local dist = (cp - pos).Magnitude
				if dist < bestD then best, bestD = obj, dist end
			end
		end
	end)
	CRYSTAL_FIND_CACHE = { at = now, part = best }
	return best
end

-- Удар/подрыв после постановки кристалла
local function hitPlaced(s, t, pos)
	local target = pos
	local part = (s.hitAim or s.twoPhaseMode == "findAndSwing") and findPlacedCrystal(pos) or nil
	if part then
		target = part:IsA("BasePart") and part.Position
			or (part.PrimaryPart and part.PrimaryPart.Position) or pos
	end
	-- аим только на взрыв, быстро и точно
	if s.hitAim and target ~= pos then aimCamera(target, 1) end
	local atk = pickSource("attack")
	-- кристалл: меч НЕ экипируем — только Attack-ремоут (или сам кристалл)
	if atk and not s.noAttackTool then
		if atk.type == "tool" then
			local ok = ensureEquipped(atk.inst)
			if ok then
				if s.aimCamera then aimCamera(target, s.smoothAim or 0.25) end
				local mode = s.toolClickMode or "Activate"
				if mode == "VirtualClick" or mode == "Both" then virtualClick(target) end
				pcall(function() atk.inst:Activate() end)
				return true
			end
		elseif atk.type == "remoteEvent" or atk.type == "remoteFunction" then
			-- Attack remote (в дампе был RemoteEvent Attack) — шлём и как атаку, и как клик
			activateSource(atk, "attack", t, target, s)
			return true
		end
	end
	-- даже без меча шлём Attack-ремоут (быстрый взрыв)
	if s.noAttackTool and atk and (atk.type == "remoteEvent" or atk.type == "remoteFunction") then
		activateSource(atk, "attack", t, target, s)
		return true
	end
	-- фолбэк: бьём тем же кристаллом
	if s.toolClickMode ~= "none" then
		local src = pickSource("crystal")
		if src and src.type == "tool" then
			local ok = ensureEquipped(src.inst)
			if ok then
				if s.aimCamera then aimCamera(target, s.smoothAim or 0.25) end
				pcall(function() src.inst:Activate() end)
				return true
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
				local bok, bidx, bkey = activateSource(bsrc, "block", t, pos, s)
				if bok and bidx and bkey then
					scheduleEffectCheck(bkey, bidx, t, pos, "block", bsrc.name)
				end
				STATE.crystal.blockPos = pos
				STATE.crystal.blockAt = os.clock()
				local bd = s.blockDelay
				if bd == nil then bd = 0 end
				if bd > 0 then task.wait(bd) end
			end
		end
	end

	local ok, idx, key = activateSource(src, "crystal", t, pos, s)
	-- если нашли Tool, но в игре есть и BuildingAction/remote — дублируем через remote (часто в воксельных играх именно он ставит)
	if src.type == "tool" then
		for _, rs in ipairs(SOURCES.crystal or {}) do
			if rs.type == "remoteEvent" or rs.type == "remoteFunction" then
				activateSource(rs, "crystal", t, pos, s)
				break
			end
		end
	end
	STATE.crystal.shots = STATE.crystal.shots + 1
	local entry = { kind = "crystal", ok = ok, src = src.name, pos = { pos.X, pos.Y, pos.Z }, target = t.name }
	logAction(entry)
	if ok then scheduleEffectCheck(key, idx, t, pos, "crystal", src.name, entry) end

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
	frame.Size = UDim2.fromOffset(344, 300)
	frame.Position = UDim2.fromOffset(14, 14)
	frame.BackgroundColor3 = Color3.fromRGB(22, 23, 30)
	frame.BackgroundTransparency = 0.08
	frame.BorderSizePixel = 0
	frame.Parent = sg
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 20)
	local stroke = Instance.new("UIStroke", frame)
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Transparency = 0.87
	stroke.Thickness = 1
	local grad = Instance.new("UIGradient", frame)
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(32, 34, 44)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(16, 17, 23)),
	})
	grad.Rotation = 90

	-- перетаскивание за любую точку
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
			if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then dragging = false end
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

	local function mkText(y, size, color, bold, key, x)
		local l = Instance.new("TextLabel", frame)
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
