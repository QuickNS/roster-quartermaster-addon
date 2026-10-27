return function(h)
    local test, equal, contains = h.test, h.equal, h.contains
    local function start()
        h.fakeCharacter()
        local frames = assert(loadfile("Tests/fixtures/Frames.lua"))()()
        local state = { attachments = {}, pickups = 0, clicks = 0, sent = 0 }
        state.items = {
            { itemID = 2589, stackCount = 30, itemName = "Linen Cloth", isBound = false, isLocked = false },
            { itemID = 2770, stackCount = 20, itemName = "Copper Ore", isBound = false, isLocked = false },
        }
        _G.C_Container = {
            GetContainerNumSlots = function(bag)
                return bag == 0 and 16 or 0
            end,
            GetContainerNumFreeSlots = function(bag)
                return bag == 0 and 10 or 0
            end,
            GetContainerItemInfo = function(bag, slot)
                return bag == 0 and state.items[slot] or nil
            end,
        }
        _G.C_Item = {
            GetItemInfoInstant = function(id)
                return id, "", "", "", 0, 7, id == 2589 and 5 or 7
            end,
        }
        local function pickup(bag, slot, count)
            assert(not state.cursor, "cursor must be empty")
            equal(bag, 0)
            local item = state.items[slot]
            count = count or item.stackCount
            assert(count > 0 and count <= item.stackCount)
            state.cursor = { item = RQ.Util.Copy(item), count = count, slot = slot }
            item.stackCount = item.stackCount - count
            if item.stackCount == 0 then
                state.items[slot] = nil
            end
            state.pickups = state.pickups + 1
            if state.afterPickup then
                state.afterPickup()
            end
        end
        _G.C_Container.PickupContainerItem = function(bag, slot, ...)
            equal(select("#", ...), 0)
            pickup(bag, slot)
        end
        _G.C_Container.SplitContainerItem = pickup
        _G.GetCursorInfo = function()
            if state.cursor then
                return "item", state.cursor.item.itemID
            end
        end
        _G.ClearCursor = function()
            local held = state.cursor
            if held then
                local existing = state.items[held.slot]
                held.item.stackCount = held.count + (existing and existing.stackCount or 0)
                state.items[held.slot] = held.item
                state.cursor = nil
            end
        end
        _G.ATTACHMENTS_MAX_SEND = 12
        _G.GetSendMailItem = function(slot)
            local item = state.attachments[slot]
            if item then
                return "Attachment", item.itemId, 0, item.count, 1
            end
        end
        _G.ClickSendMailItemButton = function(slot)
            state.clicks = state.clicks + 1
            if state.failAt == state.clicks then
                error("Attachment blocked")
            end
            assert(not state.attachments[slot], "must not replace an attachment")
            assert(state.cursor)
            state.attachments[slot] = { itemId = state.cursor.item.itemID, count = state.cursor.count }
            state.cursor = nil
            frames.Emit("MAIL_SEND_INFO_UPDATE")
        end
        _G.SendMail = function()
            state.sent = state.sent + 1
            error("The addon must never send mail")
        end
        _G.MailFrame = _G.CreateFrame("Frame")
        _G.SendMailFrame = _G.CreateFrame("Frame", nil, _G.MailFrame)
        _G.SendMailFrame:Hide()
        _G.SendMailNameEditBox = _G.CreateFrame("EditBox", nil, _G.SendMailFrame)
        _G.MailFrameTab2 = {
            Click = function()
                _G.SendMailFrame:Show()
            end,
        }
        h.loadAddon()
        frames.Emit("PLAYER_LOGIN")
        assert(RQ.Database.Register("add"))
        local recipient = RQ.Util.Copy(RQ.Database.Current())
        recipient.identity = {
            guid = "Player-Recipient",
            displayName = "Quick Slam",
            nameComplete = true,
            realm = "TestRealm PVE",
            faction = "Horde",
            ruleset = "PVE",
        }
        recipient.registration = "pending"
        recipient.snapshot.professions = {}
        recipient.inventory.bags.items = {}
        recipient.inventory.bags.details = {}
        recipient.inventory.bags.tradable = {}
        recipient.supplies = { needs = {}, goals = {} }
        RQDB.characters["Player-Recipient"] = recipient
        assert(RQ.Database.Register("add", "Player-Recipient"))
        assert(RQ.SuppliesService.SetNeed(2589, 25, "Player-Recipient"))
        assert(RQ.SuppliesService.SetNeed(2770, 5, "Player-Recipient"))
        frames.Emit("MAIL_SHOW")
        return state, frames, recipient
    end

    test("mailbox command groups proposals and only a click attaches exact quantities", function()
        local state, frames = start()
        _G.SlashCmdList.ROSTERQUARTERMASTER("mail")
        equal(RQ.MainWindow.tab, "mail")
        equal(state.pickups, 0)
        frames.Click(frames.FindButton("Attach item"))
        equal(state.attachments[1].itemId, 2589)
        equal(state.attachments[1].count, 25)
        equal(state.items[1].stackCount, 5)
        equal(_G.SendMailNameEditBox:GetText(), "Quick Slam")
        equal(state.sent, 0)
        h.flushTimers()
        frames.Click(frames.FindButton("Attach all"))
        equal(state.attachments[2].itemId, 2770)
        equal(state.attachments[2].count, 5)
        equal(state.items[2].stackCount, 15)
        equal(state.pickups, 2)
        equal(RQ.SuppliesService.Attach("Player-Recipient", 2589), false)
        equal(state.pickups, 2)
        equal(state.sent, 0)
        contains(h.messages(), "click Blizzard's Send yourself")
    end)

    test("attach all preflights capacity without moving or addressing anything", function()
        local state = start()
        _G.ATTACHMENTS_MAX_SEND = 1
        local ok, err = RQ.SuppliesService.Attach("Player-Recipient")
        equal(ok, false)
        contains({ err }, "Not enough free mail attachment slots")
        equal(state.pickups, 0)
        equal(_G.SendMailNameEditBox:GetText(), "")
        equal(state.items[1].stackCount, 30)
        equal(state.sent, 0)
    end)

    test("attachments never change a different recipient or take over anonymous attachments", function()
        local state = start()
        _G.SendMailNameEditBox:SetText("Quick Death")
        local ok, err = RQ.SuppliesService.Attach("Player-Recipient")
        equal(ok, false)
        contains({ err }, "different recipient")
        equal(_G.SendMailNameEditBox:GetText(), "Quick Death")
        equal(state.pickups, 0)
        _G.SendMailNameEditBox:SetText("")
        state.attachments[1] = { itemId = 999, count = 1 }
        ok, err = RQ.SuppliesService.Attach("Player-Recipient")
        equal(ok, false)
        contains({ err }, "Existing attachments have no recipient")
        equal(state.attachments[1].itemId, 999)
        equal(state.pickups, 0)
    end)

    test("attachments preserve unrelated same-recipient contents and use free slots", function()
        local state = start()
        _G.SendMailNameEditBox:SetText("Quick Slam")
        state.attachments[1] = { itemId = 999, count = 1 }
        local ok = RQ.SuppliesService.Attach("Player-Recipient")
        equal(ok, true)
        equal(state.attachments[1].itemId, 999)
        equal(state.attachments[2].count, 25)
        equal(state.attachments[3].count, 5)
        equal(state.sent, 0)
    end)

    test("closed mailbox combat and occupied cursor prevent all attachment actions", function()
        local state, frames = start()
        frames.Emit("MAIL_CLOSED")
        equal(RQ.SuppliesService.Attach("Player-Recipient"), false)
        frames.Emit("MAIL_SHOW")
        frames.combat = true
        equal(RQ.SuppliesService.Attach("Player-Recipient"), false)
        frames.combat = false
        state.cursor = { item = { itemID = 999 }, count = 1, slot = 9 }
        equal(RQ.SuppliesService.Attach("Player-Recipient"), false)
        equal(state.cursor.item.itemID, 999)
        equal(state.pickups, 0)
        state.cursor = nil
        _G.MailFrame:Hide()
        equal(RQ.SuppliesService.Attach("Player-Recipient"), false)
        equal(state.pickups, 0)
    end)

    test("recipient names must be verified unique and on the observed sender realm", function()
        local state, _, recipient = start()
        recipient.identity.nameComplete = nil
        local ok, err = RQ.SuppliesService.Attach("Player-Recipient")
        equal(ok, false)
        contains({ err }, "full name is unverified")
        recipient.identity.fullName = "Quick Slam"
        recipient.identity.realm = "Other Realm"
        equal(RQ.SuppliesService.Attach("Player-Recipient"), false)
        recipient.identity.realm = "TestRealm PVE"
        RQDB.characters["Player-Duplicate"] = RQ.Util.Copy(recipient)
        RQDB.characters["Player-Duplicate"].identity.guid = "Player-Duplicate"
        ok, err = RQ.SuppliesService.Attach("Player-Recipient")
        equal(ok, false)
        contains({ err }, "Ambiguous recipient")
        equal(state.pickups, 0)
    end)

    test("attachment clicks recheck ruleset and faction before touching the native draft", function()
        local state, _, recipient = start()
        for field, value in pairs({ faction = "Alliance", ruleset = "PVP" }) do
            local original = recipient.identity[field]
            recipient.identity[field] = value
            local ok, err = RQ.SuppliesService.Attach("Player-Recipient")
            equal(ok, false)
            contains({ err }, "ruleset or faction")
            equal(state.pickups, 0)
            recipient.identity[field] = nil
            equal(RQ.SuppliesService.Attach("Player-Recipient"), false)
            equal(state.pickups, 0)
            recipient.identity[field] = original
        end
        equal(RQ.SuppliesService.Attach("Player-Recipient"), true)
        assert(state.pickups > 0)
    end)

    test("bound locked and insufficient stacks cannot satisfy an attachment request", function()
        local state = start()
        state.items[1].isBound = true
        equal(RQ.Api.AttachMailItems("Quick Slam", { [2589] = 25 }), 0)
        state.items[1].isBound, state.items[1].isLocked = false, true
        equal(RQ.Api.AttachMailItems("Quick Slam", { [2589] = 25 }), 0)
        state.items[1].isLocked = nil
        equal(RQ.Api.AttachMailItems("Quick Slam", { [2589] = 25 }), 0)
        state.items[1].isLocked = false
        equal(RQ.Api.AttachMailItems("Quick Slam", { [2589] = 31 }), 0)
        equal(state.pickups, 0)
    end)

    test("attachment failure stops the batch restores the owned cursor and reports partial progress", function()
        local state = start()
        state.failAt = 2
        local ok, err = RQ.SuppliesService.Attach("Player-Recipient")
        equal(ok, false)
        contains({ err }, "1 stack(s) confirmed attached")
        contains({ err }, "nothing was sent")
        equal(state.attachments[1].count, 25)
        equal(state.attachments[2], nil)
        equal(state.items[2].stackCount, 20)
        equal(state.cursor, nil)
        equal(state.sent, 0)
    end)

    test("mailbox closure or recipient change during pickup restores the held item", function()
        local state, frames = start()
        state.afterPickup = function()
            frames.Emit("MAIL_CLOSED")
        end
        equal(RQ.SuppliesService.Attach("Player-Recipient"), false)
        equal(state.items[1].stackCount, 30)
        equal(state.cursor, nil)
        equal(state.clicks, 0)
        frames.Emit("MAIL_SHOW")
        state.afterPickup = function()
            _G.SendMailNameEditBox:SetText("Quick Death")
        end
        equal(RQ.SuppliesService.Attach("Player-Recipient"), false)
        equal(state.items[1].stackCount, 30)
        equal(state.clicks, 0)
        _G.SendMailNameEditBox:SetText("Quick Slam")
        state.afterPickup = function()
            frames.combat = true
        end
        equal(RQ.SuppliesService.Attach("Player-Recipient"), false)
        equal(state.items[1].stackCount, 30)
        equal(state.clicks, 0)
    end)

    test("whole and partial stacks fill separate attachment slots with exact combined quantity", function()
        local state = start()
        state.items[1].stackCount = 20
        state.items[3] = { itemID = 2589, stackCount = 10, itemName = "Linen Cloth", isBound = false, isLocked = false }
        local ok = RQ.SuppliesService.Attach("Player-Recipient", 2589)
        equal(ok, true)
        equal(state.attachments[1].count, 20)
        equal(state.attachments[2].count, 5)
        equal(state.items[1], nil)
        equal(state.items[3].stackCount, 5)
        equal(state.sent, 0)
    end)

    test("text mail reports remain available at an open mailbox without attaching", function()
        local state, frames = start()
        _G.SlashCmdList.ROSTERQUARTERMASTER("mail text")
        contains({ frames.FindKind("EditBox"):GetText() }, "MAIL PROPOSALS")
        equal(state.pickups, 0)
        equal(state.sent, 0)
    end)

    test("attachment limit comes from the client and preserves the first fifteen filled slots", function()
        local state = start()
        _G.ATTACHMENTS_MAX_SEND = 16
        _G.SendMailNameEditBox:SetText("Quick Slam")
        for slot = 1, 15 do
            state.attachments[slot] = { itemId = 999, count = 1 }
        end
        assert(RQ.SuppliesService.Attach("Player-Recipient", 2589))
        equal(state.attachments[16].itemId, 2589)
        equal(state.attachments[16].count, 25)
        for slot = 1, 15 do
            equal(state.attachments[slot].itemId, 999)
        end
        equal(state.sent, 0)
    end)

    test("missing attachment APIs and unconfirmed native moves do not report success", function()
        local state = start()
        local split = _G.C_Container.SplitContainerItem
        _G.C_Container.SplitContainerItem = nil
        local ok, err = RQ.SuppliesService.Attach("Player-Recipient", 2589)
        equal(ok, false)
        contains({ err }, "APIs unavailable")
        equal(state.pickups, 0)
        _G.C_Container.SplitContainerItem = split
        _G.ClickSendMailItemButton = function() end
        ok, err = RQ.SuppliesService.Attach("Player-Recipient", 2589)
        equal(ok, false)
        contains({ err }, "Attachment not yet confirmed")
        equal(state.items[1].stackCount, 30)
        equal(state.cursor, nil)
        equal(next(state.attachments), nil)
        equal(state.sent, 0)
    end)

    test("a higher capacity bag proposal attaches to a recipient with an occupied smaller bag", function()
        local state, _, recipient = start()
        state.items = {
            { itemID = 4240, stackCount = 1, itemName = "Ten Slot Bag", isBound = false, isLocked = false },
        }
        _G.C_Container.GetContainerNumSlots = function()
            return 16
        end
        _G.C_Item.GetItemInfoInstant = function(id)
            return id, "", "", "", 0, 1, 0
        end
        _G.CONTAINER_SLOTS = "%d Slot %s"
        _G.C_TooltipInfo = {
            GetItemByID = function()
                return { lines = { { leftText = "10 Slot Bag" } } }
            end,
        }
        recipient.inventory.bags.equipped = { 6, 16, 16, 16 }
        recipient.supplies.needs = {}
        assert(RQ.SuppliesService.ScanBags())
        local report = RQ.SuppliesService.Evaluate(RQDB, RQ.Database.activeId, 123456789)
        equal(#report.proposals, 1)
        contains({ report.proposals[1].reason }, "6 -> 10")
        assert(RQ.SuppliesService.Attach("Player-Recipient", 4240))
        equal(state.attachments[1].itemId, 4240)
        equal(state.attachments[1].count, 1)
        equal(state.sent, 0)
        equal(state.items[1], nil)
    end)

    local function rogueMail()
        local state, frames, recipient = start()
        recipient.identity.class = "ROGUE"
        recipient.supplies.needs = {}
        state.items = {
            { itemID = 4632, stackCount = 1, itemName = "Box", isBound = false, isLocked = false },
            {
                itemID = 4632,
                stackCount = 1,
                itemName = "Box",
                isBound = false,
                isLocked = false,
                needsUnlocking = true,
            },
        }
        _G.LOCKED = "Locked"
        _G.C_TooltipInfo = {
            GetBagItem = function(bag, slot)
                local item = bag == 0 and state.items[slot]
                return item
                    and {
                        lines = {
                            { leftText = item.itemName },
                            { leftText = item.needsUnlocking and "Locked" or "Unlocked" },
                        },
                    }
            end,
        }
        assert(RQ.SuppliesService.ScanBags())
        return state, frames, recipient
    end

    test("Rogue mail clicks attach the locked instance rather than an unlocked box with the same ID", function()
        local state, frames = rogueMail()
        _G.SlashCmdList.ROSTERQUARTERMASTER("mail")
        frames.Click(frames.FindButton("Attach item"))
        equal(state.items[2], nil)
        equal(state.items[1].itemID, 4632)
        equal(state.attachments[1].itemId, 4632)
        equal(state.attachments[1].count, 1)
        equal(state.sent, 0)
    end)

    test("mixed explicit and unlocking requests attach exact totals without duplicate stack pickups", function()
        local state, _, recipient = rogueMail()
        recipient.supplies.needs[4632] = 1
        state.items[2].stackCount = 3
        assert(RQ.SuppliesService.Attach("Player-Recipient"))
        equal(state.attachments[1].count, 3)
        equal(state.items[1].itemID, 4632)
        equal(state.items[2], nil)
        equal(state.pickups, 1)
        equal(state.sent, 0)
    end)

    test("lock evidence is rechecked before pickup and unavailable or changed locks stop attachment", function()
        local state = rogueMail()
        local calls = 0
        local original = _G.C_TooltipInfo.GetBagItem
        _G.C_TooltipInfo.GetBagItem = function(bag, slot)
            if slot == 2 then
                calls = calls + 1
                if calls >= 2 then
                    state.items[2].needsUnlocking = false
                end
            end
            return original(bag, slot)
        end
        local attached, err = RQ.Api.AttachMailItems("Quick Slam", { [4632] = 1 }, { [4632] = 1 })
        equal(attached, 0)
        contains({ err }, "bag stack changed")
        equal(state.pickups, 0)
        state.items[2].needsUnlocking = true
        _G.C_TooltipInfo.GetBagItem = nil
        attached, err = RQ.Api.AttachMailItems("Quick Slam", { [4632] = 1 }, { [4632] = 1 })
        equal(attached, 0)
        contains({ err }, "evidence")
        equal(state.pickups, 0)
        equal(state.sent, 0)
    end)

    test("invalid unlocking quotas are rejected before any item is moved", function()
        local state = rogueMail()
        for _, invalid in ipairs({ false, { [4632] = 2 }, { [4632] = -1 }, { [999] = 1 } }) do
            local attached, err = RQ.Api.AttachMailItems("Quick Slam", { [4632] = 1 }, invalid)
            equal(attached, 0)
            contains({ err }, "Invalid locked-container")
        end
        equal(state.pickups, 0)
    end)

    test("failed cursor restoration reports the held item and stops further actions", function()
        local state = start()
        state.failAt = 1
        _G.ClearCursor = function() end
        local ok, err = RQ.SuppliesService.Attach("Player-Recipient")
        equal(ok, false)
        contains({ err }, "Cursor could not be restored")
        equal(state.cursor.item.itemID, 2589)
        equal(state.cursor.count, 25)
        equal(state.pickups, 1)
        equal(state.sent, 0)
    end)
end
