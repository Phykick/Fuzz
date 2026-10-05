-- Server bootstrap: load services, Init() all, then Start() all.
local Services = script.Parent:WaitForChild("Services")

local ORDER = {
	"AudioService",
	"NetService",
	"SaveService",
	"VaultService",
	"InventoryService",
	"DwellerService",
	"ResourceService",
	"RoomService",
	"IncidentService",
	"CombatService",
	"ExplorationService",
	"FamilyService",
	"LifeService",
}

local S = {}
for _, name in ORDER do
	S[name] = require(Services:WaitForChild(name))
end
for _, name in ORDER do
	if S[name].Init then
		S[name].Init(S)
	end
end
for _, name in ORDER do
	if S[name].Start then
		task.spawn(S[name].Start)
	end
end
print("[Underhaven] server ready")
