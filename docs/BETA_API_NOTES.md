# Forever beta API notes

## Evidence status for 0.0.38

`0.0.38` uses schema 19. The minimap launcher uses standard native tracking
border/highlight textures and optional `CreateMaskTexture`/`AddMaskTexture`.
If masking fails or is absent, a round native border remains.

Dragging reads `GetCursorPosition`, `Minimap:GetEffectiveScale`, `GetCenter`,
`GetWidth` and `GetHeight` inside the adapter. Finite geometry is required;
unavailable reads stop the drag and report an error without replacing the last
saved position. Cursor coordinates are divided by the minimap's effective scale.
The angle is saved after release/hide/combat/logout, not continuously on idle.
Collectors retain ownership after reparenting or reanchoring the button.
Actual Forever texture rendering and mouse-event ordering still need validation.
Capability detection, passing mocks and older user reports are not certification
of this candidate or every API contract. Record exact client version, build,
interface, locale and event/API observations when testing.

Earlier evidence, retained only as context:

| Evidence | Scope |
| --- | --- |
| 2026-10-02 user report | 0.0.1 install, diagnostics/rescan, reload and restart smoke test |
| Reported client | Forever 1.60.1 / build 70170 / interface 16001, build date Oct 1 2026 |
| 2026-10-04 user report | 0.0.14 carried-item search working |
| Subsequent user reports | Basic bank scanning and mail tracking working |

No individual pass is implied for API return shapes, every event, partial/error
paths, combat, migration to schema 19 or the current visual workspace.
Use [MANUAL_TEST_PLAN.md](MANUAL_TEST_PLAN.md) and
[USER_ACCEPTANCE_TESTS.md](USER_ACCEPTANCE_TESTS.md) for current checks.

## Removed API consumers

The runtime no longer provides LOW discard highlights, gear scoring/arrows/
tooltip advice/editor, dungeon or Legacy tracking, or guide/next-20 leveling.
Planned roster slots, links and presets are also removed. Their old API probes,
UI contracts, profile data and guide compiler/import workflow are not release
requirements or gated future features.

Do not remove retained item tooltip/metadata access merely because gear advice
is gone: recipe/bag capacity, binding and locked-container routing still need
their own evidence. Likewise, manual `dungeonReady` is still a priority signal,
not an API-backed dungeon tracker.

## Adapter and lifecycle boundaries

All direct native calls belong in `RQ.Api`, including event/frame creation,
chat, slash registration, item metadata, inventory movement on explicit clicks
and optional graphics. Guard missing/restricted functions and invalid return
shapes; an existing symbol is not proof of a supported contract.

Diagnostics distinguish unavailable, failed and registered-but-unobserved
events. Event registration alone does not prove delivery. Modern container
methods are preferred where supported; legacy fallback must not hide a failed
modern call by inventing valid data.

Login/rescan captures identity and current sections. XP/resting, location, money,
bag and skill events refresh relevant sections with debouncing; recipe-window,
bank and mail events have their own coherence checks. Logout invalidates queued
work and preserves safe final observations. No retired bag-overlay polling is
required.

Verify these event groups rather than assuming registration proves behavior:

- `ADDON_LOADED`, `PLAYER_LOGIN`, `PLAYER_LOGOUT`, `PLAYER_ENTERING_WORLD`.
- `PLAYER_LEVEL_UP`, `PLAYER_XP_UPDATE`, `UPDATE_EXHAUSTION`,
  `PLAYER_UPDATE_RESTING`.
- `PLAYER_MONEY`, zone/subzone changes and loading transitions.
- Bag updates, bank open/close/slot changes and item metadata availability.
- Skill changes, owned profession window opening and recipe list updates.
- Mail open/close/update/send-success/send-failure and observed manual takes.
- Combat entry/exit for safe UI hiding and registration behavior.

Missing timer support must remain explicit and use guarded immediate refresh
where supported. Rescan after delayed level/API state changes. Successful
initialization does not prove that the client wrote SavedVariables to disk.

## Identity, progression and rested evidence

GUIDs are canonical; names are display values. For the observed Forever 1.60.x /
interface 16001 contract, `UnitNameUnmodified("player")` can expose first name
and surname, not the usual name/realm pair. Preserve the separately observed
realm and avoid duplicating already-full names. Other versions require their
own contract checks. A manual full-name override is explicit configuration.

A successful `GetXPExhaustion` returning `nil` is provisionally interpreted as
zero rested XP. Missing/failing/restricted calls mean unknown instead; verify
this distinction live. Zero XP or zero rested XP is valid, but a zero XP maximum
during logout teardown must not destroy a complete earlier baseline.

Offline rested is estimated from timestamped logout evidence under configurable
rates/caps. Cached fallback logout samples are lower confidence and cannot teach
rates. Perk-driven rate changes remain manual; there is no Legacy API dependency.
Resource blockers and dungeon readiness are user inputs, not observed quests.

## Native professions and recipe groceries

Only ready owned profession windows provide recipe evidence. Linked/guild
windows are not the current character's learned recipes. Independently cache
per-profession scans; incomplete reads keep older evidence with errors.

Verify native skill-line classification, skill/cap, learned status, difficulty,
reagent completeness, skill-up count and output/acquisition metadata. Orange
means currently optimal difficulty, not guaranteed skill-ups to an arbitrary
target. Unknown/alternative reagents cannot become guessed requirements.

One-craft groceries derive from eligible learned orange recipes below observed
skill cap. Goal overrides, stock floors and bag-crafting materials use existing
pure allocation logic. No external guide, approval record or next-20 route
supplies missing facts.

The profession-lag ceiling 300 and `5 * level` benchmark are assumptions.
Profession-pair advice uses reference relationships and observed same-realm
coverage; it does not certify trainer availability, Forever recipes or equipment.
Saved intended profession choices are not learned skill/provider evidence.

## Item names, search and bag planning

Item IDs remain canonical. Name/icon resolution may use observed links and
guarded modern/legacy item APIs, then request cold-cache data and refresh on
availability. Missing metadata stays an ID/unknown label, not a guessed name.
Name arrival cannot change stock. Copy reports must be reopened to reflect
later metadata.

Search includes observed bags, personal bank and mail with per-source ownership,
counts and timestamps. Discovery includes disabled registered members, reserved
or bound items and other realms; it does not authorize their transfer.

Bag planning needs observed general-purpose output capacity, binding, quantities
and equipped regular-bag slots. Do not infer capacity from recipe names or supply
a guessed four-bag layout if container constants are missing. Ready-bag allocation
uses carried stock; bank/mail coverage is not evidence of an equippable carried
bag. Unknown outputs, variable quantities and unsupported containers stay blocked.

## Personal-bank coherence

Scan personal-bank containers only while accessible. Pair stable bag and bank
observations so a deposit/withdrawal cannot leave the same item credited in both.
Early close, unsupported tabs, missing slots or changing scans preserve uncertainty.
Older unconfirmed snapshots remain discovery-only until a coherent visit.

Owner bank materials can cover groceries with an explicit withdrawal prerequisite.
Bank-transfer suggestions require withdrawal and a fresh proposal, not phantom
recipient credit. No account/guild-bank access or remote bank refresh is assumed.
Basic older user reports do not cover rapid transfers, bank capacity extremes
or interrupted scans in 0.0.34.

## Routing and explicit mail attachment

`UnitFactionGroup("player")` supplies the canonical Alliance/Horde faction.
Neutral, missing and restricted results do not establish a new tradable faction.
Ruleset inference accepts only an explicit PvE/PvP token in `GetRealmName()`;
it does not use the current PvP flag, War Mode or realm-list selection. On
unlabelled realms the user must confirm ruleset in Manage roster. This fallback
and native faction need live Forever verification on both rulesets/factions.

All mail, bag-transfer/crafting, pending-shipment and profession-provider paths
share a known matching ruleset/faction/realm predicate. Existing observations
are not migrated by guessing faction from race. Cross-realm sending is still
unverified and blocked even if the combination matches.

Cooking/Fishing assignments are GUID-keyed per combination. Raw meat/fish uses
an explicit Classic ID allowlist, including raw fish that can also be used by
other professions. Sender needs/reserves are retained; prepared food and
unknown beta IDs are not name-classified. Explicit `food` category membership
opts an unknown ID into this priority. Assignment alone does not prove skills.

Recipe/material routing retains native classification and binding safeguards.
Uncommon BoE equipment is only a disenchanting candidate; there is no remaining
gear score or upgrade-protection claim. Sender reserves/needs take priority.
Cooking/Fishing ingredients then precede other recipient groceries and explicit
surplus orders; other items retain the existing routing priorities.

Mage routing uses item ID 17056 for Light Feathers and the exact observed `Scroll:`
prefix for scrolls. The latter is a narrow name rule, not a universal localized
scroll classifier. Unknown names and `Scroll of ...` do not match it.

Rogue routing requires per-instance `C_TooltipInfo.GetBagItem` evidence and the
client's localized locked label. Requiring unlocking is distinct from the
container's temporary busy `isLocked` state. Unknown tooltip evidence is not
cached as a new fact; Attach must select/recheck the actually locked instance.
No Lockpicking skill guarantee is made.

Native attachment calls run only after an explicit click with open mailbox,
verified full recipient, same ruleset/faction/realm, known non-combat state, empty cursor and
compatible draft/free slots. Revalidate immediately before moving stock; stop
on changing draft/API failures and report partial progress. Opening a report
never attaches anything. Sending/collection remain manual.

## Shipment and inbox contract

Default observation mode records eligible send attempts/success without claiming
delivery. Passive capture must not infer a draft from old cached data if the
native draft cleared before the hook read it. COD and unresolved/non-roster
recipients cannot create usable credit.

Only after verifying actual successful sends can users confirm specific
observations. Automatic confirmation is opt-in with `/rq mail-tracking verify`
for the exact version/build/interface; any build change invalidates it.
Do not enable it merely because mocked send-success tests pass.

Inbox coverage requires stable complete loaded inbox/bag observations and
conservative unique reconciliation. Collection needs matching observed manual
takes, removed attachments and carried gains. Duplicates, returns, partial
loads, stale evidence or interrupted operations stay uncertain.

Confirmed pending/verified inbox quantities are provisional material coverage,
not carried stock, donor stock or proof of delivery. Cached active-character
mail must be reverified after login. Verify duplicate matching, partial collection,
COD, returns, failed sends and mailbox close/reopen in the client.

## Optional Auctionator craft costs

The adapter capability-checks `Auctionator.API.v1.GetAuctionPriceByItemID`,
passing caller ID `RosterQuartermaster` and the reagent item ID. Unit prices
are interpreted as copper and multiplied by required quantities in a pure helper.
Missing/invalid prices and API failures surface as unavailable; partial totals
are never presented as full craft costs. Quotes are restricted to the active
realm/ruleset/faction market and described as cached estimates, not live offers.
Mock tests cover the contract; live Forever/Auctionator compatibility is pending.
No third-party library is bundled or required.

Activity/counter/calendar consumers and generated session lists are removed.
The ordinary GetMoney snapshot remains; it is not a financial ledger.

## UI and persistence

Four native tabs are Roster / Bags and Inventory / Professions / Settings. Current UI needs
client checks for grocery columns/filters, long names, scroll preservation,
roster size, inventory pages, compact groceries, combat hiding and text fallbacks.
No UI should offer retired slots, advisor, highlights, progress or guides.

Missing combat-state support means no registration popup/dashboard opening.
Missing minimap/tooltip/keyboard helpers should degrade to text or basic controls,
not disable retained planning. Closed/hidden views should not rebuild on every
snapshot update.

Schema 16 removes retired state only, preserving registered characters,
main/role/retained settings and observations. Both roots validate before
publication; malformed/future schemas preserve originals and disable writes.
Back up account and per-character SavedVariables with the client closed.
Old-schema exports require a fresh post-upgrade export; configuration transfer
does not back up snapshots or prove disk persistence.

Record reload and full clean-exit/restart outcomes separately. Do not describe
0.0.38 as durable or client-tested until those checks have actually passed.
