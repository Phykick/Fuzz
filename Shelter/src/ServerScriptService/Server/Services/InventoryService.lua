--!strict
-- Weapons and outfits: granting, equipping, durability.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemDefinitions = require(ReplicatedStorage.Shared.ItemDefinitions)

local InventoryService = {}
local S: any

function InventoryService.grant(vault, defId: string): string?
	local def = ItemDefinitions.get(defId)
	if not def then
		return nil
	end
	local id = S.VaultService.newId(vault, "item")
	vault.data.inventory[id] = { id = id, def = defId, dur = def.durability or 0, equippedBy = nil }
	S.VaultService.dirty(vault)
	return id
end

-- Equip an item instance on a survivor (unequips whatever was in that slot).
function InventoryService.equip(vault, d, itemId: string?): (boolean, string?)
	local inv = vault.data.inventory
	if itemId == nil then
		return false, "No item"
	end
	local item = inv[itemId]
	if not item then
		return false, "Item not found"
	end
	local def = ItemDefinitions.get(item.def)
	if not def then
		return false, "Unknown item"
	end
	if item.equippedBy and item.equippedBy ~= d.id then
		local other = vault.data.dwellers[item.equippedBy]
		if other then
			InventoryService.unequip(vault, other, def.kind)
		end
	end
	InventoryService.unequip(vault, d, def.kind)
	item.equippedBy = d.id
	if def.kind == "Weapon" then
		d.weapon, d.weaponItem = item.def, itemId
	else
		d.outfit, d.outfitItem = item.def, itemId
	end
	S.VaultService.dirty(vault)
	return true
end

function InventoryService.unequip(vault, d, kind: string)
	local field = if kind == "Weapon" then "weaponItem" else "outfitItem"
	local cur = d[field]
	if cur and vault.data.inventory[cur] then
		vault.data.inventory[cur].equippedBy = nil
	end
	d[field] = nil
	if kind == "Weapon" then
		d.weapon = nil
	else
		d.outfit = nil
	end
end

function InventoryService.weaponOf(d): any
	return ItemDefinitions.Weapons[d.weapon or "Fists"] or ItemDefinitions.Weapons.Fists
end

function InventoryService.Init(services)
	S = services
	S.NetService.handle("Equip", function(player, p)
		local vault = S.VaultService.get(player)
		if not vault then
			return false, "Not ready"
		end
		local d = vault.data.dwellers[tostring(p.dwellerId)]
		if not d or d.status == "Dead" or d.status == "Arriving" then
			return false, "Survivor unavailable"
		end
		if d.child then
			return false, d.name .. " is too young for gear"
		end
		if p.itemId == nil and type(p.kind) == "string" then
			InventoryService.unequip(vault, d, p.kind)
		else
			local ok, why = InventoryService.equip(vault, d, tostring(p.itemId))
			if not ok then
				return false, why
			end
		end
		S.VaultService.send(vault, "inventory", vault.data.inventory)
		S.DwellerService.push(vault, d)
		return true
	end)
end

return InventoryService
