return function(h)
    local test, equal = h.test, h.equal
    local active = "Player-Test-1"
    local function start()
        h.fakeCharacter()
        local frames = assert(loadfile("Tests/fixtures/Frames.lua"))()()
        h.loadAddon()
        frames.Emit("PLAYER_LOGIN")
        assert(RQ.SnapshotService.Register("add"))
        return frames
    end
    local function click(frames, label)
        frames.Click(frames.FindButton(label))
        h.flushTimers()
    end
    local function visibleText(frames, fragment)
        for _, widget in ipairs(frames.widgets) do
            if widget:IsVisible() and widget.text:find(fragment, 1, true) then
                return true
            end
        end
        return false
    end
    test("workspace has four primary tabs and roster includes recommendations without retired controls", function()
        local frames = start()
        assert(RQ.MainWindow.Open("today"))
        for _, name in ipairs({ "Roster", "Bags and Inventory", "Professions", "Settings" }) do
            equal(frames.FindButton(name).parent, _G.RQMainWindow)
        end
        for _, widget in ipairs(frames.widgets) do
            if widget.parent == _G.RQMainWindow and widget.kind == "Button" then
                assert(widget.text ~= "Today" and widget.text ~= "Supplies" and widget.text ~= "Bags")
            end
        end
        equal(#RQ.MainWindow.view.rows, 1)
        equal(RQ.MainWindow.view.rows[1].id, active)
        assert(RQ.MainWindow.view.rows[1].visual.rested)
        assert(#RQ.MainWindow.view.rows[1].visual.professions > 0)
        assert(visibleText(frames, "PLAY NEXT"))
        equal(visibleText(frames, "Score:"), false)
        equal(visibleText(frames, "ID: Player-"), false)
        for _, retired in ipairs({ "Gear", "Free bag space", "Add named slot", "Legacy", "LOW" }) do
            equal(visibleText(frames, retired), false)
        end
        click(frames, "Details / copy")
        assert(visibleText(frames, "Score:"))
    end)
    test("roster main selection and management target the selected GUID", function()
        local frames = start()
        local other = RQ.Util.Copy(RQ.Database.Current())
        other.identity.guid, other.identity.fullName = "Player-Other", "Another character"
        other.registration = "pending"
        RQDB.characters["Player-Other"] = other
        assert(RQ.Database.Register("add", "Player-Other"))
        RQ.MainWindow.selectedId = "Player-Other"
        assert(RQ.MainWindow.Open("roster"))
        equal(RQ.MainWindow.tab, "roster")
        click(frames, "Make main")
        equal(RQDB.roster["Player-Other"].isMain, true)
        equal(RQDB.roster[active].isMain, false)
        equal(RQ.Database.activeId, active)
        click(frames, "Manage roster")
        equal(RQ.MainWindow.tab, "manage")
        click(frames, "Roster")
        equal(RQ.MainWindow.tab, "roster")
    end)
    test("roster Grocery list reviews the selected offline or disabled member and orange recipe sources", function()
        local frames = start()
        local other = RQ.Util.Copy(RQ.Database.Current())
        other.identity.guid, other.identity.fullName = "Player-Groceries", "Pearl crafter"
        other.registration = "pending"
        other.snapshot.professions[197] = { name = "Tailoring", skill = 10, maxSkill = 75 }
        other.recipes.professions[197] = {
            name = "Tailoring",
            complete = true,
            scannedAt = 123456789,
            recipes = {
                [900] = {
                    name = "Pearl cuffs",
                    learned = true,
                    difficulty = 0,
                    skillUps = 1,
                    reagentsComplete = true,
                    reagents = { [5498] = 1 },
                },
            },
        }
        RQDB.characters["Player-Groceries"] = other
        assert(RQ.Database.Register("add", "Player-Groceries"))
        RQ.MainWindow.selectedId = "Player-Groceries"
        RQ.MainWindow.bagQuery, RQ.MainWindow.bagSource = "old search", "bank"
        RQ.MainWindow.inventoryPage, RQ.MainWindow.groceryFilter = 3, "covered"
        assert(RQ.MainWindow.Open("roster"))
        assert(visibleText(frames, "Grocery list: 1 material/stock target(s)"))
        click(frames, "Grocery list")
        equal(RQ.MainWindow.tab, "bags")
        equal(RQ.MainWindow.bagCharacterId, "Player-Groceries")
        equal(RQ.MainWindow.bagQuery, "")
        equal(RQ.MainWindow.bagSource, "all")
        equal(RQ.MainWindow.inventoryPage, 1)
        equal(RQ.MainWindow.groceryFilter, "all")
        equal(RQ.MainWindow.view.cards[2].itemId, 5498)
        assert(not _G.RQCopyWindow or not _G.RQCopyWindow:IsShown())
        click(frames, "Recipes / details")
        assert(visibleText(frames, "Auto orange: Pearl cuffs [900]"))
        assert(visibleText(frames, "5498"))
        equal(RQ.Database.activeId, active)
        click(frames, "Full report")
        assert(_G.RQCopyWindow:IsShown())
        RQ.Api.HideCopyWindow()
        RQDB.roster["Player-Groceries"].enabled = false
        assert(RQ.MainWindow.Open("roster"))
        click(frames, "Grocery list")
        assert(visibleText(frames, "Disabled member: review only"))
        click(frames, "Recipes / details")
        assert(visibleText(frames, "Auto orange: Pearl cuffs [900]"))
        equal(RQ.SuppliesService.Plan(RQDB, 123456789).groceries["Player-Groceries"], nil)
        RQ.MainWindow.selectedId = active
        assert(RQ.MainWindow.Open("roster"))
        click(frames, "Grocery list")
        equal(visibleText(frames, "Auto orange: Pearl cuffs [900]"), false)
    end)
    test("Inventory stock cards expose automatic recipe quantities and evidence", function()
        start()
        local record = RQ.Database.Current()
        record.snapshot.professions[197] = { name = "Tailoring", skill = 10, maxSkill = 75 }
        record.recipes.professions[197] = {
            name = "Tailoring",
            complete = true,
            scannedAt = 123456789,
            recipes = {
                [900] = {
                    name = "Pearl cuffs",
                    learned = true,
                    difficulty = 0,
                    skillUps = 1,
                    reagentsComplete = true,
                    reagents = { [5498] = 1 },
                },
            },
        }
        assert(RQ.MainWindow.Open("inventory"))
        local card = RQ.MainWindow.view.cards[2]
        equal(card.itemId, 5498)
        equal(card.metrics[1].value, "1")
        assert(card.summary:find("Auto orange recipes", 1, true))
        assert(card.body:find("Auto orange: Pearl cuffs [900]", 1, true))
    end)
    test("Settings separates mechanics from membership and exposes configuration backup controls", function()
        local frames = start()
        assert(RQ.MainWindow.Open("settings"))
        equal(RQ.MainWindow.tab, "planning")
        assert(visibleText(frames, "RESTED ESTIMATES"))
        assert(visibleText(frames, "CHARACTER OVERRIDES"))
        equal(visibleText(frames, "Add slot with name"), false)
        equal(visibleText(frames, "Make main"), false)
        assert(frames.FindButton("Export configuration"))
        assert(frames.FindButton("Import configuration"))
        click(frames, "Manage roster")
        assert(frames.FindButton("Add / resume"))
        equal(visibleText(frames, "Link selected character"), false)
    end)
    test("Inventory uses item icons unknown stock metrics bounded pages and recycled detail actions", function()
        local frames = start()
        local record = RQ.Database.Current()
        for item = 9001, 9020 do
            record.supplies.needs[item] = 10
        end
        local iconReads = 0
        RQ.Api.GetItemIcon = function(item)
            iconReads = iconReads + 1
            return "icon-" .. item
        end
        assert(RQ.MainWindow.Open("inventory"))
        equal(RQ.MainWindow.tab, "bags")
        equal(RQ.MainWindow.view.inventorySection, "stock")
        equal(#RQ.MainWindow.view.cards, 12)
        assert(iconReads <= 12, "off-page stock must not trigger native icon reads")
        local itemCard = RQ.MainWindow.view.cards[2]
        equal(itemCard.itemId, 9001)
        equal(itemCard.icon, "icon-9001")
        equal(itemCard.metrics[2].value, "Unknown")
        assert(itemCard.summary:find("INCOMPLETE", 1, true))
        click(frames, "Next items")
        equal(RQ.MainWindow.view.inventoryPage, 2)
        assert(#RQ.MainWindow.view.cards <= 12)
        local count = #frames.widgets
        click(frames, "Prev items")
        click(frames, "Next items")
        equal(#frames.widgets, count)
        click(frames, "Recipes / details")
        assert(visibleText(frames, "Item ID: 9012"))
        assert(not _G.RQCopyWindow or not _G.RQCopyWindow:IsShown())
        click(frames, "Orange recipes")
        for _, widget in ipairs(frames.widgets) do
            if widget.itemIcon and widget:IsVisible() then
                equal(widget.itemIcon:IsShown(), false)
            end
        end
    end)
    test(
        "visual groceries sort shortages first and filter collection covered and unknown without changing targets",
        function()
            local frames = start()
            local record = RQ.Database.Current()
            record.supplies.needs = { [9001] = 2, [9002] = 3, [9003] = 2 }
            record.inventory.bags.complete, record.inventory.bags.scannedAt = true, 123456789
            record.inventory.bags.items = { [9001] = 2 }
            record.inventory.bank.complete, record.inventory.bank.coherent = true, true
            record.inventory.bank.scannedAt, record.inventory.bank.items = 123456789, { [9003] = 2 }
            _G.SlashCmdList.ROSTERQUARTERMASTER("supplies " .. active)
            equal(RQ.MainWindow.tab, "bags")
            equal(RQ.MainWindow.bagCharacterId, active)
            equal(#RQ.MainWindow.view.cards, 4)
            equal(RQ.MainWindow.view.cards[2].itemId, 9002)
            equal(RQ.MainWindow.view.cards[3].itemId, 9003)
            equal(RQ.MainWindow.view.cards[4].itemId, 9001)
            equal(RQ.MainWindow.view.cards[2].metrics[3].tone, "warning")
            equal(RQ.MainWindow.view.cards[4].metrics[3].tone, "positive")
            click(frames, "Show: All")
            equal(#RQ.MainWindow.view.cards, 2)
            equal(RQ.MainWindow.view.cards[2].itemId, 9002)
            click(frames, "Show: Shortages")
            equal(RQ.MainWindow.view.cards[2].itemId, 9003)
            equal(RQ.MainWindow.view.cards[2].metrics[4].value, "2")
            click(frames, "Show: Collect / incoming")
            equal(RQ.MainWindow.view.cards[2].itemId, 9001)
            click(frames, "Show: Covered")
            equal(#RQ.MainWindow.view.cards, 1)
            assert(visibleText(frames, "No items match this filter"))
            record.inventory.bags.complete = false
            assert(RQ.MainWindow.Render())
            equal(#RQ.MainWindow.view.cards, 4)
            equal(RQ.MainWindow.view.cards[2].metrics[3].value, "Unknown")
            equal(record.supplies.needs[9002], 3)
            click(frames, "Show: Unknown")
            equal(RQ.MainWindow.groceryFilter, "all")
            local filter = frames.FindButton("Show: All")
            assert(filter:IsVisible())
            equal(visibleText(frames, "Gear advisor"), false)
            for _, widget in ipairs(frames.widgets) do
                if widget.card and widget.card.groceryItem and widget:IsVisible() then
                    equal(widget.metrics[1].label.points[1][5], widget.metrics[6].label.points[1][5])
                    equal(widget.metrics[1].label:GetWidth(), 95)
                    assert(widget.itemIcon:IsShown())
                    assert(widget:GetHeight() > -widget.metrics[6].value.points[1][5] + 40)
                end
            end
        end
    )
    test("grocery status distinguishes unknown shortages provisional coverage and carried stock", function()
        start()
        equal(RQ.SuppliesService.GroceryState({}), "unknown")
        equal(RQ.SuppliesService.GroceryState({ missing = 1, inTransit = 1 }), "missing")
        equal(RQ.SuppliesService.GroceryState({ missing = 0, inTransit = 1 }), "collection")
        equal(RQ.SuppliesService.GroceryState({ missing = 0, collect = 1 }), "collection")
        equal(RQ.SuppliesService.GroceryState({ missing = 0, withdraw = 1 }), "collection")
        equal(RQ.SuppliesService.GroceryState({ missing = 0 }), "covered")
    end)
    test("grocery filters reset pagination and expansion stays tied to owner and item", function()
        local frames = start()
        local record = RQ.Database.Current()
        for item = 9001, 9020 do
            record.supplies.needs[item] = 1
        end
        assert(RQ.SuppliesService.Open(active))
        click(frames, "Recipes / details")
        assert(visibleText(frames, "Item ID: 9001"))
        click(frames, "Next items")
        equal(visibleText(frames, "Item ID: 9001"), false)
        click(frames, "Prev items")
        assert(visibleText(frames, "Item ID: 9001"))
        click(frames, "Hide details")
        equal(visibleText(frames, "Item ID: 9001"), false)
        click(frames, "Next items")
        click(frames, "Show: All")
        equal(RQ.MainWindow.view.inventoryPage, 1)
        equal(#RQ.MainWindow.view.cards, 1)
        equal(RQ.MainWindow.view.inventoryPageCount, 1)
        assert(RQ.MainWindow.Open("bags"))
        local button = frames.FindButton("Source: all")
        equal(button.enabled, true)
    end)

    test("compact roster retains incomplete wallet warnings without exposing raw identifiers", function()
        start()
        local record = RQ.Database.Current()
        record.snapshot.sections.money.complete = false
        record.snapshot.money = 12345
        assert(RQ.MainWindow.Open("roster"))
        local card = RQ.MainWindow.view.detail
        assert(card.summary:find("1g 23s 45c", 1, true))
        assert(card.summary:find("Wallet  1g 23s 45c  |  UNKNOWN", 1, true))
        equal(card.summary:find(active, 1, true), nil)
        assert((card.detail or card.body):find(active, 1, true))
    end)
    test("missing item textures retain identity and unknown quantities without inventing stock", function()
        local frames = start()
        RQ.Database.Current().supplies.needs[2589] = 5
        RQ.Api.GetItemIcon = function()
            return nil
        end
        assert(RQ.MainWindow.Open("inventory"))
        local row
        for _, widget in ipairs(frames.widgets) do
            if widget.itemId == 2589 and widget:IsVisible() then
                row = widget
            end
        end
        assert(row)
        equal(row.itemIcon.texture, "Interface\\Icons\\INV_Misc_QuestionMark")
        row.itemIcon.SetTexture = nil
        assert(RQ.MainWindow.Render())
        equal(row.itemIcon:IsShown(), false)
        equal(row.itemId, 2589)
        equal(row.card.metrics[2].value, "Unknown")
        equal(RQ.Database.Current().inventory.bags.items[2589], nil)
    end)
end
