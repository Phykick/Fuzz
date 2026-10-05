--!strict
-- Data-driven room catalogue. Add a room by adding an entry; build menu, costs, production,
-- pathing and save data pick it up automatically. Visual dressing lives client-side
-- (Client/Render/RoomDressing) and falls back to a generic shell when absent.
--
-- Every room serves survival AND daily life: production rooms are workplaces (and can break or
-- burn), the Cafeteria is where people eat, drink and chat, Bedrooms are where they sleep, the
-- Medbay is where the injured recover.
--
-- Rates are per module per minute for a full crew of average skill (5).
local RoomDefinitions = {}

export type Amenities = { eat: number?, drink: number?, sleep: number?, treat: number? }

export type RoomDef = {
	id: string,
	name: string,
	category: string, -- Survival | Population | Medical | Industry | Special | Structure
	desc: string,
	units: number, -- grid columns per module
	maxModules: number,
	stat: string?, -- skill the crew uses (see DwellerDefinitions.STATS)
	produces: string?,
	rate: { number }?, -- per level
	inputs: { [string]: number }?, -- resource used per unit produced (production chains)
	storage: { [string]: { number } }?, -- resource -> per-module storage per level
	housing: { number }?, -- beds per module per level
	amenities: Amenities?, -- seats per module for survivors' errands
	slots: number, -- worker slots per module
	powerUse: number, -- power / minute / module
	cost: number, -- bolts
	costStep: number,
	materials: number, -- materials to build
	upgrade: { number }, -- bolts per module to reach level 2, 3
	upgradeMaterials: { number },
	unlockPop: number,
	buildable: boolean,
	order: number,
	icon: string,
	incidentWeight: number,
	breakdown: number?, -- weight for machinery breakdowns
}

local defs: { [string]: RoomDef } = {
	Entrance = {
		id = "Entrance", name = "Blast Door", category = "Special",
		desc = "The shelter's only way in. Station guards here to stop raiders at the door.",
		units = 3, maxModules = 1, stat = "CMB", slots = 2, powerUse = 0.8,
		cost = 0, costStep = 0, materials = 0, upgrade = { 600, 1800 }, upgradeMaterials = { 120, 300 },
		unlockPop = 0, buildable = false, order = 0, icon = "door", incidentWeight = 0,
	},
	Elevator = {
		id = "Elevator", name = "Elevator", category = "Structure",
		desc = "Connects floors. Survivors ride it to reach rooms below.",
		units = 1, maxModules = 1, slots = 0, powerUse = 0.4,
		cost = 50, costStep = 5, materials = 10, upgrade = {}, upgradeMaterials = {},
		unlockPop = 0, buildable = true, order = 1, icon = "elevator", incidentWeight = 0,
	},
	Power = {
		id = "Power", name = "Generator", category = "Survival",
		desc = "Turbines that keep the lights on. Every other room needs power. Engineers (ENG) run it; it can break down.",
		units = 3, maxModules = 3, stat = "ENG", produces = "Power", rate = { 20, 27, 35 },
		storage = { Power = { 60, 90, 120 } }, slots = 2, powerUse = 0,
		cost = 100, costStep = 25, materials = 40, upgrade = { 500, 1500 }, upgradeMaterials = { 80, 200 },
		unlockPop = 0, buildable = true, order = 2, icon = "power", incidentWeight = 1.2, breakdown = 1,
	},
	Water = {
		id = "Water", name = "Water Purifier", category = "Survival",
		desc = "Filters groundwater into something drinkable. Needs power and mechanics (MEC).",
		units = 3, maxModules = 3, stat = "MEC", produces = "Water", rate = { 18, 24, 31 },
		storage = { Water = { 60, 90, 120 } }, slots = 2, powerUse = 3.5,
		cost = 100, costStep = 25, materials = 40, upgrade = { 500, 1500 }, upgradeMaterials = { 80, 200 },
		unlockPop = 0, buildable = true, order = 3, icon = "water", incidentWeight = 1, breakdown = 0.6,
	},
	Food = {
		id = "Food", name = "Hydroponics", category = "Survival",
		desc = "Grow-lamp farms that turn water into food. Needs power and farmers (FRM).",
		units = 3, maxModules = 3, stat = "FRM", produces = "Food", rate = { 16, 22, 28 },
		inputs = { Water = 0.3 },
		storage = { Food = { 60, 90, 120 } }, slots = 2, powerUse = 3.5,
		cost = 100, costStep = 25, materials = 40, upgrade = { 500, 1500 }, upgradeMaterials = { 80, 200 },
		unlockPop = 0, buildable = true, order = 4, icon = "food", incidentWeight = 1,
	},
	Cafeteria = {
		id = "Cafeteria", name = "Cafeteria", category = "Survival",
		desc = "Where survivors eat, drink and chat. Cooks (COO) stretch every meal and lift the mood.",
		units = 3, maxModules = 3, stat = "COO", amenities = { eat = 4, drink = 3 }, slots = 2, powerUse = 2,
		cost = 120, costStep = 30, materials = 50, upgrade = { 450, 1300 }, upgradeMaterials = { 80, 200 },
		unlockPop = 0, buildable = true, order = 5, icon = "food", incidentWeight = 0.8,
	},
	Living = {
		id = "Living", name = "Bedrooms", category = "Population",
		desc = "Bunks for sleeping and a place to unwind. Each bed houses one survivor.",
		units = 3, maxModules = 3, stat = "SOC", housing = { 6, 9, 12 }, slots = 0, powerUse = 2,
		cost = 100, costStep = 30, materials = 30, upgrade = { 400, 1200 }, upgradeMaterials = { 60, 160 },
		unlockPop = 0, buildable = true, order = 6, icon = "living", incidentWeight = 0.4,
	},
	Infirmary = {
		id = "Infirmary", name = "Medbay", category = "Medical",
		desc = "Treats the injured and makes medicine from clean water. Medics (MED) heal faster.",
		units = 3, maxModules = 3, stat = "MED", produces = "MedPatch", rate = { 1.2, 1.6, 2.1 },
		inputs = { Water = 2 }, amenities = { treat = 2 },
		storage = { MedPatch = { 4, 6, 8 } }, slots = 2, powerUse = 4,
		cost = 260, costStep = 80, materials = 80, upgrade = { 800, 2400 }, upgradeMaterials = { 120, 300 },
		unlockPop = 0, buildable = true, order = 7, icon = "medical", incidentWeight = 0.8,
	},
	Storage = {
		id = "Storage", name = "Storage Depot", category = "Survival",
		desc = "Racks, tanks and crates. Raises storage for every resource. A fire here destroys materials.",
		units = 3, maxModules = 3,
		storage = {
			Power = { 40, 60, 80 }, Food = { 50, 75, 100 }, Water = { 50, 75, 100 },
			Materials = { 150, 250, 400 }, MedPatch = { 4, 6, 8 },
		},
		slots = 0, powerUse = 0.8, cost = 200, costStep = 60, materials = 60, upgrade = { 600, 1800 }, upgradeMaterials = { 100, 250 },
		unlockPop = 0, buildable = true, order = 8, icon = "storage", incidentWeight = 0.6,
	},
	Workshop = {
		id = "Workshop", name = "Workshop", category = "Industry",
		desc = "Salvages scrap into building materials. Needs power and engineers (ENG).",
		units = 3, maxModules = 3, stat = "ENG", produces = "Materials", rate = { 10, 14, 18 },
		storage = { Materials = { 60, 100, 150 } }, slots = 2, powerUse = 3,
		cost = 150, costStep = 40, materials = 0, upgrade = { 500, 1500 }, upgradeMaterials = { 60, 160 },
		unlockPop = 0, buildable = true, order = 9, icon = "build", incidentWeight = 1, breakdown = 0.4,
	},
}

RoomDefinitions.Types = defs

function RoomDefinitions.get(id: string): RoomDef
	local d = defs[id]
	assert(d, "unknown room type " .. tostring(id))
	return d
end

function RoomDefinitions.buildable(): { RoomDef }
	local list = {}
	for _, d in defs do
		if d.buildable then
			table.insert(list, d)
		end
	end
	table.sort(list, function(a, b)
		return a.order < b.order
	end)
	return list
end

-- Total grid columns a room occupies.
function RoomDefinitions.width(id: string, modules: number): number
	return defs[id].units * modules
end

return RoomDefinitions
