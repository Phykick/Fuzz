--!strict
-- Survivor + raider visuals. The server says WHERE someone is going (room + timed route) and WHAT
-- they are doing there (activity: Working, Eating, Drinking, Sleeping, Treatment, Relaxing...);
-- this controller decides HOW it looks: walking, riding elevators, working at stations, eating at
-- the cafeteria tables, sleeping in bunks, lying in a med bed, fighting, panicking, dying.
-- Animation and movement are LOD-throttled.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Pathing = require(ReplicatedStorage.Shared.Pathing)
local Grid = require(ReplicatedStorage.Shared.Grid)
local Theme = require(ReplicatedStorage.Shared.Theme)
local ItemDefinitions = require(ReplicatedStorage.Shared.ItemDefinitions)
local DwellerDefinitions = require(ReplicatedStorage.Shared.DwellerDefinitions)
local CharacterRig = require(ReplicatedStorage.Shared.CharacterRig)
local Family = require(ReplicatedStorage.Shared.Family)

local Render = script.Parent.Parent:WaitForChild("Render")
local CharacterFactory = require(Render.CharacterFactory)
local Animator = require(Render.Animator)

local DwellerController = {}
local C: any

local ROW, FLOOR, UNIT = Config.ROW_HEIGHT, Config.FLOOR_Y, Config.UNIT
local WALK = Config.WALK_SPEED

local BARKS = {
	Power = { "Turbine's purring.", "Keep your fingers clear.", "Voltage holding steady." },
	Water = { "Pressure's good.", "Filters need a scrub.", "Tastes almost like water!" },
	Food = { "Tomatoes are coming in.", "Grow lamps make me sleepy.", "Who ate the lettuce?" },
	Living = { "Home sweet bunker.", "Anyone seen my socks?", "I miss the sky." },
	Entrance = { "All quiet at the door.", "Nobody gets in on my watch." },
	Hungry = { "I'm starving...", "When's dinner?" },
	Fire = { "FIRE! FIRE!", "Get the extinguisher!" },
	Critters = { "Get them off me!", "Rats! RATS!", "Squash it!", "Ugh, they're everywhere!" },
	Raid = { "Hold the line!", "They're coming in!" },
	Arrive = { "Hello? Anyone home?", "Is it safe in here?" },
	Child = { "Can I go outside?", "Tag, you're it!", "I'm gonna be a mechanic!", "Are we there yet?" },
	Expecting = { "The baby's kicking!", "Not long now...", "We need a name!" },
	Court = { "You come here often?", "Nice moves!", "Ha! You're funny.", "Wanna dance?" },
	Born = { "Welcome, little one!", "Look how tiny!" },
	NoFood = { "There's no food left!", "My stomach's empty...", "We need to grow more food!" },
	NoWater = { "No clean water...", "I'm so thirsty.", "The tanks are dry!" },
	Cafeteria = { "Smells good today!", "Pass the salt?", "Seconds, anyone?" },
	Infirmary = { "Hold still, this'll sting.", "Deep breaths.", "You'll be fine." },
	Workshop = { "Hand me that wrench.", "Good scrap in this pile.", "Sparks everywhere!" },
	Grown = { "Ready to pull my weight!", "I'm a grown-up now!" },
	Respond = { "On my way!", "I've got this!", "Hang on, help's coming!", "Coming through!" },
}

type V = {
	id: string,
	data: any,
	raider: boolean,
	handle: any,
	anim: any,
	sig: string,
	pos: Vector3,
	yaw: number,
	targetYaw: number,
	lane: number,
	goal: Vector3?,
	goalYaw: number?,
	action: string,
	nextThink: number,
	acc: number,
	dragging: boolean,
	travelKey: string?,
	blendOffset: Vector3,
	blend: number,
	nextBlink: number,
	nameTag: BillboardGui?,
	bubble: BillboardGui?,
	nextBark: number,
	dead: boolean,
	deadAt: number?,
	raidPath: any?,
	slot: number,
	goalFloor: number?, -- floor height while walking to a raised spot (top bunk, bed)
	eyesClosed: boolean,
	zAcc: number,
}

local visuals: { [string]: V } = {}
local folder: Folder
local highlight: Highlight
local selectedId: string? = nil

local function now(): number
	return workspace:GetServerTimeNow()
end

local function sigOf(d): string
	local a = d.appearance or {}
	return table.concat({ a.skin or "", a.hair or "", a.head or "", a.body or "", d.outfit or "", d.weapon or "", d.archetype or "",
		tostring(d.child == true), tostring(d.pregnant ~= nil), tostring(a.beard == true) }, "|")
end

local function lookFor(d)
	return CharacterFactory.lookFor(d)
end

local function yawFor(faceDeg: number): number
	return math.rad(faceDeg) + math.pi
end

local function makeNameTag(v: V)
	local head = v.handle.model:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "NameTag"
	bb.Adornee = head
	bb.Size = UDim2.fromOffset(160, 22)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 1.9, 0)
	bb.AlwaysOnTop = false
	bb.LightInfluence = 0
	bb.MaxDistance = 5000
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.FontFace = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.SemiBold)
	t.TextScaled = true
	t.TextColor3 = if v.raider then Theme.UI.danger else Theme.UI.text
	t.TextStrokeTransparency = 0.35
	t.Text = if v.raider then (v.data.name or "Raider") else string.upper((v.data.name or ""):match("^(%S+)") or "")
	t.Parent = bb
	bb.Parent = v.handle.model
	v.nameTag = bb
end

function DwellerController.bark(v: V, text: string)
	if v.bubble then
		v.bubble:Destroy()
	end
	local head = v.handle.model:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end
	local bb = Instance.new("BillboardGui")
	bb.Adornee = head
	bb.Size = UDim2.fromOffset(200, 44)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 3.4, 0)
	bb.LightInfluence = 0
	bb.MaxDistance = 5000
	local f = Instance.new("TextLabel")
	f.AutomaticSize = Enum.AutomaticSize.X
	f.Size = UDim2.fromScale(0, 1)
	f.AnchorPoint = Vector2.new(0.5, 0)
	f.Position = UDim2.fromScale(0.5, 0)
	f.BackgroundColor3 = Color3.fromRGB(245, 238, 222)
	f.FontFace = Font.new("rbxasset://fonts/families/SpecialElite.json")
	f.TextSize = 15
	f.TextColor3 = Color3.fromRGB(30, 30, 30)
	f.Text = text
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = f
	Instance.new("UICorner").Parent = f
	local s = Instance.new("UIStroke")
	s.Color = Color3.fromRGB(30, 30, 30)
	s.Thickness = 2
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = f
	f.Parent = bb
	bb.Parent = v.handle.model
	v.bubble = bb
	task.delay(3.2, function()
		if v.bubble == bb then
			TweenService:Create(f, TweenInfo.new(0.3), { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
			task.wait(0.35)
			bb:Destroy()
			if v.bubble == bb then
				v.bubble = nil
			end
		end
	end)
end

local function destroyVisual(id: string)
	local v = visuals[id]
	if v then
		v.handle.model:Destroy()
		visuals[id] = nil
	end
end

local function createVisual(id: string, data: any, raider: boolean): V
	local appearance, look
	if raider then
		appearance, look = CharacterFactory.raiderLook(data.seed or 1)
		look.weapon = data.weapon
	else
		appearance, look = data.appearance, lookFor(data)
	end
	local handle = CharacterFactory.build(appearance, look)
	handle.model.Name = (if raider then "Raider_" else "Dweller_") .. id
	handle.clickBox:SetAttribute(if raider then "RaiderId" else "DwellerId", if raider then nil else id)
	if raider then
		handle.clickBox.CanQuery = false
	end
	handle.model.Parent = folder
	local seed = (tonumber(id:match("%d+")) or 1) * 1.37
	local v: V = {
		id = id,
		data = data,
		raider = raider,
		handle = handle,
		anim = Animator.new(handle.motors, seed),
		sig = if raider then "raider" else sigOf(data),
		pos = Vector3.new(0, -1000, 0),
		yaw = math.pi,
		targetYaw = math.pi,
		lane = -0.4 + ((seed * 7.7) % 1) * 1.5,
		goal = nil,
		goalYaw = nil,
		action = "Idle",
		nextThink = 0,
		acc = 0,
		dragging = false,
		travelKey = nil,
		blendOffset = Vector3.zero,
		blend = 0,
		nextBlink = os.clock() + math.random() * 4,
		nameTag = nil,
		bubble = nil,
		nextBark = os.clock() + 8 + math.random() * 30,
		dead = false,
		deadAt = nil,
		raidPath = nil,
		slot = 0,
		goalFloor = nil,
		eyesClosed = false,
		zAcc = 0,
	}
	v.anim:setParam("weapon", data.weapon)
	v.anim:setParam("scale", handle.scale)
	CharacterFactory.setWeaponVisible(handle, raider)
	makeNameTag(v)
	visuals[id] = v
	return v
end

-- Helpers ------------------------------------------------------------------------
-- The room a survivor is in right now (their errand location, else their assignment).
local function roomOf(v: V)
	local id = v.data.at or v.data.roomId
	return id and C.StateStore.state.rooms[id]
end

local ERRAND_SPOT = { Eating = "eat", Drinking = "drink", Sleeping = "sleep", Treatment = "treat" }
local NO_SEAT_ACTION = { Eating = "Eat", Drinking = "Drink", Sleeping = "Sleep", Treatment = "Sleep" }

local function randomInRoom(room, margin: number): number
	local x0 = room.col * UNIT + margin
	local x1 = (room.col + Grid.width(room)) * UNIT - margin
	return x0 + math.random() * math.max(0.1, x1 - x0)
end

local function floorY(row: number): number
	return -row * ROW + FLOOR
end

function DwellerController.headPosition(id: string): Vector3?
	local v = visuals[id]
	local head = v and v.handle.model:FindFirstChild("Head") :: BasePart?
	return head and head.Position
end

function DwellerController.positionOf(id: string): Vector3?
	local v = visuals[id]
	return v and v.pos
end

local function muzzleOf(v: V): Vector3
	local w = v.handle.weapon
	if w then
		local mk = w:GetAttribute("MK_Muzzle")
		if typeof(mk) == "CFrame" then
			return (w:GetPivot() * mk).Position
		end
	end
	local hand = v.handle.model:FindFirstChild("RightHand") :: BasePart?
	return if hand then hand.Position else v.pos + Vector3.new(0, 3, 0)
end

local function chestOf(v: V): Vector3
	local t = v.handle.model:FindFirstChild("UpperTorso") :: BasePart?
	return if t then t.Position else v.pos + Vector3.new(0, 3.3, 0)
end

-- Behaviour ------------------------------------------------------------------------
local function think(v: V, t: number)
	local d = v.data
	local room = roomOf(v)
	local state = C.StateStore.state
	local raid = state.raid
	v.nextThink = t + 9 + math.random() * 8
	if not room then
		v.goal, v.action = nil, "Idle"
		return
	end
	local rx0 = room.col * UNIT
	local w = Grid.width(room) * UNIT
	local fy = floorY(room.row)
	local danger = (raid and raid.phase == "inside" and raid.roomId == room.id) or (room.incident ~= nil and room.incident.kind ~= "Breakdown")
	if danger and not Family.canFight(d) then
		-- children and expecting mothers huddle in the far corner
		v.goal = Vector3.new(rx0 + w - 1.6 - math.random() * 1.5, fy, -1 + math.random() * 0.6)
		v.goalYaw = yawFor(-20)
		v.action = "Panic"
		v.nextThink = t + 2
		return
	end
	local court = d.court
	local partner = court and state.dwellers[court.with]
	if court and partner and (partner.at or partner.roomId) == room.id and partner.court and partner.court.with == d.id then
		-- the couple meets up in the room: chat first, then dance
		local pair = ((tonumber(d.id) or 1) + (tonumber(partner.id) or 1)) * 0.618 % 1
		local cx = rx0 + w * (0.3 + 0.4 * pair)
		local left = d.gender == "F"
		v.goal = Vector3.new(cx + (if left then -0.9 else 0.9), fy, 0.7)
		v.goalYaw = if left then -math.pi / 2 - 0.35 else math.pi / 2 + 0.35
		local prog = (now() - court.start) / math.max(1, court.done - court.start)
		v.action = if prog < 0.5 then "Talk" else "Dance"
		v.nextThink = t + 1.5
		return
	end
	if raid and raid.phase == "inside" and raid.roomId == room.id then
		-- defenders hold the right side, facing left
		v.goal = Vector3.new(rx0 + w * (0.6 + 0.3 * math.random()), fy, -0.8 + math.random() * 2)
		v.goalYaw = yawFor(-90)
		v.action = "Shoot"
		v.nextThink = t + 2.5
		return
	end
	if room.incident and room.incident.kind ~= "Fire" and room.incident.kind ~= "Breakdown" then
		-- creatures: stomp and shoot at them around the room
		v.goal = Vector3.new(randomInRoom(room, 2), fy, -0.5 + math.random() * 1.6)
		v.goalYaw = yawFor(if math.random() < 0.5 then -70 else 70)
		v.action = "Shoot"
		v.nextThink = t + 1.2 + math.random() * 1.5
		return
	end
	if room.incident and room.incident.kind == "Fire" then
		v.goal = Vector3.new(randomInRoom(room, 2), fy, -0.5 + math.random() * 1.6)
		v.goalYaw = yawFor(if math.random() < 0.5 then -60 else 60)
		v.action = "Extinguish"
		v.nextThink = t + 2 + math.random() * 2
		return
	end
	v.goalFloor = nil
	local act = d.activity
	local kind = ERRAND_SPOT[act or ""]
	if kind then
		local seats = C.VaultRenderer.spots(room.id, kind)
		if #seats > 0 then
			-- each survivor doing the same thing here takes their own seat / bunk / bed
			local rank = 1
			for id, o in state.dwellers do
				if o ~= d and (o.at or o.roomId) == room.id and o.activity == act and id < d.id then
					rank += 1
				end
			end
			local spot = seats[(rank - 1) % #seats + 1]
			v.goal = spot.pos
			v.goalFloor = fy
			v.goalYaw = yawFor(spot.face)
			v.action = spot.action
			v.nextThink = t + 6
			return
		end
		-- no seat: cold rations / sleeping on the floor wherever they are
		v.goal = Vector3.new(randomInRoom(room, 2.5), fy, v.lane)
		v.goalYaw = yawFor((math.random() - 0.5) * 40)
		v.action = NO_SEAT_ACTION[act]
		v.nextThink = t + 8
		return
	end
	if act == "Visiting" then
		-- at a loved one's bedside
		local beds = C.VaultRenderer.spots(room.id, "treat")
		local bed = beds[1]
		v.goal = if bed then Vector3.new(bed.pos.X + 1.8 + math.random() * 0.6, fy, bed.pos.Z + 2.2) else Vector3.new(randomInRoom(room, 2), fy, v.lane)
		v.goalYaw = yawFor(140)
		v.action = "Talk"
		v.nextThink = t + 5
		return
	end
	local spots = C.VaultRenderer.workSpots(room.id)
	if room.incident and room.incident.kind == "Breakdown" and (act == "Working" or act == "Responding") and #spots > 0 then
		-- crew at their own stations; responders sent to help take the next free one
		local idx = table.find(room.assigned, d.id) or (#room.assigned + 1)
		local spot = spots[((idx - 1) % #spots) + 1]
		v.goal = spot.pos + Vector3.new((math.random() - 0.5) * 0.6, 0, 0)
		v.goalYaw = yawFor(spot.face or 180)
		v.action = if room.incident.paid then "Repair" else "Idle"
		v.nextThink = t + 3
		return
	end
	local working = act == "Working" or (act == nil and d.status == "Working")
	if working and room.id == d.roomId and #spots > 0 then
		local idx = table.find(room.assigned, d.id) or 1
		local spot = spots[((idx - 1) % #spots) + 1]
		if math.random() < 0.18 then
			-- stretch the legs for a moment
			v.goal = Vector3.new(math.clamp(spot.pos.X + (math.random() - 0.5) * 7, rx0 + 1.5, rx0 + w - 1.5), fy, v.lane)
			v.goalYaw = yawFor(if math.random() < 0.5 then 25 else -25)
			v.action = if math.random() < 0.5 then "Idle" else "Talk"
			v.nextThink = t + 3 + math.random() * 3
		else
			v.goal = spot.pos + Vector3.new((math.random() - 0.5) * 0.6, 0, 0)
			v.goalYaw = yawFor((spot.face or 180) + (math.random() - 0.5) * 30)
			v.action = spot.action
		end
		return
	end
	if d.child then
		-- kids play instead of lounging on the furniture
		local r = math.random()
		v.goal = Vector3.new(randomInRoom(room, 2), fy, -0.6 + math.random() * 1.8)
		v.goalYaw = yawFor((math.random() - 0.5) * 90)
		v.action = if r < 0.3 then "Celebrate" elseif r < 0.5 then "Wave" elseif r < 0.75 then "Talk" else "Idle"
		v.nextThink = t + 3 + math.random() * 4
		return
	end
	if (room.type == "Living" or act == "Relaxing") and #spots > 0 and room.type ~= "Cafeteria" then
		local spot = spots[math.random(1, #spots)]
		v.goal = spot.pos + Vector3.new((math.random() - 0.5) * 1.2, 0, 0)
		v.goalYaw = yawFor(if spot.action == "Sit" then 0 else (math.random() - 0.5) * 70)
		v.action = spot.action
		return
	end
	-- idle elsewhere (e.g. fresh arrivals at the blast door)
	v.goal = Vector3.new(randomInRoom(room, 3), fy, v.lane)
	v.goalYaw = yawFor((math.random() - 0.5) * 60)
	v.action = if d.status == "Working" then "Guard" else "Idle"
end

local function setFacing(v: V, dir: number)
	if dir > 0 then
		v.targetYaw = -math.pi / 2
	elseif dir < 0 then
		v.targetYaw = math.pi / 2
	end
end

local function stepDweller(v: V, dt: number, t: number, serverNow: number)
	local d = v.data
	local anim = v.anim
	if v.dragging then
		return
	end
	if d.status == "Exploring" or d.status == "Arriving" or d.status == "Waiting" then
		-- outside the shelter: shown by SurfaceController / WastelandController instead
		v.pos = Vector3.new(0, -1000, 0)
		v.handle.root.CFrame = CFrame.new(0, -1000, 0)
		return
	end
	if d.status == "Dead" then
		if not v.dead then
			v.dead = true
			anim:play("Death", 0.1)
			CharacterFactory.setExpression(v.handle, "open")
		end
		return
	elseif v.dead then
		v.dead = false
		anim.t = 0
		anim:play("Idle")
		CharacterFactory.setExpression(v.handle, "smile")
	end
	local tr = d.travel
	if tr and serverNow < tr.start + tr.duration then
		local rate = tr.rate or 1 -- > 1: hurrying (emergency responders run)
		local key = tostring(tr.start)
		if v.travelKey ~= key then
			v.travelKey = key
			local sx, srow = Pathing.sample(tr.points, tr.x0, tr.row0, (serverNow - tr.start) * rate)
			local sp = Vector3.new(sx, floorY(srow), v.lane)
			if v.pos.Y > -900 and (v.pos - sp).Magnitude < 40 then
				v.blendOffset = v.pos - sp
				v.blend = 1
			else
				v.blend = 0
			end
			v.goal = nil
		end
		local x, rowf, mode, dir = Pathing.sample(tr.points, tr.x0, tr.row0, (serverNow - tr.start) * rate)
		local p = Vector3.new(x, floorY(rowf), if mode == "lift" then 0 else v.lane)
		if v.blend > 0 then
			v.blend = math.max(0, v.blend - dt / 0.45)
			p += v.blendOffset * v.blend
		end
		v.pos = p
		if mode == "lift" then
			anim:play("Ride")
			v.targetYaw = math.pi
			C.VaultRenderer.carTo(math.floor(x / UNIT), p.Y)
		else
			anim:play(if rate > 1 then "Run" else "Walk")
			anim:setParam("speed", rate)
			setFacing(v, dir)
		end
		v.nextThink = 0
		return
	end
	-- in a room
	if t >= v.nextThink then
		think(v, t)
	end
	local raid = C.StateStore.state.raid
	local here = C.StateStore.state.rooms[d.at or d.roomId or ""]
	local inCombat = (raid and raid.phase == "inside" and raid.roomId == (d.at or d.roomId)) or (here and here.incident and here.incident.kind ~= "Fire" and here.incident.kind ~= "Breakdown")
	CharacterFactory.setWeaponVisible(v.handle, inCombat == true)
	if v.goal then
		local delta = v.goal - v.pos
		local flat = Vector3.new(delta.X, 0, delta.Z)
		if flat.Magnitude > 0.25 then
			local speed = if inCombat or v.action == "Extinguish" then WALK * 1.4 else WALK * 0.75
			local stepLen = math.min(flat.Magnitude, speed * dt)
			v.pos += flat.Unit * stepLen
			v.pos = Vector3.new(v.pos.X, v.goalFloor or v.goal.Y, v.pos.Z)
			anim:play(if speed > WALK then "Run" else "Walk")
			setFacing(v, if math.abs(delta.X) > 0.05 then delta.X else 0)
			anim:setParam("speed", speed / WALK)
			return
		end
		v.pos = Vector3.new(v.goal.X, v.goal.Y, v.goal.Z)
		if v.goalYaw then
			v.targetYaw = v.goalYaw
		end
	end
	anim:setParam("speed", 1)
	anim:play(v.action)
	-- sleepers close their eyes
	local asleep = v.action == "Sleep"
	if asleep ~= v.eyesClosed then
		v.eyesClosed = asleep
		for _, e in v.handle.eyes do
			local base = e:GetAttribute("BaseSize") or e.Size
			e:SetAttribute("BaseSize", base)
			e.Size = if asleep then Vector3.new(base.X, base.Y * 0.12, base.Z) else base
		end
	end
	-- expressions follow mood/situation
	local expr = "smile"
	if v.action == "Shoot" or v.action == "Extinguish" then
		expr = "open"
	elseif (d.happiness or 50) < 35 then
		expr = "frown"
	elseif (d.happiness or 50) < 60 then
		expr = "flat"
	end
	CharacterFactory.setExpression(v.handle, expr)
end

local function stepRaider(v: V, dt: number, t: number, serverNow: number)
	local raid = C.StateStore.state.raid
	if v.dead then
		return
	end
	if not raid then
		return
	end
	local rooms = C.StateStore.state.rooms
	if raid.phase == "moving" and raid.moveFrom and raid.moveTo then
		local a, b = rooms[raid.moveFrom], rooms[raid.moveTo]
		if a and b then
			if not v.raidPath or v.raidPath.key ~= raid.moveTo then
				local p = Pathing.find(rooms, Grid.roomCenterX(a), a.row, Grid.roomCenterX(b), b.row)
				v.raidPath = { key = raid.moveTo, path = p, x0 = Grid.roomCenterX(a), row0 = a.row }
			end
			local rp = v.raidPath
			if rp.path then
				local frac = math.clamp((serverNow - raid.moveStart) / math.max(0.1, raid.moveDur), 0, 1)
				local x, rowf, mode, dir = Pathing.sample(rp.path.points, rp.x0, rp.row0, frac * rp.path.duration - v.slot * 0.25)
				v.pos = Vector3.new(x - v.slot * 1.2 * (if dir >= 0 then 1 else -1), floorY(rowf), v.lane)
				v.anim:play(if mode == "lift" then "Ride" else "Run")
				setFacing(v, dir)
				return
			end
		end
	end
	local room = rooms[raid.roomId]
	if not room then
		return
	end
	local rx0 = room.col * UNIT
	local w = Grid.width(room) * UNIT
	local fy = floorY(room.row)
	if t >= v.nextThink then
		v.nextThink = t + 2 + math.random() * 2
		v.goal = Vector3.new(rx0 + math.max(2, w * (0.12 + 0.28 * math.random())), fy, -0.8 + math.random() * 2)
		if room.type == "Entrance" and v.pos.Y < -900 then
			v.pos = Vector3.new(rx0 + 6.5, fy, -3) -- step out of the tunnel
		end
	end
	if v.pos.Y < -900 then
		v.pos = Vector3.new(rx0 + 6.5, fy, -3)
	end
	if v.goal then
		local delta = v.goal - v.pos
		local flat = Vector3.new(delta.X, 0, delta.Z)
		if flat.Magnitude > 0.25 then
			v.pos += flat.Unit * math.min(flat.Magnitude, WALK * 1.2 * dt)
			v.pos = Vector3.new(v.pos.X, fy, v.pos.Z)
			v.anim:play("Run")
			setFacing(v, delta.X)
			return
		end
	end
	v.targetYaw = -math.pi / 2 -- face right, towards defenders
	v.anim:play("Shoot")
	CharacterFactory.setExpression(v.handle, "open")
end

local function applyTransform(v: V, dt: number)
	local diff = (v.targetYaw - v.yaw + math.pi) % (2 * math.pi) - math.pi
	v.yaw += diff * math.min(1, dt * 12)
	local base = CharacterRig.HIP_HEIGHT * v.handle.scale
	v.handle.root.CFrame = CFrame.new(v.pos.X, v.pos.Y + base, v.pos.Z) * CFrame.Angles(0, v.yaw, 0)
end

local function blink(v: V, t: number)
	if t < v.nextBlink or v.eyesClosed then
		return
	end
	v.nextBlink = t + 2.5 + math.random() * 3.5
	for _, e in v.handle.eyes do
		local s = e.Size
		e.Size = Vector3.new(s.X, s.Y * 0.12, s.Z)
		task.delay(0.11, function()
			if e.Parent then
				e.Size = s
			end
		end)
	end
end

-- Sync with state ----------------------------------------------------------------------
local function syncDweller(d)
	local v = visuals[d.id]
	if v and v.sig ~= sigOf(d) then
		destroyVisual(d.id)
		v = nil
	end
	if not v then
		v = createVisual(d.id, d, false)
	end
	v.data = d
	v.anim:setParam("weapon", d.weapon)
	v.nextThink = 0
end

local function syncRaiders(raid)
	local alive = {}
	if raid and raid.raiders then
		local i = 0
		for rid, r in raid.raiders do
			i += 1
			local key = "raider:" .. rid
			alive[key] = true
			local v = visuals[key]
			if not v then
				v = createVisual(key, { name = r.name, seed = r.seed, weapon = r.weapon }, true)
				v.slot = i - 1
				v.pos = Vector3.new(0, -1000, 0)
			end
			v.data.hp = r.hp
		end
	end
	for key, v in visuals do
		if v.raider and not alive[key] and not v.dead then
			if raid then
				-- killed
				v.dead = true
				v.anim:play("Death", 0.1)
				task.delay(2.6, function()
					destroyVisual(key)
				end)
			else
				destroyVisual(key)
			end
		end
	end
	if raid and raid.phase == "door" then
		for _, v in visuals do
			if v.raider then
				v.pos = Vector3.new(0, -1000, 0)
			end
		end
	end
end

local function visualFor(id: string): V?
	return visuals[id] or visuals["raider:" .. id]
end

local function onCombat(p)
	for _, e in p.events do
		local a, b = visualFor(e.a), visualFor(e.t)
		if a and b then
			a.anim:play("Shoot")
			a.anim:kick()
			b.anim:flinch()
			if e.w ~= "Fists" then
				local target = chestOf(b) + Vector3.new(0, (math.random() - 0.5) * 0.8, 0)
				C.EffectsController.tracer(muzzleOf(a), target, if a.raider then Color3.fromRGB(255, 120, 90) else nil)
			end
			C.EffectsController.damage((DwellerController.headPosition(b.id) or b.pos) + Vector3.new(0, 1, 1), e.d, e.c, not b.raider)
			if e.k and b.raider then
				b.dead = true
				b.anim:play("Death", 0.1)
				local key = b.id
				task.delay(2.6, function()
					destroyVisual(key)
				end)
			end
		end
	end
end

local function celebrate(id: string, seconds: number, barkPool: { string }?)
	local v = visuals[id]
	if not v or v.dead then
		return
	end
	v.goal = nil
	v.action = "Celebrate"
	v.nextThink = os.clock() + seconds
	if barkPool then
		DwellerController.bark(v, barkPool[math.random(1, #barkPool)])
	end
end

-- Little hearts that drift up from a courting couple (and Z's from sleepers).
local HEART = utf8.char(0x2665)
local function heart(v: V, glyph: string?, color: Color3?)
	local head = v.handle.model:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end
	local bb = Instance.new("BillboardGui")
	bb.Adornee = head
	bb.Size = UDim2.fromOffset(34, 34)
	bb.StudsOffsetWorldSpace = Vector3.new((math.random() - 0.5) * 0.8 + 0.9, 1.2, 0.5)
	bb.LightInfluence = 0
	bb.MaxDistance = 400
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(1, 1)
	l.Text = glyph or HEART
	l.TextScaled = true
	l.TextColor3 = color or Color3.fromRGB(255, 92, 120)
	l.TextStrokeTransparency = 0.4
	l.Parent = bb
	bb.Parent = v.handle.model
	TweenService:Create(bb, TweenInfo.new(1.6, Enum.EasingStyle.Sine), { StudsOffsetWorldSpace = bb.StudsOffsetWorldSpace + Vector3.new(0, 2.4, 0) }):Play()
	TweenService:Create(l, TweenInfo.new(1.6), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(1.7, function()
		bb:Destroy()
	end)
end

-- Nearest survivor to a GUI-space point (finger-friendly picking).
function DwellerController.nearestOnScreen(screen: Vector2, radius: number): string?
	local cam = workspace.CurrentCamera
	local inset = game:GetService("GuiService"):GetGuiInset()
	local best, bestD = nil, radius
	for id, v in visuals do
		if not v.raider and v.pos.Y > -900 then
			local sp, visible = cam:WorldToViewportPoint(chestOf(v))
			if visible then
				local d = (Vector2.new(sp.X, sp.Y) - inset - screen).Magnitude
				if d < bestD then
					best, bestD = id, d
				end
			end
		end
	end
	return best
end

-- Selection / drag -------------------------------------------------------------------
function DwellerController.select(id: string?)
	selectedId = id
	local v = id and visuals[id]
	highlight.Adornee = if v then v.handle.model else nil
end

function DwellerController.beginDrag(id: string)
	local v = visuals[id]
	local st = v and v.data.status
	if not v or st == "Dead" or st == "Exploring" or st == "Arriving" then
		return false
	end
	v.dragging = true
	v.anim:play("Dragged", 0.1)
	v.targetYaw = math.pi
	CharacterFactory.setExpression(v.handle, "open")
	return true
end

function DwellerController.dragTo(id: string, worldPos: Vector3)
	local v = visuals[id]
	if v and v.dragging then
		v.pos = Vector3.new(worldPos.X, worldPos.Y - 3.4, 2.5)
	end
end

function DwellerController.endDrag(id: string)
	local v = visuals[id]
	if v then
		v.dragging = false
		v.nextThink = 0
		-- if no new route arrives, glide back into the current room
		local room = roomOf(v)
		if room then
			v.goal = Vector3.new(Grid.roomCenterX(room), floorY(room.row), v.lane)
			v.pos = Vector3.new(v.pos.X, floorY(room.row), v.pos.Z)
		end
	end
end

function DwellerController.Init(controllers)
	C = controllers
	folder = Instance.new("Folder")
	folder.Name = "Characters"
	folder.Parent = C.InputController.world()
	highlight = Instance.new("Highlight")
	highlight.FillTransparency = 1
	highlight.OutlineColor = Theme.UI.accent
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = folder
end

function DwellerController.Start()
	local S = C.StateStore
	S.Snapshot:Connect(function(state)
		for id in visuals do
			if not visuals[id].raider and not state.dwellers[id] then
				destroyVisual(id)
			end
		end
		for _, d in state.dwellers do
			syncDweller(d)
		end
		syncRaiders(state.raid)
	end)
	S.DwellerChanged:Connect(syncDweller)
	S.DwellerRemoved:Connect(function(id)
		if selectedId == id then
			DwellerController.select(nil)
		end
		destroyVisual(id)
	end)
	S.RoomChanged:Connect(function(room)
		for _, v in visuals do
			if v.data.roomId == room.id then
				v.nextThink = 0
			end
		end
	end)
	S.Raid:Connect(function(raid)
		syncRaiders(raid)
		for _, v in visuals do
			v.nextThink = 0
		end
	end)
	S.RaidEnd:Connect(function()
		syncRaiders(nil)
		for _, v in visuals do
			v.nextThink = 0
		end
	end)
	S.Combat:Connect(onCombat)
	S.Incident:Connect(function(p)
		for _, v in visuals do
			if v.data.roomId == p.roomId and not v.raider then
				v.nextThink = 0
				local pool = if p.kind == "Fire" then BARKS.Fire else BARKS.Critters
				DwellerController.bark(v, pool[math.random(1, #pool)])
				break
			end
		end
	end)
	S.Bark:Connect(function(p)
		local v = visuals[p.id]
		local pool = BARKS[p.kind]
		if v and pool then
			DwellerController.bark(v, pool[math.random(1, #pool)])
		end
	end)
	S.Family:Connect(function(p)
		task.delay(0.15, function()
			if p.kind == "court" then
				local v = visuals[p.a]
				if v then
					DwellerController.bark(v, BARKS.Court[math.random(1, #BARKS.Court)])
				end
			elseif p.kind == "expecting" then
				celebrate(p.a, 3, nil)
				celebrate(p.b, 3, nil)
			elseif p.kind == "born" then
				celebrate(p.a, 2.5, BARKS.Born)
			elseif p.kind == "grown" then
				celebrate(p.a, 2.5, BARKS.Grown)
			end
		end)
	end)
	S.Arrival:Connect(function(p)
		task.delay(0.2, function()
			local v = visuals[p.id]
			if v then
				DwellerController.bark(v, BARKS.Arrive[math.random(1, #BARKS.Arrive)])
			end
		end)
	end)

	local barkAcc = 0
	local heartAcc = 0
	RunService.RenderStepped:Connect(function(dt)
		local t = os.clock()
		local serverNow = now()
		local x0, x1, y0, y1 = C.CameraController.visibleRect(6)
		local view = C.CameraController.viewHeight()
		local animRate = if view < 70 then 0 elseif view < 140 then 1 / 24 else 1 / 12
		local showNames = view < 34
		for _, v in visuals do
			if v.raider then
				stepRaider(v, dt, t, serverNow)
			else
				stepDweller(v, dt, t, serverNow)
			end
			local p = v.pos
			local onScreen = p.X > x0 and p.X < x1 and p.Y > y0 - 6 and p.Y < y1
			if onScreen or v.dragging then
				applyTransform(v, dt)
				v.acc += dt
				if v.acc >= animRate then
					v.anim:step(v.acc)
					v.acc = 0
				end
				blink(v, t)
			elseif v.acc < 0.5 then
				v.acc += dt
			else
				v.acc = 0
				applyTransform(v, 0.5)
			end
			if v.nameTag then
				v.nameTag.Enabled = showNames or selectedId == v.id or v.raider and view < 60
			end
		end
		-- hearts over courting couples once they have met up, Z's over sleepers (zoomed in, on screen)
		heartAcc += dt
		if heartAcc > 0.9 then
			heartAcc = 0
			if view < 60 then
				for _, v in visuals do
					local d = v.data
					local p = v.pos
					local settled = v.goal == nil or (v.goal - v.pos).Magnitude < 0.3
					if not v.raider and settled and p.X > x0 and p.X < x1 and p.Y > y0 and p.Y < y1 then
						if d.court and d.gender == "F" then
							heart(v)
						elseif v.eyesClosed and math.random() < 0.45 then
							heart(v, "z", Color3.fromRGB(190, 220, 255))
						end
					end
				end
			end
		end
		-- ambient barks (rare, only when zoomed in)
		barkAcc += dt
		if barkAcc > 1 and view < 45 then
			barkAcc = 0
			for _, v in visuals do
				if not v.raider and not v.dead and t > v.nextBark then
					v.nextBark = t + 25 + math.random() * 40
					local p = v.pos
					if p.X > x0 and p.X < x1 and p.Y > y0 and p.Y < y1 then
						local room = roomOf(v)
						local res = C.StateStore.state.resources
						local d = v.data
						local pool = (if res.Food and res.Food <= 0 then BARKS.Hungry
							elseif d.child then BARKS.Child
							elseif d.pregnant then BARKS.Expecting
							elseif d.court then BARKS.Court
							elseif room then BARKS[room.type]
							else nil)
						if pool then
							DwellerController.bark(v, pool[math.random(1, #pool)])
						end
						break
					end
				end
			end
		end
	end)
end

return DwellerController
