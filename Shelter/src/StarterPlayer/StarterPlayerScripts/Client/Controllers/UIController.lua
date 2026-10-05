--!strict
-- Orchestrates all UI and world interaction: selection, assign mode, drag & drop, menus,
-- incident banners, offline report, confirmations, Studio debug tools.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Theme = require(ReplicatedStorage.Shared.Theme)
local RoomDefinitions = require(ReplicatedStorage.Shared.RoomDefinitions)
local Simulation = require(ReplicatedStorage.Shared.Simulation)
local Resources = require(ReplicatedStorage.Shared.Resources)
local Needs = require(ReplicatedStorage.Shared.Needs)

local Ui = script.Parent.Parent:WaitForChild("Ui")
local Kit = require(Ui.Kit)
local Hud = require(Ui.Hud)
local RoomPanel = require(Ui.RoomPanel)
local DwellerPanel = require(Ui.DwellerPanel)
local ListModal = require(Ui.ListModal)
local BuildMenu = require(Ui.BuildMenu)
local ExplorePanel = require(Ui.ExplorePanel)

local UIController = {}
local T = Theme.UI
local C: any

local assigning: string? = nil
local dragging: string? = nil
local modalGui: ScreenGui

-- Selection ------------------------------------------------------------------------
function UIController.clearSelection()
	RoomPanel.close()
	DwellerPanel.close()
	C.VaultRenderer.select(nil)
	C.DwellerController.select(nil)
	if not BuildMenu.isOpen() then
		Hud.setBottomVisible(true)
	end
end

function UIController.selectRoom(id: string)
	DwellerPanel.close()
	C.DwellerController.select(nil)
	C.VaultRenderer.select(id)
	RoomPanel.open(id)
	Hud.setBottomVisible(false)
end

function UIController.selectDweller(id: string, focus: boolean?)
	RoomPanel.close()
	C.VaultRenderer.select(nil)
	C.DwellerController.select(id)
	DwellerPanel.open(id)
	local d = C.StateStore.state.dwellers[id]
	if focus and d and (d.status == "Waiting" or d.status == "Arriving") then
		local p = C.SurfaceController.arrivalPosition(id)
		if p then
			C.CameraController.focus(p, 26)
		end
	else
		-- follow the selected survivor through the shelter (panning lets go); zoom in when asked
		local p = C.DwellerController.positionOf(id)
		if p and p.Y > -900 then
			C.CameraController.focus(p + Vector3.new(0, 3, 0), if focus then 26 else nil, function()
				local q = C.DwellerController.positionOf(id)
				return if q and q.Y > -900 then q else nil
			end)
		end
	end
end

function UIController.beginAssign(dwellerId: string)
	local d = C.StateStore.state.dwellers[dwellerId]
	if not d then
		return
	end
	assigning = dwellerId
	DwellerPanel.close()
	Hud.setHint("Tap a room to send " .. d.name .. " there", function()
		assigning = nil
		Hud.setHint(nil)
	end)
end

function UIController.openPicker(roomId: string)
	ListModal.open("Pick", roomId)
end

function UIController.openList(kind: string, ctx: any?)
	ListModal.open(kind, ctx)
end

function UIController.closeBuild()
	C.BuildController.exit()
	BuildMenu.close()
	Hud.setHint(nil)
	Hud.setBottomVisible(true)
end

function UIController.openWasteland(id: string?)
	UIController.clearSelection()
	if BuildMenu.isOpen() then
		UIController.closeBuild()
	end
	ListModal.close()
	Hud.setBottomVisible(false)
	Hud.setHint(nil)
	local focus = ExplorePanel.open(id)
	C.WastelandController.open(focus)
end

function UIController.closeWasteland()
	ExplorePanel.close()
	C.WastelandController.close()
	Hud.setBottomVisible(true)
end

function UIController.sendExplore(id: string)
	ExplorePanel.sendDialog(id, modalGui)
end

function UIController.openBuild()
	UIController.onMenu("Build")
end

function UIController.onMenu(key: string)
	if key == "Wasteland" then
		UIController.openWasteland(nil)
	elseif key == "Build" then
		UIController.clearSelection()
		Hud.setBottomVisible(false)
		BuildMenu.open()
	elseif key == "Survivors" then
		ListModal.open("Survivors")
	elseif key == "Weapons" or key == "Outfits" then
		ListModal.open(key, DwellerPanel.current())
	elseif key == "Quests" then
		ListModal.open("Quests")
	elseif key == "Shop" then
		ListModal.open("Shop")
	end
end

-- Confirm dialog ----------------------------------------------------------------------
function UIController.confirm(text: string, onYes: () -> ())
	local shade = Kit.new("TextButton", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, Text = "", AutoButtonColor = false, Size = UDim2.fromScale(1, 1), Parent = modalGui })
	local card = Kit.panel({ Size = UDim2.fromOffset(520, 220), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Parent = shade })
	Kit.label({ Text = text, Font = Kit.Fonts.BodyBold, TextSize = 22, Wrapped = true, XAlign = Enum.TextXAlignment.Center, Size = UDim2.new(1, -60, 0, 100), Position = UDim2.fromOffset(30, 24), Parent = card })
	Kit.button({ Text = "CANCEL", Size = UDim2.fromOffset(180, 60), Position = UDim2.new(0.5, -195, 1, -84), Parent = card, OnClick = function()
		shade:Destroy()
	end })
	Kit.button({ Text = "CONFIRM", Style = "danger", Size = UDim2.fromOffset(180, 60), Position = UDim2.new(0.5, 15, 1, -84), Parent = card, OnClick = function()
		shade:Destroy()
		onYes()
	end })
	Kit.pop(card)
end

-- Resource and colony warnings, most urgent first (shown under the top bar).
local alertAcc = 0
function UIController.refreshAlerts()
	if os.clock() - alertAcc < 1 then
		return
	end
	alertAcc = os.clock()
	local state = C.StateStore.state
	local res, caps, flow = state.resources or {}, state.caps or {}, state.flow or {}
	local list = {}
	local function add(text: string, severity: string, rank: number, onClick: (() -> ())?)
		table.insert(list, { text = text, severity = severity, rank = rank, onClick = onClick })
	end
	local function focusRoomOf(typeId: string)
		return function()
			for id, r in state.rooms do
				if r.type == typeId then
					UIController.selectRoom(id)
					local c = C.VaultRenderer.roomCenter(id)
					if c then
						C.CameraController.focus(c, 40)
					end
					return
				end
			end
			UIController.openBuild()
		end
	end
	if (state.powerFactor or 1) < 0.99 then
		add(string.format("POWER CRITICAL - %d%% SUPPLY", math.floor((state.powerFactor or 1) * 100)), "critical", 1, focusRoomOf("Power"))
	end
	local producer = { Power = "Power", Water = "Water", Food = "Food", Materials = "Workshop", MedPatch = "Infirmary" }
	for i, key in Resources.LIST do
		local def = Resources.Defs[key]
		local v, cap = res[key] or 0, caps[key] or 1
		local f = flow[key] or { prod = 0, use = 0 }
		local net = f.prod - f.use
		local name = string.upper(def.name)
		if key ~= "Power" or (state.powerFactor or 1) >= 0.99 then
			if v / cap < def.critical and net < 0 then
				add(if key == "Food" then "FOOD SHORTAGE" else name .. " CRITICAL", "critical", 2 + i * 0.1, focusRoomOf(producer[key]))
			elseif v / cap < def.low and net < 0 then
				add(name .. " LOW", "warn", 4 + i * 0.1, focusRoomOf(producer[key]))
			end
		end
		if v >= cap - 0.5 and f.prod > 0.1 then
			add(name .. " STORAGE FULL", "info", 7 + i * 0.1, function()
				UIController.openBuild()
			end)
		end
	end
	local injured, hungry, thirsty, tired = 0, 0, 0, 0
	for _, d in state.dwellers do
		if Simulation.isInside(d) then
			if d.health < d.maxHealth * 0.5 then
				injured += 1
			end
			local n = d.needs
			if n then
				if n.Hunger < 20 then
					hungry += 1
				end
				if n.Thirst < 22 then
					thirsty += 1
				end
				if n.Energy < 12 then
					tired += 1
				end
			end
		end
	end
	if thirsty > 0 then
		add(thirsty .. (if thirsty == 1 then " SURVIVOR THIRSTY" else " SURVIVORS THIRSTY"), "warn", 3)
	end
	if hungry > 0 then
		add(hungry .. (if hungry == 1 then " SURVIVOR HUNGRY" else " SURVIVORS HUNGRY"), "warn", 3.2)
	end
	if injured > 0 then
		add(injured .. (if injured == 1 then " SURVIVOR INJURED" else " SURVIVORS INJURED"), "warn", 5, focusRoomOf("Infirmary"))
		if (res.MedPatch or 0) < 1 then
			add("MEDICINE LOW", "warn", 5.5, focusRoomOf("Infirmary"))
		end
	end
	if tired > 0 then
		add(tired .. " EXHAUSTED", "info", 6, focusRoomOf("Living"))
	end
	local d = state.derived or {}
	if (d.population or 0) >= (d.housing or 1) then
		add("HOUSING FULL", "info", 6.5, focusRoomOf("Living"))
	end
	table.sort(list, function(a, b)
		return a.rank < b.rank
	end)
	Hud.setAlerts(list)
	local _ = Needs
end

local function offlineReport(p)
	local shade = Kit.new("TextButton", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, Text = "", AutoButtonColor = false, Size = UDim2.fromScale(1, 1), Parent = modalGui })
	local card = Kit.panel({ Size = UDim2.fromOffset(560, 330), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Parent = shade })
	Kit.hazard(card, UDim2.new(0, 160, 0, 6), UDim2.fromOffset(22, 8))
	Kit.label({ Text = "WHILE YOU WERE AWAY", Font = Kit.Fonts.Header, TextSize = 30, Size = UDim2.new(1, -40, 0, 40), Position = UDim2.fromOffset(24, 20), Parent = card })
	Kit.label({ Text = "Your shelter ran for " .. Kit.fmtTime(p.seconds), TextSize = 19, Color = T.textMuted, Size = UDim2.new(1, -40, 0, 26), Position = UDim2.fromOffset(24, 62), Parent = card })
	local list = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -48, 0, 150), Position = UDim2.fromOffset(24, 98), Parent = card })
	Kit.list(list, Enum.FillDirection.Vertical, 6)
	for i, key in { "Power", "Food", "Water" } do
		local f = Kit.new("Frame", { BackgroundColor3 = T.panelInner, Size = UDim2.new(1, 0, 0, 42), LayoutOrder = i, Parent = list })
		Kit.corner(f, 8)
		Kit.icon({ Icon = string.lower(key), Color = Theme.Resource[key], Size = UDim2.fromOffset(30, 30), Position = UDim2.fromOffset(10, 6), Parent = f })
		local prod = (p.produced and p.produced[key]) or 0
		local delta = (p.delta and p.delta[key]) or 0
		Kit.label({ Text = string.format("Produced %s  ·  net %s%s", Kit.fmt(prod), if delta >= 0 then "+" else "", Kit.fmt(delta)), Font = Kit.Fonts.Number, TextSize = 20, Size = UDim2.new(1, -60, 1, 0), Position = UDim2.fromOffset(50, 0), Parent = f, Color = if delta < 0 then T.danger else T.text })
	end
	Kit.button({ Text = "BACK TO WORK", Style = "primary", Size = UDim2.fromOffset(240, 58), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Parent = card, OnClick = function()
		shade:Destroy()
	end })
	Kit.pop(card)
end

-- Banners -------------------------------------------------------------------------------
local function refreshBanner()
	local state = C.StateStore.state
	local raid = state.raid
	if raid then
		local count = 0
		for _ in raid.raiders or {} do
			count += 1
		end
		local roomId = raid.roomId
		local room = roomId and state.rooms[roomId]
		local where = if room then RoomDefinitions.Types[room.type].name else "the shelter"
		local text, frac
		if raid.phase == "door" then
			text, frac = string.format("%d RAIDERS AT THE BLAST DOOR", count), raid.doorHp / math.max(1, raid.doorMax)
		elseif raid.phase == "moving" then
			text = string.format("%d RAIDERS ON THE MOVE", count)
		else
			text = string.format("%d RAIDERS IN THE %s", count, string.upper(where))
		end
		Hud.setBanner(text, T.danger, frac, function()
			local id = if raid.phase == "moving" then raid.moveTo else roomId
			local c = id and C.VaultRenderer.roomCenter(id)
			if c then
				C.CameraController.focus(c, 34)
			end
		end)
		C.LightingController.setAlarm(true)
		return
	end
	C.LightingController.setAlarm(false)
	for id, r in state.rooms do
		if r.incident then
			local name = RoomDefinitions.Types[r.type].name
			local kind = r.incident.kind
			local text, color
			if kind == "Breakdown" then
				text = (if r.type == "Power" then "POWER FAILURE - " else "BREAKDOWN - ") .. string.upper(name)
					.. (if r.incident.paid then " (REPAIRING)" else " - TAP TO REPAIR")
				color = Color3.fromRGB(255, 196, 60)
			else
				local what = if kind == "Rats" then "BURROW RATS" elseif kind == "Roaches" then "RUST ROACHES" else "FIRE"
				text = what .. " IN THE " .. string.upper(name)
				color = if kind == "Fire" then Color3.fromRGB(255, 140, 60) else Color3.fromRGB(150, 200, 80)
			end
			Hud.setBanner(text, color, r.incident.hp / math.max(1, r.incident.maxHp), function()
				local c = C.VaultRenderer.roomCenter(id)
				if c then
					C.CameraController.focus(c, 34)
				end
				if kind == "Breakdown" then
					UIController.selectRoom(id)
				end
			end)
			return
		end
	end
	Hud.setBanner(nil)
end

-- World input ----------------------------------------------------------------------------
local function onTap(_screen: Vector2, hit: any)
	if C.WastelandController.active then
		return
	end
	if C.BuildController.handleTap(hit) then
		return
	end
	if assigning then
		if hit and hit.kind == "room" then
			local id = assigning
			assigning = nil
			Hud.setHint(nil)
			local ok = C.StateStore.action("Assign", { dwellerId = id, roomId = hit.id })
			if ok then
				UIController.selectDweller(id)
			end
		end
		return
	end
	if hit and hit.kind == "dweller" then
		UIController.selectDweller(hit.id)
	elseif hit and hit.kind == "room" then
		local room = C.StateStore.state.rooms[hit.id]
		if room and room.readySince and C.EffectsController.hasBubble(hit.id) and RoomPanel.current() ~= hit.id then
			C.EffectsController.collect(hit.id)
		else
			UIController.selectRoom(hit.id)
		end
	else
		UIController.clearSelection()
	end
end

local dragRoom: string? = nil
local function onDragStart(id: string, _pos: Vector2)
	if C.WastelandController.active then
		return
	end
	if C.DwellerController.beginDrag(id) then
		dragging = id
		local d = C.StateStore.state.dwellers[id]
		Hud.setHint("Drop " .. (d and d.name or "them") .. " on a room", nil)
	end
end

local function onDragMove(pos: Vector2)
	if not dragging then
		return
	end
	local w = C.CameraController.screenToWorld(pos)
	C.DwellerController.dragTo(dragging, w)
	local hit = C.InputController.pick(pos, true)
	local rid = hit and hit.kind == "room" and hit.id or nil
	if rid ~= dragRoom then
		dragRoom = rid
		C.VaultRenderer.select(rid)
		local room = rid and C.StateStore.state.rooms[rid]
		if room then
			local def = RoomDefinitions.Types[room.type]
			local cap = Simulation.capacity(room)
			local txt = def.name
			if cap > 0 then
				txt ..= string.format("  ·  %d/%d crew", #room.assigned, cap)
			end
			if def.stat then
				local d = C.StateStore.state.dwellers[dragging]
				txt ..= "  ·  " .. def.stat .. " " .. (d and Simulation.stat(d, def.stat) or "?")
			end
			Hud.setHint(txt, nil)
		end
	end
end

local function onDragEnd(_pos: Vector2, hit: any)
	local id = dragging
	dragging = nil
	dragRoom = nil
	Hud.setHint(nil)
	C.VaultRenderer.select(nil)
	if not id then
		return
	end
	C.DwellerController.endDrag(id)
	if hit and hit.kind == "room" then
		C.StateStore.action("Assign", { dwellerId = id, roomId = hit.id })
	end
end

-- Debug (Studio only) ---------------------------------------------------------------------
local function debugStrip()
	if not RunService:IsStudio() then
		return
	end
	local g = Kit.screen("DebugUI", 4)
	local f = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(140, 610), AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -12), Parent = g })
	Kit.list(f, Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Bottom)
	for i, a in { { "FIRE", "Fire" }, { "RAID", "Raid" }, { "+1000", "Bolts" }, { "ARRIVAL", "Arrival" }, { "EXPLORE +2.5m", "ExploreFF" },
		{ "ROMANCE", "Romance" }, { "FAMILY +5m", "FamilyFF" }, { "RATS", "Rats" }, { "ROACHES", "Roaches" }, { "THREAT +30m", "Pressure" },
		{ "BREAKDOWN", "Breakdown" } } do
		Kit.button({ Text = a[1], Size = UDim2.fromOffset(136, 40), TextSize = 15, Parent = f, Order = i, OnClick = function()
			C.StateStore.action("Debug", { kind = a[2], roomId = RoomPanel.current() })
		end })
	end
	Kit.label({ Text = "STUDIO DEBUG", Font = Kit.Fonts.Header, TextSize = 14, Color = T.textMuted, Size = UDim2.fromOffset(110, 18), Parent = f, Order = 0 })
end

function UIController.Init(controllers)
	C = controllers
	C.Hud = Hud
	Hud.Init(controllers)
	RoomPanel.Init(controllers)
	DwellerPanel.Init(controllers)
	ListModal.Init(controllers)
	BuildMenu.Init(controllers)
	ExplorePanel.Init(controllers)
	modalGui = Kit.screen("ModalUI", 20)
	debugStrip()
end

function UIController.Start()
	local S = C.StateStore
	S.Snapshot:Connect(function(state)
		Hud.updateResources(state)
		refreshBanner()
		local entrance
		for _, r in state.rooms do
			if r.type == "Entrance" then
				entrance = r
			end
		end
		if entrance then
			local c = C.VaultRenderer.roomCenter(entrance.id)
			if c then
				C.CameraController.focus(c + Vector3.new(14, -10, 0), 62)
			end
		end
		if state.mockSave then
			task.delay(2, function()
				Hud.toast("Studio test session: progress is kept in memory only (publish to enable saving).", "warn")
			end)
		end
	end)
	S.Resources:Connect(function(state)
		Hud.updateResources(state)
		UIController.refreshAlerts()
	end)
	S.Toast:Connect(function(p)
		Hud.toast(p.text, p.tone)
	end)
	S.RoomChanged:Connect(function(room)
		if RoomPanel.current() == room.id then
			RoomPanel.refresh()
		end
		refreshBanner()
		BuildMenu.refresh()
	end)
	S.RoomRemoved:Connect(function(id)
		if RoomPanel.current() == id then
			UIController.clearSelection()
		end
	end)
	S.DwellerChanged:Connect(function(d)
		if DwellerPanel.current() == d.id then
			DwellerPanel.refresh()
		end
		local rp = RoomPanel.current()
		if rp then
			RoomPanel.refresh()
		end
		if ListModal.isOpen() then
			ListModal.refresh()
		end
	end)
	-- wanderers waiting outside: HUD chip that jumps to the line and opens the first one
	local function refreshQueue()
		local first, n = nil, 0
		for _, d in C.StateStore.state.dwellers do
			if d.status == "Waiting" then
				n += 1
				if not first or d.approach.start < first.approach.start then
					first = d
				end
			end
		end
		Hud.setQueue(n, function()
			C.CameraController.focus(C.SurfaceController.doorPosition(), 30)
			if first then
				UIController.selectDweller(first.id)
			end
		end)
	end
	S.Snapshot:Connect(refreshQueue)
	S.DwellerChanged:Connect(refreshQueue)
	S.DwellerRemoved:Connect(function(id)
		refreshQueue()
		if DwellerPanel.current() == id then
			UIController.clearSelection()
		end
		if ListModal.isOpen() then
			ListModal.refresh()
		end
	end)
	S.Inventory:Connect(function()
		if ListModal.isOpen() then
			ListModal.refresh()
		end
	end)
	S.Raid:Connect(refreshBanner)
	S.RaidEnd:Connect(refreshBanner)
	S.Fire:Connect(refreshBanner)
	S.IncidentEnd:Connect(refreshBanner)
	S.Incident:Connect(refreshBanner)
	S.Offline:Connect(offlineReport)
	S.ExploreEnded:Connect(function(_id, p)
		ExplorePanel.summary(p, modalGui)
	end)
	ExplorePanel.Start()
	local I = C.InputController
	I.Tap:Connect(onTap)
	I.DragStart:Connect(onDragStart)
	I.DragMove:Connect(onDragMove)
	I.DragEnd:Connect(onDragEnd)
	I.Cancel:Connect(function()
		if assigning then
			assigning = nil
			Hud.setHint(nil)
		elseif BuildMenu.isOpen() then
			UIController.closeBuild()
		else
			UIController.clearSelection()
		end
	end)
	C.BuildController.Changed:Connect(function(active)
		if not active then
			Hud.setHint(nil)
			BuildMenu.refresh()
		end
	end)
	S.DwellerStats:Connect(function()
		if DwellerPanel.current() then
			DwellerPanel.refresh()
		end
		if RoomPanel.current() then
			RoomPanel.refresh()
		end
	end)
end

return UIController
