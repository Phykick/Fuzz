--!strict
-- Exploration view: a separate 2.5D side-scrolling wasteland far from the shelter.
-- The explorer walks in place while the world scrolls past (true 3D, so perspective gives
-- parallax for free). New journal entries from the server play out as encounters.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Exploration = require(ReplicatedStorage.Shared.Exploration)
local DwellerDefinitions = require(ReplicatedStorage.Shared.DwellerDefinitions)
local CharacterRig = require(ReplicatedStorage.Shared.CharacterRig)
local ItemDefinitions = require(ReplicatedStorage.Shared.ItemDefinitions)

local Render = script.Parent.Parent:WaitForChild("Render")
local MeshFactory = require(Render.MeshFactory)
local Scenery = require(Render.Scenery)
local CharacterFactory = require(Render.CharacterFactory)
local Animator = require(Render.Animator)

local WastelandController = {}
WastelandController.Changed = Signal.new()
WastelandController.active = false
WastelandController.focusId = nil :: string?

local C: any
local X0 = 40000
local LOOP = 360
local folder: Folder
local scroll: { { model: Model, vx: number, z: number, rot: CFrame } } = {}
local dist = 0
local built = false

type Actor = { handle: any, anim: any, vx: number, z: number, face: number, dead: boolean, creature: Model? }
type Vignette = { vx: number, prop: Model?, actors: { Actor }, entry: any, phase: string, t: number }

local hero: { handle: any, anim: any, id: string, sig: string }? = nil
local vignettes: { Vignette } = {}
local queue: { any } = {}
local seenLog: { [string]: number } = {}
local encounter: Vignette? = nil

local function wrapX(vx: number): number
	return X0 + ((vx - dist) % LOOP) - LOOP / 2
end

local function buildScene()
	if built then
		return
	end
	built = true
	Scenery.sky(folder, Vector3.new(X0, 0, 0), 0)
	Scenery.backdrop(folder, X0, 0)
	Scenery.farGround(folder, X0, 0)
	for i = 0, LOOP / 18 - 1 do
		local m = MeshFactory.spawn(if i % 2 == 0 then "WL_GROUND_A" else "WL_GROUND_B", CFrame.new(X0, 0, 0), nil, folder)
		table.insert(scroll, { model = m, vx = i * 18 + 9, z = 0, rot = CFrame.new(-9, 0, 0) })
	end
	local rng = Random.new(77)
	for _, p in Scenery.props(folder, rng, 0, LOOP - 20, 0, nil) do
		table.insert(scroll, { model = p.model, vx = p.x, z = p.z, rot = p.model:GetPivot().Rotation })
	end
	Scenery.dust(folder, Vector3.new(X0, 3, -10), 260)
	-- fill light so the explorer reads against the dusk sky
	local lp = Instance.new("Part")
	lp.Anchored = true
	lp.CanCollide = false
	lp.CanQuery = false
	lp.Transparency = 1
	lp.Position = Vector3.new(X0, 9, 14)
	lp.Parent = folder
	local l = Instance.new("PointLight")
	l.Color = Color3.fromRGB(255, 214, 170)
	l.Range = 34
	l.Brightness = 1.2
	l.Parent = lp
end

local function lookFor(d)
	return CharacterFactory.lookFor(d)
end

local function clearVignettes()
	for _, v in vignettes do
		if v.prop then
			v.prop:Destroy()
		end
		for _, a in v.actors do
			if a.handle then
				a.handle.model:Destroy()
			end
			if a.creature then
				a.creature:Destroy()
			end
		end
	end
	vignettes = {}
	queue = {}
	encounter = nil
end

local function setHero(id: string?)
	if hero and (not id or hero.id ~= id) then
		hero.handle.model:Destroy()
		hero = nil
	end
	if not id then
		return
	end
	local d = C.StateStore.state.dwellers[id]
	if not d then
		return
	end
	local sig = (d.outfit or "") .. (d.weapon or "")
	if hero and hero.sig == sig then
		return
	end
	if hero then
		hero.handle.model:Destroy()
	end
	local handle = CharacterFactory.build(d.appearance, lookFor(d))
	handle.model.Parent = folder
	local anim = Animator.new(handle.motors, 3)
	anim:setParam("weapon", d.weapon)
	hero = { handle = handle, anim = anim, id = id, sig = sig }
end

local function spawnActor(v: Vignette, kind: string, vxOff: number, face: number, seed: number)
	local a: Actor = { handle = nil, anim = nil, vx = v.vx + vxOff, z = 0.6 + (seed % 3) * 0.5, face = face, dead = false, creature = nil }
	if kind == "raider" then
		local appearance, look = CharacterFactory.raiderLook(seed)
		look.weapon = "PipeRifle"
		a.handle = CharacterFactory.build(appearance, look)
		CharacterFactory.setWeaponVisible(a.handle, true)
	elseif kind == "trader" or kind == "survivor" then
		local rng = Random.new(seed)
		local arch = if kind == "trader" then "Trader" else "Scavenger"
		local appearance = DwellerDefinitions.randomAppearance(rng, if rng:NextNumber() < 0.5 then "F" else "M", arch)
		a.handle = CharacterFactory.build(appearance, { style = arch })
	else
		a.creature = MeshFactory.spawn(kind, CFrame.new(X0, 0, 0), nil, folder)
		if kind == "CRT_RUSTROACH" then
			a.creature:ScaleTo(1.7)
		end
	end
	if a.handle then
		a.handle.model.Parent = folder
		a.anim = Animator.new(a.handle.motors, seed)
		a.anim:setParam("weapon", if kind == "raider" then "PipeRifle" else nil)
	end
	table.insert(v.actors, a)
	return a
end

local function startVignette(entry: any, dir: number)
	local def = Exploration.Events[entry.k]
	local v: Vignette = { vx = dist + dir * 30, prop = nil, actors = {}, entry = entry, phase = "approach", t = 0 }
	if def and def.scene then
		v.prop = MeshFactory.spawn(def.scene, CFrame.new(X0, 0, -6), nil, folder)
	end
	local seed = math.floor(entry.t) % 100000
	if entry.k == "RaiderCamp" then
		spawnActor(v, "raider", dir * 3, -dir, seed)
		spawnActor(v, "raider", dir * 5.5, -dir, seed + 1)
	elseif entry.k == "Mutant" then
		spawnActor(v, entry.creature or "CRT_BURROWRAT", dir * 2, -dir, seed)
		spawnActor(v, entry.creature or "CRT_BURROWRAT", dir * 5, -dir, seed + 1)
	elseif entry.k == "Trader" then
		spawnActor(v, "trader", dir * 2.4, -dir, seed)
	elseif entry.k == "Survivor" then
		spawnActor(v, "survivor", dir * 2.4, -dir, seed)
	end
	table.insert(vignettes, v)
end

local function heroPos(): Vector3
	return Vector3.new(X0, 0, 1.2)
end

local function floatLoot(entry)
	local base = heroPos() + Vector3.new(0, 6.5, 0)
	local i = 0
	local function f(text, color, icon)
		task.delay(i * 0.35, function()
			C.EffectsController.float(base + Vector3.new(0, 0, 0), text, color, icon, true)
		end)
		i += 1
	end
	local loot = entry.loot or {}
	if loot.Bolts and loot.Bolts ~= 0 then
		f((if loot.Bolts > 0 then "+" else "") .. loot.Bolts, Theme.Resource.Bolts, "bolts")
	end
	for _, k in { "Food", "Water", "MedPatch" } do
		if loot[k] then
			f("+" .. loot[k], Theme.Resource[k] or Theme.UI.text, string.lower(k == "MedPatch" and "health" or k))
		end
	end
	if loot.Scrap then
		f("+" .. loot.Scrap .. " scrap", Theme.Resource.Scrap, nil)
	end
	if loot.item then
		local def = ItemDefinitions.get(loot.item)
		if def then
			f(def.name, ItemDefinitions.Rarity[def.rarity].color, if def.kind == "Weapon" then "weapons" else "outfits")
		end
	end
	if loot.recruit then
		f("+1 SURVIVOR", Theme.UI.happy, "survivors")
	end
	if entry.dmg and entry.dmg > 0 then
		C.EffectsController.float(base + Vector3.new(-1.5, -1, 0), "-" .. math.floor(entry.dmg), Theme.UI.danger, "health")
	end
end

local function rec(): any
	local id = WastelandController.focusId
	return id and C.StateStore.state.exploration and C.StateStore.state.exploration[id]
end

local function pullJournal()
	local id = WastelandController.focusId
	local r = rec()
	if not id or not r then
		return
	end
	local n = #r.log
	local seen = seenLog[id] or n
	for i = seen + 1, n do
		local e = r.log[i]
		local def = Exploration.Events[e.k]
		if def and (def.scene or e.k == "RaiderCamp" or e.k == "Mutant" or e.k == "Trader" or e.k == "Survivor") then
			table.insert(queue, e)
		elseif e.k == "Death" then
			table.insert(queue, e)
		end
	end
	seenLog[id] = n
end

function WastelandController.open(id: string?)
	buildScene()
	WastelandController.active = true
	WastelandController.focusId = id
	clearVignettes()
	setHero(id)
	local r = rec()
	if id and r then
		-- replay the most recent encounter so there is always something happening on open
		seenLog[id] = math.max(0, #r.log - 1)
		pullJournal()
	end
	C.CameraController.enterScene(Vector3.new(X0 + 4, 4.5, 0), 26, 30)
	WastelandController.Changed:Fire(true)
end

function WastelandController.close()
	WastelandController.active = false
	clearVignettes()
	setHero(nil)
	C.CameraController.exitScene()
	WastelandController.Changed:Fire(false)
end

function WastelandController.focus(id: string)
	if WastelandController.active then
		WastelandController.open(id)
	end
end

local function placeActor(a: Actor, t: number)
	local x = wrapX(a.vx)
	if a.handle then
		a.handle.root.CFrame = CFrame.new(x, CharacterRig.HIP_HEIGHT * a.handle.scale, a.z) * CFrame.Angles(0, if a.face > 0 then -math.pi / 2 else math.pi / 2, 0)
	elseif a.creature then
		local bob = if a.dead then 0 else math.abs(math.sin(t * 9 + a.vx)) * 0.35
		local tilt = if a.dead then math.pi / 2 else 0
		-- creature meshes face +Z (towards the camera) in their rest pose
		a.creature:PivotTo(CFrame.new(x, bob, a.z) * CFrame.Angles(0, if a.face > 0 then math.pi / 2 else -math.pi / 2, 0) * CFrame.Angles(0, 0, tilt))
	end
end

local function step(dt: number)
	local t = os.clock()
	local r = rec()
	local h = hero
	local dir = if r and r.returning then -1 else 1
	local walking = h ~= nil and r ~= nil and not r.dead and encounter == nil
	if walking then
		dist += dir * Config.WALK_SPEED * dt
	end
	-- next encounter
	if walking and #queue > 0 and #vignettes < 3 then
		local e = table.remove(queue, 1)
		if e.k == "Death" then
			h.anim:play("Death", 0.1)
		else
			startVignette(e, dir)
		end
	end
	-- encounter timeline
	for i = #vignettes, 1, -1 do
		local v = vignettes[i]
		local rel = (v.vx - dist) * dir
		if v.phase == "approach" and rel <= 5 then
			v.phase = "act"
			v.t = 0
			encounter = v
		end
		if v.phase == "act" then
			v.t += dt
			local k = v.entry.k
			local combat = k == "RaiderCamp" or k == "Mutant" or k == "Checkpoint"
			if h then
				h.anim:play(if combat then "Shoot" elseif k == "Trader" or k == "Survivor" then "Talk" else "Heal")
				CharacterFactory.setWeaponVisible(h.handle, combat)
				if combat and math.random() < dt * 3 then
					h.anim:kick()
					local target = v.actors[1]
					local tp = if target then Vector3.new(wrapX(target.vx), 2.8, target.z) else Vector3.new(wrapX(v.vx), 5, -6)
					C.EffectsController.tracer(h.handle.root.Position + Vector3.new(dir * 1.3, 1.2, 0), tp, nil)
				end
			end
			for ai, a in v.actors do
				if a.anim then
					a.anim:play(if combat then "Shoot" else "Talk")
					if combat and not a.dead and math.random() < dt * 1.6 then
						a.anim:kick()
						C.EffectsController.tracer(a.handle.root.Position + Vector3.new(-dir * 1.3, 1.2, 0), heroPos() + Vector3.new(0, 3, 0), Color3.fromRGB(255, 120, 90))
						if h then
							h.anim:flinch()
						end
					end
				end
				if combat and not a.dead and v.t > 1.4 + ai * 0.7 then
					a.dead = true
					if a.anim then
						a.anim:play("Death", 0.1)
					end
					local model = a.handle and a.handle.model or a.creature
					if model then
						task.delay(2.2, function()
							model:Destroy()
						end)
					end
				end
			end
			if v.t > 3.4 then
				v.phase = "done"
				encounter = nil
				floatLoot(v.entry)
				if h then
					CharacterFactory.setWeaponVisible(h.handle, false)
				end
				for _, a in v.actors do
					if a.anim and not a.dead then
						a.anim:play("Wave")
					end
				end
			end
		end
		-- cleanup once far behind
		if v.phase == "done" and rel < -60 then
			if v.prop then
				v.prop:Destroy()
			end
			for _, a in v.actors do
				if a.handle and a.handle.model.Parent then
					a.handle.model:Destroy()
				end
				if a.creature and a.creature.Parent then
					a.creature:Destroy()
				end
			end
			table.remove(vignettes, i)
		else
			if v.prop then
				v.prop:PivotTo(CFrame.new(wrapX(v.vx), 0, -6))
			end
			for _, a in v.actors do
				if a.creature and not a.dead and v.phase == "approach" then
					a.vx -= dir * dt * 1.5 -- creatures scurry towards the explorer
				end
				placeActor(a, t)
				if a.anim then
					a.anim:step(dt)
				end
			end
		end
	end
	-- hero
	if h then
		if r and r.dead then
			h.anim:play("Death", 0.1)
		elseif walking then
			h.anim:play("Walk")
		end
		h.handle.root.CFrame = CFrame.new(X0, CharacterRig.HIP_HEIGHT * h.handle.scale, 1.2) * CFrame.Angles(0, if dir > 0 then -math.pi / 2 else math.pi / 2, 0)
		h.anim:step(dt)
	end
	-- scroll the world
	for _, s in scroll do
		s.model:PivotTo(CFrame.new(wrapX(s.vx), 0, s.z) * s.rot)
	end
end

function WastelandController.Init(controllers)
	C = controllers
	folder = Instance.new("Folder")
	folder.Name = "Wasteland"
	folder.Parent = workspace
end

function WastelandController.Start()
	local S = C.StateStore
	S.ExploreChanged:Connect(function(id)
		if WastelandController.active and id == WastelandController.focusId then
			pullJournal()
			local d = C.StateStore.state.dwellers[id]
			if d and hero and hero.sig ~= (d.outfit or "") .. (d.weapon or "") then
				setHero(id)
			end
		end
	end)
	S.ExploreEnded:Connect(function(id)
		if WastelandController.active and id == WastelandController.focusId then
			setHero(nil)
			clearVignettes()
		end
	end)
	RunService.RenderStepped:Connect(function(dt)
		if WastelandController.active then
			step(math.min(dt, 0.1))
		end
	end)
	local _ = TweenService
end

return WastelandController
