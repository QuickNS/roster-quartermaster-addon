# Changelog

## 0.0.38 - Filtered four-tab workspace

- Keep realm and ruleset/faction filters above Roster, Bags and Inventory,
  Professions and Settings. Empty scopes stay empty; All is explicit.
- Show suggested roster order, class, rested XP, profession lag and observed gold.
  Main is per realm/faction and wins equal-level ties; lower levels come first.
  Remove pins and main-lead settings. Moving a Main between groups clears its designation.
- Add expandable recorded bags/bank/inbox item rows and equipped bag sizes.
  Search keeps all recorded items visible, dimming nonmatches; bag upgrades remain separate.
- Group orange recipes and per-craft materials under Professions. Optional Auctionator
  v1 cached unit prices produce estimated craft costs only when every reagent is priced
  in the active market. Missing/unsupported prices remain unavailable.
- Add numeric grocery minimum editing and a draggable compact all/per-character
  grocery window for Auction House browsing. It remains open without the main window.
- Retire activity ledgers, monthly wallet history and generated session checklists,
  including commands, runtime modules and saved state. Latest money snapshots remain.
- Schema 19 migrates both SavedVariables roots idempotently, preserving retained
  inventory, recipes, groceries, mail and rested evidence. Back up before upgrading;
  configuration exports must be regenerated after the upgrade.
- Automated Lua/native-frame regressions and package checks cover the revamp.
  Live Forever and Auctionator acceptance remains pending.

## 0.0.37 - Minimap launcher layering

- Raise the native launcher above minimap artwork: use at least MEDIUM strata
  (retain higher minimap strata) and a frame level eight above the minimap.
- Apply layering only at creation so drawer addons retain control after collection.
  Appearance, dragging and saved angle behavior are otherwise unchanged; schema 18 remains.
- Add regression coverage for low/high minimap strata and collector-owned layering.
  Live-client rendering confirmation remains pending.

## 0.0.36 - Round, movable minimap launcher

- Replace the square fixed launcher with a native round tracking-button border,
  smaller centered icon and optional circular texture mask.
- Left-drag follows the minimap edge using cursor position and effective UI scale.
  Dragging never toggles the dashboard; regular left-click still does.
- Schema 18 saves an account-wide angle, defaulting to 225 degrees. Migration
  is idempotent, rejects invalid angles and preserves all retained data.
  Fresh post-upgrade configuration exports are required.
- Stop drag updates on release, hiding, combat, logout, geometry failure or
  collector ownership. Reparented/reanchored drawer buttons are not reclaimed.
- Configuration import/rollback refresh native placement without moving a
  collector-owned button. Missing mask APIs retain the native round border.
- Verified 459 Lua tests, 4 package tests, clean lint, formatting and Lua 5.1 syntax.
- Live Forever appearance/drag and drawer verification remain pending.

## 0.0.35 - Minimap collector compatibility

- Give the native minimap launcher the stable frame name `RQMinimapButton`.
  Collectors that skip unnamed buttons can now discover it and remember its
  drawer placement. No external library or SavedVariables change is required.
- Add regressions for name-based discovery, collector-owned parent/position/
  visibility across world entry, and working click/tooltip handlers after moving.
- Verified 449 Lua tests, 4 package tests, and clean lint, formatting and Lua 5.1
  syntax checks for the changed files.
- Live verification with the user's drawer addon remains pending.

## 0.0.34 - Trade groups and Cooking/Fishing

- Add PvE/PvP + Alliance/Horde roster views, active-group default, and explicit
  unknown-group labels. Faction is observed natively; rulesets use explicit realm
  labels or a manual Manage roster choice.
- Apply shared ruleset/faction/realm eligibility to all mail proposals and
  attachment clicks, bank-transfer advice, bag transfer/crafting plans,
  shipment credit and profession-provider coverage.
- Add one Cooking/Fishing assignee per combination in Manage roster, with
  replacement/clear controls and a roster badge. Known raw meat/fish IDs and
  explicitly classified food go there before other recipient groceries/surplus,
  while sender reserves and priority bag materials remain protected.
- Schema 17 adds optional identity facts and a Cooking/Fishing assignment map.
  Older snapshots survive; unknown trade identities must be refreshed before
  transfers. Fresh configuration exports are required after upgrade.
- Packaged with 447 passing Lua tests, 4 passing package tests, clean lint,
  formatting and Lua 5.1 syntax checks.
- Live-client acceptance remains pending.

## 0.0.33 - Removal release

- Packaged and validated with 430 Lua tests, 4 package tests, clean lint,
  formatting and Lua 5.1 syntax. Live-client acceptance remains pending.

- Replace the fixed/planned roster workflow with dynamic explicit add/ignore
  registration. No character-slot limit, planned slots, presets or linking.
  Retain actual registered characters and their role/main choices.
- Remove LOW discard highlights and the bag-space report; remove the gear
  advisor, including profiles, editor, bag arrows and tooltip scoring.
- Remove dungeon and Legacy tracking. Retain the manual `dungeonReady` ranking
  signal and rested/play-next planning; it is not a progress tracker.
- Remove profession guides and next-20 leveling paths, including tooling,
  import workflow and assets. Those plans are archived, not future roadmap work.
- Retain native profession/recipe scans, automatic one-craft orange groceries
  and visual review, explicit goals/reserves, inventory/bank/mail, bag upgrades
  and crafting plans, profession advice, activity/checklists and configuration
  transfer.
- Schema 16's idempotent migration removes retired data only, preserving
  registered characters, roles/main, retained settings and snapshots, along with
  retained goals, inventory, recipes, rested state, activity and mail history.
  Back up account and per-character SavedVariables with the client closed.
- Old-schema configuration exports require a fresh post-upgrade export; they
  are not SavedVariables backups. Downgrade requires the matching old addon and
  pre-upgrade data. No packaging, validation or live-client pass is claimed yet.

## 0.0.32 - Visual grocery review

- Roster > Grocery list and `/rq supplies <member>` open character-scoped
  Inventory cards instead of a text window. Existing Full report actions retain
  selectable text exports; recipe reports remain unchanged.
- Show item icons, shortage-first ordering and six quantity columns: target,
  carried, missing, withdraw, collect and in transit. Color distinguishes
  shortages from covered stock without treating unknown quantities as zero.
- Add All, Shortages, Collect / incoming, Covered and Unknown filters with
  summary counts. Recipe/item evidence expands inline; pagination remains
  bounded and only visible items request icons/names.
- Retain offline/disabled member review, stale evidence labels and conservative
  bank/mail semantics. Review does not change mail eligibility or stock targets.
  Separate the filter/source and Gear advisor controls to avoid overlap.
- Schema remains 15. No automatic crafting, sending or inventory movement.

## 0.0.31 - Proactive orange-recipe groceries

- Derive materials for one craft of each learned orange recipe from complete
  profession recipe scans, without manual needs or goals. Require observed
  profession skill below its cap, complete reagents and positive skill-ups.
  Shared materials sum across recipes/professions; an active goal replaces the
  same recipe's one-craft allowance. Manual needs/reserves remain stock floors.
- Recompute on scans, skill changes and inventory updates. Keep stale cached
  orange needs visibly uncertain; new successful scans remove needs for recipes
  no longer eligible. Never overwrite configured needs or goals.
- Feed automatic needs into mail suggestions, sender reserves, bank/mail coverage
  and LOW protection. Reports identify automatic recipe materials and their
  source recipes/timestamps, including needs for items not previously carried.
- Add a Grocery list button and target count to roster character details.
  Offline and disabled registered members can be reviewed; disabled members do
  not become mail recipients. Inventory stock cards expose recipe provenance.
- No SavedVariables schema change: automatic groceries are derived from the
  already persisted recipe snapshots. Sending and crafting remain manual.

## 0.0.30 - Restore LOW eligibility for confirmed non-equipment

- Prevent incomplete or cached gear observations from suppressing LOW marks when
  the live bag scan confirms the item is not equipment. Actual/unknown equipment,
  mail proposals, reserves and explicit item routes remain protected.
- `/rq bag-space` now refreshes visible marks, reports enabled/disabled state,
  counts free slots or eligible stacks, and summarizes exclusions by reason.
  Rendering failures are retried rather than reported from stale status.
- Add regressions for missing gear links, stale classification, preserved
  reserves and equipment protection, exclusion counts and rendering recovery.
  The full-bags-only threshold and schema 15 remain unchanged.

## 0.0.29 - Route Light Feathers to Mages

- Suggest transferable Light Feather surplus (item ID 17056) for the first
  enabled same-realm roster Mage, using the existing scroll-routing rules.
- Preserve sender reserves, explicit recipient needs and configured item routes.
  Mage senders retain their surplus; missing/localized names do not affect
  Light Feather recognition. Sending remains manual. No schema change.

## 0.0.28 - Handle zero-valued gear stat entries

- Validate native quantities before checking supported stat tokens. An explicit
  numeric zero for an unsupported token no longer blocks otherwise understood
  armor; malformed quantities remain unknown and all tooltip lines are audited.
- Include values in nonzero unsupported-stat messages. Do not silently ignore
  real bonuses or equate spell-damage tokens with spell power or healing.
- Add pure and native-path regressions for zero placeholders, score preservation,
  malformed quantities, tooltip effects, arrows and discard protection.
- The build 70245 cuffs report omitted the numeric spell-damage value, so live
  confirmation is still required. No profile or SavedVariables schema changes.

## 0.0.27 - Correct gear classification and wearable-armor checks

- Filter confirmed non-equipment before scoring, using native equippability
  and recognizing both empty and `INVTYPE_NON_EQUIP` slot tokens in fallback.
  Missing or inconsistent slot information stays unknown, not weapon-like.
- Replace the incorrect action-use eligibility check with guarded
  `C_PlayerInfo.CanUseItem`. Wearable armor without a Use action must not
  be labelled unusable for that reason. Preserve level/tooltip restrictions.
- Share classification with discard protection and add item name/equip-location
  evidence to versioned gear reports. No schema change; profiles are preserved.
- Weapon comparisons remain review-only pending a dedicated weapon-set scorer.

## 0.0.26 - Conservative equipment upgrade advisor

- Add opt-in per-character heuristic/custom stat profiles, editable through
  Inventory > Gear advisor or `/rq gear`, with a configurable score threshold.
- Compare armor/simple accessories to currently equipped gear; show blue native
  bag arrows and explanatory tooltip score/stat differences. Respect paired
  slots and zero baselines; never describe score gain as DPS/healing gain.
- Withhold recommendations for unknown data, weapons/off-hands, unique/set/
  effect text and unsupported tooltip/stat contracts. Use capability-checked
  native observations with exact variant links and a conservative enUS audit.
- Protect positive upgrades and unevaluated equipment from LOW discard marks.
  Clear stale overlays/tooltips on gear/bag/profile changes and combat/logout.
- Add copyable gear diagnostics and schema 15's idempotently migrated GUID-keyed
  profile settings, included in configuration transfer. No automatic equip,
  sell, destroy, craft or send action.
- Native frame/tooltip semantics and heuristic usefulness require client tests.
- Validation: 481 Lua tests (19 new gear tests), 26 Python tests, clean Lua lint,
  formatting/syntax and unchanged empty guide-catalog check.

## 0.0.25 - Mage scroll routing and white-item bag highlights

- Suggest surplus items with the exact observed `Scroll:` prefix for the first
  enabled same-realm Mage in roster order. Preserve sender reserves, explicit
  needs and item-ID policies; do not bounce scroll surplus between Mages.
- Include white items alongside gray items in lowest whole-stack vendor-value
  highlights. Preserve quest/lock/price/reservation safeguards and protect current
  mail proposals, including Mage scroll suggestions.
- Update live price collection, diagnostic/help text and acceptance tests.
  No SavedVariables schema change; mailing and discarding remain manual.

## 0.0.24 - Full-bag low-value junk highlights

- Highlight the lowest whole-stack vendor-value gray junk in full carried bags
  with green borders and a LOW label; include cheapest ties.
- Exclude unknown/zero prices, non-gray quality, locked/quest-associated items,
  known stock/recipe/reserve targets (including disabled members) and explicit
  routing items. Per-item reservations protect every stack of that item.
- Use current bag-slot observations and revalidate identity/count/lock state
  before painting. Clear marks on bag/lock changes, combat, logout and free space.
  Never pick up, destroy, sell or replace native bag-button action scripts.
- Capability-check native separate/combined bag layouts; provide `/rq bag-space`
  and Inventory's Free bag space action when native frames cannot be highlighted.
  Session-local on/off; no schema change or persisted vendor-price assumptions.
- Actual-client bag-frame and vendor-price acceptance remains pending.
- Validation: 443 Lua and 24 Python tests pass, zero lint warnings/errors in
  86 files, clean formatting/Lua 5.1 syntax and unchanged guide-catalog check.

## 0.0.23 - Consolidated visual workspace

- Replace seven primary tabs with Roster, Inventory, Activity and Settings.
  Merge recommendation/rested/task context into the roster, retaining disabled
  members and planned slots. Add slot creation and main selection directly there.
- Move membership, linking, roles and presets to Roster's Manage roster view.
  Settings now presents advanced rested assumptions, character overrides and
  configuration export/import, rather than the membership editor.
- Combine Supplies and Bags in Inventory with stock/upgrades sections, search,
  source/owner filters and mail/shipments access. Add item icons, source/quantity
  metrics and explicit unknown/stale/provisional states. Bound rendering to twelve
  reusable entries; stock metadata requests are limited to the displayed page.
- Present Activity wallet/month totals as labeled metrics with distinct colors,
  readable scope and compact coverage. Unverified native counters remain unavailable,
  never zero. Full evidence, timestamps and GUIDs remain in Details/copy.
- Apply a consistent dark palette with gold accents, class portraits/profession
  icons and compact selected-character summaries. Preserve score explanations and
  planning warnings in detailed views without filling the primary workspace.
- Preserve slash/text paths, all planning/accounting and protected-action guards.
  No SavedVariables change; schema remains 14. Native visual acceptance is pending.
- Validation: 430 Lua tests and 24 Python tests pass; zero lint warnings/errors
  across 83 files, clean formatting, Lua 5.1 syntax and guide-catalog checks.

## 0.0.22 - Session workflow and remaining safe roadmap foundations

- Schema 14 adds validated daily checklists, logistics policies, potion/bandage
  reserves and a manual dungeon/Legacy ledger; migrations are copy-safe and idempotent.
- Today Details opens Session tasks and Dungeons / Legacy. Tasks support manual
  complete/dismiss/undo, stable signatures, explicit reset and new-UTC-day login reset.
  Cached resting observations drive logout reminders without teardown guesses.
- Add explicit item-ID herb/leather/food/Engineering/Blacksmithing routes, ordered
  recipient preferences and source-aware account material totals. Reserves overlap
  generic stock targets by maximum, not addition. All allocations stay finite.
- Eligible pending/inbox bags with observed capacity suppress duplicate upgrades;
  provisional coverage never becomes ready-to-equip or craft-ready inventory.
- Add user-defined dungeon catalogs and pure readiness ranking, manual quest/clear/
  drop objectives, Legacy credits, recorded point totals and planned perk allocations.
  No native quest contract, dungeon facts, point formula or perk cost is invented.
- Add explicitly gated profession-lag ranking; default behavior stays unchanged.
- Add bounded, non-executable, checksummed configuration export/import with preview,
  explicit confirmation and session-local rollback. Observations are not backups
  and are never replaced by imported configuration.
- Add deterministic runtime-only ZIP packaging and a tag/manual release workflow.
  Remote CI/publication and live-client acceptance remain unverified.
- Add the prioritized [user acceptance walkthrough](docs/USER_ACCEPTANCE_TESTS.md).
  Native financial categories and guide-driven next-20 paths remain evidence-gated.
- Final integrated validation: **422 Lua tests, 24 Python tests**, zero lint
  warnings/errors in 81 files, clean formatting/Lua 5.1 parsing/whitespace, and
  unchanged empty approved-guide catalog.

## 0.0.21 - Native Activity dashboard

- Add the main Activity tab with Ledger, Activity and History subviews, GUID
  character/all-roster selection, normalized realm/unknown-realm filters and UTC
  month navigation. Reuse the existing wallet/month accounting; no native
  financial mappings or inferred earnings are enabled.
- Add eight-card paging with reusable native rows, explicit stale/unknown and
  empty-filter states, current/profession-high observations and per-character
  retained wallet/gap details in History.
- Preserve filters on refresh and copy all matching cards with their scope,
  not just the visible page. Refresh/Save snapshot only capture the registered
  active GUID; failed/partial reads are not presented as successful captures.
- `/rq activity [member|all]` now opens the dashboard with chat fallback.
  Existing explicit copy/text/month commands remain available.
- Add guarded month/page keyboard navigation. Preserve roster/Today keyboard
  behavior, planning/routing, schema 13 and all existing ledger data. Filter
  selections are session-local; no migration is needed.
- Validation: 343 Lua and 20 Python tests, clean lint/formatting/Lua 5.1 parsing
  and unchanged guide catalog. Visual/client acceptance remains pending.

## 0.0.20 - UTC monthly wallet observations

- Add schema-13 per-character monthly summaries with first/last/high wallet
  observations, distinct observed days, comparable-interval counts and
  unclassified wallet increases/decreases. Existing schema-12 data is preserved
  without reconstructing past months.
- Add `/rq activity-month <YYYY-MM> [member|all]` and
  `/rq activity-months [member|all]`, using native copy reports and chat fallback.
  Roster reports expose partial coverage, current scope and asynchronous
  balances; they do not sum individual highs or call transfers income.
- Keep offline/reload/loading/build/read gaps and cross-month intervals
  unallocated. Retain their all-period balance-difference totals and latest 20
  detailed intervals separately from monthly observations.
- Guard UTC calendar conversion, integer ranges and persisted monthly invariants;
  publish wallet/snapshot/months together. Monthly history survives raw-history
  pruning. In-session continuity is deliberately not restored from SavedVariables.
- Native lifetime counters, category attribution, money-transfer reconciliation,
  earned/day and the dedicated Activity/History tab remain unimplemented.
- Validation: 327 Lua tests and 20 Python tests, clean lint/formatting/Lua 5.1
  parsing and unchanged guide catalog. Native client acceptance remains pending.

## 0.0.19 - Activity baselines and statistics discovery

- Start N7a with schema-12 per-character wallet observations, a bounded 20-sample
  history, total capture count and independently retained observed wallet and
  profession highs. Migrate complete registered-wallet snapshots at their
  original timestamp; no historical income or monthly totals are fabricated.
- Capture registered GUIDs on normal refresh/money/profession events, publish
  with the snapshot and mirror independently. Preserve previous values on failed
  reads/backward clocks; deduplicate identical samples and skip logout activity scans.
- Add copyable character/all-roster reports and text fallback with known/stale/
  unknown coverage, disabled-member inclusion and exact integer copper sums.
  Latest offline balances are not simultaneous wealth, earnings or spendable
  cross-realm funds; individual maxima are never summed.
- Inventory 18 requested native metrics but leave them unavailable until their
  Forever IDs, units and character/account scope are verified. Add bounded,
  self-only raw native-category discovery for collecting that evidence.
- Add `/rq activity`, `activity-copy`, `activity-text`, `activity-refresh` and
  `activity-probe`; add capability and capture-status diagnostics.
- N7a native contract verification remains open. Monthly accounting, flow
  classification, roster money-transfer reconciliation and the dedicated
  Activity/History UI remain N7b/N7c, not features of this release.
- Validation: 306 Lua tests and 20 Python tests; clean Lua lint/formatting/syntax
  and unchanged deterministic guide catalog. Live acceptance remains pending.

## 0.0.18 - Guide contract and offline import toolchain

- Add closed guide-format-1 JSON and human-approval schemas, plus an offline
  Python standard-library validator/compiler. No dependency or SavedVariables
  schema change (still schema 11).
- Validate canonical ID types, explicit ranges, recipe versus item identities,
  per-craft arithmetic, estimated skill-ups, output units, one-time acquisition
  costs, dependency cycles, alternatives and intermediate reserves. Unsupported
  branch-dependent routes fail explicitly rather than flattening into a shopping list.
- Add production gates for permissions, full article retrieval, source/target
  edition, exact client/build/locale, independent claim evidence and a separate
  human review tied to exact candidate bytes. Classic, synthetic, unresolved or
  unreviewed data cannot ship.
- Compile deterministic literal-only Lua 5.1 with escaped UTF-8 text and atomic
  replacement. Errors/check mode preserve existing generated data.
- Add the development-time semantic import skill and two original synthetic
  layout fixtures with shared factual expectations. They are not third-party
  guide copies or evidence of a completed model extraction.
- Bundle an intentionally empty catalog, guarded pure lookup/fallback and
  diagnostic guide count. No Today guide paths or new grocery contributions
  are enabled yet. A real guide remains blocked on permitted article content,
  independent Forever-build checks and human approval; no approval is fabricated.
- Add Python tooling tests to CI/devcontainer. Validation: 20 Python tests,
  286 Lua tests, clean Lua lint/formatting/syntax and reproducible empty catalog.

## 0.0.17 - Profession coverage and free-slot advice

- Add a pure, deterministic profession advisor for enabled same-realm roster
  members. Fresh supported profession scans distinguish two empty primary slots,
  one available slot and fully learned/locked choices; stale/unknown evidence
  never becomes permission to replace a profession.
- Enumerate at most 36 pairs per selected character and show the top three with
  factor breakdowns, trade-offs and stable numeric-ID tie breaks. Consider
  roster gaps, useful duplicate gatherers, observed recipe-output demand,
  complementary supplies and soft class/role preferences.
- Bundle versioned general-WoW reference relationships with provenance. These
  are advisory evidence, not certified Forever recipe, equipment, profit or
  trainer-location guarantees; cross-faction transfer compatibility stays unknown.
- Add Profession advice to Roster/Today details and `/rq professions [text] [member]`.
  Plan/clear intent, cycle balanced/gathering/self-sufficient focus, or set explicit
  preferred/excluded professions with slash commands. Native learning/unlearning,
  travel and crafting remain manual.
- Schema 11 migrates independent per-character intent/preferences idempotently,
  preserves them through login/unlink and mirrors without aliasing. Clicks
  revalidate observed slots and exclusions; intent never supplies roster coverage.
- Record the user's basic mail-tracking success separately from extended contract
  verification. The build-specific automatic mail gate is unchanged.
- 283 tests pass, including 21 new advisor, migration, UI and 0/1/5/6/20/50-member
  coverage tests. Existing priority ranking, mail assistance and stock logic are preserved.

## 0.0.16 - Roster shipments and inbox observations

- Add a schema-10 validated, persistent roster-to-roster shipment ledger. Passive
  secure hooks observe final send arguments and readable attachments; the addon
  never invokes SendMail, TakeInboxItem or ReturnInboxItem.
- Start in observation mode. A correlated success signal remains uncertain until
  explicitly confirmed, or until the user verifies the current client build
  after the documented smoke test. Failures, overlaps, late signals and interrupted
  attempts never automatically become sent. Non-roster/cross-realm sends are ignored.
- Read accessible inboxes with guarded legacy contracts, full-download checks,
  command-idle checks and repeated paired bag/inbox observations. Publish ledger
  and inventory together; preserve unconfirmed caches on failure/close/logout.
- Match unique messages conservatively. Partial/full collection needs a recent
  observed manual take, attachment removal and coherent carried gains. Duplicate
  subjects/messages, returns and unsupported disappearance require reconciliation.
- Add `/rq shipments [text]`, confirm/stop-credit controls, manual history pruning,
  build verification commands, mail diagnostics and the Bags **mail** source with
  sender/recipient and pending-versus-observed detail.
- Fresh confirmed pending and eligible observed inbox stock can provisionally
  reduce groceries in Supplies/Today and repeated material proposals. Mail never
  becomes craft-ready stock or donor surplus. Stale/unresolved stock, COD and
  returned inbox items receive no credit. New logins invalidate active inbox credit.
- Preserve bag-only attachment assistance when inbox APIs are missing.
- User reported basic 0.0.15 bank scanning working. Extended bank cases and all
  new mail-event contracts still need live-client verification; see the manual plan.
- 262 automated tests pass, including 16 shipment/API/accounting regressions.

## 0.0.15 - Coherent personal-bank snapshots

- Scan accessible personal-bank containers using capability-checked Forever
  character-bank enums/tab enumeration, never guessed Classic indices. Bank
  opening and inventory changes trigger debounced scans.
- Stage bag/bank observations together and require stable repeated contents and
  tab layout before publication. Pending/failed changes invalidate combined
  availability immediately; close/logout retain cached counts without teardown
  scans. Unknown/unvisited and verified empty remain distinct.
- Schema 9 adds bank container counts/capacities, labels, eligible transfer
  counts, attempt timestamp and coherence evidence. Idempotent migration preserves
  legacy data without fabricating bank eligibility.
- Add All/Bags/Bank search filtering, source/container details and bank status
  cards. Default search covers both sources; old carried-only tests remain explicit.
- Verified local bank stock reduces material procurement with manual withdrawal
  instructions in Supplies and Today details. Bag-material expansion uses banked
  intermediates while protecting existing goals. Ready bag upgrades still require
  carried bags.
- Bank surplus needed by same-realm members produces non-attachable withdrawal
  guidance. No automatic bank moves/crafts/sends; recipient stock is never credited
  for a proposed withdrawal. Existing carried mail checks remain intact.
- 246 tests pass with clean lint, formatting and Lua 5.1 parsing. Client bank API,
  event timing and visual acceptance remain pending. User reported carried
  search working on 2026-10-04; that report does not validate the new bank feature.

## 0.0.14 - Roster-wide carried-bag search

- Add a search field and owner filter to Bags. Name queries match literal
  case-insensitive substrings; numeric queries match exact item IDs. Clear search
  to return to the existing upgrade/crafting overview.
- Show full owner/realm/GUID, item name/ID, optional icon, aggregate carried
  quantity and snapshot freshness. Include bound/reserved stock and registered
  disabled members; exclude ignored/pending characters and planned slots.
- Display stale/incomplete matches and separate uncertain coverage. Count
  unresolved names instead of treating a name search as proof of absence.
- Add `/rq bags <query>`, `/rq find <query>` and Copy results. Preserve query,
  owner filter, unsubmitted drafts and valid scroll positions during refreshes.
- Keep matching/scope/order pure and metadata resolution outside row rendering.
  No stock, routing, protected action or schema change; view state is ephemeral.
  **This delivers only the carried-search portion of N2a. Bank snapshots remain next.**
- 224 tests pass with clean lint, formatting and Lua 5.1 parsing, including
  stack aggregation, literal queries, scope/coverage, metadata replies, fifty-owner
  reuse and existing mail/recipe regressions. Client visual checks remain pending.

## 0.0.13 - Names for materials outside bags

- Resolve grocery, recipe-material/output, bag-material and mail labels from
  observed roster names or guarded native item-info APIs, not only the current
  character's bags. IDs remain canonical; no hard-coded item-name table is used.
- Request cold item data at most once per ID/session. Handle replies for displayed
  materials absent from bags and refresh visible dashboards without scanning or
  changing stock. Failed replies remain explicit; unavailable names retain IDs.
  Reopen copyable/text reports after asynchronous data arrives.
- Keep resolved metadata in session memory; schema 8, inventory quantities,
  freshness, targets and routing are unchanged.
- 210 tests pass, including the three missing material IDs, recipe lists,
  asynchronous replies, legacy/restricted APIs and cross-character name reuse.
  Lint, formatting and Lua 5.1 checks pass; live client verification is pending.

## 0.0.12 - Graphical Roster and Today

- Replace verbose dashboard lists with compact rows and independently scrollable
  selected details. Preserve full names, class/role/level, freshness, observed bag
  sizes, configured goals and Settings actions.
- Add native class accents/icons, profession icons and text-backed lag badges.
  Only the verified live player GUID gets a portrait; other rows use class icons.
  Missing/restricted optional graphics leave text and controls usable.
- Add realm grouping and session-only name/level/priority/lag/class sorting,
  all/member/behind/uncertain filters and stable selection. Previous/Next row
  controls work without keyboard APIs; guarded Up/Down navigation respects typing.
- Today keeps engine ranking and pin controls, shows the strongest reason,
  confidence, numeric rested XP and a configured-cap bar. Distinguish observed,
  estimated, cached and unknown values, including known zero and unknown scales.
- Keep schema 8, copy reports, generic Supplies/Bags/recipe/mail controls and all
  planning calculations unchanged. No automatic sends or other protected actions.
- 205 tests pass with clean lint, formatting and Lua 5.1 parsing. Graphical
  regressions cover missing APIs, offline portraits, long labels, zero/unknown
  progress, selection/filtering, fifty-row reuse and scroll preservation.
  Actual Forever appearance/keyboard behavior still requires client checks.

## 0.0.11 - Locked-container routing to Rogues

- Propose transferable locked-container surplus for an enabled same-realm Rogue
  using observed class, not preset names. Keep sender reservations and prior
  explicit allocations; Rogue senders retain their own containers.
- Identify locks from localized per-bag-slot tooltip evidence, separate from the
  temporary busy flag. Unknown tooltip/binding evidence never authorizes the rule.
  Lockpicking requirements remain explicitly unverified.
- Preserve locked-instance requirements through grouped mail proposals. Attach
  the locked instance when locked/unlocked boxes share an item ID, and recheck
  before pickup. Crafting, unlocking and sending are not automated.
- Schema 8 adds validated eligible locked-container counts with an idempotent
  migration; old snapshots receive no invented lock evidence.
- 193 tests pass, including mixed-state instances, unavailable/localized tooltips,
  reservations, recipient restrictions, migration and mail preflight. Lint,
  formatting and Lua 5.1 syntax checks pass; live tooltip verification is pending.

## 0.0.10 - Flexible roster and profession-lag foundation

- Revalidated the accumulated 0.0.9 baseline: 169 tests, clean lint, formatting
  and Lua 5.1 syntax. Added GitHub CI using the existing development image recipe;
  remote workflow execution is not yet verified.
- Fresh installations start with an empty plan and offer an optional five-member
  preset. Add/remove/rename any number of planned slots from Settings or slash
  commands. Removal unlinks without deleting a character or their goals.
  Existing plans and links survive the upgrade. Large plans use Settings rather
  than an offscreen registration popup.
- Restrict material/recipe/bag proposals and tailoring assignments to known
  same-realm recipients. Preserve cross-realm roster visibility, local upgrades,
  sender reserves and existing manual attachment checks.
- Add a shared pure `5 x level` primary-profession assessment in Roster, Today,
  Supplies and diagnostics. Separate configured ceilings from trained caps,
  report stale/unknown evidence and rank-training needs, and allow explicit
  secondary-profession opt-in. No new ranking weights or automatic assignments.
- Schema 7 adds validated benchmark settings and optional observed
  primary/secondary classification. Idempotent migration preserves old data and
  does not invent new observations.
- Validation: 184 passing tests; clean lint, formatting and Lua 5.1 parsing.
  New UI/client behavior still needs the documented manual acceptance checks.

## 0.0.9 - Bag sizes and priority tailoring upgrades

- Added a standalone Bags tab and `/rq bags` with per-slot equipped capacities,
  freshness, existing-bag upgrades, crafter/recipe jobs and material shortages.
- Mail suggestions now include known larger-capacity bags replacing occupied
  smaller bags. Reserve owners' own upgrades and allocate each transferable bag
  once before planning new crafts.
- Capture fixed recipe outputs and observed general-purpose bag capacity from
  localized tooltip data. Select the largest learned craftable bag for remaining
  slots; unknown/stale data is not guessed. Cross-character crafting requires
  output binding evidence.
- Add priority groceries for bag crafts, including observed bolt-to-cloth
  conversions. Ready bags and upgrade materials precede ordinary grocery and
  profession-surplus routes. Existing sender stock/leveling reserves stay protected.
- Migrate schemas 1-5 transactionally and idempotently to schema 6. Preserve old
  records without inventing bag capacity or output metadata; rescan for new data.
- Crafting, equipping and sending remain manual; existing attachment buttons
  support bag-upgrade proposals. In-transit/draft/bank/mail stock remains unknown.

## 0.0.8 - Full-name fixes and click-to-attach mail

- Correct Forever 1.60.x/interface 16001 split first-name/surname handling while
  retaining separate realm and GUID identity. Existing GUID records update on rescan;
  name evidence no longer mislabels the second value as a realm.
- Resolve missing item names from matching item links and modern/legacy item-info
  APIs; preserve known labels across temporary cache gaps and duplicate stacks.
  Request missing item data once and refresh on successful cache events.
- At an open mailbox, `/rq mail` groups proposals by recipient with Attach item
  and Attach all buttons. Explicit clicks fill the recipient and attach exact
  quantities; splitting stacks is supported. `/rq mail text` remains read-only.
- Validate unique complete names, same realm, mailbox/combat/cursor state, draft
  recipient, free slots, live stack counts, binding and locks. Preserve existing
  attachments, block same-item repeats and stop on partial failures. Never send
  mail, bypass restrictions, or retry attachments in the background.
- Optional `identity.nameComplete` metadata stays within schema 5. Old ambiguous
  names must be refreshed or explicitly overridden before using attachment controls.

## 0.0.7 - Profession routing and orange recipe goals

- Route cloth surplus to tailors, metal/stone trade goods to blacksmiths, and
  observed unbound green BoE weapons/armor to enchanters for manual review.
  Exact grocery needs take precedence; retain sender reserves and surplus for
  the sender's own professions. Deterministic allocation prevents double spending.
- Added an Orange recipes picker on Supplies cards and `/rq targets [member]`.
  Select a learned orange recipe, edit the target skill, and save its grocery goal
  without typing recipe IDs. Revalidate freshness, difficulty, materials and cap
  before saving. Recipe colors and color-change caveats appear in reports.
- Capture optional item quality/bind type and recipe difficulty within schema 5;
  old scans remain compatible, with missing metadata unknown until rescanned.
- Explain empty mail proposals with recipient setup/scan status, covered targets,
  or shortages without matching sender surplus. Clarify that profession skills
  alone do not generate material requests and free bag space is not an empty
  equipped bag slot.

## 0.0.6 - Copyable reports, profession supplies, and logout preservation

- Added copyable diagnostic/roster reports, recipe catalogs and grocery lists in
  selectable native text windows; no clipboard API or saved-data import is assumed.
- Prefer unmodified character names, with a manual full-name override and raw name
  API diagnostics. Never interpret the realm return as a surname.
- Added bag item snapshots and per-profession observed recipe catalogs with learned
  flags, reagent data and game-provided acquisition sources.
- Added selected-recipe skill goals, minimum-stock needs, dynamically recomputed
  grocery shortages, and a Supplies tab.
- Added manual mail proposals for needed materials, identified unlearned recipes
  and empty bag slots. Sender reserves, binding/lock checks, deterministic allocation
  and stale-data warnings apply. No mail action is automated.
- Added schema-5 validated supplies state, preserving schema-4 roster/planning data.
- Added a tested devcontainer with Python, Lua 5.1, Luacheck and pinned StyLua.
- Reproduced logout-time API zeros overwriting valid XP, money, bag, and profession
  observations, preventing an offline rested estimate.
- Gate the final scan on usable progression data. With missing progression or a
  zero XP maximum, keep the prior snapshot and its real observation timestamps.
- Build LOW-confidence, explicitly labelled cached logout baselines when earlier
  observations are complete. Count accumulation from logout, not from the older scan.
  These fallback baselines never train calibration rates.
- Persist specific reasons when a baseline cannot be built instead of always
  reporting the generic missing-observation message.
- Existing zeroed snapshots require revisiting the character to recapture live
  data. No SavedVariables reset is needed.
- Automated teardown/relogin regressions pass; in-client confirmation is pending.

## 0.0.5 - Rested estimation and play-next recommendations

- Added Today recommendations with deterministic ranking, two/three reasons,
  explicit confidence, and persistent pin/unpin overrides.
- Implemented hard pin, near-rested-cap, main-lead, and manual-blocker priorities,
  plus configurable weighted factors and previous-character session history.
- Added offline rested estimates from complete logout baselines; live API values
  remain observed, and unavailable evidence remains unknown.
- Added bounded, separate inn/outside login calibration with prediction comparison,
  unchanged-XP/uncapped sampling rules, and manual perk/multiplier reset.
- Added a Planning tab for provisional rates/caps, level policy, member multipliers,
  and manual blocker/dungeon signals. No unverified Legacy/quest scan is assumed.
- Added transactional schema-4 planning/calibration/session migration, independent
  per-character state copies, and pin/session rekeying on GUID promotion.
- Added `/rq today [text]`, `/rq planning`, `/rq pin <name|slot|ID>`, `/rq unpin`,
  and calibration diagnostics. The dashboard initially opens Today.
- Rested mechanics and new native UI behavior still require Forever client testing.

## 0.0.4 - Roster dashboard and minimap launcher

- Added a native minimap button with hover tooltip to open/close the dashboard.
- Added movable Roster/Settings tabs, scrollable character cards, and saved window
  position with Close/Escape and reset controls.
- Added main/role configuration, explicit unlink/relink, and offline-member
  controls without logging into or scanning those characters.
- Added age/stale/incomplete labels and retained last-observed offline rested XP
  labeling; no offline estimation is claimed yet.
- Added schema-3 window settings migration, preserving prior links and snapshots.
- Kept text commands as UI fallback, guarded combat-time opening, and avoided
  rebuilding hidden panels or replacing focused name-edit drafts.
- Added mocked native frame, minimap, configuration, and migration tests.
- `/rq` now toggles the dashboard; `/rq diag` remains the diagnostic command and
  `/rq roster text` retains chat roster output.
- New native UI behavior and persistence require in-client validation.

## 0.0.3 - Registration command fallback

- Fixed add/link/ignore commands and login callbacks crashing when the
  registration UI module is absent, leaving slash commands in the chat input.
- Moved registration orchestration into the snapshot service so slash commands
  and UI buttons share the same behavior without requiring the UI to load.
- Added a visible incomplete-installation warning and UI module status in diagnostics.
- Added regression tests reproducing the reported `RegistrationPrompt` nil error.
- SavedVariables remain at schema 2; no reset or migration is required.

## 0.0.2 - Database and snapshots

- Added transactional, idempotent schema-1 to schema-2 migration with validation
  of consumed nested data and roster links.
- Added account-wide timestamped character snapshots and independent per-character
  copies, GUID rename reconciliation, and normalized name/realm fallback promotion.
- Added explicit add/link/ignore registration, editable provisional labels,
  a combat-safe native prompt, and slash-command fallback.
- Added money, location, equipped bag-capacity, and profession skill adapters.
- Added targeted event updates with 0.25-second coalescing, synchronous logout
  capture, and incomplete-section markers that preserve older observations.
- Added roster/slot diagnostics with timestamps and stale-state warnings.
- Added migration, registration, and snapshot tests, plus schema and upgrade docs.
- New APIs, events, UI, and migration still require Forever client testing; the
  previously reported smoke-test pass applies to version 0.0.1.

## 0.0.1 - Compatibility spike

- Added an explicit-load-order Lua 5.1 addon skeleton.
- Added guarded client/character API probes and `/rq diag`.
- Added basic schema-1 SavedVariables initialization and login/logout/rescan
  snapshots, preserving unsupported or malformed databases without writing.
- Added dependency-free mocked tests, Luacheck and StyLua configuration, and
  installation/manual-validation documentation.
- Set interface metadata to `16001` from the user-reported Forever `1.60.1`,
  build `70170` (Oct 1 2026).
- Recorded the user's 2026-10-02 smoke-test pass covering installation,
  diagnostics/rescan, reload, and full-restart persistence. Detailed API/event
  results and extended failure cases remain individually unconfirmed.
