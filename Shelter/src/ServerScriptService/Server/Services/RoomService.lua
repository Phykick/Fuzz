--!strict
-- Construction authority: build (with auto-merge), upgrade, destroy (with connectivity check).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Grid = require(ReplicatedStorage.Shared.Grid)
local Simulation = require(ReplicatedStorage.Shared.Simulation)
local RoomDefinitions = require(ReplicatedStorage.Shared.RoomDefinitions)

local RoomService = {}
local S: any

-- Every built cell must stay reachable from the blast door (walk sideways, ride elevators).
local function connected(rooms): boolean
	local occ = Grid.occupancy(rooms)
	local start
	for _, r in rooms do
		if r.type == "Entrance" then
			start = r
		end
	end
	if not start then
		return false
	end
	local seen = {}
	local queue = { { start.col, start.row } }
	seen[start.row * 1000 + start.col] = true
	local count = 0
	while #queue > 0 do
		local c = table.remove(queue)
		count += 1
		local col, row = c[1], c[2]
		local here = rooms[occ[row * 1000 + col]]
		local nbrs = { { col - 1, row }, { col + 1, row } }
		if here.type == "Elevator" then
			table.insert(nbrs, { col, row - 1 })
			table.insert(nbrs, { col, row + 1 })
		end
		for _, n in nbrs do
			local k = n[2] * 1000 + n[1]
			local id = occ[k]
			if id and not seen[k] then
				local other = rooms[id]
				local vertical = n[2] ~= row
				if not vertical or other.type == "Elevator" then
					seen[k] = true
					table.insert(queue, n)
				end
			end
		end
	end
	local total = 0
	for _ in occ do
		total += 1
	end
	return count == total
end

function RoomService.Init(services)
	S = services
	local function vaultOf(player)
		return S.VaultService.get(player)
	end

	S.NetService.handle("Build", function(player, p)
		local vault = vaultOf(player)
		if not vault then
			return false, "Not ready"
		end
		local typeId, col, row = p.type, tonumber(p.col), tonumber(p.row)
		local def = RoomDefinitions.Types[typeId]
		if not def or not def.buildable or not col or not row or col % 1 ~= 0 or row % 1 ~= 0 then
			return false, "Invalid build"
		end
		local data = vault.data
		local pop = Simulation.population(data.dwellers)
		if pop < def.unlockPop then
			return false, def.name .. " unlocks at " .. def.unlockPop .. " survivors"
		end
		local ok, why = Grid.canPlace(data.rooms, typeId, col, row)
		if not ok then
			return false, why
		end
		local cost, mats = Simulation.buildCost(data.rooms, typeId)
		if data.resources.Bolts < cost then
			return false, "Need " .. cost .. " bolts"
		end
		if (data.resources.Materials or 0) < mats then
			return false, "Need " .. mats .. " materials"
		end
		data.resources.Bolts -= cost
		data.resources.Materials -= mats
		local id = S.VaultService.newId(vault, "room")
		data.rooms[id] = { id = id, type = typeId, col = col, row = row, modules = 1, level = 1, assigned = {}, pending = 0 }
		local survivor, removed = Grid.merge(data.rooms, id)
		data.progression.stats.built += 1
		for _, rid in removed do
			if rid ~= id then
				S.VaultService.send(vault, "roomRemoved", { id = rid })
			end
		end
		S.DwellerService.pushRoom(vault, data.rooms[survivor])
		-- Survivors whose room id vanished in a merge now belong to the merged room.
		for _, rid in removed do
			for _, d in data.dwellers do
				if d.roomId == rid or d.at == rid then
					if d.roomId == rid then
						d.roomId = survivor
					end
					if d.at == rid then
						d.at = survivor
					end
					S.DwellerService.push(vault, d)
				end
			end
		end
		S.VaultService.dirty(vault)
		S.ResourceService.pushResources(vault)
		return true, { roomId = survivor, merged = survivor ~= id, cost = cost, materials = mats }
	end)

	S.NetService.handle("Upgrade", function(player, p)
		local vault = vaultOf(player)
		if not vault then
			return false, "Not ready"
		end
		local room = vault.data.rooms[tostring(p.roomId)]
		if not room then
			return false, "Invalid room"
		end
		if room.incident then
			return false, "Can't upgrade during an emergency"
		end
		local cost, mats = Simulation.upgradeCost(room)
		if not cost then
			return false, "Already at max level"
		end
		local res = vault.data.resources
		if res.Bolts < cost then
			return false, "Need " .. cost .. " bolts"
		end
		if (res.Materials or 0) < mats then
			return false, "Need " .. mats .. " materials"
		end
		res.Bolts -= cost
		res.Materials -= mats
		room.level += 1
		S.DwellerService.pushRoom(vault, room)
		S.VaultService.dirty(vault)
		S.ResourceService.pushResources(vault)
		return true, { level = room.level, cost = cost }
	end)

	S.NetService.handle("Destroy", function(player, p)
		local vault = vaultOf(player)
		if not vault then
			return false, "Not ready"
		end
		local rooms = vault.data.rooms
		local room = rooms[tostring(p.roomId)]
		if not room or room.type == "Entrance" then
			return false, "That room can't be removed"
		end
		if room.incident then
			return false, "Deal with the emergency first!"
		end
		if S.CombatService.active(vault) then
			return false, "Not while raiders are in the shelter!"
		end
		if #room.assigned > 0 then
			return false, "Move its survivors out first"
		end
		for _, d in vault.data.dwellers do
			if d.roomId == room.id then
				return false, "Move its survivors out first"
			end
		end
		rooms[room.id] = nil
		if not connected(rooms) then
			rooms[room.id] = room
			return false, "Removing it would cut off part of the shelter"
		end
		S.VaultService.send(vault, "roomRemoved", { id = room.id })
		-- anyone eating, sleeping or passing through in there goes back to their own routine
		local now = S.VaultService.now()
		for _, d in vault.data.dwellers do
			if d.at == room.id then
				d.at = nil
				d.travel = nil
				d.arriveAt = 0
				d.activity = if d.status == "Dead" then nil elseif d.status == "Working" then "Working" else "Relaxing"
				d.activityEnd = nil
				if vault.rt.think and d.status ~= "Dead" then
					vault.rt.think[d.id] = now
				end
				S.DwellerService.push(vault, d)
			end
		end
		S.VaultService.dirty(vault)
		S.ResourceService.pushResources(vault)
		return true
	end)
end

return RoomService
