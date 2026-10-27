return function(h)
    local test, equal, contains = h.test, h.equal, h.contains
    local now, active = 123456789, "Player-Test-1"
    local function start(native)
        h.fakeCharacter()
        local frames = native and assert(loadfile("Tests/fixtures/Frames.lua"))()()
        h.loadAddon()
        RQ.MainWindow.realm, RQ.MainWindow.group = "all", "all"
        if frames then
            frames.Emit("PLAYER_LOGIN")
        else
            h.emit("PLAYER_LOGIN")
        end
        assert(RQ.Database.Register("add"))
        RQ.Database.Current().inventory.bags.complete = true
        RQ.Database.Current().inventory.bags.scannedAt = now
        return frames
    end
    local function member(id, name, realm)
        local record = RQ.Util.Copy(RQ.Database.Current())
        record.identity = {
            ruleset = "PVE",
            faction = "Horde",
            guid = id,
            fullName = name,
            realm = realm or "TestRealm PVE",
            class = "WARRIOR",
        }
        record.registration = "pending"
        record.inventory.bags = {
            items = {},
            details = {},
            tradable = {},
            equipped = {},
            lockedContainers = {},
            complete = true,
            scannedAt = now,
        }
        RQDB.characters[id] = record
        assert(RQ.Database.Register("add", id))
        return record
    end
    local function stock(record, id, count, name)
        record.inventory.bags.items[id] = count
        record.inventory.bags.details[id] = { name = name }
    end
    local function search(query, owner, labels)
        local result, err = RQ.InventorySearch.Evaluate(RQDB, query, now, owner, labels, "bags")
        assert(result, err)
        return result
    end
    local function click(frames, text)
        frames.Click(frames.FindButton(text))
        h.flushTimers()
    end
    local function rowFor(frames, itemId)
        for _, widget in ipairs(frames.widgets) do
            if widget.itemId == itemId and widget.actionKind == "inventory-owner" and widget:IsVisible() then
                return widget
            end
        end
        error("No visible item row " .. itemId)
    end

    test("inventory search finds copper across owners realms and item categories using literal case folding", function()
        start()
        stock(RQ.Database.Current(), 2770, 7, "Copper Ore")
        local bar = member("Player-Bar", "Quick Death", "OtherRealm")
        stock(bar, 2840, 3, "Copper Bar")
        local boots = member("Player-Boots", "Tombsie Graves")
        stock(boots, 3469, 1, "Rough Copper Boots")
        bar.supplies.needs[2840] = 3
        local result = search("  cOpPeR  ")
        equal(result.query, "cOpPeR")
        equal(#result.matches, 3)
        equal(result.ownersWithMatches, 3)
        equal(result.matches[1].characterId, "Player-Bar")
        equal(result.matches[1].quantity, 3)
        equal(result.matches[1].source, "bags")
        equal(result.matches[1].realm, "OtherRealm")
        equal(result.matches[2].quantity, 7)
        equal(result.matches[3].itemName, "Rough Copper Boots")
        equal(next(boots.inventory.bags.tradable), nil)
        equal(bar.supplies.needs[2840], 3)
        equal(bar.inventory.bags.items[2840], 3)
    end)

    test(
        "inventory discovery includes disabled registered members but excludes ignored pending and planned records",
        function()
            start()
            local disabled = member("Player-Disabled", "Disabled")
            stock(disabled, 2770, 2, "Copper Ore")
            RQDB.roster["Player-Disabled"].enabled = false
            local ignored = member("Player-Ignored", "Ignored")
            stock(ignored, 2770, 20, "Copper Ore")
            assert(RQ.Database.Register("ignore", "Player-Ignored"))
            local pending = member("Player-Pending", "Pending")
            stock(pending, 2770, 30, "Copper Ore")
            pending.registration = "pending"
            local result = search("Copper")
            equal(#result.coverage, 2)
            equal(#result.matches, 1)
            equal(result.matches[1].characterId, "Player-Disabled")
            equal(result.matches[1].enabled, false)
            contains(RQ.BagPanel.SearchReport(result, now), "DISABLED FOR PLANNING")
            local missing, err = RQ.InventorySearch.Evaluate(RQDB, "Copper", now, "Player-Ignored")
            equal(missing, nil)
            contains({ err }, "no longer a registered")
        end
    )

    test("search treats pattern metacharacters literally and numeric queries as exact item IDs", function()
        start()
        local record = RQ.Database.Current()
        stock(record, 2770, 7, "Copper [Ore] 100% + (Rare).*")
        stock(record, 27701, 1, "Other")
        for _, query in ipairs({ "[Ore]", "100%", "+", "(Rare)", ".*" }) do
            equal(#search(query).matches, 1)
        end
        equal(#search("^Copper").matches, 0)
        equal(search(" 002770 ").matches[1].itemId, 2770)
        equal(#search("277").matches, 0)
        for _, query in ipairs({ "", "   ", "0", "2147483648", string.rep("x", 129) }) do
            local result, err = RQ.InventorySearch.Evaluate(RQDB, query, now)
            equal(result, nil)
            assert(err)
        end
    end)

    test("cached incomplete stale and unknown coverage never become evidence of absence", function()
        start()
        local current = RQ.Database.Current()
        stock(current, 2770, 4, "Copper Ore")
        current.inventory.bags.complete = false
        current.inventory.bags.error = "Scan interrupted"
        local stale = member("Player-Stale", "Stale")
        stock(stale, 2840, 3, "Copper Bar")
        stale.inventory.bags.scannedAt = now - RQDB.policies.staleSnapshotHours * 3600
        local unknown = member("Player-Unknown", "Unvisited")
        unknown.inventory.bags.scannedAt, unknown.inventory.bags.complete = 0, false
        local result = search("Copper")
        equal(#result.matches, 2)
        equal(result.states.INCOMPLETE, 1)
        equal(result.states.STALE, 1)
        equal(result.states.UNKNOWN, 1)
        local lines = RQ.BagPanel.SearchReport(search("Silver"), now)
        contains(lines, "No known matches; this does not prove")
        contains(lines, "Sources: bags")
        contains(lines, "Scan interrupted")
        contains(lines, "Uncertain coverage: Unvisited")
        stale.inventory.bags.scannedAt = now + 1
        equal(search("Copper").states.STALE, 1)
    end)

    test("unresolved labels remain counted and numeric ID search works without client metadata", function()
        start()
        local current = RQ.Database.Current()
        stock(current, 2770, 2)
        local other = member("Player-Other", "Other")
        stock(other, 2770, 3)
        stock(other, 2840, 0)
        RQ.Api.GetItemName = function()
            error("Pure matching cannot call APIs")
        end
        local result = search("Copper")
        equal(#result.matches, 0)
        equal(result.unresolvedNames, 1)
        equal(#search("2770").matches, 2)
        equal(search("2770").matches[1].itemName, nil)
        local labels = { [2770] = "Copper Ore" }
        equal(#search("Copper", nil, labels).matches, 2)
        equal(search("Copper", nil, labels).unresolvedNames, 0)
        equal(current.inventory.bags.details[2770].name, nil)
        equal(labels[2770], "Copper Ore")
        equal(#RQ.InventorySearch.ItemIds(RQDB), 1)
    end)

    test("search ordering breaks identical owner and item names by canonical IDs without sharing quantities", function()
        start()
        local first = member("Player-A", "Same Name")
        local second = member("Player-B", "Same Name")
        stock(first, 2840, 3, "Copper")
        stock(first, 2770, 2, "Copper")
        stock(second, 2770, 8, "Copper")
        local result = search("Copper")
        equal(result.matches[1].characterId, "Player-A")
        equal(result.matches[1].itemId, 2770)
        equal(result.matches[2].itemId, 2840)
        equal(result.matches[3].characterId, "Player-B")
        equal(result.matches[3].quantity, 8)
        equal(#search("Copper", "Player-B").coverage, 1)
        result.matches[1].quantity = 99
        equal(first.inventory.bags.items[2770], 2)
    end)

    test("Bags search enter clear and owner controls preserve drafts filters and existing upgrades", function()
        local frames = start(true)
        stock(RQ.Database.Current(), 2770, 7, "Copper Ore")
        stock(member("Player-Other", "Other"), 2840, 3, "Copper Bar")
        assert(RQ.MainWindow.Open("bags"))
        local edit = frames.FindKind("EditBox")
        edit:SetFocus()
        edit:SetText(" Copper ")
        edit.scripts.OnEnterPressed(edit)
        h.flushTimers()
        equal(RQ.MainWindow.bagQuery, "Copper")
        equal(#RQ.MainWindow.view.inventorySearch.matches, 2)
        click(frames, "Next owner")
        equal(RQ.MainWindow.bagCharacterId, "Player-Other")
        equal(#RQ.MainWindow.view.inventorySearch.matches, 1)
        edit:SetFocus()
        edit:SetText("Unsubmitted draft")
        RQ.MainWindow.Invalidate()
        h.flushTimers()
        equal(edit:GetText(), "Unsubmitted draft")
        equal(RQ.MainWindow.bagQuery, "Copper")
        equal(RQ.MainWindow.bagCharacterId, "Player-Other")
        click(frames, "Clear search")
        equal(edit:GetText(), "")
        equal(RQ.MainWindow.bagCharacterId, nil)
        equal(RQ.MainWindow.view.inventorySearch, nil)
        equal(RQ.MainWindow.view.inventorySection, "recorded")
        click(frames, "Bag upgrades")
        equal(RQ.MainWindow.view.cards[1].title, "Roster bag upgrades")
        frames.FindButton("Refresh bags")
    end)

    test(
        "slash search and copied results include ownership while invalid input preserves the previous query",
        function()
            local frames = start(true)
            stock(RQ.Database.Current(), 2770, 7, "Copper Ore")
            _G.SlashCmdList.ROSTERQUARTERMASTER("bags Copper")
            equal(RQ.MainWindow.tab, "bags")
            equal(RQ.MainWindow.bagQuery, "Copper")
            click(frames, "Copy results")
            local copy
            for _, widget in ipairs(frames.widgets) do
                if widget.kind == "EditBox" and widget.text:find("7 x Copper Ore [2770]", 1, true) then
                    copy = widget
                end
            end
            assert(copy)
            contains({ copy.text }, "Character ID: " .. active)
            contains({ copy.text }, "Source: Bags | RECENT")
            _G.SlashCmdList.ROSTERQUARTERMASTER("find 2770")
            contains(h.messages(), "7 x Copper Ore [2770]")
            _G.SlashCmdList.ROSTERQUARTERMASTER("bags 2147483648")
            equal(RQ.MainWindow.bagQuery, "Copper")
            contains(h.messages(), "Search item ID must")
            _G.SlashCmdList.ROSTERQUARTERMASTER("find")
            contains(h.messages(), "Enter an item name")
            equal(RQDB.schemaVersion, 19)
            equal(RQDB.settings.bagQuery, nil)
        end
    )

    test("search metadata replies refresh names and icons without rescanning offline inventory", function()
        local frames = start(true)
        local offline = member("Player-Offline", "Offline Full Name")
        stock(offline, 2770, 3)
        local requests, scans = 0, 0
        _G.C_Item = {
            GetItemInfo = function()
                return nil
            end,
            RequestLoadItemDataByID = function(id)
                equal(id, 2770)
                requests = requests + 1
            end,
        }
        RQ.Api.GetBagItems = function()
            scans = scans + 1
            error("Search must not scan inventory")
        end
        assert(RQ.MainWindow.SearchBags("Copper", true))
        equal(RQ.MainWindow.view.inventorySearch.unresolvedNames, 1)
        equal(#RQ.MainWindow.view.inventorySearch.matches, 0)
        assert(RQ.MainWindow.Render())
        equal(requests, 1)
        _G.C_Item.GetItemInfo = function()
            return "Copper Ore"
        end
        _G.C_Item.GetItemInfoInstant = function(id)
            return id, "", "", "", 12345
        end
        frames.Emit("GET_ITEM_INFO_RECEIVED", 2770, true)
        frames.Emit("GET_ITEM_INFO_RECEIVED", 2770, true)
        h.flushTimers()
        equal(#RQ.MainWindow.view.inventorySearch.matches, 1)
        local row = rowFor(frames, 2770)
        equal(row.itemIcon.texture, 12345)
        equal(row.itemIcon:IsShown(), true)
        contains({ row.title.text }, "Copper Ore")
        equal(row.characterId, "Player-Offline")
        equal(scans, 0)
        equal(offline.inventory.bags.items[2770], 3)
        equal(offline.inventory.bags.details[2770].name, nil)
        equal(offline.inventory.bags.scannedAt, now)
        assert(RQ.MainWindow.Open("bags"))
        equal(RQ.MainWindow.view.inventorySection, "recorded")
        equal(RQ.Database.activeId, active)
        equal(row.itemIcon:IsVisible(), true)
    end)

    test("search invalidates removed owner filters explicitly and restores all registered coverage", function()
        local frames = start(true)
        stock(member("Player-Other", "Other"), 2770, 2, "Copper Ore")
        stock(RQ.Database.Current(), 2770, 5, "Copper Ore")
        assert(RQ.MainWindow.SearchBags("Copper", true))
        click(frames, "Next owner")
        equal(RQ.MainWindow.bagCharacterId, "Player-Other")
        assert(RQ.Database.Register("ignore", "Player-Other"))
        h.flushTimers()
        assert(RQ.MainWindow.Render())
        equal(RQ.MainWindow.bagCharacterId, nil)
        equal(#RQ.MainWindow.view.inventorySearch.coverage, 3)
        contains({ RQ.MainWindow.status }, "no longer registered")
        assert(RQ.MainWindow.Open("today"))
        assert(RQ.MainWindow.Open("bags"))
        equal(RQ.MainWindow.bagQuery, "Copper")
    end)

    test("fifty-owner searches reuse rows scroll and resolve each unique icon only once", function()
        local frames = start(true)
        stock(RQ.Database.Current(), 2770, 1, "Copper Ore")
        for index = 1, 49 do
            stock(member("Player-" .. index, "Member " .. index), 2770, index, "Copper Ore")
        end
        local icons = 0
        _G.C_Item = {
            GetItemInfoInstant = function(id)
                icons = icons + 1
                return id, "", "", "", 12345
            end,
        }
        assert(RQ.MainWindow.SearchBags("Copper", true))
        equal(#RQ.MainWindow.view.inventorySearch.matches, 50)
        equal(icons, 1)
        local count = #frames.widgets
        local row = rowFor(frames, 2770)
        local scroll = row.parent.parent
        scroll:SetVerticalScroll(500)
        assert(RQ.MainWindow.Render())
        equal(#frames.widgets, count)
        equal(scroll:GetVerticalScroll(), 500)
        equal(icons, 1)
        assert(RQ.MainWindow.SearchBags("Silver"))
        h.flushTimers()
        equal(scroll:GetVerticalScroll(), 0)
        equal(#RQ.MainWindow.view.inventorySearch.matches, 0)
        assert(RQ.MainWindow.SearchBags("Copper"))
        h.flushTimers()
        equal(#frames.widgets, count)
    end)

    test("missing item graphics keep searchable text and text search works without native frames", function()
        start()
        stock(RQ.Database.Current(), 2770, 7, "Copper Ore")
        _G.C_Item = {
            GetItemInfoInstant = function()
                error("Restricted")
            end,
        }
        local result = assert(RQ.SuppliesService.SearchInventory(RQDB, "Copper", now))
        equal(#result.matches, 1)
        equal(result.icons[2770], nil)
        _G.SlashCmdList.ROSTERQUARTERMASTER("find Copper")
        contains(h.messages(), "7 x Copper Ore [2770]")
        contains(h.messages(), "Character ID: " .. active)
    end)

    test("search uses the scanned aggregate across stacks and includes bound and fully reserved items", function()
        start()
        _G.C_Container = {
            GetContainerNumSlots = function(bag)
                return bag == 0 and 2 or 1
            end,
            GetContainerItemInfo = function(bag, slot)
                if bag == 0 then
                    return {
                        itemID = 2770,
                        stackCount = slot == 1 and 7 or 3,
                        itemName = "Copper Ore",
                        isBound = false,
                        isLocked = false,
                    }
                elseif bag == 1 then
                    return {
                        itemID = 3469,
                        stackCount = 1,
                        itemName = "Rough Copper Boots",
                        isBound = true,
                        isLocked = false,
                    }
                end
            end,
        }
        assert(RQ.SuppliesService.ScanBags())
        assert(RQ.SuppliesService.SetNeed(2770, 10))
        local result = search("Copper")
        equal(#result.matches, 2)
        equal(result.matches[1].itemId, 2770)
        equal(result.matches[1].quantity, 10)
        equal(result.matches[2].itemId, 3469)
        equal(result.matches[2].quantity, 1)
        equal(RQ.Database.Current().inventory.bags.tradable[3469], nil)
        equal(RQ.Database.Current().supplies.needs[2770], 10)
    end)

    test("carried search never counts bank mail or zero-quantity placeholders as matches", function()
        start()
        local record = RQ.Database.Current()
        stock(record, 2770, 0, "Copper Ore")
        record.inventory.bank.items[2770] = 100
        record.inventory.mail.items[2770] = 50
        equal(#search("Copper").matches, 0)
        equal(#search("2770").matches, 0)
        equal(#RQ.InventorySearch.ItemIds(RQDB, nil, "bags"), 0)
        equal(search("Copper").states.RECENT, 1)
        contains(RQ.BagPanel.SearchReport(search("Copper"), now), "Sources: bags")
        equal(record.inventory.bank.items[2770], 100)
        equal(record.inventory.mail.items[2770], 50)
    end)
end
