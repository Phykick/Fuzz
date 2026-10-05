--!strict
-- Economy: production into per-room batches, tap-to-collect (with luck bonus) or auto-collect,
-- production chains (rooms consume input resources as they produce), the power grid (graded
-- brownouts), storage caps, rush, and offline catch-up. All timing uses server clocks.
--
-- Food and water are consumed meal by meal by survivors (LifeService). The flow numbers sent to
-- the HUD use the statistical expectation (Simulation.expectedUse) so trends are smooth.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Simulation = require(ReplicatedStorage.Shared.Simulation)
local RoomDefinitions = require(ReplicatedStorage.Shared.RoomDefinitions)
local Difficulty = require(ReplicatedStorage.Shared.Difficulty)
local Resources = require(ReplicatedStorage.Shared.Resources)

local ResourceService = {}
local S: any

local function batchSize(room): number
	local def = RoomDefinitions.Types[room.type]
	if not def.rate then
		return math.huge
	end
	return math.max(3, def.rate[room.level] * room.modules * Simulation.CYCLE_SECONDS / 60 * 0.6)
end
ResourceService.batchSize = batchSize

local function crewLuck(vault, room, now): (number, number)
	local sum, n = 0, 0
	for _, id in room.assigned do
		local d = vault.data.dwellers[id]
		if d and Simulation.isWorking(d, now) then
			sum += Simulation.stat(d, "SCV")
			n += 1
		end
	end
	return if n > 0 then sum / n else 0, n
end

local function emptyFlow(): { [string]: { prod: number, use: number } }
	local f = {}
	for _, key in Resources.LIST do
		f[key] = { prod = 0, use = 0 }
	end
	return f
end

function ResourceService.pushResources(vault)
	local derived = S.VaultService.derived(vault)
	S.VaultService.send(vault, "res", {
		resources = vault.data.resources,
		rates = vault.rt.rates,
		flow = vault.rt.flow,
		powerFactor = vault.rt.powerFactor or 1,
		caps = derived.caps,
		housing = derived.housing,
		population = derived.population,
		happiness = derived.happiness,
		pressure = derived.pressure,
		t = S.VaultService.now(),
	})
end

-- Move a room's pending batch into storage. tapped=true grants the collection bonus.
local function deposit(vault, room, tapped: boolean, now: number)
	local def = RoomDefinitions.Types[room.type]
	local resKey = def.produces
	if not resKey then
		return 0, 0
	end
	local amount = math.floor(room.pending)
	room.pending -= amount
	room.readySince = nil
	local caps = Simulation.storageCaps(vault.data.rooms)
	local res = vault.data.resources
	local before = res[resKey] or 0
	res[resKey] = math.min(caps[resKey] or math.huge, before + amount)
	local gained = res[resKey] - before
	if gained < amount then
		vault.rt.wasted = vault.rt.wasted or {}
		vault.rt.wasted[resKey] = now -- storage full: production is being thrown away
	end
	local bolts = 0
	if tapped and amount > 0 then
		local luck = crewLuck(vault, room, now)
		bolts = math.ceil(amount * 0.3 * (1 + luck * 0.06))
		if vault.rt.rng:NextNumber() < luck * 0.02 then
			bolts *= 2
		end
		res.Bolts += bolts
		for _, id in room.assigned do
			local d = vault.data.dwellers[id]
			if d then
				S.DwellerService.grantXp(vault, d, 2)
			end
		end
		vault.data.progression.stats.collected += gained
	end
	S.VaultService.send(vault, "collected", {
		roomId = room.id, resource = resKey, amount = gained, bolts = bolts, tapped = tapped,
		full = gained < amount,
	})
	S.DwellerService.pushRoom(vault, room)
	S.VaultService.dirty(vault)
	return gained, bolts
end

-- Share of power demand the grid can meet right now (1 while the batteries hold charge).
local function powerFactorOf(vault, now: number, demand: number): number
	local res = vault.data.resources
	if res.Power > 0.5 or demand <= 0 then
		return 1
	end
	local supply = 0
	for _, room in vault.data.rooms do
		if RoomDefinitions.Types[room.type].produces == "Power" then
			supply += Simulation.roomRate(room, vault.data.dwellers, now, 1)
		end
	end
	return math.clamp(supply / demand, 0, 1)
end

-- Produce into a room's batch, drawing its inputs (production chains). Returns the rate achieved.
local function produce(vault, room, def, rate: number, dt: number, flow): number
	local res = vault.data.resources
	if def.inputs and rate > 0 then
		local scale = 1
		for key, perUnit in def.inputs do
			local need = rate * dt / 60 * perUnit
			if need > 0 then
				scale = math.min(scale, (res[key] or 0) / need)
			end
		end
		scale = math.clamp(scale, 0, 1)
		rate *= scale
		for key, perUnit in def.inputs do
			local used = rate * dt / 60 * perUnit
			res[key] = math.max(0, (res[key] or 0) - used)
			if flow[key] then
				flow[key].use += rate * perUnit
			end
		end
		room.starved = scale < 0.99 or nil -- shown in the room panel ("No water")
	end
	return rate
end

function ResourceService.tick(vault, dt: number)
	local data = vault.data
	local now = S.VaultService.now()
	local res = data.resources
	data.playSeconds = (data.playSeconds or 0) + dt
	local pressure = S.VaultService.pressure(vault)
	local flow = emptyFlow()
	local demand = Simulation.powerUse(data.rooms) * Difficulty.powerUse(pressure)
	local pf = powerFactorOf(vault, now, demand)
	vault.rt.powerFactor = pf
	for _, room in data.rooms do
		local def = RoomDefinitions.Types[room.type]
		if def.produces then
			local r = Simulation.roomRate(room, data.dwellers, now, pf)
			if not room.readySince then
				r = produce(vault, room, def, r, dt, flow)
				if r > 0 then
					room.pending += r * dt / 60
					if room.pending >= batchSize(room) then
						room.readySince = now
						S.DwellerService.pushRoom(vault, room)
					end
				end
			end
			if flow[def.produces] then
				flow[def.produces].prod += r
			end
			if room.readySince and now - room.readySince >= Simulation.AUTO_COLLECT then
				deposit(vault, room, false, now)
			end
		end
		if (room.rushStack or 0) > 0 and now - (room.lastRush or 0) > 120 then
			room.rushStack -= 1
			room.lastRush = now
		end
	end
	-- the grid draws continuously; meals and drinks are taken by survivors (LifeService)
	local caps = Simulation.storageCaps(data.rooms)
	res.Power = math.clamp(res.Power - demand * dt / 60, 0, caps.Power)
	local foodUse, waterUse = Simulation.expectedUse(data.dwellers, Difficulty.consumption(pressure))
	flow.Power.use += demand
	flow.Food.use += foodUse
	flow.Water.use += waterUse
	local patients = 0
	for _, d in data.dwellers do
		if d.activity == "Treatment" then
			patients += 1
		end
	end
	flow.MedPatch.use += patients * 1.5
	local rates = {}
	for key, f in flow do
		rates[key] = f.prod - f.use
	end
	vault.rt.rates = rates
	vault.rt.flow = flow
	S.DwellerService.tick(vault, dt, now)
	for key, cap in caps do
		if res[key] and res[key] > cap then
			res[key] = cap
		end
	end
	ResourceService.pushResources(vault)
	vault.rt.statAcc = (vault.rt.statAcc or 0) + dt
	if vault.rt.statAcc >= 3 then
		vault.rt.statAcc = 0
		local compact = {}
		for id, d in data.dwellers do
			local n = d.needs or {}
			compact[id] = {
				math.floor(d.health * 10) / 10, math.floor(d.happiness * 10) / 10, math.floor(d.xp), d.level,
				if d.deadFor then math.floor(d.deadFor) else nil,
				math.floor(n.Hunger or 100), math.floor(n.Thirst or 100), math.floor(n.Energy or 100),
			}
		end
		S.VaultService.send(vault, "dstats", compact)
	end
end

function ResourceService.prime(vault)
	vault.rt.rushReady = {}
end

-- Offline catch-up in coarse steps: production (with chains and the power grid) deposits directly,
-- survivors' meals and drinks are taken statistically. No incidents; nobody dies (shortages still
-- hurt health and happiness, down to a floor).
function ResourceService.offline(vault, seconds: number)
	local data = vault.data
	local res = data.resources
	local start = { Power = res.Power, Food = res.Food, Water = res.Water, Materials = res.Materials or 0 }
	local steps = math.ceil(seconds / Config.OFFLINE_STEP)
	local dt = seconds / steps
	local produced = { Power = 0, Food = 0, Water = 0, Materials = 0, MedPatch = 0 }
	local pressure = S.VaultService.pressure(vault)
	for _ = 1, steps do
		local caps = Simulation.storageCaps(data.rooms)
		local demand = Simulation.powerUse(data.rooms) * Difficulty.powerUse(pressure)
		local supply = 0
		-- crews keep working while you're away, minus meal and sleep breaks
		local function offlineRate(room, def): number
			local perSlot = def.rate[room.level] / def.slots
			local total = 0
			for _, id in room.assigned do
				local d = data.dwellers[id]
				if d and d.status == "Working" then
					total += perSlot * Simulation.workerOutput(d, def.stat) * 0.8
				end
			end
			return total * (Simulation.MERGE_BONUS[room.modules] or 1)
		end
		for _, room in data.rooms do
			local def = RoomDefinitions.Types[room.type]
			if def.produces == "Power" and not room.incident then
				supply += offlineRate(room, def)
			end
		end
		local pf = if res.Power > 0.5 then 1 else math.clamp(supply / math.max(0.01, demand), 0, 1)
		for _, room in data.rooms do
			local def = RoomDefinitions.Types[room.type]
			if def.produces and def.rate and res[def.produces] ~= nil and not room.incident then
				local r = offlineRate(room, def) * (if def.produces == "Power" then 1 else pf)
				r = produce(vault, room, def, r, dt, emptyFlow())
				local amt = r * dt / 60
				produced[def.produces] = (produced[def.produces] or 0) + amt
				res[def.produces] = math.min(caps[def.produces] or math.huge, res[def.produces] + amt)
			end
		end
		local foodUse, waterUse = Simulation.expectedUse(data.dwellers, Difficulty.consumption(pressure))
		res.Food = math.max(0, res.Food - foodUse * dt / 60)
		res.Water = math.max(0, res.Water - waterUse * dt / 60)
		res.Power = math.max(0, res.Power - demand * dt / 60)
		for _, d in data.dwellers do
			if d.status == "Working" then
				S.DwellerService.grantXp(vault, d, Simulation.xpRate(d) * dt / 60 * 0.5)
			end
			if (res.Food <= 0 or res.Water <= 0) and Simulation.isInside(d) then
				d.health = math.max(d.maxHealth * 0.15, d.health - dt * 0.08)
				d.happiness = math.max(5, d.happiness - dt * 0.08)
			end
		end
	end
	for _, room in data.rooms do
		room.pending = 0
	end
	return {
		seconds = seconds,
		delta = {
			Power = math.floor(res.Power - start.Power),
			Food = math.floor(res.Food - start.Food),
			Water = math.floor(res.Water - start.Water),
			Materials = math.floor((res.Materials or 0) - start.Materials),
		},
		produced = {
			Power = math.floor(produced.Power), Food = math.floor(produced.Food), Water = math.floor(produced.Water),
			Materials = math.floor(produced.Materials),
		},
	}
end

function ResourceService.Init(services)
	S = services
	S.NetService.handle("Collect", function(player, p)
		local vault = S.VaultService.get(player)
		if not vault then
			return false, "Not ready"
		end
		local room = vault.data.rooms[tostring(p.roomId)]
		if not room or not room.readySince then
			return false, "Nothing to collect"
		end
		local now = S.VaultService.now()
		local def = RoomDefinitions.Types[room.type]
		local total, bolts = deposit(vault, room, true, now)
		-- Collecting one batch sweeps every ready room of the same resource (one tap, many pops).
		for _, other in vault.data.rooms do
			if other ~= room and other.readySince and RoomDefinitions.Types[other.type].produces == def.produces then
				local g, b = deposit(vault, other, true, now)
				total += g
				bolts += b
			end
		end
		ResourceService.pushResources(vault)
		return true, { amount = total, bolts = bolts, resource = def.produces }
	end)
	S.NetService.handle("Rush", function(player, p)
		local vault = S.VaultService.get(player)
		if not vault then
			return false, "Not ready"
		end
		local room = vault.data.rooms[tostring(p.roomId)]
		if not room then
			return false, "Invalid room"
		end
		local def = RoomDefinitions.Types[room.type]
		if not def.produces then
			return false, "Only production rooms can be rushed"
		end
		if room.incident then
			return false, "Deal with the emergency first!"
		end
		local now = S.VaultService.now()
		if (vault.rt.rushReady[room.id] or 0) > now then
			return false, "Crew is still recovering"
		end
		local luck, crew = crewLuck(vault, room, now)
		if crew == 0 then
			return false, "Nobody is at work in there right now"
		end
		local fail = Simulation.rushFailChance(room, luck)
		vault.rt.rushReady[room.id] = now + Config.RUSH_COOLDOWN
		room.rushStack = (room.rushStack or 0) + 1
		room.lastRush = now
		if vault.rt.rng:NextNumber() < fail then
			S.IncidentService.startIncident(vault, room, "rush")
			return true, { success = false, chance = fail }
		end
		local rate = Simulation.roomRate(room, vault.data.dwellers, now, vault.rt.powerFactor or 1)
		room.pending = math.max(room.pending + rate * Config.RUSH_MINUTES, batchSize(room))
		room.readySince = now
		for _, id in room.assigned do
			local d = vault.data.dwellers[id]
			if d then
				S.DwellerService.grantXp(vault, d, 8)
			end
		end
		S.DwellerService.pushRoom(vault, room)
		S.VaultService.dirty(vault)
		return true, { success = true, chance = fail }
	end)
end

function ResourceService.Start()
	local last = os.clock()
	while true do
		task.wait(Config.SIM_TICK)
		local now = os.clock()
		local dt = math.min(5, now - last)
		last = now
		for _, vault in S.VaultService.all() do
			if vault.loaded then
				local ok, err = pcall(ResourceService.tick, vault, dt)
				if not ok then
					warn("[ResourceService] tick failed:", err)
				end
			end
		end
	end
end

return ResourceService
