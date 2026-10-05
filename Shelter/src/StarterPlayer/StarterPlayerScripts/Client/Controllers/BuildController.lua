--!strict
-- Build mode: the world desaturates, every valid placement becomes a green hologram slot,
-- hovering (PC) shows a ghost of the room, invalid cells glow red. Tap a slot to build.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Grid = require(ReplicatedStorage.Shared.Grid)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Icons = require(ReplicatedStorage.Shared.Icons)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local RoomDefinitions = require(ReplicatedStorage.Shared.RoomDefinitions)
local Simulation = require(ReplicatedStorage.Shared.Simulation)

local BuildController = {}
BuildController.Changed = Signal.new()
BuildController.active = nil :: string?

local C: any
local slotFolder: Folder
local ghost: Part
local UNIT, ROW = Config.UNIT, Config.ROW_HEIGHT
local GOOD = Color3.fromRGB(123, 224, 122)
local BAD = Color3.fromRGB(255, 77, 61)

local function clearSlots()
	slotFolder:ClearAllChildren()
	ghost.Transparency = 1
end

local function makeSlot(col: number, row: number, typeId: string)
	local def = RoomDefinitions.Types[typeId]
	local w = def.units * UNIT
	local p = Instance.new("Part")
	p.Name = "Slot"
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = true
	p.CastShadow = false
	p.Material = Enum.Material.ForceField
	p.Color = GOOD
	p.Size = Vector3.new(w - 0.7, ROW - 1.6, 9)
	p.CFrame = CFrame.new(col * UNIT + w / 2, -row * ROW + ROW / 2, 0)
	p.Transparency = 0.15
	p:SetAttribute("SlotCol", col)
	p:SetAttribute("SlotRow", row)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(46, 46)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 5000
	local img = Instance.new("ImageLabel")
	img.BackgroundTransparency = 1
	img.Size = UDim2.fromScale(1, 1)
	img.Image = Icons.build
	img.ImageColor3 = GOOD
	img.Parent = bb
	bb.Parent = p
	p.Parent = slotFolder
	-- pulse in
	p.Size = Vector3.new(w - 0.7, 0.2, 9)
	TweenService:Create(p, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Size = Vector3.new(w - 0.7, ROW - 1.6, 9) }):Play()
end

function BuildController.refreshSlots()
	local typeId = BuildController.active
	clearSlots()
	if not typeId then
		return
	end
	for _, s in Grid.validSlots(C.StateStore.state.rooms, typeId) do
		makeSlot(s.col, s.row, typeId)
	end
end

function BuildController.enter(typeId: string)
	local def = RoomDefinitions.Types[typeId]
	if not def or not def.buildable then
		return
	end
	BuildController.active = typeId
	C.LightingController.setBuildMode(true)
	C.VaultRenderer.select(nil)
	BuildController.refreshSlots()
	local minV, maxV = C.CameraController.zoomLimits()
	local _ = minV
	if C.CameraController.viewHeight() < 70 then
		C.CameraController.zoom(math.min(1.6, maxV / C.CameraController.viewHeight()))
	end
	BuildController.Changed:Fire(typeId)
end

function BuildController.exit()
	if not BuildController.active then
		return
	end
	BuildController.active = nil
	clearSlots()
	C.LightingController.setBuildMode(false)
	BuildController.Changed:Fire(nil)
end

function BuildController.cost(typeId: string): (number, number)
	return Simulation.buildCost(C.StateStore.state.rooms, typeId)
end

local function hover(screen: Vector2)
	local typeId = BuildController.active
	if not typeId then
		return
	end
	local def = RoomDefinitions.Types[typeId]
	local hit = C.InputController.pick(screen)
	if hit and hit.kind == "slot" then
		for _, s in slotFolder:GetChildren() do
			local p = s :: BasePart
			p.Transparency = if p:GetAttribute("SlotCol") == hit.col and p:GetAttribute("SlotRow") == hit.row then 0 else 0.15
		end
		ghost.Transparency = 1
		return
	end
	local w = C.CameraController.screenToWorld(screen)
	local col = math.floor(w.X / UNIT - def.units / 2 + 0.5)
	local row = math.floor(-w.Y / ROW) + 1
	local ok = Grid.canPlace(C.StateStore.state.rooms, typeId, col, row)
	local occ = Grid.occupancy(C.StateStore.state.rooms)
	if ok or Grid.at(occ, col, row) or row < 0 or row >= Config.GRID_ROWS then
		ghost.Transparency = 1
		return
	end
	ghost.Size = Vector3.new(def.units * UNIT - 0.7, ROW - 1.6, 9)
	ghost.CFrame = CFrame.new(col * UNIT + def.units * UNIT / 2, -row * ROW + ROW / 2, 0)
	ghost.Transparency = 0.35
end

local function build(col: number, row: number)
	local typeId = BuildController.active
	if not typeId then
		return
	end
	local ok, result = C.StateStore.action("Build", { type = typeId, col = col, row = row })
	if ok then
		BuildController.exit()
		local def = RoomDefinitions.Types[typeId]
		task.delay(0.15, function()
			local center = C.VaultRenderer.roomCenter(result.roomId)
			if center then
				C.EffectsController.float(center + Vector3.new(0, 1, 5), if result.merged then "ROOM EXPANDED!" else string.upper(def.name) .. " BUILT", Theme.UI.accent, "build", true)
				C.CameraController.focus(center, math.max(30, C.CameraController.viewHeight() * 0.7))
			end
			C.UIController.selectRoom(result.roomId)
		end)
	end
end

function BuildController.Init(controllers)
	C = controllers
	slotFolder = Instance.new("Folder")
	slotFolder.Name = "BuildSlots"
	slotFolder.Parent = C.InputController.world()
	ghost = Instance.new("Part")
	ghost.Name = "Ghost"
	ghost.Anchored = true
	ghost.CanCollide = false
	ghost.CanQuery = false
	ghost.CanTouch = false
	ghost.CastShadow = false
	ghost.Material = Enum.Material.ForceField
	ghost.Color = BAD
	ghost.Transparency = 1
	ghost.Parent = workspace
end

function BuildController.Start()
	C.InputController.Hover:Connect(hover)
	C.InputController.Cancel:Connect(BuildController.exit)
	C.StateStore.RoomChanged:Connect(function()
		if BuildController.active then
			BuildController.refreshSlots()
		end
	end)
	C.StateStore.RoomRemoved:Connect(function()
		if BuildController.active then
			BuildController.refreshSlots()
		end
	end)
end

-- Called by UIController when a world tap happens in build mode. Returns true if consumed.
function BuildController.handleTap(hit: any): boolean
	if not BuildController.active then
		return false
	end
	if hit and hit.kind == "slot" then
		build(hit.col, hit.row)
	end
	return true
end

return BuildController
