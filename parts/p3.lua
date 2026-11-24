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
-- 5. СОСТОЯНИЕ + ЧЕСТНОЕ ОБУЧЕНИЕ
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

-- Честная статистика: успех = реальный эффект (HP упал / объект появился), а не просто pcall.
local ARG_STATS = GENV.AURA_ARG_STATS or {}
local SRC_STATS = GENV.AURA_SRC_STATS or {}
GENV.AURA_ARG_STATS, GENV.AURA_SRC_STATS = ARG_STATS, SRC_STATS

local function statKey(srcName, phase)
	return tostring(srcName or "?") .. "|" .. tostring(phase or "?")
end

local function statRate(st)
	if not st or st.n < 1 then return nil end
	return (st.s + 1) / (st.n + 2) -- сглаженная доля успеха (Байес)
end

local function recordStat(tableRef, key, success)
	local st = tableRef[key]
	if not st then st = { n = 0, s = 0 }; tableRef[key] = st end
	st.n = st.n + 1
	if success then st.s = st.s + 1 end
	if st.n > 24 then -- забываем старое, учимся под новую ситуацию
		st.n = st.n * 0.85
		st.s = st.s * 0.85
	end
end

local findPlacedCrystal -- forward, определена ниже

-- Проверка эффекта через 0.12 сек: HP цели / появление кристалла.
local function scheduleEffectCheck(key, idx, t, pos, phase, srcName, entry)
	local before = t and tonumber(t.health) or nil
	local model = t and t.model or nil
	task.delay(0.12, function()
		if not alive() then return end
		local success = false
		if before and model and model.Parent then
			local hum = model:FindFirstChildOfClass("Humanoid")
			local nowHp = hum and hum.Health
				or tonumber(model:GetAttribute("Health")) or tonumber(model:GetAttribute("HP"))
			if type(nowHp) == "number" and nowHp < before - 0.5 then success = true end
		end
		if not success and (phase == "crystal" or phase == "block") and pos and findPlacedCrystal(pos) then
			success = true
		end
		if key and idx then recordStat(ARG_STATS, key .. "#" .. idx, success) end
		recordStat(SRC_STATS, statKey(srcName, phase), success)
		if entry then entry.effect = success and "hit" or "none" end
	end)
end

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

local function scoreSource(name, srcType, exact, phase)
	local sc = 0
	if exact then sc = sc + 100 end
	if srcType == "tool" then sc = sc + 25
	elseif srcType == "remoteEvent" then sc = sc + 20
	elseif srcType == "remoteFunction" then sc = sc + 15
	elseif srcType == "prompt" then sc = sc + 10
	elseif srcType == "module" then sc = sc + 5 end
	-- бонус за реально подтверждённый эффект в прошлом
	local rate = statRate(SRC_STATS[statKey(name, phase)])
	if rate then sc = sc + rate * 35 end
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
		src.score = scoreSource(src.name, src.type, src.exact, phase)
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
			if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") or d:IsA("UnreliableRemoteEvent") then
				local phase = classify(d.Name)
				if phase then
					local t = d:IsA("RemoteFunction") and "remoteFunction" or "remoteEvent"
					add(phase, { type = t, inst = d, name = d.Name, exact = isExact(d.Name, phase) })
					local ln = lowerRU(d.Name)
					if (ln:find("build", 1, true) or ln:find("place", 1, true)) and phase ~= "crystal" then
						add("crystal", { type = t, inst = d, name = d.Name, exact = isExact(d.Name, "crystal") })
					end
				end
			elseif d:IsA("ProximityPrompt") then
				local label = tostring(d.ActionText or "") .. " " .. tostring(d.ObjectText or "")
				local phase = classify(label)
				if phase then
					add(phase, {
						type = "prompt", inst = d,
						name = (d.ActionText ~= "" and d.ActionText) or d.Name,
						exact = isExact(label, phase),
					})
				end
			elseif d:IsA("ModuleScript") then
				local phase = classify(d.Name)
				if phase and CONFIG.Scan.RequireModules then
					local ok, mod = pcall(require, d)
					if ok and type(mod) == "table" then
						local fns = {}
						for k, v in pairs(mod) do
							if type(v) == "function" then fns[#fns + 1] = tostring(k) end
						end
						if #fns > 0 then
							add(phase, {
								type = "module", inst = d, mod = mod, fns = fns,
								name = d.Name, exact = isExact(d.Name, phase),
							})
						end
					end
				end
			end
		end
	end
	scanServices(ReplicatedStorage)
	-- workspace скан дорогой: только изредка и только если реально включено
	local lastWs = GENV.AURA_LAST_WS_SCAN or 0
	if CONFIG.Scan.WorkspaceServices and os.clock() - lastWs > 15 then
		GENV.AURA_LAST_WS_SCAN = os.clock()
		scanServices(workspace)
	end

	for phase, list in pairs(lists) do
		table.sort(list, function(a, b) return a.score > b.score end)
		SOURCES[phase] = list
