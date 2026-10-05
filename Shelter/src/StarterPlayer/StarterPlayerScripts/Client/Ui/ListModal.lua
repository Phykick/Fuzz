--!strict
-- Generic modal: Survivors roster, crew picker, Weapons, Outfits, Objectives, Shop.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.Theme)
local ItemDefinitions = require(ReplicatedStorage.Shared.ItemDefinitions)
local RoomDefinitions = require(ReplicatedStorage.Shared.RoomDefinitions)
local DwellerDefinitions = require(ReplicatedStorage.Shared.DwellerDefinitions)
local Simulation = require(ReplicatedStorage.Shared.Simulation)
local Kit = require(script.Parent.Kit)

local ListModal = {}
local T = Theme.UI
local C: any

local gui: ScreenGui
local shade: TextButton
local card: ImageLabel
local titleL: TextLabel
local tabs: Frame
local scroll: ScrollingFrame
local mode: string? = nil
local context: any = nil
local sortKey = "level"

local function clear()
	for _, c in scroll:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	for _, c in tabs:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end

local function row(height: number, order: number): Frame
	local f = Kit.new("Frame", { BackgroundColor3 = T.panelInner, Size = UDim2.new(1, -8, 0, height), LayoutOrder = order, Parent = scroll })
	Kit.corner(f, 10)
	return f
end

local function survivorRow(d: any, order: number, statKey: string?, onTap: () -> ())
	local f = row(70, order)
	local b = Kit.new("TextButton", { BackgroundTransparency = 1, Text = "", Size = UDim2.fromScale(1, 1), Parent = f })
	local skin = Color3.fromHex((d.appearance and d.appearance.skin) or "D8A47F")
	local face = Kit.new("Frame", { BackgroundColor3 = skin, Size = UDim2.fromOffset(50, 50), Position = UDim2.fromOffset(10, 10), Parent = f })
	Kit.corner(face, 25)
	Kit.stroke(face, if d.status == "Dead" then T.danger else T.border, 2)
	local initials = (d.name or "?"):gsub("(%a)%a*%s*", "%1"):sub(1, 2)
	Kit.label({ Text = initials, Font = Kit.Fonts.Header, TextSize = 20, Color = Color3.fromRGB(30, 24, 20), XAlign = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), Parent = face })
	Kit.label({ Text = d.name, Font = Kit.Fonts.Header, TextSize = 22, Size = UDim2.fromOffset(260, 28), Position = UDim2.fromOffset(72, 6), Parent = f })
	local room = d.roomId and C.StateStore.state.rooms[d.roomId]
	local where = if d.status == "Dead" then "Deceased"
		elseif d.status == "Arriving" then "On the way"
		elseif d.status == "Waiting" then "At the door"
		elseif d.status == "Exploring" then "In the wasteland"
		elseif room then RoomDefinitions.Types[room.type].name
		else "Unassigned"
	if d.child then
		where ..= "  ·  child"
	elseif d.pregnant then
		where ..= "  ·  expecting"
	end
	Kit.label({ Text = "LV " .. d.level .. "  ·  " .. where, TextSize = 16, Color = T.textMuted, Size = UDim2.fromOffset(300, 22), Position = UDim2.fromOffset(72, 36), Parent = f })
	local stats = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(330, 50), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 10), Parent = f })
	Kit.list(stats, Enum.FillDirection.Horizontal, 3, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)
	for i, key in DwellerDefinitions.STATS do
		local hi = key == statKey
		local cell = Kit.new("Frame", { BackgroundColor3 = if hi then T.accent else T.panel, Size = UDim2.fromOffset(34, 46), LayoutOrder = i, Parent = stats })
		Kit.corner(cell, 6)
		local fg = if hi then Color3.fromRGB(28, 24, 18) else T.textMuted
		Kit.label({ Text = key, Font = Kit.Fonts.Header, TextSize = 11, Color = fg, XAlign = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 3), Parent = cell })
		Kit.label({ Text = tostring(Simulation.stat(d, key)), Font = Kit.Fonts.Number, TextSize = 20, Color = if hi then fg else T.text, XAlign = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 18), Parent = cell })
	end
	b.Activated:Connect(function()
		Kit.press(f)
		onTap()
	end)
end

local function itemRow(item: any, order: number, dwellerId: string?)
	local def = ItemDefinitions.get(item.def)
	if not def then
		return
	end
	local rarity = ItemDefinitions.Rarity[def.rarity]
	local f = row(66, order)
	Kit.stroke(f, rarity.color, 2, 0.4)
	Kit.icon({ Icon = if def.kind == "Weapon" then "weapons" else "outfits", Color = rarity.color, Size = UDim2.fromOffset(40, 40), Position = UDim2.fromOffset(12, 13), Parent = f })
	Kit.label({ Text = def.name, Font = Kit.Fonts.Header, TextSize = 21, Color = rarity.color, Size = UDim2.fromOffset(300, 26), Position = UDim2.fromOffset(62, 6), Parent = f })
	local detail
	if def.kind == "Weapon" then
		detail = string.format("%s  ·  DMG %d  ·  %.1f/s  ·  CRIT %d%%", def.rarity, def.damage, def.fireRate, math.floor(def.crit * 100))
	else
		local parts = { def.rarity }
		for s, v in def.stats do
			table.insert(parts, "+" .. v .. " " .. s)
		end
		detail = table.concat(parts, "  ·  ")
	end
	local holder = item.equippedBy and C.StateStore.state.dwellers[item.equippedBy]
	if holder then
		detail ..= "  ·  on " .. holder.name
	end
	Kit.label({ Text = detail, TextSize = 15, Color = T.textMuted, Size = UDim2.fromOffset(460, 22), Position = UDim2.fromOffset(62, 34), Parent = f })
	if dwellerId then
		local equipped = item.equippedBy == dwellerId
		Kit.button({
			Text = if equipped then "EQUIPPED" else "EQUIP", Style = if equipped then "dark" else "primary",
			Size = UDim2.fromOffset(120, 46), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Parent = f,
			OnClick = function()
				if not equipped then
					local ok = C.StateStore.action("Equip", { dwellerId = dwellerId, itemId = item.id })
					if ok then
						ListModal.close()
					end
				end
			end,
		})
	end
end

local OBJECTIVES = {
	{ text = "Build a new room", stat = "built", goal = 1 },
	{ text = "Build 5 rooms", stat = "built", goal = 5 },
	{ text = "Collect 500 resources by tapping", stat = "collected", goal = 500 },
	{ text = "Welcome 3 new survivors", stat = "arrivals", goal = 3 },
	{ text = "Put out 2 fires", stat = "fires", goal = 2 },
	{ text = "Repel a raider attack", stat = "raids", goal = 1 },
}

local function tab(text: string, key: string)
	Kit.button({
		Text = text, Style = if sortKey == key then "primary" else "dark", Size = UDim2.fromOffset(86, 40), Parent = tabs, TextSize = 16,
		OnClick = function()
			sortKey = key
			ListModal.refresh()
		end,
	})
end

function ListModal.refresh()
	if not mode then
		return
	end
	clear()
	local state = C.StateStore.state
	if mode == "Survivors" or mode == "Pick" then
		local statKey = nil
		if mode == "Pick" then
			local room = state.rooms[context]
			statKey = room and RoomDefinitions.Types[room.type].stat
			titleL.Text = "ASSIGN TO " .. string.upper(room and RoomDefinitions.Types[room.type].name or "")
		else
			titleL.Text = "SURVIVORS"
			tab("LEVEL", "level")
			tab("NAME", "name")
			for _, k in DwellerDefinitions.STATS do
				tab(k, k)
			end
		end
		local list = {}
		for _, d in state.dwellers do
			local ctxRoom = context and state.rooms[context]
			local workRoom = ctxRoom ~= nil and RoomDefinitions.Types[ctxRoom.type].slots > 0
			if mode ~= "Pick" or (d.status ~= "Dead" and d.status ~= "Arriving" and d.status ~= "Exploring"
				and d.roomId ~= context and not (d.child and workRoom)) then
				table.insert(list, d)
			end
		end
		local key = if mode == "Pick" then (statKey or "level") else sortKey
		table.sort(list, function(a, b)
			if key == "name" then
				return a.name < b.name
			elseif key == "level" then
				return if a.level == b.level then a.name < b.name else a.level > b.level
			end
			local va, vb = Simulation.stat(a, key), Simulation.stat(b, key)
			return if va == vb then a.level > b.level else va > vb
		end)
		for i, d in list do
			survivorRow(d, i, statKey or (if sortKey ~= "level" and sortKey ~= "name" then sortKey else nil), function()
				if mode == "Pick" then
					local ok = C.StateStore.action("Assign", { dwellerId = d.id, roomId = context })
					if ok then
						ListModal.close()
					end
				else
					ListModal.close()
					C.UIController.selectDweller(d.id, true)
				end
			end)
		end
		if #list == 0 then
			Kit.label({ Text = "Nobody available.", TextSize = 20, Color = T.textMuted, Size = UDim2.new(1, 0, 0, 40), Parent = scroll })
		end
	elseif mode == "Weapons" or mode == "Outfits" then
		local kind = if mode == "Weapons" then "Weapon" else "Outfit"
		local d = context and state.dwellers[context]
		titleL.Text = if d then string.upper(mode) .. " FOR " .. string.upper(d.name) else string.upper(mode)
		local items = {}
		for _, item in state.inventory do
			local def = ItemDefinitions.get(item.def)
			if def and def.kind == kind then
				table.insert(items, item)
			end
		end
		table.sort(items, function(a, b)
			local da, db = ItemDefinitions.get(a.def), ItemDefinitions.get(b.def)
			local ra, rb = ItemDefinitions.Rarity[da.rarity].order, ItemDefinitions.Rarity[db.rarity].order
			return if ra == rb then da.name < db.name else ra > rb
		end)
		for i, item in items do
			itemRow(item, i, context)
		end
		if #items == 0 then
			Kit.label({ Text = "None in storage. Defeat raiders to find gear.", TextSize = 20, Color = T.textMuted, Size = UDim2.new(1, 0, 0, 40), Parent = scroll })
		end
	elseif mode == "Quests" then
		titleL.Text = "OBJECTIVES"
		local stats = (state.progression and state.progression.stats) or {}
		for i, o in OBJECTIVES do
			local v = stats[o.stat] or 0
			local f = row(64, i)
			local done = v >= o.goal
			Kit.icon({ Icon = if done then "star" else "quests", Color = if done then T.accent else T.textMuted, Size = UDim2.fromOffset(34, 34), Position = UDim2.fromOffset(14, 15), Parent = f })
			Kit.label({ Text = o.text, Font = Kit.Fonts.BodyBold, TextSize = 19, Color = if done then T.accent else T.text, Size = UDim2.fromOffset(420, 26), Position = UDim2.fromOffset(60, 6), Parent = f })
			local _, set = Kit.meter({ Parent = f, Color = if done then T.good else T.accent, Size = UDim2.fromOffset(300, 10), Position = UDim2.fromOffset(60, 40) })
			set(v / o.goal)
			Kit.label({ Text = math.min(v, o.goal) .. " / " .. o.goal, Font = Kit.Fonts.Number, TextSize = 16, Size = UDim2.fromOffset(100, 20), Position = UDim2.fromOffset(372, 34), Parent = f })
		end
	elseif mode == "Shop" then
		titleL.Text = "SUPPLY DEPOT"
		local f = row(150, 1)
		Kit.icon({ Icon = "shop", Color = T.accent, Size = UDim2.fromOffset(80, 80), Position = UDim2.fromOffset(20, 35), Parent = f })
		Kit.label({ Text = "The trader caravan hasn't reached this shelter yet.", Font = Kit.Fonts.BodyBold, TextSize = 21, Size = UDim2.new(1, -130, 0, 60), Position = UDim2.fromOffset(120, 30), Wrapped = true, Parent = f })
		Kit.label({ Text = "Coming in milestone 2: supply crates, rare outfits and pets.", TextSize = 17, Color = T.textMuted, Size = UDim2.new(1, -130, 0, 50), Position = UDim2.fromOffset(120, 88), Wrapped = true, Parent = f })
	end
end

function ListModal.open(m: string, ctx: any?)
	if not shade.Visible then
		Kit.sound("open")
	end
	mode = m
	context = ctx
	shade.Visible = true
	ListModal.refresh()
	Kit.pop(card)
end

function ListModal.close()
	if shade.Visible then
		Kit.sound("close")
	end
	mode = nil
	shade.Visible = false
end

function ListModal.isOpen(): boolean
	return mode ~= nil
end

function ListModal.Init(controllers)
	C = controllers
	gui = Kit.screen("InventoryUI", 9)
	shade = Kit.new("TextButton", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, Text = "", AutoButtonColor = false, Size = UDim2.fromScale(1, 1), Visible = false, Parent = gui })
	shade.Activated:Connect(ListModal.close)
	card = Kit.panel({ Size = UDim2.fromOffset(860, 620), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), Parent = shade })
	Kit.hazard(card, UDim2.new(0, 160, 0, 6), UDim2.fromOffset(22, 8))
	titleL = Kit.label({ Text = "", Font = Kit.Fonts.Header, TextSize = 30, Size = UDim2.fromOffset(600, 40), Position = UDim2.fromOffset(24, 18), Parent = card })
	Kit.button({ Icon = "close", Size = UDim2.fromOffset(52, 52), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 14), Parent = card, OnClick = ListModal.close })
	tabs = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -48, 0, 44), Position = UDim2.fromOffset(24, 66), Parent = card })
	Kit.list(tabs, Enum.FillDirection.Horizontal, 6)
	scroll = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1, Size = UDim2.new(1, -40, 1, -134), Position = UDim2.fromOffset(24, 116),
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 8,
		ScrollBarImageColor3 = T.accent, BorderSizePixel = 0, Parent = card,
	})
	Kit.list(scroll, Enum.FillDirection.Vertical, 8)
end

return ListModal
