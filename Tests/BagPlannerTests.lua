return function(h)
    local test, equal, contains = h.test, h.equal, h.contains
    local now = 123456789
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
    local function member(id, sizes)
        local record = RQ.Util.Copy(RQ.Database.Current())
        record.identity = {
            ruleset = "PVE",
            faction = "Horde",
            guid = id,
            displayName = id,
            nameComplete = true,
            realm = "TestRealm PVE",
        }
        record.registration = "pending"
        record.snapshot.professions = {}
        record.snapshot.sections.professions = { complete = true, observedAt = now, attemptedAt = now }
        record.inventory.bags = {
            complete = true,
            scannedAt = now,
            equipped = sizes or { 8, 8, 8, 8 },
            items = {},
            tradable = {},
            details = {},
        }
        record.recipes = { complete = false, scannedAt = now, items = {}, professions = {} }
        record.supplies = { needs = {}, goals = {} }
        RQDB.characters[id] = record
        assert(RQ.Database.Register("add", id))
        return record
    end
    local function recipe(output, capacity, reagents, outputCount)
        return {
            name = "Bag " .. output,
            learned = true,
            skillUps = 0,
            reagentsComplete = true,
            reagents = reagents or { [2589] = 6 },
            outputItemId = output,
            outputCount = outputCount or 1,
            bagSlots = capacity,
            outputBindType = 0,
        }
    end
    local function tailor(id, size)
        local record = member(id, { 16, 16, 16, 16 })
        record.snapshot.professions[197] = { name = "Tailoring", skill = 100, maxSkill = 150 }
        record.recipes.professions[197] = {
            name = "Tailoring",
            complete = true,
            scannedAt = now,
            recipes = { [100] = recipe(4240, size or 10) },
        }
        return record
    end
    local function bag(record, id, slots, count, tradable)
        record.inventory.bags.items[id] = count
        record.inventory.bags.tradable[id] = tradable or 0
        record.inventory.bags.details[id] = { name = "Bag " .. id, classId = 1, subclassId = 0, bagSlots = slots }
    end
    local function plan()
        return RQ.SuppliesService.Plan(RQDB, now)
    end
    local function ignoreActive()
        assert(RQ.Database.Register("ignore"))
    end

    test("bag planner upgrades smaller equipped bags using the largest learned observed recipe", function()
        start()
        ignoreActive()
        local crafter = tailor("Player-Tailor")
        crafter.recipes.professions[197].recipes[101] = recipe(4245, 12)
        crafter.recipes.professions[197].recipes[102] = recipe(9999, 20)
        crafter.recipes.professions[197].recipes[102].learned = false
        member("Player-Recipient", { 6, 8, 12, 16 })
        local report = plan()
        equal(#report.bags.upgrades, 2)
        equal(report.bags.upgrades[1].from, 6)
        equal(report.bags.upgrades[1].to, 12)
        equal(report.bags.upgrades[2].from, 8)
        equal(report.bags.crafts["Player-Tailor"][101].crafts, 2)
        equal(report.groceries["Player-Tailor"][2589].target, 12)
        equal(report.groceries["Player-Tailor"][2589].missing, 12)
        equal(crafter.supplies.goals[197], nil)
        equal(#plan().bags.upgrades, 2)
    end)

    test("mail proposes existing higher capacity bags for occupied slots and never allocates one bag twice", function()
        start()
        local sender = member(RQ.Database.activeId, { 16, 16, 16, 16 })
        bag(sender, 4240, 10, 2, 1)
        member("Player-A", { 6, 10, 12, 16 })
        member("Player-B", { 8, 16, 16, 16 })
        local report = RQ.SuppliesService.Evaluate(RQDB, RQ.Database.activeId, now)
        equal(#report.proposals, 1)
        equal(report.proposals[1].itemId, 4240)
        equal(report.proposals[1].count, 1)
        equal(report.proposals[1].characterId, "Player-A")
        contains({ report.proposals[1].reason }, "6 -> 10")
        equal(report.bags.upgrades[1].kind, "mail")
        sender.inventory.bags.tradable[4240] = 0
        equal(#RQ.SuppliesService.Evaluate(RQDB, RQ.Database.activeId, now).proposals, 0)
    end)

    test("existing local and transferable bags reduce crafts and material demand", function()
        start()
        ignoreActive()
        local crafter = tailor("Player-Tailor")
        bag(crafter, 4240, 10, 1, 1)
        local recipient = member("Player-Recipient", { 6, 8, 8, 16 })
        bag(recipient, 4240, 10, 1, 0)
        local report = plan()
        equal(#report.bags.upgrades, 3)
        equal(report.bags.crafts["Player-Tailor"][100].crafts, 1)
        equal(report.groceries["Player-Tailor"][2589].target, 6)
        equal(report.bags.upgrades[1].kind, "equip")
        equal(report.bags.upgrades[2].kind, "mail")
        equal(report.bags.upgrades[3].kind, "craft")
        recipient.inventory.bags.equipped = { 10, 10, 10, 16 }
        equal(next(plan().bags.crafts), nil)
    end)

    test("bag materials take priority over another tailors surplus route and ordinary grocery requests", function()
        start()
        local sender = member(RQ.Database.activeId, { 16, 16, 16, 16 })
        sender.inventory.bags.items[2589], sender.inventory.bags.tradable[2589] = 30, 30
        sender.inventory.bags.details[2589] = { name = "Linen", classId = 7, subclassId = 5 }
        local ordinary = member("Player-A", { 16, 16, 16, 16 })
        ordinary.snapshot.professions[197] = { name = "Tailoring", skill = 1, maxSkill = 75 }
        ordinary.supplies.needs[2589] = 30
        local crafter = tailor("Player-Z")
        crafter.inventory.bags.items[2589] = 2
        member("Player-Recipient", { 6, 8, 16, 16 })
        local report = RQ.SuppliesService.Evaluate(RQDB, RQ.Database.activeId, now)
        equal(report.proposals[1].characterId, "Player-Z")
        equal(report.proposals[1].count, 10)
        contains({ report.proposals[1].reason }, "Priority materials")
        equal(report.proposals[2].characterId, "Player-A")
        equal(report.proposals[2].count, 20)
        equal(#report.proposals, 2)
    end)

    test("observed bolt recipes expand bag materials into cloth without counting stocked bolts twice", function()
        start()
        ignoreActive()
        local crafter = tailor("Player-Tailor")
        local recipes = crafter.recipes.professions[197].recipes
        recipes[100].reagents = { [2996] = 3, [2320] = 1 }
        recipes[101] = recipe(2996, nil, { [2589] = 2 })
        crafter.inventory.bags.items = { [2996] = 1, [2589] = 2, [2320] = 1 }
        member("Player-Recipient", { 6, 8, 16, 16 })
        local report = plan()
        equal(report.bags.conversions["Player-Tailor"][101], 5)
        equal(report.groceries["Player-Tailor"][2996].target, 1)
        equal(report.groceries["Player-Tailor"][2996].missing, 0)
        equal(report.groceries["Player-Tailor"][2589].target, 10)
        equal(report.groceries["Player-Tailor"][2589].missing, 8)
        equal(report.groceries["Player-Tailor"][2320].missing, 1)
        recipes[101].learned = false
        report = plan()
        equal(report.groceries["Player-Tailor"][2996].missing, 5)
        equal(report.groceries["Player-Tailor"][2589], nil)
    end)

    test("bag material reserves coexist with explicit goals and do not export the crafters materials", function()
        start()
        local crafter = tailor(RQ.Database.activeId)
        crafter.supplies.needs[2589] = 10
        crafter.inventory.bags.items[2589], crafter.inventory.bags.tradable[2589] = 20, 20
        crafter.inventory.bags.details[2589] = { classId = 7, subclassId = 5 }
        local recipient = member("Player-Recipient", { 6, 16, 16, 16 })
        recipient.supplies.needs[2589] = 50
        local report = RQ.SuppliesService.Evaluate(RQDB, RQ.Database.activeId, now)
        equal(report.groceries[RQ.Database.activeId][2589].target, 16)
        equal(report.proposals[1].count, 4)
    end)

    test("stale or unknown bag and recipe observations never produce automatic craft upgrades", function()
        start()
        ignoreActive()
        local crafter = tailor("Player-Tailor")
        local recipient = member("Player-Recipient", { 6, 8, 16, 16 })
        recipient.inventory.bags.complete = false
        equal(#plan().bags.upgrades, 0)
        recipient.inventory.bags.complete = true
        recipient.inventory.bags.scannedAt = now - 49 * 3600
        equal(#plan().bags.upgrades, 0)
        recipient.inventory.bags.scannedAt = now
        local scan = crafter.recipes.professions[197]
        scan.scannedAt = now - 49 * 3600
        equal(#plan().bags.upgrades, 0)
        scan.scannedAt = now
        scan.recipes[100].bagSlots = nil
        equal(#plan().bags.upgrades, 0)
        scan.recipes[100].bagSlots = 10
        scan.recipes[100].reagentsComplete = false
        equal(#plan().bags.upgrades, 0)
        scan.recipes[100].reagentsComplete = true
        RQDB.roster["Player-Tailor"].enabled = false
        equal(#plan().bags.upgrades, 0)
    end)

    test("bag panel exposes equipped sizes upgrade steps and material shortages through a standalone tab", function()
        local frames = start(true)
        ignoreActive()
        tailor("Player-Tailor")
        member("Player-Recipient", { 6, 8, 16, 16 })
        _G.SlashCmdList.ROSTERQUARTERMASTER("bags")
        equal(RQ.MainWindow.tab, "bags")
        local cards = RQ.BagPanel.Build(RQDB, plan())
        contains({ cards[2].body }, "Bag 1: 6 slots")
        contains({ cards[2].body }, "6 -> 10 slots")
        contains({ cards[3].body }, "PRIORITY: craft 2")
        contains({ cards[3].body }, "missing 12")
        frames.Click(frames.FindButton("Bag upgrades"))
        h.flushTimers()
        equal(RQ.MainWindow.tab, "bags")
        equal(RQ.MainWindow.view.inventorySection, "upgrades")
    end)

    test("an existing beneficial bag is mailed even when an even larger bag could be crafted", function()
        start()
        local sender = member(RQ.Database.activeId, { 16, 16, 16, 16 })
        bag(sender, 4240, 10, 1, 1)
        tailor("Player-Tailor", 14)
        member("Player-Recipient", { 6, 16, 16, 16 })
        local report = RQ.SuppliesService.Evaluate(RQDB, RQ.Database.activeId, now)
        equal(#report.proposals, 1)
        contains({ report.proposals[1].reason }, "6 -> 10")
        equal(next(report.bags.crafts), nil)
        equal(next(report.bags.materials), nil)
    end)

    test("own bag upgrades are kept and an equal size bag never becomes a transfer", function()
        start()
        local sender = member(RQ.Database.activeId, { 6, 16, 16, 16 })
        bag(sender, 4240, 10, 1, 1)
        member("Player-Recipient", { 4, 16, 16, 16 })
        local report = RQ.SuppliesService.Evaluate(RQDB, RQ.Database.activeId, now)
        equal(report.bags.upgrades[1].characterId, RQ.Database.activeId)
        equal(report.bags.upgrades[1].kind, "equip")
        equal(#report.proposals, 0)
        sender.inventory.bags.equipped = { 16, 16, 16, 16 }
        RQDB.characters["Player-Recipient"].inventory.bags.equipped = { 10, 16, 16, 16 }
        equal(#RQ.SuppliesService.Evaluate(RQDB, RQ.Database.activeId, now).proposals, 0)
    end)

    test("crafting binding evidence prevents cross-character soulbound or unknown bag plans", function()
        start()
        ignoreActive()
        local crafter = tailor("Player-Tailor")
        member("Player-Recipient", { 6, 16, 16, 16 })
        local bagRecipe = crafter.recipes.professions[197].recipes[100]
        bagRecipe.outputBindType = 1
        equal(#plan().bags.upgrades, 0)
        bagRecipe.outputBindType = nil
        equal(#plan().bags.upgrades, 0)
        crafter.inventory.bags.equipped = { 6, 16, 16, 16 }
        local report = plan()
        equal(#report.bags.upgrades, 1)
        equal(report.bags.upgrades[1].characterId, "Player-Tailor")
    end)

    test("multiple tailors deterministically choose one crafter and fixed multi-output crafts round up", function()
        start()
        ignoreActive()
        local first = tailor("Player-A")
        tailor("Player-B")
        first.recipes.professions[197].recipes[100].outputCount = 2
        member("Player-Recipient", { 6, 6, 6, 16 })
        local report = plan()
        equal(report.bags.crafts["Player-A"][100].bags, 3)
        equal(report.bags.crafts["Player-A"][100].crafts, 2)
        equal(report.bags.crafts["Player-B"], nil)
        equal(report.groceries["Player-A"][2589].target, 12)
        first.inventory.bags.scannedAt = now - 49 * 3600
        report = plan()
        equal(report.bags.crafts["Player-A"], nil)
        equal(report.bags.crafts["Player-B"][100].crafts, 3)
    end)

    test(
        "cyclic conversion recipes terminate explicitly and excessive requirements do not route invented stock",
        function()
            start()
            ignoreActive()
            local crafter = tailor("Player-Tailor")
            member("Player-Recipient", { 6, 16, 16, 16 })
            local recipes = crafter.recipes.professions[197].recipes
            recipes[100].reagents = { [2996] = 1 }
            recipes[101] = recipe(2996, nil, { [2996] = 1 })
            local report = plan()
            contains(report.bags.notes["Player-Tailor"], "Cyclic")
            equal(report.groceries["Player-Tailor"][2996].missing, 1)
            recipes[100].reagents = { [2996] = 1000000 }
            recipes[101].reagents = { [2589] = 2 }
            report = plan()
            equal(next(report.bags.materials["Player-Tailor"]), nil)
            contains(report.bags.notes["Player-Tailor"], "exceeded safe limits")
        end
    )

    test("bag planning does not call game APIs or mutate stored goals counts or scans", function()
        start()
        ignoreActive()
        local crafter = tailor("Player-Tailor")
        local target = member("Player-Recipient", { 6, 16, 16, 16 })
        local recipes = crafter.recipes
        RQ.Api = setmetatable({}, {
            __index = function()
                error("pure planner must not read APIs")
            end,
        })
        local report = plan()
        equal(#report.bags.upgrades, 1)
        equal(crafter.recipes, recipes)
        equal(next(crafter.supplies.goals), nil)
        equal(target.inventory.bags.equipped[1], 6)
        equal(next(crafter.inventory.bags.items), nil)
    end)

    test("optional bag metadata migrates idempotently and invalid capacity is rejected transactionally", function()
        start()
        local crafter = tailor("Player-Tailor")
        bag(crafter, 4240, 10, 1, 1)
        local account, character = RQ.Migrations.Prepare(RQDB, RQCharDB)
        assert(account)
        local again = RQ.Migrations.Prepare(account, character)
        equal(again.characters["Player-Tailor"].recipes.professions[197].recipes[100].bagSlots, 10)
        equal(again.characters["Player-Tailor"].inventory.bags.details[4240].bagSlots, 10)
        local invalid = RQ.Util.Copy(crafter.recipes)
        invalid.professions[197].recipes[100].bagSlots = 101
        equal(RQ.Database.SaveLogistics("Player-Tailor", "recipes", invalid), false)
        equal(crafter.recipes.professions[197].recipes[100].bagSlots, 10)
        invalid = RQ.Util.Copy(crafter.inventory)
        invalid.bags.details[4240].subclassId = 1
        equal(RQ.Database.SaveLogistics("Player-Tailor", "inventory", invalid), false)
    end)

    test("schema five upgrade preserves snapshots without inventing bag outputs and is idempotent", function()
        start()
        local oldAccount, oldCharacter = RQ.Util.Copy(RQDB), RQ.Util.Copy(RQCharDB)
        oldAccount.schemaVersion, oldCharacter.schemaVersion = 5, 5
        local id = RQ.Database.activeId
        local account, character = RQ.Migrations.Prepare(oldAccount, oldCharacter)
        equal(account.schemaVersion, 19)
        equal(character.schemaVersion, 19)
        equal(oldAccount.schemaVersion, 5)
        equal(oldCharacter.schemaVersion, 5)
        equal(account.characters[id].snapshot.xp, oldAccount.characters[id].snapshot.xp)
        equal(next(account.characters[id].recipes.professions), nil)
        local again, againCharacter = RQ.Migrations.Prepare(account, character)
        equal(again.schemaVersion, 19)
        equal(againCharacter.schemaVersion, 19)
        equal(again.characters[id].snapshot.xp, account.characters[id].snapshot.xp)
        equal(again.roster[id].slotId, account.roster[id].slotId)
        local malformed = RQ.Util.Copy(account)
        malformed.characters[id].inventory.bags.details[123] = { classId = 1, subclassId = 0, bagSlots = -1 }
        local rejected = RQ.Migrations.Prepare(malformed, character)
        equal(rejected, nil)
        equal(malformed.schemaVersion, 19)
    end)
end
