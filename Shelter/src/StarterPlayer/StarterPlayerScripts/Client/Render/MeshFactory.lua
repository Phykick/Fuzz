--!strict
-- MeshFactory: clones uploaded Blender mesh templates (ReplicatedStorage.Assets.Meshes, built by
-- the Underhaven Asset Uploader plugin). Each template is a Model of MeshParts positioned relative
-- to the asset origin (WorldPivot = identity). Tint slots ("wall", "suit", ...) recolour parts.
-- Markers authored in Blender (MK_*) are stored as CFrame attributes on the template.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MeshFactory = {}

type Template = { model: Model, markers: { [string]: CFrame } }

local templates: { [string]: Template } = {}
local missing: { [string]: boolean } = {}
local root: Folder? = nil

local function folder(): Folder?
	if root then
		return root
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	root = assets and assets:FindFirstChild("Meshes") :: Folder?
	return root
end

function MeshFactory.load()
	folder()
end

function MeshFactory.has(name: string): boolean
	local f = folder()
	return f ~= nil and f:FindFirstChild(name) ~= nil
end

function MeshFactory.template(name: string): Template?
	local t = templates[name]
	if t then
		return t
	end
	local f = folder()
	local model = f and f:FindFirstChild(name) :: Model?
	if not model then
		if not missing[name] then
			missing[name] = true
			warn("[MeshFactory] missing mesh template " .. name .. " (run the Underhaven uploader)")
		end
		return nil
	end
	local markers = {}
	for k, v in model:GetAttributes() do
		if string.sub(k, 1, 3) == "MK_" and typeof(v) == "CFrame" then
			-- Blender de-duplicates object names across assets ("EyeL.001"): strip that suffix.
			local mk = string.gsub(string.sub(k, 4), "%.%d+$", "")
			markers[mk] = v
		end
	end
	t = { model = model, markers = markers }
	templates[name] = t
	return t
end

function MeshFactory.marker(name: string, markerName: string): CFrame?
	local t = MeshFactory.template(name)
	return t and t.markers[markerName]
end

-- Clone an asset, recolour tint slots and place it. tints: { slot = Color3 }.
function MeshFactory.spawn(name: string, cf: CFrame, tints: { [string]: Color3 }?, parent: Instance?): Model
	local t = MeshFactory.template(name)
	local model: Model
	if t then
		model = t.model:Clone()
		if tints then
			for _, p in model:GetChildren() do
				local slot = p:GetAttribute("Tint")
				if slot and tints[slot] then
					(p :: BasePart).Color = tints[slot]
				end
			end
		end
	else
		model = Instance.new("Model")
		model.Name = name
	end
	model:PivotTo(cf)
	model.Parent = parent
	return model
end

function MeshFactory.preload(_names: { string }) end

return MeshFactory
