--!strict
-- ModuleScript: StarterPlayer.StarterPlayerScripts.Main.Controllers.TimeController
-- Shows a small world clock + day counter, driven by the server's UpdateGameTime.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Framework.Net)

local player = Players.LocalPlayer
local TimeController = {}

local clockLabel: TextLabel?
local dayLabel:   TextLabel?

local function build()
	if clockLabel then return end
	local gui = Instance.new("ScreenGui")
	gui.Name = "WorldClock"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 2

	local panel = Instance.new("Frame")
	panel.Size = UDim2.fromOffset(132, 50)
	panel.Position = UDim2.fromOffset(8, 8)
	panel.BackgroundColor3 = Color3.fromRGB(12, 10, 8)
	panel.BackgroundTransparency = 0.35
	panel.BorderSizePixel = 0
	panel.Parent = gui

	local clock = Instance.new("TextLabel")
	clock.Size = UDim2.new(1, 0, 0, 26)
	clock.Position = UDim2.fromOffset(0, 4)
	clock.BackgroundTransparency = 1
	clock.TextColor3 = Color3.fromRGB(230, 210, 150)
	clock.Font = Enum.Font.Antique
	clock.TextSize = 20
	clock.Text = "--:--"
	clock.Parent = panel
	clockLabel = clock

	local day = Instance.new("TextLabel")
	day.Size = UDim2.new(1, 0, 0, 16)
	day.Position = UDim2.fromOffset(0, 30)
	day.BackgroundTransparency = 1
	day.TextColor3 = Color3.fromRGB(190, 175, 140)
	day.Font = Enum.Font.Gotham
	day.TextSize = 13
	day.Text = "Day -"
	day.Parent = panel
	dayLabel = day

	gui.Parent = player:WaitForChild("PlayerGui")
end

function TimeController:Init()
	Net.onClientEvent("UpdateGameTime", function(payload: any)
		local p = payload :: { hour: number, day: number, isNight: boolean }
		if clockLabel then
			clockLabel.Text = string.format("%02d:00 %s", p.hour, p.isNight and "(night)" or "(day)")
		end
		if dayLabel then dayLabel.Text = "Day " .. tostring(p.day) end
	end)
end

function TimeController:Start()
	build()
end

return TimeController
