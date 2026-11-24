	local char = player.Character
	if not char then return nil end
	for _, obj in char:GetChildren() do
		if obj:IsA("Tool") then return obj end
	end
	return nil
end

local function restoreTool(tool)
	if not tool or not tool.Parent then return end
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then pcall(function() hum:EquipTool(tool) end) end
end

local function doSwingAt(pos, useMace)
	if not pos then return false end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then return false end

	-- плавно доворачиваемся к цели ВСЕГДА (тело, не камера)
	if CONFIG.KillAura.bodyAim then bodyAim(pos, CONFIG.KillAura.bodyAimSpeed or 14) end

	local previous = heldTool()
	local mace = useMace and findMaceTool() or nil
	local tool = mace or previous
	local srcInfo = nil
	if not tool then
		srcInfo = pickSource("attack")
		if srcInfo and srcInfo.type == "tool" then tool = srcInfo.inst; srcInfo = nil end
	end

	if tool and tool:IsA("Tool") then
		if tool ~= previous then
			pcall(function() hum:EquipTool(tool) end)
			local ed = CONFIG.KillAura.equipDelay or 0
			if ed > 0 then task.wait(ed) end
		end
		pcall(function() tool:Activate() end)
		if CONFIG.KillAura.toolClickMode == "Both" or CONFIG.KillAura.toolClickMode == "VirtualClick" then
			virtualClick(pos)
		end
		if mace then
			-- мейс: удар на падении сильнее — бьём повторно и возвращаем старый предмет
			pcall(function() tool:Activate() end)
			local bd = CONFIG.MaceHelper.swapBackDelay or 0
			if bd > 0 then task.wait(bd) end
			restoreTool(previous)
		end
		return true
	end

	-- ремоут-атака (Attack/Swing из дампа)
	srcInfo = srcInfo or pickSource("attack")
	if srcInfo and (srcInfo.type == "remoteEvent" or srcInfo.type == "remoteFunction") then
		return activateSource(srcInfo, "attack", { model = char, root = getOwnRoot() }, pos, CONFIG.KillAura)
	end
	if srcInfo and srcInfo.type == "tool" then
		local ok = ensureEquipped(srcInfo.inst)
		if ok then pcall(function() srcInfo.inst:Activate() end); return true end
	end
	return false
end

task.spawn(function()
	while true do
		if not alive() then return end
		if STATE.killaura.enabled then
			local own = getOwnRoot()
			if own then
				local s = {
					range = CONFIG.KillAura.range or 20,
					priority = CONFIG.KillAura.priority or "Nearest",
					filter = CONFIG.KillAura.filter or "All",
					requireLoS = CONFIG.KillAura.requireLoS,
					finishHP = 0.3, multi = false,
				}
				-- липкая цель: не переключаться каждый кадр (иначе камера крутится)
				local sticky = STATE.killaura.targetObj
				local t = nil
				if sticky and sticky.root and sticky.root.Parent then
					local ok, dist = isValidTarget(sticky, s, own)
					if ok and dist <= (s.range * 1.2) then t = sticky end
				end
				if not t then t = selectTarget(s, own) end
				local char = player.Character
				local isSelf = t and char and (t.model == char or t.model:IsDescendantOf(char) or t.root == own)
				local tooClose = t and t.root and (t.root.Position - own.Position).Magnitude < 2
				if isSelf or tooClose then t = nil end
				STATE.killaura.targetObj = t
				STATE.killaura.target = t and t.name or nil
				if t and t.root and t.root.Parent then
					local pos = t.root.Position
					local preferMace = STATE.mace.enabled and CONFIG.KillAura.autoMace ~= false
					if doSwingAt(pos, preferMace) then
						STATE.killaura.shots = STATE.killaura.shots + 1
					end
					local d = (CONFIG.KillAura.delay or 0) + math.random() * (CONFIG.KillAura.jitter or 0)
					if d > 0 then task.wait(d) else RunService.Heartbeat:Wait() end
				else
					RunService.Heartbeat:Wait()
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
						local fd = CONFIG.MaceHelper.fallAttackDelay; if fd == nil then fd = 0.15 end
						if fd > 0 then task.wait(fd) end
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

-- AirStack: стакаем прыжки / ставим блоки под ноги
task.spawn(function()
	while true do
		if not alive() then return end
		if STATE.airstack.enabled then
		local char = player.Character
		local hum, root = char and char:FindFirstChildOfClass("Humanoid"), getOwnRoot()
		if hum and root then
			local cfg = CONFIG.AirStack
			if cfg.mode == "Block" then
				local bsrc = pickSource("block")
				if bsrc then
					activateSource(bsrc, "block", { model = char, root = root }, root.Position - Vector3.new(0, cfg.blockOffset or 3, 0), CONFIG.Crystal)
				end
				pcall(function() hum:ChangeState(Enum.HumanoidStateType.Jumping) end)
			else
				local boost = (cfg.stackBoost or 3) * math.min(STATE.airstack.stack or 0, 4)
				pcall(function()
					root.AssemblyLinearVelocity = Vector3.new(
						root.AssemblyLinearVelocity.X,
						(cfg.jumpPower or 55) + boost,
						root.AssemblyLinearVelocity.Z)
				end)
				pcall(function() hum:ChangeState(Enum.HumanoidStateType.Jumping) end)
				STATE.airstack.stack = math.min((STATE.airstack.stack or 0) + 1, 4)
			end
			task.wait(CONFIG.AirStack.jumpDelay or 0.06)
		else
			task.wait(0.2)
		end
		else
			task.wait(0.15)
		end
	end
end)

-- Speed: держим скорость (в т.ч. после респавна)
task.spawn(function()
	while true do
		if not alive() then return end
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum and STATE.speed.enabled then
			pcall(function()
				if hum.WalkSpeed ~= (CONFIG.Speed.walkSpeed or 75) then hum.WalkSpeed = CONFIG.Speed.walkSpeed or 75 end
				if hum.JumpPower ~= (CONFIG.Speed.jumpPower or 60) then hum.JumpPower = CONFIG.Speed.jumpPower or 60 end
			end)
		end
		task.wait(0.4)
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
	local lastAny = false
	while true do
		if not alive() then return end
		local anyOn = STATE.crystal.enabled or STATE.anchor.enabled or STATE.killaura.enabled or STATE.mace.enabled
		if anyOn then
			if not lastAny then -- только что включили — сразу свежий скан
				tFull, tSrc = 0, 0
			end
			lastAny = true
			local now = os.clock()
			local full = (now - tFull) >= CONFIG.Scan.FullInterval
			if full then tFull = now end
			pcall(rescanTargets, full)
			if (now - tSrc) >= CONFIG.Scan.SourceRescan then
				tSrc = now
				pcall(rescanSources)
				pcall(sourceReport)
			end
			task.wait(full and CONFIG.Scan.Interval or math.max(CONFIG.Scan.Interval, 0.35))
		else
			lastAny = false
			task.wait(1.0) -- всё выключено: спим и вообще ничего не трогаем
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
			print(("[Auras] шаг 4/4: старт завершён. Пресетов: %d | Z/G/N/M/V/T/H/K/J/L"):format(#CONFIG.Presets))
		end)
	end)
end)

end, showFatal)
if not __ok then showFatal(__err) end

