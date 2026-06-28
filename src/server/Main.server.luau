-- Script: ServerScriptService.Main
-- Server bootstrap. Do not add logic here.
-- All game systems live in Services and register via Loader.

local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Loader = require(ReplicatedStorage.Framework.Loader)
Loader.load(ServerScriptService.Services)
