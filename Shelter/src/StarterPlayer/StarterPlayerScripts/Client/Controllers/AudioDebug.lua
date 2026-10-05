--!strict
-- Developer-only audio test panel. It only exists in Studio, for the game's owner (user-owned
-- games) and for user ids listed in AudioConfig.Debug.UserIds; other players never get it.
-- Toggle with F7 (AudioConfig.Debug.Key) or the small AUDIO DEBUG button. Everything here is local
-- sound only: it never changes the shelter. "Power failure" and "Alarm" hold a simulated state
-- until "Follow game" hands control back to the real one.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local AudioConfig = require(ReplicatedStorage:WaitForChild("Audio"):WaitForChild("AudioConfig"))

local Ui = script.Parent.Parent:WaitForChild("Ui")
local Kit = require(Ui.Kit)

local AudioDebug = {}
local C: any

function AudioDebug.allowed(): boolean
	if RunService:IsStudio() then
		return true
	end
	local p = Players.LocalPlayer
	if table.find(AudioConfig.Debug.UserIds, p.UserId) then
		return true
	end
	return game.CreatorType == Enum.CreatorType.User and game.CreatorId == p.UserId
end

function AudioDebug.Init(controllers)
	C = controllers
end

function AudioDebug.Start()
	if not AudioDebug.allowed() then
		return
	end
	local A = C.AudioManager
	local alarmOn = false
	local function at(): Vector3
		return A:Focus()
	end
	-- after the button's own click, so the two don't mask each other
	local function later(fn: () -> ())
		task.delay(0.15, fn)
	end
	local tests: { { any } } = { -- { label, test }
		{ "UI click", function() A:Play("UIClick", { force = true }) end },
		{ "UI select", function() A:Play("UISelect") end },
		{ "Confirm", function() A:Play("UIConfirm") end },
		{ "Reward", function() A:Play("UIReward") end },
		{ "Success sting", function() A:Play("Achievement", { force = true }) end },
		{ "Door", function()
			A:Door("Debug", true, at(), "normal")
			task.delay(1.6, function()
				A:Door("Debug", false, at(), "normal")
			end)
		end },
		{ "Blast door", function() A:Door("DebugHeavy", true, at(), "heavy") end },
		{ "Generator", function() A:PlayAt("GeneratorStart", at()) end },
		{ "Electrical zap", function() A:PlayAt("ElectricalZap", at(), { force = true }) end },
		{ "Water", function()
			A:PlayAt("WaterSplash", at(), { force = true })
			task.delay(0.8, function()
				A:PlayAt("WaterSmall", at(), { force = true })
			end)
		end },
		{ "Footsteps", function()
			for i = 0, 5 do
				task.delay(i * 0.32, function()
					A:PlayAt(if i % 3 == 2 then "FootstepWet" else "FootstepConcrete", at(), { force = true })
				end)
			end
		end },
		{ "Elevator", function()
			local key = "Debug" .. tostring(os.clock())
			A:Elevator("depart", at(), key)
			task.delay(2.2, function()
				A:Elevator("arrive", at(), key)
			end)
		end },
		{ "Alarm on/off", function()
			alarmOn = not alarmOn
			A:Simulate("Emergency", alarmOn)
		end },
		{ "Explosion", function()
			A:PlayAt("Explosion", at(), { force = true })
			A:Emergency("Explosion")
		end },
		{ "Power failure", function() A:Simulate("PowerFailure", true) end },
		{ "Power restored", function() A:Simulate("PowerFailure", false) end },
		{ "Follow game", function()
			A:Simulate("PowerFailure", nil)
			alarmOn = false
			A:Simulate("Emergency", false)
		end },
		{ "Discovery", function() A:Play("Discovery", { force = true }) end },
		{ "Music", function() A:Play("AmbientMusic", { force = true }) end },
		{ "Report -> Output", function()
			local r = A:Report()
			print(string.format("[AudioDebug] %s: %d assets load, %d failed, %d alternates not needed", if r.done then "checked" else "still checking", r.ok, #r.failed, r.unchecked))
			for _, f in r.failed do
				print("  failed: " .. f)
			end
			if #r.missing > 0 then
				print("  silent cues: " .. table.concat(r.missing, ", "))
			end
			for _, n in AudioConfig.NotUsed do
				print(string.format("  not used: %d %s - %s", n.id, n.title, n.why))
			end
		end },
	}

	local gui = Kit.screen("AudioDebug", 30)
	local box = Kit.panel({ Size = UDim2.fromOffset(660, 470), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Parent = gui, Name = "AudioDebugPanel" })
	box.Visible = false
	Kit.label({ Text = "AUDIO DEBUG (developers only)", Font = Kit.Fonts.Header, TextSize = 20, Size = UDim2.new(1, -40, 0, 28), Position = UDim2.fromOffset(20, 14), Parent = box })
	local info = Kit.label({ Text = "", TextSize = 15, Wrapped = true, Size = UDim2.new(1, -40, 0, 44), Position = UDim2.fromOffset(20, 44), Parent = box, Name = "Status" })
	local grid = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -40, 1, -110), Position = UDim2.fromOffset(20, 96), Parent = box })
	Kit.new("UIGridLayout", { CellSize = UDim2.fromOffset(150, 46), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
	for i, t in tests do
		local fn = t[2]
		Kit.button({ Text = t[1], TextSize = 15, Order = i, Parent = grid, Name = t[1], OnClick = function()
			later(fn)
		end })
	end
	local function toggle()
		box.Visible = not box.Visible
	end
	Kit.button({ Text = "AUDIO DEBUG", TextSize = 13, Size = UDim2.fromOffset(120, 34), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0), Parent = gui, Name = "AudioDebugToggle", OnClick = toggle })
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == (Enum.KeyCode :: any)[AudioConfig.Debug.Key] then
			toggle()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			if box.Visible then
				local s = A:Stats()
				local r = A:Report()
				info.Text = string.format("voices %d/%d   alarm %s   power %s   emergencies: %s\nassets: %d load, %d failed%s",
					s.voices, s.maxVoices, if s.alarm then "ON" else "off", if s.powerFailed then "FAILED" else "ok",
					if #s.emergencies > 0 then table.concat(s.emergencies, ", ") else "none",
					r.ok, #r.failed, if r.done then "" else " (still checking)")
			end
		end
	end)
end

return AudioDebug
