return function(h)
    local test, equal, contains = h.test, h.equal, h.contains
    local active, now = "Player-Test-1", 123456789
    local function setProfessions(record, ids)
        record.snapshot.professions = {}
        record.snapshot.sections.professions = { complete = true, observedAt = now, attemptedAt = now }
        for _, id in ipairs(ids) do
            record.snapshot.professions[id] = {
                name = RQ.ProfessionRelationships.professions[id] and RQ.ProfessionRelationships.professions[id].name
                    or "Other",
                skill = 1,
                maxSkill = 75,
            }
        end
    end
    local function start(native)
        h.fakeCharacter()
        local frames = native and assert(loadfile("Tests/fixtures/Frames.lua"))()()
        h.loadAddon()
        if frames then
            frames.Emit("PLAYER_LOGIN")
        else
            h.emit("PLAYER_LOGIN")
        end
        assert(RQ.Database.Register("add"))
        local record = RQ.Database.Current()
        setProfessions(record, {})
        record.inventory.bags =
            { items = {}, tradable = {}, details = {}, equipped = {}, complete = true, scannedAt = now }
        record.recipes.professions = {}
        record.supplies = { needs = {}, goals = {} }
        return record, frames
    end
    local function member(id, ids, realm)
        local record = RQ.Util.Copy(RQ.Database.Current())
        record.identity =
            { ruleset = "PVE", faction = "Horde", guid = id, fullName = id, realm = realm or "TestRealm PVE" }
        record.registration, record.professionIntent = "pending", RQ.ProfessionConfig.PrepareIntent(nil)
        setProfessions(record, ids or {})
        record.supplies = { needs = {}, goals = {} }
        RQDB.characters[id] = record
        assert(RQ.Database.Register("add", id))
        return record
    end
    local function evaluate(id)
        return RQ.ProfessionAdvisor.Evaluate(RQDB, id or active, now)
    end
    local function key(choice)
        return table.concat(choice.additions, ",")
    end
    local function reasons(choice)
        local lines = {}
        for _, factor in ipairs(choice.factors) do
            lines[#lines + 1] = factor.reason
        end
        return lines
    end

    test("profession advisor returns deterministic top three pairs for confirmed empty slots", function()
        start()
        local report = evaluate()
        equal(report.freeSlots, 2)
        equal(report.candidateCount, 36)
        equal(#report.choices, 3)
        for index, choice in ipairs(report.choices) do
            equal(#choice.additions, 2)
            assert(choice.additions[1] < choice.additions[2])
            equal(key(choice), key(evaluate().choices[index]))
            local total = 0
            for _, factor in ipairs(choice.factors) do
                total = total + factor.points
            end
            equal(choice.score, total)
        end
        equal(next(RQ.Database.Current().snapshot.professions), nil)
    end)

    test("profession advice distinguishes unknown stale and unsupported evidence from empty professions", function()
        local record = start()
        for _, corrupt in ipairs({
            function()
                record.snapshot.sections.professions.complete = false
            end,
            function()
                record.snapshot.sections.professions.observedAt = now - 48 * 3600
            end,
            function()
                record.snapshot.professions = nil
            end,
            function()
                record.snapshot.professions[999] = { name = "Unknown", skill = 1, maxSkill = 75 }
            end,
            function()
                setProfessions(record, { 164, 171, 197 })
            end,
            function()
                setProfessions(record, { 164 })
                record.snapshot.professions[164].kind = "secondary"
            end,
            function()
                setProfessions(record, { 164 })
                record.snapshot.professions[164].maxSkill = 0
            end,
        }) do
            setProfessions(record, {})
            corrupt()
            local report = evaluate()
            equal(#report.choices, 0)
            equal(report.freeSlots, nil)
            contains({ report.blocker }, "Rescan")
        end
    end)

    test("one learned primary permits only additions and two learned primaries remain locked", function()
        local record = start()
        setProfessions(record, { 186, 129, 185, 356 })
        local report = evaluate()
        equal(report.freeSlots, 1)
        equal(report.candidateCount, 8)
        for _, choice in ipairs(report.choices) do
            equal(#choice.additions, 1)
            assert(choice.professions[186])
            assert(choice.additions[1] ~= 186)
        end
        setProfessions(record, { 186, 164 })
        equal(evaluate().freeSlots, 0)
        equal(#evaluate().choices, 0)
        equal(RQ.ProfessionAdviceService.Plan(active, { 171 }), false)
        assert(record.snapshot.professions[164])
    end)

    test("coverage scopes enabled registered members by realm and excludes provisional intent", function()
        start()
        local known = member("Known", { 171 })
        local stale = member("Stale", { 197 })
        stale.snapshot.sections.professions.observedAt = now - 48 * 3600
        member("OtherRealm", { 164 }, "OtherRealm")
        member("Disabled", { 202 })
        RQDB.roster.Disabled.enabled = false
        member("Ignored", { 333 }).registration = "ignored"
        local planned = member("Planned", {})
        planned.professionIntent.planned = { [393] = true }
        local report = evaluate()
        equal(report.coverage.members, 4)
        equal(report.coverage.uncertain, 1)
        equal(#report.coverage.professions[171].owners, 1)
        equal(#report.coverage.professions[197].owners, 0)
        equal(#report.coverage.professions[197].uncertainOwners, 1)
        equal(#report.coverage.professions[164].owners, 0)
        equal(#report.coverage.professions[393].owners, 0)
        local before = key(report.choices[1])
        known.identity.fullName = "Renamed provider"
        equal(key(evaluate().choices[1]), before)
        RQ.Database.Current().identity.realm = nil
        equal(#evaluate().choices, 0)
    end)

    test("preferences override soft class scores and exclusions never unlearn existing professions", function()
        local record = start()
        assert(RQ.ProfessionAdviceService.Preference(active, "preferred", 333, true))
        assert(evaluate().choices[1].professions[333])
        assert(RQ.ProfessionAdviceService.Preference(active, "excluded", 164, true))
        for _, choice in ipairs(evaluate().choices) do
            equal(choice.professions[164], nil)
        end
        equal(RQ.ProfessionAdviceService.Preference(active, "excluded", 333, true), false)
        setProfessions(record, { 164 })
        assert(evaluate().choices[1].professions[164])
        assert(record.snapshot.professions[164])
    end)

    test("gathering and self-sufficiency focus keep alternatives and useful duplicate gatherers", function()
        local record = start()
        member("Miner", { 186 })
        member("Smith", { 164 })
        assert(RQ.ProfessionAdviceService.Preference(active, "focus", "gathering"))
        equal(#evaluate().choices, 3)
        local found = false
        for _, choice in ipairs(evaluate().choices) do
            if choice.professions[186] then
                found = true
                contains(reasons(choice), "duplicate coverage")
                contains(reasons(choice), "observed roster crafter")
            end
        end
        assert(found)
        setProfessions(record, { 182 })
        assert(RQ.ProfessionAdviceService.Preference(active, "focus", "self-sufficient"))
        equal(evaluate().choices[1].additions[1], 171)
    end)

    test("observed recipe outputs matching unmet material demand provide an explained bounded benefit", function()
        start()
        local tailor = member("Tailor", { 197 })
        tailor.recipes.professions[197] = {
            name = "Tailoring",
            complete = true,
            scannedAt = now,
            recipes = {
                [1] = {
                    name = "Bag",
                    learned = true,
                    reagentsComplete = true,
                    reagents = {},
                    skillUps = 1,
                    outputItemId = 4240,
                    outputCount = 1,
                },
            },
        }
        RQ.Database.Current().supplies.needs[4240] = 1
        assert(RQ.ProfessionAdviceService.Preference(active, "preferred", 197, true))
        local report = evaluate()
        contains(reasons(report.choices[1]), "demand for item 4240")
        local before = report.choices[1].score
        tailor.recipes.professions[197].scannedAt = now - 48 * 3600
        equal(evaluate().choices[1].score, before - 7)
    end)

    test("planning intent persists independently and stale choice clicks are revalidated", function()
        local record = start()
        local choice = evaluate().choices[1]
        assert(RQ.ProfessionAdviceService.Plan(active, choice.additions))
        equal(next(record.snapshot.professions), nil)
        equal(#RQ.Util.Keys(record.professionIntent.planned), 2)
        equal(#evaluate().choices, 1)
        assert(RQCharDB.professionIntent.planned[choice.additions[1]])
        RQCharDB.professionIntent.planned[choice.additions[1]] = nil
        assert(record.professionIntent.planned[choice.additions[1]])
        assert(RQ.ProfessionAdviceService.Plan(active, {}))
        setProfessions(record, { 171, 182 })
        equal(RQ.ProfessionAdviceService.Plan(active, choice.additions), false)
        equal(next(record.professionIntent.planned), nil)
    end)

    test(
        "partial planned locks constrain pairs and conflicts are explicit without modifying learned choices",
        function()
            local record = start()
            assert(RQ.ProfessionAdviceService.Plan(active, { 393 }))
            equal(evaluate().candidateCount, 8)
            for _, choice in ipairs(evaluate().choices) do
                assert(choice.professions[393])
            end
            assert(RQ.ProfessionAdviceService.Plan(active, { 164, 186 }))
            setProfessions(record, { 171 })
            equal(#evaluate().choices, 0)
            contains({ evaluate().blocker }, "conflict")
            assert(record.snapshot.professions[171])
            assert(RQ.ProfessionAdviceService.Plan(active, {}))
            equal(#evaluate().choices, 3)
        end
    )

    test("schema eleven intent migration is idempotent and rejects malformed preferences atomically", function()
        start()
        local old = RQ.Util.Copy(RQDB)
        old.schemaVersion, old.characters[active].professionIntent = 10, nil
        local account, character = RQ.Migrations.Prepare(old, RQCharDB)
        equal(account.schemaVersion, 19)
        equal(account.characters[active].professionIntent.focus, "balanced")
        equal(old.characters[active].professionIntent, nil)
        local again = RQ.Migrations.Prepare(account, character)
        equal(next(again.characters[active].professionIntent.planned), nil)
        for _, invalid in ipairs({
            { focus = false },
            { planned = { [164] = true, [171] = true, [182] = true } },
            { preferred = { [999] = true } },
            { preferred = { [164] = false } },
            { preferred = { [164] = true }, excluded = { [164] = true } },
        }) do
            equal(RQ.Database.SaveLogistics(active, "professionIntent", invalid), false)
            equal(RQ.Database.Current().professionIntent.focus, "balanced")
            local broken = RQ.Util.Copy(account)
            broken.characters[active].professionIntent = invalid
            equal(RQ.Migrations.Prepare(broken, character), nil)
        end
    end)

    test("profession commands save manual intent preferences and report invalid input explicitly", function()
        local record = start()
        assert(RQ.ProfessionAdviceService.Command("profession-plan", "164,186"))
        assert(record.professionIntent.planned[164])
        assert(RQ.ProfessionAdviceService.Command("profession-plan", "clear"))
        assert(RQ.ProfessionAdviceService.Command("profession-focus", "gathering"))
        assert(RQ.ProfessionAdviceService.Command("profession-prefer", "393 on"))
        assert(RQ.ProfessionAdviceService.Command("profession-prefer", "393 off"))
        equal(record.professionIntent.preferred[393], nil)
        for _, invalid in ipairs({ "", "164,", "164,164", "129", "164,186,171" }) do
            equal(RQ.ProfessionAdviceService.Command("profession-plan", invalid), false)
        end
        equal(RQ.ProfessionAdviceService.Command("profession-focus", ""), false)
        equal(RQ.ProfessionAdviceService.Command("profession-avoid", "164 maybe"), false)
        equal(RQ.ProfessionAdviceService.Plan(active, { [1] = 164, [3] = 186 }), false)
        equal(RQ.ProfessionAdviceService.Preference(active, "preferred", 164, "off"), false)
        _G.SlashCmdList.ROSTERQUARTERMASTER("professions text")
        contains(h.messages(), "Reference model v1")
        contains(h.messages(), "Trainer locations")
    end)

    test(
        "native profession view supports selection plan clear focus and row reuse without protected actions",
        function()
            local record, frames = start(true)
            assert(RQ.MainWindow.Open("roster"))
            frames.Click(frames.FindButton("Profession advice"))
            equal(RQ.MainWindow.tab, "advice")
            equal(#RQ.MainWindow.view.professionAdvice.choices, 3)
            local count = #frames.widgets
            frames.Click(frames.FindButton("Plan professions"))
            h.flushTimers()
            equal(#RQ.Util.Keys(record.professionIntent.planned), 2)
            equal(next(record.snapshot.professions), nil)
            frames.Click(frames.FindButton("Clear intent"))
            h.flushTimers()
            frames.Click(frames.FindButton("Cycle focus"))
            h.flushTimers()
            equal(record.professionIntent.focus, "gathering")
            equal(#frames.widgets, count)
        end
    )

    test("profession intent survives ignore resume and login mirroring", function()
        local record = start()
        assert(RQ.ProfessionAdviceService.Plan(active, { 164, 186 }))
        assert(RQ.Database.Register("ignore"))
        equal(#evaluate().choices, 0)
        assert(record.professionIntent.planned[164])
        assert(RQ.Database.Register("add"))
        assert(record.professionIntent.planned[164])
        h.emit("PLAYER_ENTERING_WORLD")
        assert(RQCharDB.professionIntent.planned[186])
        assert(record.professionIntent.planned[164])
        RQDB.roster[active].enabled = false
        equal(#evaluate().choices, 0)
    end)

    test("class and role suitability are soft preferences and equal scores use profession ID order", function()
        local record = start()
        assert(RQ.ProfessionAdviceService.Plan(active, { 197, 333 }))
        record.identity.class = "MAGE"
        local mage = evaluate().choices[1].score
        record.identity.class = "UNKNOWN"
        equal(evaluate().choices[1].score, mage - 3)
        assert(RQ.ProfessionAdviceService.Plan(active, { 171, 182 }))
        local base = evaluate().choices[1].score
        RQDB.roster[active].role = "HEALER"
        equal(evaluate().choices[1].score, base + 2)
        assert(RQ.ProfessionAdviceService.Plan(active, {}))
        assert(RQ.ProfessionAdviceService.Preference(active, "focus", "gathering"))
        local choices = evaluate().choices
        equal(key(choices[1]), "182,186")
        equal(key(choices[2]), "182,393")
        equal(key(choices[3]), "186,393")
        equal(choices[1].score, choices[3].score)
    end)

    test("profession advice is pure and never calls game APIs or changes persisted intent", function()
        local record = start()
        local intent, snapshot, roster = record.professionIntent, record.snapshot, RQDB.roster
        RQ.Api.GetServerTime = function()
            error("Pure advice must use its supplied timestamp")
        end
        RQ.Api.GetItemName = function()
            error("Pure advice must use observed item IDs")
        end
        local result = evaluate()
        equal(#result.choices, 3)
        equal(record.professionIntent, intent)
        equal(record.snapshot, snapshot)
        equal(RQDB.roster, roster)
        equal(next(intent.planned), nil)
        result.intent.preferred[164] = true
        equal(intent.preferred[164], nil)
    end)

    for _, size in ipairs({ 0, 1, 5, 6, 20, 50 }) do
        test("profession advice remains bounded with " .. size .. " roster members", function()
            start()
            if size == 0 then
                RQDB.roster[active] = nil
            else
                for index = 2, size do
                    member("Member-" .. index, {})
                end
            end
            local calls, grocery = 0, RQ.SuppliesService.Grocery
            RQ.SuppliesService.Grocery = function(...)
                calls = calls + 1
                return grocery(...)
            end
            local report = evaluate()
            equal(calls, size)
            if size > 0 then
                equal(report.coverage.members, size)
                equal(report.candidateCount, 36)
                equal(#report.choices, 3)
            else
                equal(#report.choices, 0)
            end
        end)
    end
end
