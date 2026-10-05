--!strict
-- Builds the shared audio library once at server start (SoundGroups in SoundService, Sound
-- objects under ReplicatedStorage.Audio) so every client gets the same organised set.
-- All playback is client-side (StarterPlayerScripts/Client/Controllers/AudioManager).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AudioService = {}

function AudioService.Init()
	local AudioLibrary = require(ReplicatedStorage:WaitForChild("Audio"):WaitForChild("AudioLibrary"))
	AudioLibrary.ensure()
end

return AudioService
