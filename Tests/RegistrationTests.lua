return function(h)
    local test, equal = h.test, h.equal

    local function start()
        h.fakeCharacter()
        h.loadAddon()
        h.emit("PLAYER_LOGIN")
    end

    local function changeCharacter(guid, name)
        RQCharDB = nil
        _G.UnitGUID = function()
            return guid
        end
        _G.UnitName = function()
            return name
        end
        h.loadAddon()
        h.emit("PLAYER_LOGIN")
    end

    test("slash registration works when the registration UI module did not load", function()
        h.fakeCharacter()
        h.loadAddon("UI/RegistrationPrompt.lua")
        assert(RQ.Database.Initialize())
        assert(RQ.SnapshotService.Refresh())
        equal(RQ.RegistrationPrompt, nil)
        _G.SlashCmdList.ROSTERQUARTERMASTER("add")
        equal(RQDB.roster["Player-Test-1"].enabled, true)
        equal(RQ.Database.Current().registration, "member")
        h.contains(h.messages(), "Roster registration saved")
        _G.SlashCmdList.ROSTERQUARTERMASTER("ignore")
        equal(RQ.Database.Current().registration, "ignored")
        _G.SlashCmdList.ROSTERQUARTERMASTER("add")
        equal(RQ.Database.Current().registration, "member")
        h.contains(RQ.Diagnostics.Report(), "Registration UI module: NOT LOADED")
    end)

    test("missing registration UI reports installation trouble without breaking login or rescan", function()
        h.fakeCharacter()
        h.loadAddon("UI/RegistrationPrompt.lua")
        h.emit("PLAYER_LOGIN")
        h.emit("PLAYER_ENTERING_WORLD")
        h.emit("PLAYER_REGEN_ENABLED")
        _G.SlashCmdList.ROSTERQUARTERMASTER("rescan")
        equal(RQ.Database.Current().registration, "pending")
        local function warnings()
            local count = 0
            for _, message in ipairs(h.messages()) do
                if message:find("UI/RegistrationPrompt.lua did not load", 1, true) then
                    count = count + 1
                end
            end
            return count
        end
        equal(warnings(), 1)
        _G.SlashCmdList.ROSTERQUARTERMASTER("register")
        equal(warnings(), 2)
        h.contains(h.messages(), "/rq add or /rq ignore")
        h.contains(h.messages(), "Snapshot refreshed")
    end)

    test("display names never cause automatic roster registration", function()
        h.fakeCharacter()
        _G.UnitName = function()
            return "Chop Suey"
        end
        h.loadAddon()
        h.emit("PLAYER_LOGIN")
        equal(RQ.Database.Current().registration, "pending")
        equal(next(RQDB.roster), nil)
        equal(RQDB.plannedRoster, nil)
        assert(RQ.Database.Register("add"))
        equal(RQDB.roster["Player-Test-1"].role, "UNASSIGNED")
        assert(not RQDB.roster["Player-Test-1"].isMain)
        assert(RQ.Database.SetMain("Player-Test-1"))
        assert(RQ.Database.SetRole("Player-Test-1", "TANK"))
        equal(RQDB.roster["Player-Test-1"].isMain, true)
        equal(RQDB.roster["Player-Test-1"].role, "TANK")
    end)

    test("five characters remain account-wide after sequential logins and explicit registration", function()
        start()
        assert(RQ.Database.Register("add"))
        for index = 1, 4 do
            changeCharacter("Player-Test-" .. (index + 1), "Character" .. (index + 1))
            assert(RQ.Database.Register("add"))
        end
        equal(#RQ.Util.Keys(RQDB.characters), 5)
        equal(#RQ.Util.Keys(RQDB.roster), 5)
        equal(RQDB.characters["Player-Test-1"].identity.displayName, "Renamed")
        equal(RQDB.characters["Player-Test-1"].snapshot.level, 25)
        RQ.Diagnostics.Roster()
        h.contains(h.messages(), "5 tracked character(s)")
    end)

    test("renaming a GUID character changes display identity without duplicates or configuration loss", function()
        start()
        assert(RQ.Database.Register("add"))
        assert(RQ.Database.SetRole("Player-Test-1", "TANK"))
        assert(RQ.Database.SetMain("Player-Test-1"))
        _G.UnitName = function()
            return "Newname"
        end
        assert(RQ.SnapshotService.Refresh())
        equal(#RQ.Util.Keys(RQDB.characters), 1)
        equal(#RQ.Util.Keys(RQDB.roster), 1)
        equal(RQDB.roster["Player-Test-1"].displayName, "Newname")
        equal(RQDB.roster["Player-Test-1"].isMain, true)
        equal(RQDB.characters["Player-Test-1"].identity.displayName, "Newname")
        h.loadAddon()
        h.emit("PLAYER_LOGIN")
        equal(RQ.Database.Current().registration, "member")
        equal(RQDB.roster["Player-Test-1"].role, "TANK")
    end)

    test("fallback IDs normalize realm and promote to GUID with membership intact", function()
        h.fakeCharacter()
        _G.UnitGUID = nil
        _G.UnitName = function()
            return " Example "
        end
        _G.GetRealmName = function()
            return "Test Realm PVE"
        end
        h.loadAddon()
        h.emit("PLAYER_LOGIN")
        equal(RQCharDB.characterId, "name:example-testrealmpve")
        assert(RQ.Database.Register("add"))
        assert(RQ.Database.SetMain("name:example-testrealmpve"))
        assert(RQ.Database.SetRole("name:example-testrealmpve", "TANK"))
        _G.UnitGUID = function()
            return "Player-New-GUID"
        end
        assert(RQ.SnapshotService.Refresh())
        equal(RQCharDB.characterId, "Player-New-GUID")
        equal(RQDB.characters["name:example-testrealmpve"], nil)
        equal(RQDB.roster["name:example-testrealmpve"], nil)
        equal(RQDB.roster["Player-New-GUID"].isMain, true)
        equal(RQDB.roster["Player-New-GUID"].role, "TANK")
        equal(#RQ.Util.Keys(RQDB.characters), 1)
        _G.UnitGUID = nil
        assert(RQ.SnapshotService.Refresh())
        equal(RQCharDB.characterId, "Player-New-GUID")
    end)

    test("same names on different realms remain different fallback characters", function()
        h.loadAddon()
        local one = RQ.Character.Id({ displayName = "Same", realm = "Realm One" })
        local two = RQ.Character.Id({ displayName = "Same", realm = "Realm Two" })
        assert(one ~= two)
        equal(RQ.Character.Id({ displayName = "Same" }), nil)
    end)

    test("lost current identity suspends queued capture until a successful rescan", function()
        start()
        h.emit("PLAYER_MONEY")
        _G.UnitGUID = nil
        _G.UnitName = nil
        _G.GetRealmName = nil
        local ok = RQ.SnapshotService.Refresh()
        equal(ok, false)
        equal(RQ.Database.Current(), nil)
        _G.GetMoney = function()
            return 555
        end
        h.flushTimers()
        h.emit("PLAYER_MONEY")
        equal(RQDB.characters["Player-Test-1"].snapshot.money, 12345)
        h.fakeCharacter()
        assert(RQ.SnapshotService.Refresh())
        equal(RQ.Database.Current().identity.guid, "Player-Test-1")
    end)

    test("empty identity API values are unknown rather than corrupt persisted metadata", function()
        h.fakeCharacter()
        _G.UnitName = function()
            return ""
        end
        _G.GetRealmName = function()
            return " "
        end
        _G.UnitRace = function()
            return ""
        end
        _G.UnitClass = function()
            return "", ""
        end
        h.loadAddon()
        h.emit("PLAYER_LOGIN")
        equal(RQCharDB.identity.displayName, nil)
        equal(RQCharDB.identity.class, nil)
        equal(RQCharDB.identity.race, nil)
        equal(RQCharDB.identity.realm, nil)
        assert(RQ.Database.Register("add"))
        local account, character, err = RQ.Migrations.Prepare(RQDB, RQCharDB)
        assert(account and character, err)
        equal(RQ.Api.GetCapabilities().UnitName, "empty identity value")
    end)

    test("mismatched legacy identity cannot donate snapshots or inventory to a new GUID", function()
        RQCharDB = {
            schemaVersion = 1,
            identity = { guid = "Player-Other", displayName = "Other", realm = "OtherRealm" },
            snapshot = { level = 60, money = 999999 },
            inventory = { bank = { scannedAt = 100, complete = true, items = { [2589] = 50 } } },
            recipes = { scannedAt = 100, complete = true, items = { [1] = true } },
        }
        h.fakeCharacter()
        _G.GetMoney = nil
        h.loadAddon()
        h.emit("PLAYER_LOGIN")
        equal(RQCharDB.snapshot.money, nil)
        equal(RQCharDB.inventory.bank.complete, false)
        equal(RQCharDB.inventory.bank.items[2589], nil)
        equal(RQCharDB.recipes.complete, false)
        equal(RQCharDB.recipes.items[1], nil)
    end)

    test("conflicting fallback and GUID records do not get silently merged", function()
        start()
        RQDB.characters["name:renamed-testrealmpve"] = RQ.Util.Copy(RQ.Database.Current())
        local old = RQDB.characters["name:renamed-testrealmpve"]
        local ok, err = RQ.SnapshotService.Refresh()
        equal(ok, false)
        assert(err:find("both exist", 1, true))
        equal(RQDB.characters["name:renamed-testrealmpve"], old)
        equal(#RQ.Util.Keys(RQDB.characters), 2)
    end)

    test("invalid registration actions and unknown characters do not change existing members", function()
        start()
        assert(RQ.Database.Register("add"))
        assert(RQ.Database.SetMain("Player-Test-1"))
        local entry = RQDB.roster["Player-Test-1"]
        equal(RQ.Database.Register("link", "Player-Test-1"), false)
        equal(RQ.Database.Register("add", "missing"), false)
        equal(RQ.Database.Register("ignore", "missing"), false)
        equal(RQDB.roster["Player-Test-1"], entry)
        equal(entry.isMain, true)
        changeCharacter("Player-Second", "Second")
        equal(RQ.Database.Register("invalid"), false)
        equal(RQ.Database.Current().registration, "pending")
        equal(RQDB.roster["Player-Second"], nil)
        assert(RQ.Database.Register("add"))
        assert(RQ.Database.Register("add"))
        equal(#RQ.Util.Keys(RQDB.roster), 2)
        equal(entry.isMain, true)
    end)

    test("ignoring cancels pending scans and survives reload until explicitly re-enabled", function()
        start()
        assert(RQ.RegistrationPrompt.Choose("add"))
        assert(RQ.Database.SetRole("Player-Test-1", "TANK"))
        h.emit("PLAYER_MONEY")
        assert(RQ.RegistrationPrompt.Choose("ignore"))
        _G.GetMoney = function()
            error("ignored characters must not scan")
        end
        h.flushTimers()
        h.emit("PLAYER_MONEY")
        h.emit("PLAYER_LOGOUT")
        equal(RQCharDB.snapshot.money, 12345)
        h.loadAddon()
        h.emit("PLAYER_LOGIN")
        equal(RQ.Database.Current().registration, "ignored")
        equal(RQDB.roster["Player-Test-1"].enabled, false)
        RQ.Diagnostics.Roster()
        h.contains(h.messages(), "0 tracked character(s)")
        _G.GetMoney = function()
            return 42
        end
        assert(RQ.RegistrationPrompt.Choose("add"))
        equal(RQ.Database.Current().registration, "member")
        equal(RQDB.roster["Player-Test-1"].enabled, true)
        equal(RQDB.roster["Player-Test-1"].role, "TANK")
        equal(RQCharDB.snapshot.money, 42)
    end)

    test("slash membership and role changes never change actual identity", function()
        start()
        _G.SlashCmdList.ROSTERQUARTERMASTER("add")
        _G.SlashCmdList.ROSTERQUARTERMASTER("role HEALER")
        _G.SlashCmdList.ROSTERQUARTERMASTER("main")
        equal(RQDB.roster["Player-Test-1"].role, "HEALER")
        equal(RQDB.roster["Player-Test-1"].isMain, true)
        equal(RQCharDB.identity.displayName, "Renamed")
        _G.SlashCmdList.ROSTERQUARTERMASTER("ignore")
        _G.SlashCmdList.ROSTERQUARTERMASTER("add")
        equal(RQDB.roster["Player-Test-1"].role, "HEALER")
        equal(RQCharDB.identity.displayName, "Renamed")
    end)

    test("stale offline snapshots remain visible with timestamps and uncertainty", function()
        start()
        assert(RQ.Database.Register("add"))
        changeCharacter("Player-Second", "Second")
        RQDB.characters["Player-Test-1"].snapshot.lastSeen = 1
        RQ.Diagnostics.Roster()
        h.contains(h.messages(), "Renamed - TestRealm PVE [member, STALE]")
        h.contains(h.messages(), "last seen: 1")
    end)

    test("registration UI defers in combat and exposes only add and ignore outside combat", function()
        start()
        local combat = true
        local created = {}
        local function widget()
            local object = { scripts = {} }
            function object:Hide()
                self.visible = false
            end
            function object:Show()
                self.visible = true
            end
            function object:SetText(text)
                self.text = text
            end
            function object:SetScript(name, fn)
                self.scripts[name] = fn
            end
            object.SetPoint = function() end
            object.SetFrameStrata = function() end
            object.EnableMouse = function() end
            object.SetAllPoints = function() end
            object.SetColorTexture = function() end
            object.SetWidth = function() end
            object.SetSize = function() end
            object.CreateTexture = widget
            object.CreateFontString = widget
            return object
        end
        _G.InCombatLockdown = function()
            return combat
        end
        _G.CreateFrame = function()
            local object = widget()
            created[#created + 1] = object
            return object
        end
        RQ.RegistrationPrompt.Show(true)
        equal(#created, 0)
        combat = false
        h.emit("PLAYER_REGEN_ENABLED")
        equal(#created, 3)
        local window = created[1]
        equal(window.visible, true)
        equal(window.buttons[1].text, "Add as new roster member")
        equal(window.buttons[2].text, "Ignore this character")
        equal(#window.buttons, 2)
        combat = true
        h.emit("PLAYER_REGEN_DISABLED")
        equal(window.visible, false)
        combat = false
        h.emit("PLAYER_REGEN_ENABLED")
        equal(window.visible, true)
        window.buttons[1].scripts.OnClick()
        equal(RQ.Database.Current().registration, "member")
        equal(window.visible, false)
    end)
end
