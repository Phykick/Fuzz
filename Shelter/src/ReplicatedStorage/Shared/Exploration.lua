--!strict
-- Wasteland exploration definitions shared by server (simulation) and client (journal + scene).
local Exploration = {}

Exploration.FIRST_EVENT = 14 -- seconds after leaving the door
Exploration.EVENT_GAP = { 26, 52 } -- seconds between encounters
Exploration.TIER_SECONDS = 240 -- danger/loot tier rises every 4 minutes out
Exploration.RETURN_FRACTION = 0.2 -- trip home takes 20% of time spent out...
Exploration.RETURN_MIN = 15 -- ...but at least 15 s
Exploration.RETURN_MAX = 300 -- ...and at most 5 minutes
Exploration.MAX_EXPLORERS = 3
Exploration.MAX_MEDS = 5

-- weight grows with tier by `tierWeight` per tier
Exploration.Events = {
	Quiet = {
		weight = 12, tierWeight = -0.6, icon = "info", scene = nil,
		text = {
			"%s walked for hours past %s. Nothing but wind and dust.",
			"%s followed the dry riverbed near %s.",
			"%s watched the sun go copper over %s.",
			"%s found an old radio near %s. Just static.",
		},
	},
	SupplyCache = {
		weight = 18, tierWeight = 0, icon = "shop", scene = "WL_CACHE",
		text = { "%s spotted a supply drop half-buried near %s.", "%s cracked open a sealed cache at %s." },
	},
	AbandonedHouse = {
		weight = 16, tierWeight = 0, icon = "outfits", scene = "WL_RUIN_C",
		text = { "%s searched an abandoned house at %s.", "%s squeezed through the window of a collapsed home near %s." },
	},
	RuinedLab = {
		weight = 8, tierWeight = 0.4, icon = "health", scene = "WL_LAB",
		text = { "%s explored a ruined research lab outside %s.", "%s held their breath through the labs of %s." },
	},
	Checkpoint = {
		weight = 7, tierWeight = 0.5, icon = "weapons", scene = "WL_CHECKPOINT",
		text = { "%s slipped past an old military checkpoint at %s.", "%s traded shots with automated sentries near %s." },
	},
	Bunker = {
		weight = 3, tierWeight = 0.5, icon = "star", scene = "WL_HATCH",
		text = { "%s found a sealed bunker hatch under %s!", "%s pried open a forgotten bunker beneath %s." },
	},
	RaiderCamp = {
		weight = 10, tierWeight = 1.2, icon = "raid", scene = "WL_CAMP",
		text = { "%s stumbled into a raider camp at %s and fought their way out.", "Raiders ambushed %s near %s." },
	},
	Mutant = {
		weight = 14, tierWeight = 1.0, icon = "fire", scene = nil,
		text = { "Something burrowed up beneath %s at %s!", "%s fought off a pack of mutants near %s." },
	},
	Survivor = {
		weight = 5, tierWeight = 0, icon = "survivors", scene = nil,
		text = { "%s met a lone wanderer at %s.", "%s shared a campfire with a stranger near %s." },
	},
	Trader = {
		weight = 6, tierWeight = 0, icon = "bolts", scene = "WL_CART",
		text = { "%s haggled with a travelling trader at %s.", "%s bartered at a trader's cart outside %s." },
	},
	Return = { weight = 0, tierWeight = 0, icon = "assign", text = {} },
	Heal = { weight = 0, tierWeight = 0, icon = "health", text = {} },
	Death = { weight = 0, tierWeight = 0, icon = "raid", text = {} },
	Depart = { weight = 0, tierWeight = 0, icon = "assign", text = {} },
}

Exploration.Order = { "Quiet", "SupplyCache", "AbandonedHouse", "RuinedLab", "Checkpoint", "Bunker", "RaiderCamp", "Mutant", "Survivor", "Trader" }

Exploration.Places = {
	"the Rusted Mile", "Cinder Flats", "Old Kessler Farm", "Hollow Creek", "the Glass Dunes",
	"the Route 9 overpass", "Brightwater Mall", "the Ashfield rail yards", "Saint Orrin's Hospital",
	"the Radio Spire", "Copperhead Quarry", "the drowned suburbs", "Lantern Hill", "the Salt Pans",
}

function Exploration.pickEvent(rng: Random, tier: number): string
	local total = 0
	local weights = {}
	for _, k in Exploration.Order do
		local e = Exploration.Events[k]
		local w = math.max(0.5, e.weight + e.tierWeight * tier)
		weights[k] = w
		total += w
	end
	local pick = rng:NextNumber() * total
	for _, k in Exploration.Order do
		pick -= weights[k]
		if pick <= 0 then
			return k
		end
	end
	return "Quiet"
end

return Exploration
