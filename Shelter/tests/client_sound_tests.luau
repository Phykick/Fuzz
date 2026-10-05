-- Headless tests for the client SoundController (see run_client.py). Fake Sound / SoundGroup
-- objects record what plays; StateStore, camera, renderer and the UI kit are stubs.
local T = {}
local failures = {}

local function check(cond: any, msg: string)
	if not cond then
		table.insert(failures, msg)
		out("  check failed: " .. msg)
	end
	return cond
end

-- Fake engine pieces the controller touches ----------------------------------------------------
local played = {} -- { id, region start, volume, speed, sound }
local function fakeSound(n)
	local props = rawget(n, "_props")
	props.IsPlaying = false
	props.Play = function(self)
		local pr = rawget(self, "_props")
		pr.IsPlaying = true
		pr.plays += 1
		local r = pr.PlaybackRegion
		table.insert(played, { id = pr.SoundId, start = r and r.Min, volume = pr.Volume, speed = pr.PlaybackSpeed, sound = self })
	end
	props.Stop = function(self)
		self.IsPlaying = false
	end
	props.Pause = function(self)
		self.IsPlaying = false
		self.pauses = (self.pauses or 0) + 1
	end
	props.Resume = function(self)
		self.IsPlaying = true
		self.resumes = (self.resumes or 0) + 1
	end
	props.Volume = 0.5
	props.PlaybackSpeed = 1
	props.plays, props.pauses, props.resumes = 0, 0, 0
end

local realNew = Instance.new
Instance.new = function(class: string)
	local n = realNew(class)
	if class == "Sound" then
		fakeSound(n)
	end
	return n
end

local SoundService = H.newNode("SoundService", "SoundService")
local ContentProvider = H.newNode("ContentProvider", "ContentProvider")
local broken = {} -- asset ids that won't load (private / deleted)
local preloaded = {}
rawget(ContentProvider, "_props").PreloadAsync = function(_, list, callback)
	for _, item in list do
		local sid = rawget(item, "_props").SoundId
		table.insert(preloaded, sid)
		if callback then
			callback(sid, if broken[sid] then Enum.AssetFetchStatus.Failure else Enum.AssetFetchStatus.Success)
		end
	end
end
H.services.SoundService = SoundService
H.services.ContentProvider = ContentProvider
local RunService = H.services.RunService
rawget(RunService, "_props").Heartbeat = H.Signal()

local buttons = {}
local nameSeq = 0
local Kit = {}
Kit.sound = function(_cue: string) end
Kit.screen = function(name)
	return H.newNode(name, "ScreenGui")
end
Kit.new = function(class, props)
	nameSeq += 1
	local n = H.newNode((props and props.Name or class) .. nameSeq, class)
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
	b.onClick = props.OnClick
	table.insert(buttons, b)
	return b
end
Kit.list = function() end
Kit.pop = function() end
Kit.setButtonText = function(b, text)
	b.Text = text
end
H.define("StarterPlayer.StarterPlayerScripts.Client.Ui.Kit", "ModuleScript", function()
	return Kit
end)

-- Stub controllers -----------------------------------------------------------------------------
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
-- two rooms: one on screen (x 10..28), one far away
S.state = {
	ready = true,
	powerFactor = 1,
	raid = nil,
	rooms = {
		["1"] = { id = "1", type = "Entrance", col = 0, row = 0, modules = 1 },
		["2"] = { id = "2", type = "Power", col = 3, row = 0, modules = 2 },
		["3"] = { id = "3", type = "Water", col = 40, row = 10, modules = 1 },
		["4"] = { id = "4", type = "Living", col = 6, row = 0, modules = 1 },
	},
	dwellers = { ["7"] = { id = "7", status = "Working" } },
	settings = { sfx = true, music = true },
}
local centers = {
	["1"] = Vector3.new(9, 6, 0),
	["2"] = Vector3.new(27, 6, 0),
	["3"] = Vector3.new(250, -114, 0), -- off screen
	["4"] = Vector3.new(45, 6, 0),
}
local zoom = 0.3
local C = {
	StateStore = S,
	CameraController = {
		visibleRect = function(m)
			return -10 - (m or 0), 80 + (m or 0), -30 - (m or 0), 30 + (m or 0)
		end,
		zoomAlpha = function()
			return zoom
		end,
	},
	VaultRenderer = {
		roomCenter = function(id)
			return centers[id]
		end,
	},
}

local Atlas = H.require(H.node("ReplicatedStorage.Shared.SoundAtlas"))
local Bank = H.require(H.node("ReplicatedStorage.Shared.SoundBank"))

local function lastPlay()
	return played[#played]
end

-- the first played entry since `since` that used this asset id
local function playedId(sid, since)
	for i = (since or 0) + 1, #played do
		if played[i].id == sid then
			return played[i]
		end
	end
	return nil
end

-- a cue played with its first (preferred) public id
local function playedCue(cue, since)
	return playedId(Bank.Cues[cue].ids[1], since)
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
	local steps = math.floor(seconds / 0.05)
	for _ = 1, steps do
		RunService.Heartbeat:Fire(0.05)
		task.wait(0.05)
	end
end

local function boot(atlas: string?)
	Bank.ATLAS_ID = atlas or ""
	local SC = H.require(H.node("StarterPlayer.StarterPlayerScripts.Client.Controllers.SoundController"))
	SC.Init(C)
	SC.Start()
	return SC
end

-- Tests -----------------------------------------------------------------------------------------
T.public_audio_without_uploads = function()
	boot()
	local folder = SoundService:FindFirstChild("UH_Sound")
	check(folder ~= nil, "sound folder created")
	for name, cue in Bank.Cues do
		check(type(cue.ids) == "table" and #cue.ids > 0, "cue " .. name .. " has public audio")
		for _, sid in cue.ids do
			check(string.match(sid, "^rbxassetid://%d+$") ~= nil, name .. ": well-formed id " .. sid)
		end
	end
	check(table.find(preloaded, Bank.Cues.death.ids[1]) ~= nil, "candidates are checked before use")
	S.Snapshot:Fire(S.state)
	-- tapped collect on screen: full volume, then bolts
	local mark = #played
	S.Collected:Fire({ roomId = "2", amount = 5, bolts = 2, tapped = true })
	task.wait(0.3)
	local c = playedCue("collect", mark)
	check(c ~= nil, "collect plays its public sound")
	check(c and math.abs(c.volume - Bank.Cues.collect.volume) < 1e-6, "full volume on screen")
	check(playedCue("bolts", mark) ~= nil, "bolts follow")
	-- automatic deposit off screen: silent
	mark = #played
	S.Collected:Fire({ roomId = "3", amount = 5, bolts = 0, tapped = false })
	task.wait(0.2)
	check(playedCue("collect", mark) == nil, "off-screen auto-collect stays quiet")
	-- a death
	mark = #played
	S.DwellerChanged:Fire({ id = "7", status = "Dead" })
	task.wait(0.1)
	check(playedCue("death", mark) ~= nil, "death cue")
	-- each weapon has its own report
	mark = #played
	S.state.raid = { phase = "inside", roomId = "1", raiders = {} }
	S.Combat:Fire({ events = {
		{ a = "r1", t = "7", d = 5, w = "ImprovisedShotgun" },
		{ a = "7", t = "r1", d = 3, w = "Fists" },
		{ a = "r2", t = "7", d = 2, w = "ScrapPistol" },
	} })
	task.wait(0.4)
	local g = playedCue("shotgun", mark)
	check(g ~= nil, "shotgun uses the shotgun sample")
	check(playedCue("punch", mark) ~= nil, "fists punch")
	local pistol = playedCue("gunshot", mark)
	check(pistol and pistol.speed > 0.95 and pistol.speed < 1.2, "pistol pitched by weapon (" .. tostring(pistol and pistol.speed) .. ")")
	S.state.raid = nil
	-- actions
	mark = #played
	S.ActionDone:Fire("Build", true, {}, nil)
	task.wait(0.05)
	check(playedCue("build", mark) ~= nil, "build cue")
	mark = #played
	S.ActionDone:Fire("Assign", false, "full", nil)
	task.wait(0.05)
	check(playedCue("error", mark) ~= nil, "failed action buzzes")
	mark = #played
	task.wait(0.4)
	S.ActionDone:Fire("Settings", false, "x", true)
	task.wait(0.05)
	check(playedCue("error", mark) == nil, "quiet failures stay quiet")
	mark = #played
	S.Incident:Fire({ roomId = "3", kind = "Fire" })
	task.wait(0.05)
	local f = playedCue("fire_start", mark)
	check(f and f.volume >= Bank.Cues.fire_start.volume * 0.6 - 1e-6, "emergencies are heard even off screen")
end

T.unavailable_audio_falls_back = function()
	-- collect's first choice was made private: the second one plays
	broken[Bank.Cues.collect.ids[1]] = true
	-- every public choice for death is gone: our own atlas (uploaded) takes over
	for _, sid in Bank.Cues.death.ids do
		broken[sid] = true
	end
	boot("rbxassetid://424242")
	S.Snapshot:Fire(S.state)
	local mark = #played
	S.Collected:Fire({ roomId = "2", amount = 5, bolts = 0, tapped = true })
	task.wait(0.1)
	check(playedId(Bank.Cues.collect.ids[1], mark) == nil, "the unavailable sound is skipped")
	check(playedId(Bank.Cues.collect.ids[2], mark) ~= nil, "the next candidate plays instead")
	mark = #played
	S.DwellerChanged:Fire({ id = "7", status = "Dead" })
	task.wait(0.1)
	local d = playedId("rbxassetid://424242", mark)
	check(d ~= nil and d.start == Atlas.death[1], "atlas region used as last resort")
end

T.silent_and_named_when_nothing_loads = function()
	for _, sid in Bank.Cues.upgrade.ids do
		broken[sid] = true
	end
	boot()
	S.Snapshot:Fire(S.state)
	local mark = #played
	S.ActionDone:Fire("Upgrade", true, {}, nil)
	task.wait(0.1)
	check(#played == mark, "nothing plays")
	task.wait(16)
	local warned = false
	for i = #H.warnings, 1, -1 do
		local w = H.warnings[i]
		if string.find(w, "No playable audio for:", 1, true) and string.find(w, "upgrade", 1, true) then
			warned = true
			table.remove(H.warnings, i)
		end
	end
	check(warned, "Studio names the cue that needs a new id")
end

T.long_clips_are_cut = function()
	boot()
	S.Snapshot:Fire(S.state)
	local mark = #played
	S.ActionDone:Fire("Build", true, {}, nil)
	task.wait(0.05)
	local b = playedCue("build", mark)
	check(b ~= nil and b.sound.IsPlaying, "build clip playing")
	task.wait(Bank.Cues.build.cut + 0.3)
	check(b and not b.sound.IsPlaying, "stopped after its cut (" .. Bank.Cues.build.cut .. " s)")
	check(b and b.sound.Volume < Bank.Cues.build.volume * 0.5, "faded rather than chopped")
	-- overlapping gunfire uses separate voices
	mark = #played
	S.state.raid = { phase = "inside", roomId = "1", raiders = {} }
	for _ = 1, 3 do
		S.Combat:Fire({ events = { { a = "r1", t = "7", d = 1, w = "ScrapPistol" } } })
		task.wait(0.06)
	end
	S.state.raid = nil
	local voices = {}
	for i = mark + 1, #played do
		if played[i].id == Bank.Cues.gunshot.ids[1] then
			voices[played[i].sound] = true
		end
	end
	local n = 0
	for _ in voices do
		n += 1
	end
	check(n >= 2, "shots overlap on separate voices (" .. n .. ")")
end

T.ui_clicks_and_panels = function()
	boot()
	S.Snapshot:Fire(S.state)
	local mark = #played
	Kit.sound("click")
	task.wait(0.05)
	check(playedCue("click", mark) ~= nil, "button click")
	-- switching panels: close then open in the same frame -> only the open sound
	mark = #played
	task.wait(0.3)
	Kit.sound("close")
	Kit.sound("open")
	task.wait(0.2)
	-- open and close share a swish; close is the lower-pitched one
	local swish = Bank.Cues.open.ids[1]
	local closeSpeed = Bank.Cues.close.speed
	local o = playedId(swish, mark)
	check(o ~= nil and math.abs(o.speed - 1) < 0.02, "open plays")
	check(countId(swish, mark) == 1, "the close that came with it doesn't")
	mark = #played
	task.wait(0.3)
	Kit.sound("close")
	task.wait(0.2)
	local c = playedId(Bank.Cues.close.ids[1], mark)
	check(c ~= nil and math.abs(c.speed - closeSpeed) < 0.02, "a plain close plays, lower")
end

T.loops_follow_the_screen = function()
	boot()
	S.Snapshot:Fire(S.state)
	heartbeat(3)
	local folder = SoundService:FindFirstChild("UH_Sound")
	local function loop(name)
		return folder:FindFirstChild("Loop_" .. name)
	end
	check(loop("vault").IsPlaying and loop("vault").Volume > 0.25, "vault ambience playing")
	check(loop("vault").SoundId == Bank.Loops.vault.ids[1], "ambience is public audio")
	check(loop("power").Volume > 0.1, "generator on screen hums (" .. loop("power").Volume .. ")")
	check(loop("water").Volume < 0.05, "off-screen pumps barely audible (" .. loop("water").Volume .. ")")
	check(not loop("fire").IsPlaying, "no fire, no crackle")
	-- a fire on screen
	S.state.rooms["4"].incident = { kind = "Fire", hp = 10, maxHp = 10 }
	heartbeat(3)
	check(loop("fire").IsPlaying and loop("fire").Volume > 0.25, "fire crackles (" .. loop("fire").Volume .. ")")
	S.state.rooms["4"].incident = nil
	heartbeat(4)
	check(not loop("fire").IsPlaying, "crackle fades out and pauses")
	-- brownout slows the pumps
	S.state.powerFactor = 0.3
	heartbeat(1)
	check(loop("water").PlaybackSpeed < 0.85, "pumps labour in a brownout (" .. loop("water").PlaybackSpeed .. ")")
	S.state.powerFactor = 1
	-- raid at the door: alarm + banging, then the breach
	local mark = #played
	S.state.raid = { phase = "door", roomId = "1", raiders = {} }
	S.Raid:Fire(S.state.raid)
	heartbeat(3)
	check(loop("alarm").IsPlaying, "alarm sounds")
	local hits = countId(Bank.Cues.door_hit.ids[1], mark)
	check(hits >= 2, "raiders hammer on the door (" .. hits .. ")")
	mark = #played
	S.state.raid = { phase = "inside", roomId = "1", raiders = {} }
	S.Raid:Fire(S.state.raid)
	task.wait(0.05)
	check(playedCue("door_breach", mark) ~= nil, "door breach")
	S.state.raid = nil
	S.RaidEnd:Fire({ success = true })
	heartbeat(4)
	check(not loop("alarm").IsPlaying, "alarm stops after the raid")
end

T.settings_toggle_and_save = function()
	boot()
	S.state.settings = { sfx = false, music = true }
	S.Snapshot:Fire(S.state)
	local ui = SoundService:FindFirstChild("UH_UI")
	local sfx = SoundService:FindFirstChild("UH_SFX")
	local amb = SoundService:FindFirstChild("UH_Ambience")
	check(ui.Volume == 0 and sfx.Volume == 0 and amb.Volume == 1, "saved settings applied on join")
	local toggle
	for _, b in buttons do
		if b:GetAttribute("Setting") == "sfx" then
			toggle = b
		end
	end
	check(toggle ~= nil, "effects toggle exists")
	toggle.onClick()
	task.wait(0.1)
	check(sfx.Volume == 1, "effects back on")
	local sent = S.actions[#S.actions]
	check(sent and sent.name == "Settings" and sent.payload.sfx == true and sent.quiet == true, "setting saved to the server")
	check(string.find(toggle.Text, "ON", 1, true) ~= nil, "toggle shows ON")
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
	H.runUntil(H.clock() + 600, function()
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
