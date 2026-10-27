return function(h)
    local test, equal, contains = h.test, h.equal, h.contains
    local function modern()
        local state = { skill = 140, linked = false, learned = false, difficulty = 0, metadata = {} }
        state.items = {
            { itemID = 2589, stackCount = 30, itemName = "Linen Cloth", isBound = false, isLocked = false },
            { itemID = 4496, stackCount = 2, itemName = "Small Bag", isBound = false, isLocked = false },
            { itemID = 6789, stackCount = 2, itemName = "Pattern: Fancy Bag", isBound = false, isLocked = false },
        }
        _G.C_Container = {
            GetContainerNumSlots = function()
                return 16
            end,
            GetContainerNumFreeSlots = function()
                return 8
            end,
            GetContainerItemInfo = function(bag, slot)
                return bag == 0 and state.items[slot] or nil
            end,
        }
        _G.C_Item = {
            GetItemInfoInstant = function(id)
                local detail = state.metadata[id]
                if detail then
                    return id, "type", "subtype", "", 0, detail.classId, detail.subclassId
                end
                return id, "type", "subtype", "", 0, id == 4496 and 1 or id == 6789 and 9 or 7, 0
            end,
            GetItemInfo = function(id)
                local detail = state.metadata[id]
                return "Item", "", 2, 10, 5, "", "", 1, "", 0, 1, 4, 1, detail and detail.bindType
            end,
        }
        _G.GetProfessions = function()
            return 7
        end
        _G.GetProfessionInfo = function()
            return "Tailoring", 0, state.skill, 150, 0, 0, 197
        end
        _G.C_TradeSkillUI = {
            IsTradeSkillReady = function()
                return true
            end,
            IsTradeSkillLinked = function()
                return state.linked
            end,
            IsTradeSkillGuild = function()
                return false
            end,
            IsTradeSkillGuildMember = function()
                return false
            end,
            GetBaseProfessionInfo = function()
                return { professionID = 197, professionName = "Tailoring" }
            end,
            GetAllRecipeIDs = function()
                return { 100, 101 }
            end,
            GetRecipeInfo = function(id)
                return {
                    name = id == 100 and "Linen Bag" or "Fancy Bag",
                    learned = id == 100 or state.learned,
                    numSkillUps = 1,
                    relativeDifficulty = state.difficulty,
                }
            end,
            GetRecipeSourceText = function(id)
                return id == 100 and "Trainer" or "Vendor |Hitem:6789|h[Pattern: Fancy Bag]|h"
            end,
            GetRecipeSchematic = function()
                return {
                    reagentSlotSchematics = {
                        { required = true, quantityRequired = 6, reagents = { { itemID = 2589 } } },
                    },
                }
            end,
        }
        return state
    end

    local function start(native)
        h.fakeCharacter()
        local frames = native and assert(loadfile("Tests/fixtures/Frames.lua"))()()
        local state = modern()
        h.loadAddon()
        if frames then
            frames.Emit("PLAYER_LOGIN")
        else
            h.emit("PLAYER_LOGIN")
        end
        assert(RQ.Database.Register("add"))
        return state, frames
    end

    local function recipient(id)
        local record = RQ.Util.Copy(RQ.Database.Current())
        record.registration = "pending"
        record.identity = {
            ruleset = "PVE",
            faction = "Horde",
            guid = id,
            displayName = "Tombsie",
            fullName = "Miss Tombsie",
            realm = "TestRealm PVE",
        }
        record.supplies = { needs = {}, goals = {} }
        record.inventory.bags.items = { [2589] = 5 }
        record.inventory.bags.tradable = {}
        record.inventory.bags.details = {}
        record.inventory.bags.equipped = { [1] = 16, [2] = 16, [3] = 16, [4] = 0 }
        RQDB.characters[id] = record
        assert(RQ.Database.Register("add", id))
        return record
    end

    test("copy window exposes selectable diagnostics and roster without writing edited text", function()
        local _, frames = start(true)
        _G.SlashCmdList.ROSTERQUARTERMASTER("copy")
        local edit = frames.FindKind("EditBox")
        contains({ edit:GetText() }, "Schemas: account=19; character=19")
        contains({ edit:GetText() }, "ACCOUNT ROSTER")
        contains({ edit:GetText() }, "UnitNameUnmodified:")
        equal(edit.highlighted, true)
        edit:SetText("This must never be imported")
        frames.Click(frames.FindButton("Select all - Ctrl+C to copy"))
        equal(RQ.Database.Current().identity.displayName, "Renamed")
        frames.Emit("PLAYER_REGEN_DISABLED")
        equal(_G.RQCopyWindow:IsShown(), false)
        frames.combat = true
        equal(RQ.Diagnostics.Copy(), false)
    end)

    test("unmodified full names distinguish same first names while GUID pins survive renaming", function()
        h.fakeCharacter()
        _G.UnitNameUnmodified = function()
            return "Quick Slam", "Not A Surname"
        end
        _G.UnitFullName = function()
            return "Quick Slam", "TestRealm PVE"
        end
        h.loadAddon()
        h.emit("PLAYER_LOGIN")
        assert(RQ.Database.Register("add"))
        assert(RQ.Database.SetMain("Player-Test-1"))
        equal(RQ.Database.Current().identity.displayName, "Quick Slam")
        equal(RQ.Database.ResolveMember("Quick Slam"), "Player-Test-1")
        local other = recipient("Player-Other")
        other.identity.displayName, other.identity.fullName = "Quick Death", nil
        equal(RQ.Database.ResolveMember("Quick Death"), "Player-Other")
        _G.UnitNameUnmodified = function()
            return "Quick Renamed"
        end
        assert(RQ.SnapshotService.Refresh())
        equal(RQDB.roster["Player-Test-1"].isMain, true)
        equal(RQ.Database.Current().identity.displayName, "Quick Renamed")
        assert(RQ.Database.SetFullName("Quick Correctsurname"))
        assert(RQ.SnapshotService.Refresh())
        equal(RQ.Character.DisplayName(RQ.Database.Current().identity), "Quick Correctsurname")
        equal(RQ.Database.ResolveMember("Quick Correctsurname"), "Player-Test-1")
        equal(RQCharDB.identity.fullName, "Quick Correctsurname")
        equal(RQ.Database.SetFullName("|bad"), false)
    end)

    test("Forever split surnames repair existing GUID records and distinguish Quick characters", function()
        start()
        local first = RQ.Database.activeId
        local second = "Player-Other"
        recipient(second)
        for _, id in ipairs({ first, second }) do
            RQDB.characters[id].identity.displayName = "Quick"
            RQDB.characters[id].identity.fullName = nil
        end
        assert(RQ.Database.SetMain(first))
        local surname = "Slam"
        _G.GetBuildInfo = function()
            return "1.60.1", "70170", "Oct 1 2026", 16001
        end
        _G.GetRealmName = function()
            return "Classic Beta PvP"
        end
        _G.UnitName = function()
            return "Quick", surname
        end
        _G.UnitNameUnmodified = _G.UnitName
        assert(RQ.SnapshotService.Refresh())
        equal(RQ.Database.Current().identity.displayName, "Quick Slam")
        equal(RQDB.roster[first].displayName, "Quick Slam")
        equal(RQCharDB.identity.displayName, "Quick Slam")
        equal(RQCharDB.identity.realm, "Classic Beta PvP")
        _G.UnitGUID = function()
            return second
        end
        surname = "Death"
        RQCharDB = nil
        h.loadAddon()
        h.emit("PLAYER_LOGIN")
        equal(RQ.Database.Current().identity.displayName, "Quick Death")
        equal(RQ.Database.ResolveMember("Quick Slam"), first)
        equal(RQ.Database.ResolveMember("Quick Death"), second)
        equal(RQDB.roster[first].isMain, false)
        equal(#RQ.Util.Keys(RQDB.characters), 2)
        contains(RQ.Diagnostics.Roster(true), "Quick Slam")
        contains(RQ.Diagnostics.Roster(true), "Quick Death")
        contains(RQ.Api.GetNameEvidence(), "second return: Death")
    end)

    test("bag names resolve from item links cached APIs and previous observations", function()
        local state, frames = start(true)
        recipient("Player-A")
        assert(RQ.SuppliesService.SetNeed(2589, 20, "Player-A"))
        state.items[1].itemName = nil
        state.items[1].hyperlink = "|cffffffff|Hitem:2589:0:0|h[Linen Cloth]|h|r"
        _G.C_Item.GetItemInfo = function()
            return nil
        end
        assert(RQ.SuppliesService.ScanBags())
        equal(RQCharDB.inventory.bags.details[2589].name, "Linen Cloth")
        _G.SlashCmdList.ROSTERQUARTERMASTER("mail")
        contains({ frames.FindKind("EditBox"):GetText() }, "15 x Linen Cloth [2589]")
        state.items[1].hyperlink = nil
        _G.C_Item.GetItemInfo = function()
            return "Localized Linen"
        end
        assert(RQ.SuppliesService.ScanBags())
        equal(RQCharDB.inventory.bags.details[2589].name, "Localized Linen")
        _G.C_Item.GetItemInfo = function()
            return nil
        end
        _G.GetItemInfo = function()
            return "Legacy Linen"
        end
        assert(RQ.SuppliesService.ScanBags())
        equal(RQCharDB.inventory.bags.details[2589].name, "Legacy Linen")
        _G.GetItemInfo = nil
        assert(RQ.SuppliesService.ScanBags())
        equal(RQCharDB.inventory.bags.details[2589].name, "Legacy Linen")
        equal(RQCharDB.inventory.bags.items[2589], 30)
        equal(RQCharDB.inventory.bags.tradable[2589], 30)
    end)

    test("split names are client gated and do not duplicate full names or append realms", function()
        start()
        local first, second = "Quick", "Death"
        _G.UnitNameUnmodified = function()
            return first, second
        end
        _G.UnitName = _G.UnitNameUnmodified
        _G.GetRealmName = function()
            return "Classic Beta PvP"
        end
        _G.WOW_PROJECT_ID = 18
        equal(RQ.Api.GetCharacterIdentity().displayName, "Quick")
        _G.GetBuildInfo = function()
            return "1.60.1", "70170", "", 16001
        end
        equal(RQ.Api.GetCharacterIdentity().displayName, "Quick Death")
        first, second = "Quick Death", "Death"
        equal(RQ.Api.GetCharacterIdentity().displayName, "Quick Death")
        first, second = "Quick", "ClassicBetaPvP"
        equal(RQ.Api.GetCharacterIdentity().displayName, "Quick")
        second = ""
        equal(RQ.Api.GetCharacterIdentity().displayName, "Quick")
        second = "Death"
        _G.UnitNameUnmodified = nil
        equal(RQ.Api.GetCharacterIdentity().displayName, "Quick Death")
        _G.UnitFullName, _G.UnitName = _G.UnitName, nil
        equal(RQ.Api.GetCharacterIdentity().displayName, "Quick Death")
        _G.GetRealmName = nil
        equal(RQ.Api.GetCharacterIdentity().displayName, "Quick")
        _G.issecretvalue = function(value)
            return value == "Death"
        end
        equal(RQ.Api.GetCharacterIdentity().displayName, nil)
    end)

    test("item labels reject mismatched links and survive nameless duplicate stacks", function()
        local state = start()
        _G.C_Item.GetItemInfo = function()
            return nil
        end
        state.items = {
            { itemID = 2589, stackCount = 10, itemName = "Linen Cloth", isBound = false, isLocked = false },
            { itemID = 2589, stackCount = 5, isBound = true, isLocked = false },
            {
                itemID = 2592,
                stackCount = 3,
                hyperlink = "|Hitem:2589|h[Linen Cloth]|h",
                isBound = false,
                isLocked = false,
            },
        }
        assert(RQ.SuppliesService.ScanBags())
        equal(RQCharDB.inventory.bags.details[2589].name, "Linen Cloth")
        equal(RQCharDB.inventory.bags.items[2589], 15)
        equal(RQCharDB.inventory.bags.tradable[2589], 10)
        equal(RQCharDB.inventory.bags.details[2592].name, nil)
    end)

    test("Forever uses complete same-name fallback evidence without mixing modified identities", function()
        start()
        _G.GetBuildInfo = function()
            return "1.60.1", "70170", "", 16001
        end
        _G.UnitNameUnmodified = function()
            return "Quick"
        end
        _G.UnitName = function()
            return "Quick", "Death"
        end
        equal(RQ.Api.GetCharacterIdentity().displayName, "Quick Death")
        equal(RQ.Api.GetCharacterIdentity().nameComplete, true)
        _G.UnitName = function()
            return "Disguised", "Person"
        end
        local identity = RQ.Api.GetCharacterIdentity()
        equal(identity.displayName, "Quick")
        equal(identity.nameComplete, false)
        _G.UnitFullName = function()
            return "Quick Death", "TestRealm PVE"
        end
        equal(RQ.Api.GetCharacterIdentity().displayName, "Quick Death")
        _G.GetBuildInfo = nil
        equal(RQ.Api.GetCharacterIdentity().nameComplete, false)
    end)

    test("cold item names request data once and refresh on successful cache events", function()
        local state = start()
        local requests = 0
        state.items[1].itemName = nil
        RQ.Database.Current().inventory.bags.details[2589].name = nil
        _G.C_Item.GetItemInfo = function()
            return nil
        end
        _G.C_Item.RequestLoadItemDataByID = function(id)
            equal(id, 2589)
            requests = requests + 1
        end
        assert(RQ.SuppliesService.ScanBags())
        assert(RQ.SuppliesService.ScanBags())
        equal(requests, 1)
        equal(RQCharDB.inventory.bags.details[2589].name, nil)
        _G.C_Item.GetItemInfo = function()
            return "Linen Cloth"
        end
        h.emit("GET_ITEM_INFO_RECEIVED", 2589, true)
        h.emit("GET_ITEM_INFO_RECEIVED", 2589, true)
        h.flushTimers()
        equal(RQCharDB.inventory.bags.details[2589].name, "Linen Cloth")
        equal(requests, 1)
        contains({ RQ.Api.GetCapabilities()["event:GET_ITEM_INFO_RECEIVED"] }, "observed")
    end)

    test("failed item cache events are explicit and late logout events do not scan cleared bags", function()
        local state = start()
        state.items[1].itemName = nil
        RQ.Database.Current().inventory.bags.details[2589].name = nil
        _G.C_Item.GetItemInfo = function()
            return nil
        end
        assert(RQ.SuppliesService.ScanBags())
        h.emit("GET_ITEM_INFO_RECEIVED", 2589, false)
        contains(h.messages(), "Item name data unavailable for item 2589")
        h.emit("PLAYER_LOGOUT")
        local before = RQ.Database.Current().inventory.bags
        _G.C_Container.GetContainerItemInfo = function()
            error("must not scan after logout")
        end
        RQ.SuppliesService.itemNamesReceived[2589] = nil
        h.emit("GET_ITEM_INFO_RECEIVED", 2589, true)
        h.flushTimers()
        equal(RQ.Database.Current().inventory.bags, before)
        equal(RQ.SuppliesService.itemNamesReceived[2589], nil)
    end)

    test("recipe groceries resolve absent material names without inventing bag stock", function()
        start()
        local labels = { [2672] = "Localized Meat", [2678] = "Localized Spice", [6370] = "Localized Oil" }
        _G.C_Item.GetItemInfo = function(id)
            return labels[id]
        end
        _G.C_TradeSkillUI.GetRecipeSchematic = function()
            return {
                reagentSlotSchematics = {
                    { required = true, quantityRequired = 1, reagents = { { itemID = 2672 } } },
                    { required = true, quantityRequired = 1, reagents = { { itemID = 2678 } } },
                    { required = true, quantityRequired = 2, reagents = { { itemID = 6370 } } },
                },
            }
        end
        assert(RQ.SuppliesService.ScanRecipes())
        assert(RQ.SuppliesService.SetGoal(197, 100, 145))
        local record = RQ.Database.Current()
        local before = record.inventory.bags
        local lines = RQ.SuppliesService.Report(RQ.Database.activeId)
        contains(lines, "Localized Meat [2672]: target 5, in bags 0, missing 5")
        contains(lines, "Localized Spice [2678]: target 5, in bags 0, missing 5")
        contains(lines, "Localized Oil [6370]: target 10, in bags 0, missing 10")
        contains(RQ.SuppliesService.Report(RQ.Database.activeId, true), "Localized Oil [6370] x2")
        local cards = RQ.SuppliesService.RecipeCards(RQDB, RQ.Database.activeId, RQ.Api.GetServerTime())
        contains({ cards[1].body }, "Localized Meat [2672] x1")
        equal(record.inventory.bags, before)
        equal(before.items[6370], nil)
        equal(before.details[6370], nil)
        equal(record.recipes.professions[197].recipes[100].reagents[6370], 2)
    end)

    test("item labels reuse other roster observations without borrowing their quantities", function()
        start()
        local other = recipient("Player-Other")
        other.inventory.bags.items[6370] = 7
        other.inventory.bags.details[6370] = { name = "Observed Oil" }
        _G.C_Item.GetItemInfo = function()
            error("No metadata lookup needed")
        end
        assert(RQ.SuppliesService.SetNeed(6370, 10))
        local current = RQ.Database.Current()
        contains(
            RQ.SuppliesService.Report(RQ.Database.activeId),
            "Observed Oil [6370]: target 10, in bags 0, missing 10"
        )
        current.inventory.bags.details[6370] = { name = "Preferred Oil" }
        equal(RQ.SuppliesService.ItemLabel(RQDB, 6370, current), "Preferred Oil")
        equal(current.inventory.bags.items[6370], nil)
        equal(other.inventory.bags.items[6370], 7)
    end)

    test("cold absent materials refresh visible Supplies after one request without scanning bags", function()
        local _, frames = start(true)
        local requests = 0
        _G.C_Item.GetItemInfo = function()
            return nil
        end
        _G.C_Item.RequestLoadItemDataByID = function(id)
            equal(id, 6370)
            requests = requests + 1
        end
        assert(RQ.SuppliesService.SetNeed(6370, 10))
        assert(RQ.MainWindow.Open("supplies"))
        local inventory = RQ.Database.Current().inventory
        equal(RQ.MainWindow.view.cards[2].title, "Item 6370")
        equal(RQ.MainWindow.view.cards[2].itemId, 6370)
        assert(RQ.MainWindow.Render())
        equal(requests, 1)
        RQ.Api.GetBagItems = function()
            error("Metadata must not trigger absent-item bag scans")
        end
        _G.C_Item.GetItemInfo = function()
            return "Localized Oil"
        end
        frames.Emit("GET_ITEM_INFO_RECEIVED", 6370, true)
        frames.Emit("GET_ITEM_INFO_RECEIVED", 6370, true)
        h.flushTimers()
        equal(RQ.MainWindow.view.cards[2].title, "Localized Oil")
        equal(requests, 1)
        equal(RQ.Database.Current().inventory, inventory)
        equal(inventory.bags.items[6370], nil)
        equal(RQ.SuppliesService.pendingItemNames[6370], nil)
    end)

    test("failed absent-item lookups report once and later successful data can resolve them", function()
        start()
        local requests = 0
        _G.C_Item.GetItemInfo = function()
            return nil
        end
        _G.C_Item.RequestLoadItemDataByID = function()
            requests = requests + 1
        end
        equal(RQ.SuppliesService.ItemLabel(RQDB, 6370), "Item 6370")
        local messages = #h.messages()
        h.emit("GET_ITEM_INFO_RECEIVED", 6370, false)
        h.emit("GET_ITEM_INFO_RECEIVED", 6370, false)
        h.emit("GET_ITEM_INFO_RECEIVED", 2672, false)
        equal(#h.messages(), messages + 1)
        contains(h.messages(), "Item name data unavailable for item 6370")
        equal(RQ.SuppliesService.ItemLabel(RQDB, 6370), "Item 6370")
        equal(requests, 1)
        _G.GetItemInfo = function()
            return "Legacy Oil"
        end
        h.emit("GET_ITEM_INFO_RECEIVED", 6370, true)
        equal(RQ.SuppliesService.ItemLabel(RQDB, 6370), "Legacy Oil")
        equal(RQ.SuppliesService.pendingItemNames[6370], nil)
        equal(RQ.Database.Current().inventory.bags.items[6370], nil)
    end)

    test("label adapter rejects restricted names and degrades without metadata APIs", function()
        start()
        _G.C_Item.GetItemInfo = function()
            return "Restricted"
        end
        _G.issecretvalue = function(value)
            return value == "Restricted"
        end
        _G.GetItemInfo = function()
            return "Public legacy name"
        end
        equal(RQ.Api.GetItemName(6370), "Public legacy name")
        _G.C_Item.GetItemInfo, _G.GetItemInfo = nil, nil
        equal(RQ.Api.GetItemName(6370), "Public legacy name")
        equal(RQ.SuppliesService.ItemLabel(RQDB, 2672), "Item 2672")
        equal(RQ.Api.GetItemName(-1), nil)
        contains({ RQ.Api.GetCapabilities().itemName }, "invalid item ID")
        equal(RQ.Database.Current().inventory.bags.items[2672], nil)
    end)

    test("bag ledger records item IDs and quantities while excluding bound locked and unknown stacks", function()
        local state = start()
        equal(RQ.Database.Current().inventory.bags.items[2589], 30)
        equal(RQCharDB.inventory.bags.tradable[2589], 30)
        state.items[1].isBound = true
        state.items[2].isLocked = true
        state.items[3].isBound = nil
        assert(RQ.SuppliesService.ScanBags())
        equal(next(RQCharDB.inventory.bags.tradable), nil)
        equal(RQCharDB.inventory.bags.items[2589], 30)
        assert(RQCharDB.inventory.bags.items ~= RQ.Database.Current().inventory.bags.items)
        _G.C_Container.GetContainerItemInfo = function()
            error("unavailable")
        end
        assert(RQ.SuppliesService.ScanBags())
        equal(RQCharDB.inventory.bags.complete, false)
        equal(RQCharDB.inventory.bags.items[2589], 30)
        contains(h.messages(), "Bag contents unavailable")
    end)

    test("restricted nested bag data and missing clocks cannot publish empty successful scans", function()
        start()
        _G.issecretvalue = function(value)
            return value == 30
        end
        local scan, err = RQ.Api.GetBagItems()
        equal(scan, nil)
        contains({ err }, "restricted")
        _G.issecretvalue = nil
        _G.GetServerTime = nil
        equal(RQ.Api.GetBagItems(), nil)
        equal(RQ.Database.Current().inventory.bags.items[2589], 30)
    end)

    test("bag capacity and fixed recipe outputs come from guarded localized client observations", function()
        local state = start()
        _G.CONTAINER_SLOTS = "%d Slot %s"
        _G.C_TooltipInfo = {
            GetItemByID = function(id)
                if id == 4496 then
                    return { lines = { { leftText = "|cffffffff10 Slot Bag|r" } } }
                end
            end,
        }
        assert(RQ.SuppliesService.ScanBags())
        equal(RQCharDB.inventory.bags.details[4496].bagSlots, 10)
        local schematic = _G.C_TradeSkillUI.GetRecipeSchematic
        _G.C_TradeSkillUI.GetRecipeSchematic = function(...)
            local value = schematic(...)
            value.outputItemID, value.quantityMin, value.quantityMax = 4496, 1, 1
            return value
        end
        assert(RQ.SuppliesService.ScanRecipes())
        local recipe = RQCharDB.recipes.professions[197].recipes[100]
        equal(recipe.outputItemId, 4496)
        equal(recipe.outputCount, 1)
        equal(recipe.bagSlots, 10)
        _G.CONTAINER_SLOTS = "Sac (%d places)"
        _G.C_TooltipInfo.GetItemByID = function()
            return { lines = { { leftText = "Sac (12 places)" } } }
        end
        assert(RQ.SuppliesService.ScanBags())
        equal(RQCharDB.inventory.bags.details[4496].bagSlots, 12)
        state.metadata[4496] = { classId = 1, subclassId = 1 }
        assert(RQ.SuppliesService.ScanBags())
        equal(RQCharDB.inventory.bags.details[4496].bagSlots, nil)
        state.metadata[4496] = nil
        _G.C_TooltipInfo.GetItemByID = function()
            return { lines = { { leftText = "Unknown text 99" } } }
        end
        assert(RQ.SuppliesService.ScanRecipes())
        equal(RQCharDB.recipes.professions[197].recipes[100].bagSlots, nil)
        _G.C_TradeSkillUI.GetRecipeSchematic = function(...)
            local value = schematic(...)
            value.outputItemID, value.quantityMin, value.quantityMax = 4496, 1, 2
            return value
        end
        assert(RQ.SuppliesService.ScanRecipes())
        equal(RQCharDB.recipes.professions[197].recipes[100].outputItemId, nil)
    end)

    test("own recipe scans retain learned state materials and acquisition sources across reload", function()
        start()
        h.emit("TRADE_SKILL_SHOW")
        h.flushTimers()
        local recipes = RQ.Database.Current().recipes.professions[197].recipes
        equal(recipes[100].learned, true)
        equal(recipes[101].learned, false)
        equal(recipes[100].reagents[2589], 6)
        equal(recipes[101].sourceItem, 6789)
        equal(recipes[100].source, "Trainer")
        equal(RQ.Database.Current().recipes.complete, false)
        h.loadAddon()
        h.emit("PLAYER_LOGIN")
        equal(RQCharDB.recipes.professions[197].recipes[100].learned, true)
        assert(RQCharDB.recipes.professions ~= RQ.Database.Current().recipes.professions)
    end)

    test("linked recipes never become owned and failed scans preserve prior known recipes", function()
        local state = start()
        assert(RQ.SuppliesService.ScanRecipes())
        state.linked = true
        _G.C_TradeSkillUI.GetAllRecipeIDs = function()
            error("must not read linked recipes")
        end
        assert(RQ.SuppliesService.ScanRecipes())
        equal(RQ.Database.Current().recipes.professions[197].recipes[100].learned, true)
        contains({ RQ.Database.Current().recipes.error }, "linked/guild")
        local grocery, notes = RQ.SuppliesService.Grocery(RQ.Database.Current(), 123456789, 48)
        equal(grocery[2589].target, 6)
        equal(grocery[2589].orangeStale, true)
        contains(notes, "STALE / uncertain automatic")
        local previous = RQ.Database.Current().recipes
        h.emit("TRADE_SKILL_SHOW")
        h.emit("TRADE_SKILL_CLOSE")
        h.flushTimers()
        equal(RQ.Database.Current().recipes, previous)
    end)

    test(
        "orange recipe scans automatically derive one-craft groceries and survive reload without manual needs",
        function()
            local state = start()
            _G.C_TradeSkillUI.GetRecipeSchematic = function()
                return {
                    reagentSlotSchematics = {
                        { required = true, quantityRequired = 1, reagents = { { itemID = 5498 } } },
                        { required = true, quantityRequired = 2, reagents = { { itemID = 2589 } } },
                    },
                }
            end
            h.emit("TRADE_SKILL_SHOW")
            h.flushTimers()
            local record = RQ.Database.Current()
            local grocery = RQ.SuppliesService.Grocery(record, 123456789, 48)
            equal(grocery[5498].target, 1)
            equal(grocery[5498].missing, 1)
            equal(grocery[2589].target, 2)
            equal(grocery[5498].orangeTarget, 1)
            equal(grocery[5498].orangeStale, false)
            equal(grocery[5498].orangeRecipes[1].recipeId, 100)
            equal(grocery[5498].orangeRecipes[1].scannedAt, 123456789)
            equal(next(record.supplies.needs), nil)
            equal(next(record.supplies.goals), nil)
            assert(RQ.SuppliesService.ScanRecipes())
            equal(RQ.SuppliesService.Grocery(RQ.Database.Current())[5498].target, 1)
            h.loadAddon()
            h.emit("PLAYER_LOGIN")
            equal(RQ.SuppliesService.Grocery(RQ.Database.Current())[5498].target, 1)
            state.difficulty = 1
            assert(RQ.SuppliesService.ScanRecipes())
            equal(RQ.SuppliesService.Grocery(RQ.Database.Current())[5498], nil)
            equal(next(RQ.Database.Current().supplies.needs), nil)
        end
    )

    test(
        "automatic groceries sum shared recipes and professions without double-counting explicit goals or floors",
        function()
            local state = start()
            state.learned = true
            assert(RQ.SuppliesService.ScanRecipes())
            local record = RQ.Database.Current()
            equal(RQ.SuppliesService.Grocery(record)[2589].target, 12)
            assert(RQ.SuppliesService.SetGoal(197, 100, 142))
            equal(RQ.SuppliesService.Grocery(RQ.Database.Current())[2589].target, 18)
            assert(RQ.SuppliesService.SetNeed(2589, 20))
            record = RQ.Database.Current()
            equal(RQ.SuppliesService.Grocery(record)[2589].target, 20)
            record.recipes.professions[164] = RQ.Util.Copy(record.recipes.professions[197])
            record.snapshot.professions[164] = { name = "Blacksmithing", skill = 1, maxSkill = 75 }
            local grocery = RQ.SuppliesService.Grocery(record)
            equal(grocery[2589].target, 30)
            equal(grocery[2589].orangeTarget, 18)
            equal(#grocery[2589].orangeRecipes, 3)
            equal(record.supplies.needs[2589], 20)
            equal(record.recipes.professions[197].recipes[100].reagents[2589], 6)
        end
    )

    test("automatic orange groceries reject unlearned non-orange incomplete and capped recipes", function()
        start()
        assert(RQ.SuppliesService.ScanRecipes())
        local record = RQ.Database.Current()
        local recipe = record.recipes.professions[197].recipes[100]
        for _, difficulty in ipairs({ 1, 2, 3 }) do
            recipe.difficulty = difficulty
            equal(next((RQ.SuppliesService.Grocery(record))), nil)
        end
        recipe.difficulty = nil
        equal(next((RQ.SuppliesService.Grocery(record))), nil)
        recipe.difficulty, recipe.learned = 0, false
        equal(next((RQ.SuppliesService.Grocery(record))), nil)
        recipe.learned, recipe.reagentsComplete = true, false
        equal(next((RQ.SuppliesService.Grocery(record))), nil)
        recipe.reagentsComplete, recipe.skillUps = true, 0
        equal(next((RQ.SuppliesService.Grocery(record))), nil)
        recipe.skillUps = 1
        record.snapshot.professions[197].skill = 150
        equal(next((RQ.SuppliesService.Grocery(record))), nil)
        record.snapshot.professions[197].skill = 140
        record.recipes.professions[197].complete = false
        equal(next((RQ.SuppliesService.Grocery(record))), nil)
        record.recipes.professions[197].complete = true
        record.snapshot.professions[197] = nil
        equal(next((RQ.SuppliesService.Grocery(record))), nil)
    end)

    test("Small Lustrous Pearl orange needs drive mail without configured goals and respect bank coverage", function()
        local state, frames = start(true)
        _G.C_TradeSkillUI.GetRecipeSchematic = function()
            return {
                reagentSlotSchematics = {
                    { required = true, quantityRequired = 1, reagents = { { itemID = 5498 } } },
                },
            }
        end
        assert(RQ.SuppliesService.ScanRecipes())
        local other = recipient("Player-Pearl")
        other.inventory.bags.equipped = { [1] = 16 }
        RQ.Database.Current().recipes.professions = {}
        state.items = {
            { itemID = 5498, stackCount = 2, itemName = "Small Lustrous Pearl", isBound = false, isLocked = false },
        }
        assert(RQ.SuppliesService.ScanBags())
        local function evaluate()
            return RQ.SuppliesService.Evaluate(RQDB, RQ.Database.activeId, 123456789)
        end
        local report = evaluate()
        equal(#report.proposals, 1)
        equal(report.proposals[1].characterId, "Player-Pearl")
        equal(report.proposals[1].itemId, 5498)
        equal(report.proposals[1].count, 1)
        equal(report.proposals[1].stale, false)
        contains({ report.proposals[1].reason }, "automatic orange")
        _G.SlashCmdList.ROSTERQUARTERMASTER("mail")
        contains({ frames.FindKind("EditBox"):GetText() }, "Small Lustrous Pearl [5498]")
        contains({ frames.FindKind("EditBox"):GetText() }, "automatic orange recipe materials")
        contains(RQ.SuppliesService.Report("Player-Pearl"), "Auto orange: Linen Bag [100]")
        local found = false
        for _, card in ipairs(RQ.SuppliesService.MailCards(RQDB, 123456789)) do
            if card.itemId == 5498 then
                found = true
                equal(card.id, "Player-Pearl")
                contains({ card.body }, "automatic orange")
            end
        end
        assert(found)
        other.recipes.professions[197].scannedAt = 123456789 - 49 * 3600
        equal(evaluate().proposals[1].stale, true)
        contains(evaluate().notes["Player-Pearl"], "STALE / uncertain automatic")
        other.recipes.error = "Scan failed"
        equal(evaluate().groceries["Player-Pearl"][5498].target, 1)
        other.inventory.bank.complete, other.inventory.bank.coherent = true, true
        other.inventory.bank.scannedAt = 123456789
        other.inventory.bank.items = { [5498] = 1 }
        equal(#evaluate().proposals, 0)
        equal(evaluate().groceries["Player-Pearl"][5498].withdraw, 1)
        other.inventory.bank.coherent = false
        state.items[1].isBound = true
        assert(RQ.SuppliesService.ScanBags())
        equal(#evaluate().proposals, 0)
    end)

    test("automatic orange groceries reserve sender materials before proposing surplus mail", function()
        start()
        assert(RQ.SuppliesService.ScanRecipes())
        local other = recipient("Player-A")
        other.supplies.needs[2589] = 50
        local report = RQ.SuppliesService.Evaluate(RQDB, RQ.Database.activeId, 123456789)
        local quantity = 0
        for _, proposal in ipairs(report.proposals) do
            if proposal.itemId == 2589 then
                quantity = quantity + proposal.count
            end
        end
        equal(quantity, 24)
        equal(RQ.Database.Current().inventory.bags.items[2589], 30)
    end)

    test("ambiguous reagent alternatives are not guessed into a grocery list", function()
        start()
        _G.C_TradeSkillUI.GetRecipeSchematic = function()
            return {
                reagentSlotSchematics = {
                    { required = true, quantityRequired = 2, reagents = { { itemID = 2589 }, { itemID = 2592 } } },
                },
            }
        end
        assert(RQ.SuppliesService.ScanRecipes())
        assert(RQ.SuppliesService.SetGoal(197, 100, 150))
        local grocery, notes = RQ.SuppliesService.Grocery(RQ.Database.Current())
        equal(next(grocery), nil)
        contains(notes, "missing skill/material data")
    end)

    test("recipe goals recompute shortages from current skill and bag contents with minimum stock targets", function()
        local state = start()
        assert(RQ.SuppliesService.ScanRecipes())
        assert(RQ.SuppliesService.SetGoal(197, 100, 150))
        local grocery = RQ.SuppliesService.Grocery(RQ.Database.Current())
        equal(grocery[2589].target, 60)
        equal(grocery[2589].missing, 30)
        assert(RQ.SuppliesService.SetNeed(2589, 40))
        equal(RQ.SuppliesService.Grocery(RQ.Database.Current())[2589].target, 60)
        state.skill = 145
        h.emit("SKILL_LINES_CHANGED")
        h.flushTimers()
        grocery = RQ.SuppliesService.Grocery(RQ.Database.Current())
        equal(grocery[2589].target, 40)
        equal(grocery[2589].missing, 10)
        assert(RQ.SuppliesService.SetNeed(2589, 0))
        equal(RQ.SuppliesService.Grocery(RQ.Database.Current())[2589].missing, 0)
        state.items[1].stackCount = 5
        h.emit("BAG_UPDATE_DELAYED")
        h.flushTimers()
        equal(RQ.SuppliesService.Grocery(RQ.Database.Current())[2589].missing, 25)
        assert(RQ.SuppliesService.SetGoal(197, 0, 0))
        grocery = RQ.SuppliesService.Grocery(RQ.Database.Current())
        equal(grocery[2589].target, 6)
        equal(grocery[2589].missing, 1)
    end)

    test("mail allocations reserve sender needs and split finite stock without duplicate recipe suggestions", function()
        start()
        assert(RQ.SuppliesService.ScanRecipes())
        local first = recipient("Player-A")
        local second = recipient("Player-B")
        first.recipes.professions[197].recipes[102] = RQ.Util.Copy(first.recipes.professions[197].recipes[101])
        assert(RQ.SuppliesService.SetNeed(2589, 10))
        assert(RQ.SuppliesService.SetNeed(2589, 20, "Player-A"))
        assert(RQ.SuppliesService.SetNeed(2589, 25, "Player-B"))
        local report = RQ.SuppliesService.Evaluate(RQDB, RQ.Database.activeId, 123456789)
        local cloth, bags, patterns = 0, 0, 0
        for _, proposal in ipairs(report.proposals) do
            if proposal.itemId == 2589 then
                cloth = cloth + proposal.count
                equal(proposal.count, proposal.characterId == "Player-A" and 15 or 5)
            elseif proposal.itemId == 4496 then
                bags = bags + proposal.count
            elseif proposal.itemId == 6789 then
                patterns = patterns + proposal.count
            end
        end
        equal(cloth, 20)
        equal(bags, 2)
        equal(patterns, 1)
        equal(first.inventory.bags.items[2589], 5)
        equal(second.inventory.bags.items[2589], 5)
        equal(RQ.Database.Current().inventory.bags.items[2589], 30)
        equal(
            RQ.SuppliesService.Evaluate(RQDB, RQ.Database.activeId, 123456789).proposals[1].count,
            report.proposals[1].count
        )
    end)

    test("stale source inventory blocks proposals while stale recipients remain explicitly uncertain", function()
        start()
        local other = recipient("Player-A")
        assert(RQ.SuppliesService.SetNeed(2589, 20, "Player-A"))
        other.inventory.bags.scannedAt = 123456789 - 49 * 3600
        local report = RQ.SuppliesService.Evaluate(RQDB, RQ.Database.activeId, 123456789)
        equal(report.proposals[1].stale, true)
        report = RQ.SuppliesService.Evaluate(RQDB, RQ.Database.activeId, 123456789 + 49 * 3600)
        equal(#report.proposals, 0)
        contains(report.warnings, "Scan the active")
        other.inventory.bags.complete = false
        equal(RQ.SuppliesService.Grocery(other)[2589].missing, nil)
        assert(RQ.Database.Register("ignore", "Player-A"))
        equal(RQ.SuppliesService.Evaluate(RQDB, RQ.Database.activeId, 123456789).groceries["Player-A"], nil)
    end)

    test("supplies and recipes commands open copyable reports and never execute mail operations", function()
        local _, frames = start(true)
        local function copiedText()
            for _, widget in ipairs(frames.widgets) do
                if widget.kind == "EditBox" and widget.parent and widget.parent.parent == _G.RQCopyWindow then
                    return widget:GetText()
                end
            end
            error("No copy window edit box")
        end
        assert(RQ.SuppliesService.ScanRecipes())
        recipient("Player-A")
        _G.SlashCmdList.ROSTERQUARTERMASTER("need 2589 20 Player-A")
        _G.SlashCmdList.ROSTERQUARTERMASTER("goal 197 100 150 Player-A")
        _G.SlashCmdList.ROSTERQUARTERMASTER("supplies")
        equal(RQ.MainWindow.tab, "bags")
        frames.Click(frames.FindButton("Full report"))
        contains({ copiedText() }, "target")
        RQ.Api.HideCopyWindow()
        _G.SlashCmdList.ROSTERQUARTERMASTER("recipes Player-A")
        contains({ copiedText() }, "[KNOWN]")
        RQ.Api.HideCopyWindow()
        _G.SlashCmdList.ROSTERQUARTERMASTER("mail")
        contains({ copiedText() }, "nothing is attached")
        contains({ copiedText() }, "Linen Cloth [2589]")
        frames.Emit("MAIL_SHOW")
        contains(h.messages(), "No items are attached or sent automatically")
        equal(RQ.SuppliesService.SetNeed(0, 10), false)
        equal(RQ.SuppliesService.SetGoal(197, 999, 150), false)
    end)

    test("empty mail reports explain missing recipient setup without inventing profession needs", function()
        local _, frames = start(true)
        local other = recipient("Player-A")
        other.inventory.bags.equipped[4] = 16
        _G.SlashCmdList.ROSTERQUARTERMASTER("mail")
        local text = frames.FindKind("EditBox"):GetText()
        contains({ text }, "No safe matching proposals")
        contains({ text }, "Miss Tombsie: no grocery targets")
        contains({ text }, "Miss Tombsie: no recipe catalogs scanned")
        contains({ text }, "Profession routing found no eligible surplus")
        equal(#RQ.SuppliesService.Evaluate(RQDB, RQ.Database.activeId, 123456789).proposals, 0)
        assert(RQ.SuppliesService.SetNeed(2589, 20, "Player-A"))
        _G.SlashCmdList.ROSTERQUARTERMASTER("mail")
        contains({ frames.FindKind("EditBox"):GetText() }, "15 x Linen Cloth [2589] -> Miss Tombsie")
    end)

    test("empty mail reports distinguish configured needs and unavailable recipient bags", function()
        local _, frames = start(true)
        local other = recipient("Player-A")
        other.inventory.bags.equipped[4] = 16
        assert(RQ.SuppliesService.SetNeed(2589, 5, "Player-A"))
        _G.SlashCmdList.ROSTERQUARTERMASTER("mail")
        contains({ frames.FindKind("EditBox"):GetText() }, "Miss Tombsie: grocery targets are already covered")
        other.inventory.bags.complete = false
        other.recipes.error = "Profession window not ready"
        _G.SlashCmdList.ROSTERQUARTERMASTER("mail")
        contains({ frames.FindKind("EditBox"):GetText() }, "Miss Tombsie: bag contents are incomplete")
        contains({ frames.FindKind("EditBox"):GetText() }, "last recipe scan: Profession window not ready")
        other.inventory.bags.complete = true
        assert(RQ.SuppliesService.SetNeed(9999, 10, "Player-A"))
        _G.SlashCmdList.ROSTERQUARTERMASTER("mail")
        contains({ frames.FindKind("EditBox"):GetText() }, "Miss Tombsie: shortages exist")
        equal(#RQ.SuppliesService.Evaluate(RQDB, RQ.Database.activeId, 123456789).proposals, 0)
    end)

    test("empty mail reports identify the absence of enabled recipients", function()
        local _, frames = start(true)
        _G.SlashCmdList.ROSTERQUARTERMASTER("mail")
        contains({ frames.FindKind("EditBox"):GetText() }, "No other enabled roster members")
        local other = recipient("Player-A")
        RQDB.roster[other.identity.guid].enabled = false
        _G.SlashCmdList.ROSTERQUARTERMASTER("mail")
        contains({ frames.FindKind("EditBox"):GetText() }, "No other enabled roster members")
    end)

    test("profession routing sends cloth metals and only eligible BoE greens without grocery setup", function()
        local state = start()
        RQ.Database.Current().snapshot.professions = { [186] = { name = "Mining", skill = 100, maxSkill = 150 } }
        local tailor = recipient("Player-A")
        tailor.snapshot.professions = { [197] = { name = "Tailoring", skill = 81, maxSkill = 150 } }
        local smith = recipient("Player-B")
        smith.snapshot.professions = { [164] = { name = "Blacksmithing", skill = 115, maxSkill = 150 } }
        local enchanter = recipient("Player-C")
        enchanter.snapshot.professions = { [333] = { name = "Enchanting", skill = 113, maxSkill = 150 } }
        state.items = {}
        state.metadata = {
            [2589] = { classId = 7, subclassId = 5 },
            [2770] = { classId = 7, subclassId = 7 },
            [1000] = { classId = 4, subclassId = 1, bindType = 2 },
            [1001] = { classId = 2, subclassId = 1, bindType = 2 },
            [1002] = { classId = 4, subclassId = 1, bindType = 1 },
            [1003] = { classId = 4, subclassId = 1 },
            [1004] = { classId = 4, subclassId = 1, bindType = 2 },
            [1005] = { classId = 4, subclassId = 1, bindType = 2 },
            [1006] = { classId = 4, subclassId = 1, bindType = 2 },
        }
        for _, id in ipairs(RQ.Util.Keys(state.metadata)) do
            state.items[#state.items + 1] = {
                itemID = id,
                stackCount = 10,
                itemName = "Item " .. id,
                isBound = id == 1005,
                isLocked = id == 1006,
                quality = id == 1004 and 3 or 2,
            }
        end
        assert(RQ.SuppliesService.ScanBags())
        local report = RQ.SuppliesService.Evaluate(RQDB, RQ.Database.activeId, 123456789)
        local found = {}
        for _, proposal in ipairs(report.proposals) do
            found[proposal.itemId] = proposal
            contains({ proposal.reason }, "Profession routing")
            equal(proposal.count, 10)
        end
        equal(#report.proposals, 4)
        equal(found[2589].characterId, "Player-A")
        equal(found[2770].characterId, "Player-B")
        equal(found[1000].characterId, "Player-C")
        equal(found[1001].characterId, "Player-C")
        equal(RQCharDB.inventory.bags.details[1000].bindType, 2)
        equal(RQCharDB.inventory.bags.details[1000].quality, 2)
        enchanter.snapshot.sections.professions.complete = false
        report = RQ.SuppliesService.Evaluate(RQDB, RQ.Database.activeId, 123456789)
        equal(report.proposals[1].stale, true)
        _G.GetItemInfo = _G.C_Item.GetItemInfo
        _G.C_Item.GetItemInfo = nil
        assert(RQ.SuppliesService.ScanBags())
        equal(RQCharDB.inventory.bags.details[1000].bindType, 2)
        _G.GetItemInfo = function()
            return nil
        end
        assert(RQ.SuppliesService.ScanBags())
        equal(RQCharDB.inventory.bags.details[1000].bindType, nil)
        equal(#RQ.SuppliesService.Evaluate(RQDB, RQ.Database.activeId, 123456789).proposals, 2)
    end)

    test("routing reserves explicit needs before surplus and never bounces between matching professions", function()
        start()
        local source = RQ.Database.Current()
        source.inventory.bags.details[2589].subclassId = 5
        local first = recipient("Player-A")
        local second = recipient("Player-B")
        first.inventory.bags.equipped[4], second.inventory.bags.equipped[4] = 16, 16
        equal(#RQ.SuppliesService.Evaluate(RQDB, RQ.Database.activeId, 123456789).proposals, 0)
        source.snapshot.professions = {}
        local needy = recipient("Player-Z")
        needy.snapshot.professions = {}
        needy.inventory.bags.equipped[4] = 16
        assert(RQ.SuppliesService.SetNeed(2589, 10))
        assert(RQ.SuppliesService.SetNeed(2589, 20, "Player-Z"))
        local report = RQ.SuppliesService.Evaluate(RQDB, RQ.Database.activeId, 123456789)
        equal(#report.proposals, 2)
        equal(report.proposals[1].characterId, "Player-Z")
        equal(report.proposals[1].count, 15)
        equal(report.proposals[2].characterId, "Player-A")
        equal(report.proposals[2].count, 5)
        source.snapshot.sections.professions.complete = false
        report = RQ.SuppliesService.Evaluate(RQDB, RQ.Database.activeId, 123456789)
        equal(#report.proposals, 1)
        contains(report.warnings, "Refresh sender professions")
        source.snapshot.sections.professions.complete = true
        RQDB.roster["Player-A"].enabled = false
        report = RQ.SuppliesService.Evaluate(RQDB, RQ.Database.activeId, 123456789)
        equal(report.proposals[2].characterId, "Player-B")
        assert(RQ.Database.Register("ignore", "Player-B"))
        equal(#RQ.SuppliesService.Evaluate(RQDB, RQ.Database.activeId, 123456789).proposals, 1)
        equal(source.inventory.bags.items[2589], 30)
    end)

    test("orange recipe picker sets editable goals and refreshes groceries without typing IDs", function()
        local state, frames = start(true)
        assert(RQ.SuppliesService.ScanRecipes())
        _G.SlashCmdList.ROSTERQUARTERMASTER("supplies")
        frames.Click(frames.FindButton("Orange recipes"))
        equal(RQ.MainWindow.tab, "recipes")
        local edit = frames.FindKind("EditBox")
        equal(edit:GetText(), "145")
        edit:SetText("149")
        edit:SetFocus()
        RQ.MainWindow.Invalidate()
        h.flushTimers()
        equal(edit:GetText(), "149")
        frames.Click(frames.FindButton("Set goal"))
        equal(RQ.Database.Current().supplies.goals[197].recipeId, 100)
        equal(RQCharDB.supplies.goals[197].targetSkill, 149)
        equal(RQ.SuppliesService.Grocery(RQ.Database.Current())[2589].target, 54)
        equal(RQ.SuppliesService.Grocery(RQ.Database.Current())[2589].missing, 24)
        state.difficulty = 1
        assert(RQ.SuppliesService.ScanRecipes())
        frames.Click(frames.FindButton("Set goal"))
        contains(h.messages(), "Recipe no longer eligible")
        equal(RQCharDB.supplies.goals[197].targetSkill, 149)
        h.flushTimers()
        frames.Click(frames.FindButton("Grocery list"))
        equal(RQ.MainWindow.tab, "bags")
        local _, notes = RQ.SuppliesService.Grocery(RQ.Database.Current())
        contains(notes, "YELLOW")
        local reloadedFrames = assert(loadfile("Tests/fixtures/Frames.lua"))()()
        h.loadAddon()
        reloadedFrames.Emit("PLAYER_LOGIN")
        equal(RQ.Database.Current().recipes.professions[197].recipes[100].difficulty, 1)
        equal(RQ.Database.Current().supplies.goals[197].targetSkill, 149)
    end)

    test("orange goals reject stale unknown unlearned and unusable evidence and invalid targets", function()
        local state = start()
        assert(RQ.SuppliesService.ScanRecipes())
        local record = RQ.Database.Current()
        for _, target in ipairs({ 0, 140, 151, 145.5 }) do
            equal(RQ.SuppliesService.SetOrangeGoal(197, 100, target), false)
        end
        equal(RQ.SuppliesService.SetOrangeGoal(197, 101, 145), false)
        equal(RQ.SuppliesService.SetOrangeGoal(197, 100, nil), false)
        for _, difficulty in ipairs({ 1, 2, 3, 4, "orange" }) do
            state.difficulty = difficulty
            assert(RQ.SuppliesService.ScanRecipes())
            equal(RQ.SuppliesService.SetOrangeGoal(197, 100, 145), false)
        end
        state.difficulty = nil
        assert(RQ.SuppliesService.ScanRecipes())
        equal(record.recipes.professions[197].recipes[100].difficulty, nil)
        state.difficulty = 0
        assert(RQ.SuppliesService.ScanRecipes())
        local recipe = record.recipes.professions[197].recipes[100]
        recipe.reagentsComplete = false
        equal(RQ.SuppliesService.SetOrangeGoal(197, 100, 145), false)
        recipe.reagentsComplete = true
        recipe.skillUps = 0
        equal(RQ.SuppliesService.SetOrangeGoal(197, 100, 145), false)
        recipe.skillUps = 1
        record.recipes.professions[197].scannedAt = 1
        equal(RQ.SuppliesService.SetOrangeGoal(197, 100, 145), false)
        local cards = RQ.SuppliesService.RecipeCards(RQDB, RQ.Database.activeId, 123456789)
        equal(cards[1].title, "No eligible orange recipes")
        assert(RQ.SuppliesService.ScanRecipes())
        record.snapshot.sections.professions.complete = false
        equal(RQ.SuppliesService.SetOrangeGoal(197, 100, 145), false)
        record.snapshot.sections.professions.complete = true
        assert(RQ.SuppliesService.SetOrangeGoal(197, 100, 145))
        local invalid = RQ.Util.Copy(record.recipes)
        invalid.professions[197].recipes[100].difficulty = 4
        equal(RQ.Database.SaveLogistics(RQ.Database.activeId, "recipes", invalid), false)
        local inventory = RQ.Util.Copy(record.inventory)
        inventory.bags.details[2589].bindType = "BoE"
        equal(RQ.Database.SaveLogistics(RQ.Database.activeId, "inventory", inventory), false)
    end)

    test("copy reports work even when optional roster UI modules are missing", function()
        local _, frames = start(true)
        RQ.CharacterCard, RQ.RosterPanel, RQ.TodayPanel = nil, nil, nil
        assert(RQ.Diagnostics.Copy())
        contains({ frames.FindKind("EditBox"):GetText() }, "ACCOUNT ROSTER")
        contains({ frames.FindKind("EditBox"):GetText() }, "12000/40000")
    end)

    test("guild member catalogs and incomplete skill-up evidence remain explicit", function()
        start()
        _G.C_TradeSkillUI.IsTradeSkillGuildMember = function()
            return true
        end
        equal(RQ.Api.GetProfessionRecipes(), nil)
        equal(next(RQ.Database.Current().recipes.professions), nil)
        _G.C_TradeSkillUI.IsTradeSkillGuildMember = function()
            return false
        end
        assert(RQ.SuppliesService.ScanRecipes())
        assert(RQ.SuppliesService.SetGoal(197, 100, 225))
        local record = RQ.Database.Current()
        record.snapshot.sections.professions.complete = false
        local _, notes = RQ.SuppliesService.Grocery(record, 123456789, 48)
        contains(notes, "incomplete")
        contains(notes, "train/unlock")
        contains(notes, "skill-ups are not guaranteed")
        record.recipes.professions[197].recipes[100].skillUps = 0
        local grocery
        grocery, notes = RQ.SuppliesService.Grocery(record)
        equal(next(grocery), nil)
        contains(notes, "no skill-up")
    end)

    test("spare bags and already learned recipes are not mailed unnecessarily", function()
        start()
        assert(RQ.SuppliesService.ScanRecipes())
        local other = recipient("Player-A")
        other.inventory.bags.items[4496] = 1
        other.inventory.bags.details[4496] = { classId = 1, subclassId = 0 }
        other.recipes.professions[197].recipes[101].learned = true
        local report = RQ.SuppliesService.Evaluate(RQDB, RQ.Database.activeId, 123456789)
        equal(#report.proposals, 1)
        equal(report.proposals[1].itemId, 2589)
        equal(report.proposals[1].count, 7)
        other.inventory.bags.items[4496] = 0
        RQ.Database.Current().inventory.bags.equipped = { [1] = 0, [2] = 0 }
        report = RQ.SuppliesService.Evaluate(RQDB, RQ.Database.activeId, 123456789)
        equal(#report.proposals, 1)
        equal(report.proposals[1].itemId, 2589)
    end)

    test(
        "acquisition links require one identified recipe item rather than guessing currencies or alternatives",
        function()
            start()
            _G.C_TradeSkillUI.GetRecipeSourceText = function()
                return "Cost: |Hitem:2589|h[Linen]|h"
            end
            assert(RQ.SuppliesService.ScanRecipes())
            equal(RQ.Database.Current().recipes.professions[197].recipes[101].sourceItem, nil)
            _G.C_Item.GetItemInfoInstant = function(id)
                return id, "", "", "", 0, 9, 0
            end
            _G.C_TradeSkillUI.GetRecipeSourceText = function()
                return "|Hitem:6789|h[First]|h or |Hitem:9999|h[Second]|h"
            end
            assert(RQ.SuppliesService.ScanRecipes())
            equal(RQ.Database.Current().recipes.professions[197].recipes[101].sourceItem, nil)
            _G.C_TradeSkillUI.GetAllRecipeIDs = function()
                return { [2] = 100 }
            end
            assert(RQ.SuppliesService.ScanRecipes())
            equal(RQ.Database.Current().recipes.professions[197].recipes[100].learned, true)
            contains({ RQ.Database.Current().recipes.error }, "Recipe list unavailable")
        end
    )

    test("invalid runtime inventory updates fail without partially changing saved state", function()
        start()
        local previous = RQ.Database.Current().inventory
        local ok, err = RQ.Database.SaveLogistics(RQ.Database.activeId, "inventory", false)
        equal(ok, false)
        contains({ err }, "Invalid inventory")
        equal(RQ.Database.Current().inventory, previous)
        ok = RQ.Database.SaveLogistics(RQ.Database.activeId, "inventory", { bags = previous.bags })
        equal(ok, false)
        equal(RQ.Database.Current().inventory, previous)
    end)

    local function lockboxes()
        local state = start()
        state.items = {}
        _G.LOCKED = "Verriegelt"
        _G.C_TooltipInfo = {
            GetBagItem = function(bag, slot)
                local item = bag == 0 and state.items[slot]
                return item
                    and {
                        lines = {
                            { leftText = item.itemName },
                            { leftText = item.needsUnlocking and ("|cffff0000" .. _G.LOCKED .. "|r") or "Unlocked" },
                        },
                    }
            end,
        }
        return state
    end
    local function box(id, needsUnlocking, busy, bound)
        return {
            itemID = id,
            itemName = "Container " .. id,
            stackCount = 1,
            isBound = bound == true,
            isLocked = busy == true,
            needsUnlocking = needsUnlocking,
        }
    end

    test("lockbox scan distinguishes localized per-instance locks from busy stacks and names", function()
        local state = lockboxes()
        state.items = {
            box(4632, true),
            box(4632, false),
            box(4632, true, true),
            box(4632, true, false, true),
            box(1000, false),
        }
        state.items[5].itemName = "Verriegelt"
        assert(RQ.SuppliesService.ScanBags())
        local bags = RQ.Database.Current().inventory.bags
        equal(bags.items[4632], 4)
        equal(bags.tradable[4632], 2)
        equal(bags.lockedContainers[4632], 1)
        equal(bags.lockedContainers[1000], nil)
        equal(RQCharDB.inventory.bags.lockedContainers[4632], 1)
        _G.C_TooltipInfo.GetBagItem = nil
        assert(RQ.SuppliesService.ScanBags())
        equal(next(RQ.Database.Current().inventory.bags.lockedContainers), nil)
        contains({ RQ.Api.GetCapabilities().lockedContainerTooltip }, "missing")
    end)

    test("missing restricted or misleading lock tooltip data never invents locked stock", function()
        local state = lockboxes()
        state.items = { box(4632, true) }
        _G.LOCKED = nil
        assert(RQ.SuppliesService.ScanBags())
        equal(next(RQ.Database.Current().inventory.bags.lockedContainers), nil)
        contains({ RQ.Api.GetCapabilities().lockedContainerTooltip }, "label missing")
        _G.ITEM_LOCKED = "Closed"
        _G.C_TooltipInfo.GetBagItem = function()
            return { lines = { { leftText = "Box" }, { leftText = "Closed" } } }
        end
        assert(RQ.SuppliesService.ScanBags())
        equal(RQ.Database.Current().inventory.bags.lockedContainers[4632], 1)
        _G.issecretvalue = function(value)
            return value == "Closed"
        end
        assert(RQ.SuppliesService.ScanBags())
        equal(next(RQ.Database.Current().inventory.bags.lockedContainers), nil)
    end)

    test("locked surplus routes once to an enabled same-realm observed Rogue without profession scans", function()
        local state = lockboxes()
        state.items = { box(4632, true), box(4632, true), box(4632, false) }
        local source = RQ.Database.Current()
        source.snapshot.sections.professions.complete = false
        local foreign = recipient("Player-A")
        foreign.identity.class, foreign.identity.realm = "ROGUE", "OtherRealm"
        local unknown = recipient("Player-B")
        unknown.identity.class, unknown.identity.realm = "ROGUE", nil
        local rogue = recipient("Player-C")
        rogue.identity.class = "ROGUE"
        local second = recipient("Player-D")
        second.identity.class = "ROGUE"
        assert(RQ.SuppliesService.ScanBags())
        local report = RQ.SuppliesService.Evaluate(RQDB, RQ.Database.activeId, 123456789)
        equal(#report.proposals, 1)
        equal(report.proposals[1].characterId, "Player-C")
        equal(report.proposals[1].count, 2)
        equal(report.proposals[1].unlocking, 2)
        contains({ report.proposals[1].reason }, "verify Lockpicking")
        assert(RQ.Database.Register("ignore", "Player-C"))
        equal(RQ.SuppliesService.Evaluate(RQDB, RQ.Database.activeId, 123456789).proposals[1].characterId, "Player-D")
        RQDB.roster["Player-D"].enabled = false
        equal(#RQ.SuppliesService.Evaluate(RQDB, RQ.Database.activeId, 123456789).proposals, 0)
        RQDB.roster["Player-D"].enabled = true
        source.identity.class = "ROGUE"
        equal(#RQ.SuppliesService.Evaluate(RQDB, RQ.Database.activeId, 123456789).proposals, 0)
        source.identity.class = nil
        equal(#RQ.SuppliesService.Evaluate(RQDB, RQ.Database.activeId, 123456789).proposals, 0)
    end)

    test(
        "lockbox routing preserves sender reservations and earlier explicit allocations without mutating input",
        function()
            local state = lockboxes()
            state.items = { box(4632, true), box(4632, true), box(4632, true), box(4632, true) }
            local rogue = recipient("Player-Rogue")
            rogue.identity.class = "ROGUE"
            recipient("Player-Needy")
            assert(RQ.SuppliesService.ScanBags())
            assert(RQ.SuppliesService.SetNeed(4632, 1))
            assert(RQ.SuppliesService.SetNeed(4632, 1, "Player-Needy"))
            local report = RQ.SuppliesService.Evaluate(RQDB, RQ.Database.activeId, 123456789)
            equal(#report.proposals, 2)
            equal(report.proposals[1].characterId, "Player-Needy")
            equal(report.proposals[1].count, 1)
            equal(report.proposals[2].characterId, "Player-Rogue")
            equal(report.proposals[2].count, 2)
            equal(RQ.Database.Current().inventory.bags.lockedContainers[4632], 4)
            equal(RQ.SuppliesService.Evaluate(RQDB, RQ.Database.activeId, 123456789).proposals[2].count, 2)
        end
    )

    test("Scroll prefix surplus goes once to an eligible Mage without profession scans or bouncing", function()
        local state = start()
        state.items = {
            { itemID = 901, stackCount = 4, itemName = "Scroll: Test", isBound = false, isLocked = false },
            { itemID = 902, stackCount = 1, itemName = "Scroll of Test", isBound = false, isLocked = false },
            { itemID = 903, stackCount = 1, itemName = "Not Scroll: Test", isBound = false, isLocked = false },
            { itemID = 904, stackCount = 1, itemName = "Scroll: Bound", isBound = true, isLocked = false },
            { itemID = 905, stackCount = 1, itemName = "Scroll: Busy", isBound = false, isLocked = true },
        }
        local source = RQ.Database.Current()
        source.identity.class = "WARRIOR"
        source.snapshot.sections.professions.complete = false
        local foreign = recipient("Player-A")
        foreign.identity.class, foreign.identity.realm = "MAGE", "OtherRealm"
        local unknown = recipient("Player-B")
        unknown.identity.class, unknown.identity.realm = "MAGE", nil
        recipient("Player-C").identity.class = "MAGE"
        recipient("Player-D").identity.class = "MAGE"
        assert(RQ.SuppliesService.ScanBags())
        local function report()
            return RQ.SuppliesService.Evaluate(RQDB, RQ.Database.activeId, 123456789)
        end
        equal(#report().proposals, 1)
        equal(report().proposals[1].characterId, "Player-C")
        equal(report().proposals[1].itemId, 901)
        equal(report().proposals[1].count, 4)
        contains({ report().proposals[1].reason }, "Mage routing")
        RQDB.roster["Player-C"].enabled = false
        equal(report().proposals[1].characterId, "Player-D")
        assert(RQ.Database.Register("ignore", "Player-D"))
        equal(#report().proposals, 0)
        RQDB.roster["Player-C"].enabled = true
        source.identity.class = "MAGE"
        equal(#report().proposals, 0)
        source.identity.class = nil
        equal(#report().proposals, 0)
    end)

    test("Light Feathers route by ID to the first eligible Mage without bouncing or unsafe stock", function()
        local state = start()
        state.items = {
            { itemID = 17056, stackCount = 6, itemName = "Localized feather", isBound = false, isLocked = false },
            { itemID = 17056, stackCount = 2, isBound = true, isLocked = false },
            { itemID = 17056, stackCount = 3, isBound = false, isLocked = true },
            { itemID = 17056, stackCount = 4, isLocked = false },
            { itemID = 901, stackCount = 1, itemName = "Light Feather", isBound = false, isLocked = false },
        }
        local source = RQ.Database.Current()
        source.identity.class = "WARRIOR"
        source.snapshot.sections.professions.complete = false
        local foreign = recipient("Player-A")
        foreign.identity.class, foreign.identity.realm = "MAGE", "OtherRealm"
        recipient("Player-B").identity.class = "MAGE"
        recipient("Player-C").identity.class = "MAGE"
        assert(RQ.SuppliesService.ScanBags())
        source.inventory.bags.details[17056] = nil
        local function report()
            return RQ.SuppliesService.Evaluate(RQDB, RQ.Database.activeId, 123456789)
        end
        equal(#report().proposals, 1)
        equal(report().proposals[1].characterId, "Player-B")
        equal(report().proposals[1].itemId, 17056)
        equal(report().proposals[1].count, 6)
        contains({ report().proposals[1].reason }, "Mage routing: Light Feather")
        RQDB.roster["Player-B"].enabled = false
        equal(report().proposals[1].characterId, "Player-C")
        assert(RQ.Database.Register("ignore", "Player-C"))
        equal(#report().proposals, 0)
        RQDB.roster["Player-B"].enabled = true
        source.identity.class = "MAGE"
        equal(#report().proposals, 0)
    end)

    test("Light Feather routing preserves reserves needs and explicit item routes", function()
        local state = start()
        state.items = {
            { itemID = 17056, stackCount = 6, isBound = false, isLocked = false },
        }
        RQ.Database.Current().identity.class = "WARRIOR"
        recipient("Player-Mage").identity.class = "MAGE"
        recipient("Player-Needy")
        assert(RQ.SuppliesService.ScanBags())
        assert(RQ.SuppliesService.SetNeed(17056, 2))
        assert(RQ.SuppliesService.SetNeed(17056, 1, "Player-Needy"))
        local report = RQ.SuppliesService.Evaluate(RQDB, RQ.Database.activeId, 123456789)
        equal(#report.proposals, 2)
        equal(report.proposals[1].characterId, "Player-Needy")
        equal(report.proposals[1].count, 1)
        equal(report.proposals[2].characterId, "Player-Mage")
        equal(report.proposals[2].count, 3)
        equal(RQ.Database.Current().inventory.bags.items[17056], 6)
        local policy = RQ.Util.Copy(RQDB.settings.logistics)
        policy.categories.herbs.items[17056] = true
        policy.categories.herbs.recipients = { "Player-Needy" }
        assert(RQ.Database.SetLogisticsPolicies(policy))
        report = RQ.SuppliesService.Evaluate(RQDB, RQ.Database.activeId, 123456789)
        equal(#report.proposals, 1)
        equal(report.proposals[1].characterId, "Player-Needy")
        equal(report.proposals[1].count, 1)
    end)

    test("Scroll routing preserves reservations explicit needs and item-ID policy precedence", function()
        local state = start()
        state.items = {
            { itemID = 901, stackCount = 6, itemName = "Scroll: Test", isBound = false, isLocked = false },
        }
        RQ.Database.Current().identity.class = "WARRIOR"
        recipient("Player-Mage").identity.class = "MAGE"
        recipient("Player-Needy")
        assert(RQ.SuppliesService.ScanBags())
        assert(RQ.SuppliesService.SetNeed(901, 2))
        assert(RQ.SuppliesService.SetNeed(901, 1, "Player-Needy"))
        local report = RQ.SuppliesService.Evaluate(RQDB, RQ.Database.activeId, 123456789)
        equal(#report.proposals, 2)
        equal(report.proposals[1].characterId, "Player-Needy")
        equal(report.proposals[1].count, 1)
        equal(report.proposals[2].characterId, "Player-Mage")
        equal(report.proposals[2].count, 3)
        equal(RQ.Database.Current().inventory.bags.items[901], 6)
        local policy = RQ.Util.Copy(RQDB.settings.logistics)
        policy.categories.herbs.items[901] = true
        policy.categories.herbs.recipients = { "Player-Needy" }
        assert(RQ.Database.SetLogisticsPolicies(policy))
        report = RQ.SuppliesService.Evaluate(RQDB, RQ.Database.activeId, 123456789)
        equal(#report.proposals, 1)
        equal(report.proposals[1].characterId, "Player-Needy")
        equal(report.proposals[1].count, 1)
    end)

    test("schema eight adds unknown lock counts idempotently and rejects impossible eligible counts", function()
        local state = lockboxes()
        state.items = { box(4632, true) }
        assert(RQ.SuppliesService.ScanBags())
        local old = RQ.Util.Copy(RQDB)
        old.schemaVersion = 7
        old.characters["Player-Test-1"].inventory.bags.lockedContainers = nil
        local account, character = RQ.Migrations.Prepare(old, RQCharDB)
        equal(account.schemaVersion, 19)
        equal(next(account.characters["Player-Test-1"].inventory.bags.lockedContainers), nil)
        equal(old.characters["Player-Test-1"].inventory.bags.lockedContainers, nil)
        equal(account.plannedRoster, nil)
        local again = RQ.Migrations.Prepare(account, character)
        equal(next(again.characters["Player-Test-1"].inventory.bags.lockedContainers), nil)
        for _, invalid in ipairs({ { [4632] = -1 }, { [4632] = 2 }, { [4632] = "all" }, false }) do
            account.characters["Player-Test-1"].inventory.bags.lockedContainers = invalid
            local migrated, _, err = RQ.Migrations.Prepare(account, character)
            equal(migrated, nil)
            contains({ err:lower() }, "locked")
        end
    end)

    test("schema five supplies migration preserves old state and rejects malformed consumed records", function()
        start()
        local old = RQ.Util.Copy(RQDB)
        old.schemaVersion = 4
        old.characters["Player-Test-1"].supplies = nil
        local account, character = RQ.Migrations.Prepare(old, RQCharDB)
        equal(account.schemaVersion, 19)
        equal(character.schemaVersion, 19)
        equal(old.characters["Player-Test-1"].supplies, nil)
        for _, corrupt in ipairs({
            function(r)
                r.supplies.needs[2589] = -1
            end,
            function(r)
                r.inventory.bags.tradable[2589] = "all"
            end,
            function(r)
                r.supplies.goals[197] = { recipeId = 0, targetSkill = 150 }
            end,
            function(r)
                r.recipes.professions[197] = {}
            end,
        }) do
            local input = RQ.Util.Copy(account)
            corrupt(input.characters["Player-Test-1"])
            local migrated, _, err = RQ.Migrations.Prepare(input, character)
            equal(migrated, nil)
            assert(err)
            equal(input.schemaVersion, 19)
        end
    end)
end
