return function(h)
    local test, equal, contains = h.test, h.equal, h.contains
    local now, item, bagItem = 123456789, 900001, 900002
    local senderId, firstId, secondId = "Player-Test-1", "Player-A", "Player-Z"

    local function member(id)
        local record = RQ.Util.Copy(RQ.Database.Current())
        record.identity = {
            ruleset = "PVE",
            faction = "Horde",
            guid = id,
            displayName = id,
            nameComplete = true,
            realm = "TestRealm PVE",
            class = "WARRIOR",
        }
        record.registration = "member"
        record.snapshot.professions = {}
        record.snapshot.sections.professions = { complete = true, observedAt = now, attemptedAt = now }
        record.inventory.bags = {
            complete = true,
            scannedAt = now,
            equipped = { 16, 16, 16, 16 },
            items = {},
            tradable = {},
            details = {},
            lockedContainers = {},
        }
        record.inventory.bank = {
            complete = false,
            coherent = false,
            scannedAt = 0,
            attemptedAt = 0,
            items = {},
            tradable = {},
            details = {},
            containers = {},
        }
        record.inventory.mail = {
            complete = false,
            coherent = false,
            scannedAt = 0,
            attemptedAt = 0,
            items = {},
            details = {},
            messages = {},
        }
        record.recipes = { complete = false, scannedAt = 0, items = {}, professions = {} }
        record.supplies = { needs = {}, goals = {}, reserves = { potions = {}, bandages = {} } }
        RQDB.characters[id] = record
        RQDB.roster[id] = { enabled = true }
        return record
    end

    local function start()
        h.fakeCharacter()
        h.loadAddon()
        if not RQ.LogisticsPolicies then
            assert(loadfile("Core/LogisticsPolicies.lua"))()
        end
        if not RQ.LogisticsPolicyService then
            assert(loadfile("Services/LogisticsPolicyService.lua"))()
        end
        h.emit("PLAYER_LOGIN")
        assert(RQ.Database.Register("add"))
        RQDB.settings.logistics = RQ.LogisticsPolicies.Defaults()
        RQDB.mailTracking.verifiedBuild = "logistics-test-build"
        local sender = member(senderId)
        local first, second = member(firstId), member(secondId)
        return sender, first, second
    end

    local function carried(record, id, count, capacity)
        record.inventory.bags.items[id], record.inventory.bags.tradable[id] = count, count
        record.inventory.bags.details[id] = capacity and { classId = 1, subclassId = 0, bagSlots = capacity } or {}
    end

    local function bank(record, id, count)
        record.inventory.bank = {
            complete = true,
            coherent = true,
            scannedAt = now,
            attemptedAt = now,
            items = { [id] = count },
            tradable = { [id] = count },
            details = {},
            containers = { [1] = { capacity = 16, items = { [id] = count } } },
        }
    end

    local function pending(id, count, capacity)
        local transfer = {
            sourceId = senderId,
            recipientId = id,
            status = "sent",
            ambiguous = false,
            manualConfirmed = true,
            attemptedAt = now - 10,
            remaining = { [bagItem] = count },
            items = { [bagItem] = count },
            details = { [bagItem] = { classId = 1, subclassId = 0, bagSlots = capacity } },
        }
        RQDB.mailTracking.transfers[1] = transfer
        return transfer
    end

    local function inbox(record, id, count, capacity)
        record.inventory.mail = {
            complete = true,
            coherent = true,
            scannedAt = now,
            attemptedAt = now,
            items = { [id] = count },
            details = { [id] = { classId = 1, subclassId = 0, bagSlots = capacity } },
            messages = {
                {
                    sender = senderId,
                    subject = "test",
                    cod = 0,
                    returned = false,
                    daysLeft = 29,
                    items = { [id] = count },
                },
            },
        }
    end

    local function rule(category, ids)
        local value = RQDB.settings.logistics.categories[category]
        value.items[item], value.recipients = true, ids or {}
        return value
    end

    local function evaluate()
        return RQ.SuppliesService.Evaluate(RQDB, senderId, now, true)
    end

    local function copyWindow(result, copies)
        local function show(title, text)
            if copies then
                copies[#copies + 1] = title .. "\n" .. text
            end
            return result
        end
        RQ.Api.ShowCopyWindow = show
    end

    test("logistics defaults contain no guessed IDs and prepare is copy-safe and idempotent", function()
        start()
        local original = RQ.LogisticsPolicies.Defaults()
        local prepared = assert(RQ.LogisticsPolicies.Prepare(original))
        for _, category in ipairs(RQ.LogisticsPolicies.categories) do
            equal(next(prepared.categories[category].items), nil)
            equal(#prepared.categories[category].recipients, 0)
        end
        prepared.categories.herbs.items[item] = true
        equal(original.categories.herbs.items[item], nil)
        local again = assert(RQ.LogisticsPolicies.Prepare(prepared))
        equal(again.categories.herbs.items[item], true)
        equal(again == prepared, false)
    end)

    test("logistics policies reject ambiguous categories and malformed ordered GUIDs", function()
        start()
        for _, invalid in ipairs({
            false,
            { categories = false },
            { unknown = true },
            { categories = { guessed = {} } },
            { categories = { herbs = { items = false } } },
            { categories = { herbs = { items = { [0] = true } } } },
            { categories = { herbs = { items = { [item] = 1 } } } },
            { categories = { herbs = { recipients = { firstId, firstId } } } },
            { categories = { herbs = { recipients = { "Display Name" } } } },
            { categories = { herbs = { recipients = { [2] = firstId } } } },
            {
                categories = {
                    engineering = { items = { [item] = true } },
                    blacksmithing = { items = { [item] = true } },
                },
            },
        }) do
            local value, err = RQ.LogisticsPolicies.Prepare(invalid)
            equal(value, nil)
            equal(type(err), "string")
        end
    end)

    test("reserve defaults validate separate explicit IDs and quantities without mutating input", function()
        start()
        assert(loadfile("Core/SuppliesConfig.lua"))()
        local defaults = assert(RQ.SuppliesConfig.PrepareReserves(nil))
        equal(next(defaults.potions), nil)
        equal(next(defaults.bandages), nil)
        local input = { potions = { [item] = 3 } }
        local result = assert(RQ.SuppliesConfig.PrepareReserves(input))
        equal(result.potions[item], 3)
        equal(input.bandages, nil)
        for _, value in ipairs({
            false,
            { other = {} },
            { potions = { [item] = -1 } },
            { potions = { [item] = 1.5 } },
            { potions = { [item] = 1000001 } },
            { bandages = { [0] = 1 } },
            { potions = { [item] = 1 }, bandages = { [item] = 1 } },
        }) do
            local invalid, err = RQ.SuppliesConfig.PrepareReserves(value)
            equal(invalid, nil)
            equal(type(err), "string")
        end
    end)

    test("First Aid reserve overlaps generic targets by maximum and keeps finite sender stock", function()
        local sender, first, second = start()
        carried(sender, item, 12)
        sender.supplies.reserves.potions[item] = 4
        sender.supplies.needs[item] = 2
        first.supplies.reserves.potions[item] = 5
        first.supplies.needs[item] = 3
        second.supplies.reserves.bandages[item] = 6
        local report = evaluate()
        equal(report.groceries[senderId][item].target, 4)
        equal(report.groceries[firstId][item].target, 5)
        equal(report.groceries[firstId][item].genericTarget, 3)
        equal(report.groceries[firstId][item].reserveTarget, 5)
        equal(report.proposals[1].count, 5)
        equal(report.proposals[2].count, 3)
        equal(#report.proposals, 2)
        contains({ report.proposals[1].reason }, "First Aid reserve")
    end)

    test("reserve deficits reuse bank inbox and pending accounting without adding mail to sender stock", function()
        local sender, first = start()
        first.supplies.reserves.bandages[bagItem] = 12
        carried(first, bagItem, 2)
        bank(first, bagItem, 3)
        pending(firstId, 4)
        carried(sender, bagItem, 3)
        local report = evaluate()
        local need = report.groceries[firstId][bagItem]
        equal(need.withdraw, 3)
        equal(need.inTransit, 4)
        equal(need.missing, 3)
        equal(report.proposals[1].count, 3)
        equal(#report.proposals, 1)
        inbox(first, bagItem, 4)
        report = evaluate()
        equal(report.groceries[firstId][bagItem].inTransit, 0)
        equal(report.groceries[firstId][bagItem].collect, 4)
        equal(report.groceries[firstId][bagItem].missing, 3)
    end)

    test("explicit herb leather and food policies require configured item IDs", function()
        for _, category in ipairs({ "herbs", "leather", "food" }) do
            local sender = start()
            carried(sender, item, 9)
            equal(#evaluate().proposals, 0)
            rule(category, { secondId, firstId })
            local report = evaluate()
            equal(#report.proposals, 1)
            equal(report.proposals[1].characterId, secondId)
            equal(report.proposals[1].count, 9)
            contains({ report.proposals[1].reason }, category)
        end
    end)

    test("Engineering and Blacksmithing preferences are distinct and override observed metal fallback", function()
        local sender, first = start()
        carried(sender, item, 7)
        sender.inventory.bags.details[item] = { classId = 7, subclassId = 7 }
        first.snapshot.professions[164] = { skill = 100, maxSkill = 150 }
        local engineering = rule("engineering", { secondId })
        equal(evaluate().proposals[1].characterId, secondId)
        engineering.items[item] = nil
        rule("blacksmithing", { firstId })
        equal(evaluate().proposals[1].characterId, firstId)
    end)

    test("explicit policies reserve finite grocery allocations in recipient priority order", function()
        local sender, first, second = start()
        carried(sender, item, 12)
        first.supplies.needs[item], second.supplies.reserves.potions[item] = 10, 7
        rule("food", { secondId, firstId })
        local report = evaluate()
        equal(report.proposals[1].characterId, secondId)
        equal(report.proposals[1].count, 7)
        equal(report.proposals[2].characterId, firstId)
        equal(report.proposals[2].count, 5)
        equal(#report.proposals, 2)
    end)

    test("configured targets do not receive unlimited policy surplus after being filled", function()
        local sender, first, second = start()
        carried(sender, item, 20)
        first.supplies.needs[item], second.supplies.needs[item] = 3, 4
        rule("herbs", { firstId, secondId })
        local report = evaluate()
        equal(#report.proposals, 2)
        equal(report.proposals[1].count + report.proposals[2].count, 7)
    end)

    test("explicit policies skip inactive cross-realm and ignored members and retain own preference", function()
        local sender, first, second = start()
        carried(sender, item, 9)
        local routing = rule("leather", { firstId, secondId, senderId })
        first.identity.realm = "OtherRealm"
        RQDB.roster[secondId].enabled = false
        equal(#evaluate().proposals, 0)
        RQDB.roster[secondId].enabled = true
        second.registration = "ignored"
        equal(#evaluate().proposals, 0)
        second.registration = "member"
        routing.recipients = { senderId, secondId }
        equal(#evaluate().proposals, 0)
        routing.recipients = { secondId }
        equal(evaluate().proposals[1].characterId, secondId)
    end)

    test("an explicit item with no recipients holds surplus but does not block grocery requests", function()
        local sender, first = start()
        carried(sender, item, 9)
        sender.inventory.bags.details[item] = { classId = 7, subclassId = 7 }
        first.snapshot.professions[164] = { skill = 1, maxSkill = 75 }
        rule("engineering")
        equal(#evaluate().proposals, 0)
        first.supplies.needs[item] = 3
        equal(evaluate().proposals[1].count, 3)
        equal(#evaluate().proposals, 1)
    end)

    test("bank suggestions respect recipient priority and remaining deficits after carried allocation", function()
        local sender, first, second = start()
        carried(sender, item, 4)
        bank(sender, item, 8)
        first.supplies.needs[item], second.supplies.needs[item] = 6, 5
        rule("food", { secondId, firstId })
        local report = evaluate()
        equal(report.proposals[1].characterId, secondId)
        equal(report.proposals[1].count, 4)
        equal(report.bankTransfers[1].characterId, secondId)
        equal(report.bankTransfers[1].count, 1)
        equal(report.bankTransfers[2].characterId, firstId)
        equal(report.bankTransfers[2].count, 6)
    end)

    test("confirmed pending bag suppresses only covered slots without creating ready upgrades", function()
        local sender, first = start()
        first.inventory.bags.equipped = { 6, 8, 16, 16 }
        carried(sender, bagItem, 2, 10)
        pending(firstId, 1, 10)
        local report = evaluate()
        equal(#report.bags.covered, 1)
        equal(report.bags.covered[1].slot, 1)
        equal(report.bags.covered[1].state, "pending")
        equal(#report.bags.upgrades, 1)
        equal(report.bags.upgrades[1].slot, 2)
        equal(report.bags.upgrades[1].kind, "mail")
        equal(#report.proposals, 1)
        contains(report.notes[firstId], "Not equip/craft ready")
    end)

    test("pending bag capacity must be observed and strictly exceed equipped capacity", function()
        local sender, first = start()
        first.inventory.bags.equipped = { 8, 16, 16, 16 }
        carried(sender, bagItem, 1, 10)
        local transfer = pending(firstId, 1)
        equal(#evaluate().bags.covered, 0)
        transfer.details[bagItem].bagSlots = 8
        equal(#evaluate().bags.covered, 0)
        transfer.details[bagItem].bagSlots = 10
        equal(#evaluate().bags.covered, 1)
        transfer.details[bagItem].subclassId = 1
        equal(#evaluate().bags.covered, 0)
    end)

    test("uncertain failed returned stale ambiguous and unconfirmed bag transfers never suppress upgrades", function()
        local sender, first = start()
        first.inventory.bags.equipped = { 8, 16, 16, 16 }
        carried(sender, bagItem, 1, 10)
        local transfer = pending(firstId, 1, 10)
        for _, status in ipairs({ "uncertain", "awaiting", "failed", "returned", "closed", "collected", "inbox" }) do
            transfer.status = status
            equal(#evaluate().bags.covered, 0)
            equal(#evaluate().bags.upgrades, 1)
        end
        transfer.status, transfer.ambiguous = "sent", true
        equal(#evaluate().bags.covered, 0)
        transfer.ambiguous, transfer.manualConfirmed = false, false
        equal(#evaluate().bags.covered, 0)
        transfer.manualConfirmed, transfer.attemptedAt = true, now - 48 * 3600
        equal(#evaluate().bags.covered, 0)
        transfer.attemptedAt = now - 10
        sender.inventory.bags.scannedAt = now - 20
        equal(#evaluate().bags.covered, 0)
    end)

    test("verified coherent inbox suppresses bags but COD returned and incoherent observations do not", function()
        local sender, first = start()
        first.inventory.bags.equipped = { 0, 16, 16, 16 }
        carried(sender, bagItem, 1, 10)
        inbox(first, bagItem, 1, 10)
        equal(#RQ.SuppliesService.Plan(RQDB, now, false).bags.covered, 0)
        equal(#evaluate().bags.covered, 1)
        first.inventory.mail.messages[1].cod = 1
        equal(#evaluate().bags.covered, 0)
        first.inventory.mail.messages[1].cod = 0
        first.inventory.mail.messages[1].returned = true
        equal(#evaluate().bags.covered, 0)
        first.inventory.mail.messages[1].returned = false
        first.inventory.mail.coherent = false
        equal(#evaluate().bags.covered, 0)
    end)

    test("mail reserved for an explicit bag grocery cannot also suppress an equipped-slot upgrade", function()
        local sender, first = start()
        first.inventory.bags.equipped = { 8, 16, 16, 16 }
        first.supplies.needs[bagItem] = 1
        carried(sender, bagItem, 1, 10)
        pending(firstId, 1, 10)
        local report = evaluate()
        equal(report.groceries[firstId][bagItem].inTransit, 1)
        equal(#report.bags.covered, 0)
        equal(#report.bags.upgrades, 1)
        inbox(first, bagItem, 1, 10)
        report = evaluate()
        equal(report.groceries[firstId][bagItem].collect, 1)
        equal(#report.bags.covered, 0)
    end)

    test("mail coverage removes duplicate crafts and their reagent grocery demand", function()
        local sender, first = start()
        first.inventory.bags.equipped = { 8, 16, 16, 16 }
        sender.snapshot.professions[197] = { name = "Tailoring", skill = 100, maxSkill = 150 }
        sender.recipes.professions[197] = {
            complete = true,
            scannedAt = now,
            name = "Tailoring",
            recipes = {
                [900003] = {
                    name = "Observed bag",
                    learned = true,
                    reagentsComplete = true,
                    skillUps = 0,
                    outputItemId = bagItem,
                    outputCount = 1,
                    bagSlots = 10,
                    outputBindType = 0,
                    reagents = { [item] = 6 },
                },
            },
        }
        equal(evaluate().groceries[senderId][item].target, 6)
        local transfer = pending(firstId, 1, 10)
        transfer.details[bagItem] = { name = "Native name-only transfer" }
        local report = evaluate()
        equal(#report.bags.covered, 1)
        equal(#report.bags.upgrades, 0)
        equal(next(report.bags.crafts), nil)
        equal(report.groceries[senderId][item], nil)
    end)

    test("confirmed empty-slot coverage also suppresses unknown-size fallback bag proposals", function()
        local sender, first = start()
        first.inventory.bags.equipped = { 0, 16, 16, 16 }
        carried(sender, item, 1)
        sender.inventory.bags.details[item] = { classId = 1, subclassId = 0 }
        pending(firstId, 1, 10)
        equal(#evaluate().proposals, 0)
    end)

    test("native name-only mail evidence uses observed same-ID capacity without inventing capacity", function()
        local sender, first = start()
        first.inventory.bags.equipped = { 8, 16, 16, 16 }
        local transfer = pending(firstId, 1)
        transfer.details[bagItem] = { name = "Native name only" }
        equal(#evaluate().bags.covered, 0)
        carried(sender, bagItem, 1, 10)
        equal(#evaluate().bags.covered, 1)
        inbox(first, bagItem, 1)
        first.inventory.mail.details[bagItem] = { name = "Native name only" }
        equal(#evaluate().bags.covered, 1)
        sender.inventory.bags.scannedAt = now - RQDB.policies.staleSnapshotHours * 3600
        equal(#evaluate().bags.covered, 0)
    end)

    test("conflicting same-ID observed capacities never suppress duplicate work based on a guess", function()
        local sender, first, second = start()
        first.inventory.bags.equipped = { 8, 16, 16, 16 }
        carried(sender, bagItem, 1, 10)
        carried(second, bagItem, 1, 12)
        local transfer = pending(firstId, 1, 10)
        equal(#evaluate().bags.covered, 0)
        transfer.details[bagItem] = { name = "Native name only" }
        equal(#evaluate().bags.covered, 0)
    end)

    test(
        "account material totals separate owned and provisional coverage without duplicate inbox pending credit",
        function()
            local sender, first = start()
            carried(sender, bagItem, 2)
            bank(sender, bagItem, 3)
            carried(first, bagItem, 1)
            pending(firstId, 4)
            local totals = RQ.LogisticsPolicyService.MaterialTotals(RQDB, now, true)
            equal(totals.items[bagItem].bags, 3)
            equal(totals.items[bagItem].bank, 3)
            equal(totals.items[bagItem].pending, 4)
            equal(totals.items[bagItem].owned, 6)
            equal(totals.items[bagItem].covered, 10)
            inbox(first, bagItem, 4)
            totals = RQ.LogisticsPolicyService.MaterialTotals(RQDB, now, true)
            equal(totals.items[bagItem].pending, 0)
            equal(totals.items[bagItem].inbox, 4)
            equal(totals.items[bagItem].covered, 10)
        end
    )

    test("account material totals exclude stale bags incoherent bank disabled members and unverified mail", function()
        local sender, first, second = start()
        carried(sender, item, 2)
        bank(sender, item, 3)
        carried(first, item, 20)
        carried(second, item, 30)
        first.inventory.bags.scannedAt = now - 48 * 3600
        RQDB.roster[secondId].enabled = false
        sender.inventory.bank.coherent = false
        inbox(sender, item, 100)
        local totals = RQ.LogisticsPolicyService.MaterialTotals(RQDB, now, false)
        equal(totals.items[item].owned, 2)
        equal(totals.items[item].covered, 2)
        equal(totals.partial, true)
        equal(#totals.sources, 2)
        sender.inventory.bank.coherent = true
        sender.inventory.bags.complete = false
        totals = RQ.LogisticsPolicyService.MaterialTotals(RQDB, now, true)
        equal(totals.items[item].covered, 0)
    end)

    test("routing and reserve reports explicitly label unset IDs and unknown game facts", function()
        start()
        contains(RQ.LogisticsPolicyService.RoutingReport(RQDB), "UNKNOWN / unset")
        contains(RQ.LogisticsPolicyService.ReserveReport(RQDB, firstId, now, false), "rank")
        contains(
            RQ.LogisticsPolicyService.MaterialReport(RQDB, now, false, tostring(item)),
            "UNKNOWN / no eligible observations"
        )
        local result, err = RQ.LogisticsPolicyService.MaterialReport(RQDB, now, false, "guessed")
        equal(result, nil)
        equal(type(err), "string")
    end)

    test(
        "reserve command validates and persists via existing supplies writes without touching generic needs",
        function()
            local sender = start()
            sender.supplies.needs[item] = 2
            assert(RQ.LogisticsPolicyService.Command("reserve", "potions " .. item .. " 5"))
            equal(sender.supplies.reserves.potions[item], 5)
            equal(sender.supplies.needs[item], 2)
            equal(RQCharDB.supplies.reserves.potions[item], 5)
            equal(RQ.LogisticsPolicyService.Command("reserve", "bandages " .. item .. " 3"), false)
            equal(sender.supplies.reserves.bandages[item], nil)
            assert(RQ.LogisticsPolicyService.Command("reserve", "potions " .. item .. " 0"))
            equal(sender.supplies.reserves.potions[item], nil)
            equal(RQ.LogisticsPolicyService.Command("reserve", "potions " .. item .. " -1"), false)
        end
    )

    test("routing commands resolve GUID references and reject invalid updates before persistence", function()
        start()
        local saved = 0
        RQ.Database.SetLogisticsPolicies = function(value)
            local prepared, err = RQ.LogisticsPolicies.Prepare(value)
            if not prepared then
                return false, err
            end
            saved = saved + 1
            RQDB.settings.logistics = prepared
            return true
        end
        assert(RQ.LogisticsPolicyService.Command("routing-item", "herbs " .. item .. " on"))
        assert(RQ.LogisticsPolicyService.Command("routing-priority", "herbs " .. secondId .. "," .. firstId))
        equal(RQDB.settings.logistics.categories.herbs.recipients[1], secondId)
        equal(RQ.LogisticsPolicyService.Command("routing-item", "leather " .. item .. " on"), false)
        equal(RQ.LogisticsPolicyService.Command("routing-priority", "herbs " .. firstId .. "," .. firstId), false)
        equal(RQ.LogisticsPolicyService.Command("routing-priority", "herbs " .. firstId .. ","), false)
        equal(saved, 2)
        assert(RQ.LogisticsPolicyService.Command("routing-priority", "herbs clear"))
        equal(#RQDB.settings.logistics.categories.herbs.recipients, 0)
    end)

    test("logistics commands expose persistence and copy capability failures rather than claiming success", function()
        start()
        RQ.Database.SetLogisticsPolicies = nil
        local ok, err = RQ.LogisticsPolicyService.Command("routing-item", "food " .. item .. " on")
        equal(ok, false)
        contains({ err }, "persistence is unavailable")
        copyWindow(false)
        ok, err = RQ.LogisticsPolicyService.Command("routing", "copy")
        equal(ok, false)
        contains({ err }, "Copy window unavailable")
        equal(RQ.LogisticsPolicyService.Command("routing", "unexpected"), false)
    end)

    test("copyable logistics reports use only existing Api copy surface and do not mutate policy state", function()
        start()
        local copies = {}
        copyWindow(true, copies)
        assert(RQ.LogisticsPolicyService.Command("routing", "copy"))
        assert(RQ.LogisticsPolicyService.Command("reserves", "copy " .. firstId))
        assert(RQ.LogisticsPolicyService.Command("material-totals", "copy " .. item))
        equal(#copies, 3)
        contains(copies, "No equip/craft-ready claim")
        equal(next(RQDB.settings.logistics.categories.food.items), nil)
    end)
end
