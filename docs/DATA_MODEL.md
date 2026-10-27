# SavedVariables schema 19

Schema 18 is used by **0.0.38**, adding saved minimap placement to the trade-group schema.
This document describes the retained
data contract; it is not evidence of a successful client migration.

## Account and per-character state

`RQDB` is account-wide. `RQCharDB` is the independent current-character mirror.
Both publish schema 19 only after successful validation.

| State | Purpose |
| --- | --- |
| `RQDB.settings` | Window position, rested assumptions, profession lag and logistics policy |
| `RQDB.settings.minimapAngle` | Account-wide minimap angle in degrees, finite and in `[0, 360)`, default 225 |
| `RQDB.roster[characterId]` | Actual member configuration: role/main/enabled and planning overrides |
| `RQDB.characters[characterId]` | Identity, registration and timestamped observations/configuration |
| `RQDB.policies` | Snapshot freshness policy (default 48 hours) |
| `RQDB.session` | Current/previous character and retained session context |
| `RQDB.mailTracking` | Roster shipment evidence and mail contract verification |

A character record retains identity, registration, snapshot, inventory, recipes,
rested state, supplies and profession intent. Current-character mirrors
are copied rather than aliased. Account records are authoritative on attachment;
configuration-only import must not substitute old observations for new ones.

There is no planned roster table, provisional slot, default composition or
character-count cap. Transfer serialization and UI pagination have separate
bounds, not limits on roster membership.

## Identity and registration

Character GUIDs are canonical. Actual name/realm fallback IDs can be promoted
when a GUID is observed; conflicts preserve the original records and report an
error instead of guessing a merge. Display/full names can change independently.
Unmodified first name/surname observations remain distinct from realm evidence.

Identity may also contain `faction` (`Alliance`, `Horde`, or `Neutral`),
`ruleset` (`PVE` or `PVP`), and `rulesetSource` (`realm-name` or `manual`).
Missing fields remain unknown. Faction is native observation; ruleset uses an
explicit realm-name token or a user-confirmed fallback. A realm change clears
the old ruleset before new observations are applied. Native observations
override manual ruleset values. Ordinary unavailable reads retain last known
identity values; neutral observations explicitly block trading.

`Character.TradeGroup` returns one of four `ruleset:faction` keys only for known
Alliance/Horde identities. `Character.CanTrade` additionally requires a known,
normalized matching realm. All transfer-producing planners, address resolution,
attachment eligibility, pending-mail coverage and profession-provider coverage
use this shared predicate. Local stock and local bag upgrades remain usable
without knowing a trade group. Account-wide inventory display is not a transfer.
Main is exclusive within each realm/ruleset/faction key; no pin remains.

Registration states:

- `pending`: identity observed, no explicit membership decision.
- `member`: explicitly added/resumed; roster configuration exists.
- `ignored`: explicitly excluded from tracking without deleting saved history.

Disabled registered members remain available for inspection/search but
are excluded from automatic play recommendations and mail recipients. Pending
and ignored records do not count as providers. Main/role choices refer directly
to actual character IDs; ignoring or moving a Main to another group clears that designation.

Per-member retained planning includes `restedMultiplier`, `restedRevision`,
`resourceBlocker` and **`dungeonReady`**. The latter is only a manual ranking
signal. It is not a dungeon, quest, clear, drop or Legacy record.

## Capture and freshness

`snapshot.sections` separates progression, rested, location, money, bag capacity
and professions. Sections carry `complete`, `attemptedAt` and the last successful
`observedAt`. `lastSeen` does not override source-specific timestamps.

Missing values do not erase valid old values. A failed/partial read marks that
section incomplete while retaining the last observation. Never-observed values
are unknown, not zero. Source timestamp regressions produce stale/clock warnings.
Observed logout times and resting/location evidence are separate from general
snapshot recency.

Item IDs and profession skill-line IDs are numeric canonical keys. Names/icons
are optional display metadata and do not add inventory or identify recipes by
guesswork. Item metadata arrival may refresh a view but cannot create stock.

## Rested and planning state

`restedState` retains a logout baseline, bounded learned-rate samples and the
latest login comparison. Estimates require a complete timestamped baseline.
Cached earlier evidence used at logout is explicitly lower confidence and
cannot train a rate. Teardown failures preserve complete observations instead
of replacing them with zero XP maxima or empty profession/bag data.

Rates, cap, near-cap threshold and level cap are account-wide assumptions.
Changing relevant mechanics clears calibration without destroying valid baselines.
`roster[guid].isMain` is exclusive within each realm/ruleset/faction combination.
The ranking compares group, level, Main on equal levels, then other priority
signals and GUID. Schema 19 removes pinnedCharacterId, mainLeadLevels,
leadStartLevel, maxAltLag and their weights. No pin or main-lead tier remains.

## Native professions, supplies and goals

Profession observations contain skill-line ID, name, primary/secondary kind,
skill and trained maximum, with section-level completeness and time.
Recipe snapshots retain owned per-profession observations, learned status,
difficulty, reagents, skill-up/output information and acquisition evidence when
available. Unsupported/partial scans do not replace good data with empty lists.

`record.supplies` retains:

- `needs[itemId]`: explicit minimum stock targets.
- `goals[professionId]`: selected observed recipe and target skill.
- `reserves.potions` and `reserves.bandages`: separate item-ID stock floors.

Supplies are independently mirrored for the active character.
Automatic one-craft orange groceries are **derived**, not saved as manual needs:
eligible learned orange recipes require complete reagents, positive skill-ups and
observed skill below cap. A goal replaces the same recipe's automatic allowance;
other eligible recipe allowances remain. Shared materials sum, then overlapping
manual floors use a maximum. Stale provenance remains visible.

The orange picker and explicit goals are retained native-recipe workflows, not
guide steps or a next-20 plan. No guide catalog, source approval, guide compiler
or guide-based plan is part of schema 16's active contract.

### Profession intent and advice

`professionIntent` stores focus, preferences/exclusions and optional intended
primary choices separately from learned professions. It never counts as a
trained skill or provider. Learned choices cannot be removed by exclusions.
Advice uses confirmed free slots and same-realm member coverage; unknown scans
do not become empty professions.

`settings.professionLag` controls the `min(5 * level, ceiling)` benchmark,
secondary opt-ins and optional primary-deficit ranking. Default ranking is off;
the default ceiling 300 is an assumption, not a confirmed universal client rule.
Explicit goal targets remain independent of this benchmark.

## Inventory, personal bank and bag plans

`inventory.bags`, `.bank` and `.mail` each retain source time, completeness and
item counts/evidence. Counts from distinct sources must not be silently summed
when coherence is unproven. Bound/reserved items remain searchable even when
not transferable. Search does not mutate stock.

Bag observations include equipped regular-bag capacity and item/output evidence
needed by bag planning. Ready upgrades use carried bags only. Cross-character
crafting needs observed transferable output, complete reagents and supported
capacity/quantity. Preliminary crafts expand only known learned conversions.
Plans are derived and do not persist delivery promises.

Personal-bank snapshots require paired coherent bag/bank scans while the bank
is accessible. Incomplete/interrupted transfers cannot credit duplicate stock.
Older bank counts without coherence remain unconfirmed discovery evidence.
Verified owner stock covers materials with a withdrawal prerequisite; bank
transfer proposals do not credit recipients before withdrawal and a new proposal.

Per-instance locked-container tooltip evidence is used for Rogue routing and
exact attachment selection. It is not the container API's temporary busy flag.
Missing tooltip/localization evidence is unknown; neither opening skill nor
future unlocking success is inferred.

## Mail evidence

The account mail ledger is bounded to 500 shipment records, with explicit failure
when full. Eligible entries identify unique same-realm sender/recipient GUIDs,
item quantities, attempt/success/confirmation evidence and timestamps.
COD/non-roster sends cannot create spendable recipient credit.

Observed success is uncertain by default. User confirmation or exact-build
verification can establish provisional pending coverage, not delivery/collection.
Build changes invalidate automatic confirmation opt-in.

Full inbox/bag coherence and unique reconciliation prevent duplicate pending/
inbox coverage. Manual take evidence plus attachment removal/carried gains can
confirm partial/full collection. Interrupted, stale, returned or ambiguous mail
remains uncertain. Cached active-character mail needs verification on a new login.
Pending/inbox stock is neither craft-ready nor donor stock.

Closing a shipment stops credit without claiming collection. Pruning removes
closed/failed/collected history only. Draft attachments are not inventory credit.
No configuration export includes shipment or inbox observations.

## Retired activity state

Schema 19 removes `record.activity` (including the current-character mirror) and
`RQDB.checklists`. It preserves `snapshot.money` and its observation timestamp,
inventory, recipes, groceries, profession intent, mail and rested evidence.
There are no activity counters, monthly ledgers or generated session lists.

## Logistics configuration

`settings.logistics.categories` holds explicit item-ID sets and ordered unique
recipient GUIDs for herbs, leather, food, engineering and blacksmithing.
No category membership is inferred from item names. Retained sender stock floors
and trade eligibility checks precede transfers.

`settings.logistics.cooks[groupKey] = characterGUID` stores at most one
Cooking/Fishing assignee per combination. Selection replaces only that key.
The assignee must currently be registered, enabled and in that group to be used;
stored assignments become dormant if those conditions cease to hold. There is
no requirement to have already learned the professions. Config imports reject
dangling exported GUID references; runtime use also requires a matching realm.

`Data/CookingItems.lua` is a canonical ID allowlist of raw meat/shellfish/fish.
Explicitly classified `food` IDs also opt in. Unknown IDs, arbitrary name matches,
prepared food and unrelated consumables are not inferred to be raw ingredients.
Eligible carried surplus goes to the cook after sender reserves/local bag
upgrades/priority bag materials, but before other recipients' groceries and
surplus routes. Verified bank surplus produces withdrawal prerequisites only.

## Configuration transfer

The transfer format version and SavedVariables schema are distinct. Current
exports require schema 19-compatible configuration. **Old-schema exports must
be replaced with a fresh post-upgrade export**, not imported or hand-edited.

Exports contain retained settings, policies, actual registration/roster choices,
supplies/intent. They exclude snapshots,
recipes, inventories, rested evidence and mail history.

Import is replacement after strict validation, preview and explicit confirmation.
The minimap angle is included. Import/rollback refresh its native position only
while the button remains anchored to the minimap, never when a drawer owns it.
Omitted character records retain observations but become pending with empty
supplies/default intent. Rollback restores configuration against current
observations, including undoing later configuration edits. Preview and rollback
exist only until reload/logout.

Bounds include 256 KiB and 200 characters; they constrain transfer documents,
not the number of registered roster members. Adler-32 detects corruption, not
authenticity. Character references are exact IDs, not guessed name matches.

## Migration and recovery

Schema 16's removal migration is idempotent and operates on copies of both roots.
It removes retired data only:

- `plannedRoster` and retired roster-entry `plannedName`, `claimedBy`, `slotId`.
- `settings.gear`, including retired per-character advisor profiles.
- `progress`, the retired dungeon/Legacy ledger.

Retain registered characters, registration status, roles, main choice, enabled/
planning flags (including `dungeonReady`), retained settings, snapshots, supplies/
goals/reserves, recipes, inventory, rested state and intent
and mail tracking. Do not infer that removing a slot removes its linked actual
character. Removed ephemeral highlights/arrows require no replacement ledger.

Schema 17 initializes missing `settings.logistics.cooks` to an empty map.
It validates optional trade identity fields without inventing faction/ruleset
for old records. Character data, needs, recipes and all retained observations
remain unchanged. Repeating migration preserves assignments and observations.

Schema 18 initializes a missing `settings.minimapAngle` to 225, preserving an
existing valid angle. Invalid angles reject both roots without mutation. The
position is committed after dragging ends (including hide, combat entry or
logout); no frame-coordinate or drawer-layout data is stored.

Supported older roots proceed through normalization to schema 19. Validation of
both copies must complete before either original is replaced; unsupported future
schemas or malformed retained fields disable writes and preserve originals.
Successful in-memory initialization does not prove client disk persistence.

Back up account and per-character SavedVariables with the client closed before
upgrading. Retain the backup: old versions do not understand schema 19, and
configuration exports omit observations. Downgrade only with the matching old
addon and backup. Never reset SavedVariables to hide a migration error.
Validate migration/reload/restart with [MANUAL_TEST_PLAN.md](MANUAL_TEST_PLAN.md)
before considering this release accepted.
