--!strict
-- Resource registry: one entry per colony resource. HUD, storage caps, alerts and save templates
-- read from here, so adding a resource (Ammunition, Fuel, Chemicals...) is one new entry plus the
-- rooms that produce / consume it.
local Resources = {}

export type ResourceDef = {
	name: string,
	icon: string,
	base: number, -- storage capacity before Storage rooms / room tanks
	low: number, -- warn below this share of capacity
	critical: number, -- emergency below this share
	hud: boolean, -- shown as a top-bar meter
}

Resources.LIST = { "Power", "Water", "Food", "Materials", "MedPatch" }
Resources.CURRENCY = "Bolts"

Resources.Defs = {
	Power = { name = "Power", icon = "power", base = 100, low = 0.2, critical = 0.06, hud = true },
	Water = { name = "Water", icon = "water", base = 100, low = 0.2, critical = 0.08, hud = true },
	Food = { name = "Food", icon = "food", base = 100, low = 0.2, critical = 0.08, hud = true },
	Materials = { name = "Materials", icon = "build", base = 200, low = 0.1, critical = 0.03, hud = true },
	MedPatch = { name = "Medicine", icon = "health", base = 6, low = 0.2, critical = 0, hud = true },
} :: { [string]: ResourceDef }

return Resources
