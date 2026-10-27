return function(h)
    local test, equal, contains = h.test, h.equal, h.contains
    local active, other = "Player-Test-1", "Player-Test-2"

    local function start()
        h.fakeCharacter()
        h.loadAddon()
        if not RQ.LogisticsPolicies then
            assert(loadfile("Core/LogisticsPolicies.lua"))()
        end
        -- Standalone testing also works before the parent adds these files to the TOC.
        if not RQ.ConfigTransfer then
            assert(loadfile("Core/ConfigTransfer.lua"))()
            assert(loadfile("Services/ConfigTransferService.lua"))()
        end
        h.emit("PLAYER_LOGIN")
        assert(RQ.Database.Register("add"))
        return assert(RQ.Database.Current())
    end

    local function config()
        return assert(RQ.ConfigTransfer.Extract(RQDB))
    end

    local function encode(value)
        return assert(RQ.ConfigTransfer.Encode(value))
    end

    local function preview(value)
        local ok, err, token = RQ.ConfigTransferService.Command("import", encode(value))
        assert(ok, err)
        return token
    end

    local function confirm(token)
        local ok, err = RQ.ConfigTransferService.Command("import-confirm", token)
        assert(ok, err)
    end

    local function envelope(payload)
        return "RQCFG1:" .. RQ.ConfigTransfer.Checksum(payload) .. ":" .. payload
    end

    local function stringToken(text)
        return "s"
            .. #text
            .. ":"
            .. (
                text:gsub(".", function(byte)
                    return string.format("%02x", byte:byte())
                end)
            )
    end

    local function rejects(text, expected)
        local value, err = RQ.ConfigTransfer.Decode(text)
        equal(value, nil)
        assert(type(err) == "string" and #err > 0)
        if expected then
            contains({ err }, expected)
        end
    end

    test("configuration exports deterministically with dynamic roster supplies and intent only", function()
        local record = start()
        assert(RQ.Database.Register("add"))
        assert(RQ.Database.SetMain(active))
        record.supplies.needs[2589] = 21
        record.supplies.goals[197] = { recipeId = 2963, targetSkill = 75 }
        record.professionIntent.planned[197] = true
        RQDB.roster[active].resourceBlocker = true
        RQDB.roster[active].dungeonReady = true
        RQDB.settings.planning.weights.stale = -7.25
        RQDB.settings.window.x = -37.5
        RQDB.settings.window.y = 1 / 3
        RQDB.session.secret = "session evidence"
        RQDB.mailTracking.privateMarker = "mail evidence"
        record.snapshot.privateMarker = "snapshot evidence"
        record.snapshot.activityMarker = "activity evidence"
        record.inventory.privateMarker = "inventory evidence"
        record.recipes.privateMarker = "recipe evidence"
        record.restedState.privateMarker = "rested evidence"
        record.supplies.history = { privateMarker = "not configuration" }
        local first = assert(RQ.ConfigTransfer.Export(RQDB))
        equal(first, assert(RQ.ConfigTransfer.Export(RQDB)))
        equal(first:find("[^%w:%.%-+]"), nil)
        local decoded = assert(RQ.ConfigTransfer.Decode(first))
        equal(encode(decoded), first)
        equal(decoded.settings.planning.weights.stale, -7.25)
        equal(decoded.settings.window.y, 1 / 3)
        equal(decoded.roster[active].isMain, true)
        equal(decoded.plannedRoster, nil)
        equal(decoded.roster[active].slotId, nil)
        equal(decoded.settings.gear, nil)
        equal(decoded.progress, nil)
        equal(decoded.roster[active].resourceBlocker, true)
        equal(decoded.roster[active].dungeonReady, true)
        equal(decoded.characters[active].supplies.needs[2589], 21)
        equal(decoded.characters[active].supplies.goals[197].recipeId, 2963)
        equal(decoded.characters[active].professionIntent.planned[197], true)
        equal(decoded.characters[active].supplies.history, nil)
        for _, field in ipairs({ "snapshot", "activity", "inventory", "recipes", "restedState" }) do
            equal(decoded.characters[active][field], nil)
        end
        equal(decoded.session, nil)
        equal(decoded.mailTracking, nil)
        local count = 0
        for _ in pairs(decoded.characters[active]) do
            count = count + 1
        end
        equal(count, 4)
    end)

    test("configuration string codec roundtrips Unicode quotes delimiters and numeric IDs", function()
        start()
        local value = config()
        local name = "Name " .. string.char(195, 169) .. " '\"\\:{[]}"
        value.characters[active].identity.fullName = name
        value.roster[active].fullName = name
        value.characters[active].supplies.needs[2147483647] = 1000000
        local decoded = assert(RQ.ConfigTransfer.Decode(encode(value)))
        equal(decoded.characters[active].identity.fullName, name)
        equal(decoded.characters[active].supplies.needs[2147483647], 1000000)
        equal(decoded.characters[active].supplies.needs["2147483647"], nil)
    end)

    test("configuration logistics roundtrip preserves recipient order and separate reserves", function()
        start()
        local value = config()
        value.characters[other] = RQ.Util.Copy(value.characters[active])
        value.characters[other].identity.guid = other
        value.characters[other].registration = "pending"
        local rule = value.settings.logistics.categories.herbs
        rule.items[2447] = true
        rule.recipients = { other, active }
        local supplies = value.characters[active].supplies
        supplies.needs[858] = 3
        supplies.reserves = { potions = { [858] = 7 }, bandages = { [1251] = 9 } }
        local decoded = assert(RQ.ConfigTransfer.Decode(encode(value)))
        equal(decoded.settings.logistics.categories.herbs.recipients[1], other)
        equal(decoded.settings.logistics.categories.herbs.recipients[2], active)
        equal(decoded.characters[active].supplies.needs[858], 3)
        equal(decoded.characters[active].supplies.reserves.potions[858], 7)
        equal(decoded.characters[active].supplies.reserves.bandages[1251], 9)
        confirm(preview(value))
        equal(RQDB.settings.logistics.categories.herbs.recipients[1], other)
        equal(RQCharDB.supplies.reserves.bandages[1251], 9)
        assert(RQ.ConfigTransferService.Command("import-rollback"))
        equal(next(RQDB.settings.logistics.categories.herbs.items), nil)
        equal(next(RQCharDB.supplies.reserves.potions), nil)
    end)

    test("configuration logistics rejects ambiguous items malformed lists and dangling GUID references", function()
        start()
        for _, mutate in ipairs({
            function(value)
                value.settings.logistics.categories.herbs.recipients = { other }
            end,
            function(value)
                value.settings.logistics.categories.herbs.recipients = { active, active }
            end,
            function(value)
                value.settings.logistics.categories.herbs.recipients = { [2] = active }
            end,
            function(value)
                value.settings.logistics.categories.herbs.recipients = { "Renamed" }
            end,
            function(value)
                value.settings.logistics.categories.herbs.items[2447] = true
                value.settings.logistics.categories.food.items[2447] = true
            end,
            function(value)
                value.settings.logistics.categories.herbs.items[2447] = false
            end,
            function(value)
                value.characters[active].supplies.reserves.potions[858] = -1
            end,
            function(value)
                value.characters[active].supplies.reserves.bandages[1251] = 0.5
            end,
            function(value)
                value.characters[active].supplies.reserves.potions[858] = 1000001
            end,
            function(value)
                value.characters[active].supplies.reserves.potions[858] = 1
                value.characters[active].supplies.reserves.bandages[858] = 2
            end,
        }) do
            local value = config()
            mutate(value)
            local text, err = RQ.ConfigTransfer.Encode(value)
            equal(text, nil)
            assert(err)
        end
    end)

    test("configuration logistics and reserve edits invalidate pending confirmation", function()
        start()
        local token = preview(config())
        RQDB.settings.logistics = RQ.LogisticsPolicies.Defaults()
        RQDB.settings.logistics.categories.herbs.items[2447] = true
        local ok, err = RQ.ConfigTransferService.Command("import-confirm", token)
        equal(ok, false)
        contains({ err }, "changed since preview")
        token = preview(config())
        RQDB.characters[active].supplies.reserves.potions[858] = 2
        ok, err = RQ.ConfigTransferService.Command("import-confirm", token)
        equal(ok, false)
        contains({ err }, "changed since preview")
        token = preview(config())
        RQCharDB.supplies.reserves.bandages[1251] = 3
        ok, err = RQ.ConfigTransferService.Command("import-confirm", token)
        equal(ok, false)
        contains({ err }, "changed since preview")
    end)

    test("configuration rejects retired feature fields and previous schema exports", function()
        start()
        for _, mutate in ipairs({
            function(value)
                value.progress = {}
            end,
            function(value)
                value.plannedRoster = {}
            end,
            function(value)
                value.settings.gear = {}
            end,
            function(value)
                value.roster[active].slotId = "warrior"
            end,
            function(value)
                value.schemaVersion = 15
            end,
        }) do
            local value = config()
            mutate(value)
            local text, err = RQ.ConfigTransfer.Encode(value)
            equal(text, nil)
            assert(err)
        end
    end)

    test("configuration parser rejects executable malformed duplicate and unsupported data", function()
        start()
        local text = encode(config())
        rejects("return " .. text)
        rejects(envelope("return os.execute('untrusted')"), "unknown data tag")
        rejects(text:gsub("^RQCFG1:", "RQCFG2:"), "unsupported format")
        rejects(text .. "x", "checksum mismatch")
        rejects(text:sub(1, #text - 1), "checksum mismatch")
        rejects("RQCFG1:00000000:t0:", "checksum mismatch")
        rejects(envelope("t0:garbage"), "trailing data")
        rejects(envelope("t2:" .. stringToken("x") .. "b0" .. stringToken("x") .. "b1"), "duplicate")
        rejects(envelope("t1:b1b0"), "table key")
        rejects(envelope("t1:t0:b0"), "table key")
        rejects(envelope("s2:ff"), "truncated")
        rejects(envelope("s1:xx"), "string encoding")
        rejects(envelope("b2"), "boolean")
        rejects(envelope("t01:"), "length")
        rejects(envelope("n3:nan"), "number")
        rejects(envelope("n3:inf"), "number")
        rejects(envelope("n5:1e999"), "number")
        rejects(envelope("n4:0x10"), "noncanonical")
        rejects(envelope("n2:01"), "noncanonical")
        rejects(envelope("s-1:"), "length")
        rejects(false, "paste must")
        equal(RQ.ConfigTransfer.Checksum("Wikipedia"), "11e60398")
    end)

    test("configuration parser enforces exact byte depth node entry and string ceilings", function()
        start()
        local limits = RQ.ConfigTransfer.limits
        rejects(string.rep("x", limits.bytes + 1), "at most")
        rejects(envelope("s" .. (limits.string + 1) .. ":"), "length limit")
        rejects(envelope("t" .. (limits.entries + 1) .. ":"), "length limit")
        local deep = "t0:"
        for _ = 1, limits.depth do
            deep = "t1:" .. stringToken("x") .. deep
        end
        rejects(envelope(deep), "nesting")
        local function many(count)
            local entries = {}
            for index = 1, count do
                local number = tostring(index)
                entries[#entries + 1] = "n" .. #number .. ":" .. number .. "b0"
            end
            return "t" .. count .. ":" .. table.concat(entries)
        end
        local nodes = "t3:"
            .. stringToken("a")
            .. many(4096)
            .. stringToken("b")
            .. many(4096)
            .. stringToken("c")
            .. many(1808)
        rejects(envelope(nodes), "value limit")
        local value = config()
        value.roster[active].fullName = string.rep("x", limits.string)
        assert(RQ.ConfigTransfer.Decode(encode(value)))
        value.roster[active].fullName = string.rep("x", limits.string + 1)
        equal(RQ.ConfigTransfer.Encode(value), nil)
    end)

    test("configuration rejects unknown sections identifiers types cycles and unsafe markup", function()
        start()
        for _, mutate in ipairs({
            function(value)
                value.characters[active].snapshot = {}
            end,
            function(value)
                value.settings.activity = {}
            end,
            function(value)
                value.policies.mailTracking = {}
            end,
            function(value)
                value.schemaVersion = RQ.schemaVersion + 1
            end,
            function(value)
                value.characters[active].identity.guid = other
            end,
            function(value)
                value.characters["name:renamed-testrealmpve"] = value.characters[active]
            end,
            function(value)
                value.roster[active].guid = other
            end,
            function(value)
                value.roster[active].role = "INVALID"
            end,
            function(value)
                value.settings.window.x = 0 / 0
            end,
            function(value)
                value.settings.window.x = math.huge
            end,
            function(value)
                value.settings.window.x = function() end
            end,
            function(value)
                value.characters[active].supplies.needs["2589"] = 2
            end,
            function(value)
                value.characters[active].supplies.needs[0] = 2
            end,
            function(value)
                value.settings.planning.pinnedCharacterId = other
            end,
            function(value)
                value.characters[active].registration = "pending"
            end,
            function(value)
                value.characters[active].identity.fullName = "|Hitem:2589|h"
            end,
            function(value)
                value.characters[active].identity.fullName = "hello\nworld"
            end,
            function(value)
                value.settings.planning.weights = value
            end,
            function(value)
                setmetatable(value.settings, {})
            end,
        }) do
            local value = config()
            mutate(value)
            local encoded, err = RQ.ConfigTransfer.Encode(value)
            equal(encoded, nil)
            assert(err)
        end
        local text = encode(config())
        local payload = text:sub(17)
        payload = payload:gsub("^t(%d+):", function(count)
            return "t" .. (tonumber(count) + 1) .. ":"
        end, 1)
        rejects(envelope(payload .. stringToken("mailTracking") .. "t0:"), "unknown")
    end)

    test("configuration migration validation rejects malformed full candidates without publishing", function()
        start()
        local account, character = RQDB, RQCharDB
        for _, mutate in ipairs({
            function(value)
                value.characters[active].supplies.needs[2589] = -1
            end,
            function(value)
                value.characters[active].professionIntent.planned[999] = true
            end,
            function(value)
                value.settings.planning.innRate = 11
            end,
            function(value)
                value.settings.window.point = "INVALID"
            end,
        }) do
            local value = config()
            mutate(value)
            local ok, err = RQ.ConfigTransferService.Command("import", encode(value))
            equal(ok, false)
            assert(err)
            equal(RQDB, account)
            equal(RQCharDB, character)
        end
        local text = encode(config())
        RQCharDB.inventory.bags.items[2589] = -1
        local ok, err = RQ.ConfigTransferService.Command("import", text)
        equal(ok, false)
        contains({ err }, "Invalid item counts")
        equal(RQDB, account)
        equal(RQCharDB, character)
    end)

    test("configuration preview requires exact candidate token with no early changes", function()
        start()
        local value = config()
        value.settings.planning.maxLevel = 7
        value.characters[active].supplies.needs[2589] = 21
        value.characters[active].professionIntent.planned[197] = true
        local account, character, before = RQDB, RQCharDB, encode(config())
        local token = preview(value)
        equal(RQDB, account)
        equal(RQCharDB, character)
        equal(encode(config()), before)
        contains(h.messages(), "settings: 0 added, 1 changed, 0 removed")
        contains(h.messages(), "characters: 0 added, 1 changed, 0 removed")
        contains(h.messages(), "/rq import-confirm " .. token)
        equal(RQ.ConfigTransferService.Command("import-confirm", ""), false)
        equal(RQ.ConfigTransferService.Command("import-confirm", "wrong"), false)
        confirm(token)
        equal(RQDB.settings.planning.maxLevel, 7)
        equal(RQCharDB.supplies.needs[2589], 21)
        equal(RQCharDB.professionIntent.planned[197], true)
        assert(RQCharDB.supplies ~= RQDB.characters[active].supplies)
        equal(RQ.ConfigTransferService.Command("import-confirm", token), false)
    end)

    test("configuration confirmation invalidates stale config and superseded cancelled previews", function()
        start()
        local value = config()
        value.settings.planning.maxLevel = 7
        local first = preview(value)
        local second = preview(value)
        assert(first ~= second)
        equal(RQ.ConfigTransferService.Command("import-confirm", first), false)
        RQDB.settings.planning.maxLevel = 6
        local ok, err = RQ.ConfigTransferService.Command("import-confirm", second)
        equal(ok, false)
        contains({ err }, "changed since preview")
        equal(RQDB.settings.planning.maxLevel, 6)
        equal(RQ.ConfigTransferService.Command("import-confirm", second), false)
        local token = preview(value)
        assert(RQ.ConfigTransferService.Command("import-cancel"))
        equal(RQ.ConfigTransferService.Command("import-confirm", token), false)
        token = preview(value)
        equal(RQ.ConfigTransferService.Command("import", "broken"), false)
        equal(RQ.ConfigTransferService.Command("import-confirm", token), false)
    end)

    test("configuration confirmation revalidates both latest roots before atomic publication", function()
        start()
        local token = preview(config())
        RQCharDB.inventory.bags.items[2589] = -1
        local account, character = RQDB, RQCharDB
        local ok, err = RQ.ConfigTransferService.Command("import-confirm", token)
        equal(ok, false)
        contains({ err }, "Invalid item counts")
        equal(RQDB, account)
        equal(RQCharDB, character)
        equal(RQ.ConfigTransferService.Command("import-rollback"), false)
    end)

    test("configuration confirmation invalidates changed mirror configuration or active identity", function()
        start()
        local token = preview(config())
        RQCharDB.supplies.needs[2589] = 1
        local ok, err = RQ.ConfigTransferService.Command("import-confirm", token)
        equal(ok, false)
        contains({ err }, "changed since preview")
        token = preview(config())
        RQ.Database.activeId = other
        ok, err = RQ.ConfigTransferService.Command("import-confirm", token)
        equal(ok, false)
        contains({ err }, "changed since preview")
    end)

    test("configuration encoder enforces byte and character limits on actual exports", function()
        start()
        local value = config()
        for index = 1, 40 do
            local id = "Player-Size-" .. index
            value.characters[id] = RQ.Util.Copy(value.characters[active])
            value.characters[id].identity.guid = id
            value.characters[id].identity.fullName = string.rep("x", 4096)
            value.characters[id].registration = "pending"
        end
        local text, err = RQ.ConfigTransfer.Encode(value)
        equal(text, nil)
        contains({ err }, "encoded size")
        value = config()
        for index = 2, RQ.ConfigTransfer.limits.characters do
            local id = "Player-Limit-" .. index
            value.characters[id] = RQ.Util.Copy(value.characters[active])
            value.characters[id].identity.guid = id
            value.characters[id].registration = "pending"
        end
        assert(RQ.ConfigTransfer.Encode(value))
        value.characters[other] = RQ.Util.Copy(value.characters[active])
        value.characters[other].identity.guid = other
        value.characters[other].registration = "pending"
        text, err = RQ.ConfigTransfer.Encode(value)
        equal(text, nil)
        contains({ err }, "character limit")
    end)

    test("configuration import can restore a clean database and preserves local identity observations", function()
        start()
        assert(RQ.Database.Register("add"))
        local value = config()
        value.characters[active].supplies.needs[2589] = 17
        local originalName = RQDB.characters[active].identity.displayName
        value.characters[active].identity.displayName = "Imported old name"
        confirm(preview(value))
        equal(RQDB.characters[active].identity.displayName, originalName)
        local account, character = RQ.Migrations.Prepare(nil, nil)
        assert(account and character)
        local prepared, mirror, err = RQ.ConfigTransfer.Prepare(value, account, character, nil)
        assert(prepared and mirror, err)
        equal(prepared.characters[active].supplies.needs[2589], 17)
        equal(prepared.characters[active].snapshot.money, nil)
        equal(prepared.characters[active].inventory.bags.complete, false)
        equal(prepared.characters[active].identity.displayName, "Imported old name")
        equal(prepared.plannedRoster, nil)
        equal(prepared.roster[active].slotId, nil)
        equal(prepared.characters[active].registration, "member")
    end)

    test("configuration import and rollback retain observations collected before and after confirmation", function()
        start()
        local before, value = encode(config()), config()
        value.settings.planning.maxLevel = 9
        value.characters[active].supplies.needs[2589] = 30
        value.characters[other] = RQ.Util.Copy(value.characters[active])
        value.characters[other].identity.guid = other
        value.roster[other] = RQ.Util.Copy(value.roster[active])
        value.roster[other].guid = other
        local token = preview(value)
        RQDB.characters[active].snapshot.money = 111
        RQCharDB.snapshot.money = 111
        RQDB.characters[active].snapshot.activityMarker = "after preview"
        RQDB.mailTracking.privateMarker = "after preview"
        confirm(token)
        equal(RQDB.characters[active].snapshot.money, 111)
        equal(RQCharDB.snapshot.money, 111)
        equal(RQDB.characters[active].snapshot.activityMarker, "after preview")
        equal(RQDB.mailTracking.privateMarker, "after preview")
        equal(RQDB.characters[other].snapshot.money, nil)
        RQDB.characters[active].snapshot.money = 222
        RQCharDB.snapshot.money = 222
        RQDB.characters[active].snapshot.activityMarker = "after import"
        RQDB.characters[active].inventory.bags.items[2589] = 42
        RQDB.characters[active].recipes.privateMarker = "after import"
        RQDB.characters[active].restedState.privateMarker = "after import"
        RQDB.characters[other].snapshot.money = 333
        RQDB.mailTracking.privateMarker = "after import"
        RQDB.session.privateMarker = "after import"
        local ok, err = RQ.ConfigTransferService.Command("import-rollback")
        assert(ok, err)
        equal(RQDB.characters[active].snapshot.money, 222)
        equal(RQCharDB.snapshot.money, 222)
        equal(RQDB.characters[active].snapshot.activityMarker, "after import")
        equal(RQDB.characters[active].inventory.bags.items[2589], 42)
        equal(RQDB.characters[active].recipes.privateMarker, "after import")
        equal(RQDB.characters[active].restedState.privateMarker, "after import")
        equal(RQDB.mailTracking.privateMarker, "after import")
        equal(RQDB.session.privateMarker, "after import")
        equal(RQDB.characters[other].snapshot.money, 333)
        equal(RQDB.characters[other].registration, "pending")
        equal(next(RQDB.characters[other].supplies.needs), nil)
        equal(RQDB.roster[other], nil)
        local restored = config()
        restored.characters[other] = nil
        equal(encode(restored), before)
        equal(next(RQCharDB.supplies.needs), nil)
        equal(RQ.ConfigTransferService.Command("import-rollback"), false)
    end)

    test("configuration removal preserves known identities history and demotes omitted members", function()
        start()
        RQDB.characters[active].supplies.needs[2589] = 7
        local value = config()
        value.characters, value.roster = {}, {}
        confirm(preview(value))
        equal(RQDB.characters[active].registration, "pending")
        equal(RQDB.characters[active].identity.guid, active)
        equal(RQDB.characters[active].snapshot.money, 12345)
        equal(next(RQDB.characters[active].supplies.needs), nil)
        equal(next(RQCharDB.supplies.needs), nil)
        assert(RQ.ConfigTransferService.Command("import-rollback"))
        equal(RQDB.characters[active].registration, "member")
        equal(RQDB.characters[active].supplies.needs[2589], 7)
    end)

    test("configuration rollback retains only preceding import and logout clears all in-memory state", function()
        start()
        local value = config()
        value.settings.planning.maxLevel = 7
        confirm(preview(value))
        value.settings.planning.maxLevel = 9
        confirm(preview(value))
        local token = preview(value)
        assert(RQ.ConfigTransferService.Command("import-cancel"))
        assert(RQ.ConfigTransferService.Command("import-rollback"))
        equal(RQDB.settings.planning.maxLevel, 7)
        equal(RQ.ConfigTransferService.Command("import-confirm", token), false)
        confirm(preview(value))
        token = preview(value)
        RQ.ConfigTransferService.ClearPending()
        equal(RQ.ConfigTransferService.Command("import-confirm", token), false)
        equal(RQ.ConfigTransferService.Command("import-rollback"), false)
        equal(RQDB.settings.planning.maxLevel, 9)
    end)

    test("configuration service notifies resets continuity and reports export fallback and command errors", function()
        start()
        local calls, changes = 0, 0
        local copyAvailable = true
        local function showCopyWindow(title, text)
            equal(title, "RQ configuration export")
            assert(RQ.ConfigTransfer.Decode(text))
            calls = calls + 1
            return copyAvailable
        end
        RQ.Api.ShowCopyWindow = showCopyWindow
        local ok, err, text = RQ.ConfigTransferService.Command("export")
        assert(ok, err)
        assert(text)
        equal(calls, 1)
        copyAvailable = false
        assert(RQ.ConfigTransferService.Command("export"))
        contains(h.messages(), "Copy window unavailable")
        contains(h.messages(), text)
        RQ.Api.ShowCopyWindow = nil
        assert(RQ.ConfigTransferService.Command("export"))
        RQ.Database.onChanged = function()
            changes = changes + 1
        end
        confirm(preview(config()))
        equal(changes, 1)
        assert(RQ.ConfigTransferService.Command("import-rollback"))
        equal(changes, 2)
        equal(RQ.ConfigTransferService.Command("export", "unexpected"), false)
        equal(RQ.ConfigTransferService.Command("import", {}), false)
        equal(RQ.ConfigTransferService.Command("unknown"), false)
        RQ.Database.initialized = false
        equal(RQ.ConfigTransferService.Command("export"), false)
        equal(RQ.ConfigTransferService.Command("import", text), false)
    end)

    test("configuration empty import opens paste preview without publishing or confirming", function()
        start()
        local submitted
        local function showImport(title, text, callback)
            equal(title, "RQ configuration import")
            equal(text, "")
            equal(type(callback), "function")
            submitted = callback
            return true
        end
        RQ.Api.ShowCopyWindow = showImport
        local value = config()
        value.settings.planning.maxLevel = 7
        local previousToken = preview(value)
        assert(RQ.ConfigTransferService.Command("import"))
        equal(RQ.ConfigTransferService.Command("import-confirm", previousToken), false)
        local account, character = RQDB, RQCharDB
        submitted(encode(value))
        equal(RQDB, account)
        equal(RQCharDB, character)
        contains(h.messages(), "/rq import-confirm ")
        equal(RQDB.settings.planning.maxLevel, 60)
        submitted("invalid paste")
        contains(h.messages(), "Configuration import failed:")
        RQ.Api.ShowCopyWindow = nil
        local ok, err = RQ.ConfigTransferService.Command("import")
        equal(ok, false)
        contains({ err }, "Paste the complete export after /rq import")
    end)
end
