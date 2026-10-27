# Manual tests — 0.0.38

## Four-tab revamp acceptance

1. Switch realm and faction/ruleset at the top; visit all four tabs. Only scoped
   members, groceries, inventories and per-character settings should appear.
   An empty combination must not switch itself to All.
2. Roster rows show class, rested XP (offline estimates labelled), professions,
   behind markers and recorded gold. Assign a Main in two groups independently.
   Equal levels put Main first; a lower-level alt is suggested before Main.
3. Expand bags and bank for two members. Verify sizes, timestamps and unknown/
   stale labels. Search by item name and ID: matches stay bright, others dim.
   Clear search, switch owners and inspect Bag upgrades without losing snapshots.
4. In Professions, verify orange recipes/material quantities for each scoped
   member. With Auctionator, compare per-craft cost with reagent unit prices.
   Missing one price must show unavailable, never a partial total or zero.
5. In Grocery list, edit a minimum and add an item with Set item stock. Verify
   the displayed owner is the one changed; changing filters while editing must
   not write to an out-of-scope member. Zero clears only the manual minimum.
6. Open Compact list for one member and All members. Close the main window and
   browse the AH with the compact list open; check scrolling and dragging.
   Reopen the main window, change scope and verify compact contents follow.
7. Test long names, large inventories, UI scaling, metadata arriving late and
   repeated tab changes. Retired Activity, task lists and Pin controls stay absent.

## Round minimap launcher

1. Upgrade with a SavedVariables backup; expect schema 19. Disable collection
   temporarily in your drawer addon to inspect RQ's native minimap button.
2. Verify the round border/icon, tooltip instructions and normal click toggle.
   Left-drag through all four quadrants: the button should follow the edge, not
   float freely or open the dashboard when released.
3. Repeat at a different UI scale. Reload and restart the client: the saved
   angle should remain. No movement is allowed during combat.
4. Hide the button, enter combat or log out during a drag: no update loop should
   remain, and the last valid position should be saved.
5. Re-enable collection. Drawer layout, visibility, clicks and tooltips should
   work; RQ must not pull the button back to the minimap on world entry or config
   import/rollback. Use the collector's own movement controls while collected.
6. A client without texture-mask APIs should retain the round native border and
   working launcher. Native texture availability still requires a live check.

Prioritize the [trade-group acceptance checks](USER_ACCEPTANCE_TESTS.md#trade-group-and-cookingfishing-checks-for-0034).
Test all four ruleset/faction combinations and unknown/neutral observations.
Confirm boundary enforcement both when generating a proposal and when clicking
an already displayed Attach action. Repeat coverage checks on bank transfers,
bag transfers/crafting, profession advice and pending shipments. A displayed
account-wide inventory total is not permission to trade.

Cooking/Fishing priority must preserve sender reserves, choose only one enabled
GUID per combination, keep ingredients on the designated character and retain
assignments through reload/restart. Verify the manual ruleset fallback only on
unlabelled realms; record native faction API results and exact realm names.

**Status: packaged; automated checks pass; client acceptance pending.** This is a test plan, not a pass report.
Record exact version/build/interface/locale, steps, expected/actual results and
relevant diagnostics. Older user reports and mocked tests do not certify this
schema 19 trade-group release. Start with [USER_ACCEPTANCE_TESTS.md](USER_ACCEPTANCE_TESTS.md)
for a shorter walkthrough.

## 1. Safe installation and migration

1. Close the client. Back up account and per-character RosterQuartermaster
   SavedVariables and retain the matching old addon for rollback.
2. On a disposable test installation, install the complete candidate directory,
   removing old runtime files without deleting SavedVariables.
3. Verify TOC/namespace/package version alignment and `/rq diag` load status.
   No missing-file/module references should target retired features.
4. Fresh database: expect schema 19, no prepopulated roster and no preset/slot
   setup. Unknown characters are pending until explicitly added/ignored.
5. Older-schema database: expect registered characters, enabled flags, roles,
   main choice, retained settings, snapshots, inventory, recipes, supplies/goals/
   reserves, profession intent, rested calibration and
   mail history retained.
6. Confirm removal of retired planned-roster/link metadata, gear settings and
   dungeon/Legacy progress. Actual characters formerly linked to slots must
   remain actual members with their existing role/main choices.
7. Repeat initialization/reload: migration must be idempotent. Neither duplicate
   members nor starter slots should appear; retained values must not drift.
8. Test structurally partial valid old roots and malformed/future roots only
   using disposable copies. Invalid retained data must disable writes and preserve
   both originals, not partially publish one root.
9. Fully exit and restart. Confirm schema/data persistence on disk separately
   from successful in-memory initialization.

Do not reset live SavedVariables to bypass migration errors. Restore the matching
backup and old addon for downgrade; schema 19 is not backwards-compatible with
old-schema configuration imports.

## 2. Removal boundary

Inspect navigation, character details, Settings, help, copy reports and commands:

- No fixed/planned roster, inline planned-slot creation, slot names, preset,
  link or unlink controls.
- No LOW overlay, discard recommendation or bag-space report.
- No Gear advisor button/editor/profiles, blue upgrade arrows or score tooltips.
- No dungeon/Legacy tracker, quest/clear/drop/credit/perk allocation UI.
- No guide import/catalog/approval workflow or next-20 profession path.

Typing old commands must not revive retired workflows or change saved state.
Inspect the runtime archive/TOC for removed modules/assets; inspect development
validation instructions for obsolete guide tooling. Preserve ordinary item
tooltips/metadata needed by retained bag/mail features.

Confirm that **manual dungeon ready in Planning remains available**, affects
ranking as a signal and does not create progress records. Native orange recipes,
explicit goals and groceries must remain usable without any guide data.

## 3. Dynamic registration and identity

1. On an unknown character, use `/rq register`, then Add. Repeat on more than
   five characters where available; no slot/preset limit or class requirement.
2. Ignore a pending character. Reload and confirm it stays ignored and does not
   update tracking or appear as a provider/recommendation.
3. `/rq add` resumes explicitly. Existing snapshot/configuration should survive.
4. Configure actual member main/role offline. Adding another character must not
   replace an explicit main. Ignoring the main member clears that choice.
5. Test registration during combat and with unavailable UI/combat helpers.
   No unsafe popup; chat fallback explains add/ignore.
6. Test full names/surnames and actual Name-Realm selectors. Ambiguous names must
   require a precise ID, not guess. Retired slot labels must not resolve.
7. Check GUID identity after a rename; test unambiguous fallback promotion and
   conflict rejection using fixtures/disposable data rather than corrupting live
   records.

## 4. Snapshot and logout safety

- Rescan after XP/level/resting/location/money/bag/profession changes. Verify
  relevant events and individual section times, not just `lastSeen`.
- Unavailable/failed calls retain old values with incomplete warnings.
  Never-observed values stay unknown; a valid zero remains zero.
- Verify debounced updates and timer fallback. Non-player XP events must not
  rewrite the player's snapshot.
- At logout, prevent queued callbacks from publishing after teardown. Unavailable
  or zero XP maximum must preserve complete earlier data.
- Switch characters and check account/per-character isolation, copies rather
  than aliased tables, and no active scan against an offline selection.
- Age a snapshot in a fixture; verify stale/clock-mismatch labels by section.
  A fresh bag scan must not make old recipes/bank/mail fresh.

## 5. Rested/play-next regression

1. Compare active rested values with the client; verify zero vs unknown handling.
2. Log out resting, switch character and verify explicitly **estimated** rested.
   Missing logout evidence stays unknown; cached baselines show lower confidence.
3. Check default mechanics are labelled assumptions and editable.
4. At equal levels, Main should be suggested first in its realm/faction.
   Lower an alt's level and verify the alt comes first; no level-lead target applies.
5. Assign Mains in two realm/faction groups; each retains its choice independently.
   Pending/ignored/disabled members do not join the ranking population.

6. Toggle **dungeon ready** manually. Compare score/reasons without expecting
   dungeon/quest/Legacy progress. Resource blocker remains independent.
7. Test calibration eligibility/rejection after login, bounded samples, manual
   multiplier/reset and global-mechanics changes. Cached baselines must not
   teach rates; repeated rescans must not recalibrate the same login.
8. Verify optional profession-lag ranking defaults off; enabling changes only
   eligible fresh primary deficits, not hard tiers or explicit goals.

## 6. Four-tab graphical workspace

- Check Roster / Bags and Inventory / Professions / Settings only. Today/Planning/Supplies/
  Bags command aliases open their retained views, not extra primary tabs.
- Test many characters/items, long names, missing icons, small/large UI scale,
  realm/sort/status filters and GUID-stable detail selection.
- Refresh visible views while editing input or scrolling. Preserve drafts,
  selections and valid scroll positions; hidden views should not rebuild.
- Check keyboard focus and optional arrow/page navigation without stealing text
  input. Verify Close/Escape/minimap toggle and saved window position.
- Enter combat: hide/defer safely and do not automatically reopen afterward.
  Missing native graphics, tooltip or keyboard APIs must retain basic/text use.
- Copy complete scoped evidence rather than only the visible page.

## 7. Native professions, advice and goals

1. Scan each owned profession; linked/guild windows must not overwrite known
   personal recipes. Missing/partial reads retain old evidence as uncertain.
2. Verify primary/secondary classification, current skill/cap and lag benchmark.
   Missing/stale skills cannot imply zero skill/free primary slots.
3. With zero/one/two learned primaries, verify advice gives pairs/additions/no
   unlearn suggestions respectively. Same-realm named providers only.
4. Change focus, preference, exclusion and intended professions. Intent must
   persist independently without becoming learned coverage or a planned character.
5. Open `/rq targets [member]`: only eligible recent learned orange recipes with
   complete reagents. Edit/save a target; revalidate before saving.
6. Set an explicit observed recipe goal and later clear with target 0. Skill
   targets are estimates; rescan after a color change, never silently switch
   recipes or create a next-20 path.

## 8. Automatic groceries and visual review

1. With no manual needs/goals, scan a below-cap profession containing learned
   orange recipes. Expect one craft's ingredients for every eligible recipe.
2. Confirm shared ingredients sum across recipes/professions. Unknown reagents,
   unlearned recipes, nonpositive skill-ups and capped professions do not create
   unsupported targets.
3. Add an explicit goal for one recipe: its amount replaces its one-craft
   allowance, not the other recipes. Clear it and verify allowance returns.
4. Add minimum needs and potion/bandage reserves. Floors use the larger overlap,
   not duplicate targets; automatic updates must not overwrite configuration.
5. New complete scans remove no-longer-orange requirements. Stale cached scans
   remain visibly uncertain and must not masquerade as a recent observation.
6. Roster Grocery list and `/rq supplies <member>` open character-scoped visual
   Inventory cards for online/offline/disabled registered members.
7. Verify Target / In bags / Still needed / Withdraw / Collect mail / In transit
   values, shortage-first order, filters and whole-list counts across pages.
   Unknown quantities must not show as covered zeros.
8. Expand recipe evidence; verify IDs, quantities and timestamps. Full report
   retains full data; metadata loading updates icons/names without changing stock.

## 9. Bank, item search and bag crafting

1. Search `Copper`, exact `2770` and literal pattern characters. Check trimming,
   128-byte limit, all item categories, unresolved names and text fallback.
2. Include disabled registered owners; exclude pending/ignored records.
   Owner/source filters and cross-realm results must not alter transfer eligibility.
3. Open bank; deposit/withdraw while scans run. Paired bag/bank observations must
   not double count. Close early or interrupt a load: unknown, not known empty.
4. Offline bank search retains times/container evidence. Legacy unconfirmed or
   stale stock must not suppress shortages as verified current stock.
5. Verified owner materials produce Withdraw prerequisites. Bank donor suggestions
   require manual withdrawal/fresh proposal and do not prematurely credit recipients.
6. Bag upgrades choose carried beneficial bags first and allocate each once.
   Exclude backpack/bank/reagent bags and unknown capacities/binding.
7. Tailoring plans use learned observed outputs/capacities, including gray recipes.
   Check output quantities, reagents, stable ties and named recipients/slots.
8. Known intermediate crafts use existing intermediate stock before raw materials.
   Unknown conversions stay intermediate needs; include vendor reagents.
9. Craft/mail/equip manually and rescan. Bags in mail/in transit are not carried
   ready upgrades. Do not duplicate real crafting merely to test a renewed plan.

## 10. Routing and mail attachment smoke test

Use inexpensive transferable items and uniquely named same-realm test members.
Review every Send Mail draft manually; do not test failure paths with valuable items.

- Sender goals/reserves/own upgrades remain protected. Explicit category/recipient
  policies and exact needs precede general surplus; no duplicated allocation.
- Check cloth/Tailoring, metal/stone/Blacksmithing, eligible uncommon BoE/
  Enchanting routes. Gear suitability/disenchantability are manual checks.
- Light Feather ID 17056 works without name; exact `Scroll:` prefix works with
  observed names. Mage senders keep surplus; `Scroll of ...` does not match.
- For Rogue routing, verify locked-instance tooltip, localized label and correct
  selected instance when the same ID has locked/unlocked copies. Busy/bound/
  unknown-binding stacks remain blocked. No opening-skill guarantee.
- Outside a mailbox, `/rq mail` is read-only. At a mailbox, only Attach clicks
  fill recipient/move exact quantities; Send remains untouched.
- Test split stacks, free attachment limits, nonempty cursor, combat, changed/
  ambiguous/different recipient, anonymous existing attachments and duplicate
  draft item. Preserve unrelated same-recipient attachments.
- Change the draft/close mailbox or simulate an API failure mid-batch. Stop,
  report partial progress and recover only the helper's held item; no automatic
  retry, extra mail or accidental Send.

## 11. Shipments and inbox reconciliation

1. Stay in default observation mode. Capture one valid send and confirm native
   success; do not label an unconfirmed attempt delivered.
2. Confirm that exact success manually. Failed/cancelled/COD/non-roster sends
   must not become usable credit. Native draft timing must not reuse stale data.
3. Open recipient mailbox, wait for complete paired scans, and verify pending
   coverage is replaced by matching inbox coverage, not counted twice.
4. Manually collect partially/fully; require attachment removal/carried gains
   and matching take evidence before reconciliation.
5. Test duplicate quantities/items, delayed/partial loads, returns, interrupted
   collection and close/reopen. Ambiguity stays uncertain.
6. Cached active mail requires re-verification after login. Stale/closed mail
   stops covering needs; pending/inbox stock cannot become donor stock.
7. Close a shipment without claiming collection; prune only terminal records.
   Use fixtures for the 500-record full-ledger boundary.
8. Only after the above contract is verified, opt in with
   `/rq mail-tracking verify`; test `off` and build-change invalidation.

## 12. Removed activity and checklist tracking

Verify Activity, Ledger, History, Session tasks, Pin and main-lead controls are
absent. Old activity/task/pin commands must not change saved state. Reload after
schema 19 migration: activity/checklist data is gone, but current wallet and
inventory/recipe/rested/mail snapshots remain unchanged.

## 13. Configuration transfer and rollback

1. Retain an old-schema export as a rejection fixture. After upgrade, create a
   **fresh schema 19 export**; do not expect old exports to import.
2. Preview retained settings, actual roster/main/roles, needs/goals/reserves,
   profession intent. No retired gear/slot/progress data.
3. Cancel: no changes. Confirm with the explicit preview token: configuration
   replacement only; snapshots/inventory/recipes/rested/mail remain.
4. Test omission of a member: observations survive while registration becomes
   pending and supplies/intent return to defaults, as the preview warns.
5. Change observations after import, then rollback: restore configuration without
   rolling back live observations. Explain that later configuration edits also
   revert. Reload/logout clears preview and rollback.
6. Test malformed, oversized, unsupported-schema, bad-checksum and invalid-ID
   strings on disposable data. Rejection must leave both roots unchanged.
   The checksum is not authenticity validation.

Transfer's 200-character/256-KiB bounds do not impose a roster registration limit.
Exports are not SavedVariables backups.

## 14. Release evidence

Record automated Lua tests/lint/format/syntax and packaging-test results
separately from these manual outcomes. Do not run removed guide tooling.
Inspect a fresh runtime-only archive for TOC completeness and retired-file absence,
then repeat installation/reload/restart against that archive.

No client-tested claim is justified until outcomes are recorded.
**0.0.38 is packaged and passes automated checks; client acceptance remains pending.**
