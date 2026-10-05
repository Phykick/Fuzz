--!strict
-- Daily life: needs, autonomous behaviour, relationships and memories.
--
-- Every survivor inside the shelter runs a small state machine on a staggered schedule (never per
-- frame): needs decay each economy tick (cheap arithmetic), and a survivor only "thinks" when an
-- activity ends, a need crosses its threshold, or a periodic check is due. Errands are timed
-- routes (Shared/Pathing) that the client animates, so off-screen survivors cost the server the
-- same as on-screen ones and the client nothing beyond sampling a route.
--
-- Activities: Working (at the job) | Relaxing | Eating | Drinking | Sleeping | Treatment | Visiting
-- Data on a survivor: needs, activity, at (room they are in / walking to), activityEnd, memories,
-- rel (affinity by survivor id), partner, socialMood.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Grid = require(ReplicatedStorage.Shared.Grid)
local Pathing = require(ReplicatedStorage.Shared.Pathing)
local Simulation = require(ReplicatedStorage.Shared.Simulation)
local RoomDefinitions = require(ReplicatedStorage.Shared.RoomDefinitions)
local DwellerDefinitions = require(ReplicatedStorage.Shared.DwellerDefinitions)
local Needs = require(ReplicatedStorage.Shared.Needs)
local Family = require(ReplicatedStorage.Shared.Family)
local Difficulty = require(ReplicatedStorage.Shared.Difficulty)

local LifeService = {}
local S: any

local MAX_THINKS_PER_TICK = 60
local WORK_CHECK = 25 -- seconds between need checks while working / relaxing
local RELAX_AFTER_WAKE = 18 -- morning downtime in the bedroom (couples meet here)
local TREAT_THRESHOLD = 0.45
local VISIT_COOLDOWN = 150
local SOCIAL_EVERY = 5
local RESPOND_EVERY = 2 -- seconds between emergency dispatch passes
local RESPOND_HEALTH = 0.5 -- nobody below half health is sent (or goes back) into danger
local RETREAT_HEALTH = 0.3 -- anyone in a fire or fight pulls out below this
local RESPOND_RATE = 1.6 -- responders run

local ERRAND_OF = { Eating = "eat", Drinking = "drink", Sleeping = "sleep", Treatment = "treat" }

-- Memories --------------------------------------------------------------------------
function LifeService.remember(d: any, id: string, text: string, value: number, seconds: number, now: number)
	d.memories = d.memories or {}
	for i = #d.memories, 1, -1 do
		local m = d.memories[i]
		if m.id == id or m.untilT <= now then
			table.remove(d.memories, i)
		end
	end
	table.insert(d.memories, { id = id, text = text, value = value, untilT = now + seconds })
	while #d.memories > 6 do
		table.remove(d.memories, 1)
	end
end

local function firstName(d): string
	return string.match(d.name, "^(%S+)") or d.name
end

-- Location helpers ------------------------------------------------------------------
local function arrived(d, now: number): boolean
	return (d.arriveAt or 0) <= now
end

local function nearest(vault, d, now: number, filter: (any) -> boolean): any
	local x0, row0 = S.DwellerService.location(vault, d, now)
	local best, bestCost = nil, math.huge
	for _, r in vault.data.rooms do
		if filter(r) then
			local cost = math.abs(Grid.roomCenterX(r) - x0) / Config.WALK_SPEED + math.abs(r.row - row0) * 2.5
			if cost < bestCost then
				best, bestCost = r, cost
			end
		end
	end
	return best
end

-- Send a survivor somewhere to do something. duration = seconds once there (nil = open-ended).
-- rate > 1 hurries them along the route (travel.rate; Pathing.sample takes time * rate).
function LifeService.goTo(vault, d: any, room: any, activity: string, now: number, duration: number?, rate: number?): boolean
	local here = d.at == room.id and arrived(d, now) and not (d.travel and now < d.travel.start + d.travel.duration)
	if here and d.activity == activity and duration == nil and d.activityEnd == nil then
		vault.rt.think[d.id] = now + WORK_CHECK -- already doing exactly this
		return true
	end
	if here then
		d.travel = nil
	else
		local x0, row0 = S.DwellerService.location(vault, d, now)
		local tx = Grid.roomCenterX(room) + (vault.rt.rng:NextNumber() - 0.5) * math.min(8, Grid.width(room) * Config.UNIT * 0.5)
		local path = Pathing.find(vault.data.rooms, x0, row0, tx, room.row)
		if not path then
			return false
		end
		local r = rate or 1
		d.travel = { x0 = x0, row0 = row0, points = path.points, start = now, duration = path.duration / r, rate = if r ~= 1 then r else nil }
		d.arriveAt = now + path.duration / r
	end
	d.at = room.id
	d.activity = activity
	local start = math.max(now, d.arriveAt or now)
	d.activityEnd = if duration then start + duration else nil
	vault.rt.think[d.id] = if duration then start + duration else start + WORK_CHECK
	S.DwellerService.push(vault, d)
	return true
end

-- Stay put and do something (rations, sleeping on the floor...).
local function doHere(vault, d: any, activity: string, now: number, duration: number?)
	d.activity = activity
	d.activityEnd = if duration then now + duration else nil
	vault.rt.think[d.id] = if duration then now + duration else now + WORK_CHECK
	S.DwellerService.push(vault, d)
end

-- Occupancy of errand seats, rebuilt each tick and bumped as errands are handed out.
local function countUse(vault): { [string]: { [string]: number } }
	local use = {}
	for _, d in vault.data.dwellers do
		local kind = ERRAND_OF[d.activity or ""]
		if kind and d.at and Simulation.isInside(d) then
			use[d.at] = use[d.at] or {}
			use[d.at][kind] = (use[d.at][kind] or 0) + 1
		end
	end
	return use
end

local function freeSeat(vault, room, kind: string): boolean
	local cap = Simulation.amenity(room, kind)
	local used = vault.rt.use[room.id] and vault.rt.use[room.id][kind] or 0
	return cap > used and not room.incident
end

local function reserve(vault, room, kind: string)
	vault.rt.use[room.id] = vault.rt.use[room.id] or {}
	vault.rt.use[room.id][kind] = (vault.rt.use[room.id][kind] or 0) + 1
end

-- Best worker skill present in a room (cooks, medics).
local function bestCrewSkill(vault, room, stat: string, now: number): number
	local best = 0
	for _, id in room.assigned do
		local w = vault.data.dwellers[id]
		if w and Simulation.isWorking(w, now) then
			best = math.max(best, Simulation.stat(w, stat))
		end
	end
	return best
end

-- Errands -----------------------------------------------------------------------------
local function startEat(vault, d, now: number): boolean
	local caf = nearest(vault, d, now, function(r)
		return r.type == "Cafeteria" and freeSeat(vault, r, "eat")
	end)
	if caf then
		reserve(vault, caf, "eat")
		return LifeService.goTo(vault, d, caf, "Eating", now, Needs.MEAL_SECONDS)
	end
	-- no cafeteria seat: cold rations wherever they are
	doHere(vault, d, "Eating", now, Needs.MEAL_SECONDS)
	return true
end

local function startDrink(vault, d, now: number): boolean
	local spot = nearest(vault, d, now, function(r)
		return (r.type == "Cafeteria" and freeSeat(vault, r, "drink")) or (r.type == "Water" and not r.incident)
	end)
	if spot then
		if spot.type == "Cafeteria" then
			reserve(vault, spot, "drink")
		end
		return LifeService.goTo(vault, d, spot, "Drinking", now, Needs.DRINK_SECONDS)
	end
	doHere(vault, d, "Drinking", now, Needs.DRINK_SECONDS)
	return true
end

local function startSleep(vault, d, now: number): boolean
	local bed = nearest(vault, d, now, function(r)
		return (r.type == "Living" or r.type == "Entrance") and freeSeat(vault, r, "sleep")
	end)
	d.floorSleep = nil
	if bed then
		reserve(vault, bed, "sleep")
		return LifeService.goTo(vault, d, bed, "Sleeping", now, nil)
	end
	d.floorSleep = true
	LifeService.remember(d, "floor", "Slept on the floor", -6, 600, now)
	doHere(vault, d, "Sleeping", now, nil)
	return true
end

local function startTreatment(vault, d, now: number): boolean
	local meds = vault.data.resources.MedPatch or 0
	local bay = nearest(vault, d, now, function(r)
		return r.type == "Infirmary" and freeSeat(vault, r, "treat")
			and (meds > 0 or bestCrewSkill(vault, r, "MED", now) > 0)
	end)
	if not bay then
		return false
	end
	reserve(vault, bay, "treat")
	return LifeService.goTo(vault, d, bay, "Treatment", now, nil)
end

-- Emergencies --------------------------------------------------------------------------------
-- Hands a room's emergency needs on site: people to fight a fire or critters, and a repair crew
-- once the Overseer has paid for the parts (an unpaid breakdown waits on that decision).
local function handsWanted(room): number
	local inc = room.incident
	if not inc then
		return 0
	elseif inc.kind == "Breakdown" then
		return if inc.paid then 2 else 0
	end
	return math.clamp(room.modules + 1, 2, 4)
end

-- A fire or a fight (breakdowns aren't dangerous).
local function dangerous(room): boolean
	return room ~= nil and room.incident ~= nil and room.incident.kind ~= "Breakdown"
end

-- How suited someone is to answer a room's emergency: travel time minus a bonus for the right
-- skill (engineers for repairs, fitness for fires, combat for critters). nil = not available.
local function responderCost(vault, d, room, now: number): number?
	if not Simulation.isInside(d) or not Family.canFight(d) or d.respond then
		return nil
	end
	if d.activity == "Sleeping" or d.activity == "Treatment" or d.health < d.maxHealth * RESPOND_HEALTH then
		return nil
	end
	local where = d.at or d.roomId
	if where == room.id then
		return nil -- already there (and counted)
	end
	local current = where and vault.data.rooms[where]
	if current and handsWanted(current) > 0 then
		return nil -- busy with their own room's emergency
	end
	local raid = vault.rt.raid
	if raid and raid.roomId == where then
		return nil -- holding off raiders
	end
	local x0, row0 = S.DwellerService.location(vault, d, now)
	local cost = math.abs(Grid.roomCenterX(room) - x0) / Config.WALK_SPEED + math.abs(room.row - row0) * 2.5
	local kind = room.incident.kind
	if kind == "Breakdown" then
		return cost - Simulation.stat(d, "ENG") * 4
	end
	return cost - Simulation.stat(d, if kind == "Fire" then "FIT" else "CMB") * 2
end

-- Drop everything and run to a room's emergency.
function LifeService.respond(vault, d, room, now: number): boolean
	d.respond = room.id
	if not LifeService.goTo(vault, d, room, "Responding", now, nil, RESPOND_RATE) then
		d.respond = nil
		return false
	end
	vault.rt.think[d.id] = math.max(now, d.arriveAt or now) -- size things up on arrival
	S.VaultService.send(vault, "bark", { id = d.id, kind = "Respond" })
	return true
end

-- Top up every emergency with the best-placed people who can be spared; release responders
-- whose emergency is over.
local function dispatch(vault, now: number)
	local rooms = vault.data.rooms
	local onTheWay: { [string]: number } = {}
	for _, d in vault.data.dwellers do
		local target = d.respond and rooms[d.respond]
		if d.respond and (not target or handsWanted(target) == 0) then
			vault.rt.think[d.id] = now -- it's over: back to their routine
		elseif target and not arrived(d, now) then
			onTheWay[target.id] = (onTheWay[target.id] or 0) + 1
		end
	end
	for _, room in rooms do
		local want = handsWanted(room)
		if want > 0 then
			local present = S.IncidentService.present(vault, room, now)
			if dangerous(room) then
				for _, d in present do
					if d.health < d.maxHealth * RETREAT_HEALTH then
						vault.rt.think[d.id] = now -- badly hurt: decide now (they'll pull out)
					end
				end
			end
			local have = #present + (onTheWay[room.id] or 0)
			while have < want do
				local best, bestCost = nil, math.huge
				for _, d in vault.data.dwellers do
					local c = responderCost(vault, d, room, now)
					if c and c < bestCost then
						best, bestCost = d, c
					end
				end
				if not best or not LifeService.respond(vault, best, room, now) then
					break
				end
				have += 1
			end
		end
	end
end

-- Where a survivor belongs when no need is pressing: their job, else somewhere to unwind.
local function goHome(vault, d, now: number, relaxFor: number?)
	local job = d.roomId and vault.data.rooms[d.roomId]
	-- the badly hurt don't walk back into a fire or a fight
	local unsafe = dangerous(job) and d.health < d.maxHealth * RESPOND_HEALTH
	if job and d.status == "Working" and not relaxFor and not unsafe then
		LifeService.goTo(vault, d, job, "Working", now, nil)
		return
	end
	local lounge = (job and job.type == "Living" and not unsafe and job) or nearest(vault, d, now, function(r)
		return r.type == "Living" and not dangerous(r)
	end) or nearest(vault, d, now, function(r)
		return r.type == "Cafeteria" and not dangerous(r)
	end) or (not unsafe and job) or (d.at and vault.data.rooms[d.at])
	if lounge then
		LifeService.goTo(vault, d, lounge, "Relaxing", now, relaxFor or (if unsafe then 30 else nil))
	end
end

-- Pulled out of a fire or a fight: the Medbay if there's a bed, else any safe room for a while.
local function retreat(vault, d, now: number)
	if startTreatment(vault, d, now) then
		return
	end
	local here = d.at
	local safe = nearest(vault, d, now, function(r)
		return r.id ~= here and not dangerous(r) and r.type ~= "Elevator"
	end)
	if safe and LifeService.goTo(vault, d, safe, "Relaxing", now, 30) then
		return
	end
	vault.rt.think[d.id] = now + 4
end

-- Finishing activities ------------------------------------------------------------------
local function finishMeal(vault, d, now: number)
	local res = vault.data.resources
	local room = d.at and vault.data.rooms[d.at]
	local pressure = S.VaultService.pressure(vault)
	local portion = Config.MEAL_FOOD * (if d.child then 0.5 else 1) * Difficulty.consumption(pressure)
	local inCafe = room and room.type == "Cafeteria"
	local cook = if inCafe then bestCrewSkill(vault, room, "COO", now) else 0
	if cook > 0 then
		portion *= 1 - math.min(0.3, cook * 0.03)
	elseif not inCafe then
		portion *= 1.25 -- rations waste more
	end
	local got = math.min(res.Food, portion)
	res.Food -= got
	local frac = got / portion
	d.needs.Hunger = math.min(100, d.needs.Hunger + 100 * frac)
	if frac < 0.5 then
		LifeService.remember(d, "meal", "No food left", -8, 300, now)
		S.VaultService.send(vault, "bark", { id = d.id, kind = "NoFood" })
	elseif cook > 0 then
		LifeService.remember(d, "meal", "Hot meal from " .. (if cook >= 6 then "a great cook" else "the cook"), if cook >= 6 then 6 else 3, 420, now)
	elseif not inCafe then
		LifeService.remember(d, "meal", "Ate cold rations", -3, 300, now)
	end
end

local function finishDrink(vault, d, now: number)
	local res = vault.data.resources
	local pressure = S.VaultService.pressure(vault)
	local portion = Config.DRINK_WATER * (if d.child then 0.5 else 1) * Difficulty.consumption(pressure)
	local got = math.min(res.Water, portion)
	res.Water -= got
	local frac = got / portion
	d.needs.Thirst = math.min(100, d.needs.Thirst + 100 * frac)
	if frac < 0.5 then
		LifeService.remember(d, "drink", "No clean water", -8, 300, now)
		S.VaultService.send(vault, "bark", { id = d.id, kind = "NoWater" })
	end
end

-- Decide what to do next. Called when an activity ends or a check is due.
local function decide(vault, d: any, now: number)
	local think = vault.rt.think
	if d.travel and now < (d.arriveAt or 0) then
		think[d.id] = d.arriveAt
		return
	end
	local rooms = vault.data.rooms
	local here = d.at and rooms[d.at]
	local n = d.needs
	local act = d.activity
	-- responders stand down once the emergency is over, or when someone sent them elsewhere
	if d.respond then
		local target = rooms[d.respond]
		if not target or handsWanted(target) == 0 or d.at ~= d.respond then
			d.respond = nil
			if act == "Responding" then
				act = nil
			end
		end
	end
	-- anyone badly hurt in a fire or a fight pulls out instead of fighting to the death
	if dangerous(here) and act ~= "Sleeping" and Family.canFight(d) and d.health < d.maxHealth * RETREAT_HEALTH then
		d.respond = nil
		LifeService.remember(d, "retreat", "Pulled out of the " .. RoomDefinitions.Types[here.type].name .. " badly hurt", -4, 300, now)
		retreat(vault, d, now)
		return
	end
	-- emergencies in the room: fighters stay and fight, others keep clear (client huddles them)
	if here and here.incident and act ~= "Sleeping" and Family.canFight(d) then
		think[d.id] = now + 4
		return
	end
	-- finish timed / open activities
	if act == "Eating" then
		if now < (d.activityEnd or 0) then
			think[d.id] = d.activityEnd
			return
		end
		finishMeal(vault, d, now)
		act = nil
	elseif act == "Drinking" then
		if now < (d.activityEnd or 0) then
			think[d.id] = d.activityEnd
			return
		end
		finishDrink(vault, d, now)
		act = nil
	elseif act == "Sleeping" then
		local urgent = (n.Hunger < 10 or n.Thirst < 10) and n.Energy > 35
		local danger = here and (here.incident or (vault.rt.raid and vault.rt.raid.roomId == here.id))
		if n.Energy < 99 and not urgent and not danger then
			think[d.id] = now + 8
			return
		end
		if not d.floorSleep then
			LifeService.remember(d, "sleep", "Slept in a warm bunk", 3, 600, now)
		end
		d.floorSleep = nil
		goHome(vault, d, now, RELAX_AFTER_WAKE)
		return
	elseif act == "Treatment" then
		if d.health < d.maxHealth * 0.92 then
			think[d.id] = now + 6
			return
		end
		LifeService.remember(d, "treated", "Patched up in the Medbay", 2, 300, now)
		act = nil
	elseif act == "Relaxing" or act == "Visiting" then
		if d.activityEnd and now < d.activityEnd then
			think[d.id] = d.activityEnd
			return
		end
		if d.activityEnd then
			act = nil -- timed downtime is over
		end
	end
	-- needs, most urgent first
	if d.health < d.maxHealth * TREAT_THRESHOLD and startTreatment(vault, d, now) then
		return
	end
	if n.Thirst < Needs.Defs.Thirst.seek and startDrink(vault, d, now) then
		return
	end
	if n.Hunger < Needs.Defs.Hunger.seek and startEat(vault, d, now) then
		return
	end
	if n.Energy < Needs.Defs.Energy.seek and startSleep(vault, d, now) then
		return
	end
	-- check on a partner or close friend recovering in the Medbay
	if not d.child and now >= (d.visitAt or 0) then
		for id, aff in d.rel or {} do
			local o = vault.data.dwellers[id]
			if o and aff >= 60 and o.activity == "Treatment" and o.at and rooms[o.at] then
				d.visitAt = now + VISIT_COOLDOWN
				LifeService.remember(d, "worry" .. id, "Worried about " .. firstName(o), -5, 240, now)
				LifeService.goTo(vault, d, rooms[o.at], "Visiting", now, 15)
				return
			end
		end
	end
	-- otherwise: back to work / unwind
	local job = d.roomId and rooms[d.roomId]
	local atJob = d.at == d.roomId and (act == "Working" or (act == "Relaxing" and not d.activityEnd))
	if atJob and job then
		think[d.id] = now + WORK_CHECK
		return
	end
	goHome(vault, d, now, nil)
end

-- Relationships ---------------------------------------------------------------------------
local function bond(a: any, b: any, amount: number)
	a.rel = a.rel or {}
	a.rel[b.id] = math.clamp((a.rel[b.id] or 0) + amount * DwellerDefinitions.traitFactor(a, "social"), -100, 100)
end

local function socialPass(vault, now: number)
	local byRoom: { [string]: { any } } = {}
	for _, d in vault.data.dwellers do
		if Simulation.isInside(d) and d.at and arrived(d, now) and d.activity ~= "Sleeping" then
			byRoom[d.at] = byRoom[d.at] or {}
			table.insert(byRoom[d.at], d)
		end
	end
	local rng: Random = vault.rt.rng
	local dwellers = vault.data.dwellers
	for _, group in byRoom do
		if #group >= 2 then
			for _, d in group do
				-- a few conversations per survivor per pass keeps this O(n)
				for _ = 1, math.min(2, #group - 1) do
					local o = group[rng:NextInteger(1, #group)]
					if o ~= d then
						local social = d.activity == "Eating" or d.activity == "Relaxing" or d.activity == "Drinking"
						bond(d, o, if social then 1.4 else 0.6)
					end
				end
			end
		end
	end
	-- mood from the people around them, couples forming
	for _, d in dwellers do
		if not Simulation.isInside(d) then
			continue
		end
		local mood = 0
		local group = d.at and byRoom[d.at]
		if group then
			local friends = 0
			for _, o in group do
				if o ~= d and d.rel and (d.rel[o.id] or 0) >= 40 then
					friends += 1
				end
			end
			mood += math.min(6, friends * 2) * (if DwellerDefinitions.hasTrait(d, "Sociable") then 1.5 else 1)
		end
		local p = d.partner and dwellers[d.partner]
		if p then
			if p.status == "Dead" then
				mood -= 12
			elseif p.status == "Exploring" then
				mood -= 3 -- out in the wasteland (their stale room must not count as "together")
			elseif p.activity == "Treatment" or p.health < p.maxHealth * 0.35 then
				mood -= 6
			elseif p.at == d.at then
				mood += 3
			end
		elseif not d.child and d.rel then
			for id, aff in d.rel do
				local o = dwellers[id]
				if aff >= 70 and o and not o.partner and not o.child and o.gender ~= d.gender
					and (o.rel and (o.rel[d.id] or 0) >= 70) and not Family.related(d, o) then
					d.partner, o.partner = o.id, d.id
					S.DwellerService.push(vault, d)
					S.DwellerService.push(vault, o)
					S.VaultService.toast(vault, firstName(d) .. " and " .. firstName(o) .. " are now a couple!", "good")
					break
				end
			end
		end
		d.socialMood = mood
	end
end

-- The partner and family left behind when someone heads into the wasteland, and their relief
-- when they make it home (an expedition is never free for the people who stay).
function LifeService.expedition(vault, explorer: any, now: number, home: boolean)
	for _, o in vault.data.dwellers do
		if o ~= explorer and Simulation.isInside(o) and (o.partner == explorer.id or Family.related(o, explorer)) then
			if home then
				LifeService.remember(o, "away" .. explorer.id, firstName(explorer) .. " made it home", 4, 600, now)
			else
				LifeService.remember(o, "away" .. explorer.id, "Worried about " .. firstName(explorer) .. " out in the wasteland", -5, 3600, now)
			end
		end
	end
end

-- Grief: friends and partners remember a death.
function LifeService.onDeath(vault, dead: any, now: number)
	for _, d in vault.data.dwellers do
		if d ~= dead and Simulation.isInside(d) and d.rel then
			local aff = d.rel[dead.id] or 0
			if d.partner == dead.id then
				LifeService.remember(d, "grief" .. dead.id, "Lost " .. firstName(dead) .. ", their partner", -22, 1200, now)
			elseif aff >= 40 or Family.related(d, dead) then
				LifeService.remember(d, "grief" .. dead.id, "Lost a friend: " .. firstName(dead), -12, 900, now)
			end
		end
	end
end

-- Tick ----------------------------------------------------------------------------------------
function LifeService.tick(vault, dt: number, now: number)
	vault.rt.think = vault.rt.think or {}
	vault.rt.use = countUse(vault)
	local think = vault.rt.think
	vault.rt.respondAcc = (vault.rt.respondAcc or RESPOND_EVERY) + dt
	if vault.rt.respondAcc >= RESPOND_EVERY then
		vault.rt.respondAcc = 0
		dispatch(vault, now)
	end
	local due = {}
	for id, d in vault.data.dwellers do
		if not Simulation.isInside(d) then
			continue
		end
		local n = d.needs
		if not n then
			n = Needs.default()
			d.needs = n
		end
		local sleeping = d.activity == "Sleeping" and arrived(d, now)
		for _, key in Needs.LIST do
			local before = n[key]
			if key == "Energy" and sleeping then
				n.Energy = math.min(100, n.Energy + Needs.SLEEP_RESTORE * (if d.floorSleep then 0.6 else 1) * dt / 60)
			else
				n[key] = math.max(0, n[key] - Needs.decayOf(d, key) * (if sleeping then 0.5 else 1) * dt / 60)
			end
			-- crossing the threshold triggers a decision now
			local seek = Needs.Defs[key].seek
			if before >= seek and n[key] < seek and not sleeping then
				think[id] = math.min(think[id] or now, now)
			end
			local stage = Needs.stage(key, n[key])
			if stage and stage.damage > 0 then
				S.DwellerService.damage(vault, d, stage.damage * dt, if key == "Hunger" then "starvation" else "dehydration")
			end
		end
		if d.status == "Dead" then
			continue
		end
		-- rest and treatment heal; the Medbay uses medicine
		local room = d.at and vault.data.rooms[d.at]
		if d.health < d.maxHealth and arrived(d, now) and not (room and room.incident) then
			local heal = Config.REGEN_OTHER
			if d.activity == "Treatment" and room and room.type == "Infirmary" then
				local medic = bestCrewSkill(vault, room, "MED", now)
				local res = vault.data.resources
				if (res.MedPatch or 0) > 0 then
					heal = 0.7 + medic * 0.08
					d.medUse = (d.medUse or 0) + dt
					if d.medUse >= 40 then
						d.medUse = 0
						res.MedPatch -= 1
					end
				else
					heal = 0.15 + medic * 0.05
				end
			elseif sleeping then
				heal = 0.1
			elseif d.activity == "Relaxing" then
				heal = Config.REGEN_LIVING * 0.5
			end
			d.health = math.min(d.maxHealth, d.health + heal * dt)
		end
		if (think[id] or 0) <= now then
			table.insert(due, d)
		end
	end
	-- staggered decisions: the most overdue first, capped per tick
	table.sort(due, function(a, b)
		return (think[a.id] or 0) < (think[b.id] or 0)
	end)
	for i = 1, math.min(#due, MAX_THINKS_PER_TICK) do
		decide(vault, due[i], now)
	end
	vault.rt.socialAcc = (vault.rt.socialAcc or 0) + dt
	if vault.rt.socialAcc >= SOCIAL_EVERY then
		vault.rt.socialAcc = 0
		socialPass(vault, now)
	end
end

-- A survivor (re)enters the simulation: after loading, arriving, returning from the wasteland.
function LifeService.wake(vault, d: any, now: number)
	d.needs = d.needs or Needs.default()
	for _, key in Needs.LIST do
		d.needs[key] = math.max(d.needs[key], 55)
	end
	vault.rt.think = vault.rt.think or {}
	vault.rt.think[d.id] = now + vault.rt.rng:NextNumber(0.2, 2.5)
end

function LifeService.prime(vault)
	local now = S.VaultService.now()
	vault.rt.think = {}
	vault.rt.use = {}
	for _, d in vault.data.dwellers do
		if Simulation.isInside(d) then
			LifeService.wake(vault, d, now)
		end
	end
end

function LifeService.Init(services)
	S = services
end

local _ = RoomDefinitions
return LifeService
