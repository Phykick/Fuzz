--!strict
-- Remote names and helpers. Server creates the remotes; clients wait for them.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

Net.Actions = {
	Build = "Build",
	Upgrade = "Upgrade",
	Destroy = "Destroy",
	Assign = "Assign",
	Rush = "Rush",
	Collect = "Collect",
	Revive = "Revive",
	Equip = "Equip",
	Rename = "Rename",
	Debug = "Debug",
}

function Net.remotes(): (RemoteFunction, RemoteEvent)
	local folder
	if RunService:IsServer() then
		folder = ReplicatedStorage:FindFirstChild("Remotes")
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = "Remotes"
			local action = Instance.new("RemoteFunction")
			action.Name = "Action"
			action.Parent = folder
			local state = Instance.new("RemoteEvent")
			state.Name = "State"
			state.Parent = folder
			folder.Parent = ReplicatedStorage
		end
	else
		folder = ReplicatedStorage:WaitForChild("Remotes")
	end
	return folder:WaitForChild("Action") :: RemoteFunction, folder:WaitForChild("State") :: RemoteEvent
end

return Net
