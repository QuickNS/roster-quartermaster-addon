return function(h)
    local test, equal, contains = h.test, h.equal, h.contains
    local at = 1000000

    local function close(actual, expected)
        assert(math.abs(actual - expected) < 0.0000001, tostring(actual) .. " differs from " .. expected)
    end

    local function snapshot(level, rested, when, inside)
        when = when or at
        return {
            level = level or 25,
            xp = 12000,
            xpMax = 40000,
            restedXp = rested or 20000,
            wasResting = inside ~= false,
            lastSeen = when,
            lastLogout = when,
            professions = {},
            sections = {
                progression = { complete = true, observedAt = when },
                rested = { complete = true, observedAt = when },
                location = { complete = true, observedAt = when },
                professions = { complete = true, observedAt = when },
            },
        }
    end

    local function entry(main)
        return {
            enabled = true,
            isMain = main == true,
            restedMultiplier = 1,
            restedRevision = 0,
            resourceBlocker = false,
            dungeonReady = false,
        }
    end

    local function record(settings, member, level, rested, inside)
        local observed = snapshot(level, rested, at, inside)
        return {
            registration = "member",
            identity = { displayName = "Test", realm = "Realm" },
            snapshot = observed,
            restedState = {
                calibration = RQ.RestedEstimator.EmptyCalibration(settings, member),
                logout = RQ.RestedEstimator.LogoutSample(observed, settings, member),
            },
        }
    end

    local function setup()
        h.loadAddon()
        local settings = RQ.PlanningConfig.Prepare(nil)
        local member = entry()
        return settings, member, record(settings, member)
    end

    local function estimate(saved, member, settings, now)
        return RQ.RestedEstimator.Estimate(saved, member, settings, { now = now or at + 3600, staleHours = 48 })
    end

    test("rested estimates use inn/outside rates, multiplier and configured cap exactly", function()
        local settings, member, saved = setup()
        local result = estimate(saved, member, settings)
        equal(result.amount, 20250)
        equal(result.percentageOfLevel, 50.625)
        equal(result.isEstimated, true)
        equal(result.confidence, "LOW")
        equal(result.calculatedAt, at + 3600)
        saved.restedState.logout.wasResting = false
        equal(estimate(saved, member, settings).amount, 20062)
        member.restedMultiplier = 2
        saved.restedState.logout.multiplier = 2
        equal(estimate(saved, member, settings).amount, 20125)
        equal(estimate(saved, member, settings, at + 100000000).amount, 60000)
        equal(estimate(saved, member, settings, at).amount, 20000)
    end)

    test("live rested estimates use only actual API values without clamping or cached fallback", function()
        local settings, member, saved = setup()
        local result = RQ.RestedEstimator.Estimate(
            saved,
            member,
            settings,
            { active = true, restedXp = 70000, xpMax = 40000, now = at }
        )
        equal(result.amount, 70000)
        equal(result.confidence, "HIGH")
        equal(result.isEstimated, false)
        equal(RQ.RestedEstimator.Estimate(saved, member, settings, { active = true }).amount, nil)
        result = RQ.RestedEstimator.Estimate(saved, member, settings, { active = true, restedXp = 0, xpMax = 0 })
        equal(result.amount, 0)
        equal(result.percentageOfLevel, nil)
        result = RQ.RestedEstimator.Estimate(saved, member, settings, { active = true, restedXp = 1e308, xpMax = 1 })
        equal(result.percentageOfLevel, nil)
    end)

    test("offline estimates reject absent, corrupt and reversed evidence and mark stale baselines", function()
        local settings, member, saved = setup()
        equal(estimate(saved, member, settings, at - 1).amount, nil)
        equal(estimate(saved, member, settings, math.huge).amount, nil)
        equal(RQ.RestedEstimator.Estimate(saved, member, settings, {}).amount, nil)
        saved.restedState.calibration.inside = { 0.01 }
        equal(estimate(saved, member, settings).confidence, "MEDIUM")
        local stale = estimate(saved, member, settings, at + 48 * 3600)
        equal(stale.confidence, "LOW")
        contains(stale.warnings, "stale")
        saved.restedState.logout.restedXp = 70000
        local aboveCap = estimate(saved, member, settings)
        equal(aboveCap.capRatio, nil)
        contains(aboveCap.warnings, "exceeds configured cap")
        saved.restedState.logout.xpMax = 1e308
        settings.capLevels = 10
        equal(estimate(saved, member, settings).amount, nil)
        saved.restedState.logout = false
        equal(estimate(saved, member, settings).confidence, "UNKNOWN")
        saved.restedState = nil
        equal(estimate(saved, member, settings).amount, nil)
    end)

    test("logout samples require complete same-timestamp progression, rested and location", function()
        local settings, member = setup()
        for _, section in ipairs({ "progression", "rested", "location" }) do
            local value = snapshot()
            value.sections[section].complete = false
            equal(RQ.RestedEstimator.LogoutSample(value, settings, member), nil)
            value.sections[section].complete = true
            value.sections[section].observedAt = at - 1
            equal(RQ.RestedEstimator.LogoutSample(value, settings, member), nil)
        end
        for _, change in ipairs({
            { lastLogout = 0 },
            { lastSeen = at + 1 },
            { xpMax = 0 },
            { wasResting = "yes" },
        }) do
            local value = snapshot()
            for key, item in pairs(change) do
                value[key] = item
            end
            equal(RQ.RestedEstimator.LogoutSample(value, settings, member), nil)
        end
    end)

    test("login calibration compares prediction, consumes sample and learns base rate", function()
        local settings, member = setup()
        member.restedMultiplier = 2
        local saved = record(settings, member)
        local state =
            RQ.RestedEstimator.Calibrate(saved.restedState, snapshot(25, 20500, at + 3600), settings, member, at + 3600)
        equal(state.comparison.accepted, true)
        equal(state.comparison.estimated, 20500)
        equal(state.comparison.actual, 20500)
        equal(state.comparison.error, 0)
        close(state.calibration.inside[1], 0.00625)
        equal(#state.calibration.outside, 0)
        equal(state.logout, nil)
        assert(saved.restedState.logout)
        equal(#saved.restedState.calibration.inside, 0)
        local second = RQ.RestedEstimator.Calibrate(state, snapshot(25, 20500, at + 3600), settings, member, at + 3600)
        equal(second.comparison.accepted, false)
        equal(#second.calibration.inside, 1)
    end)

    test("calibration rejects short, changed-XP, capped and incomplete observations", function()
        local settings, member, saved = setup()
        local cases = {
            { elapsed = 299 },
            { elapsed = -1 },
            { xp = 12001 },
            { level = 26 },
            { xpMax = 41000 },
            { restedXp = 60000 },
            { restedXp = 20000 },
            { restedXp = 19999 },
            { incomplete = true },
        }
        for _, case in ipairs(cases) do
            local now = at + (case.elapsed or 3600)
            local value = snapshot(25, 20250, now)
            for _, key in ipairs({ "xp", "level", "xpMax", "restedXp" }) do
                if case[key] then
                    value[key] = case[key]
                end
            end
            if case.incomplete then
                value.sections.progression.complete = false
            end
            local state = RQ.RestedEstimator.Calibrate(saved.restedState, value, settings, member, now)
            equal(state.comparison.accepted, false)
            equal(#state.calibration.inside, 0)
            equal(state.logout, nil)
        end
        settings.maxLevel = 25
        saved = record(settings, member)
        local capped =
            RQ.RestedEstimator.Calibrate(saved.restedState, snapshot(25, 20250, at + 3600), settings, member, at + 3600)
        equal(capped.comparison.accepted, false)
    end)

    test("calibration averages at most eight samples per resting location", function()
        local settings, member, saved = setup()
        local state = saved.restedState
        for index = 1, 11 do
            state.logout = RQ.RestedEstimator.LogoutSample(snapshot(), settings, member)
            state =
                RQ.RestedEstimator.Calibrate(state, snapshot(25, 21000 + index, at + 3600), settings, member, at + 3600)
        end
        equal(#state.calibration.inside, 8)
        close(state.calibration.inside[1], 1004 / 40000)
        state.logout = RQ.RestedEstimator.LogoutSample(snapshot(25, 20000, at, false), settings, member)
        state = RQ.RestedEstimator.Calibrate(state, snapshot(25, 20100, at + 3600), settings, member, at + 3600)
        equal(#state.calibration.inside, 8)
        equal(#state.calibration.outside, 1)
        state.logout = RQ.RestedEstimator.LogoutSample(snapshot(), settings, member)
        local result = estimate({ restedState = state }, member, settings)
        close(result.ratePerHour, 1007.5 / 40000)
        equal(result.confidence, "MEDIUM")
    end)

    test("changed perk revisions invalidate logout estimates and calibration profiles", function()
        local settings, member, saved = setup()
        member.restedRevision = 1
        equal(estimate(saved, member, settings).amount, nil)
        local state =
            RQ.RestedEstimator.Calibrate(saved.restedState, snapshot(25, 20250, at + 3600), settings, member, at + 3600)
        equal(state.comparison.accepted, false)
        contains({ state.comparison.reason }, "profile changed")
        equal(state.calibration.profile, RQ.RestedEstimator.Profile(settings, member))
        settings.innRate = 0.02
        member.restedRevision = 0
        equal(estimate(saved, member, settings).amount, 20800)
        local changed =
            RQ.RestedEstimator.Calibrate(saved.restedState, snapshot(25, 20250, at + 3600), settings, member, at + 3600)
        equal(changed.comparison.accepted, false)
    end)

    local function roster()
        local settings = setup()
        local account = { roster = {}, policies = { staleSnapshotHours = 48 }, session = {} }
        local records = {}
        for _, id in ipairs({ "a-main", "b-alt", "c-alt" }) do
            account.roster[id] = entry(id == "a-main")
            records[id] = record(settings, account.roster[id], 25, 0)
        end
        return account, records, settings
    end

    local function rank(account, records, settings, context)
        return assert(RQ.PriorityEngine.Evaluate(account, records, settings, context or { now = at }))
    end

    test("ranking is deterministic, non-mutating and always provides two or three reasons", function()
        local account, records, settings = roster()
        account.roster["a-main"].isMain = false
        local baseline = rank(account, records, settings)
        for iteration = 1, 20 do
            local results = rank(account, records, settings)
            for index, result in ipairs(results) do
                equal(result.characterId, baseline[index].characterId)
                equal(result.score, baseline[index].score)
                equal(table.concat(result.reasons), table.concat(baseline[index].reasons))
                assert(#result.reasons >= 2 and #result.reasons <= 3, iteration)
            end
        end
        equal(baseline[1].characterId, "a-main")
        equal(baseline[2].characterId, "b-alt")
        equal(records["a-main"].restedState.logout.at, at)
        equal(account.roster["a-main"].isMain, false)
    end)

    test("partial snapshots are safe, and stale cross-character levels lower lead confidence", function()
        local account, records, settings = roster()
        local active = { now = at, activeId = "a-main", live = { restedXp = 0, xpMax = 40000 } }
        equal(rank(account, records, settings, active)[1].confidence, "HIGH")
        records["b-alt"].snapshot.sections.progression.observedAt = at - 49 * 3600
        local result = rank(account, records, settings, active)[1]
        equal(result.characterId, "a-main")
        equal(result.confidence, "HIGH")
        records["a-main"].snapshot = nil
        local results = rank(account, records, settings)
        equal(#results, 3)
        records["b-alt"].snapshot.sections.progression.observedAt = at + 1
        equal(#rank(account, records, settings), 3)
    end)

    test("profession milestones require fresh sections and level milestones use strict next boundary", function()
        local account, records, settings = roster()
        for id, member in pairs(account.roster) do
            member.isMain = false
            records[id].snapshot.level = 30
        end
        records["b-alt"].snapshot.professions = { [186] = { skill = 140 } }
        equal(rank(account, records, settings)[1].score, 10)
        records["b-alt"].snapshot.professions[186].skill = 150
        equal(rank(account, records, settings)[1].score, 0)
        records["b-alt"].snapshot.professions[186].skill = 149
        records["b-alt"].snapshot.sections.professions.observedAt = at - 49 * 3600
        equal(rank(account, records, settings)[1].score, 0)
        for _, level in ipairs({ 23, 24, 43, 44, 58, 59 }) do
            records["b-alt"].snapshot.level = level
            local scores = {}
            for _, result in ipairs(rank(account, records, settings)) do
                scores[result.characterId] = result.score
            end
            equal(scores["b-alt"], 15)
        end
        records["b-alt"].snapshot.level = 45
        equal(rank(account, records, settings)[1].score, 0)
    end)

    test("manual dungeon, previous-session and lag contributions match configured weights", function()
        local account, records, settings = roster()
        records["a-main"].snapshot.level = 40
        records["b-alt"].snapshot.level = 29
        records["c-alt"].snapshot.level = 30
        account.roster["b-alt"].dungeonReady = true
        account.session.previousCharacterId = "b-alt"
        local result = rank(account, records, settings)
        equal(result[1].characterId, "b-alt")
        close(result[1].score, 15 - 10)
    end)

    test("only enabled registered members rank and unavailable pins are explicit", function()
        local account, records, settings = roster()
        records["a-main"].registration = "pending"
        records["b-alt"].registration = "ignored"
        account.roster["c-alt"].enabled = false
        settings.pinnedCharacterId = "b-alt"
        local results, err, _, warnings = RQ.PriorityEngine.Evaluate(account, records, settings, { now = at })
        equal(err, nil)
        equal(#results, 0)
        equal(#warnings, 0)
    end)

    local function start(native, skipped)
        h.fakeCharacter()
        local frames = native and assert(loadfile("Tests/fixtures/Frames.lua"))()()
        h.loadAddon(skipped)
        if frames then
            frames.Emit("PLAYER_LOGIN")
        else
            h.emit("PLAYER_LOGIN")
        end
        assert(RQ.Database.Register("add"))
        return frames
    end

    test("schema four seeds only defensible legacy logouts and never revives consumed samples", function()
        start()
        h.emit("PLAYER_LOGOUT")
        local input = RQ.Util.Copy(RQDB)
        input.schemaVersion = 3
        input.settings.planning = nil
        input.characters["Player-Test-1"].restedState = nil
        local migrated, character, err = RQ.Migrations.Prepare(input, RQCharDB)
        assert(migrated and character, err)
        equal(migrated.schemaVersion, 19)
        assert(migrated.characters["Player-Test-1"].restedState.logout)
        equal(input.characters["Player-Test-1"].restedState, nil)
        migrated.characters["Player-Test-1"].restedState.logout = nil
        local again = RQ.Migrations.Prepare(migrated, character)
        equal(again.characters["Player-Test-1"].restedState.logout, nil)
        input.characters["Player-Test-1"].snapshot.sections.location.complete = false
        local incomplete = RQ.Migrations.Prepare(input, character)
        equal(incomplete.characters["Player-Test-1"].restedState.logout, nil)
    end)

    test("invalid planning or calibration rejects both roots transactionally", function()
        start()
        for _, corrupt in ipairs({
            function(db)
                db.settings.planning.innRate = -1
            end,
            function(db)
                db.settings.planning.capLevels = 0
            end,
            function(db)
                db.settings.planning.maxLevel = 0
            end,
            function(db)
                db.settings.planning.levelMilestones = { 45, 25 }
            end,
            function(db)
                db.settings.planning.weights.rested = math.huge
            end,
            function(db)
                db.roster["Player-Test-1"].restedMultiplier = 0
            end,
            function(db)
                db.session.currentCharacterId = false
            end,
            function(db)
                db.characters["Player-Test-1"].restedState.calibration.inside = { [2] = 0.1 }
            end,
            function(db)
                db.characters["Player-Test-1"].restedState.logout = {}
            end,
        }) do
            local input = RQ.Util.Copy(RQDB)
            corrupt(input)
            local account, character, err = RQ.Migrations.Prepare(input, RQCharDB)
            equal(account, nil)
            equal(character, nil)
            assert(err)
            equal(input.schemaVersion, 19)
        end
    end)

    test("logout/login calibrates once, mirrors independently, and rescans retain comparison", function()
        start()
        _G.IsResting = function()
            return true
        end
        h.emit("PLAYER_LOGOUT")
        local previous = RQDB.characters["Player-Test-1"].restedState
        assert(previous.logout)
        assert(previous ~= RQCharDB.restedState)
        _G.GetServerTime = function()
            return 123460389
        end
        _G.GetXPExhaustion = function()
            return 20250
        end
        h.loadAddon()
        h.emit("PLAYER_LOGIN")
        local state = RQ.Database.Current().restedState
        equal(state.comparison.accepted, true)
        equal(state.logout, nil)
        equal(#state.calibration.inside, 1)
        equal(RQCharDB.restedState.comparison.actual, 20250)
        assert(RQCharDB.restedState.calibration.inside ~= state.calibration.inside)
        local comparison = state.comparison
        h.emit("PLAYER_ENTERING_WORLD")
        RQ.SnapshotService.Refresh()
        equal(RQ.Database.Current().restedState.comparison, comparison)
        equal(#state.calibration.inside, 1)
        local report = RQ.PlanningService.Evaluate()
        equal(report.estimates["Player-Test-1"].isEstimated, false)
        _G.GetXPExhaustion = nil
        equal(RQ.PlanningService.Evaluate().estimates["Player-Test-1"].amount, nil)
    end)

    test("session history survives same-character reload and switches on a new character", function()
        start()
        h.emit("PLAYER_LOGOUT")
        _G.UnitGUID = function()
            return "Player-Second"
        end
        _G.UnitName = function()
            return "Second"
        end
        RQCharDB = nil
        h.loadAddon()
        h.emit("PLAYER_LOGIN")
        equal(RQDB.session.previousCharacterId, "Player-Test-1")
        equal(RQDB.session.currentCharacterId, "Player-Second")
        local report = RQ.PlanningService.Evaluate()
        equal(report.estimates["Player-Test-1"].isEstimated, true)
        h.emit("PLAYER_LOGOUT")
        h.loadAddon()
        h.emit("PLAYER_LOGIN")
        equal(RQDB.session.previousCharacterId, "Player-Test-1")
        equal(RQDB.session.currentCharacterId, "Player-Second")
    end)

    test("pin resolver handles GUIDs, full names, ambiguous names and ignores", function()
        start()
        equal(RQ.Database.ResolveMember("Player-Test-1"), "Player-Test-1")
        equal(RQ.Database.ResolveMember("RENAMED"), "Player-Test-1")
        equal(RQ.Database.ResolveMember("Renamed-TestRealm PVE"), "Player-Test-1")
        equal(RQ.Database.ResolveMember("Chop Suey"), nil)
        local copy = RQ.Util.Copy(RQ.Database.Current())
        copy.identity.guid, copy.identity.realm = "Player-Other", "OtherRealm"
        copy.registration = "pending"
        RQDB.characters["Player-Other"] = copy
        assert(RQ.Database.Register("add", "Player-Other"))
        local id, err = RQ.Database.ResolveMember("Renamed")
        equal(id, nil)
        contains({ err }, "Ambiguous")
        _G.SlashCmdList.ROSTERQUARTERMASTER("main Player-Test-1")
        equal(RQDB.roster["Player-Test-1"].isMain, true)
        _G.SlashCmdList.ROSTERQUARTERMASTER("unpin")
        equal(RQDB.settings.planning.pinnedCharacterId, nil)
        assert(RQ.Database.SetMain("Player-Other"))
        assert(RQ.Database.Register("ignore", "Player-Other"))
        equal(RQDB.settings.planning.pinnedCharacterId, nil)
        equal(RQ.Database.SetMain("missing"), false)
    end)

    test("fallback promotion rekeys pin and both session references even without slots", function()
        h.fakeCharacter()
        _G.UnitGUID = nil
        h.loadAddon()
        h.emit("PLAYER_LOGIN")
        assert(RQ.Database.Register("add"))
        local old = RQ.Database.activeId
        assert(RQ.Database.SetMain(old))
        RQDB.session.previousCharacterId = old
        _G.UnitGUID = function()
            return "Player-Promoted"
        end
        assert(RQ.SnapshotService.Refresh())
        equal(RQDB.roster["Player-Promoted"].isMain, true)
        equal(RQDB.session.currentCharacterId, "Player-Promoted")
        equal(RQDB.session.previousCharacterId, "Player-Promoted")
        equal(RQDB.characters[old], nil)
    end)

    test("planning edits validate atomically and perk reset clears calibration and baseline", function()
        start()
        h.emit("PLAYER_LOGOUT")
        local state = RQ.Database.Current().restedState
        state.calibration.outside = { 0.02 }
        local settings = RQ.Util.Copy(RQDB.settings.planning)
        settings.maxLevel = 0
        equal(RQ.Database.SetPlanning(settings), false)
        equal(RQDB.settings.planning.maxLevel, 60)
        settings.maxLevel = 12
        assert(RQ.Database.SetPlanning(settings))
        equal(#state.calibration.outside, 0)
        settings.innRate = 0.02
        assert(RQ.Database.SetPlanning(settings))
        equal(#state.calibration.outside, 0)
        assert(state.logout)
        assert(RQ.Database.ResetCalibration("Player-Test-1", 2))
        equal(RQDB.roster["Player-Test-1"].restedMultiplier, 2)
        equal(RQDB.roster["Player-Test-1"].restedRevision, 1)
        equal(RQ.Database.Current().restedState.logout, nil)
        equal(RQCharDB.restedState.logout, nil)
        equal(RQ.Database.ResetCalibration("Player-Test-1", 0), false)
        assert(RQ.Database.SetPlanningSignal("Player-Test-1", "resourceBlocker", true))
        equal(RQDB.roster["Player-Test-1"].resourceBlocker, true)
        equal(RQ.Database.SetPlanningSignal("Player-Test-1", "not-a-signal", true), false)
    end)

    test("Planning native form preserves focus, saves numeric units and controls manual signals", function()
        local frames = start(true)
        _G.SlashCmdList.ROSTERQUARTERMASTER("planning")
        local edit = frames.FindKind("EditBox")
        equal(edit:GetText(), "0.625")
        edit:SetText("1.25")
        edit:SetFocus()
        RQ.MainWindow.Invalidate()
        h.flushTimers()
        equal(edit:GetText(), "1.25")
        frames.Click(frames.FindButton("Save assumptions"))
        h.flushTimers()
        close(RQDB.settings.planning.innRate, 0.0125)
        frames.Click(frames.FindButton("Resource blocker: No"))
        h.flushTimers()
        equal(RQDB.roster["Player-Test-1"].resourceBlocker, true)
        frames.Click(frames.FindButton("Dungeon ready: No"))
        h.flushTimers()
        equal(RQDB.roster["Player-Test-1"].dungeonReady, true)
        frames.Click(frames.FindButton("Reset calibration"))
        h.flushTimers()
        equal(RQDB.roster["Player-Test-1"].restedRevision, 1)
        edit:SetText("bad")
        frames.Click(frames.FindButton("Save assumptions"))
        h.flushTimers()
        close(RQDB.settings.planning.innRate, 0.0125)
        contains(h.messages(), "Missing planning value")
    end)

    test("cached logout estimates count only offline time and never calibrate an observed rate", function()
        local settings, member, saved = setup()
        local value = snapshot()
        value.lastLogout = at + 600
        saved.restedState.logout = RQ.RestedEstimator.LogoutSample(value, settings, member, true)
        saved.restedState.calibration.inside = { settings.innRate }
        local result = estimate(saved, member, settings, at + 4200)
        equal(result.amount, 20250)
        equal(result.cachedBaseline, true)
        equal(result.confidence, "LOW")
        contains(result.warnings, "cached observations")
        contains({ RQ.RestedEstimator.Describe(result) }, "cached logout baseline")
        local calibrated =
            RQ.RestedEstimator.Calibrate(saved.restedState, snapshot(25, 20250, at + 4200), settings, member, at + 4200)
        equal(calibrated.comparison.accepted, false)
        equal(#calibrated.calibration.inside, 1)
        contains({ calibrated.comparison.reason }, "Cached logout baseline")
        equal(calibrated.logout, nil)
        local recentLogout = at + 48 * 3600
        value.lastLogout = recentLogout
        saved.restedState.logout = RQ.RestedEstimator.LogoutSample(value, settings, member, true)
        contains(estimate(saved, member, settings, recentLogout).warnings, "stale")
    end)

    test("cached baselines reject incomplete or future evidence and persist specific missing-data reasons", function()
        local settings, member = setup()
        for _, section in ipairs({ "progression", "rested", "location" }) do
            local value = snapshot()
            value.lastLogout = at + 600
            value.sections[section].complete = false
            local sample, reason = RQ.RestedEstimator.LogoutSample(value, settings, member, true)
            equal(sample, nil)
            contains({ reason }, section)
            value.sections[section].complete = true
            value.sections[section].observedAt = at + 601
            equal(RQ.RestedEstimator.LogoutSample(value, settings, member, true), nil)
        end
        local value = snapshot()
        value.xpMax = 0
        local sample, reason = RQ.RestedEstimator.LogoutSample(value, settings, member, true)
        equal(sample, nil)
        contains({ reason }, "XP maximum is zero")
        local state = RQ.PlanningConfig.PrepareState({ logoutReason = reason })
        equal(estimate({ restedState = state }, member, settings).reason, reason)
        equal(RQ.PlanningConfig.PrepareState({ logoutReason = false }), nil)
        value.xpMax = 40000
        sample = RQ.RestedEstimator.LogoutSample(value, settings, member, true)
        sample.observedAt = nil
        equal(RQ.PlanningConfig.PrepareState({ logout = sample }), nil)
    end)

    test("cached logout survives another character login without losing XP or sharing state", function()
        start()
        _G.GetServerTime = function()
            return 123456900
        end
        _G.UnitXP = function()
            return 0
        end
        _G.UnitXPMax = function()
            return 0
        end
        h.emit("PLAYER_LOGOUT")
        local offlineId = RQ.Database.activeId
        assert(RQCharDB.restedState.logout.cached)
        assert(RQCharDB.restedState.logout ~= RQDB.characters[offlineId].restedState.logout)
        h.fakeCharacter()
        _G.UnitGUID = function()
            return "Player-Second"
        end
        _G.UnitName = function()
            return "Second"
        end
        _G.GetServerTime = function()
            return 123460500
        end
        RQCharDB = nil
        h.loadAddon()
        h.emit("PLAYER_LOGIN")
        local offline = RQDB.characters[offlineId]
        equal(offline.snapshot.xp, 12000)
        equal(offline.snapshot.xpMax, 40000)
        equal(offline.snapshot.money, 12345)
        local report = RQ.PlanningService.Evaluate()
        equal(report.estimates[offlineId].amount, 20062)
        equal(report.estimates[offlineId].isEstimated, true)
        equal(report.estimates[offlineId].cachedBaseline, true)
        _G.SlashCmdList.ROSTERQUARTERMASTER("roster text")
        contains(h.messages(), "cached logout baseline")
    end)

    test("offline descriptions never depend on evaluating an active character first", function()
        local settings, member, saved = setup()
        contains({ RQ.RestedEstimator.Describe(estimate(saved, member, settings)) }, "estimated offline")
        equal(RQ.RestedEstimator.Describe({ reason = "No baseline" }), "Rested XP: unknown - No baseline")
    end)

    test("tab changes reset scroll while planning refresh does not hide focused editors", function()
        local frames = start(true)
        _G.SlashCmdList.ROSTERQUARTERMASTER("roster")
        local scroll = frames.FindKind("ScrollFrame")
        scroll:SetVerticalScroll(100)
        frames.Click(frames.FindButton("Suggested order"))
        equal(scroll:GetVerticalScroll(), 0)
        frames.Click(frames.FindButton("Settings"))
        local edit = frames.FindKind("EditBox")
        edit:SetText("0.7")
        edit:SetFocus()
        edit.parent:SetScript("OnHide", function()
            edit:ClearFocus()
        end)
        RQ.MainWindow.Invalidate()
        h.flushTimers()
        equal(edit:HasFocus(), true)
        equal(edit:GetText(), "0.7")
        local multiplier
        for _, widget in ipairs(frames.widgets) do
            if widget.kind == "EditBox" and widget:IsVisible() then
                multiplier = widget
            end
        end
        multiplier:SetText("invalid")
        frames.Click(frames.FindButton("Save multiplier"))
        h.flushTimers()
        equal(RQDB.roster["Player-Test-1"].restedRevision, 0)
        contains(h.messages(), "Enter a numeric")
        multiplier:SetText("2")
        frames.Click(frames.FindButton("Save multiplier"))
        h.flushTimers()
        equal(RQDB.roster["Player-Test-1"].restedMultiplier, 2)
        equal(RQDB.roster["Player-Test-1"].restedRevision, 1)
    end)

    test("incomplete logout discards old baseline and ignored login cannot recalibrate it", function()
        start()
        h.emit("PLAYER_LOGOUT")
        assert(RQ.Database.Current().restedState.logout)
        _G.IsResting = nil
        h.emit("PLAYER_LOGOUT")
        equal(RQ.Database.Current().restedState.logout, nil)
        _G.IsResting = function()
            return true
        end
        h.emit("PLAYER_LOGOUT")
        assert(RQ.Database.Current().restedState.logout)
        assert(RQ.Database.Register("ignore"))
        h.loadAddon()
        h.emit("PLAYER_LOGIN")
        equal(RQ.Database.Current().restedState.logout, nil)
        equal(RQCharDB.restedState.logout, nil)
        assert(RQ.Database.Register("add"))
        RQ.SnapshotService.Refresh()
        equal(#RQ.Database.Current().restedState.calibration.inside, 0)
    end)
end
