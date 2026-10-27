return function(h)
    local test, equal, contains = h.test, h.equal, h.contains
    local now = 123456789
    local function start(native)
        h.fakeCharacter()
        local frames = native and assert(loadfile("Tests/fixtures/Frames.lua"))()()
        h.loadAddon()
        if frames then
            frames.Emit("PLAYER_LOGIN")
        else
            h.emit("PLAYER_LOGIN")
        end
        return frames
    end
    local function member(id, realm)
        local record = RQ.Util.Copy(RQ.Database.Current())
        record.identity =
            { ruleset = "PVE", faction = "Horde", guid = id, displayName = "Quick", fullName = id, realm = realm }
        record.registration = "pending"
        record.inventory.bags =
            { items = {}, details = {}, equipped = {}, tradable = {}, scannedAt = now, complete = true }
        record.snapshot.professions = {}
        record.recipes.professions = {}
        record.supplies = { needs = {}, goals = {} }
        RQDB.characters[id] = record
        assert(RQ.Database.Register("add", id))
        return record
    end
    local function snapshot(skill, cap, level)
        return {
            level = level or 21,
            professions = {
                [197] = { name = "Tailoring", skill = skill or 81, maxSkill = cap or 150 },
            },
            sections = {
                progression = { complete = true, observedAt = now },
                professions = { complete = true, observedAt = now },
            },
        }
    end
    local function assess(saved, settings, at)
        return RQ.ProfessionStatus.Evaluate(saved, at or now, 48, settings or RQDB.settings.professionLag)
    end

    test("new installations start with no members and registration is explicit and idempotent", function()
        start()
        equal(RQDB.plannedRoster, nil)
        equal(next(RQDB.roster), nil)
        equal(RQ.Database.Current().registration, "pending")
        equal(#RQ.RosterPanel.Build(RQDB, RQ.Database.activeId, now).cards, 0)
        assert(RQ.Database.Register("add"))
        assert(RQ.Database.Register("add"))
        equal(#RQ.Util.Keys(RQDB.roster), 1)
        equal(RQ.Database.Current().registration, "member")
        local account, character = RQ.Migrations.Prepare(RQDB, RQCharDB)
        equal(account.plannedRoster, nil)
        equal(account.schemaVersion, 19)
        equal(character.schemaVersion, 19)
    end)

    test("ignore and resume preserve snapshots goals and roles but require explicit main selection", function()
        start()
        assert(RQ.Database.Register("add"))
        assert(RQ.Database.SetMain(RQ.Database.activeId))
        assert(RQ.Database.SetRole(RQ.Database.activeId, "TANK"))
        local current = RQ.Database.Current()
        current.supplies.needs[2770] = 20
        local before = current.snapshot
        local entry = RQDB.roster[RQ.Database.activeId]
        equal(entry.role, "TANK")
        equal(entry.isMain, true)
        equal(current.snapshot, before)
        equal(current.supplies.needs[2770], 20)
        assert(RQ.Database.Register("ignore"))
        equal(entry.enabled, false)
        equal(entry.isMain, false)
        equal(current.supplies.needs[2770], 20)
        assert(RQ.Database.Register("add"))
        equal(entry.enabled, true)
        equal(entry.role, "TANK")
        equal(entry.isMain, false)
        assert(RQ.Database.SetMain(RQ.Database.activeId))
        equal(entry.isMain, true)
        equal(current.snapshot, before)
        assert(RQ.Migrations.Prepare(RQDB, RQCharDB))
    end)

    test("same-name members remain independently configurable by GUID", function()
        start()
        local first = member("Player-First", "TestRealm PVE")
        local second = member("Player-Second", "TestRealm PVE")
        first.identity.fullName, second.identity.fullName = "Same", "Same"
        assert(RQ.Database.SetRole("Player-First", "HEALER"))
        assert(RQ.Database.SetRole("Player-Second", "DPS"))
        assert(RQ.Database.SetMain("Player-Second"))
        assert(RQ.Database.Register("ignore", "Player-First"))
        equal(first.registration, "ignored")
        equal(second.registration, "member")
        equal(RQDB.roster["Player-First"].role, "HEALER")
        equal(RQDB.roster["Player-Second"].role, "DPS")
        equal(RQDB.roster["Player-Second"].isMain, true)
        equal(RQ.Database.SetRole("missing", "TANK"), false)
    end)

    test("schema seven preserves schema six choices and rejects invalid benchmark metadata transactionally", function()
        start()
        assert(RQ.Database.Register("add"))
        assert(RQ.Database.SetMain(RQ.Database.activeId))
        assert(RQ.Database.SetRole(RQ.Database.activeId, "TANK"))
        RQDB.schemaVersion, RQCharDB.schemaVersion = 6, 6
        RQDB.settings.professionLag = nil
        RQDB.characters[RQ.Database.activeId].snapshot.professions[186].kind = nil
        local account, character = RQ.Migrations.Prepare(RQDB, RQCharDB)
        equal(account.settings.professionLag.ceiling, 300)
        equal(account.roster[RQ.Database.activeId].isMain, true)
        equal(account.characters[RQ.Database.activeId].snapshot.professions[186].kind, nil)
        equal(RQDB.settings.professionLag, nil)
        local second = RQ.Migrations.Prepare(account, character)
        equal(second.roster[RQ.Database.activeId].role, "TANK")
        for _, invalid in ipairs({
            false,
            { ceiling = 0 },
            { ceiling = 1.5 },
            { ceilings = { [197] = -1 } },
            { secondary = { [185] = "yes" } },
        }) do
            local input = RQ.Util.Copy(account)
            input.settings.professionLag = invalid
            local bad, char, err = RQ.Migrations.Prepare(input, character)
            equal(bad, nil)
            equal(char, nil)
            assert(err)
            equal(input.settings.professionLag, invalid)
        end
        account.characters[RQ.Database.activeId].snapshot.professions[186].kind = "made-up"
        equal(RQ.Migrations.Prepare(account, character), nil)
    end)

    test("zero one five six twenty and fifty members render without caps or repeated widget growth", function()
        local frames = start(true)
        RQ.MainWindow.realm, RQ.MainWindow.group = "all", "all"
        local template = RQ.Util.Copy(RQ.Database.Current())
        for _, count in ipairs({ 0, 1, 5, 6, 20, 50 }) do
            RQDB.characters, RQDB.roster = {}, {}
            for index = 1, count do
                local id = "Player-" .. index
                local record = RQ.Util.Copy(template)
                record.identity.guid = id
                record.registration = "pending"
                RQDB.characters[id] = record
                assert(RQ.Database.Register("add", id))
            end
            local view = RQ.RosterPanel.Build(RQDB, nil, now)
            equal(#view.characterIds, count)
            equal(#view.cards, count)
            assert(RQ.MainWindow.Open("roster"))
            local widgets = #frames.widgets
            assert(RQ.MainWindow.Render())
            equal(#frames.widgets, widgets)
        end
        local view = RQ.RosterPanel.Build(RQDB, nil, now, "Player-40")
        equal(view.selectedId, "Player-40")
        local scroll = frames.FindKind("ScrollFrame")
        assert(scroll.scrollChild:GetHeight() > scroll:GetHeight())
    end)

    test("large dynamic rosters retain pending registration without listing every member in the popup", function()
        local frames = start(true)
        for index = 1, 50 do
            member("Player-Member-" .. index, "TestRealm PVE")
        end
        local view = RQ.RosterPanel.Build(RQDB, RQ.Database.activeId, now)
        equal(#view.cards, 50)
        equal(#view.characterIds, 51)
        RQ.RegistrationPrompt.Show(true)
        frames.Click(frames.FindButton("Add as new roster member"))
        h.flushTimers()
        equal(RQ.Database.Current().registration, "member")
        equal(#RQ.RosterPanel.Build(RQDB, RQ.Database.activeId, now).cards, 51)
    end)

    test("manage controls register members and configure the benchmark ceiling", function()
        local frames = start(true)
        assert(RQ.MainWindow.Open("manage"))
        frames.Click(frames.FindButton("Add / resume"))
        h.flushTimers()
        equal(RQ.Database.Current().registration, "member")
        local edit = frames.FindKind("EditBox")
        edit:SetText("225")
        frames.Click(frames.FindButton("Save ceiling"))
        h.flushTimers()
        equal(RQDB.settings.professionLag.ceiling, 225)
    end)

    test("profession lag boundaries trained caps and configured ceilings are distinct from goals", function()
        start()
        for _, row in ipairs({ { 104, "BEHIND", 1 }, { 105, "ON_TRACK", 0 }, { 106, "ON_TRACK", 0 } }) do
            local value = assess(snapshot(row[1])).professions[1]
            equal(value.benchmark, 105)
            equal(value.state, row[2])
            equal(value.deficit, row[3])
        end
        local value = assess(snapshot(75, 75)).professions[1]
        equal(value.deficit, 30)
        equal(value.needsTraining, true)
        contains({ RQ.ProfessionStatus.Describe(value) }, "train next rank")
        equal(assess(snapshot()).professions[1].deficit, 24)
        equal(assess(snapshot(300, 300, 60)).professions[1].state, "ON_TRACK")
        local settings = RQ.Util.Copy(RQDB.settings.professionLag)
        settings.ceilings[197] = 100
        equal(assess(snapshot(100), settings).professions[1].state, "ON_TRACK")
        equal(assess(snapshot(100, 150, 25)).professions[1].benchmark, 125)
        RQ.Database.Current().supplies.goals[197] = { recipeId = 100, targetSkill = 150 }
        assess(snapshot(100, 150, 25))
        equal(RQ.Database.Current().supplies.goals[197].targetSkill, 150)
    end)

    test("unknown stale and secondary professions never become fabricated zero-skill deficits", function()
        start()
        local saved = snapshot()
        saved.sections.professions.complete = false
        equal(assess(saved).professions[1].state, "UNKNOWN")
        equal(assess(saved).freePrimarySlots, nil)
        saved.sections.professions.complete = true
        saved.sections.progression.observedAt = now - 48 * 3600
        equal(assess(saved).professions[1].state, "STALE")
        equal(assess(saved).professions[1].deficit, nil)
        saved.sections.progression.observedAt = now
        saved.level = nil
        equal(assess(saved).professions[1].state, "UNKNOWN")
        saved = snapshot()
        saved.professions[185] = { name = "Cooking", skill = 50, maxSkill = 75 }
        local result = assess(saved)
        equal(result.professions[1].state, "NOT_ASSESSED")
        equal(result.freePrimarySlots, 1)
        local config = RQ.Util.Copy(RQDB.settings.professionLag)
        config.secondary[185] = true
        equal(assess(saved, config).professions[1].deficit, 55)
        saved.professions = {}
        equal(assess(saved).freePrimarySlots, 2)
        saved.professions[999] = { name = "Unknown", skill = 50, maxSkill = 75 }
        equal(assess(saved).freePrimarySlots, nil)
        saved.professions[999].kind = "primary"
        equal(assess(saved).freePrimarySlots, 1)
    end)

    test("observed API classification survives capture and pure status never calls APIs", function()
        start()
        local saved = RQ.Database.Current().snapshot
        equal(saved.professions[186].kind, "primary")
        equal(saved.professions[185].kind, "secondary")
        RQ.Api.GetServerTime = function()
            error("pure status must not query the client")
        end
        local result = assess(saved)
        equal(result.primaryCount, 1)
        equal(saved.professions[186].skill, 100)
        equal(assess(saved).professions[2].state, result.professions[2].state)
    end)

    test("duplicate profession slots reject the scan instead of claiming a free primary slot", function()
        start()
        _G.GetProfessions = function()
            return 7, 7
        end
        equal(RQ.Api.GetProfessions(), nil)
        contains({ RQ.Api.GetCapabilities().GetProfessionInfo }, "invalid profession data")
    end)

    test("roster Today Supplies and diagnostics share status without changing recommendation scores", function()
        start()
        assert(RQ.Database.Register("add"))
        local current = RQ.Database.Current()
        current.snapshot = snapshot()
        local before = RQ.PlanningService.Evaluate()
        local expected = "Tailoring [197]: BEHIND by 24"
        local view = RQ.RosterPanel.Build(RQDB, RQ.Database.activeId, now)
        contains({ view.cards[1].body }, expected)
        contains({ RQ.TodayPanel.Build(RQDB, before)[1].body }, expected)
        contains(RQ.SuppliesService.Report(RQ.Database.activeId), expected)
        contains(RQ.Diagnostics.Roster(true), expected)
        local config = RQ.Util.Copy(RQDB.settings.professionLag)
        config.ceiling = 75
        assert(RQ.Database.SetProfessionConfig(config))
        equal(RQ.PlanningService.Evaluate().recommendations[1].score, before.recommendations[1].score)
    end)

    test("slash roster and secondary benchmark settings validate before saving", function()
        start()
        local slash = _G.SlashCmdList.ROSTERQUARTERMASTER
        slash("add")
        equal(RQ.Database.Current().registration, "member")
        slash("profession-track 185 on")
        slash("profession-cap 197 225")
        equal(RQDB.settings.professionLag.secondary[185], true)
        equal(RQDB.settings.professionLag.ceilings[197], 225)
        slash("profession-cap 197 -1")
        slash("profession-track 185 bad")
        equal(RQDB.settings.professionLag.ceilings[197], 225)
        equal(RQDB.settings.professionLag.secondary[185], true)
        slash("ignore")
        equal(RQ.Database.Current().registration, "ignored")
        equal(RQDB.settings.professionLag.ceilings[197], 225)
        contains(h.messages(), "Usage:")
    end)

    test("explicit groceries and surplus routing stay within a known normalized realm", function()
        start()
        assert(RQ.Database.Register("add"))
        local source = RQ.Database.Current()
        source.inventory.bags = {
            scannedAt = now,
            complete = true,
            equipped = {},
            items = { [2770] = 20 },
            tradable = { [2770] = 20 },
            details = { [2770] = { classId = 7, subclassId = 7 } },
        }
        local foreign = member("A-Foreign", "OtherRealm")
        foreign.supplies.needs[2770] = 20
        foreign.snapshot.professions[164] = { name = "Blacksmithing", skill = 100, maxSkill = 150 }
        local unknown = member("B-Unknown")
        unknown.supplies.needs[2770] = 20
        local localMember = member("C-Local", "Test Realm PVE")
        localMember.snapshot.professions[164] = { name = "Blacksmithing", skill = 100, maxSkill = 150 }
        localMember.supplies.needs[2770] = 5
        local report = RQ.SuppliesService.Evaluate(RQDB, RQ.Database.activeId, now)
        assert(#report.proposals > 0)
        local count = 0
        for _, proposal in ipairs(report.proposals) do
            equal(proposal.characterId, "C-Local")
            count = count + proposal.count
        end
        equal(count, 20)
        source.identity.realm = nil
        equal(#RQ.SuppliesService.Evaluate(RQDB, RQ.Database.activeId, now).proposals, 0)
        equal(RQ.Character.SameRealm({ realm = "-" }, { realm = " - " }), false)
        equal(#RQ.RosterPanel.Build(RQDB, nil, now).characterIds, 4)
    end)

    test("bag transfers and tailoring jobs do not cross realms but still allow local unknown-realm upgrades", function()
        start()
        assert(RQ.Database.Register("ignore"))
        local tailor = member("A-Tailor", "Realm A")
        tailor.inventory.bags.equipped = { 16 }
        tailor.inventory.bags.items[4240] = 1
        tailor.inventory.bags.tradable[4240] = 1
        tailor.inventory.bags.details[4240] = { classId = 1, subclassId = 0, bagSlots = 10 }
        tailor.snapshot.professions[197] = { name = "Tailoring", skill = 100, maxSkill = 150 }
        tailor.recipes.professions[197] = {
            name = "Tailoring",
            scannedAt = now,
            complete = true,
            recipes = {
                [100] = {
                    name = "Bag",
                    learned = true,
                    reagentsComplete = true,
                    skillUps = 1,
                    reagents = { [2589] = 6 },
                    outputItemId = 4245,
                    outputCount = 1,
                    outputBindType = 0,
                    bagSlots = 12,
                },
            },
        }
        member("B-Foreign", "Realm B").inventory.bags.equipped = { 4 }
        member("C-Local", "Realm A").inventory.bags.equipped = { 6, 8 }
        local plan = RQ.SuppliesService.Plan(RQDB, now)
        equal(#plan.bags.upgrades, 2)
        for _, upgrade in ipairs(plan.bags.upgrades) do
            equal(upgrade.characterId, "C-Local")
        end
        equal(plan.bags.crafts["A-Tailor"][100].crafts, 1)
        equal(plan.groceries["A-Tailor"][2589].target, 6)
        tailor.identity.realm = nil
        tailor.inventory.bags.equipped = { 4 }
        plan = RQ.SuppliesService.Plan(RQDB, now)
        equal(#plan.bags.upgrades, 1)
        equal(plan.bags.upgrades[1].kind, "equip")
        equal(plan.bags.upgrades[1].characterId, "A-Tailor")
    end)
end
