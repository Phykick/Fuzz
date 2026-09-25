-- Minimal Vector3 / CFrame stand-ins so shared combat modules can be unit-tested
-- with the stand-alone `luau` CLI (math only, no engine).
local Vector3 = {}
local V = {}
V.__index = function(v, k)
	if k == "X" then return v[1] elseif k == "Y" then return v[2] elseif k == "Z" then return v[3]
	elseif k == "Magnitude" then return math.sqrt(v[1]^2 + v[2]^2 + v[3]^2)
	elseif k == "Unit" then local m = math.sqrt(v[1]^2 + v[2]^2 + v[3]^2); return Vector3.new(v[1]/m, v[2]/m, v[3]/m)
	end
	return V[k]
end
function Vector3.new(x, y, z) return setmetatable({ x or 0, y or 0, z or 0 }, V) end
Vector3.zero = Vector3.new(0, 0, 0)
V.__add = function(a, b) return Vector3.new(a[1]+b[1], a[2]+b[2], a[3]+b[3]) end
V.__sub = function(a, b) return Vector3.new(a[1]-b[1], a[2]-b[2], a[3]-b[3]) end
V.__unm = function(a) return Vector3.new(-a[1], -a[2], -a[3]) end
V.__mul = function(a, b)
	if type(a) == "number" then return Vector3.new(a*b[1], a*b[2], a*b[3]) end
	if type(b) == "number" then return Vector3.new(a[1]*b, a[2]*b, a[3]*b) end
	return Vector3.new(a[1]*b[1], a[2]*b[2], a[3]*b[3])
end
V.__div = function(a, b) return Vector3.new(a[1]/b, a[2]/b, a[3]/b) end
function V.Dot(a, b) return a[1]*b[1] + a[2]*b[2] + a[3]*b[3] end
function V.Cross(a, b) return Vector3.new(a[2]*b[3]-a[3]*b[2], a[3]*b[1]-a[1]*b[3], a[1]*b[2]-a[2]*b[1]) end
function V.Lerp(a, b, t) return a + (b - a) * t end

local CFrame = {}
local C = {}
C.__index = function(c, k)
	if k == "Position" then return c.p end
	if k == "Rotation" then return setmetatable({ p = Vector3.zero, r = c.r }, C) end
	return C[k]
end
local function mk(p, r) return setmetatable({ p = p, r = r }, C) end
local I = { {1,0,0}, {0,1,0}, {0,0,1} }
local function mm(a, b)
	local o = {}
	for i = 1, 3 do o[i] = {} for j = 1, 3 do o[i][j] = a[i][1]*b[1][j] + a[i][2]*b[2][j] + a[i][3]*b[3][j] end end
	return o
end
local function mv(a, v) return Vector3.new(a[1][1]*v[1]+a[1][2]*v[2]+a[1][3]*v[3], a[2][1]*v[1]+a[2][2]*v[2]+a[2][3]*v[3], a[3][1]*v[1]+a[3][2]*v[2]+a[3][3]*v[3]) end
local function tr(a) return { {a[1][1],a[2][1],a[3][1]}, {a[1][2],a[2][2],a[3][2]}, {a[1][3],a[2][3],a[3][3]} } end
local function q2m(x, y, z, w)
	local n = math.sqrt(x*x+y*y+z*z+w*w); x, y, z, w = x/n, y/n, z/n, w/n
	return { {1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w)}, {2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w)}, {2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y)} }
end
local function m2q(m)
	local t = m[1][1] + m[2][2] + m[3][3]
	local x, y, z, w
	if t > 0 then local s = math.sqrt(t + 1) * 2; w = 0.25*s; x = (m[3][2]-m[2][3])/s; y = (m[1][3]-m[3][1])/s; z = (m[2][1]-m[1][2])/s
	elseif m[1][1] > m[2][2] and m[1][1] > m[3][3] then local s = math.sqrt(1+m[1][1]-m[2][2]-m[3][3])*2; w = (m[3][2]-m[2][3])/s; x = 0.25*s; y = (m[1][2]+m[2][1])/s; z = (m[1][3]+m[3][1])/s
	elseif m[2][2] > m[3][3] then local s = math.sqrt(1+m[2][2]-m[1][1]-m[3][3])*2; w = (m[1][3]-m[3][1])/s; x = (m[1][2]+m[2][1])/s; y = 0.25*s; z = (m[2][3]+m[3][2])/s
	else local s = math.sqrt(1+m[3][3]-m[1][1]-m[2][2])*2; w = (m[2][1]-m[1][2])/s; x = (m[1][3]+m[3][1])/s; y = (m[2][3]+m[3][2])/s; z = 0.25*s end
	return x, y, z, w
end
function CFrame.new(a, b, c, qx, qy, qz, qw)
	if a == nil then return mk(Vector3.zero, I) end
	if type(a) == "table" then return mk(a, I) end
	if qx ~= nil then return mk(Vector3.new(a, b, c), q2m(qx, qy, qz, qw)) end
	return mk(Vector3.new(a, b, c), I)
end
CFrame.identity = CFrame.new()
function CFrame.fromMatrix(p, x, y, z)
	return mk(p, { {x[1], y[1], z[1]}, {x[2], y[2], z[2]}, {x[3], y[3], z[3]} })
end
function CFrame.Angles(rx, ry, rz)
	local function R(ax, a)
		local c, s = math.cos(a), math.sin(a)
		if ax == 1 then return { {1,0,0},{0,c,-s},{0,s,c} } elseif ax == 2 then return { {c,0,s},{0,1,0},{-s,0,c} } end
		return { {c,-s,0},{s,c,0},{0,0,1} }
	end
	return mk(Vector3.zero, mm(mm(R(1, rx), R(2, ry)), R(3, rz)))
end
C.__mul = function(a, b)
	if getmetatable(b) == C then return mk(a.p + mv(a.r, b.p), mm(a.r, b.r)) end
	return a.p + mv(a.r, b)
end
function C.Inverse(a) local rt = tr(a.r); return mk(-mv(rt, a.p), rt) end
function C.PointToObjectSpace(a, v) return mv(tr(a.r), v - a.p) end
function C.VectorToWorldSpace(a, v) return mv(a.r, v) end
function C.ToObjectSpace(a, b) return a:Inverse() * b end
function C.Lerp(a, b, t)
	local x0, y0, z0, w0 = m2q(a.r)
	local x1, y1, z1, w1 = m2q(b.r)
	local d = x0*x1 + y0*y1 + z0*z1 + w0*w1
	if d < 0 then x1, y1, z1, w1, d = -x1, -y1, -z1, -w1, -d end
	local k0, k1
	if d > 0.9995 then k0, k1 = 1 - t, t else local th = math.acos(d); local s = math.sin(th); k0, k1 = math.sin((1-t)*th)/s, math.sin(t*th)/s end
	return mk(a.p:Lerp(b.p, t), q2m(k0*x0+k1*x1, k0*y0+k1*y1, k0*z0+k1*z1, k0*w0+k1*w1))
end
return { Vector3 = Vector3, CFrame = CFrame }
