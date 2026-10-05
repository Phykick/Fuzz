--!strict
-- Unified mouse / touch / keyboard input for the 2.5D view.
--   tap            -> Tap(screenPos, hit)
--   drag on world  -> camera pan (with inertia)
--   press+drag a survivor (mouse) or long-press then drag (touch) -> survivor drag & drop
--   wheel / pinch  -> zoom towards the pointer
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local InputController = {}
InputController.Tap = Signal.new()
InputController.Hover = Signal.new()
InputController.DragStart = Signal.new()
InputController.DragMove = Signal.new()
InputController.DragEnd = Signal.new()
InputController.Cancel = Signal.new()

local C: any
local camera = workspace.CurrentCamera
local TAP_MOVE = 12
local LONG_PRESS = 0.28

type Press = { pos: Vector2, start: Vector2, t: number, hit: any, mode: string, isTouch: boolean }
local press: Press? = nil
local touches: { [InputObject]: Vector2 } = {}
local pinchDist: number? = nil
local pinchMid: Vector2? = nil

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Include

function InputController.world(): Folder
	local w = workspace:FindFirstChild("UH_World") :: Folder?
	if not w then
		w = Instance.new("Folder")
		w.Name = "UH_World"
		w.Parent = workspace
	end
	return w :: Folder
end

local function cast(screen: Vector2, include: { Instance }): RaycastResult?
	params.FilterDescendantsInstances = include
	local ray = camera:ScreenPointToRay(screen.X, screen.Y) -- GUI-space (inset-aware)
	return workspace:Raycast(ray.Origin, ray.Direction * 5000, params)
end

-- What is under a screen point? Returns { kind = "dweller"|"room"|"slot", ... } or nil.
-- Survivors win over rooms (room hitboxes sit in front of the characters), with a
-- screen-space tolerance so small characters are easy to grab with a finger.
-- dropOnly = true ignores survivors (used while dragging one).
function InputController.pick(screen: Vector2, dropOnly: boolean?): any
	local w = InputController.world()
	if not dropOnly then
		local chars = w:FindFirstChild("Characters")
		local surface = workspace:FindFirstChild("Surface")
		local outside = surface and surface:FindFirstChild("Walkers")
		local targets = {}
		for _, f in { chars, outside } do
			if f then
				table.insert(targets, f)
			end
		end
		if #targets > 0 then
			local hit = cast(screen, targets)
			local did = hit and hit.Instance:GetAttribute("DwellerId")
			if did then
				return { kind = "dweller", id = did, position = hit.Position }
			end
		end
		local near = C and C.DwellerController and C.DwellerController.nearestOnScreen(screen, if UserInputService.TouchEnabled then 46 else 26)
		if near then
			return { kind = "dweller", id = near }
		end
	end
	local include = {}
	for _, name in { "Rooms", "BuildSlots" } do
		local f = w:FindFirstChild(name)
		if f then
			table.insert(include, f)
		end
	end
	local result = cast(screen, include)
	if not result then
		return nil
	end
	local inst = result.Instance
	local slot = inst:GetAttribute("SlotCol")
	if slot then
		return { kind = "slot", col = slot, row = inst:GetAttribute("SlotRow"), position = result.Position }
	end
	local rid = inst:GetAttribute("RoomId")
	if rid then
		return { kind = "room", id = rid, position = result.Position }
	end
	return nil
end

local function begin(pos: Vector2, isTouch: boolean)
	press = { pos = pos, start = pos, t = os.clock(), hit = InputController.pick(pos), mode = "pending", isTouch = isTouch }
end

local function move(pos: Vector2)
	local p = press
	if not p then
		return
	end
	local delta = pos - p.pos
	p.pos = pos
	if p.mode == "pending" then
		if (pos - p.start).Magnitude > TAP_MOVE then
			if p.hit and p.hit.kind == "dweller" and not p.isTouch then
				p.mode = "dragDweller"
				InputController.DragStart:Fire(p.hit.id, pos)
			else
				p.mode = "pan"
				C.CameraController.setDragging(true)
				C.CameraController.pan(pos - p.start)
			end
		end
	elseif p.mode == "pan" then
		C.CameraController.pan(delta)
	elseif p.mode == "dragDweller" then
		InputController.DragMove:Fire(pos)
	end
end

local function finish(pos: Vector2)
	local p = press
	press = nil
	if not p then
		return
	end
	if p.mode == "pending" then
		InputController.Tap:Fire(pos, p.hit)
	elseif p.mode == "pan" then
		C.CameraController.setDragging(false)
	elseif p.mode == "dragDweller" then
		InputController.DragEnd:Fire(pos, InputController.pick(pos, true))
	end
end

function InputController.isDragging(): boolean
	return press ~= nil and press.mode == "dragDweller"
end

function InputController.Init(controllers)
	C = controllers
end

function InputController.Start()
	UserInputService.InputBegan:Connect(function(input, processed)
		local t = input.UserInputType
		if t == Enum.UserInputType.Touch then
			if processed then
				return
			end
			touches[input] = Vector2.new(input.Position.X, input.Position.Y)
			local n = 0
			for _ in touches do
				n += 1
			end
			if n == 1 then
				begin(touches[input], true)
			elseif n == 2 then
				-- second finger: cancel tap/drag and start pinch
				if press and press.mode == "dragDweller" then
					InputController.DragEnd:Fire(press.pos, nil)
				end
				press = nil
				C.CameraController.setDragging(true)
				pinchDist, pinchMid = nil, nil
			end
		elseif t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.MouseButton2 then
			if processed then
				return
			end
			begin(Vector2.new(input.Position.X, input.Position.Y), false)
			if t == Enum.UserInputType.MouseButton2 and press then
				press.hit = nil -- right-drag always pans
			end
		elseif t == Enum.UserInputType.Keyboard then
			if processed then
				return
			end
			if input.KeyCode == Enum.KeyCode.Escape then
				InputController.Cancel:Fire()
			elseif input.KeyCode == Enum.KeyCode.Equals or input.KeyCode == Enum.KeyCode.E then
				C.CameraController.zoom(0.8)
			elseif input.KeyCode == Enum.KeyCode.Minus or input.KeyCode == Enum.KeyCode.Q then
				C.CameraController.zoom(1.25)
			end
		end
	end)
	UserInputService.InputChanged:Connect(function(input, processed)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseWheel then
			if processed then
				return
			end
			local factor = if input.Position.Z > 0 then 0.86 else 1.16
			C.CameraController.zoom(factor, Vector2.new(input.Position.X, input.Position.Y))
		elseif t == Enum.UserInputType.MouseMovement then
			local pos = Vector2.new(input.Position.X, input.Position.Y)
			if press then
				move(pos)
			else
				InputController.Hover:Fire(pos)
			end
		elseif t == Enum.UserInputType.Touch and touches[input] then
			touches[input] = Vector2.new(input.Position.X, input.Position.Y)
			local list = {}
			for _, p in touches do
				table.insert(list, p)
			end
			if #list >= 2 then
				local a, b = list[1], list[2]
				local d = (a - b).Magnitude
				local mid = (a + b) / 2
				if pinchDist and pinchMid then
					C.CameraController.zoom(pinchDist / math.max(1, d), mid)
					C.CameraController.pan(mid - pinchMid)
				end
				pinchDist, pinchMid = d, mid
			elseif #list == 1 then
				move(list[1])
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.Touch then
			local pos = touches[input] or Vector2.new(input.Position.X, input.Position.Y)
			touches[input] = nil
			local n = 0
			for _ in touches do
				n += 1
			end
			if n == 0 then
				if pinchDist then
					pinchDist, pinchMid = nil, nil
					C.CameraController.setDragging(false)
				else
					finish(pos)
				end
			end
		elseif t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.MouseButton2 then
			finish(Vector2.new(input.Position.X, input.Position.Y))
		end
	end)
	-- Long-press on a survivor (touch) starts a drag.
	RunService.Heartbeat:Connect(function()
		local p = press
		if p and p.mode == "pending" and p.isTouch and p.hit and p.hit.kind == "dweller" and os.clock() - p.t > LONG_PRESS then
			p.mode = "dragDweller"
			InputController.DragStart:Fire(p.hit.id, p.pos)
		end
		-- Keyboard panning
		local k = Vector2.zero
		if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then
			k += Vector2.new(1, 0)
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then
			k -= Vector2.new(1, 0)
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up) then
			k += Vector2.new(0, 1)
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down) then
			k -= Vector2.new(0, 1)
		end
		if k.Magnitude > 0 and not UserInputService:GetFocusedTextBox() then
			C.CameraController.pan(k * 9)
			C.CameraController.setDragging(false)
		end
	end)
end

return InputController
