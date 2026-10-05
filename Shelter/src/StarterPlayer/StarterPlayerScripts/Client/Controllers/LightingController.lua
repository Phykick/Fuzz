--!strict
-- Underground lighting setup + global mood effects (alarm pulse during raids, build-mode grade).
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local LightingController = {}

local grade: ColorCorrectionEffect
local alarm = 0
local alarmTarget = 0
local buildMode = false

function LightingController.setAlarm(on: boolean)
	alarmTarget = if on then 1 else 0
end

function LightingController.setBuildMode(on: boolean)
	buildMode = on
	TweenService:Create(grade, TweenInfo.new(0.35), {
		Saturation = if on then -0.35 else 0.12,
		Contrast = if on then 0.02 else 0.1,
	}):Play()
end

function LightingController.Init()
	-- Low dusk sun behind the scene (from -Z, slightly left): it lights the surface world but the
	-- bedrock backdrop and rock tiles shadow the open-fronted rooms below.
	Lighting.GeographicLatitude = -40
	Lighting.ClockTime = 16
	Lighting.Brightness = 1.7
	Lighting.Ambient = Color3.fromRGB(70, 62, 58)
	Lighting.OutdoorAmbient = Color3.fromRGB(122, 104, 100)
	Lighting.ColorShift_Top = Color3.fromRGB(255, 196, 140)
	Lighting.ColorShift_Bottom = Color3.fromRGB(60, 40, 50)
	-- Our scenery draws its own sun; Roblox's skybox sun (21 deg wide) would swamp the
	-- narrow far-zoom camera.
	local sky = Lighting:FindFirstChildOfClass("Sky")
	if sky then
		sky.CelestialBodiesShown = false
		sky.StarCount = 0
	end
	Lighting.EnvironmentDiffuseScale = 0.25
	Lighting.EnvironmentSpecularScale = 0.55
	Lighting.GlobalShadows = true
	for _, c in Lighting:GetChildren() do
		if c:IsA("Atmosphere") or c:IsA("SunRaysEffect") or c:IsA("DepthOfFieldEffect") then
			c:Destroy()
		end
	end
	grade = Lighting:FindFirstChild("UH_Grade") :: ColorCorrectionEffect
	if not grade then
		grade = Instance.new("ColorCorrectionEffect")
		grade.Name = "UH_Grade"
		grade.Parent = Lighting
	end
	grade.Contrast = 0.1
	grade.Saturation = 0.12
	grade.Brightness = 0.02
	grade.TintColor = Color3.fromRGB(255, 247, 236)
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect") or Instance.new("BloomEffect")
	bloom.Intensity = 0.55
	bloom.Size = 22
	bloom.Threshold = 1.35
	bloom.Parent = Lighting
end

function LightingController.Start()
	RunService.RenderStepped:Connect(function(dt)
		alarm += (alarmTarget - alarm) * math.min(1, dt * 3)
		if alarm > 0.01 and not buildMode then
			local p = (math.sin(os.clock() * 4) + 1) / 2
			grade.TintColor = Color3.fromRGB(255, 247, 236):Lerp(Color3.fromRGB(255, 170, 150), alarm * p * 0.6)
		elseif not buildMode then
			grade.TintColor = Color3.fromRGB(255, 247, 236)
		end
	end)
end

return LightingController
