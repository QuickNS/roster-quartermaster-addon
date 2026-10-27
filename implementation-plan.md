# Roster Quartermaster — Implementation plan

## 1. Release scope and status

The current release is **0.0.38, SavedVariables schema 19**. It revamps the workspace,
keeps realm/faction filters visible across four tabs, adds inventory highlighting
and compact groceries, and removes activity lists and pins. No checklist here implies
client acceptance. Historical delivery notes remain in [CHANGELOG.md](CHANGELOG.md);
this document describes the active product and remaining work.

The product coordinates actual account characters through explicit add/ignore
registration, rested/play-next planning, profession observations and material
logistics. It must not require a fixed composition or a preset. The roster has
no planned-slot system or character-count limit; bounded UI pages and configuration
transfer payload limits are separate safety constraints.

Trade-compatible roster views group members by PVE/PVP and Alliance/Horde.
All transfers additionally retain same-realm validation. Unknown identities are
visible but excluded from transfer/provider planning. Manage roster can assign
one Cooking/Fishing GUID per group and manually confirm an unlabelled realm's
ruleset. Native faction and explicit realm labels take precedence over guesses.
Known raw meat/fish IDs and user-classified food prioritize that assignee after
sender reserves and bag-material priorities, before other recipient groceries.
Main is a realm/faction equal-level tie-breaker; these are logical trade
rosters, not duplicated databases.

### Retired scope — archived, not deferred

The following are removed, including their UI, commands and relevant runtime/
development assets:

- Fixed/planned roster templates, provisional slot names and links, presets.
- LOW discard highlighting and its bag-space report.
- Gear advisor profiles, scoring, overlays/arrows, tooltip advice and editor.
- Dungeon tracking and Legacy catalogs, credits and perk-allocation tracking.
- Profession guide ingestion, approval/compiler/import tooling, guide assets
  and guide-driven next-20 leveling plans.

Guide and next-20 plans are **archived and no longer on the roadmap**. They are
not awaiting source approval or later activation. Do not rebuild them as part
of hardening or treat their old milestones as outstanding work.

Keep the manual `dungeonReady` ranking signal and manual rested multipliers.
Neither requires a dungeon/Legacy ledger. Keep native recipes, one-craft orange
groceries and explicit recipe/skill goals; none is an optimized leveling guide.

## 2. Engineering boundaries

- Target World of Warcraft: Forever and Lua 5.1 syntax.
- Use `RQ`; all direct game calls, event registration and native UI operations
  go through capability-checked `RQ.Api`.
- Keep recommendation, estimation, allocation, profession advice and
  craft-cost calculations pure and testable. UI renders service results rather
  than implementing its own planning logic.
- Character GUIDs and item IDs are canonical; names are display values.
- Offline data is timestamped observation, not remotely queried live state.
  Inferred rested XP must always be labelled estimated.
- Missing/restricted/failed APIs remain visible and must not become zero or
  known-empty facts. Capability-check optional graphics and keyboard helpers.
- No automated combat, crafting, equipping, purchases, mailing or character
  selection. Attachment assistance is an explicit revalidated user click only.
- Every schema change requires transactional, idempotent migration.
- Avoid external dependencies; document why native code is insufficient before
  adding any. No runtime dependency is required by the retained scope.

## 3. Runtime architecture

The TOC is the explicit runtime load manifest. Maintain the existing division:

| Area | Responsibility |
| --- | --- |
| `Core/` | API adapter, validation/configuration, database, migration and diagnostics |
| `Models/` | Character identity and snapshot shapes |
| `Data/` | Retained reference data such as cooking ingredient IDs and profession relationships |
| `Services/` | Snapshot capture, pure planning/logistics and workflow orchestration |
| `UI/` | Four-tab workspace, registration, character/grocery/bag/mail views |
| `Bootstrap.lua` | Lifecycle, slash dispatch and event orchestration |
| `Tests/` | Lua mock/unit/regression tests and packaging tests |
| `Tools/package.py` | Runtime-only deterministic archive construction |

The addon does not browse websites or invoke an LLM. Removed guide tooling is
not part of this architecture or the development validation path.

## 4. Persistence and schema 19 migration

`RQDB` holds account settings, actual roster configuration, character observations,
policies, session state and mail tracking. `RQCharDB` independently
mirrors current-character observations and relevant configuration.
See [DATA_MODEL.md](docs/DATA_MODEL.md) for evidence boundaries.

Schema 16 removes retired data only: planned-roster/link metadata, gear settings
and dungeon/Legacy progress. Preserve registered characters, registration states,
roles, main choice, retained settings, snapshots, inventory, recipes, goals/
reserves, rested state, profession intent and mail history.
Do not interpret missing planned slots as missing actual members or rebuild a
starter roster.

Schema 17 adds optional native faction/ruleset identity facts and an initially
empty ruleset/faction-to-cook GUID map. Preserve unknown identity fields as
unknown, enforce the trade boundary centrally and test repeated migration.

Schema 18 adds a finite minimap angle in `[0, 360)` with default 225. Commit it
when dragging stops; never save drawer coordinates or take back a collected
button. Config imports/rollback refresh only RQ-owned minimap placement.

Validate copied account and character roots before publishing either. Repeating
the migration must not lose retained state. Malformed retained fields or future
schemas must leave both originals intact and disable writes with diagnostics.
Test old-schema, partial, invalid and already-current data.

Require a client-closed SavedVariables backup before upgrade. Configuration
exports exclude observations and are not a substitute. Old-schema configuration
exports require a **fresh post-upgrade schema 19 export** from the source install.
Rollback/downgrade requires the matching old addon and pre-upgrade data.

## 5. Registration, snapshots and freshness

Fresh installs start empty. Unknown characters remain pending until explicitly
added or ignored. Add/resume and ignore have chat fallbacks and no combat popup.
No presets, slot assignment, linking or inferred class/profession roster exist.

Maintain GUID identity through renames. Promote actual name/realm fallbacks only
when unambiguous; preserve/report conflicts. Main, role, enabled state and
per-member planning choices operate directly on actual characters.
Ignored records retain saved history but stop tracking; pending/ignored records
are not providers or recommendation candidates.

Capture login/rescan and debounced section-specific events for progression,
rested, location, money, bags and professions. Keep section attempted/successful
timestamps and completeness separate from `lastSeen`. A recent overall snapshot
does not imply recent bank, mail or recipe evidence. Protect final logout data
against unavailable APIs/teardown zeros.

## 6. Rested estimation and recommendations

Active rested XP is observed live; offline values require a logout baseline and
are labelled estimated. Cached logout fallbacks have lower confidence and cannot
train calibration. Learn bounded rates only from complete comparable login/
logout evidence. Reset calibration manually after mechanics/perk changes.

Default mechanics are configurable assumptions, not Forever facts: inn/outside
rates 0.625%/0.15625% of a level per hour, cap 150%, near-cap threshold 90% of
that cap and level cap 60.

Recommend lower levels first within each realm/faction; Main wins equal-level ties.
Then apply near-cap/resource signals, weighted rotation and stable GUID ties.
Preserve level-cap handling, freshness/confidence reasons and previous-session effects.
Manual `dungeonReady` remains a soft ranking signal, with no quest, clear,
drop or Legacy tracking behind it.

Primary-profession lag is `min(5 * level, ceiling)`, default ceiling 300.
Missing/stale data is not a deficit. Ranking influence is opt-in and off by
default; hard priority tiers are unchanged. Explicit profession goals remain
distinct from lag benchmarks.

## 7. Professions and groceries

Capture owned native profession skills and per-profession recipe lists.
Reject linked/guild lists and incomplete evidence; retain source timestamps.
Show rank-cap and incomplete/stale warnings rather than assumed empty skills.

Automatic groceries are materials for one craft of every learned orange recipe
with complete reagents, positive skill-ups and observed skill below its cap.
Sum shared reagents across recipes/professions. An explicit goal replaces that
recipe's allowance; manual needs/reserves are stock floors and must not be
overwritten or double counted.

Keep the orange picker and explicit recipe/skill-target editor. A goal estimates
crafts from observed data; it does not promise orange difficulty to the target,
automatically choose subsequent recipes, or generate a next-20 path.

Profession advice compares confirmed free primary slots using same-realm coverage,
reference relationships, observed output demand, preferences and soft class/role
fit. Learned choices are locked. Saved profession intent is separate from learned
skills and actual coverage; it is not a planned-roster feature.

## 8. Inventory, bank, mail and bags

Search registered characters by literal item-name substring or exact item ID.
Preserve owner/source filters, per-source quantities, unknown names and freshness.
Discovery can include disabled members and other realms without authorizing
cross-realm logistics or treating bound stock as transferable.

Use paired coherent personal-bank/bag scans. Verified owner bank stock covers
materials only with withdrawal prerequisites. Partial/unconfirmed bank evidence
cannot suppress shortages; bank-transfer suggestions are not recipient credit.

Allocate sender reserves and own upgrades first, then ready bag upgrades/materials,
Cooking/Fishing ingredients, other explicit needs and eligible general surplus.
Require the same known ruleset, faction and realm for each transfer and keep
deterministic single allocation per source. Retain observed profession routes,
Mage scroll/Light Feather routing and tooltip-confirmed locked-container routing
to Rogues, with all binding/metadata safeguards.

Ready-bag selection uses carried observed general-purpose bags. For unfilled
upgrades, use observed learned Tailoring outputs/capacities and complete reagents.
Known intermediates can expand material shortages; no guessed conversions.
Crafting/equipping remain manual. Mail/in-transit bags are not ready upgrades.

At a mailbox, Attach item/all refresh and revalidate exact quantities, recipient,
cursor, binding, combat and draft state. No Send call, automatic retry or background
attachment. Track only eligible uniquely identified same-ruleset/faction/realm roster shipments.

Default mail confirmation stays observational. Automatic confirmation requires
explicit verification for the exact client build after smoke tests. Paired
inbox/bag evidence reconciles manual collection; ambiguous/returned/stale records
remain uncertain. Confirmed pending/inbox stock is provisional coverage, not
craft-ready or donor stock.

## 9. Configuration transfer and retired lists

Do not retain activity ledgers, monthly accounting, profession-high histories or
generated session checklists. Schema 19 removes these records while preserving
the latest timestamped money observation and all retained logistics evidence.

Configuration transfer is strict bounded data parsing, replacement preview and
explicit confirmation, with session-only cancel/rollback. Preserve current
observations during import and rollback. Checksum is corruption detection, not
authentication. Configuration limits do not impose a roster-slot limit.

## 10. UI and diagnostics

Use four primary tabs: Roster, Bags and Inventory, Professions and Settings.
Realm/ruleset/faction filters are always visible above navigation and apply to all
character views. Explicit All is required to broaden scope. Roster shows suggested
order, professions, rested XP and latest gold; no pins. Bags/bank expand into
recorded items, with search dimming nonmatches and a separate bag-upgrade view.
Professions shows orange recipes/materials, optional cached Auctionator cost and
editable groceries. A small scoped grocery window remains available beside the AH.
Settings respects selected character scope; global assumptions/imports remain labelled.

Maintain text fallbacks, copyable full evidence, bounded pagination, coalesced
visible refreshes and stable selection/scrolling. Do not rebuild hidden dashboards.
Preserve edited input while refreshing observations. Class colors/icons supplement
text; unknown quantities are not colored as covered zeroes.

Remove all controls/help/copy text for retired modules, not just their navigation
buttons. Keep `/rq planning`'s manual dungeon-ready control clearly distinct
from removed tracking. Command examples belong in [README.md](README.md).

## 11. Active roadmap and release gates

1. **Validate the 0.0.34 trade boundaries and retained removal scope.** Check TOC, bootstrap,
   configuration transfer, migration, UI, tests and package contents for retired
   references. No new runtime behavior is certified by documentation.
2. **Run automated retained-feature regressions.** Lua 5.1 tests, lint, format,
   syntax and packaging tests using the existing toolchain. Verify migration
   retention/idempotence and absence of default roster creation. Do not run or
   restore deleted guide tests/compiler steps.
3. **Exercise client acceptance.** Fresh install, older-schema upgrade, reload/
   restart, unlimited dynamic membership, combat/fallback UI, manual readiness,
   groceries, bank/mail, bag crafting and configuration transfer.
   Record exact client version/build/interface and outcomes.
4. **Package only after validation.** Build the version-matched runtime archive,
   inspect its contents and perform clean-install smoke tests. Verify remote CI
   separately; local success does not prove remote jobs ran.
5. **Continue retained-feature hardening.** Resolve unverified native counter
   contracts and extended bank/mail/recipe/UI edge cases using client evidence.
   Categorized monthly accounting remains future work pending trustworthy data.

Guides, next-20 paths, gear scoring, discard highlights and dungeon/Legacy
tracking are not items in this roadmap.

## 12. Definition of done

- Both SavedVariables roots migrate transactionally to schema 19, preserving
  retained data and explicit registration/main/role choices.
- No fixed roster, slot/preset/link workflow or retired feature is loaded,
  exported as current configuration, rendered or shipped.
- Rested/play-next and manual readiness still work; native professions, orange
  groceries/goals, visual UI, inventory/bank/mail, bag upgrades, advice and
  configuration transfer pass their relevant checks.
- No observation is relabelled as live, certain, earned or client-verified without
  matching evidence.
- Documentation and package versions agree; fresh post-upgrade exports and
  backup/downgrade requirements are explicit.
- Automated checks, package inspection and the
  [acceptance walkthrough](docs/USER_ACCEPTANCE_TESTS.md) have recorded outcomes.

**Current state: 0.0.38 is packaged; 396 Lua tests, 4 package tests, lint,
formatting and Lua 5.1 syntax pass.** Live-client acceptance remains pending;
the manual definition-of-done items are not completed claims.
