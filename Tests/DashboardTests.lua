return function(h)
    local test, equal, contains = h.test, h.equal, h.contains
    local nativeFrames = assert(loadfile("Tests/fixtures/Frames.lua"))()

    local function start(native, skipped)
        h.fakeCharacter()
        local frames = native and nativeFrames()
        h.loadAddon(skipped)
        if frames then
            frames.Emit("PLAYER_LOGIN")
        else
            h.emit("PLAYER_LOGIN")
        end
        return frames
    end

    local function secondCharacter()
        local record = RQ.Util.Copy(RQ.Database.Current())
        record.identity = { guid = "Player-Second", displayName = "Second", realm = "OtherRealm", class = "PRIEST" }
        record.registration = "pending"
        RQDB.characters["Player-Second"] = record
        return record
    end

    test("schema two upgrades without mutating links, settings or source tables", function()
        start()
        assert(RQ.Database.Register("link", "warrior"))
        RQDB.schemaVersion, RQCharDB.schemaVersion = 2, 2
        RQDB.settings.window = nil
        RQDB.settings.custom = { value = 42 }
        local oldAccount = RQDB
        local account, character, err = RQ.Migrations.Prepare(RQDB, RQCharDB)
        assert(account and character, err)
        equal(account.schemaVersion, 5)
        equal(character.schemaVersion, 5)
        equal(account.roster["Player-Test-1"].slotId, "warrior")
        equal(account.plannedRoster.warrior.claimedBy, "Player-Test-1")
        equal(account.settings.window.point, "CENTER")
        equal(oldAccount.settings.window, nil)
        equal(oldAccount.schemaVersion, 2)
        account.settings.custom.value = 43
        equal(oldAccount.settings.custom.value, 42)
        account.settings.window = { point = "TOPLEFT", relativePoint = "TOPLEFT", x = -200, y = -100 }
        local nextAccount = RQ.Migrations.Prepare(account, character)
        equal(nextAccount.settings.window.x, -200)
    end)

    test("invalid window positions reject migration and keep saved positions untouched", function()
        start()
        for _, position in ipairs({
            false,
            { x = "bad" },
            { x = math.huge },
            { y = 0 / 0 },
            { point = "INVALID" },
        }) do
            local input = { schemaVersion = 2, settings = { window = position } }
            local account, _, err = RQ.Migrations.Prepare(input, nil)
            equal(account, nil)
            assert(err:find("window", 1, true))
            equal(input.schemaVersion, 2)
        end
        local previous = RQDB.settings.window
        equal(RQ.Database.SaveWindowPosition({ x = 0 }), false)
        equal(RQDB.settings.window, previous)
        assert(RQ.Database.SaveWindowPosition({ point = "BOTTOMRIGHT", relativePoint = "CENTER", x = -10, y = 20 }))
    end)

    test("partial roster entries without snapshots remain configurable with unknown observations", function()
        RQDB = {
            schemaVersion = 2,
            roster = {
                ["Player-Old"] = { displayName = "Old", role = "TANK", isMain = true },
            },
        }
        h.loadAddon()
        assert(RQ.Database.Initialize())
        local record = RQDB.characters["Player-Old"]
        equal(record.registration, "member")
        equal(record.snapshot.level, nil)
        equal(record.snapshot.lastSeen, nil)
        equal(RQDB.roster["Player-Old"].enabled, true)
        assert(RQ.Database.SetRole("Player-Old", "HEALER"))
        local view = RQ.RosterPanel.Build(RQDB, nil, 100)
        equal(view.selectedId, "Player-Old")
        contains({ view.cards[1].body }, "UNKNOWN")
    end)

    test("snapshot ages display time units without treating unknown times as current", function()
        h.loadAddon()
        equal(RQ.CharacterCard.Age(nil, 100), "Unknown")
        equal(RQ.CharacterCard.Age(0, 100), "Unknown")
        equal(RQ.CharacterCard.Age(101, 100), "Clock mismatch")
        equal(RQ.CharacterCard.Age(100, 159), "59s ago")
        equal(RQ.CharacterCard.Age(100, 160), "1m ago")
        equal(RQ.CharacterCard.Age(100, 3700), "1h ago")
        equal(RQ.CharacterCard.Age(100, 86500), "1d ago")
    end)

    test("only one main is selected and later links cannot reclaim the old default", function()
        start()
        assert(RQ.Database.Register("link", "warrior"))
        secondCharacter()
        assert(RQ.Database.Register("add", nil, "Player-Second"))
        assert(RQ.Database.SetMain("Player-Second"))
        equal(RQDB.roster["Player-Test-1"].isMain, false)
        equal(RQDB.roster["Player-Second"].isMain, true)
        equal(RQDB.plannedRoster.warrior.isMain, false)
        assert(RQ.Database.Register("link", "warrior"))
        equal(RQDB.roster["Player-Test-1"].isMain, false)
        assert(RQ.Database.Register("ignore", nil, "Player-Second"))
        equal(RQDB.roster["Player-Second"].isMain, false)
        equal(RQ.Database.SetMain("Player-Second"), false)
        assert(RQ.Database.Register("add", nil, "Player-Second"))
        equal(RQDB.roster["Player-Second"].isMain, false)
    end)

    test("roles and explicit unlink/relink preserve GUID snapshots and main choice", function()
        start()
        assert(RQ.Database.Register("link", "warrior"))
        assert(RQ.Database.SetRole("Player-Test-1", "FLEX"))
        equal(RQDB.roster["Player-Test-1"].role, "FLEX")
        equal(RQDB.plannedRoster.warrior.role, "FLEX")
        equal(RQ.Database.SetRole("Player-Test-1", "invalid"), false)
        equal(RQ.Database.SetRole("missing", "TANK"), false)
        local snapshot = RQ.Database.Current().snapshot
        assert(RQ.Database.Unlink("Player-Test-1"))
        equal(RQDB.plannedRoster.warrior.claimedBy, nil)
        equal(RQDB.plannedRoster.warrior.isMain, false)
        equal(RQDB.roster["Player-Test-1"].isMain, true)
        assert(RQ.Database.Register("link", "druid"))
        equal(RQDB.roster["Player-Test-1"].isMain, true)
        equal(RQDB.plannedRoster.druid.isMain, true)
        equal(RQDB.roster["Player-Test-1"].slotId, "druid")
        equal(RQ.Database.Current().snapshot, snapshot)
    end)

    test("offline registration and ignore never scan or replace the active character", function()
        start()
        local offline = secondCharacter()
        local before = RQ.Util.Copy(offline.snapshot)
        RQ.Api.GetCharacterProgression = function()
            error("must not capture an offline character")
        end
        assert(RQ.SnapshotService.Register("link", "priest", "Player-Second"))
        assert(RQ.Database.SetRole("Player-Second", "HEALER"))
        equal(offline.snapshot.lastSeen, before.lastSeen)
        equal(offline.snapshot.level, before.level)
        equal(RQ.Database.activeId, "Player-Test-1")
        equal(RQCharDB.identity.guid, "Player-Test-1")
        assert(RQ.SnapshotService.Register("ignore", nil, "Player-Second"))
        equal(offline.registration, "ignored")
        equal(RQDB.plannedRoster.priest.claimedBy, "Player-Second")
    end)

    test("cards expose actual and planned state without fabricating offline rested estimates", function()
        start()
        assert(RQ.Database.Register("link", "warrior"))
        local offline = secondCharacter()
        offline.registration = "ignored"
        offline.snapshot.lastSeen = 1
        offline.snapshot.sections.money.complete = false
        local view = RQ.RosterPanel.Build(RQDB, RQ.Database.activeId, 123456789)
        equal(#view.cards, 6)
        local card
        for _, entry in ipairs(view.cards) do
            if entry.id == "Player-Second" then
                card = entry
            end
        end
        contains({ card.body }, "Registration: ignored")
        contains({ card.body }, "STALE")
        contains({ card.body }, "last observed offline; not an estimate")
        contains({ card.body }, "money")
        local empty = RQ.CharacterCard.Build(
            "unknown",
            { identity = {}, snapshot = {}, registration = "pending" },
            nil,
            nil,
            nil,
            48
        )
        contains({ empty.body }, "Rested XP: Unknown")
        contains({ empty.body }, "UNKNOWN")
    end)

    test("hidden dashboards are not constructed or rebuilt on snapshot changes", function()
        start()
        local calls = 0
        RQ.Api.RenderRosterWindow = function()
            calls = calls + 1
            return true
        end
        assert(RQ.SnapshotService.Refresh())
        h.flushTimers()
        equal(calls, 0)
        equal(RQ.Api.IsRosterWindowShown(), false)
    end)

    test("minimap click toggles the native dashboard and provides a tooltip", function()
        local frames = start(true)
        local button = frames.MinimapButton()
        equal(RQ.Api.IsRosterWindowShown(), false)
        button.scripts.OnEnter(button)
        equal(_G.GameTooltip.text, "Roster Quartermaster")
        equal(_G.GameTooltip.shown, true)
        contains(_G.GameTooltip.lines, "Click to open or close")
        button.scripts.OnLeave(button)
        equal(_G.GameTooltip.shown, false)
        frames.Click(button)
        equal(RQ.Api.IsRosterWindowShown(), true)
        frames.Click(button)
        equal(RQ.Api.IsRosterWindowShown(), false)
        frames.Emit("PLAYER_ENTERING_WORLD")
        local count = 0
        for _, widget in ipairs(frames.widgets) do
            if widget.kind == "Button" and widget.parent == _G.Minimap then
                count = count + 1
            end
        end
        equal(count, 1)
    end)

    test("missing tooltip does not break the minimap launcher", function()
        local frames = start(true)
        _G.GameTooltip = nil
        local button = frames.MinimapButton()
        button.scripts.OnEnter(button)
        button.scripts.OnLeave(button)
        equal(RQ.Api.GetCapabilities().minimapTooltip, "missing GameTooltip")
        frames.Click(button)
        equal(RQ.Api.IsRosterWindowShown(), true)
    end)

    test("failed minimap construction is bounded and still allows slash dashboard access", function()
        h.fakeCharacter()
        local frames = nativeFrames()
        local create = _G.CreateFrame
        local attempts = 0
        _G.CreateFrame = function(kind, name, parent, template)
            if parent == _G.Minimap then
                attempts = attempts + 1
                error("minimap buttons unavailable")
            end
            return create(kind, name, parent, template)
        end
        h.loadAddon()
        frames.Emit("PLAYER_LOGIN")
        frames.Emit("PLAYER_ENTERING_WORLD")
        frames.Emit("PLAYER_ENTERING_WORLD")
        equal(attempts, 1)
        contains(h.messages(), "Minimap button unavailable")
        _G.SlashCmdList.ROSTERQUARTERMASTER("roster")
        equal(RQ.Api.IsRosterWindowShown(), true)
    end)

    test("visible dashboard refresh coalesces notifications and stops rendering when closed", function()
        local frames = start(true)
        frames.Click(frames.MinimapButton())
        local build = RQ.RosterPanel.Build
        local count = 0
        RQ.RosterPanel.Build = function(...)
            count = count + 1
            return build(...)
        end
        for _ = 1, 10 do
            RQ.Database.NotifyChanged()
        end
        equal(count, 0)
        equal(h.timerCount(), 1)
        h.flushTimers()
        equal(count, 1)
        RQ.Api.HideRosterWindow()
        RQ.Database.NotifyChanged()
        h.flushTimers()
        equal(count, 1)
    end)

    test("dashboard has scrollable cards, an escape registration and working close button", function()
        local frames = start(true)
        _G.SlashCmdList.ROSTERQUARTERMASTER("roster")
        equal(RQ.Api.IsRosterWindowShown(), true)
        contains(_G.UISpecialFrames, "RQMainWindow")
        local scroll = frames.FindKind("ScrollFrame")
        assert(scroll.scrollChild:GetHeight() > scroll:GetHeight())
        scroll.scripts.OnMouseWheel(scroll, -1000)
        equal(scroll:GetVerticalScroll(), scroll.scrollChild:GetHeight() - scroll:GetHeight())
        scroll.scripts.OnMouseWheel(scroll, 1000)
        equal(scroll:GetVerticalScroll(), 0)
        frames.Click(frames.FindButton("Close"))
        equal(RQ.Api.IsRosterWindowShown(), false)
    end)

    test("native drag stop saves a normalized position and reset restores the center", function()
        local frames = start(true)
        frames.Click(frames.MinimapButton())
        local window = _G.RQMainWindow
        window.scripts.OnDragStart(window)
        equal(window.moving, true)
        window:ClearAllPoints()
        window:SetPoint("TOPLEFT", _G.UIParent, "TOPLEFT", -120, -80)
        window.scripts.OnDragStop(window)
        equal(window.moving, false)
        equal(RQDB.settings.window.point, "TOPLEFT")
        equal(RQDB.settings.window.x, -120)
        equal(RQDB.settings.window.y, -80)
        local account = RQ.Migrations.Prepare(RQDB, RQCharDB)
        equal(account.settings.window.x, -120)
        _G.SlashCmdList.ROSTERQUARTERMASTER("reset-window")
        equal(RQDB.settings.window.point, "CENTER")
        equal(window.points[1][1], "CENTER")
    end)

    test("native window initially restores the saved anchor", function()
        RQDB = {
            schemaVersion = 2,
            settings = {
                window = { point = "TOPRIGHT", relativePoint = "TOPRIGHT", x = -66, y = -77 },
            },
        }
        local frames = start(true)
        frames.Click(frames.MinimapButton())
        equal(_G.RQMainWindow.points[1][1], "TOPRIGHT")
        equal(_G.RQMainWindow.points[1][4], -66)
        equal(_G.RQMainWindow.points[1][5], -77)
    end)

    test("settings buttons link, edit, set main and role, ignore and resume", function()
        local frames = start(true)
        _G.SlashCmdList.ROSTERQUARTERMASTER("settings")
        frames.Click(frames.FindButton("Link selected character"))
        h.flushTimers()
        equal(RQDB.roster["Player-Test-1"].slotId, "druid")
        frames.Click(frames.FindButton("Make main"))
        h.flushTimers()
        equal(RQDB.roster["Player-Test-1"].isMain, true)
        frames.Click(frames.FindButton("Role: Flexible (next)"))
        h.flushTimers()
        equal(RQDB.roster["Player-Test-1"].role, "UNASSIGNED")
        local edit = frames.FindKind("EditBox")
        edit:SetText("Luna Tick")
        edit.scripts.OnEnterPressed(edit)
        h.flushTimers()
        equal(RQDB.plannedRoster.druid.plannedName, "Luna Tick")
        frames.Click(frames.FindButton("Ignore"))
        h.flushTimers()
        equal(RQ.Database.Current().registration, "ignored")
        equal(frames.FindButton("Make main").enabled, false)
        frames.Click(frames.FindButton("Add / resume"))
        h.flushTimers()
        equal(RQ.Database.Current().registration, "member")
        frames.Click(frames.FindButton("Unlink slot"))
        h.flushTimers()
        equal(RQDB.plannedRoster.druid.claimedBy, nil)
    end)

    test("live refresh preserves focused name drafts and selected slot changes reset them", function()
        local frames = start(true)
        _G.SlashCmdList.ROSTERQUARTERMASTER("settings")
        local edit = frames.FindKind("EditBox")
        edit:SetFocus()
        edit:SetText("Unsaved draft")
        assert(RQ.SnapshotService.Refresh())
        h.flushTimers()
        equal(edit:GetText(), "Unsaved draft")
        frames.Click(frames.FindButton("Next", 2))
        h.flushTimers()
        equal(edit:GetText(), "Miss Tombsie")
        equal(RQDB.plannedRoster.druid.plannedName, "Kit Cat")
        edit.scripts.OnEscapePressed(edit)
        equal(RQ.Api.IsRosterWindowShown(), false)
    end)

    test("configure buttons target their own offline card rather than the active character", function()
        local frames = start(true)
        local offline = secondCharacter()
        _G.SlashCmdList.ROSTERQUARTERMASTER("roster")
        local button = frames.FindButton("Configure")
        equal(button.parent.characterId, "Player-Second")
        frames.Click(button)
        equal(RQ.MainWindow.selectedId, "Player-Second")
        frames.Click(frames.FindButton("Add / resume"))
        h.flushTimers()
        equal(offline.registration, "member")
        equal(RQ.Database.Current().registration, "pending")
        frames.Click(frames.FindButton("Make main"))
        h.flushTimers()
        equal(RQDB.roster["Player-Second"].isMain, true)
        equal(RQCharDB.identity.guid, "Player-Test-1")
    end)

    test("combat hides the dashboard and blocks minimap popups without reopening automatically", function()
        local frames = start(true)
        assert(RQ.Database.Register("add"))
        frames.Click(frames.MinimapButton())
        frames.combat = true
        frames.Emit("PLAYER_REGEN_DISABLED")
        equal(RQ.Api.IsRosterWindowShown(), false)
        frames.Click(frames.MinimapButton())
        equal(RQ.Api.IsRosterWindowShown(), false)
        contains(h.messages(), "Dashboard not opened")
        frames.combat = false
        frames.Emit("PLAYER_REGEN_ENABLED")
        equal(RQ.Api.IsRosterWindowShown(), false)
        _G.InCombatLockdown = nil
        frames.Click(frames.MinimapButton())
        equal(RQ.Api.IsRosterWindowShown(), false)
    end)

    test("missing dashboard module leaves minimap clicks and slash text fallback usable", function()
        local frames = start(true, "UI/MainWindow.lua")
        frames.Click(frames.MinimapButton())
        contains(h.messages(), "Dashboard module did not load")
        contains(h.messages(), "No recommendation")
        _G.SlashCmdList.ROSTERQUARTERMASTER("role HEALER")
        contains(h.messages(), "Select a registered")
        _G.SlashCmdList.ROSTERQUARTERMASTER("add")
        _G.SlashCmdList.ROSTERQUARTERMASTER("role HEALER")
        _G.SlashCmdList.ROSTERQUARTERMASTER("main")
        equal(RQDB.roster["Player-Test-1"].role, "HEALER")
        equal(RQDB.roster["Player-Test-1"].isMain, true)
        _G.SlashCmdList.ROSTERQUARTERMASTER("roster text")
        contains(h.messages(), "1 tracked character(s)")
    end)

    test("unsupported native window APIs report failure and keep text commands available", function()
        local frames = start(true)
        local create = _G.CreateFrame
        _G.CreateFrame = function(kind, name, parent, template)
            if kind == "ScrollFrame" then
                error("scroll template unavailable")
            end
            return create(kind, name, parent, template)
        end
        frames.Click(frames.MinimapButton())
        equal(RQ.Api.IsRosterWindowShown(), false)
        contains(h.messages(), "Dashboard unavailable:")
        contains(h.messages(), "No recommendation")
        _G.SlashCmdList.ROSTERQUARTERMASTER("link warrior")
        equal(RQDB.roster["Player-Test-1"].slotId, "warrior")
        contains(RQ.Diagnostics.Report(), "rosterWindow: error:")
    end)

    test("missing minimap does not prevent opening the dashboard by slash command", function()
        local frames = start(true)
        -- A fresh adapter simulates a client without the stock minimap.
        _G.Minimap = nil
        h.loadAddon()
        frames.Emit("PLAYER_LOGIN")
        _G.SlashCmdList.ROSTERQUARTERMASTER("roster")
        equal(RQ.Api.IsRosterWindowShown(), true)
        contains(RQ.Diagnostics.Report(), "minimapButton: missing Minimap")
    end)
end
