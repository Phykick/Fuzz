--!strict
-- The pressure curve: how hard the wasteland pushes back. 0 = a fresh shelter, 1 = a big, old one.
-- Pressure grows with play time (not offline time) and population. Every escalating number in the
-- simulation reads from here, so the whole curve is tuned in one place.
local Config = require(script.Parent.Config)

local Difficulty = {}

function Difficulty.pressure(playSeconds: number, population: number): number
	local age = math.clamp((playSeconds / 60) / Config.PRESSURE_MINUTES, 0, 1)
	local size = math.clamp((population - 5) / (Config.PRESSURE_POP - 5), 0, 1)
	return math.clamp(0.55 * age + 0.45 * size, 0, 1)
end

-- Economy
function Difficulty.consumption(p: number): number -- food + water per survivor
	return 1 + 0.35 * p
end

function Difficulty.powerUse(p: number): number
	return 1 + 0.35 * p
end

-- Incidents
function Difficulty.incidentChance(p: number): number -- per minute
	return Config.INCIDENT_CHANCE_PER_MIN * (1 + 1.5 * p)
end

function Difficulty.incidentGap(p: number): number -- minimum seconds between incidents
	return Config.INCIDENT_MIN_GAP * (1 - 0.5 * p)
end

function Difficulty.infestationShare(p: number): number -- share of incidents that are creatures
	return 0.25 + 0.35 * p
end

function Difficulty.creatureStrength(p: number): number
	return 1 + 0.9 * p
end

-- Raids
function Difficulty.raidDelay(rng: Random, p: number): number
	return rng:NextNumber(Config.RAID_INTERVAL[1], Config.RAID_INTERVAL[2]) * (1 - 0.4 * p)
end

function Difficulty.raidSize(population: number, p: number): number
	return math.clamp(2 + math.floor(population / 6) + math.floor(p * 3), 2, 8)
end

function Difficulty.raiderStrength(p: number): number -- raider health and damage
	return 1 + 0.8 * p
end

Difficulty.LABELS = { "CALM", "UNEASY", "DANGEROUS", "DESPERATE" }

function Difficulty.label(p: number): (string, number)
	local tier = math.clamp(math.floor(p * 4) + 1, 1, 4)
	return Difficulty.LABELS[tier], tier
end

return Difficulty
