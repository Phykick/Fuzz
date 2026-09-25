-- Rig imported as separate parts that are only welded (no Motor6D, no Bones).
-- RigRepair must build joints so the animation reproduces the solver.
local RigData = MODS.RigData
local G_TRUE = CFrame.Angles(0, math.pi, 0)
local S_TRUE = 0.9
local ORIGIN = Vector3.new(0.1, -0.35, 0)
local refE = RigData.pivot.LowerTorso
local function toRig(p) return ORIGIN + G_TRUE:VectorToWorldSpace((p - refE) * S_TRUE) end
local HRP_CF = CFrame.new(-5, 3, 8) * CFrame.Angles(0, -1.2, 0)

local list = {}
local function IsA(self, c)
	return c == self.ClassName or (c == "BasePart" and self.ClassName == "MeshPart")
end
local function add(obj) table.insert(list, obj); return obj end
local function destroy(self)
	for i, o in list do if o == self then table.remove(list, i) break end end
end
local hrp = add({ Name = "HumanoidRootPart", ClassName = "MeshPart", IsA = IsA, CFrame = HRP_CF, Position = HRP_CF.Position })
local parts = {}
for b, hb in RigData.hurtboxes do
	-- MeshPart origin = bounding-box centre (what Studio's importer produces), axis aligned
	local cf = HRP_CF * CFrame.new(toRig(hb.center)) * G_TRUE
	parts[b] = add({ Name = b, ClassName = "MeshPart", IsA = IsA, CFrame = cf, Position = cf.Position })
end
for b in parts do
	add({ Name = "Weld", ClassName = "WeldConstraint", IsA = IsA, Part0 = hrp, Part1 = parts[b], Destroy = destroy })
end
Instance = { new = function(class)
	local o = { ClassName = class, IsA = IsA, Transform = CFrame.identity }
	return setmetatable(o, { __newindex = function(t, k, v)
		rawset(t, k, v)
		if k == "Parent" then add(t) end
	end })
end }
local model = {
	FindFirstChild = function(_, n) return n == "HumanoidRootPart" and hrp or nil end,
	GetDescendants = function() local c = {} for i, o in list do c[i] = o end return c end,
}
local ok, how = RigRepair.ensure(model)
print("rigrepair:", ok, how)
local rig = assert(PoseDriver.bind(model))
local pose = PoseDriver.newPose()
local worst, fails = 0, 0
for key, bones in REF do
	local clipName, frame = key:match("^(.-)@(%d+)$")
	PoseDriver.sample(PoseDriver.getClip(clipName), tonumber(frame) / 30, false, pose)
	rig:apply(pose)
	local world = { [hrp] = HRP_CF }
	for _, b in RigData.bones do
		local node = rig.nodes[b]
		if node then
			local m = node.obj
			world[m.Part1] = world[m.Part0] * m.C0 * m.Transform * m.C1:Inverse()
			local pv = (world[m.Part0] * m.C0 * m.Transform).Position
			local e = (pv - HRP_CF * toRig(bones[b])).Magnitude
			worst = math.max(worst, e)
			if e > 2e-3 then fails += 1; print(("FAIL %s %s err %.4f"):format(key, b, e)) end
		end
	end
end
print(("rigrepair: worst joint error %.6f studs, %d failures"):format(worst, fails))
print(fails == 0 and ok and "ALL PASS" or "FAIL")
