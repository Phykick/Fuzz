-- Generated. Rest-pose rig description in Roblox axes (character faces -Z).
-- Pivots are joint positions (bone heads) in the authoring rig's space;
-- the runtime maps them onto the live rig via RightShoulder/LeftShoulder/Neck.
return {
	bones = { "LowerTorso", "UpperTorso", "Head", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot", "SwordHandle", "BowHandle" },
	parent = { LowerTorso = "HumanoidRootPart", UpperTorso = "LowerTorso", Head = "UpperTorso", LeftUpperArm = "UpperTorso", LeftLowerArm = "LeftUpperArm", LeftHand = "LeftLowerArm", RightUpperArm = "UpperTorso", RightLowerArm = "RightUpperArm", RightHand = "RightLowerArm", LeftUpperLeg = "LowerTorso", LeftLowerLeg = "LeftUpperLeg", LeftFoot = "LeftLowerLeg", RightUpperLeg = "LowerTorso", RightLowerLeg = "RightUpperLeg", RightFoot = "RightLowerLeg", SwordHandle = "RightHand", BowHandle = "LeftHand" },
	upper = { UpperTorso = true, Head = true, LeftUpperArm = true, LeftLowerArm = true, LeftHand = true, RightUpperArm = true, RightLowerArm = true, RightHand = true, SwordHandle = true, BowHandle = true },
	pivot = {
		LowerTorso = Vector3.new(0, 2.65, 0),
		UpperTorso = Vector3.new(0, 2.85, 0),
		Head = Vector3.new(0, 4.45, 0),
		LeftUpperArm = Vector3.new(-0.85, 4.2, 0),
		LeftLowerArm = Vector3.new(-0.85, 3.22, 0),
		LeftHand = Vector3.new(-0.85, 2.3, 0),
		RightUpperArm = Vector3.new(0.85, 4.2, 0),
		RightLowerArm = Vector3.new(0.85, 3.22, 0),
		RightHand = Vector3.new(0.85, 2.3, 0),
		LeftUpperLeg = Vector3.new(-0.35, 2.55, 0),
		LeftLowerLeg = Vector3.new(-0.35, 1.4, 0),
		LeftFoot = Vector3.new(-0.35, 0.3, 0),
		RightUpperLeg = Vector3.new(0.35, 2.55, 0),
		RightLowerLeg = Vector3.new(0.35, 1.4, 0),
		RightFoot = Vector3.new(0.35, 0.3, 0),
		SwordHandle = Vector3.new(0.85, 2.08, 0),
		BowHandle = Vector3.new(-0.85, 2.08, 0),
	},
	points = {
		BladeBase = { bone = "SwordHandle", pos = Vector3.new(0.85, 2.08, -0.225) },
		BladeMid = { bone = "SwordHandle", pos = Vector3.new(0.85, 2.08, -1.68) },
		BladeTip = { bone = "SwordHandle", pos = Vector3.new(0.85, 2.08, -3.135) },
		BowUpperNock = { bone = "BowHandle", pos = Vector3.new(-0.85, 2.632, -2.6625) },
		BowLowerNock = { bone = "BowHandle", pos = Vector3.new(-0.85, 2.632, 2.6625) },
		BowStringRest = { bone = "BowHandle", pos = Vector3.new(-0.85, 2.632, -0.15) },
		BowArrowRest = { bone = "BowHandle", pos = Vector3.new(-0.905, 2.08, -0.15) },
		RightFingers = { bone = "RightHand", pos = Vector3.new(0.85, 2, 0) },
	},
	studsPerMetre = 3,
	arrowLength = 2.73,
}
