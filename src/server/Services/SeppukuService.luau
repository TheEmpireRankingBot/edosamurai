--!strict
-- ModuleScript: ServerScriptService.Services.SeppukuService
-- Clean self-death and lineage inheritance. Server-authoritative; clients only request.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loader        = require(ReplicatedStorage.Framework.Loader)
local Logger        = require(ReplicatedStorage.Framework.Logger)
local Net           = require(ReplicatedStorage.Framework.Net)
local Validate      = require(ReplicatedStorage.Framework.Validate)
local SeppukuConfig = require(ReplicatedStorage.Config.SeppukuConfig)

local SCOPE = "SeppukuService"

local SeppukuService = {}

local dataService:    any
local economyService: any
local combatService:  any
local duelService:    any

local inProgress: { [number]: boolean } = {}

type Lineage = { ancestorName: string?, inheritedMon: number, generationCount: number }
type Reputation = { renown: number, notoriety: number }

local function normalizeLineage(raw: any): Lineage
    local lineage = if type(raw) == "table" then raw else {}
    local ancestor = lineage.ancestorName
    local inherited = tonumber(lineage.inheritedMon) or 0
    local generation = tonumber(lineage.generationCount) or 0
    return {
        ancestorName = if type(ancestor) == "string" and ancestor ~= "" then ancestor else nil,
        inheritedMon = math.max(0, math.floor(inherited)),
        generationCount = math.max(0, math.floor(generation)),
    }
end

local function normalizeReputation(raw: any): Reputation
    local rep = if type(raw) == "table" then raw else {}
    return {
        renown = math.max(0, math.floor(tonumber(rep.renown) or 0)),
        notoriety = math.max(0, math.floor(tonumber(rep.notoriety) or 0)),
    }
end

local function familyNameFor(player: Player): string
    if player.DisplayName ~= nil and player.DisplayName ~= "" then
        return player.DisplayName
    end
    return player.Name
end

local function profileReady(player: Player): boolean
    return dataService.getProfile(player) ~= nil
end

local function pushLineage(player: Player)
    if not profileReady(player) then return end
    local lineage = normalizeLineage(dataService.get(player, "lineage"))
    Net.fireClient("UpdateLineageDisplay", player, {
        ancestorName = lineage.ancestorName,
        generationCount = lineage.generationCount,
        inheritedMon = lineage.inheritedMon,
    })
end

function SeppukuService.getEligibility(player: Player): any
    if not profileReady(player) then
        return { eligible = false, reason = "Profile is still loading", kind = "loading", threshold = SeppukuConfig.DISGRACE_NOTORIETY_THRESHOLD, notoriety = 0 }
    end

    local rep = normalizeReputation(dataService.get(player, "reputation"))
    local state = combatService.getState(player)
    if state ~= nil and state.isDead then
        return { eligible = false, reason = "You are already dead", kind = "dead", threshold = SeppukuConfig.DISGRACE_NOTORIETY_THRESHOLD, notoriety = rep.notoriety }
    end

    local downedBy = combatService.getDownedBy(player)
    if state ~= nil and state.isDowned then
        if downedBy ~= nil and duelService.areDueling(downedBy, player) then
            return { eligible = true, reason = "Duel loss may be answered with seppuku", kind = "duelLoss", threshold = SeppukuConfig.DISGRACE_NOTORIETY_THRESHOLD, notoriety = rep.notoriety }
        end
        return { eligible = false, reason = "You are downed outside a duel", kind = "downed", threshold = SeppukuConfig.DISGRACE_NOTORIETY_THRESHOLD, notoriety = rep.notoriety }
    end

    if combatService.hasActiveAttacker(player) then
        return { eligible = false, reason = "Cannot perform seppuku while an attacker is active", kind = "combat", threshold = SeppukuConfig.DISGRACE_NOTORIETY_THRESHOLD, notoriety = rep.notoriety }
    end

    if rep.notoriety >= SeppukuConfig.DISGRACE_NOTORIETY_THRESHOLD then
        return { eligible = true, reason = "Disgrace demands an answer", kind = "disgrace", threshold = SeppukuConfig.DISGRACE_NOTORIETY_THRESHOLD, notoriety = rep.notoriety }
    end

    return { eligible = true, reason = "Voluntary seppuku is available", kind = "voluntary", threshold = SeppukuConfig.DISGRACE_NOTORIETY_THRESHOLD, notoriety = rep.notoriety }
end

local function pushStatus(player: Player)
    Net.fireClient("SeppukuStatus", player, SeppukuService.getEligibility(player))
end

function SeppukuService.grantPendingInheritance(player: Player)
    if not profileReady(player) then return end
    local lineage = normalizeLineage(dataService.get(player, "lineage"))
    local amount = lineage.inheritedMon
    if amount <= 0 then
        pushLineage(player)
        return
    end

    -- Zero first so a crash/rejoin cannot claim the same inheritance twice.
    lineage.inheritedMon = 0
    dataService.set(player, "lineage", lineage)
    economyService.addCurrency(player, "mon", amount)
    pushLineage(player)
    Logger.info(SCOPE, string.format("Inheritance granted: %s +%d mon (gen=%d)", player.Name, amount, lineage.generationCount))
end

function SeppukuService.requestSeppuku(player: Player): boolean
    if inProgress[player.UserId] then
        Net.fireClient("SeppukuStatus", player, { eligible = false, reason = "Seppuku is already in progress", kind = "pending", threshold = SeppukuConfig.DISGRACE_NOTORIETY_THRESHOLD, notoriety = 0 })
        return false
    end

    local eligibility = SeppukuService.getEligibility(player)
    if eligibility.eligible ~= true then
        Net.fireClient("SeppukuStatus", player, eligibility)
        Logger.warn(SCOPE, player.Name .. " seppuku rejected: " .. tostring(eligibility.reason))
        return false
    end

    inProgress[player.UserId] = true
    local ok = Logger.try(SCOPE .. "/requestSeppuku", function()
        local bal = economyService.getBalance(player) or { mon = 0, silver = 0, ryo = 0 }
        local mon = math.max(0, math.floor(tonumber((bal :: any).mon) or 0))
        local inherited = math.floor(mon * SeppukuConfig.SEPPUKU_INHERITANCE_RATE)

        local lineage = normalizeLineage(dataService.get(player, "lineage"))
        lineage.ancestorName = familyNameFor(player)
        lineage.inheritedMon = inherited
        lineage.generationCount += 1
        dataService.set(player, "lineage", lineage)

        if mon > 0 then
            local removed = economyService.removeCurrency(player, "mon", mon)
            if not removed then error("failed to remove current mon for inheritance snapshot") end
        else
            economyService.fireBalance(player)
        end

        local rep = normalizeReputation(dataService.get(player, "reputation"))
        rep.notoriety = 0
        dataService.set(player, "reputation", rep)

        pushLineage(player)
        Net.fireClient("SeppukuAnim", player, { duration = SeppukuConfig.SEPPUKU_ANIM_WINDUP })
        Net.fireClient("SeppukuStatus", player, { eligible = false, reason = "Seppuku accepted", kind = "accepted", threshold = SeppukuConfig.DISGRACE_NOTORIETY_THRESHOLD, notoriety = 0 })

        local downedBy = combatService.getDownedBy(player)
        if downedBy ~= nil and duelService.areDueling(downedBy, player) then
            duelService.endDuelBetween(downedBy, player, "seppuku")
        end

        Logger.info(SCOPE, string.format(
            "%s performed seppuku | inherited=%d | generation=%d | kind=%s",
            player.Name, inherited, lineage.generationCount, tostring(eligibility.kind)
        ))
    end)

    if not ok then
        inProgress[player.UserId] = nil
        pushStatus(player)
        return false
    end

    task.delay(SeppukuConfig.SEPPUKU_ANIM_WINDUP, function()
        if player.Parent ~= nil then
            combatService.performCleanDeath(player, "seppuku")
        end
        inProgress[player.UserId] = nil
    end)
    return true
end

function SeppukuService:Init()
    dataService    = Loader.get("DataService")
    economyService = Loader.get("EconomyService")
    combatService  = Loader.get("CombatService")
    duelService    = Loader.get("DuelService")
end

function SeppukuService:Start()
    Net.registerClientEvent("UpdateLineageDisplay")
    Net.registerClientEvent("SeppukuStatus")
    Net.registerClientEvent("SeppukuAnim")

    Net.registerFunction("GetSeppukuStatus",
        function(): (boolean, string?) return true, nil end,
        function(player: Player): any
            return SeppukuService.getEligibility(player)
        end,
        { rate = 2 }
    )

    Net.registerEvent("RequestSeppuku",
        Validate.shape({ source = Validate.literal(SeppukuConfig.RequestSources) }),
        { rate = 1 }
    )
    Net.onEvent("RequestSeppuku", function(player: Player, _payload: any)
        SeppukuService.requestSeppuku(player)
    end)

    local function hook(player: Player)
        player.CharacterAdded:Connect(function(_char: Model)
            task.defer(function()
                local waited = 0
                while player.Parent ~= nil and dataService.getProfile(player) == nil and waited < 30 do
                    task.wait(0.2)
                    waited += 0.2
                end
                if player.Parent ~= nil then
                    SeppukuService.grantPendingInheritance(player)
                    pushStatus(player)
                end
            end)
        end)
        task.spawn(function()
            local waited = 0
            while player.Parent ~= nil and dataService.getProfile(player) == nil and waited < 30 do
                task.wait(0.2)
                waited += 0.2
            end
            if player.Parent ~= nil then
                if player.Character ~= nil then
                    SeppukuService.grantPendingInheritance(player)
                else
                    pushLineage(player)
                end
                pushStatus(player)
            end
        end)
    end

    Players.PlayerAdded:Connect(hook)
    for _, player in Players:GetPlayers() do hook(player) end

    Players.PlayerRemoving:Connect(function(player: Player)
        inProgress[player.UserId] = nil
    end)
end

return SeppukuService
