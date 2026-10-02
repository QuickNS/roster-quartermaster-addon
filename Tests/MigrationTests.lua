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
        equal(RQDB.schemaVersion, 2)
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

    test("migration is idempotent and preserves edited or deliberately empty slots", function()
        h.loadAddon()
        local account, character = RQ.Migrations.Prepare(nil, nil)
        equal(#RQ.Util.Keys(account.plannedRoster), 5)
        account.plannedRoster.druid.plannedName = "Luna Tick"
        account.plannedRoster.rogue = nil
        local second, char = RQ.Migrations.Prepare(account, character)
        equal(second.plannedRoster.druid.plannedName, "Luna Tick")
        equal(second.plannedRoster.rogue, nil)
        equal(char.schemaVersion, 2)
        second.plannedRoster = {}
        local third = RQ.Migrations.Prepare(second, char)
        equal(next(third.plannedRoster), nil)
        equal(RQ.DefaultRoster.druid.plannedName, "Kit Cat")
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
            { plannedRoster = { warrior = { plannedName = false } } },
            { plannedRoster = { warrior = { claimedBy = "Player-X" } } },
            { roster = { ["Player-X"] = { slotId = "missing" } } },
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
        RQDB = { schemaVersion = 2, characters = { ["Player-Old"] = { snapshot = { lastSeen = 1 } } } }
        RQCharDB = { schemaVersion = 2 }
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
