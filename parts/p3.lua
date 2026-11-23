		local hitPos = nil
		if worldPos then
			local okr, rayRes = pcall(function()
				local origin = cam.CFrame.Position
				local dir = (worldPos - origin)
				if dir.Magnitude < 0.001 then return nil end
				local rp = RaycastParams.new()
				rp.FilterType = Enum.RaycastFilterType.Exclude
				rp.FilterDescendantsInstances = { player.Character }
				return workspace:Raycast(origin, dir.Unit * 200, rp)
			end)
			if okr and rayRes then hitPos = rayRes.Position end
			-- фолбэк: луч вниз от точки (ищем блок под ней)
			if not hitPos then
				local okd, down = pcall(function()
					local rp = RaycastParams.new()
					rp.FilterType = Enum.RaycastFilterType.Exclude
					rp.FilterDescendantsInstances = { player.Character }
					return workspace:Raycast(worldPos + Vector3.new(0, 8, 0), Vector3.new(0, -20, 0), rp)
				end)
				if okd and down then hitPos = down.Position end
			end
			local target = hitPos or worldPos
			local okv, vp = pcall(function() return cam:WorldToViewportPoint(target) end)
			if okv and vp and vp.Z > 0 then
				sx, sy = math.clamp(vp.X, 0, vs.X), math.clamp(vp.Y, 0, vs.Y)
			end
		end
	end
	-- 1) VirtualInputManager: кнопка 1 = правая (надёжнее всего в экзекьюторах)
	local ok = pcall(function()
		local VIM = game:GetService("VirtualInputManager")
		VIM:SendMouseButtonEvent(sx, sy, 1, true, game, 1)
		task.wait(0.03)
		VIM:SendMouseButtonEvent(sx, sy, 1, false, game, 1)
	end)
	if ok then return true end
	-- 2) хелперы экзекьютора
	if type(mouse2click) == "function" and pcall(mouse2click) then return true end
	if type(mouse2down) == "function" and type(mouse2up) == "function" then
		if pcall(mouse2down) then
			task.wait(0.03)
			pcall(mouse2up)
			return true
		end
	end
	-- 3) последний шанс: тот же VirtualUser, но Button2Down/Up
	return pcall(function()
		VirtualUser:CaptureController()
		VirtualUser:Button2Down(Vector2.new(sx, sy))
		task.wait(0.03)
		VirtualUser:Button2Up(Vector2.new(sx, sy))
	end)
end

-- Прямая видимость до цели
local losParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Exclude

local function hasLoS(fromPos, targetEntry)
	local char = player.Character
	losParams.FilterDescendantsInstances = { char }
	local toPos = targetEntry.root.Position
	local hit = workspace:Raycast(fromPos, toPos - fromPos, losParams)
	if not hit then return true end
	local h = hit.Instance
	local m = targetEntry.model
	if h == targetEntry.root then return true end
	if m:IsA("BasePart") then return h == m end
	local ok, res = pcall(function() return m:IsAncestorOf(h) end)
	return ok and res
end

-- =================================================================
-- 5. СОСТОЯНИЕ
-- =================================================================
local STATE = {
	crystal = { enabled = false, shots = 0, target = nil },
	anchor  = { enabled = false, shots = 0, target = nil },
	killaura = { enabled = false, shots = 0, target = nil },
	mace = { enabled = false, lastJump = 0 },
	warn = nil,       -- текст предупреждения (например, низкое HP)
	warnAt = 0,
	log = {},         -- запись действий для "обучения"/датасета
}

-- Простой логгер действий (датасет в памяти -> по K+J или вручную можно выгрузить)
local function logAction(entry)
	entry.t = os.clock()
	entry.preset = (CONFIG.Presets[PRESET_IDX] or {}).name
	local log = STATE.log
	log[#log + 1] = entry
	if #log > 500 then table.remove(log, 1) end -- кольцевой буфер
end

local function exportLog()
	local ok, Http = pcall(game.GetService, game, "HttpService")
	local payload = { exportedAt = os.time(), entries = STATE.log }
	local text
	if ok and Http then
		local ok2, j = pcall(function() return Http:JSONEncode(payload) end)
		text = ok2 and j or tostring(#STATE.log) .. " entries"
	else
		text = "[AurasLog] entries=" .. tostring(#STATE.log)
	end
	if type(setclipboard) == "function" then pcall(setclipboard, text) end
	print("[Auras] Лог действий (" .. #STATE.log .. " шт) скопирован в буфер/консоль")
	return text
end

local PRESET_IDX    = 1
local MULTI_IDX     = 1
local SOURCE_INDEX  = { crystal = 1, anchor = 1, charge = 1, block = 1, attack = 1 }
local ARG_INDEX     = { crystal = 1, anchor = 1, charge = 1, block = 1 }
local FN_INDEX      = { crystal = 1, anchor = 1, charge = 1, block = 1 }

local SOURCES = { crystal = {}, anchor = {}, charge = {}, attack = {} }
local TARGETS = {}

-- =================================================================
-- 6. СКАНЕР ИСТОЧНИКОВ (чем именно ауры могут пользоваться)
-- =================================================================
local function classify(name)
	local n = lowerRU(tostring(name or ""))
	if containsAny(n, P.Exact.crystal) then return "crystal" end
	if containsAny(n, P.Exact.charge)  then return "charge"  end
	if containsAny(n, P.Exact.anchor)  then return "anchor"  end
	if containsAny(n, P.Exact.block)   then return "block"   end
	if containsAny(n, P.Charge) then return "charge" end
	if containsAny(n, P.Anchor) then return "anchor" end
	if containsAny(n, P.Crystal) then return "crystal" end
	if containsAny(n, P.Block) then return "block" end
	if containsAny(n, P.Attack) then return "attack" end
	return nil
end

local function scoreSource(name, srcType, exact)
	local sc = 0
	if exact then sc = sc + 100 end
	if srcType == "tool" then sc = sc + 25
	elseif srcType == "remoteEvent" then sc = sc + 20
	elseif srcType == "remoteFunction" then sc = sc + 15
	elseif srcType == "prompt" then sc = sc + 10
	elseif srcType == "module" then sc = sc + 5 end
	return sc
end

local function findToolByName(name)
	local backpack = player:FindFirstChild("Backpack")
	local char = player.Character
	local n = lowerRU(name)
	for _, container in ipairs({ backpack, char }) do
		if container then
			for _, c in container:GetChildren() do
				if c:IsA("Tool") and lowerRU(c.Name) == n then return c end
			end
		end
	end
	return nil
end

local function rescanSources()
	local backpack = player:FindFirstChild("Backpack")
	local char = player.Character
	local lists = { crystal = {}, anchor = {}, charge = {}, block = {}, attack = {} }
	local seen = {}

	local function add(phase, src)
		if not phase or not lists[phase] then return end
		-- анчор: ТОЛЬКО Tool (никаких RemoteEvent/промптов/модулей)
		if phase == "anchor" and src.type ~= "tool" then return end
		local k = tostring(src.inst) .. "|" .. phase
		if seen[k] then return end
		seen[k] = true
		src.score = scoreSource(src.name, src.type, src.exact)
		table.insert(lists[phase], src)
	end

	local function considerTool(tool, live)
		local phase = classify(tool.Name)
		if not phase then return end
		if live then
			add(phase, { type = "tool", inst = tool, name = tool.Name, exact = isExact(tool.Name, phase) })
			return
		end
		-- шаблон: клонируем в рюкзак (если разрешено и такого ещё нет)
		if not CONFIG.Scan.CloneTemplates then return end
		if phase == "attack" and not CONFIG.Scan.CloneAttack then return end -- без спама оружием
		if findToolByName(tool.Name) then return end
		if not live and tool.Parent == workspace and not CONFIG.Scan.CloneFromWorkspace then return end
		local ok, clone = pcall(function() return tool:Clone() end)
		if not ok or not clone then return end
		clone.Parent = backpack
		print(("[Auras] Шаблон склонирован в рюкзак: %s"):format(clone.Name))
		add(phase, { type = "tool", inst = clone, name = clone.Name, exact = isExact(clone.Name, phase) })
	end

	-- 1) живые Tool'ы
	for _, container in ipairs({ backpack, char }) do
		if container then
			for _, d in container:GetChildren() do
				if d:IsA("Tool") then considerTool(d, true) end
			end
		end
	end

	-- 2) шаблоны Tool'ы в ReplicatedStorage (+ workspace, если включено)
	local function scanToolTemplates(root)
		if not root then return end
		for _, d in root:GetDescendants() do
			if d:IsA("Tool") then considerTool(d, false) end
		end
	end
	scanToolTemplates(ReplicatedStorage)
	pcall(function() scanToolTemplates(game:GetService("StarterPack")) end) -- Tool'ы на старте (анчор может лежать тут)
	if CONFIG.Scan.CloneFromWorkspace then scanToolTemplates(workspace) end

	-- 3) RemoteEvent / RemoteFunction / ProximityPrompt / ModuleScript
	local function scanServices(root)
		if not root then return end
		for _, d in root:GetDescendants() do
			if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") then
				local phase = classify(d.Name)
				if phase then
					local t = d:IsA("RemoteEvent") and "remoteEvent" or "remoteFunction"
					add(phase, { type = t, inst = d, name = d.Name, exact = isExact(d.Name, phase) })
					-- build/place ремоуты полезны и для кристалла тоже
					local ln = lowerRU(d.Name)
					if (ln:find("build", 1, true) or ln:find("place", 1, true)) and phase ~= "crystal" then
