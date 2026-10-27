return function(h)
    local test, equal, contains = h.test, h.equal, h.contains
    local active, recipient, now = "Player-Test-1", "Player-Recipient", 123456789
    local function start()
        RQDB, RQCharDB = nil, nil
        h.fakeCharacter()
        local frames = assert(loadfile("Tests/fixtures/Frames.lua"))()()
        local state = { hooks = {}, inbox = {}, carried = 0, draft = 10, cod = 0 }
        _G.C_Container = {
            GetContainerNumSlots = function(bag)
                return bag == 0 and 2 or 0
            end,
            GetContainerNumFreeSlots = function()
                return 1
            end,
            GetContainerItemInfo = function(bag, slot)
                if bag == 0 and slot == 1 and state.carried > 0 then
                    return {
                        itemID = 2770,
                        stackCount = state.carried,
                        itemName = "Copper Ore",
                        isBound = false,
                        isLocked = false,
                    }
                end
            end,
        }
        _G.MailFrame = _G.CreateFrame("Frame")
        _G.SendMailNameEditBox = _G.CreateFrame("EditBox")
        _G.SendMailNameEditBox:SetText("Quick Slam")
        _G.ATTACHMENTS_MAX_SEND, _G.ATTACHMENTS_MAX_RECEIVE = 12, 16
        _G.GetSendMailItem = function(slot)
            if slot == 1 and state.draft > 0 then
                return "Copper Ore", 2770, 1, state.draft, 1
            end
        end
        _G.GetSendMailCOD = function()
            return state.cod
        end
        _G.SendMail = function()
            error("Addon must never call SendMail")
        end
        _G.TakeInboxItem = function()
            error("Addon must never collect mail")
        end
        _G.ReturnInboxItem = function()
            error("Addon must never return mail")
        end
        _G.hooksecurefunc = function(name, callback)
            state.hooks[name] = callback
        end
        _G.C_Mail = {
            IsCommandPending = function()
                return state.pending or false
            end,
        }
        _G.GetInboxNumItems = function()
            return #state.inbox, state.total or #state.inbox
        end
        _G.GetInboxHeaderInfo = function(index)
            local message = state.inbox[index]
            if message then
                return nil,
                    nil,
                    message.sender,
                    message.subject,
                    0,
                    message.cod or 0,
                    29,
                    message.count > 0 and 1 or nil,
                    false,
                    message.returned or false
            end
        end
        _G.GetInboxItem = function(index, slot)
            local message = state.inbox[index]
            if message and message.count > 0 and slot == 1 then
                return "Copper Ore", 2770, 1, message.count, 1
            end
        end
        h.loadAddon()
        RQ.MainWindow.realm, RQ.MainWindow.group = "all", "all"
        frames.Emit("PLAYER_LOGIN")
        assert(RQ.Database.Register("add"))
        assert(RQ.Database.SetFullName("Sender Name"))
        local record = RQ.Util.Copy(RQ.Database.Current())
        record.identity = {
            ruleset = "PVE",
            faction = "Horde",
            guid = recipient,
            fullName = "Quick Slam",
            realm = "TestRealm PVE",
            class = "WARRIOR",
        }
        record.registration = "pending"
        record.supplies = { needs = { [2770] = 20 }, goals = {} }
        RQDB.characters[recipient] = record
        assert(RQ.Database.Register("add", recipient))
        frames.Emit("MAIL_SHOW")
        h.flushTimers()
        state.emit = frames.Emit
        return state
    end
    local function send(state, verified)
        if verified then
            assert(RQ.MailService.Verify(true))
        end
        state.hooks.SendMail("Quick Slam", "Supplies")
        state.emit("MAIL_SEND_SUCCESS")
        state.draft = 0
        h.flushTimers()
        return RQDB.mailTracking.transfers[1]
    end
    local function visit(state, count)
        RQ.Database.activeId = recipient
        _G.UnitGUID = function()
            return recipient
        end
        state.inbox = { { sender = "Sender Name", subject = "Supplies", count = count } }
        state.emit("MAIL_INBOX_UPDATE")
        h.flushTimers()
        return RQ.Database.Current().inventory
    end

    test("mail migration is idempotent and invalid ledger writes are atomic", function()
        start()
        local old = RQ.Util.Copy(RQDB)
        old.schemaVersion, old.mailTracking = 9, nil
        local account, character = RQ.Migrations.Prepare(old, RQCharDB)
        equal(account.schemaVersion, 19)
        equal(account.mailTracking.nextId, 1)
        equal(old.mailTracking, nil)
        local again = RQ.Migrations.Prepare(account, character)
        equal(again.mailTracking.nextId, 1)
        equal(again.characters[active].inventory.mail.coherent, false)
        local invalid = { nextId = 0, transfers = {} }
        equal(RQ.Database.SaveMailTracking(invalid), false)
        equal(RQDB.mailTracking.nextId, 1)
        local inventory = RQ.Util.Copy(RQ.Database.Current().inventory)
        inventory.mail.items[2770] = -1
        equal(RQ.Database.SaveMailTracking(RQDB.mailTracking, inventory, active), false)
        equal(RQ.Database.Current().inventory.mail.items[2770], nil)
    end)

    test("passive send defaults to uncertain and explicit confirmation covers but never creates surplus", function()
        local state = start()
        local transfer = send(state)
        equal(transfer.status, "uncertain")
        equal(transfer.signal, true)
        equal(transfer.items[2770], 10)
        equal(RQ.SuppliesService.Plan(RQDB, now).groceries[recipient][2770].missing, 20)
        assert(RQ.MailService.Resolve(1, "sent"))
        local need = RQ.SuppliesService.Plan(RQDB, now).groceries[recipient][2770]
        equal(need.pendingMail, 10)
        equal(need.missing, 10)
        equal(RQ.InventoryAvailability.Materials(RQDB.characters[recipient], now, 48)[2770], nil)
        assert(RQ.MailService.Resolve(1, "close"))
        equal(RQ.SuppliesService.Plan(RQDB, now).groceries[recipient][2770].missing, 20)
    end)

    test("automatic orange needs credit confirmed mail without creating carried stock", function()
        local state = start()
        local record = RQDB.characters[recipient]
        record.supplies.needs = {}
        record.snapshot.professions[164] = { name = "Blacksmithing", skill = 10, maxSkill = 75 }
        record.recipes.professions[164] = {
            name = "Blacksmithing",
            complete = true,
            scannedAt = now,
            recipes = {
                [900] = {
                    name = "Test orange craft",
                    learned = true,
                    difficulty = 0,
                    skillUps = 1,
                    reagentsComplete = true,
                    reagents = { [2770] = 10 },
                },
            },
        }
        equal(RQ.SuppliesService.Plan(RQDB, now).groceries[recipient][2770].missing, 10)
        send(state)
        equal(RQ.SuppliesService.Plan(RQDB, now).groceries[recipient][2770].missing, 10)
        assert(RQ.MailService.Resolve(1, "sent"))
        local need = RQ.SuppliesService.Plan(RQDB, now).groceries[recipient][2770]
        equal(need.target, 10)
        equal(need.orangeTarget, 10)
        equal(need.missing, 0)
        equal(need.inTransit, 10)
        equal(RQ.InventoryAvailability.Materials(RQDB.characters[recipient], now, 48)[2770], nil)
        assert(RQ.MailService.Resolve(1, "close"))
        equal(RQ.SuppliesService.Plan(RQDB, now).groceries[recipient][2770].missing, 10)
    end)

    test("verified send success is unique and expires without hiding deficits", function()
        local state = start()
        equal(send(state, true).status, "sent")
        state.emit("MAIL_SEND_SUCCESS")
        equal(#RQ.Util.Keys(RQDB.mailTracking.transfers), 1)
        equal(RQ.MailTracker.Coverage(RQDB, recipient, now, true).pending[2770], 10)
        equal(RQ.MailTracker.Coverage(RQDB, recipient, now + 1000000, true).pending[2770], nil)
        _G.GetBuildInfo = function()
            return "new-client", "new-build", "", 16001
        end
        equal(RQ.MailService.Verified(), false)
    end)

    test("confirmed shipment coverage is suspended if a character changes or loses its trade group", function()
        local state = start()
        equal(send(state, true).status, "sent")
        local identity = RQDB.characters[recipient].identity
        equal(RQ.MailTracker.Coverage(RQDB, recipient, now, true).pending[2770], 10)
        for field, value in pairs({ faction = "Alliance", ruleset = "PVP" }) do
            local original = identity[field]
            identity[field] = value
            equal(RQ.MailTracker.Coverage(RQDB, recipient, now, true).pending[2770], nil)
            identity[field] = nil
            equal(RQ.MailTracker.Coverage(RQDB, recipient, now, true).pending[2770], nil)
            identity[field] = original
        end
        equal(RQ.MailTracker.Coverage(RQDB, recipient, now, true).pending[2770], 10)
    end)

    test("non-roster ambiguous cross-realm and COD sends do not become shipments", function()
        local state = start()
        local count = #h.messages()
        state.hooks.SendMail("External Friend", "Gift")
        equal(#h.messages(), count)
        equal(next(RQDB.mailTracking.transfers), nil)
        RQDB.characters[recipient].identity.realm = "Elsewhere"
        state.hooks.SendMail("Quick Slam", "Gift")
        equal(next(RQDB.mailTracking.transfers), nil)
        RQDB.characters[recipient].identity.realm = "TestRealm PVE"
        state.cod = 10
        state.hooks.SendMail("Quick Slam", "Gift")
        equal(next(RQDB.mailTracking.transfers), nil)
        contains(h.messages(), "COD")
        local duplicate = RQ.Util.Copy(RQDB.characters[recipient])
        duplicate.identity.guid, duplicate.registration = "Duplicate", "pending"
        RQDB.characters.Duplicate = duplicate
        assert(RQ.Database.Register("add", "Duplicate"))
        equal(RQ.MailTracker.Resolve(RQDB, "Quick Slam", active), nil)
    end)

    test("failed empty overlapping closed and reloaded attempts never auto-confirm", function()
        local state = start()
        assert(RQ.MailService.Verify(true))
        state.draft = 0
        state.hooks.SendMail("Quick Slam", "Supplies")
        equal(next(RQDB.mailTracking.transfers), nil)
        state.draft = 10
        state.hooks.SendMail("Quick Slam", "Supplies")
        state.emit("MAIL_FAILED")
        equal(RQDB.mailTracking.transfers[1].status, "failed")
        state.hooks.SendMail("Quick Slam", "Supplies")
        state.hooks.SendMail("Quick Slam", "Supplies")
        state.emit("MAIL_SEND_SUCCESS")
        equal(RQDB.mailTracking.transfers[2].status, "uncertain")
        equal(RQDB.mailTracking.transfers[3].status, "uncertain")
        state.hooks.SendMail("Quick Slam", "Supplies")
        state.emit("MAIL_CLOSED")
        state.emit("MAIL_SEND_SUCCESS")
        equal(RQDB.mailTracking.transfers[4].status, "uncertain")
        state.emit("MAIL_SHOW")
        state.hooks.SendMail("Quick Slam", "Supplies")
        RQ.MailService.Initialize()
        equal(RQDB.mailTracking.transfers[5].status, "uncertain")
    end)

    test(
        "inbox arrival replaces pending credit once and manual partial/full collection conserves quantities",
        function()
            local state = start()
            send(state, true)
            local inventory = visit(state, 10)
            equal(inventory.mail.items[2770], 10)
            equal(RQDB.mailTracking.transfers[1].status, "inbox")
            local coverage = RQ.MailTracker.Coverage(RQDB, recipient, now, true)
            equal(coverage.pending[2770], nil)
            equal(coverage.inbox[2770], 10)
            state.hooks.TakeInboxItem(1, 1)
            state.carried, state.inbox[1].count = 4, 6
            state.emit("MAIL_INBOX_UPDATE")
            h.flushTimers()
            equal(RQDB.mailTracking.transfers[1].remaining[2770], 6)
            equal(RQDB.mailTracking.transfers[1].status, "inbox")
            local need = RQ.SuppliesService.Plan(RQDB, now, true).groceries[recipient][2770]
            equal(need.have, 4)
            equal(need.collect, 6)
            equal(need.missing, 10)
            state.hooks.TakeInboxItem(1, 1)
            state.carried, state.inbox = 10, {}
            state.emit("MAIL_INBOX_UPDATE")
            h.flushTimers()
            equal(RQDB.mailTracking.transfers[1].status, "collected")
            equal(RQ.Database.Current().inventory.mail.items[2770], nil)
            equal(RQCharDB.inventory.bags.items[2770], 10)
        end
    )

    test("duplicate inbox messages stay unattributed but physical stock is counted once", function()
        local state = start()
        send(state, true)
        visit(state, 10)
        state.inbox[2] = RQ.Util.Copy(state.inbox[1])
        state.emit("MAIL_INBOX_UPDATE")
        h.flushTimers()
        equal(RQDB.mailTracking.transfers[1].status, "uncertain")
        local coverage = RQ.MailTracker.Coverage(RQDB, recipient, now, true)
        equal(coverage.inbox[2770], 20)
        equal(coverage.pending[2770], nil)
        state.inbox[1], state.inbox[2] = state.inbox[2], state.inbox[1]
        state.emit("MAIL_INBOX_UPDATE")
        h.flushTimers()
        equal(RQDB.mailTracking.transfers[1].status, "uncertain")
        state.inbox[2] = nil
        state.emit("MAIL_INBOX_UPDATE")
        h.flushTimers()
        equal(RQDB.mailTracking.transfers[1].status, "uncertain")
        equal(RQDB.mailTracking.transfers[1].ambiguous, true)
        equal(RQ.MailService.Resolve(1, "sent"), false)
        equal(RQ.MailTracker.Coverage(RQDB, recipient, now, true).inbox[2770], 10)
    end)

    test("disappearance without take evidence and explicit returns are not inferred collections", function()
        for _, returned in ipairs({ false, true }) do
            local state = start()
            send(state, true)
            visit(state, 10)
            if returned then
                state.hooks.ReturnInboxItem(1)
            end
            state.carried, state.inbox = 10, {}
            state.emit("MAIL_INBOX_UPDATE")
            h.flushTimers()
            equal(RQDB.mailTracking.transfers[1].status, "uncertain")
            equal(RQ.MailTracker.Coverage(RQDB, recipient, now, true).pending[2770], nil)
        end
    end)

    test("unloaded pending interrupted and inconsistent inbox scans retain unconfirmed caches", function()
        local state = start()
        send(state, true)
        visit(state, 10)
        for _, unavailable in ipairs({ "total", "pending" }) do
            state[unavailable] = unavailable == "total" and 2 or true
            state.emit("MAIL_INBOX_UPDATE")
            h.flushTimers()
            local mail = RQ.Database.Current().inventory.mail
            equal(mail.items[2770], 10)
            equal(mail.coherent, false)
            equal(RQ.MailTracker.Coverage(RQDB, recipient, now, true).inbox[2770], nil)
            state[unavailable] = nil
            assert(RQ.MailService.Scan())
        end
        state.emit("MAIL_INBOX_UPDATE")
        state.emit("MAIL_CLOSED")
        h.flushTimers()
        equal(RQ.Database.Current().inventory.mail.coherent, false)
        equal(RQ.Database.Current().inventory.mail.items[2770], 10)
    end)

    test("in-mail search and shipment dashboard show recipient ownership and provisional coverage", function()
        local state = start()
        send(state, true)
        local result = RQ.SuppliesService.SearchInventory(RQDB, "Copper", now, nil, "mail")
        equal(#result.matches, 1)
        equal(result.matches[1].characterId, recipient)
        equal(result.matches[1].pending, 10)
        equal(result.matches[1].quantity, 10)
        assert(RQ.MainWindow.Open("shipments"), table.concat(h.messages(), "\n"))
        equal(RQ.MainWindow.view.tab, "shipments")
        contains({ RQ.MainWindow.view.cards[2].body }, "Quick Slam")
        visit(state, 10)
        result = RQ.SuppliesService.SearchInventory(RQDB, "2770", now, recipient, "mail")
        equal(#result.matches, 1)
        equal(result.matches[1].quantity, 10)
        equal(result.matches[1].pending, 0)
    end)

    test("external incoming COD and returned messages never invent roster send histories", function()
        local state = start()
        assert(RQ.MailService.Verify(true))
        state.inbox = {
            { sender = "External", subject = "Gift", count = 7 },
            { sender = "External", subject = "COD", count = 3, cod = 100 },
            { sender = "Quick Slam", subject = "Return", count = 2, returned = true },
        }
        assert(RQ.MailService.Scan())
        equal(next(RQDB.mailTracking.transfers), nil)
        equal(RQ.Database.Current().inventory.mail.items[2770], 12)
        equal(RQ.MailTracker.Coverage(RQDB, active, now, true).inbox[2770], 7)
    end)

    test("new login disables cached inbox and unobserved incoming credit until mailbox verification", function()
        local state = start()
        send(state, true)
        RQ.Database.activeId = recipient
        _G.UnitGUID = function()
            return recipient
        end
        RQ.MailService.Initialize()
        equal(RQ.MailTracker.Coverage(RQDB, recipient, now, true).pending[2770], nil)
        visit(state, 10)
        equal(RQ.MailTracker.Coverage(RQDB, recipient, now, true).inbox[2770], 10)
        RQ.MailService.Initialize()
        equal(RQ.MailTracker.Coverage(RQDB, recipient, now, true).inbox[2770], nil)
    end)

    test("turning off verified mode stops automatic credit and returned mail invalidates pending delivery", function()
        local state = start()
        send(state, true)
        assert(RQ.MailService.Verify(false))
        equal(RQ.SuppliesService.Plan(RQDB, now, RQ.MailService.Verified()).groceries[recipient][2770].missing, 20)
        assert(RQ.MailService.Verify(true))
        state.inbox = { { sender = "Quick Slam", subject = "Supplies", count = 10, returned = true } }
        assert(RQ.MailService.Scan())
        equal(RQDB.mailTracking.transfers[1].status, "uncertain")
        equal(RQ.MailTracker.Coverage(RQDB, recipient, now, true).pending[2770], nil)
    end)

    test("late success, stale take evidence and native contract mismatch stay uncertain", function()
        local state = start()
        assert(RQ.MailService.Verify(true))
        state.hooks.SendMail("Quick Slam", "Supplies")
        _G.GetServerTime = function()
            return now + 31
        end
        state.emit("MAIL_SEND_SUCCESS")
        equal(RQDB.mailTracking.transfers[1].status, "uncertain")
        _G.GetServerTime = function()
            return now
        end
        visit(state, 10)
        state.hooks.TakeInboxItem(1, 1)
        _G.GetServerTime = function()
            return now + 31
        end
        state.inbox, state.carried = {}, 10
        h.flushTimers()
        equal(RQDB.mailTracking.transfers[1].status, "uncertain")
        _G.GetInboxNumItems = function()
            return 1, 1
        end
        _G.GetInboxHeaderInfo = function()
            return nil, nil, "Sender Name", "Supplies", 0, 0, 29, true
        end
        local pair, err = RQ.Api.GetMailInventory(recipient)
        equal(pair, nil)
        contains({ err }, "header contract")
    end)

    test("multiple same-subject transfers and inbox reordering cannot silently pick a shipment", function()
        local state = start()
        send(state, true)
        state.draft = 10
        state.hooks.SendMail("Quick Slam", "Supplies")
        state.emit("MAIL_SEND_SUCCESS")
        state.draft = 0
        h.flushTimers()
        visit(state, 10)
        equal(RQDB.mailTracking.transfers[1].status, "uncertain")
        equal(RQDB.mailTracking.transfers[2].status, "uncertain")
        equal(RQ.MailTracker.Coverage(RQDB, recipient, now, true).inbox[2770], 10)
        state.inbox[2] = { sender = "External", subject = "Gift", count = 4 }
        assert(RQ.MailService.Scan())
        state.inbox[1], state.inbox[2] = state.inbox[2], state.inbox[1]
        assert(RQ.MailService.Scan())
        equal(RQDB.mailTracking.transfers[1].status, "uncertain")
        equal(RQ.MailTracker.Coverage(RQDB, recipient, now, true).inbox[2770], 14)
    end)

    test("read changes and ledger validation failures cannot publish fresh-looking inbox counts", function()
        local state = start()
        visit(state, 10)
        local calls, native = 0, _G.GetInboxItem
        _G.GetInboxItem = function(index, slot)
            if slot == 1 then
                calls = calls + 1
                state.inbox[1].count = calls
            end
            return native(index, slot)
        end
        local pair, err = RQ.Api.GetMailInventory(recipient)
        equal(pair, nil)
        contains({ err }, "changed")
        _G.GetInboxItem = native
        state.inbox[1].count = 1000001
        equal(RQ.MailService.Scan(), false)
        equal(RQ.Database.Current().inventory.mail.items[2770], 10)
        equal(RQ.Database.Current().inventory.mail.coherent, false)
        local ledger = RQ.Util.Copy(RQDB.mailTracking)
        ledger.nextId = 0
        equal(RQ.Database.SaveMailTracking(ledger), false)
        equal(RQDB.mailTracking.nextId, 1)
    end)
end
