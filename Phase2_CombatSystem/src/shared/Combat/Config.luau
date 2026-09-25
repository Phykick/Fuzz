--[[
	Combat tuning. Everything a designer should need to tweak lives here.
	Distances are studs (1 m = 3 studs), times are seconds.
]]
local Config = {}

-- stamina ------------------------------------------------------------------
Config.Stamina = {
	Max = 100,
	RegenPerSecond = 22,
	RegenDelay = 0.9, -- seconds after spending before regen starts
	RegenMultiplierBlocking = 0.35,
	RegenMultiplierDrawing = 0.25,
	AttackCost = { HighRight = 18, HighLeft = 18, HorizontalRL = 20, HorizontalLR = 20, Thrust = 15 },
	MinToAttack = 8, -- below this you cannot start an attack
	FeintCost = 7,
	SprintPerSecond = 12,
	BowDrawCost = 8,
	BowHoldPerSecond = 7, -- at full draw
	PainCost = 8, -- stamina lost when hit
	BlockCostMultiplier = 0.9, -- stamina lost = damage * this when a block absorbs a blow
	LowStaminaDamageMultiplier = 0.7, -- attacks started under 20 stamina hit softer
}

-- sword --------------------------------------------------------------------
Config.Sword = {
	Damage = { HighRight = 30, HighLeft = 30, HorizontalRL = 27, HorizontalLR = 27, Thrust = 26 },
	PartMultiplier = { Head = 1.25, UpperTorso = 1.0, LowerTorso = 0.9, Arm = 0.75, Leg = 0.8 },
	RiposteMultiplier = 1.4, -- next attack after a perfect block
	RiposteWindow = 1.4,
	ComboWindowAfterRecoveryStart = 0.18, -- a new attack may cancel recovery after this
	HitSampleCount = 7, -- points swept along the blade
	MaxHitRange = 12, -- targets further than this (HRP to HRP) are skipped
	AttackRate = 1.0, -- global playback speed for attacks
	TurnRateDuringAttack = 150, -- deg/s the attacker may still turn while committed
}

-- blocking -----------------------------------------------------------------
Config.Block = {
	ActiveAfter = 0.12, -- block is solid this long after pressing
	PerfectWindow = 0.32, -- blow landing within this of pressing = perfect block
	CoverAngle = 80, -- degrees either side of facing that the block covers
	GuardBreakDamageFraction = 0.35,
	PerfectBlockStaminaGain = 10,
}

-- movement -----------------------------------------------------------------
Config.WalkSpeed = {
	Guard = 7,
	Sprint = 13,
	Blocking = 4,
	Windup = 2.5,
	Active = 1.5,
	Recovery = 3,
	Staggered = 0.5,
	Bow = 7,
	BowDrawing = 3.5,
}

-- bow ----------------------------------------------------------------------
Config.Bow = {
	-- ~55 m/s war arrow at full draw; gravity 9.81 m/s^2 at 3 studs/m
	FullDrawSpeed = 165,
	MinDrawSpeedFraction = 0.4,
	Gravity = 29.4,
	MinDrawToShoot = 0.35, -- releasing earlier than this lets the string down instead
	Damage = 48,
	PartMultiplier = { Head = 2.0, UpperTorso = 1.0, LowerTorso = 0.9, Arm = 0.6, Leg = 0.7 },
	BaseSpreadDeg = 0.5,
	SpreadGrowthPerSecond = 0.9, -- holding at full draw gets shakier
	MaxSpreadDeg = 4.0,
	LowStaminaSpreadDeg = 2.5,
	MaxAimAngleFromFacing = 40,
	ArrowLifetime = 5,
	StuckArrowLifetime = 25,
	MaxRange = 600,
}

-- animation blending ---------------------------------------------------------
Config.Anim = {
	ActionFadeIn = 0.1,
	ActionFadeOut = 0.18,
	LocoFade = 0.2,
}

-- sparring partner AI ---------------------------------------------------------
Config.AI = {
	PreferredDistance = 4.6, -- all attacks connect between ~3 and 5.4 studs (tests/range_test.luau)
	AttackRange = 5.2,
	AttackCooldown = { 1.4, 2.8 },
	BlockChance = 0.55,
	PerfectBlockChance = 0.2,
	FeintChance = 0.12,
	ReactionTime = { 0.12, 0.28 },
	RespawnDelay = 4,
}

return Config
