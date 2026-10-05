--!strict
-- BuildUI: horizontal carousel of room cards. Picking one enters build mode.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Theme = require(ReplicatedStorage.Shared.Theme)
local RoomDefinitions = require(ReplicatedStorage.Shared.RoomDefinitions)
local Simulation = require(ReplicatedStorage.Shared.Simulation)
local Kit = require(script.Parent.Kit)

local BuildMenu = {}
local T = Theme.UI
local C: any

local gui: ScreenGui
local sheet: ImageLabel
local row: ScrollingFrame
local isOpen = false

local ICON = { Power = "power", Water = "water", Food = "food", Living = "population", Elevator = "upgrade", Infirmary = "health", Storage = "shop", Cafeteria = "food", Workshop = "build" }

local function card(def: RoomDefinitions.RoomDef, order: number)
	local state = C.StateStore.state
	local pop = Simulation.population(state.dwellers)
	local locked = pop < def.unlockPop or not def.buildable
	local cost, mats = Simulation.buildCost(state.rooms, def.id)
	local afford = (state.resources.Bolts or 0) >= cost and (state.resources.Materials or 0) >= mats
	local theme = Theme.room(def.id)
	local b = Kit.new("ImageButton", { BackgroundColor3 = T.panelInner, Size = UDim2.fromOffset(150, 168), LayoutOrder = order, Image = "", AutoButtonColor = not locked, Parent = row })
	Kit.corner(b, 12)
	local active = C.BuildController.active == def.id
	Kit.stroke(b, if active then T.accent else T.border, if active then 4 else 2)
	local swatch = Kit.new("Frame", { BackgroundColor3 = theme.wall, Size = UDim2.new(1, -16, 0, 74), Position = UDim2.fromOffset(8, 8), Parent = b })
	Kit.corner(swatch, 8)
	Kit.new("UIGradient", { Color = ColorSequence.new(theme.wall, theme.wall2), Rotation = 90, Parent = swatch })
	Kit.icon({ Icon = ICON[def.id] or "build", Color = theme.glow, Size = UDim2.fromOffset(52, 52), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Parent = swatch })
	Kit.label({ Text = string.upper(def.name), Font = Kit.Fonts.Header, TextSize = 17, XAlign = Enum.TextXAlignment.Center, Size = UDim2.new(1, -8, 0, 22), Position = UDim2.fromOffset(4, 88), Parent = b, Truncate = Enum.TextTruncate.AtEnd })
	Kit.label({
		Text = if def.stat then (def.stat .. " · " .. def.category) else def.category, TextSize = 14, Color = T.textMuted,
		XAlign = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 110), Parent = b,
	})
	local price = Kit.new("Frame", { BackgroundColor3 = if locked then T.shadow elseif afford then T.accent else T.danger, Size = UDim2.new(1, -16, 0, 30), Position = UDim2.new(0, 8, 1, -38), Parent = b })
	Kit.corner(price, 8)
	if locked then
		Kit.label({ Text = if def.buildable then ("POP " .. def.unlockPop) else "SOON", Font = Kit.Fonts.Header, TextSize = 17, XAlign = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), Parent = price, Color = T.textMuted })
	else
		Kit.icon({ Icon = "bolts", Color = Color3.fromRGB(28, 24, 18), Size = UDim2.fromOffset(22, 22), Position = UDim2.fromOffset(10, 4), Parent = price })
		Kit.label({ Text = Kit.fmt(cost) .. (if mats > 0 then " +" .. mats .. "m" else ""), Font = Kit.Fonts.Number, TextSize = 16, Color = Color3.fromRGB(28, 24, 18), Size = UDim2.new(1, -40, 1, 0), Position = UDim2.fromOffset(36, 0), Parent = price })
	end
	b.Activated:Connect(function()
		if locked then
			C.Hud.toast(def.name .. (if def.buildable then (" unlocks at " .. def.unlockPop .. " survivors") else " arrives in a later update"), "warn")
			return
		end
		Kit.press(b)
		C.BuildController.enter(def.id)
		C.Hud.setHint("Tap a green slot to build the " .. def.name .. " (" .. Kit.fmt(cost) .. " bolts" .. (if mats > 0 then ", " .. mats .. " materials" else "") .. ")", function()
			C.BuildController.exit()
		end)
		BuildMenu.refresh()
	end)
end

function BuildMenu.refresh()
	if not isOpen then
		return
	end
	for _, c in row:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local defs = {}
	for _, d in RoomDefinitions.Types do
		if d.id ~= "Entrance" then
			table.insert(defs, d)
		end
	end
	table.sort(defs, function(a, b)
		return a.order < b.order
	end)
	for i, d in defs do
		card(d, i)
	end
end

function BuildMenu.open()
	if not isOpen then
		Kit.sound("open")
	end
	isOpen = true
	sheet.Visible = true
	BuildMenu.refresh()
	sheet.Position = UDim2.new(0.5, 0, 1, 260)
	TweenService:Create(sheet, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(0.5, 0, 1, -10) }):Play()
end

function BuildMenu.close()
	if isOpen then
		Kit.sound("close")
	end
	isOpen = false
	sheet.Visible = false
end

function BuildMenu.isOpen(): boolean
	return isOpen
end

function BuildMenu.Init(controllers)
	C = controllers
	gui = Kit.screen("BuildUI", 6)
	sheet = Kit.panel({ Size = UDim2.fromOffset(1060, 216), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10), Parent = gui, Name = "BuildSheet" })
	sheet.Visible = false
	Kit.hazard(sheet, UDim2.new(0, 160, 0, 6), UDim2.fromOffset(22, 8))
	Kit.label({ Text = "CONSTRUCTION", Font = Kit.Fonts.Header, TextSize = 22, Size = UDim2.fromOffset(300, 26), Position = UDim2.fromOffset(200, 6), Parent = sheet, Color = T.accent })
	row = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1, Size = UDim2.new(1, -110, 0, 176), Position = UDim2.fromOffset(18, 34),
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.X, ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 6, ScrollBarImageColor3 = T.accent, BorderSizePixel = 0, Parent = sheet,
	})
	Kit.list(row, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	Kit.button({
		Icon = "close", Size = UDim2.fromOffset(70, 70), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 8), Parent = sheet,
		OnClick = function()
			C.UIController.closeBuild()
		end,
	})
end

return BuildMenu
