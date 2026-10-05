--!strict
-- Family rules shared by the server (authority) and the client (UI): who may pair up, who is
-- related, and what children / expecting mothers may do.
--
-- Dweller fields used:
--   court    = { with, start, done }   both partners while they chat + dance in Living Quarters
--   pregnant = { father, since, due }  expecting mother
--   child    = true, growAt           children (can't work, fight, explore or equip gear)
--   parents  = { motherId, fatherId? } children (and the adults they grow into)
--   restUntil                          cooldown before another romance
local Config = require(script.Parent.Config)
local Simulation = require(script.Parent.Simulation)

local Family = {}

function Family.isChild(d: any): boolean
	return d.child == true
end

function Family.canWork(d: any): boolean
	return d.child ~= true
end

-- Children and expecting mothers keep out of fights and fires.
function Family.canFight(d: any): boolean
	return d.child ~= true and d.pregnant == nil
end

function Family.canExplore(d: any): (boolean, string?)
	if d.child then
		return false, d.name .. " is too young to go outside"
	end
	if d.pregnant then
		return false, d.name .. " is expecting and staying safe inside"
	end
	return true, nil
end

-- Parents, children and (half-)siblings never pair up.
function Family.related(a: any, b: any): boolean
	local pa, pb = a.parents, b.parents
	if pa and table.find(pa, b.id) then
		return true
	end
	if pb and table.find(pb, a.id) then
		return true
	end
	if pa and pb then
		for _, id in pa do
			if table.find(pb, id) then
				return true
			end
		end
	end
	return false
end

-- Seconds the pair spends chatting and dancing; charming survivors are quicker.
function Family.courtDuration(a: any, b: any): number
	local cha = (Simulation.stat(a, "SOC") + Simulation.stat(b, "SOC")) / 2
	local lo, hi = Config.COURT_TIME[1], Config.COURT_TIME[2]
	return math.clamp(hi - (cha - 1) * (hi - lo) / 9, lo, hi)
end

function Family.clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

-- One-line family status for the profile panel (nil when there is nothing to say).
function Family.note(d: any, dwellers: { [string]: any }, now: number): string?
	if d.status == "Arriving" then
		return "Walking to the shelter"
	end
	if d.status == "Waiting" then
		return "Waiting outside the bunker door"
	end
	if d.child and d.growAt then
		return "Grows up in " .. Family.clock(d.growAt - now)
	end
	if d.pregnant then
		return "Expecting a baby - due in " .. Family.clock(d.pregnant.due - now)
	end
	if d.court then
		local p = dwellers[d.court.with]
		return "Getting to know " .. (if p then (string.match(p.name, "^(%S+)") or p.name) else "someone")
	end
	return nil
end

return Family
