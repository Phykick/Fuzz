--!strict
-- Per-player shelter lifecycle: load/create, migrate, offline catch-up, snapshot, autosave.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Simulation = require(ReplicatedStorage.Shared.Simulation)
local Difficulty = require(ReplicatedStorage.Shared.Difficulty)
local AudioConfig = require(ReplicatedStorage:WaitForChild("Audio"):WaitForChild("AudioConfig"))

local VaultService = {}
local S: any

export type Vault = {
	player: Player,
	userId: number,
	data: any,
	rt: any,
	loaded: boolean,
	closed: boolean?, -- the player left / the server is closing; no more autosaves
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
		settings = { volumes = {} },
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
		settings = data.settings,
	}
end

function VaultService.sendSnapshot(vault: Vault)
	VaultService.send(vault, "snapshot", VaultService.snapshot(vault))
end

-- Save / load ------------------------------------------------------------------
local inFlight = 0 -- loads and saves still talking to the DataStore (BindToClose waits for them)

local function cleanForSave(data: any): any
	-- Runtime-only fields never persist (travel paths, pending timers).
	local copy = table.clone(data)
	copy.rooms = {}
	for id, r in data.rooms do
		local rr = table.clone(r)
		rr.readySince = nil
		if r.incident then
			-- emergencies persist, so leaving and rejoining doesn't put out a fire or pay for a
			-- repair; the spread timer (math.huge for breakdowns) restarts on load
			rr.incident = table.clone(r.incident)
			rr.incident.spreadAt = nil
		end
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

-- Returns true when the shelter was written. release = final save (drops the session lock).
function VaultService.save(vault: Vault, release: boolean): boolean
	if not vault.loaded then
		return false
	end
	if not release and vault.rt.saving then
		return false -- the previous autosave is still on its way
	end
	vault.rt.saving = true
	vault.rt.dirty = false -- changes from here on belong to the next save
	inFlight += 1
	local success, ok, outcome = pcall(S.SaveService.save, vault.userId, cleanForSave(vault.data), release, function()
		-- once the final save has started, a late autosave must not re-take the session lock
		return not release and vault.closed == true
	end)
	inFlight -= 1
	vault.rt.saving = false
	if not success then
		warn("[VaultService] save failed:", ok)
		ok, outcome = false, "error"
	end
	if ok then
		vault.rt.lastSave = os.clock()
	else
		vault.rt.dirty = true
		if outcome == "locked" and vault.player.Parent then
			-- another server took this shelter over: stop here rather than keep playing a session
			-- whose progress can no longer be saved
			vault.player:Kick("Your shelter was opened on another server. Please rejoin.")
		end
	end
	return ok
end

local function hasVault(userId: number): boolean
	for _, v in vaults do
		if v.userId == userId then
			return true
		end
	end
	return false
end

-- The player left (or the server is closing): final save, releasing the session lock.
local function closeVault(player: Player)
	local vault = vaults[player]
	if not vault then
		return
	end
	vaults[player] = nil
	vault.closed = true
	if vault.loaded then
		S.CombatService.onLeave(vault)
		VaultService.save(vault, true)
	end
	-- still loading: onPlayerAdded lets go of the lock once the load returns
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
	inFlight += 1
	local okLoad, data, status = pcall(S.SaveService.load, player.UserId, template())
	if not okLoad then
		warn("[VaultService] load failed for", player.UserId, data)
		data, status = nil, "error"
	end
	if vaults[player] ~= vault or status == "error" then
		-- left mid-load (or the load blew up): don't sit on the session lock we may have taken,
		-- or the player is locked out of every other server until it expires
		if status ~= "failed" and status ~= "locked" and not hasVault(player.UserId) then
			S.SaveService.releaseLock(player.UserId)
		end
		inFlight -= 1
		if vaults[player] == vault then
			vaults[player] = nil
			player:Kick("Could not load your shelter safely. Please rejoin in a moment.")
		end
		return
	end
	inFlight -= 1
	if status == "failed" or status == "locked" then
		vaults[player] = nil
		player:Kick(if status == "locked"
			then "Your shelter is still open on another server. Please rejoin in a minute."
			else "Could not load your shelter safely. Please rejoin in a moment.")
		return
	end
	local fresh = data == nil
	vault.data = data or template()
	for _, r in vault.data.rooms do
		r.readySince = nil
		r.pending = r.pending or 0
	end
	for _, d in vault.data.dwellers do
		d.travel = nil
		d.arriveAt = 0
		if d.status == "Dead" then
			d.roomId = nil -- older saves kept the job of the dead (their slot is already free)
		end
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
	elseif status == "repaired" then
		VaultService.toast(vault, "Some damaged records in your save were removed. A backup was kept.", "warn")
	end
	vault.rt.lastSave = os.clock() -- loading just took (refreshed) the session lock
	VaultService.dirty(vault)
end

function VaultService.Init(services)
	S = services
	-- the player's audio volumes (Master, Music, SFX, Ambient, UI: 0..1), saved with the shelter.
	-- (Older saves have sfx/music on-off switches instead; the client still reads those.)
	S.NetService.handle("Settings", function(player, p)
		local vault = VaultService.get(player)
		if not vault then
			return false, "Not ready"
		end
		local st = vault.data.settings
		if type(st) ~= "table" then
			st = {}
			vault.data.settings = st
		end
		for _, key in { "sfx", "music" } do
			if type(p[key]) == "boolean" then
				st[key] = p[key]
			end
		end
		if type(p.volumes) == "table" then
			local vols = if type(st.volumes) == "table" then st.volumes else {}
			for _, key in AudioConfig.PlayerVolumes do
				local v = p.volumes[key]
				if type(v) == "number" and v == v and math.abs(v) ~= math.huge then
					vols[key] = math.floor(math.clamp(v, 0, 1) * 20 + 0.5) / 20
				end
			end
			st.volumes = vols
		end
		VaultService.dirty(vault)
		return true, st
	end)
end

function VaultService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, p in Players:GetPlayers() do
		task.spawn(onPlayerAdded, p)
	end
	Players.PlayerRemoving:Connect(closeVault)
	game:BindToClose(function()
		-- Final saves for everyone still here, then wait for every load and save in flight
		-- (including ones PlayerRemoving started): the server process ends as soon as this returns.
		local players = {}
		for player in vaults do
			table.insert(players, player)
		end
		for _, player in players do
			task.spawn(closeVault, player)
		end
		local deadline = os.clock() + 25
		repeat
			task.wait(0.1)
		until inFlight == 0 or os.clock() > deadline
	end)
	while true do
		task.wait(Config.AUTOSAVE_INTERVAL)
		for _, vault in vaults do
			-- saving also refreshes the session lock, so save now and then even if nothing changed
			if vault.loaded and (vault.rt.dirty or os.clock() - (vault.rt.lastSave or 0) >= S.SaveService.LOCK_REFRESH) then
				task.spawn(VaultService.save, vault, false)
			end
		end
	end
end

return VaultService
