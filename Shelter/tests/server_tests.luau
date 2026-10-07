-- Headless server tests (see run.py). Every T.<name> runs in its own fresh server process.
-- Globals in scope: H (fake engine, prelude.luau), out (real print), and the faked Roblox globals.
local T = {}

local failures = {}
local allowed = {}

local function check(cond: any, msg: string)
	if not cond then
		table.insert(failures, msg)
		out("  check failed: " .. msg)
	end
	return cond
end

-- warnings a test provokes on purpose
local function allowWarn(pattern: string)
	table.insert(allowed, pattern)
end

local function svc(name: string)
	return H.require(H.node("ServerScriptService.Server.Services." .. name))
end

local function shared(name: string)
	return H.require(H.node("ReplicatedStorage.Shared." .. name))
end

-- Call a server action exactly like a client would (no yielding before or after).
local function invokeNow(p, action: string, payload: any)
	local rf = H.node("ReplicatedStorage.Remotes.Action")
	local r = rf.OnServerInvoke(p, action, payload)
	if r.ok then
		return true, r.result
	end
	return false, r.reason
end

local function invoke(p, action: string, payload: any)
	local ok, r = invokeNow(p, action, payload)
	task.wait(0.1) -- stay under the per-player rate limit
	return ok, r
end

local function waitFor(cond: () -> any, timeout: number?, step: number?): boolean
	local t0 = H.clock()
	while not cond() do
		if H.clock() - t0 > (timeout or 60) then
			return false
		end
		task.wait(step or 0.25)
	end
	return true
end

local function serverReady()
	return waitFor(function()
		return H.services.ReplicatedStorage:FindFirstChild("Remotes") ~= nil and #H.closeFns > 0
	end, 30)
end

local function joinLoaded(userId: number)
	local p = H.join(userId)
	check(waitFor(function()
		return svc("VaultService").get(p) ~= nil
	end, 120), "player " .. userId .. " loaded")
	return p, svc("VaultService").get(p)
end

local function roomOf(vault, typeId: string)
	for _, r in vault.data.rooms do
		if r.type == typeId then
			return r
		end
	end
	return nil
end

local function dwellerNamed(vault, prefix: string)
	for _, d in vault.data.dwellers do
		if string.sub(d.name, 1, #prefix) == prefix then
			return d
		end
	end
	return nil
end

local function saved(userId: number)
	return H.store["shelter_" .. userId]
end

local function count(t): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

local function lastEvent(p, kind: string)
	local found
	for _, e in H.events[p] or {} do
		if e.kind == kind then
			found = e.payload
		end
	end
	return found
end

---------------------------------------------------------------------------------------------
-- Baseline: 25 minutes of play with every system exercised, a rejoin, and saves in between.
---------------------------------------------------------------------------------------------
T.smoke = function()
	serverReady()
	local p, v = joinLoaded(1)
	check(lastEvent(p, "snapshot") ~= nil, "snapshot sent on join")
	local kinds = { "Fire", "Rats", "Raid", "Arrival", "Breakdown", "Romance", "FamilyFF", "Pressure", "Bolts", "Roaches", "ExploreFF" }
	local explorer
	for minute = 1, 25 do
		for _ = 1, 12 do
			task.wait(5)
			for _, r in v.data.rooms do
				if r.readySince then
					invoke(p, "Collect", { roomId = r.id })
				end
				if r.incident and r.incident.kind == "Breakdown" and not r.incident.paid then
					invoke(p, "Repair", { roomId = r.id })
				end
			end
			for _, d in v.data.dwellers do
				if d.status == "Waiting" then
					invoke(p, "Admit", { dwellerId = d.id })
				end
			end
		end
		invoke(p, "Debug", { kind = kinds[(minute % #kinds) + 1] })
		if minute == 3 then
			for _, d in v.data.dwellers do
				if d.status == "Working" and d.health > d.maxHealth * 0.6 and not d.pregnant then
					explorer = d
					break
				end
			end
			local ok, why = invoke(p, "Explore", { dwellerId = explorer.id, medpatches = 1 })
			check(ok, "explore (" .. tostring(why) .. ")")
		elseif minute == 8 then
			invoke(p, "Recall", { dwellerId = explorer.id })
		elseif minute == 10 then
			local slots = shared("Grid").validSlots(v.data.rooms, "Storage")
			v.data.resources.Bolts += 1000
			v.data.resources.Materials = 200
			check(#slots > 0 and invoke(p, "Build", { type = "Storage", col = slots[1].col, row = slots[1].row }), "build")
		elseif minute == 12 then
			local room = roomOf(v, "Water")
			invoke(p, "Rush", { roomId = room.id })
		elseif minute == 15 then
			H.leave(p)
			task.wait(10)
			p, v = joinLoaded(1)
		end
	end
	check(svc("VaultService").save(v, false), "a full save of the played shelter goes through")
	check(v.data.resources.MedPatch == v.data.resources.MedPatch, "resources are numbers")
end

---------------------------------------------------------------------------------------------
-- 1. NaN injection through the Explore request
---------------------------------------------------------------------------------------------
T.nan_medpatches = function()
	serverReady()
	local p, v = joinLoaded(1)
	invoke(p, "Explore", { dwellerId = dwellerNamed(v, "Theo").id, medpatches = "nan" })
	local mp = v.data.resources.MedPatch
	check(mp == mp, "string 'nan' leaves MedPatch a number (got " .. tostring(mp) .. ")")
	invoke(p, "Explore", { dwellerId = dwellerNamed(v, "Maya").id, medpatches = 0 / 0 })
	mp = v.data.resources.MedPatch
	check(mp == mp, "raw NaN leaves MedPatch a number (got " .. tostring(mp) .. ")")
	for id, rec in v.data.exploration do
		check(rec.medpatches == rec.medpatches, "explorer " .. id .. " carries a real number of MedPatches")
	end
	v.data.resources.MedPatch = 0
	local hurt = dwellerNamed(v, "James")
	hurt.health = 10
	check(not invoke(p, "Heal", { dwellerId = hurt.id }), "Heal still needs a MedPatch")
	check(not invoke(p, "Build", { type = "Storage", col = 1 / 0, row = 0 }), "infinite numbers rejected")
end

---------------------------------------------------------------------------------------------
-- 2. Shutdown must not drop saves that are still in flight
---------------------------------------------------------------------------------------------
T.shutdown_waits_for_saves = function()
	serverReady()
	local ps = {}
	for i = 1, 3 do
		local p, v = joinLoaded(10 + i)
		ps[i] = p
		v.data.resources.Bolts = 4240 + i
	end
	H.ds.latency = 2.5
	local closing = 0
	for _, fn in H.closeFns do
		closing += 1
		task.spawn(function()
			fn()
			closing -= 1
		end)
	end
	for _, p in ps do
		H.leave(p)
	end
	check(waitFor(function()
		return closing == 0
	end, 30, 0.05), "BindToClose finished within 30 s")
	H.kill() -- the process ends the moment BindToClose returns
	for i = 1, 3 do
		local s = saved(10 + i)
		check(s and s.data and s.data.resources.Bolts == 4240 + i, "player " .. i .. " progress saved before shutdown")
		check(s and s.lock == nil, "player " .. i .. " session lock released")
	end
end

---------------------------------------------------------------------------------------------
-- 3. Damaged saves: repair what we can, never overwrite what we couldn't archive
---------------------------------------------------------------------------------------------
T.corrupt_save_repaired = function()
	serverReady()
	allowWarn("SaveService")
	local p, v = joinLoaded(1)
	local shelterNo = v.data.shelterNo
	local maya = dwellerNamed(v, "Maya")
	H.leave(p)
	task.wait(5)
	saved(1).data.dwellers[maya.id].stats = nil -- one damaged record
	p, v = joinLoaded(1)
	check(v.data.shelterNo == shelterNo, "same shelter loaded, not a fresh one")
	check(v.data.dwellers[maya.id] == nil, "damaged survivor dropped")
	check(dwellerNamed(v, "Sarah") ~= nil, "everyone else kept")
	for _, r in v.data.rooms do
		check(table.find(r.assigned, maya.id) == nil, "no room still lists the dropped survivor")
	end
	local archived = false
	for k in H.store do
		if string.find(k, "shelter_1_corrupt_", 1, true) then
			archived = true
		end
	end
	check(archived, "original save archived")
	task.wait(90)
end

T.corrupt_save_not_overwritten = function()
	serverReady()
	allowWarn("SaveService")
	local p, v = joinLoaded(1)
	H.leave(p)
	task.wait(5)
	saved(1).data.rooms = "garbage" -- unrecoverable
	H.ds.failKeys["_corrupt_"] = true -- and the archive copy can't be written
	p = H.join(1)
	task.wait(150)
	local s = saved(1)
	check(s.data.rooms == "garbage", "damaged save left untouched while it can't be archived")
	check(p.kicked ~= nil, "player asked to come back later")
	check(s.lock == nil, "session lock released")
end

---------------------------------------------------------------------------------------------
-- 4. Session locks
---------------------------------------------------------------------------------------------
T.lock_released_when_leaving_during_load = function()
	serverReady()
	H.ds.latency = 3
	local p = H.join(7)
	task.wait(1) -- the load is still in flight
	H.leave(p)
	task.wait(30)
	local s = saved(7)
	check(s == nil or s.lock == nil, "session lock released (held by " .. tostring(s and s.lock and s.lock.job) .. ")")
end

T.stolen_lock_detected = function()
	serverReady()
	local p, v = joinLoaded(1)
	saved(1).lock = { job = "job-B", time = os.time() } -- another server took over the session
	local ok = svc("VaultService").save(v, false)
	check(ok == false, "save reports that it did not save")
	task.wait(1)
	check(p.kicked ~= nil, "player told the shelter is open elsewhere")
end

T.lock_refreshed_while_idle = function()
	serverReady()
	local p, v = joinLoaded(1)
	local VS = svc("VaultService")
	VS.dirty = function() end -- nothing in the shelter changes
	local lockTimes = {}
	for _ = 1, 8 do
		v.rt.dirty = false
		task.wait(60)
		table.insert(lockTimes, saved(1).lock and saved(1).lock.time or 0)
	end
	local stale = os.time() - lockTimes[#lockTimes]
	check(stale < 200, "lock refreshed even when the shelter looked unchanged (" .. stale .. " s old)")
	local _ = p
end

---------------------------------------------------------------------------------------------
-- 5. Wanderers outside the door are not part of the shelter yet
---------------------------------------------------------------------------------------------
T.waiting_wanderer_cannot_explore = function()
	serverReady()
	local p, v = joinLoaded(1)
	v.rt.nextArrival = 0
	local w
	check(waitFor(function()
		for _, d in v.data.dwellers do
			if d.status == "Waiting" then
				w = d
				return true
			end
		end
		return false
	end, 120), "a wanderer reached the door")
	if not w then
		return
	end
	check(not invoke(p, "Explore", { dwellerId = w.id }), "can't send a wanderer exploring before letting them in")
	check(w.status == "Waiting", "still waiting outside")
end

---------------------------------------------------------------------------------------------
-- 6. Raids vs. rooms that vanish; demolition during emergencies
---------------------------------------------------------------------------------------------
T.raid_skips_missing_rooms = function()
	serverReady()
	local p, v = joinLoaded(1)
	local CS = svc("CombatService")
	check(CS.startRaid(v), "raid started")
	local raid = v.rt.raid
	raid.phase = "inside"
	raid.roomId = "9998" -- the room they were in was demolished / merged
	table.insert(raid.order, 1, "9999") -- and so was the next one on their route
	task.wait(1)
	check(v.rt.raid ~= nil, "raid carries on past rooms that no longer exist")
	check(v.rt.raid == nil or v.data.rooms[v.rt.raid.moveTo] ~= nil, "raiders head for a real room")
	local _ = p
end

T.no_demolition_during_emergencies = function()
	serverReady()
	local p, v = joinLoaded(1)
	local living = roomOf(v, "Living")
	check(svc("IncidentService").startFire(v, living, "test"), "fire started")
	check(not invoke(p, "Destroy", { roomId = living.id }), "can't demolish a burning room")
	check(v.data.rooms[living.id] ~= nil, "room still there")
	living.incident = nil
	check(svc("CombatService").startRaid(v), "raid started")
	check(not invoke(p, "Destroy", { roomId = living.id }), "can't demolish while raiders are around")
end

T.demolition_moves_people_out = function()
	serverReady()
	local p, v = joinLoaded(1)
	local living = roomOf(v, "Living")
	local sarah = dwellerNamed(v, "Sarah")
	sarah.needs = { Hunger = 100, Thirst = 100, Energy = 100 }
	sarah.at, sarah.activity, sarah.travel, sarah.arriveAt, sarah.activityEnd = living.id, "Relaxing", nil, 0, nil
	local ok, why = invokeNow(p, "Destroy", { roomId = living.id })
	check(ok, "demolished (" .. tostring(why) .. ")")
	check(sarah.at ~= living.id, "nobody left standing in a demolished room")
	task.wait(10)
	check(sarah.at == nil or v.data.rooms[sarah.at] ~= nil, "she is somewhere real")
end

---------------------------------------------------------------------------------------------
-- 7. Rejoining doesn't clear emergencies or raids
---------------------------------------------------------------------------------------------
T.incidents_survive_rejoin = function()
	serverReady()
	local p, v = joinLoaded(1)
	local IS = svc("IncidentService")
	local living, power = roomOf(v, "Living"), roomOf(v, "Power")
	check(IS.startFire(v, living, "test"), "fire started")
	check(IS.startBreakdown(v, power, "test"), "breakdown started")
	H.leave(p)
	task.wait(10)
	check(saved(1).lock == nil, "released on leave")
	p, v = joinLoaded(1)
	local fire = v.data.rooms[living.id].incident
	check(fire and fire.kind == "Fire", "fire still burning after rejoining")
	local bd = v.data.rooms[power.id].incident
	check(bd and bd.kind == "Breakdown" and bd.paid == false, "unpaid breakdown still there after rejoining")
	task.wait(60) -- keeps burning / spreading without errors
	check(invoke(p, "Repair", { roomId = power.id }), "the saved breakdown can still be repaired")
end

T.raid_resumes_after_rejoin = function()
	serverReady()
	local p, v = joinLoaded(1)
	check(svc("CombatService").startRaid(v), "raid started")
	H.leave(p)
	task.wait(5)
	p, v = joinLoaded(1)
	check(waitFor(function()
		return v.rt.raid ~= nil
	end, 120), "raiders at the door come back soon after rejoining")
end

---------------------------------------------------------------------------------------------
-- 8. Rush: production chains apply, no free batch
---------------------------------------------------------------------------------------------
T.rush_uses_inputs = function()
	serverReady()
	local p, v = joinLoaded(1)
	v.data.resources.Bolts, v.data.resources.Materials = 5000, 400
	local slots = shared("Grid").validSlots(v.data.rooms, "Infirmary")
	local ok, res = invoke(p, "Build", { type = "Infirmary", col = slots[1].col, row = slots[1].row })
	check(ok, "medbay built (" .. tostring(res) .. ")")
	local bay = v.data.rooms[res.roomId]
	local iris = dwellerNamed(v, "Iris")
	iris.needs = { Hunger = 100, Thirst = 100, Energy = 100 }
	check(invoke(p, "Assign", { dwellerId = iris.id, roomId = bay.id }), "medic assigned")
	local Sim = shared("Simulation")
	check(waitFor(function()
		iris.needs = { Hunger = 100, Thirst = 100, Energy = 100 }
		return Sim.isWorking(iris, workspace:GetServerTimeNow())
	end, 60, 0.05), "medic at work")
	local rng = v.rt.rng
	v.rt.rng = { -- a lucky rush
		NextNumber = function(_, a, b)
			return if a then b else 0.99
		end,
		NextInteger = function(_, a)
			return a
		end,
	}
	bay.pending, bay.readySince = 0, nil
	v.data.resources.Water = 0
	local ok2, r2 = invokeNow(p, "Rush", { roomId = bay.id })
	v.rt.rng = rng
	check(not (ok2 and r2.success) or bay.pending < 1, "no medicine without water (pending " .. tostring(bay.pending) .. ")")
	check(bay.pending < 1, "no free batch")
	v.data.resources.Water = 80
	v.rt.rushReady[bay.id] = 0
	v.rt.rng = { NextNumber = function(_, a, b)
		return if a then b else 0.99
	end, NextInteger = function(_, a)
		return a
	end }
	ok2, r2 = invokeNow(p, "Rush", { roomId = bay.id })
	v.rt.rng = rng
	check(ok2 and r2.success, "second rush went through")
	check(v.data.resources.Water < 80, "rushing the medbay uses water")
	check(bay.pending > 0, "and makes some medicine")
end

---------------------------------------------------------------------------------------------
-- 9. Tapping into full storage
---------------------------------------------------------------------------------------------
T.full_storage_pays_no_bonus = function()
	serverReady()
	local p, v = joinLoaded(1)
	local water = roomOf(v, "Water")
	v.data.resources.Water = shared("Simulation").storageCaps(v.data.rooms).Water
	water.pending, water.readySince = 12, workspace:GetServerTimeNow()
	local bolts0 = v.data.resources.Bolts
	local ok, r = invokeNow(p, "Collect", { roomId = water.id })
	check(ok and r.amount == 0, "nothing fit in storage")
	check(v.data.resources.Bolts == bolts0, "no bonus bolts for production thrown away (+" .. (v.data.resources.Bolts - bolts0) .. ")")
end

---------------------------------------------------------------------------------------------
-- 10. Dying in the wasteland; recruits who don't fit
---------------------------------------------------------------------------------------------
T.explorer_death_is_a_death = function()
	serverReady()
	local p, v = joinLoaded(1)
	local Exploration = shared("Exploration")
	local sarah, james = dwellerNamed(v, "Sarah"), dwellerNamed(v, "James")
	check(sarah.partner == james.id, "Sarah and James are partners")
	check(invoke(p, "Explore", { dwellerId = james.id }), "sent exploring")
	local rec = v.data.exploration[james.id]
	local hurting = { RuinedLab = true, Checkpoint = true, Bunker = true, RaiderCamp = true, Mutant = true }
	for seed = 1, 5000 do
		if hurting[Exploration.pickEvent(Random.new(seed), 0)] then
			rec.seed = seed
			break
		end
	end
	james.health = 0.001
	check(waitFor(function()
		return james.status == "Dead"
	end, 60), "explorer died")
	check(james.diedAt ~= nil, "death recorded (diedAt)")
	local grieving = false
	for _, m in sarah.memories or {} do
		if string.find(m.id, "grief", 1, true) then
			grieving = true
		end
	end
	check(grieving, "partner grieves")
end

T.recruit_count_is_honest = function()
	serverReady()
	local p, v = joinLoaded(1)
	v.rt.nextArrival = math.huge
	local theo = dwellerNamed(v, "Theo")
	check(invoke(p, "Explore", { dwellerId = theo.id }), "sent exploring")
	v.data.exploration[theo.id].recruits = 12
	check(invoke(p, "Recall", { dwellerId = theo.id }), "recalled")
	local before = count(v.data.dwellers)
	check(waitFor(function()
		return lastEvent(p, "exploreEnd") ~= nil
	end, 60), "explorer home")
	local added = count(v.data.dwellers) - before
	local summary = lastEvent(p, "exploreEnd").summary
	check(summary.recruits == added, "summary counts the recruits who moved in (" .. summary.recruits .. " vs " .. added .. ")")
end

---------------------------------------------------------------------------------------------
-- 11. The dead don't hold on to their job
---------------------------------------------------------------------------------------------
T.dead_free_their_room = function()
	serverReady()
	local p, v = joinLoaded(1)
	local food = roomOf(v, "Food")
	local maya = dwellerNamed(v, "Maya")
	svc("DwellerService").kill(v, maya, "test")
	local ok, why = invoke(p, "Destroy", { roomId = food.id })
	check(ok, "room whose only worker died can be demolished (" .. tostring(why) .. ")")
	check(invoke(p, "Revive", { dwellerId = maya.id }), "revived")
	check(maya.roomId == nil or v.data.rooms[maya.roomId] ~= nil, "revived survivor has no stale job")
end

---------------------------------------------------------------------------------------------
-- 12. Traits and small things
---------------------------------------------------------------------------------------------
T.brave_and_nervous = function()
	local Sim = shared("Simulation")
	local function mk(traits)
		return {
			status = "Idle", traits = traits, health = 100, maxHealth = 100, happiness = 50,
			needs = { Hunger = 100, Thirst = 100, Energy = 100 }, stats = {},
		}
	end
	local calm = { rooms = {}, resources = { Power = 50 }, population = 5, housing = 10, mood = 0, now = 0, danger = 0 }
	local alarm = table.clone(calm)
	alarm.danger = 1
	local function drop(traits)
		return Sim.happinessTarget(mk(traits), calm) - Sim.happinessTarget(mk(traits), alarm)
	end
	local base, brave, nervous = drop({ "HardWorker" }), drop({ "Brave" }), drop({ "Nervous" })
	check(base > 0, "emergencies weigh on morale (" .. base .. ")")
	check(brave == 0, "Brave survivors are unfazed (" .. brave .. ")")
	check(nervous > base, "Nervous survivors are hit harder (" .. nervous .. " vs " .. base .. ")")
end

T.emergency_reaches_morale = function()
	serverReady()
	local p, v = joinLoaded(1)
	check(svc("IncidentService").startFire(v, roomOf(v, "Living"), "test"), "fire started")
	local Sim = shared("Simulation")
	local seen
	local real = Sim.happinessTarget
	Sim.happinessTarget = function(d, ctx)
		seen = ctx.danger
		return real(d, ctx)
	end
	task.wait(2)
	Sim.happinessTarget = real
	check(seen and seen > 0, "the shelter knows there is an emergency (" .. tostring(seen) .. ")")
	local _ = p
end

T.rename_is_saved = function()
	serverReady()
	local p, v = joinLoaded(1)
	v.rt.dirty = false
	check(invokeNow(p, "Rename", { dwellerId = dwellerNamed(v, "Theo").id, name = "Theodore Vance" }), "renamed")
	check(v.rt.dirty, "rename marks the shelter for saving")
end

-- A room with a free work slot that isn't this survivor's own.
local function openPost(v, d)
	local Simulation = shared("Simulation")
	local Defs = shared("RoomDefinitions").Types
	for _, r in v.data.rooms do
		if r.id ~= d.roomId and Defs[r.type].slots > 0 and r.type ~= "Elevator" and not r.incident
			and #r.assigned < Simulation.capacity(r) then
			return r
		end
	end
	return nil
end

T.assigned_survivor_stays_at_post = function()
	serverReady()
	local p, v = joinLoaded(1)
	local VS = svc("VaultService")
	task.wait(5)
	local d = dwellerNamed(v, "Theo")
	local post = openPost(v, d)
	check(post ~= nil, "a room with a free slot")
	-- thirst just above where they'd go for a drink, hunger already below it: the old behaviour
	-- walked them straight back out
	d.needs = { Hunger = 44, Thirst = 52, Energy = 80 }
	check(invoke(p, "Assign", { dwellerId = d.id, roomId = post.id }), "assigned")
	local arrive = d.arriveAt
	local left = nil
	while VS.now() < arrive + 85 do
		task.wait(0.5)
		if VS.now() > arrive + 0.5 and (d.at ~= post.id or d.activity ~= "Working") then
			left = VS.now() - arrive
			break
		end
	end
	check(left == nil, "stays at the post through the shift (left after " .. tostring(left) .. " s for " .. tostring(d.activity) .. ")")
	-- after the shift, the break they've been putting off
	check(waitFor(function()
		return d.activity == "Eating" or d.activity == "Drinking"
	end, 30), "takes the break once the shift is over (" .. tostring(d.activity) .. ")")
	check(waitFor(function()
		return d.at == post.id and d.activity == "Working"
	end, 90), "and comes back to the post afterwards")
end

T.urgent_need_still_interrupts_a_shift = function()
	serverReady()
	local p, v = joinLoaded(1)
	local VS = svc("VaultService")
	task.wait(5)
	local d = dwellerNamed(v, "Theo")
	local post = openPost(v, d)
	d.needs = { Hunger = 90, Thirst = 90, Energy = 90 }
	check(invoke(p, "Assign", { dwellerId = d.id, roomId = post.id }), "assigned")
	check(waitFor(function()
		return d.at == post.id and VS.now() >= (d.arriveAt or 0)
	end, 30), "arrived")
	task.wait(10)
	check(d.at == post.id and d.activity == "Working", "working")
	d.needs.Thirst = 22.3 -- about to become very thirsty
	check(waitFor(function()
		return d.activity == "Drinking"
	end, 5), "an urgent need still pulls them away (" .. tostring(d.activity) .. ")")
end

T.dispatch_leaves_fresh_assignments_alone = function()
	serverReady()
	local p, v = joinLoaded(1)
	task.wait(5)
	for _, o in v.data.dwellers do
		o.needs = { Hunger = 100, Thirst = 100, Energy = 100 }
	end
	local d = dwellerNamed(v, "Theo")
	local post = openPost(v, d)
	check(invoke(p, "Assign", { dwellerId = d.id, roomId = post.id }), "assigned")
	local living = roomOf(v, "Living")
	check(svc("IncidentService").startFire(v, living, "test"), "fire elsewhere")
	task.wait(6)
	check(d.respond == nil and d.at == post.id, "the survivor the Overseer just placed isn't sent to the fire")
	local others = 0
	for _, o in v.data.dwellers do
		if o.respond == living.id then
			others += 1
		end
	end
	check(others >= 1, "others still respond (" .. others .. ")")
end

T.audio_volumes_saved = function()
	serverReady()
	local p, v = joinLoaded(1)
	local SS = H.services.SoundService
	check(SS:FindFirstChild("Master") and SS:FindFirstChild("SFX") and SS:FindFirstChild("Voice"), "SoundGroups built at server start")
	check(H.node("ReplicatedStorage.Audio"):GetAttribute("Built") == true, "audio library built for the clients")
	check(invoke(p, "Settings", { volumes = { SFX = 0.33, Master = 2, Music = -1, Bogus = 0.5 } }), "volumes accepted")
	local vols = v.data.settings.volumes
	check(vols.SFX == 0.35 and vols.Master == 1 and vols.Music == 0 and vols.Bogus == nil, "clamped, rounded to 5%, unknown keys ignored")
	check(not invoke(p, "Settings", { volumes = { SFX = 0 / 0 } }), "NaN rejected")
	check(v.data.settings.volumes.SFX == 0.35, "a bad value doesn't overwrite")
	check(invoke(p, "Settings", { volumes = { UI = 0.5 } }), "one slider at a time")
	check(v.data.settings.volumes.SFX == 0.35 and v.data.settings.volumes.UI == 0.5, "other sliders kept")
	local copy = H.jsonCopy(v.data)
	check(copy.settings.volumes.SFX == 0.35, "volumes survive a save")
end

---------------------------------------------------------------------------------------------
-- Emergency response (design doc §10 / §23): survivors elsewhere drop what they're doing
---------------------------------------------------------------------------------------------
local function responders(v, roomId: string)
	local list = {}
	for _, d in v.data.dwellers do
		if d.respond == roomId then
			table.insert(list, d)
		end
	end
	return list
end

T.fire_in_empty_room_draws_responders = function()
	serverReady()
	local p, v = joinLoaded(1)
	local living = roomOf(v, "Living") -- nobody works in the bedrooms
	for _, d in v.data.dwellers do
		d.needs = { Hunger = 100, Thirst = 100, Energy = 100 }
	end
	check(svc("IncidentService").startFire(v, living, "test"), "fire started")
	task.wait(4)
	local sent = responders(v, living.id)
	check(#sent >= 2, "at least two survivors sent to fight it (" .. #sent .. ")")
	check(waitFor(function()
		return living.incident == nil
	end, 60), "fire put out within a minute (a fire nobody fights burns ~2.5 min and spreads)")
	task.wait(6)
	check(#responders(v, living.id) == 0, "responders stand down once it's out")
	for _, d in sent do
		check(d.activity ~= "Responding", d.name .. " went back to their routine")
	end
	local _ = p
end

T.paid_repair_brings_an_engineer = function()
	serverReady()
	local p, v = joinLoaded(1)
	local power = roomOf(v, "Power")
	local sarah = dwellerNamed(v, "Sarah") -- the only generator crew
	check(invoke(p, "Assign", { dwellerId = sarah.id, roomId = roomOf(v, "Living").id }), "crew moved away")
	task.wait(15)
	check(#power.assigned == 0, "generator unstaffed")
	check(svc("IncidentService").startBreakdown(v, power, "test"), "breakdown")
	task.wait(6)
	check(#responders(v, power.id) == 0, "nobody shows up before the Overseer pays for parts")
	v.data.resources.Materials = 500
	check(invoke(p, "Repair", { roomId = power.id }), "repair paid")
	task.wait(4)
	local sent = responders(v, power.id)
	check(#sent >= 1, "someone sent to fix it")
	local best, bestEng = nil, -1
	for _, d in sent do
		local eng = shared("Simulation").stat(d, "ENG")
		if eng > bestEng then
			best, bestEng = d, eng
		end
	end
	check(waitFor(function()
		return power.incident == nil
	end, 120), "generator repaired")
	local _ = best
end

T.hurt_responders_pull_back = function()
	serverReady()
	local p, v = joinLoaded(1)
	local living = roomOf(v, "Living")
	for _, d in v.data.dwellers do
		d.needs = { Hunger = 100, Thirst = 100, Energy = 100 }
	end
	check(svc("IncidentService").startInfestation(v, living, "test", "Roaches"), "infestation started")
	living.incident.hp *= 50 -- a long fight
	local first
	check(waitFor(function()
		for _, d in v.data.dwellers do
			if d.respond == living.id and d.at == living.id and (d.arriveAt or 0) <= workspace:GetServerTimeNow() then
				first = d
				return true
			end
		end
		return false
	end, 60), "a responder reached the room")
	if not first then
		return
	end
	first.health = first.maxHealth * 0.2
	task.wait(6)
	check(first.status ~= "Dead", "the wounded responder is still alive")
	check(first.respond == nil and first.at ~= living.id, "and pulled back instead of fighting to the death")
	local _ = p
end

---------------------------------------------------------------------------------------------
-- Expeditions weigh on the people left behind (design doc §14)
---------------------------------------------------------------------------------------------
T.partner_worries_about_explorer = function()
	serverReady()
	local p, v = joinLoaded(1)
	local sarah, james = dwellerNamed(v, "Sarah"), dwellerNamed(v, "James")
	check(sarah.partner == james.id, "partners")
	check(invoke(p, "Explore", { dwellerId = james.id }), "James sent out")
	task.wait(8)
	local function memory(d, id)
		for _, m in d.memories or {} do
			if m.id == id then
				return m
			end
		end
		return nil
	end
	local worry = memory(sarah, "away" .. james.id)
	check(worry and worry.value < 0, "Sarah worries while James is outside")
	check((sarah.socialMood or 0) < 0, "and it shows in her mood (" .. tostring(sarah.socialMood) .. ")")
	check(invoke(p, "Recall", { dwellerId = james.id }), "recalled")
	check(waitFor(function()
		return james.status ~= "Exploring"
	end, 60), "James is back")
	local relief = memory(sarah, "away" .. james.id)
	check(relief and relief.value > 0, "relief when he's home")
end

---------------------------------------------------------------------------------------------
-- Scale (design doc §38): a big, busy colony must stay cheap on the server
---------------------------------------------------------------------------------------------
-- Replace the starter shelter with a full-height one: a central shaft, a 3-module room on either
-- side of every floor (all level 3), and `pop` survivors with jobs filled first.
local function bigColony(v, pop: number)
	local DS = svc("DwellerService")
	local rooms = {}
	local n = 0
	local function add(typeId, col, row, modules)
		n += 1
		local id = "b" .. n
		rooms[id] = { id = id, type = typeId, col = col, row = row, modules = modules, level = if typeId == "Elevator" or typeId == "Entrance" then 1 else 3, assigned = {}, pending = 0 }
		return rooms[id]
	end
	add("Entrance", 9, 0, 1)
	local cycle = { "Living", "Power", "Water", "Food", "Cafeteria", "Living", "Infirmary", "Storage", "Workshop", "Living" }
	local k = 0
	for row = 0, 24 do
		add("Elevator", 12, row, 1)
		if row > 0 then
			k += 1
			add(cycle[(k - 1) % #cycle + 1], 3, row, 3)
			k += 1
			add(cycle[(k - 1) % #cycle + 1], 13, row, 3)
		else
			add("Living", 13, row, 3)
		end
	end
	v.data.rooms = rooms
	v.data.dwellers = {}
	v.data.exploration = {}
	for key in v.data.resources do
		v.data.resources[key] = 2000
	end
	local jobs = {}
	for _, r in rooms do
		local def = shared("RoomDefinitions").Types[r.type]
		for _ = 1, def.slots * r.modules do
			table.insert(jobs, r)
		end
	end
	for i = 1, pop do
		local d = DS.create(v, { level = 3 })
		local r = jobs[i]
		if r then
			table.insert(r.assigned, d.id)
			d.roomId, d.at, d.status, d.activity = r.id, r.id, "Working", "Working"
		end
	end
	svc("LifeService").prime(v)
	v.rt.nextArrival = math.huge
	v.rt.nextRaid = math.huge
	return rooms
end

local function measure(pop: number, seconds: number): number
	local p, v = joinLoaded(1)
	bigColony(v, pop)
	task.wait(5) -- settle: first decisions for everyone
	local t0 = H.realClock()
	task.wait(seconds)
	local cost = (H.realClock() - t0) / seconds * 1000
	out(string.format("  %d survivors: %.1f ms of server time per second", pop, cost))
	local _ = p
	return cost
end

T.scale_200 = function()
	serverReady()
	check(measure(200, 60) < 40, "200 survivors cost under 40 ms per second")
end

T.scale_500 = function()
	serverReady()
	check(measure(500, 60) < 80, "500 survivors cost under 80 ms per second")
end

T.scale_500_with_emergencies = function()
	serverReady()
	local p, v = joinLoaded(1)
	bigColony(v, 500)
	task.wait(5)
	local IS = svc("IncidentService")
	local n = 0
	for _, r in v.data.rooms do
		if n < 3 and r.type ~= "Elevator" and r.type ~= "Entrance" and r.row > 5 then
			if IS.startFire(v, r, "test") then
				r.incident.hp *= 20 -- keep them burning for the whole measurement
				n += 1
			end
		end
	end
	check(n == 3, "three fires")
	local t0 = H.realClock()
	task.wait(60)
	local cost = (H.realClock() - t0) / 60 * 1000
	out(string.format("  500 survivors + 3 fires: %.1f ms of server time per second", cost))
	check(cost < 80, "emergency dispatch stays cheap at 500 survivors")
	local _ = p
end

---------------------------------------------------------------------------------------------
-- Runner
---------------------------------------------------------------------------------------------
T.__run = function(name: string)
	local main = H.node("ServerScriptService.Server.Main")
	task.spawn(rawget(main, "_props").__source, main, H.require)
	local done = false
	task.spawn(function()
		local ok, err = pcall(T[name])
		if not ok then
			table.insert(failures, "test error: " .. tostring(err))
		end
		done = true
	end)
	H.runUntil(H.clock() + 6 * 3600, function()
		return done
	end)
	if not done then
		table.insert(failures, "test did not finish")
	end
	for _, e in H.errors do
		table.insert(failures, "thread error: " .. e)
	end
	for _, w in H.warnings do
		local ok = false
		for _, pat in allowed do
			if string.find(w, pat, 1, true) then
				ok = true
			end
		end
		if not ok then
			table.insert(failures, "unexpected warning: " .. w)
		end
	end
	out(if #failures == 0 then "RESULT PASS" else "RESULT FAIL")
	for _, f in failures do
		out("  - " .. f)
	end
end

return T
