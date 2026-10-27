return function(h)
    local test, equal, contains = h.test, h.equal, h.contains
    local now, active = 123456789, "Player-Test-1"
    local function item(id, count, bound)
        return {
            itemID = id,
            stackCount = count,
            itemName = id == 2770 and "Copper Ore" or "Copper Bar",
            isBound = bound == true,
            isLocked = false,
        }
    end
    local function start(native)
        h.fakeCharacter()
        local frames = native and assert(loadfile("Tests/fixtures/Frames.lua"))()()
        local state = {
            tabs = { 6, 7 },
            sizes = { [0] = 2, [6] = 3, [7] = 2 },
            usable = true,
            reads = 0,
            slots = { [0] = { item(2770, 10) }, [6] = { item(2770, 3), item(2840, 2) }, [7] = { item(2770, 4, true) } },
        }
        _G.Enum = {
            BankType = { Character = 27, Account = 28 },
            BagIndex = { Keyring = -1, CharacterBankTab_1 = 6, CharacterBankTab_2 = 7, AccountBankTab_1 = 15 },
        }
        _G.C_Bank = {
            CanUseBank = function(kind)
                equal(kind, 27)
                return state.usable
            end,
            FetchPurchasedBankTabIDs = function(kind)
                equal(kind, 27)
                return state.tabs
            end,
            FetchNumPurchasedBankTabs = function(kind)
                equal(kind, 27)
                return #state.tabs
            end,
        }
        _G.C_Container = {
            GetContainerNumSlots = function(id)
                if id < 0 or id == 15 then
                    error("Account bank/keyring must never be scanned")
                end
                return state.sizes[id] or 0
            end,
            GetContainerNumFreeSlots = function()
                return 0
            end,
            GetContainerItemInfo = function(bag, slot)
                state.reads = state.reads + 1
                if state.fail and bag == 7 then
                    error("Bank data restricted")
                end
                return state.slots[bag] and state.slots[bag][slot]
            end,
        }
        h.loadAddon()
        state.emit = frames and frames.Emit or h.emit
        state.emit("PLAYER_LOGIN")
        assert(RQ.Database.Register("add"))
        return state, frames
    end
    local function open(state)
        state.emit("BANKFRAME_OPENED")
        h.flushTimers()
        return RQ.Database.Current().inventory
    end
    local function member(id, carried)
        local record = RQ.Util.Copy(RQ.Database.Current())
        record.identity =
            { ruleset = "PVE", faction = "Horde", guid = id, fullName = id, realm = "TestRealm PVE", class = "WARRIOR" }
        record.registration = "pending"
        record.inventory.bags.items, record.inventory.bags.tradable = carried or {}, {}
        record.inventory.bags.equipped, record.inventory.bags.details = {}, {}
        record.inventory.bank = {
            items = {},
            details = {},
            tradable = {},
            containers = {},
            complete = false,
            coherent = false,
            scannedAt = 0,
            attemptedAt = 0,
        }
        record.supplies = { needs = {}, goals = {} }
        RQDB.characters[id] = record
        assert(RQ.Database.Register("add", id))
        return record
    end

    test("personal-bank scan uses verified tab enumeration and aggregates bound and unbound stock", function()
        local state = start()
        local inventory = open(state)
        equal(inventory.bank.coherent, true)
        equal(inventory.bank.complete, true)
        equal(inventory.bank.items[2770], 7)
        equal(inventory.bank.tradable[2770], 3)
        equal(inventory.bank.items[2840], 2)
        equal(inventory.bank.containers[6].items[2770], 3)
        equal(inventory.bank.containers[7].capacity, 2)
        equal(inventory.bags.items[2770], 10)
        equal(inventory.bags.equipped[6], nil)
        equal(inventory.bank.scannedAt, now)
        equal(RQCharDB.inventory.bank.items[2770], 7)
        inventory.bank.items[2770] = 99
        equal(RQCharDB.inventory.bank.items[2770], 7)
        contains({ RQ.Api.GetCapabilities().bankInventory }, "coherent")
    end)

    test(
        "unopened banks remain unknown and verified empty banks including zero purchased tabs are known empty",
        function()
            local state = start()
            equal(RQ.Database.Current().inventory.bank.complete, false)
            local pair, err = RQ.Api.GetBankInventory(active)
            equal(pair, nil)
            contains({ err }, "closed")
            state.slots[6], state.slots[7] = {}, {}
            equal(next(open(state).bank.items), nil)
            equal(RQ.Database.Current().inventory.bank.complete, true)
            state.tabs = {}
            state.emit("BANK_TABS_CHANGED")
            h.flushTimers()
            equal(RQ.Database.Current().inventory.bank.coherent, true)
            equal(next(RQ.Database.Current().inventory.bank.containers), nil)
            equal(next(RQ.Database.Current().inventory.bank.items), nil)
        end
    )

    test("deposits and withdrawals invalidate both budgets immediately and publish a coherent replacement", function()
        local state = start()
        open(state)
        assert(RQ.SuppliesService.SetNeed(2770, 20))
        local need = RQ.SuppliesService.Plan(RQDB, now).groceries[active][2770]
        equal(need.have, 10)
        equal(need.bankHave, 7)
        equal(need.withdraw, 7)
        equal(need.missing, 3)
        state.slots[0][1].stackCount = 7
        state.slots[6][1].stackCount = 6
        state.emit("BAG_UPDATE", 0)
        equal(RQ.Database.Current().inventory.bags.complete, false)
        equal(RQ.Database.Current().inventory.bank.coherent, false)
        equal(RQ.SuppliesService.Plan(RQDB, now).groceries[active][2770].missing, nil)
        state.emit("PLAYERBANKSLOTS_CHANGED")
        state.emit("BAG_UPDATE_DELAYED")
        local reads = state.reads
        h.flushTimers()
        assert(state.reads > reads)
        need = RQ.SuppliesService.Plan(RQDB, now).groceries[active][2770]
        equal(need.have, 7)
        equal(need.bankHave, 10)
        equal(need.withdraw, 10)
        equal(need.missing, 3)
        state.slots[0][1].stackCount, state.slots[6][1].stackCount = 13, 0
        state.slots[6][1] = nil
        state.emit("PLAYERBANKSLOTS_CHANGED")
        h.flushTimers()
        need = RQ.SuppliesService.Plan(RQDB, now).groceries[active][2770]
        equal(need.have, 13)
        equal(need.bankHave, 4)
        equal(need.missing, 3)
    end)

    test("closed bank rescans and logout preserve confirmed bank caches without teardown reads", function()
        local state = start()
        open(state)
        state.emit("BANKFRAME_CLOSED")
        state.slots[6], state.slots[7] = {}, {}
        assert(RQ.SuppliesService.ScanBags())
        equal(RQ.Database.Current().inventory.bank.items[2770], 7)
        equal(RQ.Database.Current().inventory.bank.coherent, true)
        equal(RQ.Database.Current().inventory.bank.scannedAt, now)
        local reads = state.reads
        state.emit("PLAYER_LOGOUT")
        state.emit("PLAYERBANKSLOTS_CHANGED")
        state.emit("BAG_UPDATE_DELAYED")
        h.flushTimers()
        equal(state.reads, reads)
        equal(RQ.Database.Current().inventory.bank.items[2770], 7)
        local account, character = RQ.Migrations.Prepare(RQDB, RQCharDB)
        equal(account.characters[active].inventory.bank.coherent, true)
        equal(character.inventory.bank.items[2770], 7)
    end)

    test("close before deferred refresh keeps cached bank uncertain even after a fresh carried scan", function()
        local state = start()
        open(state)
        state.slots[0][1].stackCount = 13
        state.slots[6][1] = nil
        state.emit("BAG_UPDATE", 0)
        state.emit("BANKFRAME_CLOSED")
        local reads = state.reads
        h.flushTimers()
        equal(state.reads, reads)
        equal(RQ.Database.Current().inventory.bank.items[2770], 7)
        equal(RQ.Database.Current().inventory.bank.complete, false)
        assert(RQ.SuppliesService.ScanBags())
        local record = RQ.Database.Current()
        equal(record.inventory.bags.items[2770], 13)
        equal(RQ.InventoryAvailability.BankEligible(record, now, 48), false)
        local need = RQ.InventoryAvailability.Need(record, 2770, 20, now, 48)
        equal(need.have, 13)
        equal(need.bankHave, nil)
        equal(need.missing, 7)
        local inventory = open(state)
        equal(inventory.bank.items[2770], 4)
        equal(RQ.InventoryAvailability.Need(record, 2770, 20, now, 48).missing, 3)
    end)

    test("failed bank reads never publish only the successful half and repeat errors do not spam", function()
        local state = start()
        open(state)
        state.fail = true
        state.slots[0][1].stackCount = 99
        state.emit("PLAYERBANKSLOTS_CHANGED")
        h.flushTimers()
        local record = RQ.Database.Current()
        equal(record.inventory.bags.items[2770], 10)
        equal(record.inventory.bags.complete, false)
        equal(record.inventory.bank.items[2770], 7)
        equal(record.inventory.bank.coherent, false)
        contains(h.messages(), "Bank contents unavailable")
        local count = #h.messages()
        equal(RQ.BankService.Scan(), false)
        equal(#h.messages(), count)
        state.fail = false
        assert(RQ.BankService.Scan())
        equal(record.inventory.bags.items[2770], 99)
        equal(record.inventory.bank.error, nil)
    end)

    test("missing bank APIs enums mismatched count and foreign duplicate or carried tabs fail closed", function()
        local state = start()
        open(state)
        local original = RQ.Util.Copy(_G.Enum)
        for _, tabs in ipairs({ { 6, 6 }, { 15 }, { -1 }, { 0 }, { 1 }, { 999 } }) do
            state.tabs = tabs
            equal(RQ.BankService.Scan(), false)
            equal(RQ.Database.Current().inventory.bank.items[2770], 7)
            equal(RQ.Database.Current().inventory.bank.coherent, false)
        end
        state.tabs = { 6, 7 }
        _G.Enum.BankType = nil
        equal(RQ.BankService.Scan(), false)
        _G.Enum = original
        _G.C_Bank.FetchNumPurchasedBankTabs = function()
            return 1
        end
        equal(RQ.BankService.Scan(), false)
        _G.C_Bank.FetchNumPurchasedBankTabs = function()
            return 2
        end
        state.usable = false
        equal(RQ.BankService.Scan(), false)
        state.usable = true
        _G.C_Bank.FetchPurchasedBankTabIDs = nil
        equal(RQ.BankService.Scan(), false)
        equal(RQ.Database.Current().inventory.bank.items[2770], 7)
    end)

    test("zero slot loading restricted nested data and unstable reads preserve the previous bank", function()
        local state = start()
        open(state)
        state.sizes[7] = 0
        equal(RQ.BankService.Scan(), false)
        equal(RQ.Database.Current().inventory.bank.items[2770], 7)
        state.sizes[7] = 2
        _G.issecretvalue = function(value)
            return value == state.slots[6][1]
        end
        equal(RQ.BankService.Scan(), false)
        _G.issecretvalue = nil
        local get = _G.C_Container.GetContainerItemInfo
        _G.C_Container.GetContainerItemInfo = function(bag, slot)
            if bag == 6 and slot == 1 then
                local value = RQ.Util.Copy(state.slots[6][1])
                state.slots[6][1].stackCount = state.slots[6][1].stackCount + 1
                return value
            end
            return get(bag, slot)
        end
        equal(RQ.BankService.Scan(), false)
        contains({ RQ.Database.Current().inventory.bank.error }, "changed during scan")
        equal(RQ.Database.Current().inventory.bank.items[2770], 7)
        _G.C_Container.GetContainerItemInfo = get
        assert(RQ.BankService.Scan())
    end)

    test("bank reads recheck active GUID and access before publishing", function()
        local state = start()
        open(state)
        _G.UnitGUID = function()
            return "Someone-Else"
        end
        equal(RQ.BankService.Scan(), false)
        equal(RQ.Database.Current().inventory.bank.items[2770], 7)
        _G.UnitGUID = function()
            return active
        end
        local count = 0
        _G.C_Bank.CanUseBank = function()
            count = count + 1
            return count < 3
        end
        equal(RQ.BankService.Scan(), false)
        contains({ RQ.Database.Current().inventory.bank.error }, "access or tab layout changed")
    end)

    test("ignored characters and stale queued callbacks never scan banks", function()
        local state = start()
        assert(RQ.Database.Register("ignore"))
        local before = state.reads
        open(state)
        equal(state.reads, before)
        assert(RQ.Database.Register("add"))
        state.emit("BANKFRAME_OPENED")
        state.emit("PLAYER_LOGOUT")
        h.flushTimers()
        equal(state.reads, before)
        equal(RQ.Database.Current().inventory.bank.coherent, false)
    end)

    test("schema nine migration preserves old bank items but never invents coherence", function()
        local state = start()
        open(state)
        local old, char = RQ.Util.Copy(RQDB), RQ.Util.Copy(RQCharDB)
        old.schemaVersion, char.schemaVersion = 8, 8
        old.characters[active].inventory.bank.containers = nil
        char.inventory.bank.containers = nil
        local account, character, err = RQ.Migrations.Prepare(old, char)
        assert(account, err)
        equal(account.schemaVersion, 19)
        equal(character.schemaVersion, 19)
        equal(account.characters[active].inventory.bank.items[2770], 7)
        equal(account.characters[active].inventory.bank.coherent, false)
        equal(next(account.characters[active].inventory.bank.containers), nil)
        equal(old.characters[active].inventory.bank.coherent, true)
        equal(old.schemaVersion, 8)
        local again = RQ.Migrations.Prepare(account, character)
        equal(again.characters[active].inventory.bank.coherent, false)
        equal(again.characters[active].inventory.bank.scannedAt, now)
    end)

    test("malformed bank metadata and impossible coherent totals reject transactionally", function()
        local state = start()
        open(state)
        for _, corrupt in ipairs({
            function(b)
                b.items[2770] = -1
            end,
            function(b)
                b.tradable[2770] = 99
            end,
            function(b)
                b.coherent = "yes"
            end,
            function(b)
                b.containers[6].capacity = 0
            end,
            function(b)
                b.containers[6].items[2770] = 99
            end,
            function(b)
                b.attemptedAt = -1
            end,
            function(b)
                b.details[2770].name = false
            end,
        }) do
            local inventory = RQ.Util.Copy(RQ.Database.Current().inventory)
            corrupt(inventory.bank)
            equal(RQ.Database.SaveLogistics(active, "inventory", inventory), false)
            equal(RQ.Database.Current().inventory.bank.items[2770], 7)
            local input = RQ.Util.Copy(RQDB)
            input.characters[active].inventory = inventory
            local account, character, err = RQ.Migrations.Prepare(input, RQCharDB)
            equal(account, nil)
            equal(character, nil)
            assert(err)
            equal(input.schemaVersion, 19)
        end
    end)

    test(
        "local bank reduces procurement but always requires manual withdrawal and never changes carried quantity",
        function()
            local state = start()
            open(state)
            assert(RQ.SuppliesService.SetNeed(2770, 20))
            local record = RQ.Database.Current()
            local plan = RQ.SuppliesService.Plan(RQDB, now)
            local need = plan.groceries[active][2770]
            equal(20, need.have + need.withdraw + need.missing)
            equal(need.withdraw, 7)
            contains(RQ.SuppliesService.Report(active), "Withdraw from bank: 7 x Copper Ore [2770]")
            local recommendations = RQ.PlanningService.Evaluate()
            local cards = RQ.TodayPanel.Build(RQDB, recommendations, nil, active, plan)
            contains({ cards[1].detail }, "Withdraw from bank: 7")
            equal(record.inventory.bags.items[2770], 10)
            record.inventory.bank.scannedAt = now - 48 * 3600
            need = RQ.InventoryAvailability.Need(record, 2770, 20, now, 48)
            equal(need.bankHave, nil)
            equal(need.withdraw, 0)
            equal(need.missing, 10)
            record.inventory.bank.scannedAt = now
            record.inventory.bank.coherent = false
            equal(RQ.InventoryAvailability.Need(record, 2770, 20, now, 48).bankHave, nil)
        end
    )

    test(
        "recipient bank credit prevents duplicate material mail and source bank never becomes attachable stock",
        function()
            local state = start()
            open(state)
            local target = member("Player-Recipient", {})
            target.supplies.needs[2770] = 5
            target.inventory.bank = RQ.Util.Copy(RQ.Database.Current().inventory.bank)
            local report = RQ.SuppliesService.Evaluate(RQDB, active, now)
            equal(report.groceries["Player-Recipient"][2770].missing, 0)
            equal(#report.proposals, 0)
            equal(#report.bankTransfers, 0)
            target.inventory.bank.coherent = false
            report = RQ.SuppliesService.Evaluate(RQDB, active, now)
            equal(report.proposals[1].count, 5)
            equal(#report.bankTransfers, 0)
            assert(RQ.SuppliesService.SetNeed(2770, 10))
            report = RQ.SuppliesService.Evaluate(RQDB, active, now)
            equal(#report.proposals, 0)
            equal(#report.bankTransfers, 1)
            equal(report.bankTransfers[1].count, 3)
            equal(report.groceries["Player-Recipient"][2770].missing, 5)
            target.identity.realm = "OtherRealm"
            equal(#RQ.SuppliesService.Evaluate(RQDB, active, now).bankTransfers, 0)
        end
    )

    test("bank transfer suggestions reserve local withdrawals and allocate each verified unbound unit once", function()
        local state = start()
        open(state)
        member("Player-A").supplies.needs[2770] = 5
        member("Player-B").supplies.needs[2770] = 5
        assert(RQ.SuppliesService.SetNeed(2770, 12))
        local report = RQ.SuppliesService.Evaluate(RQDB, active, now)
        equal(#report.proposals, 0)
        equal(#report.bankTransfers, 1)
        equal(report.bankTransfers[1].characterId, "Player-A")
        equal(report.bankTransfers[1].count, 3)
        assert(RQ.SuppliesService.SetNeed(2770, 16))
        report = RQ.SuppliesService.Evaluate(RQDB, active, now)
        equal(report.bankTransfers[1].count, 1)
        assert(RQ.SuppliesService.SetNeed(2770, 17))
        equal(#RQ.SuppliesService.Evaluate(RQDB, active, now).bankTransfers, 0)
    end)

    test("Cooking Fishing bank guidance preserves local reserves and cannot cross trade groups", function()
        local state = start()
        state.slots[0], state.slots[6], state.slots[7] = { item(769, 2) }, { item(769, 10) }, { item(769, 4, true) }
        open(state)
        local cook = member("Player-Cook")
        local other = member("Player-Other")
        other.supplies.needs[769] = 50
        assert(RQ.Database.SetCook("Player-Cook"))
        assert(RQ.SuppliesService.SetNeed(769, 6))
        local report = RQ.SuppliesService.Evaluate(RQDB, active, now)
        equal(#report.proposals, 0)
        equal(#report.bankTransfers, 1)
        equal(report.bankTransfers[1].characterId, "Player-Cook")
        equal(report.bankTransfers[1].count, 10)
        assert(RQ.SuppliesService.SetNeed(769, 10))
        report = RQ.SuppliesService.Evaluate(RQDB, active, now)
        equal(report.bankTransfers[1].count, 6)
        cook.identity.faction, other.identity.faction = "Alliance", "Alliance"
        equal(#RQ.SuppliesService.Evaluate(RQDB, active, now).bankTransfers, 0)
        cook.identity.faction = "Horde"
        assert(RQ.Database.SetCook(active))
        equal(#RQ.SuppliesService.Evaluate(RQDB, active, now).bankTransfers, 0)
    end)

    test("bank materials prevent duplicate intermediate crafts in bag plans without stealing manual targets", function()
        local state = start()
        open(state)
        local tailor = RQ.Database.Current()
        tailor.snapshot.professions[197] = { name = "Tailoring", skill = 100, maxSkill = 150 }
        tailor.inventory.bags.equipped = { 16, 16, 16, 16 }
        tailor.inventory.bank.items, tailor.inventory.bank.tradable = { [2996] = 6 }, {}
        tailor.inventory.bank.containers = { [6] = { capacity = 3, items = { [2996] = 6 } } }
        tailor.recipes.professions[197] = {
            name = "Tailoring",
            complete = true,
            scannedAt = now,
            recipes = {
                [100] = {
                    name = "Bag",
                    learned = true,
                    skillUps = 1,
                    reagentsComplete = true,
                    reagents = { [2996] = 6 },
                    outputItemId = 4240,
                    outputCount = 1,
                    bagSlots = 10,
                    outputBindType = 0,
                },
                [101] = {
                    name = "Bolt",
                    learned = true,
                    skillUps = 1,
                    reagentsComplete = true,
                    reagents = { [2589] = 2 },
                    outputItemId = 2996,
                    outputCount = 1,
                },
            },
        }
        local recipient = member("Player-Small")
        recipient.snapshot.professions = {}
        recipient.recipes.professions = {}
        recipient.inventory.bags.equipped = { 8, 16, 16, 16 }
        local plan = RQ.SuppliesService.Plan(RQDB, now)
        equal(plan.bags.conversions[active][101], nil)
        equal(plan.groceries[active][2996].withdraw, 6)
        equal(plan.groceries[active][2996].missing, 0)
        assert(RQ.SuppliesService.SetNeed(2996, 6))
        plan = RQ.SuppliesService.Plan(RQDB, now)
        equal(plan.bags.conversions[active][101], 6)
        equal(plan.groceries[active][2589].missing, 12)
        equal(plan.groceries[active][2996].withdraw, 6)
    end)

    test("bank search separates owners sources quantities and container details without changing stock", function()
        local state = start()
        open(state)
        local other = member("Player-Other", { [3469] = 1 })
        other.inventory.bags.details[3469] = { name = "Rough Copper Boots" }
        local result = RQ.SuppliesService.SearchInventory(RQDB, "copper", now)
        equal(#result.matches, 4)
        equal(#result.coverage, 6)
        local bank = RQ.SuppliesService.SearchInventory(RQDB, "copper", now, nil, "bank")
        equal(#bank.matches, 2)
        equal(bank.matches[1].source, "bank")
        local ore
        for _, match in ipairs(bank.matches) do
            if match.itemId == 2770 then
                ore = match
            end
        end
        equal(ore.quantity, 7)
        equal(#ore.containers, 2)
        local lines = RQ.BagPanel.SearchReport(bank, now)
        contains(lines, "Source: Bank | RECENT")
        contains(lines, "Bank container 6: 3 item(s)")
        contains(lines, "Withdraw manually before crafting")
        state.emit("BANKFRAME_CLOSED")
        equal(#RQ.SuppliesService.SearchInventory(RQDB, "2770", now, nil, "all").matches, 2)
        equal(#RQ.SuppliesService.SearchInventory(RQDB, "2770", now, nil, "bags").matches, 1)
        equal(RQ.SuppliesService.SearchInventory(RQDB, "Copper", now, nil, "invalid"), nil)
        local death = member("Player-Rogue")
        death.identity.fullName = "Quick Death"
        death.inventory.bank = {
            complete = true,
            coherent = true,
            scannedAt = now,
            attemptedAt = now,
            items = { [2840] = 3 },
            tradable = { [2840] = 3 },
            details = { [2840] = { name = "Copper Bar" } },
            containers = { [6] = { capacity = 3, items = { [2840] = 3 } } },
        }
        RQ.Database.Current().identity.fullName = "Quick Slam"
        RQ.Database.Current().inventory.bank = RQ.Snapshot.EmptySource()
        other.identity.fullName = "Tombsie Graves"
        result = RQ.SuppliesService.SearchInventory(RQDB, "copper", now)
        equal(#result.matches, 3)
        equal(result.matches[1].characterName, "Quick Death")
        equal(result.matches[1].source, "bank")
        equal(result.matches[1].quantity, 3)
        equal(result.matches[2].characterName, "Quick Slam")
        equal(result.matches[2].source, "bags")
        equal(result.matches[2].quantity, 10)
        equal(result.matches[3].characterName, "Tombsie Graves")
        equal(result.matches[3].itemName, "Rough Copper Boots")
        equal(result.matches[3].quantity, 1)
    end)

    test("Bags source filter and copy preserve query while bank-only zero results never imply absence", function()
        local state, frames = start(true)
        open(state)
        assert(RQ.MainWindow.SearchBags("Copper", true))
        equal(RQ.MainWindow.bagSource, "all")
        frames.Click(frames.FindButton("Source: all"))
        h.flushTimers()
        equal(RQ.MainWindow.bagSource, "bags")
        equal(#RQ.MainWindow.view.inventorySearch.matches, 1)
        frames.Click(frames.FindButton("Source: bags"))
        h.flushTimers()
        equal(RQ.MainWindow.bagSource, "bank")
        equal(#RQ.MainWindow.view.inventorySearch.matches, 2)
        frames.Click(frames.FindButton("Copy results"))
        local found = false
        for _, widget in ipairs(frames.widgets) do
            if widget.kind == "EditBox" and widget.text:find("Source: Bank", 1, true) then
                found = true
            end
        end
        assert(found)
        assert(RQ.MainWindow.Render())
        equal(RQ.MainWindow.bagSource, "bank")
        assert(RQ.MainWindow.SearchBags("Silver"))
        h.flushTimers()
        contains(RQ.BagPanel.SearchReport(RQ.MainWindow.view.inventorySearch, now), "No known matches")
        assert(RQ.MainWindow.SearchBags(""))
        h.flushTimers()
        equal(RQ.MainWindow.bagSource, "all")
        equal(RQ.MainWindow.view.inventorySection, "recorded")
    end)

    test("bank-only cold names refresh while open and queued work never reads closed storage", function()
        local state = start()
        state.slots[6][2].itemName = nil
        local requests = 0
        _G.C_Item = {
            GetItemInfo = function()
                return nil
            end,
            RequestLoadItemDataByID = function(id)
                equal(id, 2840)
                requests = requests + 1
            end,
        }
        open(state)
        equal(requests, 1)
        equal(RQ.Database.Current().inventory.bank.details[2840].name, nil)
        _G.C_Item.GetItemInfo = function()
            return "Localized Copper Bar"
        end
        state.emit("GET_ITEM_INFO_RECEIVED", 2840, true)
        h.flushTimers()
        equal(RQ.Database.Current().inventory.bank.details[2840].name, "Localized Copper Bar")
        equal(RQ.Database.Current().inventory.bags.items[2840], nil)
        equal(requests, 1)
        state.emit("BANKFRAME_CLOSED")
        local reads = state.reads
        state.emit("GET_ITEM_INFO_RECEIVED", 2840, true)
        h.flushTimers()
        equal(state.reads, reads)
    end)

    test("bank transfer cards are withdrawal guidance not executable attachments", function()
        local state = start()
        open(state)
        member("Player-Recipient").supplies.needs[2770] = 5
        assert(RQ.SuppliesService.SetNeed(2770, 10))
        local cards = RQ.SuppliesService.MailCards(RQDB, now)
        local found
        for _, card in ipairs(cards) do
            if card.title:find("Withdraw before mailing", 1, true) then
                found = card
            end
        end
        assert(found)
        equal(found.actionKind, "supplies")
        contains({ found.body }, "Not attached or credited")
        local pickups = 0
        _G.C_Container.PickupContainerItem = function()
            pickups = pickups + 1
        end
        equal(RQ.SuppliesService.Attach("Player-Recipient", 2770), false)
        equal(pickups, 0)
    end)

    test("out-of-range aggregated bank stock fails validation without leaving old stock eligible", function()
        local state = start()
        open(state)
        state.slots[6][1].stackCount = 1000000
        state.slots[7][1].stackCount = 1000000
        equal(RQ.BankService.Scan(), false)
        equal(RQ.Database.Current().inventory.bank.items[2770], 7)
        equal(RQ.Database.Current().inventory.bank.coherent, false)
        equal(RQ.Database.Current().inventory.bags.complete, false)
        contains(h.messages(), "Bank snapshot not saved")
    end)

    test("timer-unavailable bank updates run immediately and explicit rescan updates both sources", function()
        local state = start()
        _G.C_Timer = nil
        state.emit("BANKFRAME_OPENED")
        equal(RQ.Database.Current().inventory.bank.coherent, true)
        state.slots[0][1].stackCount = 8
        state.slots[6][1].stackCount = 5
        assert(RQ.SnapshotService.Refresh())
        equal(RQ.Database.Current().inventory.bags.items[2770], 8)
        equal(RQ.Database.Current().inventory.bank.items[2770], 9)
        equal(RQCharDB.inventory.bank.items[2770], 9)
    end)
end
