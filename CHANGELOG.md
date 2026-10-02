# Changelog

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
