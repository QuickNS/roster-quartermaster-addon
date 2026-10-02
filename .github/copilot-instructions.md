# Roster Quartermaster Copilot Instructions

- Target World of Warcraft: Forever.
- Use Lua 5.1-compatible syntax unless the client proves otherwise.
- Use the global namespace `RQ`; do not introduce unrelated globals.
- Put every direct WoW API call behind `RQ.Api`.
- Keep recommendation, routing, estimation, and checklist logic pure and testable.
- Do not automate protected actions such as combat, crafting, mailing, or auctions.
- Use item IDs and character GUIDs as canonical identifiers.
- Treat names as display values that may change.
- Treat offline character state as timestamped snapshots.
- Label inferred rested XP as estimated.
- Every SavedVariables schema change requires an idempotent migration.
- UI modules must not contain planning business logic.
- Capability-check beta APIs and degrade gracefully.
- Add or update tests whenever planning logic changes.
- Do not add external dependencies without documenting why native code is insufficient.
