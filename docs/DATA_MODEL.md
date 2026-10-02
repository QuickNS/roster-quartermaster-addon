# SavedVariables schema 5

`RQDB` is account-wide; `RQCharDB` is per-character. Both declare
`schemaVersion = 5`. Initialization happens after SavedVariables load.

## Account state

| Field | Purpose |
| --- | --- |
| `settings` | Existing settings and user extensions are preserved. |
| `settings.window` | Native window anchor: `point`, `relativePoint`, finite signed `x`/`y` offsets. |
| `settings.planning` | Rates, cap, level rules, milestones, weights, optional pinned character ID. |
| `session` | Current and previous character IDs; same-character reload does not rotate history. |
| `policies.staleSnapshotHours` | Non-negative threshold, default 48 hours. |
| `plannedRoster[slotId]` | Editable planning configuration, seeded once from `Data/DefaultRoster.lua`. |
| `roster[characterId]` | Confirmed member configuration plus observed identity fields. |
| `characters[characterId]` | Snapshot record for a pending, member, or ignored character. |

Slot IDs (`warrior`, `priest`, `druid`, `rogue`, `shaman`) are configuration keys,
not actual identities. A linked slot contains `claimedBy = characterId`; the
member entry has the reciprocal `slotId`. Migration rejects inconsistent links.
Deleted slots or an explicitly empty slot table are not recreated on reload.

A character record contains:

```lua
{
    registration = "pending", -- or "member", "ignored"
    identity = { guid = "...", displayName = "...", realm = "...", class = "...", race = "..." },
    snapshot = {
        level = 25, xp = 12000, xpMax = 40000, restedXp = 20000,
        money = 12345, zone = "...", subZone = "...", wasResting = false,
        bagSlots = 32, freeBagSlots = 10,
        lastSeen = 123456789, lastLogout = 123456000,
        professions = {
            [186] = { name = "Mining", skill = 100, maxSkill = 150 },
        },
        sections = {
            progression = { complete = true, observedAt = 123456789, attemptedAt = 123456789 },
            -- rested, location, money, bags, professions use the same metadata.
        },
    },
    inventory = {
        bags = { scannedAt = 0, complete = false, items = {} },
        bank = { scannedAt = 0, complete = false, items = {} },
        mail = { scannedAt = 0, complete = false, items = {} },
    },
    recipes = { scannedAt = 0, complete = false, items = {} },
}
```

These are example values, not initialization defaults. Unknown scalar values are
absent. Planned profession IDs are intentions, not learned profession snapshots.
Bag items and opened profession recipes are observed in schema 5, as described below.
Bank and mail inventories remain unknown; absent data is not zero stock.

## Per-character state

`RQCharDB` contains `characterId` plus independent copies of the current record's
`identity`, `snapshot`, `inventory`, `recipes`, `restedState`, and `supplies`. There are no shared mutable
snapshot tables between the two SavedVariables roots. Unknown extension fields
from the previous schema are preserved.

On login, an existing account record is authoritative. If it does not exist,
matching per-character legacy identity/snapshot data is imported before the
first capture. Other characters' account records are never replaced with the
current character's snapshot.

## Identity and registration

- A GUID is canonical whenever present.
- The fallback is `name:<normalized actual name>-<normalized realm>`; name is
  trimmed/lowercased and realm whitespace is removed before lowercasing.
- A temporarily missing GUID may reuse the prior GUID only when actual name and
  realm still match. Missing all current identity evidence suspends capture.
- When a GUID becomes available, the matching actual-name fallback record and
  its slot/configuration links, pin, and session references are rekeyed together.
- Existing GUID and fallback records are not silently merged: capture is
  suspended and the conflict is reported. Restore a known-good backup or resolve
  the saved-data conflict with explicit user approval.
- Provisional names are never used for matching. A new snapshot starts pending;
  only a user action makes it a roster member or links a slot.
- Ignore stops snapshot updates and excludes the record from text roster output.
  The dashboard keeps an ignored card for explicit re-enabling. Existing role
  configuration and links are retained, but the main designation and pin are cleared.
- Main selection clears other member and provisional-main flags. Linking another
  character never overrides an existing explicitly selected main.
- Role changes update the member and its linked provisional slot. Offline
  configuration uses the stored character ID and never captures active APIs into
  that character's snapshot.
- Unlink releases the slot but preserves the member, role, main choice, and
  snapshot. Reassigning requires this explicit unlink before linking elsewhere.

Fallback-only renames cannot be reconciled safely without additional identity
evidence. GUID rename behavior is covered by tests.

## Capture and freshness

`SnapshotService` collects through `RQ.Api`; `Snapshot.Apply` merges a single
section. Valid returned fields update. Missing values retain earlier observations
and mark the entire section incomplete. A section's `observedAt` advances only
when every expected field was obtained; `attemptedAt` tracks the attempt.
If the clock fails, new observations do not inherit an apparently fresh section
timestamp. Partial section values must not be presented as uniformly current.

`lastSeen` advances at successful capture checkpoints when the clock is available.
`lastLogout` is set on synchronous logout capture. If logout progression is unavailable
or has a zero XP maximum, the remaining API scan is skipped and prior values and
observation timestamps are preserved; only the logout timestamp advances.
Pending timer callbacks are
invalidated on rescan, registration changes, and logout.

The whole-snapshot freshness label is `UNKNOWN` without usable timestamps,
`CLOCK MISMATCH` for future timestamps, `STALE` at or beyond the configured
threshold, or `RECENT`. Section completeness and timestamps must also be checked;
a money update does not make old profession or bag data current.

## Migration and corruption handling

`Migrations.Prepare` copies both roots, accepts schemas 1 through 5 (or missing version
on a partial database), fills absent containers, seeds absent provisional
configuration, validates shapes/values/link consistency, and stamps schema 5.
It is idempotent and preserves unknown fields and non-nil user configuration.
It does not fabricate an observation timestamp for schema-1 snapshots.

Only after both prepared roots pass validation does `Database.Initialize`
publish them. Unsupported schemas and invalid consumed fields disable all
persistence with explicit diagnostics; neither original root is overwritten.
Back up both SavedVariables files before upgrading. Schema 1 code cannot read
newer schemas, so downgrade by restoring that backup, not by changing version numbers.

Schema 3 adds a validated `settings.window` position, defaulting to a centered
anchor with zero offsets. Migration preserves already valid positions and repairs
missing position fields; malformed coordinates or anchors disable writes instead
of resetting user data. Older roster entries missing only their account snapshot
receive a record with unknown observations so they remain visible/configurable;
no level, timestamp, or inventory amount is invented.

The native window clamps itself to the screen when restored. UI frame references,
selected tabs/rows, drafts, minimap widgets, and refresh callbacks are runtime-only;
they are never written to SavedVariables. The minimap launcher has a fixed
lower-left anchor and adds no persistence fields.

## Planning and rested state (schema 4)

`settings.planning` defaults come from `Data/DefaultPolicies.lua`. Rates are **levels
per hour**, `capLevels` is levels of XP, and `nearCapRatio` is a fraction of that cap.
The Planning UI displays these as percentages. Numeric settings, positive ascending
milestone arrays, bounded finite signed weights, and optional pin IDs are validated.
Unknown extension fields remain preserved. Initial mechanics are unverified.

Members have `restedMultiplier = 1`, `restedRevision = 0`, `resourceBlocker = false`,
and `dungeonReady = false`. The multiplier affects accumulation rate, not the
global cap. The boolean signals are manually configured, not observed quest or
inventory state. Resetting calibration increments the revision and clears both
learned samples and the old baseline.

Each character has:

```lua
restedState = {
    calibration = { profile = "", inside = {}, outside = {} },
    -- Optional logout: at, level, xp, xpMax, restedXp, wasResting,
    --                  multiplier, revision, profile, cached, observedAt
    -- Optional logoutReason: explanation when no baseline can be built
    -- Optional comparison: at, accepted, reason, estimated, actual, error, observedRate
}
```

A profile identifies global rates/cap/maximum level and member multiplier/revision.
Only eight numeric samples per location and the latest comparison are retained.
Calibration records **base** rates; the member multiplier is applied when estimating.
Profile changes reset learned rates. Changed global mechanics retain the observed
baseline for estimates but reject learning across that change.

Normally, complete progression/rested/location sections observed at the exact logout
timestamp create a baseline. Since 0.0.6, unavailable/zero-maximum logout progression
triggers a cached fallback using complete earlier sections. `at` remains the logout
time; `observedAt` is the oldest required section's actual timestamp, and `cached`
marks the added uncertainty. Cached baselines are always LOW confidence and cannot
train rates. Section timestamps are not relabelled as fresh. Missing, incomplete,
or future-dated required evidence still prevents baseline creation; `logoutReason`
preserves the explanation. A missing logout clock never reuses an old baseline.
These optional fields are backward-compatible within schema 4.

Pre-schema-4 snapshots can seed a baseline only from exact logout observations
with `lastSeen == lastLogout`; schema 4 never recreates a consumed baseline during
migration, and migration does not invent a cached fallback.

The first successful identity reconciliation of a login starts session history and
consumes the baseline, comparing newly captured rested XP when available. Learning
requires an interval of at least 300 seconds, unchanged level/XP/XPMax, complete
login observations, unchanged profile, positive gain and no configured cap censoring.
Ignored logins discard the baseline without capture. Rescans do not recalibrate.
The next synchronous logout establishes the next baseline. Crashes may leave no
usable logout evidence; the result is unknown, not invented offline accumulation.

`PriorityEngine.Evaluate(account, records, settings, context)` is pure and uses the
repository's dot-call convention. Explicit context supplies time, active ID and live
API values; the engine does not fetch time or call game APIs. It returns ordered
recommendations (ID, score, tier, confidence, two/three reasons, estimate), an error
slot, estimates keyed by ID, and global warnings. Tiers precede score, then stable
character ID breaks ties. The planning service supplies API context, text output,
and persistence orchestration; the Today panel only builds a view model.

## Full names and supplies (schema 5)

`identity.displayName` prefers the unmodified name returned by the client.
`identity.fullName` is an optional explicit user override. Display/recipient
selection uses the override first, but GUID identity is never rekeyed by a display
edit. A name API's realm return is not concatenated as a surname. Fallback IDs use
the actual API name, not planned labels; unavailable unmodified names cannot
establish a surname, so `/rq fullname` and reportable API evidence remain available.

`inventory.bags.items[itemId] = count` stores bag totals. `tradable[itemId]` counts
only explicitly unbound, unlocked stacks. `details[itemId]` optionally stores name,
class and subclass IDs; `equipped[bagIndex]` stores regular equipped bag sizes.
Empty/malformed/failed scans retain old counts, mark the source incomplete and
save `error`; incomplete sources cannot supply mail allocations. Bank/mail are
untouched. Bag counts are not scanned during final logout teardown.

`recipes.professions[professionId]` holds `{name, complete, scannedAt, recipes}`.
Each recipe ID maps to `{name, learned, reagents, reagentsComplete, skillUps,
source?, sourceItem?}`. `reagents[itemId]` contains per-craft quantities. Required
slots with alternative reagent choices are explicitly incomplete rather than
choosing a quality/currency/item arbitrarily. A learning-item mapping requires one
unique acquisition-linked item identified as a recipe by the item API; currencies
and ambiguous alternatives are not selected. Opening one profession never marks all professions known;
the outer `recipes.complete` remains false. No shared/guild catalog is recorded as
the player's learned list.

`supplies.needs[itemId]` is a configured minimum stock target.
`supplies.goals[professionId] = {recipeId, targetSkill}` is the selected recipe for
a skill goal. Estimated crafts are `ceil(max(0, targetSkill - observedSkill) /
skillUps)`. Reagent requirements sum across goals, then combine with manual stock
targets by maximum, not addition. This is an estimate: skill-ups can fail. No
optimal Forever guide or acquisition location is invented.

Groceries and mail proposals are computed, not persisted. Bag stock subtracts from
targets; stale/incomplete evidence stays visible. Sender reserves and each proposal
decrease the available allocation pool, with stable destination and item-ID order.
Mail/in-transit inventory is unknown and not credited. Proposals do not execute any
protected action or edit the client mail form. Manual review remains required.
