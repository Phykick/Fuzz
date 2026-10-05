--!strict
-- ExplorationUI: explorer tabs, live journal, status + loot bar, send-out dialog, return summary.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Theme = require(ReplicatedStorage.Shared.Theme)
local Exploration = require(ReplicatedStorage.Shared.Exploration)
local ItemDefinitions = require(ReplicatedStorage.Shared.ItemDefinitions)
local Kit = require(script.Parent.Kit)

local ExplorePanel = {}
local T = Theme.UI
local C: any

local gui: ScreenGui
local root: Frame
local tabs: Frame
local journal: ScrollingFrame
local status: ImageLabel
local nameL: TextLabel
local hpSet: (number, Color3?) -> ()
local timeL: TextLabel
local dangerL: TextLabel
local lootRow: Frame
local actionHost: Frame
local empty: ImageLabel
local focusId: string? = nil
local lastLogCount = -1
local lastActionKey = ""

local DANGER = { "LOW", "LOW", "GUARDED", "GUARDED", "ELEVATED", "ELEVATED", "HIGH", "HIGH", "SEVERE", "SEVERE", "EXTREME" }

local function explorers(): { string }
	local list = {}
	for id in C.StateStore.state.exploration or {} do
		table.insert(list, id)
	end
	table.sort(list)
	return list
end

local function lootChip(parent: Instance, icon: string?, text: string, color: Color3, order: number)
	local f = Kit.new("Frame", { BackgroundColor3 = T.panelInner, Size = UDim2.fromOffset(0, 34), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = order, Parent = parent })
	Kit.corner(f, 8)
	Kit.pad(f, 8, 0)
	Kit.list(f, Enum.FillDirection.Horizontal, 5, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	if icon then
		Kit.icon({ Icon = icon, Color = color, Size = UDim2.fromOffset(22, 22), Parent = f, Order = 1 })
	end
	Kit.label({ Text = text, Font = Kit.Fonts.Number, TextSize = 18, Color = color, Size = UDim2.fromOffset(0, 26), AutoSize = Enum.AutomaticSize.X, Parent = f, Order = 2 })
end

local function rebuildTabs()
	for _, c in tabs:GetChildren() do
		if c:IsA("GuiButton") then
			c:Destroy()
		end
	end
	for i, id in explorers() do
		local d = C.StateStore.state.dwellers[id]
		if d then
			local rec = C.StateStore.state.exploration[id]
			Kit.button({
				Text = string.upper(d.name:match("^(%S+)") or d.name), Style = if id == focusId then "primary" else "dark",
				Icon = if rec and rec.dead then "raid" elseif rec and rec.returning then "assign" else "wasteland",
				Size = UDim2.fromOffset(170, 50), TextSize = 17, Parent = tabs, Order = i,
				OnClick = function()
					ExplorePanel.focus(id)
				end,
			})
		end
	end
end

local function rebuildJournal(rec)
	for _, c in journal:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	if not rec then
		return
	end
	local n = #rec.log
	for i = n, 1, -1 do
		local e = rec.log[i]
		local def = Exploration.Events[e.k]
		local f = Kit.new("Frame", { BackgroundColor3 = T.panelInner, BackgroundTransparency = 0.1, Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = n - i, Parent = journal })
		Kit.corner(f, 8)
		Kit.pad(f, 10, 8)
		local tone = if e.k == "Death" or (e.dmg and e.dmg > 0) then T.danger elseif e.k == "Return" or e.k == "Heal" then T.good else T.accent
		Kit.icon({ Icon = def and def.icon or "info", Color = tone, Size = UDim2.fromOffset(26, 26), Parent = f })
		local col = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -36, 0, 0), Position = UDim2.fromOffset(36, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = f })
		Kit.list(col, Enum.FillDirection.Vertical, 2)
		local stamp = Kit.fmtTime(math.max(0, (e.t or rec.start) - rec.start))
		Kit.label({
			Text = "<font color=\"#A9A291\">" .. stamp .. "</font>  " .. (e.text or ""), Rich = true, Wrapped = true, TextSize = 16,
			Size = UDim2.new(1, 0, 0, 0), AutoSize = Enum.AutomaticSize.Y, Parent = col, Order = 1,
		})
		local loot = e.loot or {}
		local parts = {}
		if loot.Bolts and loot.Bolts ~= 0 then
			table.insert(parts, (if loot.Bolts > 0 then "+" else "") .. loot.Bolts .. " bolts")
		end
		for _, k in { "Food", "Water", "MedPatch", "Scrap" } do
			if loot[k] then
				table.insert(parts, "+" .. loot[k] .. " " .. string.lower(k))
			end
		end
		if loot.item then
			local def2 = ItemDefinitions.get(loot.item)
			if def2 then
				table.insert(parts, def2.name)
			end
		end
		if loot.recruit then
			table.insert(parts, "+1 survivor")
		end
		if e.dmg and e.dmg > 0 then
			table.insert(parts, "-" .. math.floor(e.dmg) .. " hp")
		end
		if e.xp and e.xp > 0 then
			table.insert(parts, "+" .. e.xp .. " xp")
		end
		if #parts > 0 then
			Kit.label({ Text = table.concat(parts, "  ·  "), Font = Kit.Fonts.Number, TextSize = 15, Color = tone, Wrapped = true, Size = UDim2.new(1, 0, 0, 0), AutoSize = Enum.AutomaticSize.Y, Parent = col, Order = 2 })
		end
	end
end

local function refresh()
	if not root.Visible then
		return
	end
	local state = C.StateStore.state
	local ids = explorers()
	if focusId and not state.exploration[focusId] then
		focusId = ids[1]
		C.WastelandController.focus(focusId)
	end
	empty.Visible = #ids == 0
	status.Visible = focusId ~= nil
	journal.Parent.Visible = focusId ~= nil
	local rec = focusId and state.exploration[focusId]
	local d = focusId and state.dwellers[focusId]
	if rec and #rec.log ~= lastLogCount then
		lastLogCount = #rec.log
		rebuildJournal(rec)
	end
	if not rec or not d then
		return
	end
	local now = C.StateStore.now()
	nameL.Text = string.upper(d.name) .. "  ·  LV " .. d.level
	hpSet(d.health / d.maxHealth, if d.health / d.maxHealth < 0.35 then T.danger else T.health)
	local out = now - rec.start
	local tier = math.min(10, math.floor(out / Exploration.TIER_SECONDS))
	timeL.Text = "OUT " .. Kit.fmtTime(out)
	dangerL.Text = "DANGER: " .. DANGER[tier + 1]
	dangerL.TextColor3 = if tier >= 6 then T.danger elseif tier >= 3 then T.accent else T.good
	for _, c in lootRow:GetChildren() do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	lootChip(lootRow, "bolts", Kit.fmt(math.max(0, rec.loot.Bolts or 0)), Theme.Resource.Bolts, 1)
	lootChip(lootRow, "weapons", tostring(#(rec.loot.items or {})), T.text, 2)
	if (rec.recruits or 0) > 0 then
		lootChip(lootRow, "survivors", tostring(rec.recruits), T.happy, 3)
	end
	lootChip(lootRow, "health", tostring(rec.medpatches or 0) .. " meds", Theme.Resource.MedPatch, 4)
	for _, k in { "Food", "Water" } do
		if (rec.loot[k] or 0) > 0 then
			lootChip(lootRow, string.lower(k), tostring(rec.loot[k]), Theme.Resource[k], 5)
		end
	end
	-- action button
	local key = if rec.dead then "dead" elseif rec.returning then "ret" else "out"
	if key ~= lastActionKey then
		lastActionKey = key
		for _, c in actionHost:GetChildren() do
			if c:IsA("GuiButton") then
				c:Destroy()
			end
		end
		if rec.dead then
			Kit.button({ Text = "REVIVE", Icon = "health", Style = "primary", Size = UDim2.fromOffset(170, 60), Parent = actionHost, Order = 1, OnClick = function()
				C.StateStore.action("Revive", { dwellerId = d.id })
			end })
		elseif not rec.returning then
			Kit.button({ Text = "RECALL", Icon = "assign", Style = "primary", Size = UDim2.fromOffset(170, 60), Parent = actionHost, Order = 1, OnClick = function()
				C.StateStore.action("Recall", { dwellerId = d.id })
			end })
		else
			local b = Kit.button({ Text = "HOME IN", Icon = "assign", Style = "dark", Size = UDim2.fromOffset(190, 60), Parent = actionHost, Order = 1 })
			b.Name = "Countdown"
		end
	end
	local cd = actionHost:FindFirstChild("Countdown")
	if cd and rec.returning then
		Kit.setButtonText(cd, "HOME IN " .. Kit.fmtTime(math.max(0, rec.returnStart + rec.returnDur - now)))
	end
end

function ExplorePanel.focus(id: string?)
	focusId = id
	lastLogCount = -1
	lastActionKey = ""
	C.WastelandController.focus(id)
	rebuildTabs()
	refresh()
end

function ExplorePanel.open(id: string?)
	local ids = explorers()
	focusId = id or ids[1]
	root.Visible = true
	lastLogCount = -1
	lastActionKey = ""
	rebuildTabs()
	refresh()
	return focusId
end

function ExplorePanel.close()
	root.Visible = false
end

function ExplorePanel.isOpen(): boolean
	return root.Visible
end

-- Send-out dialog with a MedPatch selector.
function ExplorePanel.sendDialog(dwellerId: string, modalGui: ScreenGui)
	local state = C.StateStore.state
	local d = state.dwellers[dwellerId]
	if not d then
		return
	end
	local meds = math.min(2, state.resources.MedPatch or 0)
	local shade = Kit.new("TextButton", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, Text = "", AutoButtonColor = false, Size = UDim2.fromScale(1, 1), Parent = modalGui })
	local card = Kit.panel({ Size = UDim2.fromOffset(600, 380), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Parent = shade })
	Kit.hazard(card, UDim2.new(0, 160, 0, 6), UDim2.fromOffset(22, 8))
	Kit.icon({ Icon = "wasteland", Color = T.accent, Size = UDim2.fromOffset(64, 64), Position = UDim2.fromOffset(24, 26), Parent = card })
	Kit.label({ Text = "SEND " .. string.upper(d.name) .. " OUT?", Font = Kit.Fonts.Header, TextSize = 28, Size = UDim2.new(1, -120, 0, 36), Position = UDim2.fromOffset(100, 26), Parent = card })
	Kit.label({
		Text = "Explorers find bolts, gear, food and other survivors. The longer they stay out, the richer - and deadlier - the wasteland gets. Recall them any time.",
		TextSize = 17, Color = T.textMuted, Wrapped = true, Size = UDim2.new(1, -124, 0, 80), Position = UDim2.fromOffset(100, 64), Parent = card,
	})
	Kit.label({ Text = "MEDPATCHES TO CARRY", Font = Kit.Fonts.Header, TextSize = 18, Size = UDim2.fromOffset(300, 24), Position = UDim2.fromOffset(100, 158), Parent = card })
	local val = Kit.label({ Text = tostring(meds), Font = Kit.Fonts.Number, TextSize = 34, XAlign = Enum.TextXAlignment.Center, Size = UDim2.fromOffset(80, 44), Position = UDim2.fromOffset(170, 188), Parent = card })
	local avail = Kit.label({ Text = "(" .. (state.resources.MedPatch or 0) .. " in storage)", TextSize = 16, Color = T.textMuted, Size = UDim2.fromOffset(200, 44), Position = UDim2.fromOffset(320, 188), Parent = card })
	local _ = avail
	local function set(n: number)
		meds = math.clamp(n, 0, math.min(Exploration.MAX_MEDS, state.resources.MedPatch or 0))
		val.Text = tostring(meds)
	end
	Kit.button({ Text = "-", Size = UDim2.fromOffset(56, 48), Position = UDim2.fromOffset(100, 186), Parent = card, OnClick = function()
		set(meds - 1)
	end })
	Kit.button({ Text = "+", Size = UDim2.fromOffset(56, 48), Position = UDim2.fromOffset(256, 186), Parent = card, OnClick = function()
		set(meds + 1)
	end })
	Kit.button({ Text = "CANCEL", Size = UDim2.fromOffset(180, 60), Position = UDim2.new(0.5, -195, 1, -84), Parent = card, OnClick = function()
		shade:Destroy()
	end })
	Kit.button({ Text = "EXPLORE", Icon = "wasteland", Style = "primary", Size = UDim2.fromOffset(200, 60), Position = UDim2.new(0.5, 15, 1, -84), Parent = card, OnClick = function()
		shade:Destroy()
		local ok = C.StateStore.action("Explore", { dwellerId = dwellerId, medpatches = meds })
		if ok then
			C.UIController.openWasteland(dwellerId)
		end
	end })
	Kit.pop(card)
end

function ExplorePanel.summary(p: any, modalGui: ScreenGui)
	local d = C.StateStore.state.dwellers[p.id]
	local s = p.summary or {}
	local shade = Kit.new("TextButton", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, Text = "", AutoButtonColor = false, Size = UDim2.fromScale(1, 1), Parent = modalGui })
	local card = Kit.panel({ Size = UDim2.fromOffset(600, 420), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Parent = shade })
	Kit.hazard(card, UDim2.new(0, 160, 0, 6), UDim2.fromOffset(22, 8))
	Kit.label({ Text = string.upper(d and d.name or "Explorer") .. " IS HOME", Font = Kit.Fonts.Header, TextSize = 30, Size = UDim2.new(1, -40, 0, 40), Position = UDim2.fromOffset(24, 22), Parent = card })
	Kit.label({ Text = "Out for " .. Kit.fmtTime(p.seconds or 0) .. "  ·  " .. (p.events or 0) .. " encounters", TextSize = 18, Color = T.textMuted, Size = UDim2.new(1, -40, 0, 24), Position = UDim2.fromOffset(24, 62), Parent = card })
	local grid = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -48, 0, 220), Position = UDim2.fromOffset(24, 100), Parent = card })
	Kit.new("UIGridLayout", { CellSize = UDim2.fromOffset(170, 44), CellPadding = UDim2.fromOffset(8, 8), Parent = grid })
	lootChip(grid, "bolts", "+" .. Kit.fmt(s.Bolts or 0) .. " bolts", Theme.Resource.Bolts, 1)
	for i, k in { "Food", "Water", "MedPatch", "Scrap" } do
		if s[k] then
			lootChip(grid, if k == "MedPatch" then "health" elseif k == "Scrap" then nil else string.lower(k), "+" .. s[k] .. " " .. string.lower(k), Theme.Resource[k] or T.text, 1 + i)
		end
	end
	if (s.recruits or 0) > 0 then
		lootChip(grid, "survivors", "+" .. s.recruits .. " survivors", T.happy, 7)
	end
	for i, defId in s.items or {} do
		local def = ItemDefinitions.get(defId)
		if def then
			lootChip(grid, if def.kind == "Weapon" then "weapons" else "outfits", def.name, ItemDefinitions.Rarity[def.rarity].color, 10 + i)
		end
	end
	Kit.button({ Text = "WELCOME BACK", Style = "primary", Size = UDim2.fromOffset(240, 58), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Parent = card, OnClick = function()
		shade:Destroy()
	end })
	Kit.pop(card)
end

function ExplorePanel.Init(controllers)
	C = controllers
	gui = Kit.screen("ExplorationUI", 8)
	root = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = gui })
	-- header + tabs
	local head = Kit.panel({ Size = UDim2.fromOffset(620, 70), Position = UDim2.fromOffset(118, 96), Parent = root })
	Kit.icon({ Icon = "wasteland", Color = T.accent, Size = UDim2.fromOffset(44, 44), Position = UDim2.fromOffset(14, 13), Parent = head })
	Kit.label({ Text = "WASTELAND", Font = Kit.Fonts.Header, TextSize = 26, Size = UDim2.fromOffset(160, 40), Position = UDim2.fromOffset(66, 15), Parent = head })
	tabs = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -240, 1, -16), Position = UDim2.fromOffset(226, 8), Parent = head })
	Kit.list(tabs, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	-- journal
	local jp = Kit.panel({ Size = UDim2.fromOffset(440, 520), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 96), Parent = root })
	Kit.label({ Text = "JOURNAL", Font = Kit.Fonts.Header, TextSize = 22, Color = T.accent, Size = UDim2.fromOffset(200, 28), Position = UDim2.fromOffset(18, 12), Parent = jp })
	journal = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1, Size = UDim2.new(1, -28, 1, -56), Position = UDim2.fromOffset(16, 46), CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 6, ScrollBarImageColor3 = T.accent, BorderSizePixel = 0, Parent = jp,
	})
	Kit.list(journal, Enum.FillDirection.Vertical, 6)
	-- status bar
	status = Kit.panel({ Size = UDim2.fromOffset(980, 132), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Parent = root })
	nameL = Kit.label({ Text = "", Font = Kit.Fonts.Header, TextSize = 24, Size = UDim2.fromOffset(380, 30), Position = UDim2.fromOffset(22, 14), Parent = status })
	Kit.icon({ Icon = "health", Color = T.health, Size = UDim2.fromOffset(22, 22), Position = UDim2.fromOffset(22, 52), Parent = status })
	local _, hs = Kit.meter({ Parent = status, Color = T.health, Size = UDim2.fromOffset(200, 14), Position = UDim2.fromOffset(52, 56) })
	hpSet = hs
	timeL = Kit.label({ Text = "", Font = Kit.Fonts.Number, TextSize = 19, Size = UDim2.fromOffset(160, 24), Position = UDim2.fromOffset(270, 50), Parent = status })
	dangerL = Kit.label({ Text = "", Font = Kit.Fonts.Header, TextSize = 17, Size = UDim2.fromOffset(200, 24), Position = UDim2.fromOffset(410, 18), Parent = status })
	lootRow = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(620, 38), Position = UDim2.fromOffset(20, 84), Parent = status })
	Kit.list(lootRow, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	actionHost = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(420, 70), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0), Parent = status })
	Kit.list(actionHost, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)
	Kit.button({ Text = "SHELTER", Icon = "build", Size = UDim2.fromOffset(170, 60), Parent = actionHost, Order = 9, OnClick = function()
		C.UIController.closeWasteland()
	end })
	-- empty state
	empty = Kit.panel({ Size = UDim2.fromOffset(620, 220), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Parent = root })
	Kit.icon({ Icon = "wasteland", Color = T.accent, Size = UDim2.fromOffset(80, 80), Position = UDim2.fromOffset(28, 30), Parent = empty })
	Kit.label({ Text = "Nobody is out in the wasteland.", Font = Kit.Fonts.Header, TextSize = 26, Size = UDim2.new(1, -150, 0, 34), Position = UDim2.fromOffset(126, 34), Parent = empty })
	Kit.label({ Text = "Open a survivor's profile and press EXPLORE to send them out for loot.", TextSize = 18, Color = T.textMuted, Wrapped = true, Size = UDim2.new(1, -150, 0, 60), Position = UDim2.fromOffset(126, 74), Parent = empty })
	Kit.button({ Text = "BACK TO SHELTER", Style = "primary", Size = UDim2.fromOffset(240, 56), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16), Parent = empty, OnClick = function()
		C.UIController.closeWasteland()
	end })
end

function ExplorePanel.Start()
	local S = C.StateStore
	S.ExploreChanged:Connect(function()
		if root.Visible then
			rebuildTabs()
			lastActionKey = ""
			refresh()
		end
	end)
	S.ExploreEnded:Connect(function()
		if root.Visible then
			rebuildTabs()
			refresh()
		end
	end)
	S.DwellerStats:Connect(refresh)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc > 0.5 and root.Visible then
			acc = 0
			refresh()
		end
	end)
end

return ExplorePanel
