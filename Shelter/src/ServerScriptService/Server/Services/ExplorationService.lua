--!strict
-- Wasteland exploration: server-authoritative, timestamp driven, deterministic per event index
-- (seed + index), so offline time replays the same journey. Survivors find loot, fight, heal
-- with carried MedPatches, may recruit other survivors, and walk home when recalled.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Grid = require(ReplicatedStorage.Shared.Grid)
local Pathing = require(ReplicatedStorage.Shared.Pathing)
local Simulation = require(ReplicatedStorage.Shared.Simulation)
local ItemDefinitions = require(ReplicatedStorage.Shared.ItemDefinitions)
local Exploration = require(ReplicatedStorage.Shared.Exploration)
local Family = require(ReplicatedStorage.Shared.Family)

local ExplorationService = {}
local S: any

local MAX_EVENTS = 160
local MAX_LOG = 60
local MAX_ITEMS = 18

local function push(vault, id: string)
	S.VaultService.send(vault, "explore", { id = id, rec = vault.data.exploration[id] })
end

local function addLog(rec, entry)
	table.insert(rec.log, entry)
	while #rec.log > MAX_LOG do
		table.remove(rec.log, 1)
	end
end

local function itemCount(rec): number
	return #rec.loot.items
end

local function weapon(d)
	return ItemDefinitions.Weapons[d.weapon or "Fists"] or ItemDefinitions.Weapons.Fists
end

local function addRes(rec, key: string, n: number)
	rec.loot[key] = (rec.loot[key] or 0) + n
end

local function beginReturn(vault, d, rec, now: number, reason: string?)
	if rec.returning or rec.dead then
		return
	end
	rec.returning = true
	rec.returnStart = now
	rec.returnDur = math.clamp((now - rec.start) * Exploration.RETURN_FRACTION, Exploration.RETURN_MIN, Exploration.RETURN_MAX)
	addLog(rec, { t = now, k = "Return", text = reason or (d.name .. " turned back towards Underhaven.") })
end

-- Resolve one event deterministically.
local function resolve(vault, d, rec, t: number)
	local idx = rec.events
	local rng = Random.new(rec.seed + idx * 7919)
	local elapsed = t - rec.start
	local tier = math.min(10, math.floor(elapsed / Exploration.TIER_SECONDS))
	local kind = Exploration.pickEvent(rng, tier)
	local def = Exploration.Events[kind]
	local place = Exploration.Places[rng:NextInteger(1, #Exploration.Places)]
	local luck = Simulation.stat(d, "SCV")
	local per = Simulation.stat(d, "SCV")
	local cha = Simulation.stat(d, "SOC")
	local int = Simulation.stat(d, "MED")
	local endu = Simulation.stat(d, "FIT")
	local str = Simulation.stat(d, "CMB")
	local w = weapon(d)
	local tierMult = 1 + tier * 0.28
	local entry = { t = t, k = kind, text = "", loot = {} :: { [string]: any }, dmg = 0, xp = 0, place = place }
	local function bolts(lo: number, hi: number)
		local n = math.floor(rng:NextInteger(lo, hi) * tierMult * (1 + per * 0.04))
		addRes(rec, "Bolts", n)
		entry.loot.Bolts = (entry.loot.Bolts or 0) + n
	end
	local function item(chance: number, kindPref: string?, bonus: number?)
		if itemCount(rec) >= MAX_ITEMS then
			return
		end
		if rng:NextNumber() < chance + luck * 0.012 then
			local rarity = ItemDefinitions.rollRarity(rng, luck + tier + (bonus or 0))
			local k = kindPref or (if rng:NextNumber() < 0.55 then "Weapon" else "Outfit")
			local id = ItemDefinitions.randomOf(k, rarity, rng) or ItemDefinitions.randomOf(k, "Common", rng)
			if id then
				table.insert(rec.loot.items, id)
				entry.loot.item = id
			end
		end
	end
	local function hurt(base: number, mitigation: number)
		local dmg = base * (1 + tier * 0.35) * math.clamp(1 - mitigation, 0.25, 1)
		entry.dmg = math.floor(dmg * 10) / 10
		d.health = math.max(0, d.health - dmg)
	end
	local fight = math.min(0.55, w.damage / 28) + endu * 0.035 + str * 0.01
	if kind == "Quiet" then
		entry.text = string.format(def.text[rng:NextInteger(1, #def.text)], d.name, place)
		entry.xp = 4
	elseif kind == "SupplyCache" then
		bolts(8, 24)
		if rng:NextNumber() < 0.45 then
			local r = if rng:NextNumber() < 0.5 then "Food" else "Water"
			local n = rng:NextInteger(5, 14)
			addRes(rec, r, n)
			entry.loot[r] = n
		end
		entry.xp = 8
	elseif kind == "AbandonedHouse" then
		bolts(5, 16)
		local sc = rng:NextInteger(1, 4)
		addRes(rec, "Scrap", sc)
		entry.loot.Scrap = sc
		item(0.18 + tier * 0.02)
		entry.xp = 10
	elseif kind == "RuinedLab" then
		if rng:NextNumber() < 0.55 then
			addRes(rec, "MedPatch", 1)
			entry.loot.MedPatch = 1
		end
		item(0.12, nil, 1)
		hurt(4, int * 0.07)
		entry.xp = 14
	elseif kind == "Checkpoint" then
		hurt(6, fight)
		bolts(10, 28)
		item(0.32, "Weapon")
		entry.xp = 18
	elseif kind == "Bunker" then
		bolts(30, 70)
		item(0.5, nil, 2)
		hurt(3, per * 0.05)
		entry.xp = 22
	elseif kind == "RaiderCamp" then
		hurt(8, fight)
		bolts(15, 45)
		item(0.28, "Weapon")
		entry.xp = 26 + tier * 4
	elseif kind == "Mutant" then
		hurt(5, fight)
		local meat = rng:NextInteger(3, 9)
		addRes(rec, "Food", meat)
		entry.loot.Food = meat
		entry.xp = 18 + tier * 3
		entry.creature = if rng:NextNumber() < 0.6 then "CRT_BURROWRAT" else "CRT_RUSTROACH"
	elseif kind == "Survivor" then
		if rng:NextNumber() < 0.22 + cha * 0.05 then
			rec.recruits = (rec.recruits or 0) + 1
			entry.loot.recruit = 1
			entry.recruited = true
		else
			bolts(4, 12)
		end
		entry.xp = 12
	elseif kind == "Trader" then
		if (rec.loot.Bolts or 0) >= 30 and itemCount(rec) < MAX_ITEMS then
			rec.loot.Bolts -= 30
			local rarity = ItemDefinitions.rollRarity(rng, luck + cha)
			local id = ItemDefinitions.randomOf(if rng:NextNumber() < 0.5 then "Weapon" else "Outfit", rarity, rng)
			if id then
				table.insert(rec.loot.items, id)
				entry.loot.item = id
				entry.loot.Bolts = -30
			end
		else
			local n = rng:NextInteger(4, 10) + cha
			addRes(rec, "Water", n)
			entry.loot.Water = n
		end
		entry.xp = 10
	end
	if kind ~= "Quiet" then
		local lines = def.text
		entry.text = string.format(lines[rng:NextInteger(1, #lines)], d.name, place)
	end
	entry.xp = math.floor(entry.xp * tierMult)
	S.DwellerService.grantXp(vault, d, entry.xp)
	addLog(rec, entry)
	-- Aftermath: heal, die, or head home
	if d.health > 0 and d.health < d.maxHealth * 0.35 and (rec.medpatches or 0) > 0 then
		rec.medpatches -= 1
		d.health = math.min(d.maxHealth, d.health + d.maxHealth * 0.45)
		addLog(rec, { t = t, k = "Heal", text = d.name .. " patched up with a MedPatch." })
	end
	if d.health <= 0 then
		rec.dead = true
		addLog(rec, { t = t, k = "Death", text = d.name .. " did not survive " .. place .. "." })
		-- the same death as anywhere else: revive timer, grief, shelter mood
		S.DwellerService.kill(vault, d, "the wasteland", d.name .. " has died in the wasteland. Revive them within "
			.. math.floor(Config.REVIVE_WINDOW / 60) .. " minutes to bring them home.")
	elseif d.health < d.maxHealth * 0.2 and (rec.medpatches or 0) == 0 then
		beginReturn(vault, d, rec, t, d.name .. " is badly hurt and limping home.")
	elseif itemCount(rec) >= MAX_ITEMS then
		beginReturn(vault, d, rec, t, d.name .. "'s pack is full - heading home.")
	end
end

local function arrive(vault, d, rec, now: number)
	local data = vault.data
	local caps = Simulation.storageCaps(data.rooms)
	local res = data.resources
	local summary = { Bolts = math.max(0, math.floor(rec.loot.Bolts or 0)), items = rec.loot.items, recruits = rec.recruits or 0 }
	res.Bolts += summary.Bolts
	for _, key in { "Food", "Water", "MedPatch", "Scrap" } do
		local n = math.floor(rec.loot[key] or 0)
		if n > 0 then
			-- salvaged scrap goes straight into building materials
			local into = if key == "Scrap" then "Materials" else key
			res[into] = math.min(caps[into] or math.huge, (res[into] or 0) + n)
			summary[into] = n
		end
	end
	res.MedPatch = (res.MedPatch or 0) + (rec.medpatches or 0)
	for _, defId in rec.loot.items do
		S.InventoryService.grant(vault, defId)
	end
	local entrance
	for _, r in data.rooms do
		if r.type == "Entrance" then
			entrance = r
		end
	end
	data.exploration[d.id] = nil
	d.status = "Idle"
	S.LifeService.expedition(vault, d, now, true)
	if entrance then
		d.roomId = entrance.id
		d.at = entrance.id
		d.activity = "Relaxing"
		d.activityEnd = now + 10
		S.LifeService.wake(vault, d, now)
		local x1 = Grid.roomCenterX(entrance)
		local pts = { { x = x1, row = entrance.row, mode = "walk" } }
		local x0 = entrance.col * Config.UNIT + 2
		d.travel = { x0 = x0, row0 = entrance.row, points = pts, start = now, duration = Pathing.duration(pts, x0, entrance.row) }
		d.arriveAt = now + d.travel.duration
	end
	-- recruits follow the explorer home (housing permitting)
	local housing = Simulation.housing(data.rooms)
	local found, joined = summary.recruits, 0
	for _ = 1, found do
		if Simulation.population(data.dwellers) < housing and entrance then
			local nd = S.DwellerService.create(vault, { level = vault.rt.rng:NextInteger(2, 5) })
			nd.roomId = entrance.id
			nd.at = entrance.id
			nd.status = "Idle"
			S.LifeService.wake(vault, nd, now)
			S.DwellerService.push(vault, nd)
			joined += 1
		end
	end
	summary.recruits = joined
	if joined < found then
		S.VaultService.toast(vault, (found - joined) .. " survivor" .. (if found - joined == 1 then "" else "s")
			.. " " .. d.name .. " met had to move on - no room inside. Build more Bedrooms.", "warn")
	end
	data.progression.stats.explorations = (data.progression.stats.explorations or 0) + 1
	S.DwellerService.push(vault, d)
	S.VaultService.send(vault, "inventory", data.inventory)
	S.VaultService.send(vault, "exploreEnd", { id = d.id, summary = summary, seconds = now - rec.start, events = rec.events })
	S.VaultService.toast(vault, d.name .. " is back from the wasteland!", "good")
	S.ResourceService.pushResources(vault)
	S.VaultService.dirty(vault)
end

function ExplorationService.tick(vault, now: number)
	local data = vault.data
	for id, rec in data.exploration do
		local d = data.dwellers[id]
		if not d then
			data.exploration[id] = nil
			continue
		end
		local changed = false
		if not rec.returning and not rec.dead then
			local budget = 200
			while now >= rec.nextEventAt and rec.events < MAX_EVENTS and budget > 0 and not rec.returning and not rec.dead do
				budget -= 1
				resolve(vault, d, rec, rec.nextEventAt)
				rec.events += 1
				local rng = Random.new(rec.seed + rec.events * 104729)
				rec.nextEventAt += rng:NextNumber(Exploration.EVENT_GAP[1], Exploration.EVENT_GAP[2])
				changed = true
			end
		end
		if rec.returning and now >= rec.returnStart + rec.returnDur then
			arrive(vault, d, rec, now)
		elseif changed then
			push(vault, id)
			S.DwellerService.push(vault, d)
			S.VaultService.dirty(vault)
		end
	end
end

function ExplorationService.Init(services)
	S = services
	S.NetService.handle("Explore", function(player, p)
		local vault = S.VaultService.get(player)
		if not vault then
			return false, "Not ready"
		end
		local d = vault.data.dwellers[tostring(p.dwellerId)]
		-- only survivors inside the shelter (wanderers at the door haven't been let in yet)
		if not d or not Simulation.isInside(d) then
			return false, "Survivor unavailable"
		end
		local allowed, why = Family.canExplore(d)
		if not allowed then
			return false, why
		end
		if d.health < d.maxHealth * 0.5 then
			return false, d.name .. " needs to heal first"
		end
		local count = 0
		for _ in vault.data.exploration do
			count += 1
		end
		if count >= Exploration.MAX_EXPLORERS then
			return false, "Only " .. Exploration.MAX_EXPLORERS .. " explorers at a time"
		end
		local want = tonumber(p.medpatches) or 0
		if want ~= want then
			want = 0 -- tonumber("nan") is NaN, and math.clamp passes NaN straight through
		end
		local meds = math.clamp(math.floor(want), 0, math.min(Exploration.MAX_MEDS, vault.data.resources.MedPatch or 0))
		vault.data.resources.MedPatch -= meds
		local now = S.VaultService.now()
		local room = d.roomId and vault.data.rooms[d.roomId]
		if room then
			local i = table.find(room.assigned, d.id)
			if i then
				table.remove(room.assigned, i)
				S.DwellerService.pushRoom(vault, room)
			end
		end
		d.status = "Exploring"
		d.travel = nil
		d.roomId = nil
		d.respond = nil
		S.LifeService.expedition(vault, d, now, false)
		vault.data.exploration[d.id] = {
			start = now,
			seed = vault.rt.rng:NextInteger(1, 2 ^ 30),
			nextEventAt = now + Exploration.FIRST_EVENT,
			events = 0,
			log = { { t = now, k = "Depart", text = d.name .. " stepped out of the blast door into the wasteland." } },
			loot = { Bolts = 0, items = {} },
			medpatches = meds,
			returning = false,
			dead = false,
		}
		S.DwellerService.push(vault, d)
		push(vault, d.id)
		S.ResourceService.pushResources(vault)
		S.VaultService.dirty(vault)
		return true
	end)
	S.NetService.handle("Recall", function(player, p)
		local vault = S.VaultService.get(player)
		if not vault then
			return false, "Not ready"
		end
		local d = vault.data.dwellers[tostring(p.dwellerId)]
		local rec = d and vault.data.exploration[d.id]
		if not rec then
			return false, "Not exploring"
		end
		if rec.dead then
			return false, "Revive " .. d.name .. " first"
		end
		if rec.returning then
			return false, "Already on the way home"
		end
		beginReturn(vault, d, rec, S.VaultService.now(), nil)
		push(vault, d.id)
		S.VaultService.dirty(vault)
		return true, { returnDur = rec.returnDur }
	end)
end

-- Called by DwellerService when a dead explorer is revived.
function ExplorationService.revived(vault, d)
	local rec = vault.data.exploration[d.id]
	if rec then
		rec.dead = false
		d.status = "Exploring"
		beginReturn(vault, d, rec, S.VaultService.now(), d.name .. " was revived and is heading home.")
		push(vault, d.id)
	end
end

function ExplorationService.fastForward(vault, seconds: number)
	for _, rec in vault.data.exploration do
		rec.start -= seconds
		rec.nextEventAt -= seconds
		if rec.returning then
			rec.returnStart -= seconds
		end
	end
end

function ExplorationService.Start()
	while true do
		task.wait(1)
		for _, vault in S.VaultService.all() do
			if vault.loaded then
				local ok, err = pcall(ExplorationService.tick, vault, S.VaultService.now())
				if not ok then
					warn("[ExplorationService]", err)
				end
			end
		end
	end
end

return ExplorationService
