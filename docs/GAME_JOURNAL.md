# The Quelled Land - Game Journal

Single source of truth for the build. The live code-accessible mirror is
`ReplicatedStorage.GameJournal` (`src/shared/GameJournal.luau`). Keep this file and
the Luau journal aligned after every checkpoint.

Project: The Quelled Land  
Place: Edo: Rising Sun  
Genre: Edo-period Restricted (18+) Roblox RP  
Language: Luau `--!strict`, fully typed  
Last pass: 2026-06-28, Codex map-story skeleton + Gensui prophecy handoff

## Golden Rules

- Server authoritative; clients only request.
- Every remote goes through `Net` with rate limits and `Validate`.
- All player data goes through `DataService`.
- Services use Loader `Init`/`Start`.
- Config lives in one shared config module per domain.
- Risky calls use `Logger.try`.
- Fail loud; do not silently continue from corrupted state.

## Recent Checkpoints

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
- Omamori -> consuming systems: CONNECTED on buff-read side; acquisition/sale path still open.
- Offering -> ShrineFavor -> Disaster: CONNECTED.
- Time -> NPC/Vendor/Disaster: CONNECTED.
- Economic floor: CONNECTED.
- Morality -> World reaction: CONNECTED.
- Seppuku -> Lineage/Inheritance: CONNECTED.
- Phantom system: GAP.

## Remaining Known Gaps

1. Omamori acquisition + sale path.
2. Phantom system reading `shura_kills`.
3. `honorableDuelWin` Gi gain is unreachable.
4. Money-changer UI for `RequestExchange`.
5. Vendor remotes need server-side proximity checks.

## Handoff State

Updated: 2026-06-28  
Agent: Codex  
Current task completed: Task 2 - Gap #1, Seppuku + Lineage/Inheritance

Green:
- Boot-green with SeppukuService online and remotes registered.
- Seppuku -> Lineage/Inheritance marked CONNECTED.
- Data verification restored the live test profile after mutation checks.
- Rojo source mirror exported from current Studio scripts into `src/`.
- Git remote configured for `TheEmpireRankingBot/edosamurai`; push checkpoint is the current active handoff step.
- External storyline Google Doc updated into a fillable map-based skeleton; use `The Bell That Rings Before Dawn` and Priest Gensui's prophecy as the current narrative north star.

Next:
- Task 3 is combat test assets; those proxies already exist from the earlier Codex pass, but rerun verification before marking the new task complete.

## Changelog

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
