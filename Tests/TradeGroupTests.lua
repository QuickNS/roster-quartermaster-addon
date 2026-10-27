return function(h)
    local test, equal, contains = h.test, h.equal, h.contains
    local active, now = "Player-Test-1", 123456789

    local function start(native)
        h.fakeCharacter()
        local frames = native and assert(loadfile("Tests/fixtures/Frames.lua"))()()
        h.loadAddon()
        if frames then
            frames.Emit("PLAYER_LOGIN")
        else
            h.emit("PLAYER_LOGIN")
        end
        assert(RQ.Database.Register("add"))
        return frames
    end

    local function member(id, ruleset, faction)
        local record = RQ.Util.Copy(RQ.Database.Current())
        record.identity = {
            guid = id,
            fullName = id,
            realm = "TestRealm PVE",
            ruleset = ruleset,
            faction = faction,
            class = "MAGE",
        }
        record.registration = "pending"
        record.supplies = { needs = {}, goals = {} }
        record.inventory.bags = {
            complete = true,
            scannedAt = now,
            items = {},
            tradable = {},
            details = {},
            equipped = { [1] = 16, [2] = 16, [3] = 16, [4] = 16 },
        }
        RQDB.characters[id] = record
        assert(RQ.Database.Register("add", id))
        return record
    end

    local function stock(record, item, count, tradable)
        local bags = record.inventory.bags
        bags.complete, bags.scannedAt = true, now
        bags.items[item], bags.tradable[item] = count, tradable or count
        bags.details[item] = { name = "Localized ingredient", classId = 7, subclassId = 8 }
    end

    local function report()
        return RQ.SuppliesService.Evaluate(RQDB, active, now)
    end

    test("trade identity observes faction and explicit realm ruleset without guessing normal realms", function()
        start()
        local identity = RQ.Api.GetCharacterIdentity()
        equal(identity.faction, "Horde")
        equal(identity.ruleset, "PVE")
        equal(identity.rulesetSource, "realm-name")
        for _, realm in ipairs({ "Normal", "Unknown", "pvpserver", "Realm PvP PvE" }) do
            equal(RQ.Character.RulesetFromRealm(realm), nil)
        end
        equal(RQ.Character.RulesetFromRealm("Classic Beta PvP"), "PVP")
        equal(RQ.Character.RulesetFromRealm("Classic Beta PvE"), "PVE")
        _G.UnitFactionGroup = function()
            return "Neutral"
        end
        equal(RQ.Character.TradeGroup(RQ.Api.GetCharacterIdentity()), nil)
        _G.UnitFactionGroup = function()
            error("unavailable")
        end
        equal(RQ.Api.GetCharacterIdentity().faction, nil)
        contains({ RQ.Api.GetCapabilities().UnitFactionGroup }, "error:")
        _G.GetRealmName = function()
            return "Unlabelled"
        end
        equal(RQ.Api.GetCharacterIdentity().ruleset, nil)
    end)

    test("trade eligibility requires every boundary and rejects unknown matching values", function()
        start()
        local source = RQ.Database.Current().identity
        local target = RQ.Util.Copy(source)
        equal(RQ.Character.CanTrade(source, target), true)
        for field, value in pairs({ ruleset = "PVP", faction = "Alliance", realm = "Other" }) do
            local altered = RQ.Util.Copy(target)
            altered[field] = value
            equal(RQ.Character.CanTrade(source, altered), false)
            altered[field] = nil
            equal(RQ.Character.CanTrade(source, altered), false)
            equal(RQ.Character.CanTrade(altered, altered), false)
        end
    end)

    test("manual rulesets persist through rescans but reset after a realm change", function()
        start()
        _G.GetRealmName = function()
            return "Unlabelled"
        end
        assert(RQ.SnapshotService.Refresh())
        equal(RQ.Database.Current().identity.ruleset, nil)
        assert(RQ.Database.SetRuleset(active, "PVP"))
        equal(RQCharDB.identity.rulesetSource, "manual")
        assert(RQ.SnapshotService.Refresh())
        equal(RQ.Database.Current().identity.ruleset, "PVP")
        equal(RQ.Database.SetRuleset(active, "RP"), false)
        _G.GetRealmName = function()
            return "Another Unlabelled"
        end
        assert(RQ.SnapshotService.Refresh())
        equal(RQ.Database.Current().identity.ruleset, nil)
        _G.GetRealmName = function()
            return "Classic Beta PvE"
        end
        assert(RQ.SnapshotService.Refresh())
        equal(RQCharDB.identity.ruleset, "PVE")
        equal(RQ.Database.SetRuleset(active, "PVP"), false)
    end)

    test("schema seventeen migration retains old snapshots without inventing faction and is idempotent", function()
        start()
        local old, oldChar = RQ.Util.Copy(RQDB), RQ.Util.Copy(RQCharDB)
        old.schemaVersion, oldChar.schemaVersion = 16, 16
        old.settings.logistics.cooks = nil
        old.characters[active].identity.faction = nil
        old.roster[active].faction = nil
        oldChar.identity.faction = nil
        old.characters[active].supplies.needs[769] = 7
        local migrated, mirror = RQ.Migrations.Prepare(old, oldChar)
        assert(migrated and mirror)
        equal(migrated.schemaVersion, 19)
        equal(migrated.characters[active].supplies.needs[769], 7)
        equal(migrated.characters[active].snapshot.xp, old.characters[active].snapshot.xp)
        equal(RQ.Character.TradeGroup(migrated.characters[active].identity), nil)
        equal(next(migrated.settings.logistics.cooks), nil)
        local again, secondChar = RQ.Migrations.Prepare(migrated, mirror)
        equal(RQ.ConfigTransfer.Export(again), RQ.ConfigTransfer.Export(migrated))
        equal(secondChar.snapshot.xp, mirror.snapshot.xp)
        equal(old.schemaVersion, 16)
        equal(old.settings.logistics.cooks, nil)
        local invalid = RQ.Util.Copy(migrated)
        invalid.settings.logistics.cooks = false
        equal(RQ.Migrations.Prepare(invalid, mirror), nil)
        invalid = RQ.Util.Copy(migrated)
        invalid.characters[active].identity.faction = "guess"
        equal(RQ.Migrations.Prepare(invalid, mirror), nil)
    end)

    test("Cooking Fishing assignment is unique per combination and dormant for disabled or moved members", function()
        start()
        for _, ruleset in ipairs({ "PVE", "PVP" }) do
            for _, faction in ipairs({ "Alliance", "Horde" }) do
                local id = "Player-" .. ruleset .. "-" .. faction
                local record = member(id, ruleset, faction)
                assert(RQ.Database.SetCook(id))
                equal(RQ.LogisticsPolicies.Cook(RQDB, record.identity), id)
            end
        end
        equal(#RQ.Util.Keys(RQDB.settings.logistics.cooks), 4)
        local second = member("Player-Second", "PVE", "Horde")
        assert(RQ.Database.SetCook("Player-Second"))
        equal(RQDB.settings.logistics.cooks["PVE:Horde"], "Player-Second")
        equal(#RQ.Util.Keys(RQDB.settings.logistics.cooks), 4)
        assert(RQ.Database.Register("ignore", "Player-Second"))
        equal(RQ.LogisticsPolicies.Cook(RQDB, second.identity), nil)
        assert(RQ.Database.Register("add", "Player-Second"))
        equal(RQ.LogisticsPolicies.Cook(RQDB, second.identity), "Player-Second")
        second.identity.ruleset = "PVP"
        equal(RQ.LogisticsPolicies.Cook(RQDB, RQ.Database.Current().identity), nil)
        second.identity.ruleset = "PVE"
        assert(RQ.Database.SetCook("Player-Second"))
        equal(RQDB.settings.logistics.cooks["PVE:Horde"], nil)
        member("Player-Unknown")
        equal(RQ.Database.SetCook("Player-Unknown"), false)
    end)

    test("raw meat and fish prefer the cook over competing groceries but preserve sender reserves", function()
        start()
        local source = RQ.Database.Current()
        local cook = member("Player-Cook", "PVE", "Horde")
        local competitor = member("Player-First", "PVE", "Horde")
        assert(RQ.Database.SetCook("Player-Cook"))
        stock(source, 769, 12, 9)
        stock(source, 6291, 6)
        stock(source, 858, 4)
        source.supplies.needs[769] = 5
        competitor.supplies.needs = { [769] = 20, [6291] = 20, [858] = 4 }
        cook.supplies.needs[769] = 1
        local quantities = {}
        for _, proposal in ipairs(report().proposals) do
            quantities[proposal.itemId] = (quantities[proposal.itemId] or 0) + proposal.count
            if proposal.itemId == 858 then
                equal(proposal.characterId, "Player-First")
            else
                equal(proposal.characterId, "Player-Cook")
                contains({ proposal.reason }, "Cooking/Fishing")
            end
        end
        equal(quantities[769], 7)
        equal(quantities[6291], 6)
        equal(quantities[858], 4)
        source.inventory.bags.tradable[769] = 0
        for _, proposal in ipairs(report().proposals) do
            assert(proposal.itemId ~= 769)
        end
    end)

    test("unknown beta items are not classified by name and explicit food classification supports them", function()
        start()
        member("Player-Cook", "PVE", "Horde")
        assert(RQ.Database.SetCook("Player-Cook"))
        local source = RQ.Database.Current()
        stock(source, 999999, 8)
        source.inventory.bags.details[999999].name = "Raw Special Fish"
        equal(#report().proposals, 0)
        RQDB.settings.logistics.categories.food.items[999999] = true
        local proposals = report().proposals
        equal(#proposals, 1)
        equal(proposals[1].characterId, "Player-Cook")
        equal(proposals[1].count, 8)
    end)

    test("the cook keeps ingredients rather than bouncing them to another character", function()
        start()
        local other = member("Player-Other", "PVE", "Horde")
        other.supplies.needs[769] = 30
        assert(RQ.Database.SetCook(active))
        stock(RQ.Database.Current(), 769, 10)
        equal(#report().proposals, 0)
        assert(RQ.Database.SetCook(active))
        equal(report().proposals[1].count, 10)
    end)

    test("mail paths exclude wrong and unknown trade groups despite explicit recipient priority", function()
        start()
        local source = RQ.Database.Current()
        for _, item in ipairs({ 769, 2589, 17056, 2770 }) do
            stock(source, item, 20)
        end
        source.inventory.bags.details[2589] = { classId = 7, subclassId = 5 }
        source.inventory.bags.details[2770] = { classId = 7, subclassId = 7 }
        for index, pair in ipairs({ { "PVP", "Horde" }, { "PVE", "Alliance" }, {} }) do
            local id = "Player-Bad-" .. index
            local other = member(id, pair[1], pair[2])
            other.supplies.needs = { [769] = 30, [2589] = 30, [2770] = 30 }
            other.snapshot.professions[197] = { name = "Tailoring", skill = 50, maxSkill = 75 }
            other.snapshot.professions[164] = { name = "Blacksmithing", skill = 50, maxSkill = 75 }
            RQDB.settings.logistics.categories.food.recipients[index] = id
        end
        RQDB.settings.logistics.categories.food.items[769] = true
        equal(#report().proposals, 0)
        local good = member("Player-Good", "PVE", "Horde")
        good.supplies.needs[2589] = 5
        assert(RQ.Database.SetCook("Player-Good"))
        for _, proposal in ipairs(report().proposals) do
            equal(proposal.characterId, "Player-Good")
        end
        assert(#report().proposals >= 3)
        RQDB.settings.logistics.cooks["PVE:Horde"] = "Player-Bad-1"
        equal(RQ.LogisticsPolicies.Cook(RQDB, source.identity), nil)
        source.identity.faction = nil
        equal(#report().proposals, 0)
    end)

    test("bag upgrades and profession coverage respect trade groups while local bags remain useful", function()
        start()
        local source = RQ.Database.Current()
        local other = member("Player-Other", "PVP", "Horde")
        source.inventory.bags.equipped = { [1] = 16, [2] = 16, [3] = 16, [4] = 16 }
        stock(source, 4496, 1)
        source.inventory.bags.details[4496] = { classId = 1, subclassId = 0, bagSlots = 6 }
        other.inventory.bags.equipped[1] = 0
        other.snapshot.professions[197] = { name = "Tailoring", skill = 50, maxSkill = 75 }
        equal(#report().bags.upgrades, 0)
        other.identity.ruleset = "PVE"
        equal(report().bags.upgrades[1].characterId, "Player-Other")
        other.identity.faction = "Alliance"
        equal(#report().bags.upgrades, 0)
        source.inventory.bags.equipped[1] = 0
        source.identity.faction = nil
        equal(report().bags.upgrades[1].kind, "equip")
        local advice = RQ.ProfessionAdvisor.Evaluate(RQDB, active, now)
        contains({ advice.blocker }, "Ruleset or faction unknown")
    end)

    test("mail address resolution never matches a different trade group with the same name", function()
        start()
        local good = member("Player-Good", "PVE", "Horde")
        local bad = member("Player-Bad", "PVP", "Horde")
        good.identity.fullName, bad.identity.fullName = "Same Name", "Same Name"
        equal(RQ.MailTracker.Resolve(RQDB, "Same Name", active), "Player-Good")
        good.identity.faction = "Alliance"
        equal(RQ.MailTracker.Resolve(RQDB, "Same Name", active), nil)
    end)

    test("configuration roundtrips Cooking Fishing assignments and rejects invalid group or dangling GUID", function()
        start()
        member("Player-Cook", "PVE", "Horde")
        assert(RQ.Database.SetCook("Player-Cook"))
        local config = assert(RQ.ConfigTransfer.Extract(RQDB))
        local decoded = assert(RQ.ConfigTransfer.Decode(assert(RQ.ConfigTransfer.Encode(config))))
        equal(decoded.settings.logistics.cooks["PVE:Horde"], "Player-Cook")
        equal(decoded.characters[active].identity.faction, "Horde")
        local account, character = RQ.Migrations.Prepare(nil, nil)
        local restored = assert(RQ.ConfigTransfer.Prepare(decoded, account, character))
        equal(RQ.LogisticsPolicies.Cook(restored, restored.characters[active].identity), "Player-Cook")
        decoded.settings.logistics.cooks["PVE:Horde"] = "Player-Missing"
        equal(RQ.ConfigTransfer.Encode(decoded), nil)
        decoded.settings.logistics.cooks = { ["PVE:Neutral"] = "Player-Cook" }
        equal(RQ.ConfigTransfer.Encode(decoded), nil)
    end)

    test("native manual ruleset control enables assignment only after faction is known", function()
        local frames = start(true)
        RQ.MainWindow.realm, RQ.MainWindow.group = "all", "all"
        _G.GetRealmName = function()
            return "Unlabelled"
        end
        assert(RQ.SnapshotService.Refresh())
        assert(RQ.MainWindow.Open("manage"))
        equal(frames.FindButton("Assign Cooking/Fishing").enabled, false)
        frames.Click(frames.FindButton("Ruleset: Unknown (next)"))
        h.flushTimers()
        equal(RQCharDB.identity.ruleset, "PVE")
        equal(frames.FindButton("Assign Cooking/Fishing").enabled, true)
        frames.Click(frames.FindButton("Ruleset: PVE (next)"))
        h.flushTimers()
        equal(RQCharDB.identity.ruleset, "PVP")
        frames.Click(frames.FindButton("Assign Cooking/Fishing"))
        h.flushTimers()
        equal(RQDB.settings.logistics.cooks["PVP:Horde"], active)
        _G.UnitFactionGroup = function()
            return "Neutral"
        end
        assert(RQ.SnapshotService.Refresh())
        h.flushTimers()
        equal(frames.FindButton("Assign Cooking/Fishing").enabled, false)
    end)

    test("native roster manager assigns and clears the selected group cook and switches separated views", function()
        local frames = start(true)
        member("Player-Cook", "PVE", "Horde")
        member("Player-Other", "PVP", "Alliance")
        assert(RQ.Database.SetMain("Player-Other"))
        assert(RQ.MainWindow.Open("roster"))
        equal(RQ.MainWindow.view.group, "PVE:Horde")
        equal(#RQ.MainWindow.view.rows, 2)
        equal(RQ.MainWindow.view.headline:find("Player-Other", 1, true), nil)
        RQ.MainWindow.selectedId = "Player-Cook"
        assert(RQ.MainWindow.Open("manage"))
        frames.Click(frames.FindButton("Assign Cooking/Fishing"))
        h.flushTimers()
        equal(RQDB.settings.logistics.cooks["PVE:Horde"], "Player-Cook")
        local assigned = RQ.RosterPanel.Build(RQDB, active, now)
        for _, card in ipairs(assigned.cards) do
            if card.id == "Player-Cook" then
                contains({ card.visual.badges }, "COOK / FISH")
            end
        end
        frames.Click(frames.FindButton("Clear Cooking/Fishing assignment"))
        h.flushTimers()
        equal(RQDB.settings.logistics.cooks["PVE:Horde"], nil)
        assert(RQ.MainWindow.Open("roster"))
        frames.Click(frames.FindButton("PVE:Horde"))
        h.flushTimers()
        equal(RQ.MainWindow.view.group, "PVP:Alliance")
        equal(#RQ.MainWindow.view.rows, 1)
        equal(RQ.MainWindow.view.rows[1].id, "Player-Other")
        equal(RQ.MainWindow.view.selectedId, "Player-Other")
        contains({ RQ.MainWindow.view.headline }, "Player-Other")
        assert(RQ.MainWindow.Open("manage"))
        frames.Click(frames.FindButton("Assign Cooking/Fishing"))
        h.flushTimers()
        equal(RQDB.settings.logistics.cooks["PVP:Alliance"], "Player-Other")
    end)
end
