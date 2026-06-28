-- LocalScript: StarterPlayer.StarterPlayerScripts.Main
-- Client bootstrap. Do not add logic here.
-- All client systems live in Controllers and register via Loader.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Loader = require(ReplicatedStorage.Framework.Loader)
Loader.load(script.Controllers)
