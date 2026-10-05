--!strict
-- Incidents: fires, creature infestations and machinery breakdowns (start, spread, fight off,
-- repair) and scheduling of random accidents and raids. A broken Generator is a power failure:
-- production stops until the Overseer pays Materials and someone present repairs it. Frequency, creature toughness and raid timing follow the pressure curve
-- (Shared/Difficulty), so an old, crowded shelter is a lot busier than a new one.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Grid = require(ReplicatedStorage.Shared.Grid)
local Simulation = require(ReplicatedStorage.Shared.Simulation)
local RoomDefinitions = require(ReplicatedStorage.Shared.RoomDefinitions)
local ItemDefinitions = require(ReplicatedStorage.Shared.ItemDefinitions)
local Family = require(ReplicatedStorage.Shared.Family)
local Difficulty = require(ReplicatedStorage.Shared.Difficulty)

local IncidentService = {}
local S: any

local FIRE_SPREAD_DELAY = 32
local CREATURE_SPREAD_DELAY = 45
local MAX_INCIDENTS = 3

-- Creature infestations: which wasteland critter, how tough, how hard it bites.
IncidentService.Creatures = {
	Rats = { name = "Burrow Rats", mesh = "CRT_BURROWRAT", hp = 50, bite = 1.6, reward = 20 },
	Roaches = { name = "Rust Roaches", mesh = "CRT_RUSTROACH", hp = 72, bite = 2.3, reward = 28 },
}
local CREATURES = IncidentService.Creatures

local function present(vault, room, now: number)
	local out = {}
	for _, d in vault.data.dwellers do
		-- children and expecting mothers keep clear of fires and fights
		if (d.at or d.roomId) == room.id and (d.status == "Working" or d.status == "Idle") and (d.arriveAt or 0) <= now
			and d.activity ~= "Sleeping" and Family.canFight(d) then
			table.insert(out, d)
		end
	end
	return out
end
IncidentService.present = present

local function incidentCount(vault): number
	local n = 0
	for _, r in vault.data.rooms do
		if r.incident then
			n += 1
		end
	end
	return n
end

local function roomName(room): string
	return RoomDefinitions.Types[room.type].name
end

function IncidentService.startFire(vault, room, cause: string)
	if room.incident or room.type == "Elevator" or incidentCount(vault) >= MAX_INCIDENTS then
		return false
	end
	local now = S.VaultService.now()
	local hp = 55 * room.modules * (1 + 0.3 * (room.level - 1))
	room.incident = { kind = "Fire", hp = hp, maxHp = hp, started = now, spreadAt = now + FIRE_SPREAD_DELAY, cause = cause }
	room.readySince = nil
	vault.rt.lastIncident = now
	S.VaultService.send(vault, "incident", { roomId = room.id, kind = "Fire", cause = cause })
	S.VaultService.toast(vault, (if cause == "rush" then "Rush failed! " else "") .. "FIRE in the " .. roomName(room) .. "!", "bad")
	S.DwellerService.pushRoom(vault, room)
	return true
end

function IncidentService.startInfestation(vault, room, cause: string, kind: string?)
	if room.incident or room.type == "Elevator" or incidentCount(vault) >= MAX_INCIDENTS then
		return false
	end
	local rng: Random = vault.rt.rng
	local now = S.VaultService.now()
	local p = S.VaultService.pressure(vault)
	local k = kind or (if p > 0.35 and rng:NextNumber() < 0.5 then "Roaches" else "Rats")
	local def = CREATURES[k]
	local hp = def.hp * room.modules * (1 + 0.3 * (room.level - 1)) * Difficulty.creatureStrength(p)
	local count = math.clamp(1 + room.modules + math.floor(p * 2.5), 2, 6)
	room.incident = {
		kind = k, hp = hp, maxHp = hp, started = now, spreadAt = now + CREATURE_SPREAD_DELAY,
		cause = cause, count = count, strength = Difficulty.creatureStrength(p),
	}
	room.readySince = nil
	vault.rt.lastIncident = now
	S.VaultService.send(vault, "incident", { roomId = room.id, kind = k, cause = cause })
	S.VaultService.toast(vault, (if cause == "rush" then "Rush failed! " else "") .. string.upper(def.name) .. " in the " .. roomName(room) .. "!", "bad")
	S.DwellerService.pushRoom(vault, room)
	return true
end

-- Machinery breakdown: the room stops until repaired (Materials + someone present to fix it).
function IncidentService.startBreakdown(vault, room, cause: string)
	if room.incident or incidentCount(vault) >= MAX_INCIDENTS then
		return false
	end
	local now = S.VaultService.now()
	local cost = Simulation.repairCost(room)
	room.incident = { kind = "Breakdown", hp = 0, maxHp = 1, started = now, spreadAt = math.huge, cause = cause, cost = cost, paid = false }
	room.readySince = nil
	vault.rt.lastIncident = now
	S.VaultService.send(vault, "incident", { roomId = room.id, kind = "Breakdown", cause = cause })
	local what = if room.type == "Power" then "POWER FAILURE! The Generator" else "BREAKDOWN! The " .. roomName(room)
	S.VaultService.toast(vault, what .. " broke down - repair costs " .. cost .. " materials.", "bad")
	S.DwellerService.pushRoom(vault, room)
	return true
end

-- Player pays for a repair; whoever is in the room then fixes it (Engineering speeds it up).
function IncidentService.payRepair(vault, room): (boolean, string?)
	local inc = room.incident
	if not inc or inc.kind ~= "Breakdown" then
		return false, "Nothing to repair"
	end
	if inc.paid then
		return false, "Repairs are under way"
	end
	local res = vault.data.resources
	if (res.Materials or 0) < inc.cost then
		return false, "Need " .. inc.cost .. " materials"
	end
	res.Materials -= inc.cost
	inc.paid = true
	S.DwellerService.pushRoom(vault, room)
	S.ResourceService.pushResources(vault)
	S.VaultService.dirty(vault)
	return true, nil
end

-- Fire or creatures, weighted by pressure.
function IncidentService.startIncident(vault, room, cause: string)
	local p = S.VaultService.pressure(vault)
	if vault.rt.rng:NextNumber() < Difficulty.infestationShare(p) then
		return IncidentService.startInfestation(vault, room, cause, nil)
	end
	return IncidentService.startFire(vault, room, cause)
end

local function endIncident(vault, room, now: number)
	local inc = room.incident
	local creature = CREATURES[inc.kind]
	local fighters = present(vault, room, now)
	if inc.kind == "Breakdown" then
		room.incident = nil
		for _, d in fighters do
			S.DwellerService.grantXp(vault, d, 12)
		end
		S.VaultService.send(vault, "incidentEnd", { roomId = room.id, kind = inc.kind, success = true, bolts = 0 })
		S.VaultService.toast(vault, "The " .. roomName(room) .. " is running again.", "good")
		S.DwellerService.pushRoom(vault, room)
		S.VaultService.dirty(vault)
		return
	end
	local reward = (if creature then creature.reward else 18) * room.modules
	room.incident = nil
	vault.data.resources.Bolts += reward
	for _, d in fighters do
		S.DwellerService.grantXp(vault, d, 15)
	end
	table.insert(vault.rt.mood, { value = 4, expires = os.clock() + 150 })
	local stats = vault.data.progression.stats
	if creature then
		stats.infestations = (stats.infestations or 0) + 1
	else
		stats.fires += 1
	end
	S.VaultService.send(vault, "incidentEnd", { roomId = room.id, kind = inc.kind, success = true, bolts = reward })
	S.VaultService.toast(vault, (if creature then "The " .. creature.name .. " in the " .. roomName(room) .. " are gone."
		else "Fire in the " .. roomName(room) .. " is out.") .. " +" .. reward .. " bolts", "good")
	S.DwellerService.pushRoom(vault, room)
	S.VaultService.dirty(vault)
end

local function spread(vault, room, inc, now: number)
	local occ = Grid.occupancy(vault.data.rooms)
	local candidates = {}
	for _, c in { room.col - 1, room.col + Grid.width(room) } do
		local id = Grid.at(occ, c, room.row)
		local other = id and vault.data.rooms[id]
		if other and not other.incident and other.type ~= "Elevator" and (inc.kind ~= "Fire" or other.type ~= "Entrance") then
			table.insert(candidates, other)
		end
	end
	if #candidates == 0 then
		return
	end
	local target = candidates[vault.rt.rng:NextInteger(1, #candidates)]
	if inc.kind == "Fire" then
		IncidentService.startFire(vault, target, "spread")
	else
		IncidentService.startInfestation(vault, target, "spread", inc.kind)
	end
end

local function tickIncidents(vault, dt: number, now: number)
	local updates = {}
	local ended = {}
	for _, room in vault.data.rooms do
		local inc = room.incident
		if not inc then
			continue
		end
		local fighters = present(vault, room, now)
		local creature = CREATURES[inc.kind]
		local dps = 0
		if inc.kind == "Breakdown" then
			-- paid repairs progress with whoever is there; Engineering makes it quick
			if inc.paid then
				local speed = 0
				for _, d in fighters do
					speed += 0.012 + Simulation.stat(d, "ENG") * 0.004
				end
				inc.hp = math.min(1, inc.hp + speed * dt)
			end
			if inc.hp >= 1 then
				table.insert(ended, room)
			else
				table.insert(updates, { roomId = room.id, hp = inc.hp, maxHp = 1, fighters = #fighters })
			end
			continue
		elseif creature then
			-- survivors fight with whatever they carry; the critters bite back
			for _, d in fighters do
				local w = S.InventoryService.weaponOf(d)
				local aim = if w.id == "Fists" then Simulation.stat(d, "CMB") * 0.06 else Simulation.stat(d, "CMB") * 0.03
				dps += w.damage * w.fireRate * (1 + aim) * 0.6 + Simulation.stat(d, "CMB") * 0.15
				local bite = dt * creature.bite * (inc.strength or 1) * (1 - math.min(0.4, Simulation.stat(d, "FIT") * 0.04))
				S.DwellerService.damage(vault, d, bite, inc.kind == "Rats" and "burrow rats" or "rust roaches")
			end
			if #fighters == 0 and inc.kind == "Rats" then
				-- unchecked rats raid the pantry
				local res = vault.data.resources
				res.Food = math.max(0, res.Food - dt * 0.25)
			end
		else
			dps = 0.6 -- fires slowly burn out on their own
			if room.type == "Storage" then
				-- a burning depot destroys what it holds
				local res = vault.data.resources
				res.Materials = math.max(0, (res.Materials or 0) - dt * 1.2 * room.modules)
				res.Food = math.max(0, res.Food - dt * 0.4 * room.modules)
			end
			for _, d in fighters do
				dps += 1.6 + Simulation.stat(d, "FIT") * 0.15 + Simulation.stat(d, "FIT") * 0.1
				local burn = dt * 1.4 * (1 - math.min(0.4, Simulation.stat(d, "FIT") * 0.04))
				S.DwellerService.damage(vault, d, burn, "burns")
			end
		end
		inc.hp -= dps * dt
		if inc.hp <= 0 then
			table.insert(ended, room)
		else
			table.insert(updates, { roomId = room.id, hp = inc.hp, maxHp = inc.maxHp, fighters = #fighters })
			if now >= inc.spreadAt then
				inc.spreadAt = now + (if creature then CREATURE_SPREAD_DELAY else FIRE_SPREAD_DELAY)
				-- creatures only spread while nobody is fighting them
				if not creature or #fighters == 0 then
					spread(vault, room, inc, now)
				end
			end
		end
	end
	for _, room in ended do
		endIncident(vault, room, now)
	end
	if #updates > 0 then
		vault.rt.fireSendAcc = (vault.rt.fireSendAcc or 0) + dt
		if vault.rt.fireSendAcc >= 0.5 then
			vault.rt.fireSendAcc = 0
			S.VaultService.send(vault, "fire", updates)
		end
	end
end

local function weightedPick(rng: Random, pool: { { any } }): any
	local total = 0
	for _, e in pool do
		total += e[2]
	end
	local pick = rng:NextNumber() * total
	for _, e in pool do
		pick -= e[2]
		if pick <= 0 then
			return e[1]
		end
	end
	return nil
end

local function rollIncidents(vault, now: number)
	if now < vault.rt.nextRoll then
		return
	end
	vault.rt.nextRoll = now + 60
	local rng: Random = vault.rt.rng
	local p = S.VaultService.pressure(vault)
	if now - vault.rt.lastIncident > Difficulty.incidentGap(p) and not S.CombatService.active(vault) then
		if rng:NextNumber() < Difficulty.incidentChance(p) then
			local pool = {}
			if rng:NextNumber() < Difficulty.infestationShare(p) then
				-- critters dig in from the rock: deeper rooms are likelier, staffed or not
				for _, r in vault.data.rooms do
					if r.type ~= "Elevator" and r.type ~= "Entrance" and not r.incident then
						table.insert(pool, { r, 1 + r.row * 0.15 })
					end
				end
				local room = weightedPick(rng, pool)
				if room then
					IncidentService.startInfestation(vault, room, "accident", nil)
				end
			else
				-- accidents happen where people work; short-staffed rooms are riskier
				for _, r in vault.data.rooms do
					local def = RoomDefinitions.Types[r.type]
					if #r.assigned > 0 and def.incidentWeight > 0 and not r.incident then
						local short = #r.assigned < Simulation.capacity(r)
						table.insert(pool, { r, def.incidentWeight * (if short then 1.6 else 1) })
					end
				end
				local room = weightedPick(rng, pool)
				if room then
					IncidentService.startFire(vault, room, "accident")
				end
			end
		end
	end
	-- machinery wears out: staffed machines break down now and then (more often under pressure)
	if not S.CombatService.active(vault) and rng:NextNumber() < 0.07 * (1 + p) then
		local pool = {}
		for _, r in vault.data.rooms do
			local def = RoomDefinitions.Types[r.type]
			if def.breakdown and #r.assigned > 0 and not r.incident then
				table.insert(pool, { r, def.breakdown * r.level })
			end
		end
		local room = weightedPick(rng, pool)
		if room then
			IncidentService.startBreakdown(vault, room, "wear")
		end
	end
	local pop = Simulation.population(vault.data.dwellers)
	if now >= vault.rt.nextRaid and not S.CombatService.active(vault) then
		vault.rt.nextRaid = now + Difficulty.raidDelay(rng, p)
		if pop >= 3 then
			S.CombatService.startRaid(vault)
		end
	end
end

function IncidentService.prime(vault)
	local now = S.VaultService.now()
	vault.rt.lastIncident = now
	vault.rt.nextRoll = now + 60
	vault.rt.nextRaid = now + Config.RAID_FIRST_DELAY
end

function IncidentService.Init(services)
	S = services
	S.NetService.handle("Repair", function(player, p)
		local vault = S.VaultService.get(player)
		local room = vault and vault.data.rooms[tostring(p.roomId)]
		if not room then
			return false, "Invalid room"
		end
		return IncidentService.payRepair(vault, room)
	end)
	S.NetService.handle("Debug", function(player, p)
		if not RunService:IsStudio() then
			return false, "Debug actions are Studio-only"
		end
		local vault = S.VaultService.get(player)
		if not vault then
			return false, "Not ready"
		end
		if p.kind == "Fire" or p.kind == "Rats" or p.kind == "Roaches" then
			local room = vault.data.rooms[tostring(p.roomId)]
			if not room then
				for _, r in vault.data.rooms do
					if #r.assigned > 0 and not r.incident then
						room = r
						break
					end
				end
			end
			if not room then
				return false, "No room"
			end
			if p.kind == "Fire" then
				return IncidentService.startFire(vault, room, "debug"), "No room"
			end
			return IncidentService.startInfestation(vault, room, "debug", p.kind), "No room"
		elseif p.kind == "Breakdown" then
			for _, r in vault.data.rooms do
				if r.type == "Power" and not r.incident then
					return IncidentService.startBreakdown(vault, r, "debug"), "No generator"
				end
			end
			return false, "No working generator"
		elseif p.kind == "Raid" then
			return S.CombatService.startRaid(vault), "Raid already active"
		elseif p.kind == "Bolts" then
			vault.data.resources.Bolts += 1000
			S.ResourceService.pushResources(vault)
			return true
		elseif p.kind == "ExploreFF" then
			S.ExplorationService.fastForward(vault, 150)
			return true
		elseif p.kind == "Arrival" then
			vault.rt.nextArrival = 0
			return true
		elseif p.kind == "Pressure" then
			-- jump the shelter 30 minutes further along the pressure curve
			vault.data.playSeconds = (vault.data.playSeconds or 0) + 1800
			S.ResourceService.pushResources(vault)
			return true
		elseif p.kind == "Romance" or p.kind == "FamilyFF" then
			return S.FamilyService.debug(vault, p.kind)
		end
		return false, "Unknown debug action"
	end)
end

function IncidentService.Start()
	local last = os.clock()
	while true do
		task.wait(Config.COMBAT_TICK)
		local t = os.clock()
		local dt = math.min(1, t - last)
		last = t
		for _, vault in S.VaultService.all() do
			if vault.loaded then
				local now = S.VaultService.now()
				local ok, err = pcall(function()
					tickIncidents(vault, dt, now)
					rollIncidents(vault, now)
				end)
				if not ok then
					warn("[IncidentService]", err)
				end
			end
		end
	end
end

local _ = ItemDefinitions
return IncidentService
