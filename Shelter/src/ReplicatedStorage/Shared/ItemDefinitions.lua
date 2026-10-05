--!strict
-- Original post-apocalyptic weapons and outfits.
local ItemDefinitions = {}

ItemDefinitions.Rarity = {
	Common = { order = 1, color = Color3.fromHex("C9CED6"), weight = 60 },
	Uncommon = { order = 2, color = Color3.fromHex("7BE07A"), weight = 25 },
	Rare = { order = 3, color = Color3.fromHex("43A6F2"), weight = 10 },
	Epic = { order = 4, color = Color3.fromHex("B07BFF"), weight = 4 },
	Legendary = { order = 5, color = Color3.fromHex("FFB23E"), weight = 1 },
}

export type Weapon = {
	id: string, kind: "Weapon", name: string, rarity: string, damage: number, fireRate: number,
	range: number, crit: number, durability: number, mesh: string, sound: string?,
}
export type Outfit = {
	id: string, kind: "Outfit", name: string, rarity: string, stats: { [string]: number },
	-- wardrobe style (Shared/CharacterStyles) worn with this outfit + optional colour-slot overrides
	style: string, tints: { [string]: string }?,
}

ItemDefinitions.Weapons = {
	Fists = { id = "Fists", kind = "Weapon", name = "Bare Knuckles", rarity = "Common", damage = 2, fireRate = 1.1, range = 2.5, crit = 0.02, durability = 0, mesh = "" },
	ScrapPistol = { id = "ScrapPistol", kind = "Weapon", name = "Scrap Pistol", rarity = "Common", damage = 4, fireRate = 1.0, range = 30, crit = 0.05, durability = 120, mesh = "WPN_SCRAP_PISTOL" },
	ScrapRevolver = { id = "ScrapRevolver", kind = "Weapon", name = "Scrap Revolver", rarity = "Uncommon", damage = 7, fireRate = 0.7, range = 30, crit = 0.1, durability = 140, mesh = "WPN_SCRAP_PISTOL" },
	PipeRifle = { id = "PipeRifle", kind = "Weapon", name = "Pipe Rifle", rarity = "Uncommon", damage = 6, fireRate = 0.9, range = 45, crit = 0.08, durability = 160, mesh = "WPN_PIPE_RIFLE" },
	ImprovisedShotgun = { id = "ImprovisedShotgun", kind = "Weapon", name = "Improvised Shotgun", rarity = "Rare", damage = 11, fireRate = 0.55, range = 14, crit = 0.06, durability = 150, mesh = "WPN_SHOTGUN" },
	IndustrialSMG = { id = "IndustrialSMG", kind = "Weapon", name = "Industrial SMG", rarity = "Rare", damage = 3, fireRate = 3.2, range = 25, crit = 0.04, durability = 200, mesh = "WPN_PIPE_RIFLE" },
	MakeshiftRifle = { id = "MakeshiftRifle", kind = "Weapon", name = "Makeshift Marksman", rarity = "Epic", damage = 15, fireRate = 0.5, range = 60, crit = 0.18, durability = 180, mesh = "WPN_PIPE_RIFLE" },
	EnergyCarbine = { id = "EnergyCarbine", kind = "Weapon", name = "Arc Carbine", rarity = "Legendary", damage = 12, fireRate = 1.4, range = 50, crit = 0.12, durability = 260, mesh = "WPN_PIPE_RIFLE" },
} :: { [string]: Weapon }

ItemDefinitions.Outfits = {
	UtilitySuit = { id = "UtilitySuit", kind = "Outfit", name = "Utility Suit", rarity = "Common", stats = {}, style = "Technician" },
	EngineerSuit = { id = "EngineerSuit", kind = "Outfit", name = "Engineer Coverall", rarity = "Uncommon", stats = { ENG = 2 }, style = "Engineer" },
	SecurityUniform = { id = "SecurityUniform", kind = "Outfit", name = "Security Uniform", rarity = "Uncommon", stats = { CMB = 2 }, style = "Security" },
	MedicalScrubs = { id = "MedicalScrubs", kind = "Outfit", name = "Medical Scrubs", rarity = "Uncommon", stats = { MED = 2 }, style = "Medic" },
	ScavengerGear = { id = "ScavengerGear", kind = "Outfit", name = "Scavenger Leathers", rarity = "Rare", stats = { SCV = 2, FIT = 1 }, style = "Scavenger" },
	HazmatSuit = { id = "HazmatSuit", kind = "Outfit", name = "Hazmat Suit", rarity = "Rare", stats = { FIT = 2, MEC = 1 }, style = "Mechanic",
		tints = { suit = "E8C640", sleeve = "E8C640", pants = "E8C640", accent = "2A2A2A", pad = "2A2A2A" } },
	HeavyArmor = { id = "HeavyArmor", kind = "Outfit", name = "Scrapplate Armor", rarity = "Epic", stats = { CMB = 2, FIT = 3 }, style = "Soldier",
		tints = { vest = "5A5048", hat = "6E5A44" } },
	ExplorerOutfit = { id = "ExplorerOutfit", kind = "Outfit", name = "Explorer Kit", rarity = "Epic", stats = { SCV = 2, FIT = 2, CMB = 1 }, style = "Trader",
		tints = { coat = "6A7A3A", sleeve = "6A7A3A", hat = "A57C46", accent = "D9B26F" } },
} :: { [string]: Outfit }

function ItemDefinitions.get(id: string): any
	return ItemDefinitions.Weapons[id] or ItemDefinitions.Outfits[id]
end

-- Weighted rarity roll; luck shifts weight towards rarer results.
function ItemDefinitions.rollRarity(rng: Random, luck: number): string
	local total, weights = 0, {}
	for name, r in ItemDefinitions.Rarity do
		local w = r.weight * (1 + (r.order - 1) * luck * 0.06)
		weights[name] = w
		total += w
	end
	local pick = rng:NextNumber() * total
	for name, w in weights do
		pick -= w
		if pick <= 0 then
			return name
		end
	end
	return "Common"
end

function ItemDefinitions.randomOf(kind: string, rarity: string, rng: Random): string?
	local pool = {}
	local src = if kind == "Weapon" then ItemDefinitions.Weapons else ItemDefinitions.Outfits
	for id, def in src :: any do
		if def.rarity == rarity and id ~= "Fists" then
			table.insert(pool, id)
		end
	end
	if #pool == 0 then
		return nil
	end
	table.sort(pool)
	return pool[rng:NextInteger(1, #pool)]
end

return ItemDefinitions
