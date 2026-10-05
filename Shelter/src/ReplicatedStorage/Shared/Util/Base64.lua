--!strict
-- Base64 → buffer decoder used to unpack Blender-exported mesh data.
local Base64 = {}

local lookup: { [number]: number } = {}
local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
for i = 1, 64 do
	lookup[string.byte(alphabet, i)] = i - 1
end
lookup[61] = 0 -- '=' padding

function Base64.decode(s: string): buffer
	local len = #s
	local pad = 0
	if string.byte(s, len) == 61 then
		pad += 1
	end
	if string.byte(s, len - 1) == 61 then
		pad += 1
	end
	local outLen = (len // 4) * 3 - pad
	local out = buffer.create(outLen)
	local o = 0
	for i = 1, len, 4 do
		local a, b, c, d = string.byte(s, i, i + 3)
		local n = lookup[a] * 262144 + lookup[b] * 4096 + lookup[c] * 64 + lookup[d]
		if o < outLen then
			buffer.writeu8(out, o, n // 65536)
		end
		if o + 1 < outLen then
			buffer.writeu8(out, o + 1, (n // 256) % 256)
		end
		if o + 2 < outLen then
			buffer.writeu8(out, o + 2, n % 256)
		end
		o += 3
	end
	return out
end

return Base64
