--!strict
-- Survivor needs: definitions, decay, shortage stages and their effects. Shared by the server
-- (LifeService, authority) and the client (profile bars, warnings).
--
-- Each need runs 0..100 where 100 is fully satisfied. Survivors look after a need on their own once
-- it drops below `seek` (if the shelter has the infrastructure). Below that, escalating stages
-- cost mood, then work efficiency, then health. New needs (Hygiene, Social, Fun, Comfort, Safety,
-- Stress...) slot in as more entries in Needs.Defs + Needs.LIST.
local DwellerDefinitions = require(script.Parent.DwellerDefinitions)

local Needs = {}

export type Stage = { below: number, label: string, mood: number, work: number, damage: number }
export type NeedDef = {
	name: string,
	icon: string,
	decay: number, -- points per minute while awake
	seek: number, -- start looking after it below this
	traitField: string?, -- DwellerDefinitions trait factor that scales decay
	stages: { Stage }, -- most severe first
}

Needs.LIST = { "Hunger", "Thirst", "Energy" }

Needs.Defs = {
	Hunger = {
		name = "Food", icon = "food", decay = 13, seek = 45, traitField = "hunger",
		stages = {
			{ below = 0.5, label = "Starving", mood = -22, work = 0.4, damage = 0.25 },
			{ below = 10, label = "Weak with hunger", mood = -16, work = 0.55, damage = 0 },
			{ below = 20, label = "Very hungry", mood = -10, work = 0.8, damage = 0 },
			{ below = 32, label = "Hungry", mood = -5, work = 1, damage = 0 },
		},
	},
	Thirst = {
		name = "Water", icon = "water", decay = 18, seek = 50,
		stages = {
			{ below = 0.5, label = "Dehydrated", mood = -25, work = 0.35, damage = 0.35 },
			{ below = 10, label = "Parched", mood = -18, work = 0.5, damage = 0 },
			{ below = 22, label = "Very thirsty", mood = -10, work = 0.8, damage = 0 },
			{ below = 35, label = "Thirsty", mood = -5, work = 1, damage = 0 },
		},
	},
	Energy = {
		name = "Rest", icon = "happy", decay = 6, seek = 25, traitField = "energy",
		stages = {
			{ below = 0.5, label = "Collapsed", mood = -12, work = 0.3, damage = 0 },
			{ below = 12, label = "Exhausted", mood = -8, work = 0.65, damage = 0 },
			{ below = 22, label = "Tired", mood = -3, work = 0.9, damage = 0 },
		},
	},
} :: { [string]: NeedDef }

Needs.SLEEP_RESTORE = 30 -- energy per minute while asleep (floor sleepers recover at 60%)
Needs.MEAL_SECONDS = 14
Needs.DRINK_SECONDS = 7

function Needs.default(): { [string]: number }
	return { Hunger = 85, Thirst = 85, Energy = 90 }
end

-- Decay per minute for this survivor (traits, children, hard work).
function Needs.decayOf(d: any, key: string): number
	local def = Needs.Defs[key]
	local rate = def.decay
	if def.traitField then
		rate *= DwellerDefinitions.traitFactor(d, def.traitField)
	end
	if d.child then
		rate *= if key == "Energy" then 1.1 else 0.7
	end
	if key == "Energy" and d.activity == "Working" then
		rate *= 1.2
	end
	return rate
end

function Needs.stage(key: string, value: number): Stage?
	for _, s in Needs.Defs[key].stages do
		if value < s.below then
			return s
		end
	end
	return nil
end

-- Multiplier on work output from unmet needs (worst stage wins).
function Needs.workFactor(d: any): number
	local n = d.needs
	if not n then
		return 1
	end
	local f = 1
	for _, key in Needs.LIST do
		local s = Needs.stage(key, n[key] or 100)
		if s and s.work < f then
			f = s.work
		end
	end
	return f
end

-- Mood points from unmet needs (summed).
function Needs.mood(d: any): number
	local n = d.needs
	if not n then
		return 0
	end
	local m = 0
	for _, key in Needs.LIST do
		local s = Needs.stage(key, n[key] or 100)
		if s then
			m += s.mood
		end
	end
	return m
end

-- The most pressing need problem, for UI ("Very thirsty"), or nil.
function Needs.worst(d: any): (string?, string?)
	local n = d.needs
	if not n then
		return nil, nil
	end
	local best, label, key = 0, nil, nil
	for _, k in Needs.LIST do
		local s = Needs.stage(k, n[k] or 100)
		if s and -s.mood > best then
			best, label, key = -s.mood, s.label, k
		end
	end
	return label, key
end

return Needs
