--!strict
-- Persistence: DataStore + session locks + versioned schema + corruption quarantine.
-- Falls back to an in-memory store when DataStores are unavailable (unpublished place or
-- Studio API access disabled) so the game stays playable in Studio.
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DwellerDefinitions = require(ReplicatedStorage.Shared.DwellerDefinitions)
local Needs = require(ReplicatedStorage.Shared.Needs)
local RoomDefinitions = require(ReplicatedStorage.Shared.RoomDefinitions)

local SaveService = {}

local STORE_NAME = "UH_Shelters_v1"
-- Seconds before an abandoned session lock may be taken over. A live server re-saves (refreshing
-- its lock) at least every LOCK_REFRESH seconds, so this only bites after a crash.
local LOCK_TTL = 240
SaveService.LOCK_REFRESH = 80
local JOB = game.JobId ~= "" and game.JobId or ("studio-" .. tostring(math.random(1e6)))

type Store = {
	UpdateAsync: (any, string, (any) -> any) -> any,
	SetAsync: (any, string, any) -> (),
}

local store: Store? = nil
local usingMock = false
local mock: { [string]: any } = {}

-- JSON round-trip so the mock rejects exactly what a real DataStore would (Vector3s, cycles...).
local HttpService = game:GetService("HttpService")
local function roundTrip(v: any): any
	return if v == nil then nil else HttpService:JSONDecode(HttpService:JSONEncode(v))
end

local MockStore = {}
function MockStore:UpdateAsync(key: string, fn: (any) -> any)
	local nxt = fn(roundTrip(mock[key]))
	if nxt == nil then
		return nil
	end
	mock[key] = roundTrip(nxt)
	return roundTrip(mock[key])
end
function MockStore:SetAsync(key: string, value: any)
	mock[key] = roundTrip(value)
end

-- Ordered schema migrations: [fromVersion] = function(data) -> data at fromVersion+1
local MIGRATIONS: { [number]: (any) -> any } = {
	-- 1 -> 2: skills replace the old 7-attribute set; personalities, needs, relationships,
	-- locations; Materials (old Scrap is converted, plus a starter stock).
	[1] = function(d)
		local order = DwellerDefinitions.TraitOrder
		for id, dw in d.dwellers do
			if dw.stats and dw.stats.STR ~= nil then
				dw.stats = DwellerDefinitions.migrateStats(dw.stats)
			end
			if not dw.traits then
				local first = dw.trait or order[(tonumber(id) or 1) % #order + 1]
				local second = order[((tonumber(id) or 1) * 7) % #order + 1]
				dw.traits = if second == first then { first } else { first, second }
			end
			dw.needs = dw.needs or Needs.default()
			dw.rel = dw.rel or {}
			dw.memories = dw.memories or {}
			dw.at = dw.at or dw.roomId
		end
		local res = d.resources or {}
		res.Materials = (res.Materials or 0) + (res.Scrap or 0) + 150
		res.Scrap = 0
		d.resources = res
		d.playSeconds = d.playSeconds or 0
		return d
	end,
}

local function deepFill(dst: any, template: any)
	for k, v in template do
		if dst[k] == nil then
			dst[k] = if type(v) == "table" then table.clone(v) else v
		elseif type(v) == "table" and type(dst[k]) == "table" and next(v) ~= nil and #v == 0 then
			-- fill nested dictionaries, but never overwrite arrays/collections with defaults
			if k ~= "rooms" and k ~= "dwellers" and k ~= "inventory" then
				deepFill(dst[k], v)
			end
		end
	end
end

function SaveService.isMock(): boolean
	return usingMock
end

-- Damaged saves -----------------------------------------------------------------
local function goodRoom(r: any): boolean
	return type(r) == "table" and type(r.type) == "string" and RoomDefinitions.Types[r.type] ~= nil
		and type(r.col) == "number" and type(r.row) == "number"
end

local function goodDweller(d: any): boolean
	return type(d) == "table" and type(d.stats) == "table" and type(d.name) == "string"
end

-- Why a save can't be used at all (nil when it can, perhaps after repair()).
local function unusable(data: any): string?
	if type(data) ~= "table" then
		return "not a table"
	end
	if type(data.rooms) ~= "table" or type(data.dwellers) ~= "table" or type(data.resources) ~= "table" then
		return "missing core tables"
	end
	for _, r in data.rooms do
		if goodRoom(r) and r.type == "Entrance" then
			return nil
		end
	end
	return "no blast door"
end

-- Damaged room / survivor records (read-only scan).
local function problemsIn(data: any): { string }
	local problems = {}
	for id, r in data.rooms do
		if not goodRoom(r) then
			table.insert(problems, "bad room " .. tostring(id))
		end
	end
	for id, d in data.dwellers do
		if not goodDweller(d) then
			table.insert(problems, "bad dweller " .. tostring(id))
		end
	end
	return problems
end

-- Drop damaged records and every reference to them, keeping the rest of the shelter.
local function repair(data: any)
	for id, r in data.rooms do
		if not goodRoom(r) then
			data.rooms[id] = nil
		end
	end
	for id, d in data.dwellers do
		if not goodDweller(d) then
			data.dwellers[id] = nil
		end
	end
	for _, r in data.rooms do
		if type(r.assigned) ~= "table" then
			r.assigned = {}
		end
		for i = #r.assigned, 1, -1 do
			if data.dwellers[r.assigned[i]] == nil then
				table.remove(r.assigned, i)
			end
		end
	end
	for _, d in data.dwellers do
		if d.roomId ~= nil and data.rooms[d.roomId] == nil then
			d.roomId = nil
			if d.status == "Working" then
				d.status = "Idle"
			end
		end
		if d.at ~= nil and data.rooms[d.at] == nil then
			d.at = nil
		end
		if d.partner ~= nil and data.dwellers[d.partner] == nil then
			d.partner = nil
		end
	end
	if type(data.exploration) == "table" then
		for id in data.exploration do
			if data.dwellers[id] == nil then
				data.exploration[id] = nil
			end
		end
	end
	if type(data.inventory) == "table" then
		for _, item in data.inventory do
			if type(item) == "table" and item.equippedBy ~= nil and data.dwellers[item.equippedBy] == nil then
				item.equippedBy = nil
			end
		end
	end
end

-- Keep a copy of a damaged save before anything overwrites it. Must succeed before the player
-- is allowed to play on (and autosave over) that shelter.
local function archive(s: any, key: string, data: any): boolean
	for attempt = 1, 3 do
		local ok, err = pcall(function()
			s:SetAsync(key .. "_corrupt_" .. os.time(), data)
		end)
		if ok then
			return true
		end
		warn("[SaveService] archiving damaged save", key, "failed:", err)
		task.wait(attempt)
	end
	return false
end

-- Upgrade older payloads and fill fields added since they were written.
function SaveService.migrate(data: any, template: any): any
	local v = data.schema or 0
	while v < Config.SCHEMA_VERSION do
		local fn = MIGRATIONS[v]
		if fn then
			data = fn(data)
		end
		v += 1
	end
	data.schema = Config.SCHEMA_VERSION
	deepFill(data, template)
	return data
end

local function lockedElsewhere(cur: any): boolean
	return cur ~= nil and cur.lock ~= nil and cur.lock.job ~= JOB and os.time() - (cur.lock.time or 0) < LOCK_TTL
end

-- Let go of this server's session lock without writing shelter data (e.g. the player left while
-- their shelter was still loading). Does nothing if another server holds the lock.
function SaveService.releaseLock(userId: number): boolean
	local key = "shelter_" .. userId
	local s = store :: any
	for attempt = 1, 3 do
		local ok, err = pcall(function()
			s:UpdateAsync(key, function(cur)
				if cur == nil or cur.lock == nil or cur.lock.job ~= JOB then
					return nil
				end
				cur.lock = nil
				return cur
			end)
		end)
		if ok then
			return true
		end
		warn("[SaveService] releasing lock for", userId, "failed:", err)
		task.wait(attempt)
	end
	return false
end

-- Returns (data|nil, status):
--   "new"      no save yet (fresh player)
--   "loaded"   ok
--   "repaired" damaged rooms / survivors were dropped (the original is archived)
--   "corrupt"  unusable (archived); start a new shelter
--   "locked"   open on another server right now
--   "failed"   DataStore trouble
-- After "locked" / "failed" this server holds no lock; otherwise it does.
function SaveService.load(userId: number, template: any): (any?, string)
	local key = "shelter_" .. userId
	local s = store :: any
	local busy = false
	for attempt = 1, 5 do
		local payload
		busy = false
		local ok, err = pcall(function()
			payload = s:UpdateAsync(key, function(cur)
				if lockedElsewhere(cur) then
					busy = true
					return nil -- locked by another live server: abort this update, retry later
				end
				cur = cur or { data = nil }
				cur.lock = { job = JOB, time = os.time() }
				return cur
			end)
		end)
		if ok and payload and payload.lock and payload.lock.job == JOB then
			local data = payload.data
			if data == nil then
				return nil, "new"
			end
			local why = unusable(data)
			local problems = if why then { why } else problemsIn(data)
			if #problems == 0 then
				return SaveService.migrate(data, template), "loaded"
			end
			warn("[SaveService] damaged save for", userId, table.concat(problems, ", "), "- archiving")
			if not archive(s, key, data) then
				-- never let this session's saves overwrite a damaged shelter we couldn't keep a copy of
				SaveService.releaseLock(userId)
				return nil, "failed"
			end
			if why then
				return nil, "corrupt"
			end
			repair(data)
			if unusable(data) then
				return nil, "corrupt"
			end
			return SaveService.migrate(data, template), "repaired"
		end
		warn("[SaveService] load attempt", attempt, "failed:", err or "session locked elsewhere")
		task.wait(2 ^ attempt * 0.5)
	end
	return nil, if busy then "locked" else "failed"
end

-- Write a shelter. `abort` is checked as the write lands (a late autosave must not re-take a lock
-- the final save just released). Returns (saved, outcome): outcome is "saved", "skipped",
-- "locked" (another server owns the session now - nothing was written) or "error".
function SaveService.save(userId: number, data: any, release: boolean, abort: (() -> boolean)?): (boolean, string)
	local key = "shelter_" .. userId
	local s = store :: any
	for attempt = 1, 3 do
		local outcome = "saved"
		local ok, err = pcall(function()
			s:UpdateAsync(key, function(cur)
				if abort and abort() then
					outcome = "skipped"
					return nil
				end
				if lockedElsewhere(cur) then
					outcome = "locked"
					return nil -- another server owns this session now; never clobber it
				end
				outcome = "saved"
				return {
					data = data,
					lock = if release then nil else { job = JOB, time = os.time() },
					savedAt = os.time(),
				}
			end)
		end)
		if ok then
			return outcome == "saved", outcome
		end
		warn("[SaveService] save attempt", attempt, "failed:", err)
		task.wait(attempt)
	end
	return false, "error"
end

function SaveService.Init()
	local ok, ds = pcall(function()
		local s = DataStoreService:GetDataStore(STORE_NAME)
		s:GetAsync("__probe") -- throws when API access is unavailable
		return s
	end)
	if ok and game.PlaceId ~= 0 then
		store = ds :: any
	else
		store = MockStore :: any
		usingMock = true
		warn("[SaveService] DataStores unavailable (" .. (if game.PlaceId == 0 then "unpublished place" else tostring(ds)) .. ") - using in-memory saves for this session")
	end
end

return SaveService
