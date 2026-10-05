--!strict
-- Client mirror of the server's shelter state + typed change signals + action helper.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local StateStore = {}

StateStore.state = {
	ready = false,
	rooms = {} :: { [string]: any },
	dwellers = {} :: { [string]: any },
	resources = {} :: { [string]: number },
	caps = {} :: { [string]: number },
	rates = {} :: { [string]: number },
	derived = {} :: any,
	inventory = {} :: { [string]: any },
	progression = {} :: any,
	raid = nil :: any,
	shelterNo = 0,
	mockSave = false,
	exploration = {} :: { [string]: any },
	flow = {} :: { [string]: { prod: number, use: number } }, -- per resource, per minute
	powerFactor = 1, -- share of power demand the grid meets (brownout below 1)
	settings = { sfx = true, music = true } :: any, -- saved with the shelter
}

StateStore.Snapshot = Signal.new()
StateStore.RoomChanged = Signal.new()
StateStore.RoomRemoved = Signal.new()
StateStore.DwellerChanged = Signal.new()
StateStore.DwellerRemoved = Signal.new()
StateStore.Resources = Signal.new()
StateStore.Toast = Signal.new()
StateStore.Collected = Signal.new()
StateStore.Incident = Signal.new()
StateStore.IncidentEnd = Signal.new()
StateStore.Fire = Signal.new()
StateStore.Raid = Signal.new()
StateStore.Combat = Signal.new()
StateStore.RaidEnd = Signal.new()
StateStore.LevelUp = Signal.new()
StateStore.Arrival = Signal.new()
StateStore.Approach = Signal.new()
StateStore.Family = Signal.new()
StateStore.Bark = Signal.new()
StateStore.Offline = Signal.new()
StateStore.Inventory = Signal.new()
StateStore.DwellerStats = Signal.new()
StateStore.ExploreChanged = Signal.new()
StateStore.ExploreEnded = Signal.new()
StateStore.ActionDone = Signal.new() -- (name, ok, result | reason, quiet) after every server action

local actionRemote: RemoteFunction

function StateStore.now(): number
	return workspace:GetServerTimeNow()
end

-- Invoke a server action. Returns ok, result | reason. Failures surface as toasts.
function StateStore.action(name: string, payload: any?, quiet: boolean?): (boolean, any)
	local ok, res = pcall(function()
		return actionRemote:InvokeServer(name, payload or {})
	end)
	if not ok or type(res) ~= "table" then
		StateStore.Toast:Fire({ text = "Connection hiccup - try again", tone = "bad" })
		StateStore.ActionDone:Fire(name, false, "network", quiet)
		return false, "network"
	end
	if not res.ok then
		if not quiet then
			StateStore.Toast:Fire({ text = tostring(res.reason), tone = "warn" })
		end
		StateStore.ActionDone:Fire(name, false, res.reason, quiet)
		return false, res.reason
	end
	StateStore.ActionDone:Fire(name, true, res.result, quiet)
	return true, res.result
end

local handlers = {
	snapshot = function(p)
		local s = StateStore.state
		s.rooms = p.rooms
		s.dwellers = p.dwellers
		s.resources = p.resources
		s.inventory = p.inventory or {}
		s.progression = p.progression or {}
		s.derived = p.derived or {}
		s.caps = s.derived.caps or {}
		s.rates = p.rates or {}
		s.flow = p.flow or {}
		s.powerFactor = p.powerFactor or 1
		s.raid = p.raid
		s.shelterNo = p.shelterNo
		s.mockSave = p.mockSave
		s.exploration = p.exploration or {}
		s.settings = p.settings or s.settings
		s.ready = true
		StateStore.Snapshot:Fire(s)
	end,
	res = function(p)
		local s = StateStore.state
		s.resources = p.resources
		s.rates = p.rates or s.rates
		s.flow = p.flow or s.flow
		s.powerFactor = p.powerFactor or 1
		s.caps = p.caps or s.caps
		s.derived.housing = p.housing
		s.derived.population = p.population
		s.derived.happiness = p.happiness
		s.derived.pressure = p.pressure
		StateStore.Resources:Fire(s)
	end,
	room = function(p)
		StateStore.state.rooms[p.id] = p
		StateStore.RoomChanged:Fire(p)
	end,
	roomRemoved = function(p)
		StateStore.state.rooms[p.id] = nil
		StateStore.RoomRemoved:Fire(p.id)
	end,
	dweller = function(p)
		StateStore.state.dwellers[p.id] = p
		StateStore.DwellerChanged:Fire(p)
	end,
	dwellerRemoved = function(p)
		StateStore.state.dwellers[p.id] = nil
		StateStore.DwellerRemoved:Fire(p.id)
	end,
	explore = function(p)
		StateStore.state.exploration[p.id] = p.rec
		StateStore.ExploreChanged:Fire(p.id)
	end,
	exploreEnd = function(p)
		StateStore.state.exploration[p.id] = nil
		StateStore.ExploreEnded:Fire(p.id, p)
	end,
	dstats = function(p)
		local ds = StateStore.state.dwellers
		for id, v in p do
			local d = ds[id]
			if d then
				d.health, d.happiness, d.xp, d.level = v[1], v[2], v[3], v[4]
				d.deadFor = v[5]
				if v[6] then
					d.needs = d.needs or {}
					d.needs.Hunger, d.needs.Thirst, d.needs.Energy = v[6], v[7], v[8]
				end
			end
		end
		StateStore.DwellerStats:Fire()
	end,
	inventory = function(p)
		StateStore.state.inventory = p
		StateStore.Inventory:Fire(p)
	end,
	toast = function(p)
		StateStore.Toast:Fire(p)
	end,
	collected = function(p)
		StateStore.Collected:Fire(p)
	end,
	incident = function(p)
		StateStore.Incident:Fire(p)
	end,
	incidentEnd = function(p)
		StateStore.IncidentEnd:Fire(p)
	end,
	fire = function(p)
		for _, u in p do
			local r = StateStore.state.rooms[u.roomId]
			if r and r.incident then
				r.incident.hp = u.hp
				r.incident.maxHp = u.maxHp
			end
		end
		StateStore.Fire:Fire(p)
	end,
	raid = function(p)
		StateStore.state.raid = p
		StateStore.Raid:Fire(p)
	end,
	combat = function(p)
		local raid = StateStore.state.raid
		if raid and p.raiders then
			raid.raiders = p.raiders
		end
		StateStore.Combat:Fire(p)
	end,
	raidEnd = function(p)
		StateStore.state.raid = nil
		StateStore.RaidEnd:Fire(p)
	end,
	levelup = function(p)
		StateStore.LevelUp:Fire(p)
	end,
	arrival = function(p)
		StateStore.Arrival:Fire(p)
	end,
	approach = function(p)
		StateStore.Approach:Fire(p)
	end,
	family = function(p)
		StateStore.Family:Fire(p)
	end,
	bark = function(p)
		StateStore.Bark:Fire(p)
	end,
	offline = function(p)
		StateStore.Offline:Fire(p)
	end,
}

function StateStore.Init()
	local action, state = Net.remotes()
	actionRemote = action
	state.OnClientEvent:Connect(function(kind: string, payload: any)
		local h = (handlers :: any)[kind]
		if h then
			h(payload)
		end
	end)
end

return StateStore
