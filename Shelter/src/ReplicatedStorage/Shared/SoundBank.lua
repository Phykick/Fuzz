--!strict
-- Sound cues: which public Roblox audio each game event plays, how loud, how long and how often.
--
-- Every id below is a PUBLIC Creator Store audio asset (titles in the comments; almost all are
-- from Roblox's licensed Pro Sound Effects library), so they play in any experience with no
-- uploads. Each cue lists candidates in order: the client checks the first one actually loads
-- (ContentProvider:PreloadAsync) and moves to the next if Roblox has made it unavailable. To
-- change a sound, put another Creator Store audio id first in its list.
--
-- cut: seconds to play before fading out (library clips are often long or hold several takes).
-- speed: base playback speed (pitch). pitch: random +/- share per play.
-- region / ATLAS_ID: optional last resort, our own generated sounds (audio/underhaven_sounds.ogg,
-- regions in Shared/SoundAtlas) - only used if you upload that file and set ATLAS_ID.
local SoundBank = {}

SoundBank.ATLAS_ID = "" -- optional, e.g. "rbxassetid://1234567890"

local function id(n: number): string
	return "rbxassetid://" .. string.format("%d", n)
end

export type Cue = {
	ids: { string }?,
	region: string?,
	group: string,
	volume: number,
	cut: number?,
	speed: number?,
	pitch: number?,
	cooldown: number?,
}

SoundBank.Cues = {
	-- interface
	click = { ids = {
		id(82284970220669), -- UI Click / Interact SFX
		id(9126109935), -- Tonal Click Blurp Tone Slightly Metallic Swi (SFX)
	}, cut = 0.3, region = "ui_click", group = "UI", volume = 0.35, pitch = 0.05, cooldown = 0.05 },
	open = { ids = {
		id(9113318154), -- Baseball Swish 2 (SFX)
		id(9113081793), -- Airy Whoosh Blast 4 (SFX)
	}, cut = 0.45, region = "ui_open", group = "UI", volume = 0.2, cooldown = 0.12 },
	close = { ids = {
		id(9113318154), -- Baseball Swish 2 (SFX), lower
		id(9113081793), -- Airy Whoosh Blast 4 (SFX)
	}, cut = 0.4, speed = 0.85, region = "ui_close", group = "UI", volume = 0.15, cooldown = 0.12 },
	error = { ids = {
		id(9113085665), -- Alarm Buzzer 3 (SFX)
	}, cut = 0.4, region = "ui_error", group = "UI", volume = 0.22, cooldown = 0.3 },

	-- economy and building
	collect = { ids = {
		id(9126072433), -- Synth Sparkle Tone High Pitch Bell Tone Burs (SFX)
		id(1169755927), -- Coin Collect - SFX
	}, cut = 1.2, region = "collect", group = "SFX", volume = 0.3, pitch = 0.06, cooldown = 0.08 },
	bolts = { ids = {
		id(1169755927), -- Coin Collect - SFX
		id(9119219346), -- Slot Machine 7 (SFX)
	}, cut = 0.9, region = "bolts", group = "SFX", volume = 0.3, pitch = 0.04, cooldown = 0.1 },
	build = { ids = {
		id(9117665655), -- Pneumatic Air Blast Grinding Tool 1 (SFX)
		id(9120094799), -- Toggle Switch Metal Industrial Equipment 19 (SFX)
	}, cut = 1.8, region = "build", group = "SFX", volume = 0.35, cooldown = 0.3 },
	upgrade = { ids = {
		id(9126073011), -- Synth Sparkle Tone High Pitch Bell Tone Ding (SFX)
	}, region = "upgrade", group = "SFX", volume = 0.4, cooldown = 0.3 },
	demolish = { ids = {
		id(9125392715), -- Big Rocks Drop Interior Muffled Some Debris (SFX)
		id(9116546593), -- Metal Crash 4 (SFX)
	}, cut = 2.5, region = "demolish", group = "SFX", volume = 0.45, cooldown = 0.3 },
	rush = { ids = {
		id(9125973984), -- Spaceship Blast High Pitch Energy Charge Up (SFX)
	}, region = "rush", group = "SFX", volume = 0.3, cooldown = 0.3 },

	-- people
	levelup = { ids = {
		id(9116420445), -- Magic Tone Tonal Shimmer Shaking Rattle 1 (SFX)
		id(9126073011), -- Synth Sparkle Tone High Pitch Bell Tone Ding (SFX)
	}, cut = 2, region = "levelup", group = "SFX", volume = 0.35, cooldown = 0.4 },
	heal = { ids = {
		id(9125986205), -- Sparkle Tone Constant High End Shimmer Spark (SFX)
	}, cut = 1.5, region = "heal", group = "SFX", volume = 0.3, cooldown = 0.2 },
	revive = { ids = {
		id(9125626784), -- Light Cone Suck Synth And Reverse Cymbal Bui (SFX)
	}, cut = 3, region = "revive", group = "SFX", volume = 0.4, cooldown = 0.3 },
	doorbell = { ids = {
		id(9114141265), -- Door Knock 2 (SFX): a wanderer knocks on the blast door
	}, cut = 2, region = "doorbell", group = "SFX", volume = 0.5, cooldown = 2 },
	welcome = { ids = {
		id(9114145200), -- Door Long Squeaks 18 (SFX)
		id(9119630175), -- Steel Door 4 (SFX)
	}, cut = 1.8, region = "welcome", group = "SFX", volume = 0.35, cooldown = 0.3 },
	birth = { ids = {
		id(9113234666), -- Baby Crying Upset 6 Months Old 2 (SFX)
	}, cut = 2, region = "birth", group = "SFX", volume = 0.25, cooldown = 0.5 },
	romance = { ids = {
		id(9126073011), -- Synth Sparkle Tone High Pitch Bell Tone Ding (SFX), higher
	}, cut = 1.2, speed = 1.25, region = "romance", group = "SFX", volume = 0.25, cooldown = 1 },
	death = { ids = {
		id(9113122524), -- Angel Presence Cymbal Drone 4 (SFX)
	}, cut = 3, region = "death", group = "SFX", volume = 0.4, cooldown = 0.5 },

	-- emergencies and combat
	fire_start = { ids = {
		id(9114444008), -- Fire Whoosh 3 (SFX)
	}, region = "fire_start", group = "SFX", volume = 0.45, cooldown = 0.3 },
	extinguish = { ids = {
		id(9120562287), -- Water Hose Gun 7 (SFX)
	}, cut = 1.8, region = "extinguish", group = "SFX", volume = 0.35, cooldown = 0.3 },
	breakdown = { ids = {
		id(9117870273), -- Power Down 11 (SFX)
		id(9114247505), -- Electricity Static 22 (SFX)
	}, cut = 2.5, region = "breakdown", group = "SFX", volume = 0.45, cooldown = 0.3 },
	repair_done = { ids = {
		id(9120094799), -- Toggle Switch Metal Industrial Equipment 19 (SFX)
	}, cut = 1.2, region = "repair_done", group = "SFX", volume = 0.35, cooldown = 0.3 },
	creature = { ids = {
		id(9118053542), -- Rat Squeaks 37 (SFX)
		id(2909172855), -- Squeaking Sound Effect
	}, cut = 1.3, region = "creature", group = "SFX", volume = 0.3, pitch = 0.12, cooldown = 0.5 },
	gunshot = { ids = {
		id(9114726695), -- Gun Single Shots 5 (SFX)
	}, cut = 0.8, region = "gunshot", group = "SFX", volume = 0.22, pitch = 0.08, cooldown = 0.04 },
	shotgun = { ids = {
		id(9112910543), -- 12 Gauge Shotgun 3 (SFX)
	}, cut = 0.9, region = "gunshot", group = "SFX", volume = 0.22, pitch = 0.05, cooldown = 0.04 },
	revolver = { ids = {
		id(9119298682), -- Smith Wesson 38 Revolver 2 (SFX)
	}, cut = 0.9, region = "gunshot", group = "SFX", volume = 0.22, pitch = 0.05, cooldown = 0.04 },
	rifle = { ids = {
		id(9113181642), -- Assault Rifle 21 (SFX)
	}, cut = 0.35, region = "gunshot", group = "SFX", volume = 0.2, pitch = 0.06, cooldown = 0.04 },
	punch = { ids = {
		id(9113964719), -- Cracky Punch 1 (SFX)
	}, cut = 0.6, region = "punch", group = "SFX", volume = 0.3, pitch = 0.1, cooldown = 0.04 },
	door_hit = { ids = {
		id(9119630175), -- Steel Door 4 (SFX)
	}, cut = 1.5, region = "door_hit", group = "SFX", volume = 0.4, pitch = 0.05, cooldown = 0.6 },
	door_breach = { ids = {
		id(9114224217), -- Earthquake Explosion 3 (SFX)
		id(9114363548), -- Explosion Soft Crack 11 (SFX)
	}, cut = 3.5, region = "door_breach", group = "SFX", volume = 0.55, cooldown = 1 },
	raid_win = { ids = {
		id(152866462), -- Victory Sound
		id(266632027), -- Victory SFX
		id(9126073011), -- Synth Sparkle Tone High Pitch Bell Tone Ding (SFX)
	}, cut = 3, region = "raid_win", group = "SFX", volume = 0.45, cooldown = 1 },
	raid_lose = { ids = {
		id(9117870273), -- Power Down 11 (SFX), slowed
	}, cut = 2.5, speed = 0.8, region = "raid_lose", group = "SFX", volume = 0.4, cooldown = 1 },
} :: { [string]: Cue }

-- Continuous beds; SoundController fades them with what's on screen.
SoundBank.Loops = {
	vault = { ids = {
		id(9112775175), -- Eerie Ambience 1 (SFX): slow rumbly presence, pipe interior
		id(9125515917), -- Eastern Wind Constant Resonant Humming Ambie (SFX)
	}, region = "amb_vault", group = "Ambience", volume = 0.4 },
	power = { ids = {
		id(9112839293), -- Oil Refinery Ambience 2 (SFX): burners, compressors, machine hum
		id(9113910422), -- Conveyor Belt 2 (SFX)
	}, region = "hum_power", group = "Ambience", volume = 0.25 },
	water = { ids = {
		id(9114184147), -- Drips Small Into Bowl 4 (SFX)
	}, region = "hum_water", group = "Ambience", volume = 0.25 },
	fire = { ids = {
		id(9120827361), -- Wood Crack Snapping Splintering Crackling 1 (SFX)
		id(158853971), -- Fire Burning [Sound Effect]
	}, region = "fire", group = "SFX", volume = 0.35 },
	alarm = { ids = {
		id(9113073742), -- Air Raid Siren Old Fashioned 1 (SFX)
		id(9113083860), -- Alarm Beeps 1 (SFX)
	}, region = "alarm", group = "SFX", volume = 0.18 },
} :: { [string]: Cue }

-- Which gunshot each weapon fires, and its pitch.
SoundBank.Weapons = {
	ScrapPistol = { cue = "gunshot", speed = 1.05 },
	ScrapRevolver = { cue = "revolver", speed = 1 },
	PipeRifle = { cue = "rifle", speed = 0.92 },
	ImprovisedShotgun = { cue = "shotgun", speed = 1 },
	IndustrialSMG = { cue = "rifle", speed = 1.15 },
	MakeshiftRifle = { cue = "revolver", speed = 0.85 },
	EnergyCarbine = { cue = "gunshot", speed = 1.35 },
}

return SoundBank
