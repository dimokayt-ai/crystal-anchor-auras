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
	scanServices(workspace)

	for phase, list in pairs(lists) do
		table.sort(list, function(a, b) return a.score > b.score end)
		SOURCES[phase] = list
		if (SOURCE_INDEX[phase] or 1) > #list then SOURCE_INDEX[phase] = 1 end
	end
end

local function sourceReport()
	for _, phase in ipairs({ "crystal", "anchor", "charge", "block", "attack" }) do
		local names = {}
		for _, s in ipairs(SOURCES[phase]) do
			names[#names + 1] = s.type .. ":" .. s.name
		end
		print(("[Auras] %-7s → %d | %s"):format(phase, #SOURCES[phase], table.concat(names, ", ")))
	end
end

local function sourceValid(src)
	if not src or not src.inst then return false end
	local ok, res = pcall(function() return src.inst.Parent ~= nil end)
	return ok and res
end

local function pickSource(phase)
	local list = SOURCES[phase]
	if not list or #list == 0 then return nil end
	local start = SOURCE_INDEX[phase] or 1
	for i = 0, #list - 1 do
		local idx = ((start - 1 + i) % #list) + 1
		if sourceValid(list[idx]) then
			SOURCE_INDEX[phase] = idx
			return list[idx]
		end
	end
	return nil
end

-- ДИАГНОСТИКА: всё, что игра предлагает (инструменты, ремоуты, структура)
local function dumpWorld()
	pcall(function()
		local tools, re, rf = {}, {}, {}
		local function scan(root)
			if not root then return end
			for _, d in root:GetDescendants() do
				if d:IsA("Tool") then
					tools[#tools + 1] = d.Name
				elseif d:IsA("RemoteEvent") then
					re[#re + 1] = d.Name
				elseif d:IsA("RemoteFunction") then
					rf[#rf + 1] = d.Name
				end
			end
		end
		scan(ReplicatedStorage)
		scan(player:FindFirstChild("Backpack"))
		scan(player.Character)

		local parts = {}
		parts[#parts + 1] = ("ИТОГО Tool=%d RemoteEvent=%d RemoteFunction=%d"):format(#tools, #re, #rf)
		local function add(tag, arr)
			for _, n in ipairs(arr) do parts[#parts + 1] = tag .. ": " .. n end
		end
		add("Tool", tools)
		add("RemoteEvent", re)
		add("RemoteFunction", rf)

		-- структура ReplicatedStorage (2 уровня) — видно системы предметов
		for _, d in ReplicatedStorage:GetChildren() do
			parts[#parts + 1] = "RS: " .. d.Name .. " (" .. d.ClassName .. ")"
			if d:IsA("Folder") or d:IsA("Model") then
				local kids = d:GetChildren()
				for i = 1, math.min(#kids, 30) do
					parts[#parts + 1] = "   └ " .. kids[i].Name .. " (" .. kids[i].ClassName .. ")"
				end
				if #kids > 30 then
					parts[#parts + 1] = "   └ ...ещё " .. (#kids - 30)
				end
			end
		end

		-- печать в консоль (первые 150 строк)
		for i = 1, math.min(#parts, 150) do
			print("[Auras] DUMP " .. parts[i])
		end
		if #parts > 150 then
			print(("[Auras] DUMP ...ещё %d строк — они в буфере обмена"):format(#parts - 150))
		end

		-- копируем ВСЁ в буфер обмена: жмёшь Ctrl+V и вставляешь мне
		if type(setclipboard) == "function" then
			if pcall(setclipboard, "[Auras DUMP]\n" .. table.concat(parts, "\n")) then
				print("[Auras] DUMP скопирован в буфер обмена — вставь мне (Ctrl+V)")
			end
		end
	end)
end

-- =================================================================
-- 7. СКАНЕР ЦЕЛЕЙ (гуманоиды и не только)
-- =================================================================
local function buildEntry(model)
	if not model or model == player.Character then return nil end

	-- humanoid: прямой потомок или глубоко внутри (вложенные риги)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		humanoid = model:FindFirstChildWhichIsA("Humanoid", true)
	end

	-- корень: много вариантов (R15, R6, кастомные риги, Part-мобы)
	local root = nil
	if humanoid and humanoid.RootPart then root = humanoid.RootPart end
	if not root then root = model:FindFirstChild("HumanoidRootPart") end
	if not root then root = model:FindFirstChild("Torso") end
	if not root then root = model:FindFirstChild("RootPart") end
	if not root then root = model:FindFirstChild("UpperTorso") end
	if not root then root = model.PrimaryPart end
	if not root and humanoid then root = humanoid:FindFirstChildWhichIsA("BasePart", true) end
	if not root then root = model:FindFirstChildWhichIsA("BasePart", true) end
	if not root and model:IsA("BasePart") then root = model end -- Part-моб (сама деталь с HP)
	if not root then return nil end

	-- HP: humanoid -> атрибуты -> Value-объекты
	local health, maxHealth = nil, nil
	if humanoid then
		health = humanoid.Health
		maxHealth = humanoid.MaxHealth
	end
	if health == nil then health = readNumber(model, { "Health", "HP", "health", "hp" }) end
	if maxHealth == nil then maxHealth = readNumber(model, { "MaxHealth", "MaxHP", "Health", "HP" }) end
	if maxHealth and health and health > maxHealth then maxHealth = health end

	local pc = Players:GetPlayerFromCharacter(model)
	local isPlayer = pc ~= nil

	-- "узнается ли цель как враг": humanoid ИЛИ hp ИЛИ имя/тег
	local recognized = humanoid ~= nil
