return function(h)
    local test, equal, contains = h.test, h.equal, h.contains
    local function modern()
        local state = { skill = 140, linked = false, learned = false }
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
                return id, "type", "subtype", "", 0, id == 4496 and 1 or id == 6789 and 9 or 7, 0
            end,
        }
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
        assert(RQ.Database.Register("link", "warrior"))
        return state, frames
    end

    local function recipient(id)
        local record = RQ.Util.Copy(RQ.Database.Current())
        record.registration = "pending"
        record.identity = { guid = id, displayName = "Tombsie", fullName = "Miss Tombsie", realm = "TestRealm" }
        record.supplies = { needs = {}, goals = {} }
        record.inventory.bags.items = { [2589] = 5 }
        record.inventory.bags.tradable = {}
        record.inventory.bags.details = {}
        record.inventory.bags.equipped = { [1] = 16, [2] = 16, [3] = 16, [4] = 0 }
        RQDB.characters[id] = record
        assert(RQ.Database.Register("add", nil, id))
        return record
    end

    test("copy window exposes selectable diagnostics and roster without writing edited text", function()
        local _, frames = start(true)
        _G.SlashCmdList.ROSTERQUARTERMASTER("copy")
        local edit = frames.FindKind("EditBox")
        contains({ edit:GetText() }, "Schemas: account=5; character=5")
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
            return "Quick Slam", "TestRealm"
        end
        h.loadAddon()
        h.emit("PLAYER_LOGIN")
        assert(RQ.Database.Register("link", "warrior"))
        assert(RQ.Database.Pin("Player-Test-1"))
        equal(RQ.Database.Current().identity.displayName, "Quick Slam")
        equal(RQ.Database.ResolveMember("Quick Slam"), "Player-Test-1")
        local other = recipient("Player-Other")
        other.identity.displayName, other.identity.fullName = "Quick Death", nil
        equal(RQ.Database.ResolveMember("Quick Death"), "Player-Other")
        _G.UnitNameUnmodified = function()
            return "Quick Renamed"
        end
        assert(RQ.SnapshotService.Refresh())
        equal(RQDB.settings.planning.pinnedCharacterId, "Player-Test-1")
        equal(RQ.Database.Current().identity.displayName, "Quick Renamed")
        assert(RQ.Database.SetFullName("Quick Correctsurname"))
        assert(RQ.SnapshotService.Refresh())
        equal(RQ.Character.DisplayName(RQ.Database.Current().identity), "Quick Correctsurname")
        equal(RQ.Database.ResolveMember("Quick Correctsurname"), "Player-Test-1")
        equal(RQCharDB.identity.fullName, "Quick Correctsurname")
        equal(RQ.Database.SetFullName("|bad"), false)
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
        local previous = RQ.Database.Current().recipes
        h.emit("TRADE_SKILL_SHOW")
        h.emit("TRADE_SKILL_CLOSE")
        h.flushTimers()
        equal(RQ.Database.Current().recipes, previous)
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
        equal(next(grocery), nil)
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
        assert(RQ.Database.Register("ignore", nil, "Player-A"))
        equal(RQ.SuppliesService.Evaluate(RQDB, RQ.Database.activeId, 123456789).groceries["Player-A"], nil)
    end)

    test("supplies and recipes commands open copyable reports and never execute mail operations", function()
        local _, frames = start(true)
        assert(RQ.SuppliesService.ScanRecipes())
        recipient("Player-A")
        _G.SlashCmdList.ROSTERQUARTERMASTER("need 2589 20 Player-A")
        _G.SlashCmdList.ROSTERQUARTERMASTER("goal 197 100 150 Player-A")
        _G.SlashCmdList.ROSTERQUARTERMASTER("supplies")
        equal(RQ.MainWindow.tab, "supplies")
        frames.Click(frames.FindButton("View supplies"))
        contains({ frames.FindKind("EditBox"):GetText() }, "target")
        RQ.Api.HideCopyWindow()
        _G.SlashCmdList.ROSTERQUARTERMASTER("recipes Player-A")
        contains({ frames.FindKind("EditBox"):GetText() }, "[KNOWN]")
        RQ.Api.HideCopyWindow()
        _G.SlashCmdList.ROSTERQUARTERMASTER("mail")
        contains({ frames.FindKind("EditBox"):GetText() }, "nothing is attached")
        contains({ frames.FindKind("EditBox"):GetText() }, "Linen Cloth [2589]")
        frames.Emit("MAIL_SHOW")
        contains(h.messages(), "No items are attached or sent automatically")
        equal(RQ.SuppliesService.SetNeed(0, 10), false)
        equal(RQ.SuppliesService.SetGoal(197, 999, 150), false)
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
        equal(#report.proposals, 0)
        other.inventory.bags.items[4496] = 0
        RQ.Database.Current().inventory.bags.equipped = { [1] = 0, [2] = 0 }
        report = RQ.SuppliesService.Evaluate(RQDB, RQ.Database.activeId, 123456789)
        equal(#report.proposals, 0)
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

    test("schema five supplies migration preserves old state and rejects malformed consumed records", function()
        start()
        local old = RQ.Util.Copy(RQDB)
        old.schemaVersion = 4
        old.characters["Player-Test-1"].supplies = nil
        local account, character = RQ.Migrations.Prepare(old, RQCharDB)
        equal(account.schemaVersion, 5)
        equal(character.schemaVersion, 5)
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
            equal(input.schemaVersion, 5)
        end
    end)
end
