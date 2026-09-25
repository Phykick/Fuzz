--!nonstrict
-- Small geometry helpers for server-side hit detection.
local Geometry = {}

-- Does segment a->b intersect the oriented box (cf, size)? Returns the entry
-- fraction t (0..1) or nil. Slab test in the box's local space.
function Geometry.segmentBox(a: Vector3, b: Vector3, cf: CFrame, size: Vector3, pad: number?): number?
	local la = cf:PointToObjectSpace(a)
	local lb = cf:PointToObjectSpace(b)
	local d = lb - la
	local h = size * 0.5 + Vector3.one * (pad or 0)
	local tmin, tmax = 0, 1
	for _, axis in { "X", "Y", "Z" } do
		local o, dir, e = la[axis], d[axis], h[axis]
		if math.abs(dir) < 1e-9 then
			if o < -e or o > e then
				return nil
			end
		else
			local t1 = (-e - o) / dir
			local t2 = (e - o) / dir
			if t1 > t2 then
				t1, t2 = t2, t1
			end
			tmin = math.max(tmin, t1)
			tmax = math.min(tmax, t2)
			if tmin > tmax then
				return nil
			end
		end
	end
	return tmin
end

-- Horizontal angle (degrees) between a model's facing and the direction to `point`.
function Geometry.facingAngle(rootCFrame: CFrame, point: Vector3): number
	local look = rootCFrame.LookVector
	local to = point - rootCFrame.Position
	local a = Vector3.new(look.X, 0, look.Z)
	local b = Vector3.new(to.X, 0, to.Z)
	if a.Magnitude < 1e-6 or b.Magnitude < 1e-6 then
		return 0
	end
	return math.deg(math.acos(math.clamp(a.Unit:Dot(b.Unit), -1, 1)))
end

-- Random direction within `deg` degrees of `dir`.
function Geometry.spread(dir: Vector3, deg: number, rng: Random): Vector3
	if deg <= 0 then
		return dir.Unit
	end
	local cf = CFrame.lookAt(Vector3.zero, dir)
	local r = math.rad(deg) * math.sqrt(rng:NextNumber())
	local a = rng:NextNumber() * math.pi * 2
	return (cf * CFrame.Angles(math.cos(a) * r, math.sin(a) * r, 0)).LookVector
end

return Geometry
