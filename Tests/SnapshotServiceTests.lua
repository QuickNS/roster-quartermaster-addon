return function(h)
    local test, equal = h.test, h.equal

    local function start()
        h.fakeCharacter()
        h.loadAddon()
        h.emit("PLAYER_LOGIN")
    end

    test("snapshots include account-wide progression, money, location, bags and numeric profession IDs", function()
        start()
        local record = RQDB.characters["Player-Test-1"]
        equal(record.registration, "pending")
        equal(record.snapshot.money, 12345)
        equal(record.snapshot.zone, "Test Zone")
        equal(record.snapshot.subZone, "Test Inn")
        equal(record.snapshot.bagSlots, 32)
        equal(record.snapshot.freeBagSlots, 10)
        equal(record.snapshot.professions[186].skill, 100)
        equal(record.snapshot.professions[185].skill, 20)
        equal(record.snapshot.sections.professions.complete, true)
        equal(record.snapshot.sections.professions.observedAt, 123456789)
        equal(record.inventory.bags.complete, false)
        equal(record.inventory.bank.complete, false)
        equal(record.inventory.mail.complete, false)
        equal(record.recipes.complete, false)
        RQCharDB.snapshot.professions[186].skill = 101
        equal(record.snapshot.professions[186].skill, 100)
    end)

    test("noisy events coalesce and only scan their affected sections", function()
        start()
        local counts = { bags = 0, money = 0, professions = 0, xp = 0 }
        RQ.Api.GetBagCapacity = function()
            counts.bags = counts.bags + 1
            return { bagSlots = 40, freeBagSlots = 20 }
        end
        RQ.Api.GetMoney = function()
            counts.money = counts.money + 1
            return 100
        end
        RQ.Api.GetProfessions = function()
            counts.professions = counts.professions + 1
            return {}
        end
        RQ.Api.GetCharacterProgression = function()
            counts.xp = counts.xp + 1
            return {}
        end
        for _ = 1, 10 do
            h.emit("BAG_UPDATE_DELAYED")
            h.emit("PLAYER_MONEY")
        end
        equal(h.timerCount(), 1)
        equal(counts.bags, 0)
        h.flushTimers()
        equal(counts.bags, 1)
        equal(counts.money, 1)
        equal(counts.professions, 0)
        equal(counts.xp, 0)
        equal(RQCharDB.snapshot.freeBagSlots, 20)
        equal(RQCharDB.snapshot.money, 100)
    end)

    test("unit XP events filter other units and level-up waits for current API state", function()
        start()
        h.emit("PLAYER_XP_UPDATE", "pet")
        equal(h.timerCount(), 0)
        h.emit("PLAYER_LEVEL_UP", 26)
        _G.UnitLevel = function()
            return 26
        end
        _G.UnitXP = function()
            return 10
        end
        _G.GetXPExhaustion = function()
            return 0
        end
        h.flushTimers()
        equal(RQCharDB.snapshot.level, 26)
        equal(RQCharDB.snapshot.xp, 10)
        equal(RQCharDB.snapshot.restedXp, 0)
    end)

    test("failed APIs retain old values and timestamps while marking the section incomplete", function()
        start()
        _G.GetServerTime = function()
            return 123456800
        end
        _G.GetMoney = function()
            error("restricted money")
        end
        _G.GetProfessions = nil
        _G.UnitXP = function()
            return 14000
        end
        _G.UnitLevel = nil
        assert(RQ.SnapshotService.Refresh())
        equal(RQCharDB.snapshot.money, 12345)
        equal(RQCharDB.snapshot.sections.money.observedAt, 123456789)
        equal(RQCharDB.snapshot.sections.money.attemptedAt, 123456800)
        equal(RQCharDB.snapshot.sections.money.complete, false)
        equal(RQCharDB.snapshot.professions[186].skill, 100)
        equal(RQCharDB.snapshot.sections.professions.complete, false)
        equal(RQCharDB.snapshot.level, 25)
        equal(RQCharDB.snapshot.xp, 14000)
        equal(RQCharDB.snapshot.sections.progression.complete, false)
        equal(RQCharDB.snapshot.lastSeen, 123456800)
        h.contains(RQ.Diagnostics.Report(), "Snapshot money: INCOMPLETE")
    end)

    test("successful empty profession scan clears old professions; failure does not", function()
        start()
        _G.GetProfessions = function()
            return nil
        end
        h.emit("SKILL_LINES_CHANGED")
        h.flushTimers()
        equal(next(RQCharDB.snapshot.professions), nil)
        equal(RQCharDB.snapshot.sections.professions.complete, true)
    end)

    test("modern container APIs are supported without counting bank or absent bags", function()
        start()
        local scanned = {}
        _G.NUM_TOTAL_EQUIPPED_BAG_SLOTS = 5
        _G.C_Container = {
            GetContainerNumSlots = function(bag)
                assert(bag >= 0 and bag <= 5)
                scanned[bag] = true
                return bag == 5 and 10 or 0
            end,
            GetContainerNumFreeSlots = function(bag)
                equal(bag, 5)
                return 3
            end,
        }
        local capacity = RQ.Api.GetBagCapacity()
        equal(capacity.bagSlots, 10)
        equal(capacity.freeBagSlots, 3)
        equal(#RQ.Util.Keys(scanned), 6)
        _G.C_Container.GetContainerNumFreeSlots = function()
            return 11
        end
        equal(RQ.Api.GetBagCapacity(), nil)
        _G.NUM_TOTAL_EQUIPPED_BAG_SLOTS = "bad"
        equal(RQ.Api.GetBagCapacity(), nil)
    end)

    test("profession scans reject missing IDs and restricted return values", function()
        start()
        _G.GetProfessionInfo = function()
            return "Mining", 0, 10, 75
        end
        equal(RQ.Api.GetProfessions(), nil)
        equal(RQ.Api.GetCapabilities().GetProfessionInfo, "invalid profession data or missing skill-line ID")
        local secret = {}
        _G.GetProfessions = function()
            return secret
        end
        _G.issecretvalue = function(value)
            return value == secret
        end
        equal(RQ.Api.GetProfessions(), nil)
        equal(RQ.Api.GetCapabilities().GetProfessions, "restricted value")
    end)

    test("resting, zone and profession events update on their next flush", function()
        start()
        _G.IsResting = function()
            return true
        end
        _G.GetZoneText = function()
            return "Capital"
        end
        _G.GetProfessionInfo = function()
            return "Mining", 0, 125, 150, 0, 0, 186
        end
        h.emit("PLAYER_UPDATE_RESTING")
        h.emit("ZONE_CHANGED_NEW_AREA")
        h.emit("TRADE_SKILL_LIST_UPDATE")
        h.flushTimers()
        equal(RQCharDB.snapshot.wasResting, true)
        equal(RQCharDB.snapshot.zone, "Capital")
        equal(RQCharDB.snapshot.professions[186].skill, 125)
    end)

    test("logout captures pending state and invalidates delayed callbacks", function()
        start()
        _G.GetMoney = function()
            return 99999
        end
        _G.IsResting = function()
            return true
        end
        _G.GetServerTime = function()
            return 123456900
        end
        h.emit("PLAYER_MONEY")
        h.emit("PLAYER_LOGOUT")
        equal(RQCharDB.snapshot.money, 99999)
        equal(RQCharDB.snapshot.wasResting, true)
        equal(RQCharDB.snapshot.lastLogout, 123456900)
        _G.GetMoney = function()
            error("callback must not scan after logout")
        end
        h.flushTimers()
        equal(RQ.Api.GetCapabilities().GetMoney, "available")
    end)

    test("rescan invalidates old timers without losing subsequent event updates", function()
        start()
        h.emit("PLAYER_MONEY")
        assert(RQ.SnapshotService.Refresh())
        _G.GetMoney = function()
            return 555
        end
        h.emit("PLAYER_MONEY")
        h.flushTimers()
        equal(RQCharDB.snapshot.money, 555)
    end)

    test("missing timer degrades to immediate updates with one visible warning", function()
        start()
        _G.C_Timer = nil
        _G.GetMoney = function()
            return 0
        end
        h.emit("PLAYER_MONEY")
        h.emit("PLAYER_MONEY")
        equal(RQCharDB.snapshot.money, 0)
        local warnings = 0
        for _, message in ipairs(h.messages()) do
            if message:find("without debouncing", 1, true) then
                warnings = warnings + 1
            end
        end
        equal(warnings, 1)
    end)

    test("freshness threshold and clock failures are explicit", function()
        h.loadAddon()
        equal(RQ.Snapshot.Freshness({ lastSeen = 100 }, 100 + 48 * 3600 - 1, 48), "RECENT")
        equal(RQ.Snapshot.Freshness({ lastSeen = 100 }, 100 + 48 * 3600, 48), "STALE")
        equal(RQ.Snapshot.Freshness({}, 100, 48), "UNKNOWN")
        equal(RQ.Snapshot.Freshness({ lastSeen = 100 }, nil, 48), "UNKNOWN")
        equal(RQ.Snapshot.Freshness({ lastSeen = 100 }, 99, 48), "CLOCK MISMATCH")
    end)

    test("missing clock never fabricates fresh section timestamps", function()
        start()
        _G.GetServerTime = nil
        assert(RQ.SnapshotService.Refresh())
        equal(RQCharDB.snapshot.sections.money.observedAt, nil)
        equal(RQCharDB.snapshot.sections.money.attemptedAt, nil)
        h.emit("PLAYER_LOGOUT")
        equal(RQCharDB.snapshot.lastLogout, nil)
    end)
end
