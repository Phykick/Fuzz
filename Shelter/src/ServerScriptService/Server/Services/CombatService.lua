--!strict
-- Raids: raiders breach the blast door, then fight room by room against whoever is present.
-- Combat is server-authoritative and room-scoped; clients only animate the event stream.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Grid = require(ReplicatedStorage.Shared.Grid)
local Pathing = require(ReplicatedStorage.Shared.Pathing)
local Simulation = require(ReplicatedStorage.Shared.Simulation)
local ItemDefinitions = require(ReplicatedStorage.Shared.ItemDefinitions)
local RoomDefinitions = require(ReplicatedStorage.Shared.RoomDefinitions)
local Difficulty = require(ReplicatedStorage.Shared.Difficulty)

local CombatService = {}
local S: any

local RAIDER_NAMES = { "Gutter", "Rasp", "Knuckles", "Slag", "Mags", "Crowbar", "Vex", "Rattle", "Soot", "Brick" }
local RAIDER_WEAPONS = { "ScrapPistol", "PipeRifle", "ImprovisedShotgun", "ScrapPistol" }
local RAID_TIMEOUT = 200
local LOOT_TIME = 6

function CombatService.active(vault): boolean
	return vault.rt.raid ~= nil
end

function CombatService.publicState(vault)
	local raid = vault.rt.raid
	if not raid then
		return nil
	end
	local raiders = {}
	for id, r in raid.raiders do
		raiders[id] = { id = id, name = r.name, hp = r.hp, maxHp = r.maxHp, weapon = r.weapon, seed = r.seed }
	end
	return {
		id = raid.id, phase = raid.phase, roomId = raid.roomId, doorHp = raid.doorHp, doorMax = raid.doorMax,
		raiders = raiders, moveFrom = raid.moveFrom, moveTo = raid.moveTo, moveStart = raid.moveStart,
		moveDur = raid.moveDur, loot = raid.loot,
	}
end

local function pushState(vault)
	S.VaultService.send(vault, "raid", CombatService.publicState(vault))
end

-- Rooms in breadth-first order from the entrance (elevators traversed but not raided).
local function raidOrder(vault, entrance)
	local rooms = vault.data.rooms
	local occ = Grid.occupancy(rooms)
	local order, seen = {}, { [entrance.id] = true }
	local queue = { entrance }
	while #queue > 0 do
		local r = table.remove(queue, 1)
		if r.type ~= "Elevator" and r ~= entrance then
			table.insert(order, r.id)
		end
		local cands = {}
		table.insert(cands, Grid.at(occ, r.col - 1, r.row))
		table.insert(cands, Grid.at(occ, r.col + Grid.width(r), r.row))
		if r.type == "Elevator" then
			table.insert(cands, Grid.at(occ, r.col, r.row + 1))
			table.insert(cands, Grid.at(occ, r.col, r.row - 1))
		end
		for _, id in cands do
			if id and not seen[id] then
				local o = rooms[id]
				if o.type == "Elevator" or o.row == r.row then
					seen[id] = true
					table.insert(queue, o)
				end
			end
		end
	end
	return order
end

function CombatService.startRaid(vault): boolean
	if vault.rt.raid then
		return false
	end
	local entrance
	for _, r in vault.data.rooms do
		if r.type == "Entrance" then
			entrance = r
		end
	end
	if not entrance then
		return false
	end
	local rng: Random = vault.rt.rng
	local pop = Simulation.population(vault.data.dwellers)
	local lvl, n = 0, 0
	for _, d in vault.data.dwellers do
		if d.status ~= "Dead" then
			lvl += d.level
			n += 1
		end
	end
	local avg = if n > 0 then lvl / n else 1
	-- raids grow with the shelter: more raiders, tougher and harder-hitting as pressure rises
	local pressure = S.VaultService.pressure(vault)
	local strength = Difficulty.raiderStrength(pressure)
	local count = Difficulty.raidSize(pop, pressure)
	local raiders = {}
	for i = 1, count do
		local weapon = RAIDER_WEAPONS[rng:NextInteger(1, #RAIDER_WEAPONS)]
		local hp = math.floor((38 + avg * 7 + rng:NextInteger(0, 10)) * strength)
		raiders["r" .. i] = {
			name = RAIDER_NAMES[rng:NextInteger(1, #RAIDER_NAMES)],
			hp = hp, maxHp = hp,
			damage = (2.6 + avg * 0.35) * strength,
			weapon = weapon,
			cooldown = rng:NextNumber(0.3, 1.2),
			seed = rng:NextInteger(1, 1e6),
		}
	end
	local now = S.VaultService.now()
	local doorMax = 90 * entrance.level
	vault.rt.raid = {
		id = tostring(os.time()),
		phase = "door",
		raiders = raiders,
		roomId = entrance.id,
		doorHp = doorMax,
		doorMax = doorMax,
		order = raidOrder(vault, entrance),
		index = 0,
		loot = 0,
		lootTimer = 0,
		started = now,
	}
	S.VaultService.toast(vault, "RAIDERS at the blast door! " .. count .. " of them - send fighters to the entrance.", "bad")
	S.DwellerService.scatterQueue(vault)
	pushState(vault)
	return true
end

local function endRaid(vault, success: boolean)
	local raid = vault.rt.raid
	if not raid then
		return
	end
	vault.rt.raid = nil
	local rng: Random = vault.rt.rng
	local result = { success = success, bolts = 0, item = nil, stolen = raid.loot, stolenFood = raid.lootFood or 0, stolenWater = raid.lootWater or 0 }
	if success then
		local count = 0
		for _ in raid.raiders do
			count += 1
		end
		result.bolts = 45 + rng:NextInteger(10, 40) * math.max(1, raid.killed or 2)
		local res = vault.data.resources
		res.Bolts += result.bolts + raid.loot -- stolen goods recovered
		res.Food += raid.lootFood or 0
		res.Water += raid.lootWater or 0
		local luck = 0
		for _, d in vault.data.dwellers do
			if d.status ~= "Dead" then
				luck = math.max(luck, Simulation.stat(d, "SCV"))
			end
		end
		if rng:NextNumber() < 0.45 then
			local rarity = ItemDefinitions.rollRarity(rng, luck)
			local def = ItemDefinitions.randomOf("Weapon", rarity, rng) or "ScrapPistol"
			S.InventoryService.grant(vault, def)
			result.item = def
			S.VaultService.send(vault, "inventory", vault.data.inventory)
		end
		table.insert(vault.rt.mood, { value = 6, expires = os.clock() + 240 })
		vault.data.progression.stats.raids += 1
		S.VaultService.toast(vault, "Raiders defeated! +" .. result.bolts .. " bolts" .. (if result.item then " and a " .. ItemDefinitions.get(result.item).name else ""), "good")
	else
		table.insert(vault.rt.mood, { value = -6, expires = os.clock() + 240 })
		S.VaultService.toast(vault, string.format("The raiders escaped with %d bolts, %d food and %d water.",
			math.floor(raid.loot), math.floor(raid.lootFood or 0), math.floor(raid.lootWater or 0)), "bad")
	end
	S.VaultService.send(vault, "raidEnd", result)
	S.ResourceService.pushResources(vault)
	S.VaultService.dirty(vault)
end

local function advance(vault, raid, now: number)
	local rooms = vault.data.rooms
	-- rooms on the route may have been demolished or merged away since the raid began: skip them
	local nextId
	repeat
		raid.index += 1
		nextId = raid.order[raid.index]
	until nextId == nil or rooms[nextId] ~= nil
	if not nextId then
		endRaid(vault, false) -- went through the whole shelter: they leave with their loot
		return
	end
	local from, to = rooms[raid.roomId], rooms[nextId]
	local fromX = if from then Grid.roomCenterX(from) else 0
	local path = Pathing.find(rooms, fromX, if from then from.row else 0, Grid.roomCenterX(to), to.row)
	raid.phase = "moving"
	raid.moveFrom = raid.roomId
	raid.moveTo = nextId
	raid.moveStart = now
	raid.moveDur = if path then path.duration * 0.8 else 3
	raid.lootTimer = 0
	pushState(vault)
end

local function tickRaid(vault, raid, dt: number, now: number, events)
	local rng: Random = vault.rt.rng
	if now - raid.started > RAID_TIMEOUT then
		endRaid(vault, false)
		return
	end
	if raid.phase == "door" then
		local dps = 0
		for _, r in raid.raiders do
			local w = ItemDefinitions.Weapons[r.weapon]
			dps += r.damage * w.fireRate
		end
		raid.doorHp -= dps * dt
		if raid.doorHp <= 0 then
			raid.doorHp = 0
			raid.phase = "inside"
			raid.lootTimer = 0
			pushState(vault)
		end
		return
	elseif raid.phase == "moving" then
		if now >= raid.moveStart + raid.moveDur then
			raid.roomId = raid.moveTo
			raid.phase = "inside"
			pushState(vault)
		end
		return
	end
	local room = vault.data.rooms[raid.roomId]
	if not room then
		advance(vault, raid, now)
		return
	end
	local defenders = S.IncidentService.present(vault, room, now)
	if #defenders == 0 then
		raid.lootTimer += dt
		local res = vault.data.resources
		local steal = math.min(res.Bolts, res.Bolts * 0.012 * dt + dt)
		res.Bolts -= steal
		raid.loot += steal
		-- they clear out the pantry too
		local food = math.min(res.Food, (res.Food * 0.02 + 0.6) * dt)
		local water = math.min(res.Water, (res.Water * 0.02 + 0.6) * dt)
		res.Food -= food
		res.Water -= water
		raid.lootFood = (raid.lootFood or 0) + food
		raid.lootWater = (raid.lootWater or 0) + water
		if raid.lootTimer >= LOOT_TIME then
			advance(vault, raid, now)
		end
		return
	end
	-- Raiders shoot
	for rid, r in raid.raiders do
		r.cooldown -= dt
		if r.cooldown <= 0 and #defenders > 0 then
			local w = ItemDefinitions.Weapons[r.weapon]
			r.cooldown = 1 / w.fireRate * rng:NextNumber(0.85, 1.2)
			local target = defenders[rng:NextInteger(1, #defenders)]
			local crit = rng:NextNumber() < 0.05
			local dmg = r.damage * (1 - math.min(0.4, Simulation.stat(target, "FIT") * 0.03)) * rng:NextNumber(0.85, 1.15) * (if crit then 2 else 1)
			local killed = S.DwellerService.damage(vault, target, dmg, "raiders")
			table.insert(events, { a = rid, t = target.id, d = math.floor(dmg * 10) / 10, c = crit, k = killed, w = r.weapon })
			if killed then
				table.remove(defenders, table.find(defenders, target) :: number)
			end
		end
	end
	-- Survivors shoot back
	local aliveIds = {}
	for rid in raid.raiders do
		table.insert(aliveIds, rid)
	end
	for _, d in defenders do
		if #aliveIds == 0 then
			break
		end
		raid.cool = raid.cool or {}
		local cd = (raid.cool[d.id] or rng:NextNumber(0, 0.6)) - dt
		if cd <= 0 then
			local w = S.InventoryService.weaponOf(d)
			cd = 1 / w.fireRate * rng:NextNumber(0.85, 1.15)
			local tid = aliveIds[rng:NextInteger(1, #aliveIds)]
			local target = raid.raiders[tid]
			local aim = if w.id == "Fists" then Simulation.stat(d, "CMB") * 0.05 else Simulation.stat(d, "CMB") * 0.03
			local crit = rng:NextNumber() < w.crit + Simulation.stat(d, "SCV") * 0.01
			local dmg = w.damage * (1 + aim) * rng:NextNumber(0.85, 1.15) * (if crit then 2 else 1) * (1 + d.level * 0.02)
			target.hp -= dmg
			local killed = target.hp <= 0
			table.insert(events, { a = d.id, t = tid, d = math.floor(dmg * 10) / 10, c = crit, k = killed, w = w.id })
			S.DwellerService.grantXp(vault, d, 1)
			if killed then
				raid.raiders[tid] = nil
				raid.killed = (raid.killed or 0) + 1
				table.remove(aliveIds, table.find(aliveIds, tid) :: number)
			end
		end
		raid.cool[d.id] = cd
	end
	if #aliveIds == 0 then
		endRaid(vault, true)
	end
end

-- The Overseer left mid-raid. Raiders still hammering on the door come back soon after they
-- return (IncidentService.prime); raiders already inside escape with what they took.
function CombatService.onLeave(vault)
	local raid = vault.rt.raid
	vault.rt.raid = nil
	if raid and raid.phase == "door" then
		vault.data.raidPending = true
	end
end

function CombatService.Init(services)
	S = services
end

function CombatService.Start()
	local last = os.clock()
	while true do
		task.wait(Config.COMBAT_TICK)
		local t = os.clock()
		local dt = math.min(1, t - last)
		last = t
		for _, vault in S.VaultService.all() do
			local raid = vault.loaded and vault.rt.raid
			if raid then
				local events = {}
				local ok, err = pcall(tickRaid, vault, raid, dt, S.VaultService.now(), events)
				if not ok then
					warn("[CombatService]", err)
					vault.rt.raid = nil
				end
				if #events > 0 then
					S.VaultService.send(vault, "combat", { events = events, raiders = (vault.rt.raid and CombatService.publicState(vault) or {}).raiders })
				end
			end
		end
	end
end

local _ = RoomDefinitions
return CombatService
