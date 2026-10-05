--!strict
-- Room-grid rules shared by server (authority) and client (build previews).
-- A room occupies columns [col, col + units*modules - 1] on one row.
local Config = require(script.Parent.Config)
local RoomDefinitions = require(script.Parent.RoomDefinitions)

local Grid = {}

export type Room = {
	id: string,
	type: string,
	col: number,
	row: number,
	modules: number,
	level: number,
	assigned: { string },
	[string]: any,
}

local function key(col: number, row: number): number
	return row * 1000 + col
end

function Grid.width(room: Room): number
	return RoomDefinitions.Types[room.type].units * room.modules
end

function Grid.occupancy(rooms: { [string]: Room }): { [number]: string }
	local occ = {}
	for id, r in rooms do
		for c = r.col, r.col + Grid.width(r) - 1 do
			occ[key(c, r.row)] = id
		end
	end
	return occ
end

function Grid.at(occ: { [number]: string }, col: number, row: number): string?
	return occ[key(col, row)]
end

function Grid.canPlace(rooms: { [string]: Room }, typeId: string, col: number, row: number, occ: { [number]: string }?): (boolean, string?)
	local def = RoomDefinitions.Types[typeId]
	if not def then
		return false, "Unknown room"
	end
	local w = def.units
	if col < 0 or row < 0 or col + w > Config.GRID_COLS or row >= Config.GRID_ROWS then
		return false, "Outside the excavation zone"
	end
	occ = occ or Grid.occupancy(rooms)
	for c = col, col + w - 1 do
		if occ[key(c, row)] then
			return false, "Space is occupied"
		end
	end
	local left = occ[key(col - 1, row)]
	local right = occ[key(col + w, row)]
	if left or right then
		return true
	end
	if typeId == "Elevator" then
		local above = occ[key(col, row - 1)]
		local below = occ[key(col, row + 1)]
		if (above and rooms[above].type == "Elevator") or (below and rooms[below].type == "Elevator") then
			return true
		end
		return false, "Elevators must connect to a room or another elevator"
	end
	return false, "Rooms must connect to an existing room or elevator"
end

-- Candidate build positions (only spots adjacent to existing structure), used for build-mode slots.
function Grid.validSlots(rooms: { [string]: Room }, typeId: string): { { col: number, row: number } }
	local def = RoomDefinitions.Types[typeId]
	local occ = Grid.occupancy(rooms)
	local seen, out = {}, {}
	local function try(col, row)
		local k = key(col, row)
		if seen[k] then
			return
		end
		seen[k] = true
		if Grid.canPlace(rooms, typeId, col, row, occ) then
			table.insert(out, { col = col, row = row })
		end
	end
	for _, r in rooms do
		local w = Grid.width(r)
		try(r.col + w, r.row)
		try(r.col - def.units, r.row)
		if typeId == "Elevator" and r.type == "Elevator" then
			try(r.col, r.row + 1)
			try(r.col, r.row - 1)
		end
	end
	table.sort(out, function(a, b)
		return if a.row == b.row then a.col < b.col else a.row < b.row
	end)
	return out
end

-- Merge a freshly placed single-module room with compatible neighbours (same type & level).
-- Returns the surviving room id and a list of removed room ids.
function Grid.merge(rooms: { [string]: Room }, newId: string): (string, { string })
	local new = rooms[newId]
	local def = RoomDefinitions.Types[new.type]
	if def.maxModules <= 1 then
		return newId, {}
	end
	local occ = Grid.occupancy(rooms)
	local function compatible(id: string?): Room?
		if not id or id == newId then
			return nil
		end
		local r = rooms[id]
		if r.type == new.type and r.level == new.level and not r.incident then
			return r
		end
		return nil
	end
	local L = compatible(occ[key(new.col - 1, new.row)])
	local R = compatible(occ[key(new.col + Grid.width(new), new.row)])
	local removed = {}
	if L and R and L.modules + new.modules + R.modules <= def.maxModules then
		L.modules += new.modules + R.modules
		for _, d in R.assigned do
			table.insert(L.assigned, d)
		end
		for _, d in new.assigned do
			table.insert(L.assigned, d)
		end
		rooms[newId] = nil
		rooms[R.id] = nil
		table.insert(removed, newId)
		table.insert(removed, R.id)
		return L.id, removed
	elseif L and L.modules + new.modules <= def.maxModules then
		L.modules += new.modules
		rooms[newId] = nil
		table.insert(removed, newId)
		return L.id, removed
	elseif R and R.modules + new.modules <= def.maxModules then
		R.col = new.col
		R.modules += new.modules
		rooms[newId] = nil
		table.insert(removed, newId)
		return R.id, removed
	end
	return newId, removed
end

-- World-space helpers ----------------------------------------------------------
function Grid.roomOrigin(room: Room): CFrame
	return CFrame.new(room.col * Config.UNIT, -room.row * Config.ROW_HEIGHT, 0)
end

function Grid.roomCenterX(room: Room): number
	return (room.col + Grid.width(room) / 2) * Config.UNIT
end

function Grid.floorY(row: number): number
	return -row * Config.ROW_HEIGHT + Config.FLOOR_Y
end

function Grid.bounds(rooms: { [string]: Room }): (number, number, number, number)
	local minC, maxC, minR, maxR = math.huge, -math.huge, math.huge, -math.huge
	for _, r in rooms do
		minC = math.min(minC, r.col)
		maxC = math.max(maxC, r.col + Grid.width(r))
		minR = math.min(minR, r.row)
		maxR = math.max(maxR, r.row)
	end
	if minC == math.huge then
		return 0, Config.GRID_COLS, 0, 2
	end
	return minC, maxC, minR, maxR
end

return Grid
