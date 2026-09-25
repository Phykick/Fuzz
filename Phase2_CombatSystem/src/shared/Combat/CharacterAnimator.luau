--!nonstrict
--[[
	CharacterAnimator: layered animation state for one combat character.

	  base   = idle loop, blended into 4-way locomotion by the root's velocity
	           (playback rate = ground speed / authored speed, so feet don't skate)
	  action = the clip sequence in the character's "Act" attribute (set by the
	           server), full-body or upper-body only, cross-faded in and out

	The server writes "Act" = "id|startTime|rate|flags|ClipA,ClipB". Everyone
	evaluates the same timeline from workspace:GetServerTimeNow(), so clients
	render it and the server can rebuild exact blade/hurtbox positions.
	Flags: "u" = upper body only (legs keep walking), "h" = hold the last frame.
]]

local Combat = script.Parent
local PoseDriver = require(Combat.PoseDriver)
local Clips = require(Combat.Clips)
local RigData = require(Combat.RigData)
local Config = require(Combat.Config)

local CharacterAnimator = {}
CharacterAnimator.__index = CharacterAnimator

local DIRS = { "Fwd", "Back", "Left", "Right" }
local UPPER = RigData.upper

-- act encoding ----------------------------------------------------------------
function CharacterAnimator.encodeAct(id: number, t0: number, rate: number, flags: string, seq: { string }): string
	return string.format("%d|%.4f|%.3f|%s|%s", id, t0, rate, flags, table.concat(seq, ","))
end

function CharacterAnimator.parseAct(s: string?)
	if not s or s == "" then
		return nil
	end
	local parts = string.split(s, "|")
	if #parts < 5 then
		return nil
	end
	return {
		id = tonumber(parts[1]),
		t0 = tonumber(parts[2]) or 0,
		rate = tonumber(parts[3]) or 1,
		upper = string.find(parts[4], "u", 1, true) ~= nil,
		hold = string.find(parts[4], "h", 1, true) ~= nil,
		seq = string.split(parts[5], ","),
	}
end

-- Total length (s) of a sequence played once (loops count once).
function CharacterAnimator.sequenceLength(seq: { string }): number
	local t = 0
	for _, n in seq do
		t += PoseDriver.clipLength(n)
	end
	return t
end

-- construction ------------------------------------------------------------------
function CharacterAnimator.new(model: Model)
	local rig, err = PoseDriver.bind(model)
	if not rig then
		return nil, err
	end
	local self = setmetatable({
		model = model,
		rig = rig,
		hrp = rig.hrp,
		humanoid = model:FindFirstChildOfClass("Humanoid"),
		idleT = math.random() * 3,
		phase = 0,
		moveW = 0,
		rate = 1,
		dirW = { Fwd = 1, Back = 0, Left = 0, Right = 0 },
		idle = PoseDriver.newPose(),
		loco = PoseDriver.newPose(),
		base = PoseDriver.newPose(),
		dirPose = {},
		actPose = PoseDriver.newPose(),
		out = PoseDriver.newPose(),
		snap = PoseDriver.newPose(),
		actKey = nil,
		act = nil,
		actW = 0,
		actUpper = false,
		fadeT = 1,
		hasOut = false,
		actClip = nil, -- name of the clip currently playing in the action layer
		actClipTime = 0,
	}, CharacterAnimator)
	for _, d in DIRS do
		self.dirPose[d] = PoseDriver.newPose()
	end
	return self
end

local function copyPose(src, dst)
	for i, r in src.rots do
		dst.rots[i] = r
	end
	dst.off = src.off
end

-- Evaluate the action layer at `now`. Returns true while it is producing a pose.
function CharacterAnimator:_evalAction(now: number): boolean
	local act = self.act
	if not act then
		return false
	end
	local elapsed = math.max(0, (now - act.t0) * act.rate)
	local n = #act.seq
	for i, name in act.seq do
		local clip = PoseDriver.getClip(name)
		local last = i == n
		if elapsed < clip.length or (last and (clip.meta.loop or act.hold)) then
			PoseDriver.sample(clip, elapsed, last and clip.meta.loop, self.actPose)
			self.actClip = name
			self.actClipTime = elapsed
			return true
		end
		elapsed -= clip.length
	end
	self.actClip = nil
	return false
end

-- Advance and return the blended pose for this frame.
function CharacterAnimator:update(dt: number, now: number)
	local model = self.model
	-- action attribute changed -> start a cross-fade from the current output
	local key = model:GetAttribute("Act")
	if key ~= self.actKey then
		self.actKey = key
		local act = CharacterAnimator.parseAct(key)
		if self.hasOut then
			copyPose(self.out, self.snap)
			self.fadeT = 0
		end
		self.act = act
		if act then
			self.actUpper = act.upper
		end
	end

	-- base layer: idle + locomotion
	local weapon = model:GetAttribute("Weapon") or "Sword"
	local prefix = weapon == "Bow" and "Bow" or "Sword"
	self.idleT += dt
	PoseDriver.sample(PoseDriver.getClip(prefix .. "_Idle"), self.idleT, true, self.idle)

	local hrp = self.hrp
	local rel = hrp.CFrame:VectorToObjectSpace(hrp.AssemblyLinearVelocity)
	local speed = Vector3.new(rel.X, 0, rel.Z).Magnitude
	local grounded = true
	if self.humanoid then
		grounded = self.humanoid.FloorMaterial ~= Enum.Material.Air
	end
	local moving = grounded and speed > 0.5
	local k = math.clamp(dt / Config.Anim.LocoFade, 0, 1)
	self.moveW += ((moving and 1 or 0) - self.moveW) * k
	if moving then
		local f, b = math.max(0, -rel.Z), math.max(0, rel.Z)
		local l, r = math.max(0, -rel.X), math.max(0, rel.X)
		local sum = f + b + l + r
		local target = { Fwd = f / sum, Back = b / sum, Left = l / sum, Right = r / sum }
		for _, d in DIRS do
			self.dirW[d] += (target[d] - self.dirW[d]) * math.clamp(dt * 8, 0, 1)
		end
		self.rate = speed / Clips.locoSpeed
	end
	if self.moveW > 0.01 then
		local len = PoseDriver.clipLength(prefix .. "_Walk_Fwd")
		self.phase = (self.phase + dt * self.rate / len) % 1
		for _, d in DIRS do
			if self.dirW[d] > 0.01 then
				PoseDriver.sample(PoseDriver.getClip(prefix .. "_Walk_" .. d), self.phase * len, true, self.dirPose[d])
			end
		end
		PoseDriver.mix(self.dirPose, self.dirW, self.loco)
		PoseDriver.blend(self.idle, self.loco, self.moveW, nil, self.base)
	else
		copyPose(self.idle, self.base)
	end

	-- action layer
	local active = self:_evalAction(now)
	local target = active and 1 or 0
	local rateK = active and Config.Anim.ActionFadeIn or Config.Anim.ActionFadeOut
	self.actW += (target - self.actW) * math.clamp(dt / rateK, 0, 1)
	if active and self.actW > 0.98 then
		self.actW = 1
	end
	local out = self.out
	if self.actW > 0.001 then
		local w = self.actW
		w = w * w * (3 - 2 * w)
		PoseDriver.blend(self.base, self.actPose, w, self.actUpper and UPPER or nil, out)
	else
		copyPose(self.base, out)
	end

	-- cross-fade from the previous action's last pose
	if self.fadeT < 1 then
		self.fadeT = math.min(1, self.fadeT + dt / Config.Anim.ActionFadeIn)
		local w = self.fadeT * self.fadeT * (3 - 2 * self.fadeT)
		PoseDriver.blend(self.snap, out, w, nil, out)
	end
	self.hasOut = true
	return out
end

-- Current bow prop state (arrow / string), from the playing bow clip.
function CharacterAnimator:bowProps()
	if not self.actClip or self.actW < 0.5 then
		return nil
	end
	local clip = PoseDriver.getClip(self.actClip)
	if not clip.props then
		return nil
	end
	return PoseDriver.sampleProps(clip, self.actClipTime, clip.meta.loop)
end

return CharacterAnimator
