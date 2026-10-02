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
- Addon loading, other live Forever APIs, reload behavior, and full-restart
  persistence remain unverified.
