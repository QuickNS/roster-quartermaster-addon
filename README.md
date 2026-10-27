# Roster Quartermaster

An account-wide roster coordinator for **World of Warcraft: Forever**.
See the [implementation plan](implementation-plan.md), [data model](docs/DATA_MODEL.md),
[beta API notes](docs/BETA_API_NOTES.md), and [acceptance walkthrough](docs/USER_ACCEPTANCE_TESTS.md).

## Current status: 0.0.38

`0.0.38` reorganizes the UI into four tabs with persistent realm and
ruleset/faction filters. Main is an equal-level tie-breaker within its realm/faction,
not a lead target. Bags and bank snapshots expand into item rows; search dims
nonmatches. Professions includes orange recipes, optional Auctionator craft costs,
editable groceries and a small floating grocery list for Auction House browsing.
Activity/checklist tracking and pins are removed. Schema 19 migrates saved data
idempotently. Live-client acceptance of this UI remains pending.

The roster is dynamic: explicitly **Add** actual characters or **Ignore** them.
There is no fixed roster size, planned-slot limit, starter preset, or linking
workflow. Registered characters retain their main/role choices and observations.

Previously removed in 0.0.33 (still absent):

- Planned/fixed rosters, provisional slots, presets and slot links.
- LOW discard highlights and their bag-space report.
- Gear advisor profiles, scoring, bag arrows, tooltip advice and editor.
- Dungeon tracker and Legacy tracking.
- Profession guides and next-20 leveling paths, including their tooling,
  import workflow, assets and roadmap items.

The manual **dungeonReady** planning signal remains: it is a ranking override,
not a dungeon tracker. Native profession/recipe scans, the orange recipe picker,
explicit recipe goals and one-craft groceries also remain; they do not require
or implement a guide.

### Retained capabilities

- Roster / Bags and Inventory / Professions / Settings visual workspace, minimap launcher,
  copyable reports, realm filters and offline character review.
- Observed live rested XP, explicitly estimated offline rested XP, deterministic
  play-next ranking, per-group Main tie-breakers and manual planning signals.
- Native profession skills and recipe scans, profession-lag labels, same-realm
  profession advice and separately saved profession intent.
- One craft of each eligible learned orange recipe as automatic groceries,
  explicit recipe goals, minimum-stock needs and potion/bandage reserves.
- Visual grocery cards, account-wide bag/bank/mail search, coherent personal-bank
  snapshots, manual withdrawal prerequisites and source-aware material coverage.
- Trade-compatible mail proposals, explicitly clicked attachment assistance, shipment
  observations and mailbox reconciliation. Sending always stays manual.
- Ready-bag upgrades and observed Tailoring bag-crafting/material plans.
- Latest observed character gold and safe configuration export/import.

No action automates combat, crafting, equipping, purchasing, sending mail,
collecting mail, selling, destroying items or selecting characters.
Opening a report or mailbox does not move items; only an explicit Attach click
uses the attachment helper.

## Installation and upgrade

1. Close the client and back up **both account and per-character SavedVariables**
   for RosterQuartermaster. Keep that backup for downgrade or recovery.
2. Install the complete addon under
   `Interface/AddOns/RosterQuartermaster/`, with `RosterQuartermaster.toc` directly
   inside that directory. Replace the old addon directory so retired runtime
   files are not left behind; do not delete SavedVariables.
3. Enable the addon, log in, and use `/rq diag` to inspect load/schema/API status.
   `/rq` or the **RQ** minimap button opens the dashboard.
4. Follow the [manual tests](docs/MANUAL_TEST_PLAN.md) before treating this
   candidate as safe for routine use.

Schema 16's idempotent migration removes retired data only: planned-roster and
slot-link metadata, gear settings, and dungeon/Legacy progress. It retains
registered characters, registration choices, roles, main designation, retained
settings, snapshots, inventory/recipe evidence, goals, reserves and mail history.
Schema 19 additionally removes activity ledgers, checklist decisions, pin and main-lead settings. Both roots are validated before publication.
Malformed or unsupported schemas disable writes rather than replace originals.
See [migration details](docs/DATA_MODEL.md#migration-and-recovery).

Schema 17 adds an initially empty Cooking/Fishing assignment map and optional
faction/ruleset identity fields without discarding retained data. Old characters
with unknown faction/ruleset are excluded from transfers until revisited.

Schema 18 adds the minimap angle, defaulting to the lower-left edge (225 degrees).
Existing character data and assignments remain intact. Back up SavedVariables
before upgrading.

**Old-schema configuration exports are not upgrade backups and cannot be
imported as schema 19 configuration. Make a fresh export after a successful
upgrade.** Export/import does not restore observations. Downgrading requires
the old addon and its matching pre-upgrade SavedVariables backup.

### Registration and identity

On an unknown character, choose **Add as new roster member** or **Ignore this
character**. `/rq add` and `/rq ignore` provide the same explicit choices;
`/rq register` reopens registration. Deferring the choice leaves a pending
character, not a planned roster member. No registration popup opens in combat.
If the UI is missing, reinstall the complete addon and use the slash commands.

Fresh installations start empty. Add any number of actual characters as you
visit them; no preset or profession/class composition is required. Settings
provides Add / resume, Ignore, Make main and role controls for selected records.
Ignoring stops tracking without deleting the record; ignoring a main
member clears that designation. Resume explicitly when desired.

GUIDs are canonical. Names and surnames are display values, not planning keys.
A normalized actual name-and-realm fallback can be promoted when a GUID becomes
available; conflicting records are reported, not guessed or silently merged.
Use exact GUIDs or unambiguous actual names in `[member]` command arguments.
No command accepts a retired planned-slot selector.

The adapter prefers unmodified names and handles Forever's observed first-name/
surname returns separately from realm. Revisit characters and `/rq rescan` to
refresh incomplete labels. `/rq fullname <full name>` sets an explicit actual-name
override; update it after a rename. Mail requires a uniquely verified full
recipient name on the same realm.

### Trade rosters and Cooking/Fishing

The roster starts in the active character's **PvE/PvP + Alliance/Horde** group
when known. Use the trade-group button for another combination, **All trade
groups**, or unknown identities. Characters remain in one account database;
this is a trade boundary and roster view, not a duplicate character record.
Explicit All filters enable account-wide review. Each realm/faction has its own
Main; changing a character's realm/faction/ruleset clears its old Main designation
rather than taking over the destination group's Main.

Faction comes from `UnitFactionGroup` on login/rescan, not from names or race
guesses. Ruleset is read from an explicit PvE/PvP token in the realm name.
If absent, select the character in **Manage roster** and click **Ruleset**
to confirm PvE or PvP manually. A realm change clears that fallback; observed
realm labels take precedence. Unknown/neutral faction never permits trading.

In **Manage roster**, select an enabled member and click **Assign Cooking/Fishing**.
This replaces the previous assignment for that combination only. Click
**Clear Cooking/Fishing assignment** to remove it. A `COOK / FISH` badge marks
the designated character. Assignment does not learn either profession.
Ignored, disabled, missing, or moved-out-of-group assignees are not eligible.

Mail suggestions, attachment clicks, bank-transfer advice, transferable bag
plans, shipment coverage and profession-provider coverage require the same
known ruleset **and** faction. The existing **same-realm safeguard also remains**:
cross-realm mail addressing/compatibility is not inferred from a shared ruleset.
Explicit item routes and grocery needs cannot bypass any of these boundaries.

## Dashboard

The minimap launcher is a named native button (`RQMinimapButton`) so collectors
that scan minimap children can identify it. It uses a round tracking-button
border and a circular icon mask when supported. It is layered above the native
minimap artwork without forcing layering after collection. **Left-drag** around the minimap
to reposition it; release to save the account-wide angle. A drag does not open
the dashboard. Ordinary left-click still toggles it. Dragging is disabled in combat.

RQ does not reclaim its position, parent or visibility after a drawer addon
moves it; use that addon's controls while collected. Reload after upgrading;
use your collector's rescan/settings if it does not refresh automatically.
Collectors that support only DataBroker/LibDBIcon registration may need
additional integration; this release does not claim support for every drawer.

The four primary tabs are **Roster / Bags and Inventory / Professions / Settings**.
The realm and ruleset/faction selectors remain above them. The default is the
active character's group; unknown identity stays in an unknown scope. Empty
filters stay empty. Select **All realms** and **All trade groups** explicitly to
review everything. Scope is session-only, shared across tabs and never changes
which character is actually logged in.

- **Roster:** suggested order, class, level, rested XP, observed gold and
  profession-lag highlights. Main is assigned through Details or Manage roster.
- **Bags and Inventory:** expand each character's bags/bank, review equipped bag
  sizes and choose Bag upgrades. Search by item name or exact ID; matching rows
  stay bright and other recorded items remain visible but dimmed. Pages are bounded.
- **Professions:** orange recipes and materials per craft. Auctionator v1 prices
  are optional cached copper/unit estimates for the active market only. Missing
  prices, another realm/faction or an unsupported API show unavailable, not zero.
  No purchase or crafting action is automated.
- **Grocery list:** Next owner cycles all/per-character stock review within the
  filter. Save stock edits an existing minimum; Set item stock opens a numeric
  item-ID/quantity form for the selected character (zero removes the minimum).
  Recipe requirements still contribute independently.
- **Compact list:** a small draggable, scrollable grocery window stays open when
  the main dashboard closes. It shows missing/target quantities and owners, follows
  scope changes and refreshes with observations. Counts are cached, not live stock.
- **Settings:** selected-character controls respect scope. Rested assumptions
  and export/import are explicitly account-wide settings.

`/rq today` uses recommendation order; `/rq planning` opens Settings.
`/rq supplies [member]` opens groceries and `/rq bags [query]` opens recorded items.
These commands do not add primary tabs.

- Drag the window to move it; its position is saved. **Center** or
  `/rq reset-window` restores the default.
- Roster rows show actual names, class/role/level, profession badges, rested
  values and evidence warnings. Select **Details** without changing the active
  character or ranking.
- Realm, sort and status filters operate on registered character views.
  Previous/Next row and capability-checked keyboard navigation preserve
  GUID-stable selection. Sorting/filtering does not modify configuration.
- **Rescan current** always scans the logged-in character, never an offline
  selection. View state is session-only; refreshes preserve valid scroll positions.
- Close with **Close**, Escape where supported, `/rq close`, or `/rq`.
  Entering combat hides the dashboard; it does not reopen automatically.
- Missing native UI/minimap support has text fallbacks. Use `/rq roster text`,
  `/rq today text`, and `/rq diag`.

Reports include names, realms, GUIDs, item quantities and timestamps. Review them
before sharing. Copy reports are troubleshooting snapshots, not configuration
backups; reopen after metadata arrives.

## Rested and play-next planning

Only enabled registered members participate. Within each realm/faction group,
lower levels are suggested first. Main wins equal-level ties; it never creates
a level-lead target or prevents the player from choosing another character.
Among the remaining equal-level ties, rested-cap/resource signals and weighted
rested XP, milestones, profession lag (if enabled), previous-session and freshness
signals apply. Exact ties use a stable GUID order. There is no pin override.
Offline rested values remain explicitly estimated and stale evidence remains labelled.

Initial mechanics are **unverified assumptions**, editable in Planning:

| Assumption | Default |
| --- | --- |
| Inn accumulation | 0.625% of one level per hour |
| Outside accumulation | 0.15625% of one level per hour |
| Rested cap | 150% of one level |
| Near-cap threshold | 90% of the configured cap |
| Configured level cap | 60 |

Active rested XP is read live. Offline estimates require a complete timestamped
logout baseline. Missing evidence remains unknown. A failed logout scan can
preserve a complete earlier observation as a **cached logout baseline**, marked
LOW confidence and accumulated from logout, not from its earlier scan time.
Teardown zeros must not overwrite valid data.

Login calibration compares predicted and actual rested XP only when elapsed time,
unchanged level/XP, complete observations and caps permit it. At most eight
samples per resting location are retained. Cached fallback baselines cannot
teach rates. Estimates remain estimates even with learned rates.

Use the member multiplier or **Reset calibration** after a relevant perk change;
perk detection is manual. Changing mechanics clears learned rates while keeping
valid observed baselines. **Resource blocker** and **dungeon ready** are manual
ranking signals only. Neither derives dungeon progress, quests, clears or Legacy
credits.

### Profession lag and advice

The primary-profession benchmark is `min(5 * level, configured ceiling)`;
the default ceiling 300 is an assumption. For example, level 21 and skill 81
gives a 24-point deficit against 105. Skill at its trained cap also gives a
rank-training warning, not a guarantee that training is available.

Unknown/incomplete/stale observations do not become zero skills or free slots.
Secondaries are excluded unless opted in, e.g. `/rq profession-track 185 on`.
Use `/rq profession-cap 197 225` for a profession ceiling override. Labels do not
change ranking unless `/rq profession-ranking on [weight]` enables the opt-in
primary-deficit score; default is off. Explicit goal targets remain separate.

**Profession advice** in Roster, or `/rq professions [member]`, explains enabled
same-realm coverage and up to three suggestions for confirmed free primary slots.
Two learned primaries remain locked; a stale scan requests a rescan, never an
unlearn action. Advice weighs coverage, companion professions, observed recipe
demand and soft class/role fit, not profit or globally optimal assignment.

- `/rq profession-focus <balanced|gathering|self-sufficient> [member]`
- `/rq profession-prefer <ID> on|off [member]`
- `/rq profession-avoid <ID> on|off [member]`
- `/rq profession-plan <ID[,ID]|clear> [member]`

Saved profession intent is not a planned character slot or an observed learned
skill. Learn manually and rescan. Primary IDs include Blacksmithing 164,
Leatherworking 165, Alchemy 171, Herbalism 182, Mining 186, Tailoring 197,
Engineering 202, Enchanting 333 and Skinning 393. Secondary skills do not occupy
primary slots. Reference relationships are not verified Forever trainer/recipe
or equipment guarantees.

## Native recipes and visual groceries

1. Visit registered characters and `/rq rescan` after the world loads.
2. Open each owned profession window. `/rq scan-recipes` retries the open window;
   linked/guild recipe lists are not recorded as owned. Missing APIs preserve
   old observations with errors, not successful empty scans.
3. Each complete recipe scan contributes materials for **one craft of every
   learned orange recipe** with complete reagents, positive skill-ups and
   observed profession skill below its cap. Shared ingredients sum across
   recipes/professions. Stale evidence remains visibly uncertain; a new successful
   scan removes recipes no longer eligible. This is not a next-20 leveling path.
4. Optionally use **Orange recipes** or `/rq targets [member]` to select a learned
   orange recipe and explicit target skill. The picker defaults to five more
   points bounded by the trained cap and requires recent complete observations.
   It rechecks eligibility when saving.
5. `/rq goal <profession ID> <recipe ID> <target skill> [member]` sets an explicit
   goal using an observed recipe. Target 0 clears it. A goal replaces that
   recipe's one-craft allowance, not other recipes' allowances. Crafts are an
   estimate: current orange difficulty does not guarantee skill-ups all the way
   to the target. Rescan and revise the selected recipe yourself.
6. `/rq need <item ID> <quantity> [member]` adds a minimum-stock target; 0 clears
   it. For example, `/rq need 2589 40` requests 40 Linen Cloth on the current
   character, subject to checking the item ID in this client.
7. **Roster > Grocery list** or `/rq supplies [member]` opens visual Inventory
   cards. Offline and disabled registered members can be reviewed without making
   them automatic mail recipients.

Grocery cards show **Target, In bags, Still needed, Withdraw, Collect mail and
In transit**, with shortages first. Filters cover All, Shortages, Collect /
incoming, Covered and Unknown. Whole-list counts, bounded pagination, item icons,
inline recipe details and Full report preserve evidence and unknown quantities.
Recipe lines include names/IDs, quantities and scan timestamps.

Recipe requirements sum; overlapping minimum-stock needs and reserves use a
maximum rather than double counting. Bag-crafting budgets retain separate
requirements. Missing/alternative reagent evidence is never filled by invented
guide data. Manual needs and goals are not overwritten by automatic groceries.

## Inventory, bank and bag upgrades

`/rq bags Copper` searches observed bags, bank and mail by case-insensitive
literal name substring. Digits-only queries are exact item IDs, e.g.
`/rq bags 2770`. `/rq find <query>` prints results without native frames.
Queries are limited to 128 bytes; pattern characters are literal.

Search includes offline and disabled **registered** members, bound equipment
and reserves. It excludes pending/ignored records. Owner/source filters, icons,
quantities, source timestamps and coverage warnings distinguish unknown from
empty. Bank/mail/carried quantities remain separate. Cross-realm discovery
never authorizes transfers. Clear search returns to bag upgrades.

### Personal bank

Open the personal bank to refresh it. Paired bag/bank scans must be coherent
before bank stock covers material needs. Closing the bank early, transfers in
progress, unsupported containers or partial scans cannot create a known-empty
bank or duplicate stock. Cached offline contents retain freshness labels.
Older unconfirmed bank observations are discovery-only until refreshed.

Verified owner bank stock reduces material deficits with a **Withdraw**
prerequisite. Bank-transfer suggestions require manual withdrawal and a fresh
mail proposal; they are not recipient credit. Account/guild bank stock is not
assumed accessible. Only carried items can be attached to mail.

### Bag upgrades and crafting

Inventory bag upgrades, also opened with `/rq bags`, use observed regular equipped
bag capacities. The backpack, bank and reagent bag are not replacement targets.
An owner's carried beneficial bag is reserved first, then transferable bags are
allocated once to same-realm members' smallest bags.

For remaining slots, the planner chooses the largest observed learned
general-purpose Tailoring bag output; stable GUID/recipe-ID order breaks ties.
Gray recipes are allowed. Unknown capacity, variable output, binding, reagents
or stale/incomplete evidence block unsupported assignments.

Material plans show crafter, recipe, craft count and recipients. Known learned
intermediate recipes can expand shortages into raw materials after existing
intermediate stock is used. Unobserved conversions stay as intermediate requests.
Thread and other non-cloth reagents remain included.

Ready bags and their materials precede ordinary grocery requests in mail
allocation. Craft, mail and equip manually, then rescan. Bags still in mail or
in transit are not ready upgrades; collect them before acting on renewed craft
plans. Capacity is not proof of equip eligibility.

## Mail, routing and reserves

`/rq mail` proposes safe trade-compatible transfers, prioritizing ready bags/materials,
the designated Cooking/Fishing character's raw ingredients, and then other
grocery shortages before general surplus routing. Sender needs,
reserves, recipe materials and own bag upgrades remain protected. Unknown
binding, busy/locked stacks and ambiguous names block unsafe attachment.

General routing uses observed evidence:

- Known raw meat, shellfish and fish item IDs go to the group's Cooking/Fishing
  character, even without a grocery target and before other recipients' grocery
  needs or explicit surplus recipient orders. Sender grocery/reserve quantities
  stay protected. The designated cook keeps their own ingredients instead of
  bouncing them elsewhere. Verified bank surplus is withdrawal guidance only.
  Classification is an explicit Classic item-ID list, not a name match or a
  blanket food/consumable rule. For an unlisted Forever ingredient, explicitly
  classify its ID using `/rq routing-item food <item ID> on`. This also opts that
  item into Cooking/Fishing priority; use `off` to remove your classification.
- Cloth to Tailoring; metal/stone trade goods to Blacksmithing.
- Unbound, non-busy uncommon BoE weapons/armor to Enchanting as **candidates**.
  Check upgrades, disenchantability and required skill yourself; there is no gear
  advisor.
- Light Feathers (item ID 17056) and surplus names starting exactly with `Scroll:`
  to the first enabled same-realm Mage. A Mage keeps their own surplus.
- Bag instances whose tooltip confirms they require unlocking to a same-realm
  Rogue. Lockpicking skill is not guaranteed; a Rogue keeps their own surplus.

Except for the Cooking/Fishing ingredient priority above, explicit needs and
configured item routes take priority over general surplus. The item ID remains
canonical even where a name prefix selects a routing rule. Stale/incomplete
profession evidence blocks general profession routing. Missing quest/lock/
binding/classification evidence is not guessed.

Configure optional item-ID categories and ordered recipients:

```text
/rq routing
/rq routing-item herbs 2447 on
/rq routing-priority herbs <member[,member...]>
/rq reserve potions <item ID> <quantity> [member]
/rq reserve bandages <item ID> <quantity> [member]
/rq reserves
/rq material-totals
```

Categories are herbs, leather, food, engineering and blacksmithing; they do not
infer membership from item names. Quantity 0 clears a reserve. Recipient lists
use actual members; `clear` removes a configured ordering.

### Explicit attachment clicks

At an open mailbox, **Attach item / Attach all** refresh and revalidate the
proposal, fill the full recipient and move the exact carried quantity, splitting
stacks when necessary. **They never click Send.** Outside a mailbox, or with
`/rq mail text`, the report is read-only.

Attachment requires known out-of-combat state, empty cursor, enough mail slots
and an unambiguous same-realm recipient. A different existing recipient,
anonymous attachments or duplicate draft items stop the helper. Unrelated
same-recipient attachments are preserved. Failures stop the batch, report partial
progress and attempt to return only the helper's own held item. No background
retry or follow-up mail is sent. Review realm/faction rules, quantities, subject
and recipient yourself.

### Shipments and inboxes

`/rq shipments` opens the roster-only ledger. Manually composed sends can be
observed, but only for uniquely identified same-realm members; COD sends and
non-roster recipients do not create usable shipment credit.

Default **observation mode** does not treat a captured success as certain
delivery. After verifying that send, **Confirm sent** or `/rq shipment <ID> sent`
confirms that specific observed success. Never confirm failures or cancellations.
Only after the client mail smoke test, `/rq mail-tracking verify` enables
automatic confirmation for the exact version/build/interface; `off` disables
it and a build change invalidates the opt-in.

Visit the recipient mailbox. Full loaded inbox/bag scans, unique matching,
manually observed takes and carried gains reconcile collection conservatively.
Ambiguous, stale, returned or interrupted evidence stays uncertain. Confirmed
pending and verified inbox stock may provisionally cover needs, but must be
collected before crafting; they are never donor stock.

New logins require active-character mailbox verification before cached mail is
credited. `/rq shipment <ID> close` stops credit without claiming collection.
`/rq shipment prune` removes only closed/failed/collected history. The ledger
is bounded to 500 records and reports when full. There is no remote inbox scan.

## Removed activity lists

Activity ledgers, monthly financial summaries, profession-high histories and
session checklists are no longer tracked. Their commands, runtime modules and
saved records are removed in schema 19. The latest timestamped wallet snapshot
is retained for each character; it is not income, profit or a lifetime high.

## Configuration transfer

`/rq export` opens a configuration string; `/rq import` opens paste/preview.
Review the replacement preview before using its explicit confirmation token with
`/rq import-confirm <token>`. `/rq import-cancel` cancels;
`/rq import-rollback` restores the previous configuration until logout/reload.

This replaces configuration, not a merge or a SavedVariables restore. Omitted
characters keep observations but become pending with default intent/empty supplies.
Snapshots, recipes, inventory, rested evidence and mail ledgers are
not imported. Rollback applies configuration against current observations and
also undoes subsequent configuration edits.

Use only a **fresh schema 19 post-upgrade export**. Old-schema exports require
re-export after upgrading the source installation, not manual string editing.
The transfer format has safety bounds (256 KiB, 200 characters) independent of
the unlimited dynamic roster; checksum validation detects corruption, not trust.

## Useful commands

| Command | Purpose |
| --- | --- |
| `/rq`, `/rq close`, `/rq reset-window` | Toggle, close or center the dashboard |
| `/rq roster [text]`, `/rq today [text]` | Roster or play-next view/text |
| `/rq settings`, `/rq planning` | Character controls or planning assumptions |
| `/rq register`, `/rq add`, `/rq ignore` | Explicit registration |
| `/rq main [character ID]`, `/rq role <role> [character ID]` | Main/role configuration |
| `/rq diag`, `/rq copy`, `/rq rescan` | Diagnostics, copy report, current snapshot |
| `/rq fullname <full name>` | Actual-name override |
| `/rq recipes [member]`, `/rq scan-recipes` | Observed recipes and open-window rescan |
| `/rq targets [member]`, `/rq supplies [member]` | Explicit orange goal picker and visual groceries |
| `/rq bags [query]`, `/rq find <query>` | Recorded inventory and source-aware item search |
| `/rq mail [text]`, `/rq shipments [text]` | Mail proposals and shipment evidence |

Roles are UNASSIGNED, TANK, HEALER, DPS, HEALER_DPS and FLEX. Removed slot,
gear, bag-space and progress commands are not supported.

## Development, validation and packaging

The runtime has no external dependencies. Direct game APIs belong behind
`RQ.Api`; planning/routing/estimation logic stays pure and Lua 5.1
compatible. Use the existing devcontainer toolchain: Lua 5.1, Luacheck, StyLua
and Python 3 standard-library packaging tests.

From the repository root, the intended checks are:

```sh
lua5.1 Tests/run.lua
luacheck Core Data Models Services UI Bootstrap.lua Tests
stylua --check Core Data Models Services UI Bootstrap.lua Tests
find Core Data Models Services UI Tests -name '*.lua' -exec luac5.1 -p {} \;
luac5.1 -p Bootstrap.lua
python3 -B -m unittest discover -s Tests -p 'test_package.py'
```

Automated validation covers 396 Lua tests and 4 package tests, plus lint,
formatting and Lua 5.1 syntax. Mock tests do not establish live Forever compatibility. The old guide
toolchain and guide tests are no longer part of development.

After validation, create a runtime-only archive with:

```sh
python3 -B Tools/package.py --output dist/RosterQuartermaster-0.0.38.zip
```

The archive should contain `RosterQuartermaster/` with the TOC, Bootstrap and
its runtime files, not Tests, Tools, repository metadata or development assets.
Verify TOC/namespace/tag agreement and the absence of retired feature assets.
`0.0.38` is packaged and passes automated validation; live-client acceptance
remains pending.

Earlier user reports covered the 0.0.1 install/reload/restart smoke test and basic
carried search, bank scanning and mail tracking in later builds. They are not
passes for this trade-group release, all API contracts, or extended failure cases.
The recorded interface target is 16001; verify the actual client build with
diagnostics and complete the acceptance checklist before release.
