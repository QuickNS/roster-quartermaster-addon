# SavedVariables schema 2

`RQDB` is account-wide; `RQCharDB` is per-character. Both declare
`schemaVersion = 2`. Initialization happens after SavedVariables load.

## Account state

| Field | Purpose |
| --- | --- |
| `settings` | Existing settings and user extensions are preserved. |
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
Item inventory and recipes remain unknown until their later scanning milestones.

## Per-character state

`RQCharDB` contains `characterId` plus independent copies of the current record's
`identity`, `snapshot`, `inventory`, and `recipes`. There are no shared mutable
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
  its slot/configuration links are rekeyed together.
- Existing GUID and fallback records are not silently merged: capture is
  suspended and the conflict is reported. Restore a known-good backup or resolve
  the saved-data conflict with explicit user approval.
- Provisional names are never used for matching. A new snapshot starts pending;
  only a user action makes it a roster member or links a slot.
- Ignore stops snapshot updates and excludes the record from roster output.
  Existing member configuration and links are retained for explicit re-enabling.

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
`lastLogout` is set on synchronous logout capture. Pending timer callbacks are
invalidated on rescan, registration changes, and logout.

The whole-snapshot freshness label is `UNKNOWN` without usable timestamps,
`CLOCK MISMATCH` for future timestamps, `STALE` at or beyond the configured
threshold, or `RECENT`. Section completeness and timestamps must also be checked;
a money update does not make old profession or bag data current.

## Migration and corruption handling

`Migrations.Prepare` copies both roots, accepts schema 1 or 2 (or missing version
on a partial database), fills absent containers, seeds absent provisional
configuration, validates shapes/values/link consistency, and stamps schema 2.
It is idempotent and preserves unknown fields and non-nil user configuration.
It does not fabricate an observation timestamp for schema-1 snapshots.

Only after both prepared roots pass validation does `Database.Initialize`
publish them. Unsupported schemas and invalid consumed fields disable all
persistence with explicit diagnostics; neither original root is overwritten.
Back up both SavedVariables files before upgrading. Schema 1 code cannot read
schema 2, so downgrade by restoring that backup, not by changing version numbers.
