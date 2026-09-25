-- Build a deliberately awkward mock rig: rotated 180 deg, scaled 1.1, random
-- joint frames and part centres. PoseDriver must still reproduce the solver.
local RigData = MODS.RigData
local G_TRUE = CFrame.Angles(0, math.pi, 0)
local S_TRUE = 1.1
local ORIGIN = Vector3.new(0.3, -0.2, 0.1)   -- where the authoring root pivot sits in HRP space
local refE = RigData.pivot.LowerTorso
local function toRig(p) return ORIGIN + G_TRUE:VectorToWorldSpace((p - refE) * S_TRUE) end

local seed = 7
local function rnd() seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648 end
local function rrot() return CFrame.Angles(rnd() * 6.28, rnd() * 6.28, rnd() * 6.28) end

local HRP_CF = CFrame.new(10, 3, -4) * CFrame.Angles(0, 0.7, 0)
local function IsA(self, c) return c == self.__class or (c == "BasePart" and self.__class == "Part") or (c == "Attachment" and self.__class == "Bone") end
local hrp = { Name = "HumanoidRootPart", CFrame = HRP_CF, __class = "Part", IsA = IsA }
local parts = { HumanoidRootPart = hrp }
local restRel = { [hrp] = CFrame.identity }
local motors = {}
for _, b in RigData.bones do
	local piv = toRig(RigData.pivot[b])
	local part = { Name = b, __class = "Part", IsA = IsA }
	parts[b] = part
	restRel[part] = CFrame.new(piv + Vector3.new(rnd() - 0.5, rnd() - 0.5, rnd() - 0.5)) * rrot()
end
for _, b in RigData.bones do
	local p0 = parts[RigData.parent[b]]
	local p1 = parts[b]
	local J = CFrame.new(toRig(RigData.pivot[b])) * rrot()
	local m = { Part0 = p0, Part1 = p1, C0 = restRel[p0]:Inverse() * J, C1 = restRel[p1]:Inverse() * J,
		Transform = CFrame.identity, Parent = true, __class = "Motor6D", IsA = IsA }
	table.insert(motors, m)
end
local model = {
	FindFirstChild = function(_, n) return parts[n] end,
	GetDescendants = function() return motors end,
}

local rig = assert(PoseDriver.bind(model))
local fails = 0
local function check(label, got, want, tol)
	local e = (got - want).Magnitude
	if e > tol then fails += 1; print(("FAIL %s err %.5f"):format(label, e)) end
	return e
end
check("scale", Vector3.new(rig.scale, 0, 0), Vector3.new(S_TRUE, 0, 0), 1e-6)

local pose = PoseDriver.newPose()
local worst = 0
for key, bones in REF do
	local clipName, frame = key:match("^(.-)@(%d+)$")
	local clip = PoseDriver.getClip(clipName)
	PoseDriver.sample(clip, tonumber(frame) / 30, false, pose)
	rig:apply(pose)
	-- forward kinematics exactly as the engine does it with the written Transforms
	local world = { [hrp] = HRP_CF }
	for _, b in RigData.bones do
		for _, m in motors do
			if m.Part1.Name == b then
				world[m.Part1] = world[m.Part0] * m.C0 * m.Transform * m.C1:Inverse()
				local pivotWorld = (world[m.Part0] * m.C0 * m.Transform).Position
				worst = math.max(worst, check(key .. " " .. b, pivotWorld, HRP_CF * toRig(bones[b]), 1e-3))
			end
		end
	end
	-- server path (no Transforms): pointWorld must agree with the engine path
	if not bones._BladeTip then continue end
	local tipServer = rig:pointWorld("BladeTip", HRP_CF)
	worst = math.max(worst, check(key .. " BladeTip", tipServer, HRP_CF * toRig(bones._BladeTip), 2e-3))
	local sh = world[parts.SwordHandle] * rig.points.BladeTip.offset -- engine: part frame * offset
	check(key .. " BladeTip engine==server", sh, tipServer, 1e-4)
end
print(("posedriver[Motor6D]: worst joint error %.6f studs, %d failures"):format(worst, fails))

-- ---- skinned rig: Bones inside the root part, random bone rolls, no Motor6Ds
local broot = { Name = "HumanoidRootPart", CFrame = HRP_CF, __class = "Part", IsA = IsA }
local bonesByName, blist = {}, {}
local function mkBone(name, parent, worldRest)   -- worldRest in HRP space
	local parentRest = parent == broot and CFrame.identity or parent.__rest
	local b = { Name = name, __class = "Bone", IsA = IsA, Parent = parent, Transform = CFrame.identity,
		CFrame = parentRest:Inverse() * worldRest, __rest = worldRest }
	bonesByName[name] = b
	table.insert(blist, b)
	return b
end
local rootB = mkBone("Root", broot, CFrame.new(toRig(Vector3.new(0, 0, 0))) * rrot())
local hrn = mkBone("HumanoidRootNode", rootB, CFrame.new(toRig(RigData.pivot.LowerTorso)) * rrot())
for _, b in RigData.bones do
	local pname = RigData.parent[b]
	local parent = pname == "HumanoidRootPart" and hrn or bonesByName[pname]
	mkBone(b, parent, CFrame.new(toRig(RigData.pivot[b])) * rrot())
end
local bmodel = {
	FindFirstChild = function(_, n) return n == "HumanoidRootPart" and broot or nil end,
	GetDescendants = function() return blist end,
}
local brig = assert(PoseDriver.bind(bmodel))
local bworst = 0
for key, bones in REF do
	local clipName, frame = key:match("^(.-)@(%d+)$")
	PoseDriver.sample(PoseDriver.getClip(clipName), tonumber(frame) / 30, false, pose)
	brig:apply(pose)
	local world = {}
	local function W(b)
		if b == broot then return HRP_CF end
		if not world[b] then world[b] = W(b.Parent) * b.CFrame * b.Transform end
		return world[b]
	end
	for _, name in RigData.bones do
		bworst = math.max(bworst, check("bone " .. key .. " " .. name, W(bonesByName[name]).Position, HRP_CF * toRig(bones[name]), 1e-3))
	end
end
print(("posedriver[Bone]: worst joint error %.6f studs, %d failures"):format(bworst, fails))
-- loop sampling / blend sanity
local idle = PoseDriver.getClip("Sword_Idle")
local a = PoseDriver.sample(idle, 0, true, PoseDriver.newPose())
local b = PoseDriver.sample(idle, idle.length, true, PoseDriver.newPose())
check("idle loop seam", a.off, b.off, 1e-4)
print(fails == 0 and "ALL PASS" or "FAIL")
