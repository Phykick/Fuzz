--!strict
-- Procedural R15 animation library (no uploaded animation assets needed).
-- Poses are tables of Motor6D.Transform CFrames keyed by standard R15 joint names.
-- Axis conventions (joint frames are axis-aligned with the character, forward = -Z):
--   limbs:  +X rotation swings a hanging limb FORWARD; knee bends are negative.
--   torso:  -X rotation leans FORWARD.   roll (Z): +Z moves a right-side limb outward.
local Animator = {}

local CharacterRig = require(game:GetService("ReplicatedStorage").Shared.CharacterRig)
-- Root offsets for low poses, as absolute pelvis heights above the floor.
local HIP = CharacterRig.HIP_HEIGHT
local SIT_Y = 1.53 - HIP -- on a chair / kneeling
local BED_Y = 0.61 - HIP -- lying on a bunk
local FLOOR_Y = 0.41 - HIP -- collapsed on the floor
Animator.__index = Animator

local sin, cos, abs, max, min, pi = math.sin, math.cos, math.abs, math.max, math.min, math.pi
local function rx(a: number)
	return CFrame.Angles(a, 0, 0)
end
local function ry(a: number)
	return CFrame.Angles(0, a, 0)
end
local function rz(a: number)
	return CFrame.Angles(0, 0, a)
end
local function smooth(x: number)
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end
-- Cheap smooth noise in [-1, 1]
local function noise(t: number, seed: number)
	return math.noise(t, seed * 7.31, 0.5) * 1.6
end
-- Periodic gesture envelope: 0 most of the time, smooth 1 bursts.
local function pulse(t: number, period: number, width: number)
	local p = (t % period) / period
	return smooth(min(p / width, (1 - p) / width, 1))
end

type Pose = { [string]: CFrame }
type Params = { seed: number, speed: number?, weapon: string?, scale: number? }

local Anims: { [string]: (number, Params) -> Pose } = {}

Anims.Idle = function(t, p)
	local b = sin(t * 2.1 + p.seed) * 0.03
	local look = noise(t * 0.25, p.seed)
	return {
		Root = CFrame.new(0, b * 0.8, 0) * rz(noise(t * 0.15, p.seed + 3) * 0.03),
		Waist = rx(-0.03 + b) * ry(look * 0.08),
		Neck = ry(look * 0.45) * rx(noise(t * 0.3, p.seed + 1) * 0.08),
		LeftShoulder = rz(-0.07 - b) * rx(noise(t * 0.4, p.seed + 2) * 0.05),
		RightShoulder = rz(0.07 + b) * rx(noise(t * 0.4, p.seed + 4) * 0.05),
		LeftElbow = rx(0.14),
		RightElbow = rx(0.14),
		LeftHip = rz(-0.02),
		RightHip = rz(0.02),
	}
end

local function gait(t: number, p: Params, freq: number, amp: number, lean: number, armAmp: number, elbow: number): Pose
	local ph = t * freq * 2 * pi
	local function leg(phase: number)
		local hip = amp * sin(phase)
		local knee = -(0.08 + (amp * 1.75) * max(0, cos(phase + pi * 0.3)) ^ 2)
		local ankle = 0.3 * sin(phase + 0.4) - 0.05
		return hip, knee, ankle
	end
	local lh, lk, la = leg(ph)
	local rh, rk, ra = leg(ph + pi)
	local bob = 0.09 * cos(2 * ph) + 0.02
	return {
		Root = CFrame.new(0, bob, 0) * ry(sin(ph) * 0.07) * rz(sin(ph) * 0.035),
		Waist = rx(lean) * ry(-sin(ph) * 0.12),
		Neck = rx(-lean * 0.6 + 0.03 * cos(2 * ph)) * ry(noise(t * 0.3, p.seed) * 0.15),
		LeftHip = rx(lh) * rz(-0.03),
		LeftKnee = rx(lk),
		LeftAnkle = rx(la),
		RightHip = rx(rh) * rz(0.03),
		RightKnee = rx(rk),
		RightAnkle = rx(ra),
		LeftShoulder = rx(-armAmp * sin(ph)) * rz(-0.1),
		RightShoulder = rx(armAmp * sin(ph)) * rz(0.1),
		LeftElbow = rx(elbow + 0.3 * max(0, -sin(ph))),
		RightElbow = rx(elbow + 0.3 * max(0, sin(ph))),
	}
end

local GAIT_HZ = { Walk = 1.95, Run = 2.8 } -- gait cycles per second at speed 1
Anims.Walk = function(t, p)
	return gait(t, p, GAIT_HZ.Walk * (p.speed or 1), 0.5, -0.07, 0.5, 0.28)
end
Anims.Run = function(t, p)
	return gait(t, p, GAIT_HZ.Run * (p.speed or 1), 0.72, -0.24, 0.85, 1.25)
end
Anims.Panic = function(t, p)
	local pose = gait(t, p, 3.0, 0.7, -0.12, 0.2, 0.4)
	pose.LeftShoulder = rx(2.5 + sin(t * 13) * 0.35) * rz(-0.3)
	pose.RightShoulder = rx(2.5 + sin(t * 13 + 1.5) * 0.35) * rz(0.3)
	pose.Neck = rx(-0.25) * ry(sin(t * 6) * 0.4)
	return pose
end

Anims.Work = function(t, p)
	local a = sin(t * 5 + p.seed)
	return {
		Root = CFrame.new(0, sin(t * 2.5) * 0.02, 0),
		Waist = rx(-0.14 + a * 0.03),
		Neck = rx(-0.22) * ry(noise(t * 0.4, p.seed) * 0.2),
		LeftShoulder = rx(0.85 + a * 0.12) * rz(-0.1),
		RightShoulder = rx(0.9 - a * 0.12) * rz(0.1),
		LeftElbow = rx(0.95 + a * 0.3),
		RightElbow = rx(0.95 - a * 0.3),
		LeftHip = rx(0.05),
		RightHip = rx(-0.03),
	}
end

Anims.UseComputer = function(t, p)
	local tap = sin(t * 15 + p.seed)
	local glance = pulse(t + p.seed, 6, 0.15)
	return {
		Root = CFrame.new(0, sin(t * 1.8) * 0.015, 0),
		Waist = rx(-0.1),
		Neck = rx(-0.05 + glance * 0.15) * ry(glance * 0.6),
		LeftShoulder = rx(0.72) * rz(-0.12),
		RightShoulder = rx(0.72) * rz(0.12),
		LeftElbow = rx(1.15 + tap * 0.12),
		RightElbow = rx(1.15 - tap * 0.12),
		LeftWrist = rx(-0.3),
		RightWrist = rx(-0.3),
	}
end

Anims.Repair = function(t, p)
	local h = sin(t * 7.5 + p.seed)
	local strike = max(0, h) ^ 2
	return {
		Root = CFrame.new(0, -0.18, 0),
		Waist = rx(-0.3 - strike * 0.08) * ry(0.12),
		Neck = rx(-0.25),
		RightShoulder = rx(1.35 + h * 0.55) * rz(0.12),
		RightElbow = rx(0.75 + h * 0.4),
		LeftShoulder = rx(0.85) * rz(-0.15),
		LeftElbow = rx(1.0),
		LeftHip = rx(0.32),
		RightHip = rx(0.2),
		LeftKnee = rx(-0.55),
		RightKnee = rx(-0.4),
		LeftAnkle = rx(0.22),
		RightAnkle = rx(0.18),
	}
end

Anims.Farm = function(t, p)
	local c = sin(t * 1.6 + p.seed)
	local reach = smooth((c + 1) / 2)
	return {
		Root = CFrame.new(0, -0.35 * reach, 0),
		Waist = rx(-0.25 - 0.35 * reach),
		Neck = rx(-0.15),
		LeftShoulder = rx(0.55 + 0.45 * reach + sin(t * 6) * 0.08) * rz(-0.1),
		RightShoulder = rx(0.55 + 0.45 * reach - sin(t * 6) * 0.08) * rz(0.1),
		LeftElbow = rx(0.5),
		RightElbow = rx(0.5),
		LeftHip = rx(0.35 * reach),
		RightHip = rx(0.25 * reach),
		LeftKnee = rx(-0.6 * reach),
		RightKnee = rx(-0.45 * reach),
	}
end

Anims.Guard = function(t, p)
	local scan = noise(t * 0.2, p.seed)
	local armed = p.weapon ~= nil and p.weapon ~= "Fists"
	return {
		Root = CFrame.new(0, sin(t * 2) * 0.02, 0),
		Waist = ry(scan * 0.15),
		Neck = ry(scan * 0.6),
		RightShoulder = if armed then rx(0.55) * rz(0.15) else rz(0.35) * rx(0.15),
		RightElbow = if armed then rx(1.05) else rx(1.5),
		LeftShoulder = if armed then rx(0.75) * rz(-0.3) else rz(-0.35) * rx(0.15),
		LeftElbow = if armed then rx(1.1) else rx(1.5),
		LeftHip = rz(-0.08),
		RightHip = rz(0.08),
	}
end

Anims.Sit = function(t, p)
	local look = noise(t * 0.22, p.seed)
	return {
		Root = CFrame.new(0, SIT_Y, 0.15),
		Waist = rx(0.08 + sin(t * 2) * 0.02),
		Neck = ry(look * 0.5) * rx(0.05),
		LeftHip = rx(1.45) * rz(-0.06),
		RightHip = rx(1.45) * rz(0.06),
		LeftKnee = rx(-1.45),
		RightKnee = rx(-1.45),
		LeftShoulder = rx(0.45) * rz(-0.08),
		RightShoulder = rx(0.45) * rz(0.08),
		LeftElbow = rx(0.7),
		RightElbow = rx(0.7),
	}
end

Anims.Talk = function(t, p)
	local base = Anims.Idle(t, p)
	local g = pulse(t + p.seed, 2.8, 0.3)
	local g2 = pulse(t + p.seed + 1.3, 4.1, 0.25)
	base.RightShoulder = rx(0.25 + g * 0.6) * rz(0.12 + g * 0.2)
	base.RightElbow = rx(0.5 + g * 0.8 + sin(t * 9) * 0.12 * g)
	base.LeftShoulder = rx(0.15 + g2 * 0.5) * rz(-0.12 - g2 * 0.2)
	base.LeftElbow = rx(0.4 + g2 * 0.7)
	base.Neck = (base.Neck :: CFrame) * rx(sin(t * 5) * 0.06 * (g + g2))
	return base
end

Anims.Eat = function(t, p)
	local base = Anims.Idle(t, p)
	local e = pulse(t + p.seed, 2.6, 0.35)
	base.RightShoulder = rx(0.35 + e * 0.95) * rz(0.12 - e * 0.25)
	base.RightElbow = rx(0.4 + e * 1.9)
	base.Neck = (base.Neck :: CFrame) * rx(-e * 0.15)
	base.LeftShoulder = rx(0.4) * rz(-0.1)
	base.LeftElbow = rx(1.2)
	return base
end

-- Seated at a cafeteria table, eating.
Anims.SitEat = function(t, p)
	local base = Anims.Sit(t, p)
	local e = pulse(t + p.seed, 2.4, 0.35)
	base.RightShoulder = rx(0.75 + e * 0.75) * rz(0.12 - e * 0.2)
	base.RightElbow = rx(0.9 + e * 1.4)
	base.LeftShoulder = rx(0.7) * rz(-0.1)
	base.LeftElbow = rx(1.1)
	base.Neck = (base.Neck :: CFrame) * rx(0.12 - e * 0.15)
	return base
end

-- Standing at the water dispenser, sipping from a cup.
Anims.Drink = function(t, p)
	local base = Anims.Idle(t, p)
	local e = pulse(t + p.seed, 3.2, 0.45)
	base.RightShoulder = rx(0.5 + e * 0.9) * rz(0.1)
	base.RightElbow = rx(0.8 + e * 1.5)
	base.Neck = (base.Neck :: CFrame) * rx(-e * 0.3)
	return base
end

Anims.Sleep = function(t, p)
	local b = sin(t * 1.3) * 0.03
	return {
		Root = CFrame.new(0, BED_Y, 0) * rz(pi / 2),
		Waist = rx(b),
		Neck = rz(-0.15) * rx(0.1),
		LeftShoulder = rz(-0.15) * rx(0.2),
		RightShoulder = rz(0.15) * rx(0.4),
		LeftElbow = rx(0.6),
		RightElbow = rx(1.2),
		LeftHip = rx(0.25),
		RightHip = rx(0.05),
		LeftKnee = rx(-0.5),
		RightKnee = rx(-0.15),
	}
end

Anims.Shoot = function(t, p)
	local fists = p.weapon == nil or p.weapon == "Fists"
	if fists then
		local jab = max(0, sin(t * 9 + p.seed)) ^ 3
		local jab2 = max(0, sin(t * 9 + p.seed + pi)) ^ 3
		return {
			Root = CFrame.new(0, -0.15 + sin(t * 4.5) * 0.04, 0),
			Waist = rx(-0.15) * ry(0.25 + (jab - jab2) * 0.2),
			Neck = ry(-0.2),
			RightShoulder = rx(0.9 + jab * 0.7) * rz(0.1),
			RightElbow = rx(1.9 - jab * 1.6),
			LeftShoulder = rx(0.9 + jab2 * 0.7) * rz(-0.1),
			LeftElbow = rx(1.9 - jab2 * 1.6),
			LeftHip = rx(0.35),
			RightHip = rx(-0.3),
			LeftKnee = rx(-0.3),
			RightKnee = rx(-0.15),
		}
	end
	return {
		Root = CFrame.new(0, -0.1 + sin(t * 2.2) * 0.02, 0),
		Waist = ry(0.32) * rx(-0.05),
		Neck = ry(-0.28),
		RightShoulder = rx(1.52) * rz(0.05),
		RightElbow = rx(0.06),
		RightWrist = rx(0.05),
		LeftShoulder = rx(1.38) * rz(0.42),
		LeftElbow = rx(0.45),
		LeftHip = rx(0.3) * rz(-0.06),
		RightHip = rx(-0.25) * rz(0.06),
		LeftKnee = rx(-0.25),
		RightKnee = rx(-0.1),
	}
end

Anims.Extinguish = function(t, p)
	local sweep = sin(t * 2.3 + p.seed)
	return {
		Root = CFrame.new(0, -0.12, 0),
		Waist = rx(-0.15) * ry(sweep * 0.32),
		Neck = ry(sweep * 0.2) * rx(-0.1),
		RightShoulder = rx(1.1) * rz(0.15),
		RightElbow = rx(0.5),
		LeftShoulder = rx(1.25) * rz(-0.05),
		LeftElbow = rx(0.4),
		LeftHip = rx(0.25),
		RightHip = rx(-0.2),
		LeftKnee = rx(-0.25),
	}
end

Anims.Heal = function(t, p)
	local w = sin(t * 4 + p.seed)
	return {
		Root = CFrame.new(0, SIT_Y, 0),
		Waist = rx(-0.35),
		Neck = rx(-0.3),
		LeftHip = rx(1.35),
		LeftKnee = rx(-1.6),
		RightHip = rx(-0.15),
		RightKnee = rx(-1.75),
		RightAnkle = rx(0.6),
		RightShoulder = rx(0.95 + w * 0.15),
		RightElbow = rx(0.8),
		LeftShoulder = rx(0.95 - w * 0.15),
		LeftElbow = rx(0.8),
	}
end

Anims.Celebrate = function(t, p)
	local hop = abs(sin(t * 6 + p.seed))
	return {
		Root = CFrame.new(0, hop * 0.55, 0),
		Waist = rx(0.1),
		Neck = rx(0.25),
		LeftShoulder = rz(-2.55 - hop * 0.2) * rx(0.2),
		RightShoulder = rz(2.55 + hop * 0.2) * rx(0.2),
		LeftElbow = rx(0.3),
		RightElbow = rx(0.3),
		LeftKnee = rx(-0.4 * (1 - hop)),
		RightKnee = rx(-0.4 * (1 - hop)),
		LeftHip = rx(0.2 * (1 - hop)),
		RightHip = rx(0.2 * (1 - hop)),
	}
end

Anims.Carry = function(t, p)
	local pose = gait(t, p, 1.8, 0.42, -0.05, 0, 0)
	pose.LeftShoulder = rx(1.0) * rz(-0.15)
	pose.RightShoulder = rx(1.0) * rz(0.15)
	pose.LeftElbow = rx(0.9)
	pose.RightElbow = rx(0.9)
	return pose
end

-- Happy two-step used while a couple gets to know each other.
Anims.Dance = function(t, p)
	local beat = t * 5.2 + p.seed
	local sway = sin(beat * 0.5)
	local hop = abs(sin(beat))
	return {
		Root = CFrame.new(sway * 0.12, hop * 0.12, 0) * rz(sway * 0.08) * ry(sway * 0.25),
		Waist = rz(-sway * 0.12) * rx(0.05),
		Neck = rz(sway * 0.15) * rx(0.12),
		LeftShoulder = rz(-0.6 - hop * 0.5) * rx(0.4 + sway * 0.3),
		RightShoulder = rz(0.6 + hop * 0.5) * rx(0.4 - sway * 0.3),
		LeftElbow = rx(1.1 + hop * 0.3),
		RightElbow = rx(1.1 + hop * 0.3),
		LeftHip = rx(0.25 * max(0, sway)),
		RightHip = rx(0.25 * max(0, -sway)),
		LeftKnee = rx(-0.45 * max(0, sway)),
		RightKnee = rx(-0.45 * max(0, -sway)),
	}
end

Anims.Ride = function(t, p)
	local pose = Anims.Idle(t, p)
	pose.Neck = rx(0.2) * ry(noise(t * 0.4, p.seed) * 0.2)
	return pose
end

Anims.Wave = function(t, p)
	local pose = Anims.Idle(t, p)
	pose.RightShoulder = rz(2.4) * rx(0.2)
	pose.RightElbow = rx(0.6 + sin(t * 10) * 0.45)
	pose.Neck = rx(0.1)
	return pose
end

Anims.Dragged = function(t, p)
	local kick = sin(t * 9)
	return {
		Root = CFrame.new(0, 0.6, 0),
		Waist = rx(0.1),
		Neck = rx(0.25) * ry(sin(t * 3) * 0.3),
		LeftShoulder = rz(-2.7) * rx(0.15),
		RightShoulder = rz(2.7) * rx(0.15),
		LeftHip = rx(0.4 + kick * 0.35),
		RightHip = rx(0.4 - kick * 0.35),
		LeftKnee = rx(-0.6 - kick * 0.25),
		RightKnee = rx(-0.6 + kick * 0.25),
	}
end

Anims.Death = function(t, p)
	local k = smooth(t / 0.55)
	local bounce = if t > 0.55 then max(0, sin((t - 0.55) * 18) * 0.06 * math.exp(-(t - 0.55) * 8)) else 0
	return {
		Root = CFrame.new(0, FLOOR_Y * k + bounce, 0.4 * k) * rx(1.5 * k),
		Waist = rx(0.15 * k),
		Neck = rx(0.25 * k) * ry(0.5 * k),
		LeftShoulder = rz(-1.3 * k) * rx(0.4 * k),
		RightShoulder = rz(1.1 * k) * rx(-0.2 * k),
		LeftElbow = rx(0.5 * k),
		RightElbow = rx(0.2 * k),
		LeftHip = rx(0.35 * k) * rz(-0.2 * k),
		RightHip = rx(0.1 * k) * rz(0.25 * k),
		LeftKnee = rx(-0.45 * k),
	}
end

Animator.Anims = Anims

-- Instance ---------------------------------------------------------------------
export type AnimState = {
	motors: { [string]: Motor6D },
	name: string,
	t: number,
	params: Params,
	from: Pose?,
	blend: number,
	blendTime: number,
	last: Pose,
	hurt: number,
	recoil: number,
	onFootfall: ((running: boolean) -> ())?, -- set by whoever wants footstep sounds
	footIdx: number?,
}

function Animator.new(motors: { [string]: Motor6D }, seed: number)
	local self = setmetatable({
		motors = motors,
		name = "Idle",
		t = math.random() * 10,
		params = { seed = seed, speed = 1 } :: Params,
		from = nil :: Pose?,
		blend = 1,
		blendTime = 0.25,
		last = {} :: Pose,
		hurt = 0,
		recoil = 0,
		onFootfall = nil :: ((running: boolean) -> ())?,
		footIdx = nil :: number?,
	}, Animator)
	return self
end

function Animator:play(name: string, blendTime: number?)
	if name == self.name or not Anims[name] then
		return
	end
	self.from = self.last
	self.blend = 0
	self.blendTime = blendTime or 0.25
	self.name = name
	if name == "Death" then
		self.t = 0
	end
end

function Animator:setParam(key: string, value: any)
	(self.params :: any)[key] = value
end

function Animator:flinch()
	self.hurt = 1
end

function Animator:kick()
	self.recoil = 1
end

function Animator:step(dt: number)
	self.t += dt
	local pose = Anims[self.name](self.t, self.params)
	-- footfalls: a foot lands twice per gait cycle, when its hip swing peaks forward
	local hz = GAIT_HZ[self.name]
	if hz and self.onFootfall then
		local k = math.floor(2 * self.t * hz * (self.params.speed or 1) - 0.5)
		if self.footIdx and k ~= self.footIdx and self.blend >= 0.5 then
			self.onFootfall(self.name == "Run")
		end
		self.footIdx = k
	else
		self.footIdx = nil
	end
	if self.blend < 1 then
		self.blend = min(1, self.blend + dt / self.blendTime)
		local a = smooth(self.blend)
		local from = self.from or {}
		local mixed = {}
		for j in self.motors do
			local f = from[j] or CFrame.identity
			local to = pose[j] or CFrame.identity
			mixed[j] = f:Lerp(to, a)
		end
		pose = mixed
	end
	if self.hurt > 0 then
		self.hurt = max(0, self.hurt - dt * 3)
		local h = self.hurt
		pose.Waist = (pose.Waist or CFrame.identity) * rx(0.35 * h)
		pose.Neck = (pose.Neck or CFrame.identity) * rx(0.3 * h)
	end
	if self.recoil > 0 then
		self.recoil = max(0, self.recoil - dt * 7)
		pose.RightShoulder = (pose.RightShoulder or CFrame.identity) * rx(0.28 * self.recoil)
		pose.RightElbow = (pose.RightElbow or CFrame.identity) * rx(0.15 * self.recoil)
	end
	local s = self.params.scale or 1
	for j, m in self.motors do
		local cf = pose[j] or CFrame.identity
		if j == "Root" and s ~= 1 then
			-- root offsets are authored for a full-size adult; scaled rigs (children) shrink them
			cf = CFrame.new(cf.Position * s) * cf.Rotation
		end
		m.Transform = cf
	end
	self.last = pose
end

return Animator
