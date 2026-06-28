--!strict
-- ModuleScript: StarterPlayer.StarterPlayerScripts.Main.Controllers.HUDController
-- Listens for UpdateCurrencyDisplay and UpdateFactionDisplay from the server
-- and keeps the HUD labels up to date.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net    = require(ReplicatedStorage.Framework.Net)
local Logger = require(ReplicatedStorage.Framework.Logger)

local SCOPE  = "HUDController"
local player = Players.LocalPlayer

local HUDController = {}

-- Build a minimal HUD in code. Replace with a proper StarterGui asset in production.
local hudGui: ScreenGui?
local monLabel:    TextLabel?
local silverLabel: TextLabel?
local ryoLabel:    TextLabel?
local factionLabel: TextLabel?
local tierLabel:   TextLabel?
local lineageLabel: TextLabel?

local function buildHud()
	if hudGui then return end

	local gui = Instance.new("ScreenGui")
	gui.Name           = "HUD"
	gui.ResetOnSpawn   = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder   = 1

	local panel = Instance.new("Frame")
	panel.Size              = UDim2.fromOffset(220, 142)
	panel.Position          = UDim2.new(1, -228, 0, 8)
	panel.BackgroundColor3  = Color3.fromRGB(12, 10, 8)
	panel.BackgroundTransparency = 0.35
	panel.BorderSizePixel   = 0
	panel.Parent            = gui

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.Padding       = UDim.new(0, 2)
	list.SortOrder     = Enum.SortOrder.LayoutOrder
	list.Parent        = panel

	local pad = Instance.new("UIPadding")
	pad.PaddingTop   = UDim.new(0, 8)
	pad.PaddingLeft  = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent       = panel

	local function makeLabel(order: number, default: string): TextLabel
		local lbl = Instance.new("TextLabel")
		lbl.LayoutOrder          = order
		lbl.Size                 = UDim2.new(1, 0, 0, 18)
		lbl.BackgroundTransparency = 1
		lbl.Text                 = default
		lbl.TextColor3           = Color3.fromRGB(210, 190, 140)
		lbl.TextSize             = 14
		lbl.Font                 = Enum.Font.Antique
		lbl.TextXAlignment       = Enum.TextXAlignment.Left
		lbl.Parent               = panel
		return lbl
	end

	factionLabel = makeLabel(1, "Faction: —")
	monLabel     = makeLabel(2, "Mon: —")
	silverLabel  = makeLabel(3, "Silver: —")
	ryoLabel     = makeLabel(4, "Ryo: —")
	tierLabel    = makeLabel(5, "Spirit: —")
	lineageLabel = makeLabel(6, "Lineage: Gen 0")

	gui.Parent = player.PlayerGui
	hudGui     = gui
end

function HUDController:Init()
	Net.onClientEvent("UpdateCurrencyDisplay", function(payload: any)
		local p = payload :: { mon: number, silver: number, ryo: number }
		if monLabel    then monLabel.Text    = string.format("Mon: %d",    p.mon)    end
		if silverLabel then silverLabel.Text = string.format("Silver: %d", p.silver) end
		if ryoLabel    then ryoLabel.Text    = string.format("Ryo: %d",    p.ryo)    end
		Logger.info(SCOPE, string.format("Balance — mon:%d silver:%d ryo:%d",
			p.mon, p.silver, p.ryo))
	end)

	Net.onClientEvent("UpdateFactionDisplay", function(payload: any)
		local p = payload :: { faction: string?, rank: string? }
		if factionLabel then
			if p.faction then
				factionLabel.Text = string.format("[%s] %s", p.faction, p.rank or "")
			else
				factionLabel.Text = "Faction: —"
			end
		end
	end)

	Net.onClientEvent("UpdateMoralityDisplay", function(payload: any)
		local p = payload :: { tierName: string, score: number }
		if tierLabel then
			tierLabel.Text = string.format("Spirit: %s (%d)", p.tierName, p.score)
		end
	end)

	Net.onClientEvent("UpdateLineageDisplay", function(payload: any)
		local p = payload :: { ancestorName: string?, generationCount: number }
		if lineageLabel then
			local gen = p.generationCount or 0
			if p.ancestorName ~= nil and p.ancestorName ~= "" then
				lineageLabel.Text = string.format("Lineage: Gen %d (%s)", gen, p.ancestorName)
			else
				lineageLabel.Text = string.format("Lineage: Gen %d", gen)
			end
		end
	end)
end

function HUDController:Start()
	buildHud()
end

return HUDController
