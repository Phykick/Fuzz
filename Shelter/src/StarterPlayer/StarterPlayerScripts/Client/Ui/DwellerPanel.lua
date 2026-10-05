--!strict
-- DwellerUI: survivor profile sheet with a live 3D portrait. The header shows health, mood and what
-- they are doing right now; tabs show NEEDS (needs, memories, personality), SKILLS (skills,
-- equipment) and PEOPLE (partner, friends, family).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Theme = require(ReplicatedStorage.Shared.Theme)
local ItemDefinitions = require(ReplicatedStorage.Shared.ItemDefinitions)
local DwellerDefinitions = require(ReplicatedStorage.Shared.DwellerDefinitions)
local Family = require(ReplicatedStorage.Shared.Family)
local CharacterRig = require(ReplicatedStorage.Shared.CharacterRig)
local RoomDefinitions = require(ReplicatedStorage.Shared.RoomDefinitions)
local Simulation = require(ReplicatedStorage.Shared.Simulation)
local Needs = require(ReplicatedStorage.Shared.Needs)
local Config = require(ReplicatedStorage.Shared.Config)
local Kit = require(script.Parent.Kit)
local CharacterFactory = require(script.Parent.Parent.Render.CharacterFactory)

local DwellerPanel = {}
local T = Theme.UI
local C: any

local gui: ScreenGui
local sheet: ImageLabel
local vp: ViewportFrame
local portraitSig: string? = nil
local nameL: TextLabel
local subL: TextLabel
local levelL: TextLabel
local xpSet: (number, Color3?) -> ()
local hpSet: (number, Color3?) -> ()
local hpL: TextLabel
local happySet: (number, Color3?) -> ()
local happyL: TextLabel
local assignL: TextLabel
local buttons: Frame
local tabButtons: { [string]: ImageButton } = {}
local pages: { [string]: Frame } = {}
local tab = "NEEDS"
local dwellerId: string? = nil
local buttonsKey = ""
local pageKey = ""

-- NEEDS page widgets
local needRows: { [string]: { set: (number, Color3?) -> (), state: TextLabel } } = {}
local memoryList: Frame
local traitsL: TextLabel
local noteL: TextLabel
-- SKILLS page widgets
local statRows: { [string]: { set: (number, Color3?) -> (), value: TextLabel, label: TextLabel } } = {}
local bestL: TextLabel
local weaponL: TextLabel
local outfitL: TextLabel
-- PEOPLE page
local peopleList: Frame

local function sigOf(d): string
	local a = d.appearance or {}
	return table.concat({ d.id, a.skin or "", a.hair or "", d.outfit or "", d.weapon or "", d.archetype or "",
		tostring(d.child == true), tostring(d.pregnant ~= nil), tostring(a.beard == true) }, "|")
end

local function firstName(d): string
	return string.match(d.name, "^(%S+)") or d.name
end

local function rebuildPortrait(d)
	vp:ClearAllChildren()
	local world = Instance.new("WorldModel")
	world.Parent = vp
	local handle = CharacterFactory.build(d.appearance, CharacterFactory.lookFor(d))
	handle.model:PivotTo(CFrame.new(0, CharacterRig.HIP_HEIGHT * handle.scale, 0) * CFrame.Angles(0, math.pi - 0.35, 0))
	handle.model.Parent = world
	CharacterFactory.setExpression(handle, if d.status == "Dead" then "frown" elseif (d.happiness or 50) >= 60 then "smile" else "flat")
	local cam = Instance.new("Camera")
	cam.FieldOfView = 24
	cam.CFrame = CFrame.lookAt(Vector3.new(0.85, 4.5, 10), Vector3.new(0, 3.95, 0))
	cam.Parent = vp
	vp.CurrentCamera = cam
	local light = Instance.new("PointLight")
	light.Parent = handle.model:FindFirstChild("Head")
end

-- What they are doing right now, in words.
local function activityText(d, state): (string, Color3)
	if d.status == "Dead" then
		local left = Config.REVIVE_WINDOW - (d.deadFor or 0)
		return "DECEASED (" .. tostring(d.cause or "unknown") .. ") - revive within " .. Family.clock(left), T.danger
	elseif d.status == "Exploring" then
		return "Exploring the wasteland", T.accent
	elseif d.status == "Arriving" then
		return "Walking to the shelter", T.accent
	elseif d.status == "Waiting" then
		return "Waiting outside - gives up in " .. Family.clock(Config.QUEUE_PATIENCE - (d.waitedFor or 0)), T.accent
	end
	local room = (d.at or d.roomId) and state.rooms[d.at or d.roomId]
	local where = if room then RoomDefinitions.Types[room.type].name else "the shelter"
	local moving = d.travel and C.StateStore.now() < (d.arriveAt or 0)
	local act = d.activity
	local text
	if act == "Eating" then
		text = if room and room.type == "Cafeteria" then "Eating in the Cafeteria" else "Eating cold rations"
	elseif act == "Drinking" then
		text = "Getting a drink in the " .. where
	elseif act == "Sleeping" then
		text = if d.floorSleep then "Sleeping on the floor" else "Sleeping in the " .. where
	elseif act == "Treatment" then
		text = "Being treated in the Medbay"
	elseif act == "Visiting" then
		text = "Visiting someone in the Medbay"
	elseif act == "Responding" then
		local inc = room and room.incident
		text = (if inc and inc.kind == "Breakdown" then "Fixing the " elseif inc and inc.kind == "Fire" then "Fighting the fire in the "
			else "Answering the emergency in the ") .. where
		return (if moving then "Running to help: " .. string.lower(string.sub(text, 1, 1)) .. string.sub(text, 2) else text), T.accent
	elseif act == "Relaxing" then
		text = "Unwinding in the " .. where
	elseif d.status == "Working" then
		text = "Working in the " .. where
	else
		text = "Unassigned - in the " .. where
	end
	if moving then
		text = "Heading out: " .. string.lower(string.sub(text, 1, 1)) .. string.sub(text, 2)
	end
	return text, if d.status == "Working" or act == "Working" then T.text else T.textMuted
end

local function relationLabel(d, o, aff: number): (string, Color3)
	if d.partner == o.id then
		return "Partner", Color3.fromRGB(255, 140, 160)
	elseif Family.related(d, o) then
		return "Family", Color3.fromRGB(255, 200, 120)
	elseif aff >= 75 then
		return "Best friend", T.good
	elseif aff >= 40 then
		return "Friend", T.good
	elseif aff <= -30 then
		return "Rival", T.danger
	end
	return "Acquaintance", T.textMuted
end

local function refreshPeople(d, state)
	for _, c in peopleList:GetChildren() do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	local list = {}
	for id, aff in d.rel or {} do
		local o = state.dwellers[id]
		if o then
			table.insert(list, { o = o, aff = aff, score = (if d.partner == id then 1000 else 0) + (if Family.related(d, o) then 500 else 0) + aff })
		end
	end
	-- family members without a relationship entry yet
	for _, o in state.dwellers do
		if o ~= d and Family.related(d, o) and not (d.rel and d.rel[o.id]) then
			table.insert(list, { o = o, aff = 50, score = 500 })
		end
	end
	table.sort(list, function(a, b)
		return a.score > b.score
	end)
	if #list == 0 then
		local f = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), Parent = peopleList })
		Kit.label({ Text = "Hasn't got to know anyone yet.", TextSize = 16, Color = T.textMuted, Size = UDim2.fromScale(1, 1), Parent = f })
		return
	end
	for i, e in list do
		if i > 8 then
			break
		end
		local label, col = relationLabel(d, e.o, e.aff)
		local f = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 32), LayoutOrder = i, Parent = peopleList })
		Kit.label({ Text = e.o.name .. (if e.o.status == "Dead" then " (dead)" else ""), Font = Kit.Fonts.BodyBold, TextSize = 16,
			Size = UDim2.fromOffset(180, 30), Parent = f, Truncate = Enum.TextTruncate.AtEnd })
		Kit.label({ Text = label, TextSize = 15, Color = col, Size = UDim2.fromOffset(110, 30), Position = UDim2.fromOffset(184, 0), Parent = f })
		local _, set = Kit.meter({ Parent = f, Size = UDim2.fromOffset(150, 12), Position = UDim2.fromOffset(300, 9) })
		set(math.clamp((e.aff + 100) / 200, 0, 1), col)
	end
end

local function refreshPage(d, state)
	local now = C.StateStore.now()
	-- NEEDS
	for _, key in Needs.LIST do
		local row = needRows[key]
		local v = (d.needs and d.needs[key]) or 100
		local stage = Needs.stage(key, v)
		row.set(v / 100, if not stage then T.good elseif stage.damage > 0 or stage.work < 0.6 then T.danger else T.accent)
		row.state.Text = if stage then stage.label elseif v < Needs.Defs[key].seek then "Looking for it" else "Fine"
		row.state.TextColor3 = if stage then T.danger elseif v < Needs.Defs[key].seek then T.accent else T.textMuted
	end
	local mkey = ""
	for _, m in d.memories or {} do
		if m.untilT > now then
			mkey ..= m.id .. ";"
		end
	end
	if pageKey ~= mkey .. tab then
		pageKey = mkey .. tab
		for _, c in memoryList:GetChildren() do
			if c:IsA("TextLabel") then
				c:Destroy()
			end
		end
		local shown = 0
		for _, m in d.memories or {} do
			if m.untilT > now and shown < 4 then
				shown += 1
				Kit.label({
					Text = string.format("%s%d  %s", if m.value >= 0 then "+" else "", m.value, m.text), TextSize = 15,
					Color = if m.value >= 0 then T.good else T.danger, Size = UDim2.new(1, 0, 0, 20), Parent = memoryList, Order = shown,
				})
			end
		end
		if shown == 0 then
			Kit.label({ Text = "Nothing much on their mind.", TextSize = 15, Color = T.textMuted, Size = UDim2.new(1, 0, 0, 20), Parent = memoryList })
		end
	end
	local names = {}
	for _, t in DwellerDefinitions.traitsOf(d) do
		local def = (DwellerDefinitions.Traits :: any)[t]
		if def then
			table.insert(names, def.name)
		end
	end
	traitsL.Text = if #names > 0 then "Personality: " .. table.concat(names, " · ") else "Personality: easy-going"
	local note = Family.note(d, state.dwellers, now)
	noteL.Text = note or ""
	-- SKILLS
	local job = d.roomId and state.rooms[d.roomId]
	local def = job and RoomDefinitions.Types[job.type]
	for key, row in statRows do
		local v = Simulation.stat(d, key)
		row.set(v / 12, if def and def.stat == key then T.accent else Color3.fromRGB(150, 160, 175))
		row.value.Text = tostring(v)
		row.label.TextColor3 = if def and def.stat == key then T.accent else T.textMuted
	end
	local best, bv = Simulation.bestRoom(d)
	bestL.Text = if best then ("Best fit: " .. RoomDefinitions.Types[best].name .. " (" .. DwellerDefinitions.STAT_NAMES[RoomDefinitions.Types[best].stat] .. " " .. bv .. ")") else ""
	local w = ItemDefinitions.Weapons[d.weapon or "Fists"]
	weaponL.Text = w.name .. string.format("  ·  %d dmg", w.damage)
	weaponL.TextColor3 = ItemDefinitions.Rarity[w.rarity].color
	local o = d.outfit and ItemDefinitions.Outfits[d.outfit]
	outfitL.Text = if o then o.name else "Standard issue"
	outfitL.TextColor3 = if o then ItemDefinitions.Rarity[o.rarity].color else T.textMuted
	if tab == "PEOPLE" then
		refreshPeople(d, state)
	end
end

local function setTab(name: string)
	tab = name
	pageKey = ""
	for key, page in pages do
		page.Visible = key == name
	end
	for key, b in tabButtons do
		b.ImageColor3 = if key == name then T.accent else T.panelInner
		local cap = b:FindFirstChild("Caption", true) :: TextLabel?
		if cap then
			cap.TextColor3 = if key == name then Color3.fromRGB(28, 24, 18) else T.text
		end
	end
	DwellerPanel.refresh()
end

function DwellerPanel.refresh()
	if not dwellerId then
		return
	end
	local state = C.StateStore.state
	local d = state.dwellers[dwellerId]
	if not d then
		DwellerPanel.close()
		return
	end
	if portraitSig ~= sigOf(d) then
		portraitSig = sigOf(d)
		rebuildPortrait(d)
	end
	nameL.Text = string.upper(d.name)
	local arch = DwellerDefinitions.Archetypes[d.archetype]
	if d.child then
		local parents = {}
		for _, pid in d.parents or {} do
			local pd = state.dwellers[pid]
			if pd then
				table.insert(parents, firstName(pd))
			end
		end
		subL.Text = "Child" .. (if #parents > 0 then " of " .. table.concat(parents, " & ") else "")
	else
		local partner = d.partner and state.dwellers[d.partner]
		subL.Text = (arch and arch.name or "Survivor") .. " · age " .. (d.age or "?") .. (if partner then " · with " .. firstName(partner) else "")
	end
	levelL.Text = "LEVEL " .. d.level
	local need = DwellerDefinitions.xpForLevel(d.level)
	xpSet((d.xp or 0) / need)
	hpSet(d.health / d.maxHealth, if d.health / d.maxHealth < 0.35 then T.danger else T.health)
	hpL.Text = string.format("%d / %d", math.floor(d.health), math.floor(d.maxHealth))
	local h = d.happiness or 0
	happySet(h / 100, if h >= 60 then T.happy elseif h >= 35 then T.accent else T.danger)
	happyL.Text = string.format("%d%%", math.floor(h + 0.5))
	local text, col = activityText(d, state)
	assignL.Text = text
	assignL.TextColor3 = col
	refreshPage(d, state)

	local hurt = Simulation.isInside(d) and d.health < d.maxHealth * 0.75
	local bkey = d.id .. ":" .. tostring(d.status) .. ":" .. tostring(d.child == true) .. ":" .. tostring(d.pregnant ~= nil) .. ":" .. tostring(hurt)
	if bkey == buttonsKey then
		return
	end
	buttonsKey = bkey
	for _, c in buttons:GetChildren() do
		if c:IsA("GuiButton") then
			c:Destroy()
		end
	end
	if d.status == "Dead" then
		local cost = Simulation.reviveCost(d)
		Kit.button({
			Text = "REVIVE", Sub = Kit.fmt(cost) .. " bolts", Icon = "health", Style = "primary", Size = UDim2.fromOffset(180, 66), Parent = buttons, Order = 1,
			OnClick = function()
				C.StateStore.action("Revive", { dwellerId = d.id })
			end,
		})
	elseif d.status == "Waiting" then
		Kit.button({
			Text = "LET IN", Icon = "assign", Style = "good", Size = UDim2.fromOffset(150, 60), Parent = buttons, Order = 1,
			OnClick = function()
				C.StateStore.action("Admit", { dwellerId = d.id })
			end,
		})
		Kit.button({
			Text = "TURN AWAY", Icon = "close", Style = "danger", Size = UDim2.fromOffset(170, 60), Parent = buttons, Order = 2,
			OnClick = function()
				C.StateStore.action("TurnAway", { dwellerId = d.id })
			end,
		})
		Kit.button({
			Text = "LOOK", Icon = "wasteland", Size = UDim2.fromOffset(110, 60), Parent = buttons, Order = 3,
			OnClick = function()
				local pos = C.SurfaceController.arrivalPosition(d.id)
				if pos then
					C.CameraController.focus(pos, 26)
				end
			end,
		})
	elseif d.status == "Arriving" then
		Kit.button({
			Text = "LOOK", Icon = "wasteland", Style = "primary", Size = UDim2.fromOffset(170, 60), Parent = buttons, Order = 1,
			OnClick = function()
				local pos = C.SurfaceController.arrivalPosition(d.id)
				if pos then
					C.CameraController.focus(pos, 30)
				end
			end,
		})
	elseif d.status == "Exploring" then
		Kit.button({
			Text = "VIEW", Icon = "wasteland", Style = "primary", Size = UDim2.fromOffset(170, 60), Parent = buttons, Order = 1,
			OnClick = function()
				C.UIController.openWasteland(d.id)
			end,
		})
		Kit.button({
			Text = "RECALL", Icon = "assign", Size = UDim2.fromOffset(170, 60), Parent = buttons, Order = 2,
			OnClick = function()
				C.StateStore.action("Recall", { dwellerId = d.id })
			end,
		})
	else
		Kit.button({
			Text = "ASSIGN", Icon = "assign", Style = "primary", Size = UDim2.fromOffset(112, 58), TextSize = 17, IconSize = 22, Parent = buttons, Order = 1,
			OnClick = function()
				C.UIController.beginAssign(d.id)
			end,
		})
		if hurt then
			-- badly hurt survivors can't explore anyway: offer a MedPatch instead
			Kit.button({
				Text = "HEAL", Sub = "1 MedPatch", Icon = "health", Style = "good", Size = UDim2.fromOffset(116, 58), TextSize = 17, IconSize = 22, Parent = buttons, Order = 2,
				OnClick = function()
					C.StateStore.action("Heal", { dwellerId = d.id })
				end,
			})
		elseif Family.canExplore(d) then
			Kit.button({
				Text = "EXPLORE", Icon = "wasteland", Size = UDim2.fromOffset(116, 58), TextSize = 17, IconSize = 22, Parent = buttons, Order = 2,
				OnClick = function()
					C.UIController.sendExplore(d.id)
				end,
			})
		end
		if not d.child then
			Kit.button({
				Text = "WEAPON", Icon = "weapons", Size = UDim2.fromOffset(110, 58), TextSize = 17, IconSize = 22, Parent = buttons, Order = 3,
				OnClick = function()
					C.UIController.openList("Weapons", d.id)
				end,
			})
			Kit.button({
				Text = "OUTFIT", Icon = "outfits", Size = UDim2.fromOffset(104, 58), TextSize = 17, IconSize = 22, Parent = buttons, Order = 4,
				OnClick = function()
					C.UIController.openList("Outfits", d.id)
				end,
			})
		end
	end
end

function DwellerPanel.open(id: string)
	dwellerId = id
	buttonsKey = ""
	pageKey = ""
	sheet.Visible = true
	portraitSig = nil
	DwellerPanel.refresh()
	sheet.Position = UDim2.new(1, 520, 0.5, 30)
	TweenService:Create(sheet, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(1, -14, 0.5, 30) }):Play()
end

function DwellerPanel.close()
	dwellerId = nil
	sheet.Visible = false
	vp:ClearAllChildren()
	portraitSig = nil
end

function DwellerPanel.current(): string?
	return dwellerId
end

function DwellerPanel.Init(controllers)
	C = controllers
	gui = Kit.screen("DwellerUI", 7)
	sheet = Kit.panel({ Size = UDim2.fromOffset(500, 660), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 30), Parent = gui, Name = "DwellerSheet" })
	sheet.Visible = false
	Kit.hazard(sheet, UDim2.new(0, 140, 0, 6), UDim2.fromOffset(22, 8))
	local frame = Kit.new("Frame", { BackgroundColor3 = Color3.fromRGB(34, 40, 48), Size = UDim2.fromOffset(170, 190), Position = UDim2.fromOffset(20, 22), Parent = sheet })
	Kit.corner(frame, 10)
	Kit.stroke(frame, T.accent, 2)
	Kit.new("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(70, 80, 92), Color3.fromRGB(26, 30, 36)), Rotation = 90, Parent = frame,
	})
	vp = Kit.new("ViewportFrame", {
		BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Ambient = Color3.fromRGB(150, 150, 160),
		LightColor = Color3.fromRGB(255, 240, 220), LightDirection = Vector3.new(-1, -1, -1), Parent = frame,
	})
	nameL = Kit.label({ Text = "", Font = Kit.Fonts.Header, TextSize = 30, Size = UDim2.fromOffset(270, 36), Position = UDim2.fromOffset(204, 22), Parent = sheet, Truncate = Enum.TextTruncate.AtEnd })
	subL = Kit.label({ Text = "", TextSize = 16, Color = T.textMuted, Size = UDim2.fromOffset(270, 22), Position = UDim2.fromOffset(204, 58), Parent = sheet, Truncate = Enum.TextTruncate.AtEnd })
	levelL = Kit.label({ Text = "", Font = Kit.Fonts.Header, TextSize = 20, Color = T.xp, Size = UDim2.fromOffset(120, 24), Position = UDim2.fromOffset(204, 90), Parent = sheet })
	local _, xs = Kit.meter({ Parent = sheet, Color = T.xp, Size = UDim2.fromOffset(160, 12), Position = UDim2.fromOffset(310, 96) })
	xpSet = xs
	Kit.icon({ Icon = "health", Color = T.health, Size = UDim2.fromOffset(22, 22), Position = UDim2.fromOffset(204, 124), Parent = sheet })
	local _, hs = Kit.meter({ Parent = sheet, Color = T.health, Size = UDim2.fromOffset(150, 14), Position = UDim2.fromOffset(234, 128) })
	hpSet = hs
	hpL = Kit.label({ Text = "", Font = Kit.Fonts.Number, TextSize = 15, Size = UDim2.fromOffset(90, 20), Position = UDim2.fromOffset(392, 124), Parent = sheet })
	Kit.icon({ Icon = "happy", Color = T.happy, Size = UDim2.fromOffset(22, 22), Position = UDim2.fromOffset(204, 156), Parent = sheet })
	local _, hps = Kit.meter({ Parent = sheet, Color = T.happy, Size = UDim2.fromOffset(150, 14), Position = UDim2.fromOffset(234, 160) })
	happySet = hps
	happyL = Kit.label({ Text = "", Font = Kit.Fonts.Number, TextSize = 15, Size = UDim2.fromOffset(90, 20), Position = UDim2.fromOffset(392, 156), Parent = sheet })
	assignL = Kit.label({ Text = "", Font = Kit.Fonts.BodyBold, TextSize = 16, Size = UDim2.fromOffset(280, 40), Position = UDim2.fromOffset(204, 182), Parent = sheet, Wrapped = true })

	-- tabs
	for i, name in { "NEEDS", "SKILLS", "PEOPLE" } do
		tabButtons[name] = Kit.button({
			Text = name, Size = UDim2.fromOffset(146, 36), TextSize = 17, Position = UDim2.fromOffset(20 + (i - 1) * 154, 226), Parent = sheet,
			OnClick = function()
				setTab(name)
			end,
		})
	end
	local function page(name: string): Frame
		local p = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(460, 300), Position = UDim2.fromOffset(20, 270), Parent = sheet, Name = name })
		pages[name] = p
		return p
	end

	-- NEEDS page
	local np = page("NEEDS")
	for i, key in Needs.LIST do
		local def = Needs.Defs[key]
		local y = (i - 1) * 32
		Kit.icon({ Icon = def.icon, Color = T.text, Size = UDim2.fromOffset(22, 22), Position = UDim2.fromOffset(0, y + 2), Parent = np })
		Kit.label({ Text = string.upper(def.name), Font = Kit.Fonts.Header, TextSize = 16, Color = T.textMuted, Size = UDim2.fromOffset(70, 24), Position = UDim2.fromOffset(28, y), Parent = np })
		local _, set = Kit.meter({ Parent = np, Size = UDim2.fromOffset(200, 14), Position = UDim2.fromOffset(100, y + 6) })
		local st = Kit.label({ Text = "", TextSize = 15, Color = T.textMuted, Size = UDim2.fromOffset(150, 24), Position = UDim2.fromOffset(310, y), Parent = np })
		needRows[key] = { set = set, state = st }
	end
	Kit.label({ Text = "ON THEIR MIND", Font = Kit.Fonts.Header, TextSize = 15, Color = T.textMuted, Size = UDim2.fromOffset(200, 20), Position = UDim2.fromOffset(0, 104), Parent = np })
	memoryList = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(460, 90), Position = UDim2.fromOffset(0, 126), Parent = np })
	Kit.list(memoryList, Enum.FillDirection.Vertical, 2)
	traitsL = Kit.label({ Text = "", Font = Kit.Fonts.BodyBold, TextSize = 16, Color = T.accent, Size = UDim2.fromOffset(460, 22), Position = UDim2.fromOffset(0, 226), Parent = np, Truncate = Enum.TextTruncate.AtEnd })
	noteL = Kit.label({ Text = "", TextSize = 15, Color = Color3.fromRGB(255, 140, 160), Size = UDim2.fromOffset(460, 22), Position = UDim2.fromOffset(0, 252), Parent = np })

	-- SKILLS page
	local sp = page("SKILLS")
	for i, key in DwellerDefinitions.STATS do
		local y = (i - 1) * 24
		local lab = Kit.label({ Text = key, Font = Kit.Fonts.Header, TextSize = 16, Color = T.textMuted, Size = UDim2.fromOffset(44, 22), Position = UDim2.fromOffset(0, y), Parent = sp })
		Kit.label({ Text = DwellerDefinitions.STAT_NAMES[key], TextSize = 14, Color = T.textMuted, Size = UDim2.fromOffset(110, 22), Position = UDim2.fromOffset(46, y), Parent = sp })
		local _, set = Kit.meter({ Parent = sp, Size = UDim2.fromOffset(240, 12), Position = UDim2.fromOffset(160, y + 5) })
		local val = Kit.label({ Text = "1", Font = Kit.Fonts.Number, TextSize = 17, Size = UDim2.fromOffset(40, 22), Position = UDim2.fromOffset(412, y), Parent = sp })
		statRows[key] = { set = set, value = val, label = lab }
	end
	bestL = Kit.label({ Text = "", TextSize = 15, Color = T.accent, Size = UDim2.fromOffset(460, 20), Position = UDim2.fromOffset(0, 222), Parent = sp })
	Kit.icon({ Icon = "weapons", Color = T.text, Size = UDim2.fromOffset(22, 22), Position = UDim2.fromOffset(0, 248), Parent = sp })
	weaponL = Kit.label({ Text = "", Font = Kit.Fonts.BodyBold, TextSize = 16, Size = UDim2.fromOffset(420, 22), Position = UDim2.fromOffset(30, 248), Parent = sp })
	Kit.icon({ Icon = "outfits", Color = T.text, Size = UDim2.fromOffset(22, 22), Position = UDim2.fromOffset(0, 274), Parent = sp })
	outfitL = Kit.label({ Text = "", Font = Kit.Fonts.BodyBold, TextSize = 16, Size = UDim2.fromOffset(420, 22), Position = UDim2.fromOffset(30, 274), Parent = sp })

	-- PEOPLE page
	local pp = page("PEOPLE")
	peopleList = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = pp })
	Kit.list(peopleList, Enum.FillDirection.Vertical, 4)

	buttons = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -40, 0, 70), Position = UDim2.new(0, 20, 1, -86), Parent = sheet })
	Kit.list(buttons, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	Kit.button({
		Icon = "close", Style = "dark", Size = UDim2.fromOffset(48, 48), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 14), Parent = sheet,
		OnClick = function()
			C.UIController.clearSelection()
		end,
	})
	setTab("NEEDS")
end

return DwellerPanel
