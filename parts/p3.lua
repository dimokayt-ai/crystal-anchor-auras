	end
	return nil
end

local function hasAnyTag(inst, tags)
	for _, tag in ipairs(tags or {}) do
		local ok, res = pcall(CollectionService.HasTag, CollectionService, inst, tag)
		if ok and res then return true end
	end
	return false
end

local function getOwnRoot()
	local char = player.Character
	if not char then return nil end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum and hum.RootPart then return hum.RootPart end
	return char:FindFirstChild("HumanoidRootPart")
end

local function myHpRatio()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and hum.MaxHealth > 0 then
		return hum.Health / hum.MaxHealth
	end
	return nil
end

-- Экипировка инструмента (должен быть в Backpack)
local function ensureEquipped(tool)
	local char = player.Character
	if not char or not tool or not tool.Parent then return false, false end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return false, false end
	if tool.Parent == char then return true, false end
	local backpack = player:FindFirstChild("Backpack")
	if tool.Parent ~= backpack then return false, false end
	local ok = pcall(function() hum:EquipTool(tool) end)
	if not ok then return false, false end
	local delay = CURRENT_SETTINGS and CURRENT_SETTINGS.equipDelay or 0
	if delay and delay > 0 then task.wait(delay) end
	return true, true
end

-- Опциональный поворот камеры к точке
local function aimCamera(pos)
	local cam = workspace.CurrentCamera
	local root = getOwnRoot()
	if not cam or not root then return end
	local ok = pcall(function()
		cam.CFrame = CFrame.lookAt(cam.CFrame.Position, pos)
	end)
	return ok
end

-- Клик мышью по экранной позиции точки (VirtualUser) — ЛКМ (сломать/удар)
local function virtualClick(worldPos)
	local cam = workspace.CurrentCamera
	if not cam then return false end
	local vp = cam:WorldToViewportPoint(worldPos)
	local ok = pcall(function()
		VirtualUser:CaptureController()
		VirtualUser:ClickButton1(Vector2.new(vp.X, vp.Y))
	end)
	return ok
end

-- ПКМ по точке: в этих играх ПКМ = установка, ЛКМ = сломать
local function pressRightClick(worldPos)
	local cam = workspace.CurrentCamera
	local sx, sy = 0, 0
	if cam then
		local vs = cam.ViewportSize
		sx, sy = vs.X / 2, vs.Y / 2
		if worldPos then
			local okv, vp = pcall(function() return cam:WorldToViewportPoint(worldPos) end)
			-- точка перед камерой и в экране — кликаем по ней, иначе в центр
			if okv and vp and vp.Z > 0 and vp.X >= 0 and vp.X <= vs.X and vp.Y >= 0 and vp.Y <= vs.Y then
				sx, sy = vp.X, vp.Y
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
	warn = nil,       -- текст предупреждения (например, низкое HP)
	warnAt = 0,
}

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
		if seen[src.inst] then return end
		seen[src.inst] = true
		src.score = scoreSource(src.name, src.type, src.exact)
