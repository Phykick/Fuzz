--!strict
-- AudioManager: the one place the game plays sound (client side).
--
-- Every sound is a cue in ReplicatedStorage.Audio.AudioConfig, played from a clone of its Sound in
-- the ReplicatedStorage.Audio library (AudioLibrary). The manager:
--   * checks every asset actually loads and settles each cue on the first listed id that does.
--     Failures are recorded in AudioConfig.Failed and reported in Studio; they are never replaced
--     with some other sound, the cue just goes quiet.
--   * throttles: per-cue cooldowns, small voice pools, a cap on voices at once (expendable sounds
--     give way), one UI sound per moment (the most important wins), a budget for footsteps.
--   * plays world sounds in 3D where they happen (rooms, survivors, doors, the elevator car). The
--     listener hovers in front of what the camera looks at, closer when zoomed in, so what you look
--     at is what you hear. UI and notifications are 2D.
--   * layers ambience from the game state: the vault's air (always), generator and purifier
--     machinery at the nearest visible rooms, occasional details from staffed rooms, rare distant
--     machinery, rare quiet music between emergencies.
--   * runs one alarm layer for every emergency (fire, power failure, water failure, raid,
--     explosion, infestation): a burst when something new goes wrong, sparse reminders while it
--     lasts, silence when it's over. It never loops for the whole emergency and never stacks.
--   * reacts to power failure and restoration, machines starting and stopping, construction,
--     doors, the elevator, footsteps, survivor activities, resources, rewards and story moments.
--   * has volume sliders (Master, Music, SFX, Ambient, UI) saved with the shelter.
-- Other controllers call it through C.AudioManager (e.g. C.AudioManager:Footstep(...)).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")

local AudioFolder = ReplicatedStorage:WaitForChild("Audio")
local AudioConfig = require(AudioFolder:WaitForChild("AudioConfig"))
local AudioLibrary = require(AudioFolder:WaitForChild("AudioLibrary"))

local Ui = script.Parent.Parent:WaitForChild("Ui")
local Kit = require(Ui.Kit)

local AudioManager = {}
local C: any

type Asset = AudioConfig.Asset
export type PlayOpts = {
	at: Vector3?, -- play here in 3D (3D cues only; without it a cue plays 2D)
	gain: number?, -- volume multiplier
	pitch: number?, -- PlaybackSpeed multiplier
	cut: number?, -- override the cue's cut
	force: boolean?, -- ignore the cue's cooldown
}

local Sounds = AudioConfig.Sounds
local Loops = AudioConfig.Loops
local MAX_VOICES = 14 -- one-shots playing at once; mobile-friendly
local UI_WINDOW = 0.08 -- UI sounds closer together than this don't stack
local FADE = 0.15 -- fade when a clip is cut short
local SAVE_DELAY = 1.5 -- seconds of slider quiet before the volumes are saved
local MACHINES = { Power = true, Water = true, Workshop = true, Infirmary = true, Food = true }
local COLLECT = { Food = "CollectFood", Water = "CollectWater", Materials = "CollectMaterials", Medicine = "CollectMedicine" }

local groups: { [string]: SoundGroup } = {}
local volumes: { [string]: number } = { Master = 1, Music = 1, SFX = 1, Ambient = 1, UI = 1 }
local twoD: Folder -- 2D voices live here
local emitter: BasePart -- 3D voices hang off attachments on this invisible part at the origin
local listener = Vector3.new(0, 0, 40)

local function rand(a: number, b: number): number
	return a + (b - a) * math.random()
end

local function cueOf(name: string): any
	return Sounds[name] or Loops[name]
end

-- Loading checks ---------------------------------------------------------------------------------
local status: { [number]: string } = {} -- asset id -> "ok" | "failed" | "checking"
local chosen: { [string]: Asset? } = {} -- cue -> the asset it plays
local missing: { [string]: boolean } = {} -- cues with nothing playable
local checked = false
local onSourceChanged: (name: string) -> ()

local function loads(a: Asset): (boolean, string)
	local probe = Instance.new("Sound")
	probe.SoundId = AudioConfig.contentId(a)
	local result: any = nil
	local called = pcall(function()
		ContentProvider:PreloadAsync({ probe }, function(_, fetch)
			result = fetch
		end)
	end)
	probe:Destroy()
	if not called then
		return false, "error"
	end
	return result == Enum.AssetFetchStatus.Success, tostring(result)
end

local function check(a: Asset, cueName: string): boolean
	while status[a.id] == "checking" do
		task.wait(0.1)
	end
	local s = status[a.id]
	if s then
		return s == "ok"
	end
	status[a.id] = "checking"
	local ok, why = loads(a)
	status[a.id] = if ok then "ok" else "failed"
	if not ok then
		AudioConfig.Failed[a.id] = { cue = cueName, status = why, title = a.title, source = a.source }
	end
	return ok
end

-- Settle a cue on the first listed id that loads (alternates are only fetched if needed, except
-- for cues that pick randomly between all of theirs).
local function resolve(name: string)
	local cue = cueOf(name)
	local found: Asset? = nil
	for _, a in cue.ids do
		if check(a, name) then
			found = found or a
			if cue.pick ~= "random" then
				break
			end
		end
	end
	missing[name] = if found then nil else true
	if chosen[name] ~= found then
		chosen[name] = found
		onSourceChanged(name)
	end
end

local function pickAsset(name: string, cue: any): Asset?
	if cue.pick == "random" and #cue.ids > 1 then
		local pool = {}
		for _, a in cue.ids do
			if status[a.id] ~= "failed" then
				table.insert(pool, a)
			end
		end
		return if #pool > 0 then pool[math.random(1, #pool)] else nil
	end
	return chosen[name]
end

function AudioManager:Report(): any
	local seen, ok, failed, unchecked = {}, 0, {}, 0
	local function scan(name: string, cue: any)
		for _, a in cue.ids do
			if not seen[a.id] then
				seen[a.id] = true
				local s = status[a.id]
				if s == "ok" then
					ok += 1
				elseif s == "failed" then
					local f = AudioConfig.Failed[a.id]
					table.insert(failed, string.format('%d "%s" (%s, %s)', a.id, a.title, f and f.cue or name, f and f.status or "?"))
				else
					unchecked += 1 -- an alternate that was never needed
				end
			end
		end
	end
	for name, cue in Sounds do
		scan(name, cue)
	end
	for name, cue in Loops do
		scan(name, cue)
	end
	table.sort(failed)
	local quiet = {}
	for name in missing do
		table.insert(quiet, name)
	end
	table.sort(quiet)
	return { done = checked, ok = ok, failed = failed, unchecked = unchecked, missing = quiet }
end

local function printReport()
	local r = AudioManager:Report()
	if #r.failed == 0 then
		print(string.format("[Audio] %d sound assets checked; all of them load.", r.ok))
	else
		warn(string.format("[Audio] %d of %d sound assets failed to load (recorded in AudioConfig.Failed):\n  %s",
			#r.failed, r.ok + #r.failed, table.concat(r.failed, "\n  ")))
	end
	if #r.missing > 0 then
		warn("[Audio] No playable sound for: " .. table.concat(r.missing, ", ") .. ". These stay silent until another id is listed in AudioConfig.")
	end
end

local function verifyAll()
	local order = {}
	for name, cue in Sounds do
		table.insert(order, { name, if cue.group == "UI" then 0 else 2 })
	end
	for name in Loops do
		table.insert(order, { name, 1 })
	end
	table.sort(order, function(a, b)
		if a[2] ~= b[2] then
			return a[2] < b[2]
		end
		return a[1] < b[1]
	end)
	for _, e in order do
		resolve(e[1])
	end
	checked = true
	if RunService:IsStudio() then
		printReport()
	end
end

-- Volumes ------------------------------------------------------------------------------------------
local function audible(group: string): boolean
	return volumes.Master > 0 and (volumes[group] or 1) > 0
end

local function applyVolumes()
	for name, base in AudioConfig.Groups do
		local g = groups[name]
		if g then
			g.Volume = if name == "Master" then volumes.Master else base * (volumes[name] or 1) * volumes.Master
		end
	end
end

-- Voices -------------------------------------------------------------------------------------------
type Voice = { sound: Sound, att: Attachment?, token: number, started: number, priority: number }
local pools: { [string]: { Voice } } = {}
local active: { [Voice]: boolean } = {}
local tokenSeq = 0
local lastPlayed: { [string]: number } = {}
local lastUI: { t: number, priority: number, voice: Voice }? = nil
local warned: { [string]: boolean } = {}

local function newSound(name: string): Sound
	local t = AudioLibrary.template(name)
	if t then
		return t:Clone()
	end
	-- the library hasn't arrived yet: build the same thing from the config
	local cue = cueOf(name)
	local s = Instance.new("Sound")
	s.Name = name
	s.Volume = cue.volume
	s.PlaybackSpeed = cue.speed or 1
	s.SoundGroup = groups[cue.group]
	if cue.space == "3D" then
		local r = AudioConfig.RollOff[cue.rolloff or "Room"]
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = r[1]
		s.RollOffMaxDistance = r[2]
	end
	return s
end

local function countPlaying(): number
	local n = 0
	for v in active do
		if v.sound.IsPlaying then
			n += 1
		else
			active[v] = nil
		end
	end
	return n
end

local function fadeOut(v: Voice, token: number, seconds: number?)
	local s = v.sound
	local v0 = s.Volume
	for i = 1, 5 do
		task.wait((seconds or FADE) / 5)
		if v.token ~= token then
			return
		end
		s.Volume = v0 * (1 - i / 5)
	end
	if v.token == token then
		s:Stop()
		active[v] = nil
	end
end

local function stopVoice(v: Voice, fade: number?)
	if fade then
		task.spawn(fadeOut, v, v.token, fade)
	else
		tokenSeq += 1
		v.token = tokenSeq
		v.sound:Stop()
		active[v] = nil
	end
end

local function voiceFor(name: string, cue: any, spatial: boolean): Voice
	local key = if spatial then name .. "@3D" else name
	local pool = pools[key]
	if not pool then
		pool = {}
		pools[key] = pool
	end
	for _, v in pool do
		if not v.sound.IsPlaying then
			return v
		end
	end
	if #pool < (cue.voices or 2) then
		local s = newSound(name)
		local v: Voice = { sound = s, att = nil, token = 0, started = 0, priority = cue.priority or 1 }
		if spatial then
			local att = Instance.new("Attachment")
			att.Name = name
			att.Parent = emitter
			s.Parent = att
			v.att = att
		else
			s.Parent = twoD
		end
		table.insert(pool, v)
		return v
	end
	local oldest = pool[1]
	for _, v in pool do
		if v.started < oldest.started then
			oldest = v
		end
	end
	return oldest
end

local function play(name: string, opts: PlayOpts?): Sound?
	local cue = Sounds[name]
	if not cue then
		if not warned[name] and RunService:IsStudio() then
			warned[name] = true
			warn("[Audio] Unknown sound cue: " .. tostring(name))
		end
		return nil
	end
	local o: PlayOpts = opts or {}
	if not audible(cue.group) then
		return nil
	end
	local now = os.clock()
	if not o.force and now - (lastPlayed[name] or -1e9) < (cue.cooldown or 0.03) then
		return nil
	end
	local prio = cue.priority or 1
	local ui = lastUI
	if cue.group == "UI" and ui and now - ui.t < UI_WINDOW then
		if prio <= ui.priority then
			return nil
		end
		stopVoice(ui.voice)
	end
	if countPlaying() >= MAX_VOICES then
		if prio <= 0 then
			return nil
		end
		local victim: Voice? = nil
		for v in active do
			if v.priority <= prio and (victim == nil or v.priority < victim.priority or (v.priority == victim.priority and v.started < victim.started)) then
				victim = v
			end
		end
		if not victim then
			return nil
		end
		stopVoice(victim)
	end
	local a = pickAsset(name, cue)
	if not a then
		return nil
	end
	lastPlayed[name] = now
	local v = voiceFor(name, cue, o.at ~= nil and cue.space == "3D")
	local s = v.sound
	s:Stop()
	tokenSeq += 1
	v.token = tokenSeq
	v.started = now
	v.priority = prio
	local att = v.att
	if att and o.at then
		att.Position = o.at
	end
	local id = AudioConfig.contentId(a)
	if s.SoundId ~= id then
		s.SoundId = id
	end
	local g = groups[cue.group]
	if g then
		s.SoundGroup = g -- (voices made before the library arrived have none yet)
	end
	local vary, pitch = cue.vary or 0, cue.pitch or 0
	s.Volume = cue.volume * (o.gain or 1) * (1 + (math.random() * 2 - 1) * vary)
	s.PlaybackSpeed = (cue.speed or 1) * (o.pitch or 1) * (1 + (math.random() * 2 - 1) * pitch)
	s.TimePosition = cue.start or 0
	s:Play()
	active[v] = true
	local cut = o.cut or cue.cut
	if cut then
		task.delay(cut, fadeOut, v, v.token)
	end
	if cue.group == "UI" then
		lastUI = { t = now, priority = prio, voice = v }
	end
	return s
end

-- Fade out every voice of a cue (e.g. music when an emergency starts).
local function stopCue(name: string, fade: number?)
	for key, pool in pools do
		if key == name or key == name .. "@3D" then
			for _, v in pool do
				if v.sound.IsPlaying then
					stopVoice(v, fade)
				end
			end
		end
	end
end

function AudioManager:Play(name: string, opts: PlayOpts?): Sound?
	return play(name, opts)
end

function AudioManager:PlayAt(name: string, position: Vector3, opts: PlayOpts?): Sound?
	local o: any = if opts then table.clone(opts) else {}
	o.at = position
	return play(name, o)
end

function AudioManager:Stop(name: string)
	stopCue(name, FADE)
end

-- Beds (continuous layers) ---------------------------------------------------------------------
type Slot = { sound: Sound?, att: Attachment?, key: string?, target: number, current: number, speed: number, playing: boolean, started: boolean }
type Bed = { name: string, cue: any, slots: { Slot } }
local beds: { [string]: Bed } = {}

local function bedSound(bed: Bed, slot: Slot)
	if slot.sound then
		slot.sound:Destroy()
		slot.sound = nil
	end
	slot.playing, slot.started = false, false
	local a = chosen[bed.name]
	if not a then
		return
	end
	local s = newSound(bed.name)
	s.SoundId = AudioConfig.contentId(a)
	s.Looped = true
	s.Volume = 0
	s.Parent = slot.att or twoD
	slot.sound = s
end

local function makeBed(name: string, cue: any)
	local spatial = cue.space == "3D"
	local bed: Bed = { name = name, cue = cue, slots = {} }
	for i = 1, (if spatial then cue.emitters or 1 else 1) do
		local slot: Slot = { sound = nil, att = nil, key = nil, target = 0, current = 0, speed = 1, playing = false, started = false }
		if spatial then
			local att = Instance.new("Attachment")
			att.Name = name .. i
			att.Parent = emitter
			slot.att = att
		end
		bedSound(bed, slot)
		table.insert(bed.slots, slot)
	end
	beds[name] = bed
end

-- wants: { { key = roomId, pos = Vector3?, gain = 0..1, speed = number? } }, most important first.
-- Rooms keep their slot while wanted; a new room takes a silent (or the quietest) slot and fades in.
local function setBed(name: string, wants: { any })
	local bed = beds[name]
	if not bed then
		return
	end
	local taken: { [Slot]: boolean } = {}
	for _, w in wants do
		for _, slot in bed.slots do
			if slot.key == w.key and not taken[slot] then
				w.slot = slot
				taken[slot] = true
				break
			end
		end
	end
	for _, w in wants do
		if not w.slot then
			local best: Slot? = nil
			for _, slot in bed.slots do
				if not taken[slot] and (best == nil or slot.current < best.current) then
					best = slot
				end
			end
			if best then
				taken[best] = true
				w.slot = best
				best.key = w.key
				best.current = 0
			end
		end
		local slot: Slot? = w.slot
		if slot then
			if slot.att and w.pos then
				slot.att.Position = w.pos
			end
			slot.target = w.gain
			slot.speed = w.speed or 1
		end
	end
	for _, slot in bed.slots do
		if not taken[slot] then
			slot.target = 0
		end
	end
end

local function stepBeds(dt: number)
	local k = math.min(1, dt * 2.5)
	for _, bed in beds do
		for _, slot in bed.slots do
			slot.current += (slot.target - slot.current) * k
			local s = slot.sound
			if not s then
				continue
			end
			s.Volume = bed.cue.volume * slot.current
			s.PlaybackSpeed = slot.speed
			if slot.current > 0.003 and not slot.playing then
				if slot.started then
					s:Resume()
				else
					s:Play()
					slot.started = true
				end
				slot.playing = true
			elseif slot.target == 0 and slot.current <= 0.003 and slot.playing then
				s:Pause()
				slot.playing = false
				slot.key = nil
			end
		end
	end
end

-- Alarm: one voice for every emergency ----------------------------------------------------------
local alarm = { sound = nil :: Sound?, playing = false, current = 0, level = 0, untilT = 0, nextReminder = math.huge, step = 0, lastOnset = -1e9 }
local emergencies: { [string]: boolean } = {}
local manual: { [string]: boolean } = {} -- AudioManager:Emergency(kind, true)
local momentary: { [string]: number } = {} -- kind -> until (explosions)

local function burst(seconds: number, level: number)
	local a = chosen.Alarm
	if not a or not audible("SFX") then
		return
	end
	local s = alarm.sound
	if not s then
		local n = newSound("Alarm")
		n.Looped = true -- short alarm clips repeat within a burst
		n.Volume = 0
		n.Parent = twoD
		alarm.sound = n
		s = n
	end
	local snd = s :: Sound
	local id = AudioConfig.contentId(a)
	if snd.SoundId ~= id then
		snd.SoundId = id
	end
	alarm.level = level
	alarm.untilT = os.clock() + seconds
	if not alarm.playing then
		snd.TimePosition = 0
		snd:Play()
		alarm.playing = true
	end
end

local function stepAlarm(dt: number)
	local s = alarm.sound
	if not s or not alarm.playing then
		return
	end
	local target = if os.clock() < alarm.untilT then alarm.level else 0
	local rate = if target > alarm.current then 12 else 4 -- quick in, slower out
	alarm.current += (target - alarm.current) * math.min(1, dt * rate)
	s.Volume = alarm.current
	if target == 0 and alarm.current < 0.004 then
		s:Stop()
		alarm.playing = false
		alarm.current = 0
	end
end

local function setEmergencies(kinds: { [string]: boolean })
	local now = os.clock()
	for k, t in momentary do
		if now < t then
			kinds[k] = true
		else
			momentary[k] = nil
		end
	end
	for k in manual do
		kinds[k] = true
	end
	local any, fresh = false, false
	for k in kinds do
		any = true
		if not emergencies[k] then
			fresh = true
		end
	end
	emergencies = kinds
	local E = AudioConfig.Emergency
	if fresh and now - alarm.lastOnset > 4 then
		alarm.lastOnset = now
		burst(E.onsetBurst, E.volume)
		alarm.step = 1
		alarm.nextReminder = now + E.onsetBurst + E.reminders[1]
		stopCue("AmbientMusic", 1.5)
	elseif fresh then
		-- another emergency right on top of the last: keep the same burst going a little longer
		burst(math.max(1.5, alarm.untilT - now), E.volume)
	elseif any and now >= alarm.nextReminder then
		burst(E.reminderBurst, E.reminderVolume)
		alarm.step = math.min(alarm.step + 1, #E.reminders)
		alarm.nextReminder = now + E.reminderBurst + E.reminders[alarm.step]
	elseif not any then
		alarm.nextReminder = math.huge
		alarm.untilT = math.min(alarm.untilT, now) -- all clear: fade now
	end
end

-- Hook for systems without their own state here (e.g. future structural damage):
-- AudioManager:Emergency("CriticalDamage", true) ... AudioManager:Emergency("CriticalDamage", false)
function AudioManager:Emergency(kind: string, on: boolean?)
	if kind == "Explosion" then
		momentary.Explosion = os.clock() + 6
	else
		manual[kind] = if on == false then nil else true
	end
end

-- World: power, machines, ambience, emergencies (4x a second) ---------------------------------
local power = { failed = false, since = 0, want = false, wantSince = 0 }
local simulated: { powerFail: boolean? } = { powerFail = nil } -- debug panel override
local running: { [string]: boolean } = {}
local centers: { [string]: Vector3 } = {}
local nextDetail: { [string]: number } = {}
local detailGate = 0
local nextBrownout, nextZap, nextFight, nextDoorHit, nextSqueak = 0, 0, 0, 0, 0
local nextDistant, nextMusic = math.huge, math.huge
local primed = false

local function updatePower(pf: number, now: number)
	local E = AudioConfig.Emergency
	local want = if simulated.powerFail ~= nil then simulated.powerFail
		elseif power.failed then pf < E.powerBackAbove
		else pf < E.powerFailBelow
	if not primed then
		power.failed, power.want, power.since = want, want, now
		return
	end
	if want ~= power.want then
		power.want = want
		power.wantSince = now
	end
	local settle = if simulated.powerFail ~= nil then 0 else 1.5
	if want ~= power.failed and now - power.wantSince >= settle then
		power.failed = want
		if want then
			power.since = now
			play("PowerFailure")
		else
			play("PowerRestored")
			if now - power.since > 5 then
				task.delay(1, play, "Achievement", { gain = 0.6 })
			end
		end
	end
end

-- Generators and purifiers announce starting and stopping.
local function machine(id: string, r: any, pf: number, at: Vector3): boolean
	if r.type ~= "Power" and r.type ~= "Water" then
		return false
	end
	local workers = if type(r.assigned) == "table" then #r.assigned else 0
	local on = r.incident == nil and workers > 0 and (r.type == "Power" or pf > 0.25)
	local before = running[id]
	running[id] = on
	if before == nil or before == on or not primed then
		return on
	end
	if on then
		play(if r.type == "Power" then "GeneratorStart" else "PurifierStart", { at = at })
	elseif r.type == "Water" then
		play("WaterFailure", { at = at }) -- the pumps wind down
	end
	return on
end

local function spotIn(id: string): Vector3?
	local minX, maxX, floorY = C.VaultRenderer.roomBounds(id)
	if minX then
		return Vector3.new(minX + (maxX - minX) * rand(0.2, 0.8), floorY + 1.5, 0)
	end
	return centers[id]
end

local function roomActivity(id: string, r: any, pf: number, now: number)
	local cfg = AudioConfig.RoomActivity[r.type]
	if not cfg or #cfg.sounds == 0 or r.incident then
		return
	end
	local workers = if type(r.assigned) == "table" then #r.assigned else 0
	if workers == 0 or (r.type ~= "Power" and pf < 0.3) then
		return
	end
	local t = nextDetail[id]
	if not t then
		nextDetail[id] = now + rand(cfg.every[1], cfg.every[2]) * 0.5
		return
	end
	if now < t or now < detailGate then
		return
	end
	nextDetail[id] = now + rand(cfg.every[1], cfg.every[2]) / (1 + 0.15 * math.min(workers, 6))
	detailGate = now + 2.5
	local at = spotIn(id)
	if at then
		play(cfg.sounds[math.random(1, #cfg.sounds)], { at = at })
	end
end

local function nearest(list: { any }, n: number): { any }
	table.sort(list, function(a, b)
		return a.d2 < b.d2
	end)
	local out = {}
	for i = 1, math.min(n, #list) do
		out[i] = list[i]
	end
	return out
end

local function pickOne(list: { any }): any
	return list[math.random(1, #list)]
end

local function updateWorld()
	local state = C.StateStore.state
	if not state.ready then
		return
	end
	local now = os.clock()
	local CC = C.CameraController
	local x0, x1, y0, y1 = CC.visibleRect(8)
	local view = CC.viewHeight()
	local pf = math.min(1, state.powerFactor or 1)
	local outside = C.WastelandController ~= nil and C.WastelandController.active == true
	updatePower(pf, now)
	local kinds: { [string]: boolean } = {}
	local gens, waters, fires, critters, starved, sparks, burning = {}, {}, {}, {}, {}, {}, {}
	local entrance: Vector3? = nil
	local far: { Vector3 } = {} -- rooms out of view, for distant sounds
	for id, r in state.rooms do
		local c = C.VaultRenderer.roomCenter(id) or centers[id]
		if not c then
			continue
		end
		centers[id] = c
		local seen = c.X > x0 and c.X < x1 and c.Y > y0 and c.Y < y1
		if not seen then
			table.insert(far, c)
		end
		local d2 = (c.X - listener.X) ^ 2 + (c.Y - listener.Y) ^ 2
		local inc = r.incident
		if r.type == "Entrance" then
			entrance = c
		end
		if inc then
			if inc.kind == "Fire" then
				kinds.Fire = true
				local frac = if (inc.maxHp or 0) > 0 then math.clamp(inc.hp / inc.maxHp, 0, 1) else 1
				table.insert(fires, { key = id, pos = c, gain = 0.55 + 0.45 * frac, d2 = d2 })
				if seen then
					table.insert(burning, id)
					if MACHINES[r.type] then
						table.insert(sparks, c) -- machinery shorting in the flames
					end
				end
			elseif inc.kind == "Breakdown" then
				if r.type == "Power" then
					kinds.PowerFailure = true
					if seen then
						table.insert(sparks, c) -- a damaged generator keeps sparking
					end
				elseif r.type == "Water" then
					kinds.WaterFailure = true
				end
			else
				kinds.Infestation = true
				table.insert(critters, c)
			end
		end
		local on = machine(id, r, pf, c)
		if on and seen and not outside then
			table.insert(if r.type == "Power" then gens else waters, { key = id, pos = c, d2 = d2 })
		end
		if seen and not outside then
			if pf < 0.97 and r.type ~= "Power" and r.type ~= "Elevator" and r.type ~= "Entrance" then
				table.insert(starved, c)
			end
			if view < 80 and primed then
				roomActivity(id, r, pf, now)
			end
		end
	end
	if state.raid then
		kinds.Raid = true
	end
	if power.failed then
		kinds.PowerFailure = true
	end
	local water = state.resources and state.resources.Water
	if type(water) == "number" and water <= 0 and next(state.dwellers) ~= nil then
		kinds.WaterFailure = true -- the tanks are dry
	end
	setEmergencies(kinds)
	local calm = next(emergencies) == nil

	-- beds
	local failing = power.failed
	local g = nearest(gens, 2)
	for _, w in g do
		w.gain = if failing then 0.4 else 1
	end
	setBed("GeneratorHum", g)
	local wl = nearest(waters, 2)
	for _, w in wl do
		w.gain = (0.4 + 0.6 * pf) * (if failing then 0.5 else 1)
		w.speed = 0.85 + 0.15 * pf -- pumps labour in a brownout
	end
	setBed("WaterFlow", wl)
	setBed("FireCrackle", nearest(fires, 2))
	local air = (if failing then 0.55 else 1) * (if alarm.playing then 0.75 else 1) * (if CC.zoomAlpha() > 0.75 then 0.85 else 1) * (if outside then 0.3 else 1)
	setBed("VaultAir", { { key = "air", gain = air } })

	if not primed then
		primed = true
		nextDistant = now + rand(AudioConfig.Distant.every[1], AudioConfig.Distant.every[2])
		nextMusic = now + AudioConfig.Music.firstAfter
		return
	end
	if outside then
		return
	end
	-- occasional details, most urgent first; never more than a couple at once
	if #starved > 0 and pf < 0.97 and now >= nextBrownout then
		nextBrownout = now + rand(10, 25) / (1 + (1 - pf) * 2)
		play(if pf < 0.6 then "ElectricalZap" else "ElectricalTick", { at = pickOne(starved), gain = 1.3 })
	end
	if #sparks > 0 and now >= nextZap then
		nextZap = now + rand(5, 12)
		play("ElectricalZap", { at = pickOne(sparks) })
	end
	if #burning > 0 and now >= nextFight then
		-- survivors fighting the fire: water hitting the flames
		local present = {}
		for _, d in state.dwellers do
			local tr = d.travel
			if d.status ~= "Dead" and not (tr and workspace:GetServerTimeNow() < tr.start + tr.duration) then
				present[d.at or d.roomId or ""] = true
			end
		end
		local fighting = {}
		for _, id in burning do
			if present[id] then
				table.insert(fighting, id)
			end
		end
		if #fighting > 0 then
			nextFight = now + rand(1.5, 3)
			local at = spotIn(pickOne(fighting))
			if at then
				play("FireFight", { at = at })
			end
		end
	end
	local raid = state.raid
	if raid and raid.phase == "door" and entrance and now >= nextDoorHit then
		nextDoorHit = now + rand(1.4, 2.2) -- raiders hammering on the blast door
		play("RaidDoorHit", { at = entrance })
	end
	if #critters > 0 and now >= nextSqueak then
		nextSqueak = now + rand(2, 4.5)
		play("CreatureSqueak", { at = pickOne(critters), gain = 0.8 })
	end
	if calm and #far > 0 and now >= nextDistant then
		local D = AudioConfig.Distant
		nextDistant = now + rand(D.every[1], D.every[2])
		play(pickOne(D.sounds), { at = pickOne(far), gain = 0.7 })
	end
	if calm and now >= nextMusic then
		local M = AudioConfig.Music
		nextMusic = now + rand(M.gap[1], M.gap[2])
		play(pickOne(M.tracks))
	end
end

-- Listener: hovers in front of the camera's focus, closer when zoomed in -----------------------
local function updateListener()
	local x0, x1, y0, y1 = C.CameraController.visibleRect(0)
	local view = C.CameraController.viewHeight()
	local x, y, z = (x0 + x1) / 2, (y0 + y1) / 2, math.clamp(view * 0.4, 6, 60)
	if math.abs(x - listener.X) + math.abs(y - listener.Y) + math.abs(z - listener.Z) < 0.05 then
		return
	end
	listener = Vector3.new(x, y, z)
	SoundService:SetListener(Enum.ListenerType.CFrame, CFrame.new(x, y, z))
end

-- The point on the vault plane the listener is in front of (debug tools play things here).
function AudioManager:Focus(): Vector3
	return Vector3.new(listener.X, listener.Y, 0)
end

local function nearCentre(pos: Vector3, maxView: number): boolean
	local view = C.CameraController.viewHeight()
	if view > maxView then
		return false
	end
	local r = view * AudioConfig.Footsteps.radius
	return (pos.X - listener.X) ^ 2 + (pos.Y - listener.Y) ^ 2 <= r * r
end

-- Survivors ------------------------------------------------------------------------------------------
local stepTokens, stepAt = 0, 0

-- A foot lands (called from the walk/run animation). Zoomed in and near the middle of the screen
-- only, within a budget across all survivors; `important` (the selected survivor) skips the
-- distance check but not the budget.
function AudioManager:Footstep(pos: Vector3, running: boolean?, roomType: string?, important: boolean?)
	local F = AudioConfig.Footsteps
	local view = C.CameraController.viewHeight()
	if view > F.maxView then
		return
	end
	if not important and not nearCentre(pos, F.maxView) then
		return
	end
	local now = os.clock()
	stepTokens = math.min(F.perSecond * 0.5, stepTokens + (now - stepAt) * F.perSecond)
	stepAt = now
	if stepTokens < 1 then
		return
	end
	stepTokens -= 1
	local surface = F.roomSurface[roomType or ""] or "Concrete"
	play(F.surfaces[surface] or F.surfaces.Concrete, { at = pos, gain = if running then 1.2 else 1, pitch = if running then 1.05 else 1, force = true })
end

-- A survivor starts an activity at a station (repairing, drinking, farming...).
local heardAt: { [string]: number } = {}
local interactGate = 0
function AudioManager:Interaction(action: string, pos: Vector3, who: string?)
	local cue = AudioConfig.Interactions[action]
	if not cue or not primed or not nearCentre(pos, AudioConfig.Footsteps.maxView) then
		return
	end
	local now = os.clock()
	local key = who or action
	if now < interactGate or now - (heardAt[key] or -1e9) < 12 then
		return
	end
	heardAt[key] = now
	interactGate = now + 1.5 -- one survivor at a time
	play(cue, { at = pos, gain = 0.8 })
end

-- Survivor voices (talking, laughing, crying...): AudioConfig.Voice[kind] lists cues; none yet.
function AudioManager:Voice(kind: string, pos: Vector3?)
	local list = AudioConfig.Voice[kind]
	if list and #list > 0 then
		play(pickOne(list), { at = pos })
	end
end

-- Doors: a door that is toggled again within a moment (interrupted animation) stays quiet.
local doorAt: { [string]: number } = {}
function AudioManager:Door(key: string, opening: boolean, pos: Vector3?, kind: string?)
	local now = os.clock()
	if now - (doorAt[key] or -1e9) < 1.2 then
		return
	end
	doorAt[key] = now
	local cue = if kind == "heavy" then "DoorHeavy" elseif kind == "old" then "DoorOld" elseif opening then "DoorOpen" else "DoorClose"
	play(cue, { at = pos, pitch = if kind == "heavy" and not opening then 0.85 else 1, force = true })
end

-- Elevator car: "depart" when it starts moving, "move" while it does, "arrive" when it stops.
-- Survivors ride all the time, so only cars on screen, zoomed in, and not too often.
local cars: { [string]: any } = {}
local nextRide = 0
function AudioManager:Elevator(event: string, pos: Vector3, key: string)
	local e = cars[key]
	if not e then
		e = { depart = -1e9, arrive = -1e9, motor = nil }
		cars[key] = e
	end
	if event == "move" then
		local m = e.motor
		local att = m and m.Parent
		if att and att:IsA("Attachment") then
			att.Position = pos
		end
		return
	end
	if C.CameraController.viewHeight() > 70 then
		return
	end
	local x0, x1, y0, y1 = C.CameraController.visibleRect(6)
	if pos.X < x0 or pos.X > x1 or pos.Y < y0 or pos.Y > y1 then
		return
	end
	local now = os.clock()
	if event == "depart" then
		if now - e.depart < 8 or now < nextRide then
			return
		end
		e.depart = now
		nextRide = now + 4
		play("ElevatorButton", { at = pos })
		task.delay(0.15, play, "ElevatorDoorClose", { at = pos })
		task.delay(0.45, function()
			e.motor = play("ElevatorMotor", { at = pos })
		end)
	elseif event == "arrive" then
		if now - e.depart > 30 or now - e.arrive < 3 then
			return
		end
		e.arrive = now
		local m = e.motor
		if m and m.IsPlaying then
			for _, pool in pools do
				for _, v in pool do
					if v.sound == m then
						stopVoice(v, 0.3)
					end
				end
			end
		end
		e.motor = nil
		play("ElevatorArrive", { at = pos })
		task.delay(0.25, play, "ElevatorDoorOpen", { at = pos })
	end
end

-- Wasteland encounters (exploration view).
function AudioManager:Encounter(kind: string, pos: Vector3?)
	if kind == "Bunker" then
		play("DoorOld", { at = pos })
		task.delay(1, play, "Discovery")
	elseif kind == "AbandonedHouse" then
		if math.random() < 0.5 then
			play("DoorOld", { at = pos })
		end
	elseif kind == "RuinedLab" then
		play("ElectricalZap", { at = pos })
		if math.random() < 0.35 then
			task.delay(0.8, play, "Discovery")
		end
	elseif kind == "Mutant" then
		play("CreatureSqueak", { at = pos, pitch = 0.8 })
	elseif kind == "Trader" then
		play("Currency")
	end
end

-- A weapon fires (or a punch lands).
function AudioManager:Shot(weapon: string?, pos: Vector3?)
	if weapon == "Fists" then
		play("Punch", { at = pos })
		return
	end
	local w = weapon and AudioConfig.Weapons[weapon]
	play(if w then w.cue else "Gunshot", { at = pos, pitch = if w then w.speed else 1 })
end

-- Debug: "PowerFailure" true/false forces the power state, nil follows the game again;
-- "Emergency" true/false holds a test emergency.
function AudioManager:Simulate(what: string, on: boolean?)
	if what == "PowerFailure" then
		simulated.powerFail = on
	elseif what == "Emergency" then
		manual.Debug = if on then true else nil
	end
end

function AudioManager:Stats(): any
	local kinds = {}
	for k in emergencies do
		table.insert(kinds, k)
	end
	table.sort(kinds)
	return { voices = countPlaying(), maxVoices = MAX_VOICES, emergencies = kinds, powerFailed = power.failed, alarm = alarm.playing, checked = checked }
end

-- Volume panel ---------------------------------------------------------------------------------------
local panelButton: ImageButton? = nil
local panel: ImageLabel? = nil
local valueLabels: { [string]: TextLabel } = {}
local saveToken = 0
local unsaved = false

local function pct(v: number): string
	return tostring(math.floor(v * 100 + 0.5)) .. "%"
end

local function refreshPanel()
	local b = panelButton
	if not b then
		return
	end
	Kit.setButtonText(b, if volumes.Master > 0 then "SOUND" else "MUTED")
	for k, l in valueLabels do
		l.Text = pct(volumes[k])
	end
end

function AudioManager:GetVolume(name: string): number
	return volumes[name] or 1
end

function AudioManager:SetVolume(name: string, value: number, noSave: boolean?)
	if volumes[name] == nil or value ~= value then
		return
	end
	volumes[name] = math.floor(math.clamp(value, 0, 1) * 20 + 0.5) / 20
	applyVolumes()
	refreshPanel()
	if noSave then
		return
	end
	unsaved = true
	saveToken += 1
	local mine = saveToken
	task.delay(SAVE_DELAY, function()
		if mine == saveToken then
			unsaved = false
			C.StateStore.action("Settings", { volumes = table.clone(volumes) }, true)
		end
	end)
end

local function readSettings(st: any)
	if type(st) ~= "table" or unsaved then
		return
	end
	local v = st.volumes
	if type(v) == "table" and next(v) ~= nil then
		for _, k in AudioConfig.PlayerVolumes do
			if type(v[k]) == "number" then
				volumes[k] = math.clamp(v[k], 0, 1)
			end
		end
	else
		-- older saves had two on/off switches
		if st.sfx == false then
			volumes.SFX, volumes.UI = 0, 0
		end
		if st.music == false then
			volumes.Ambient, volumes.Music = 0, 0
		end
	end
	applyVolumes()
	refreshPanel()
end

local function buildPanel()
	local gui = Kit.screen("AudioUI", 7)
	local box: ImageLabel
	panelButton = Kit.button({
		Text = "SOUND", Size = UDim2.fromOffset(112, 46), TextSize = 17, AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -16), Parent = gui, Name = "SoundToggle",
		OnClick = function()
			box.Visible = not box.Visible
			if box.Visible then
				Kit.pop(box)
			end
		end,
	})
	local n = #AudioConfig.PlayerVolumes
	box = Kit.panel({ Size = UDim2.fromOffset(330, 24 + n * 52), AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -70), Parent = gui, Name = "VolumePanel" })
	box.Visible = false
	panel = box
	local list = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -24, 1, -24), Position = UDim2.fromOffset(12, 12), Parent = box })
	Kit.list(list, Enum.FillDirection.Vertical, 6)
	for i, key in AudioConfig.PlayerVolumes do
		local row = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 46), LayoutOrder = i, Name = key, Parent = list })
		Kit.label({ Text = string.upper(key), Font = Kit.Fonts.Header, TextSize = 18, Size = UDim2.new(0, 108, 1, 0), Parent = row })
		Kit.button({ Text = "-", Size = UDim2.fromOffset(52, 44), Position = UDim2.fromOffset(110, 1), TextSize = 22, Parent = row, Name = "Down",
			OnClick = function()
				AudioManager:SetVolume(key, volumes[key] - 0.1)
			end })
		valueLabels[key] = Kit.label({ Text = pct(volumes[key]), Font = Kit.Fonts.Number, TextSize = 18, XAlign = Enum.TextXAlignment.Center,
			Size = UDim2.new(0, 70, 1, 0), Position = UDim2.fromOffset(164, 0), Parent = row, Name = "Value" })
		Kit.button({ Text = "+", Size = UDim2.fromOffset(52, 44), Position = UDim2.fromOffset(236, 1), TextSize = 22, Parent = row, Name = "Up",
			OnClick = function()
				AudioManager:SetVolume(key, volumes[key] + 0.1)
			end })
	end
	refreshPanel()
end

-- Game events -------------------------------------------------------------------------------------------
local statuses: { [string]: string } = {}
local raidPhase: string? = nil

local function roomPos(id: string?): Vector3?
	if not id then
		return nil
	end
	local c = C.VaultRenderer.roomCenter(id)
	if c then
		centers[id] = c
	end
	return c or centers[id]
end

local function entrancePos(): Vector3?
	for id, r in C.StateStore.state.rooms do
		if r.type == "Entrance" then
			return roomPos(id)
		end
	end
	return nil
end

local function connectEvents()
	local S = C.StateStore
	S.Snapshot:Connect(function(state)
		table.clear(statuses)
		for id, d in state.dwellers do
			statuses[id] = d.status
		end
		raidPhase = state.raid and state.raid.phase
		readSettings(state.settings)
	end)
	S.ActionDone:Connect(function(name: string, ok: boolean, result: any, quiet: boolean?, payload: any?)
		if not ok then
			if not quiet then
				play("UIError")
			end
			return
		end
		local p = if type(payload) == "table" then payload else {}
		if name == "Build" then
			play("ConstructionStart", { at = roomPos(result and result.roomId) })
			task.delay(0.45, play, "ConstructionComplete")
		elseif name == "Upgrade" then
			play("Upgrade", { at = roomPos(p.roomId) })
			task.delay(0.4, play, "ConstructionComplete", { gain = 0.8 })
		elseif name == "Destroy" then
			play("Demolish", { at = centers[p.roomId or ""] })
		elseif name == "Rush" then
			if result and result.success then
				play("MachineryStartup", { at = roomPos(p.roomId) })
			end
		elseif name == "Repair" then
			play("SwitchToggle", { at = roomPos(p.roomId) })
		elseif name == "Revive" then
			play("Revive")
		elseif name == "Heal" then
			play("Heal")
		elseif name == "Explore" then
			AudioManager:Door("BlastDoor", true, entrancePos(), "heavy")
		elseif name == "Assign" or name == "Equip" then
			play("UISelect")
		elseif name == "TurnAway" then
			play("UICancel")
		end
	end)
	S.Collected:Connect(function(p)
		if not p.tapped then
			return -- the simulation's own deposits are silent
		end
		if (p.amount or 0) <= 0 then
			if p.full then
				play("UIError", { gain = 0.6 })
			end
			return
		end
		play(COLLECT[p.resource] or "UIReward")
		if (p.bolts or 0) > 0 then
			task.delay(0.12, play, "Currency")
		end
	end)
	S.Incident:Connect(function(p)
		local r = C.StateStore.state.rooms[p.roomId]
		local at = roomPos(p.roomId)
		if p.cause == "rush" and (p.kind == "Fire" or p.kind == "Breakdown") then
			play("Explosion", { at = at }) -- the overloaded machine blows
			AudioManager:Emergency("Explosion")
		end
		if p.kind == "Fire" then
			play("FireStart", { at = at })
			if r and MACHINES[r.type] then
				task.delay(0.5, play, "ElectricalZap", { at = at })
			end
		elseif p.kind == "Breakdown" then
			if r and r.type == "Power" then
				play("ElectricalEmergency", { at = at })
			elseif r and r.type == "Water" then
				play("WaterLeak", { at = at })
			else
				play("MachineBreakdown", { at = at })
			end
		else
			play("CreatureSqueak", { at = at })
		end
	end)
	S.IncidentEnd:Connect(function(p)
		local r = C.StateStore.state.rooms[p.roomId]
		local at = roomPos(p.roomId)
		if p.kind == "Fire" then
			play("FireOut", { at = at })
		elseif p.kind == "Breakdown" then
			-- generators and purifiers announce their own restart (see machine()); add the success
			if r and r.type == "Power" then
				task.delay(1, play, "Achievement", { gain = 0.55 })
			elseif not (r and r.type == "Water") then
				play("MachineRestart", { at = at })
			end
		else
			play("CreatureSqueak", { at = at, pitch = 1.25 })
		end
		if (p.bolts or 0) > 0 then
			task.delay(0.3, play, "Currency")
		end
	end)
	S.Raid:Connect(function(raid)
		local phase = raid and raid.phase
		if phase and raidPhase == "door" and phase ~= "door" then
			play("Explosion", { at = entrancePos() }) -- the blast door is breached
			AudioManager:Emergency("Explosion")
		end
		raidPhase = phase
	end)
	S.RaidEnd:Connect(function(p)
		raidPhase = nil
		play(if p.success then "Achievement" else "RaidLost")
	end)
	S.Combat:Connect(function(p)
		local raid = C.StateStore.state.raid
		local fallback = roomPos(raid and raid.roomId)
		for i, e in p.events do
			if i > 4 then
				break
			end
			local at = (C.DwellerController and C.DwellerController.positionOf(e.a)) or fallback
			task.delay((i - 1) * 0.06, function()
				AudioManager:Shot(e.w, at)
			end)
		end
	end)
	S.LevelUp:Connect(function()
		play("LevelUp")
	end)
	S.Arrival:Connect(function()
		AudioManager:Door("BlastDoor", true, entrancePos(), "heavy") -- a wanderer is let in
	end)
	S.Family:Connect(function(p)
		if p.kind == "court" then
			play("Romance")
		elseif p.kind == "expecting" then
			play("Romance", { pitch = 1.12 })
		elseif p.kind == "born" then
			play("SurvivorBorn")
		elseif p.kind == "grown" then
			play("LevelUp")
		end
	end)
	S.DwellerChanged:Connect(function(d)
		local before = statuses[d.id]
		statuses[d.id] = d.status
		if before and before ~= d.status then
			if d.status == "Dead" then
				play("SurvivorDeath")
			elseif d.status == "Waiting" then
				play("Doorbell", { at = entrancePos() })
			end
		end
	end)
	S.DwellerRemoved:Connect(function(id)
		statuses[id] = nil
	end)
	S.ExploreEnded:Connect(function(id)
		AudioManager:Door("BlastDoor", true, entrancePos(), "heavy")
		local d = C.StateStore.state.dwellers[id]
		if d and d.status ~= "Dead" then
			task.delay(0.6, play, "ResourceCollected") -- back safe with the haul
		end
	end)
	S.Offline:Connect(function()
		play("UIReward")
	end)
	if C.BuildController and C.BuildController.Changed then
		C.BuildController.Changed:Connect(function(typeId)
			if typeId then
				play("ConstructionMode")
			end
		end)
	end
end

-- Lifecycle -----------------------------------------------------------------------------------------
onSourceChanged = function(name: string)
	local bed = beds[name]
	if bed then
		for _, slot in bed.slots do
			bedSound(bed, slot)
		end
	end
end

local function hookGroups()
	for name in AudioConfig.Groups do
		local g = AudioLibrary.group(name)
		if g then
			groups[name] = g
		end
	end
	applyVolumes()
end

function AudioManager.Init(controllers)
	C = controllers
	for name, cue in Sounds do
		chosen[name] = cue.ids[1] -- optimistic until checked
	end
	for name, cue in Loops do
		chosen[name] = cue.ids[1]
	end
	-- the library comes from the server; if it hasn't arrived, build what's missing here
	if AudioFolder:GetAttribute("Built") then
		AudioLibrary.ensure()
	end
	hookGroups()
	twoD = Instance.new("Folder")
	twoD.Name = "UH_Audio2D"
	twoD.Parent = SoundService
	local part = Instance.new("Part")
	part.Name = "UH_AudioEmitters"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(1, 1, 1)
	part.CFrame = CFrame.new(0, 0, 0)
	part.Parent = if C.InputController then C.InputController.world() else workspace
	emitter = part
	-- UI: every button press clicks; panels and menus use the named cues
	local alias = { click = "UIClick", open = "UISelect" }
	Kit.sound = function(cue: string)
		local name = alias[cue] or cue
		if Sounds[name] then
			play(name)
		end
	end
end

function AudioManager.Start()
	buildPanel()
	connectEvents()
	readSettings(C.StateStore.state.settings)
	if not AudioFolder:GetAttribute("Built") then
		local t0 = os.clock()
		while not AudioFolder:GetAttribute("Built") and os.clock() - t0 < 5 do
			task.wait(0.25)
		end
		AudioLibrary.ensure()
		hookGroups()
	end
	for name, cue in Loops do
		makeBed(name, cue)
	end
	task.delay(3, verifyAll)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		updateListener()
		acc += dt
		if acc >= 0.25 then
			acc = 0
			updateWorld()
		end
		stepBeds(dt)
		stepAlarm(dt)
	end)
end

return AudioManager
