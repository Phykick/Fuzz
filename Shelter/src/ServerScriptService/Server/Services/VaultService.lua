--!strict
-- Per-player shelter lifecycle: load/create, migrate, offline catch-up, snapshot, autosave.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Simulation = require(ReplicatedStorage.Shared.Simulation)
local Difficulty = require(ReplicatedStorage.Shared.Difficulty)

local VaultService = {}
local S: any

export type Vault = {
	player: Player,
	userId: number,
	data: any,
	rt: any,
	loaded: boolean,
}

local vaults: { [Player]: Vault } = {}

function VaultService.now(): number
	return workspace:GetServerTimeNow()
end

function VaultService.get(player: Player): Vault?
	local v = vaults[player]
	return if v and v.loaded then v else nil
end

function VaultService.all(): { [Player]: Vault }
	return vaults
end

function VaultService.send(vault: Vault, kind: string, payload: any)
	S.NetService.send(vault.player, kind, payload)
end

function VaultService.toast(vault: Vault, text: string, tone: string?)
	VaultService.send(vault, "toast", { text = text, tone = tone or "info" })
end

function VaultService.newId(vault: Vault, kind: string): string
	local c = vault.data.counters
	c[kind] = (c[kind] or 0) + 1
	return tostring(c[kind])
end

function VaultService.dirty(vault: Vault)
	vault.rt.dirty = true
end

-- Template --------------------------------------------------------------------
local function template()
	return {
		schema = Config.SCHEMA_VERSION,
		createdAt = os.time(),
		lastSimTime = os.time(),
		playSeconds = 0, -- time actually played; drives the pressure curve
		shelterNo = 0,
		resources = table.clone(Config.START_RESOURCES),
		rooms = {},
		dwellers = {},
		inventory = {},
		counters = { room = 0, dweller = 0, item = 0 },
		progression = { stats = { built = 0, collected = 0, fires = 0, raids = 0, arrivals = 0 }, objectives = {} },
		exploration = {},
		settings = { sfx = true, music = true },
	}
end
VaultService.template = template

local function addRoom(vault: Vault, typeId: string, col: number, row: number, modules: number?, level: number?)
	local id = VaultService.newId(vault, "room")
	vault.data.rooms[id] = {
		id = id, type = typeId, col = col, row = row, modules = modules or 1, level = level or 1,
		assigned = {}, pending = 0,
	}
	return vault.data.rooms[id]
end

local function seedNewShelter(vault: Vault)
	local rng = vault.rt.rng
	vault.data.shelterNo = rng:NextInteger(100, 999)
	local entrance = addRoom(vault, "Entrance", 9, 0)
	addRoom(vault, "Elevator", 12, 0)
	addRoom(vault, "Elevator", 12, 1)
	addRoom(vault, "Elevator", 12, 2)
	local living = addRoom(vault, "Living", 13, 0)
	local water = addRoom(vault, "Water", 9, 1)
	local power = addRoom(vault, "Power", 13, 1)
	local cafe = addRoom(vault, "Cafeteria", 9, 2)
	local food = addRoom(vault, "Food", 13, 2)
	local inv = S.InventoryService
	local pistol = inv.grant(vault, "ScrapPistol")
	inv.grant(vault, "ScrapPistol")
	inv.grant(vault, "UtilitySuit")
	-- the founders: a small crew with jobs, a couple and a pair of friends
	local starters = {
		{ name = "Sarah Calder", arch = "Engineer", gender = "F", room = power, stat = "ENG", skill = 7 },
		{ name = "James Rook", arch = "Technician", gender = "M", room = water, stat = "MEC", skill = 6 },
		{ name = "Maya Okafor", arch = "Farmer", gender = "F", room = food, stat = "FRM", skill = 6 },
		{ name = "Theo Vance", arch = "Cook", gender = "M", room = cafe, stat = "COO", skill = 6 },
		{ name = "Iris Nakamura", arch = "Medic", gender = "F", room = water, stat = "MED", skill = 6 },
		{ name = "Omar Haddad", arch = "Security", gender = "M", room = entrance, stat = "CMB", skill = 5 },
	}
	local made = {}
	for i, s in starters do
		local d = S.DwellerService.create(vault, { archetype = s.arch, gender = s.gender, level = 1, name = s.name })
		d.stats[s.stat] = math.max(d.stats[s.stat], s.skill)
		d.roomId = s.room.id
		d.at = s.room.id
		d.status = "Working"
		d.activity = "Working"
		d.arriveAt = 0
		d.needs = { Hunger = 60 + i * 5, Thirst = 70 + i * 3, Energy = 55 + i * 7 }
		table.insert(s.room.assigned, d.id)
		if s.arch == "Security" then
			inv.equip(vault, d, pistol)
		end
		made[i] = d
	end
	local function pair(a, b, aff: number, partners: boolean)
		a.rel[b.id], b.rel[a.id] = aff, aff
		if partners then
			a.partner, b.partner = b.id, a.id
		end
	end
	pair(made[1], made[2], 82, true) -- Sarah & James
	pair(made[3], made[4], 50, false)
	pair(made[5], made[1], 45, false)
	local _ = living
end

-- Snapshot ---------------------------------------------------------------------
-- How hard the wasteland pushes back right now (0..1, see Shared/Difficulty).
function VaultService.pressure(vault: Vault): number
	local data = vault.data
	return Difficulty.pressure(data.playSeconds or 0, (Simulation.population(data.dwellers)))
end

function VaultService.derived(vault: Vault)
	local data = vault.data
	local alive = Simulation.population(data.dwellers)
	return {
		caps = Simulation.storageCaps(data.rooms),
		housing = Simulation.housing(data.rooms),
		population = alive,
		happiness = Simulation.vaultHappiness(data.dwellers),
		pressure = VaultService.pressure(vault),
	}
end

function VaultService.snapshot(vault: Vault)
	local data = vault.data
	return {
		shelterNo = data.shelterNo,
		resources = data.resources,
		rooms = data.rooms,
		dwellers = data.dwellers,
		inventory = data.inventory,
		progression = data.progression,
		exploration = data.exploration,
		derived = VaultService.derived(vault),
		rates = vault.rt.rates or {},
		flow = vault.rt.flow,
		powerFactor = vault.rt.powerFactor or 1,
		raid = S.CombatService.publicState(vault),
		serverTime = VaultService.now(),
		mockSave = S.SaveService.isMock(),
	}
end

function VaultService.sendSnapshot(vault: Vault)
	VaultService.send(vault, "snapshot", VaultService.snapshot(vault))
end

-- Save / load ------------------------------------------------------------------
local function cleanForSave(data: any): any
	-- Runtime-only fields never persist (fires, travel paths, pending timers).
	local copy = table.clone(data)
	copy.rooms = {}
	for id, r in data.rooms do
		local rr = table.clone(r)
		rr.incident = nil
		rr.readySince = nil
		rr.assigned = table.clone(r.assigned)
		copy.rooms[id] = rr
	end
	copy.dwellers = {}
	for id, d in data.dwellers do
		local dd = table.clone(d)
		dd.travel = nil
		dd.arriveAt = 0
		copy.dwellers[id] = dd
	end
	copy.lastSimTime = os.time()
	return copy
end

function VaultService.save(vault: Vault, release: boolean)
	if not vault.loaded then
		return
	end
	local ok = S.SaveService.save(vault.userId, cleanForSave(vault.data), release)
	if ok then
		vault.rt.dirty = false
	end
	return ok
end

local function onPlayerAdded(player: Player)
	local vault: Vault = {
		player = player,
		userId = player.UserId,
		data = nil,
		rt = { rng = Random.new(), dirty = false, mood = {}, rates = {} },
		loaded = false,
	}
	vaults[player] = vault
	local data, status = S.SaveService.load(player.UserId, template())
	if vaults[player] ~= vault then
		return -- left during load
	end
	if status == "failed" then
		player:Kick("Could not load your shelter safely. Please rejoin in a moment.")
		return
	end
	local fresh = data == nil
	vault.data = data or template()
	for _, r in vault.data.rooms do
		r.incident = nil
		r.readySince = nil
		r.pending = r.pending or 0
	end
	for _, d in vault.data.dwellers do
		d.travel = nil
		d.arriveAt = 0
	end
	if fresh then
		seedNewShelter(vault)
	end
	vault.loaded = true
	local away = 0
	if not fresh then
		away = math.clamp(os.time() - (vault.data.lastSimTime or os.time()), 0, Config.OFFLINE_CAP)
	end
	vault.data.lastSimTime = os.time()
	S.ResourceService.prime(vault)
	S.DwellerService.prime(vault)
	S.IncidentService.prime(vault)
	S.LifeService.prime(vault)
	local report = if away >= 60 then S.ResourceService.offline(vault, away) else nil
	VaultService.sendSnapshot(vault)
	if fresh then
		VaultService.toast(vault, "Welcome, Overseer. Shelter " .. vault.data.shelterNo .. " is online.", "good")
	elseif report then
		VaultService.send(vault, "offline", report)
	end
	if status == "corrupt" then
		VaultService.toast(vault, "Your previous save was damaged and has been archived. A new shelter was founded.", "bad")
	end
	VaultService.dirty(vault)
end

function VaultService.Init(services)
	S = services
end

function VaultService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, p in Players:GetPlayers() do
		task.spawn(onPlayerAdded, p)
	end
	Players.PlayerRemoving:Connect(function(player)
		local vault = vaults[player]
		vaults[player] = nil
		if vault and vault.loaded then
			S.CombatService.cancel(vault)
			VaultService.save(vault, true)
		end
	end)
	game:BindToClose(function()
		local threads = {}
		for _, vault in vaults do
			table.insert(threads, task.spawn(function()
				VaultService.save(vault, true)
			end))
		end
		task.wait(2)
	end)
	while true do
		task.wait(Config.AUTOSAVE_INTERVAL)
		for _, vault in vaults do
			if vault.loaded and vault.rt.dirty then
				task.spawn(VaultService.save, vault, false)
			end
		end
	end
end

return VaultService
