-- Headless tests for the client AudioManager (see run.py). Fake Sound objects record what plays;
-- StateStore, camera, renderer and the UI kit are stubs. The audio library (SoundGroups + Sound
-- objects) is built the way the server builds it at start.
local T = {}
local failures = {}

local function check(cond: any, msg: string)
	if not cond then
		table.insert(failures, msg)
		out("  check failed: " .. msg)
	end
	return cond
end

-- Fake engine pieces ---------------------------------------------------------------------------
local played = {} -- { id, volume, speed, sound, t }
local function fakeSound(n)
	local props = rawget(n, "_props")
	props.IsPlaying = false
	props.SoundId = ""
	props.TimePosition = 0
	props.Looped = false
	props.Volume = 0.5
	props.PlaybackSpeed = 1
	props.plays = 0
	props.Play = function(self)
		local pr = rawget(self, "_props")
		pr.IsPlaying = true
		pr.plays += 1
		table.insert(played, { id = pr.SoundId, volume = pr.Volume, speed = pr.PlaybackSpeed, sound = self, t = H.clock() })
	end
	props.Stop = function(self)
		rawget(self, "_props").IsPlaying = false
	end
	props.Pause = function(self)
		rawget(self, "_props").IsPlaying = false
	end
	props.Resume = function(self)
		rawget(self, "_props").IsPlaying = true
	end
end

local realNew = Instance.new
Instance.new = function(class: string)
	local n = realNew(class)
	if class == "Sound" then
		fakeSound(n)
	end
	return n
end

local SoundService = H.services.SoundService
local broken = {} -- content ids that won't load (private / deleted / moderated)
rawget(H.services.ContentProvider, "_props").PreloadAsync = function(_, list, callback)
	for _, item in list do
		local sid = rawget(item, "_props").SoundId
		if callback then
			callback(sid, if broken[sid] then Enum.AssetFetchStatus.Failure else Enum.AssetFetchStatus.Success)
		end
	end
end
local RunService = H.services.RunService
rawget(RunService, "_props").Heartbeat = H.Signal()
local UIS = H.newNode("UserInputService", "UserInputService")
rawget(UIS, "_props").InputBegan = H.Signal()
H.services.UserInputService = UIS
rawget(H.services.Players, "_props").LocalPlayer = { UserId = 42 }
rawget(H.game, "_props").CreatorType = Enum.CreatorType.Group
rawget(H.game, "_props").CreatorId = 7

-- UI kit stub: real nodes, names kept so rows and buttons can be found
local buttons = {}
local seq = 0
local Kit = {}
Kit.Fonts = { Header = "Header", Body = "Body", BodyBold = "BodyBold", Number = "Number" }
Kit.sound = function(_cue: string) end
Kit.screen = function(name)
	return H.newNode(name, "ScreenGui")
end
Kit.new = function(class, props)
	seq += 1
	local n = H.newNode(props and props.Name or (class .. seq), class)
	for k, v in props or {} do
		if k ~= "Parent" and k ~= "Name" then
			n[k] = v
		end
	end
	if props and props.Parent then
		n.Parent = props.Parent
	end
	return n
end
Kit.button = function(props)
	local b = Kit.new("ImageButton", { Name = props.Name or "Button", Parent = props.Parent })
	b.Text = props.Text
	b.onClick = props.OnClick
	table.insert(buttons, b)
	return b
end
Kit.label = function(props)
	local l = Kit.new("TextLabel", { Name = props.Name or ("Label" .. (seq + 1)), Parent = props.Parent })
	l.Text = props.Text
	return l
end
Kit.panel = function(props)
	return Kit.new("ImageLabel", { Name = props.Name or "Panel", Parent = props.Parent })
end
Kit.list = function() end
Kit.pop = function() end
Kit.setButtonText = function(b, text)
	b.Text = text
end
H.define("StarterPlayer.StarterPlayerScripts.Client.Ui.Kit", "ModuleScript", function()
	return Kit
end)

local function press(label: string, rowName: string?)
	for _, b in buttons do
		local parent = b.Parent
		if (b.Text == label or b.Name == label) and (rowName == nil or (parent and parent.Name == rowName)) then
			b.onClick()
			return true
		end
	end
	return false
end

-- Stub controllers -------------------------------------------------------------------------------
local function signals(list)
	local s = {}
	for _, n in list do
		s[n] = H.Signal()
	end
	return s
end

local S = signals({ "Snapshot", "ActionDone", "Collected", "Incident", "IncidentEnd", "Raid", "RaidEnd", "Combat",
	"LevelUp", "Arrival", "Family", "DwellerChanged", "DwellerRemoved", "ExploreEnded", "Offline" })
S.actions = {}
S.action = function(name, payload, quiet)
	table.insert(S.actions, { name = name, payload = payload, quiet = quiet })
	return true
end
-- camera shows x -10..80, y -30..30; listener over (35, 0)
S.state = {
	ready = true,
	powerFactor = 1,
	raid = nil,
	resources = { Water = 50 },
	rooms = {
		["1"] = { id = "1", type = "Entrance", assigned = {} },
		["2"] = { id = "2", type = "Power", assigned = { "7" } },
		["3"] = { id = "3", type = "Water", assigned = { "8" } }, -- far off screen
		["4"] = { id = "4", type = "Living", assigned = {} },
		["5"] = { id = "5", type = "Water", assigned = {} }, -- on screen, nobody working yet
	},
	dwellers = { ["7"] = { id = "7", status = "Working", roomId = "2" }, ["8"] = { id = "8", status = "Working", roomId = "3" } },
	settings = {},
}
local centers = {
	["1"] = Vector3.new(9, 6, 0),
	["2"] = Vector3.new(27, 6, 0),
	["3"] = Vector3.new(250, -114, 0),
	["4"] = Vector3.new(45, 6, 0),
	["5"] = Vector3.new(60, -6, 0),
}
local view = 30
local worldNode = H.newNode("UH_World", "Folder")
local C = {
	StateStore = S,
	CameraController = {
		visibleRect = function(m)
			return -10 - (m or 0), 80 + (m or 0), -30 - (m or 0), 30 + (m or 0)
		end,
		viewHeight = function()
			return view
		end,
		zoomAlpha = function()
			return (view - 11) / 109
		end,
	},
	VaultRenderer = {
		roomCenter = function(id)
			return centers[id]
		end,
		roomBounds = function(id)
			local c = centers[id]
			if not c then
				return nil
			end
			return c.X - 8, c.X + 8, c.Y - 4
		end,
	},
	InputController = {
		world = function()
			return worldNode
		end,
	},
	BuildController = { Changed = H.Signal() },
	DwellerController = {
		positionOf = function(id)
			return if id == "r1" then Vector3.new(12, 6, 0) else nil
		end,
	},
	WastelandController = { active = false },
}

local Config = H.require(H.node("ReplicatedStorage.Audio.AudioConfig"))
local Library = H.require(H.node("ReplicatedStorage.Audio.AudioLibrary"))

local function cid(n: number): string
	return string.format("rbxassetid://%d", n)
end

local function playedId(sid, since)
	for i = (since or 0) + 1, #played do
		if played[i].id == sid then
			return played[i]
		end
	end
	return nil
end

-- the first play of a cue (voices are clones named after their cue)
local function playedName(name, since)
	for i = (since or 0) + 1, #played do
		if played[i].sound.Name == name then
			return played[i]
		end
	end
	return nil
end

local function countName(name, since)
	local n = 0
	for i = (since or 0) + 1, #played do
		if played[i].sound.Name == name then
			n += 1
		end
	end
	return n
end

local function countId(sid, since)
	local n = 0
	for i = (since or 0) + 1, #played do
		if played[i].id == sid then
			n += 1
		end
	end
	return n
end

local function heartbeat(seconds)
	for _ = 1, math.floor(seconds / 0.05 + 0.5) do
		RunService.Heartbeat:Fire(0.05)
		task.wait(0.05)
	end
end

-- the Sound of a 3D bed slot (attachments on the emitter part are named <Bed><n>)
local function bed(name: string, i: number?)
	local emitter = worldNode:FindFirstChild("UH_AudioEmitters")
	local att = emitter and emitter:FindFirstChild(name .. (i or 1))
	return att and att:FindFirstChild(name), att
end

local function twoD(name: string)
	return SoundService:FindFirstChild("UH_Audio2D"):FindFirstChild(name)
end

-- warnings a test provokes on purpose
local function takeWarning(pattern: string): string?
	for i = #H.warnings, 1, -1 do
		local w = H.warnings[i]
		if string.find(w, pattern, 1, true) then
			table.remove(H.warnings, i)
			return w
		end
	end
	return nil
end

local function boot()
	Library.ensure() -- what AudioService does on the server at start
	local AM = H.require(H.node("StarterPlayer.StarterPlayerScripts.Client.Controllers.AudioManager"))
	C.AudioManager = AM
	AM.Init(C)
	AM.Start()
	S.Snapshot:Fire(S.state)
	heartbeat(0.3)
	return AM
end

-- Every audio id in the brief that is meant to play (three are deliberately left out: see NotUsed).
local BRIEF_IDS = {
	113397864512278, 958120197, 4601635577, 119541807359284, 17403146731, 330274138, 1835270782,
	135658480423375, 9114235460, 9119594530, 9125980816, 9120102202, 9116279358, 9125519018, 9114270776,
	2091298142, 6814491848, 6814493519, 9114145200, 9114151207,
	6362185620, 1244506786, 18984787734,
	9113088926, 98532097014415, 108427904413933, 168323076,
	444742380, 9119481278, 9172960182, 114560640706315, 9120590649, 9120591135, 9117941991,
	101485554695540, 55224766,
	1841151615, 9042708412,
}
local CLICK, SELECT, CONFIRM = cid(113397864512278), cid(4601635577), cid(119541807359284)
local COIN_DROP, COIN, SUCCESS = cid(330274138), cid(17403146731), cid(1835270782)
local ELECTRIC, STATIC_BLAST, TOGGLE, BURSTS = cid(135658480423375), cid(9119594530), cid(9120102202), cid(9116279358)
local ALARM = cid(9113088926)

-- Tests -----------------------------------------------------------------------------------------
T.library_matches_the_brief = function()
	boot()
	for name, v in { Master = 1, Music = 0.35, SFX = 0.75, UI = 0.55, Ambient = 0.45, Voice = 1 } do
		local g = SoundService:FindFirstChild(name)
		check(g and g.ClassName == "SoundGroup" and math.abs(g.Volume - v) < 1e-9, "SoundGroup " .. name .. " at " .. v)
	end
	local root = H.node("ReplicatedStorage.Audio")
	local function at(path: string)
		local n = root
		for _, part in string.split(path, "/") do
			n = n and n:FindFirstChild(part)
		end
		return n
	end
	for _, path in { "UI/Click", "UI/Select", "UI/Confirm", "UI/Cancel", "UI/Error", "UI/Reward", "Vault/Generator",
		"Vault/Machinery", "Vault/Electricity", "Vault/Doors", "Vault/Elevator", "Vault/Pipes", "Vault/Water",
		"Characters/Footsteps", "Characters/Interaction", "Characters/Injury", "Events/Alarm", "Events/Fire",
		"Events/PowerFailure", "Events/WaterFailure", "Events/Raid", "Events/Explosion", "Resources",
		"Rewards/ResourceCollected", "Rewards/ConstructionComplete", "Rewards/LevelUp", "Rewards/Achievement" } do
		check(at(path) ~= nil, "folder ReplicatedStorage.Audio." .. path)
	end
	for name, cue in Config.Sounds do
		local s = at(cue.folder .. "/" .. name)
		check(s and s.ClassName == "Sound" and s.SoundId == cid(cue.ids[1].id), "Sound object for " .. name)
		check(s and s.SoundGroup == SoundService:FindFirstChild(cue.group), name .. " is in the " .. cue.group .. " group")
		if cue.space == "3D" then
			check(s and s.RollOffMode == Enum.RollOffMode.InverseTapered and s.RollOffMaxDistance > s.RollOffMinDistance, name .. " fades with distance")
		end
	end
	local used = {}
	for _, list in { Config.Sounds, Config.Loops } do
		for _, cue in list do
			for _, a in cue.ids do
				used[a.id] = true
			end
		end
	end
	for _, id in BRIEF_IDS do
		check(used[id], "brief id " .. id .. " is used, unchanged")
	end
	for _, n in Config.NotUsed do
		check(not used[n.id], "kept out: " .. n.title)
	end
	local function first(cue: string)
		return (Config.Sounds[cue] or Config.Loops[cue]).ids[1].id
	end
	for cue, id in {
		UIClick = 113397864512278, UISelect = 4601635577, UIConfirm = 119541807359284, UIReward = 330274138,
		ConstructionComplete = 1835270782, ConstructionStart = 9120102202, ConstructionMode = 9120102202,
		CollectFood = 330274138, Currency = 17403146731, GeneratorStart = 135658480423375, ElectricalZap = 9114235460,
		PowerFailure = 9119594530, PowerRestored = 135658480423375, MachineryStartup = 9125980816,
		ElectricalEmergency = 9116279358, Alarm = 9113088926, DoorOpen = 6814491848, DoorClose = 6814493519,
		DoorOpenClose = 2091298142, DoorHeavy = 9114151207, DoorOld = 9114145200, WaterSplash = 444742380,
		WaterFlow = 9172960182, Explosion = 101485554695540, FootstepConcrete = 6362185620, Discovery = 9042708412,
		AmbientMusic = 1841151615,
	} do
		check(first(cue) == id, cue .. " uses " .. id)
	end
	-- UI volumes in the requested ranges
	local S_ = Config.Sounds
	check(S_.UIClick.volume >= 0.25 and S_.UIClick.volume <= 0.4, "click 0.25-0.4")
	check(S_.UISelect.volume >= 0.2 and S_.UISelect.volume <= 0.35, "select 0.2-0.35")
	check(S_.UIConfirm.volume >= 0.3 and S_.UIConfirm.volume <= 0.45, "confirm 0.3-0.45")
	check(S_.UIReward.volume >= 0.35 and S_.UIReward.volume <= 0.5, "reward 0.35-0.5")
	check(S_.Achievement.volume >= 0.5 and S_.Achievement.volume <= 0.7, "achievement 0.5-0.7")
end

T.failed_ids_are_recorded_not_replaced = function()
	broken[cid(113397864512278)] = true -- UI Click 1
	broken[cid(9113088926)] = true -- Alarm Master 19
	broken[cid(9125519018)] = true -- both Electric Whooshes: Upgrade has nothing left
	broken[cid(9114270776)] = true
	boot()
	task.wait(4) -- the load check runs a few seconds after joining
	local f = Config.Failed[113397864512278]
	check(f and f.cue == "UIClick", "failed click recorded in AudioConfig.Failed")
	check(Config.Failed[9113088926] ~= nil, "failed alarm recorded")
	local mark = #played
	Kit.sound("UIClick")
	task.wait(0.05)
	check(playedId(cid(958120197), mark), "click uses its listed alternate (958120197)")
	check(not playedId(CLICK, mark), "the broken id isn't played")
	mark = #played
	S.ActionDone:Fire("Upgrade", true, {}, nil, { roomId = "2" })
	task.wait(0.1)
	check(countName("Upgrade", mark) == 0, "a cue with nothing loadable stays silent (no stand-in)")
	-- the alarm moves on to the next alarm in the brief's list
	S.state.rooms["4"].incident = { kind = "Fire", hp = 10, maxHp = 10 }
	heartbeat(1)
	check(playedId(cid(98532097014415), mark), "alarm falls back to the brief's alternate alarm")
	S.state.rooms["4"].incident = nil
	check(takeWarning("failed to load") ~= nil, "Studio lists failed assets")
	local w = takeWarning("No playable sound for")
	check(w and string.find(w, "Upgrade", 1, true), "Studio names the silent cues")
	for i = 1, #played do
		local id = played[i].id
		local known = false
		for _, list in { Config.Sounds, Config.Loops } do
			for _, cue in list do
				for _, a in cue.ids do
					if cid(a.id) == id then
						known = true
					end
				end
			end
		end
		check(known, "only configured ids ever play (" .. tostring(id) .. ")")
	end
end

T.ui_sounds_dont_stack = function()
	boot()
	local mark = #played
	Kit.sound("UIClick") -- a list row is pressed...
	Kit.sound("UISelect") -- ...and selects a survivor in the same moment
	task.wait(0.03)
	local click, sel = playedId(CLICK, mark), playedId(SELECT, mark)
	check(sel and sel.sound.IsPlaying, "select plays")
	check(click == nil or not click.sound.IsPlaying, "the click under it is cut")
	mark = #played
	Kit.sound("UIClick")
	task.wait(0.03)
	check(not playedId(CLICK, mark), "a less important UI sound in the same moment is dropped")
	task.wait(0.3)
	mark = #played
	Kit.sound("UIClick")
	task.wait(0.03)
	local c = playedId(CLICK, mark)
	check(c, "later clicks play")
	check(c and c.sound.Parent.Name == "UH_Audio2D", "UI is 2D")
	check(c and c.volume >= 0.25 and c.volume <= 0.4, "click volume " .. tostring(c and c.volume))
	task.wait(0.3)
	mark = #played
	Kit.sound("UIClick")
	Kit.sound("UIConfirm")
	task.wait(0.03)
	check(playedId(CONFIRM, mark) and playedId(CONFIRM, mark).sound.IsPlaying, "confirm wins over the click")
end

T.resources_only_by_hand = function()
	boot()
	local mark = #played
	S.Collected:Fire({ roomId = "2", resource = "Food", amount = 5, bolts = 2, tapped = true })
	task.wait(0.3)
	local food = playedName("CollectFood", mark)
	check(food and food.id == COIN_DROP, "collecting food: coin drop")
	check(playedId(COIN, mark), "bolts: coin sound")
	mark = #played
	task.wait(0.3)
	S.Collected:Fire({ roomId = "5", resource = "Water", amount = 5, bolts = 0, tapped = true })
	task.wait(0.1)
	local w = playedName("CollectWater", mark)
	check(w and w.id == COIN_DROP and w.speed > 1.0, "water: same coin drop, a little higher")
	mark = #played
	task.wait(0.3)
	for _ = 1, 10 do
		S.Collected:Fire({ roomId = "2", resource = "Food", amount = 1, bolts = 0, tapped = false })
		task.wait(0.05)
	end
	check(#played == mark or countId(COIN_DROP, mark) == 0, "the simulation's own deposits are silent")
end

T.construction = function()
	boot()
	local mark = #played
	for _ = 1, 5 do
		C.BuildController.Changed:Fire("Power")
		task.wait(0.03)
	end
	task.wait(0.05)
	check(countName("ConstructionMode", mark) == 1, "entering build mode: one switch click, even when spammed")
	check(playedId(TOGGLE, mark), "build mode uses the industrial toggle switch")
	mark = #played
	S.ActionDone:Fire("Build", true, { roomId = "2" }, nil, { type = "Power", col = 3, row = 0 })
	task.wait(0.1)
	local st = playedName("ConstructionStart", mark)
	check(st and st.id == TOGGLE, "construction starts with the switch")
	check(st and st.sound.Parent.ClassName == "Attachment" and st.sound.Parent.Position == centers["2"], "in 3D at the new room")
	task.wait(0.6)
	check(playedId(SUCCESS, mark), "construction complete: success sting")
	mark = #played
	S.ActionDone:Fire("Build", false, "Not enough materials", nil, {})
	task.wait(0.05)
	check(playedName("UIError", mark), "a refused build buzzes")
end

T.footsteps_are_throttled = function()
	local AM = boot()
	local here = Vector3.new(35, 0, 0)
	local mark = #played
	for _ = 1, 40 do -- 20 footfalls a second asked for, for 2 seconds
		AM:Footstep(here, false, "Living")
		task.wait(0.05)
	end
	local n = countName("FootstepConcrete", mark)
	check(n >= 8 and n <= 16, "footsteps capped near 6 a second (" .. n .. " in 2 s)")
	for i = mark + 1, #played do
		local p = played[i]
		if p.sound.Name == "FootstepConcrete" then
			check(p.volume >= 0.15 and p.volume <= 0.3, "footstep volume 0.15-0.3 (" .. p.volume .. ")")
			check(p.speed >= 0.95 and p.speed <= 1.05, "footstep speed 0.95-1.05 (" .. p.speed .. ")")
			check(p.sound.Parent.ClassName == "Attachment", "footsteps are 3D")
		end
	end
	local ids = {}
	for i = mark + 1, #played do
		ids[played[i].id] = true
	end
	local variety = 0
	for _ in ids do
		variety += 1
	end
	check(variety >= 2, "footsteps vary between the concrete samples")
	view = 60
	task.wait(1)
	mark = #played
	for _ = 1, 10 do
		AM:Footstep(here)
		task.wait(0.2)
	end
	check(countName("FootstepConcrete", mark) == 0, "no footsteps when zoomed out")
	view = 30
	mark = #played
	for _ = 1, 5 do
		AM:Footstep(Vector3.new(75, 25, 0))
		task.wait(0.3)
	end
	check(countName("FootstepConcrete", mark) == 0, "survivors at the edge of the screen are quiet")
	for _ = 1, 3 do
		AM:Footstep(Vector3.new(75, 25, 0), false, nil, true)
		task.wait(0.3)
	end
	check(countName("FootstepConcrete", mark) == 3, "the selected survivor is always heard")
	mark = #played
	AM:Footstep(here, true, "Water")
	task.wait(0.05)
	check(playedName("FootstepWet", mark), "wet floor in the water purifier")
end

T.survivor_activities = function()
	local AM = boot()
	local here = Vector3.new(35, 0, 0)
	local mark = #played
	AM:Interaction("Repair", here, "a")
	task.wait(0.05)
	check(playedName("SwitchToggle", mark), "starting a repair: a switch clunk")
	mark = #played
	AM:Interaction("Drink", here, "b") -- someone else, straight after
	task.wait(2)
	AM:Interaction("Repair", here, "a") -- the same survivor again, too soon
	task.wait(0.05)
	check(#played == mark, "one survivor at a time, and not the same one over and over")
	AM:Interaction("Drink", here, "b")
	task.wait(0.05)
	check(playedName("WaterSmall", mark), "drinking: a small slosh")
	view = 60
	task.wait(2)
	mark = #played
	AM:Interaction("Farm", here, "c")
	task.wait(0.05)
	check(#played == mark, "not when zoomed out")
	AM:Interaction("Sleep", here, "d")
	check(#played == mark, "sleeping makes no sound")
end

T.doors_are_debounced = function()
	local AM = boot()
	local pos = Vector3.new(9, 6, 0)
	local mark = #played
	AM:Door("BlastDoor", true, pos, "heavy")
	task.wait(0.4)
	AM:Door("BlastDoor", false, pos, "heavy") -- interrupted straight away
	task.wait(0.4)
	AM:Door("BlastDoor", true, pos, "heavy")
	task.wait(0.1)
	check(countId(cid(9114151207), mark) == 1, "an interrupted door doesn't replay (" .. countId(cid(9114151207), mark) .. ")")
	check(playedId(cid(9114151207), mark).sound.Parent.ClassName == "Attachment", "doors are 3D")
	task.wait(1.5)
	mark = #played
	AM:Door("BlastDoor", false, pos, "heavy")
	task.wait(0.05)
	local c = playedId(cid(9114151207), mark)
	check(c and c.speed < 0.9, "heavy door closing, lower")
	mark = #played
	AM:Door("Store", true, pos)
	task.wait(1.4)
	AM:Door("Store", false, pos)
	task.wait(0.05)
	check(playedId(cid(6814491848), mark) and playedId(cid(6814493519), mark), "ordinary door open and close sounds")
end

T.elevator_rides = function()
	local AM = boot()
	local pos = Vector3.new(30, 0, 0)
	local mark = #played
	AM:Elevator("depart", pos, "3")
	task.wait(0.6)
	check(playedName("ElevatorButton", mark) and playedName("ElevatorDoorClose", mark), "button and doors on departure")
	local motor = playedName("ElevatorMotor", mark)
	check(motor and motor.speed < 0.7, "the motor is a slowed industrial whoosh")
	AM:Elevator("move", Vector3.new(30, -10, 0), "3")
	check(motor and motor.sound.Parent.Position.Y == -10, "the motor travels with the car")
	task.wait(0.5)
	AM:Elevator("arrive", Vector3.new(30, -12, 0), "3")
	task.wait(0.6)
	check(motor and not motor.sound.IsPlaying, "the motor stops on arrival")
	check(playedName("ElevatorArrive", mark) and playedName("ElevatorDoorOpen", mark), "clunk and doors on arrival")
	mark = #played
	AM:Elevator("depart", pos, "3")
	task.wait(0.6)
	AM:Elevator("depart", Vector3.new(500, 0, 0), "9")
	task.wait(0.6)
	check(countName("ElevatorButton", mark) == 0, "no repeat within seconds, and off-screen cars are silent")
end

T.one_alarm_for_every_emergency = function()
	local AM = boot()
	heartbeat(1)
	local mark = #played
	S.state.rooms["4"].incident = { kind = "Fire", hp = 10, maxHp = 10 }
	S.Incident:Fire({ roomId = "4", kind = "Fire" })
	heartbeat(1)
	check(playedName("FireStart", mark), "fire starts with a whoosh")
	local first = playedId(ALARM, mark)
	local alarm = first and first.sound
	check(alarm and alarm.IsPlaying and alarm.Looped, "the alarm sounds")
	check(alarm and alarm.Volume >= 0.45 and alarm.Volume <= 0.65, "emergency volume 0.45-0.65 (" .. tostring(alarm and alarm.Volume) .. ")")
	local crackle = bed("FireCrackle")
	check(crackle and crackle.IsPlaying, "the fire crackles where it burns")
	S.state.raid = { phase = "door", roomId = "1", raiders = {} }
	S.Raid:Fire(S.state.raid)
	heartbeat(1.5)
	local voices = {}
	for i = mark + 1, #played do
		if played[i].id == ALARM then
			voices[played[i].sound] = true
		end
	end
	local nv = 0
	for _ in voices do
		nv += 1
	end
	check(nv == 1, "a second emergency doesn't stack another alarm (" .. nv .. ")")
	check(playedName("RaidDoorHit", mark), "raiders hammer on the blast door")
	heartbeat(3)
	check(alarm and not alarm.IsPlaying, "the alarm doesn't loop for the whole emergency")
	local p0 = alarm and alarm.plays or 0
	heartbeat(16)
	check(alarm and alarm.plays > p0, "it reminds while the emergency lasts")
	S.state.rooms["4"].incident = nil
	S.state.raid = nil
	S.RaidEnd:Fire({ success = true })
	heartbeat(3)
	check(alarm and not alarm.IsPlaying, "silence when it's over")
	check(playedId(SUCCESS, mark), "raid repelled: success sting")
	local p1 = alarm and alarm.plays or 0
	heartbeat(60)
	check(alarm and alarm.plays == p1, "no alarm after the all clear")
	check(AM:Stats().voices <= AM:Stats().maxVoices, "voice cap respected")
end

T.power_failure_and_restore = function()
	boot()
	heartbeat(2)
	local hum = bed("GeneratorHum")
	check(hum and hum.IsPlaying and hum.Volume > 0.2, "the visible generator hums (" .. tostring(hum and hum.Volume) .. ")")
	check(hum and hum.Parent.Position == centers["2"], "...at the generator")
	local air = twoD("VaultAir")
	check(air and air.IsPlaying, "the vault's air is always there")
	local humBefore, airBefore = hum and hum.Volume or 0, air and air.Volume or 0
	local mark = #played
	S.state.powerFactor = 0.3
	heartbeat(4)
	check(playedId(STATIC_BLAST, mark), "power failure: electrical failure sound")
	check(playedId(ALARM, mark), "power failure sounds the alarm")
	check(hum and hum.Volume < humBefore * 0.6, "machinery quietens (" .. tostring(hum and hum.Volume) .. ")")
	check(air and air.Volume < airBefore, "the vault goes quieter")
	heartbeat(4)
	mark = #played
	S.state.powerFactor = 1
	heartbeat(3)
	check(playedId(ELECTRIC, mark), "power back: electrical start-up")
	check(playedId(SUCCESS, mark), "and a success sting after a long outage")
	heartbeat(3)
	check(hum and hum.Volume > humBefore * 0.8, "machinery back up")
end

T.machines_start_and_stop = function()
	boot()
	heartbeat(1)
	local mark = #played
	S.state.rooms["5"].assigned = { "9" } -- the purifier gets its first worker
	heartbeat(0.5)
	local start = playedName("PurifierStart", mark)
	check(start and start.id == ELECTRIC and start.sound.Parent.Position == centers["5"], "purifier starts with an electric sound at the room")
	heartbeat(2)
	local flow, att = bed("WaterFlow")
	check(flow and flow.IsPlaying and att.Position == centers["5"], "water flows at the running purifier")
	check(flow and flow.SoundId == cid(9172960182), "the water fountain loop")
	mark = #played
	S.state.rooms["5"].incident = { kind = "Breakdown", hp = 0, maxHp = 1 }
	S.Incident:Fire({ roomId = "5", kind = "Breakdown" })
	heartbeat(0.5)
	check(playedName("WaterLeak", mark) and playedName("WaterFailure", mark), "a broken purifier leaks and winds down")
	mark = #played
	S.state.rooms["2"].incident = { kind = "Breakdown", hp = 0, maxHp = 1 }
	S.Incident:Fire({ roomId = "2", kind = "Breakdown" })
	heartbeat(1)
	check(playedId(BURSTS, mark), "generator failure: electrical bursts")
	check(C.AudioManager:Stats().alarm, "and the alarm (the same one the purifier set off)")
	mark = #played
	S.state.rooms["2"].incident = nil
	S.IncidentEnd:Fire({ roomId = "2", kind = "Breakdown" })
	heartbeat(2)
	check(playedName("GeneratorStart", mark), "repaired generator starts up")
	check(playedId(SUCCESS, mark), "with success feedback")
	S.state.rooms["5"].incident = nil
end

T.ambience_is_sparse = function()
	-- three busy rooms on screen, each with its own timer (rare distant sounds switched off here)
	S.state.rooms["5"].assigned = { "9" }
	S.state.rooms["6"] = { id = "6", type = "Workshop", assigned = { "10", "11" } }
	centers["6"] = Vector3.new(15, -6, 0)
	Config.Distant.every = { 1e6, 1e6 }
	local AM = boot()
	local mark = #played
	heartbeat(180)
	-- calm vault, zoomed in: occasional details from staffed rooms, nothing from the empty bedroom
	local details, lastT = 0, -1e9
	local gaps = true
	for i = mark + 1, #played do
		local p = played[i]
		local n = p.sound.Name
		if n == "ElectricalTick" or n == "SwitchToggle" or n == "WaterSmall" or n == "WaterDrip" then
			details += 1
			if p.t - lastT < 2.4 then
				gaps = false
			end
			lastT = p.t
		end
	end
	check(details >= 6, "the vault makes occasional machine noises (" .. details .. " in 3 min)")
	check(gaps, "details never crowd each other")
	check(#played - mark < 60, "no sound spam (" .. (#played - mark) .. " one-shots in 3 calm minutes)")
	check(playedName("AmbientMusic", mark), "rare quiet music between emergencies")
	check(AM:Stats().alarm == false, "no alarm in a calm vault")
	-- the off-screen purifier makes no noise of its own
	local flow = bed("WaterFlow")
	check(flow == nil or not flow.IsPlaying or flow.Parent.Position ~= centers["3"], "off-screen rooms stay silent")
end

T.volumes_are_saved = function()
	local AM = boot()
	local sfx, master = SoundService:FindFirstChild("SFX"), SoundService:FindFirstChild("Master")
	check(math.abs(sfx.Volume - 0.75) < 1e-9, "SFX starts at 0.75")
	check(press("-", "SFX") and press("-", "SFX"), "the SFX slider's minus button")
	check(math.abs(sfx.Volume - 0.75 * 0.8) < 1e-9, "SFX down to 80% (" .. sfx.Volume .. ")")
	check(#S.actions == 0, "not saved on every tap")
	task.wait(2)
	local sent = S.actions[#S.actions]
	check(#S.actions == 1 and sent.name == "Settings" and sent.quiet and sent.payload.volumes.SFX == 0.8, "saved once, quietly")
	local value = SoundService -- (find the SFX row's value label)
	for _, b in buttons do
		if b.Parent and b.Parent.Name == "SFX" then
			value = b.Parent:FindFirstChild("Value")
		end
	end
	check(value and value.Text == "80%", "the panel shows 80%")
	AM:SetVolume("Master", 0.5, true)
	check(math.abs(sfx.Volume - 0.75 * 0.8 * 0.5) < 1e-9 and master.Volume == 0.5, "Master scales everything")
	AM:SetVolume("UI", 0, true)
	local mark = #played
	task.wait(0.2)
	Kit.sound("UIClick")
	task.wait(0.05)
	check(not playedName("UIClick", mark), "a muted group plays nothing")
	S.state.settings = { sfx = false, music = true }
	S.Snapshot:Fire(S.state)
	task.wait(0.05)
	check(sfx.Volume == 0 and SoundService:FindFirstChild("UI").Volume == 0, "older saves' on/off switches still apply")
	S.state.settings = { volumes = { Master = 1, Music = 1, SFX = 0.5, Ambient = 1, UI = 1 } }
	S.Snapshot:Fire(S.state)
	task.wait(0.05)
	check(math.abs(sfx.Volume - 0.375) < 1e-9, "saved volumes applied on join")
end

T.voice_cap_and_priorities = function()
	local AM = boot()
	local here = Vector3.new(35, 0, 0)
	for _, cue in { "Gunshot", "Shotgun", "Revolver", "Rifle", "Punch" } do
		for _ = 1, 4 do
			AM:PlayAt(cue, here, { force = true, cut = 5 })
		end
	end
	check(AM:Stats().voices <= 14, "at most 14 one-shots at once (" .. AM:Stats().voices .. ")")
	local mark = #played
	AM:Footstep(here)
	check(countName("FootstepConcrete", mark) == 0, "expendable sounds give way when it's busy")
	AM:PlayAt("Explosion", here)
	check(playedName("Explosion", mark), "an explosion still gets through")
	check(AM:Stats().voices <= 14, "...by replacing something less important")
end

T.combat_and_story = function()
	local AM = boot()
	local mark = #played
	S.state.raid = { phase = "inside", roomId = "1", raiders = {} }
	S.Combat:Fire({ events = {
		{ a = "r1", t = "7", d = 5, w = "ImprovisedShotgun" },
		{ a = "7", t = "r1", d = 3, w = "Fists" },
		{ a = "r2", t = "7", d = 2, w = "ScrapPistol" },
	} })
	task.wait(0.4)
	local sg = playedName("Shotgun", mark)
	check(sg and sg.sound.Parent.Position == Vector3.new(12, 6, 0), "the shotgun fires where the raider stands")
	check(playedName("Punch", mark), "fists punch")
	local pistol = playedName("Gunshot", mark)
	check(pistol and pistol.speed > 0.95 and pistol.speed < 1.2, "pistol pitched for its weapon")
	S.state.raid = nil
	mark = #played
	S.Family:Fire({ kind = "born", a = "7" })
	task.wait(0.05)
	local born = playedName("SurvivorBorn", mark)
	check(born and born.id == cid(9042708412) and born.sound.SoundGroup == SoundService:FindFirstChild("Music"), "a birth: the Forgotten Memories sting, in the Music group")
	mark = #played
	AM:Encounter("Bunker", Vector3.new(35, 0, 0))
	task.wait(1.2)
	check(playedId(cid(9114145200), mark), "a forgotten bunker: old squeaky door")
	mark = #played
	S.state.rooms["2"].incident = { kind = "Fire", hp = 10, maxHp = 10 }
	S.Incident:Fire({ roomId = "2", kind = "Fire", cause = "rush" })
	task.wait(0.1)
	check(playedId(cid(101485554695540), mark), "an overloaded machine explodes")
	S.state.rooms["2"].incident = nil
	task.wait(2) -- past the explosion's cooldown
	mark = #played
	S.state.rooms["4"].incident = { kind = "Fire", hp = 10, maxHp = 10 }
	S.Incident:Fire({ roomId = "4", kind = "Fire", cause = "accident" })
	task.wait(0.1)
	check(not playedId(cid(101485554695540), mark), "an ordinary fire doesn't explode")
	S.state.rooms["4"].incident = nil
end

T.debug_panel_is_for_developers_only = function()
	H.studio = false
	boot()
	local AD = H.require(H.node("StarterPlayer.StarterPlayerScripts.Client.Controllers.AudioDebug"))
	AD.Init(C)
	check(not AD.allowed(), "a normal player doesn't get the audio debug panel")
	AD.Start()
	check(not press("AudioDebugToggle"), "...and nothing is created for them")
	Config.Debug.UserIds = { 42 }
	check(AD.allowed(), "a listed developer does")
	Config.Debug.UserIds = {}
	H.studio = true
	check(AD.allowed(), "always in Studio")
	AD.Start()
	local mark = #played
	check(press("Power failure"), "debug buttons exist in Studio")
	heartbeat(1)
	check(playedId(STATIC_BLAST, mark), "the power failure test plays the failure sound")
	check(C.AudioManager:Stats().powerFailed, "(simulated, local only)")
	press("Follow game")
	heartbeat(2)
	check(not C.AudioManager:Stats().powerFailed, "back to the real power state")
	check(#S.actions == 0, "debug tests never send anything to the server")
end

-- Runner ------------------------------------------------------------------------------------------
T.__run = function(name: string)
	local done = false
	task.spawn(function()
		local ok, err = pcall(T[name])
		if not ok then
			table.insert(failures, "test error: " .. tostring(err))
		end
		done = true
	end)
	H.runUntil(H.clock() + 900, function()
		return done
	end)
	for _, e in H.errors do
		table.insert(failures, "thread error: " .. e)
	end
	for _, w in H.warnings do
		table.insert(failures, "unexpected warning: " .. w)
	end
	out(if #failures == 0 then "RESULT PASS" else "RESULT FAIL")
	for _, f in failures do
		out("  - " .. f)
	end
end

return T
