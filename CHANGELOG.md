# Changelog

## 0.0.1 - Compatibility spike

- Added an explicit-load-order Lua 5.1 addon skeleton.
- Added guarded client/character API probes and `/rq diag`.
- Added basic schema-1 SavedVariables initialization and login/logout/rescan
  snapshots, preserving unsupported or malformed databases without writing.
- Added dependency-free mocked tests, Luacheck and StyLua configuration, and
  installation/manual-validation documentation.
- Live Forever API compatibility, interface metadata, reload behavior, and
  full-restart persistence remain unverified.
