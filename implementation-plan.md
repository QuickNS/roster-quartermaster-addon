# Roster Quartermaster — Autonomous Implementation Plan

## 1. Project status and roster assumptions

This document is intended to be sufficiently complete for an autonomous coding agent to implement most of the addon with minimal clarification.

The addon is a personal, account-wide roster coordinator for **World of Warcraft: Forever**. It should recommend which character to play next, track rested experience and progression milestones, coordinate professions and materials, and generate a practical daily checklist.

The planned roster is shown below. **All character names are provisional and may change before or after launch. Never hard-code character names into business logic.** Seed them as editable defaults and identify actual characters by GUID whenever possible.

| Planned name | Race     | Class/role                        | Permanent professions     | Levelling emphasis                       |
| ------------ | -------- | --------------------------------- | ------------------------- | ---------------------------------------- |
| Chop Suey    | Orc      | Protection Warrior; intended main | Mining + Engineering      | First-clear dungeons plus outdoor quests |
| Miss Tombsie | Undead   | Priest; healer                    | Tailoring + Enchanting    | Dungeon-heavy hybrid                     |
| Kit Cat      | Skyborne | Druid; flexible tank/healer/DPS   | Herbalism + Alchemy       | Outdoor gathering and selected dungeons  |
| Quick Death  | Undead   | Rogue; melee DPS                  | Skinning + Leatherworking | Primarily outdoor questing               |
| Voodoo Child | Troll    | Shaman; healer/DPS                | Mining + Blacksmithing    | Balanced questing and dungeons           |

Alternative planned Druid name: **Luna Tick**.

Default roster strategy:

- Keep the Warrior approximately five levels ahead after the first level-25 wave.
- Use level 25, 45, and 60 as character milestones.
- Use profession skill 150, 225, and 300 as corresponding profession milestones.
- Prioritize rested experience when selecting an alt.
- Run dungeons primarily for first clears, quests, role practice, and important equipment—not repeated XP farming.
- Standard healing potions are currently associated with First Aid in the Forever beta. First Aid therefore needs separate tracking for potion ingredients and cloth-based bandages.
- Give early cloth priority to the Priest for bags and Tailoring/Enchanting, while allowing the minimum cloth needed to progress priority First Aid characters.
- Give Engineering material priority to the Warrior; send surplus metal to the Shaman for Blacksmithing.
- The Druid supplies herbs for both Alchemy and First Aid healing-potion recipes.

These gameplay rules must be configurable. Beta mechanics and the planned roster may change.

---

## 2. Agent execution instructions

The implementing agent should:

1. Inspect the workspace and any existing repository or instruction files before modifying anything.
2. If no addon repository exists, create the structure specified in this document.
3. Target World of Warcraft: Forever only for the first release.
4. Use Lua 5.1-compatible syntax unless the running Forever client proves that a newer construct is safe.
5. Validate uncertain WoW APIs in the client instead of inventing signatures.
6. Put all direct WoW API access behind an adapter module.
7. Keep recommendation, routing, estimation, and checklist logic independent from the UI and unit-testable outside WoW.
8. Implement milestones in the order specified below and leave the repository working after every milestone.
9. Add graceful fallbacks whenever beta APIs are absent or restricted.
10. Never automate protected actions such as combat decisions, crafting, mailing, auction purchases, or character selection.
11. Record unresolved beta API questions in `docs/BETA_API_NOTES.md` instead of scattering speculative TODOs through the code.
12. Do not block implementation on the provisional character names; provide editable roster configuration.

The agent may make ordinary implementation decisions autonomously when they preserve these constraints. It should request clarification only when a decision would materially change the product scope or require unsafe/protected automation.

---

## 3. Product objective

The addon should answer one central question:

> Which character should I play now, and what should I accomplish during this session?

It should coordinate a five-character levelling campaign rather than provide a full quest route.

The core user journey is:

1. Log into a character.
2. The addon captures current character state.
3. Open the addon using `/rq`.
4. See the recommended character and an explanation.
5. See today's highest-priority tasks, material transfers, profession goals, and dungeon opportunities.
6. Complete or dismiss tasks.
7. Before logout, receive a short checklist and park the character in a rested area.
8. Offline character snapshots remain visible and rested XP is estimated until those characters log in again.

---

## 4. Scope

### 4.1 Minimum viable product

The MVP must provide:

- Editable account-wide roster configuration.
- Automatic registration of characters as they log in.
- Character snapshots containing level, XP, rested XP, location, resting state, last seen, money, bag capacity, and known profession levels.
- Offline rested-XP estimation with an explicit `Estimated` label.
- A deterministic `Play next` recommendation with human-readable reasons.
- A daily/session checklist.
- Level 25/45/60 milestone tracking.
- Profession 150/225/300 milestone tracking.
- Configurable material-routing policies.
- Basic bag inventory scanning.
- Login and logout reminders.
- Slash commands for opening, diagnostics, rescanning, pinning, export, and import.
- Schema-versioned SavedVariables and migrations.
- Unit tests for all pure planning logic.
- A README containing installation, usage, development, testing, and packaging instructions.

### 4.2 Version 1 features after the MVP

- Cached bank and mailbox inventory snapshots.
- First Aid consumable stock management.
- Profession recipe/material planning.
- Dungeon eligibility, quest bundles, first-clear state, desired drops, and Legacy bracket tracking.
- Legacy Point overview and planned perk allocation.
- Optional Questie and Auctionator integrations.
- Minimap button.
- Configurable notification levels.

### 4.3 Explicit non-goals

- Combat rotation or threat assistance.
- Automated crafting, mailing, vendoring, auctioning, or purchasing.
- Automatic character login or selection.
- Full quest-path optimization.
- Exact real-time state for offline characters.
- Replacing established bag, map, quest, auction, or damage-meter addons.
- Cross-account synchronization.

---

## 5. Technical decisions

| Decision                       | Choice                                                       |
| ------------------------------ | ------------------------------------------------------------ |
| Addon name                     | `RosterQuartermaster`                                        |
| Short prefix                   | `RQ`                                                         |
| Target client                  | World of Warcraft: Forever                                   |
| Language                       | Lua compatible with the client; default to Lua 5.1 conventions |
| UI framework                   | Native WoW frames for MVP                                    |
| External libraries             | None for MVP unless clearly justified                        |
| Persistence                    | Account-wide and per-character SavedVariables                |
| Canonical character identifier | Player GUID; normalized full name and realm only as fallback |
| Canonical item identifier      | Numeric item ID                                              |
| Testing                        | Pure Lua unit tests with mocked API adapter                  |
| Formatting                     | StyLua                                                       |
| Static analysis                | Luacheck and Lua Language Server annotations                 |
| Packaging                      | GitHub Actions-generated ZIP with a top-level `RosterQuartermaster/` directory |

The addon must not assume that Classic Era APIs are available unchanged. Forever currently uses a modern addon architecture with restrictions. Every API used should be confirmed in the running client or guarded by a capability check.

---

## 6. Proposed repository structure

```text
RosterQuartermaster/
├── RosterQuartermaster.toc
├── Bootstrap.lua
├── Core/
│   ├── Namespace.lua
│   ├── Constants.lua
│   ├── Events.lua
│   ├── Database.lua
│   ├── Migrations.lua
│   ├── Api.lua
│   ├── Capabilities.lua
│   └── Logger.lua
├── Models/
│   ├── Character.lua
│   ├── Objective.lua
│   ├── ChecklistItem.lua
│   ├── MaterialRule.lua
│   └── Snapshot.lua
├── Services/
│   ├── SnapshotService.lua
│   ├── RestedEstimator.lua
│   ├── PriorityEngine.lua
│   ├── ChecklistService.lua
│   ├── ProfessionService.lua
│   ├── InventoryService.lua
│   ├── RoutingService.lua
│   ├── LegacyService.lua
│   └── ExportService.lua
├── Data/
│   ├── DefaultRoster.lua
│   ├── DefaultPolicies.lua
│   ├── ProfessionMilestones.lua
│   ├── MaterialCategories.lua
│   └── ForeverDungeons.lua
├── UI/
│   ├── MainWindow.lua
│   ├── TodayPanel.lua
│   ├── RosterPanel.lua
│   ├── CharacterCard.lua
│   ├── ProfessionsPanel.lua
│   ├── MaterialsPanel.lua
│   ├── SettingsPanel.lua
│   ├── ImportExportDialog.lua
│   └── Widgets.lua
├── Integrations/
│   ├── Questie.lua
│   └── Auctionator.lua
├── Localization/
│   └── enUS.lua
├── docs/
│   ├── BETA_API_NOTES.md
│   ├── DATA_MODEL.md
│   └── MANUAL_TEST_PLAN.md
├── Tests/
│   ├── fixtures/
│   ├── PriorityEngineTests.lua
│   ├── RestedEstimatorTests.lua
│   ├── RoutingServiceTests.lua
│   ├── ChecklistServiceTests.lua
│   └── MigrationTests.lua
├── .github/
│   ├── workflows/
│   │   ├── validate.yml
│   │   └── package.yml
│   └── copilot-instructions.md
├── .luacheckrc
├── stylua.toml
├── README.md
└── CHANGELOG.md
```

If the client requires a strict file load order, reflect that order explicitly in the `.toc` file. Do not depend on runtime directory enumeration.

---

## 7. SavedVariables design

The `.toc` should eventually declare:

```toc
## SavedVariables: RQDB
## SavedVariablesPerCharacter: RQCharDB
```

Do not hard-code the `.toc` interface number until it is obtained from the current client.

### 7.1 Account-wide database

```lua
RQDB = {
    schemaVersion = 1,

    roster = {
        -- Canonical key: player GUID.
        ["Player-GUID"] = {
            displayName = "Chop Suey",
            plannedName = "Chop Suey",
            race = "Orc",
            class = "WARRIOR",
            role = "TANK",
            isMain = true,
            enabled = true,
            targetLead = 5,
            manualPriority = 0,
            professions = {
                primary = { "Mining", "Engineering" },
                secondary = { "First Aid", "Cooking" },
            },
        },
    },

    policies = {
        mainLeadLevels = 5,
        professionMilestones = { 150, 225, 300 },
        levelMilestones = { 25, 45, 60 },
        healingPotionMinimum = 20,
        staleSnapshotHours = 48,
    },

    materialRules = {},
    professionGoals = {},
    dungeonGoals = {},
    legacy = {},
    settings = {},
}
```

### 7.2 Per-character database

```lua
RQCharDB = {
    schemaVersion = 1,

    identity = {
        guid = nil,
        displayName = nil,
        realm = nil,
        class = nil,
        race = nil,
    },

    snapshot = {
        level = 1,
        xp = 0,
        xpMax = 1,
        restedXp = 0,
        money = 0,
        freeBagSlots = 0,
        zone = nil,
        subZone = nil,
        wasResting = false,
        lastSeen = 0,
        lastLogout = 0,
        professions = {},
    },

    inventory = {
        bags = { scannedAt = 0, items = {} },
        bank = { scannedAt = 0, items = {} },
        mail = { scannedAt = 0, items = {} },
    },

    objectives = {},
    checklist = {},
    dungeons = {},
}
```

### 7.3 Persistence requirements

- Every schema change requires an idempotent migration.
- Initialization must tolerate nil, partial, stale, or future-version data.
- Never overwrite a non-empty database with defaults merely because initialization is incomplete.
- Store timestamps on snapshots and inventory sources.
- Mark stale data in the UI.
- Include configuration export/import from the beginning because Forever beta builds have exhibited SavedVariables persistence problems.
- Export configuration, roster, policies, and objectives. Do not export large inventory history in the first release.

---

## 8. WoW API adapter and event capture

All direct game access must live in `Core/Api.lua`. No service or UI module should call global WoW APIs directly.

Target adapter methods:

```lua
RQ.Api.GetBuildInfo()
RQ.Api.GetCharacterIdentity()
RQ.Api.GetCharacterProgression()
RQ.Api.GetRestedXP()
RQ.Api.GetMoney()
RQ.Api.GetLocation()
RQ.Api.IsResting()
RQ.Api.GetBagCapacity()
RQ.Api.ScanBags()
RQ.Api.ScanBank()
RQ.Api.ScanMailbox()
RQ.Api.GetProfessions()
RQ.Api.GetKnownRecipes()
RQ.Api.GetQuestState(questId)
RQ.Api.GetCompletedQuestState(questId)
RQ.Api.GetServerTime()
```

Each method should return normalized addon-owned data rather than leaking raw API return shapes.

Events to validate in the Forever client include:

- `ADDON_LOADED`
- `PLAYER_LOGIN`
- `PLAYER_ENTERING_WORLD`
- `PLAYER_LOGOUT`
- `PLAYER_LEVEL_UP`
- `PLAYER_XP_UPDATE`
- `UPDATE_EXHAUSTION`
- `PLAYER_UPDATE_RESTING`
- `PLAYER_MONEY`
- `BAG_UPDATE_DELAYED`
- `SKILL_LINES_CHANGED`
- `TRADE_SKILL_LIST_UPDATE`
- `QUEST_LOG_UPDATE`
- `ZONE_CHANGED_NEW_AREA`
- `BANKFRAME_OPENED`
- `BANKFRAME_CLOSED`
- `MAIL_SHOW`
- `MAIL_CLOSED`

For each event:

1. Confirm it fires in Forever.
2. Debounce noisy events such as bag updates.
3. Update only the affected snapshot section.
4. Persist through the normal database service.
5. Refresh visible UI panels only when necessary.

If an API or event is unavailable, expose that in `/rq diag` and degrade gracefully.

---

## 9. Character snapshot service

`SnapshotService` owns collection and reconciliation of the current character.

Responsibilities:

- Register a new character on first login.
- Match an existing provisional roster entry by user confirmation, not name guessing.
- Store actual GUID, name, race, class, and realm.
- Capture progression and rested XP.
- Capture location and resting state.
- Capture money and bag capacity.
- Capture professions when APIs expose them.
- Mark bank/mail/profession recipe data stale until the relevant UI has been opened.
- Update `lastSeen` continuously at sensible checkpoints and `lastLogout` during logout.

The first time an unrecognized character logs in, show a small prompt:

- Add as new roster member.
- Link to a provisional roster slot.
- Ignore this character.

This is how name changes are reconciled safely.

---

## 10. Rested-XP estimator

For the active character, use the game-provided rested XP value.

For offline characters:

1. Start from the last observed rested XP.
2. Calculate elapsed offline time.
3. Use whether the character logged out in a rested area.
4. Apply a configurable accumulation rate and cap.
5. Apply a configurable Well Rested modifier if known.
6. Clamp the result.
7. Return the estimate plus a confidence indicator.

Recommended return shape:

```lua
{
    amount = 18000,
    percentageOfLevel = 45,
    isEstimated = true,
    confidence = "MEDIUM",
    calculatedAt = 123456789,
}
```

Do not hard-code unverified Forever rates as facts. Begin with configurable defaults and implement calibration:

- On login, compare the previous estimate with the actual value.
- Derive an observed accumulation rate when the character gained no XP while offline.
- Maintain a bounded moving average per character or perk configuration.
- Reset calibration when a relevant Legacy perk changes.

The UI must display `Estimated` for offline rested XP.

---

## 11. Priority engine

The priority engine must be pure, deterministic, and independent from WoW APIs.

Entry point:

```lua
local result = PriorityEngine:Evaluate(accountState, characterStates, settings)
```

Return an ordered list:

```lua
{
    {
        characterId = "Player-GUID",
        score = 83,
        reasons = {
            "Rested XP is estimated to be capped",
            "Herbalism is blocking First Aid supplies",
            "Character is eight levels behind the main",
        },
    },
}
```

### 11.1 Default scoring factors

| Factor                                            |       Default contribution |
| ------------------------------------------------- | -------------------------: |
| Manually pinned character                         |                      +1000 |
| Rested XP ratio                                   |                   0 to +40 |
| Main lacks the configured lead                    |                        +50 |
| Alt is more than the configured distance behind   |                   0 to +30 |
| Within two levels of 25/45/60                     |                        +15 |
| Profession or material shortage blocks the roster |                        +25 |
| Complete dungeon quest bundle ready               |                        +15 |
| Within ten profession points of 150/225/300       |                        +10 |
| Played in the immediately preceding session       |                        -10 |
| Snapshot too stale for a confident decision       | -5 and explanatory warning |

Store weights in defaults and make them configurable later.

### 11.2 Hard recommendation rules

- A manual pin always wins.
- If the Warrior is not maintaining the configured lead, prefer the Warrior unless another character is at or near the rested cap.
- Prefer a capped-rested character before wasting further rested accumulation.
- Allow a resource blocker to override normal rotation.
- Never hide uncertainty caused by stale snapshots.
- Always explain the top recommendation using two or three concise reasons.

---

## 12. Checklist engine

Checklist categories:

- `LOGIN`
- `PREPARE`
- `LEVEL`
- `PROFESSION`
- `DUNGEON`
- `TRANSFER`
- `LOGOUT`

Task model:

```lua
{
    id = "route-peacebloom-warrior",
    characterId = "Player-GUID",
    category = "TRANSFER",
    priority = 80,
    title = "Send Peacebloom to Chop Suey",
    reason = "The Warrior is below the configured healing-potion reserve",
    completionMode = "MANUAL",
    completed = false,
    generatedAt = 123456789,
}
```

### 12.1 Daily checklist template

At session start:

- Check rested XP and recommendation.
- Collect and route mail.
- Repair equipment.
- Train available abilities if the addon can safely detect them; otherwise show a manual reminder at relevant levels.
- Restock food, water, bandages, and healing potions.
- Check gathering skill against the current zone.
- Check profession milestone proximity.
- Check dungeon quest readiness.
- Use Dedicated Study when unlocked and available, if its API state can be read.

During play:

- Gather relevant resources without excessive detours.
- Keep the active gathering profession in range for the current zone.
- Prefer first-clear dungeons with quest bundles.
- Preserve reserved materials.
- Send or mark meaningful upgrades before disenchanting or selling.

Before logout:

- Mail materials to their configured owners.
- Mail unwanted green items to the Enchanter when appropriate.
- Refill another character's consumables when stock permits.
- Craft items that free meaningful bag space.
- Repair when convenient.
- Park in an inn or capital.
- Record or generate the next intended objective.

Tasks may be automatically completed only when the condition is reliable. Every task must also support manual completion or dismissal.

---

## 13. Material-routing engine

Use item IDs and categories rather than localized names.

Rule model:

```lua
{
    id = "linen-to-priest",
    itemId = 2589,
    category = "CLOTH",
    destinationCharacterId = "priest-guid",
    reserveOnSource = 0,
    priority = 100,
    reason = "Early bags and Tailoring/Enchanting progression",
    enabled = true,
}
```

Required capabilities:

- Exact item rule.
- Material-category rule.
- Destination character.
- Source reserve.
- Account-wide reserve.
- Split allocation.
- Priority ordering.
- `Do not consume` warning.
- Stale inventory warning.

Default policies:

| Material              | Primary destination | Policy                                                       |
| --------------------- | ------------------- | ------------------------------------------------------------ |
| Cloth                 | Priest              | Bags and Tailoring/Enchanting first; allow minimum First Aid progression |
| Healing-potion herbs  | Warrior initially   | Maintain configured potion stock; Druid gathers              |
| Other herbs           | Druid               | Reserve for Alchemy milestones                               |
| Ore and stone         | Warrior             | Reach useful Engineering threshold first                     |
| Surplus ore and stone | Shaman              | Feed Blacksmithing                                           |
| Leather               | Rogue               | Reserve Engineering requirements before LW allocation if configured |
| Unwanted green items  | Priest              | Equip, auction, or disenchant according to manual classification |
| Meat and fish         | Designated cook     | Produce useful stat/XP food before selling surplus           |

The addon should show guidance at the mailbox but must not automatically attach or send items.

---

## 14. Inventory ledger

Inventory is snapshot-based.

Sources:

- Bags: update while the character is online.
- Bank: update only when the bank has been opened and successfully scanned.
- Mail: update only when the mailbox has been opened and successfully scanned.
- Guild bank: out of scope for MVP.

Each source stores:

```lua
{
    scannedAt = 123456789,
    complete = true,
    items = {
        [2589] = 34,
    },
}
```

Account totals must include timestamps and indicate when one or more character sources are stale. Do not claim an exact account total if a relevant source has never been scanned.

---

## 15. Profession and First Aid tracking

Track for each profession:

- Current skill.
- Current configured target.
- Observed known/unlearned recipes per character, including acquisition sources when exposed.
- A selected recipe focus toward the next milestone and a live-updated material grocery list.
- Next milestone.
- Character responsible.
- Last scan time.
- Relevant material shortages.
- Legacy milestone completion.

Default milestone mapping:

| Character level target | Profession skill target |
| ---------------------: | ----------------------: |
|                     25 |                     150 |
|                     45 |                     225 |
|                     60 |                     300 |

First Aid requires dedicated logic:

- Track standard healing-potion quantities by character.
- Track potion ingredients separately from bandage cloth.
- Track bandage quantities.
- Give the Warrior and Rogue a high default First Aid priority.
- Warn before consuming cloth reserved for Priest bags or Tailoring progression.
- Support a configurable potion stock minimum.
- Allow the Warrior to be the initial central potion crafter while still permitting every character to train First Aid.

Forever recipe data is volatile. Keep item IDs, recipe IDs, requirements, and build metadata in versioned files under `Data/`. Business logic must not depend on English item names.

---

## 16. Dungeon and Legacy tracking

The initial dungeon implementation may be manual-first because Forever quest IDs and dungeon data can change during beta.

For each dungeon, support:

- Level range.
- Eligible characters.
- Available and completed quests.
- Prerequisite quests.
- First-clear status.
- Final-boss completion.
- Desired item notes.
- Recommended role.
- Legacy bracket membership.
- User-defined priority.

Recommendation states:

- `HIGH`: first clear with most or all quests.
- `MEDIUM`: important equipment target or role-practice objective.
- `LOW`: repeat run without quests or target equipment.

Legacy tracking must include:

- Each class at level 25, 45, and 60.
- Each non-gathering primary profession at 150, 225, and 300.
- Dungeon bracket completion.
- Account-wide points earned.
- Planned perk allocation per character.
- Well Rested status or intended priority when detectable/configured.

Static dungeon and Legacy data must include a source/build comment and be replaceable without changing services or UI code.

---

## 17. User interface

### 17.1 Main window

The MVP window should contain:

1. `Today`
2. `Roster`
3. `Professions`
4. `Settings`

Add `Materials`, `Dungeons`, and `Legacy` as later tabs.

### 17.2 Today panel

Display:

- Recommended character.
- Recommendation confidence.
- Two or three explanatory reasons.
- Primary session objective.
- Profession objective.
- Dungeon opportunity.
- Material transfers.
- Five highest-priority checklist items.
- Before-logout checklist.
- Pin/override control.

Example:

```text
Play Kit Cat next

• Rested XP is estimated to be capped.
• Herbalism is blocking First Aid supplies.
• Kit Cat is eight levels behind Chop Suey.

Today
[ ] Reach level 15
[ ] Gather 30 Peacebloom
[ ] Raise Herbalism to 75
[ ] Send 20 Peacebloom to Chop Suey
[ ] Log out in an inn
```

### 17.3 Roster panel

Each character card shows:

- Actual and planned name.
- Full first-and-last character name, separate from the realm and provisional label.
- Race, class, role, and main indicator.
- Level and XP.
- Rested XP with exact/estimated marker.
- Last seen and stale state.
- Location and resting status.
- Profession skills and targets.
- Current objective.

### 17.4 Settings panel

Allow editing:

- Roster membership and provisional-name links.
- Main character.
- Target level lead.
- Priority weights.
- Level and profession milestones.
- Potion and consumable stock targets.
- Material-routing policies.
- Notification verbosity.
- Rested-XP rate/cap assumptions.

### 17.5 UI requirements

- Native visual style compatible with Forever.
- Movable window with saved position.
- Reasonable default size for 1080p and ultrawide displays.
- Scrollable content where necessary.
- No permanent screen obstruction.
- No combat-time popups except critical errors explicitly enabled by the user.
- Keyboard and mouse operation.
- Text should remain understandable without colour alone.
- Selectable, copyable diagnostic and roster text for reporting problems without screenshots.

---

## 18. Slash commands

Implement:

```text
/rq
/rq today
/rq roster
/rq professions
/rq pin <character>
/rq unpin
/rq rescan
/rq diag
/rq debug on|off
/rq export
/rq import
/rq reset-session
```

`/rq diag` should show:

- Addon version.
- Client build and interface number.
- Detected client project/flavour.
- Available API capabilities.
- Current character GUID.
- Database schema versions.
- Last snapshot times.
- SavedVariables initialization status.
- Loaded optional integrations.

Do not print sensitive or excessively large SavedVariables by default.

---

## 19. Export and import

Because beta persistence has been unreliable, export/import is an MVP requirement.

Requirements:

- Open a copyable multiline edit box.
- Export a compact serialized representation of configuration, roster links, policies, objectives, and routing rules.
- Include export format version and checksum where practical.
- Do not use executable Lua source as the import format unless it is strictly parsed and never executed.
- Validate size, schema, types, identifiers, and version before import.
- Show a preview of changes.
- Require explicit confirmation before replacing current configuration.
- Preserve a rollback copy of the preceding configuration in memory until logout or reload.

Avoid adding a large serialization dependency unless the custom format becomes a maintenance burden.

---

## 20. Optional integrations

Integrations are optional and must not be required for core operation.

### Questie

Potential uses:

- Determine whether known dungeon quests are available or completed.
- Link objectives to quest information.

### Auctionator

Potential uses:

- Compare estimated auction value against disenchant value.
- Mark materials as safe to sell.

Integration rules:

- Detect addon availability safely.
- Isolate each integration in its own module.
- Never reference undocumented globals without capability checks.
- Core addon must load and function if an integration is absent or broken.

---

## 21. Development milestones and acceptance criteria

### Milestone 0 — Compatibility spike

Deliverables:

- Minimal `.toc` and `Bootstrap.lua`.
- Client/interface detection.
- `/rq diag` skeleton.
- Character GUID, name, level, XP, rested XP, and resting-state output.
- Basic account and per-character SavedVariables.
- `docs/BETA_API_NOTES.md` with observed results.

Acceptance criteria:

- Addon loads without Lua errors.
- `/reload` works.
- Full client restart behaviour is documented.
- Unsupported APIs are reported without crashing.

### Milestone 1 — Database and snapshots

Deliverables:

- Database initialization and migrations.
- Character registration/linking.
- Snapshot service.
- Login/logout/event updates.
- Diagnostic snapshot output.

Acceptance criteria:

- Five characters appear after each has logged in once.
- Name changes do not create duplicates when the GUID remains stable.
- Partial or absent SavedVariables recover safely.
- Stale snapshot timestamps are visible.

### Milestone 2 — Roster dashboard

Deliverables:

- Main frame.
- Roster tab.
- Character cards.
- Main-character and role configuration.
- Planned-name editing and linking.

Acceptance criteria:

- All roster state is usable without inspecting Lua tables.
- Window position persists when client persistence functions correctly.
- Unknown/off-roster characters can be ignored or linked explicitly.

### Milestone 3 — Rested estimation and priority

Deliverables:

- Offline rested estimator.
- Initial calibration logic.
- Priority engine.
- Explanation generation.
- Pin/unpin behaviour.
- Today tab recommendation header.

Acceptance criteria:

- The engine produces deterministic results for identical inputs.
- Offline estimates are never labelled as exact.
- A pinned character always wins.
- Main-lead and rested-cap rules are covered by tests.
- Recommendation always includes explanatory reasons.

### Milestone 4 — Daily checklists

Deliverables:

- Checklist data model.
- Session task generation.
- Manual complete/dismiss actions.
- Login and logout task groups.
- Session reset.

Acceptance criteria:

- A complete session can be guided from the Today tab.
- Dismissed tasks do not immediately regenerate without a state change.
- Logout reminder detects whether the active character is resting.

### Milestone 5 — Professions and material routing

Deliverables:

- Profession snapshots and milestones.
- Bag scanner.
- Material categories.
- Routing policies.
- Account material totals with timestamps.
- First Aid and cloth-reservation policies.
- Mailbox guidance UI.
- Suggest needed recipe/material transfers and general-purpose bags for empty bag slots.
- Respect each sender's grocery reserves and clearly distinguish observed, stale,
  unknown and in-transit inventory. Never guess a recipe's learning-item mapping.

Acceptance criteria:

- The addon can explain where cloth, ore, leather, and herbs should go.
- It warns before allocating cloth reserved for the Priest.
- Warrior Engineering and Shaman Blacksmithing reserves are distinct.
- Stale inventory is clearly identified.
- No protected mailing action is automated.

### Milestone 6 — Legacy and dungeons

Deliverables:

- Level and profession Legacy milestones.
- Dungeon data model.
- Manual-first dungeon checklist.
- Quest-bundle readiness.
- Desired-drop notes.
- Legacy bracket completion.

Acceptance criteria:

- The Warrior's 15–25 dungeon campaign can be planned and tracked.
- First clears are ranked above no-objective repeat runs.
- Static data can be updated independently from services and UI.

### Milestone 7 — Hardening and release

Deliverables:

- Import/export.
- Migration and corrupt-data tests.
- Performance review.
- Manual test plan.
- README and screenshots.
- CI validation and release ZIP.
- Changelog.

Acceptance criteria:

- Fresh install, upgrade, `/reload`, and full restart are tested.
- No Lua errors during the manual test plan.
- CI runs formatting, static analysis, unit tests, and packaging.
- Release ZIP has the correct top-level directory.

---

## 22. Testing strategy

### 22.1 Unit tests

Test pure modules outside WoW:

- Priority scoring.
- Main-level lead logic.
- Rested-XP estimation and clamping.
- Calibration behaviour.
- Material reserves and split allocation.
- Checklist generation and suppression.
- Character linking.
- Schema migrations.
- Empty, partial, stale, and invalid snapshots.
- Import validation.

Example fake adapter:

```lua
local FakeApi = {
    GetCharacterProgression = function()
        return {
            level = 25,
            xp = 12000,
            xpMax = 40000,
        }
    end,

    GetRestedXP = function()
        return 20000
    end,

    IsResting = function()
        return true
    end,
}
```

### 22.2 In-game tests

Required smoke tests:

- Fresh install.
- Login on a known character.
- Login on an unknown character.
- Link actual character to provisional roster slot.
- `/reload`.
- Full client restart.
- Gain XP and level up.
- Enter and leave a rested area.
- Open and close bank.
- Open and close mailbox.
- Learn or increase a profession.
- Move items between bags.
- Change zone.
- Complete and dismiss tasks.
- Export, reset, and import configuration.
- Disable optional integrated addons.
- Enter combat and verify no prohibited UI operation occurs.

### 22.3 Performance constraints

- Do not rescan every bag slot every frame.
- Debounce bag, quest, and profession events.
- Do not rebuild hidden panels unnecessarily.
- Avoid unbounded history tables.
- Keep debug logging disabled by default.
- Avoid loading large static datasets until their feature is opened or required.

---

## 23. GitHub and CI

Use two workflows.

### `validate.yml`

Run on pushes and pull requests:

1. Check formatting.
2. Run Luacheck.
3. Run unit tests.
4. Verify required addon files exist.
5. Verify `.toc` references existing files in valid load order.

### `package.yml`

Run on version tags:

1. Re-run validation.
2. Copy only runtime addon files into `RosterQuartermaster/`.
3. Exclude tests, development configuration, and repository metadata.
4. Create `RosterQuartermaster-<version>.zip`.
5. Attach the ZIP to the GitHub release.

Use semantic versions beginning with `0.1.0` for the first usable MVP.

---

## 24. VS Code and GitHub Copilot guidance

Recommended development support:

- Lua Language Server.
- StyLua integration.
- Luacheck task.
- GitHub Copilot and Copilot Chat.
- A workspace task for tests.
- A workspace task for packaging.
- A development junction linking the repository addon directory into the Forever client's `Interface/AddOns` directory.

Create `.github/copilot-instructions.md` containing:

```markdown
# Roster Quartermaster Copilot Instructions

- Target World of Warcraft: Forever.
- Use Lua 5.1-compatible syntax unless the client proves otherwise.
- Use the global namespace `RQ`; do not introduce unrelated globals.
- Put every direct WoW API call behind `RQ.Api`.
- Keep recommendation, routing, estimation, and checklist logic pure and testable.
- Do not automate protected actions such as combat, crafting, mailing, or auctions.
- Use item IDs and character GUIDs as canonical identifiers.
- Treat names as display values that may change.
- Treat offline character state as timestamped snapshots.
- Label inferred rested XP as estimated.
- Every SavedVariables schema change requires an idempotent migration.
- UI modules must not contain planning business logic.
- Capability-check beta APIs and degrade gracefully.
- Add or update tests whenever planning logic changes.
- Do not add external dependencies without documenting why native code is insufficient.
```

The implementation agent should commit after each completed milestone or coherent sub-milestone so failures can be isolated easily.

---

## 25. Manual gameplay defaults

Seed these defaults but expose them through settings.

### Initial progression sequence

1. Create all five characters and park them in rested areas.
2. Warrior to approximately 12–15 with Mining and temporary Skinning.
3. Priest to approximately 10–12 to establish bags, wand, Tailoring, and Enchanting.
4. Druid through the Skyborne starting zone to establish Herbalism.
5. Warrior to 25; replace temporary Skinning with Engineering around level 15–20.
6. Druid to 25.
7. Priest to 25.
8. Rogue to 25.
9. Shaman to 25.
10. Continue in approximately five-level waves while maintaining the Warrior's configured lead.

### Daily character-selection policy

1. Manually pinned character.
2. Character approaching the rested-XP cap.
3. Warrior if he lacks the intended lead.
4. Character needed to resolve a material or profession bottleneck.
5. Character with a strong first-clear dungeon opportunity.
6. Lowest appropriate character with meaningful rested XP.

### Default material policy

1. Priest wand and initial bags.
2. Minimum First Aid progression for the Warrior.
3. Priest Tailoring/Enchanting milestones.
4. Warrior and Rogue bandages.
5. Remaining characters' First Aid.

These are recommendations, not enforced restrictions. The user must be able to override them at any time.

---

## 26. Definition of done

The first complete release is done when:

- The addon loads on the current Forever client without Lua errors.
- Each roster character can be linked despite provisional or changed names.
- Character snapshots survive `/reload` and, when the client permits, full restart.
- `/rq today` recommends a character and explains why.
- Rested XP is tracked exactly for the active character and estimated for offline characters.
- The Warrior lead rule works.
- Level and profession milestones are visible.
- Daily and logout checklists work.
- Material-routing rules cover cloth, herbs, ore, stone, leather, and green items.
- First Aid potion and bandage priorities are represented separately.
- Inventory information is timestamped and stale state is visible.
- No protected action is automated.
- Configuration can be exported and imported safely.
- Pure logic has unit-test coverage.
- CI produces a valid release ZIP.
- README and manual test documentation are complete.

The agent should favour a reliable, explainable MVP over speculative integration with every possible Forever API. A user-visible manual control is preferable to an unreliable automatic inference.
