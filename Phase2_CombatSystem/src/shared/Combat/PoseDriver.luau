--!nonstrict
--[[
	PoseDriver: plays the baked combat animations by writing Motor6D.Transform.

	No Animation assets, no publishing: the animation data ships as ModuleScripts
	(AnimData/*). Each frame stores every bone's world-space delta rotation from
	rest (+ pelvis offset). At bind time we read the live rig's own C0/C1, so any
	importer convention (joint frames, part centres, facing, scale) is handled:

	    posed(part) = Pivot' * D * Pivot^-1 * rest(part)      (HRP space)
	    Transform   = C0^-1 * posed(Part0)^-1 * posed(Part1) * C1

	The same math runs on the server (hitboxes, weapon points) without touching
	the parts, and on clients (visuals) where Transforms are applied.
]]

local Combat = script.Parent
local RigData = require(Combat.RigData)
local Clips = require(Combat.Clips)
local AnimFolder = Combat.AnimData

local PoseDriver = {}
PoseDriver.__index = PoseDriver

local BONES = RigData.bones
local NB = #BONES
local FPS = Clips.fps
local BONE_INDEX = {}
for i, b in BONES do
	BONE_INDEX[b] = i
end
PoseDriver.BONES = BONES
PoseDriver.BONE_INDEX = BONE_INDEX

----------------------------------------------------------------------------
-- clip data
----------------------------------------------------------------------------
local cache = {}

function PoseDriver.getClip(name: string)
	local c = cache[name]
	if c then
		return c
	end
	local meta = Clips.clips[name]
	assert(meta, "PoseDriver: unknown clip " .. tostring(name))
	local mod = AnimFolder:FindFirstChild(name)
	assert(mod, "PoseDriver: missing AnimData/" .. name)
	local raw = require(mod)
	local d = raw.data
	local stride = NB * 4 + 3
	local frames = table.create(raw.frames)
	for f = 1, raw.frames do
		local base = (f - 1) * stride
		local rots = table.create(NB)
		for b = 1, NB do
			local i = base + (b - 1) * 4
			rots[b] = CFrame.new(0, 0, 0, d[i + 1], d[i + 2], d[i + 3], d[i + 4])
		end
		local o = base + NB * 4
		frames[f] = { rots = rots, off = Vector3.new(d[o + 1], d[o + 2], d[o + 3]) }
	end
	local props
	if raw.props then
		props = table.create(raw.frames)
		local p = raw.props
		for f = 1, raw.frames do
			local i = (f - 1) * 11
			props[f] = {
				arrow = p[i + 1], -- 0 none, 1 in the draw hand, 2 nocked on the string
				held = p[i + 2] > 0.5, -- fingers pulling the string
				nock = Vector3.new(p[i + 3], p[i + 4], p[i + 5]),
				dir = Vector3.new(p[i + 6], p[i + 7], p[i + 8]),
				string = Vector3.new(p[i + 9], p[i + 10], p[i + 11]),
			}
		end
	end
	c = { name = name, meta = meta, frames = frames, n = raw.frames, props = props, length = meta.length }
	cache[name] = c
	return c
end

function PoseDriver.clipLength(name: string): number
	return Clips.clips[name].length
end

function PoseDriver.marker(name: string, marker: string): number?
	local m = Clips.clips[name]
	return m and m.markers[marker]
end

-- A pose is { rots = {CFrame x NB}, off = Vector3 } in authoring space.
function PoseDriver.newPose()
	local rots = table.create(NB, CFrame.identity)
	return { rots = rots, off = Vector3.zero }
end

local function frameAt(clip, t: number, loop: boolean)
	local len = clip.length
	if loop and len > 0 then
		t = t % len
	else
		t = math.clamp(t, 0, len)
	end
	local x = t * FPS
	local i = math.floor(x)
	local a = x - i
	local i0 = math.clamp(i + 1, 1, clip.n)
	local i1 = math.clamp(i + 2, 1, clip.n)
	return clip.frames[i0], clip.frames[i1], a, i0
end

-- Sample `clip` at time t into `out` (allocation free apart from CFrame math).
function PoseDriver.sample(clip, t: number, loop: boolean, out)
	local f0, f1, a = frameAt(clip, t, loop)
	local r0, r1, ro = f0.rots, f1.rots, out.rots
	for b = 1, NB do
		ro[b] = r0[b]:Lerp(r1[b], a)
	end
	out.off = f0.off:Lerp(f1.off, a)
	return out
end

function PoseDriver.sampleProps(clip, t: number, loop: boolean)
	if not clip.props then
		return nil
	end
	local _, _, a, i0 = frameAt(clip, t, loop)
	local p0 = clip.props[i0]
	local p1 = clip.props[math.min(i0 + 1, clip.n)]
	return {
		arrow = p0.arrow,
		held = p0.held,
		nock = p0.nock:Lerp(p1.nock, a),
		dir = p0.dir:Lerp(p1.dir, a).Unit,
		string = p0.string:Lerp(p1.string, a),
	}
end

-- out = lerp(a, b, w) on bones in `mask` (nil = all); other bones copy `a`.
function PoseDriver.blend(a, b, w: number, mask, out)
	local ra, rb, ro = a.rots, b.rots, out.rots
	for i = 1, NB do
		if mask == nil or mask[BONES[i]] then
			ro[i] = ra[i]:Lerp(rb[i], w)
		else
			ro[i] = ra[i]
		end
	end
	if mask == nil then
		out.off = a.off:Lerp(b.off, w)
	else
		out.off = a.off
	end
	return out
end

-- Weighted sum of several poses (weights must sum to 1). Used for locomotion.
function PoseDriver.mix(poses, weights, out)
	local first = true
	local acc = 0
	for k, p in poses do
		local w = weights[k]
		if w and w > 1e-4 then
			if first then
				for i = 1, NB do
					out.rots[i] = p.rots[i]
				end
				out.off = p.off
				acc = w
				first = false
			else
				acc += w
				local t = w / acc
				for i = 1, NB do
					out.rots[i] = out.rots[i]:Lerp(p.rots[i], t)
				end
				out.off = out.off:Lerp(p.off, t)
			end
		end
	end
	return out
end

----------------------------------------------------------------------------
-- rig binding
----------------------------------------------------------------------------
local function basis(a: Vector3, b: Vector3): CFrame
	local x = a.Unit
	local z = x:Cross(b).Unit
	local y = z:Cross(x)
	return CFrame.fromMatrix(Vector3.zero, x, y, z)
end

-- Importers sometimes keep the "_Geo" mesh suffix on part names.
function PoseDriver.boneName(name: string): string
	return (string.gsub(name, "_Geo$", ""))
end

function PoseDriver.bind(model: Model)
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return nil, "no HumanoidRootPart"
	end
	local joints = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") and d.Part1 then
			local name = PoseDriver.boneName(d.Part1.Name)
			if BONE_INDEX[name] then
				joints[name] = d
			end
		end
	end
	for _, b in { "LowerTorso", "UpperTorso", "Head", "RightUpperArm", "LeftUpperArm" } do
		if not joints[b] then
			return nil, "missing joint for " .. b
		end
	end

	-- rest-pose part frames relative to the HumanoidRootPart, from the joint chain
	local restRel = { [hrp] = CFrame.identity }
	local pivot = {}
	for _, b in BONES do
		local m = joints[b]
		if m then
			local p0 = m.Part0
			local r0 = restRel[p0] or hrp.CFrame:ToObjectSpace(p0.CFrame)
			restRel[p0] = r0
			restRel[m.Part1] = r0 * m.C0 * m.C1:Inverse()
			pivot[b] = (r0 * m.C0).Position
		end
	end

	-- authoring space -> this rig: rotation G and scale s from shoulder/neck pivots
	local P = RigData.pivot
	local e1 = P.RightUpperArm - P.LeftUpperArm
	local e2 = P.Head - P.LowerTorso
	local r1 = pivot.RightUpperArm - pivot.LeftUpperArm
	local r2 = pivot.Head - pivot.LowerTorso
	local G = basis(r1, r2) * basis(e1, e2):Inverse()
	local s = r1.Magnitude / e1.Magnitude

	local self = setmetatable({
		model = model,
		hrp = hrp,
		joints = joints,
		restRel = restRel,
		pivot = pivot,
		G = G,
		Ginv = G:Inverse(),
		scale = s,
		refE = P.LowerTorso,
		refR = pivot.LowerTorso,
		posed = {},
		points = {},
	}, PoseDriver)

	local FALLBACK = { SwordHandle = "RightHand", BowHandle = "LeftHand" }
	for name, pt in RigData.points do
		local m = joints[pt.bone]
		if m then
			local pr = pivot[pt.bone] + G:VectorToWorldSpace((pt.pos - P[pt.bone]) * s)
			self.points[name] = { part = m.Part1, offset = restRel[m.Part1]:PointToObjectSpace(pr) }
		elseif FALLBACK[pt.bone] and joints[FALLBACK[pt.bone]] then
			-- weapon imported without its own joint: ride on the hand instead
			local hm = joints[FALLBACK[pt.bone]]
			self.points[name] = { part = hm.Part1, offset = restRel[hm.Part1]:PointToObjectSpace(self:mapPoint(pt.pos)) }
		end
	end
	return self
end

-- Authoring-space point (armature space) -> rig HRP space.
function PoseDriver:mapPoint(p: Vector3): Vector3
	return self.refR + self.G:VectorToWorldSpace((p - self.refE) * self.scale)
end

function PoseDriver:mapVector(v: Vector3): Vector3
	return self.G:VectorToWorldSpace(v)
end

-- Compute posed part frames (HRP space) for `pose`. Returns self.posed.
function PoseDriver:solve(pose)
	local posed = self.posed
	local restRel, pivot, joints = self.restRel, self.pivot, self.joints
	local G, Ginv = self.G, self.Ginv
	posed[self.hrp] = CFrame.identity
	for i, b in BONES do
		local m = joints[b]
		if m then
			local p0 = m.Part0
			local P0 = posed[p0] or restRel[p0]
			local Jr = pivot[b]
			local Jp
			if b == "LowerTorso" then
				Jp = Jr + G:VectorToWorldSpace(pose.off * self.scale)
			else
				Jp = P0 * restRel[p0]:PointToObjectSpace(Jr)
			end
			local D = G * pose.rots[i] * Ginv
			posed[m.Part1] = CFrame.new(Jp) * D * CFrame.new(-Jr) * restRel[m.Part1]
		end
	end
	return posed
end

-- Write Motor6D.Transform for `pose` (client side, every frame).
function PoseDriver:apply(pose)
	local posed = self:solve(pose)
	local restRel = self.restRel
	for _, b in BONES do
		local m = self.joints[b]
		if m and m.Parent then
			local P0 = posed[m.Part0] or restRel[m.Part0]
			local P1 = posed[m.Part1]
			m.Transform = m.C0:Inverse() * P0:Inverse() * P1 * m.C1
		end
	end
end

-- Clear Transforms (e.g. on death so ragdoll/physics can take over).
function PoseDriver:reset()
	for _, m in self.joints do
		if m.Parent then
			m.Transform = CFrame.identity
		end
	end
end

-- World position of a named reference point (BladeTip, BowArrowRest, ...)
-- using the last solve() (works on the server without Transforms applied).
function PoseDriver:pointWorld(name: string, rootCFrame: CFrame?): Vector3?
	local pt = self.points[name]
	if not pt then
		return nil
	end
	local posed = self.posed[pt.part] or self.restRel[pt.part]
	return (rootCFrame or self.hrp.CFrame) * posed * pt.offset
end

-- World CFrame of a part from the last solve().
function PoseDriver:partWorld(part: BasePart, rootCFrame: CFrame?): CFrame
	local posed = self.posed[part] or self.restRel[part] or CFrame.identity
	return (rootCFrame or self.hrp.CFrame) * posed
end

return PoseDriver
