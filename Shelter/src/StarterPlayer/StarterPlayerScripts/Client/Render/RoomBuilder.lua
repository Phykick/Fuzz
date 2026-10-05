--!strict
-- Assembles a complete room diorama (shell modules, end walls, dressing, lights, animators)
-- from Blender assets. Pure client-side; driven by VaultRenderer.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local MeshFactory = require(script.Parent.MeshFactory)
local RoomDressing = require(script.Parent.RoomDressing)

local RoomBuilder = {}

local MW = Config.MODULE_WIDTH
local FLOOR = Config.FLOOR_Y

export type Built = {
	model: Model,
	host: BasePart,
	hitbox: BasePart,
	animators: { (dt: number, t: number) -> () },
	lights: { PointLight },
	work: { { pos: Vector3, face: number, action: string } },
	-- errand seats by kind: eat, drink, sleep, treat (pos includes any height, e.g. a top bunk)
	spots: { [string]: { { pos: Vector3, face: number, action: string } } },
	width: number,
	tags: { [string]: Model },
}

local function lightAt(host: BasePart, cf: CFrame, color: Color3, range: number, brightness: number, shadows: boolean): PointLight
	local anchor = Instance.new("Attachment")
	anchor.Name = "LightAnchor"
	anchor.Parent = host
	anchor.WorldCFrame = cf
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = shadows
	l.Parent = anchor
	return l
end

local function makeAnimator(kind: string, target: Model?, light: PointLight?, speed: number, baseCF: CFrame?): ((number, number) -> ())?
	local seed = math.random() * 10
	if kind == "spinZ" and target and baseCF then
		local angle = 0
		return function(dt)
			angle += dt * speed
			target:PivotTo(baseCF * CFrame.Angles(0, 0, angle))
		end
	elseif kind == "beacon" then
		local parts = target and target:GetChildren() or {}
		return function(_, t)
			local on = math.sin((t + seed) * 5) > 0.2
			for _, p in parts do
				if (p :: BasePart).Material == Enum.Material.Neon then
					(p :: BasePart).Transparency = if on then 0 else 0.55
				end
			end
			if light then
				light.Enabled = on
			end
		end
	elseif kind == "hum" and light then
		local b = light.Brightness
		return function(_, t)
			light.Brightness = b * (0.85 + 0.15 * math.sin((t + seed) * 7) + 0.05 * math.sin((t + seed) * 23))
		end
	elseif kind == "sway" and target and baseCF then
		return function(_, t)
			target:PivotTo(baseCF * CFrame.Angles(math.sin(t * 1.3 + seed) * 0.025, 0, math.sin(t * 0.9 + seed) * 0.035))
		end
	elseif kind == "pulse" and target then
		local parts = target:GetChildren()
		return function(_, t)
			local a = 0.15 + 0.15 * math.sin((t + seed) * 2.2)
			for _, p in parts do
				if (p :: BasePart).Material == Enum.Material.Neon then
					(p :: BasePart).Transparency = a
				end
			end
		end
	end
	return nil
end

local function placeProp(parent: Instance, prop: RoomDressing.Prop, moduleCF: CFrame, tints, theme, out: Built)
	local cf = moduleCF * CFrame.new(prop.pos[1], FLOOR + prop.pos[2], prop.pos[3]) * CFrame.Angles(0, math.rad(prop.rot or 0), 0)
	local model = MeshFactory.spawn(prop.asset, cf, tints, parent)
	if prop.scale and prop.scale ~= 1 then
		model:ScaleTo(prop.scale)
	end
	if prop.fx then
		-- small ambient effects: steam over pots, sparks at a workbench
		local mk = MeshFactory.marker(prop.asset, prop.fx.marker) or CFrame.identity
		local a = Instance.new("Attachment")
		a.Parent = out.host
		a.WorldCFrame = cf * mk
		local e = Instance.new("ParticleEmitter")
		if prop.fx.kind == "sparks" then
			e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			e.Color = ColorSequence.new(Color3.fromRGB(255, 200, 90), Color3.fromRGB(255, 110, 40))
			e.LightEmission = 1
			e.Size = NumberSequence.new(0.18, 0)
			e.Lifetime = NumberRange.new(0.25, 0.5)
			e.Speed = NumberRange.new(4, 8)
			e.SpreadAngle = Vector2.new(60, 60)
			e.Acceleration = Vector3.new(0, -18, 0)
			e.Rate = 0
			local t0 = math.random() * 3
			table.insert(out.animators, function(_, t)
				e.Rate = if math.sin((t + t0) * 1.7) > 0.6 then 45 else 0
			end)
		else
			e.Texture = "rbxasset://textures/particles/smoke_main.dds"
			e.Color = ColorSequence.new(Color3.fromRGB(235, 235, 235))
			e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
			e.Size = NumberSequence.new(0.4, 1.6)
			e.Lifetime = NumberRange.new(1.2, 2)
			e.Speed = NumberRange.new(1, 2)
			e.Rate = 5
		end
		e.EmissionDirection = Enum.NormalId.Top
		e.Parent = a
	end
	if prop.tag then
		out.tags[prop.tag] = model
		model:SetAttribute("BaseCFrame", cf)
	end
	if prop.anim then
		local fn = makeAnimator(prop.anim, model, nil, prop.speed or 1, cf)
		if fn then
			table.insert(out.animators, fn)
		end
	end
	if prop.attach then
		for _, a in prop.attach do
			local mk = MeshFactory.marker(prop.asset, a.marker) or CFrame.identity
			local acf = cf * mk
			local sub = MeshFactory.spawn(a.asset, acf, tints, model)
			if a.anim then
				local subLight: PointLight? = nil
				if a.anim == "beacon" then
					subLight = lightAt(out.host, acf * CFrame.new(0, 0.4, 0), Color3.fromHex("FF9A3C"), 6, 1.2, false)
					table.insert(out.lights, subLight :: PointLight)
				end
				local fn = makeAnimator(a.anim, sub, subLight, a.speed or 1, acf)
				if fn then
					table.insert(out.animators, fn)
				end
			end
		end
	end
	if prop.light then
		local L = prop.light
		local lcf
		if L.marker then
			lcf = cf * (MeshFactory.marker(prop.asset, L.marker) or CFrame.identity)
		else
			local o = L.offset or { 0, 1, 0 }
			lcf = cf * CFrame.new(o[1], o[2], o[3])
		end
		local color = theme[L.color] or Color3.new(1, 1, 1)
		local light = lightAt(out.host, lcf, color, L.range, L.brightness, false)
		table.insert(out.lights, light)
		if L.anim then
			local fn = makeAnimator(L.anim, nil, light, 1, nil)
			if fn then
				table.insert(out.animators, fn)
			end
		end
	end
	return model
end

-- origin: CFrame at the room's left edge, row base (slab bottom), z = 0.
function RoomBuilder.build(roomType: string, modules: number, level: number, origin: CFrame, parent: Instance?): Built
	local theme = Theme.room(roomType)
	local tints = theme
	local model = Instance.new("Model")
	model.Name = roomType
	local width = modules * MW
	local host = Instance.new("Part")
	host.Name = "LightHost"
	host.Anchored = true
	host.CanCollide = false
	host.CanQuery = false
	host.CanTouch = false
	host.Transparency = 1
	host.Size = Vector3.one * 0.2
	host.CFrame = origin
	host.Parent = model
	local out: Built = {
		model = model,
		host = host,
		hitbox = nil :: any,
		animators = {},
		lights = {},
		work = {},
		spots = {},
		width = width,
		tags = {},
	}
	local shell = Instance.new("Folder")
	shell.Name = "Shell"
	shell.Parent = model
	for m = 0, modules - 1 do
		local mcf = origin * CFrame.new(m * MW, 0, 0)
		MeshFactory.spawn("SHELL_ROOM_FLOOR_A", mcf, tints, shell)
		MeshFactory.spawn("SHELL_ROOM_CEIL_A", mcf, tints, shell)
		MeshFactory.spawn(if m % 2 == 0 then "SHELL_ROOM_WALL_A" else "SHELL_ROOM_WALL_B", mcf, tints, shell)
		local lightColor = theme.lightColor
		table.insert(out.lights, lightAt(out.host, mcf * CFrame.new(MW / 2, 10.1, -0.8), lightColor, 17, 1.35, true))
	end
	MeshFactory.spawn("SHELL_ROOM_END_L", origin, tints, shell)
	MeshFactory.spawn("SHELL_ROOM_END_R", origin * CFrame.new(width, 0, 0), tints, shell)

	local dressing = (RoomDressing :: any)[roomType]
	if dressing then
		local props = Instance.new("Folder")
		props.Name = "Props"
		props.Parent = model
		for m = 0, modules - 1 do
			local mcf = origin * CFrame.new(m * MW, 0, 0)
			for _, prop in dressing.module do
				placeProp(props, prop, mcf, tints, theme, out)
			end
			for lv = 2, level do
				local extra = dressing.level and dressing.level[lv]
				if extra then
					for _, prop in extra do
						placeProp(props, prop, mcf, tints, theme, out)
					end
				end
			end
			for _, w in dressing.work or {} do
				table.insert(out.work, {
					pos = (mcf * CFrame.new(w.x, FLOOR, w.z)).Position,
					face = w.face or 180,
					action = w.action,
				})
			end
			for kind, list in dressing.spots or {} do
				out.spots[kind] = out.spots[kind] or {}
				for _, w in list do
					table.insert(out.spots[kind], {
						pos = (mcf * CFrame.new(w.x, FLOOR + (w.y or 0), w.z)).Position,
						face = w.face or 180,
						action = w.action,
					})
				end
			end
		end
	end

	local hit = Instance.new("Part")
	hit.Name = "Hitbox"
	hit.Anchored = true
	hit.CanCollide = false
	hit.CanTouch = false
	hit.CanQuery = true
	hit.Transparency = 1
	hit.Size = Vector3.new(width, Config.ROW_HEIGHT, 1)
	hit.CFrame = origin * CFrame.new(width / 2, Config.ROW_HEIGHT / 2, 4.6)
	hit.Parent = model
	out.hitbox = hit
	model.Parent = parent
	return out
end

return RoomBuilder
