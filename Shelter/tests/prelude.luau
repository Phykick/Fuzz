-- Minimal fake Roblox environment for running the Underhaven server headless in the Luau CLI.
-- Virtual clock + cooperative scheduler (task.*), fake Players / DataStores / remotes, and a
-- strict JSON round-trip that rejects what a real DataStore would (NaN/inf, mixed tables...).

local H = {}
H.errors = {}
H.warnings = {}
H.events = {} -- [player] = { {kind, payload}, ... }
H.quiet = false

---------------------------------------------------------------------------------------------
-- Virtual clock + scheduler
---------------------------------------------------------------------------------------------
local EPOCH = 1750000000
local now = 0
local queue = {} -- { thread, wake, args }
local seq = 0

function H.clock(): number
	return now
end

local function schedule(co, wake, ...)
	seq += 1
	table.insert(queue, { co = co, wake = wake, seq = seq, args = table.pack(...) })
end

local function resume(co, ...)
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		local msg = tostring(err) .. "\n" .. debug.traceback(co)
		table.insert(H.errors, msg)
		if not H.quiet then
			print("[thread error] " .. msg)
		end
	end
end

local task = {}
function task.spawn(fn, ...)
	local co = if type(fn) == "thread" then fn else coroutine.create(fn)
	resume(co, ...)
	return co
end
function task.defer(fn, ...)
	local co = if type(fn) == "thread" then fn else coroutine.create(fn)
	schedule(co, now, ...)
	return co
end
function task.delay(t, fn, ...)
	local co = if type(fn) == "thread" then fn else coroutine.create(fn)
	schedule(co, now + (t or 0), ...)
	return co
end
function task.wait(t)
	t = math.max(t or 0, 1 / 60)
	local co = coroutine.running()
	schedule(co, now + t)
	coroutine.yield()
	return t
end
function task.cancel(co)
	for i = #queue, 1, -1 do
		if queue[i].co == co then
			table.remove(queue, i)
		end
	end
end
H.task = task

-- Run the scheduler until virtual time `untilT` (or until `stopWhen()` is true).
function H.runUntil(untilT: number, stopWhen: (() -> boolean)?)
	while true do
		if stopWhen and stopWhen() then
			return true
		end
		local best, bi = nil, nil
		for i, e in queue do
			if not best or e.wake < best.wake or (e.wake == best.wake and e.seq < best.seq) then
				best, bi = e, i
			end
		end
		if not best or best.wake > untilT then
			now = math.max(now, untilT)
			return false
		end
		table.remove(queue, bi)
		now = math.max(now, best.wake)
		if coroutine.status(best.co) == "suspended" then
			resume(best.co, table.unpack(best.args, 1, best.args.n))
		end
	end
end

function H.advance(seconds: number)
	H.runUntil(now + seconds)
end

-- Drop every pending thread (the server process is gone).
function H.kill()
	table.clear(queue)
end

---------------------------------------------------------------------------------------------
-- Globals
---------------------------------------------------------------------------------------------
local fakeOs = setmetatable({
	time = function(t)
		if t then
			return os.time(t)
		end
		return math.floor(EPOCH + now)
	end,
	clock = function()
		return now
	end,
}, { __index = os })
H.os = fakeOs

local function warn(...)
	local parts = {}
	for i = 1, select("#", ...) do
		table.insert(parts, tostring((select(i, ...))))
	end
	local msg = table.concat(parts, " ")
	table.insert(H.warnings, msg)
	if not H.quiet then
		print("[warn] " .. msg)
	end
end
H.warn = warn

local function hprint(...)
	if not H.quiet then
		print(...)
	end
end
H.print = hprint

-- Deterministic Random (xorshift32)
local Random = {}
Random.__index = Random
local seedCounter = 12345
function Random.new(seed)
	seedCounter += 7919
	-- scramble so nearby seeds give unrelated streams
	local s = (math.floor(seed or seedCounter) * 2654435761 + 2463534242) % 4294967296
	if s == 0 then
		s = 2463534242
	end
	local r = setmetatable({ s = s }, Random)
	for _ = 1, 4 do
		r:_next()
	end
	return r
end
function Random:_next(): number
	local x = self.s
	x = bit32.bxor(x, bit32.lshift(x, 13))
	x = bit32.bxor(x, bit32.rshift(x, 17))
	x = bit32.bxor(x, bit32.lshift(x, 5))
	self.s = x
	return x / 4294967296
end
function Random:NextNumber(a, b)
	local r = self:_next()
	if a == nil then
		return r
	end
	return a + (b - a) * r
end
function Random:NextInteger(a, b)
	return a + math.floor(self:_next() * (b - a + 1))
end
H.Random = Random

local Vector3 = {
	new = function(x, y, z)
		return { X = x or 0, Y = y or 0, Z = z or 0 }
	end,
}
Vector3.zero = Vector3.new()
local CFrame = {
	new = function(x, y, z)
		return { X = x or 0, Y = y or 0, Z = z or 0 }
	end,
}
local Color3 = {
	fromHex = function(h)
		return { hex = h }
	end,
	fromRGB = function(r, g, b)
		return { r = r, g = g, b = b }
	end,
	new = function(r, g, b)
		return { r = r, g = g, b = b }
	end,
}

---------------------------------------------------------------------------------------------
-- Signals and instances
---------------------------------------------------------------------------------------------
local function Signal()
	local s = { _fns = {} }
	function s:Connect(fn)
		table.insert(self._fns, fn)
		return {
			Disconnect = function()
				local i = table.find(self._fns, fn)
				if i then
					table.remove(self._fns, i)
				end
			end,
		}
	end
	function s:Fire(...)
		for _, fn in table.clone(self._fns) do
			task.spawn(fn, ...)
		end
	end
	return s
end
H.Signal = Signal

local Node = {}
local function newNode(name: string, className: string?)
	local n = { _name = name, _class = className or "Folder", _children = {}, _parent = nil, _props = {} }
	return setmetatable(n, Node)
end
Node.__index = function(self, k)
	if k == "Name" then
		return rawget(self, "_name")
	elseif k == "Parent" then
		return rawget(self, "_parent")
	elseif k == "ClassName" then
		return rawget(self, "_class")
	end
	local m = rawget(Node, k)
	if m then
		return m
	end
	local props = rawget(self, "_props")
	if props[k] ~= nil then
		return props[k]
	end
	local c = rawget(self, "_children")[k]
	if c then
		return c
	end
	error(tostring(k) .. " is not a valid member of " .. rawget(self, "_name"), 2)
end
Node.__newindex = function(self, k, v)
	if k == "Name" then
		rawset(self, "_name", v)
	elseif k == "Parent" then
		local old = rawget(self, "_parent")
		if old then
			rawget(old, "_children")[rawget(self, "_name")] = nil
		end
		rawset(self, "_parent", v)
		if v then
			rawget(v, "_children")[rawget(self, "_name")] = self
		end
	else
		rawget(self, "_props")[k] = v
	end
end
function Node.FindFirstChild(self, name)
	return rawget(self, "_children")[name]
end
function Node.WaitForChild(self, name)
	local c = rawget(self, "_children")[name]
	assert(c, "WaitForChild would hang: " .. tostring(name))
	return c
end
function Node.GetChildren(self)
	local out = {}
	for _, c in rawget(self, "_children") do
		table.insert(out, c)
	end
	return out
end
function Node.SetAttribute(self, k, v)
	rawget(self, "_props")["@" .. k] = v
end
function Node.GetAttribute(self, k)
	return rawget(self, "_props")["@" .. k]
end
H.newNode = newNode

local Instance = {}
function Instance.new(className: string)
	local n = newNode(className, className)
	if className == "RemoteEvent" then
		rawget(n, "_props").FireClient = function(_, player, kind, payload)
			H.events[player] = H.events[player] or {}
			table.insert(H.events[player], { kind = kind, payload = payload })
		end
		rawget(n, "_props").FireAllClients = function() end
	end
	return n
end

---------------------------------------------------------------------------------------------
-- Strict JSON round trip (what DataStores accept)
---------------------------------------------------------------------------------------------
local function jsonCopy(v, path: string, depth: number)
	assert(depth < 100, "JSON: table nested too deep / cycle at " .. path)
	local t = type(v)
	if t == "number" then
		if v ~= v or v == math.huge or v == -math.huge then
			error("JSON: non-finite number at " .. path, 0)
		end
		return v
	elseif t == "string" or t == "boolean" or t == "nil" then
		return v
	elseif t == "table" then
		if getmetatable(v) ~= nil then
			error("JSON: userdata-like value at " .. path, 0)
		end
		local n = #v
		local count = 0
		for _ in v do
			count += 1
		end
		local out = {}
		if count == n then
			for i = 1, n do
				out[i] = jsonCopy(v[i], path .. "[" .. i .. "]", depth + 1)
			end
		else
			for k, x in v do
				if type(k) ~= "string" then
					error("JSON: mixed / non-string keys at " .. path .. " (key " .. tostring(k) .. ")", 0)
				end
				out[k] = jsonCopy(x, path .. "." .. k, depth + 1)
			end
		end
		return out
	end
	error("JSON: cannot encode " .. t .. " at " .. path, 0)
end
H.jsonCopy = function(v)
	return jsonCopy(v, "$", 0)
end

local HttpService = newNode("HttpService", "HttpService")
rawget(HttpService, "_props").HttpEnabled = false
rawget(HttpService, "_props").JSONEncode = function(_, v)
	return { __json = jsonCopy(v, "$", 0) }
end
rawget(HttpService, "_props").JSONDecode = function(_, s)
	return jsonCopy(s.__json, "$", 0)
end

---------------------------------------------------------------------------------------------
-- DataStores: latency + failure injection, strict JSON
---------------------------------------------------------------------------------------------
H.store = {} -- key -> stored value (already JSON-copied)
H.ds = { latency = 0.2, failNext = 0, failKeys = {}, writes = 0 }

local function dsCall(key: string)
	task.wait(H.ds.latency)
	if H.ds.failNext > 0 then
		H.ds.failNext -= 1
		error("502: API Services rejected request (injected)", 0)
	end
	for pat in H.ds.failKeys do
		if string.find(key, pat, 1, true) then
			error("502: injected failure for " .. key, 0)
		end
	end
end

local Store = {}
Store.__index = Store
function Store:GetAsync(key)
	dsCall(key)
	return if H.store[key] == nil then nil else jsonCopy(H.store[key], key, 0)
end
function Store:SetAsync(key, value)
	dsCall(key)
	H.store[key] = jsonCopy(value, key, 0)
	H.ds.writes += 1
end
function Store:UpdateAsync(key, fn)
	dsCall(key)
	local cur = if H.store[key] == nil then nil else jsonCopy(H.store[key], key, 0)
	local nxt = fn(cur)
	if nxt == nil then
		return nil
	end
	H.store[key] = jsonCopy(nxt, key, 0)
	H.ds.writes += 1
	return jsonCopy(H.store[key], key, 0)
end

local DataStoreService = newNode("DataStoreService", "DataStoreService")
rawget(DataStoreService, "_props").GetDataStore = function(_, name)
	return setmetatable({ name = name }, Store)
end

---------------------------------------------------------------------------------------------
-- Players
---------------------------------------------------------------------------------------------
local Players = newNode("Players", "Players")
local playerList = {}
rawget(Players, "_props").PlayerAdded = Signal()
rawget(Players, "_props").PlayerRemoving = Signal()
rawget(Players, "_props").GetPlayers = function()
	return table.clone(playerList)
end

function H.join(userId: number)
	local p = setmetatable({ UserId = userId, Name = "Player" .. userId, Parent = Players, kicked = nil }, {
		__tostring = function(self)
			return self.Name
		end,
	})
	function p:Kick(msg)
		self.kicked = msg or ""
		H.leave(self)
	end
	table.insert(playerList, p)
	H.events[p] = {}
	Players.PlayerAdded:Fire(p)
	return p
end

function H.leave(p)
	local i = table.find(playerList, p)
	if not i then
		return
	end
	table.remove(playerList, i)
	p.Parent = nil
	Players.PlayerRemoving:Fire(p)
end

---------------------------------------------------------------------------------------------
-- Other services
---------------------------------------------------------------------------------------------
local RunService = newNode("RunService", "RunService")
rawget(RunService, "_props").IsServer = function()
	return true
end
rawget(RunService, "_props").IsClient = function()
	return false
end
H.studio = true
rawget(RunService, "_props").IsStudio = function()
	return H.studio
end
rawget(RunService, "_props").IsRunning = function()
	return true
end

local TextService = newNode("TextService", "TextService")
rawget(TextService, "_props").FilterStringAsync = function(_, text)
	return {
		GetNonChatStringForBroadcastAsync = function()
			return text
		end,
	}
end

local ReplicatedStorage = newNode("ReplicatedStorage", "ReplicatedStorage")
local ServerScriptService = newNode("ServerScriptService", "ServerScriptService")
local ServerStorage = newNode("ServerStorage", "ServerStorage")

local services = {
	HttpService = HttpService,
	DataStoreService = DataStoreService,
	Players = Players,
	RunService = RunService,
	TextService = TextService,
	ReplicatedStorage = ReplicatedStorage,
	ServerScriptService = ServerScriptService,
	ServerStorage = ServerStorage,
}

H.closeFns = {}
local game = newNode("game", "DataModel")
rawget(game, "_props").GetService = function(_, name)
	return assert(services[name], "no fake service " .. tostring(name))
end
rawget(game, "_props").JobId = "job-A"
rawget(game, "_props").PlaceId = 1234
rawget(game, "_props").BindToClose = function(_, fn)
	table.insert(H.closeFns, fn)
end
H.game = game
H.services = services

local workspace = newNode("Workspace", "Workspace")
rawget(workspace, "_props").GetServerTimeNow = function()
	return EPOCH + now
end

H.env = {
	game = game,
	workspace = workspace,
	task = task,
	os = fakeOs,
	warn = warn,
	print = hprint,
	Random = Random,
	Instance = Instance,
	Vector3 = Vector3,
	CFrame = CFrame,
	Color3 = Color3,
}

---------------------------------------------------------------------------------------------
-- Module registry (filled in by the generated bundle)
---------------------------------------------------------------------------------------------
local loaded = {}
local function hrequire(node)
	if loaded[node] ~= nil then
		return loaded[node]
	end
	local fn = assert(rawget(node, "_props").__source, "not a ModuleScript: " .. tostring(node.Name))
	local result = fn(node, hrequire)
	loaded[node] = result
	return result
end
H.require = hrequire

function H.define(path: string, kind: string, fn)
	local parts = string.split(path, ".")
	local node = services[parts[1]]
	assert(node, "unknown root " .. parts[1])
	for i = 2, #parts do
		local c = rawget(node, "_children")[parts[i]]
		if not c then
			c = newNode(parts[i], if i == #parts then kind else "Folder")
			c.Parent = node
		end
		node = c
	end
	rawset(node, "_class", kind)
	rawget(node, "_props").__source = fn
	return node
end

function H.node(path: string)
	local parts = string.split(path, ".")
	local node = services[parts[1]]
	for i = 2, #parts do
		node = rawget(node, "_children")[parts[i]]
	end
	return node
end

return H
