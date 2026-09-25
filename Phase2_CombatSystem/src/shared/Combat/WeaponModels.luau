--!nonstrict
--[[
	WeaponModels: the visible sword and bow, positioned every frame on the
	animated grip (so they work no matter how the rig was imported).

	Uses ReplicatedStorage.CombatAssets.Sword / .Bow if you add them (pivot =
	grip, +Y = blade / upper limb, bow string on +Z); otherwise builds a
	faithful stand-in from parts using the Phase 1 dimensions.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RigData = require(script.Parent.RigData)

local WeaponModels = {}

local STEEL = Color3.fromRGB(176, 178, 182)
local DARK = Color3.fromRGB(62, 62, 68)
local LEATHER = Color3.fromRGB(84, 52, 30)
local YEW = Color3.fromRGB(196, 128, 70)
local HORN = Color3.fromRGB(40, 32, 26)

local function part(model, name, size, cf, color, material, shape)
	local p = Instance.new("Part")
	p.Name = name
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = true
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local function sword(s)
	local d = RigData.swordDims
	local m = Instance.new("Model")
	m.Name = "Sword"
	local up = CFrame.Angles(0, 0, math.rad(90)) -- cylinder axis (X) -> +Y
	local gripY = (d.gripTop - d.gripLen / 2) * s
	part(m, "Grip", Vector3.new(d.gripLen, d.gripR * 2, d.gripR * 1.7) * s, CFrame.new(0, gripY, 0) * up, LEATHER,
		Enum.Material.Leather, Enum.PartType.Cylinder)
	part(m, "Guard", Vector3.new(d.guardSpan, d.guardH * 0.6, 0.06) * s, CFrame.new(0, (d.gripTop + d.guardH * 0.5) * s, 0),
		DARK, Enum.Material.Metal)
	local b0 = d.gripTop + d.guardH
	local mainLen = d.bladeLen * 0.86
	part(m, "Blade", Vector3.new((d.bladeW0 + d.bladeW1) * 0.5, mainLen, d.bladeT) * s,
		CFrame.new(0, (b0 + mainLen / 2) * s, 0), STEEL, Enum.Material.Metal)
	local tipLen = d.bladeLen - mainLen
	part(m, "Tip", Vector3.new(d.bladeW1 * 0.55, tipLen, d.bladeT * 0.8) * s,
		CFrame.new(0, (b0 + mainLen + tipLen / 2) * s, 0), STEEL, Enum.Material.Metal)
	local pommelY = (d.gripTop - d.gripLen - d.pommelR + 0.02) * s
	part(m, "Pommel", Vector3.new(0.1, d.pommelR * 2, d.pommelR * 2) * s,
		CFrame.new(0, pommelY, 0) * CFrame.Angles(0, math.rad(90), 0), DARK, Enum.Material.Metal, Enum.PartType.Cylinder)
	m.WorldPivot = CFrame.identity
	return m
end

local function bow(s)
	local d = RigData.bowDims
	local curve = RigData.bowCurve
	local m = Instance.new("Model")
	m.Name = "Bow"
	local half = curve[#curve][1]
	for i = 1, #curve - 1 do
		local a, b = curve[i], curve[i + 1]
		local p0 = Vector3.new(0, a[1], a[2]) * s
		local p1 = Vector3.new(0, b[1], b[2]) * s
		local mid = (p0 + p1) / 2
		local t = math.abs((a[1] + b[1]) / 2) / half
		local w = d.wGrip + (d.wTip - d.wGrip) * t
		local dep = d.dGrip + (d.dTip - d.dGrip) * t
		local len = (p1 - p0).Magnitude + 0.02 * s
		part(m, "Limb", Vector3.new(w * s, dep * s, len), CFrame.lookAt(mid, p1), YEW, Enum.Material.Wood)
	end
	part(m, "GripWrap", Vector3.new(d.wGrip * 1.25, d.gripHalf * 1.4, d.dGrip * 1.2) * s, CFrame.new(), LEATHER,
		Enum.Material.Leather)
	for _, sign in { 1, -1 } do
		local c = curve[sign > 0 and #curve or 1]
		part(m, "Nock", Vector3.new(d.wTip * 1.3, 0.16, d.dTip * 1.3) * s, CFrame.new(0, (c[1] - sign * 0.07) * s, c[2] * s),
			HORN, Enum.Material.SmoothPlastic)
	end
	m.WorldPivot = CFrame.identity
	return m
end

function WeaponModels.new(name: string, scale: number): Model
	local assets = ReplicatedStorage:FindFirstChild("CombatAssets")
	local template = assets and assets:FindFirstChild(name)
	local m
	if template then
		m = template:Clone()
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
			end
		end
	elseif name == "Sword" then
		m = sword(scale)
	else
		m = bow(scale)
	end
	m.Name = "Held" .. name
	return m
end

return WeaponModels
