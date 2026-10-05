--!strict
-- 2.5D side-view camera. Always looks down -Z; the player can never rotate it.
-- FOV is tied to zoom: near-orthographic at full-vault view, gentle perspective up close.
-- Distance is solved every frame so the visible height equals the zoom target exactly.
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local CameraController = {}

local camera = workspace.CurrentCamera
local MIN_VIEW = 11 -- survivor close-up (studs of visible height)
local MAX_VIEW_CAP = 240
local FOV_NEAR, FOV_FAR = 26, 9

local center = Vector2.new(75, 0)
local target = center
local view = 60
local viewTarget = 60
local velocity = Vector2.zero
local dragging = false
local bounds = { minX = 0, maxX = 156, minY = -60, maxY = 12 }
local maxView = 120
local focusLock: (() -> Vector3?)? = nil

function CameraController.viewHeight(): number
	return view
end

function CameraController.zoomAlpha(): number
	-- 0 = closest, 1 = farthest
	return math.clamp((view - MIN_VIEW) / (maxView - MIN_VIEW), 0, 1)
end

local function fovFor(v: number): number
	local t = math.clamp((v - MIN_VIEW) / (110 - MIN_VIEW), 0, 1)
	return FOV_NEAR + (FOV_FAR - FOV_NEAR) * (t ^ 0.7)
end

local function clampTarget(c: Vector2, v: number): Vector2
	local vp = camera.ViewportSize
	local aspect = vp.X / math.max(1, vp.Y)
	local halfW, halfH = v * aspect / 2, v / 2
	local minX, maxX = bounds.minX + halfW * 0.6, bounds.maxX - halfW * 0.6
	local minY, maxY = bounds.minY + halfH * 0.6, bounds.maxY - halfH * 0.6
	local x = if minX > maxX then (bounds.minX + bounds.maxX) / 2 else math.clamp(c.X, minX, maxX)
	local y = if minY > maxY then (bounds.minY + bounds.maxY) / 2 else math.clamp(c.Y, minY, maxY)
	return Vector2.new(x, y)
end

-- Built-area rectangle in world studs (rooms + margin) so the camera never drifts into void.
function CameraController.setBounds(minX: number, maxX: number, minY: number, maxY: number)
	bounds = { minX = minX, maxX = maxX, minY = minY, maxY = maxY }
	local vp = camera.ViewportSize
	local aspect = vp.X / math.max(1, vp.Y)
	local needH = math.max(maxY - minY, (maxX - minX) / aspect)
	maxView = math.clamp(needH * 1.05, 40, MAX_VIEW_CAP)
	viewTarget = math.min(viewTarget, maxView)
end

-- World point under a screen position on the z = 0 plane.
function CameraController.screenToWorld(screen: Vector2): Vector3
	local ray = camera:ScreenPointToRay(screen.X, screen.Y)
	local t = -ray.Origin.Z / ray.Direction.Z
	return ray.Origin + ray.Direction * t
end

function CameraController.worldPerPixel(): number
	return view / math.max(1, camera.ViewportSize.Y)
end

function CameraController.pan(deltaPixels: Vector2)
	focusLock = nil
	local k = CameraController.worldPerPixel()
	target = clampTarget(target + Vector2.new(-deltaPixels.X * k, deltaPixels.Y * k), viewTarget)
	center = target
	velocity = Vector2.new(-deltaPixels.X * k, deltaPixels.Y * k) * 60
end

function CameraController.setDragging(on: boolean)
	dragging = on
	if on then
		velocity = Vector2.zero
	end
end

-- Zoom by factor (>1 zooms out) keeping the world point under `screen` fixed.
function CameraController.zoom(factor: number, screen: Vector2?)
	local newView = math.clamp(viewTarget * factor, MIN_VIEW, maxView)
	if screen then
		local vp = camera.ViewportSize
		local inset = GuiService:GetGuiInset()
		local offset = (screen + inset - vp / 2) * (viewTarget / vp.Y)
		local world = target + Vector2.new(offset.X, -offset.Y)
		local ratio = newView / viewTarget
		target = world - (world - target) * ratio
	end
	viewTarget = newView
	target = clampTarget(target, viewTarget)
end

function CameraController.focus(pos: Vector3, viewH: number?, follow: (() -> Vector3?)?)
	target = clampTarget(Vector2.new(pos.X, pos.Y), viewH or viewTarget)
	if viewH then
		viewTarget = math.clamp(viewH, MIN_VIEW, maxView)
	end
	focusLock = follow
	velocity = Vector2.zero
end

-- Scene mode: snap to a separate set (e.g. the wasteland) with its own bounds; exitScene restores.
local saved: any = nil
function CameraController.enterScene(c: Vector3, viewH: number, halfWidth: number)
	if not saved then
		saved = { center = center, target = target, view = view, viewTarget = viewTarget, bounds = bounds, maxView = maxView }
	end
	bounds = { minX = c.X - halfWidth, maxX = c.X + halfWidth, minY = c.Y - 14, maxY = c.Y + 36 }
	maxView = 44
	target = Vector2.new(c.X, c.Y)
	center = target
	view = viewH
	viewTarget = viewH
	velocity = Vector2.zero
	focusLock = nil
end

function CameraController.exitScene()
	if saved then
		center, target, view, viewTarget, bounds, maxView = saved.center, saved.target, saved.view, saved.viewTarget, saved.bounds, saved.maxView
		saved = nil
	end
	velocity = Vector2.zero
	focusLock = nil
end

function CameraController.zoomLimits(): (number, number)
	return MIN_VIEW, maxView
end

-- Rectangle currently visible on the z=0 plane (for culling / LOD).
function CameraController.visibleRect(margin: number?): (number, number, number, number)
	local vp = camera.ViewportSize
	local aspect = vp.X / math.max(1, vp.Y)
	local m = margin or 0
	local hw, hh = view * aspect / 2 + m, view / 2 + m
	return center.X - hw, center.X + hw, center.Y - hh, center.Y + hh
end

function CameraController.Init()
	camera.CameraType = Enum.CameraType.Scriptable
end

function CameraController.Start()
	RunService:BindToRenderStep("UH_Camera", Enum.RenderPriority.Camera.Value, function(dt)
		camera.CameraType = Enum.CameraType.Scriptable
		if focusLock then
			local p = focusLock()
			if p then
				target = clampTarget(Vector2.new(p.X, p.Y + 1), viewTarget)
			else
				focusLock = nil
			end
		end
		if not dragging and velocity.Magnitude > 0.01 then
			target = clampTarget(target + velocity * dt, viewTarget)
			velocity *= math.exp(-dt * 5)
		end
		local a = 1 - math.exp(-dt * 10)
		center = center:Lerp(target, a)
		view += (viewTarget - view) * a
		local fov = fovFor(view)
		local dist = (view / 2) / math.tan(math.rad(fov) / 2)
		camera.FieldOfView = fov
		camera.CFrame = CFrame.new(center.X, center.Y, dist)
		camera.Focus = CFrame.new(center.X, center.Y, 0)
	end)
end

local _ = Config
return CameraController
