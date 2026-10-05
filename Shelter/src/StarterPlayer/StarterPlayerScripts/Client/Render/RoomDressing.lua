--!strict
-- Per-room-type dressing layouts. Positions are module-local Roblox coords:
--   x: 0..18 along the module, y: height above floor top, z: depth (back wall -6, lane 0, front +4)
-- `rot` is yaw in degrees. `attach` spawns sub-assets at a marker of the parent asset.
-- `anim` names map to RoomBuilder animators. `light` adds a PointLight at a marker or offset.
-- `work` spots are where assigned survivors stand; `action` picks their animation.
local RoomDressing = {}

export type Prop = {
	asset: string,
	pos: { number },
	rot: number?,
	scale: number?,
	fx: { marker: string, kind: string }?,
	attach: { { asset: string, marker: string, anim: string?, speed: number? } }?,
	light: { marker: string?, offset: { number }?, color: string, range: number, brightness: number, anim: string? }?,
	anim: string?,
	speed: number?,
	tag: string?,
}

-- `spots` are errand seats by kind (eat, drink, sleep, treat); `y` lifts a spot (top bunk, bed).
export type WorkSpot = { x: number, z: number, y: number?, face: number?, action: string }

RoomDressing.Power = {
	module = {
		{ asset = "PWR_CONSOLE", pos = { 2.9, 0, -2.0 }, attach = { { asset = "PWR_BEACON", marker = "Beacon", anim = "beacon" } } },
		{
			asset = "PWR_TURBINE", pos = { 9.6, 0, -3.6 },
			attach = { { asset = "PWR_ROTOR", marker = "Rotor", anim = "spinZ", speed = 5 } },
			light = { marker = "Glow", color = "glow", range = 11, brightness = 1.6, anim = "hum" },
		},
		{ asset = "PWR_CAPACITOR", pos = { 15.4, 0, -3.5 }, light = { offset = { 0, 5.4, 1.2 }, color = "glow", range = 7, brightness = 0.9, anim = "hum" } },
	} :: { Prop },
	level = {
		[2] = {
			{ asset = "PWR_PANEL", pos = { 2.9, 5.4, -5.65 } },
			{ asset = "PWR_BEACON", pos = { 15.4, 8.0, -3.5 }, anim = "beacon" },
		},
		[3] = {
			{ asset = "PWR_TRIM", pos = { 9.6, 5.2, -2.95 }, anim = "pulse" },
			{ asset = "PWR_CABLETRAY", pos = { 9, 9.25, 2.0 } },
		},
	} :: { [number]: { Prop } },
	work = {
		{ x = 2.9, z = -0.5, face = 180, action = "UseComputer" },
		{ x = 6.0, z = -0.6, face = 180, action = "Repair" },
		{ x = 13.4, z = -0.4, face = 180, action = "Repair" },
	} :: { WorkSpot },
}

RoomDressing.Water = {
	module = {
		{ asset = "WTR_TANK", pos = { 3.6, 0, -3.8 }, light = { marker = "Water", color = "glow", range = 8, brightness = 1.1, anim = "hum" } },
		{ asset = "WTR_FILTER", pos = { 9.6, 0, -4.0 } },
		{ asset = "WTR_PUMP", pos = { 14.6, 0, -3.4 }, attach = { { asset = "WTR_VALVE", marker = "Wheel", anim = "spinZ", speed = 1.1 } } },
		{ asset = "WTR_PANEL", pos = { 9.6, 4.9, -5.65 } },
	} :: { Prop },
	level = {
		[2] = { { asset = "WTR_CHANNEL", pos = { 9, 0, -2.05 } } },
		[3] = { { asset = "WTR_UVBANK", pos = { 14.6, 5.4, -5.6 }, anim = "pulse" } },
	} :: { [number]: { Prop } },
	work = {
		{ x = 5.9, z = -0.4, face = 180, action = "Repair" },
		{ x = 9.6, z = -0.7, face = 180, action = "UseComputer" },
		{ x = 12.6, z = -0.3, face = 180, action = "Repair" },
	} :: { WorkSpot },
}

RoomDressing.Food = {
	module = {
		{ asset = "FOOD_RACK", pos = { 3.3, 0, -4.4 } },
		{ asset = "FOOD_PLANTER", pos = { 9.3, 0, -3.6 }, attach = { { asset = "FOOD_CROPS", marker = "Crops", anim = "sway" } } },
		{ asset = "FOOD_LAMP", pos = { 9.3, 8.6, -3.6 }, light = { marker = "Light", color = "glow", range = 11, brightness = 1.3, anim = "hum" } },
		{ asset = "FOOD_BENCH", pos = { 15.0, 0, -4.2 } },
	} :: { Prop },
	level = {
		[2] = { { asset = "FOOD_SPRINKLER", pos = { 9, 9.5, -2.4 } } },
		[3] = { { asset = "FOOD_NUTRIENT", pos = { 12.5, 0, -5.0 }, anim = "pulse" } },
	} :: { [number]: { Prop } },
	work = {
		{ x = 3.3, z = -0.7, face = 180, action = "Farm" },
		{ x = 9.3, z = -0.9, face = 180, action = "Farm" },
		{ x = 15.0, z = -0.7, face = 180, action = "Work" },
	} :: { WorkSpot },
}

RoomDressing.Living = {
	-- two full-size bunks per module (sized for the v2 survivors), a sofa corner between them
	module = {
		{ asset = "LQ_BUNK", pos = { 3.1, 0, -4.3 }, scale = 1.5 },
		{ asset = "LQ_PLANT", pos = { 6.7, 0, -4.9 } },
		{ asset = "LQ_POSTER", pos = { 6.7, 4.6, -5.68 } },
		{ asset = "LQ_SOFA", pos = { 9.1, 0, -4.4 } },
		{ asset = "LQ_RUG", pos = { 9.1, 0, -0.6 } },
		{ asset = "LQ_LAMP", pos = { 11.6, 0, -5.0 }, light = { marker = "Light", color = "glow", range = 11, brightness = 1.0 } },
		{ asset = "LQ_BUNK", pos = { 14.9, 0, -4.3 }, scale = 1.5 },
	} :: { Prop },
	level = {
		[2] = { { asset = "LQ_TABLE", pos = { 10.9, 0, -1.9 } } },
		[3] = { { asset = "LQ_TV", pos = { 10.9, 1.86, -2.05 } }, { asset = "LQ_DRESSER", pos = { 17.4, 0, -1.8 }, rot = -90 } },
	} :: { [number]: { Prop } },
	work = { -- unwinding spots
		{ x = 8.1, z = -3.3, face = 180, action = "Sit" },
		{ x = 10.1, z = -3.3, face = 180, action = "Sit" },
		{ x = 7.0, z = 0.6, face = 180, action = "Talk" },
		{ x = 11.4, z = 0.4, face = 180, action = "Talk" },
		{ x = 9.1, z = 1.2, face = 180, action = "Idle" },
	} :: { WorkSpot },
	spots = {
		sleep = {
			{ x = 3.1, z = -4.3, y = 1.55, face = 0, action = "Sleep" },
			{ x = 14.9, z = -4.3, y = 1.55, face = 0, action = "Sleep" },
			{ x = 3.1, z = -4.3, y = 4.85, face = 0, action = "Sleep" },
			{ x = 14.9, z = -4.3, y = 4.85, face = 0, action = "Sleep" },
			{ x = 9.1, z = -0.4, y = 0, face = 0, action = "Sleep" }, -- on the rug when the bunks are full
		},
	},
}

RoomDressing.Entrance = {
	module = {
		{ asset = "ENTR_FRAME", pos = { 0, -1, 0 }, tag = "Frame" },
		{ asset = "ENTR_DOOR", pos = { 6.5, 4.6, -3.9 }, tag = "Door" },
		{ asset = "PROP_LOCKER", pos = { 15.8, 0, -5.0 } },
		{ asset = "PROP_SANDBAGS", pos = { 13.2, 0, -2.4 } },
		{ asset = "PROP_EXTINGUISHER", pos = { 11.4, 1.0, -5.65 } },
		{ asset = "PROP_CRATE", pos = { 16.2, 0, -2.2 }, rot = 12 },
	} :: { Prop },
	level = {} :: { [number]: { Prop } },
	work = {
		{ x = 12.4, z = -0.6, face = 90, action = "Guard" },
		{ x = 14.6, z = 0.4, face = 90, action = "Guard" },
	} :: { WorkSpot },
}

RoomDressing.Cafeteria = {
	module = {
		{ asset = "CAF_FRIDGE", pos = { 1.3, 0, -4.6 } },
		{ asset = "CAF_COUNTER", pos = { 5.0, 0, -4.6 }, fx = { marker = "Steam", kind = "steam" } },
		{ asset = "CAF_HOOD", pos = { 3.7, 7.6, -4.7 }, light = { offset = { 0, -0.2, 0.6 }, color = "light", range = 9, brightness = 0.9 } },
		{ asset = "CAF_MENU", pos = { 11.6, 5.4, -5.62 } },
		{ asset = "CAF_TABLE", pos = { 9.2, 0, -1.4 } },
		{ asset = "CAF_TABLE", pos = { 14.0, 0, -1.4 } },
		{ asset = "CAF_DISPENSER", pos = { 17.1, 0, -4.7 }, light = { offset = { 0, 3.3, 0.6 }, color = "glow", range = 5, brightness = 0.6, anim = "hum" } },
	} :: { Prop },
	level = {
		[2] = { { asset = "PROP_CRATE", pos = { 1.4, 0, -1.4 }, rot = 8 } },
		[3] = { { asset = "LQ_PLANT", pos = { 16.8, 0, -1.2 } } },
	} :: { [number]: { Prop } },
	work = { -- cooks at the stove and counter
		{ x = 3.7, z = -2.7, face = 180, action = "Work" },
		{ x = 6.3, z = -2.7, face = 180, action = "Work" },
	} :: { WorkSpot },
	spots = {
		eat = { -- diners face each other across the tables (profile to the camera)
			{ x = 7.6, z = -1.4, face = 90, action = "SitEat" },
			{ x = 10.8, z = -1.4, face = -90, action = "SitEat" },
			{ x = 12.4, z = -1.4, face = 90, action = "SitEat" },
			{ x = 15.6, z = -1.4, face = -90, action = "SitEat" },
		},
		drink = {
			{ x = 17.1, z = -3.0, face = 180, action = "Drink" },
			{ x = 16.0, z = -2.4, face = 160, action = "Drink" },
			{ x = 17.4, z = -1.6, face = 200, action = "Drink" },
		},
	},
}

RoomDressing.Infirmary = {
	module = {
		{ asset = "MED_MONITOR", pos = { 1.1, 0, -4.0 }, light = { marker = "Screen", color = "glow", range = 6, brightness = 0.8, anim = "hum" } },
		{ asset = "MED_BED", pos = { 4.7, 0, -3.8 } },
		{ asset = "MED_IV", pos = { 8.0, 0, -4.8 } },
		{ asset = "MED_CABINET", pos = { 9.6, 4.6, -5.2 } },
		{ asset = "MED_CURTAIN", pos = { 9.6, 0, -3.2 } },
		{ asset = "MED_BED", pos = { 13.5, 0, -3.8 } },
		{ asset = "MED_MONITOR", pos = { 17.1, 0, -4.0 }, light = { marker = "Screen", color = "glow", range = 6, brightness = 0.8, anim = "hum" } },
	} :: { Prop },
	level = {
		[2] = { { asset = "MED_IV", pos = { 16.6, 0, -2.0 } } },
		[3] = { { asset = "PROP_LOCKER", pos = { 11.2, 0, -5.0 } } },
	} :: { [number]: { Prop } },
	work = {
		{ x = 1.8, z = -1.8, face = 180, action = "UseComputer" },
		{ x = 11.2, z = -1.2, face = 230, action = "Work" },
	} :: { WorkSpot },
	spots = {
		treat = {
			{ x = 4.7, z = -3.8, y = 2.1, face = 0, action = "Sleep" },
			{ x = 13.5, z = -3.8, y = 2.1, face = 0, action = "Sleep" },
		},
	},
}

RoomDressing.Storage = {
	module = {
		{ asset = "STO_SHELF", pos = { 3.0, 0, -4.8 } },
		{ asset = "STO_TANKS", pos = { 8.3, 0, -4.3 } },
		{ asset = "STO_CRATES", pos = { 12.4, 0, -4.0 } },
		{ asset = "STO_PALLET", pos = { 16.0, 0, -2.2 } },
	} :: { Prop },
	level = {
		[2] = { { asset = "PROP_BARREL", pos = { 5.7, 0, -1.8 } } },
		[3] = { { asset = "PROP_EXTINGUISHER", pos = { 6.0, 1.0, -5.65 } } },
	} :: { [number]: { Prop } },
	work = {} :: { WorkSpot },
}

RoomDressing.Workshop = {
	module = {
		{ asset = "WRK_TOOLWALL", pos = { 3.8, 4.8, -5.62 } },
		{ asset = "WRK_BENCH", pos = { 3.8, 0, -4.2 }, fx = { marker = "Spark", kind = "sparks" } },
		{ asset = "WRK_PRESS", pos = { 10.0, 0, -4.0 }, attach = { { asset = "WRK_WHEEL", marker = "Wheel", anim = "spinZ", speed = 9 } } },
		{ asset = "WRK_SCRAP", pos = { 15.0, 0, -3.2 } },
	} :: { Prop },
	level = {
		[2] = { { asset = "PROP_TOOLBOX", pos = { 7.0, 0, -1.6 }, rot = 15 } },
		[3] = { { asset = "PROP_LOCKER", pos = { 17.2, 0, -5.0 } } },
	} :: { [number]: { Prop } },
	work = {
		{ x = 3.8, z = -2.3, face = 180, action = "Repair" },
		{ x = 10.0, z = -2.2, face = 180, action = "Work" },
		{ x = 13.6, z = -1.0, face = 150, action = "Repair" },
	} :: { WorkSpot },
}

return RoomDressing
