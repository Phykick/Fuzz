--!strict
-- Builds the game's audio objects from AudioConfig:
--   SoundService: Master, Music, SFX, UI, Ambient, Voice (SoundGroups, default volumes)
--   ReplicatedStorage.Audio: UI/Vault/Characters/Events/Resources/Rewards/Music folders holding one
--   Sound per cue (named after the cue, with its first id, volume, group and 3D roll-off).
-- AudioManager clones these Sounds to play them. The server builds everything once at start; a
-- client only fills in anything that hasn't replicated yet. Safe to call more than once.
local SoundService = game:GetService("SoundService")

local AudioConfig = require(script.Parent:WaitForChild("AudioConfig"))

local AudioLibrary = {}

local templates: { [string]: Sound } = {}

local function child(parent: Instance, name: string, class: string): Instance
	local c = parent:FindFirstChild(name)
	if c then
		return c
	end
	local n = Instance.new(class)
	n.Name = name
	n.Parent = parent
	return n
end

local function folderAt(path: string): Instance
	local f: Instance = script.Parent
	for _, part in string.split(path, "/") do
		f = child(f, part, "Folder")
	end
	return f
end

function AudioLibrary.group(name: string): SoundGroup?
	return SoundService:FindFirstChild(name) :: SoundGroup?
end

local function make(name: string, cue: any, looped: boolean)
	local folder = folderAt(cue.folder)
	local existing = folder:FindFirstChild(name)
	if existing then
		templates[name] = existing :: Sound
		return
	end
	local s = Instance.new("Sound")
	s.Name = name
	local first = cue.ids[1]
	s.SoundId = if first then AudioConfig.contentId(first) else ""
	s.Volume = cue.volume
	s.PlaybackSpeed = cue.speed or 1
	s.Looped = looped
	s.SoundGroup = AudioLibrary.group(cue.group)
	if cue.space == "3D" then
		local r = AudioConfig.RollOff[cue.rolloff or "Room"]
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = r[1]
		s.RollOffMaxDistance = r[2]
	end
	local ids, titles, sources = {}, {}, {}
	for _, a in cue.ids do
		table.insert(ids, AudioConfig.contentId(a))
		table.insert(titles, a.title)
		table.insert(sources, a.source)
	end
	s:SetAttribute("Space", cue.space or "2D")
	s:SetAttribute("Ids", table.concat(ids, " ")) -- first is preferred, the rest are alternates
	s:SetAttribute("Titles", table.concat(titles, " | "))
	s:SetAttribute("Sources", table.concat(sources, " | "))
	s.Parent = folder
	templates[name] = s
end

function AudioLibrary.ensure()
	for name, volume in AudioConfig.Groups do
		if not SoundService:FindFirstChild(name) then
			local g = Instance.new("SoundGroup")
			g.Name = name
			g.Volume = volume
			g.Parent = SoundService
		end
	end
	for top, subs in AudioConfig.Folders do
		for _, sub in subs do
			folderAt(top .. "/" .. sub)
		end
		folderAt(top)
	end
	for name, cue in AudioConfig.Sounds do
		make(name, cue, false)
	end
	for name, cue in AudioConfig.Loops do
		make(name, cue, true)
	end
	script.Parent:SetAttribute("Built", true)
end

-- The library Sound for a cue (nil before ensure()).
function AudioLibrary.template(name: string): Sound?
	return templates[name]
end

return AudioLibrary
