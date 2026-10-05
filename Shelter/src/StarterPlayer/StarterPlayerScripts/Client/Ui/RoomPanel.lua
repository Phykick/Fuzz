--!strict
-- RoomUI: bottom sheet for the selected room.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Theme = require(ReplicatedStorage.Shared.Theme)
local RoomDefinitions = require(ReplicatedStorage.Shared.RoomDefinitions)
local Simulation = require(ReplicatedStorage.Shared.Simulation)
local DwellerDefinitions = require(ReplicatedStorage.Shared.DwellerDefinitions)
local Kit = require(script.Parent.Kit)

local RoomPanel = {}
local T = Theme.UI
local C: any

local gui: ScreenGui
local sheet: ImageLabel
local title: TextLabel
local stars: { ImageLabel } = {}
local chips: Frame
local crew: Frame
local actions: Frame
local fireBar: Frame
local fireText: TextLabel
local roomId: string? = nil
local lastKey = ""
local RES_ICON = { Power = "power", Food = "food", Water = "water", MedPatch = "health", Materials = "build" }
local AMENITY = { { "eat", "Eating", "seats" }, { "sleep", "Sleeping", "beds" }, { "treat", "Treatment", "beds" } }

local function cap0(room): number
	return Simulation.capacity(room)
end

local function chip(text: string, icon: string?, color: Color3?, order: number)
	local f = Kit.new("Frame", { BackgroundColor3 = T.panelInner, Size = UDim2.fromOffset(0, 38), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = order, Parent = chips })
	Kit.corner(f, 8)
	Kit.pad(f, 10, 0)
	Kit.list(f, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	if icon then
		Kit.icon({ Icon = icon, Color = color, Size = UDim2.fromOffset(24, 24), Parent = f, Order = 1 })
	end
	Kit.label({ Text = text, Font = Kit.Fonts.Number, TextSize = 19, Color = color or T.text, Size = UDim2.fromOffset(0, 30), AutoSize = Enum.AutomaticSize.X, Parent = f, Order = 2 })
end

local function crewSlot(d: any?, statKey: string?, order: number, onTap: () -> ())
	local b = Kit.new("ImageButton", {
		BackgroundColor3 = if d then T.panelInner else T.shadow, BackgroundTransparency = if d then 0 else 0.3,
		Size = UDim2.fromOffset(76, 76), LayoutOrder = order, Image = "", AutoButtonColor = true, Parent = crew,
	})
	Kit.corner(b, 38)
	if d then
		local happy = d.happiness or 50
		Kit.stroke(b, if d.status == "Dead" then T.danger elseif happy >= 60 then T.happy elseif happy >= 35 then T.accent else T.danger, 3)
		local skin = Color3.fromHex((d.appearance and d.appearance.skin) or "D8A47F")
		local face = Kit.new("Frame", { BackgroundColor3 = skin, Size = UDim2.fromOffset(46, 46), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Parent = b })
		Kit.corner(face, 23)
		local initials = (d.name or "?"):gsub("(%a)%a*%s*", "%1"):sub(1, 2)
		Kit.label({ Text = initials, Font = Kit.Fonts.Header, TextSize = 22, Color = Color3.fromRGB(30, 24, 20), XAlign = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), Parent = face })
		local stat = if statKey then Simulation.stat(d, statKey) else d.level
		local tag = Kit.new("Frame", { BackgroundColor3 = T.accent, Size = UDim2.fromOffset(44, 20), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 4), Parent = b })
		Kit.corner(tag, 6)
		Kit.label({ Text = (statKey or "LV") .. " " .. stat, Font = Kit.Fonts.Header, TextSize = 14, Color = Color3.fromRGB(28, 24, 18), XAlign = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), Parent = tag })
	else
		Kit.stroke(b, T.border, 2)
		Kit.label({ Text = "+", Font = Kit.Fonts.Header, TextSize = 40, Color = T.textMuted, XAlign = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), Parent = b })
	end
	b.Activated:Connect(function()
		Kit.press(b)
		onTap()
	end)
end

function RoomPanel.refresh()
	if not roomId then
		return
	end
	local state = C.StateStore.state
	local room = state.rooms[roomId]
	if not room then
		RoomPanel.close()
		return
	end
	local def = RoomDefinitions.Types[room.type]
	title.Text = string.upper(def.name)
	for i, s in stars do
		s.ImageColor3 = if i <= room.level then T.accent else T.border
		s.Visible = room.type ~= "Elevator"
	end
	for _, c in chips:GetChildren() do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	local nowT = C.StateStore.now()
	local keyParts = {
		room.id, tostring(room.level), tostring(room.modules), tostring(room.readySince ~= nil), tostring(room.incident ~= nil),
		tostring((state.resources.Bolts or 0) >= (Simulation.upgradeCost(room) or math.huge)),
		tostring(room.incident and room.incident.kind), tostring(room.incident and room.incident.paid),
		tostring((state.resources.Materials or 0) >= (if room.incident and room.incident.cost then room.incident.cost else 0)),
	}
	for _, id in room.assigned do
		local d = state.dwellers[id]
		table.insert(keyParts, id .. ":" .. (d and math.floor(d.happiness / 25) or 0))
	end
	if cap0(room) == 0 then
		for _, d in state.dwellers do
			if (d.at or d.roomId) == room.id and Simulation.isInside(d) then
				table.insert(keyParts, d.id)
			end
		end
	end
	local key = table.concat(keyParts :: any, ",")
	local rebuild = key ~= lastKey
	lastKey = key
	if rebuild then
		for _, c in crew:GetChildren() do
			if c:IsA("GuiButton") then
				c:Destroy()
			end
		end
		for _, c in actions:GetChildren() do
			if c:IsA("GuiButton") then
				c:Destroy()
			end
		end
	end
	if def.produces then
		local pf = if def.produces == "Power" then 1 else (state.powerFactor or 1)
		local rate = Simulation.roomRate(room, state.dwellers, nowT, pf)
		chip(string.format("+%.1f/min", rate), RES_ICON[def.produces], Theme.Resource[def.produces], 1)
		-- production chain: what it consumes to make that
		for key, perUnit in def.inputs or {} do
			chip(string.format("-%.1f/min", rate * perUnit), RES_ICON[key], if room.starved then T.danger else T.textMuted, 1)
			if room.starved then
				chip("NOT ENOUGH " .. string.upper(key), nil, T.danger, 1)
			end
		end
		if pf < 0.99 then
			chip(string.format("BROWNOUT %d%%", math.floor(pf * 100)), "power", T.danger, 1)
		end
	end
	if def.stat then
		chip(def.stat .. " · " .. DwellerDefinitions.STAT_NAMES[def.stat], nil, T.accent, 2)
	end
	-- seats in use (cafeteria, bunks, med beds)
	for _, a in AMENITY do
		local cap = Simulation.amenity(room, a[1])
		if cap > 0 and (a[1] ~= "sleep" or room.type == "Living") then
			local used = 0
			for _, d in state.dwellers do
				if (d.at or d.roomId) == room.id and d.activity == a[2] then
					used += 1
				end
			end
			chip(string.format("%d/%d %s", used, cap, a[3]), "population", if used >= cap then T.accent else T.text, 3)
		end
	end
	if def.housing then
		chip("+" .. def.housing[room.level] * room.modules .. " beds", "population", T.text, 3)
	end
	if def.storage then
		for res, per in def.storage do
			chip("+" .. per[room.level] * room.modules .. " storage", RES_ICON[res], Theme.Resource[res], 4)
		end
	end
	if def.powerUse > 0 then
		chip(string.format("-%.1f/min", def.powerUse * room.modules), "power", T.textMuted, 5)
	end
	if room.modules > 1 then
		chip(room.modules .. "x merged", "build", T.textMuted, 6)
	end
	-- crew
	local cap = Simulation.capacity(room)
	if not rebuild then
		-- fire status still updates live
	elseif cap > 0 then
		for i = 1, cap do
			local did = room.assigned[i]
			local d = did and state.dwellers[did]
			crewSlot(d, def.stat, i, function()
				if d then
					C.UIController.selectDweller(d.id)
				else
					C.UIController.openPicker(room.id)
				end
			end)
		end
	else
		local present = {}
		for _, d in state.dwellers do
			if (d.at or d.roomId) == room.id and Simulation.isInside(d) then
				table.insert(present, d)
			end
		end
		for i, d in present do
			if i > 8 then
				break
			end
			crewSlot(d, nil, i, function()
				C.UIController.selectDweller(d.id)
			end)
		end
	end
	-- actions
	local upCost, upMats = Simulation.upgradeCost(room)
	local inc0 = room.incident
	if rebuild and inc0 and inc0.kind == "Breakdown" then
		local afford = (state.resources.Materials or 0) >= inc0.cost
		Kit.button({
			Text = if inc0.paid then "REPAIRING" else "REPAIR", Sub = if inc0.paid then "in progress" else inc0.cost .. " materials",
			Icon = "build", Style = if inc0.paid then "dark" elseif afford then "primary" else "danger",
			Size = UDim2.fromOffset(170, 70), Parent = actions, Order = -1,
			OnClick = function()
				if not inc0.paid then
					C.StateStore.action("Repair", { roomId = room.id })
				end
			end,
		})
	end
	if rebuild and room.type ~= "Elevator" then
		if upCost then
			local afford = (state.resources.Bolts or 0) >= upCost and (state.resources.Materials or 0) >= upMats
			Kit.button({
				Text = "UPGRADE", Sub = Kit.fmt(upCost) .. "b + " .. upMats .. "m", Icon = "upgrade", Style = if afford then "primary" else "dark",
				Size = UDim2.fromOffset(160, 70), Parent = actions, Order = 1,
				OnClick = function()
					local ok = C.StateStore.action("Upgrade", { roomId = room.id })
					if ok then
						local center = C.VaultRenderer.roomCenter(room.id)
						if center then
							C.EffectsController.float(center + Vector3.new(0, 1, 5), "LEVEL " .. (room.level + 1) .. "!", T.accent, "upgrade", true)
						end
					end
				end,
			})
		else
			Kit.button({ Text = "MAX LEVEL", Size = UDim2.fromOffset(160, 70), Parent = actions, Order = 1 })
		end
	end
	if rebuild and def.produces then
		local luck, n = 0, 0
		for _, id in room.assigned do
			local d = state.dwellers[id]
			if d then
				luck += Simulation.stat(d, "SCV")
				n += 1
			end
		end
		local fail = Simulation.rushFailChance(room, if n > 0 then luck / n else 0)
		Kit.button({
			Text = "RUSH", Sub = string.format("%d%% risk", math.floor(fail * 100 + 0.5)), Icon = "rush", Style = "dark",
			Size = UDim2.fromOffset(140, 70), Parent = actions, Order = 2,
			OnClick = function()
				local ok, res = C.StateStore.action("Rush", { roomId = room.id })
				if ok and res and res.success then
					local center = C.VaultRenderer.roomCenter(room.id)
					if center then
						C.EffectsController.float(center + Vector3.new(0, 2, 5), "RUSHED!", T.good, "rush", true)
					end
				end
			end,
		})
		if room.readySince then
			Kit.button({
				Text = "COLLECT", Icon = RES_ICON[def.produces], Style = "good", Size = UDim2.fromOffset(150, 70), Parent = actions, Order = 0,
				OnClick = function()
					C.EffectsController.collect(room.id)
				end,
			})
		end
	end
	if rebuild and room.type ~= "Entrance" then
		Kit.button({
			Icon = "close", Style = "dark", Size = UDim2.fromOffset(56, 70), Parent = actions, Order = 5, IconColor = T.danger,
			OnClick = function()
				C.UIController.confirm("Demolish this " .. def.name .. "? No refund.", function()
					local ok = C.StateStore.action("Destroy", { roomId = room.id })
					if ok then
						RoomPanel.close()
					end
				end)
			end,
		})
	end
	if rebuild then
		Kit.button({
			Icon = "info", Style = "dark", Size = UDim2.fromOffset(56, 70), Parent = actions, Order = 6,
			OnClick = function()
				C.Hud.toast(def.desc, "info")
			end,
		})
	end
	-- fire
	local inc = room.incident
	fireBar.Visible = inc ~= nil
	if inc then
		if inc.kind == "Breakdown" then
			fireText.Text = if inc.paid
				then string.format("REPAIRING %d%% - anyone in the room helps (Engineering is fastest)", math.floor(math.clamp(inc.hp, 0, 1) * 100))
				else string.format("BROKEN DOWN - no output until repaired (%d materials)", inc.cost)
		else
			local what = if inc.kind == "Rats" then "BURROW RATS!" elseif inc.kind == "Roaches" then "RUST ROACHES!" else "FIRE!"
			fireText.Text = string.format("%s %d%% - drag survivors in to fight", what, math.floor(math.clamp(inc.hp / inc.maxHp, 0, 1) * 100))
		end
	end
end

function RoomPanel.open(id: string)
	if not sheet.Visible then
		Kit.sound("open")
	end
	roomId = id
	lastKey = ""
	sheet.Visible = true
	RoomPanel.refresh()
	sheet.Position = UDim2.new(0.5, 0, 1, 260)
	TweenService:Create(sheet, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(0.5, 0, 1, -12) }):Play()
end

function RoomPanel.close()
	if sheet.Visible then
		Kit.sound("close")
	end
	roomId = nil
	sheet.Visible = false
end

function RoomPanel.current(): string?
	return roomId
end

function RoomPanel.Init(controllers)
	C = controllers
	gui = Kit.screen("RoomUI", 6)
	sheet = Kit.panel({ Size = UDim2.fromOffset(900, 236), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Parent = gui, Name = "RoomSheet" })
	sheet.Visible = false
	Kit.hazard(sheet, UDim2.new(0, 160, 0, 6), UDim2.fromOffset(22, 8))
	title = Kit.label({ Text = "ROOM", Font = Kit.Fonts.Header, TextSize = 30, Size = UDim2.fromOffset(420, 38), Position = UDim2.fromOffset(22, 16), Parent = sheet })
	local starRow = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(110, 30), Position = UDim2.fromOffset(22, 52), Parent = sheet })
	Kit.list(starRow, Enum.FillDirection.Horizontal, 4)
	for i = 1, 3 do
		stars[i] = Kit.icon({ Icon = "star", Size = UDim2.fromOffset(24, 24), Parent = starRow, Order = i })
	end
	chips = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -170, 0, 40), Position = UDim2.fromOffset(150, 48), Parent = sheet })
	Kit.list(chips, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	crew = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(500, 90), Position = UDim2.fromOffset(22, 108), Parent = sheet })
	Kit.list(crew, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	actions = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(560, 80), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, 112), Parent = sheet })
	Kit.list(actions, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)
	Kit.button({
		Icon = "close", Style = "dark", Size = UDim2.fromOffset(52, 52), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 14), Parent = sheet,
		OnClick = function()
			C.UIController.clearSelection()
		end,
	})
	fireBar = Kit.new("Frame", { BackgroundColor3 = Color3.fromRGB(70, 22, 16), Size = UDim2.new(1, -44, 0, 30), Position = UDim2.new(0, 22, 1, -40), Visible = false, Parent = sheet })
	Kit.corner(fireBar, 8)
	Kit.icon({ Icon = "fire", Color = Color3.fromRGB(255, 140, 60), Size = UDim2.fromOffset(24, 24), Position = UDim2.fromOffset(8, 3), Parent = fireBar })
	fireText = Kit.label({ Text = "", Font = Kit.Fonts.BodyBold, TextSize = 18, Color = Color3.fromRGB(255, 200, 170), Size = UDim2.new(1, -44, 1, 0), Position = UDim2.fromOffset(40, 0), Parent = fireBar })
end

return RoomPanel
