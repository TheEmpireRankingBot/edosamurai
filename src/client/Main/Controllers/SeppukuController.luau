--!strict
-- ModuleScript: StarterPlayer.StarterPlayerScripts.Main.Controllers.SeppukuController
-- Character menu seppuku option. UI only requests; server owns eligibility and data.

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net    = require(ReplicatedStorage.Framework.Net)
local Logger = require(ReplicatedStorage.Framework.Logger)

local SCOPE = "SeppukuController"
local player = Players.LocalPlayer

local SeppukuController = {}

local gui: ScreenGui?
local openButton: TextButton?
local panel: Frame?
local seppukuButton: TextButton?
local reasonLabel: TextLabel?
local confirmFrame: Frame?
local pending = false
local eligible = false

local function applyStatus(status: any)
    eligible = type(status) == "table" and status.eligible == true
    local reason = if type(status) == "table" and type(status.reason) == "string" then status.reason else "Status unavailable"
    if seppukuButton then
        seppukuButton.Active = eligible and not pending
        seppukuButton.AutoButtonColor = eligible and not pending
        seppukuButton.Text = if pending then "Pending..." elseif eligible then "Seppuku" else "Seppuku Locked"
        seppukuButton.TextTransparency = eligible and 0 or 0.35
        seppukuButton.BackgroundColor3 = if eligible then Color3.fromRGB(74, 34, 30) else Color3.fromRGB(35, 32, 30)
    end
    if reasonLabel then
        reasonLabel.Text = reason
        reasonLabel.TextColor3 = if eligible then Color3.fromRGB(205, 185, 135) else Color3.fromRGB(170, 130, 120)
    end
end

local function refreshStatus()
    task.spawn(function()
        local ok, status = pcall(function()
            return Net.invokeServer("GetSeppukuStatus")
        end)
        if ok then
            applyStatus(status)
        else
            applyStatus({ eligible = false, reason = "Status unavailable" })
        end
    end)
end

local function showConfirm(show: boolean)
    if confirmFrame then confirmFrame.Visible = show end
end

local function build()
    if gui then return end
    local g = Instance.new("ScreenGui")
    g.Name = "CharacterMenu"
    g.ResetOnSpawn = false
    g.IgnoreGuiInset = true
    g.DisplayOrder = 7

    local button = Instance.new("TextButton")
    button.Name = "CharacterButton"
    button.Size = UDim2.fromOffset(112, 30)
    button.Position = UDim2.new(0, 8, 1, -46)
    button.AnchorPoint = Vector2.new(0, 1)
    button.BackgroundColor3 = Color3.fromRGB(22, 18, 14)
    button.BorderSizePixel = 0
    button.Text = "Character"
    button.TextColor3 = Color3.fromRGB(225, 205, 160)
    button.Font = Enum.Font.GothamMedium
    button.TextSize = 13
    button.Parent = g
    openButton = button

    local p = Instance.new("Frame")
    p.Name = "Panel"
    p.Size = UDim2.fromOffset(300, 184)
    p.Position = UDim2.new(0, 8, 1, -84)
    p.AnchorPoint = Vector2.new(0, 1)
    p.BackgroundColor3 = Color3.fromRGB(18, 14, 11)
    p.BorderSizePixel = 0
    p.Visible = false
    p.Parent = g
    panel = p

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -24, 0, 28)
    title.Position = UDim2.fromOffset(12, 10)
    title.BackgroundTransparency = 1
    title.Text = "Character"
    title.TextColor3 = Color3.fromRGB(230, 210, 165)
    title.Font = Enum.Font.Antique
    title.TextSize = 20
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = p

    local reason = Instance.new("TextLabel")
    reason.Size = UDim2.new(1, -24, 0, 42)
    reason.Position = UDim2.fromOffset(12, 42)
    reason.BackgroundTransparency = 1
    reason.Text = "Checking..."
    reason.TextColor3 = Color3.fromRGB(170, 150, 120)
    reason.Font = Enum.Font.Gotham
    reason.TextSize = 13
    reason.TextWrapped = true
    reason.TextXAlignment = Enum.TextXAlignment.Left
    reason.TextYAlignment = Enum.TextYAlignment.Top
    reason.Parent = p
    reasonLabel = reason

    local seppuku = Instance.new("TextButton")
    seppuku.Name = "SeppukuButton"
    seppuku.Size = UDim2.new(1, -24, 0, 36)
    seppuku.Position = UDim2.fromOffset(12, 92)
    seppuku.BackgroundColor3 = Color3.fromRGB(35, 32, 30)
    seppuku.BorderSizePixel = 0
    seppuku.Text = "Seppuku Locked"
    seppuku.TextColor3 = Color3.fromRGB(235, 220, 185)
    seppuku.Font = Enum.Font.GothamBold
    seppuku.TextSize = 14
    seppuku.Parent = p
    seppukuButton = seppuku

    local hint = Instance.new("TextLabel")
    hint.Size = UDim2.new(1, -24, 0, 20)
    hint.Position = UDim2.fromOffset(12, 136)
    hint.BackgroundTransparency = 1
    hint.Text = "Press M to toggle"
    hint.TextColor3 = Color3.fromRGB(130, 115, 90)
    hint.Font = Enum.Font.Gotham
    hint.TextSize = 12
    hint.TextXAlignment = Enum.TextXAlignment.Left
    hint.Parent = p

    local c = Instance.new("Frame")
    c.Name = "Confirm"
    c.Size = UDim2.fromOffset(300, 116)
    c.Position = UDim2.new(0, 0, 0, -124)
    c.BackgroundColor3 = Color3.fromRGB(12, 9, 8)
    c.BorderSizePixel = 0
    c.Visible = false
    c.Parent = p
    confirmFrame = c

    local ct = Instance.new("TextLabel")
    ct.Size = UDim2.new(1, -24, 0, 42)
    ct.Position = UDim2.fromOffset(12, 10)
    ct.BackgroundTransparency = 1
    ct.Text = "Confirm seppuku?"
    ct.TextColor3 = Color3.fromRGB(230, 210, 165)
    ct.Font = Enum.Font.Antique
    ct.TextSize = 18
    ct.Parent = c

    local confirm = Instance.new("TextButton")
    confirm.Size = UDim2.fromOffset(126, 34)
    confirm.Position = UDim2.fromOffset(12, 66)
    confirm.BackgroundColor3 = Color3.fromRGB(92, 32, 28)
    confirm.BorderSizePixel = 0
    confirm.Text = "Confirm"
    confirm.TextColor3 = Color3.fromRGB(245, 225, 205)
    confirm.Font = Enum.Font.GothamBold
    confirm.TextSize = 14
    confirm.Parent = c

    local cancel = Instance.new("TextButton")
    cancel.Size = UDim2.fromOffset(126, 34)
    cancel.Position = UDim2.fromOffset(162, 66)
    cancel.BackgroundColor3 = Color3.fromRGB(36, 31, 27)
    cancel.BorderSizePixel = 0
    cancel.Text = "Cancel"
    cancel.TextColor3 = Color3.fromRGB(220, 200, 170)
    cancel.Font = Enum.Font.GothamMedium
    cancel.TextSize = 14
    cancel.Parent = c

    button.Activated:Connect(function()
        if panel then
            panel.Visible = not panel.Visible
            if panel.Visible then refreshStatus() else showConfirm(false) end
        end
    end)

    seppuku.Activated:Connect(function()
        if eligible and not pending then showConfirm(true) end
    end)

    confirm.Activated:Connect(function()
        if pending then return end
        pending = true
        showConfirm(false)
        applyStatus({ eligible = false, reason = "Seppuku requested" })
        Net.fireServer("RequestSeppuku", { source = "voluntary" })
        Logger.info(SCOPE, "Requested seppuku")
    end)
    cancel.Activated:Connect(function() showConfirm(false) end)

    g.Parent = player:WaitForChild("PlayerGui")
    gui = g
end

function SeppukuController:Init()
    Net.onClientEvent("SeppukuStatus", function(status: any)
        pending = false
        applyStatus(status)
    end)
    Net.onClientEvent("SeppukuAnim", function(payload: any)
        local duration = if type(payload) == "table" and type(payload.duration) == "number" then payload.duration else 1.2
        Logger.info(SCOPE, string.format("Seppuku animation placeholder (%.1fs)", duration))
    end)
end

function SeppukuController:Start()
    build()
    refreshStatus()
    UserInputService.InputBegan:Connect(function(input: InputObject, gp: boolean)
        if gp then return end
        if input.KeyCode == Enum.KeyCode.M then
            if panel then
                panel.Visible = not panel.Visible
                if panel.Visible then refreshStatus() else showConfirm(false) end
            end
        end
    end)
end

return SeppukuController
