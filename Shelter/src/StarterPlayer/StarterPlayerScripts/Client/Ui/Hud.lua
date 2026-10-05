--!strict
-- MainHUD: top resource bar (stored / capacity / production / consumption / trend for every
-- resource), prioritised alerts, bottom action bar, toasts, incident banners.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Theme = require(ReplicatedStorage.Shared.Theme)
local Difficulty = require(ReplicatedStorage.Shared.Difficulty)
local Resources = require(ReplicatedStorage.Shared.Resources)
local Kit = require(script.Parent.Kit)

local Hud = {}
local T = Theme.UI
local C: any

local gui: ScreenGui
local meters: { [string]: { set: (number, Color3?) -> (), value: TextLabel, rate: TextLabel, frame: Frame } } = {}
local alertRow: Frame
local infoPop: Frame?
local lastState: any = nil
local boltsLabel: TextLabel
local popLabel: TextLabel
local happyLabel: TextLabel
local happyIcon: ImageLabel
local threatLabel: TextLabel
local threatIcon: ImageLabel
local queueButton: ImageButton
local queueClick: (() -> ())? = nil
local shelterLabel: TextLabel
local bottomBar: Frame
local toastStack: Frame
local banner: Frame
local bannerText: TextLabel
local bannerMeter: (number, Color3?) -> ()
local bannerMeterFrame: Frame
local hintBar: Frame
local hintText: TextLabel
local hintCancel: () -> ()

local function fmtRate(r: number): string
	local a = math.abs(r)
	return (if r >= 0 then "+" else "-") .. (if a >= 10 or a == 0 then string.format("%d", math.floor(a + 0.5)) else string.format("%.1f", a))
end

-- Popover under a meter: where the resource comes from, where it goes, how long it lasts.
local function showInfo(key: string)
	if infoPop then
		infoPop:Destroy()
		infoPop = nil
	end
	local m = meters[key]
	local state = lastState
	if not m or not state then
		return
	end
	local def = Resources.Defs[key]
	local f = (state.flow or {})[key] or { prod = 0, use = 0 }
	local v, cap = (state.resources or {})[key] or 0, (state.caps or {})[key] or 1
	local net = f.prod - f.use
	local horizon = if net < -0.05 then string.format("Runs out in %d min", math.ceil(v / -net))
		elseif net > 0.05 and v < cap then string.format("Full in %d min", math.ceil((cap - v) / net))
		elseif v >= cap - 0.5 and net > 0 then "Storage full - extra is wasted"
		else "Holding steady"
	local lines = {
		string.format("%s   %d / %d", string.upper(def.name), math.floor(v), math.floor(cap)),
		string.format("Production  %s/min", fmtRate(f.prod)),
		string.format("Consumption  %s/min", fmtRate(-f.use)),
		string.format("Net  %s/min  -  %s", fmtRate(net), horizon),
	}
	if key == "Power" and (state.powerFactor or 1) < 0.99 then
		table.insert(lines, string.format("BROWNOUT: rooms get %d%% of the power they need", math.floor((state.powerFactor or 1) * 100)))
	end
	local pop = Kit.new("Frame", {
		BackgroundColor3 = T.panel, BackgroundTransparency = 0.04, Size = UDim2.fromOffset(330, 22 + #lines * 24),
		Position = UDim2.new(0, m.frame.AbsolutePosition.X - gui.AbsolutePosition.X - 20, 0, m.frame.AbsolutePosition.Y - gui.AbsolutePosition.Y + 72),
		Name = "ResourceInfo", Parent = gui,
	})
	Kit.corner(pop, 10)
	Kit.stroke(pop, Theme.Resource[key] or T.border, 2)
	for i, text in lines do
		Kit.label({
			Text = text, Font = if i == 1 then Kit.Fonts.Header else Kit.Fonts.BodyBold, TextSize = if i == 1 then 18 else 16,
			Color = if i == 4 and net < 0 then T.danger elseif i == 5 then T.danger else T.text,
			Size = UDim2.new(1, -24, 0, 22), Position = UDim2.fromOffset(12, 10 + (i - 1) * 24), Parent = pop,
		})
	end
	Kit.pop(pop)
	infoPop = pop
	task.delay(5, function()
		if infoPop == pop then
			pop:Destroy()
			infoPop = nil
		end
	end)
end

local function buildTop()
	local top = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 92), Name = "TopBar", Parent = gui })
	local shade = Kit.new("Frame", {
		BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35, BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 20), Parent = top, ZIndex = 0,
	})
	Kit.new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }),
		Parent = shade,
	})
	-- left cluster: shelter badge + happiness
	local left = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(330, 70), Position = UDim2.fromOffset(118, 10), Parent = top })
	local badge = Kit.icon({ Icon = "level", Color = T.accent, Size = UDim2.fromOffset(66, 66), Position = UDim2.fromOffset(0, 0), Parent = left })
	shelterLabel = Kit.label({
		Text = "---", Font = Kit.Fonts.Header, TextSize = 20, Color = T.text, Stroke = 2,
		XAlign = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), Parent = badge,
	})
	local hp, hv = Kit.pill({ Icon = "happy", IconColor = T.happy, Size = UDim2.fromOffset(128, 46), Position = UDim2.fromOffset(76, 10), Parent = left, Text = "--%" })
	happyLabel = hv
	happyIcon = hp:FindFirstChild("Icon") :: ImageLabel
	-- threat level (the pressure curve): rises with play time and population
	local tp, tv = Kit.pill({ Icon = "raid", IconColor = T.good, Size = UDim2.fromOffset(170, 40), Position = UDim2.fromOffset(76, 62), Parent = left, Text = "CALM", TextSize = 18 })
	threatLabel = tv
	threatLabel.FontFace = Kit.Fonts.Header
	threatIcon = tp:FindFirstChild("Icon") :: ImageLabel
	-- center meters: stored / capacity on the bar, production and consumption underneath, the bar
	-- colour and arrow show the trend. Tap a meter for the full breakdown.
	local center = Kit.new("Frame", {
		BackgroundTransparency = 1, Size = UDim2.fromOffset(#Resources.LIST * 166, 74), AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 30, 0, 6), Parent = top,
	})
	Kit.list(center, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center)
	for i, key in Resources.LIST do
		local def = Resources.Defs[key]
		local col = Theme.Resource[key] or T.text
		local f = Kit.new("TextButton", {
			BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Size = UDim2.fromOffset(160, 74), LayoutOrder = i, Name = key, Parent = center,
		})
		local disc = Kit.new("Frame", {
			BackgroundColor3 = T.panel, Size = UDim2.fromOffset(46, 46), Position = UDim2.fromOffset(0, 6), Parent = f, ZIndex = 2,
		})
		Kit.corner(disc, 23)
		Kit.stroke(disc, col, 3)
		Kit.icon({ Icon = def.icon, Color = col, Size = UDim2.fromOffset(30, 30), Position = UDim2.fromOffset(8, 8), Parent = disc, ZIndex = 3 })
		local m, set = Kit.meter({ Parent = f, Color = col, Size = UDim2.fromOffset(118, 16), Position = UDim2.fromOffset(38, 21) })
		Kit.stroke(m, T.border, 2)
		local value = Kit.label({
			Text = "0", Font = Kit.Fonts.Number, TextSize = 15, Color = T.text, Stroke = 1,
			Size = UDim2.fromOffset(112, 16), Position = UDim2.fromOffset(50, 2), Parent = f, XAlign = Enum.TextXAlignment.Right,
		})
		local rate = Kit.label({
			Text = "", Font = Kit.Fonts.Number, TextSize = 14, Color = T.textMuted, Stroke = 1,
			Size = UDim2.fromOffset(118, 16), Position = UDim2.fromOffset(42, 40), Parent = f,
		})
		f.Activated:Connect(function()
			showInfo(key)
		end)
		meters[key] = { set = set, value = value, rate = rate, frame = f :: any }
	end
	-- right cluster
	local right = Kit.new("Frame", {
		BackgroundTransparency = 1, Size = UDim2.fromOffset(330, 70), AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 12), Parent = top,
	})
	Kit.list(right, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Right)
	local _, pv = Kit.pill({ Icon = "population", IconColor = T.text, Size = UDim2.fromOffset(126, 46), Parent = right, Order = 1, Text = "0/0" })
	popLabel = pv
	local _, bv = Kit.pill({ Icon = "bolts", IconColor = Theme.Resource.Bolts, StrokeColor = Theme.Resource.Bolts, Size = UDim2.fromOffset(176, 46), Parent = right, Order = 2, Text = "0", TextColor = Theme.Resource.Bolts })
	boltsLabel = bv
	-- wanderers waiting outside the bunker
	queueButton = Kit.button({
		Text = "AT THE DOOR", Icon = "population", Style = "primary", Size = UDim2.fromOffset(250, 46), TextSize = 18,
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 92), Parent = gui,
		OnClick = function()
			if queueClick then
				queueClick()
			end
		end,
	})
	queueButton.Visible = false
	-- alerts under the top bar (most urgent first)
	alertRow = Kit.new("Frame", {
		BackgroundTransparency = 1, Size = UDim2.fromOffset(900, 34), AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 30, 0, 86), Name = "Alerts", Parent = gui,
	})
	Kit.list(alertRow, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center)
	-- keep the whole bar on screen on narrow (phone) displays
	local scale = Instance.new("UIScale")
	scale.Parent = top
	local function fit()
		local w = gui.AbsoluteSize.X
		local s = math.clamp(w / 1560, 0.55, 1)
		scale.Scale = s
		top.Size = UDim2.new(1 / s, 0, 0, 92)
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()
end

local SEVERITY = {
	critical = { color = T.danger, icon = "raid" },
	warn = { color = T.accent, icon = "info" },
	info = { color = Color3.fromRGB(240, 210, 120), icon = "info" },
}

-- alerts: { { text, severity = critical|warn|info, onClick? } } (already prioritised)
function Hud.setAlerts(alerts: { any })
	for _, c in alertRow:GetChildren() do
		if c:IsA("GuiButton") then
			c:Destroy()
		end
	end
	for i, a in alerts do
		if i > 3 then
			break
		end
		local sev = SEVERITY[a.severity] or SEVERITY.info
		local b = Kit.new("TextButton", {
			BackgroundColor3 = T.panel, BackgroundTransparency = 0.05, Text = "", AutoButtonColor = true,
			Size = UDim2.fromOffset(0, 32), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = i, Parent = alertRow,
		})
		Kit.corner(b, 16)
		Kit.stroke(b, sev.color, 2)
		Kit.pad(b, 12, 0)
		Kit.list(b, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
		Kit.icon({ Icon = sev.icon, Color = sev.color, Size = UDim2.fromOffset(20, 20), Parent = b, Order = 1 })
		Kit.label({ Text = a.text, Font = Kit.Fonts.Header, TextSize = 16, Color = sev.color, Size = UDim2.fromOffset(0, 24), AutoSize = Enum.AutomaticSize.X, Parent = b, Order = 2 })
		if a.onClick then
			b.Activated:Connect(a.onClick)
		end
	end
end

local THREAT_COLORS = { T.good, T.accent, Color3.fromRGB(255, 140, 60), T.danger }

function Hud.setThreat(pressure: number)
	local name, tier = Difficulty.label(pressure)
	threatLabel.Text = "THREAT: " .. name
	threatLabel.TextColor3 = THREAT_COLORS[tier]
	threatIcon.ImageColor3 = THREAT_COLORS[tier]
end

function Hud.setQueue(count: number, onClick: (() -> ())?)
	queueClick = onClick
	queueButton.Visible = count > 0
	Kit.setButtonText(queueButton, if count == 1 then "1 AT THE DOOR" else count .. " AT THE DOOR")
end

local BUTTONS = {
	{ key = "Build", icon = "build", text = "BUILD" },
	{ key = "Survivors", icon = "survivors", text = "SURVIVORS" },
	{ key = "Wasteland", icon = "wasteland", text = "WASTELAND" },
	{ key = "Weapons", icon = "weapons", text = "WEAPONS" },
	{ key = "Outfits", icon = "outfits", text = "OUTFITS" },
	{ key = "Quests", icon = "quests", text = "OBJECTIVES" },
	{ key = "Shop", icon = "shop", text = "SHOP" },
}

local function buildBottom()
	bottomBar = Kit.new("Frame", {
		BackgroundTransparency = 1, Size = UDim2.fromOffset(#BUTTONS * 112 + 40, 104), AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10), Name = "BottomBar", Parent = gui,
	})
	local plate = Kit.panel({ Size = UDim2.fromScale(1, 1), Parent = bottomBar })
	Kit.hazard(plate, UDim2.new(0, 120, 0, 6), UDim2.new(0.5, -60, 0, 4))
	local row = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -24, 1, -18), Position = UDim2.fromOffset(12, 12), Parent = plate })
	Kit.list(row, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	for i, b in BUTTONS do
		local btn = Kit.new("ImageButton", {
			BackgroundTransparency = 1, Size = UDim2.fromOffset(104, 80), LayoutOrder = i, Name = b.key,
			Image = "", AutoButtonColor = false, Parent = row,
		})
		local face = Kit.new("Frame", { BackgroundColor3 = T.panelInner, Size = UDim2.fromScale(1, 1), Parent = btn })
		Kit.corner(face, 10)
		Kit.stroke(face, T.border, 2)
		Kit.icon({ Icon = b.icon, Color = if b.key == "Build" or b.key == "Wasteland" then T.accent else T.text, Size = UDim2.fromOffset(40, 40), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8), Parent = face })
		Kit.label({ Text = b.text, Font = Kit.Fonts.Header, TextSize = 15, XAlign = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 20), Position = UDim2.new(0, 0, 1, -26), Parent = face, Color = T.text })
		btn.Activated:Connect(function()
			Kit.press(btn)
			C.UIController.onMenu(b.key)
		end)
		btn.MouseEnter:Connect(function()
			face.BackgroundColor3 = T.border
		end)
		btn.MouseLeave:Connect(function()
			face.BackgroundColor3 = T.panelInner
		end)
	end
end

function Hud.setBottomVisible(on: boolean)
	local target = if on then UDim2.new(0.5, 0, 1, -10) else UDim2.new(0.5, 0, 1, 130)
	TweenService:Create(bottomBar, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { Position = target }):Play()
end

-- Toasts -------------------------------------------------------------------------
local TONE = {
	good = { T.good, "star" },
	bad = { T.danger, "raid" },
	warn = { T.accent, "info" },
	info = { T.text, "info" },
}

function Hud.toast(text: string, tone: string?)
	local tc = TONE[tone or "info"] or TONE.info
	local f = Kit.new("Frame", {
		BackgroundColor3 = T.panel, BackgroundTransparency = 0.05, Size = UDim2.fromOffset(0, 46),
		AutomaticSize = Enum.AutomaticSize.X, Parent = toastStack, LayoutOrder = -math.floor(os.clock() * 100),
	})
	Kit.corner(f, 23)
	Kit.stroke(f, tc[1], 2)
	Kit.pad(f, 16, 0)
	Kit.list(f, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	Kit.icon({ Icon = tc[2], Color = tc[1], Size = UDim2.fromOffset(26, 26), Parent = f, Order = 1 })
	Kit.label({ Text = text, TextSize = 19, Font = Kit.Fonts.BodyBold, Size = UDim2.fromOffset(0, 30), AutoSize = Enum.AutomaticSize.X, Parent = f, Order = 2 })
	Kit.pop(f)
	local kids = {}
	for _, c in toastStack:GetChildren() do
		if c:IsA("Frame") then
			table.insert(kids, c)
		end
	end
	if #kids > 3 then
		table.sort(kids, function(a, b)
			return a.LayoutOrder > b.LayoutOrder
		end)
		kids[1]:Destroy()
	end
	task.delay(3.6, function()
		if f.Parent then
			for _, d in f:GetDescendants() do
				if d:IsA("TextLabel") then
					TweenService:Create(d, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
				elseif d:IsA("ImageLabel") then
					TweenService:Create(d, TweenInfo.new(0.3), { ImageTransparency = 1 }):Play()
				elseif d:IsA("UIStroke") then
					TweenService:Create(d, TweenInfo.new(0.3), { Transparency = 1 }):Play()
				end
			end
			TweenService:Create(f, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
			task.wait(0.32)
			f:Destroy()
		end
	end)
end

-- Banners ------------------------------------------------------------------------
function Hud.setBanner(text: string?, color: Color3?, fraction: number?, onTap: (() -> ())?)
	if not text then
		banner.Visible = false
		return
	end
	banner.Visible = true
	bannerText.Text = text
	local stroke = banner:FindFirstChildOfClass("UIStroke")
	if stroke and color then
		stroke.Color = color
	end
	bannerMeterFrame.Visible = fraction ~= nil
	if fraction then
		bannerMeter(fraction, color)
	end
	banner:SetAttribute("HasTap", onTap ~= nil)
	Hud._bannerTap = onTap
end
Hud._bannerTap = nil :: (() -> ())?

function Hud.setHint(text: string?, onCancel: (() -> ())?)
	if not text then
		hintBar.Visible = false
		return
	end
	hintBar.Visible = true
	hintText.Text = text
	hintCancel = onCancel or function() end
	Kit.pop(hintBar)
end

-- Updates --------------------------------------------------------------------------
function Hud.updateResources(state)
	lastState = state
	local res, caps, flow = state.resources or {}, state.caps or {}, state.flow or {}
	for key, m in meters do
		local def = Resources.Defs[key]
		local v, cap = res[key] or 0, caps[key] or 1
		local f = flow[key] or { prod = 0, use = 0 }
		local net = f.prod - f.use
		local low = v / cap < def.low and net < 0
		m.set(v / cap, if low then T.danger else Theme.Resource[key])
		m.value.Text = Kit.fmt(v) .. "/" .. Kit.fmt(cap)
		-- "+12 -15 = -3/m": production, consumption, trend
		m.rate.Text = string.format("%s %s = %s/m", fmtRate(f.prod), fmtRate(-f.use), fmtRate(net))
		m.rate.TextColor3 = if net < -0.05 then T.danger elseif net > 0.05 then T.good else T.textMuted
		m.frame:SetAttribute("Low", low)
	end
	boltsLabel.Text = Kit.fmt(res.Bolts or 0)
	local d = state.derived or {}
	popLabel.Text = string.format("%d/%d", math.floor(d.population or 0), math.floor(d.housing or 0))
	popLabel.TextColor3 = if (d.population or 0) >= (d.housing or 0) then T.accent else T.text
	local h = d.happiness or 0
	happyLabel.Text = string.format("%d%%", math.floor(h + 0.5))
	happyIcon.ImageColor3 = if h >= 60 then T.happy elseif h >= 35 then T.accent else T.danger
	shelterLabel.Text = tostring(state.shelterNo or "")
	Hud.setThreat(d.pressure or 0)
end

function Hud.Init(controllers)
	C = controllers
	gui = Kit.screen("MainHUD", 5)
	buildTop()
	buildBottom()
	toastStack = Kit.new("Frame", {
		BackgroundTransparency = 1, Size = UDim2.fromOffset(900, 200), AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 128), Name = "Toasts", Parent = gui,
	})
	Kit.list(toastStack, Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center)
	banner = Kit.new("TextButton", {
		BackgroundColor3 = Color3.fromRGB(40, 16, 14), BackgroundTransparency = 0.05, Text = "", AutoButtonColor = false,
		Size = UDim2.fromOffset(460, 62), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 260),
		Visible = false, Name = "Banner", Parent = gui,
	})
	Kit.corner(banner, 10)
	Kit.stroke(banner, T.danger, 3)
	Kit.icon({ Icon = "raid", Color = T.danger, Size = UDim2.fromOffset(44, 44), Position = UDim2.fromOffset(10, 9), Parent = banner })
	bannerText = Kit.label({ Text = "", Font = Kit.Fonts.Header, TextSize = 24, Size = UDim2.new(1, -70, 0, 30), Position = UDim2.fromOffset(62, 6), Parent = banner })
	local bm, bset = Kit.meter({ Parent = banner, Size = UDim2.new(1, -76, 0, 10), Position = UDim2.fromOffset(62, 40), Color = T.danger })
	bannerMeterFrame = bm
	bannerMeter = bset
	banner.Activated:Connect(function()
		if Hud._bannerTap then
			Hud._bannerTap()
		end
	end)
	hintBar = Kit.new("Frame", {
		BackgroundColor3 = T.panel, BackgroundTransparency = 0.04, Size = UDim2.fromOffset(620, 64),
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -128), Visible = false, Name = "Hint", Parent = gui,
	})
	Kit.corner(hintBar, 12)
	Kit.stroke(hintBar, T.accent, 2)
	hintText = Kit.label({ Text = "", Font = Kit.Fonts.BodyBold, TextSize = 20, Size = UDim2.new(1, -170, 1, 0), Position = UDim2.fromOffset(18, 0), Parent = hintBar, Wrapped = true })
	Kit.button({
		Text = "CANCEL", Style = "danger", Size = UDim2.fromOffset(130, 46), AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0), Parent = hintBar, OnClick = function()
			if hintCancel then
				hintCancel()
			end
		end,
	})
	-- low-resource pulse
	RunService.RenderStepped:Connect(function()
		local p = (math.sin(os.clock() * 6) + 1) / 2
		for _, m in meters do
			local stroke = m.frame:FindFirstChild("Meter") and (m.frame:FindFirstChild("Meter") :: Frame):FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = if m.frame:GetAttribute("Low") then T.border:Lerp(T.danger, p) else T.border
			end
		end
	end)
end

function Hud.gui(): ScreenGui
	return gui
end

return Hud
