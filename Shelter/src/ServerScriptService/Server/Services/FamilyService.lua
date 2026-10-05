--!strict
-- Families. A woman and a man relaxing in the same Living Quarters may hit it off: they chat and
-- dance for a while (Family.courtDuration), then she is expecting. The baby is born after
-- Config.PREGNANCY_TIME and grows into a working adult after Config.CHILD_GROW_TIME.
-- Relatives never pair up, and no romance starts while the shelter has no room for a baby.
-- Every timer is an absolute server timestamp, so it survives saves and offline time.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Simulation = require(ReplicatedStorage.Shared.Simulation)
local DwellerDefinitions = require(ReplicatedStorage.Shared.DwellerDefinitions)
local Family = require(ReplicatedStorage.Shared.Family)

local FamilyService = {}
local S: any

local function firstName(name: string): string
	return string.match(name, "^(%S+)") or name
end

local function lastName(name: string): string?
	local first, last = string.match(name, "^(%S+)%s+.-(%S+)$")
	return if first then last else nil
end

-- Awake and unwinding in this bedroom (after sleep, or off duty).
local function eligible(d: any, room: any, now: number): boolean
	return Simulation.isInside(d) and (d.at or d.roomId) == room.id and d.activity == "Relaxing"
		and not d.child and not d.court and not d.pregnant
		and (d.arriveAt or 0) <= now and (d.restUntil or 0) <= now
end

local function pendingBirths(vault): number
	local n = 0
	for _, d in vault.data.dwellers do
		if d.pregnant then
			n += 1
		end
	end
	return n
end

local function push(vault, ...)
	for _, d in { ... } do
		S.DwellerService.push(vault, d)
	end
	S.VaultService.dirty(vault)
end

function FamilyService.cancel(vault, d: any)
	local c = d.court
	if not c then
		return
	end
	d.court = nil
	local p = vault.data.dwellers[c.with]
	if p and p.court and p.court.with == d.id then
		p.court = nil
		push(vault, p)
	end
	push(vault, d)
end

local function startCourt(vault, f: any, m: any, now: number)
	local dur = Family.courtDuration(f, m)
	f.court = { with = m.id, start = now, done = now + dur }
	m.court = { with = f.id, start = now, done = now + dur }
	push(vault, f, m)
	S.VaultService.send(vault, "family", { kind = "court", a = f.id, b = m.id })
end

local function conceive(vault, f: any, m: any, now: number)
	f.court, m.court = nil, nil
	f.pregnant = { father = m.id, since = now, due = now + Config.PREGNANCY_TIME }
	f.partner, m.partner = m.id, f.id
	m.restUntil = now + Config.FAMILY_COOLDOWN
	f.happiness = math.min(100, f.happiness + 15)
	m.happiness = math.min(100, m.happiness + 15)
	push(vault, f, m)
	S.VaultService.send(vault, "family", { kind = "expecting", a = f.id, b = m.id })
	S.VaultService.toast(vault, firstName(f.name) .. " and " .. firstName(m.name) .. " are expecting a baby!", "good")
end

local function pick(rng: Random, a: any, b: any): any
	if a == nil then
		return b
	elseif b == nil then
		return a
	end
	return if rng:NextNumber() < 0.5 then a else b
end

local function birth(vault, mother: any, now: number)
	local rng: Random = vault.rt.rng
	local dwellers = vault.data.dwellers
	local father = dwellers[mother.pregnant.father]
	local gender = if rng:NextNumber() < 0.5 then "F" else "M"
	local child = S.DwellerService.create(vault, { gender = gender, level = 1, archetype = "Worker" })
	local surname = (father and lastName(father.name)) or lastName(mother.name)
	child.name = firstName(DwellerDefinitions.randomName(rng, gender)) .. " " .. (surname or "Underhaven")
	child.child = true
	child.age = 0
	child.growAt = now + Config.CHILD_GROW_TIME
	child.parents = { mother.id }
	if father then
		table.insert(child.parents, father.id)
	end
	child.trait = nil
	child.traits = DwellerDefinitions.randomTraits(rng)
	child.happiness = 85
	-- aptitudes lean towards the parents'
	for _, s in DwellerDefinitions.STATS do
		local a = mother.stats[s] or 1
		local b = if father then (father.stats[s] or 1) else a
		child.stats[s] = math.clamp(math.floor((a + b) / 2 + rng:NextNumber(-1, 1) + 0.5), 1, 6)
	end
	child.maxHealth = DwellerDefinitions.maxHealthFor(1, child.stats.FIT, child.traits)
	child.health = child.maxHealth
	-- looks come from the parents
	local ma, fa = mother.appearance or {}, (father and father.appearance) or {}
	local ap = child.appearance
	ap.skin = pick(rng, ma.skin, fa.skin) or ap.skin
	ap.hairColor = pick(rng, ma.hairColor, fa.hairColor) or ap.hairColor
	ap.eyeColor = pick(rng, ma.eyeColor, fa.eyeColor) or ap.eyeColor
	ap.beard = false
	ap.body = "standard"
	ap.archetype = nil
	-- born where the mother is, then heads to the nearest Living Quarters
	child.roomId = mother.roomId
	child.at = mother.at or mother.roomId
	child.activity = "Relaxing"
	S.LifeService.wake(vault, child, now)
	child.status = "Idle"
	child.arriveAt = 0
	mother.pregnant = nil
	mother.restUntil = now + Config.FAMILY_COOLDOWN
	local stats = vault.data.progression.stats
	stats.births = (stats.births or 0) + 1
	local here = mother.roomId and vault.data.rooms[mother.roomId]
	local home = if here and here.type == "Living" then here else nil
	if not home then
		for _, r in vault.data.rooms do
			if r.type == "Living" then
				home = r
				break
			end
		end
	end
	push(vault, mother, child)
	if home and home ~= here then
		S.DwellerService.moveTo(vault, child, home, now)
	end
	S.VaultService.send(vault, "family", { kind = "born", a = mother.id, b = child.id })
	S.VaultService.toast(vault, firstName(mother.name) .. " had a baby: welcome, " .. firstName(child.name) .. "!", "good")
end

local function growUp(vault, d: any, now: number)
	local rng: Random = vault.rt.rng
	d.child = nil
	d.growAt = nil
	d.age = 18
	local arch = DwellerDefinitions.ArchetypeOrder[rng:NextInteger(1, #DwellerDefinitions.ArchetypeOrder - 1)]
	d.archetype = arch
	d.appearance.archetype = arch
	local def = DwellerDefinitions.Archetypes[arch]
	for s, b in def.bias do
		d.stats[s] = math.min(DwellerDefinitions.MAX_STAT, d.stats[s] + b)
	end
	if d.gender == "M" and rng:NextNumber() < 0.3 then
		d.appearance.beard = true
	end
	d.maxHealth = DwellerDefinitions.maxHealthFor(d.level, d.stats.FIT, DwellerDefinitions.traitsOf(d))
	d.health = d.maxHealth
	d.restUntil = now + Config.FAMILY_COOLDOWN
	push(vault, d)
	S.VaultService.send(vault, "family", { kind = "grown", a = d.id })
	S.VaultService.toast(vault, firstName(d.name) .. " grew up and wants to work as a " .. def.name .. "!", "good")
end

-- Called every economy tick from DwellerService.tick.
function FamilyService.tick(vault, dt: number, now: number)
	local dwellers = vault.data.dwellers
	local deliveries = {} -- births add dwellers, so they run after this traversal
	for _, d in dwellers do
		local preg = d.pregnant
		if preg and now >= preg.due then
			if d.status == "Idle" or d.status == "Working" then
				table.insert(deliveries, d)
			else
				preg.due = now + 30 -- deliver once she is safely back inside
			end
		end
		if d.child and d.growAt and now >= d.growAt and d.status ~= "Dead" then
			growUp(vault, d, now)
		end
		local c = d.court
		if c then
			local p = dwellers[c.with]
			local room = (d.at or d.roomId) and vault.data.rooms[d.at or d.roomId]
			local here = d.at or d.roomId
			if not p or not p.court or p.court.with ~= d.id or not Simulation.isInside(d) or not Simulation.isInside(p)
				or here ~= (p.at or p.roomId) or not room or room.incident then
				FamilyService.cancel(vault, d)
			elseif now >= c.done and d.gender == "F" then
				conceive(vault, d, p, now)
			end
		end
	end
	for _, mother in deliveries do
		birth(vault, mother, now)
	end
	-- new romances: at most one per Living Quarters per tick, only if a baby would have a bunk
	local alive = Simulation.population(dwellers)
	if alive + pendingBirths(vault) >= Simulation.housing(vault.data.rooms) then
		return
	end
	local rng: Random = vault.rt.rng
	for _, room in vault.data.rooms do
		if room.type ~= "Living" or room.incident then
			continue
		end
		local fs, ms = {}, {}
		for _, d in dwellers do
			if eligible(d, room, now) then
				table.insert(if d.gender == "F" then fs else ms, d)
			end
		end
		if #fs == 0 or #ms == 0 then
			continue
		end
		local f = fs[rng:NextInteger(1, #fs)]
		local options = {}
		for _, m in ms do
			if not Family.related(f, m) then
				table.insert(options, m)
			end
		end
		if #options > 0 then
			local m = options[rng:NextInteger(1, #options)]
			local cha = (Simulation.stat(f, "SOC") + Simulation.stat(m, "SOC")) / 2
			-- couples and close friends are far likelier to get romantic
			local aff = (f.rel and f.rel[m.id]) or 0
			local bond = if f.partner == m.id then 3 elseif aff >= 40 then 1.5 elseif aff < 15 then 0.3 else 1
			local perSecond = Config.COURT_RATE * (0.6 + cha * 0.08) * bond / 60
			if rng:NextNumber() < 1 - math.exp(-perSecond * dt) then
				startCourt(vault, f, m, now)
			end
		end
	end
end

-- Studio debug helpers (IncidentService "Debug" action).
function FamilyService.debug(vault, kind: string): (boolean, string?)
	local now = S.VaultService.now()
	if kind == "Romance" then
		for _, room in vault.data.rooms do
			if room.type == "Living" then
				local fs, ms = {}, {}
				for _, d in vault.data.dwellers do
					if eligible(d, room, now) then
						table.insert(if d.gender == "F" then fs else ms, d)
					end
				end
				for _, f in fs do
					for _, m in ms do
						if not Family.related(f, m) then
							startCourt(vault, f, m, now)
							return true, nil
						end
					end
				end
			end
		end
		return false, "Put an unrelated woman and man in Living Quarters first"
	elseif kind == "FamilyFF" then
		for _, d in vault.data.dwellers do
			if d.court then
				d.court.done -= 300
			end
			if d.pregnant then
				d.pregnant.due -= 300
			end
			if d.growAt then
				d.growAt -= 300
			end
			if d.restUntil then
				d.restUntil -= 300
			end
		end
		return true, nil
	end
	return false, "Unknown"
end

function FamilyService.Init(services)
	S = services
end

return FamilyService
