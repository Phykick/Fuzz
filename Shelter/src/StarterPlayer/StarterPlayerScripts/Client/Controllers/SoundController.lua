--!strict
-- Sound: public Roblox audio for every game event (Creator Store ids in SoundBank, mostly Roblox's
-- licensed Pro Sound Effects library), so nothing has to be uploaded. On join the client checks
-- each cue's candidates actually load and settles on the first that does (Roblox can make audio
-- unavailable); our own generated atlas is an optional last resort. One-shots play from a small
-- per-cue pool, and long library clips are cut short with a fade. Continuous beds (vault air,
-- machinery, water, fire, raid alarm) fade with what's on screen, so the shelter sounds like what
-- you look at; pumps slow down in a brownout. Events come from StateStore, UI clicks through
-- Kit.sound. Two toggles (Sound effects / Ambience) are saved with the shelter (data.settings).
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

local POOL = 4 -- voices per cue, so overlapping plays (gunfire, clicks) don't cut each other off
local FADE = 0.15 -- seconds to fade out a clip that is cut short
local folder: Folder
local groups: { [string]: SoundGroup } = {}
local lastPlayed: { [string]: number } = {}
type Source = { id: string, start: number?, length: number? } -- a public asset, or a region of our atlas
local sources: { [string]: Source? } = {}
local pools: { [string]: { list: { Sound }, id: string, nextIdx: number } } = {}
local playTokens: { [Sound]: number } = {}
local tokenSeq = 0
type Loop = { sound: Sound?, cue: any, target: number, current: number, speed: number, playing: boolean, started: boolean }
local loops: { [string]: Loop } = {}
local settings = { sfx = true, music = true }
local statuses: { [string]: string } = {}
local raidPhase: string? = nil
local missing: { string } = {}

-- Playback -------------------------------------------------------------------------------------
local function region(name: string?): (number?, number?)
	local r = name and (SoundAtlas :: any)[name]
	if not r then
		return nil
	end
	return r[1], r[2]
end

-- A sound for the cue's current source, from a small pool.
local function voiceFor(name: string, src: Source): Sound
	local pool = pools[name]
	if not pool or pool.id ~= src.id then
		if pool then
			for _, old in pool.list do
				old:Destroy()
			end
		end
		pool = { list = {}, id = src.id, nextIdx = 1 }
		pools[name] = pool
	end
	for _, v in pool.list do
		if not v.IsPlaying then
			return v
		end
	end
	if #pool.list < POOL then
		local v = Instance.new("Sound")
		v.Name = name
		v.SoundId = src.id
		if src.start then
			v.PlaybackRegionsEnabled = true
			v.PlaybackRegion = NumberRange.new(src.start, src.start + (src.length :: number))
		end
		v.Parent = folder
		table.insert(pool.list, v)
		return v
	end
	local v = pool.list[pool.nextIdx]
	pool.nextIdx = pool.nextIdx % #pool.list + 1
	return v
end

-- Fade a clip out and stop it, unless it has been restarted meanwhile.
local function fadeOut(v: Sound, token: number)
	local v0 = v.Volume
	for i = 1, 5 do
		task.wait(FADE / 5)
		if playTokens[v] ~= token then
			return
		end
		v.Volume = v0 * (1 - i / 5)
	end
	if playTokens[v] == token then
		v:Stop()
	end
end

-- Play a cue. gain scales the cue's volume (e.g. by distance); pitch multiplies its speed.
function SoundController.play(name: string, gain: number?, pitch: number?)
	local cue = (SoundBank.Cues :: any)[name]
	local src = sources[name]
	if not cue or not src then
		return
	end
	local now = os.clock()
	if now - (lastPlayed[name] or -1e9) < (cue.cooldown or 0.03) then
		return
	end
	lastPlayed[name] = now
	local v = voiceFor(name, src)
	v:Stop()
	tokenSeq += 1
	local token = tokenSeq
	playTokens[v] = token
	v.SoundGroup = groups[cue.group]
	v.Volume = cue.volume * (gain or 1)
	v.PlaybackSpeed = (cue.speed or 1) * (pitch or 1) * (1 + (math.random() * 2 - 1) * (cue.pitch or 0))
	v:Play()
	if cue.cut and not src.start then -- atlas regions are already the right length
		task.delay(cue.cut, fadeOut, v, token)
	end
end

local function play(name: string, gain: number?, pitch: number?)
	SoundController.play(name, gain, pitch)
end

-- Does this asset actually load? (private, deleted or moderated audio doesn't)
local function loads(id: string): boolean
	local ok = false
	local probe = Instance.new("Sound")
	probe.SoundId = id
	local called = pcall(function()
		ContentProvider:PreloadAsync({ probe }, function(_, status)
			ok = status == Enum.AssetFetchStatus.Success
		end)
	end)
	probe:Destroy()
	return called and ok
end

local buildLoop: (key: string) -> ()

-- Use the cue's first candidate straight away, then settle on the first one that really loads,
-- falling back to our atlas (if uploaded) and finally to silence.
local function resolve(name: string, cue: any, isLoop: boolean)
	local ids = cue.ids or {}
	local start, length = region(cue.region)
	local atlas: Source? = if SoundBank.ATLAS_ID ~= "" and start then { id = SoundBank.ATLAS_ID, start = start, length = length } else nil
	sources[name] = if ids[1] then { id = ids[1] } else atlas
	task.spawn(function()
		local chosen: Source? = nil
		for _, candidate in ids do
			if loads(candidate) then
				chosen = { id = candidate }
				break
			end
		end
		chosen = chosen or atlas
		local before = sources[name]
		sources[name] = chosen
		if not chosen then
			table.insert(missing, name)
		end
		local changed = (before == nil) ~= (chosen == nil) or (before ~= nil and chosen ~= nil and before.id ~= chosen.id)
		if isLoop and changed then
			buildLoop(name)
		end
	end)
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
-- (Re)create a bed's Sound for its current source; the Heartbeat loop starts it when needed.
buildLoop = function(key: string)
	local l = loops[key]
	if not l then
		return
	end
	if l.sound then
		l.sound:Destroy()
		l.sound = nil
	end
	l.playing, l.started = false, false
	local src = sources[key]
	if not src then
		return
	end
	local v = Instance.new("Sound")
	v.Name = "Loop_" .. key
	v.SoundId = src.id
	v.Looped = true
	if src.start then
		v.PlaybackRegionsEnabled = true
		v.PlaybackRegion = NumberRange.new(src.start, src.start + (src.length :: number))
		v.LoopRegion = NumberRange.new(src.start, src.start + (src.length :: number))
	end
	v.Volume = 0
	v.SoundGroup = groups[l.cue.group]
	v.Parent = folder
	l.sound = v
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
					local w = (SoundBank.Weapons :: any)[e.w]
					play(if w then w.cue else "gunshot", gain, if w then w.speed else 1)
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
	for key, cue in SoundBank.Loops :: any do
		loops[key] = { sound = nil, cue = cue, target = 0, current = 0, speed = 1, playing = false, started = false }
	end
	for key, cue in SoundBank.Loops :: any do
		resolve(key, cue, true)
		buildLoop(key)
	end
	for name, cue in SoundBank.Cues :: any do
		resolve(name, cue, false)
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
	buildToggle()
	applySettings()
	connectEvents()
	if RunService:IsStudio() then
		task.delay(15, function()
			if #missing > 0 then
				table.sort(missing)
				warn("[Sound] No playable audio for: " .. table.concat(missing, ", ") .. " - put another Creator Store audio id first in SoundBank.")
			end
		end)
	end
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
			local v = l.sound
			if not v then
				continue
			end
			v.Volume = l.cue.volume * l.current
			v.PlaybackSpeed = l.speed
			if l.current > 0.003 and not l.playing then
				if l.started then
					v:Resume()
				else
					v:Play()
					l.started = true
				end
				l.playing = true
			elseif l.target == 0 and l.current <= 0.003 and l.playing then
				v:Pause()
				l.playing = false
			end
		end
	end)
end

return SoundController
