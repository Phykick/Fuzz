--!strict
-- Builds stylised R15 survivors from the SV_* Blender kit and a wardrobe style
-- (Shared/CharacterStyles, generated from blender/styles.json).
-- Output is a standard R15 model (HumanoidRootPart, 15 named parts, standard Motor6D + RigAttachment
-- names, accessory attachments, Humanoid) so Roblox Accessories / layered gear can be added later.
-- Clothing overlays, faces, hair, headgear, props and weapons are welded to their body part.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterRig = require(ReplicatedStorage.Shared.CharacterRig)
local CharacterStyles = require(ReplicatedStorage.Shared.CharacterStyles)
local DwellerDefinitions = require(ReplicatedStorage.Shared.DwellerDefinitions)
local ItemDefinitions = require(ReplicatedStorage.Shared.ItemDefinitions)
local MeshFactory = require(script.Parent.MeshFactory)

local CharacterFactory = {}

local DEFAULT_COLORS = { pad = "2A2A2E", glove = "2A2A2E", boot = "3A2A1E", belt = "3A2A1E", accent = "888888", pants = "3A3A40" }
local MASKS = { HAT_MASK = true, RAID_MASK = true }
-- Children: smaller rig with a proportionally bigger head, bright play clothes.
local CHILD_SCALE = 0.64
local CHILD_HEAD = 1.22
local CHILD_SHIRTS = { "4FA3D9", "E8A33A", "D9534F", "5CB85C", "9B6FD1", "F2C12E", "3FB6A8" }
local CHILD_PANTS = { "2C3D5C", "3A3632", "4A5A2E", "5A3A5E" }

export type Handle = {
	model: Model,
	root: BasePart,
	motors: { [string]: Motor6D },
	eyes: { BasePart },
	brows: { BasePart },
	mouths: { [string]: { BasePart } },
	weapon: Model?,
	weaponId: string?,
	clickBox: BasePart,
	parts: { BasePart },
	expression: string,
	scale: number, -- overall model scale (height variation, children)
}

-- look = { style, colors (slot -> hex overrides), weapon, raider, child, pregnant }
export type Look = {
	style: string?,
	colors: { [string]: string }?,
	weapon: string?,
	raider: boolean?,
	child: boolean?,
	pregnant: boolean?,
}

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = b
end

local function prep(p: BasePart, shadow: boolean)
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = shadow
end

-- Spawn an asset and return (mainPart, decorations). For rig parts the bulkiest piece becomes the
-- named R15 part; the rest are welded to it.
local function spawnPart(asset: string, cf: CFrame, tints, model: Model, rigName: string?, scale: Vector3?): (BasePart?, { BasePart })
	local m = MeshFactory.spawn(asset, cf, tints, nil)
	local parts = {}
	for _, c in m:GetChildren() do
		if c:IsA("BasePart") then
			table.insert(parts, c)
		end
	end
	if #parts == 0 then
		m:Destroy()
		return nil, {}
	end
	local main = parts[1]
	if rigName then
		local best = -1
		for _, p in parts do
			local v = p.Size.X * p.Size.Y * p.Size.Z
			if v > best then
				best = v
				main = p
			end
		end
	end
	if scale and scale ~= Vector3.one then
		for _, p in parts do
			local rel = cf:ToObjectSpace(p.CFrame)
			p.Size *= scale
			p.CFrame = cf * CFrame.new(rel.Position * scale) * rel.Rotation
		end
	end
	local decos = {}
	for _, p in parts do
		prep(p, p.Size.Magnitude > 0.6)
		p.Parent = model
		if p ~= main then
			table.insert(decos, p)
		end
	end
	if rigName then
		main.Name = rigName
	end
	m:Destroy()
	return main, decos
end

local function hex(h: string?): Color3
	return Color3.fromHex(h or "808080")
end

-- Colour slots for a style, with the same fallbacks as blender/preview_survivors.py.
local function resolveColors(style: any, overrides: { [string]: string }?): { [string]: string }
	local c = table.clone(DEFAULT_COLORS)
	for k, v in style.colors do
		c[k] = v
	end
	if overrides then
		for k, v in overrides do
			c[k] = v
		end
	end
	c.shirt = c.shirt or c.suit or "888888"
	c.suit = c.suit or c.shirt
	c.sleeve = c.sleeve or c.shirt
	c.coat = c.coat or c.shirt
	c.apron = c.apron or c.shirt
	c.vest = c.vest or c.accent
	c.hat = c.hat or c.accent
	return c
end

-- Body asset per R15 part for a style (mirrors parts_for() in blender/preview_survivors.py).
local function bodyAssets(style: any): { [string]: string }
	local fore = if style.forearm == "rolled" then "SV_FOREARM_ROLLED_" else "SV_FOREARM_"
	local hand = if style.hands == "glove" then "SV_GLOVE_" else "SV_HAND_"
	local thigh = if style.thigh == "cargo" then "SV_THIGH_CARGO_" else "SV_THIGH_"
	local shin = if style.shin == "pad" then "SV_SHIN_PAD" else "SV_SHIN"
	local foot = if style.feet == "boot" then "SV_BOOT" else "SV_SHOE"
	return {
		UpperTorso = "SV_" .. style.torso,
		LowerTorso = "SV_HIPS",
		RightUpperArm = "SV_UPPERARM_R",
		LeftUpperArm = "SV_UPPERARM_L",
		RightLowerArm = fore .. "R",
		LeftLowerArm = fore .. "L",
		RightHand = hand .. "R",
		LeftHand = hand .. "L",
		RightUpperLeg = thigh .. "R",
		LeftUpperLeg = thigh .. "L",
		RightLowerLeg = shin,
		LeftLowerLeg = shin,
		RightFoot = foot,
		LeftFoot = foot,
	}
end

-- Look for a dweller record: children wear play clothes, expecting mothers the maternity uniform,
-- otherwise an equipped outfit's style, else the archetype's.
function CharacterFactory.lookFor(d: any): Look
	if d.child then
		local n = tonumber(string.match(tostring(d.id), "%d+")) or 1
		local shirt = CHILD_SHIRTS[n % #CHILD_SHIRTS + 1]
		return { style = "Child", child = true, colors = { shirt = shirt, sleeve = shirt, pants = CHILD_PANTS[n % #CHILD_PANTS + 1] } }
	end
	if d.pregnant then
		-- one uniform for every expecting mother, whatever her job or outfit
		return { style = "Maternity", pregnant = true }
	end
	local outfit = d.outfit and ItemDefinitions.Outfits[d.outfit]
	if outfit then
		return { style = outfit.style, colors = outfit.tints, weapon = d.weapon }
	end
	local archetype = d.archetype or (d.appearance and d.appearance.archetype) or "Worker"
	local arch = DwellerDefinitions.Archetypes[archetype]
	return { style = if arch then arch.style else archetype, weapon = d.weapon }
end

function CharacterFactory.build(appearance: any, look: Look): Handle
	local model = Instance.new("Model")
	model.Name = "Survivor"
	local style = CharacterStyles.Styles[look.style or ""] or CharacterStyles.Styles.Worker
	local colors = resolveColors(style, look.colors)
	local tints: { [string]: Color3 } = {}
	for slot, h in colors do
		tints[slot] = hex(h)
	end
	tints.skin = hex(appearance.skin)
	tints.hair = hex(appearance.hairColor)
	-- older saves have no eye colour: derive a stable one from the skin + hair
	tints.eye = hex(appearance.eyeColor or DwellerDefinitions.EyeColors[(#(appearance.skin or "") + #(appearance.hairColor or "") + string.byte(appearance.skin or "A")) % #DwellerDefinitions.EyeColors + 1])

	local body = CharacterRig.BodyScale[appearance.body or "standard"] or Vector3.one
	local armX = 1 + (body.X - 1) * 0.85
	local legX = 1 + (body.X - 1) * 0.55
	local limbScale = Vector3.new(1 + (body.X - 1) * 0.5, 1, 1 + (body.Z - 1) * 0.5)

	local function rigPos(name: string, p: Vector3): Vector3
		if string.find(name, "Arm") or string.find(name, "Hand") or string.find(name, "Shoulder") or string.find(name, "Elbow") or string.find(name, "Wrist") then
			return Vector3.new(p.X * armX, p.Y, p.Z)
		elseif string.find(name, "Leg") or string.find(name, "Foot") or string.find(name, "Hip") or string.find(name, "Knee") or string.find(name, "Ankle") then
			return Vector3.new(p.X * legX, p.Y, p.Z)
		end
		return p
	end
	local headScale = if look.child then CHILD_HEAD else 1
	local function partScale(name: string): Vector3
		if name == "UpperTorso" or name == "LowerTorso" then
			return body
		elseif name == "Head" then
			return Vector3.one * headScale
		end
		return limbScale
	end

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CFrame = CFrame.new(0, CharacterRig.HIP_HEIGHT, 0)
	root.Parent = model
	model.PrimaryPart = root

	local headAsset = CharacterRig.HeadFor(appearance)
	local assets = bodyAssets(style)
	assets.Head = headAsset
	local partsByName: { [string]: BasePart } = { HumanoidRootPart = root }
	local all: { BasePart } = {}
	for name, center in CharacterRig.Parts do
		local main, decos = spawnPart(assets[name], CFrame.new(rigPos(name, center)), tints, model, name, partScale(name))
		if main then
			partsByName[name] = main
			table.insert(all, main)
			for _, d in decos do
				weld(main, d)
				table.insert(all, d)
			end
		end
	end

	-- Joints + rig attachments
	local motors = {}
	for _, j in CharacterRig.Joints do
		local jname, p0n, p1n, pos, attName = j[1], j[2], j[3], j[4], j[5]
		local p0, p1 = partsByName[p0n], partsByName[p1n]
		if p0 and p1 then
			local jcf = CFrame.new(rigPos(jname, pos))
			local a0 = Instance.new("Attachment")
			a0.Name = attName
			a0.CFrame = p0.CFrame:ToObjectSpace(jcf)
			a0.Parent = p0
			local a1 = Instance.new("Attachment")
			a1.Name = attName
			a1.CFrame = p1.CFrame:ToObjectSpace(jcf)
			a1.Parent = p1
			local m = Instance.new("Motor6D")
			m.Name = jname
			m.Part0 = p0
			m.Part1 = p1
			m.C0 = a0.CFrame
			m.C1 = a1.CFrame
			m.Parent = p1
			motors[jname] = m
		end
	end
	for partName, atts in CharacterRig.AccessoryAttachments do
		local p = partsByName[partName]
		if p then
			for an, pos in atts do
				local a = Instance.new("Attachment")
				a.Name = an
				a.CFrame = p.CFrame:ToObjectSpace(CFrame.new(rigPos(partName, pos)))
				a.Parent = p
			end
		end
	end

	-- Face features sit on markers authored on the head mesh
	local head = partsByName.Head
	local headCF = CFrame.new(CharacterRig.Parts.Head)
	local eyes, brows, mouths = {}, {}, {}
	local function feature(asset: string, markerName: string, extra: CFrame?): { BasePart }
		local mk = MeshFactory.marker(headAsset, markerName)
		if not mk or not head then
			return {}
		end
		local main, decos = spawnPart(asset, headCF * CFrame.new(mk.Position * headScale) * (extra or CFrame.identity), tints, model, nil, Vector3.one * headScale)
		local out = {}
		if main then
			weld(head :: BasePart, main)
			table.insert(out, main)
			for _, d in decos do
				weld(head :: BasePart, d)
				table.insert(out, d)
			end
		end
		return out
	end
	for _, side in { "L", "R" } do
		for _, p in feature("SV_EYE", "Eye" .. side) do
			table.insert(eyes, p)
		end
		local browTilt = ((appearance.brow or 1) - 2) * 8 * (if side == "L" then 1 else -1)
		for _, p in feature("SV_BROW", "Brow" .. side, CFrame.Angles(0, 0, math.rad(browTilt))) do
			table.insert(brows, p)
		end
	end
	for key, asset in CharacterRig.Mouths do
		local ps = feature(asset, "Mouth")
		for _, p in ps do
			p.Transparency = if key == "smile" then 0 else 1
		end
		mouths[key] = ps
	end

	-- Wardrobe pieces are authored around the centre of the part they are welded to
	local function attach(asset: string, partName: string)
		local p = partsByName[partName]
		if not p or not MeshFactory.has(asset) then
			return
		end
		local main, decos = spawnPart(asset, CFrame.new(rigPos(partName, CharacterRig.Parts[partName])), tints, model, nil, partScale(partName))
		if main then
			weld(p, main)
			for _, d in decos do
				weld(p, d)
			end
		end
	end

	-- Hair: hats that cover the crown crop it, hoods/helmets/toques hide it
	local hair = appearance.hair
	if hair == "HAIR_NONE" or style.hideHair == "all" then
		hair = nil
	elseif style.hideHair == "short" and hair and not CharacterRig.HairUnderHat[hair] then
		hair = "HAIR_CROP"
	end
	if hair then
		attach("SV_" .. hair, "Head")
	end
	local masked = false
	for _, g in style.head do
		masked = masked or MASKS[g] == true
	end
	if appearance.beard and not masked then
		attach("SV_HAIR_BEARD", "Head")
	end
	for _, o in style.overlays do
		attach("SV_" .. o[1], o[2])
	end
	for _, g in style.head do
		attach("SV_" .. g, "Head")
	end
	for _, pr in style.props do
		attach("SV_" .. pr[1], pr[2])
	end

	-- Click target
	local click = Instance.new("Part")
	click.Name = "ClickBox"
	click.Size = Vector3.new(2.6, 6.2, 2.4)
	click.Transparency = 1
	click.CanCollide = false
	click.CanTouch = false
	click.CanQuery = true
	click.Massless = true
	click.Anchored = false
	click.CFrame = CFrame.new(0, 3.1, 0)
	click.Parent = model
	weld(root, click)

	local hum = Instance.new("Humanoid")
	hum.RigType = Enum.HumanoidRigType.R15
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.EvaluateStateMachine = false
	hum.RequiresNeck = false
	hum.BreakJointsOnDeath = false
	hum.Parent = model

	local handle: Handle = {
		model = model,
		root = root,
		motors = motors,
		eyes = eyes,
		brows = brows,
		mouths = mouths,
		weapon = nil,
		weaponId = nil,
		clickBox = click,
		parts = all,
		expression = "smile",
		scale = 1,
	}
	local h = (appearance.height or 1) * (if look.child then CHILD_SCALE else 1)
	if math.abs(h - 1) > 0.005 then
		model:ScaleTo(h)
		handle.scale = h
	end
	if look.weapon then
		CharacterFactory.setWeapon(handle, look.weapon)
	end
	return handle
end

function CharacterFactory.setWeapon(handle: Handle, weaponId: string?)
	if handle.weaponId == weaponId then
		return
	end
	if handle.weapon then
		handle.weapon:Destroy()
		handle.weapon = nil
	end
	handle.weaponId = weaponId
	local def = weaponId and ItemDefinitions.Weapons[weaponId]
	if not def or def.mesh == "" then
		return
	end
	local hand = handle.model:FindFirstChild("RightHand") :: BasePart?
	if not hand then
		return
	end
	local grip = hand:FindFirstChild("RightGripAttachment") :: Attachment?
	local gripCF = if grip then grip.WorldCFrame else hand.CFrame
	-- Barrel (+Y in Blender = -Z in Roblox) points along the arm's downward axis.
	local cf = gripCF * CFrame.Angles(math.rad(-90), 0, 0)
	local m = MeshFactory.spawn(def.mesh, cf, nil, handle.model)
	m.Name = "Weapon"
	for _, p in m:GetChildren() do
		if p:IsA("BasePart") then
			prep(p, false)
			weld(hand, p)
			if not m.PrimaryPart then
				-- pivot follows the animated hand; keep the asset origin as the pivot point
				p.PivotOffset = p.CFrame:ToObjectSpace(cf)
				m.PrimaryPart = p
			end
		end
	end
	handle.weapon = m
end

function CharacterFactory.setWeaponVisible(handle: Handle, visible: boolean)
	if handle.weapon then
		for _, p in handle.weapon:GetChildren() do
			if p:IsA("BasePart") then
				p.LocalTransparencyModifier = if visible then 0 else 1
			end
		end
	end
end

function CharacterFactory.setExpression(handle: Handle, expr: string)
	if handle.expression == expr or not handle.mouths[expr] then
		return
	end
	for key, ps in handle.mouths do
		for _, p in ps do
			p.Transparency = if key == expr then 0 else 1
		end
	end
	handle.expression = expr
end

-- Raider look generated from a seed.
function CharacterFactory.raiderLook(seed: number): (any, Look)
	local rng = Random.new(seed)
	local shirts = { "4A3A2E", "3A3A3A", "5A3A2A", "2E2A24" }
	local accents = { "7A2A1E", "8C6A3A", "3E2E22" }
	local appearance = DwellerDefinitions.randomAppearance(rng, if rng:NextNumber() < 0.5 then "M" else "F", "Raider")
	appearance.archetype = "Raider"
	appearance.hair = if rng:NextNumber() < 0.5 then "HAIR_MOHAWK" else "HAIR_SHORT"
	local shirt = shirts[rng:NextInteger(1, #shirts)]
	return appearance, {
		style = "Raider",
		colors = { shirt = shirt, sleeve = shirt, accent = accents[rng:NextInteger(1, #accents)] },
		raider = true,
	}
end

return CharacterFactory
