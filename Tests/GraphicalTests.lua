return function(h)
    local test, equal, contains = h.test, h.equal, h.contains
    local now, active = 123456789, "Player-Test-1"
    local function start()
        h.fakeCharacter()
        local frames = assert(loadfile("Tests/fixtures/Frames.lua"))()()
        _G.CLASS_ICON_TCOORDS = { WARRIOR = { 0, 0.25, 0, 0.25 }, PRIEST = { 0.5, 0.75, 0, 0.25 } }
        _G.RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } }
        _G.LOCALIZED_CLASS_NAMES_MALE = { WARRIOR = "Warrior", PRIEST = "Priest" }
        _G.SetPortraitTexture = function(texture, unit)
            equal(unit, "player")
            texture.portrait = _G.UnitGUID(unit)
        end
        h.loadAddon()
        RQ.MainWindow.realm, RQ.MainWindow.group = "all", "all"
        RQ.MainWindow.rosterSort = "name"
        frames.Emit("PLAYER_LOGIN")
        assert(RQ.Database.Register("add"))
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
            class = "PRIEST",
        }
        record.registration = "pending"
        RQDB.characters[id] = record
        assert(RQ.Database.Register("add", id))
        return record
    end
    local function rows(frames)
        local result = {}
        for _, widget in ipairs(frames.widgets) do
            if widget.card and widget:IsVisible() then
                result[#result + 1] = widget
            end
        end
        table.sort(result, function(a, b)
            return a.points[1][5] > b.points[1][5]
        end)
        return result
    end
    local function textVisible(frames, text)
        for _, widget in ipairs(frames.widgets) do
            if widget:IsVisible() and widget.text:find(text, 1, true) then
                return widget
            end
        end
        error("No visible text: " .. text)
    end
    local function click(frames, label)
        frames.Click(frames.FindButton(label))
        h.flushTimers()
    end

    test("graphical roster uses full names and shared lag assessment without modifying snapshots", function()
        local frames = start()
        local record = member("Player-B", "Very Long Full Name With A Surname", "OtherRealm")
        record.snapshot.professions[186].name = "A localized profession with a long display label"
        local before = RQ.Util.Copy(record)
        assert(RQ.MainWindow.Open("roster"))
        local list = rows(frames)
        equal(#list, 2)
        equal(list[1].characterId, "Player-B")
        contains({ list[1].heading.text }, record.identity.fullName)
        equal(list[1].realm.text, "OtherRealm")
        contains({ list[1].professions[2].text.text }, "Behind 25")
        assert(list[1].professions[2].text:GetStringHeight() > 14)
        assert(
            list[1].select.points[1][5]
                < list[1].professions[2].text.points[1][5] - list[1].professions[2].text:GetStringHeight()
        )
        equal(record.snapshot.professions[186].skill, before.snapshot.professions[186].skill)
        equal(record.snapshot.lastSeen, before.snapshot.lastSeen)
    end)

    test("roster realm grouping sorting and filters preserve selected GUID and hidden details", function()
        local frames = start()
        local other = member("Player-B", "Alpha")
        other.snapshot.level = 10
        member("Player-C", "Bravo", "AnotherRealm")
        RQ.MainWindow.selectedId = "Player-B"
        assert(RQ.MainWindow.Open("roster"))
        click(frames, "Sort: name")
        equal(RQ.MainWindow.view.sort, "level")
        equal(rows(frames)[2].characterId, "Player-B")
        equal(RQ.MainWindow.selectedId, "Player-B")
        click(frames, "Show: all")
        click(frames, "Show: members")
        equal(RQ.MainWindow.view.filter, "behind")
        equal(#RQ.MainWindow.view.rows, 2)
        equal(RQ.MainWindow.view.detail.id, "Player-B")
        textVisible(frames, "Selection is hidden by the current filters")
        click(frames, "Show: behind")
        equal(#rows(frames), 0)
        textVisible(frames, "No matching characters")
        click(frames, "Show: uncertain")
        click(frames, "All realms")
        equal(RQ.MainWindow.view.realm, "anotherrealm")
        equal(#rows(frames), 1)
        click(frames, "Next row")
        equal(RQ.MainWindow.selectedId, "Player-C")
        equal(RQ.MainWindow.view.detail.id, "Player-C")
    end)

    test("roster priority sort uses engine ranks and profession sort uses existing deficits", function()
        start()
        member("Player-B", "Alpha").snapshot.professions[186].skill = 120
        assert(RQ.Database.SetMain("Player-B"))
        local report = assert(RQ.PlanningService.Evaluate())
        local view = RQ.RosterPanel.Build(
            RQDB,
            active,
            now,
            nil,
            report.estimates,
            { sort = "priority" },
            report.recommendations
        )
        equal(view.rows[1].id, "Player-B")
        local sorted = RQ.RosterPanel.SelectRows(view.cards, { sort = "profession" })
        equal(sorted[1].id, active)
        equal(sorted[1].visual.deficit, 25)
        equal(sorted[2].visual.deficit, 5)
        equal(report.recommendations[1].characterId, "Player-B")
    end)

    test(
        "Today preserves engine order and score while exposing reasons rested values and configuration actions",
        function()
            local frames = start()
            member("Player-B", "Alpha", "OtherRealm")
            local report = assert(RQ.PlanningService.Evaluate())
            assert(RQ.MainWindow.Open("today"))
            for index, row in ipairs(rows(frames)) do
                equal(row.characterId, report.recommendations[index].characterId)
                equal(row.card.visual.rank, index)
                contains({ row.card.summary }, row.card.visual.reason)
                contains({ row.card.detail }, "Score: " .. string.format("%.1f", report.recommendations[index].score))
            end
            local id = rows(frames)[2].characterId
            frames.Click(rows(frames)[2].action)
            h.flushTimers()
            equal(RQ.MainWindow.tab, "manage")
            equal(RQ.MainWindow.selectedId, id)
            equal(RQ.Database.Pin, nil)
        end
    )

    test("rested graphics distinguish zero unknown cached estimates and unknown cap scales", function()
        local frames = start()
        assert(RQ.MainWindow.Open("today"))
        local row = rows(frames)[1]
        equal(row.restFill:IsShown(), true)
        equal(row.restFill:GetWidth(), 420 * row.card.visual.rested.ratio)
        _G.GetXPExhaustion = function()
            return 0
        end
        assert(RQ.MainWindow.Render())
        contains({ row.restLabel.text }, "Rested: 0 XP")
        contains({ row.restBadge.text }, "OBSERVED")
        equal(row.card.visual.rested.ratio, 0)
        equal(row.restFill:IsShown(), false)
        local visual = RQ.CharacterCard.RestedVisual({
            amount = 0,
            isEstimated = true,
            cachedBaseline = true,
            confidence = "LOW",
        })
        equal(visual.ratio, nil)
        contains({ visual.badge }, "CACHED ESTIMATE")
        contains({ visual.label }, "percentage unknown")
        local unknown = RQ.CharacterCard.RestedVisual({ reason = "Stale observation" })
        equal(unknown.label, "Rested XP: unknown")
        equal(unknown.ratio, nil)
        local original = RQ.PlanningService.Evaluate
        RQ.PlanningService.Evaluate = function()
            local report = original()
            report.recommendations[1].estimate = { reason = "Stale observation" }
            return report
        end
        assert(RQ.MainWindow.Render())
        contains({ row.restLabel.text }, "unknown")
        contains({ row.restBadge.text }, "Progress scale unknown")
        equal(row.restFill:IsShown(), false)
    end)

    test(
        "portraits are limited to verified live GUID and reused rows cannot keep another character portrait",
        function()
            local frames = start()
            local other = member("Player-B", "Zeta")
            assert(RQ.MainWindow.Open("roster"))
            local list = rows(frames)
            equal(list[1].portrait.portrait, active)
            equal(list[2].portrait.portrait, nil)
            contains({ list[2].portrait.texture }, "UI-CHARACTERCREATE-CLASSES")
            other.identity.fullName = "Alpha"
            assert(RQ.MainWindow.Render())
            list = rows(frames)
            equal(list[1].characterId, "Player-B")
            equal(list[1].portrait.portrait, nil)
            equal(list[2].portrait.portrait, active)
            _G.UnitGUID = function()
                return nil
            end
            assert(RQ.MainWindow.Render())
            equal(list[2].portrait.portrait, nil)
        end
    )

    test("missing or failed graphics APIs retain text and actions", function()
        local frames = start()
        _G.CLASS_ICON_TCOORDS, _G.SetPortraitTexture, _G.RAID_CLASS_COLORS = nil, nil, nil
        assert(RQ.MainWindow.Open("roster"))
        local row = rows(frames)[1]
        equal(row.portrait:IsShown(), false)
        contains({ row.identity.text }, "Warrior")
        row.portrait.SetTexCoord = function()
            error("restricted")
        end
        _G.SetPortraitTexture = function()
            error("restricted")
        end
        assert(RQ.MainWindow.Render())
        equal(row.portrait:IsShown(), false)
        row.professions[1].icon.SetTexture = nil
        assert(RQ.MainWindow.Render())
        equal(row.professions[1].icon:IsShown(), false)
        click(frames, "Configure selected")
        equal(RQ.MainWindow.tab, "manage")
    end)

    test("keyboard selection propagates typing unavailable focus checks and non-navigation keys", function()
        start()
        member("Player-B", "Alpha")
        assert(RQ.MainWindow.Open("roster"))
        _G.GetCurrentKeyBoardFocus = function()
            return nil
        end
        _G.RQMainWindow.scripts.OnKeyDown(_G.RQMainWindow, "DOWN")
        h.flushTimers()
        equal(RQ.MainWindow.selectedId, "Player-B")
        equal(_G.RQMainWindow.propagate, false)
        _G.GetCurrentKeyBoardFocus = function()
            return {}
        end
        _G.RQMainWindow.scripts.OnKeyDown(_G.RQMainWindow, "DOWN")
        equal(_G.RQMainWindow.propagate, true)
        equal(RQ.MainWindow.selectedId, "Player-B")
        _G.GetCurrentKeyBoardFocus = nil
        _G.RQMainWindow.scripts.OnKeyDown(_G.RQMainWindow, "UP")
        equal(_G.RQMainWindow.propagate, true)
        _G.RQMainWindow.scripts.OnKeyDown(_G.RQMainWindow, "W")
        equal(_G.RQMainWindow.propagate, true)
        assert(RQ.MainWindow.Open("manage"))
        _G.GetCurrentKeyBoardFocus = function()
            return nil
        end
        _G.RQMainWindow.scripts.OnKeyDown(_G.RQMainWindow, "DOWN")
        equal(_G.RQMainWindow.propagate, true)
    end)

    test("class sorting unknown profession evidence and observed detail values stay explicit", function()
        start()
        local record = member("Player-B", "Alpha")
        record.snapshot.professions[999] = { name = "Unclassified", skill = 10, maxSkill = 75 }
        record.inventory.bags.equipped = { [1] = 16, [2] = 0 }
        record.supplies.goals[186] = { recipeId = 123, targetSkill = 125 }
        record.supplies.needs[2770] = 20
        assert(RQ.Database.SetRole("Player-B", "HEALER"))
        local view = RQ.RosterPanel.Build(RQDB, active, now, nil, nil, { sort = "class" })
        equal(view.rows[1].id, "Player-B")
        contains({ view.rows[1].visual.role }, "Healer")
        local uncertain = RQ.RosterPanel.SelectRows(view.cards, { filter = "uncertain" })
        equal(#uncertain, 1)
        equal(uncertain[1].id, "Player-B")
        contains({ uncertain[1].body }, "Slot 1: 16 slots, Slot 2: empty")
        contains({ uncertain[1].body }, "recipe 123 -> skill 125")
        contains({ uncertain[1].body }, "Stock target: item 2770 x20")
    end)

    test("keyboard buttons remain usable when native keyboard methods are absent", function()
        local frames = start()
        local create = _G.CreateFrame
        _G.CreateFrame = function(...)
            local frame = create(...)
            frame.EnableKeyboard, frame.SetPropagateKeyboardInput = nil, nil
            return frame
        end
        member("Player-B", "Alpha")
        assert(RQ.MainWindow.Open("roster"))
        click(frames, "Next row")
        equal(RQ.MainWindow.selectedId, "Player-B")
        equal(_G.RQMainWindow.scripts.OnKeyDown, nil)
    end)

    test("graphical rows reuse widgets at fifty characters and keep both scroll positions on refresh", function()
        local frames = start()
        for index = 1, 49 do
            member("Player-" .. index, string.format("Member %02d", index))
        end
        assert(RQ.MainWindow.Open("roster"))
        equal(#rows(frames), 50)
        local count = #frames.widgets
        local row = rows(frames)[1]
        local scroll = row.parent.parent
        local detailScroll = frames.FindButton("Configure selected").parent.parent
        scroll:SetVerticalScroll(500)
        detailScroll:SetVerticalScroll(50)
        assert(RQ.MainWindow.Render())
        equal(#frames.widgets, count)
        equal(scroll:GetVerticalScroll(), 500)
        equal(detailScroll:GetVerticalScroll(), 50)
        click(frames, "Show: all")
        equal(#frames.widgets, count)
        assert(RQ.MainWindow.Open("bags"))
        equal(row:IsVisible(), false)
        assert(RQ.MainWindow.Open("roster"))
        equal(#rows(frames), 50)
    end)

    test("roster shows only members while Manage includes ignored and pending characters", function()
        local frames = start()
        member("Player-B", "Ignored")
        assert(RQ.Database.Register("ignore", "Player-B"))
        local pending = RQ.Util.Copy(RQ.Database.Current())
        pending.identity.guid, pending.identity.fullName = "Player-C", "Pending"
        pending.registration = "pending"
        RQDB.characters["Player-C"] = pending
        member("Player-D", "Disabled")
        RQDB.roster["Player-D"].enabled = false
        assert(RQ.MainWindow.Open("roster"))
        equal(#rows(frames), 2)
        for _, row in ipairs(rows(frames)) do
            assert(row.characterId == active or row.characterId == "Player-D")
        end
        click(frames, "Manage roster")
        equal(RQ.MainWindow.tab, "manage")
        equal(#RQ.MainWindow.view.characterIds, 4)
        RQ.MainWindow.selectedId = "Player-B"
        assert(RQ.MainWindow.Render())
        textVisible(frames, "[ignored]")
        equal(frames.FindButton("Add / resume").enabled, true)
        click(frames, "Next")
        equal(RQ.MainWindow.selectedId, "Player-C")
        textVisible(frames, "[pending]")
        click(frames, "Add / resume")
        equal(pending.registration, "member")
        click(frames, "Roster")
        equal(#rows(frames), 3)
    end)
end
