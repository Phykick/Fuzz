--!strict
-- Single source for colours (see docs/02_style_guide.md).
local Theme = {}

local hex = Color3.fromHex

-- Tint slots consumed by Blender meshes exported with "<mat>|<slot>" materials.
Theme.Rooms = {
	Power = {
		wall = hex("2F5E5C"), wall2 = hex("22403F"), floor = hex("4A4E52"), accent = hex("E8A33A"),
		glow = hex("6EF3FF"), light = hex("DDF6FF"), lightColor = hex("CFEFFF"),
	},
	Water = {
		wall = hex("3C5470"), wall2 = hex("2B3C52"), floor = hex("3E4A55"), accent = hex("D9D2C0"),
		glow = hex("49D2FF"), light = hex("DDF0FF"), lightColor = hex("CFE6FF"),
	},
	Food = {
		wall = hex("56663B"), wall2 = hex("3E4A2B"), floor = hex("5A4632"), accent = hex("E0C341"),
		glow = hex("FF5FD2"), light = hex("FFE9C9"), lightColor = hex("FFE0C0"),
	},
	Living = {
		wall = hex("C9B48A"), wall2 = hex("8C6E4C"), floor = hex("7A5638"), accent = hex("B5432F"),
		glow = hex("FFD9A0"), light = hex("FFE7C2"), lightColor = hex("FFD3A0"),
	},
	Entrance = {
		wall = hex("4A4E54"), wall2 = hex("33373C"), floor = hex("44484D"), accent = hex("F2B630"),
		glow = hex("FF6A3D"), light = hex("FFF1DD"), lightColor = hex("FFE2C0"),
	},
	Elevator = {
		wall = hex("3A3F45"), wall2 = hex("24282C"), floor = hex("2A2D31"), accent = hex("C4572A"),
		glow = hex("FF9B4A"), light = hex("FFE2C0"), lightColor = hex("FFCB8A"),
	},
	Cafeteria = {
		wall = hex("B8643A"), wall2 = hex("7E4428"), floor = hex("6B5A4A"), accent = hex("F2C12E"),
		glow = hex("FFC86E"), light = hex("FFF0D6"), lightColor = hex("FFE4BC"),
	},
	Medbay = {
		wall = hex("D8E2E0"), wall2 = hex("8FA6A4"), floor = hex("B9C4C4"), accent = hex("2E9E5A"),
		glow = hex("7CF2C0"), light = hex("F2FFFB"), lightColor = hex("E6FFF7"),
	},
	Storage = {
		wall = hex("5E5A4E"), wall2 = hex("3F3C34"), floor = hex("4C4A44"), accent = hex("D8A23A"),
		glow = hex("FFD27A"), light = hex("FFF1DD"), lightColor = hex("FFE6C4"),
	},
	Workshop = {
		wall = hex("4E5A64"), wall2 = hex("343D45"), floor = hex("40444A"), accent = hex("E8761E"),
		glow = hex("FF9B4A"), light = hex("FFF1DD"), lightColor = hex("FFE2C0"),
	},
	Default = {
		wall = hex("5A6068"), wall2 = hex("3E434A"), floor = hex("44484D"), accent = hex("E8A33A"),
		glow = hex("FFD54A"), light = hex("FFF1DD"), lightColor = hex("FFE2C0"),
	},
}

Theme.UI = {
	panel = hex("1C2026"),
	panelInner = hex("262B33"),
	border = hex("3A414C"),
	rivet = hex("59616E"),
	accent = hex("FFB23E"),
	accentDark = hex("C77A12"),
	text = hex("F3EAD7"),
	textMuted = hex("A9A291"),
	happy = hex("7BE07A"),
	danger = hex("FF4D3D"),
	health = hex("E2483B"),
	xp = hex("9C7BFF"),
	good = hex("7BE07A"),
	shadow = hex("0B0C0E"),
}

Theme.Resource = {
	Power = hex("FFD54A"),
	Food = hex("FF8A3D"),
	Water = hex("43C6F2"),
	Bolts = hex("D8B26A"),
	Scrap = hex("A3A9B0"),
	Materials = hex("C9A27A"),
	MedPatch = hex("FF6B6B"),
}

Theme.SkinTones = { "F6D7C3", "EAC09E", "D8A47F", "B97A57", "8D5524", "5E3A22", "3F2A1E" }
Theme.HairColors = { "1F1A17", "3B2A20", "6A4428", "A0662F", "D9B26F", "B9B5AE", "8E2F24", "2F3A55" }

function Theme.room(roomType: string)
	return Theme.Rooms[roomType] or Theme.Rooms.Default
end

return Theme
