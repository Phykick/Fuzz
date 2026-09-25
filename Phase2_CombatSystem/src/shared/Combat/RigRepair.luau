--!nonstrict
--[[
	RigRepair: makes an imported rig drivable.

	If PoseDriver can already bind the rig (Motor6Ds, AnimationConstraints or
	skinned Bones), nothing is changed. Otherwise, if the R15 body parts exist
	as separate parts (e.g. only welded together, or imported without joints),
	Motor6Ds are built at the correct joint pivots: the authoring skeleton is
	fitted onto the parts' actual centres (rotation + scale + offset).
]]
local Combat = script.Parent
local PoseDriver = require(Combat.PoseDriver)
local RigData = require(Combat.RigData)

local RigRepair = {}

local JOINT_NAMES = {
	LowerTorso = "Root", UpperTorso = "Waist", Head = "Neck",
	LeftUpperArm = "LeftShoulder", LeftLowerArm = "LeftElbow", LeftHand = "LeftWrist",
	RightUpperArm = "RightShoulder", RightLowerArm = "RightElbow", RightHand = "RightWrist",
	LeftUpperLeg = "LeftHip", LeftLowerLeg = "LeftKnee", LeftFoot = "LeftAnkle",
	RightUpperLeg = "RightHip", RightLowerLeg = "RightKnee", RightFoot = "RightAnkle",
	SwordHandle = "SwordGrip", BowHandle = "BowGrip",
}
local REQUIRED = { "LowerTorso", "UpperTorso", "Head", "LeftUpperArm", "RightUpperArm", "LeftHand", "RightHand" }

local function basis(a: Vector3, b: Vector3): CFrame
	local x = a.Unit
	local z = x:Cross(b).Unit
	local y = z:Cross(x)
	return CFrame.fromMatrix(Vector3.zero, x, y, z)
end

-- Returns (true, description) when the rig can be driven afterwards.
function RigRepair.ensure(model: Model): (boolean, string)
	local rig, err = PoseDriver.bind(model)
	if rig then
		return true, "joints ok"
	end
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return false, err
	end
	local parts = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= hrp then
			local n = PoseDriver.boneName(d.Name)
			if JOINT_NAMES[n] and not parts[n] then
				parts[n] = d
			end
		end
	end
	for _, n in REQUIRED do
		if not parts[n] then
			return false, err
		end
	end

	-- fit the authoring body onto the real parts (bounding-box centres)
	local H = RigData.hurtboxes
	local e1 = H.RightUpperArm.center - H.LeftUpperArm.center
	local e2 = H.Head.center - H.LowerTorso.center
	local r1 = parts.RightUpperArm.Position - parts.LeftUpperArm.Position
	local r2 = parts.Head.Position - parts.LowerTorso.Position
	local G = basis(r1, r2) * basis(e1, e2):Inverse()
	local s = r1.Magnitude / e1.Magnitude
	local origin = parts.LowerTorso.Position
	local function map(p: Vector3): Vector3
		return origin + G:VectorToWorldSpace((p - H.LowerTorso.center) * s)
	end

	-- remove rigid connections between rig parts, then build proper joints
	local isRig = { [hrp] = true }
	for _, p in parts do
		isRig[p] = true
	end
	for _, d in model:GetDescendants() do
		if (d:IsA("Weld") or d:IsA("WeldConstraint") or d:IsA("Motor6D") or d:IsA("ManualWeld"))
			and d.Part0 and d.Part1 and isRig[d.Part0] and isRig[d.Part1] then
			d:Destroy()
		end
	end
	local built = 0
	for _, b in RigData.bones do
		local part = parts[b]
		local pname = RigData.parent[b]
		local p0 = pname == "HumanoidRootPart" and hrp or parts[pname]
		if part and p0 then
			local pivot = CFrame.new(map(RigData.pivot[b]))
			local m = Instance.new("Motor6D")
			m.Name = JOINT_NAMES[b]
			m.Part0 = p0
			m.Part1 = part
			m.C0 = p0.CFrame:ToObjectSpace(pivot)
			m.C1 = part.CFrame:ToObjectSpace(pivot)
			m.Parent = part
			built += 1
		end
	end
	local ok, err2 = PoseDriver.bind(model)
	if ok then
		return true, string.format("built %d Motor6D joints (rig had none usable)", built)
	end
	return false, tostring(err2)
end

return RigRepair
