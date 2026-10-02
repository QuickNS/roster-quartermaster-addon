# Manual tests

These tests require the actual Forever client. On 2026-10-02, the user reported
that the supplied installation, diagnostics/rescan, reload, and full-restart
smoke-test walkthrough passed on client 1.60.1, build 70170, interface 16001.
No separate results were supplied for the extended cases below, including
second-character isolation, level-cap behavior, corrupt data, and combat.
See [BETA_API_NOTES.md](BETA_API_NOTES.md) for the evidence and its limits.

That report applies to **0.0.1**, not the new **0.0.2** features below.
All Milestone 1 client tests are pending.

Back up SavedVariables before testing. Do not delete existing user data to
simulate a clean installation; use a backed-up test profile instead.

## Installation and diagnostics

1. Obtain the client interface number and install as described in the README.
2. Enable Lua error reporting through the client-supported settings.
3. Log in. Confirm the roster-snapshots message appears without Lua errors.
4. Run `/rq` and `/rq diag`. Confirm they display the same report.
5. Compare GUID/name, realm, class, level, XP, rested XP, and resting state against
   the client. Check the build/interface values against the installation evidence.
6. Check that missing/failed APIs appear explicitly in the capability list.
   A reported numeric project ID must not be treated as confirmation of flavour.
7. Confirm account and character schema versions are `2` and the SavedVariables
   status is `initialized`.
8. Confirm the login events are `observed`, while logout is not claimed observed
   before it has occurred.

## Snapshot refresh

1. Note the saved server timestamp.
2. Gain XP, spend/earn money, change bag capacity, increase a profession, and
   enter/leave a rested area or zone.
3. Wait at least 0.25 seconds after each change and run `/rq diag` **without
   rescanning first**. Confirm saved section values/timestamps update only for
   the affected sections. Live progression lines alone are not proof of capture.
   Also run `/rq rescan` separately and confirm all available sections refresh.
4. Inspect `RQCharDB.snapshot` through a client-supported variable inspector to
   verify the **saved** values, not only the live diagnostic values.
5. Test an exhausted rested pool, a nonzero rested pool, and a level-cap character.
   Confirm a successful nil exhausted-pool return represents zero in this build.
6. Run an unknown `/rq` subcommand. Expect usage text, not a Lua error.

Profession and bag APIs may be unavailable on the beta client. Expect an
`INCOMPLETE` section with a diagnostic capability reason, not a fabricated empty
profession list or zero bag capacity. Older observations should be retained.
Inventory bags/bank/mail and recipe sources remain unscanned in this milestone.

## Schema-1 upgrade and registration

1. Close the client and back up both SavedVariables files. Keep the backup outside
   the addon directory. Install all runtime directories listed in the README.
2. Log into a character used with 0.0.1. Confirm schema 2, retained custom settings
   and prior logout timestamp, and a new account character record. Registration
   must remain pending until you choose; a matching planned name is not consent.
3. Choose **Link** to the intended slot, or use `/rq link warrior` on the main.
   Confirm `/rq slots` reports that link and `/rq roster` shows one member.
4. Test `/rq name druid Luna Tick`; actual character names must not change.
5. On another character, try linking the occupied slot. Expect an error and no
   overwritten link. Then choose another slot or `/rq add`.
6. Repeat across the five intended characters. From any one of them, `/rq roster`
   should display all five stored records, not just the active character.
7. Use `/rq ignore` on a test character. Its snapshot should stop updating and it
   should disappear from `/rq roster`, including after `/reload`.
   Use `/rq register` followed by Add (or `/rq add`) to resume. Prior links remain.
8. Choose **Decide later** on a pending character. Expect no further automatic
   prompts that login, but `/rq register` should reopen the choices.
9. If a character rename is available naturally, confirm the unchanged GUID
   updates the display name without making a second record. Do not purchase a
   rename just for this test; the GUID behavior is also covered by mocks.

## Snapshot freshness

1. Verify `/rq roster` labels offline values as last observed, not exact current
   state or estimated rested XP.
2. Use an old offline snapshot or a backed-up test profile to check the 48-hour
   stale threshold and visible server timestamps.
3. In the test profile, make one section stale while the overall snapshot is
   recent. Confirm the section warning remains visible.
4. Unavailable timestamps must display as unknown, not as fresh data.

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
3. Test diagnostics and `/rq register` during combat. Expect chat text only,
   with no registration popup until combat ends. An open prompt must hide when
   combat begins. If combat-state detection is unavailable, use slash commands;
   the addon must not guess that showing a popup is safe.
4. Test unavailable native UI templates in a mocked or supported test environment.
   Expect an explicit error and working `/rq add`, `/rq link`, and `/rq ignore`.
5. Confirm there are no per-frame bag scans or background inventory work.
6. Record actual results and client build in `BETA_API_NOTES.md`.

The dashboard, planning logic, item-level bags/bank/mail, profession planning,
checklists, and import/export need separate acceptance tests as they are added.
