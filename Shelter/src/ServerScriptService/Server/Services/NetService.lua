--!strict
-- Remote wiring: validates + rate-limits client intents and dispatches to service handlers.
-- Clients never send state, only intents ("assign X to Y"). Handlers return (ok, result|reason).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)

local NetService = {}

local handlers: { [string]: (Player, any) -> (boolean, any) } = {}
local buckets: { [Player]: { tokens: number, last: number } } = {}
local actionRemote: RemoteFunction
local stateRemote: RemoteEvent

function NetService.handle(action: string, fn: (Player, any) -> (boolean, any))
	handlers[action] = fn
end

function NetService.send(player: Player, kind: string, payload: any)
	if player.Parent then
		stateRemote:FireClient(player, kind, payload)
	end
end

local function allow(player: Player): boolean
	local b = buckets[player]
	local now = os.clock()
	if not b then
		b = { tokens = Config.ACTION_RATE_LIMIT, last = now }
		buckets[player] = b
	end
	b.tokens = math.min(Config.ACTION_RATE_LIMIT, b.tokens + (now - b.last) * Config.ACTION_RATE_LIMIT)
	b.last = now
	if b.tokens < 1 then
		return false
	end
	b.tokens -= 1
	return true
end

function NetService.Init()
	actionRemote, stateRemote = Net.remotes()
	actionRemote.OnServerInvoke = function(player: Player, action: any, payload: any)
		if type(action) ~= "string" or (payload ~= nil and type(payload) ~= "table") then
			return { ok = false, reason = "Bad request" }
		end
		if not allow(player) then
			return { ok = false, reason = "Slow down" }
		end
		local fn = handlers[action]
		if not fn then
			return { ok = false, reason = "Unknown action" }
		end
		local success, ok, result = pcall(fn, player, payload or {})
		if not success then
			warn("[NetService]", action, ok)
			return { ok = false, reason = "Server error" }
		end
		if ok then
			return { ok = true, result = result }
		end
		return { ok = false, reason = result }
	end
	Players.PlayerRemoving:Connect(function(p)
		buckets[p] = nil
	end)
end

return NetService
