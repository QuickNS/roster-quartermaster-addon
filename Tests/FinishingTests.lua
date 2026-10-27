return function(h)
    local test, equal = h.test, h.equal
    local function start()
        h.fakeCharacter()
        h.loadAddon()
        h.emit("PLAYER_LOGIN")
        assert(RQ.SnapshotService.Register("add"))
    end
    test("profession lag ranking is explicitly gated defaults off and cannot override an equal-level Main", function()
        start()
        local baseline = RQ.PlanningService.Evaluate().recommendations[1].score
        equal(RQDB.settings.professionLag.rankingEnabled, false)
        _G.SlashCmdList.ROSTERQUARTERMASTER("profession-ranking on 10")
        local enabled = RQ.PlanningService.Evaluate().recommendations[1].score
        assert(math.abs(enabled - baseline - 2) < 0.000001)
        RQ.Database.Current().snapshot.sections.professions.complete = false
        equal(RQ.PlanningService.Evaluate().recommendations[1].score, baseline)
        _G.SlashCmdList.ROSTERQUARTERMASTER("profession-ranking off")
        equal(RQDB.settings.professionLag.rankingEnabled, false)
        _G.SlashCmdList.ROSTERQUARTERMASTER("profession-ranking on 101")
        equal(RQDB.settings.professionLag.rankingEnabled, false)
        local active = RQ.Database.activeId
        local other = RQ.Util.Copy(RQ.Database.Current())
        other.identity.guid = "Player-Lag"
        other.snapshot.sections.professions.complete = true
        other.snapshot.professions[186].skill = 0
        RQDB.characters["Player-Lag"] = other
        RQDB.roster["Player-Lag"] = RQ.Util.Copy(RQDB.roster[active])
        _G.SlashCmdList.ROSTERQUARTERMASTER("profession-ranking on 100")
        assert(RQ.Database.SetMain(active))
        equal(RQ.PlanningService.Evaluate().recommendations[1].characterId, active)
    end)
    test("fifty-member pure dashboard and priority refresh stays bounded", function()
        start()
        local record = RQ.Database.Current()
        for index = 1, 49 do
            local id = "Player-Perf-" .. index
            RQDB.characters[id] = RQ.Util.Copy(record)
            RQDB.characters[id].identity.guid = id
            RQDB.roster[id] = RQ.Util.Copy(RQDB.roster[RQ.Database.activeId])
            RQDB.roster[id].isMain = false
        end
        collectgarbage("collect")
        local begin = os.clock()
        for _ = 1, 10 do
            local report = RQ.PlanningService.Evaluate()
            equal(#report.recommendations, 50)
        end
        local elapsed = os.clock() - begin
        io.write(string.format("PERF 50-member priority: 10 refreshes %.4fs (budget 2s)\n", elapsed))
        assert(elapsed < 2, "50-member pure refresh benchmark exceeded 2 seconds for ten refreshes")
    end)
    test("fifty-member 500-recipe material planning stays within measured refresh budget", function()
        start()
        local now = 123456789
        local record = RQ.Database.Current()
        record.inventory.bags = {
            complete = true,
            scannedAt = now,
            equipped = { 20, 20, 20, 20 },
            items = {},
            tradable = {},
            details = {},
        }
        for index = 1, 49 do
            local id = "Player-Catalog-" .. index
            RQDB.characters[id] = RQ.Util.Copy(record)
            RQDB.characters[id].identity.guid = id
            RQDB.characters[id].inventory.bags.equipped = { 8, 8, 8, 8 }
            RQDB.roster[id] = RQ.Util.Copy(RQDB.roster[RQ.Database.activeId])
        end
        record.snapshot.professions[197] = { name = "Tailoring", skill = 100, maxSkill = 150 }
        record.recipes = {
            complete = true,
            scannedAt = now,
            items = {},
            professions = {
                [197] = { name = "Tailoring", complete = true, scannedAt = now, recipes = {} },
            },
        }
        for index = 1, 500 do
            record.recipes.professions[197].recipes[index] = {
                name = "Synthetic bag " .. index,
                learned = true,
                skillUps = 0,
                reagentsComplete = true,
                reagents = { [2589] = 6 },
                outputItemId = 900000 + index,
                outputCount = 1,
                bagSlots = 8 + index % 12,
                outputBindType = 0,
            }
        end
        local begin = os.clock()
        for _ = 1, 3 do
            local plan = RQ.SuppliesService.Plan(RQDB, now)
            equal(#plan.bags.upgrades, 196)
            equal(plan.bags.upgrades[1].to, 19)
        end
        local elapsed = os.clock() - begin
        io.write(string.format("PERF 50-member/500-recipe logistics: 3 refreshes %.4fs (budget 2s)\n", elapsed))
        assert(elapsed < 2, "material planning exceeded 2 seconds for three refreshes")
    end)
    test("retired feature commands cannot recreate settings tasks or modules", function()
        h.fakeCharacter()
        local frames = assert(loadfile("Tests/fixtures/Frames.lua"))()()
        h.loadAddon()
        frames.Emit("PLAYER_LOGIN")
        assert(RQ.SnapshotService.Register("add"))
        for _, command in ipairs({
            "progress dungeon trial 15 25 tank 70 early | Test Dungeon",
            "gear",
            "bag-space",
            "preset starter",
            "slot-add warrior",
            "link warrior",
            "slots",
        }) do
            _G.SlashCmdList.ROSTERQUARTERMASTER(command)
        end
        assert(RQ.MainWindow.Open("today"))
        for _, module in ipairs({
            "GearService",
            "GearAdvisor",
            "GearConfig",
            "BagSpaceService",
            "BagSpacePlanner",
            "ProgressService",
            "ProgressPlanner",
            "ProgressConfig",
            "DefaultRoster",
            "ActivityService",
            "ActivityView",
            "ChecklistPlanner",
            "ChecklistService",
            "GuideCatalog",
            "GuidePathPlanner",
            "ProfessionGuides",
        }) do
            equal(RQ[module], nil)
        end
        local migrated, mirrored = RQ.Migrations.Prepare(RQDB, RQCharDB)
        equal(migrated.progress, nil)
        equal(migrated.settings.gear, nil)
        equal(migrated.plannedRoster, nil)
        equal(mirrored.progress, nil)
    end)
    test("reserve and routing commands persist normalized config without activity lists", function()
        start()
        _G.SlashCmdList.ROSTERQUARTERMASTER("reserve bandages 2581 10")
        _G.SlashCmdList.ROSTERQUARTERMASTER("routing-item herbs 2447 on")
        assert(RQDB.settings.logistics.categories.herbs.items[2447], table.concat(h.messages(), "\n"))
        equal(RQ.Database.Current().supplies.reserves.bandages[2581], 10)
        equal(RQCharDB.supplies.reserves.bandages[2581], 10)
        local migrated = RQ.Migrations.Prepare(RQDB, RQCharDB)
        assert(migrated.settings.logistics.categories.herbs.items[2447])
    end)
    test(
        "native multiline import previews without applying and explicit confirm rollback preserve observations",
        function()
            h.fakeCharacter()
            local frames = assert(loadfile("Tests/fixtures/Frames.lua"))()()
            h.loadAddon()
            frames.Emit("PLAYER_LOGIN")
            assert(RQ.SnapshotService.Register("add"))
            local ok, err, encoded = RQ.ConfigTransferService.Command("export", "")
            assert(ok, err)
            assert(#encoded > 255)
            _G.SlashCmdList.ROSTERQUARTERMASTER("profession-ranking on 20")
            local token
            local preview = RQ.ConfigTransferService.Preview
            RQ.ConfigTransferService.Preview = function(text)
                local success, failure, value = preview(text)
                if success then
                    token = value
                end
                return success, failure, value
            end
            _G.SlashCmdList.ROSTERQUARTERMASTER("import")
            frames.FindKind("EditBox"):SetText(encoded)
            frames.Click(frames.FindButton("Preview import"))
            assert(token, table.concat(h.messages(), "\n"))
            equal(RQDB.settings.professionLag.rankingEnabled, true)
            _G.SlashCmdList.ROSTERQUARTERMASTER("import-confirm " .. token)
            equal(RQDB.settings.professionLag.rankingEnabled, false)
            _G.GetMoney = function()
                return 333
            end
            frames.Emit("PLAYER_MONEY")
            h.flushTimers()
            _G.SlashCmdList.ROSTERQUARTERMASTER("import-rollback")
            equal(RQDB.settings.professionLag.rankingEnabled, true)
            equal(RQ.Database.Current().snapshot.money, 333)
            frames.Emit("PLAYER_LOGOUT")
            equal(RQ.ConfigTransferService.Rollback(), false)
        end
    )
end
