# Forever beta API notes

## Evidence status

On 2026-10-02, the user reported this in-client `GetBuildInfo()` output:

```text
1.60.1 70170 Oct 1 2026 16001
```

This identifies client version **1.60.1**, build **70170**, build date
**Oct 1 2026**, and interface **16001**. The TOC now declares that observed
interface number.

Later on 2026-10-02, the user reported: **"everything passed. diag looks fine"**
after receiving the installation, diagnostics/rescan, `/reload`, and full-restart
persistence walkthrough for version 0.0.1. Those smoke tests are recorded as
user-reported passes on the build above, not as independently observed results.
The new version 0.0.2 APIs, migration, registration UI, and event updates have
only been tested with mocks so far.

During 0.0.2 testing on 2026-10-02, the user reported `/rq link warrior`
remaining in the chat input, with `Bootstrap.lua:74: attempt to index field
'RegistrationPrompt' (a nil value)`. The user then confirmed that the `UI`
directory had been omitted from the installation. Omitting the module in the test loader
reproduced the same exception. Version 0.0.3 removes the slash-command dependency
on that module and reports its absence. In-client confirmation is pending.

Version 0.0.4 adds the roster dashboard and requested native minimap launcher.
Its UI, geometry, schema-3 upgrade, and configuration interactions have been
tested with mocked frames only; visual compatibility in Forever remains pending.

No diagnostic transcript or separate per-test results were supplied. Individual
API return values, event delivery details, and extended failure cases remain
unconfirmed. No direct client access was available during implementation.
Mock results must not be recorded as in-client observations.

The compatibility probe tests conventional WoW API names with capability checks;
it does not assert that Forever exposes these APIs unchanged. Calls that throw
are contained at the adapter boundary and reported by `/rq diag`. Restricted
return values are rejected when `issecretvalue` is available.

## Candidate APIs to verify

The overall diagnostic smoke test passed according to the user. `Unverified`
below means the specific API contract or output has not been supplied or
individually confirmed; it does not mean the smoke test failed.

| API / global | Candidate shape or use | Status |
| --- | --- | --- |
| `GetBuildInfo()` | version, build, date, interface number | User-reported output confirmed on 2026-10-02; see above |
| `WOW_PROJECT_ID` | Numeric project ID; not proof of Forever flavour | Unverified |
| `UnitGUID("player")` | Character GUID string | Unverified |
| `UnitName("player")` | Display name as first return value | Unverified |
| `GetRealmName()` | Realm string | Unverified |
| `UnitClass("player")` | Class token as second return value | Unverified |
| `UnitRace("player")` | Localized race label as first return value | Unverified |
| `UnitLevel("player")` | Non-negative level number | Unverified |
| `UnitXP("player")` / `UnitXPMax("player")` | Current and maximum XP | Unverified |
| `GetXPExhaustion()` | Rested XP; successful nil provisionally means zero | Unverified |
| `IsResting()` | Boolean resting state; other types rejected | Unverified |
| `GetServerTime()` | Non-negative timestamp, assumed seconds | Unverified |
| `issecretvalue(value)` | Restricted-value detection when present | Unverified |
| `CreateFrame("Frame")` | Event frame supporting `SetScript` and `RegisterEvent` | Unverified |
| `SlashCmdList` / `SLASH_ROSTERQUARTERMASTER1` | Native `/rq` registration | Unverified |
| `DEFAULT_CHAT_FRAME:AddMessage(text)` / `print(text)` | Diagnostics and fallback output | Unverified |
| `GetMoney()` | Non-negative copper amount | New in 0.0.2; unverified |
| `GetZoneText()` / `GetSubZoneText()` | Location labels, including an empty subzone | New in 0.0.2; unverified |
| `NUM_TOTAL_EQUIPPED_BAG_SLOTS` / `NUM_BAG_SLOTS` | Equipped bag count, excluding backpack index 0 | New in 0.0.2; unverified |
| `C_Container.GetContainerNumSlots` / `GetContainerNumSlots` | Slot count per equipped bag | New in 0.0.2; unverified |
| `C_Container.GetContainerNumFreeSlots` / `GetContainerNumFreeSlots` | Free-slot count as first return | New in 0.0.2; unverified |
| `GetProfessions()` | Up to six profession indices, possibly with nil holes | New in 0.0.2; unverified |
| `GetProfessionInfo(index)` | Name, icon, rank, max rank, ability count, offset, skill-line ID | New in 0.0.2; unverified |
| `C_Timer.After(seconds, callback)` | One-shot event coalescing | New in 0.0.2; unverified |
| `InCombatLockdown()` | Boolean combat-lockdown state | New in 0.0.2; unverified |
| Native frames, textures, `GameFontNormal`, `UIPanelButtonTemplate` | Registration choices; guarded construction | New in 0.0.2; unverified |
| `Minimap`, button textures, `GameTooltip` | Fixed lower-left launcher, click toggle and hover tooltip | New in 0.0.4; unverified |
| `UIPanelScrollFrameTemplate`, `SetScrollChild`, vertical scrolling | Roster card viewport | New in 0.0.4; unverified |
| `InputBoxTemplate`, focus, Enter/Escape handlers | Planned-name editing without overwriting focused drafts | New in 0.0.4; unverified |
| `SetMovable`, drag scripts, `GetPoint`, `SetClampedToScreen` | Saved/restored account window position | New in 0.0.4; unverified |
| `UISpecialFrames` | Escape registration for the native `RQMainWindow` frame | New in 0.0.4; unverified |

There is deliberately no guessed clock fallback or invented client-flavour
identifier. Missing GUIDs use a normalized actual name/realm fallback when both
are available. Missing all identifying information prevents capture instead of
guessing a provisional roster slot.

Profession capture uses stable numeric skill-line IDs from `GetProfessionInfo`.
There is no localized-name-based `GetSkillLineInfo` fallback: the legacy API's
ability to identify profession rows reliably is unresolved. Missing/restricted
profession APIs leave the section incomplete and retain older observations.
The skill-line IDs in the default planned roster are conventional planning
defaults, not validated Forever recipe or profession data.

Bag capture counts equipped capacity only; it does not scan item slots, bank,
mail, or recipes. Missing bag-count constants result in unknown capacity rather
than an assumed four-bag layout. Modern container methods are preferred when
present, with legacy methods used only when their modern counterpart is absent.

No combat-state API means no registration popup; chat commands still work.
Failed native widget creation is reported and falls back to chat instructions.
The dashboard likewise refuses to open without a known out-of-combat state and
hides on combat entry. A failed native dashboard initialization stays disabled
for that session; use text commands and reload after correcting the installation.
If `UISpecialFrames` is absent, the Close button and `/rq close` remain available.
If `Minimap` is absent, `/rq` still works and launcher detection retries on
`PLAYER_ENTERING_WORLD`. A missing `GameTooltip` does not disable the launcher.

## Events

In addition to `ADDON_LOADED`, `PLAYER_LOGIN`, and `PLAYER_LOGOUT`, version 0.0.2
registers the following unverified candidate events:

- `PLAYER_ENTERING_WORLD`: identity reconciliation and full refresh.
- `PLAYER_LEVEL_UP`, `PLAYER_XP_UPDATE`: progression/rested refresh; XP events for
  non-player units are ignored.
- `UPDATE_EXHAUSTION`: rested refresh.
- `PLAYER_UPDATE_RESTING`: location/resting and rested refresh.
- `PLAYER_MONEY`: money refresh.
- `BAG_UPDATE_DELAYED`: capacity refresh only.
- `SKILL_LINES_CHANGED`, `TRADE_SKILL_LIST_UPDATE`: profession skill refresh.
- `ZONE_CHANGED_NEW_AREA`, `ZONE_CHANGED`, `ZONE_CHANGED_INDOORS`: location refresh.
- `PLAYER_REGEN_DISABLED` / `PLAYER_REGEN_ENABLED`: hide/defer registration UI.

Diagnostics distinguish **registered (not yet observed)** from **observed**.
Successful registration alone does not prove that an event fires. Registration
failures are reported individually and do not prevent other subscriptions.

Events coalesce into one section-specific update after 0.25 seconds. If the timer
API is absent/restricted, the addon warns once and refreshes immediately instead.
Level-up capture is deferred with the timer so progression APIs can catch up.
Without a working timer, use `/rq rescan` if the level-up event precedes the API
state change. Logout captures synchronously and invalidates queued callbacks.
No per-frame polling is performed. Quest, bank, and mail events are deferred.

## Persistence

`RQDB` is account-wide and `RQCharDB` is per-character. Version 0.0.2 keeps
independent account-wide character snapshots, explicit registration status,
provisional slot links, and per-character current-state copies.

- Nil and structurally valid partial databases initialize at schema 3.
- Schemas 1/2 migrate to schema 3 on copied data; both roots are validated before
  either is replaced. The migration is idempotent.
- Unknown fields are preserved during initialization.
- Invalid table shapes or any explicit unsupported schema disable writes to
  **both** databases. The originals are retained, with an explicit diagnostic.
- Downgrading requires restoring the pre-upgrade backup; schema 3 is not
  understood by earlier versions. Future changes require idempotent migrations.
- A successful initializer means only that the in-memory tables are ready. It
  does not prove the client wrote them to disk.

### Version 0.0.1 client observations

| Check | Observed result |
| --- | --- |
| Forever version/build/interface | User-reported 2026-10-02: 1.60.1 / 70170 / 16001; build date Oct 1 2026 |
| Installation and `/rq diag` | User-reported pass, 2026-10-02; diagnostics "looks fine" |
| `/rq rescan` after a state change | Covered by user's overall smoke-test pass; no separate output supplied |
| API return types, including no-rested-XP behavior | Not individually confirmed |
| Event delivery | Not individually confirmed |
| `/reload` with retained account and character markers | Covered by user's overall smoke-test pass; no separate output supplied |
| Full exit/restart with retained markers | Covered by user's overall smoke-test pass; no separate output supplied |
| Logout timestamp written and retained | Not individually confirmed |
| Missing/restricted API behavior in the client | Not individually confirmed |
| Second-character isolation, level-cap cases, corrupt data, and combat | Extended manual tests not explicitly reported |

### Version 0.0.2 client observations

| Check | Observed result |
| --- | --- |
| Schema-1 upgrade preserving existing data | Not run in client |
| Add/link/ignore and editable provisional names | Not run in client |
| Five account-wide records and GUID rename reconciliation | Not run in client |
| Targeted XP/resting/location/money/bag/profession events | Not run in client |
| Registration popup, combat deferral, and slash fallback | Not run in client |
| Reload/restart with account-wide snapshots and links | Not run in client |

### Version 0.0.4 client observations

| Check | Observed result |
| --- | --- |
| Native minimap button location, icon, tooltip and click toggle | Not run in client |
| Roster/Settings tabs, card layout and scrolling | Not run in client |
| Main, role, planned-name editing, offline controls and unlink/relink | Not run in client |
| Schema-3 upgrade and window position across reload/restart | Not run in client |
| Combat hiding, Escape/Close, and unavailable-UI fallback | Not run in client |

If persistence fails, record the exact build and whether the failure occurs on
reload, clean exit, or both. Do not describe data as durable until tested.
Configuration export/import remains a later requirement, not an existing
workaround.
