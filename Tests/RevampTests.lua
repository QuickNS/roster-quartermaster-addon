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
    local function clone(id, realm, faction)
        local record = RQ.Util.Copy(RQ.Database.Current())
        record.identity.guid, record.identity.fullName = id, id
        record.identity.realm = realm or record.identity.realm
        record.identity.faction = faction or record.identity.faction
        RQDB.characters[id] = record
        RQDB.roster[id] = RQ.Util.Copy(RQDB.roster[active])
        RQDB.roster[id].isMain = false
        return record
    end
    local function click(frames, label)
        frames.Click(frames.FindButton(label))
        h.flushTimers()
    end
    local function groceries(record)
        record.supplies.needs[5498] = 3
        record.inventory.bags.items = { [5498] = 1, [2589] = 20 }
        record.inventory.bags.details =
            { [5498] = { name = "Small Lustrous Pearl" }, [2589] = { name = "Linen Cloth" } }
    end

    test("four primary tabs keep shared filters visible and settings selections scoped", function()
        local frames = start()
        clone("Player-Foreign", "Elsewhere PVE", "Horde")
        for _, tab in ipairs({ "roster", "bags", "professions", "settings", "manage" }) do
            assert(RQ.MainWindow.Open(tab))
            for _, label in ipairs({ "Roster", "Bags and Inventory", "Professions", "Settings" }) do
                equal(frames.FindButton(label).parent, _G.RQMainWindow)
            end
            local view = RQ.MainWindow.view
            assert(frames.FindButton(view.realms[view.realm]):IsVisible())
            assert(frames.FindButton(view.groups[view.group]):IsVisible())
            equal(#view.characterIds, 1)
            equal(view.selectedId, active)
        end
        RQ.MainWindow.realm, RQ.MainWindow.group = "all", "all"
        assert(RQ.MainWindow.Open("roster"))
        equal(#RQ.MainWindow.view.rows, 2)
    end)
    test("scope is immutable and excludes foreign inventories plans and shipment rows", function()
        start()
        local foreign = clone("Player-Foreign", "Elsewhere PVE", "Horde")
        foreign.supplies.needs[999] = 200
        local identity = RQ.Database.Current().identity
        local scoped = RQ.WorkspaceScope.Account(RQDB, RQ.Character.Realm(identity), RQ.Character.TradeGroup(identity))
        equal(scoped.characters["Player-Foreign"], nil)
        equal(scoped.roster["Player-Foreign"], nil)
        assert(RQDB.characters["Player-Foreign"])
        equal(#RQ.InventorySearch.CharacterIds(scoped), 1)
        assert(RQ.SuppliesService.Plan(scoped, 123456789))
    end)
    test("Main is per market and only wins equal level ties without a lead or pin", function()
        start()
        local alt = clone("Player-Alt")
        clone("Player-OtherMain", "Other PVE")
        assert(RQ.Database.SetMain(active))
        assert(RQ.Database.SetMain("Player-OtherMain"))
        equal(RQDB.roster[active].isMain, true)
        equal(RQDB.roster["Player-OtherMain"].isMain, true)
        local report = RQ.PlanningService.Evaluate()
        local positions = {}
        for index, row in ipairs(report.recommendations) do
            positions[row.characterId] = index
        end
        assert(positions[active] < positions["Player-Alt"])
        alt.snapshot.level = RQ.Database.Current().snapshot.level - 1
        report = RQ.PlanningService.Evaluate()
        for index, row in ipairs(report.recommendations) do
            positions[row.characterId] = index
        end
        assert(positions["Player-Alt"] < positions[active])
        assert(RQ.Database.SetMain("Player-Alt"))
        equal(RQDB.roster[active].isMain, false)
        equal(RQDB.roster["Player-OtherMain"].isMain, true)
        equal(RQ.Database.Pin, nil)
        assert(RQ.Database.SetMain(active))
        local moved = RQ.Util.Copy(RQ.Database.Current().identity)
        moved.realm = "Other PVE"
        assert(RQ.Database.Attach(moved))
        equal(RQDB.roster[active].isMain, false)
        equal(RQDB.roster["Player-OtherMain"].isMain, true)
    end)
    test("inventory expands bags and bank and search dims rather than removes nonmatches", function()
        local frames = start()
        groceries(RQ.Database.Current())
        RQ.Database.Current().inventory.bank.items = { [5498] = 2 }
        assert(RQ.MainWindow.Open("bags"))
        click(frames, "Expand")
        local items = 0
        for _, card in ipairs(RQ.MainWindow.view.cards) do
            if card.compact then
                items = items + 1
            end
        end
        equal(items, 2)
        assert(RQ.MainWindow.SearchBags("pearl"))
        h.flushTimers()
        local matched, muted = 0, 0
        for _, card in ipairs(RQ.MainWindow.view.cards) do
            if card.compact then
                if card.muted then
                    muted = muted + 1
                else
                    matched = matched + 1
                end
            end
        end
        equal(matched, 2)
        equal(muted, 1)
        local dimmed
        for _, widget in ipairs(frames.widgets) do
            if widget:IsVisible() and widget.card and widget.card.muted then
                equal(widget.alpha, 0.30)
                equal(widget:GetHeight(), 48)
                dimmed = true
            end
        end
        assert(dimmed)
        local count = #RQ.MainWindow.view.allCards
        click(frames, "Collapse")
        equal(#RQ.MainWindow.view.allCards, count - 2)
        equal(RQ.MainWindow.bagQuery, "pearl")
    end)
    test("compact groceries stays open beside auction house and supports selected or full scope", function()
        local frames = start()
        groceries(RQ.Database.Current())
        local alt = clone("Player-Alt")
        alt.supplies.needs[2589] = 5
        assert(RQ.MainWindow.OpenGroceries(active))
        click(frames, "Compact list")
        assert(_G.RQGroceryWindow:IsVisible())
        assert(_G.RQGroceryWindow.text:GetText():find("Pearl", 1, true))
        equal(_G.RQGroceryWindow.text:GetText():find("Player-Alt", 1, true), nil)
        RQ.Api.HideRosterWindow()
        assert(_G.RQGroceryWindow:IsVisible())
        RQ.MainWindow.bagCharacterId = nil
        click(frames, "Refresh list")
        assert(_G.RQGroceryWindow.text:GetText():find("Player-Alt", 1, true))
    end)
    test("Auctionator prices use copper unit costs and never invent partial totals or foreign quotes", function()
        start()
        local identity = RQ.Database.Current().identity
        _G.Auctionator = {
            API = {
                v1 = {
                    GetAuctionPriceByItemID = function(caller, item)
                        equal(caller, "RosterQuartermaster")
                        return item == 5498 and 1250 or nil
                    end,
                },
            },
        }
        equal(RQ.Api.GetAuctionPrice(5498, identity), 1250)
        equal(RQ.Api.GetAuctionPrice(2589, identity), nil)
        local foreign = RQ.Util.Copy(identity)
        foreign.realm = "Other PVE"
        equal(RQ.Api.GetAuctionPrice(5498, foreign), nil)
        equal(RQ.WorkspaceScope.CraftCost({ [5498] = 3 }, { [5498] = 1250 }), 3750)
        local cost, missing = RQ.WorkspaceScope.CraftCost({ [5498] = 3, [2589] = 1 }, { [5498] = 1250 })
        equal(cost, nil)
        equal(missing[1], 2589)
        _G.Auctionator.API.v1.GetAuctionPriceByItemID = function()
            error("unsupported beta")
        end
        local _, err = RQ.Api.GetAuctionPrice(5498, identity)
        assert(err:find("unsupported beta", 1, true))
    end)
    test("native stock editor saves typed quantities and rejects a changed scope", function()
        local frames = start()
        groceries(RQ.Database.Current())
        assert(RQ.MainWindow.OpenGroceries(active))
        click(frames, "Set item stock")
        _G.RQStockEditor.item:SetText("2589")
        _G.RQStockEditor.quantity:SetText("12")
        click(frames, "Save minimum")
        equal(RQ.Database.Current().supplies.needs[2589], 12)
        equal(_G.RQStockEditor:IsShown(), false)
        click(frames, "Set item stock")
        _G.RQStockEditor.item:SetText("2589")
        _G.RQStockEditor.quantity:SetText("99")
        RQ.MainWindow.realm = "otherpve"
        click(frames, "Save minimum")
        equal(RQ.Database.Current().supplies.needs[2589], 12)
        assert(_G.RQStockEditor:IsShown())
        assert(RQ.MainWindow.status:find("outside", 1, true))
        _G.InCombatLockdown = function()
            return true
        end
        frames.Emit("PLAYER_REGEN_DISABLED")
        equal(_G.RQStockEditor:IsShown(), false)
        equal(_G.RQStockEditor.item:HasFocus(), false)
        equal(RQ.Api.ShowStockEditor(active, "Character", function() end), false)
    end)
    test("recipe cards show per craft materials cached costs and unknown partial prices within scope", function()
        local frames = start()
        local record = RQ.Database.Current()
        groceries(record)
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
                    reagents = { [5498] = 2 },
                },
            },
        }
        local foreign = clone("Player-Foreign", "Other PVE")
        foreign.recipes.professions[197].recipes[900].name = "Foreign recipe"
        _G.Auctionator = {
            API = {
                v1 = {
                    GetAuctionPriceByItemID = function()
                        return 1250
                    end,
                },
            },
        }
        assert(RQ.MainWindow.Open("professions"))
        equal(#RQ.MainWindow.view.cards, 1)
        local card = RQ.MainWindow.view.cards[1]
        assert(card.summary:find("0g 25s 0c", 1, true))
        assert(card.body:find("Small Lustrous Pearl [5498] x2", 1, true))
        record.recipes.professions[197].recipes[900].reagents[2589] = 1
        _G.Auctionator.API.v1.GetAuctionPriceByItemID = function(_, item)
            return item == 5498 and 1250 or nil
        end
        assert(RQ.MainWindow.Render())
        assert(RQ.MainWindow.view.cards[1].summary:find("1 reagent prices missing", 1, true))
        for id = 901, 913 do
            record.recipes.professions[197].recipes[id] = RQ.Util.Copy(record.recipes.professions[197].recipes[900])
        end
        assert(RQ.MainWindow.Render())
        equal(#RQ.MainWindow.view.cards, 12)
        equal(RQ.MainWindow.view.recipePageCount, 2)
        click(frames, "Next recipes")
        equal(#RQ.MainWindow.view.cards, 2)
        equal(RQ.MainWindow.view.cards[1].recipeId, 912)
        local widgets = #frames.widgets
        click(frames, "Prev recipes")
        equal(#frames.widgets, widgets)
    end)
    test("empty filters never broaden scope and floating groceries follow filter changes", function()
        local frames = start()
        groceries(RQ.Database.Current())
        assert(RQ.MainWindow.OpenGroceries(active))
        click(frames, "Compact list")
        RQ.MainWindow.realm = "missingrealm"
        for _, tab in ipairs({ "roster", "bags", "professions", "settings", "manage", "mail", "shipments" }) do
            assert(RQ.MainWindow.Open(tab))
            equal(RQ.MainWindow.realm, "missingrealm")
            equal(#RQ.MainWindow.view.characterIds, 0)
            assert(_G.RQGroceryWindow.text:GetText():find("No grocery targets", 1, true))
        end
    end)
    test(
        "schema nineteen removes pins lead settings and activity lists idempotently preserving stock and money",
        function()
            start()
            groceries(RQ.Database.Current())
            RQDB.schemaVersion, RQCharDB.schemaVersion = 18, 18
            RQDB.settings.planning.pinnedCharacterId = active
            RQDB.settings.planning.mainLeadLevels = 5
            RQDB.characters[active].activity = { legacy = true }
            RQDB.checklists = { members = {} }
            local account, character = RQ.Migrations.Prepare(RQDB, RQCharDB)
            equal(account.schemaVersion, 19)
            equal(account.characters[active].activity, nil)
            equal(account.checklists, nil)
            equal(account.settings.planning.pinnedCharacterId, nil)
            equal(account.settings.planning.mainLeadLevels, nil)
            equal(account.characters[active].snapshot.money, RQDB.characters[active].snapshot.money)
            equal(account.characters[active].supplies.needs[5498], 3)
            assert(RQDB.characters[active].activity)
            local again = RQ.Migrations.Prepare(account, character)
            equal(again.characters[active].activity, nil)
            equal(again.characters[active].supplies.needs[5498], 3)
        end
    )
end
