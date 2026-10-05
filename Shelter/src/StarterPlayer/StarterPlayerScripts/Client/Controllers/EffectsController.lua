--!strict
-- World-space feedback: collect bubbles, resource pops, fires, creature infestations, combat
-- tracers, damage numbers, level-up badges. Interactive billboards live in PlayerGui (required for taps on mobile).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Icons = require(ReplicatedStorage.Shared.Icons)
local RoomDefinitions = require(ReplicatedStorage.Shared.RoomDefinitions)
local Family = require(ReplicatedStorage.Shared.Family)
local MeshFactory = require(script.Parent.Parent:WaitForChild("Render"):WaitForChild("MeshFactory"))

local EffectsController = {}
local C: any

local player = Players.LocalPlayer
local guiFolder: ScreenGui
local fxFolder: Folder
local bubbles: { [string]: BillboardGui } = {}
local fires: { [string]: { folder: Folder, bar: BillboardGui, light: PointLight } } = {}
local RES_ICON = { Power = "power", Food = "food", Water = "water", MedPatch = "health", Materials = "build" }

local function anchorPart(pos: Vector3): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.one * 0.2
	p.Position = pos
	p.Parent = fxFolder
	return p
end

-- Collect bubbles --------------------------------------------------------------
local function setBubble(room)
	local existing = bubbles[room.id]
	local def = RoomDefinitions.Types[room.type]
	local ready = room.readySince ~= nil and def.produces ~= nil and not room.incident
	if not ready then
		if existing then
			existing:Destroy()
			bubbles[room.id] = nil
		end
		return
	end
	if existing then
		return
	end
	local center = C.VaultRenderer.roomCenter(room.id)
	if not center then
		return
	end
	local anchor = anchorPart(center + Vector3.new(0, 4.6, 4.8))
	local bb = Instance.new("BillboardGui")
	bb.Name = "Collect_" .. room.id
	bb.Adornee = anchor
	bb.Size = UDim2.fromOffset(64, 64)
	bb.AlwaysOnTop = true
	bb.Active = true
	bb.ResetOnSpawn = false
	bb.MaxDistance = 5000
	local btn = Instance.new("ImageButton")
	btn.Size = UDim2.fromScale(1, 1)
	btn.BackgroundColor3 = Theme.UI.panel
	btn.BackgroundTransparency = 0.05
	btn.Image = Icons[RES_ICON[def.produces] or "star"]
	btn.ImageColor3 = Theme.Resource[def.produces] or Theme.UI.accent
	btn.ScaleType = Enum.ScaleType.Fit
	btn.AutoButtonColor = true
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = btn
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Resource[def.produces] or Theme.UI.accent
	stroke.Thickness = 3
	stroke.Parent = btn
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = btn
	btn.Parent = bb
	btn.Activated:Connect(function()
		EffectsController.collect(room.id)
	end)
	bb.Parent = guiFolder
	bubbles[room.id] = bb
	bb.Destroying:Connect(function()
		anchor:Destroy()
	end)
	-- bob
	task.spawn(function()
		local t0 = os.clock()
		while bb.Parent do
			local t = os.clock() - t0
			bb.StudsOffsetWorldSpace = Vector3.new(0, math.abs(math.sin(t * 3.2)) * 0.9, 0)
			RunService.RenderStepped:Wait()
		end
	end)
end

function EffectsController.collect(roomId: string)
	local bb = bubbles[roomId]
	if bb then
		bb.Enabled = false
	end
	local ok = C.StateStore.action("Collect", { roomId = roomId })
	if not ok and bb then
		bb.Enabled = true
	end
end

function EffectsController.hasBubble(roomId: string): boolean
	return bubbles[roomId] ~= nil
end

-- Floating text -----------------------------------------------------------------
function EffectsController.float(pos: Vector3, text: string, color: Color3, icon: string?, big: boolean?)
	local anchor = anchorPart(pos)
	local bb = Instance.new("BillboardGui")
	bb.Adornee = anchor
	bb.Size = UDim2.fromOffset(if big then 180 else 120, if big then 44 else 32)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 5000
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.fromScale(1, 1)
	row.Parent = bb
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 4)
	layout.Parent = row
	if icon then
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.Size = UDim2.fromScale(0.26, 1)
		img.SizeConstraint = Enum.SizeConstraint.RelativeYY
		img.Image = Icons[icon] or ""
		img.ImageColor3 = color
		img.Parent = row
	end
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.AutomaticSize = Enum.AutomaticSize.X
	lbl.Size = UDim2.fromScale(0, 1)
	lbl.FontFace = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold)
	lbl.TextScaled = true
	lbl.Text = text
	lbl.TextColor3 = color
	lbl.TextStrokeTransparency = 0.2
	lbl.Parent = row
	bb.Parent = fxFolder
	local rise = Instance.new("NumberValue")
	rise.Changed:Connect(function(v)
		bb.StudsOffsetWorldSpace = Vector3.new(0, v * 3.5, 0)
		lbl.TextTransparency = math.max(0, (v - 0.6) / 0.4)
		lbl.TextStrokeTransparency = 0.2 + lbl.TextTransparency * 0.8
	end)
	TweenService:Create(rise, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = 1 }):Play()
	Debris:AddItem(anchor, 1.5)
	Debris:AddItem(bb, 1.5)
	Debris:AddItem(rise, 1.5)
end

-- Fire --------------------------------------------------------------------------
local function setFire(room)
	local burning = room.incident and room.incident.kind == "Fire"
	local f = fires[room.id]
	if not burning then
		if f then
			for _, d in f.folder:GetDescendants() do
				if d:IsA("ParticleEmitter") then
					d.Enabled = false
				end
			end
			f.bar:Destroy()
			Debris:AddItem(f.folder, 3)
			fires[room.id] = nil
		end
		return
	end
	if f then
		return
	end
	local x0, x1, floorY = C.VaultRenderer.roomBounds(room.id)
	if not x0 then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "Fire_" .. room.id
	folder.Parent = fxFolder
	local w = x1 - x0
	local n = math.max(2, math.floor(w / 6))
	for i = 1, n do
		local p = anchorPart(Vector3.new(x0 + w * (i - 0.5) / n + (math.random() - 0.5) * 2, floorY + 0.4, -1.5 + math.random() * 2.5))
		p.Parent = folder
		local fire = Instance.new("ParticleEmitter")
		fire.Texture = "rbxasset://textures/particles/fire_main.dds"
		fire.LightEmission = 1
		fire.LightInfluence = 0
		fire.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 230, 140)),
			ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 120, 40)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(160, 30, 10)),
		})
		fire.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.2), NumberSequenceKeypoint.new(1, 0.4) })
		fire.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		fire.Lifetime = NumberRange.new(0.6, 1.1)
		fire.Rate = 22
		fire.Speed = NumberRange.new(3, 6)
		fire.SpreadAngle = Vector2.new(12, 12)
		fire.Acceleration = Vector3.new(0, 4, 0)
		fire.EmissionDirection = Enum.NormalId.Top
		fire.Rotation = NumberRange.new(-30, 30)
		fire.Parent = p
		local smoke = Instance.new("ParticleEmitter")
		smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
		smoke.Color = ColorSequence.new(Color3.fromRGB(40, 36, 34))
		smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 5) })
		smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
		smoke.Lifetime = NumberRange.new(1.5, 2.5)
		smoke.Rate = 6
		smoke.Speed = NumberRange.new(2, 4)
		smoke.EmissionDirection = Enum.NormalId.Top
		smoke.Parent = p
	end
	local lightPart = anchorPart(Vector3.new((x0 + x1) / 2, floorY + 3, 1))
	lightPart.Parent = folder
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 120, 50)
	light.Range = math.min(30, w + 6)
	light.Brightness = 2.5
	light.Parent = lightPart
	-- HP bar
	local bb = Instance.new("BillboardGui")
	bb.Adornee = lightPart
	bb.StudsOffsetWorldSpace = Vector3.new(0, 6.2, 3.5)
	bb.Size = UDim2.fromOffset(150, 30)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 5000
	local back = Instance.new("Frame")
	back.Size = UDim2.new(1, 0, 0, 14)
	back.Position = UDim2.fromOffset(0, 14)
	back.BackgroundColor3 = Theme.UI.panel
	back.BorderSizePixel = 0
	back.Parent = bb
	Instance.new("UICorner").Parent = back
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Theme.UI.danger
	fill.BorderSizePixel = 0
	fill.Parent = back
	Instance.new("UICorner").Parent = fill
	local icon = Instance.new("ImageLabel")
	icon.BackgroundTransparency = 1
	icon.Image = Icons.fire
	icon.ImageColor3 = Color3.fromRGB(255, 140, 60)
	icon.Size = UDim2.fromOffset(26, 26)
	icon.Position = UDim2.fromOffset(-30, 8)
	icon.Parent = bb
	bb.Parent = fxFolder
	fires[room.id] = { folder = folder, bar = bb, light = light }
end

-- Creature infestations ------------------------------------------------------------
type Critter = { model: Model, x: number, z: number, tx: number, tz: number, pause: number, yaw: number }
type Infestation = {
	folder: Folder, bar: BillboardGui, critters: { Critter }, kind: string, shotAcc: number,
	x0: number, x1: number, fy: number, total: number,
}
local infestations: { [string]: Infestation } = {}
local CRITTER = {
	Rats = { mesh = "CRT_BURROWRAT", scale = 0.62, speed = 5, color = Color3.fromRGB(190, 150, 120) },
	Roaches = { mesh = "CRT_RUSTROACH", scale = 0.95, speed = 7, color = Color3.fromRGB(150, 80, 40) },
}

local function poof(pos: Vector3, color: Color3)
	local p = anchorPart(pos)
	p.Transparency = 0.3
	p.Shape = Enum.PartType.Ball
	p.Material = Enum.Material.SmoothPlastic
	p.Color = color
	p.Size = Vector3.one * 0.8
	TweenService:Create(p, TweenInfo.new(0.4), { Size = Vector3.one * 2.6, Transparency = 1 }):Play()
	Debris:AddItem(p, 0.45)
end

local function healthBar(adornee: BasePart, icon: string, iconColor: Color3): BillboardGui
	local bb = Instance.new("BillboardGui")
	bb.Adornee = adornee
	bb.StudsOffsetWorldSpace = Vector3.new(0, 6.2, 3.5)
	bb.Size = UDim2.fromOffset(150, 30)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 5000
	local back = Instance.new("Frame")
	back.Size = UDim2.new(1, 0, 0, 14)
	back.Position = UDim2.fromOffset(0, 14)
	back.BackgroundColor3 = Theme.UI.panel
	back.BorderSizePixel = 0
	back.Parent = bb
	Instance.new("UICorner").Parent = back
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(150, 200, 80)
	fill.BorderSizePixel = 0
	fill.Parent = back
	Instance.new("UICorner").Parent = fill
	local ic = Instance.new("ImageLabel")
	ic.BackgroundTransparency = 1
	ic.Image = Icons[icon]
	ic.ImageColor3 = iconColor
	ic.Size = UDim2.fromOffset(26, 26)
	ic.Position = UDim2.fromOffset(-30, 8)
	ic.Parent = bb
	bb.Parent = fxFolder
	return bb
end

local function setCreatures(room)
	local inc = room.incident
	local spec = inc and CRITTER[inc.kind]
	local cur = infestations[room.id]
	if not spec then
		if cur then
			for _, c in cur.critters do
				poof(c.model:GetPivot().Position + Vector3.new(0, 0.6, 0), CRITTER[cur.kind].color)
			end
			cur.bar:Destroy()
			cur.folder:Destroy()
			infestations[room.id] = nil
		end
		return
	end
	if cur then
		return
	end
	local x0, x1, floorY = C.VaultRenderer.roomBounds(room.id)
	if not x0 then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "Critters_" .. room.id
	folder.Parent = fxFolder
	local critters = {}
	for _ = 1, inc.count or 3 do
		local x = x0 + 2 + math.random() * math.max(0.5, x1 - x0 - 4)
		local z = -1.6 + math.random() * 3.2
		local m = MeshFactory.spawn(spec.mesh, CFrame.new(x, floorY, z), nil, folder)
		if spec.scale ~= 1 then
			m:ScaleTo(spec.scale)
		end
		for _, p in m:GetDescendants() do
			if p:IsA("BasePart") then
				p.CanQuery = false
				p.CanCollide = false
				p.CanTouch = false
			end
		end
		table.insert(critters, { model = m, x = x, z = z, tx = x, tz = z, pause = math.random(), yaw = math.random() * 6.28 })
	end
	local anchor = anchorPart(Vector3.new((x0 + x1) / 2, floorY + 3, 1))
	anchor.Parent = folder
	infestations[room.id] = {
		folder = folder, bar = healthBar(anchor, "raid", spec.color), critters = critters, kind = inc.kind,
		shotAcc = 0, x0 = x0, x1 = x1, fy = floorY, total = #critters,
	}
end

-- Breakdowns: smoke and sparks from dead machinery, with a repair progress bar.
local breakdowns: { [string]: { folder: Folder, bar: BillboardGui } } = {}

local function setBreakdown(room)
	local broken = room.incident and room.incident.kind == "Breakdown"
	local cur = breakdowns[room.id]
	if not broken then
		if cur then
			cur.bar:Destroy()
			for _, d in cur.folder:GetDescendants() do
				if d:IsA("ParticleEmitter") then
					d.Enabled = false
				end
			end
			Debris:AddItem(cur.folder, 3)
			breakdowns[room.id] = nil
		end
		return
	end
	if cur then
		return
	end
	local x0, x1, floorY = C.VaultRenderer.roomBounds(room.id)
	if not x0 then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "Breakdown_" .. room.id
	folder.Parent = fxFolder
	local w = x1 - x0
	for i = 1, math.max(1, math.floor(w / 9)) do
		local p = anchorPart(Vector3.new(x0 + w * (i - 0.5) / math.max(1, math.floor(w / 9)), floorY + 3.5, -3))
		p.Parent = folder
		local smoke = Instance.new("ParticleEmitter")
		smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
		smoke.Color = ColorSequence.new(Color3.fromRGB(60, 58, 56))
		smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 4) })
		smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
		smoke.Lifetime = NumberRange.new(2, 3)
		smoke.Rate = 4
		smoke.Speed = NumberRange.new(1.5, 3)
		smoke.EmissionDirection = Enum.NormalId.Top
		smoke.Parent = p
		local sparks = Instance.new("ParticleEmitter")
		sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparks.Color = ColorSequence.new(Color3.fromRGB(255, 210, 120), Color3.fromRGB(255, 120, 40))
		sparks.LightEmission = 1
		sparks.Size = NumberSequence.new(0.2, 0)
		sparks.Lifetime = NumberRange.new(0.3, 0.6)
		sparks.Speed = NumberRange.new(5, 10)
		sparks.SpreadAngle = Vector2.new(70, 70)
		sparks.Acceleration = Vector3.new(0, -20, 0)
		sparks.Rate = 6
		sparks.Parent = p
	end
	local anchor = anchorPart(Vector3.new((x0 + x1) / 2, floorY + 3, 1))
	anchor.Parent = folder
	local bar = healthBar(anchor, "build", Color3.fromRGB(255, 200, 80))
	local fill = bar:FindFirstChild("Fill", true) :: Frame?
	if fill then
		fill.BackgroundColor3 = Color3.fromRGB(255, 196, 60)
		fill.Size = UDim2.fromScale(math.clamp(room.incident.hp or 0, 0, 1), 1)
	end
	breakdowns[room.id] = { folder = folder, bar = bar }
end

local function stepCreatures(dt: number)
	local t = os.clock()
	local state = C.StateStore.state
	for roomId, inf in infestations do
		local spec = CRITTER[inf.kind]
		for _, c in inf.critters do
			c.pause -= dt
			if c.pause <= 0 then
				local dx, dz = c.tx - c.x, c.tz - c.z
				local dist = math.sqrt(dx * dx + dz * dz)
				if dist < 0.2 then
					c.tx = inf.x0 + 2 + math.random() * math.max(0.5, inf.x1 - inf.x0 - 4)
					c.tz = -1.6 + math.random() * 3.2
					c.pause = math.random() * 1.1
				else
					local stepLen = math.min(dist, spec.speed * dt)
					c.x += dx / dist * stepLen
					c.z += dz / dist * stepLen
					c.yaw = math.atan2(dx, dz) -- meshes face +Z at rest
				end
			end
			local bob = if c.pause > 0 then 0 else math.abs(math.sin(t * 16 + c.x)) * 0.12
			c.model:PivotTo(CFrame.new(c.x, inf.fy + bob, c.z) * CFrame.Angles(0, c.yaw, 0))
		end
		-- armed survivors in the room take shots at them
		inf.shotAcc += dt
		if inf.shotAcc > 0.4 and #inf.critters > 0 then
			inf.shotAcc = 0
			local shooters = {}
			for id, d in state.dwellers do
				if d.roomId == roomId and d.weapon and (d.status == "Working" or d.status == "Idle") and Family.canFight(d) then
					table.insert(shooters, id)
				end
			end
			if #shooters > 0 then
				local from = C.DwellerController.headPosition(shooters[math.random(1, #shooters)])
				local c = inf.critters[math.random(1, #inf.critters)]
				if from then
					EffectsController.tracer(from - Vector3.new(0, 0.9, 0), Vector3.new(c.x, inf.fy + 0.6, c.z))
				end
			end
		end
	end
end

function EffectsController.updateFireBar(roomId: string, hp: number, maxHp: number)
	local bd = breakdowns[roomId]
	if bd then
		local fill = bd.bar:FindFirstChild("Fill", true) :: Frame?
		if fill then
			TweenService:Create(fill, TweenInfo.new(0.4), { Size = UDim2.fromScale(math.clamp(hp / maxHp, 0, 1), 1) }):Play()
		end
	end
	local inf = infestations[roomId]
	if inf then
		local fill = inf.bar:FindFirstChild("Fill", true) :: Frame?
		if fill then
			TweenService:Create(fill, TweenInfo.new(0.4), { Size = UDim2.fromScale(math.clamp(hp / maxHp, 0, 1), 1) }):Play()
		end
		-- fewer critters as the infestation is beaten back
		local want = math.max(1, math.ceil(inf.total * math.clamp(hp / maxHp, 0, 1)))
		while #inf.critters > want do
			local c = table.remove(inf.critters) :: Critter
			poof(c.model:GetPivot().Position + Vector3.new(0, 0.6, 0), CRITTER[inf.kind].color)
			c.model:Destroy()
		end
	end
	local f = fires[roomId]
	if f then
		local fill = f.bar:FindFirstChild("Fill", true) :: Frame?
		if fill then
			TweenService:Create(fill, TweenInfo.new(0.4), { Size = UDim2.fromScale(math.clamp(hp / maxHp, 0, 1), 1) }):Play()
		end
	end
end

function EffectsController.isBurning(roomId: string): boolean
	return fires[roomId] ~= nil
end

-- Combat ------------------------------------------------------------------------
function EffectsController.tracer(from: Vector3, to: Vector3, color: Color3?)
	local dist = (to - from).Magnitude
	if dist < 0.1 then
		return
	end
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.Neon
	p.Color = color or Color3.fromRGB(255, 214, 120)
	p.Size = Vector3.new(0.09, 0.09, dist)
	p.CFrame = CFrame.lookAt((from + to) / 2, to)
	p.CastShadow = false
	p.Parent = fxFolder
	TweenService:Create(p, TweenInfo.new(0.12), { Transparency = 1, Size = Vector3.new(0.02, 0.02, dist) }):Play()
	Debris:AddItem(p, 0.15)
	local flash = Instance.new("Part")
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.CanTouch = false
	flash.Shape = Enum.PartType.Ball
	flash.Material = Enum.Material.Neon
	flash.Color = Color3.fromRGB(255, 200, 90)
	flash.Size = Vector3.one * 0.6
	flash.Position = from
	flash.CastShadow = false
	flash.Parent = fxFolder
	local l = Instance.new("PointLight")
	l.Color = Color3.fromRGB(255, 190, 90)
	l.Range = 8
	l.Brightness = 3
	l.Parent = flash
	TweenService:Create(flash, TweenInfo.new(0.08), { Transparency = 1, Size = Vector3.one * 1.1 }):Play()
	Debris:AddItem(flash, 0.1)
end

function EffectsController.damage(pos: Vector3, amount: number, crit: boolean, friendly: boolean)
	local text = tostring(math.floor(amount + 0.5)) .. (if crit then "!" else "")
	EffectsController.float(pos, text, if friendly then Theme.UI.danger else Color3.fromRGB(255, 232, 160), nil, crit)
end

function EffectsController.Init(controllers)
	C = controllers
	guiFolder = Instance.new("ScreenGui")
	guiFolder.Name = "WorldUI"
	guiFolder.ResetOnSpawn = false
	guiFolder.IgnoreGuiInset = true
	guiFolder.Parent = player:WaitForChild("PlayerGui")
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "UH_Effects"
	fxFolder.Parent = workspace
end

function EffectsController.Start()
	local S = C.StateStore
	local function refreshRoom(room)
		setBubble(room)
		setFire(room)
		setCreatures(room)
		setBreakdown(room)
		if room.incident and room.incident.hp then
			EffectsController.updateFireBar(room.id, room.incident.hp, room.incident.maxHp)
		end
	end
	S.Snapshot:Connect(function(state)
		task.defer(function()
			for _, r in state.rooms do
				refreshRoom(r)
			end
		end)
	end)
	S.RoomChanged:Connect(function(room)
		task.defer(refreshRoom, room)
	end)
	S.RoomRemoved:Connect(function(id)
		if bubbles[id] then
			bubbles[id]:Destroy()
			bubbles[id] = nil
		end
	end)
	S.Fire:Connect(function(updates)
		for _, u in updates do
			EffectsController.updateFireBar(u.roomId, u.hp, u.maxHp)
		end
	end)
	S.Collected:Connect(function(p)
		local center = C.VaultRenderer.roomCenter(p.roomId)
		if center and p.amount > 0 then
			local icon = RES_ICON[p.resource] or "star"
			EffectsController.float(center + Vector3.new(0, 2, 5), "+" .. p.amount, Theme.Resource[p.resource] or Theme.UI.text, icon, true)
			if p.bolts and p.bolts > 0 then
				task.delay(0.25, function()
					EffectsController.float(center + Vector3.new(3, 1, 5), "+" .. p.bolts, Theme.Resource.Bolts, "bolts")
				end)
			end
		elseif center and p.full then
			EffectsController.float(center + Vector3.new(0, 2, 5), "STORAGE FULL", Theme.UI.danger)
		end
	end)
	RunService.RenderStepped:Connect(stepCreatures)
	S.LevelUp:Connect(function(p)
		local pos = C.DwellerController.headPosition(p.id)
		if pos then
			EffectsController.float(pos + Vector3.new(0, 1.2, 1), "LEVEL " .. p.level .. "!", Theme.UI.xp, "star", true)
		end
	end)
end

local _ = Config
return EffectsController
