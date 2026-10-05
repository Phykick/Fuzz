--!strict
-- Pure economy + colony formulas shared by server (authority) and client (UI previews).
local Config = require(script.Parent.Config)
local RoomDefinitions = require(script.Parent.RoomDefinitions)
local ItemDefinitions = require(script.Parent.ItemDefinitions)
local DwellerDefinitions = require(script.Parent.DwellerDefinitions)
local Resources = require(script.Parent.Resources)
local Needs = require(script.Parent.Needs)

local Simulation = {}

Simulation.RESOURCES = { "Power", "Food", "Water", "Materials", "MedPatch" }
Simulation.MERGE_BONUS = { 1.0, 1.06, 1.12 }
Simulation.CYCLE_SECONDS = 40 -- one production batch per crew
Simulation.AUTO_COLLECT = 25 -- seconds a ready batch waits for a tap before auto-depositing

-- Effective skill including outfit bonuses and traits.
function Simulation.stat(d: any, stat: string): number
	local v = d.stats[stat] or 1
	if d.outfit then
		local o = ItemDefinitions.Outfits[d.outfit]
		if o and o.stats[stat] then
			v += o.stats[stat]
		end
	end
	if stat == "SCV" and DwellerDefinitions.hasTrait(d, "Lucky") then
		v += 2
	end
	return v
end

-- Inside the shelter (not dead, out exploring, or still outside the bunker).
function Simulation.isInside(d: any): boolean
	local s = d.status
	return s ~= "Dead" and s ~= "Exploring" and s ~= "Arriving" and s ~= "Waiting"
end

-- The room a survivor is physically in (or walking to).
function Simulation.at(d: any): string?
	return d.at or d.roomId
end

-- At their job and actually working (not off eating, sleeping or in the Medbay).
function Simulation.isWorking(d: any, now: number): boolean
	return d.status == "Working"
		and (d.activity == nil or d.activity == "Working")
		and (d.at == nil or d.at == d.roomId)
		and (d.arriveAt or 0) <= now
end

-- Output of one worker: skill, happiness, needs, traits.
function Simulation.workerOutput(d: any, stat: string): number
	local s = Simulation.stat(d, stat)
	local happy = 0.6 + 0.6 * ((d.happiness or 50) / 100)
	local trait = 1 + (if DwellerDefinitions.hasTrait(d, "HardWorker") then 0.1 else 0)
	return (0.3 + 0.14 * s) * happy * trait * Needs.workFactor(d)
end

-- Per-minute output of a room from the crew present. powerFactor 0..1: the share of power demand
-- the grid can meet (only Generators run without power).
function Simulation.roomRate(room: any, dwellers: { [string]: any }, now: number, powerFactor: any): number
	local def = RoomDefinitions.Types[room.type]
	if not def or not def.produces or not def.rate then
		return 0
	end
	if room.incident then
		return 0
	end
	local pf: number = if powerFactor == true then 1 elseif powerFactor == false then 0 else (powerFactor :: number)
	local perSlot = def.rate[room.level] / def.slots
	local bonus = Simulation.MERGE_BONUS[room.modules] or 1
	local total = 0
	for _, id in room.assigned do
		local d = dwellers[id]
		if d and Simulation.isWorking(d, now) then
			total += perSlot * Simulation.workerOutput(d, def.stat :: string) * bonus
		end
	end
	if def.produces ~= "Power" then
		total *= pf
	end
	return total
end

function Simulation.capacity(room: any): number
	local def = RoomDefinitions.Types[room.type]
	return def.slots * room.modules
end

-- Seats for an errand kind ("eat", "drink", "sleep", "treat") in a room.
function Simulation.amenity(room: any, kind: string): number
	local def = RoomDefinitions.Types[room.type]
	if kind == "sleep" then
		if room.type == "Entrance" then
			return 4 -- founders' bunks by the blast door
		end
		return if def.housing then def.housing[room.level] * room.modules else 0
	end
	local a = def.amenities and (def.amenities :: any)[kind]
	return if a then a * room.modules else 0
end

function Simulation.storageCaps(rooms: { [string]: any }): { [string]: number }
	local caps = { Scrap = 999 }
	for key, r in Resources.Defs do
		caps[key] = r.base
	end
	for _, r in rooms do
		local def = RoomDefinitions.Types[r.type]
		if def.storage then
			for res, perLevel in def.storage do
				caps[res] = (caps[res] or 0) + perLevel[r.level] * r.modules
			end
		end
	end
	return caps
end

function Simulation.housing(rooms: { [string]: any }): number
	local cap = 4 -- the blast-door room has bunks for the founders
	for _, r in rooms do
		local def = RoomDefinitions.Types[r.type]
		if def.housing then
			cap += def.housing[r.level] * r.modules
		end
	end
	return cap
end

function Simulation.powerUse(rooms: { [string]: any }): number
	local use = 0
	for _, r in rooms do
		local def = RoomDefinitions.Types[r.type]
		use += def.powerUse * r.modules * (1 + 0.15 * (r.level - 1))
	end
	return use
end

function Simulation.population(dwellers: { [string]: any }): (number, number)
	local alive, total = 0, 0
	for _, d in dwellers do
		total += 1
		if Simulation.isInside(d) then
			alive += 1
		end
	end
	return alive, total
end

-- Mouths to feed: everyone inside, children count half.
function Simulation.consumers(dwellers: { [string]: any }): number
	local n = 0
	for _, d in dwellers do
		if Simulation.isInside(d) then
			n += if d.child then 0.5 else 1
		end
	end
	return n
end

-- Expected food / water use per minute (statistical: how often survivors eat and drink).
-- Actual use happens meal by meal (LifeService); this drives HUD trends and offline catch-up.
function Simulation.expectedUse(dwellers: { [string]: any }, multiplier: number): (number, number)
	local food, water = 0, 0
	local hunger, thirst = Needs.Defs.Hunger, Needs.Defs.Thirst
	for _, d in dwellers do
		if Simulation.isInside(d) then
			local size = if d.child then 0.5 else 1
			food += Config.MEAL_FOOD * size * Needs.decayOf(d, "Hunger") / (100 - hunger.seek)
			water += Config.DRINK_WATER * size * Needs.decayOf(d, "Thirst") / (100 - thirst.seek)
		end
	end
	return food * multiplier, water * multiplier
end

-- Bolts + materials to build one more module of this type.
function Simulation.buildCost(rooms: { [string]: any }, typeId: string): (number, number)
	local def = RoomDefinitions.Types[typeId]
	local count = 0
	for _, r in rooms do
		if r.type == typeId then
			count += r.modules
		end
	end
	return def.cost + def.costStep * count, def.materials + math.floor(def.materials * 0.25 * count)
end

function Simulation.upgradeCost(room: any): (number?, number)
	local def = RoomDefinitions.Types[room.type]
	local c = def.upgrade[room.level]
	if not c then
		return nil, 0
	end
	return c * room.modules, (def.upgradeMaterials[room.level] or 0) * room.modules
end

-- Materials to repair a broken-down room.
function Simulation.repairCost(room: any): number
	return 45 * room.modules * room.level
end

-- Best room type for a survivor (highest relevant skill).
function Simulation.bestRoom(d: any): (string?, number)
	local best, bestV = nil, -1
	for id, def in RoomDefinitions.Types do
		if def.stat and def.slots > 0 and (def.buildable or id == "Entrance") then
			local v = Simulation.stat(d, def.stat)
			if v > bestV then
				best, bestV = id, v
			end
		end
	end
	return best, bestV
end

-- Sum of a survivor's active memories (good meal, slept on the floor, friend died...).
function Simulation.memoryMood(d: any, now: number): number
	local m = 0
	for _, mem in d.memories or {} do
		if mem.untilT > now then
			m += mem.value
		end
	end
	return m
end

-- Target happiness for a survivor; actual happiness drifts towards it.
-- ctx: rooms, resources, population, housing, mood (shelter-wide), now
function Simulation.happinessTarget(d: any, ctx: { [string]: any }): number
	local h = 55
	if d.status == "Working" and d.roomId then
		local room = ctx.rooms[d.roomId]
		local def = room and RoomDefinitions.Types[room.type]
		if def and def.stat then
			local s = Simulation.stat(d, def.stat)
			h += 6 + math.min(14, (s - 3) * 3) -- a job that suits them
		end
	elseif not d.child then
		h -= 8 -- idle hands
	end
	h += Needs.mood(d)
	if ctx.population > ctx.housing then
		h -= 12 * DwellerDefinitions.traitFactor(d, "crowd")
	end
	if (ctx.resources.Power or 0) <= 0 then
		h -= 8 -- lights out
	end
	if d.health < d.maxHealth * 0.5 then
		h -= 10
	end
	h += d.socialMood or 0
	h += Simulation.memoryMood(d, ctx.now or 0)
	h += ctx.mood or 0
	return math.clamp(h, 0, 100)
end

function Simulation.xpRate(d: any): number
	local base = 3 + d.level * 0.15 -- xp per minute while working
	if DwellerDefinitions.hasTrait(d, "QuickLearner") then
		base *= 1.25
	end
	return base
end

function Simulation.reviveCost(d: any): number
	return math.floor((Config.REVIVE_BASE + Config.REVIVE_PER_LEVEL * d.level) * (1 + 0.5 * (d.revives or 0)))
end

function Simulation.rushFailChance(room: any, crewLuck: number): number
	local stack = room.rushStack or 0
	return math.clamp(Config.RUSH_BASE_FAIL + stack * Config.RUSH_STACK_FAIL - crewLuck * 0.015, 0.05, 0.9)
end

function Simulation.vaultHappiness(dwellers: { [string]: any }): number
	local sum, n = 0, 0
	for _, d in dwellers do
		if Simulation.isInside(d) then
			sum += d.happiness
			n += 1
		end
	end
	return if n == 0 then 0 else sum / n
end

function Simulation.xpForLevel(level: number): number
	return DwellerDefinitions.xpForLevel(level)
end

return Simulation
