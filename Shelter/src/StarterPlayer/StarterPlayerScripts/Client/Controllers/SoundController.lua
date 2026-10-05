--!strict
-- Sound: one uploaded audio atlas (SoundBank.ATLAS_ID) played in pieces with PlaybackRegion.
-- One-shots come from a small pool of voices; continuous beds (vault air, generator hum, water
-- pumps, fire, raid alarm) fade with what's on screen, so the shelter sounds like what you look
-- at. Pumps slow down in a brownout. Events come from StateStore; UI clicks through Kit.sound.
-- Two toggles (Sound effects / Ambience) are saved with the shelter (data.settings).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")

local SoundBank = require(ReplicatedStorage.Shared.SoundBank)
local SoundAtlas = require(ReplicatedStorage.Shared.SoundAtlas)
local Theme = require(ReplicatedStorage.Shared.Theme)

local Ui = script.Parent.Parent:WaitForChild("Ui")
local Kit = require(Ui.Kit)

local SoundController = {}
local C: any

local VOICES = 14
local enabled = SoundBank.ATLAS_ID ~= ""
local folder: Folder
local groups: { [string]: SoundGroup } = {}
local voices: { Sound } = {}
local nextVoice = 1
local lastPlayed: { [string]: number } = {}
type Loop = { sound: Sound, cue: any, target: number, current: number, speed: number, playing: boolean, started: boolean }
local loops: { [string]: Loop } = {}
local settings = { sfx = true, music = true }
local statuses: { [string]: string } = {}
local raidPhase: string? = nil

-- Playback -------------------------------------------------------------------------------------
local function region(name: string): (number?, number?)
	local r = (SoundAtlas :: any)[name]
	if not r then
		return nil
	end
	return r[1], r[2]
end

-- Play a cue. gain scales the cue's volume (e.g. by distance); pitch multiplies its speed.
function SoundController.play(name: string, gain: number?, pitch: number?)
	if not enabled then
		return
	end
	local cue = (SoundBank.Cues :: any)[name]
	if not cue then
		return
	end
	local start, length = region(cue.region)
	if not start then
		return
	end
	local now = os.clock()
	if now - (lastPlayed[name] or -1e9) < (cue.cooldown or 0.03) then
		return
	end
	lastPlayed[name] = now
	local s = voices[nextVoice]
	nextVoice = nextVoice % #voices + 1
	s:Stop()
	s.SoundGroup = groups[cue.group]
	s.PlaybackRegion = NumberRange.new(start, start + (length :: number))
	s.Volume = cue.volume * (gain or 1)
	s.PlaybackSpeed = (pitch or 1) * (1 + (math.random() * 2 - 1) * (cue.pitch or 0))
	s:Play()
end

local function play(name: string, gain: number?, pitch: number?)
	SoundController.play(name, gain, pitch)
end

-- Louder for things on screen, a muffled hint of what's happening elsewhere.
local function onScreen(roomId: string?): boolean
	if not roomId then
		return true
	end
	local c = C.VaultRenderer.roomCenter(roomId)
	if not c then
		return false
	end
	local x0, x1, y0, y1 = C.CameraController.visibleRect(4)
	return c.X > x0 and c.X < x1 and c.Y > y0 and c.Y < y1
end

local function roomGain(roomId: string?): number
	local far = C.CameraController.zoomAlpha() > 0.75
	return (if onScreen(roomId) then 1 else 0.35) * (if far then 0.75 else 1)
end

-- Settings ----------------------------------------------------------------------------------------
local function applySettings()
	groups.UI.Volume = if settings.sfx then 1 else 0
	groups.SFX.Volume = if settings.sfx then 1 else 0
	groups.Ambience.Volume = if settings.music then 1 else 0
end

local toggleButton: ImageButton
local togglePanel: Frame

local function refreshToggles()
	if not toggleButton then
		return
	end
	Kit.setButtonText(toggleButton, if settings.sfx or settings.music then "SOUND" else "MUTED")
	for _, b in togglePanel:GetChildren() do
		local key = b:GetAttribute("Setting")
		if key then
			local on = (settings :: any)[key] == true
			Kit.setButtonText(b, (if key == "sfx" then "EFFECTS " else "AMBIENCE ") .. (if on then "ON" else "OFF"))
			local button = b :: ImageButton
			button.ImageColor3 = if on then Theme.UI.good else Theme.UI.panelInner
		end
	end
end

local function setSetting(key: string, on: boolean)
	(settings :: any)[key] = on
	applySettings()
	refreshToggles()
	task.spawn(function()
		C.StateStore.action("Settings", { [key] = on }, true)
	end)
end

local function buildToggle()
	local gui = Kit.screen("SoundUI", 7)
	toggleButton = Kit.button({
		Text = "SOUND", Size = UDim2.fromOffset(112, 46), TextSize = 17, AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -16), Parent = gui, Name = "SoundToggle",
		OnClick = function()
			togglePanel.Visible = not togglePanel.Visible
			if togglePanel.Visible then
				Kit.pop(togglePanel)
			end
		end,
	})
	togglePanel = Kit.new("Frame", {
		BackgroundTransparency = 1, Size = UDim2.fromOffset(190, 108), AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -70), Visible = false, Parent = gui,
	})
	Kit.list(togglePanel, Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Bottom)
	for i, key in { "sfx", "music" } do
		local b = Kit.button({
			Text = "", Size = UDim2.fromOffset(190, 48), TextSize = 17, Parent = togglePanel, Order = i,
			OnClick = function()
				setSetting(key, not (settings :: any)[key])
			end,
		})
		b:SetAttribute("Setting", key)
	end
	refreshToggles()
end

-- Loops ---------------------------------------------------------------------------------------------
local function makeLoop(key: string, cue: any)
	local start, length = region(cue.region)
	if not start then
		return
	end
	local s = Instance.new("Sound")
	s.Name = "Loop_" .. key
	s.SoundId = SoundBank.ATLAS_ID
	s.PlaybackRegionsEnabled = true
	s.PlaybackRegion = NumberRange.new(start, start + (length :: number))
	s.LoopRegion = NumberRange.new(start, start + (length :: number))
	s.Looped = true
	s.Volume = 0
	s.SoundGroup = groups[cue.group]
	s.Parent = folder
	loops[key] = { sound = s, cue = cue, target = 0, current = 0, speed = 1, playing = false, started = false }
end

local nextDoorHit, nextSqueak = 0, 0

-- What the beds should be doing right now (4x a second).
local function updateTargets()
	local state = C.StateStore.state
	if not state.ready then
		return
	end
	local x0, x1, y0, y1 = C.CameraController.visibleRect(8)
	local close = 1 - 0.55 * C.CameraController.zoomAlpha()
	local power, water, fireOn, fireSeen = 0, 0, false, false
	local critters: { string } = {}
	for id, r in state.rooms do
		local c = C.VaultRenderer.roomCenter(id)
		local seen = c ~= nil and c.X > x0 and c.X < x1 and c.Y > y0 and c.Y < y1
		local inc = r.incident
		if inc and inc.kind == "Fire" then
			fireOn = true
			fireSeen = fireSeen or seen
		elseif inc and inc.kind ~= "Breakdown" then
			table.insert(critters, id)
		end
		if seen and not inc then
			if r.type == "Power" then
				power += r.modules
			elseif r.type == "Water" then
				water += r.modules
			end
		end
	end
	local pf = state.powerFactor or 1
	loops.vault.target = 1
	loops.power.target = if power > 0 then math.min(1, 0.55 + 0.15 * power) * close else 0.08
	loops.water.target = (if water > 0 then math.min(1, 0.55 + 0.15 * water) * close else 0.06) * (0.4 + 0.6 * pf)
	loops.water.speed = 0.75 + 0.25 * pf -- pumps labour in a brownout
	loops.fire.target = if fireOn then (if fireSeen then 1 else 0.3) else 0
	local raid = state.raid
	loops.alarm.target = if raid then (if raid.phase == "door" then 1 else 0.6) else 0
	local now = os.clock()
	-- raiders hammering on the blast door
	if raid and raid.phase == "door" and now >= nextDoorHit then
		nextDoorHit = now + 1 + math.random() * 0.6
		local entrance
		for id, r in state.rooms do
			if r.type == "Entrance" then
				entrance = id
			end
		end
		play("door_hit", roomGain(entrance))
	end
	-- critters chittering in infested rooms
	if #critters > 0 and now >= nextSqueak then
		nextSqueak = now + 1.8 + math.random() * 2.2
		local id = critters[math.random(1, #critters)]
		play("creature", roomGain(id) * 0.8)
	end
end

-- Events --------------------------------------------------------------------------------------------
local function connectEvents()
	local S = C.StateStore
	S.Snapshot:Connect(function(state)
		table.clear(statuses)
		for id, d in state.dwellers do
			statuses[id] = d.status
		end
		raidPhase = state.raid and state.raid.phase
		local st = state.settings
		if type(st) == "table" then
			settings.sfx = st.sfx ~= false
			settings.music = st.music ~= false
			applySettings()
			refreshToggles()
		end
	end)
	S.ActionDone:Connect(function(name: string, ok: boolean, result: any, quiet: boolean?)
		if not ok then
			if not quiet then
				play("error")
			end
			return
		end
		if name == "Build" then
			play("build")
		elseif name == "Upgrade" then
			play("upgrade")
		elseif name == "Destroy" then
			play("demolish")
		elseif name == "Rush" and result and result.success then
			play("rush")
		elseif name == "Repair" then
			play("build", 0.6, 1.15)
		elseif name == "Revive" then
			play("revive")
		elseif name == "Heal" then
			play("heal")
		elseif name == "Explore" then
			play("welcome", 0.8, 0.8)
		elseif name == "TurnAway" then
			play("close")
		end
	end)
	S.Collected:Connect(function(p)
		if (p.amount or 0) <= 0 then
			if p.full and p.tapped then
				play("error", 0.6)
			end
			return
		end
		-- taps are the player's doing; automatic deposits only make a sound when seen
		local gain = roomGain(p.roomId)
		if not p.tapped and gain < 1 then
			return
		end
		play("collect", gain * (if p.tapped then 1 else 0.5))
		if (p.bolts or 0) > 0 then
			task.delay(0.12, play, "bolts", gain)
		end
	end)
	S.Incident:Connect(function(p)
		local gain = math.max(0.6, roomGain(p.roomId)) -- emergencies are always worth hearing
		play(if p.kind == "Fire" then "fire_start" elseif p.kind == "Breakdown" then "breakdown" else "creature", gain)
	end)
	S.IncidentEnd:Connect(function(p)
		local gain = roomGain(p.roomId)
		if p.kind == "Fire" then
			play("extinguish", gain)
		elseif p.kind == "Breakdown" then
			play("repair_done", gain)
		else
			play("creature", gain, 1.25)
		end
		if (p.bolts or 0) > 0 then
			task.delay(0.3, play, "bolts", gain)
		end
	end)
	S.Raid:Connect(function(raid)
		local phase = raid and raid.phase
		if phase and raidPhase == "door" and phase ~= "door" then
			play("door_breach")
		end
		raidPhase = phase
	end)
	S.RaidEnd:Connect(function(p)
		raidPhase = nil
		play(if p.success then "raid_win" else "raid_lose")
	end)
	S.Combat:Connect(function(p)
		local raid = C.StateStore.state.raid
		local gain = roomGain(raid and raid.roomId) * 0.9
		for i, e in p.events do
			if i > 4 then
				break
			end
			task.delay((i - 1) * 0.06, function()
				if e.w == "Fists" then
					play("punch", gain)
				else
					play("gunshot", gain, (SoundBank.WeaponPitch :: any)[e.w] or 1)
				end
			end)
		end
	end)
	S.LevelUp:Connect(function()
		play("levelup")
	end)
	S.Arrival:Connect(function()
		play("welcome")
	end)
	S.Family:Connect(function(p)
		if p.kind == "court" then
			play("romance")
		elseif p.kind == "expecting" then
			play("romance", 1, 1.12)
		elseif p.kind == "born" then
			play("birth")
		elseif p.kind == "grown" then
			play("levelup")
		end
	end)
	S.DwellerChanged:Connect(function(d)
		local before = statuses[d.id]
		statuses[d.id] = d.status
		if before and before ~= d.status then
			if d.status == "Dead" then
				play("death")
			elseif d.status == "Waiting" then
				play("doorbell")
			end
		end
	end)
	S.DwellerRemoved:Connect(function(id)
		statuses[id] = nil
	end)
	S.ExploreEnded:Connect(function()
		play("welcome")
		task.delay(0.25, play, "bolts")
	end)
	S.Offline:Connect(function()
		play("open")
	end)
end

-- Lifecycle -------------------------------------------------------------------------------------------
function SoundController.Init(controllers)
	C = controllers
	folder = Instance.new("Folder")
	folder.Name = "UH_Sound"
	folder.Parent = SoundService
	for _, name in { "UI", "SFX", "Ambience" } do
		local g = Instance.new("SoundGroup")
		g.Name = "UH_" .. name
		g.Volume = 1
		g.Parent = SoundService
		groups[name] = g
	end
	if not enabled then
		if RunService:IsStudio() then
			warn("[Sound] No audio uploaded yet: upload Shelter/audio/underhaven_sounds.ogg and set SoundBank.ATLAS_ID (see README).")
		end
		return
	end
	for i = 1, VOICES do
		local s = Instance.new("Sound")
		s.Name = "Voice" .. i
		s.SoundId = SoundBank.ATLAS_ID
		s.PlaybackRegionsEnabled = true
		s.Parent = folder
		table.insert(voices, s)
	end
	for key, cue in SoundBank.Loops :: any do
		makeLoop(key, cue)
	end
	-- UI hooks: every button press clicks; panels sound when they open and close
	local lastOpen = 0
	Kit.sound = function(cue: string)
		if cue == "open" then
			lastOpen = os.clock()
			play("open")
		elseif cue == "close" then
			-- switching panels closes one and opens another: let the open win
			task.delay(0.05, function()
				if os.clock() - lastOpen > 0.1 then
					play("close")
				end
			end)
		else
			play(cue)
		end
	end
end

function SoundController.Start()
	if not enabled then
		return
	end
	buildToggle()
	applySettings()
	connectEvents()
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync({ voices[1] })
		end)
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 0.25 then
			acc = 0
			updateTargets()
		end
		local k = math.min(1, dt * 2.5)
		for _, l in loops do
			l.current += (l.target - l.current) * k
			local s = l.sound
			s.Volume = l.cue.volume * l.current
			s.PlaybackSpeed = l.speed
			if l.current > 0.003 and not l.playing then
				if l.started then
					s:Resume()
				else
					s:Play()
					l.started = true
				end
				l.playing = true
			elseif l.target == 0 and l.current <= 0.003 and l.playing then
				s:Pause()
				l.playing = false
			end
		end
	end)
end

return SoundController
