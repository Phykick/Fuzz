--!strict
-- Survivors: creation, assignment + travel, XP/levels, happiness, health, death, arrivals.
-- Wanderers appear on the surface, walk to the bunker and wait in line outside until the
-- Overseer lets them in (or turns them away). The dead can only be revived for a limited time.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Grid = require(ReplicatedStorage.Shared.Grid)
local Pathing = require(ReplicatedStorage.Shared.Pathing)
local Simulation = require(ReplicatedStorage.Shared.Simulation)
local RoomDefinitions = require(ReplicatedStorage.Shared.RoomDefinitions)
local DwellerDefinitions = require(ReplicatedStorage.Shared.DwellerDefinitions)
local Family = require(ReplicatedStorage.Shared.Family)
local Needs = require(ReplicatedStorage.Shared.Needs)

local DwellerService = {}
local S: any

function DwellerService.create(vault, opts: any?)
	opts = opts or {}
	local rng: Random = vault.rt.rng
	local gender = opts.gender or (if rng:NextNumber() < 0.5 then "F" else "M")
	local arch = opts.archetype
		or DwellerDefinitions.ArchetypeOrder[rng:NextInteger(1, #DwellerDefinitions.ArchetypeOrder - 1)]
	local traits = DwellerDefinitions.randomTraits(rng)
	local stats = DwellerDefinitions.randomStats(rng, arch)
	local level = opts.level or 1
	local id = S.VaultService.newId(vault, "dweller")
	local d = {
		id = id,
		name = opts.name or DwellerDefinitions.randomName(rng, gender),
		gender = gender,
		age = rng:NextInteger(18, 62),
		archetype = arch,
		level = level,
		xp = 0,
		stats = stats,
		traits = traits,
		needs = Needs.default(),
		rel = {},
		memories = {},
		happiness = 60,
		weapon = nil,
		weaponItem = nil,
		outfit = nil,
		outfitItem = nil,
		roomId = nil,
		status = "Idle",
		appearance = DwellerDefinitions.randomAppearance(rng, gender, arch),
		arriveAt = 0,
		bornAt = os.time(),
	}
	d.maxHealth = DwellerDefinitions.maxHealthFor(level, stats.FIT, traits)
	d.health = d.maxHealth
	vault.data.dwellers[id] = d
	S.VaultService.dirty(vault)
	return d
end

function DwellerService.push(vault, d)
	S.VaultService.send(vault, "dweller", d)
end

function DwellerService.pushRoom(vault, room)
	S.VaultService.send(vault, "room", room)
end

local function entranceOf(vault): any
	for _, r in vault.data.rooms do
		if r.type == "Entrance" then
			return r
		end
	end
	return nil
end

-- Current position (x studs, row) of a survivor, following any route in progress.
function DwellerService.location(vault, d, now: number): (number, number)
	local tr = d.travel
	if tr and now < tr.start + tr.duration then
		local x, row = Pathing.sample(tr.points, tr.x0, tr.row0, now - tr.start)
		return x, math.floor(row + 0.5)
	end
	local room = (d.at and vault.data.rooms[d.at]) or (d.roomId and vault.data.rooms[d.roomId])
	if room then
		return Grid.roomCenterX(room), room.row
	end
	local entrance = entranceOf(vault)
	if entrance then
		return Grid.roomCenterX(entrance), entrance.row
	end
	return 0, 0
end

local function removeFromRoom(vault, d)
	local room = d.roomId and vault.data.rooms[d.roomId]
	if room then
		local i = table.find(room.assigned, d.id)
		if i then
			table.remove(room.assigned, i)
		end
		return room
	end
	return nil
end

-- Move a survivor into a room (server-authoritative route + arrival time).
function DwellerService.moveTo(vault, d, room, now: number): (boolean, string?)
	local def = RoomDefinitions.Types[room.type]
	if room.type == "Elevator" then
		return false, "Survivors can't be stationed in an elevator"
	end
	local cap = Simulation.capacity(room)
	if def.slots > 0 and d.roomId ~= room.id and #room.assigned >= cap then
		return false, def.name .. " is full"
	end
	local x0, row0 = DwellerService.location(vault, d, now)
	local tx = Grid.roomCenterX(room) + (vault.rt.rng:NextNumber() - 0.5) * math.min(8, Grid.width(room) * Config.UNIT * 0.5)
	local path = Pathing.find(vault.data.rooms, x0, row0, tx, room.row)
	if not path then
		return false, "No route to that room"
	end
	if d.court then
		S.FamilyService.cancel(vault, d)
	end
	local old = removeFromRoom(vault, d)
	if def.slots > 0 then
		table.insert(room.assigned, d.id)
		d.status = "Working"
	else
		d.status = "Idle"
	end
	d.roomId = room.id
	d.at = room.id
	d.activity = if def.slots > 0 then "Working" else "Relaxing"
	d.activityEnd = nil
	d.travel = { x0 = x0, row0 = row0, points = path.points, start = now, duration = path.duration }
	d.arriveAt = now + path.duration
	if vault.rt.think then
		vault.rt.think[d.id] = d.arriveAt + 20 -- the player's call: give it a moment before needs pull them away
	end
	S.VaultService.dirty(vault)
	DwellerService.push(vault, d)
	if old and old ~= room then
		DwellerService.pushRoom(vault, old)
	end
	DwellerService.pushRoom(vault, room)
	return true
end

function DwellerService.kill(vault, d, cause: string, message: string?)
	if d.status == "Dead" then
		return
	end
	local room = removeFromRoom(vault, d)
	d.status = "Dead"
	d.health = 0
	d.roomId = nil -- the job is free again; the body stays where they fell (d.at)
	d.travel = nil
	d.activity = nil
	S.LifeService.onDeath(vault, d, S.VaultService.now())
	d.diedAt = S.VaultService.now()
	d.deadFor = 0
	d.cause = cause
	table.insert(vault.rt.mood, { value = -20, expires = os.clock() + 600 })
	S.VaultService.toast(vault, message or (d.name .. " has died (" .. cause .. "). Revive them within "
		.. math.floor(Config.REVIVE_WINDOW / 60) .. " minutes or lose them for good."), "bad")
	DwellerService.push(vault, d)
	if room then
		DwellerService.pushRoom(vault, room)
	end
	S.VaultService.dirty(vault)
end

-- Remove a survivor from the shelter for good (gear goes back to storage).
local function remove(vault, d)
	local id = d.id
	local room = removeFromRoom(vault, d)
	if d.court then
		S.FamilyService.cancel(vault, d)
	end
	S.InventoryService.unequip(vault, d, "Weapon")
	S.InventoryService.unequip(vault, d, "Outfit")
	if vault.data.exploration[id] then
		vault.data.exploration[id] = nil
		S.VaultService.send(vault, "explore", { id = id, rec = nil })
	end
	vault.data.dwellers[id] = nil
	S.VaultService.send(vault, "dwellerRemoved", { id = id })
	S.VaultService.send(vault, "inventory", vault.data.inventory)
	if room then
		DwellerService.pushRoom(vault, room)
	end
	S.VaultService.dirty(vault)
end

-- The revive window ran out.
function DwellerService.bury(vault, d)
	remove(vault, d)
	table.insert(vault.rt.mood, { value = -15, expires = os.clock() + 900 })
	S.VaultService.toast(vault, d.name .. " has been laid to rest. The shelter mourns.", "bad")
end

-- Apply damage; returns true if the survivor died.
function DwellerService.damage(vault, d, amount: number, cause: string): boolean
	if d.status == "Dead" then
		return false
	end
	d.health = math.max(0, d.health - amount)
	if d.health <= 0 then
		DwellerService.kill(vault, d, cause)
		return true
	end
	return false
end

function DwellerService.grantXp(vault, d, amount: number)
	if d.status == "Dead" or d.level >= DwellerDefinitions.MAX_LEVEL then
		return
	end
	d.xp += amount
	local need = DwellerDefinitions.xpForLevel(d.level)
	if d.xp >= need then
		d.xp -= need
		d.level += 1
		local newMax = DwellerDefinitions.maxHealthFor(d.level, d.stats.FIT, DwellerDefinitions.traitsOf(d))
		d.health = math.min(newMax, d.health + (newMax - d.maxHealth) + newMax * 0.25)
		d.maxHealth = newMax
		table.insert(vault.rt.mood, { value = 2, expires = os.clock() + 120 })
		S.VaultService.send(vault, "levelup", { id = d.id, level = d.level })
		DwellerService.push(vault, d)
	end
end

local function context(vault)
	local mood = 0
	local now = os.clock()
	for i = #vault.rt.mood, 1, -1 do
		local m = vault.rt.mood[i]
		if m.expires < now then
			table.remove(vault.rt.mood, i)
		else
			mood += m.value
		end
	end
	local pop = Simulation.population(vault.data.dwellers)
	return {
		rooms = vault.data.rooms,
		resources = vault.data.resources,
		population = pop,
		housing = Simulation.housing(vault.data.rooms),
		mood = math.clamp(mood, -40, 20),
		now = S.VaultService.now(),
		danger = S.IncidentService.danger(vault),
	}
end

-- Wanderers outside (walking up or waiting in line), oldest first.
function DwellerService.queue(vault): { any }
	local q = {}
	for _, d in vault.data.dwellers do
		if (d.status == "Arriving" or d.status == "Waiting") and d.approach then
			table.insert(q, d)
		end
	end
	table.sort(q, function(a, b)
		return a.approach.start < b.approach.start
	end)
	return q
end

local function queueSlotX(bunkerX: number, i: number): number
	return bunkerX + 12 + (i - 1) * 2.4
end

-- Raiders scare off anyone waiting outside.
function DwellerService.scatterQueue(vault)
	local q = DwellerService.queue(vault)
	for _, d in q do
		remove(vault, d)
	end
	if #q > 0 then
		S.VaultService.toast(vault, (if #q == 1 then "The wanderer" else #q .. " wanderers") .. " outside fled from the raiders.", "bad")
	end
end

-- Called once per economy tick by ResourceService.
function DwellerService.tick(vault, dt: number, now: number)
	-- needs, errands, healing, relationships
	S.LifeService.tick(vault, dt, now)
	local ctx = context(vault)
	local buried, gaveUp = {}, {}
	for _, d in vault.data.dwellers do
		if d.status == "Dead" then
			d.deadFor = (d.deadFor or 0) + dt
			if d.deadFor >= Config.REVIVE_WINDOW then
				table.insert(buried, d)
			end
			continue
		end
		if d.status == "Waiting" then
			d.waitedFor = (d.waitedFor or 0) + dt
			if d.waitedFor >= Config.QUEUE_PATIENCE then
				table.insert(gaveUp, d)
			end
			continue
		end
		if d.status == "Exploring" or d.status == "Arriving" then
			continue
		end
		local target = Simulation.happinessTarget(d, ctx)
		local cheerful = DwellerDefinitions.hasTrait(d, "Cheerful") and target > d.happiness
		local rate = Config.HAPPINESS_DRIFT * (if cheerful then 1.5 else 1)
		d.happiness = math.clamp(d.happiness + math.clamp(target - d.happiness, -rate * dt, rate * dt), 0, 100)
		if Simulation.isWorking(d, now) then
			DwellerService.grantXp(vault, d, Simulation.xpRate(d) * dt / 60)
		end
	end
	for _, d in buried do
		DwellerService.bury(vault, d)
	end
	for _, d in gaveUp do
		remove(vault, d)
		S.VaultService.toast(vault, d.name .. " got tired of waiting outside and wandered off.", "warn")
	end
	-- Wanderers that reached the bunker line up outside the door.
	for _, d in vault.data.dwellers do
		if d.status == "Arriving" and (not d.approach or now >= d.approach.enter) then
			d.status = "Waiting"
			d.waitedFor = 0
			DwellerService.push(vault, d)
			S.VaultService.toast(vault, d.name .. " is waiting at the bunker door. Let them in?", "info")
		end
	end
	-- New wanderers appear somewhere on the surface while the line has room.
	if now >= vault.rt.nextArrival then
		local rng = vault.rt.rng
		vault.rt.nextArrival = now + rng:NextNumber(Config.ARRIVAL_INTERVAL[1], Config.ARRIVAL_INTERVAL[2])
		local entrance = entranceOf(vault)
		local line = #DwellerService.queue(vault)
		if entrance and line < Config.QUEUE_MAX and not S.CombatService.active(vault) then
			local d = DwellerService.create(vault, { level = rng:NextInteger(1, 3) })
			local bx = Grid.roomCenterX(entrance)
			local side = if rng:NextNumber() < 0.5 then -1 else 1
			local fromX = bx + side * rng:NextNumber(Config.ARRIVAL_SPAWN[1], Config.ARRIVAL_SPAWN[2])
			local toX = queueSlotX(bx, line + 1)
			d.status = "Arriving"
			d.roomId = nil
			d.approach = { fromX = fromX, toX = toX, start = now, enter = now + math.abs(fromX - toX) / Config.ARRIVAL_WALK_SPEED }
			DwellerService.push(vault, d)
			S.VaultService.send(vault, "approach", { id = d.id })
			S.VaultService.toast(vault, "A wanderer is heading for the shelter from the " .. (if side < 0 then "west" else "east") .. "!", "info")
		end
	end
	S.FamilyService.tick(vault, dt, now)
end

-- Let a waiting wanderer in: through the blast door, then they wait for a job.
function DwellerService.admit(vault, d, now: number): (boolean, string?)
	local entrance = entranceOf(vault)
	if not entrance then
		return false, "No blast door"
	end
	if d.status ~= "Waiting" then
		return false, d.name .. " hasn't reached the door yet"
	end
	if S.CombatService.active(vault) then
		return false, "Not while raiders are at the door!"
	end
	if Simulation.population(vault.data.dwellers) >= Simulation.housing(vault.data.rooms) then
		return false, "No room inside - build or upgrade Living Quarters"
	end
	d.approach = nil
	d.waitedFor = nil
	d.roomId = entrance.id
	d.at = entrance.id
	d.activity = "Relaxing"
	d.activityEnd = now + 12
	d.status = "Idle"
	local x1 = Grid.roomCenterX(entrance)
	local pts = { { x = x1, row = entrance.row, mode = "walk" } }
	local x0 = entrance.col * Config.UNIT + 2
	d.travel = { x0 = x0, row0 = entrance.row, points = pts, start = now, duration = Pathing.duration(pts, x0, entrance.row) }
	d.arriveAt = now + d.travel.duration
	vault.data.progression.stats.arrivals += 1
	S.LifeService.wake(vault, d, now)
	vault.rt.think[d.id] = d.activityEnd
	DwellerService.push(vault, d)
	S.VaultService.dirty(vault)
	S.VaultService.send(vault, "arrival", { id = d.id })
	S.VaultService.toast(vault, d.name .. " is inside. Assign them a job!", "good")
	return true, nil
end

function DwellerService.prime(vault)
	vault.rt.nextArrival = S.VaultService.now() + 75
end

local function owned(player, p): (any, any)
	local vault = S.VaultService.get(player)
	if not vault then
		return nil, nil
	end
	return vault, vault.data.dwellers[tostring(p.dwellerId)]
end

function DwellerService.Init(services)
	S = services
	S.NetService.handle("Assign", function(player, p)
		local vault = S.VaultService.get(player)
		if not vault then
			return false, "Not ready"
		end
		local d = vault.data.dwellers[tostring(p.dwellerId)]
		local room = vault.data.rooms[tostring(p.roomId)]
		if not d or not room then
			return false, "Invalid target"
		end
		if d.status == "Dead" then
			return false, d.name .. " needs to be revived first"
		end
		if d.status == "Exploring" then
			return false, d.name .. " is out in the wasteland"
		end
		if d.status == "Arriving" then
			return false, d.name .. " is still walking to the shelter"
		end
		if not Family.canWork(d) and RoomDefinitions.Types[room.type].slots > 0 then
			return false, d.name .. " is too young to work - try the Living Quarters"
		end
		local now = S.VaultService.now()
		if d.status == "Waiting" then
			-- dragging someone from the line straight into a room lets them in first
			local ok, why = DwellerService.admit(vault, d, now)
			if not ok then
				return false, why
			end
		end
		return DwellerService.moveTo(vault, d, room, now)
	end)
	S.NetService.handle("Admit", function(player, p)
		local vault, d = owned(player, p)
		if not vault or not d then
			return false, "Invalid"
		end
		return DwellerService.admit(vault, d, S.VaultService.now())
	end)
	S.NetService.handle("TurnAway", function(player, p)
		local vault, d = owned(player, p)
		if not vault or not d or (d.status ~= "Waiting" and d.status ~= "Arriving") then
			return false, "Invalid"
		end
		remove(vault, d)
		S.VaultService.toast(vault, d.name .. " was turned away.", "info")
		return true
	end)
	S.NetService.handle("Heal", function(player, p)
		local vault, d = owned(player, p)
		if not vault or not d or not Simulation.isInside(d) then
			return false, "Survivor unavailable"
		end
		if d.health >= d.maxHealth - 0.5 then
			return false, d.name .. " is already healthy"
		end
		local res = vault.data.resources
		if (res.MedPatch or 0) < 1 then
			return false, "No MedPatches left"
		end
		res.MedPatch -= 1
		d.health = math.min(d.maxHealth, d.health + d.maxHealth * Config.MEDPATCH_HEAL)
		DwellerService.push(vault, d)
		S.ResourceService.pushResources(vault)
		S.VaultService.dirty(vault)
		return true
	end)
	S.NetService.handle("Revive", function(player, p)
		local vault, d = owned(player, p)
		if not vault or not d or d.status ~= "Dead" then
			return false, "Nothing to revive"
		end
		local cost = Simulation.reviveCost(d)
		if vault.data.resources.Bolts < cost then
			return false, "Need " .. cost .. " bolts"
		end
		vault.data.resources.Bolts -= cost
		d.status = "Idle"
		d.health = d.maxHealth * 0.5 -- revived survivors still need rest or a MedPatch
		d.happiness = math.max(d.happiness, 45)
		d.diedAt = nil
		d.deadFor = nil
		d.revives = (d.revives or 0) + 1
		d.activity = nil
		S.LifeService.wake(vault, d, S.VaultService.now())
		if vault.data.exploration[d.id] then
			S.ExplorationService.revived(vault, d)
		end
		S.VaultService.dirty(vault)
		DwellerService.push(vault, d)
		S.ResourceService.pushResources(vault)
		return true
	end)
	S.NetService.handle("Rename", function(player, p)
		local vault, d = owned(player, p)
		if not vault or not d or type(p.name) ~= "string" then
			return false, "Invalid"
		end
		local name = p.name:gsub("[^%w%s%-']", ""):sub(1, 24)
		if #name < 2 then
			return false, "Name too short"
		end
		local ok, filtered = pcall(function()
			return game:GetService("TextService"):FilterStringAsync(name, player.UserId):GetNonChatStringForBroadcastAsync()
		end)
		d.name = if ok then filtered else d.name
		DwellerService.push(vault, d)
		S.VaultService.dirty(vault)
		return true
	end)
end

return DwellerService
