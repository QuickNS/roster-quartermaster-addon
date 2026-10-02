# Roster Quartermaster

An account-wide roster coordinator for **World of Warcraft: Forever**.
The design is in [implementation-plan.md](implementation-plan.md).

## Current status

Version `0.0.2` implements **Milestone 1: database and snapshots**, not the MVP:

- Lua 5.1-compatible addon entry point and explicit TOC load order.
- Capability-checked API adapter with visible missing, restricted, and failed API diagnostics.
- Character GUID/name, realm/class/race, level, XP, rested XP, and resting-state probe.
- Transactional schema-1 to schema-2 migration and account-wide offline snapshots.
- Explicit add/link/ignore registration with a small combat-safe prompt and slash fallback.
- Five editable provisional roster slots; names never trigger automatic links.
- Money, location, bag-capacity, and profession observations when APIs expose them.
- Login/logout/rescan capture plus targeted, debounced XP, resting, zone, bag, and skill events.
- Per-section timestamps, incomplete-data warnings, and stale offline snapshot labels.
- Non-destructive rejection of malformed or unsupported-schema SavedVariables.
- Mocked boot, reload, persistence, and API failure tests.

**The 0.0.1 in-game smoke tests passed according to the user on 2026-10-02.**
The TOC targets interface `16001`, reported from Forever `1.60.1`, build `70170`
(Oct 1 2026). The report covers installation, diagnostics/rescan, `/reload`, and
full-restart persistence. Detailed API output and extended failure cases have
not been individually confirmed. **The new 0.0.2 migration, registration UI,
events, and APIs still require in-client testing.** See [beta API notes](docs/BETA_API_NOTES.md) and the
[manual test plan](docs/MANUAL_TEST_PLAN.md).

The roster dashboard, recommendations, offline rested estimates, checklists,
profession planning, item inventory scans, routing, and configuration import/export
are not implemented yet. Next is Milestone 2: the roster dashboard and richer
configuration controls. Profession skill capture is available, but recipe
discovery and profession planning are not.

## Installation for compatibility testing

1. In the running Forever client, obtain its interface/build information:

   ```text
   /run if GetBuildInfo then print(GetBuildInfo()) else print("GetBuildInfo unavailable") end
   ```

   The observed API output contains version, build, date, and interface number.
   The current recorded result is `1.60.1 70170 Oct 1 2026 16001`.

2. [RosterQuartermaster.toc](RosterQuartermaster.toc) already declares
   `## Interface: 16001`. If your client reports a different interface number,
   record the new build and update the header before testing. Do not substitute
   a guessed value. If the API is unavailable, use the client's
   documented build information before continuing; do not bypass compatibility
   restrictions. Record the observation in [BETA_API_NOTES.md](docs/BETA_API_NOTES.md).
3. Create `Interface/AddOns/RosterQuartermaster/` in the Forever client directory.
   Copy `RosterQuartermaster.toc`, `Bootstrap.lua`, and all of `Core/`, `Data/`,
   `Models/`, `Services/`, and `UI/` into it. **When upgrading from 0.0.1, copy the
   new directories too.** The TOC must be directly inside that directory, not
   in an extra nested folder.
4. Enable the addon and log in. Use `/rq diag`.
5. Follow the manual reload/restart tests. Back up existing SavedVariables before
   testing beta builds. There is no configuration export/import yet.

This addon provides information only. It does not craft, mail, purchase, select
characters, or automate combat.

### Upgrading and registering

Back up your account and per-character addon SavedVariables while the client is
closed before upgrading. Schema 1 migrates automatically to schema 2 on login;
keep the backup if you need to downgrade. Future or malformed schemas disable
writes without replacing the original data.

On an unknown character, choose **Add as new roster member**, **Link** to an
available provisional slot, or **Ignore**. You can **Decide later** to hide the
prompt for this login while keeping a pending snapshot. No popup opens in combat;
slash commands remain available. If the UI or combat-state API is unavailable,
use the chat instructions instead.

Example on your intended main:

```text
/rq slots
/rq link warrior
/rq roster
```

Slot IDs are `warrior`, `priest`, `druid`, `rogue`, and `shaman`. They describe
editable planning slots, not hard-coded actual characters. For example:

```text
/rq name druid Luna Tick
```

GUIDs survive character renames. When GUIDs are unavailable, a normalized actual
name-and-realm key is used and promoted to the GUID once available. Name-only
fallbacks cannot reliably reconcile renames; the addon does not guess.
Conflicting fallback/GUID records are preserved and reported rather than merged.

Ignored characters stop snapshot updates and are omitted from `/rq roster`.
Their existing configuration and slot link are retained. Use `/rq register` and
choose Add (or `/rq add`) to resume. Members already linked to one slot cannot
silently claim a different one; reassignment controls are deferred.

## Commands

| Command | Current behavior |
| --- | --- |
| `/rq` | Print diagnostics; the main dashboard is not implemented yet. |
| `/rq diag` | Print capabilities, registration, schemas, saved section timestamps and observed values. |
| `/rq rescan` | Refresh the current snapshot; unavailable fields retain their old values with incomplete markers. |
| `/rq roster` | List account characters, registration status, saved values, timestamps, and stale/incomplete warnings. |
| `/rq slots` | List provisional slot IDs, editable planned names, and existing links. |
| `/rq register` | Reopen registration, including for ignored characters. |
| `/rq add` | Add or re-enable the current character without guessing a slot. |
| `/rq link <slot>` | Explicitly link the current character to an available provisional slot. |
| `/rq ignore` | Stop tracking the current character until explicitly re-enabled. |
| `/rq name <slot> <planned name>` | Edit a provisional display name, preserving actual identity. |

Diagnostics contain your current character name, GUID, and realm. Review them
before sharing. They do not dump SavedVariables or inventory.

Never-observed data is displayed as `unavailable`, not as fabricated
level/XP/resting state. Failed refreshes retain prior values but mark the affected
section `INCOMPLETE`, preserving its last successful observation time. A snapshot
can be recent while an individual section is incomplete or stale. The default
staleness threshold is 48 hours. Offline rested XP is **last observed**, not a
current value or an offline estimate.

A successful `GetXPExhaustion` call returning `nil` is provisionally
interpreted as zero rested XP; this candidate API behavior needs client validation.
An unavailable or failing function returns unknown rested XP instead.

## Development and testing

There are no runtime dependencies. Development tools:

- Lua 5.1 (`lua5.1`, `luac5.1`).
- Luacheck (tested with 0.25.0).
- StyLua with Lua 5.1 support (tested with 2.5.2).

Run from this directory:

```sh
lua5.1 Tests/run.lua
luacheck Core Data Models Services UI Bootstrap.lua Tests
stylua --check Core Data Models Services UI Bootstrap.lua Tests
find Core Data Models Services UI Tests -name '*.lua' -exec luac5.1 -p {} \;
luac5.1 -p Bootstrap.lua
```

Apply formatting with `stylua Core Data Models Services UI Bootstrap.lua Tests`.
The dependency-free test runner loads the actual TOC order and fakes the game
environment; it does not establish compatibility with a live Forever client.
Do not run the fake test environment inside the game.

All direct game API access, event-frame creation, chat output, and slash-command
registration belong in [Core/Api.lua](Core/Api.lua). Database initialization
waits for this addon's `ADDON_LOADED` event or `PLAYER_LOGIN`.
See [DATA_MODEL.md](docs/DATA_MODEL.md) for schema and registration invariants.

### Development packaging

The interface number is recorded for the current test build. Stage all runtime
files, keeping the directory structure:

```text
RosterQuartermaster/
  RosterQuartermaster.toc
  Bootstrap.lua
  Core/
  Data/
  Models/
  Services/
  UI/
```

From the staging directory, run:

```sh
zip -r RosterQuartermaster-0.0.2.zip RosterQuartermaster
```

Do not ship tests, toolchains, repository metadata, or development configuration.
This is a development-test archive, not a validated release. Automated
validation/release workflows and the first MVP version `0.1.0` are scheduled
for later milestones.
