# Changelog

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
