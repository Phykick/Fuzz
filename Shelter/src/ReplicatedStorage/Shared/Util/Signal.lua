--!strict
-- Minimal synchronous signal.
local Signal = {}
Signal.__index = Signal

export type Connection = { Disconnect: (Connection) -> (), Connected: boolean }

function Signal.new()
	return setmetatable({ _handlers = {} :: { [any]: (...any) -> () } }, Signal)
end

function Signal:Connect(fn: (...any) -> ())
	local key = {}
	self._handlers[key] = fn
	local conn = { Connected = true }
	function conn.Disconnect(c)
		c.Connected = false
		self._handlers[key] = nil
	end
	return conn
end

function Signal:Once(fn: (...any) -> ())
	local conn
	conn = self:Connect(function(...)
		conn:Disconnect()
		fn(...)
	end)
	return conn
end

function Signal:Fire(...)
	for _, fn in self._handlers do
		task.spawn(fn, ...)
	end
end

function Signal:Wait()
	local thread = coroutine.running()
	self:Once(function(...)
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

return Signal
