--!strict
-- Renders the shelter from replicated state: rooms (RoomBuilder), elevators + cars, the blast
-- door, bedrock tiles around the built area, and a backdrop. Animates only what is on screen.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Grid = require(ReplicatedStorage.Shared.Grid)
local Theme = require(ReplicatedStorage.Shared.Theme)

local Render = script.Parent.Parent:WaitForChild("Render")
local MeshFactory = require(Render.MeshFactory)
local RoomBuilder = require(Render.RoomBuilder)

local VaultRenderer = {}
local C: any

type Visual = {
	key: string,
	room: any,
	model: Model,
	built: any?,
	hitbox: BasePart,
	minX: number,
	maxX: number,
	minY: number,
	maxY: number,
	lights: { PointLight },
	animators: { (number, number) -> () },
}

local visuals: { [string]: Visual } = {}
local rockTiles: { [string]: Model } = {}
local cars: { [string]: { model: Model, col: number, y: number, target: number, moving: boolean } } = {}
local world: Folder
local roomsFolder: Folder
local rockFolder: Folder
local selection: SelectionBox
local doorOpen = false
local doorModel: Model? = nil

local UNIT, ROW = Config.UNIT, Config.ROW_HEIGHT

local function keyOf(r): string
	return string.format("%s|%d|%d|%d|%d", r.type, r.col, r.row, r.modules, r.level)
end

local function makeHitbox(model: Model, roomId: string, x0: number, y0: number, w: number): BasePart
	local hit = model:FindFirstChild("Hitbox") :: BasePart?
	if not hit then
		hit = Instance.new("Part")
		hit.Name = "Hitbox"
		hit.Anchored = true
		hit.CanCollide = false
		hit.CanTouch = false
		hit.Transparency = 1
		hit.Size = Vector3.new(w, ROW, 1)
		hit.CFrame = CFrame.new(x0 + w / 2, y0 + ROW / 2, 4.6)
		hit.Parent = model
	end
	local h = hit :: BasePart
	h.CanQuery = true
	h:SetAttribute("RoomId", roomId)
	return h
end

local function destroyVisual(id: string)
	local v = visuals[id]
	if v then
		v.model:Destroy()
		visuals[id] = nil
	end
end

local function buildVisual(room)
	local id = room.id
	destroyVisual(id)
	local origin = Grid.roomOrigin(room)
	local w = Grid.width(room) * UNIT
	local model: Model
	local built = nil
	local lights, animators = {}, {}
	if room.type == "Elevator" then
		model = Instance.new("Model")
		model.Name = "Elevator_" .. id
		MeshFactory.spawn("ELEV_SHAFT", origin, Theme.room("Elevator"), model)
		model.Parent = roomsFolder
	else
		built = RoomBuilder.build(room.type, room.modules, room.level, origin, roomsFolder)
		model = built.model
		model.Name = room.type .. "_" .. id
		lights = built.lights
		animators = built.animators
		if built.tags.Door then
			doorModel = built.tags.Door
		end
	end
	local hit = makeHitbox(model, id, origin.Position.X, origin.Position.Y, w)
	visuals[id] = {
		key = keyOf(room),
		room = room,
		model = model,
		built = built,
		hitbox = hit,
		minX = origin.Position.X,
		maxX = origin.Position.X + w,
		minY = origin.Position.Y,
		maxY = origin.Position.Y + ROW,
		lights = lights,
		animators = animators,
	}
end

-- Elevator cars: one per vertical run of elevator cells in a column.
local function rebuildCars()
	local cols: { [number]: { number } } = {}
	for _, r in C.StateStore.state.rooms do
		if r.type == "Elevator" then
			cols[r.col] = cols[r.col] or {}
			table.insert(cols[r.col], r.row)
		end
	end
	local seen = {}
	for col, rows in cols do
		table.sort(rows)
		local k = tostring(col)
		seen[k] = true
		if not cars[k] then
			local y = -rows[1] * ROW + Config.FLOOR_Y
			local m = MeshFactory.spawn("ELEV_CAR", CFrame.new(col * UNIT + UNIT / 2, y, 0), Theme.room("Elevator"), world)
			m.Name = "ElevatorCar_" .. col
			cars[k] = { model = m, col = col, y = y, target = y, moving = false }
		end
	end
	for k, car in cars do
		if not seen[k] then
			car.model:Destroy()
			cars[k] = nil
		end
	end
end

function VaultRenderer.carTo(col: number, y: number)
	local car = cars[tostring(col)]
	if car then
		car.target = y
	end
end

local function tileVariant(col: number, row: number): string
	local h = (col * 73856093 + row * 19349663) % 3
	return ({ "ROCK_TILE_A", "ROCK_TILE_B", "ROCK_TILE_C" })[h + 1]
end

-- Bedrock: detailed 1-cell tiles near rooms, cheap 3-cell slabs for the rest of the visible
-- underground (from the surface down past the deepest room, wider than the camera can pan).
local NEAR_COLS, NEAR_ROWS = 4, 2
local function rebuildRock()
	local rooms = C.StateStore.state.rooms
	local occ = Grid.occupancy(rooms)
	local minC, maxC, _, maxR = Grid.bounds(rooms)
	local c0 = math.floor((minC - 24) / 3) * 3
	local c1 = maxC + 24
	local r1 = math.max(maxR + 5, 8)
	local near: { [number]: boolean } = {}
	for _, r in rooms do
		for c = r.col - NEAR_COLS, r.col + Grid.width(r) - 1 + NEAR_COLS do
			for rr = r.row - NEAR_ROWS, r.row + NEAR_ROWS do
				near[rr * 1000 + c] = true
			end
		end
	end
	local want: { [string]: { asset: string, cf: CFrame } } = {}
	for row = -1, r1 do
		for bc = c0, c1, 3 do
			local allFar = true
			for c = bc, bc + 2 do
				local k = row * 1000 + c
				if near[k] or occ[k] then
					allFar = false
				end
			end
			if allFar then
				want["s" .. row .. ":" .. bc] = {
					asset = if ((bc // 3) + row) % 2 == 0 then "ROCK_SLAB_A" else "ROCK_SLAB_B",
					cf = CFrame.new(bc * UNIT, -row * ROW, 0),
				}
			else
				for c = bc, bc + 2 do
					if not occ[row * 1000 + c] then
						want["t" .. row .. ":" .. c] = { asset = tileVariant(c, row), cf = CFrame.new(c * UNIT, -row * ROW, 0) }
					end
				end
			end
		end
	end
	for k, m in rockTiles do
		local w = want[k]
		if not w or m.Name ~= w.asset then
			m:Destroy()
			rockTiles[k] = nil
		end
	end
	for k, w in want do
		if not rockTiles[k] then
			rockTiles[k] = MeshFactory.spawn(w.asset, w.cf, nil, rockFolder)
		end
	end
end

local function updateBounds()
	local minC, maxC, minR, maxR = Grid.bounds(C.StateStore.state.rooms)
	-- vertical bounds reach up past the surface so the player can look outside
	C.CameraController.setBounds((minC - 4) * UNIT, (maxC + 4) * UNIT, -(maxR + 1) * ROW - 10, math.max(-minR * ROW + ROW + 12, 24 + 58))
end

function VaultRenderer.refreshAll()
	local rooms = C.StateStore.state.rooms
	for id in visuals do
		if not rooms[id] then
			destroyVisual(id)
		end
	end
	for id, r in rooms do
		local v = visuals[id]
		if not v or v.key ~= keyOf(r) then
			buildVisual(r)
		else
			v.room = r
		end
	end
	rebuildCars()
	rebuildRock()
	updateBounds()
end

function VaultRenderer.roomCenter(id: string): Vector3?
	local v = visuals[id]
	if not v then
		return nil
	end
	return Vector3.new((v.minX + v.maxX) / 2, (v.minY + v.maxY) / 2, 0)
end

function VaultRenderer.roomBounds(id: string): (number?, number?, number?)
	local v = visuals[id]
	if not v then
		return nil
	end
	return v.minX, v.maxX, v.minY + Config.FLOOR_Y
end

function VaultRenderer.workSpots(id: string)
	local v = visuals[id]
	return v and v.built and v.built.work or {}
end

-- Errand seats of a kind ("eat", "drink", "sleep", "treat") in a room.
function VaultRenderer.spots(id: string, kind: string)
	local v = visuals[id]
	return v and v.built and v.built.spots and v.built.spots[kind] or {}
end

function VaultRenderer.visual(id: string): Visual?
	return visuals[id]
end

function VaultRenderer.select(id: string?)
	local v = id and visuals[id]
	selection.Adornee = if v then v.hitbox else nil
end

function VaultRenderer.setDoorOpen(open: boolean)
	if open == doorOpen or not doorModel then
		return
	end
	doorOpen = open
	local base = doorModel:GetAttribute("BaseCFrame") :: CFrame
	local model = doorModel :: Model
	if C.AudioManager then
		C.AudioManager:Door("BlastDoor", open, base.Position, "heavy")
	end
	local v = Instance.new("NumberValue")
	v.Value = if open then 0 else 1
	v.Changed:Connect(function(a)
		-- roll the octagonal door sideways like a wheel
		model:PivotTo(base * CFrame.new(-8.8 * a, 0, -0.2 * a) * CFrame.Angles(0, 0, 8.8 * a / 4.1))
	end)
	local tw = TweenService:Create(v, TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { Value = if open then 1 else 0 })
	tw.Completed:Connect(function()
		v:Destroy()
	end)
	tw:Play()
end

function VaultRenderer.Init(controllers)
	C = controllers
	world = C.InputController.world()
	roomsFolder = Instance.new("Folder")
	roomsFolder.Name = "Rooms"
	roomsFolder.Parent = world
	rockFolder = Instance.new("Folder")
	rockFolder.Name = "Rock"
	rockFolder.Parent = world
	local back = Instance.new("Part")
	back.Name = "Backdrop"
	back.Anchored = true
	back.CanCollide = false
	back.CanQuery = false
	back.CanTouch = false
	-- Bedrock backdrop behind everything underground; stops at the surface so the sky shows.
	-- (Roblox clamps parts to 2048 studs per axis, so stay within that.)
	back.Size = Vector3.new(2048, 2000, 1)
	back.CFrame = CFrame.new(78, 24 - 1000.5, -9)
	back.Material = Enum.Material.Slate
	back.Color = Color3.fromRGB(58, 46, 37)
	back.CastShadow = false
	back.Parent = world
	selection = Instance.new("SelectionBox")
	selection.Color3 = Theme.UI.accent
	selection.LineThickness = 0.18
	selection.SurfaceTransparency = 0.92
	selection.SurfaceColor3 = Theme.UI.accent
	selection.Parent = world
end

function VaultRenderer.Start()
	local S = C.StateStore
	S.Snapshot:Connect(VaultRenderer.refreshAll)
	S.RoomChanged:Connect(function(room)
		local v = visuals[room.id]
		if not v or v.key ~= keyOf(room) then
			VaultRenderer.refreshAll()
		else
			v.room = room
		end
	end)
	S.RoomRemoved:Connect(function()
		VaultRenderer.refreshAll()
	end)
	S.Raid:Connect(function(raid)
		VaultRenderer.setDoorOpen(raid ~= nil and raid.phase ~= "door")
	end)
	S.RaidEnd:Connect(function()
		task.delay(3, function()
			VaultRenderer.setDoorOpen(false)
		end)
	end)
	if S.state.ready then
		VaultRenderer.refreshAll()
	end

	local acc, lightAcc = 0, 0
	RunService.RenderStepped:Connect(function(dt)
		local t = os.clock()
		-- elevator cars glide to their targets (and tell the AudioManager when they start and stop)
		for k, car in cars do
			local moving = math.abs(car.y - car.target) > 0.05
			if math.abs(car.y - car.target) > 0.01 then
				car.y += (car.target - car.y) * math.min(1, dt * 6)
				car.model:PivotTo(CFrame.new(car.col * UNIT + UNIT / 2, car.y, 0))
			end
			if C.AudioManager and (moving or car.moving) then
				local pos = Vector3.new(car.col * UNIT + UNIT / 2, car.y + 2, 0)
				C.AudioManager:Elevator(if moving == car.moving then "move" elseif moving then "depart" else "arrive", pos, k)
			end
			car.moving = moving
		end
		acc += dt
		lightAcc += dt
		if acc < 1 / 30 then
			return
		end
		local step = acc
		acc = 0
		local x0, x1, y0, y1 = C.CameraController.visibleRect(8)
		local far = C.CameraController.zoomAlpha() > 0.85
		-- during a power shortage machines slow down (the grid only meets part of the demand)
		local pf = C.StateStore.state.powerFactor or 1
		for _, v in visuals do
			local onScreen = v.maxX > x0 and v.minX < x1 and v.maxY > y0 and v.minY < y1
			local live = C.StateStore.state.rooms[v.room.id] or v.room
			local broken = live.incident ~= nil and live.incident.kind == "Breakdown"
			if onScreen and not far and not broken then
				local s = if v.room.type == "Power" then step else step * pf
				for _, fn in v.animators do
					fn(s, t)
				end
			end
		end
		if lightAcc > 0.25 then
			lightAcc = 0
			local lx0, lx1, ly0, ly1 = C.CameraController.visibleRect(30)
			-- brownout: lights flicker, and black out as the shortage deepens (Generators keep theirs)
			local pf = C.StateStore.state.powerFactor or 1
			for _, v in visuals do
				local near = v.maxX > lx0 and v.minX < lx1 and v.maxY > ly0 and v.minY < ly1
				local starved = pf < 0.99 and v.room.type ~= "Power"
				for _, l in v.lights do
					if starved and near then
						l.Enabled = math.random() < 0.15 + 0.85 * pf
					elseif l.Shadows or not near or not l.Enabled then
						l.Enabled = near
					end
				end
			end
		end
	end)
end

return VaultRenderer
