--!strict
-- Persistence: DataStore + session locks + versioned schema + corruption quarantine.
-- Falls back to an in-memory store when DataStores are unavailable (unpublished place or
-- Studio API access disabled) so the game stays playable in Studio.
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DwellerDefinitions = require(ReplicatedStorage.Shared.DwellerDefinitions)
local Needs = require(ReplicatedStorage.Shared.Needs)

local SaveService = {}

local STORE_NAME = "UH_Shelters_v1"
local LOCK_TTL = 600 -- seconds before an abandoned session lock may be stolen
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

local function validate(data: any): (boolean, string?)
	if type(data) ~= "table" then
		return false, "not a table"
	end
	if type(data.rooms) ~= "table" or type(data.dwellers) ~= "table" or type(data.resources) ~= "table" then
		return false, "missing core tables"
	end
	for id, r in data.rooms do
		if type(r) ~= "table" or type(r.type) ~= "string" or type(r.col) ~= "number" or type(r.row) ~= "number" then
			return false, "bad room " .. tostring(id)
		end
	end
	for id, d in data.dwellers do
		if type(d) ~= "table" or type(d.stats) ~= "table" or type(d.name) ~= "string" then
			return false, "bad dweller " .. tostring(id)
		end
	end
	return true
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

-- Returns (data|nil, status). data == nil means "no save yet" (fresh player).
function SaveService.load(userId: number, template: any): (any?, string)
	local key = "shelter_" .. userId
	local s = store :: any
	for attempt = 1, 5 do
		local payload
		local ok, err = pcall(function()
			payload = s:UpdateAsync(key, function(cur)
				if cur and cur.lock and cur.lock.job ~= JOB and os.time() - (cur.lock.time or 0) < LOCK_TTL then
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
			local valid, why = validate(data)
			if not valid then
				warn("[SaveService] corrupt save for", userId, why, "- quarantining")
				pcall(function()
					s:SetAsync(key .. "_corrupt_" .. os.time(), data)
				end)
				return nil, "corrupt"
			end
			return SaveService.migrate(data, template), "loaded"
		end
		warn("[SaveService] load attempt", attempt, "failed:", err or "session locked elsewhere")
		task.wait(2 ^ attempt * 0.5)
	end
	return nil, "failed"
end

function SaveService.save(userId: number, data: any, release: boolean): boolean
	local key = "shelter_" .. userId
	local s = store :: any
	for attempt = 1, 3 do
		local ok, err = pcall(function()
			s:UpdateAsync(key, function(cur)
				if cur and cur.lock and cur.lock.job ~= JOB and os.time() - (cur.lock.time or 0) < LOCK_TTL then
					return nil -- another server owns this session now; never clobber it
				end
				return {
					data = data,
					lock = if release then nil else { job = JOB, time = os.time() },
					savedAt = os.time(),
				}
			end)
		end)
		if ok then
			return true
		end
		warn("[SaveService] save attempt", attempt, "failed:", err)
		task.wait(attempt)
	end
	return false
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
