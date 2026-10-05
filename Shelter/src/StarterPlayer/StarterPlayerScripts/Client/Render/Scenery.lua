--!strict
-- Wasteland scenery builder shared by the surface above the shelter and the exploration scene.
-- Layers (camera looks down -Z): sky (z -900) > mountains (-520) > skyline (-260) > mid props
-- (-14..-70) > ground strip (front face at z +5.6) > near props.
local MeshFactory = require(script.Parent.MeshFactory)

local Scenery = {}

local SKY_TOP = Color3.fromRGB(58, 72, 112)
local SKY_MID = Color3.fromRGB(178, 116, 112)
local SKY_LOW = Color3.fromRGB(250, 182, 112)
local HAZE = Color3.fromRGB(214, 146, 112)

Scenery.MID_PROPS = {
	{ "WL_RUIN_A", 0.9 }, { "WL_RUIN_B", 0.7 }, { "WL_RUIN_C", 1.0 }, { "WL_TREE_A", 1.2 }, { "WL_TREE_B", 1.2 },
	{ "WL_BUS", 0.4 }, { "WL_CAR", 0.9 }, { "WL_POLE", 0.9 }, { "WL_BILLBOARD", 0.5 }, { "WL_BOULDER_A", 1.0 },
	{ "WL_FENCE", 0.7 }, { "WL_BARRELS", 0.5 },
}
Scenery.NEAR_PROPS = {
	{ "WL_BOULDER_B", 1.2 }, { "WL_BOULDER_A", 0.6 }, { "WL_TREE_B", 0.5 }, { "WL_BARRELS", 0.4 }, { "WL_FENCE", 0.5 },
}

local function weighted(rng: Random, list)
	local total = 0
	for _, e in list do
		total += e[2]
	end
	local p = rng:NextNumber() * total
	for _, e in list do
		p -= e[2]
		if p <= 0 then
			return e[1]
		end
	end
	return list[1][1]
end
Scenery.weighted = weighted

local function gui(part: BasePart, canvas: Vector2): SurfaceGui
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Back -- +Z side, facing the camera
	sg.LightInfluence = 0
	sg.Brightness = 1
	sg.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	sg.CanvasSize = canvas
	sg.Parent = part
	return sg
end

local function plane(name: string, size: Vector3, cf: CFrame, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Material = Enum.Material.SmoothPlastic
	p.Parent = parent
	return p
end

-- Unlit dusk sky (gradient + sun disc + glow) on one plane. Roblox clamps parts to 2048 studs
-- per axis, so the plane is exactly that; the canvas is square so the sun stays round.
function Scenery.sky(parent: Instance, center: Vector3, horizonY: number)
	local sky = plane("Sky", Vector3.new(2048, 2048, 1), CFrame.new(center.X, horizonY + 600, -900), parent)
	sky.Color = SKY_TOP
	local sg = gui(sky, Vector2.new(512, 512))
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BorderSizePixel = 0
	f.BackgroundColor3 = Color3.new(1, 1, 1)
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	-- the horizon sits (1024 - 600) / 2048 = 0.79 down the canvas
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, SKY_TOP),
		ColorSequenceKeypoint.new(0.5, SKY_TOP:Lerp(SKY_MID, 0.5)),
		ColorSequenceKeypoint.new(0.68, SKY_MID),
		ColorSequenceKeypoint.new(0.77, SKY_LOW),
		ColorSequenceKeypoint.new(1, SKY_LOW),
	})
	g.Parent = f
	f.Parent = sg
	-- sun: soft glow + disc, just above the horizon, left of centre (matches the light direction)
	local sunX, sunY = 0.42, 0.772
	for i, spec in { { 0.11, 0.86, Color3.fromRGB(255, 196, 130) }, { 0.05, 0.62, Color3.fromRGB(255, 214, 150) }, { 0.02, 0, Color3.fromRGB(255, 240, 205) } } do
		local d = Instance.new("Frame")
		d.AnchorPoint = Vector2.new(0.5, 0.5)
		d.Position = UDim2.fromScale(sunX, sunY)
		d.Size = UDim2.fromScale(spec[1], spec[1])
		d.BackgroundColor3 = spec[3]
		d.BackgroundTransparency = spec[2]
		d.BorderSizePixel = 0
		d.ZIndex = 1 + i
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = d
		d.Parent = f
	end
	return sky
end

-- Warm haze in front of the distant skyline/mountains: aerial perspective at the horizon.
function Scenery.haze(parent: Instance, cx: number, horizonY: number)
	local p = plane("Haze", Vector3.new(2048, 420, 1), CFrame.new(cx, horizonY + 170, -236), parent)
	p.Transparency = 1
	local sg = gui(p, Vector2.new(512, 128))
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BorderSizePixel = 0
	f.BackgroundColor3 = HAZE
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0.9),
		NumberSequenceKeypoint.new(0.85, 0.64),
		NumberSequenceKeypoint.new(1, 0.56),
	})
	g.Parent = f
	f.Parent = sg
	return p
end

function Scenery.backdrop(parent: Instance, x0: number, horizonY: number)
	Scenery.haze(parent, x0, horizonY)
	MeshFactory.spawn("WL_MOUNTAINS", CFrame.new(x0 - 600, horizonY - 12, -520), nil, parent)
	MeshFactory.spawn("WL_MOUNTAINS", CFrame.new(x0 + 280, horizonY - 16, -560), nil, parent)
	MeshFactory.spawn("WL_SKYLINE", CFrame.new(x0 - 260, horizonY - 8, -260), nil, parent)
end

-- Flat plain from the back of the ground strip out to the mountains (no holes at any zoom).
function Scenery.farGround(parent: Instance, cx: number, y: number)
	local p = Instance.new("Part")
	p.Name = "FarGround"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.Sand
	p.Color = Color3.fromRGB(122, 98, 70)
	p.Size = Vector3.new(2048, 4, 760)
	p.CFrame = CFrame.new(cx, y - 2.3, -68 - 380)
	p.Parent = parent
	return p
end

function Scenery.ground(parent: Instance, x0: number, x1: number, y: number): { Model }
	local out = {}
	local i = 0
	local x = x0
	while x < x1 do
		table.insert(out, MeshFactory.spawn(if i % 2 == 0 then "WL_GROUND_A" else "WL_GROUND_B", CFrame.new(x, y, 0), nil, parent))
		x += 18
		i += 1
	end
	return out
end

-- Random mid/near props between x0..x1, skipping ranges in `avoid` ({ {a,b}, ... }).
function Scenery.props(parent: Instance, rng: Random, x0: number, x1: number, y: number, avoid: { { number } }?): { { model: Model, x: number, z: number } }
	local out = {}
	local function blocked(x: number, w: number)
		for _, a in avoid or {} do
			if x + w > a[1] and x - w < a[2] then
				return true
			end
		end
		return false
	end
	local x = x0
	while x < x1 do
		x += rng:NextNumber(10, 24)
		if not blocked(x, 8) then
			local name = weighted(rng, Scenery.MID_PROPS)
			local z = -rng:NextNumber(16, 70)
			local m = MeshFactory.spawn(name, CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(rng:NextNumber(-25, 25)), 0), nil, parent)
			table.insert(out, { model = m, x = x, z = z })
		end
	end
	x = x0
	while x < x1 do
		x += rng:NextNumber(18, 40)
		if not blocked(x, 6) then
			local name = weighted(rng, Scenery.NEAR_PROPS)
			local z = -rng:NextNumber(2, 10)
			local m = MeshFactory.spawn(name, CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(rng:NextNumber(-40, 40)), 0), nil, parent)
			table.insert(out, { model = m, x = x, z = z })
		end
	end
	return out
end

-- Wind-blown dust drifting across the surface.
function Scenery.dust(parent: Instance, center: Vector3, width: number)
	local p = Instance.new("Part")
	p.Name = "Dust"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.Transparency = 1
	p.Size = Vector3.new(width, 1, 40)
	p.Position = center
	p.Parent = parent
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Color = ColorSequence.new(Color3.fromRGB(196, 160, 120))
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.86), NumberSequenceKeypoint.new(1, 1) })
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 10) })
	e.Lifetime = NumberRange.new(6, 10)
	e.Rate = 6
	e.Speed = NumberRange.new(4, 9)
	e.EmissionDirection = Enum.NormalId.Right
	e.SpreadAngle = Vector2.new(10, 5)
	e.LightInfluence = 0.4
	e.Parent = p
	return p
end

return Scenery
