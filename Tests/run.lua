local tests = {}
local messages
local frame
local apiNames = {
    "GetBuildInfo",
    "UnitGUID",
    "UnitName",
    "GetRealmName",
    "UnitClass",
    "UnitRace",
    "UnitLevel",
    "UnitXP",
    "UnitXPMax",
    "GetXPExhaustion",
    "IsResting",
    "GetServerTime",
    "issecretvalue",
    "CreateFrame",
    "WOW_PROJECT_ID",
    "DEFAULT_CHAT_FRAME",
    "SlashCmdList",
    "SLASH_ROSTERQUARTERMASTER1",
}

local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function contains(lines, text)
    for _, line in ipairs(lines) do
        if line:find(text, 1, true) then
            return
        end
    end
    error("missing output: " .. text)
end

local function test(name, run)
    tests[#tests + 1] = { name = name, run = run }
end

local function loadAddon()
    local toc = assert(io.open("RosterQuartermaster.toc", "r"))
    local files = {}
    for line in toc:lines() do
        if line:match("%.lua$") then
            files[#files + 1] = line
        end
    end
    toc:close()
    assert(#files > 0, "TOC has no runtime files")
    for _, path in ipairs(files) do
        assert(loadfile(path))()
    end
end

local function reset()
    for _, name in ipairs(apiNames) do
        _G[name] = nil
    end
    RQ = nil
    RQDB = nil
    RQCharDB = nil
    messages = {}
    frame = { events = {} }
    function frame:SetScript(script, handler)
        equal(script, "OnEvent")
        self.handler = handler
    end
    function frame:RegisterEvent(event)
        self.events[event] = true
    end
    _G.CreateFrame = function(kind)
        equal(kind, "Frame")
        return frame
    end
    _G.DEFAULT_CHAT_FRAME = {
        AddMessage = function(_, message)
            messages[#messages + 1] = message
        end,
    }
    _G.SlashCmdList = {}
end

local function fakeCharacter()
    _G.GetBuildInfo = function()
        return "test-client", "12345", "test-date", 99999
    end
    _G.WOW_PROJECT_ID = 42
    _G.UnitGUID = function(unit)
        equal(unit, "player")
        return "Player-Test-1"
    end
    _G.UnitName = function()
        return "Renamed"
    end
    _G.GetRealmName = function()
        return "TestRealm"
    end
    _G.UnitClass = function()
        return "Warrior", "WARRIOR", 1
    end
    _G.UnitRace = function()
        return "Orc", "Orc", 2
    end
    _G.UnitLevel = function()
        return 25
    end
    _G.UnitXP = function()
        return 12000
    end
    _G.UnitXPMax = function()
        return 40000
    end
    _G.GetXPExhaustion = function()
        return 20000
    end
    _G.IsResting = function()
        return false
    end
    _G.GetServerTime = function()
        return 123456789
    end
end

local function emit(event, ...)
    assert(frame.events[event], "unregistered event: " .. event)
    frame.handler(frame, event, ...)
end

test("TOC load order, scoped initialization, login and logout", function()
    fakeCharacter()
    loadAddon()
    equal(_G.SLASH_ROSTERQUARTERMASTER1, "/rq")
    emit("ADDON_LOADED", "UnrelatedAddon")
    equal(RQDB, nil)
    emit("ADDON_LOADED", "RosterQuartermaster")
    equal(RQDB.schemaVersion, 1)
    equal(RQCharDB.schemaVersion, 1)
    emit("PLAYER_LOGIN")
    equal(RQCharDB.identity.guid, "Player-Test-1")
    equal(RQCharDB.identity.class, "WARRIOR")
    equal(RQCharDB.snapshot.level, 25)
    equal(RQCharDB.snapshot.xp, 12000)
    equal(RQCharDB.snapshot.xpMax, 40000)
    equal(RQCharDB.snapshot.restedXp, 20000)
    equal(RQCharDB.snapshot.wasResting, false)
    emit("PLAYER_LOGOUT")
    equal(RQCharDB.snapshot.lastLogout, 123456789)
    equal(RQ.Api.GetCapabilities()["event:PLAYER_LOGOUT"], "observed")
end)

test("diagnostics include observed build, snapshot and capability output", function()
    fakeCharacter()
    loadAddon()
    emit("PLAYER_LOGIN")
    _G.SlashCmdList.ROSTERQUARTERMASTER("  DIAG  ")
    contains(messages, "Interface: 99999; project ID: 42")
    contains(messages, "GUID: Player-Test-1")
    contains(messages, "Level: 25; XP: 12000/40000")
    contains(messages, "Rested XP (observed): 20000; resting: false")
    contains(messages, "Schemas: account=1; character=1")
    contains(messages, "Last saved observation (server timestamp): 123456789")
end)

test("missing APIs do not invent character state", function()
    loadAddon()
    emit("PLAYER_LOGIN")
    equal(RQCharDB.snapshot.level, nil)
    equal(RQCharDB.snapshot.restedXp, nil)
    equal(RQCharDB.snapshot.wasResting, nil)
    contains(RQ.Diagnostics.Report(), "UnitGUID: missing")
    contains(messages, "Rested XP (observed): unavailable; resting: unavailable")
end)

test("no rested XP differs from unavailable API", function()
    _G.GetXPExhaustion = function()
        return nil
    end
    loadAddon()
    equal(RQ.Api.GetRestedXP(), 0)
    _G.GetXPExhaustion = nil
    equal(RQ.Api.GetRestedXP(), nil)
end)

test("API errors and malformed numbers are explicitly diagnosed", function()
    fakeCharacter()
    _G.UnitXP = function()
        error("restricted in test")
    end
    _G.UnitLevel = function()
        return -1
    end
    _G.UnitXPMax = function()
        return 0 / 0
    end
    _G.GetXPExhaustion = function()
        return "unknown"
    end
    _G.IsResting = function()
        return 1
    end
    loadAddon()
    local _, snapshot = RQ.Diagnostics.Capture()
    equal(snapshot.xp, nil)
    equal(snapshot.level, nil)
    equal(snapshot.xpMax, nil)
    equal(snapshot.restedXp, nil)
    equal(snapshot.wasResting, nil)
    contains(RQ.Diagnostics.Report(), "UnitXP: error:")
    contains(messages, "UnitLevel: invalid numeric value")
    contains(messages, "IsResting: unexpected return type")
end)

test("restricted values are rejected before normalization", function()
    local secret = {}
    _G.UnitXP = function()
        return secret
    end
    _G.issecretvalue = function(value)
        return value == secret
    end
    loadAddon()
    equal(RQ.Api.GetCharacterProgression().xp, nil)
    equal(RQ.Api.GetCapabilities().UnitXP, "restricted value")
end)

test("partial SavedVariables retain custom values and initialization is idempotent", function()
    RQDB = { settings = { marker = "keep" }, custom = { enabled = true } }
    RQCharDB = { identity = { guid = "Player-Existing" }, custom = "keep" }
    loadAddon()
    assert(RQ.Database.Initialize())
    local account = RQDB
    local character = RQCharDB
    assert(RQ.Database.Initialize())
    equal(RQDB, account)
    equal(RQCharDB, character)
    equal(RQDB.settings.marker, "keep")
    equal(RQDB.custom.enabled, true)
    equal(RQCharDB.identity.guid, "Player-Existing")
    equal(RQCharDB.custom, "keep")
    emit("PLAYER_LOGIN")
    equal(RQCharDB.identity.guid, "Player-Existing")
end)

test("future schemas are preserved with writes disabled", function()
    local account = { schemaVersion = 999, settings = { marker = "keep" } }
    local character = { schemaVersion = 1, identity = {}, snapshot = { level = 50 } }
    RQDB = account
    RQCharDB = character
    fakeCharacter()
    loadAddon()
    emit("PLAYER_LOGIN")
    emit("PLAYER_LOGOUT")
    equal(RQ.Database.initialized, false)
    equal(RQDB, account)
    equal(RQCharDB, character)
    equal(RQCharDB.snapshot.level, 50)
    contains(messages, "unsupported schema; original data preserved")
    RQ.Diagnostics.Report()
end)

test("invalid roots and nested fields are not overwritten", function()
    for _, invalid in ipairs({ false, "corrupt", 42, { snapshot = "corrupt" } }) do
        RQDB = nil
        RQCharDB = invalid
        loadAddon()
        equal(RQ.Database.Initialize(), false)
        equal(RQDB, nil)
        equal(RQCharDB, invalid)
        RQ.Diagnostics.Report()
    end
end)

test("simulated reload retains settings and last logout", function()
    fakeCharacter()
    loadAddon()
    emit("PLAYER_LOGIN")
    RQDB.settings.marker = "keep"
    emit("PLAYER_LOGOUT")
    loadAddon()
    emit("ADDON_LOADED", "RosterQuartermaster")
    emit("PLAYER_LOGIN")
    equal(RQDB.settings.marker, "keep")
    equal(RQCharDB.snapshot.lastLogout, 123456789)
    equal(RQCharDB.identity.guid, "Player-Test-1")
end)

test("rescan updates the probe and does not claim unavailable storage worked", function()
    fakeCharacter()
    loadAddon()
    _G.SlashCmdList.ROSTERQUARTERMASTER("rescan")
    contains(messages, "Snapshot not saved")
    emit("PLAYER_LOGIN")
    _G.UnitXP = function()
        return 13000
    end
    _G.SlashCmdList.ROSTERQUARTERMASTER("rescan")
    equal(RQCharDB.snapshot.xp, 13000)
    contains(messages, "Compatibility snapshot refreshed")
    _G.SlashCmdList.ROSTERQUARTERMASTER("unknown")
    contains(messages, "Available commands:")
end)

test("unsupported events are reported and remaining events still work", function()
    function frame:RegisterEvent(event)
        if event == "PLAYER_LOGOUT" then
            error("unsupported event")
        end
        self.events[event] = true
    end
    loadAddon()
    emit("PLAYER_LOGIN")
    equal(RQ.Database.initialized, true)
    contains(messages, "Event PLAYER_LOGOUT unavailable")
    contains(RQ.Diagnostics.Report(), "event:PLAYER_LOGOUT: error:")
end)

test("missing frame or slash APIs do not crash loading", function()
    _G.CreateFrame = nil
    _G.SlashCmdList = nil
    loadAddon()
    equal(RQ.eventFrame, nil)
    contains(messages, "Cannot register /rq")
    contains(messages, "Cannot subscribe to events")
end)

test("event handler installation failures are visible without crashing", function()
    function frame.SetScript()
        error("handler restricted")
    end
    loadAddon()
    equal(RQ.eventFrame, nil)
    contains(messages, "Cannot install event handler")
    contains(RQ.Diagnostics.Report(), "OnEvent: error:")
end)

test("build return shape and failed restriction checks remain unknown", function()
    _G.GetBuildInfo = function()
        return "test-client", "12345", "test-date", "not-an-interface-number"
    end
    loadAddon()
    equal(RQ.Api.GetBuildInfo().interface, nil)
    equal(RQ.Api.GetCapabilities().GetBuildInfo, "unexpected return type")
    fakeCharacter()
    _G.issecretvalue = function()
        error("restriction check unavailable")
    end
    equal(RQ.Api.GetBuildInfo().interface, nil)
    equal(RQ.Api.GetClientProject(), nil)
    equal(RQ.Api.GetCharacterProgression().xp, nil)
    equal(RQ.Api.GetCapabilities().GetBuildInfo, "restricted value")
end)

test("a malformed account does not initialize or modify the character database", function()
    RQDB = { settings = false }
    RQCharDB = { identity = { guid = "Player-Existing" } }
    local account = RQDB
    local character = RQCharDB
    loadAddon()
    equal(RQ.Database.Initialize(), false)
    equal(RQDB, account)
    equal(RQCharDB, character)
    equal(RQCharDB.schemaVersion, nil)
    contains(messages, "RQDB.settings is not a table")
end)

local failed = 0
for _, item in ipairs(tests) do
    reset()
    local ok, err = pcall(item.run)
    if ok then
        io.write("PASS ", item.name, "\n")
    else
        failed = failed + 1
        io.write("FAIL ", item.name, ": ", tostring(err), "\n")
    end
end
io.write(string.format("%d tests, %d failures\n", #tests, failed))
os.exit(failed == 0 and 0 or 1)
