# Compatibility spike manual tests

These tests require the actual Forever client. On 2026-10-02, the user reported
that the supplied installation, diagnostics/rescan, reload, and full-restart
smoke-test walkthrough passed on client 1.60.1, build 70170, interface 16001.
No separate results were supplied for the extended cases below, including
second-character isolation, level-cap behavior, corrupt data, and combat.
See [BETA_API_NOTES.md](BETA_API_NOTES.md) for the evidence and its limits.

Back up SavedVariables before testing. Do not delete existing user data to
simulate a clean installation; use a backed-up test profile instead.

## Installation and diagnostics

1. Obtain the client interface number and install as described in the README.
2. Enable Lua error reporting through the client-supported settings.
3. Log in. Confirm the compatibility-probe message appears without Lua errors.
4. Run `/rq` and `/rq diag`. Confirm they display the same report.
5. Compare GUID/name, realm, class, level, XP, rested XP, and resting state against
   the client. Check the build/interface values against the installation evidence.
6. Check that missing/failed APIs appear explicitly in the capability list.
   A reported numeric project ID must not be treated as confirmation of flavour.
7. Confirm account and character schema versions are `1` and the SavedVariables
   status is `initialized`.
8. Confirm the login events are `observed`, while logout is not claimed observed
   before it has occurred.

## Snapshot refresh

1. Note the saved server timestamp.
2. Gain XP or enter/leave a rested area.
3. Run `/rq rescan`, then `/rq diag`. Confirm the persisted timestamp advances and
   the observation reflects the new state.
4. Inspect `RQCharDB.snapshot` through a client-supported variable inspector to
   verify the **saved** values, not only the live diagnostic values.
5. Test an exhausted rested pool, a nonzero rested pool, and a level-cap character.
   Confirm a successful nil exhausted-pool return represents zero in this build.
6. Run an unknown `/rq` subcommand. Expect usage text, not a Lua error.

Automatic XP/resting/zone event updates belong to Milestone 1. They are not an
acceptance criterion for this spike.

## Reload and restart persistence

1. Using a client-supported variable inspector, set
   `RQDB.settings.persistenceProbe` to a recognizable string and
   `RQCharDB.persistenceProbe` to a different recognizable string.
2. Run `/reload`. Confirm both markers remain and diagnostics still work.
3. Check `RQCharDB.snapshot.lastLogout` after loading. Confirm it reflects the
   prior logout event if the client fires that event on reload.
4. Exit the game normally, fully restart it, and log into the same character.
   Confirm both markers remain. Record this separately from the reload result.
5. Log into a second character. Confirm the account marker remains shared while
   its character marker and snapshot are independent from the first character.
6. Remove only the two test marker fields when finished.

Mock tests cover reinitialization of the tables, not the client's disk writes.
Do not report a full restart pass based on a successful `/reload`.

## Failure handling and safety

1. In a backed-up test profile, try a future schema number and a malformed root or
   snapshot table. Confirm initialization explicitly disables persistence, `/rq
   diag` remains usable, and `/rq rescan` does not report a successful save.
2. Restore the original backed-up data after the corruption tests.
3. Test diagnostics during combat. Expect chat text only: no popups, protected
   actions, crafting, mailing, purchasing, or character selection.
4. Confirm there are no per-frame bag scans or background inventory work.
5. Record actual results and client build in `BETA_API_NOTES.md`.

Roster linking, the dashboard, planning logic, bags/bank/mail, professions,
checklists, and import/export need separate acceptance tests as they are added.
