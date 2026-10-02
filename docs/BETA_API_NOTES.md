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
persistence walkthrough. Those smoke tests are recorded as user-reported passes
on the build above, not as independently observed results.

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

There is deliberately no guessed clock fallback or invented client-flavour
identifier. Missing GUIDs remain unknown in this spike; fallback identifiers and
explicit provisional-roster linking belong to the registration milestone.

## Events

The probe registers `ADDON_LOADED`, `PLAYER_LOGIN`, and `PLAYER_LOGOUT`.
Diagnostics distinguish **registered (not yet observed)** from **observed**.
Successful registration alone does not prove that an event fires. Registration
failures are reported individually and do not prevent other subscriptions.

All other events listed in the implementation plan are deferred until their
snapshot sections exist. No bag scans or per-frame polling are performed.

## Persistence

`RQDB` is account-wide and `RQCharDB` is per-character. This spike records current
identity and a small compatibility snapshot; it does not yet maintain offline
account-wide character records or register roster members.

- Nil and structurally valid partial databases are initialized at schema 1.
- Unknown fields are preserved during initialization.
- Invalid table shapes or any explicit unsupported schema disable writes to
  **both** databases. The originals are retained, with an explicit diagnostic.
- No migration from an earlier released schema exists because there is no
  earlier release. Future schema changes must introduce idempotent migrations.
- A successful initializer means only that the in-memory tables are ready. It
  does not prove the client wrote them to disk.

### Client observations to record

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

If persistence fails, record the exact build and whether the failure occurs on
reload, clean exit, or both. Do not describe data as durable until tested.
Configuration export/import remains a later requirement, not an existing
workaround.
