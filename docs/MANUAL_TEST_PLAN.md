# Manual tests

These tests require the actual Forever client. On 2026-10-02, the user reported
that the supplied installation, diagnostics/rescan, reload, and full-restart
smoke-test walkthrough passed on client 1.60.1, build 70170, interface 16001.
No separate results were supplied for the extended cases below, including
second-character isolation, level-cap behavior, corrupt data, and combat.
See [BETA_API_NOTES.md](BETA_API_NOTES.md) for the evidence and its limits.

That report applies to **0.0.1**, not the later features below. The missing-UI
installation problem in 0.0.2 was identified separately. Complete Milestone 1/2
acceptance results have not been reported; the 0.0.4 dashboard/minimap tests are pending.

Back up SavedVariables before testing. Do not delete existing user data to
simulate a clean installation; use a backed-up test profile instead.

## Installation and diagnostics

1. Obtain the client interface number and install as described in the README.
2. Enable Lua error reporting through the client-supported settings.
3. Log in. Confirm the roster-ready message appears without Lua errors.
4. Run `/rq` to open the dashboard and `/rq diag` for the separate diagnostic report.
5. Compare GUID/name, realm, class, level, XP, rested XP, and resting state against
   the client. Check the build/interface values against the installation evidence.
6. Check that missing/failed APIs appear explicitly in the capability list.
   A reported numeric project ID must not be treated as confirmation of flavour.
7. Confirm account and character schema versions are `3` and the SavedVariables
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

## Upgrade and registration

1. Close the client and back up both SavedVariables files. Keep the backup outside
   the addon directory. Install all runtime directories listed in the README.
2. Log into a character used with 0.0.1 or 0.0.2/0.0.3. Confirm schema 3, retained custom settings
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
   should disappear from `/rq roster text`, including after `/reload`, while
   remaining labeled ignored in the dashboard.
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

## Dashboard and minimap launcher

1. Confirm one RQ button appears at the lower-left edge of the stock minimap.
   Hover for the tooltip; click once to open the dashboard and again to close.
   Changing zones must not create duplicate buttons.
2. Confirm `/rq`, `/rq roster`, and `/rq settings` open the intended UI. Confirm
   `/rq diag` and `/rq roster text` remain usable without the dashboard.
3. Verify the 800x600 window at 1080p and the available ultrawide/UI-scale settings:
   no clipped controls, readable labels, accessible scrollbar, and visible Close.
4. Scroll through all known and provisional character cards. Check actual and
   planned names, race/class, roles, main flag, XP, last-observed rested XP,
   professions, location/resting state, timestamps, age, and uncertainty warnings.
5. Click Configure on an offline card. Use Add / resume, Make main, and the role
   button. Confirm only the selected character changes; the active snapshot and
   logged-in character must not be replaced or switched.
6. Verify only one new main selection remains. Linking the Warrior afterward
   must not override that selection. Ignoring the main clears its main flag.
7. Select a provisional slot, type a planned name, and press Enter or Save name.
   Gain XP or money while the edit box is focused: the draft must not be replaced.
   Switching slots should replace the draft with that slot's saved label.
8. Confirm an occupied slot cannot be overwritten. Unlink explicitly, select
   another free slot, and relink; retain the actual GUID and snapshot.
9. Drag the window, close/open it, `/reload`, then fully restart. Verify the saved
   position survives when client persistence works. Test Center and
   `/rq reset-window`, including after changing screen size or UI scale.
10. Close with Close, Escape, `/rq`, and `/rq close`. Enter combat with the window
    open: it must hide and must not automatically reopen afterward. Minimap clicks
    during combat should give text guidance, not open a popup.
11. In a supported test/mocked environment, remove the stock minimap, tooltip,
    or a dashboard template independently. Confirm capability warnings and
    functioning slash fallback, with no broken registration commands.
12. Check that hidden panels are not rebuilt on snapshot events. Visible panels
    should update after events without losing the current selection.

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

Planning logic, item-level bags/bank/mail, profession planning,
checklists, and import/export need separate acceptance tests as they are added.
