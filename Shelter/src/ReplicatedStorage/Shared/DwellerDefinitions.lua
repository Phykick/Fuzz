--!strict
-- Survivors: skills, jobs (archetypes), personality traits, appearance pools and generation rules.
local DwellerDefinitions = {}

-- Skills 1..10. Each job room uses one; combat, scavenging and fitness matter everywhere.
DwellerDefinitions.STATS = { "ENG", "MEC", "FRM", "COO", "MED", "CMB", "SOC", "FIT", "SCV" }
DwellerDefinitions.STAT_NAMES = {
	ENG = "Engineering", MEC = "Mechanics", FRM = "Farming", COO = "Cooking", MED = "Medicine",
	CMB = "Combat", SOC = "Social", FIT = "Fitness", SCV = "Scavenging",
}
DwellerDefinitions.STAT_DESC = {
	ENG = "Generators, workshops and repairs",
	MEC = "Water purification and machinery",
	FRM = "Hydroponic farming",
	COO = "Cafeteria meals (less food per meal, happier diners)",
	MED = "Medbay treatment and medicine",
	CMB = "Fighting raiders and creatures",
	SOC = "Friendships, romance, morale",
	FIT = "Health, firefighting, hauling, stamina",
	SCV = "Finds in the wasteland, lucky breaks",
}
-- Saves before schema 2 used a different 7-attribute set; this maps them onto skills.
DwellerDefinitions.LEGACY_STATS = { STR = "ENG", PER = "MEC", END = "FIT", CHA = "SOC", INT = "MED", AGI = "FRM", LCK = "SCV" }
DwellerDefinitions.MAX_STAT = 10
DwellerDefinitions.MAX_LEVEL = 50

-- Archetype = job identity: default wardrobe style (Shared/CharacterStyles) + skill leanings.
-- Equipped outfits (items) swap the style.
DwellerDefinitions.Archetypes = {
	Worker = { name = "Shelter Worker", style = "Worker", bias = { FIT = 1, ENG = 1 } },
	Engineer = { name = "Engineer", style = "Engineer", bias = { ENG = 2 } },
	Scientist = { name = "Scientist", style = "Scientist", bias = { MED = 1, MEC = 1 } },
	Medic = { name = "Medic", style = "Medic", bias = { MED = 2 } },
	Security = { name = "Security Guard", style = "Security", bias = { CMB = 2 } },
	Farmer = { name = "Farmer", style = "Farmer", bias = { FRM = 2 } },
	Cook = { name = "Cook", style = "Cook", bias = { COO = 2 } },
	Mechanic = { name = "Mechanic", style = "Mechanic", bias = { MEC = 2 } },
	Scavenger = { name = "Scavenger", style = "Scavenger", bias = { SCV = 2 } },
	Soldier = { name = "Soldier", style = "Soldier", bias = { CMB = 1, FIT = 1 } },
	Trader = { name = "Trader", style = "Trader", bias = { SOC = 2 } },
	Technician = { name = "Technician", style = "Technician", bias = { MEC = 1, ENG = 1 } },
	Overseer = { name = "Overseer", style = "Overseer", bias = { SOC = 1, MED = 1 } },
}

-- Random arrivals draw from every archetype except the last (the Overseer is unique).
DwellerDefinitions.ArchetypeOrder = {
	"Worker", "Engineer", "Scientist", "Medic", "Security", "Farmer", "Cook",
	"Mechanic", "Scavenger", "Soldier", "Trader", "Technician", "Overseer",
}

DwellerDefinitions.HairStyles = {
	F = { "HAIR_BOB", "HAIR_PONYTAIL", "HAIR_BUN", "HAIR_CURLY", "HAIR_SHORT", "HAIR_BRAIDS", "HAIR_SWEPT" },
	M = { "HAIR_SHORT", "HAIR_MOHAWK", "HAIR_CURLY", "HAIR_SWEPT", "HAIR_SHORT", "HAIR_NONE", "HAIR_SLICK" },
}
DwellerDefinitions.EyeColors = { "3A2414", "5A3A22", "6E4A2A", "4A6A8A", "3E7A4A", "5E6E78", "8A6A3A" }
DwellerDefinitions.BodyTypes = { "slim", "standard", "standard", "heavy" }
DwellerDefinitions.Heads = { "SV_HEAD_A", "SV_HEAD_B" }

local FIRST = {
	F = { "Ada", "Bea", "Cora", "Dina", "Edie", "Fern", "Greta", "Hana", "Iris", "June", "Kit", "Lena", "Mara",
		"Nell", "Opal", "Pia", "Quin", "Rosa", "Sana", "Tess", "Uma", "Vera", "Wren", "Yara", "Zoe", "Maya", "Noor", "Sarah" },
	M = { "Abe", "Bram", "Cal", "Dev", "Eli", "Finn", "Gus", "Hal", "Ivo", "Jude", "Kai", "Leo", "Milo", "Nico",
		"Otto", "Pax", "Rafe", "Sol", "Theo", "Uri", "Vic", "Wes", "Yusuf", "Zane", "Arlo", "Omar", "Tariq", "James" },
}
local LAST = { "Ashby", "Brask", "Calder", "Dunmore", "Ellery", "Faraday", "Gorse", "Hollis", "Ingram", "Joss",
	"Kettle", "Lowry", "Marsh", "Nash", "Orwin", "Pike", "Quarry", "Rook", "Stroud", "Tallow", "Underwood",
	"Vance", "Whitlock", "Yates", "Zeller", "Okafor", "Nakamura", "Rivera", "Petrov", "Haddad", "Lindqvist" }

-- Personality traits (each survivor gets two). Numbers are read by Simulation / Needs / LifeService.
DwellerDefinitions.Traits = {
	HardWorker = { name = "Hard Worker", desc = "+10% output at work.", production = 0.1 },
	Cheerful = { name = "Cheerful", desc = "Mood recovers faster.", happiness = 0.5 },
	Tough = { name = "Tough", desc = "+15 max health.", health = 15 },
	Lucky = { name = "Lucky", desc = "+2 Scavenging; luckier finds.", luck = 2 },
	QuickLearner = { name = "Quick Learner", desc = "+25% XP.", xp = 0.25 },
	BigEater = { name = "Big Eater", desc = "Gets hungry 30% faster.", hunger = 1.3 },
	LightEater = { name = "Light Eater", desc = "Gets hungry 25% slower.", hunger = 0.75 },
	Energetic = { name = "Energetic", desc = "Tires 25% slower.", energy = 0.75 },
	Sleepyhead = { name = "Sleepyhead", desc = "Tires 25% faster.", energy = 1.25 },
	Sociable = { name = "Sociable", desc = "Makes friends fast; happier around friends.", social = 1.6 },
	Loner = { name = "Loner", desc = "Slow to make friends; doesn't mind crowds.", social = 0.5, crowd = 0 },
	Brave = { name = "Brave", desc = "Emergencies don't rattle them.", danger = 0 },
	Nervous = { name = "Nervous", desc = "Emergencies hit their mood hard.", danger = 2 },
}
DwellerDefinitions.TraitOrder = {
	"HardWorker", "Cheerful", "Tough", "Lucky", "QuickLearner", "BigEater", "LightEater",
	"Energetic", "Sleepyhead", "Sociable", "Loner", "Brave", "Nervous",
}
-- Pairs that can't appear together.
local OPPOSITE = { BigEater = "LightEater", LightEater = "BigEater", Energetic = "Sleepyhead", Sleepyhead = "Energetic",
	Sociable = "Loner", Loner = "Sociable", Brave = "Nervous", Nervous = "Brave" }

function DwellerDefinitions.randomTraits(rng: Random): { string }
	local a = DwellerDefinitions.TraitOrder[rng:NextInteger(1, #DwellerDefinitions.TraitOrder)]
	local b = a
	while b == a or OPPOSITE[a] == b do
		b = DwellerDefinitions.TraitOrder[rng:NextInteger(1, #DwellerDefinitions.TraitOrder)]
	end
	return { a, b }
end

-- Traits of a survivor (current list, or the single trait older saves stored).
function DwellerDefinitions.traitsOf(d: any): { string }
	if d.traits then
		return d.traits
	end
	return if d.trait then { d.trait } else {}
end

function DwellerDefinitions.hasTrait(d: any, id: string): boolean
	return table.find(DwellerDefinitions.traitsOf(d), id) ~= nil
end

-- Product of a numeric trait field across a survivor's traits (1 when none set it).
function DwellerDefinitions.traitFactor(d: any, field: string): number
	local f = 1
	for _, t in DwellerDefinitions.traitsOf(d) do
		local def = (DwellerDefinitions.Traits :: any)[t]
		local v = def and def[field]
		if type(v) == "number" then
			f *= v
		end
	end
	return f
end

function DwellerDefinitions.randomName(rng: Random, gender: string): string
	local firsts = FIRST[gender] or FIRST.F
	return firsts[rng:NextInteger(1, #firsts)] .. " " .. LAST[rng:NextInteger(1, #LAST)]
end

function DwellerDefinitions.randomAppearance(rng: Random, gender: string, archetype: string)
	local skins = { "F6D7C3", "EAC09E", "D8A47F", "B97A57", "8D5524", "5E3A22", "3F2A1E" }
	local hairs = { "1F1A17", "3B2A20", "6A4428", "A0662F", "D9B26F", "B9B5AE", "8E2F24", "2F3A55" }
	local styles = DwellerDefinitions.HairStyles[gender] or DwellerDefinitions.HairStyles.F
	return {
		gender = gender,
		skin = skins[rng:NextInteger(1, #skins)],
		hair = styles[rng:NextInteger(1, #styles)],
		hairColor = hairs[rng:NextInteger(1, #hairs)],
		head = DwellerDefinitions.Heads[rng:NextInteger(1, #DwellerDefinitions.Heads)],
		body = DwellerDefinitions.BodyTypes[rng:NextInteger(1, #DwellerDefinitions.BodyTypes)],
		height = math.floor((0.94 + rng:NextNumber() * 0.12) * 100) / 100,
		beard = gender == "M" and rng:NextNumber() < 0.3,
		brow = rng:NextInteger(1, 3),
		eyeColor = DwellerDefinitions.EyeColors[rng:NextInteger(1, #DwellerDefinitions.EyeColors)],
		archetype = archetype,
	}
end

function DwellerDefinitions.randomStats(rng: Random, archetype: string, budget: number?)
	local stats = {}
	local keys = DwellerDefinitions.STATS
	for _, s in keys do
		stats[s] = 1
	end
	local points = budget or rng:NextInteger(12, 18)
	for _ = 1, points do
		local s = keys[rng:NextInteger(1, #keys)]
		if stats[s] < 6 then
			stats[s] += 1
		end
	end
	local arch = DwellerDefinitions.Archetypes[archetype]
	if arch then
		for s, b in arch.bias do
			stats[s] = math.min(DwellerDefinitions.MAX_STAT, (stats[s] or 1) + b)
		end
	end
	return stats
end

-- Convert an old 7-attribute block to skills (schema 1 -> 2).
function DwellerDefinitions.migrateStats(old: { [string]: number }): { [string]: number }
	local out = {}
	for _, s in DwellerDefinitions.STATS do
		out[s] = 1
	end
	for k, v in old do
		local nk = DwellerDefinitions.LEGACY_STATS[k] or k
		if out[nk] ~= nil then
			out[nk] = math.clamp(v, 1, DwellerDefinitions.MAX_STAT)
		end
	end
	-- the two new skills lean on related old attributes
	out.COO = math.clamp(math.floor(((old.AGI or 1) + (old.CHA or 1)) / 2 + 0.5), 1, DwellerDefinitions.MAX_STAT)
	out.CMB = math.clamp(math.floor(((old.STR or 1) + (old.PER or 1)) / 2 + 0.5), 1, DwellerDefinitions.MAX_STAT)
	return out
end

function DwellerDefinitions.xpForLevel(level: number): number
	return math.floor(60 * level ^ 1.45)
end

-- traits: a list (or a single trait id from older saves)
function DwellerDefinitions.maxHealthFor(level: number, fitness: number, traits: any): number
	local hp = 100 + (level - 1) * (2.5 + fitness * 0.5)
	local list = if type(traits) == "table" then traits elseif traits then { traits } else {}
	if table.find(list, "Tough") then
		hp += 15
	end
	return math.floor(hp)
end

return DwellerDefinitions
