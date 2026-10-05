--!strict
-- Every sound in Underhaven, in one place. AudioLibrary turns this into the SoundGroups in
-- SoundService and the Sound objects under ReplicatedStorage.Audio; AudioManager (client) plays them.
--
-- To swap a sound, change its id in Assets: every cue that uses it follows. Each asset records where
-- it comes from, because not every public Roblox upload is safe for commercial use:
--   "pse"       Roblox's licensed Pro Sound Effects library ("(SFX)" titles): fine in any experience.
--   "apm"       Roblox's licensed APM Music library.
--   "community" uploaded by a Roblox user; where it originally came from is unverified. These are
--               kept in their own entries so they can be replaced in one line before release.
-- `checked` says how far the store listing could be confirmed from outside Roblox when this was
-- written: "store" (Creator Store page seen), "mirror" (only a fan site lists it), "unverified"
-- (not indexed anywhere reachable). Everything is checked again at runtime: the client asks Roblox
-- to load every id and records the ones that fail in AudioConfig.Failed (and the Studio Output).
-- A failed id is never swapped for a random one; a cue just moves on to its listed alternates.
local AudioConfig = {}

export type Asset = { id: number, title: string, source: string, checked: string }

local function asset(id: number, title: string, source: string, checked: string): Asset
	return { id = id, title = title, source = source, checked = checked }
end

AudioConfig.Assets = {
	UI = {
		Click = asset(113397864512278, "UI Click 1", "community", "unverified"),
		ClickAlt = asset(958120197, "UIClick", "community", "unverified"),
		Select = asset(4601635577, "UIButtonSelect", "community", "unverified"),
		Confirm = asset(119541807359284, "Click Button SOUND", "community", "unverified"),
		Coin = asset(17403146731, "Coin sound", "community", "unverified"),
		CoinDrop = asset(330274138, "Coin Drop", "community", "mirror"),
		Success = asset(1835270782, "Sounds of Success StingA", "apm", "unverified"),
	},
	Electrical = {
		Electric = asset(135658480423375, "Electric sound", "community", "unverified"),
		Zaps = asset(9114235460, "Electrical Zaps 1 (SFX)", "pse", "mirror"),
		StaticBlast = asset(9119594530, "Static Zap Blast 1", "pse", "unverified"),
		ChargeUp = asset(9125980816, "Spaceship Pre Blast Electric Charge Up Glass", "pse", "unverified"),
		Toggle = asset(9120102202, "Toggle Switch Metal Industrial Equipment 12", "pse", "unverified"),
		Bursts = asset(9116279358, "Lightning Flashes Quick Electrical Bursts 53", "pse", "unverified"),
		Whoosh = asset(9125519018, "Electric Whoosh", "pse", "unverified"),
		WhooshAlt = asset(9114270776, "Electric Whoosh", "pse", "unverified"),
	},
	Doors = {
		OpenClose = asset(2091298142, "Door Open and Close Sound effect", "community", "store"),
		Open = asset(6814491848, "Door Open Sound", "community", "store"),
		Close = asset(6814493519, "Door Close Sound", "community", "unverified"),
		LongSqueak = asset(9114145200, "Door Long Squeaks 18 (SFX)", "pse", "store"),
		PushOpen = asset(9114151207, "Door Push Open 4", "pse", "unverified"),
	},
	Footsteps = {
		Concrete = asset(6362185620, "Concrete Footsteps", "community", "mirror"),
		General = asset(1244506786, "Footsteps", "community", "mirror"),
		Concrete2 = asset(18984787734, "Footstep concrete", "community", "unverified"),
	},
	Alarms = {
		Master = asset(9113088926, "Alarm Master 19", "pse", "unverified"),
		Alt1 = asset(98532097014415, "alarm", "community", "unverified"),
		Alt2 = asset(108427904413933, "Alarm", "community", "unverified"),
		Alt3 = asset(168323076, "ALARM", "community", "store"),
	},
	Water = {
		Splash = asset(444742380, "Water Splash", "community", "unverified"),
		Sloshes = asset(9119481278, "Splashes Small Wet Sloshes Drips 11", "pse", "unverified"),
		Fountain = asset(9172960182, "Water fountain loop", "community", "unverified"),
		Drop = asset(114560640706315, "Water Drop - Sound Effects", "community", "mirror"),
		Splat1 = asset(9120590649, "Water Splatter Short Splat 1", "pse", "unverified"),
		Splat8 = asset(9120591135, "Water Splatter Short Splat 8", "pse", "unverified"),
		Puddle = asset(9117941991, "Puddle Impact Big Puddle Splash Footsteps 15", "pse", "unverified"),
	},
	Explosions = {
		Big = asset(101485554695540, "Explosion", "community", "unverified"),
		Old = asset(55224766, "Explosion Sound", "community", "unverified"),
	},
	Ambience = {
		-- an APM music track (0:31, minimal/cinematic), not an electrical hum: used as rare quiet music
		Electricity = asset(1841151615, "Electricity", "apm", "store"),
		-- not the official APM upload of "Forgotten Memories" (that is 1842074746 / 1845175569)
		Memories = asset(9042708412, "Forgotten Memories sting", "community", "unverified"),
	},
	-- Not in the audio brief: Pro Sound Effects picked earlier for game events the brief has no sound
	-- for (combat, creatures, fire, family moments, machinery beds). Replace freely.
	Earlier = {
		EerieAmbience = asset(9112775175, "Eerie Ambience 1 (SFX)", "pse", "store"),
		Refinery = asset(9112839293, "Oil Refinery Ambience 2 (SFX)", "pse", "store"),
		Conveyor = asset(9113910422, "Conveyor Belt 2 (SFX)", "pse", "store"),
		FireWhoosh = asset(9114444008, "Fire Whoosh 3 (SFX)", "pse", "store"),
		FireCrackle = asset(9120827361, "Wood Crack Snapping Splintering Crackling 1 (SFX)", "pse", "store"),
		FireBurning = asset(158853971, "Fire Burning [Sound Effect]", "community", "store"),
		PowerDown = asset(9117870273, "Power Down 11 (SFX)", "pse", "store"),
		Buzzer = asset(9113085665, "Alarm Buzzer 3 (SFX)", "pse", "store"),
		DoorKnock = asset(9114141265, "Door Knock 2 (SFX)", "pse", "store"),
		SteelDoor = asset(9119630175, "Steel Door 4 (SFX)", "pse", "store"),
		Pistol = asset(9114726695, "Gun Single Shots 5 (SFX)", "pse", "store"),
		Shotgun = asset(9112910543, "12 Gauge Shotgun 3 (SFX)", "pse", "store"),
		Revolver = asset(9119298682, "Smith Wesson 38 Revolver 2 (SFX)", "pse", "store"),
		Rifle = asset(9113181642, "Assault Rifle 21 (SFX)", "pse", "store"),
		Punch = asset(9113964719, "Cracky Punch 1 (SFX)", "pse", "store"),
		RatSqueaks = asset(9118053542, "Rat Squeaks 37 (SFX)", "pse", "store"),
		Squeaking = asset(2909172855, "Squeaking Sound Effect", "community", "store"),
		Shimmer = asset(9116420445, "Magic Tone Tonal Shimmer Shaking Rattle 1 (SFX)", "pse", "store"),
		SparkleDing = asset(9126073011, "Synth Sparkle Tone High Pitch Bell Tone Ding (SFX)", "pse", "store"),
		SparkleHeal = asset(9125986205, "Sparkle Tone Constant High End Shimmer Spark (SFX)", "pse", "store"),
		ReverseCymbal = asset(9125626784, "Light Cone Suck Synth And Reverse Cymbal Bui (SFX)", "pse", "store"),
		AngelDrone = asset(9113122524, "Angel Presence Cymbal Drone 4 (SFX)", "pse", "store"),
		RocksDrop = asset(9125392715, "Big Rocks Drop Interior Muffled Some Debris (SFX)", "pse", "store"),
		MetalCrash = asset(9116546593, "Metal Crash 4 (SFX)", "pse", "store"),
	},
}

-- Ids from the brief that are deliberately NOT played, and why.
AudioConfig.NotUsed = {
	{ id = 6034003547, title = "Footstep Module", why = "A Model (a ModuleScript plus a table of footstep sounds), not audio. Its listing says the sounds are CS:GO footsteps, i.e. ripped game audio. Our own code plays footsteps instead." },
	{ id = 131700277400105, title = "ZRK's Advanced Footstep Sounds", why = "Most likely a Model with scripts; it couldn't be inspected from here, so nothing from it was inserted. Inspect it in Studio before taking any of its audio." },
	{ id = 5348162330, title = "Alarm Sound", why = "Community upload whose origin is unclear (fan sites credit it to 'The Sound'); the brief says to use it only if its provenance is acceptable. Add it to Sounds.Alarm.ids once checked." },
}

-- Filled in at runtime by AudioManager: [asset id] = { cue = name, status = "Failure" | ..., title = ... }.
AudioConfig.Failed = {} :: { [number]: any }

-- Sound groups (all children of SoundService) and their default volumes. The player's own volume
-- (0..1) multiplies the default, and Master multiplies everything.
AudioConfig.Groups = {
	Master = 1,
	Music = 0.35,
	SFX = 0.75,
	UI = 0.55,
	Ambient = 0.45,
	Voice = 1,
}
AudioConfig.PlayerVolumes = { "Master", "Music", "SFX", "Ambient", "UI" } -- the sliders, in order

-- Folders under ReplicatedStorage.Audio (each cue's Sound object goes in its `folder`).
AudioConfig.Folders = {
	UI = { "Click", "Select", "Confirm", "Cancel", "Error", "Reward" },
	Vault = { "Generator", "Machinery", "Electricity", "Doors", "Elevator", "Pipes", "Water" },
	Characters = { "Footsteps", "Interaction", "Injury" },
	Events = { "Alarm", "Fire", "PowerFailure", "WaterFailure", "Raid", "Explosion", "Infestation" },
	Resources = { "Food", "Water", "Materials", "Medicine", "Currency" },
	Rewards = { "ResourceCollected", "ConstructionComplete", "LevelUp", "Achievement", "Discovery" },
	Music = {},
}

-- How far 3D sounds carry, in studs from the listener (which hovers in front of what the camera
-- looks at, closer when zoomed in). min: full volume inside this; max: silent beyond it.
AudioConfig.RollOff = {
	Small = { 10, 70 }, -- footsteps, drips, switches
	Room = { 22, 130 }, -- machinery, doors, fire
	Large = { 60, 500 }, -- explosions, breaches
}

export type Cue = {
	ids: { Asset }, -- first that loads is used; the rest are alternates
	folder: string,
	group: string,
	volume: number,
	space: string?, -- "2D" (default: UI, notifications) or "3D" (world: placed where it happens)
	rolloff: string?, -- RollOff class for 3D
	cooldown: number?, -- seconds before the cue can play again
	pitch: number?, -- random PlaybackSpeed variation, +/- (0.05 = 0.95..1.05)
	vary: number?, -- random volume variation, +/- fraction (0.1 = +/-10%)
	speed: number?, -- base PlaybackSpeed
	cut: number?, -- stop (with a short fade) after this many seconds; library clips are often long
	start: number?, -- skip this many seconds into the clip
	pick: string?, -- "random": any id that loads, each play (variation); default: the first that loads
	voices: number?, -- how many copies may overlap (default 2)
	priority: number?, -- 0 = expendable (dropped first when busy), 1 normal, 2+ important
}

local A = AudioConfig.Assets
local UI, EL, DO, FS, AL, WA, EX, AM, OLD = A.UI, A.Electrical, A.Doors, A.Footsteps, A.Alarms, A.Water, A.Explosions, A.Ambience, A.Earlier

-- One-shots. AudioManager:Play("UIClick") / AudioManager:PlayAt("DoorOpen", position).
AudioConfig.Sounds = {
	-- Interface (2D). UI sounds within 80 ms of each other don't stack: the higher priority wins.
	UIClick = { ids = { UI.Click, UI.ClickAlt }, folder = "UI/Click", group = "UI", volume = 0.32, cut = 0.6, pitch = 0.02, cooldown = 0.05, priority = 1 },
	UISelect = { ids = { UI.Select }, folder = "UI/Select", group = "UI", volume = 0.28, cut = 0.8, cooldown = 0.08, priority = 2 },
	UIConfirm = { ids = { UI.Confirm }, folder = "UI/Confirm", group = "UI", volume = 0.38, cut = 1, cooldown = 0.15, priority = 3 },
	UICancel = { ids = { UI.ClickAlt }, folder = "UI/Cancel", group = "UI", volume = 0.26, speed = 0.85, cut = 0.6, cooldown = 0.08, priority = 2 },
	UIError = { ids = { OLD.Buzzer }, folder = "UI/Error", group = "UI", volume = 0.3, cut = 0.45, cooldown = 0.4, priority = 3 },
	UIReward = { ids = { UI.CoinDrop }, folder = "UI/Reward", group = "UI", volume = 0.42, cut = 1.5, cooldown = 0.15, priority = 3 },

	-- Resources: only when the player collects by hand, never on simulation ticks.
	CollectFood = { ids = { UI.CoinDrop }, folder = "Resources/Food", group = "UI", volume = 0.4, cut = 1.5, pitch = 0.03, cooldown = 0.12, priority = 3 },
	CollectWater = { ids = { UI.CoinDrop }, folder = "Resources/Water", group = "UI", volume = 0.4, speed = 1.06, cut = 1.5, pitch = 0.03, cooldown = 0.12, priority = 3 },
	CollectMaterials = { ids = { UI.CoinDrop }, folder = "Resources/Materials", group = "UI", volume = 0.4, speed = 0.92, cut = 1.5, pitch = 0.03, cooldown = 0.12, priority = 3 },
	CollectMedicine = { ids = { UI.CoinDrop }, folder = "Resources/Medicine", group = "UI", volume = 0.4, speed = 1.12, cut = 1.5, pitch = 0.03, cooldown = 0.12, priority = 3 },
	Currency = { ids = { UI.Coin }, folder = "Resources/Currency", group = "UI", volume = 0.4, cut = 1.5, cooldown = 0.15, priority = 3 },

	-- Rewards
	ConstructionComplete = { ids = { UI.Success }, folder = "Rewards/ConstructionComplete", group = "UI", volume = 0.6, cut = 4, cooldown = 2.5, priority = 4 },
	Achievement = { ids = { UI.Success }, folder = "Rewards/Achievement", group = "UI", volume = 0.65, cut = 4, cooldown = 2.5, priority = 4 },
	ResourceCollected = { ids = { UI.Success }, folder = "Rewards/ResourceCollected", group = "UI", volume = 0.55, cut = 4, cooldown = 2.5, priority = 4 },
	LevelUp = { ids = { OLD.Shimmer }, folder = "Rewards/LevelUp", group = "UI", volume = 0.4, cut = 1.6, cooldown = 1, priority = 3 },
	Discovery = { ids = { AM.Memories }, folder = "Rewards/Discovery", group = "Music", volume = 0.9, cut = 8, cooldown = 20, priority = 4 },
	AmbientMusic = { ids = { AM.Electricity }, folder = "Music", group = "Music", volume = 0.5, cooldown = 60, voices = 1, priority = 1 },

	-- Construction and machinery
	ConstructionMode = { ids = { EL.Toggle }, folder = "Vault/Machinery", group = "UI", volume = 0.4, cut = 0.8, cooldown = 0.3, priority = 3 },
	ConstructionStart = { ids = { EL.Toggle }, folder = "Vault/Machinery", group = "SFX", volume = 0.5, speed = 0.9, cut = 0.8, cooldown = 0.25, space = "3D", rolloff = "Room" },
	Upgrade = { ids = { EL.Whoosh, EL.WhooshAlt }, folder = "Vault/Machinery", group = "SFX", volume = 0.5, cut = 2, cooldown = 0.5, space = "3D", rolloff = "Room" },
	Demolish = { ids = { OLD.RocksDrop, OLD.MetalCrash }, folder = "Vault/Machinery", group = "SFX", volume = 0.5, cut = 2, cooldown = 0.5, space = "3D", rolloff = "Room" },
	MachineryStartup = { ids = { EL.ChargeUp }, folder = "Vault/Machinery", group = "SFX", volume = 0.45, cut = 2.2, cooldown = 3, space = "3D", rolloff = "Room" },
	MachineRestart = { ids = { EL.WhooshAlt, EL.Whoosh }, folder = "Vault/Machinery", group = "SFX", volume = 0.35, cut = 1.6, cooldown = 1, space = "3D", rolloff = "Room" },
	SwitchToggle = { ids = { EL.Toggle }, folder = "Vault/Machinery", group = "SFX", volume = 0.35, cut = 0.8, pitch = 0.05, vary = 0.1, cooldown = 0.2, space = "3D", rolloff = "Small" },
	MachineBreakdown = { ids = { EL.StaticBlast }, folder = "Vault/Machinery", group = "SFX", volume = 0.5, cut = 2, cooldown = 1, space = "3D", rolloff = "Room" },

	-- Generator and electricity
	GeneratorStart = { ids = { EL.Electric }, folder = "Vault/Generator", group = "SFX", volume = 0.5, cut = 2.5, cooldown = 1, space = "3D", rolloff = "Room" },
	PurifierStart = { ids = { EL.Electric }, folder = "Vault/Water", group = "SFX", volume = 0.35, speed = 1.1, cut = 2, cooldown = 1, space = "3D", rolloff = "Room" },
	ElectricalTick = { ids = { EL.Zaps }, folder = "Vault/Electricity", group = "SFX", volume = 0.2, cut = 0.7, pitch = 0.08, vary = 0.1, cooldown = 1.5, space = "3D", rolloff = "Small", priority = 0 },
	ElectricalZap = { ids = { EL.Zaps }, folder = "Vault/Electricity", group = "SFX", volume = 0.38, cut = 1.2, pitch = 0.06, vary = 0.1, cooldown = 1, space = "3D", rolloff = "Room" },
	ElectricalEmergency = { ids = { EL.Bursts }, folder = "Events/PowerFailure", group = "SFX", volume = 0.55, cut = 2.5, cooldown = 2, space = "3D", rolloff = "Room", priority = 3 },
	PowerFailure = { ids = { EL.StaticBlast }, folder = "Events/PowerFailure", group = "SFX", volume = 0.6, cut = 2.5, cooldown = 3, priority = 3 },
	PowerRestored = { ids = { EL.Electric }, folder = "Events/PowerFailure", group = "SFX", volume = 0.55, cut = 2.5, cooldown = 3, priority = 3 },

	-- Water
	WaterSplash = { ids = { WA.Splash }, folder = "Vault/Water", group = "SFX", volume = 0.4, cut = 1.5, pitch = 0.05, vary = 0.1, cooldown = 0.5, space = "3D", rolloff = "Room" },
	WaterSmall = { ids = { WA.Sloshes, WA.Drop }, folder = "Vault/Pipes", group = "SFX", volume = 0.22, cut = 1.4, pitch = 0.08, vary = 0.1, cooldown = 1, pick = "random", space = "3D", rolloff = "Small", priority = 0 },
	WaterDrip = { ids = { WA.Drop, WA.Sloshes }, folder = "Vault/Pipes", group = "SFX", volume = 0.18, cut = 1, pitch = 0.1, vary = 0.1, cooldown = 1, pick = "random", space = "3D", rolloff = "Small", priority = 0 },
	WaterSplatter = { ids = { WA.Splat1, WA.Splat8 }, folder = "Vault/Water", group = "SFX", volume = 0.28, cut = 1, pitch = 0.06, vary = 0.1, cooldown = 0.6, pick = "random", space = "3D", rolloff = "Small", priority = 0 },
	WaterFailure = { ids = { OLD.PowerDown }, folder = "Events/WaterFailure", group = "SFX", volume = 0.45, speed = 0.8, cut = 2, cooldown = 2, space = "3D", rolloff = "Room", priority = 2 },
	WaterLeak = { ids = { WA.Puddle, WA.Splat1 }, folder = "Events/WaterFailure", group = "SFX", volume = 0.4, cut = 1.5, cooldown = 2, space = "3D", rolloff = "Room" },

	-- Doors (debounced per door by AudioManager:Door)
	DoorOpen = { ids = { DO.Open }, folder = "Vault/Doors", group = "SFX", volume = 0.45, cut = 1.6, pitch = 0.04, vary = 0.1, cooldown = 0.3, space = "3D", rolloff = "Room" },
	DoorClose = { ids = { DO.Close }, folder = "Vault/Doors", group = "SFX", volume = 0.45, cut = 1.4, pitch = 0.04, vary = 0.1, cooldown = 0.3, space = "3D", rolloff = "Room" },
	DoorOpenClose = { ids = { DO.OpenClose }, folder = "Vault/Doors", group = "SFX", volume = 0.45, cut = 4, pitch = 0.04, cooldown = 0.5, space = "3D", rolloff = "Room" },
	DoorHeavy = { ids = { DO.PushOpen, DO.OpenClose }, folder = "Vault/Doors", group = "SFX", volume = 0.55, cut = 2.5, pitch = 0.03, cooldown = 0.5, space = "3D", rolloff = "Room", priority = 2 },
	DoorOld = { ids = { DO.LongSqueak }, folder = "Vault/Doors", group = "SFX", volume = 0.45, cut = 3, cooldown = 20, space = "3D", rolloff = "Room" },
	Doorbell = { ids = { OLD.DoorKnock }, folder = "Vault/Doors", group = "SFX", volume = 0.5, cut = 1.6, cooldown = 2, space = "3D", rolloff = "Room", priority = 2 },

	-- Elevator: no elevator recording in the brief, so it is built from industrial parts
	ElevatorButton = { ids = { EL.Toggle }, folder = "Vault/Elevator", group = "SFX", volume = 0.3, speed = 1.15, cut = 0.6, cooldown = 0.5, space = "3D", rolloff = "Small" },
	ElevatorDoorClose = { ids = { DO.Close }, folder = "Vault/Elevator", group = "SFX", volume = 0.25, speed = 1.1, cut = 1, cooldown = 0.5, space = "3D", rolloff = "Small" },
	ElevatorMotor = { ids = { EL.WhooshAlt, EL.Whoosh }, folder = "Vault/Elevator", group = "SFX", volume = 0.3, speed = 0.6, cut = 2.5, cooldown = 0.5, space = "3D", rolloff = "Room" },
	ElevatorArrive = { ids = { EL.Toggle }, folder = "Vault/Elevator", group = "SFX", volume = 0.35, speed = 0.75, cut = 0.8, cooldown = 0.5, space = "3D", rolloff = "Small" },
	ElevatorDoorOpen = { ids = { DO.Open }, folder = "Vault/Elevator", group = "SFX", volume = 0.25, speed = 1.1, cut = 1, cooldown = 0.5, space = "3D", rolloff = "Small" },

	-- Survivors
	FootstepConcrete = { ids = { FS.Concrete, FS.Concrete2, FS.General }, folder = "Characters/Footsteps", group = "SFX", volume = 0.22, vary = 0.3, pitch = 0.05, cut = 0.32, pick = "random", voices = 3, space = "3D", rolloff = "Small", priority = 0 },
	FootstepWet = { ids = { WA.Puddle, FS.Concrete }, folder = "Characters/Footsteps", group = "SFX", volume = 0.16, vary = 0.25, pitch = 0.05, cut = 0.35, pick = "random", voices = 2, space = "3D", rolloff = "Small", priority = 0 },
	SurvivorDeath = { ids = { OLD.AngelDrone }, folder = "Characters/Injury", group = "SFX", volume = 0.45, cut = 4, cooldown = 1, priority = 3 },
	SurvivorBorn = { ids = { AM.Memories }, folder = "Characters/Interaction", group = "Music", volume = 0.9, cut = 8, cooldown = 10, priority = 3 },
	Heal = { ids = { OLD.SparkleHeal }, folder = "Characters/Injury", group = "SFX", volume = 0.35, cut = 1.4, cooldown = 0.3 },
	Revive = { ids = { OLD.ReverseCymbal }, folder = "Characters/Injury", group = "SFX", volume = 0.45, cut = 2.5, cooldown = 0.5, priority = 2 },
	Romance = { ids = { OLD.SparkleDing }, folder = "Characters/Interaction", group = "SFX", volume = 0.3, speed = 1.25, cut = 1.2, cooldown = 1 },

	-- Emergencies
	Alarm = { ids = { AL.Master, AL.Alt1, AL.Alt2, AL.Alt3 }, folder = "Events/Alarm", group = "SFX", volume = 0.55, voices = 1, priority = 5 },
	FireStart = { ids = { OLD.FireWhoosh }, folder = "Events/Fire", group = "SFX", volume = 0.5, cut = 1.6, cooldown = 0.5, space = "3D", rolloff = "Room", priority = 2 },
	FireFight = { ids = { WA.Splat1, WA.Splat8 }, folder = "Events/Fire", group = "SFX", volume = 0.3, cut = 1, pitch = 0.06, vary = 0.1, cooldown = 0.6, pick = "random", space = "3D", rolloff = "Small" },
	FireOut = { ids = { WA.Splash }, folder = "Events/Fire", group = "SFX", volume = 0.45, cut = 1.5, cooldown = 0.5, space = "3D", rolloff = "Room", priority = 2 },
	Explosion = { ids = { EX.Big, EX.Old }, folder = "Events/Explosion", group = "SFX", volume = 0.7, cut = 4, cooldown = 1.5, space = "3D", rolloff = "Large", priority = 4 },
	RaidDoorHit = { ids = { OLD.SteelDoor }, folder = "Events/Raid", group = "SFX", volume = 0.5, cut = 0.9, pitch = 0.06, vary = 0.1, cooldown = 0.6, space = "3D", rolloff = "Room", priority = 2 },
	RaidLost = { ids = { OLD.PowerDown }, folder = "Events/Raid", group = "SFX", volume = 0.45, speed = 0.8, cut = 2.2, cooldown = 1, priority = 3 },
	CreatureSqueak = { ids = { OLD.RatSqueaks, OLD.Squeaking }, folder = "Events/Infestation", group = "SFX", volume = 0.4, cut = 1.3, pitch = 0.12, vary = 0.1, cooldown = 0.5, space = "3D", rolloff = "Room" },
	Gunshot = { ids = { OLD.Pistol }, folder = "Events/Raid", group = "SFX", volume = 0.3, cut = 0.8, pitch = 0.08, vary = 0.1, cooldown = 0.04, voices = 4, space = "3D", rolloff = "Room" },
	Shotgun = { ids = { OLD.Shotgun }, folder = "Events/Raid", group = "SFX", volume = 0.3, cut = 0.9, pitch = 0.05, vary = 0.1, cooldown = 0.04, voices = 3, space = "3D", rolloff = "Room" },
	Revolver = { ids = { OLD.Revolver }, folder = "Events/Raid", group = "SFX", volume = 0.3, cut = 0.9, pitch = 0.05, vary = 0.1, cooldown = 0.04, voices = 3, space = "3D", rolloff = "Room" },
	Rifle = { ids = { OLD.Rifle }, folder = "Events/Raid", group = "SFX", volume = 0.28, cut = 0.35, pitch = 0.06, vary = 0.1, cooldown = 0.04, voices = 4, space = "3D", rolloff = "Room" },
	Punch = { ids = { OLD.Punch }, folder = "Events/Raid", group = "SFX", volume = 0.35, cut = 0.6, pitch = 0.1, vary = 0.1, cooldown = 0.04, voices = 3, space = "3D", rolloff = "Small" },
} :: { [string]: Cue }

-- Continuous layers. AudioManager decides how loud each one is from the game state.
AudioConfig.Loops = {
	-- low: the vault's air, pipes and hum (2D, always there, ducks in a power failure)
	VaultAir = { ids = { OLD.EerieAmbience }, folder = "Vault/Pipes", group = "Ambient", volume = 0.5 },
	-- medium: machinery placed at the nearest visible rooms (3D)
	GeneratorHum = { ids = { OLD.Refinery, OLD.Conveyor }, folder = "Vault/Generator", group = "Ambient", volume = 0.55, space = "3D", rolloff = "Room", emitters = 2 },
	WaterFlow = { ids = { WA.Fountain }, folder = "Vault/Water", group = "Ambient", volume = 0.45, space = "3D", rolloff = "Room", emitters = 2 },
	FireCrackle = { ids = { OLD.FireCrackle, OLD.FireBurning }, folder = "Events/Fire", group = "SFX", volume = 0.5, space = "3D", rolloff = "Room", emitters = 2 },
} :: { [string]: any }

-- Rare, quiet music between emergencies (Music group).
AudioConfig.Music = {
	tracks = { "AmbientMusic" }, -- cues in Sounds
	firstAfter = 120, -- seconds after joining
	gap = { 420, 840 }, -- seconds between plays
}

-- One alarm layer for every emergency: a burst when something new goes wrong, quieter reminders
-- while it lasts, silence when it's over. Never loops for the whole emergency, never stacks.
AudioConfig.Emergency = {
	onsetBurst = 3.5, -- seconds of alarm when a new kind of emergency starts
	reminderBurst = 2,
	reminders = { 14, 22, 30 }, -- gaps between reminders (the last repeats)
	volume = 0.55,
	reminderVolume = 0.42,
	powerFailBelow = 0.5, -- grid meets less than half the demand: power failure
	powerBackAbove = 0.65,
}

-- Footsteps come from the walk/run animation's footfalls, throttled hard.
AudioConfig.Footsteps = {
	maxView = 46, -- studs of visible height; zoomed out further, no footsteps at all
	radius = 0.6, -- only within this fraction of the view height from the screen centre
	perSecond = 6, -- across all survivors
	surfaces = { Concrete = "FootstepConcrete", Wet = "FootstepWet" },
	roomSurface = { Water = "Wet" }, -- room type -> surface (default Concrete)
}

-- Occasional detail sounds from visible rooms, by room type (only while staffed and powered).
-- every = seconds between sounds for one room; fewer people, longer gaps. Empty = quiet room.
AudioConfig.RoomActivity = {
	Power = { sounds = { "ElectricalTick", "SwitchToggle" }, every = { 18, 40 } },
	Water = { sounds = { "WaterSmall", "WaterDrip" }, every = { 10, 24 } },
	Food = { sounds = { "WaterSplatter", "WaterDrip" }, every = { 24, 50 } },
	Workshop = { sounds = { "SwitchToggle", "ElectricalTick" }, every = { 14, 30 } },
	Infirmary = { sounds = { "ElectricalTick" }, every = { 45, 90 } },
	Cafeteria = { sounds = {}, every = { 30, 60 } }, -- footsteps only (voices later)
	Living = { sounds = {}, every = { 30, 60 } },
	Storage = { sounds = {}, every = { 30, 60 } },
}

-- Rare distant mechanical events, placed at a random room (so usually far and faint).
AudioConfig.Distant = { sounds = { "SwitchToggle", "DoorOpenClose", "ElectricalTick", "MachineRestart" }, every = { 90, 200 } }

-- What a survivor's activity sounds like when they start it (zoomed in, on screen only).
AudioConfig.Interactions = {
	Repair = "SwitchToggle",
	Extinguish = "FireFight",
	Drink = "WaterSmall",
	Farm = "WaterSplatter",
	UseComputer = "ElectricalTick",
	Work = "SwitchToggle",
}

-- Survivor voices go in the Voice group later (talking, eating, laughing, arguments, crying,
-- injuries, panic, celebration). Add cue names here and they will be picked up.
AudioConfig.Voice = {} :: { [string]: { string } }

-- Which gunshot each weapon fires, and its pitch.
AudioConfig.Weapons = {
	ScrapPistol = { cue = "Gunshot", speed = 1.05 },
	ScrapRevolver = { cue = "Revolver", speed = 1 },
	PipeRifle = { cue = "Rifle", speed = 0.92 },
	ImprovisedShotgun = { cue = "Shotgun", speed = 1 },
	IndustrialSMG = { cue = "Rifle", speed = 1.15 },
	MakeshiftRifle = { cue = "Revolver", speed = 0.85 },
	EnergyCarbine = { cue = "Gunshot", speed = 1.35 },
}

-- Audio debug panel: always available in Studio; in live servers only for these user ids
-- (and the game's owner, for games owned by a user).
AudioConfig.Debug = { UserIds = {} :: { number }, Key = "F7" }

-- "rbxassetid://<id>"
function AudioConfig.contentId(a: Asset): string
	return string.format("rbxassetid://%d", a.id)
end

return AudioConfig
