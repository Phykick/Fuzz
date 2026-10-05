--!strict
-- The world above the shelter: dusk sky, mountains, ruined skyline, ground strip, props and the
-- bunker entrance over the blast door. Explorers visibly leave/return across the surface,
-- wanderers walk in from wherever they appeared, and raiders gather at the bunker while they breach.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Grid = require(ReplicatedStorage.Shared.Grid)
local DwellerDefinitions = require(ReplicatedStorage.Shared.DwellerDefinitions)
local CharacterRig = require(ReplicatedStorage.Shared.CharacterRig)
local ItemDefinitions = require(ReplicatedStorage.Shared.ItemDefinitions)

local Render = script.Parent.Parent:WaitForChild("Render")
local MeshFactory = require(Render.MeshFactory)
local Scenery = require(Render.Scenery)
local CharacterFactory = require(Render.CharacterFactory)
local Animator = require(Render.Animator)

local SurfaceController = {}
local C: any

SurfaceController.SURFACE_Y = 24
local SY = SurfaceController.SURFACE_Y
local folder: Folder
local bunkerX = 63
local built = false

type Walker = {
	handle: any, anim: any, x: number, dir: number, t0: number, kind: string, done: boolean,
	approach: any?, waiting: boolean?, slot: number?, waveUntil: number?,
}
local walkerFolder: Folder
local walkers: { [string]: Walker } = {}

local function entranceX(): number
	for _, r in C.StateStore.state.rooms do
		if r.type == "Entrance" then
			return Grid.roomCenterX(r)
		end
	end
	return 63
end

local function build()
	if built then
		return
	end
	built = true
	bunkerX = entranceX()
	local x0 = -26 * Config.UNIT
	local x1 = (Config.GRID_COLS + 26) * Config.UNIT
	Scenery.sky(folder, Vector3.new(bunkerX, 0, 0), SY)
	Scenery.backdrop(folder, bunkerX, SY)
	Scenery.ground(folder, x0, x1, SY)
	Scenery.farGround(folder, bunkerX, SY)
	local rng = Random.new((C.StateStore.state.shelterNo or 1) * 31)
	Scenery.props(folder, rng, x0, x1, SY, { { bunkerX - 14, bunkerX + 14 } })
	local bunker = MeshFactory.spawn("WL_BUNKER", CFrame.new(bunkerX, SY, -1.5), nil, folder)
	bunker.Name = "Bunker"
	Scenery.dust(folder, Vector3.new(bunkerX, SY + 3, -10), 600)
	-- warm practical light at the bunker so the entrance reads at dusk
	local lp = Instance.new("Part")
	lp.Anchored = true
	lp.CanCollide = false
	lp.CanQuery = false
	lp.Transparency = 1
	lp.Position = Vector3.new(bunkerX, SY + 7, 6)
	lp.Parent = folder
	local l = Instance.new("PointLight")
	l.Color = Color3.fromRGB(255, 196, 130)
	l.Range = 26
	l.Brightness = 1.4
	l.Parent = lp
end

local function lookFor(d)
	return CharacterFactory.lookFor(d)
end

local function removeWalker(key: string)
	local w = walkers[key]
	if w then
		w.handle.model:Destroy()
		walkers[key] = nil
	end
end

local function addWalker(key: string, appearance, look, x: number, dir: number, kind: string)
	removeWalker(key)
	local handle = CharacterFactory.build(appearance, look)
	handle.model.Parent = walkerFolder
	CharacterFactory.setWeaponVisible(handle, kind == "raider")
	local anim = Animator.new(handle.motors, #key)
	anim:setParam("weapon", look.weapon)
	walkers[key] = { handle = handle, anim = anim, x = x, dir = dir, t0 = os.clock(), kind = kind, done = false }
end

-- Explorers: show a walker for ~25 s after departure and before arrival.
local function syncExplorers()
	local state = C.StateStore.state
	local now = C.StateStore.now()
	local wanted = {}
	for id, rec in state.exploration or {} do
		local d = state.dwellers[id]
		if d then
			local key = "x:" .. id
			if not rec.returning and now - rec.start < 24 then
				wanted[key] = true
				if not walkers[key] then
					addWalker(key, d.appearance, lookFor(d), bunkerX, 1, "out")
				end
			elseif rec.returning and rec.returnStart + rec.returnDur - now < 18 and rec.returnStart + rec.returnDur - now > 0 then
				wanted[key] = true
				if not walkers[key] then
					local remaining = rec.returnStart + rec.returnDur - now
					addWalker(key, d.appearance, lookFor(d), bunkerX + remaining * Config.WALK_SPEED, -1, "home")
				end
			end
		end
	end
	-- wanderers: walking up (server-timed approach.start -> approach.enter), then waiting in line
	-- to the right of the bunker door until they are let in or turned away. Tap one to decide.
	local line = {}
	for _, d in state.dwellers do
		if (d.status == "Arriving" or d.status == "Waiting") and d.approach then
			table.insert(line, d)
		end
	end
	table.sort(line, function(a, b)
		return a.approach.start < b.approach.start
	end)
	for i, d in line do
		local key = "a:" .. d.id
		wanted[key] = true
		local a = d.approach
		if not walkers[key] then
			local k = math.clamp((now - a.start) / math.max(0.1, a.enter - a.start), 0, 1)
			addWalker(key, d.appearance, lookFor(d), a.fromX + (a.toX - a.fromX) * k, if a.toX >= a.fromX then 1 else -1, "arrive")
			walkers[key].handle.clickBox:SetAttribute("DwellerId", d.id)
		end
		local w = walkers[key]
		w.approach = a
		w.waiting = d.status == "Waiting"
		w.slot = i
	end
	local raid = state.raid
	if raid and raid.phase == "door" then
		local i = 0
		for rid, r in raid.raiders or {} do
			i += 1
			local key = "r:" .. rid
			wanted[key] = true
			if not walkers[key] then
				local appearance, look = CharacterFactory.raiderLook(r.seed or i)
				look.weapon = r.weapon
				addWalker(key, appearance, look, bunkerX - 40 - i * 3, 1, "raider")
				walkers[key].handle.model:SetAttribute("Slot", i)
			end
		end
	end
	for key in walkers do
		if not wanted[key] then
			removeWalker(key)
		end
	end
end

local function slotX(i: number): number
	return bunkerX + 12 + (i - 1) * 2.4
end

-- Where a wanderer outside is right now (for LOOK buttons and camera focus).
function SurfaceController.arrivalPosition(id: string): Vector3?
	local w = walkers["a:" .. id]
	if w then
		return Vector3.new(w.x, SY + 3, 0)
	end
	local d = C.StateStore.state.dwellers[id]
	local a = d and d.approach
	if not a then
		return nil
	end
	local k = math.clamp((C.StateStore.now() - a.start) / math.max(0.1, a.enter - a.start), 0, 1)
	return Vector3.new(a.fromX + (a.toX - a.fromX) * k, SY + 3, 0)
end

-- Camera target for the line outside the bunker door.
function SurfaceController.doorPosition(): Vector3
	return Vector3.new(bunkerX + 13, SY + 4, 0)
end

function SurfaceController.Init(controllers)
	C = controllers
	folder = Instance.new("Folder")
	folder.Name = "Surface"
	folder.Parent = workspace
	walkerFolder = Instance.new("Folder")
	walkerFolder.Name = "Walkers"
	walkerFolder.Parent = folder
end

function SurfaceController.Start()
	local S = C.StateStore
	S.Snapshot:Connect(function()
		build()
		syncExplorers()
	end)
	S.ExploreChanged:Connect(syncExplorers)
	S.DwellerChanged:Connect(syncExplorers)
	S.DwellerRemoved:Connect(syncExplorers)
	S.ExploreEnded:Connect(syncExplorers)
	S.Raid:Connect(syncExplorers)
	S.RaidEnd:Connect(syncExplorers)
	if S.state.ready then
		build()
	end
	local acc = 0
	RunService.RenderStepped:Connect(function(dt)
		acc += dt
		if acc > 1 then
			acc = 0
			syncExplorers()
		end
		local x0, x1, y0, y1 = C.CameraController.visibleRect(10)
		local visible = y1 > SY - 4
		for key, w in walkers do
			if w.kind == "raider" then
				local slot = w.handle.model:GetAttribute("Slot") or 1
				local target = bunkerX - 6 - slot * 2.4
				if w.x < target then
					w.x = math.min(target, w.x + Config.WALK_SPEED * 1.3 * dt)
					w.anim:play("Run")
				else
					w.anim:play("Shoot")
					if math.random() < dt * 1.2 then
						w.anim:kick()
						local muzzle = w.handle.root.Position + Vector3.new(1.2, 1.3, 0)
						C.EffectsController.tracer(muzzle, Vector3.new(bunkerX, SY + 3.6 + math.random() * 1.5, 4.2), Color3.fromRGB(255, 120, 90))
					end
				end
				w.handle.root.CFrame = CFrame.new(w.x, SY + CharacterRig.HIP_HEIGHT * w.handle.scale, 1 + (slot % 2) * 1.4) * CFrame.Angles(0, -math.pi / 2, 0)
			elseif w.kind == "arrive" then
				local a = w.approach
				local face = w.dir
				if not w.waiting then
					local k = math.clamp((C.StateStore.now() - a.start) / math.max(0.1, a.enter - a.start), 0, 1)
					w.x = a.fromX + (a.toX - a.fromX) * k
					w.anim:play(if k < 1 then "Walk" else "Idle")
					w.anim:setParam("speed", Config.ARRIVAL_WALK_SPEED / Config.WALK_SPEED)
				else
					-- in line: shuffle forward when someone ahead is let in
					local target = slotX(w.slot or 1)
					local gap = target - w.x
					if math.abs(gap) > 0.1 then
						w.x += math.sign(gap) * math.min(math.abs(gap), Config.WALK_SPEED * 0.6 * dt)
						face = math.sign(gap)
						w.anim:setParam("speed", 0.6)
						w.anim:play("Walk")
					else
						face = -1 -- towards the door
						local t = os.clock()
						if (w.waveUntil or 0) < t and math.random() < dt * 0.06 then
							w.waveUntil = t + 2.2
						end
						w.anim:play(if (w.waveUntil or 0) > t then "Wave" else "Idle")
					end
				end
				w.handle.root.CFrame = CFrame.new(w.x, SY + CharacterRig.HIP_HEIGHT * w.handle.scale, 1.6)
					* CFrame.Angles(0, if face > 0 then -math.pi / 2 else math.pi / 2, 0)
			else
				w.x += w.dir * Config.WALK_SPEED * dt
				local arrived = w.kind == "home" and w.x <= bunkerX
				local gone = w.kind == "out" and w.x > bunkerX + 140
				if arrived or gone then
					w.handle.model.Parent = nil
				else
					w.anim:play("Walk")
					w.handle.root.CFrame = CFrame.new(w.x, SY + CharacterRig.HIP_HEIGHT * w.handle.scale, 1.2) * CFrame.Angles(0, if w.dir > 0 then -math.pi / 2 else math.pi / 2, 0)
				end
			end
			if visible and w.handle.model.Parent and w.x > x0 and w.x < x1 then
				w.anim:step(dt)
			end
		end
		local _ = y0
	end)
end

return SurfaceController
