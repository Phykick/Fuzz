-- Do attacks connect at fighting distance? Real PoseDriver + Geometry code,
-- R15-sized hurtboxes, target standing in guard facing the attacker.
local RigData = MODS.RigData
local Geometry = MODS.Geometry
local SIZE = {
	Head = Vector3.new(0.72, 0.95, 0.8), UpperTorso = Vector3.new(1.4, 1.6, 0.66), LowerTorso = Vector3.new(1.18, 0.62, 0.64),
	LeftUpperArm = Vector3.new(0.4, 1.18, 0.42), RightUpperArm = Vector3.new(0.4, 1.18, 0.42),
	LeftLowerArm = Vector3.new(0.31, 0.94, 0.32), RightLowerArm = Vector3.new(0.31, 0.94, 0.32),
	LeftHand = Vector3.new(0.13, 0.42, 0.25), RightHand = Vector3.new(0.13, 0.42, 0.25),
	LeftUpperLeg = Vector3.new(0.52, 1.27, 0.56), RightUpperLeg = Vector3.new(0.52, 1.27, 0.56),
	LeftLowerLeg = Vector3.new(0.37, 1.08, 0.4), RightLowerLeg = Vector3.new(0.37, 1.08, 0.4),
	LeftFoot = Vector3.new(0.32, 0.36, 0.86), RightFoot = Vector3.new(0.32, 0.36, 0.86),
	SwordHandle = Vector3.new(0.1, 0.1, 0.1), BowHandle = Vector3.new(0.1, 0.1, 0.1),
}
local CHILD = { LowerTorso = "UpperTorso", UpperTorso = "Head", LeftUpperArm = "LeftLowerArm", LeftLowerArm = "LeftHand",
	RightUpperArm = "RightLowerArm", RightLowerArm = "RightHand", LeftUpperLeg = "LeftLowerLeg", LeftLowerLeg = "LeftFoot",
	RightUpperLeg = "RightLowerLeg", RightLowerLeg = "RightFoot" }
local function makeRig()
	local ref = RigData.pivot.LowerTorso
	local function P(b) return RigData.pivot[b] - ref end
	local function IsA(self, c) return c == self.__class or (c == "BasePart" and self.__class == "Part") end
	local hrp = { Name = "HumanoidRootPart", CFrame = CFrame.identity, __class = "Part", IsA = IsA }
	local parts = { HumanoidRootPart = hrp }
	local rest = { [hrp] = CFrame.identity }
	for _, b in RigData.bones do
		local c = P(b)
		if CHILD[b] then c = (P(b) + P(CHILD[b])) * 0.5
		elseif b == "Head" then c = P(b) + Vector3.new(0, 0.48, 0)
		elseif string.find(b, "Hand") then c = P(b) + Vector3.new(0, -0.21, 0)
		elseif string.find(b, "Foot") then c = P(b) + Vector3.new(0, -0.15, -0.2) end
		parts[b] = { Name = b, Size = SIZE[b], __class = "Part", IsA = IsA }
		rest[parts[b]] = CFrame.new(c)
	end
	local motors = {}
	for _, b in RigData.bones do
		local p0, p1 = parts[RigData.parent[b]], parts[b]
		local J = CFrame.new(P(b))
		local m = { Part0 = p0, Part1 = p1, C0 = rest[p0]:Inverse() * J, C1 = rest[p1]:Inverse() * J, Parent = true,
			__class = "Motor6D", IsA = IsA }
		table.insert(motors, m)
	end
	return { FindFirstChild = function(_, n) return parts[n] end, GetDescendants = function() return motors end }
end

local attacker = assert(PoseDriver.bind(makeRig()))
local target = assert(PoseDriver.bind(makeRig()))
local idle = PoseDriver.getClip("Sword_Idle")
local tpose = PoseDriver.sample(idle, 0, true, PoseDriver.newPose())
target:solve(tpose)
local pose = PoseDriver.newPose()
local results = {}
for _, dir in { "HighRight", "HighLeft", "HorizontalRL", "HorizontalLR", "Thrust" } do
	local name = "Sword_Attack_" .. dir
	local clip = PoseDriver.getClip(name)
	local t0, t1 = PoseDriver.marker(name, "AttackActive"), PoseDriver.marker(name, "RecoveryStart")
	local line = dir .. ":"
	for _, d in { 3.0, 4.0, 4.5, 5.0, 5.4, 5.8, 6.2 } do
		local tRoot = CFrame.new(0, 0, -d) * CFrame.Angles(0, math.pi, 0)
		local boxes = target:hurtboxes(tRoot)
		local prev, hit
		local t = t0
		while t <= t1 + 1e-6 and not hit do
			PoseDriver.sample(clip, t, false, pose)
			attacker:solve(pose)
			local base = attacker:pointWorld("BladeBase", CFrame.identity)
			local tip = attacker:pointWorld("BladeTip", CFrame.identity)
			local cur = {}
			for i = 1, 7 do cur[i] = base:Lerp(tip, (i - 1) / 6) end
			prev = prev or cur
			for _, box in boxes do
				for i = 1, 7 do
					if Geometry.segmentBox(prev[i], cur[i], box.cf, box.size, 0.05) then hit = box.name break end
				end
				if hit then break end
			end
			prev = cur
			t += 1 / 60
		end
		line ..= ("  %.1f:%s"):format(d, hit or "miss")
	end
	print(line)
end
