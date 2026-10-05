--!strict
-- Walk + elevator routing through the shelter. Deterministic so the server can compute
-- arrival times and the client can animate the identical route.
local Config = require(script.Parent.Config)
local Grid = require(script.Parent.Grid)

local Pathing = {}

export type Waypoint = { x: number, row: number, mode: string } -- mode: "walk" | "lift"
export type Path = { points: { Waypoint }, duration: number }

local UNIT = Config.UNIT

-- Contiguous horizontal runs of built cells per row: row -> list of {c0, c1}
local function runs(rooms: { [string]: Grid.Room })
	local byRow: { [number]: { number } } = {}
	for _, r in rooms do
		local list = byRow[r.row] or {}
		byRow[r.row] = list
		for c = r.col, r.col + Grid.width(r) - 1 do
			table.insert(list, c)
		end
	end
	local out = {}
	for row, cols in byRow do
		table.sort(cols)
		local segs = {}
		local s, prev = cols[1], cols[1]
		for i = 2, #cols do
			if cols[i] ~= prev + 1 then
				table.insert(segs, { s, prev })
				s = cols[i]
			end
			prev = cols[i]
		end
		table.insert(segs, { s, prev })
		out[row] = segs
	end
	return out
end

local function segmentOf(segs, row: number, x: number): number?
	local list = segs[row]
	if not list then
		return nil
	end
	local c = math.floor(x / UNIT)
	for i, s in list do
		if c >= s[1] and c <= s[2] then
			return i
		end
	end
	return nil
end

function Pathing.duration(points: { Waypoint }, fromX: number, fromRow: number): number
	local t, x, row = 0, fromX, fromRow
	for _, p in points do
		if p.mode == "lift" then
			t += math.abs(p.row - row) * Config.ROW_HEIGHT / Config.ELEVATOR_SPEED + Config.ELEVATOR_BOARD_TIME
		else
			t += math.abs(p.x - x) / Config.WALK_SPEED
		end
		x, row = p.x, p.row
	end
	return t
end

-- Shortest route from (x0,row0) to (x1,row1). Returns nil if unreachable.
function Pathing.find(rooms: { [string]: Grid.Room }, x0: number, row0: number, x1: number, row1: number): Path?
	local segs = runs(rooms)
	local s0, s1 = segmentOf(segs, row0, x0), segmentOf(segs, row1, x1)
	if not s0 or not s1 then
		return nil
	end
	if row0 == row1 and s0 == s1 then
		local pts = { { x = x1, row = row1, mode = "walk" } }
		return { points = pts, duration = Pathing.duration(pts, x0, row0) }
	end
	-- Graph over elevator cells.
	local elev: { [number]: { col: number, row: number } } = {}
	local nodes = {}
	for _, r in rooms do
		if r.type == "Elevator" then
			local k = r.row * 1000 + r.col
			elev[k] = { col = r.col, row = r.row }
			table.insert(nodes, k)
		end
	end
	local WALK, LIFT = Config.WALK_SPEED, Config.ELEVATOR_SPEED
	local dist: { [number]: number } = {}
	local prev: { [number]: number } = {}
	local done: { [number]: boolean } = {}
	local START, GOAL = -1, -2
	dist[START] = 0
	local function ex(k)
		return (elev[k].col + 0.5) * UNIT
	end
	local function neighbours(k)
		local out = {}
		local function sameSeg(rowA, xA, rowB, xB)
			return rowA == rowB and segmentOf(segs, rowA, xA) == segmentOf(segs, rowB, xB)
		end
		local kx, krow
		if k == START then
			kx, krow = x0, row0
		else
			kx, krow = ex(k), elev[k].row
		end
		for _, n in nodes do
			if n ~= k then
				local e = elev[n]
				local nx = ex(n)
				if sameSeg(krow, kx, e.row, nx) then
					table.insert(out, { n, math.abs(nx - kx) / WALK })
				elseif k ~= START and e.col == elev[k].col and math.abs(e.row - krow) == 1 then
					table.insert(out, { n, Config.ROW_HEIGHT / LIFT })
				end
			end
		end
		if k ~= START and sameSeg(krow, kx, row1, x1) then
			table.insert(out, { GOAL, math.abs(x1 - kx) / WALK + Config.ELEVATOR_BOARD_TIME })
		end
		return out
	end
	while true do
		local best, bestD = nil, math.huge
		for k, d in dist do
			if not done[k] and d < bestD then
				best, bestD = k, d
			end
		end
		if best == nil or best == GOAL then
			break
		end
		done[best] = true
		for _, e in neighbours(best) do
			local n, w = e[1], e[2]
			local nd = bestD + w
			if nd < (dist[n] or math.huge) then
				dist[n] = nd
				prev[n] = best
			end
		end
	end
	if not dist[GOAL] then
		return nil
	end
	-- Rebuild chain of nodes
	local chain = {}
	local cur = prev[GOAL]
	while cur and cur ~= START do
		table.insert(chain, 1, cur)
		cur = prev[cur]
	end
	local pts: { Waypoint } = {}
	local lastRow = row0
	for _, k in chain do
		local e = elev[k]
		local x = ex(k)
		if e.row == lastRow then
			table.insert(pts, { x = x, row = e.row, mode = "walk" })
		else
			-- vertical hop: collapse consecutive lift moves
			local last = pts[#pts]
			if last and last.mode == "lift" then
				last.row = e.row
			else
				table.insert(pts, { x = x, row = e.row, mode = "lift" })
			end
		end
		lastRow = e.row
	end
	table.insert(pts, { x = x1, row = row1, mode = "walk" })
	return { points = pts, duration = Pathing.duration(pts, x0, row0) }
end

-- Position along a path at time t (seconds since start). Returns x, row (fractional), mode.
function Pathing.sample(points: { Waypoint }, x0: number, row0: number, t: number): (number, number, string, number)
	local x, row = x0, row0
	for _, p in points do
		local seg
		if p.mode == "lift" then
			seg = math.abs(p.row - row) * Config.ROW_HEIGHT / Config.ELEVATOR_SPEED + Config.ELEVATOR_BOARD_TIME
		else
			seg = math.abs(p.x - x) / Config.WALK_SPEED
		end
		if t <= seg and seg > 0 then
			local a = t / seg
			if p.mode == "lift" then
				local board = Config.ELEVATOR_BOARD_TIME / seg
				local k = math.clamp((a - board * 0.5) / (1 - board), 0, 1)
				k = k * k * (3 - 2 * k)
				return x, row + (p.row - row) * k, "lift", (if p.row > row then 1 else -1)
			end
			return x + (p.x - x) * a, row, "walk", (if p.x >= x then 1 else -1)
		end
		t -= seg
		x, row = p.x, p.row
	end
	return x, row, "idle", 0
end

return Pathing
