-- Плавный лоадер: качает CrystalAnchorAuras с GitHub ПО ЧАСТЯМ
-- с прогресс-баром, вместо одного большого куска (так не вылетает)
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local BASE = "https://raw.githubusercontent.com/dimokayt-ai/crystal-anchor-auras/main/parts/"
local COUNT = 8

local function toast(text, color)
	local pg = player and player:FindFirstChild("PlayerGui")
	if not pg then return nil end
	local old = pg:FindFirstChild("AurasLoader")
	if old then old:Destroy() end
	local sg = Instance.new("ScreenGui")
	sg.Name = "AurasLoader"
	sg.ResetOnSpawn = false
	sg.Parent = pg
	local f = Instance.new("Frame")
	f.Size = UDim2.fromOffset(330, 74)
	f.Position = UDim2.new(0.5, -165, 0.35, 0)
	f.BackgroundColor3 = Color3.fromRGB(18, 18, 26)
	f.BorderSizePixel = 0
	f.Parent = sg
	Instance.new("UICorner", f).CornerRadius = UDim.new(0, 8)
	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(0, 0, 0, 6)
	bar.Position = UDim2.new(0, 8, 1, -14)
	bar.BackgroundColor3 = Color3.fromRGB(130, 100, 255)
	bar.BorderSizePixel = 0
	bar.Parent = f
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, -16, 0, 44)
	l.Position = UDim2.fromOffset(8, 6)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.Gotham
	l.TextSize = 14
	l.TextColor3 = color or Color3.fromRGB(225, 225, 235)
	l.TextWrapped = true
	l.Text = text
	l.Parent = f
	return sg, bar, l
end

local function fetchPart(i)
	local url = BASE .. "p" .. i .. ".lua"
	for _ = 1, 3 do
		local ok, data = pcall(function() return game:HttpGet(url) end)
		if ok and type(data) == "string" and #data > 100 and not data:find("^%s*<") then
			return data
		end
		task.wait(0.4)
	end
	return nil
end

local sg, bar, label = toast("Загрузка с GitHub...")
if not label then return end

local parts = {}
for i = 1, COUNT do
	label.Text = ("Загрузка: часть %d из %d..."):format(i, COUNT)
	bar.Size = UDim2.new((i - 1) / COUNT, 0, 0, 6)
	local data = fetchPart(i)
	if not data then
		toast("Не скачалась часть " .. i .. ". Проверь интернет/VPN и запусти ещё раз.",
			Color3.fromRGB(255, 120, 120))
		return
	end
	parts[#parts + 1] = data
	task.wait(0.08)
end

bar.Size = UDim2.new(1, -16, 0, 6)
label.Text = "Готово, запускаю..."
local fn, err = loadstring(table.concat(parts))
if not fn then
	toast("Ошибка компиляции: " .. tostring(err), Color3.fromRGB(255, 120, 120))
	return
end
local ok, runErr = xpcall(fn, debug.traceback)
if not ok then
	toast("Ошибка запуска: " .. tostring(runErr), Color3.fromRGB(255, 120, 120))
	return
end
task.wait(0.6)
if sg and sg.Parent then sg:Destroy() end
