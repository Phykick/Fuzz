--!nonstrict
--[[
	Builds an arrow visual. If ReplicatedStorage.CombatAssets.Arrow exists (e.g.
	an import of export/fbx/Arrow_Battlefield.fbx) it is cloned; otherwise a
	light procedural arrow is built from parts.
	Pivot = nock (string groove); the arrow points along -Z (LookVector), so
	`model:PivotTo(CFrame.lookAt(nock, target))` aims it.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RigData = require(script.Parent.RigData)

local ArrowModel = {}

local LENGTH = RigData.arrowLength

local function part(parent, name, size, cf, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.Wood
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	p.Parent = parent
	return p
end

local function procedural(): Model
	local m = Instance.new("Model")
	m.Name = "Arrow"
	local shaft = part(m, "Shaft", Vector3.new(0.045, 0.045, LENGTH - 0.25),
		CFrame.new(0, 0, -(LENGTH - 0.25) / 2), Color3.fromRGB(188, 158, 112))
	part(m, "Arrowhead", Vector3.new(0.05, 0.05, 0.28), CFrame.new(0, 0, -LENGTH + 0.12),
		Color3.fromRGB(58, 56, 55), Enum.Material.Metal)
	for i = 0, 2 do
		local a = math.rad(90 + i * 120)
		local cf = CFrame.new(0, 0, -0.42) * CFrame.Angles(0, 0, a) * CFrame.new(0, 0.04, 0)
		local vane = part(m, "Fletching", Vector3.new(0.004, 0.06, 0.55), cf, Color3.fromRGB(122, 122, 128),
			Enum.Material.Fabric)
		vane.Transparency = 0.05
	end
	part(m, "Nock", Vector3.new(0.05, 0.05, 0.06), CFrame.new(0, 0, -0.03), Color3.fromRGB(40, 32, 26),
		Enum.Material.SmoothPlastic)
	m.PrimaryPart = shaft
	m.WorldPivot = CFrame.identity
	return m
end

function ArrowModel.new(): Model
	local assets = ReplicatedStorage:FindFirstChild("CombatAssets")
	local template = assets and assets:FindFirstChild("Arrow")
	local m
	if template then
		m = template:Clone()
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				d.Massless = true
			end
		end
	else
		m = procedural()
	end
	return m
end

return ArrowModel
