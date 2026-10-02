# Roster Quartermaster

An account-wide roster coordinator for **World of Warcraft: Forever**.
The design is in [implementation-plan.md](implementation-plan.md).

## Current status

Version `0.0.1` implements the **Milestone 0 compatibility spike**, not the MVP:

- Lua 5.1-compatible addon entry point and explicit TOC load order.
- Capability-checked API adapter with visible missing, restricted, and failed API diagnostics.
- Character GUID/name, realm/class/race, level, XP, rested XP, and resting-state probe.
- Basic account-wide and per-character SavedVariables initialization.
- Probe snapshots on login, logout, and explicit rescan.
- Non-destructive rejection of malformed or unsupported-schema SavedVariables.
- Mocked boot, reload, persistence, and API failure tests.

**Forever compatibility is not yet verified in-game.** The interface number is
deliberately not guessed. Native persistence across `/reload` and a full client
restart still needs testing. See [beta API notes](docs/BETA_API_NOTES.md) and the
[manual test plan](docs/MANUAL_TEST_PLAN.md).

The roster dashboard, roster linking, migrations, recommendations, offline
rested estimates, checklists, professions, routing, and configuration import/export
are not implemented yet. The next milestone is database migrations and the
account-wide snapshot/registration service. Character names are not hard-coded
into the probe.

## Installation for compatibility testing

1. In the running Forever client, obtain its interface/build information:

   ```text
   /run if GetBuildInfo then print(GetBuildInfo()) else print("GetBuildInfo unavailable") end
   ```

   The candidate WoW API returns version, build, date, and interface number.
   Confirm that return shape in this client; do not substitute a guessed number.

2. Add `## Interface: <observed interface number>` to
   [RosterQuartermaster.toc](RosterQuartermaster.toc), replacing the placeholder
   with the actual numeric value. If the API is unavailable, use the client's
   documented build information before continuing; do not bypass compatibility
   restrictions. Record the observation in [BETA_API_NOTES.md](docs/BETA_API_NOTES.md).
3. Create `Interface/AddOns/RosterQuartermaster/` in the Forever client directory.
   Copy `RosterQuartermaster.toc`, `Bootstrap.lua`, and `Core/` into it. The TOC
   must be directly inside that directory, not in an extra nested folder.
4. Enable the addon and log in. Use `/rq diag`.
5. Follow the manual reload/restart tests. Back up existing SavedVariables before
   testing beta builds. There is no configuration export/import yet.

This addon provides information only. It does not craft, mail, purchase, select
characters, or automate combat.

## Commands

| Command | Current behavior |
| --- | --- |
| `/rq` | Print compatibility diagnostics; no window yet. |
| `/rq diag` | Print client/build, API availability, character state, database status, and saved timestamp. |
| `/rq rescan` | Save a new compatibility snapshot, or explain why persistence is disabled. |

Diagnostics contain your current character name, GUID, and realm. Review them
before sharing. They do not dump SavedVariables or inventory.

Missing data is displayed as `unavailable`, not as fabricated level/XP/resting
state. A successful `GetXPExhaustion` call returning `nil` is provisionally
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
luacheck Core Bootstrap.lua Tests
stylua --check Core Bootstrap.lua Tests
find Core Tests -name '*.lua' -exec luac5.1 -p {} \;
luac5.1 -p Bootstrap.lua
```

Apply formatting with `stylua Core Bootstrap.lua Tests`.
The dependency-free test runner loads the actual TOC order and fakes the game
environment; it does not establish compatibility with a live Forever client.
Do not run the fake test environment inside the game.

All direct game API access, event-frame creation, chat output, and slash-command
registration belong in [Core/Api.lua](Core/Api.lua). Database initialization
waits for this addon's `ADDON_LOADED` event or `PLAYER_LOGIN`.

### Development packaging

Only package after recording the actual interface number. Stage these files:

```text
RosterQuartermaster/
  RosterQuartermaster.toc
  Bootstrap.lua
  Core/
    Namespace.lua
    Api.lua
    Database.lua
    Diagnostics.lua
```

From the staging directory, run:

```sh
zip -r RosterQuartermaster-0.0.1.zip RosterQuartermaster
```

Do not ship tests, toolchains, repository metadata, or development configuration.
This is a compatibility-test archive, not a validated release. Automated
validation/release workflows and the first MVP version `0.1.0` are scheduled
for later milestones.
