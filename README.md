# Roster Quartermaster

An account-wide roster coordinator for **World of Warcraft: Forever**.
The design is in [implementation-plan.md](implementation-plan.md).

## Current status

Version `0.0.5` implements **Milestone 3: rested estimation and priority**, not the MVP:

- Lua 5.1-compatible addon entry point and explicit TOC load order.
- Capability-checked API adapter with visible missing, restricted, and failed API diagnostics.
- Character GUID/name, realm/class/race, level, XP, rested XP, and resting-state probe.
- Transactional migrations from schemas 1/2/3 to schema 4 and account-wide offline snapshots.
- Native minimap button with tooltip to open/close the roster dashboard.
- Movable, scrollable window with saved position and Today/Roster/Settings/Planning tabs.
- Offline rested estimates, configurable assumptions, bounded login calibration and manual perk reset.
- Deterministic play-next recommendations with reasons, confidence, and pin/unpin overrides.
- Character cards with identity, planned name, role/main, progression, professions, location, and freshness.
- Main/role configuration, explicit unlink/relink, and offline-member controls.
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
not been individually confirmed. **The dashboard, minimap button, schema-4 upgrade,
rested planning, and extended APIs still require in-client testing.** See [beta API notes](docs/BETA_API_NOTES.md) and the
[manual test plan](docs/MANUAL_TEST_PLAN.md).

Checklists, profession/material planning, item inventory scans, routing, and
configuration import/export are not implemented yet. Next is Milestone 4: daily
checklists. Profession skill capture is available, but targets and session
objectives are explicitly shown as not configured until their planning milestones.

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
4. Enable the addon and log in. Click the **RQ minimap button** or use `/rq`
   to open the dashboard. Use `/rq diag` for diagnostics.
5. Follow the manual reload/restart tests. Back up existing SavedVariables before
   testing beta builds. There is no configuration export/import yet.

This addon provides information only. It does not craft, mail, purchase, select
characters, or automate combat.

### Troubleshooting a stuck registration command

If `/rq link warrior` stays in the chat input and reports
`RegistrationPrompt (a nil value)`, the registration UI module did not load.
Check that the installed addon includes `UI/RegistrationPrompt.lua` and that the
installed TOC contains that path before `Bootstrap.lua`. Copy the complete
updated addon, not just individual changed files, then run `/reload`.
If the file and TOC entry are both present, enable `/console scriptErrors 1` and
check for an earlier load error.

Version 0.0.3 makes add/link/ignore independent of that UI module and reports
its absence in chat and `/rq diag`. It does not reset your saved data. Reinstalling
the missing module is still necessary to restore the registration window.

### Upgrading and registering

Back up your account and per-character addon SavedVariables while the client is
closed before upgrading. Schemas 1, 2 and 3 migrate automatically to schema 4 on login;
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

Ignored characters stop snapshot updates and are omitted from `/rq roster text`.
They remain visible as ignored in the dashboard so you can resume them without
editing Lua tables. Existing role configuration and links are retained; ignoring
the main clears that main designation, and ignoring a pinned character clears its pin.
Use Add / resume in Settings, `/rq register`,
or `/rq add` to resume.

### Using the dashboard

- Click the **RQ** button at the lower-left edge of the stock minimap to toggle
  the window. It has a hover tooltip and uses no external library. Its minimap
  position is currently fixed.
- `/rq` also toggles the window (initially Today); `/rq today`, `/rq roster`,
  `/rq settings`, and `/rq planning` open a specific
  tab. **`/rq` no longer prints diagnostics; use `/rq diag` for that.**
- Drag the window background/title to move it. The position is saved account-wide.
  **Center** or `/rq reset-window` restores the default position.
- Scroll the Roster tab with the mouse wheel or scrollbar. Cards show offline
  snapshots as last observed, including incomplete/stale warnings. Rested XP is
  separately labelled observed live, estimated offline, or unknown.
- Click **Configure** on a character, or choose a character with Previous/Next
  in Settings. The selector includes pending and ignored characters.
- Use Add / resume, Ignore, Make main, and the role-cycle button to configure
  that character. There is at most one newly selected main; later links do not
  override that explicit choice.
- Select a provisional slot separately, edit its planned name and press Enter
  or Save name, then explicitly link it. Occupied slots cannot be overwritten.
  To move a linked character to another slot, **Unlink slot** first.
- Offline configuration changes do not scan, log into, or select that character
  in the client. **Rescan current** always scans the logged-in character.
- Close with **Close**, Escape (when native Escape registration is available),
  `/rq`, or `/rq close`. Entering combat hides the dashboard; it does not reopen
  automatically afterward. A minimap click during combat shows text guidance.
- If the stock minimap or native window APIs are unavailable, use `/rq roster text`
  and the configuration slash commands. Diagnostics report the missing capability.

Hidden dashboards are not rebuilt on snapshot events. Visible updates are
coalesced, and a focused planned-name draft is not overwritten by live updates.

### Rested planning and Today

Today shows the top recommendation and the rest of the ranked roster. Only enabled,
registered members participate. Each recommendation has two or three reasons and
a confidence label. Pin next/Unpin override automatic rotation; pins persist across
reloads and character switches. `/rq pin warrior` resolves a linked slot; actual
names, actual `Name-Realm`, unique planned names, and exact IDs also work. Ambiguous
names are rejected with matching IDs, never guessed.

Hard priority order is **pin, near rested cap, main needing lead, manual blocker,
then weighted rotation**. The default five-level main lead begins only after every
enabled member has reached level 25 and has a known level. At the configured level
cap, XP/lead priorities stop. The engine also considers alt lag, approaching
level/profession milestones, manual dungeon readiness, previous-character session,
and stale observations. Stale levels used from another member lower confidence;
stale profession sections do not award milestone credit.

Planning exposes eight global assumptions and a selected-member rate multiplier,
calibration reset, manual resource-blocker/dungeon-ready toggles, and pin control.
The initial values are **unverified assumptions**, not Forever facts:

- Inn rate: **0.625% of a level/hour**; outside rate: **0.15625%/hour**.
- Cap: **150% of a level**; near-cap threshold: **90% of that cap**.
- Main lead: **5 levels**, starting after everyone reaches **25**.
- Alt catch-up distance: **10 levels**; configured maximum level: **60**.

Offline estimates require a complete, timestamped logout observation. Missing
evidence stays unknown rather than projecting from a possibly mid-session cache.
Logout in an inn and switch to another character to see the estimate. Active
rested XP comes directly from the game API; it never falls back to cached data.
Offline estimates are LOW confidence with assumptions/stale baselines, or MEDIUM
with usable learned rates; they are never exact.

Login compares predicted and actual rested XP and can learn a rate when at least
five minutes elapsed, level/XP/XP-per-level are unchanged, observations are complete,
and positive accumulation is below the configured caps. Up to eight samples per
resting location are averaged, and only the latest comparison is retained.
Rescan/entering-world events do not calibrate again. `/rq diag` reports sample counts
and accepted/rejected reasons; Today also shows the last comparison.

After a relevant perk change, update the rate multiplier or use **Reset calibration**,
then log out to establish a new baseline. Perk detection is manual; no Legacy API
contract is assumed. Changed global mechanics clear learned rates while retaining
valid observed logout data for estimates under the new assumptions. Blocker and
dungeon signals are also manual until later inventory/quest milestones.

## Commands

| Command | Current behavior |
| --- | --- |
| `/rq` | Toggle the dashboard, initially Today (text fallback if unavailable). |
| `/rq today [text]` | Open recommendations, or print them without the UI. |
| `/rq planning` | Edit rested assumptions, member multiplier, and manual planning signals. |
| `/rq pin <name\|slot\|ID>` | Pin an enabled member as play-next; ambiguous names are rejected. |
| `/rq unpin` | Clear the account-wide pin. |
| `/rq diag` | Print capabilities, registration, schemas, saved section timestamps and observed values. |
| `/rq rescan` | Refresh the current snapshot; unavailable fields retain their old values with incomplete markers. |
| `/rq roster` | Open the Roster tab. |
| `/rq roster text` | Print account snapshots, excluding ignored characters. |
| `/rq settings` | Open roster configuration controls. |
| `/rq close` | Close the dashboard. |
| `/rq reset-window` | Reset saved window position to center. |
| `/rq main [character ID]` | Make an enabled member the main; defaults to the current character. |
| `/rq role <role> [character ID]` | Set UNASSIGNED, TANK, HEALER, DPS, HEALER_DPS, or FLEX. |
| `/rq unlink [character ID]` | Release a provisional link without deleting the character snapshot. |
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
staleness threshold is 48 hours. Offline rested XP is explicitly **estimated** or
unknown; cached snapshot values remain separately labelled last observed.

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
zip -r RosterQuartermaster-0.0.5.zip RosterQuartermaster
```

Do not ship tests, toolchains, repository metadata, or development configuration.
This is a development-test archive, not a validated release. Automated
validation/release workflows and the first MVP version `0.1.0` are scheduled
for later milestones.
