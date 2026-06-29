# The Quelled Land - Game Journal

Single source of truth for the build. The live code-accessible mirror is
`ReplicatedStorage.GameJournal` (`src/shared/GameJournal.luau`). Keep this file and
the Luau journal aligned after every checkpoint.

Project: The Quelled Land  
Place: Edo: Rising Sun  
Genre: Edo-period Restricted (18+) Roblox RP  
Language: Luau `--!strict`, fully typed  
Last pass: 2026-06-29, Codex game-test readiness gap closure

## Golden Rules

- Server authoritative; clients only request.
- Every remote goes through `Net` with rate limits and `Validate`.
- All player data goes through `DataService`.
- Services use Loader `Init`/`Start`.
- Config lives in one shared config module per domain.
- Risky calls use `Logger.try`.
- Fail loud; do not silently continue from corrupted state.

## Recent Checkpoints

### Codex Game-Test Readiness Gap Closure (2026-06-29)

Status: PASS, Studio synced live, boot-green.

Closed the remaining code-side gap list:
- Omamori acquisition and sale path: priests can prepare `talisman_paper` as shrine-prepared Gofu Paper, craft all four omamori, and sell a crafted charm to a nearby player through `EconomyService.transfer`.
- Phantom system: `shura_kills` is now trimmed and read by `MoralityService`; T4+ Shura payloads include recent victim names and `MoralityController` renders local grey phantom shadows.
- `honorableDuelWin`: sparing a downed duel opponent now ends the duel with reason `honorable`, waking the existing +3 Gi reward.
- Money changer: added tagged `MoneyChanger` prompt support, a Studio fallback `MoneyChangerSpot`, and a `MoneyChangerController` UI for `RequestExchange` with the existing 5% fee.
- Vendor exploit consistency: `RequestVendorBuy` / `RequestVendorSell` now reject out-of-range calls server-side.

Files touched:
- `EconomyService`, `MoralityService`, `NPCService`, `PriestService`, `CombatService`
- `PriestController`, `MoralityController`, `MoneyChangerController`
- `EconomyConfig`, `MoralityConfig`, `PriestConfig`, `VendorDefs`
- journals

Verification:
- Studio source sync imported 18 changed scripts/configs/controllers/journal entries into `Edo: Rising Sun`.
- Boot-green: all services/controllers loaded, including `MoneyChangerController`; new remotes registered: `RequestPrepareTalismanPaper`, `RequestSellOmamori`, `RequestExchange`, `RequestVendorBuy`, `RequestVendorSell`.
- Server probe: no missing remotes; `MoralityService.getRecentShuraKills` present; `PriestConfig.TalismanPaper.itemId == "talisman_paper"`; `VendorDefs.INTERACTION_RANGE == 14`; Studio fallback `MoneyChangerSpot` exists, is tagged `MoneyChanger`, and has `MoneyChangerPrompt`; live `GameJournal.KnownGaps[1]` says no remaining prior code-side gaps.
- Console had only pre-existing asset permission warnings for asset `86889305034722`, not script/runtime errors.

### Codex Combat Unequip + Dummy Armor Selector (2026-06-29)

Status: PASS, Studio patched live, boot-green.

Fixed:
- Physical Tool equip/unequip now drives `equipped.weapon` through the existing CombatService data flow.
- When a Katana Tool leaves the character and no other recognized Tool is equipped, the server normalizes the player to `Unarmed`.
- CombatController and SoloDummyHitController mirror Tool equip/unequip locally so `RequestMeleeHit` / `RequestSoloDummyHit` no longer keep sending stale Katana after unequip.
- Solo dummy now has a Studio-only armor selector UI (`SoloDummyArmorSelector`) and hotkeys: `Z=light`, `X=medium`, `C=heavy`.
- New validated remote: `RequestSoloDummyArmorClass` -> SoloDummyCombatHarness, using `CombatConfig.ArmorClassNames`.

Verification:
- Live Studio scripts patched directly because Rojo had not yet synced these new source edits.
- Studio boot-green: `RequestSoloDummyArmorClass` registered, CombatService online, CombatController online, no new runtime errors.
- Console showed current player normalized to `Unarmed` on spawn.

### Edo Armour Classes (Claude, 2026-06-29)

Status: DONE, boot-green, live-verified.

Replaced the flat 40% armour reduction with Edo-period armour classes so fists are no longer a quick KO and armour scales by class:
- **Light** (Tatami-gusoku / kusari katabira) = 15% reduction — fragile; heavier foes overwhelm.
- **Medium** (Dō-maru / munition okegawa-dō) = 60% — survivable; clean kills need tactical gap hits.
- **Heavy** (Tōsei-gusoku full harness) = 93% — near-immune to normal blows; only a GapZone hit, a Kanabo (ignoresArmor), or downing+executing breaks it.

`equipped.armor` now stores the class key; `CombatConfig.getArmorReduction()` resolves it (unknown legacy value → 0.40 fallback). GapZone hits + Kanabo still bypass armour for full damage = the skill kill path (historically the neck/armpit gaps a swordsman aimed for). Damage (HP 100): fists none 15 / light 13 / medium 6 / **heavy 1**; Katana torso none 55 / light 47 / medium 22 / **heavy 4**; any GapZone 55; Kanabo 70. Verified live via the solo dummy (heavy Katana torso=4, Naginata torso=3, GapZone=55 → downs in 2).

### Codex Narrative Doc Expansion

Status: PASS, external Google Doc updated.

Notes:
- Expanded `Edo: The Rising Sun - Kurosawa Storyline` into the main narrative selling point for the game.
- Google Doc: https://docs.google.com/document/d/14VqOW2mYENI0OAmE8xdFVNCv-wV8s_Am1c1aBv7V0jk
- Narrative direction: philosophical bushido pressure without declaring the code good or bad.
- New storyline spine: `The Weight of the Rising Sun`, a 4-6 hour Kurokawa campaign about law, rice, hunger, mercy, violence, seppuku, lineage, and the town remembering player choices.
- 2026-06-28 update: reworked the doc into a fillable map-based skeleton, `The Bell That Rings Before Dawn`, using the Castle District, Market, Farmlands, Sanctuary, Liminal Fringe, and Execution Grounds as act structure.
- Added new character web: Miyo, Captain Hayato, Lady Renko, O-Kane, Priest Gensui, Jiro, and Sute.
- Priest Gensui is the prophecy hinge. His line about mirror/rice/bell/rope/kegare should sound like shrine atmosphere first, then become clear only after the execution arc resolves.
- Treat this external doc as the story north star for future quests, NPC writing, faction reactions, and main campaign implementation.

### Codex Rojo/Git Handoff

Status: PASS, local Git checkpoint created and remote configured.

Notes:
- Studio source was exported into the Rojo tree at `C:\Users\chuab\TheQuelledLand`.
- Git repository was initialized on `main`.
- GitHub remote configured as `https://github.com/TheEmpireRankingBot/edosamurai.git`.
- Commit `35a9ae9` captured the Task 2 Seppuku/Lineage checkpoint before this handoff note.
- This journal update exists so Claude can see the source-control state before continuing Task 3.

### Codex Task 2 - Seppuku Lineage Inheritance

Status: PASS, boot-green.

Files touched:
- `src/shared/Config/SeppukuConfig.luau`
- `src/server/Services/SeppukuService.luau`
- `src/server/Services/CombatService.luau`
- `src/client/Main/Controllers/SeppukuController.luau`
- `src/client/Main/Controllers/HUDController.luau`
- `src/shared/GameJournal.luau`

Implemented:
- `SEPPUKU_INHERITANCE_RATE = 0.75`
- `DISGRACE_NOTORIETY_THRESHOLD = 5`
- `RequestSeppuku`, `GetSeppukuStatus`, `SeppukuStatus`, `SeppukuAnim`, `UpdateLineageDisplay`
- Active recent-attacker rejection
- Clean self-death through CombatService with jisei broadcast and no Shura write
- Persistent lineage snapshot: `ancestorName`, `inheritedMon`, `generationCount`
- One-shot next-spawn inheritance grant through `EconomyService.addCurrency`, zeroing `inheritedMon` before grant
- HUD lineage indicator and character menu seppuku option with confirm dialog

Verification:
- Active attacker rejected.
- Disgraced seppuku accepted.
- `100 mon -> 75 inherited`.
- Notoriety cleared.
- `gi_shura` stayed `0`.
- Jisei broadcast fired.
- Respawn granted `75 mon`.
- Second grant did not double-claim.
- Non-seppuku kill left `inheritedMon=0`, `generation=0`, and notoriety still `5`.
- Test profile fields were restored.
- Fresh boot green with SeppukuService online.

### Codex Task 1 - Morality World Reaction

Status: PASS, boot-green.

Implemented:
- `MoralityService.getMoralityStanding(player)` -> `Honored | Neutral | Feared | Shunned`
- `MoralityConfig.WorldReaction`
- NPC standing-aware barks, Shunned/Feared retreat, Samurai suspicion barks
- Honored vendor discount/bonus, Feared penalty, Shunned penalty/refusal

Verification:
- Neutral rice `12/5`, ore sell allowed.
- Honored rice buy `11`, ore sell `16`.
- Shura T5 rice `17/3`, ore `refuseSell=true`.
- Shunned ore sale returned `Vendor refuses to buy from the Shunned`.
- NPC cluster produced fear barks, Samurai suspicion, and retreat.
- Purify/normalize restored neutral prices.

## Feedback Loops

- Combat -> Morality: CONNECTED.
- Morality -> Combat: CONNECTED.
- Combat -> Duel/SafeZone: CONNECTED.
- Duel -> Notoriety/Bounty: CONNECTED stub.
- Death -> Jisei: CONNECTED.
- Priest Harae -> Morality: CONNECTED.
- Priest Disaster -> Economy: CONNECTED.
- Omamori -> consuming systems/acquisition/sale: CONNECTED.
- Offering -> ShrineFavor -> Disaster: CONNECTED.
- Time -> NPC/Vendor/Disaster: CONNECTED.
- Economic floor: CONNECTED.
- Morality -> World reaction: CONNECTED.
- Seppuku -> Lineage/Inheritance: CONNECTED.
- Phantom system: CONNECTED.

## Remaining Known Gaps

None from the prior code-side gap list. Builder/content TODO remains: place real map-authored `MoneyChanger`, priest, shrine, safe-zone, and meditation tags instead of relying on Studio fallback/test pieces.

## Handoff State

Updated: 2026-06-29
Agent: Codex  
Current task completed: game-test readiness gap closure

Green:
- Boot-green with SeppukuService online and remotes registered.
- Seppuku -> Lineage/Inheritance marked CONNECTED.
- Data verification restored the live test profile after mutation checks.
- Rojo source mirror exported from current Studio scripts into `src/`.
- Git remote configured for `TheEmpireRankingBot/edosamurai`; push checkpoint is the current active handoff step.
- External storyline Google Doc updated into a fillable map-based skeleton; use `The Bell That Rings Before Dawn` and Priest Gensui's prophecy as the current narrative north star.
- Tool unequip state is now server-authoritative: no recognized Tool in the character means `equipped.weapon = "Unarmed"`.
- Solo dummy armor can be changed in Studio via UI buttons or `Z/X/C`; the harness writes `SoloArmorDummy.ArmorClass` and resets HP.
- Omamori loop is reachable end-to-end: prepare Gofu Paper -> craft -> sell nearby -> buyer applies buff.
- Phantom visuals read `shura_kills` for T4+ Shura players.
- Honorable duel spare now grants the existing `honorableDuelWin` Gi reward.
- Money changer UI calls `RequestExchange` near a tagged changer and preserves the existing 5% fee.
- Vendor buy/sell remotes now validate proximity server-side.

Next:
- Commit and push this checkpoint.

## Changelog

### 2026-06-29 - Codex Game-Test Readiness Gap Closure

- Agent: Codex. Closed the remaining code-side gaps from the journal.
- Files touched: `EconomyService`, `MoralityService`, `NPCService`, `PriestService`, `CombatService`, `PriestController`, `MoralityController`, `MoneyChangerController`, `EconomyConfig`, `MoralityConfig`, `PriestConfig`, `VendorDefs`, journals.
- Added priest-side Gofu Paper preparation (`RequestPrepareTalismanPaper`) and nearby omamori sale (`RequestSellOmamori`) using `EconomyService.transfer` and inventory rollback on failure.
- Added Shura phantom payload/rendering from `shura_kills`, activated only for tiers whose config enables `phantoms`.
- Connected duel spare wins to `reason="honorable"` so `honorableDuelWin` Gi gain is reachable.
- Added money-changer prompt/UI path for `RequestExchange`; Studio fallback creates `MoneyChangerSpot` if no tagged changer exists.
- Added server-side vendor proximity rejection for buy/sell remotes.
- Verified live boot-green after syncing 18 scripts into Studio; server probe confirmed remotes, Gofu Paper config, MoneyChanger prompt/tag, vendor range, phantom API, and journal gap status.

### 2026-06-29 - Codex Combat Unequip + Solo Dummy Armor Selector

- Agent: Codex. Player bugfix handoff after Claude armor-class pass.
- Files touched: `CombatService`, `CombatController`, `SoloDummyHitController`, `SoloDummyCombatHarness`, `docs/GAME_JOURNAL.md`, `src/shared/GameJournal.luau`.
- Fixed stale weapon state after Tool unequip: CombatService now resolves recognized Tool names/attributes, updates `equipped.weapon` on character Tool add/remove, and normalizes to `Unarmed` when no recognized Tool remains equipped.
- CombatController and SoloDummyHitController now mirror physical Tool equip/unequip locally so client hit requests do not keep sending stale Katana after unequip.
- Added `RequestSoloDummyArmorClass` and a Studio-only solo dummy armor selector UI with `light`, `medium`, and `heavy` buttons plus hotkeys `Z/X/C`.
- Live Studio was patched directly; boot verification showed the new remote registered and all Loader services/controllers online with no new runtime errors.

### 2026-06-29 - Edo armour classes (Claude)

- Replaced flat `ARMOR_DAMAGE_REDUCTION` (0.40) with `CombatConfig.ArmorClasses` (light 15% / medium 60% / heavy 93%); added `CombatConfig.getArmorReduction(value)` (nil/none→0, known class→its reduction, unknown legacy value→0.40 fallback).
- `CombatService.resolveHit` now reduces a normal hit by the class reduction; GapZone hits and Kanabo (`ignoresArmor`) still bypass armour for full damage.
- `equipped.armor` stores the class key. Test harnesses read an `ArmorClass` (solo dummy) / `CombatTestArmorClass` (2-player dummy) attribute, default heavy.
- Files: `CombatConfig`, `CombatService`, `SoloDummyCombatHarness`, `CombatTestHarness`, `GameJournal`.
- Verified live: `getArmorReduction` unit test (0/.15/.60/.93, legacy .40) + solo-dummy integration (heavy Katana torso=4, Naginata torso=3, GapZone=55). Boot green, 14 services + 17 controllers.

### 2026-06-28 - Codex Map Story Skeleton & Gensui Prophecy

- Agent: Codex. Narrative/storyline handoff follow-up.
- Files touched: external Google Doc `Edo: The Rising Sun - Kurosawa Storyline`, `docs/GAME_JOURNAL.md`, `src/shared/GameJournal.luau`.
- Reworked the story doc around the attached map: Farmlands = wound, Market = bargain, Castle = command, Sanctuary = warning, Liminal Fringe = discarded truth, Execution Grounds = public memory.
- Added a fillable act skeleton, new character web, ending skeletons, dialogue slots, and quest design rules for emotional, philosophical bushido play.
- Added Priest Gensui as a Shinto-Buddhist prophecy character. His mirror/rice/bell/rope/kegare line predicts the arc but should only fully land after players see the consequences.
- Verified Google Doc identity, tab `t.0`, current revision readback, prophecy paragraph, heading structure, and no accidental list formatting.

### 2026-06-28 - Codex Narrative Doc Expansion

- Agent: Codex. Narrative/storyline handoff.
- Files touched: external Google Doc `Edo: The Rising Sun - Kurosawa Storyline`, `docs/GAME_JOURNAL.md`, `src/shared/GameJournal.luau`.
- Expanded the storyline into `The Weight of the Rising Sun`, a philosophical bushido campaign that makes players question duty, mercy, loyalty, violence, honor, seppuku, and lineage without condemning or praising the code outright.
- Verified Google Doc identity, tab `t.0`, Heading 2 structure, normal paragraphs, and HTML export after cleanup.

### 2026-06-28 - Codex Rojo/Git Handoff

- Agent: Codex. Source-control handoff after Task #2.
- Files touched: `docs/GAME_JOURNAL.md`, `src/shared/GameJournal.luau`.
- Exported current Studio scripts into the Rojo source tree at `C:\Users\chuab\TheQuelledLand`.
- Initialized local Git on `main`, configured origin to `https://github.com/TheEmpireRankingBot/edosamurai.git`, and prepared the checkpoint for push.
