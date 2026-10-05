--!strict
-- Underhaven UI kit: retro-industrial widgets (gunmetal plates, rivets, amber accents).
-- Designed at 1600x900; UIScale adapts to phone / tablet / desktop.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Theme = require(ReplicatedStorage.Shared.Theme)
local Icons = require(ReplicatedStorage.Shared.Icons)

local Kit = {}
local T = Theme.UI

Kit.Fonts = {
	Header = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold),
	Number = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.SemiBold),
	Body = Font.new("rbxasset://fonts/families/TitilliumWeb.json", Enum.FontWeight.SemiBold),
	BodyBold = Font.new("rbxasset://fonts/families/TitilliumWeb.json", Enum.FontWeight.Bold),
	Flavor = Font.new("rbxasset://fonts/families/SpecialElite.json"),
}

function Kit.isTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

function Kit.screen(name: string, order: number?): ScreenGui
	local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
	local g = Instance.new("ScreenGui")
	g.Name = name
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	g.DisplayOrder = order or 0
	g.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	local scale = Instance.new("UIScale")
	scale.Name = "Scale"
	scale.Parent = g
	local function fit()
		local cam = workspace.CurrentCamera
		local vp = cam.ViewportSize
		local s = math.min(vp.Y / 900, vp.X / 1500)
		if Kit.isTouch() then
			s *= 1.18 -- fatter touch targets on phones/tablets
		end
		scale.Scale = math.clamp(s, 0.5, 1.3)
	end
	fit()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	g.Parent = pg
	return g
end

-- Size of the canvas in design units (viewport / UIScale)
function Kit.canvas(g: ScreenGui): Vector2
	local s = (g:FindFirstChild("Scale") :: UIScale).Scale
	return workspace.CurrentCamera.ViewportSize / s
end

function Kit.new(class: string, props: { [string]: any }, children: { Instance }?): any
	local inst = Instance.new(class)
	for k, v in props do
		if k ~= "Parent" then
			(inst :: any)[k] = v
		end
	end
	if children then
		for _, c in children do
			c.Parent = inst
		end
	end
	if props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

function Kit.corner(parent: Instance, r: number?)
	return Kit.new("UICorner", { CornerRadius = UDim.new(0, r or 8), Parent = parent })
end

function Kit.stroke(parent: Instance, color: Color3?, thickness: number?, transparency: number?)
	return Kit.new("UIStroke", {
		Color = color or T.border,
		Thickness = thickness or 2,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

function Kit.pad(parent: Instance, px: number, py: number?)
	return Kit.new("UIPadding", {
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
		PaddingTop = UDim.new(0, py or px),
		PaddingBottom = UDim.new(0, py or px),
		Parent = parent,
	})
end

function Kit.list(parent: Instance, dir: Enum.FillDirection?, padding: number?, halign: Enum.HorizontalAlignment?, valign: Enum.VerticalAlignment?)
	return Kit.new("UIListLayout", {
		FillDirection = dir or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, padding or 6),
		HorizontalAlignment = halign or Enum.HorizontalAlignment.Left,
		VerticalAlignment = valign or Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = parent,
	})
end

-- Riveted gunmetal plate (9-slice art + gradient tint)
function Kit.panel(props: { [string]: any }): ImageLabel
	local p = Kit.new("ImageLabel", {
		BackgroundTransparency = 1,
		Image = Icons.panel,
		ImageColor3 = props.Color or T.panel,
		ImageTransparency = props.Transparency or 0.04,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Rect.new(24, 24, 104, 104),
		SliceScale = props.SliceScale or 0.75,
		Size = props.Size or UDim2.fromOffset(200, 100),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		Name = props.Name or "Panel",
		ZIndex = props.ZIndex or 1,
		Active = true,
		Parent = props.Parent,
	})
	return p
end

function Kit.label(props: { [string]: any }): TextLabel
	local l = Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		FontFace = props.Font or Kit.Fonts.Body,
		Text = props.Text or "",
		TextColor3 = props.Color or T.text,
		TextSize = props.TextSize or 18,
		TextXAlignment = props.XAlign or Enum.TextXAlignment.Left,
		TextYAlignment = props.YAlign or Enum.TextYAlignment.Center,
		TextWrapped = props.Wrapped or false,
		RichText = props.Rich or false,
		Size = props.Size or UDim2.new(1, 0, 0, (props.TextSize or 18) + 6),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		AutomaticSize = props.AutoSize or Enum.AutomaticSize.None,
		LayoutOrder = props.Order or 0,
		Name = props.Name or "Label",
		ZIndex = props.ZIndex or 1,
		TextTruncate = props.Truncate or Enum.TextTruncate.None,
		Parent = props.Parent,
	})
	if props.Stroke then
		Kit.new("UIStroke", { Color = T.shadow, Thickness = props.Stroke, Parent = l })
	end
	return l
end

function Kit.icon(props: { [string]: any }): ImageLabel
	return Kit.new("ImageLabel", {
		BackgroundTransparency = 1,
		Image = Icons[props.Icon] or props.Icon or "",
		ImageColor3 = props.Color or T.text,
		Size = props.Size or UDim2.fromOffset(28, 28),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		ScaleType = Enum.ScaleType.Fit,
		LayoutOrder = props.Order or 0,
		Name = props.Name or "Icon",
		ZIndex = props.ZIndex or 1,
		Parent = props.Parent,
	})
end

local function press(btn: GuiObject)
	local s = btn:FindFirstChildOfClass("UIScale") or Kit.new("UIScale", { Parent = btn })
	s.Scale = 0.92
	TweenService:Create(s, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end
Kit.press = press

function Kit.pop(obj: GuiObject)
	local s = obj:FindFirstChildOfClass("UIScale") or Kit.new("UIScale", { Parent = obj })
	s.Scale = 0.85
	TweenService:Create(s, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-- Chunky button: optional icon + caption. style: "primary" | "dark" | "danger" | "good"
function Kit.button(props: { [string]: any }): ImageButton
	local style = props.Style or "dark"
	local bg = if style == "primary" then T.accent elseif style == "danger" then T.danger elseif style == "good" then T.good else T.panelInner
	local fg = if style == "primary" or style == "good" then Color3.fromRGB(28, 24, 18) else T.text
	local b = Kit.new("ImageButton", {
		BackgroundTransparency = 1,
		Image = Icons.button,
		ImageColor3 = bg,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Rect.new(28, 28, 100, 100),
		SliceScale = 0.6,
		Size = props.Size or UDim2.fromOffset(140, 56),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.Order or 0,
		Name = props.Name or "Button",
		AutoButtonColor = true,
		ZIndex = props.ZIndex or 1,
		Parent = props.Parent,
	})
	local row = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = b, ZIndex = b.ZIndex })
	Kit.list(row, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	if props.Icon then
		Kit.icon({ Icon = props.Icon, Color = props.IconColor or fg, Size = UDim2.fromOffset(props.IconSize or 26, props.IconSize or 26), Parent = row, Order = 1, ZIndex = b.ZIndex })
	end
	if props.Text then
		Kit.label({
			Text = props.Text, Font = Kit.Fonts.Header, TextSize = props.TextSize or 20, Color = fg,
			Size = UDim2.fromOffset(0, 26), AutoSize = Enum.AutomaticSize.X, Parent = row, Order = 2,
			XAlign = Enum.TextXAlignment.Center, Name = "Caption", ZIndex = b.ZIndex,
		})
	end
	if props.Sub then
		Kit.label({
			Text = props.Sub, Font = Kit.Fonts.Number, TextSize = 15, Color = fg, Name = "Sub",
			Size = UDim2.new(1, 0, 0, 16), Position = UDim2.new(0, 0, 1, -18), XAlign = Enum.TextXAlignment.Center, Parent = b,
			ZIndex = b.ZIndex,
		})
	end
	b.Activated:Connect(function()
		press(b)
		if props.OnClick then
			props.OnClick()
		end
	end)
	return b
end

function Kit.setButtonText(b: Instance, text: string)
	local cap = b:FindFirstChild("Caption", true) :: TextLabel?
	if cap then
		cap.Text = text
	end
end

-- Horizontal meter. Returns frame + setter(fraction, color?)
function Kit.meter(props: { [string]: any }): (Frame, (number, Color3?) -> ())
	local back = Kit.new("Frame", {
		BackgroundColor3 = T.shadow,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		Size = props.Size or UDim2.new(1, 0, 0, 10),
		Position = props.Position or UDim2.new(),
		LayoutOrder = props.Order or 0,
		Name = props.Name or "Meter",
		Parent = props.Parent,
	})
	Kit.corner(back, 5)
	local fill = Kit.new("Frame", {
		BackgroundColor3 = props.Color or T.accent,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0.5, 1),
		Name = "Fill",
		Parent = back,
	})
	Kit.corner(fill, 5)
	Kit.new("UIGradient", {
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190)),
		Rotation = 90,
		Parent = fill,
	})
	local function set(f: number, color: Color3?)
		TweenService:Create(fill, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(math.clamp(f, 0, 1), 1) }):Play()
		if color then
			fill.BackgroundColor3 = color
		end
	end
	return back, set
end

-- Rounded pill with icon + value text. Returns frame, valueLabel
function Kit.pill(props: { [string]: any }): (Frame, TextLabel)
	local f = Kit.new("Frame", {
		BackgroundColor3 = T.panel,
		BackgroundTransparency = 0.08,
		Size = props.Size or UDim2.fromOffset(150, 44),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.Order or 0,
		Name = props.Name or "Pill",
		Parent = props.Parent,
	})
	Kit.corner(f, 22)
	Kit.stroke(f, props.StrokeColor or T.border, 2)
	Kit.icon({ Icon = props.Icon, Color = props.IconColor, Size = UDim2.fromOffset(34, 34), Position = UDim2.fromOffset(6, 5), Parent = f })
	local v = Kit.label({
		Text = props.Text or "0", Font = Kit.Fonts.Number, TextSize = props.TextSize or 24, Color = props.TextColor or T.text,
		Size = UDim2.new(1, -48, 1, 0), Position = UDim2.fromOffset(44, 0), Parent = f, Name = "Value",
	})
	return f, v
end

-- Hazard-striped accent tab for headers
function Kit.hazard(parent: Instance, size: UDim2, position: UDim2?)
	local f = Kit.new("Frame", {
		BackgroundColor3 = T.accent,
		BorderSizePixel = 0,
		Size = size,
		Position = position or UDim2.new(),
		ClipsDescendants = true,
		Name = "Hazard",
		Parent = parent,
	})
	for i = 0, 12 do
		Kit.new("Frame", {
			BackgroundColor3 = T.shadow,
			BorderSizePixel = 0,
			Size = UDim2.new(0, 8, 2, 0),
			Position = UDim2.new(0, i * 18 - 6, -0.5, 0),
			Rotation = 35,
			Parent = f,
		})
	end
	return f
end

function Kit.fmt(n: number): string
	n = math.floor(n + 0.5)
	if n >= 1e6 then
		return string.format("%.1fM", n / 1e6)
	elseif n >= 1e4 then
		return string.format("%.1fK", n / 1e3)
	end
	local s = tostring(n)
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

function Kit.fmtTime(sec: number): string
	sec = math.floor(sec)
	local h = sec // 3600
	local m = (sec % 3600) // 60
	if h > 0 then
		return string.format("%dh %02dm", h, m)
	end
	return string.format("%dm %02ds", m, sec % 60)
end

return Kit
