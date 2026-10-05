--!strict
-- Stylised R15 survivor rig (v2). Positions are in character space (feet on y=0, facing -Z) and
-- MUST match blender/kit_survivors.py + blender/preview_survivors.py (Blender (x, y, z) = Roblox (x, z, -y)).
local CharacterRig = {}

CharacterRig.HEIGHT = 5.75
CharacterRig.HIP_HEIGHT = 2.75

-- Part centres (each SV_* asset is authored around the centre of the part it belongs to)
CharacterRig.Parts = {
	LowerTorso = Vector3.new(0, 2.75, 0),
	UpperTorso = Vector3.new(0, 3.72, 0),
	Head = Vector3.new(0, 5.1, 0),
	LeftUpperArm = Vector3.new(-1.05, 3.7, 0),
	LeftLowerArm = Vector3.new(-1.05, 2.72, 0),
	LeftHand = Vector3.new(-1.05, 1.98, 0),
	RightUpperArm = Vector3.new(1.05, 3.7, 0),
	RightLowerArm = Vector3.new(1.05, 2.72, 0),
	RightHand = Vector3.new(1.05, 1.98, 0),
	LeftUpperLeg = Vector3.new(-0.4, 2.03, 0),
	LeftLowerLeg = Vector3.new(-0.4, 1.02, 0),
	LeftFoot = Vector3.new(-0.4, 0.26, -0.16),
	RightUpperLeg = Vector3.new(0.4, 2.03, 0),
	RightLowerLeg = Vector3.new(0.4, 1.02, 0),
	RightFoot = Vector3.new(0.4, 0.26, -0.16),
}

-- Standard R15 joints: name, part0, part1, joint position, rig attachment name
CharacterRig.Joints = {
	{ "Root", "HumanoidRootPart", "LowerTorso", Vector3.new(0, 2.75, 0), "RootRigAttachment" },
	{ "Waist", "LowerTorso", "UpperTorso", Vector3.new(0, 3.0, 0), "WaistRigAttachment" },
	{ "Neck", "UpperTorso", "Head", Vector3.new(0, 4.42, 0), "NeckRigAttachment" },
	{ "LeftShoulder", "UpperTorso", "LeftUpperArm", Vector3.new(-1.05, 4.22, 0), "LeftShoulderRigAttachment" },
	{ "LeftElbow", "LeftUpperArm", "LeftLowerArm", Vector3.new(-1.05, 3.2, 0), "LeftElbowRigAttachment" },
	{ "LeftWrist", "LeftLowerArm", "LeftHand", Vector3.new(-1.05, 2.24, 0), "LeftWristRigAttachment" },
	{ "RightShoulder", "UpperTorso", "RightUpperArm", Vector3.new(1.05, 4.22, 0), "RightShoulderRigAttachment" },
	{ "RightElbow", "RightUpperArm", "RightLowerArm", Vector3.new(1.05, 3.2, 0), "RightElbowRigAttachment" },
	{ "RightWrist", "RightLowerArm", "RightHand", Vector3.new(1.05, 2.24, 0), "RightWristRigAttachment" },
	{ "LeftHip", "LowerTorso", "LeftUpperLeg", Vector3.new(-0.4, 2.55, 0), "LeftHipRigAttachment" },
	{ "LeftKnee", "LeftUpperLeg", "LeftLowerLeg", Vector3.new(-0.4, 1.52, 0), "LeftKneeRigAttachment" },
	{ "LeftAnkle", "LeftLowerLeg", "LeftFoot", Vector3.new(-0.4, 0.52, 0), "LeftAnkleRigAttachment" },
	{ "RightHip", "LowerTorso", "RightUpperLeg", Vector3.new(0.4, 2.55, 0), "RightHipRigAttachment" },
	{ "RightKnee", "RightUpperLeg", "RightLowerLeg", Vector3.new(0.4, 1.52, 0), "RightKneeRigAttachment" },
	{ "RightAnkle", "RightLowerLeg", "RightFoot", Vector3.new(0.4, 0.52, 0), "RightAnkleRigAttachment" },
}

-- Standard accessory attachments (so Roblox Accessories can be worn later).
CharacterRig.AccessoryAttachments = {
	Head = {
		HatAttachment = Vector3.new(0, 5.75, 0),
		HairAttachment = Vector3.new(0, 5.75, 0),
		FaceFrontAttachment = Vector3.new(0, 5.12, -0.6),
		FaceCenterAttachment = Vector3.new(0, 5.12, 0),
	},
	UpperTorso = {
		NeckAttachment = Vector3.new(0, 4.42, 0),
		BodyFrontAttachment = Vector3.new(0, 3.72, -0.5),
		BodyBackAttachment = Vector3.new(0, 3.72, 0.5),
		LeftCollarAttachment = Vector3.new(-0.7, 4.35, 0),
		RightCollarAttachment = Vector3.new(0.7, 4.35, 0),
	},
	LowerTorso = {
		WaistCenterAttachment = Vector3.new(0, 2.95, 0),
		WaistFrontAttachment = Vector3.new(0, 2.95, -0.48),
		WaistBackAttachment = Vector3.new(0, 2.95, 0.48),
	},
	LeftUpperArm = { LeftShoulderAttachment = Vector3.new(-1.05, 4.22, 0) },
	RightUpperArm = { RightShoulderAttachment = Vector3.new(1.05, 4.22, 0) },
	LeftHand = { LeftGripAttachment = Vector3.new(-1.05, 1.88, 0) },
	RightHand = { RightGripAttachment = Vector3.new(1.05, 1.88, 0) },
	LeftFoot = { LeftFootAttachment = Vector3.new(-0.4, 0.05, 0) },
	RightFoot = { RightFootAttachment = Vector3.new(0.4, 0.05, 0) },
}

CharacterRig.Mouths = {
	smile = "SV_MOUTH_SMILE",
	flat = "SV_MOUTH_FLAT",
	frown = "SV_MOUTH_FROWN",
	open = "SV_MOUTH_OPEN",
}

-- Hair that still reads under a hat covering the crown; anything else is cropped to SV_HAIR_CROP.
CharacterRig.HairUnderHat = { HAIR_PONYTAIL = true, HAIR_BRAIDS = true }

CharacterRig.BodyScale = {
	slim = Vector3.new(0.92, 1, 0.94),
	standard = Vector3.new(1, 1, 1),
	heavy = Vector3.new(1.14, 1, 1.12),
}

-- Saves made before the v2 survivors stored CHR_* head ids.
CharacterRig.HeadFor = function(appearance: any): string
	if appearance.gender == "F" then
		return "SV_HEAD_C"
	end
	local h = appearance.head or ""
	return if string.find(h, "_B$") then "SV_HEAD_B" else "SV_HEAD_A"
end

return CharacterRig
