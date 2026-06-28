# The Quelled Land - Game Journal

Single source of truth for the build. The live code-accessible mirror is
`ReplicatedStorage.GameJournal` (`src/shared/GameJournal.luau`). Keep this file and
the Luau journal aligned after every checkpoint.

Project: The Quelled Land  
Place: Edo: Rising Sun  
Genre: Edo-period Restricted (18+) Roblox RP  
Language: Luau `--!strict`, fully typed  
Last pass: 2026-06-28, Codex Task 2 - Seppuku -> Lineage/Inheritance

## Golden Rules

- Server authoritative; clients only request.
- Every remote goes through `Net` with rate limits and `Validate`.
- All player data goes through `DataService`.
- Services use Loader `Init`/`Start`.
- Config lives in one shared config module per domain.
- Risky calls use `Logger.try`.
- Fail loud; do not silently continue from corrupted state.

## Recent Checkpoints

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

Next:
- Commit and push this checkpoint.
- Task 3 is combat test assets; those proxies already exist from the earlier Codex pass, but rerun verification before marking the new task complete.
