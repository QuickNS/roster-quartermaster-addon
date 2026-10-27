# 0.0.38 user acceptance walkthrough

This is the planned acceptance path for **schema 19**. The candidate is packaged
and passes automated checks. Nothing below is a recorded client pass; do not infer client
compatibility from earlier versions' tests.

Use inexpensive items and a backup/test installation. The detailed
[manual test plan](MANUAL_TEST_PLAN.md) includes failure paths and API evidence.

## Round draggable minimap button in 0.0.38

With the button outside a collector, verify its round border/icon. Left-drag it
around the minimap and release: the dashboard must not open, the button must
stay on the edge, and reload/restart must restore its angle. Repeat at a different
UI scale. Normal clicking must still toggle the dashboard.

While collected, the drawer owns its layout and movement. Verify that dragging,
world entry and configuration import do not pull it back onto the minimap.
See the [detailed launcher tests](MANUAL_TEST_PLAN.md#round-minimap-launcher)
for combat, hide/logout and capability-failure cases.

## Trade-group and Cooking/Fishing checks for 0.0.34

1. Visit and `/rq rescan` each participating character. Verify faction and
   ruleset in `/rq diag` and Manage roster. If the realm name lacks PvE/PvP,
   explicitly choose the correct **Ruleset**; do not infer it from combat flags.
2. Open Roster. It should initially show the active combination. Cycle the
   trade-group button through available groups, All trade groups and Unknown
   if present. Review an offline member without moving/deleting its record.
3. In Manage roster, select a member and **Assign Cooking/Fishing**. Assign a
   second member of that combination: only the second should show `COOK / FISH`.
   Assign a different combination independently. Clear, ignore and resume
   an assignee; an ignored/disabled/unknown-group member must not receive mail.
4. Carry inexpensive raw meat (e.g. item 769) and raw fish (e.g. 6291). From a
   different compatible character run `/rq mail`. With no grocery target, the
   assigned character should still receive proposals. Set a source stock floor
   and verify it stays carried; competing recipient groceries must not win.
   The assigned character should keep their own raw ingredients.
5. Repeat with opposite faction, opposite ruleset, missing faction/ruleset and
   another realm. No suggestions or Attach actions may cross these boundaries,
   even with explicit needs/item recipient priorities. Unknown identities require
   a visit/rescan/manual ruleset confirmation, not a guessed transfer.
6. Verify an unknown beta ingredient is not selected merely because its name
   says meat/fish. `/rq routing-item food <ID> on` explicitly opts it in.
   Test a potion/prepared food separately: it must not be treated as raw food
   unless explicitly opted in.
7. Check bank ingredients produce **Withdraw before mailing**, never attachments.
   After withdrawal/rescan only carried quantities may be attached. Send remains
   manual. Reload/restart and verify each group's assignment persists.

## 1. Back up and upgrade without losing the roster

1. Close the client and back up account **and per-character** addon SavedVariables.
   Keep the old addon too if you may downgrade.
2. Install the complete candidate in `Interface/AddOns/RosterQuartermaster/`.
   Remove the previous addon directory first so retired files do not remain;
   leave SavedVariables intact.
3. Log in and run `/rq diag`. Expect the candidate version and schema 19 without
   missing retired modules or migration errors.
4. Check all registered characters, main, roles, retained settings, snapshots,
   needs/goals/reserves, profession intent, rested data, inventory/recipes,
   mail history. Schema 19 deliberately removes activity ledgers and checklists.
5. Reload, then fully exit/restart and check again. Migration must be repeatable
   without duplicate/lost actual characters or changed retained choices.

**Expected:** schema 17 initializes an empty assignment map without inventing
old characters' faction/ruleset. Earlier migration still removes only retired planned-roster/link metadata, gear settings
and dungeon/Legacy progress. Characters previously linked to slots remain
registered. Invalid/future data must be preserved with writes disabled rather
than reset. Do not fix errors by deleting SavedVariables.

## 2. Add actual characters; no slots or presets

- Fresh installs begin empty. `/rq register` offers Add or Ignore.
- `/rq add` explicitly adds/resumes the current character; `/rq ignore` stops
  tracking without deleting its saved record.
- Add more than five actual characters where available. There is no roster
  slot limit, fixed class/profession composition or preset.
- Configure main and role on actual members. No planned-name, slot-add,
  link/unlink or preset controls should remain.
- Names/surnames display correctly; use actual names or exact GUIDs in commands.
  Ambiguous names must not guess a recipient or member.

**Expected:** offline configuration never logs in/selects/scans that character.
Ignored/pending characters do not become providers or recommendations.
Combat-safe slash fallback remains available.

## 3. Confirm the reduced interface

Open `/rq`: primary tabs are **Roster / Bags and Inventory / Professions / Settings**.
Scroll/filter actual characters, select details and test minimap/Close/Escape.
Enter combat and verify the window hides safely.

There should be no:

- LOW discard marks or Free bag space report.
- Gear advisor editor/profiles, upgrade arrows or score tooltips.
- Dungeon/Legacy tracker or credits/perk-allocation controls.
- Profession guide workflow, catalog or next-20 leveling path.
- Planned roster slot/preset/link workflow.

Old commands must not bring those features back. Ordinary native tooltips and
item metadata used by bags/mail remain.

## 4. Verify retained rested/play-next behavior

1. Compare active rested XP with the client, then log out resting and inspect
   that character from another member. Offline rested must say **estimated**
   or unknown, not live/exact.
2. At equal levels, Main should be first within its realm/faction. An alt at a
   lower level should be suggested before Main. Configure a second group's Main
   and verify the first group's choice is unchanged.

3. Open `/rq planning`; check assumptions, multiplier/reset and
   manual blocker.
4. Toggle **dungeon ready** and compare score/reasons. This manual signal remains,
   but must not create dungeon/quest/Legacy tracking.
5. Check profession-lag ranking is off by default. Enabling it changes only
   eligible deficits, not hard priority tiers.

**Expected:** old snapshots are labelled stale/incomplete; missing evidence is
not zero. Calibrated offline rested is still an estimate.

## 5. Scan professions and review orange groceries

1. On each registered character, `/rq rescan`, then open each owned profession
   window and `/rq scan-recipes`.
2. With no manual goals, find a below-cap profession with learned orange recipes
   and complete reagents. Expect materials for **one craft of each eligible
   recipe**, including shared materials summed across recipes.
3. Select the member in Roster and choose **Grocery list**, or
   `/rq supplies <member>`. Review Target / In bags / Still needed / Withdraw /
   Collect mail / In transit columns.
4. Test All, Shortages, Collect / incoming, Covered and Unknown filters; expand
   recipe evidence and use Full report. Counts describe the entire scoped list,
   not just the current page.
5. `/rq targets <member>` selects an observed orange recipe and explicit skill
   target. Its goal replaces its one-craft allowance rather than duplicating it.
   Other eligible recipes remain. Clearing target 0 restores that allowance.
6. Add `/rq need <item ID> <quantity> [member]` and consumable reserves. Floors
   must not be overwritten by recipe rescans.
7. Increase skill/rescan or use a test fixture: recipes no longer eligible should
   leave the automatic list; stale scans must remain visibly uncertain.

**Expected:** no guide or next-20 path is needed. A target skill is an estimate,
not a guaranteed run of orange crafts. Offline/disabled registered members remain
reviewable without enabling them as mail recipients.

## 6. Keep profession advice and explicit intent

Open **Profession advice** or `/rq professions [member]`. Verify same-realm named
coverage and suggestions only for confirmed free primary slots.
Two learned primaries must not trigger an unlearn suggestion. Stale/incomplete
skills request a rescan rather than imply free slots.

Change focus/preferences or save intended professions. Intent must persist
separately from learned skills and must not create a planned character/slot.
Check lag labels use the configured benchmark, not explicit goal targets.

## 7. Exercise inventory, bank and bag upgrades

- `/rq bags Copper` and `/rq find 2770` find known items with actual owners,
  source counts, timestamps and uncertain coverage. Bound/reserved items remain
  searchable; other realms do not become authorized transfers.
- Open bank and transfer a small stack. Wait for stable paired scans and verify
  no duplicate bag/bank credit. Closing early leaves uncertainty, not a known
  empty bank.
- Owner bank materials show **Withdraw** prerequisites. Manually withdraw before
  crafting or requesting a fresh mail proposal.
- `/rq bags` shows carried ready upgrades and observed Tailoring bag plans.
  Existing ready bags are assigned once before new crafts; unknown capacities/
  outputs do not generate guessed plans.
- Craft/equip manually, then rescan. Known intermediate materials and vendor
  reagents are included; bags still in mail are not carried ready upgrades.

## 8. Route safely and send manually

Use two enabled same-realm members and inexpensive transferable items.

1. Check `/rq routing`, `/rq reserves` and `/rq material-totals`.
   Configure explicit item categories/ordered recipients if needed.
2. Open `/rq mail` at a mailbox. Exact uncovered groceries and bag priorities
   must preserve sender needs/reserves.
3. Check retained profession surplus routes, Mage Light Feather/`Scroll:` rules
   and tooltip-confirmed locked items for Rogues when suitable test items exist.
4. Click Attach item/all. It may fill recipient and attach the exact quantity,
   but **must never click Send**. Verify recipient, subject, binding and quantities
   before manually sending.
5. Change recipient/draft, close mailbox, use a nonempty cursor or enter combat.
   The helper must stop rather than retry or guess.
6. `/rq shipments` records eligible observed sends conservatively. Confirm only
   a send you verified succeeded. Do not enable automatic confirmation before
   completing the detailed mail smoke test.
7. Open recipient mailbox and collect manually. Pending/inbox coverage must not
   double count, and ambiguous/stale/returned evidence must remain uncertain.

**Expected:** no send/collect automation, no bank attachment, no use of draft
stock as coverage and no cross-realm/cross-faction assumptions.

## 9. Verify removal of tracking lists

Activity, Ledger, History, Session tasks, pins and main-lead controls should be
absent. Old commands should not create records. Latest wallet snapshots still
appear on Roster; they are not income or profit.

## 10. Make a fresh configuration export

**Old-schema configuration exports require a new post-upgrade export.**
They are neither schema 19 import files nor backups of observations.

1. After a successful upgrade, `/rq export` creates current configuration.
2. `/rq import` previews replacement. Inspect main/roles/registration, retained
   settings and supplies/intent. No retired data appears.
3. Cancel and confirm nothing changed. Preview again and apply only with the
   explicit confirmation token when ready.
4. Verify snapshots, recipes, inventory, rested evidence and mail
   ledgers are unchanged. Omitted members retain observations but become pending
   with default intent/empty supplies, as warned by the preview.
5. Test `/rq import-rollback` before reload/logout; current observations stay
   current. Later configuration edits also revert. Reload/logout clears rollback.
6. A test old-schema export or corrupted string must be rejected without mutation.

Transfer limits (200 characters/256 KiB) are document safety bounds, not limits
on adding characters to the roster. Keep actual SavedVariables backups.

## Release decision

Record results and blockers rather than checking these steps off from memory.
The package needs automated tests/lint/syntax/format checks, runtime-only archive
inspection and installation/reload/restart acceptance. Removed guide tooling is
not part of validation and guides/next-20 are no longer roadmap items.

Extended client API cases and optional Auctionator compatibility
remain separate evidence gaps, not reasons to restore retired functionality.
**0.0.38 is packaged and passes automated checks; no client-tested claim is made.**
