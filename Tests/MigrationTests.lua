return function(h)
    local test, equal = h.test, h.equal

    test("schema one migration preserves nested configuration and does not mutate its input", function()
        RQDB = { schemaVersion = 1, settings = { custom = { 42 } }, policies = { staleSnapshotHours = 12 } }
        RQCharDB = {
            schemaVersion = 1,
            identity = { guid = "Player-Test-1" },
            snapshot = { level = 17, xp = 12, wasResting = false, lastSeen = 123, lastLogout = 100 },
        }
        local oldAccount, oldCharacter = RQDB, RQCharDB
        h.loadAddon()
        assert(RQ.Database.Initialize())
        equal(RQDB.schemaVersion, 19)
        equal(RQDB.settings.custom[1], 42)
        equal(RQDB.policies.staleSnapshotHours, 12)
        equal(RQCharDB.snapshot.level, 17)
        equal(RQCharDB.snapshot.wasResting, false)
        equal(RQCharDB.snapshot.lastLogout, 100)
        equal(RQCharDB.inventory.bank.complete, false)
        equal(RQCharDB.inventory.bank.scannedAt, 0)
        equal(RQCharDB.recipes.complete, false)
        equal(oldAccount.schemaVersion, 1)
        equal(oldAccount.plannedRoster, nil)
        equal(oldCharacter.snapshot.sections, nil)
        RQDB.settings.custom[1] = 99
        equal(oldAccount.settings.custom[1], 42)
    end)

    test("schema sixteen retires features atomically while preserving dynamic roster and retained data", function()
        h.fakeCharacter()
        h.loadAddon()
        h.emit("PLAYER_LOGIN")
        assert(RQ.Database.Register("add"))
        local id = RQ.Database.activeId
        assert(RQ.Database.SetRole(id, "TANK"))
        assert(RQ.Database.SetMain(id))
        assert(RQ.Database.SetMain(id))
        local record = RQ.Database.Current()
        record.supplies.needs[5498] = 2
        record.supplies.goals[197] = { recipeId = 3844, targetSkill = 100 }
        record.professionIntent.planned[197] = true
        record.inventory.bags.items[5498] = 1
        record.inventory.bank.items[2589] = 20
        record.inventory.mail.items[2592] = 10
        local alt = RQ.Util.Copy(record)
        alt.identity.guid, alt.registration = "Player-Alt", "pending"
        RQDB.characters["Player-Alt"] = alt
        assert(RQ.Database.Register("add", "Player-Alt"))
        assert(RQ.Database.SetRole("Player-Alt", "HEALER"))
        RQCharDB = RQ.Util.Copy(record)
        local expectedAccount, expectedChar = RQ.Migrations.Prepare(RQDB, RQCharDB)
        assert(expectedAccount and expectedChar)
        local old, oldChar = RQ.Util.Copy(expectedAccount), RQ.Util.Copy(expectedChar)
        old.schemaVersion, oldChar.schemaVersion = 15, 15
        old.plannedRoster = { warrior = { claimedBy = id }, unclaimed = { plannedName = "Unused" } }
        old.progress = { characters = { [id] = { perks = { retired = true } } } }
        old.settings.gear = { enabled = true, customProfiles = { retired = true } }
        old.roster[id].slotId, old.roster[id].plannedName = "warrior", "Old name"
        old.roster["Player-Alt"].slotId = "priest"
        oldChar.progress, oldChar.plannedRoster = {}, {}
        old.checklists = { members = { [id] = { decisions = {} } } }
        old.checklists.members[id].decisions["dungeon-review"] = { state = "dismiss", signature = "old" }
        old.checklists.members[id].decisions["progress:trial"] = { state = "complete", signature = "old" }
        local migrated, mirror, err = RQ.Migrations.Prepare(old, oldChar)
        assert(migrated and mirror, err)
        local function same(actual, expected)
            equal(type(actual), type(expected))
            if type(expected) ~= "table" then
                equal(actual, expected)
                return
            end
            for key, value in pairs(expected) do
                same(actual[key], value)
            end
            for key in pairs(actual) do
                assert(expected[key] ~= nil, "Unexpected migrated field: " .. tostring(key))
            end
        end
        same(migrated, expectedAccount)
        same(mirror, expectedChar)
        local second, secondChar = RQ.Migrations.Prepare(migrated, mirror)
        same(second, migrated)
        same(secondChar, mirror)
        equal(old.schemaVersion, 15)
        equal(oldChar.schemaVersion, 15)
        equal(old.roster[id].slotId, "warrior")
        equal(old.settings.gear.enabled, true)
        equal(old.plannedRoster.unclaimed.plannedName, "Unused")
        equal(old.checklists.members[id].decisions["dungeon-review"].state, "dismiss")
    end)

    test("malformed retired settings do not block migration or seed roster members", function()
        h.loadAddon()
        local account = assert(RQ.Migrations.Prepare({
            schemaVersion = 15,
            plannedRoster = { warrior = { plannedName = false, claimedBy = "Player-Missing" } },
            progress = false,
            settings = { gear = false },
        }, nil))
        equal(account.plannedRoster, nil)
        equal(account.progress, nil)
        equal(account.settings.gear, nil)
        equal(next(account.roster), nil)
        equal(next(account.characters), nil)
        local legacy = assert(RQ.Migrations.Prepare({ schemaVersion = 1 }, nil))
        equal(legacy.plannedRoster, nil)
        equal(next(legacy.roster), nil)
    end)

    test("corrupt nested state rejects both databases without partial migration", function()
        h.loadAddon()
        local cases = {
            { characters = { ["Player-X"] = false } },
            { characters = { ["Player-X"] = { snapshot = { xp = "bad" } } } },
            { characters = { ["Player-X"] = { snapshot = { sections = { money = false } } } } },
            { characters = { ["Player-X"] = { registration = false } } },
            { characters = { ["Player-X"] = { registration = "member" } } },
            { policies = { staleSnapshotHours = -1 } },
            { policies = { staleSnapshotHours = 0 / 0 } },
        }
        for index, account in ipairs(cases) do
            account.schemaVersion = 1
            local original = { schemaVersion = 1, snapshot = { level = 25 } }
            local migrated, character, err = RQ.Migrations.Prepare(account, original)
            assert(migrated == nil, "unexpected successful migration for corrupt case " .. index)
            equal(character, nil)
            assert(err:find("original data preserved", 1, true))
            equal(account.schemaVersion, 1)
            equal(original.snapshot.sections, nil)
        end
    end)

    test("current-schema partial records are repaired conservatively", function()
        RQDB = { schemaVersion = 3, characters = { ["Player-Old"] = { snapshot = { lastSeen = 1 } } } }
        RQCharDB = { schemaVersion = 3 }
        h.loadAddon()
        assert(RQ.Database.Initialize())
        local record = RQDB.characters["Player-Old"]
        equal(record.registration, "pending")
        equal(record.inventory.mail.complete, false)
        equal(record.snapshot.lastSeen, 1)
        equal(record.snapshot.level, nil)
        equal(RQCharDB.snapshot.level, nil)
    end)

    test("malformed professions and inventory metadata disable initialization", function()
        h.loadAddon()
        for _, character in ipairs({
            { snapshot = { professions = { [186] = { name = "Mining", skill = "bad", maxSkill = 150 } } } },
            { inventory = { bank = { scannedAt = -1 } } },
            { recipes = { complete = "yes" } },
            { snapshot = { sections = { rested = { observedAt = false } } } },
        }) do
            local account, char, err = RQ.Migrations.Prepare(nil, character)
            equal(account, nil)
            equal(char, nil)
            assert(err)
        end
    end)
end
