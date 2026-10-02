# Changelog

## 0.0.5 - Rested estimation and play-next recommendations

- Added Today recommendations with deterministic ranking, two/three reasons,
  explicit confidence, and persistent pin/unpin overrides.
- Implemented hard pin, near-rested-cap, main-lead, and manual-blocker priorities,
  plus configurable weighted factors and previous-character session history.
- Added offline rested estimates from complete logout baselines; live API values
  remain observed, and unavailable evidence remains unknown.
- Added bounded, separate inn/outside login calibration with prediction comparison,
  unchanged-XP/uncapped sampling rules, and manual perk/multiplier reset.
- Added a Planning tab for provisional rates/caps, level policy, member multipliers,
  and manual blocker/dungeon signals. No unverified Legacy/quest scan is assumed.
- Added transactional schema-4 planning/calibration/session migration, independent
  per-character state copies, and pin/session rekeying on GUID promotion.
- Added `/rq today [text]`, `/rq planning`, `/rq pin <name|slot|ID>`, `/rq unpin`,
  and calibration diagnostics. The dashboard initially opens Today.
- Rested mechanics and new native UI behavior still require Forever client testing.

## 0.0.4 - Roster dashboard and minimap launcher

- Added a native minimap button with hover tooltip to open/close the dashboard.
- Added movable Roster/Settings tabs, scrollable character cards, and saved window
  position with Close/Escape and reset controls.
- Added main/role configuration, explicit unlink/relink, and offline-member
  controls without logging into or scanning those characters.
- Added age/stale/incomplete labels and retained last-observed offline rested XP
  labeling; no offline estimation is claimed yet.
- Added schema-3 window settings migration, preserving prior links and snapshots.
- Kept text commands as UI fallback, guarded combat-time opening, and avoided
  rebuilding hidden panels or replacing focused name-edit drafts.
- Added mocked native frame, minimap, configuration, and migration tests.
- `/rq` now toggles the dashboard; `/rq diag` remains the diagnostic command and
  `/rq roster text` retains chat roster output.
- New native UI behavior and persistence require in-client validation.

## 0.0.3 - Registration command fallback

- Fixed add/link/ignore commands and login callbacks crashing when the
  registration UI module is absent, leaving slash commands in the chat input.
- Moved registration orchestration into the snapshot service so slash commands
  and UI buttons share the same behavior without requiring the UI to load.
- Added a visible incomplete-installation warning and UI module status in diagnostics.
- Added regression tests reproducing the reported `RegistrationPrompt` nil error.
- SavedVariables remain at schema 2; no reset or migration is required.

## 0.0.2 - Database and snapshots

- Added transactional, idempotent schema-1 to schema-2 migration with validation
  of consumed nested data and roster links.
- Added account-wide timestamped character snapshots and independent per-character
  copies, GUID rename reconciliation, and normalized name/realm fallback promotion.
- Added explicit add/link/ignore registration, editable provisional labels,
  a combat-safe native prompt, and slash-command fallback.
- Added money, location, equipped bag-capacity, and profession skill adapters.
- Added targeted event updates with 0.25-second coalescing, synchronous logout
  capture, and incomplete-section markers that preserve older observations.
- Added roster/slot diagnostics with timestamps and stale-state warnings.
- Added migration, registration, and snapshot tests, plus schema and upgrade docs.
- New APIs, events, UI, and migration still require Forever client testing; the
  previously reported smoke-test pass applies to version 0.0.1.

## 0.0.1 - Compatibility spike

- Added an explicit-load-order Lua 5.1 addon skeleton.
- Added guarded client/character API probes and `/rq diag`.
- Added basic schema-1 SavedVariables initialization and login/logout/rescan
  snapshots, preserving unsupported or malformed databases without writing.
- Added dependency-free mocked tests, Luacheck and StyLua configuration, and
  installation/manual-validation documentation.
- Set interface metadata to `16001` from the user-reported Forever `1.60.1`,
  build `70170` (Oct 1 2026).
- Recorded the user's 2026-10-02 smoke-test pass covering installation,
  diagnostics/rescan, reload, and full-restart persistence. Detailed API/event
  results and extended failure cases remain individually unconfirmed.
