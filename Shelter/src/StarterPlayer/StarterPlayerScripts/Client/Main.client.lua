-- Client bootstrap: Init() all controllers, then Start() them.
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

local Controllers = script.Parent:WaitForChild("Controllers")

local ORDER = {
	"StateStore",
	"LightingController",
	"CameraController",
	"InputController",
	"VaultRenderer",
	"EffectsController",
	"DwellerController",
	"SurfaceController",
	"WastelandController",
	"BuildController",
	"UIController",
}

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.EmotesMenu, false)
end)

local C = {}
for _, name in ORDER do
	C[name] = require(Controllers:WaitForChild(name))
end
for _, name in ORDER do
	if C[name].Init then
		C[name].Init(C)
	end
end
for _, name in ORDER do
	if C[name].Start then
		task.spawn(C[name].Start)
	end
end
-- Studio-only automation hook (used for testing camera/screens from outside the client VM).
if game:GetService("RunService"):IsStudio() then
	local hook = Instance.new("BindableFunction")
	hook.Name = "UH_Debug"
	hook.OnInvoke = function(cmd: string, a: any, b: any, c: any)
		if cmd == "focus" then
			C.CameraController.focus(Vector3.new(a, b, 0), c)
		elseif cmd == "wasteland" then
			C.UIController.openWasteland(a)
		elseif cmd == "shelter" then
			C.UIController.closeWasteland()
		elseif cmd == "select" then
			C.UIController.selectDweller(a, true)
		elseif cmd == "drag" then
			-- simulate a drag & drop of survivor `a` onto room `b`
			C.DwellerController.beginDrag(a)
			task.wait(0.3)
			C.DwellerController.endDrag(a)
			return C.StateStore.action("Assign", { dwellerId = a, roomId = b })
		elseif cmd == "state" then
			return C.StateStore.state
		end
		return true
	end
	hook.Parent = Players.LocalPlayer:WaitForChild("PlayerScripts")
end
