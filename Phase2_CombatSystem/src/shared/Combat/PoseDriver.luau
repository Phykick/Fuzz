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
--
-- Studio's importer can produce three kinds of joints. All are driven the
-- same way:  frame(moved) = frame(parent) * c0 * Transform * c1^-1
--   Motor6D             parent = Part0, moved = Part1, c0/c1 = C0/C1
--   AnimationConstraint parent = Attachment0's part, moved = Attachment1's part
--   Bone (skinned rig)  parent = Bone.Parent, moved = the Bone, c0 = Bone.CFrame
----------------------------------------------------------------------------
local REQUIRED = { "LowerTorso", "UpperTorso", "Head", "LeftUpperArm", "RightUpperArm", "LeftHand", "RightHand" }

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

-- Human-readable summary of a model's joint structure (for error reports).
function PoseDriver.describe(model: Model): string
	local counts, bones, motors, parts = {}, {}, {}, {}
	for _, d in model:GetDescendants() do
		counts[d.ClassName] = (counts[d.ClassName] or 0) + 1
		if d:IsA("Bone") and #bones < 30 then
			table.insert(bones, d.Name)
		elseif (d:IsA("Motor6D") or d:IsA("Weld") or d:IsA("WeldConstraint")) and #motors < 20 then
			local p0 = d.Part0 and d.Part0.Name or "nil"
			local p1 = d.Part1 and d.Part1.Name or "nil"
			table.insert(motors, d.ClassName .. "(" .. p0 .. "->" .. p1 .. ")")
		elseif d:IsA("BasePart") and #parts < 30 then
			table.insert(parts, d.Name)
		end
	end
	local c = {}
	for k, v in counts do
		if v > 0 and (k == "Motor6D" or k == "Bone" or k == "AnimationConstraint" or k == "MeshPart" or k == "Part"
			or k == "Weld" or k == "WeldConstraint" or k == "Humanoid") then
			table.insert(c, k .. "=" .. v)
		end
	end
	return "classes{" .. table.concat(c, ", ") .. "} parts{" .. table.concat(parts, ", ") .. "} bones{"
		.. table.concat(bones, ", ") .. "} joints{" .. table.concat(motors, ", ") .. "}"
end

function PoseDriver.bind(model: Model)
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return nil, "no HumanoidRootPart"
	end
	local motors, anims, bones = {}, {}, {}
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") and d.Part0 and d.Part1 then
			local n = PoseDriver.boneName(d.Part1.Name)
			if BONE_INDEX[n] and not motors[n] then
				motors[n] = d
			end
		elseif d:IsA("AnimationConstraint") and d.Attachment0 and d.Attachment1
			and d.Attachment0.Parent and d.Attachment1.Parent then
			local n = PoseDriver.boneName(d.Attachment1.Parent.Name)
			if BONE_INDEX[n] and not anims[n] then
				anims[n] = d
			end
		elseif d:IsA("Bone") then
			local n = PoseDriver.boneName(d.Name)
			if BONE_INDEX[n] and not bones[n] then
				bones[n] = d
			end
		end
	end

	-- one node per bone: Motor6D > AnimationConstraint > Bone
	local nodes, byMoved = {}, {}
	for _, b in BONES do
		local node
		if motors[b] then
			local m = motors[b]
			node = { kind = "Motor6D", obj = m, parent = m.Part0, moved = m.Part1, c0 = m.C0, c1 = m.C1 }
		elseif anims[b] then
			local a = anims[b]
			node = { kind = "AnimationConstraint", obj = a, parent = a.Attachment0.Parent, moved = a.Attachment1.Parent,
				c0 = a.Attachment0.CFrame, c1 = a.Attachment1.CFrame }
		elseif bones[b] then
			local bn = bones[b]
			node = { kind = "Bone", obj = bn, parent = bn.Parent, moved = bn, c0 = bn.CFrame, c1 = CFrame.identity }
		end
		if node then
			node.bone = b
			nodes[b] = node
			byMoved[node.moved] = node
		end
	end
	local missing = {}
	for _, b in REQUIRED do
		if not nodes[b] then
			table.insert(missing, b)
		end
	end
	if #missing > 0 then
		return nil, "no Motor6D / AnimationConstraint / Bone for " .. table.concat(missing, ", ")
			.. ". Rig structure: " .. PoseDriver.describe(model)
	end

	-- rest frames relative to the HumanoidRootPart
	local restCache = { [hrp] = CFrame.identity }
	local function restOf(inst)
		local r = restCache[inst]
		if r then
			return r
		end
		local node = byMoved[inst]
		if node then
			r = restOf(node.parent) * node.c0 * node.c1:Inverse()
		elseif inst:IsA("BasePart") then
			r = hrp.CFrame:ToObjectSpace(inst.CFrame)
		elseif inst:IsA("Attachment") then -- Bones are Attachments
			r = restOf(inst.Parent) * inst.CFrame
		else
			r = CFrame.identity
		end
		restCache[inst] = r
		return r
	end
	local restFrame, pivot = {}, {}
	for b, node in nodes do
		restFrame[b] = restOf(node.moved)
		pivot[b] = (restOf(node.parent) * node.c0).Position
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
		nodes = nodes,
		byMoved = byMoved,
		restOf = restOf,
		restFrame = restFrame,
		pivot = pivot,
		G = G,
		Ginv = G:Inverse(),
		scale = s,
		refE = P.LowerTorso,
		refR = pivot.LowerTorso,
		posed = {}, -- [boneName] = CFrame (HRP space)
		posedInst = {},
		points = {},
		hurt = {},
		kinds = {},
	}, PoseDriver)
	for b, node in nodes do
		self.kinds[node.kind] = (self.kinds[node.kind] or 0) + 1
	end

	-- reference points (blade, bow nocks, fingers) ride on their bone
	local FALLBACK = { SwordHandle = "RightHand", BowHandle = "LeftHand" }
	for name, pt in RigData.points do
		local bone = pt.bone
		local pr
		if nodes[bone] then
			pr = pivot[bone] + G:VectorToWorldSpace((pt.pos - P[bone]) * s)
		elseif FALLBACK[bone] and nodes[FALLBACK[bone]] then
			bone = FALLBACK[bone] -- weapon imported without its own joint
			pr = self:mapPoint(pt.pos)
		end
		if pr then
			self.points[name] = { bone = bone, offset = restFrame[bone]:PointToObjectSpace(pr) }
		end
	end

	-- hurtboxes from the authoring body (independent of how parts were imported)
	for b, hb in RigData.hurtboxes do
		if nodes[b] then
			local boxRest = CFrame.new(self:mapPoint(hb.center)) * G
			table.insert(self.hurt, { name = b, offset = restFrame[b]:ToObjectSpace(boxRest), size = hb.size * s })
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

-- posed frame of any instance in the rig (falls back to its rest frame)
function PoseDriver:_posedOf(inst)
	local f = self.posedInst[inst]
	if f then
		return f
	end
	if inst ~= self.hrp and not self.byMoved[inst] and inst:IsA("Attachment") and inst.Parent then
		return self:_posedOf(inst.Parent) * inst.CFrame -- e.g. a helper bone inside a moving bone
	end
	return self.restOf(inst)
end

-- Compute posed frames (HRP space) for `pose`. Returns self.posed (by bone name).
function PoseDriver:solve(pose)
	local posed, posedInst = self.posed, self.posedInst
	table.clear(posedInst)
	local G, Ginv, s = self.G, self.Ginv, self.scale
	for i, b in BONES do
		local node = self.nodes[b]
		if node then
			local P0 = self:_posedOf(node.parent)
			local Jr = self.pivot[b]
			local Jp
			if b == "LowerTorso" then
				Jp = Jr + G:VectorToWorldSpace(pose.off * s)
			else
				Jp = P0 * self.restOf(node.parent):PointToObjectSpace(Jr)
			end
			local D = G * pose.rots[i] * Ginv
			local f = CFrame.new(Jp) * D * CFrame.new(-Jr) * self.restFrame[b]
			posed[b] = f
			posedInst[node.moved] = f
		end
	end
	return posed
end

-- Write the joints' Transform for `pose` (client side, every frame).
function PoseDriver:apply(pose)
	self:solve(pose)
	for _, b in BONES do
		local node = self.nodes[b]
		if node and node.obj.Parent then
			local P0 = self:_posedOf(node.parent)
			node.obj.Transform = node.c0:Inverse() * P0:Inverse() * self.posed[b] * node.c1
		end
	end
end

-- Clear Transforms (e.g. on death so ragdoll/physics can take over).
function PoseDriver:reset()
	for _, node in self.nodes do
		if node.obj.Parent then
			node.obj.Transform = CFrame.identity
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
	local f = self.posed[pt.bone] or self.restFrame[pt.bone]
	return (rootCFrame or self.hrp.CFrame) * f * pt.offset
end

-- World frame of a bone from the last solve().
function PoseDriver:boneWorld(bone: string, rootCFrame: CFrame?): CFrame?
	local f = self.posed[bone] or self.restFrame[bone]
	return f and (rootCFrame or self.hrp.CFrame) * f
end

-- Posed hurtboxes in world space: { {name, cf, size}, ... } (fills `out`).
function PoseDriver:hurtboxes(rootCFrame: CFrame?, out)
	out = out or {}
	table.clear(out)
	local root = rootCFrame or self.hrp.CFrame
	for _, h in self.hurt do
		local f = self.posed[h.name] or self.restFrame[h.name]
		table.insert(out, { name = h.name, cf = root * f * h.offset, size = h.size })
	end
	return out
end

-- The BasePart that visibly moves with a bone (nil for skinned/Bone rigs).
function PoseDriver:movingPart(bone: string)
	local node = self.nodes[bone]
	if node and node.kind ~= "Bone" and node.moved:IsA("BasePart") then
		return node.moved
	end
	return nil
end

return PoseDriver
