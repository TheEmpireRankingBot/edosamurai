--!strict
-- ModuleScript: ReplicatedStorage.GameJournal  (Rojo: src/shared/GameJournal.luau)
-- ============================================================================
--  THE QUELLED LAND — GAME JOURNAL (single source of truth)
-- ============================================================================
--  This module documents the WHOLE build so every future change stays coherent.
--  It is data only (no behaviour). Read PILLARS before adding anything; check
--  FEEDBACK_LOOPS so new systems reinforce the existing ones; consult
--  BUILDER_TAGS for what the greybox must contain to light every system up.
--  A readable mirror lives at /docs/GAME_JOURNAL.md in the repo.
--  Last consolidation pass: 2026-06-28.
-- ============================================================================

local GameJournal = {}

GameJournal.Meta = {
	project   = "The Quelled Land",
	place     = "Edo: Rising Sun",
	genre     = "Edo-period Restricted (18+) Roblox RP",
	language  = "Luau --!strict, fully typed",
	layers    = "Foundation + L1 Faction/Economy/Morality + L2 Combat/Duels + L3 NPC/Time/Gather + L4 Game-Feel + L5 Priest/Disaster",
	lastPass  = "2026-06-28 (Codex Task 2: Seppuku -> Lineage/Inheritance)",
	moduleCount = 50,
}

-- ============================================================================
-- PROJECT & PILLARS
-- ============================================================================
GameJournal.Pillars = {
	premise = "A small Edo-period town sits on a thin place where blood and death "
		.. "breed kegare (spiritual pollution). Players choose a faction (Samurai, "
		.. "Merchant, Civilian, Priest) and live, trade, fight, and worship while the "
		.. "rites hold the seal against disaster. Combat is lethal but contextual; "
		.. "honor and corruption are a single visible axis.",
	pillars = {
		"CORE HOOK — Gi/Shura is a TEMPTATION, not a punishment. Bloodlust (executing "
			.. "the helpless) grants real power (damageBonus at T3+) but corrupts: "
			.. "desaturation, vignette, hand-shake, and an accuracy penalty at T4+. "
			.. "Power now is paid for with corruption later. NEVER balance this away.",
		"LETHAL BUT CONTEXTUAL — you cannot freely murder. Town (SafeZone) is sacrosanct, "
			.. "same-faction is protected, real fights happen in sanctioned duels or the "
			.. "lawless wilderness. Down -> Execute (Shura) or Spare (Gi) is the moral fulcrum.",
		"ALIVE WITH FEW PLAYERS — scheduled NPCs populate the town and a solo player can "
			.. "complete the full economy (gather -> sell -> buy) with nobody else online.",
		"DEATH IS MEANINGFUL — every death broadcasts a jisei (death poem) to nearby "
			.. "players; players may compose their own ahead of time.",
		"PRIEST = NON-COMBAT POWER — only priests purify others' corruption (harae) and "
			.. "only priests quell the disasters that threaten the whole server.",
	},
	architecture = {
		"Server is the only authority; clients only REQUEST.",
		"Every remote routes through Net (token-bucket rate limit + Validate guard).",
		"All player data through DataService (ProfileStore-backed); never DataStore direct.",
		"Services use Loader Init(cache deps)/Start(wire) two-phase boot.",
		"No magic numbers: tunables live in shared Config modules.",
	},
}

-- ============================================================================
-- SYSTEM MANIFEST  (per service: purpose / remotes / config / schema / status)
-- ============================================================================
-- status: "working" = verified live or by trace; "partial" = built but gated by
-- missing content/players; "gap" = net-new piece not built (see KnownGaps).
GameJournal.SystemManifest = {
	-- ---- Foundation ----
	{ name="Loader", kind="framework", status="working",
		purpose="Two-phase service/controller loader. Init=cache deps, Start=wire. Halts loudly on Init failure.",
		key={"load(folder)","get(name)"} },
	{ name="Net", kind="framework", status="working",
		purpose="The only networking path. Token-bucket rate limit + Validate guard on EVERY call. No raw remotes exist anywhere.",
		key={"registerEvent","onEvent","fireClient","fireAllClients","registerClientEvent","registerFunction","fireServer","onClientEvent","invokeServer"} },
	{ name="Validate", kind="framework", status="working",
		purpose="Runtime type guards for remote args (string/integer/positiveInteger/boolean/table/vector/instanceOf/player/shape/literal)." },
	{ name="Logger", kind="framework", status="working",
		purpose="Structured logging + Logger.try (the ONLY sanctioned pcall wrapper)." },
	{ name="DataService", kind="service", status="working",
		purpose="Sole data authority. ProfileStore-backed. get/set(whitelisted key)/getProfile, autosave, BindToClose release.",
		schema="ALL fields (via get/set)", deps={"ProfileStore","DataSchema"} },
	{ name="PlayerService", kind="service", status="working",
		purpose="Template service. Owns RequestPing (pipeline proof).", remotes={"RequestPing"}, deps={"DataService"} },

	-- ---- Layer 1 ----
	{ name="FactionService", kind="service", status="working",
		purpose="Faction selection, rank, permissions, faction-spawn teleport, respawn placement.",
		remotes={"GetFactionStatus","RequestFactionSelect","RequestResetFaction(Studio-only)","UpdateFactionDisplay","ShowFactionSelect"},
		config="FactionDefs", schema={"faction","rank"}, deps={"DataService","EconomyService"},
		api={"getFaction","getRank","hasPermission","canChoose","getSpawnTag","teleportToFactionSpawn"} },
	{ name="EconomyService", kind="service", status="working",
		purpose="Dupe-safe currency authority. add/remove/transfer/exchange. Changer fee + offering = mon sinks. Pushes balance on join (added this pass).",
		remotes={"RequestExchange (ORPHAN: no client caller)","UpdateCurrencyDisplay"},
		config="EconomyConfig", schema={"currency"}, deps={"DataService"} },
	{ name="MoralityService", kind="service", status="working",
		purpose="Owns gi_shura axis, social standing, kill logging, meditation (server-timed), combat-modifier reads. Pushes corruption visuals on join.",
		remotes={"TriggerMeditationStart","TriggerMeditationEnd","UpdateMoralityDisplay"},
		config="MoralityConfig", schema={"gi_shura","shura_kills(write-only)"}, deps={"DataService"},
		api={"applyKill","applyGi","adjust","getTier","getMoralityStanding","getCombatModifiers","startMeditation","completeMeditation"} },

	-- ---- Layer 2 ----
	{ name="CombatService", kind="service", status="working for player targets; solo part testing uses Studio-only harness",
		purpose="Server-authoritative melee. Hit validation (reach/cooldown/stamina/weapon-spoof), block/parry/dodge, armor+GapZone, Shura damage/accuracy, downed->execute/spare, kill+jisei+respawn. Exposes recent-attacker detection and clean self-death for SeppukuService. Reads PriestService buffs. NOTE: production RequestMeleeHit resolves targets through Players:GetPlayerByUserId; loose NPC/part dummies cannot exercise true downed/kill flow without changing combat logic.",
		remotes={"RequestMeleeHit","RequestBlock","RequestDodge","RequestExecuteOrSpare","RequestEquipWeapon","RequestSetJisei","HitConfirmed","CombatFeedback","StaminaUpdate","ShowDownedPrompt","EnterDownedState","ExitDownedState","ShowJiseiPoem","CombatLoadout","CombatFeel"},
		config={"CombatConfig","FeelConfig"}, schema={"equipped","jiseiPoem","stats(totalKills/honorableKills)"},
		deps={"DataService","DuelService","FactionService","MoralityService","PriestService"},
		signals={"onLethalEvent(kind,victim,attacker,pos)"} },
	{ name="DuelService", kind="service", status="working",
		purpose="Anti-griefing authority. canDamage gate (safezone/same-faction/duel/kirisute), duel invites+accept, notoriety/bounty flag stub.",
		remotes={"RequestDuel","AcceptDuel","ShowDuelInvite","DuelStarted","DuelEnded"},
		schema={"stats(duelsWon/duelsLost)","reputation(notoriety)"}, deps={"DataService","FactionService","MoralityService"},
		api={"canDamage","inSafeZone","areDueling","flagAggression","endDuelBetween"} },
	{ name="SeppukuService", kind="service", status="working",
		purpose="Clean self-death + persistent lineage inheritance. Validates eligibility, snapshots 75% mon into lineage, clears notoriety, broadcasts jisei through CombatService, respawns, grants inheritedMon once, and pushes lineage HUD/status.",
		remotes={"GetSeppukuStatus","RequestSeppuku","UpdateLineageDisplay","SeppukuStatus","SeppukuAnim"},
		config="SeppukuConfig", schema={"lineage","currency(mon via EconomyService)","reputation(notoriety)"}, deps={"DataService","EconomyService","CombatService","DuelService"},
		api={"getEligibility","requestSeppuku","grantPendingInheritance"} },

	-- ---- Layer 3 ----
	{ name="InventoryService", kind="service", status="working",
		purpose="Item authority (add/remove/count). All ops via DataService. DRY core for Gather/NPC/Priest.",
		config="ItemDefs", schema={"inventory"}, deps={"DataService"} },
	{ name="TimeService", kind="service", status="working",
		purpose="World clock (1 real min = 1 game hour). Drives Lighting + onHourChanged/onDayChanged signals.",
		remotes={"UpdateGameTime"}, signals={"onHourChanged(hour,day)","onDayChanged(day)"} },
	{ name="NPCService", kind="service", status="working",
		purpose="Class-scheduled NPCs (anchor walk + barks driven by TimeService) AND the vendor economy (buy/sell, daily restock). Reads MoralityService standing for barks/retreat + vendor buy/sell modifiers; reads Fortune omamori sellPrice buff; broadcastMood for disaster reactions.",
		remotes={"GetVendorData","RequestVendorBuy","RequestVendorSell"},
		config={"NPCDefs","VendorDefs","ItemDefs","MoralityConfig"}, deps={"TimeService","EconomyService","InventoryService","PriestService","MoralityService"} },
	{ name="GatherService", kind="service", status="working",
		purpose="Tagged nodes yield raw items (timed, cooldown-gated, re-validated post-cast). Honours DisasterService modifier (slow/reduce/disable).",
		remotes={"RequestGather"}, config="ItemDefs", deps={"InventoryService","FactionService"},
		api={"setDisasterModifier"}, note="ALLOW_ALL_GATHER=true intentionally bypasses canGather so solo non-Civilians survive." },

	-- ---- Layer 4 ----
	{ name="FeelConfig+FeelController", kind="feel", status="working",
		purpose="Cosmetic-only game feel. Server emits CombatFeel to participants+witnesses; client renders hitstop, shake, punch, execution slow-mo, stylized blood, hit-markers, sound. Never touches the sim." },

	-- ---- Layer 5 ----
	{ name="PriestService", kind="service", status="partial (rites need zones; harae needs 2 players)",
		purpose="Kegare tracking (hooks CombatService.onLethalEvent), misogi (server-timed), harae (purify another's Shura w/ consent), spiritual energy, omamori craft/apply + getBuff, saisen sink + ShrineFavor pool.",
		remotes={"RequestMisogi","RequestHarae","RequestHaraeConsent","RequestCraftOmamori","RequestApplyOmamori","RequestOffering","UpdateKegare","UpdateEnergy","UpdateShrineFavor","PurifyFeel","HaraeConsentRequest","RiteResult","OmamoriUpdate"},
		config="PriestConfig", schema={"kegare","spiritualEnergy","reputation(renown)"},
		deps={"DataService","MoralityService","EconomyService","FactionService","InventoryService","CombatService"},
		api={"getBuff","addKegare","canPerformRite","getShrineFavor","getRecentOfferings","addShrineFavor"} },
	{ name="DisasterService", kind="service", status="partial (quell needs ShrineGround zone)",
		purpose="Live-op threat. Drought/blight modify GatherService; only a pure priest quells via a server-validated rhythm ritual at the shrine. Offerings give missed-beat credits. Auto-schedules on onDayChanged / low favor.",
		remotes={"RequestQuellRitual","SubmitRitualStep","DisasterStarted","DisasterQuelled","RitualState"},
		config="PriestConfig", deps={"TimeService","PriestService","GatherService","EconomyService","NPCService"} },
}

-- ============================================================================
-- DATA SCHEMA  (field : type : default : readers/writers)
-- ============================================================================
GameJournal.DataSchema = {
	{ field="currency", type="{mon,silver,ryo:number}", default="{0,0,0}", rw="EconomyService (rw), Faction/NPC/Priest/Disaster (via Economy)" },
	{ field="faction", type="string?", default="nil", rw="FactionService (rw)" },
	{ field="rank", type="number", default="1", rw="FactionService (rw)" },
	{ field="gi_shura", type="number -100..100", default="0", rw="MoralityService (rw); PriestService.harae (w via adjust)" },
	{ field="shura_kills", type="{any}", default="{}", rw="MoralityService (WRITE-ONLY) — phantom system never reads it (GAP)" },
	{ field="kegare", type="number 0..100", default="0", rw="PriestService (rw)" },
	{ field="spiritualEnergy", type="number 0..100", default="100", rw="PriestService (rw)" },
	{ field="inventory", type="{ {itemId,quantity} }", default="{}", rw="InventoryService (rw); Gather/NPC/Priest (via Inventory)" },
	{ field="equipped", type="{weapon,armor,tool:string?}", default="{}", rw="CombatService (rw weapon); armor/tool unused yet" },
	{ field="reputation", type="{renown,notoriety:number}", default="{0,0}", rw="DuelService (notoriety), PriestService/Disaster (renown)" },
	{ field="lineage", type="{ancestorName,inheritedMon,generationCount}", default="{nil,0,0}", rw="SeppukuService (rw): ancestorName=DisplayName/Name, inheritedMon one-shot grant, generationCount increments on seppuku" },
	{ field="jiseiPoem", type="string", default="\"\"", rw="CombatService (rw); default fallback CombatConfig.DEFAULT_JISEI" },
	{ field="stats", type="{totalKills,honorableKills,duelsWon,duelsLost}", default="{0,0,0,0}", rw="CombatService.kill (kills), DuelService.endDuel (duels) — single writer each" },
	{ field="createdAt", type="number", default="os.time()", rw="ProfileStore (w once)" },
	{ field="version", type="number", default="1", rw="DataSchema.migrate" },
}

-- ============================================================================
-- THE FEEDBACK-LOOP MAP  (how systems reinforce each other = coherence)
-- ============================================================================
-- status: CONNECTED = wired end-to-end (verified live or by trace);
--         GAP = one side is a net-new piece that was never built (see KnownGaps).
GameJournal.FeedbackLoops = {
	{ loop="Combat -> Morality", status="CONNECTED",
		detail="resolveDownedChoice: EXECUTE -> kill + applyKill{wasHelpless,wasDuel,wasInTown=inSafeZone(victim)}; SPARE -> applyGi('spareDowned'). Every kill with a killer flows through applyKill." },
	{ loop="Morality -> Combat", status="CONNECTED",
		detail="resolveHit reads getCombatModifiers: damageBonus is applied to damage AND accuracyPenalty becomes a live miss-chance. Temptation (power) and cost (miss) both fire." },
	{ loop="Combat -> Duel/SafeZone", status="CONNECTED",
		detail="resolveHit gates on duelService.canDamage: no damage in SafeZone, same-faction protected unless canKirisute (samurai) — and kirisute still applies Shura via the execute path." },
	{ loop="Duel -> Notoriety/Bounty", status="CONNECTED (stub)",
		detail="resolveHit -> flagAggression: unsanctioned wilderness hits raise reputation.notoriety + log a BOUNTY stub for a future LawService. Reachable + throttled." },
	{ loop="Death -> Jisei", status="CONNECTED",
		detail="CombatService.kill -> _broadcastJisei to all within JISEI_RADIUS. Compose UI exists (press P -> RequestSetJisei); empty poem falls back to DEFAULT_JISEI. (Seppuku is a separate death path not yet built.)" },
	{ loop="Priest Harae -> Morality", status="CONNECTED",
		detail="_performHarae gates range+consent+energy+kegare, then moralityService.adjust(target,+12,'harae') and fires PurifyFeel to both. Downed targets consent implicitly." },
	{ loop="Priest Disaster -> Economy", status="CONNECTED",
		detail="startDisaster -> gatherService.setDisasterModifier (drought slows+reduces yield; blight disables rice node). Quell clears it. Verified live: gather honours the modifier." },
	{ loop="Omamori -> consuming systems", status="CONNECTED",
		detail="getBuff is READ by CombatService (staminaRegen, accuracyOffset, damageResist) and NPCService (sellPrice). All 4 effect types consumed. (Caveat: see Gaps — 3/4 recipes need talisman_paper, which has no acquisition path; and there is no P2P path to SELL a charm to another faction.)" },
	{ loop="Offering -> ShrineFavor -> Disaster", status="CONNECTED",
		detail="offer() destroys mon (hard sink, verified live) and feeds shrineFavor + recentOfferings. DisasterService consumes BOTH: low favor invites a disaster, and recentOfferings buy missed-beat credits in the quell ritual." },
	{ loop="Time -> NPC/Vendor/Disaster", status="CONNECTED",
		detail="onHourChanged drives NPC schedule transitions+barks; onDayChanged restocks vendors AND runs the disaster auto-scheduler. Verified live: clock advances and ticks fire." },
	{ loop="Economic floor (solo gather->sell->buy)", status="CONNECTED",
		detail="Verified LIVE with 1 player: gather rice -> sell to rice_merchant (+5) -> buy back (-12). Fully server-side, works with nobody else online. (Vendors sell raw goods+tools, not weapons.)" },
	{ loop="Faction permissions checked at use", status="PARTIAL",
		detail="canKirisute IS checked (DuelService.canDamage). canGather is intentionally bypassed (ALLOW_ALL_GATHER) for the solo floor. canPurify is enforced as faction=='Priest' (equivalent, not via hasPermission). Other permissions (canOwnStall, canRunFestival, canEnforceLaw, ...) are defined but not yet consumed — forward hooks." },
	{ loop="Morality -> World reaction (NPC wariness / Gi perk)", status="CONNECTED",
		detail="NPCService reads MoralityService.getMoralityStanding. Honored players get deferential barks + vendor discount/sell bonus; Feared/Shunned players trigger wary/fear barks, Shunned/Feared retreat classes back away via existing move tween, SamuraiPatrol barks suspicion, and Shunned vendors apply SHUNNED_PRICE_PENALTY plus configured sale refusals." },
	{ loop="Seppuku -> Lineage/Inheritance", status="CONNECTED",
		detail="RequestSeppuku validates status via SeppukuService: voluntary/disgraced/duel-loss only, blocked by an active recent attacker. Seppuku is clean death: no Shura write, jisei broadcasts through CombatService, 75% current mon snapshots to lineage.inheritedMon, notoriety clears, generationCount increments, and the next spawn grants inheritedMon once then zeros it. Murder/execution paths do not touch lineage or clear notoriety." },
	{ loop="Phantom system (read shura_kills)", status="GAP",
		detail="shura_kills is WRITTEN on every Shura kill but never READ. The tier 'phantoms' flag reaches the client (phantomActive) but renders nothing — no shadow-of-past-victims spawns. Net-new — see KnownGaps." },
}

-- ============================================================================
-- NET REMOTE INDEX  (name : owner : direction : validator : client caller)
-- ============================================================================
GameJournal.NetRemotes = {
	-- C2S events
	{ name="RequestPing", owner="PlayerService", dir="C2S", validator="shape{message:string}", caller="PingController (Studio-gated stress test)" },
	{ name="RequestFactionSelect", owner="FactionService", dir="C2S", validator="shape{faction:literal(FactionDefs.Names)}", caller="FactionSelectController" },
	{ name="RequestResetFaction", owner="FactionService", dir="C2S", validator="shape{}", caller="FactionSelectController dev button (Studio only)" },
	{ name="RequestExchange", owner="EconomyService", dir="C2S", validator="shape{from:literal(CURRENCIES),amount:positiveInteger}", caller="NONE (orphan — money-changer UI not built)" },
	{ name="TriggerMeditationStart", owner="MoralityService", dir="C2S", validator="pass-through", caller="MoralityController (needs a MeditationZone in-world)" },
	{ name="TriggerMeditationEnd", owner="MoralityService", dir="C2S", validator="pass-through", caller="MoralityController" },
	{ name="RequestMeleeHit", owner="CombatService", dir="C2S", validator="shape{targetId:integer,weaponType:literal(WeaponNames),hitPosition:vector}", caller="CombatController" },
	{ name="RequestBlock", owner="CombatService", dir="C2S", validator="shape{active:boolean}", caller="CombatController" },
	{ name="RequestDodge", owner="CombatService", dir="C2S", validator="shape{}", caller="CombatController" },
	{ name="RequestExecuteOrSpare", owner="CombatService", dir="C2S", validator="shape{choice:literal(execute|spare)}", caller="DownedPromptController" },
	{ name="RequestEquipWeapon", owner="CombatService", dir="C2S", validator="shape{weapon:literal(WeaponNames)}", caller="CombatController + test Tool EquipBridge" },
	{ name="RequestSetJisei", owner="CombatService", dir="C2S", validator="shape{poem:string}", caller="JiseiController (compose, press P)" },
	{ name="RequestSeppuku", owner="SeppukuService", dir="C2S", validator="shape{source:literal(voluntary)}", caller="SeppukuController character menu (press M / Character button)" },
	{ name="RequestSoloDummyHit", owner="SoloDummyCombatHarness", dir="C2S", validator="shape{weaponType:literal(WeaponNames),hitPosition:vector}", caller="SoloDummyHitController (Studio-only proxy; mirrors armor/gap math, not production combat)" },
	{ name="RequestDuel", owner="DuelService", dir="C2S", validator="shape{targetId:integer}", caller="DuelController (press T)" },
	{ name="AcceptDuel", owner="DuelService", dir="C2S", validator="shape{challengerId:integer}", caller="DuelController (accept popup)" },
	{ name="RequestGather", owner="GatherService", dir="C2S", validator="instanceOf(BasePart)", caller="GatherController (ProximityPrompt)" },
	{ name="RequestVendorBuy", owner="NPCService", dir="C2S", validator="shape{vendorId:string,itemId:string,qty:positiveInteger}", caller="VendorController" },
	{ name="RequestVendorSell", owner="NPCService", dir="C2S", validator="shape{vendorId,itemId:string,qty:positiveInteger}", caller="VendorController" },
	{ name="RequestMisogi", owner="PriestService", dir="C2S", validator="shape{}", caller="PriestController (MisogiZone prompt)" },
	{ name="RequestHarae", owner="PriestService", dir="C2S", validator="shape{targetId:integer}", caller="PriestController (aim + H)" },
	{ name="RequestHaraeConsent", owner="PriestService", dir="C2S", validator="shape{accept:boolean}", caller="PriestController consent popup" },
	{ name="RequestCraftOmamori", owner="PriestService", dir="C2S", validator="shape{id:literal(OMAMORI_IDS)}", caller="PriestController craft menu" },
	{ name="RequestApplyOmamori", owner="PriestService", dir="C2S", validator="shape{id:literal(OMAMORI_IDS)}", caller="OmamoriController (pouch, O)" },
	{ name="RequestOffering", owner="PriestService", dir="C2S", validator="shape{amount:positiveInteger}", caller="OfferingController (SaisenBox prompt)" },
	{ name="RequestQuellRitual", owner="DisasterService", dir="C2S", validator="shape{}", caller="DisasterController (ShrineGround prompt)" },
	{ name="SubmitRitualStep", owner="DisasterService", dir="C2S", validator="shape{stepId:integer,timing:number}", caller="DisasterController (SPACE; SERVER scores timing)" },
	-- C2S functions
	{ name="GetFactionStatus", owner="FactionService", dir="C2S fn", validator="true", caller="FactionSelectController (race-free fallback)" },
	{ name="GetVendorData", owner="NPCService", dir="C2S fn", validator="string", caller="VendorController; returns standing-adjusted prices/refuseSell" },
	{ name="GetSeppukuStatus", owner="SeppukuService", dir="C2S fn", validator="true", caller="SeppukuController eligibility refresh" },
	-- S2C events (display only)
	{ name="UpdateFactionDisplay", owner="FactionService", dir="S2C", caller="HUDController, FactionSelectController" },
	{ name="ShowFactionSelect", owner="FactionService", dir="S2C", caller="FactionSelectController" },
	{ name="UpdateCurrencyDisplay", owner="EconomyService", dir="S2C", caller="HUDController" },
	{ name="UpdateMoralityDisplay", owner="MoralityService", dir="S2C", caller="MoralityController, HUDController" },
	{ name="UpdateLineageDisplay/SeppukuStatus/SeppukuAnim", owner="SeppukuService", dir="S2C", caller="HUDController, SeppukuController" },
	{ name="HitConfirmed/CombatFeedback/StaminaUpdate/CombatLoadout", owner="CombatService", dir="S2C", caller="CombatController" },
	{ name="ShowDownedPrompt/EnterDownedState/ExitDownedState", owner="CombatService", dir="S2C", caller="DownedPromptController, CombatController" },
	{ name="ShowJiseiPoem", owner="CombatService", dir="S2C", caller="JiseiController" },
	{ name="CombatFeel", owner="CombatService", dir="S2C", caller="FeelController" },
	{ name="ShowDuelInvite/DuelStarted/DuelEnded", owner="DuelService", dir="S2C", caller="DuelController" },
	{ name="UpdateGameTime", owner="TimeService", dir="S2C", caller="TimeController" },
	{ name="UpdateKegare/UpdateEnergy/RiteResult/PurifyFeel/HaraeConsentRequest", owner="PriestService", dir="S2C", caller="PriestController" },
	{ name="OmamoriUpdate", owner="PriestService", dir="S2C", caller="OmamoriController" },
	{ name="UpdateShrineFavor", owner="PriestService", dir="S2C", caller="OfferingController" },
	{ name="DisasterStarted/DisasterQuelled/RitualState", owner="DisasterService", dir="S2C", caller="DisasterController" },
}

-- ============================================================================
-- BUILDER TAGGING SPEC  (CollectionService tags the code expects in Workspace)
-- ============================================================================
-- present=true means at least one exists in the current place; present=false
-- means the system is built but DARK until the builder places + tags a part.
-- Apply tags with the Tag Editor (View > Tag Editor) or CollectionService:AddTag.
GameJournal.BuilderTags = {
	-- Faction spawns (1+ BasePart each; players teleport to a random tagged part)
	{ tag="SamuraiSpawn",  on="BasePart", present=true,  does="Samurai spawn/respawn point." },
	{ tag="MerchantSpawn", on="BasePart", present=true,  does="Merchant spawn/respawn point." },
	{ tag="CivilianSpawn", on="BasePart", present=true,  does="Civilian spawn/respawn point." },
	{ tag="PriestSpawn",   on="BasePart", present=true,  does="Priest spawn/respawn point." },

	-- Combat context
	{ tag="SafeZone", on="BasePart (volume)", present=false, does="No damage inside; also counts as 'in town' for the killInTown Shura modifier. Tag the town hub. REQUIRED for the anti-griefing rules to be testable." },
	{ tag="GapZone", on="Attachment (named 'GapZone')", present=true, does="Present on ServerStorage.TestAssets.ArmorPlaceholder and Workspace.CombatTestArena.SoloArmorDummy. A hit within GAP_RADIUS(1.5) ignores armor reduction (full damage)." },

	-- Morality
	{ tag="MeditationZone", on="BasePart (volume)", present=false, does="Stand inside for MEDITATION_DURATION(30s) to recover +8 gi_shura. WITHOUT this tag, meditation can never fire (the client polls for it)." },

	-- Priest / Disaster (ALL currently absent — the whole priest loop is dark without them)
	{ tag="MisogiZone", on="BasePart (volume)", present=false, does="Cold-water purification pavilion. Priest stands inside 20s -> kegare to 0 (server-timed; leaving early cancels)." },
	{ tag="ShrineTendZone", on="BasePart (volume)", present=false, does="Priest standing here regenerates spiritual energy x6 faster." },
	{ tag="SaisenBox", on="BasePart", present=false, does="Offering box. Opens the saisen amount picker -> RequestOffering (mon is destroyed as a hard sink, feeds ShrineFavor)." },
	{ tag="BloodZone", on="BasePart (volume)", present=false, does="Pollutes a priest on contact (+kegare, cooldown-gated). Place where blood/death lingers." },
	{ tag="ShrineGround", on="BasePart", present=false, does="Where the quelling ritual is performed. Priest must be within RITUAL_SHRINE_RANGE(16) to begin RequestQuellRitual." },
	{ tag="PlagueZone", on="BasePart", present=false, does="Reserved (future disease pollution). Not consumed yet." },

	-- NPC anchors (1+ BasePart each; NPCs walk to a random tagged anchor per schedule state)
	{ tag="Anchor_Inn",      on="BasePart", present=true, does="Shopkeeper midday 'eat'." },
	{ tag="Anchor_Market",   on="BasePart", present=true, does="Shopkeeper/Vendor stall." },
	{ tag="Anchor_Plaza",    on="BasePart", present=true, does="Townsfolk/Shopkeeper socialize + wander." },
	{ tag="Anchor_House",    on="BasePart", present=true, does="NPC sleep at night." },
	{ tag="Anchor_Field",    on="BasePart", present=true, does="Townsfolk work." },
	{ tag="Anchor_Gate",     on="BasePart", present=true, does="SamuraiPatrol patrol." },
	{ tag="Anchor_Barracks", on="BasePart", present=true, does="SamuraiPatrol rest at night." },
	{ tag="Anchor_Shrine",   on="BasePart", present=true, does="Priest rites all day." },

	-- NPC class markers (on a Model with a PrimaryPart/BasePart)
	{ tag="NPC_Shopkeeper",    on="Model", present=true, does="Scheduled townsperson (Shopkeeper class)." },
	{ tag="NPC_Townsfolk",     on="Model", present=true, does="Scheduled townsperson (Townsfolk class)." },
	{ tag="NPC_SamuraiPatrol", on="Model", present=true, does="Patrolling samurai NPC." },
	{ tag="NPC_Priest",        on="Model", present=true, does="Shrine priest NPC." },
	{ tag="NPC_Vendor", on="Model", present=true, does="Trader NPC. MUST ALSO set a string Attribute 'VendorId' = 'rice_merchant' or 'tool_smith' (see VendorDefs) to open a shop." },

	-- Gather nodes (BasePart; a ProximityPrompt is auto-added at runtime)
	{ tag="Node_RicePaddy",   on="BasePart", present=true, does="Yields rice (gatherTime 3, cooldown 10). Disabled by the blight disaster." },
	{ tag="Node_OreVein",     on="BasePart", present=true, does="Yields ore (gatherTime 4, cooldown 15)." },
	{ tag="Node_FishingSpot", on="BasePart", present=true, does="Yields fish (gatherTime 3, cooldown 12)." },
}

GameJournal.BuilderTodo = {
	"PRIORITY: place + tag SafeZone (town hub) — unlocks anti-griefing rules + the killInTown morality nuance.",
	"PRIORITY: place + tag the priest zones (MisogiZone, ShrineTendZone, SaisenBox, ShrineGround, BloodZone) at the shrine — the entire priest/disaster loop is dark without them.",
	"Place + tag MeditationZone — unlocks the only non-priest way to recover Gi.",
	"Confirm each NPC_Vendor Model has a 'VendorId' string Attribute (rice_merchant / tool_smith).",
	"Replace grey combat proxy weapons/armor with real equipment only after mechanics are validated; keep the WeaponType keys and GapZone attachment convention unchanged.",
}

-- ============================================================================
-- COMBAT TEST ASSETS  (grey proxies only; no combat balance or logic changes)
-- ============================================================================
GameJournal.CombatTestAssets = {
	purpose = "Mechanics-only combat playtest scaffolding. No aesthetics, no CombatConfig edits, no production CombatService edits.",
	storage = {
		weapons = "ServerStorage.TestAssets.Weapons",
		armor = "ServerStorage.TestAssets.ArmorPlaceholder",
		arena = "Workspace.CombatTestArena",
	},
	weapons = {
		{ name="Katana", class="Tool", handleSize="0.2,0.2,5", weaponType="Katana", tag="Weapon_Katana", note="Precise class; EquipBridge fires RequestEquipWeapon{weapon='Katana'}." },
		{ name="Kanabo", class="Tool", handleSize="0.5,0.5,3.5", weaponType="Kanabo", tag="Weapon_Kanabo", note="Bludgeon class; ignoresArmor=true in CombatConfig." },
		{ name="Wakizashi", class="Tool", handleSize="0.2,0.2,3", weaponType="Unarmed", tag="Weapon_Unarmed", note="Visual short-blade proxy only; Wakizashi is not a CombatConfig weapon key, so it exercises Unarmed." },
	},
	armor = {
		model="ArmorPlaceholder",
		convention="Two Attachments named EXACTLY 'GapZone' on ArmorTorso (neck + right armpit). CombatService checks attachment name, not CollectionService tag.",
		expected="Katana torso hit is armor-reduced to 33; Katana GapZone hit is full 55; Kanabo is full 70 regardless of armor.",
	},
	solo = {
		dummy="Workspace.CombatTestArena.SoloArmorDummy",
		controller="StarterPlayer.StarterPlayerScripts.SoloDummyHitController",
		serverHarness="ServerScriptService.SoloDummyCombatHarness",
		note="Studio-only one-player proxy because production CombatService targets Players by UserId. Left-click SoloArmorDummy with a proxy weapon equipped to test armor/gap/Kanabo math and HP readout. This does NOT test true player downed/execute/spare; use the 2-player harness for that.",
		verified="2026-06-28: Katana torso=33, Katana GapZone=55, Kanabo torso=70; dummy resets to 100 HP after downed.",
	},
	multiplayer = {
		harness="ServerScriptService.CombatTestHarness",
		note="Studio-only 2-player local-server test. P1 receives proxy weapons; P2 becomes a frozen armored real Player target so production RequestMeleeHit/downed/kill flow can be tested without changing combat logic.",
	},
}

-- ============================================================================
-- KNOWN GAPS / TODO  (prioritized net-new pieces — NOT built this pass)
-- ============================================================================
GameJournal.KnownGaps = {
	{ rank=3, title="Omamori acquisition + sale path",
		why="3 of 4 omamori need talisman_paper, which has NO source (not gathered/sold/dropped); and there is no way to SELL a crafted charm to another faction. The buff-read side is fully wired, so this is the missing half of the loop.",
		rec="Make talisman_paper gatherable or vendor-stocked, and add a player stall / vendor consignment so priests can actually sell charms." },
	{ rank=4, title="Phantom system (read shura_kills)",
		why="shura_kills is logged on every Shura kill but never read; the tier 'phantoms' flag renders nothing. A specced horror beat is inert.",
		rec="At T4+ spawn fading shadow-NPCs of logged victims near the corrupted player (cosmetic, client-side from a server-sent recent-victims list)." },
	{ rank=5, title="honorableDuelWin Gi gain is unreachable",
		why="endDuel grants honorableDuelWin only when reason=='honorable', but no caller ever passes that (only yield/death/forfeit). The +3 Gi path is dead.",
		rec="Decide the honorable-victory condition (e.g. winning a duel by SPARING) and pass reason='honorable' there — or remove the unused gain. (Balance call: avoided this pass to not double-dip with spareDowned.)" },
	{ rank=6, title="Money-changer UI (RequestExchange orphan)",
		why="EconomyService.RequestExchange is fully built+validated but no client fires it; currency exchange + its 5% sink are unreachable.",
		rec="Add a changer NPC/UI (mirror VendorController) firing RequestExchange." },
	{ rank=7, title="Vendor remotes lack a server proximity check",
		why="buy/sell are gated only by the client ProximityPrompt; the remote works from anywhere. Economically neutral (fair value, no dupe) so low-risk, but inconsistent with the 'validate at point of use' rule.",
		rec="Add a server-side range check vs the vendor NPC in buy/sellFromVendor." },
}

-- ============================================================================
-- HANDOFF STATE
-- ============================================================================
GameJournal.HandoffState = {
	updated="2026-06-28",
	agent="Codex",
	phase="Phase 1",
	task="Task 2 - Gap #1: Seppuku + Lineage/Inheritance",
	green={
		"Boot-green with SeppukuService online and remotes registered.",
		"Seppuku -> Lineage/Inheritance marked CONNECTED.",
		"DISGRACE_NOTORIETY_THRESHOLD=5: five aggression flags is the disgrace prompt threshold; SEPPUKU_INHERITANCE_RATE=0.75.",
		"Seppuku snapshots 75% current mon into lineage.inheritedMon, clears current mon, clears notoriety, increments generationCount, stores DisplayName/Name as ancestorName, and performs clean self-death with no Shura write.",
		"Next spawn grants inheritedMon once through EconomyService.addCurrency and zeros inheritedMon before the grant to prevent double-claim on rejoin.",
		"Non-seppuku kill path leaves lineage untouched and notoriety uncleared.",
	},
	next={
		"Commit + push this checkpoint before starting the next numbered task.",
		"Task 3 in the new list is combat test assets; those proxies already exist from the earlier Codex pass, but rerun verification before marking the new task complete.",
	},
	todo={
		"Local /docs/GAME_JOURNAL.md mirror was not present in this Studio-only session; ReplicatedStorage.GameJournal is the updated contract.",
		"Seppuku animation is a placeholder client hook (SeppukuAnim) until a real animation asset is supplied.",
	},
}

-- ============================================================================
-- CHANGELOG
-- ============================================================================
GameJournal.Changelog = {
	{ date="2026-06-28", title="Codex Task 2 - Seppuku lineage inheritance", entries={
		"Agent: Codex. Task #2 / Gap #1.",
		"Files touched: ReplicatedStorage.Config.SeppukuConfig, ServerScriptService.Services.SeppukuService, ServerScriptService.Services.CombatService, StarterPlayer.StarterPlayerScripts.Main.Controllers.SeppukuController, StarterPlayer.StarterPlayerScripts.Main.Controllers.HUDController, ReplicatedStorage.GameJournal.",
		"Added SeppukuConfig with SEPPUKU_INHERITANCE_RATE=0.75 and DISGRACE_NOTORIETY_THRESHOLD=5 (five aggression flags = repeated disgrace, not one stray hit).",
		"Added SeppukuService with validated/rate-limited RequestSeppuku, GetSeppukuStatus, lineage/status HUD pushes, active-attacker rejection, clean self-death, and one-shot inheritance grant on next spawn.",
		"Extended CombatService with recent-attacker tracking, getDownedBy, hasActiveAttacker, and performCleanDeath so seppuku reuses jisei/respawn without kill stats or Shura writes.",
		"Added a Character menu seppuku option (press M or Character button), greyed out with server reason, confirm dialog, and placeholder SeppukuAnim hook; HUD now shows Lineage generation/ancestor.",
		"Verification: active attacker rejected; disgraced player seppuku accepted; 100 mon -> 75 inherited; notoriety cleared; gi_shura stayed 0; jisei broadcast fired; respawn granted 75 and zeroed inheritedMon; second grant did not double-claim; non-seppuku kill respawned with mon=100, notoriety=5, inheritedMon=0, generation=0; profile fields restored after test.",
	} },
	{ date="2026-06-28", title="Codex Task 1 - Morality world reaction", entries={
		"Agent: Codex. Task #1 / Gap #2.",
		"Files touched: ReplicatedStorage.Config.MoralityConfig, ServerScriptService.Services.MoralityService, ServerScriptService.Services.NPCService, ReplicatedStorage.GameJournal, and restored the expected ReplicatedStorage.Remotes folder in the place file.",
		"Added read-only MoralityService.getMoralityStanding(player) -> Honored/Neutral/Feared/Shunned; Shunned starts at gi_shura <= -61 (Consumed/Shura T4+).",
		"Added MoralityConfig.WorldReaction as the single config home for standing thresholds, NPC bark pools, retreat classes, Honored modifiers, FEARED_PRICE_PENALTY, SHUNNED_PRICE_PENALTY, and Shunned sale refusals.",
		"NPCService bark loop now checks nearest players cheaply, branches on standing, makes Shunned/Feared retreat classes back away through existing moveNPC tween logic, and gives SamuraiPatrol suspicion barks.",
		"Vendor pricing now uses standing through the existing GetVendorData/RequestVendorBuy/RequestVendorSell flow: Honored discount/bonus, Feared penalty, Shunned worse buy+sell prices, and Shunned ore sale refusal.",
		"Verification: neutral rice 12/5 and ore sell allowed; Honored rice buy 11 and ore sell 16; Shura T5 rice 17/3, ore refuseSell=true, sellOre returns 'Vendor refuses to buy from the Shunned'; NPC cluster produced Shunned fear barks, SamuraiPatrol suspicion bark, and retreat movement; purify back to neutral restored 12/5 and ore sell allowed.",
	} },
	{ date="2026-06-28", title="Combat proxy + solo dummy pass", entries={
		"Added grey proxy weapon Tools in ServerStorage.TestAssets.Weapons: Katana -> weaponType Katana, Kanabo -> weaponType Kanabo, Wakizashi -> weaponType Unarmed because Wakizashi is not a CombatConfig key.",
		"Each proxy Tool has a Handle, RightGripAttachment, and EquipBridge LocalScript that uses the existing RequestEquipWeapon data flow so the server weapon-spoof check can pass.",
		"Added ServerStorage.TestAssets.ArmorPlaceholder with two Attachments named exactly GapZone on ArmorTorso (neck + right armpit) to match CombatService gap-hit detection.",
		"Added Workspace.CombatTestArena with AttackerStand, DummyStand, and SoloArmorDummy (visible torso/gap markers + HP billboard) for one-player armor/gap/Kanabo testing.",
		"Added Studio-only SoloDummyHitController + SoloDummyCombatHarness. This mirrors CombatConfig armor/gap damage math for a clickable part because production RequestMeleeHit only targets real Players by UserId.",
		"Verification: Katana torso hit = 33 reduced damage, Katana GapZone hit = 55 full damage, Kanabo torso hit = 70 full damage; solo dummy resets to 100 HP after downed.",
		"Added Studio-only CombatTestHarness for 2-player local-server tests: P1 attacker gets proxy weapons, P2 is a frozen armored real Player target for production downed/kill flow.",
	} },
	{ date="2026-06-28", title="Consolidation & coherence pass", entries={
		"Inventoried all 47 modules; confirmed server-authoritative throughout, every remote via Net w/ validator, all data via DataService, --!strict everywhere. No raw remotes, no direct DataStore access found.",
		"FIX: FactionDefs.Names added as the single source for faction names; FactionService validator now derives from it (was a hardcoded literal). Verified live: invalid 'Ninja' rejected.",
		"FIX: FactionService now caches economyService in Init (was Start) per the Loader convention.",
		"FIX: PingController's noisy invalid-arg + 50-ping stress test gated to Studio (production now fires a single benign ping).",
		"GLUE: MoralityService now pushes corruption visuals on join (returning Shura players desaturate immediately). Verified live.",
		"GLUE: EconomyService now pushes the balance on join (currency HUD correct for returning players). Verified live.",
		"Created this GameJournal (Studio ReplicatedStorage.GameJournal + repo /docs/GAME_JOURNAL.md).",
		"Live playtest PASS: boot green (14 services + 16 controllers), solo economy loop (gather->sell->buy), saisen sink (ShrineFavor 100->150), clock advance, and an exploit sweep (all bad args rejected, no dupes).",
	} },
}

return GameJournal
