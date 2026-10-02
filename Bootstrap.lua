local eventSections = {
    PLAYER_LEVEL_UP = { "progression", "rested" },
    PLAYER_XP_UPDATE = { "progression", "rested" },
    UPDATE_EXHAUSTION = { "rested" },
    PLAYER_UPDATE_RESTING = { "location", "rested" },
    PLAYER_MONEY = { "money" },
    BAG_UPDATE_DELAYED = { "bags" },
    SKILL_LINES_CHANGED = { "professions" },
    TRADE_SKILL_LIST_UPDATE = { "professions" },
    ZONE_CHANGED_NEW_AREA = { "location" },
    ZONE_CHANGED = { "location" },
    ZONE_CHANGED_INDOORS = { "location" },
}

local function refresh()
    local ok, err = RQ.SnapshotService.Refresh()
    local record = RQ.Database.Current()
    if not ok and (not record or record.registration ~= "ignored") then
        RQ.Api.Print("Snapshot not saved: " .. err)
    end
    return ok, err
end

local missingPromptReported = false

local function showRegistration(force)
    if RQ.RegistrationPrompt then
        RQ.RegistrationPrompt.Show(force)
        return
    end
    if force or not missingPromptReported then
        RQ.Api.Print("UI/RegistrationPrompt.lua did not load. Reinstall the complete addon and TOC, then /reload.")
        RQ.Api.Print("Registration still works: /rq add, /rq link <slot>, or /rq ignore.")
        missingPromptReported = true
    end
end

local function onEvent(event, argument)
    RQ.Api.MarkEventObserved(event)
    if event == "ADDON_LOADED" then
        if argument == RQ.name then
            RQ.Database.Initialize()
        end
    elseif event == "PLAYER_LOGIN" then
        if RQ.Database.Initialize() then
            refresh()
            showRegistration()
        end
        RQ.Api.Print("Roster snapshots loaded. Use /rq roster or /rq diag; the dashboard is not implemented yet.")
    elseif event == "PLAYER_LOGOUT" then
        RQ.SnapshotService.Logout()
    elseif event == "PLAYER_ENTERING_WORLD" then
        if RQ.Database.initialized then
            refresh()
            showRegistration()
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        RQ.Api.HideRegistrationPrompt()
    elseif event == "PLAYER_REGEN_ENABLED" then
        showRegistration()
    elseif eventSections[event] then
        if event ~= "PLAYER_XP_UPDATE" or argument == "player" then
            RQ.SnapshotService.Queue(eventSections[event])
        end
    end
end

RQ.Api.RegisterSlashCommand(function(message)
    local command, argument = (message or ""):match("^%s*(%S*)%s*(.-)%s*$")
    command = command:lower()
    if command == "" or command == "diag" then
        RQ.Diagnostics.Report()
    elseif command == "rescan" then
        if not RQ.Database.initialized then
            RQ.Api.Print("Snapshot not saved: " .. RQ.Database.status)
            return
        end
        local ok, err = refresh()
        if ok then
            RQ.Api.Print("Snapshot refreshed; incomplete sections retain old values. Use /rq diag for freshness.")
            showRegistration()
        elseif RQ.Database.Current() and RQ.Database.Current().registration == "ignored" then
            RQ.Api.Print("Snapshot not saved: " .. err)
        end
    elseif command == "register" then
        showRegistration(true)
    elseif command == "add" or command == "ignore" or command == "link" then
        RQ.SnapshotService.Register(command, argument:lower())
    elseif command == "roster" then
        RQ.Diagnostics.Roster()
    elseif command == "slots" then
        RQ.Diagnostics.Slots()
    elseif command == "name" then
        local slot, name = argument:match("^(%S+)%s+(.+)$")
        if not slot then
            RQ.Api.Print("Usage: /rq name <slot> <planned name>")
            return
        end
        local ok, err = RQ.Database.RenameSlot(slot:lower(), name)
        RQ.Api.Print(ok and "Planned name updated." or "Name not changed: " .. err)
    else
        RQ.Api.Print(
            "Available commands: /rq diag, rescan, roster, slots, register, add, link <slot>, ignore, "
                .. "name <slot> <name>."
        )
    end
end)

local events = {
    "ADDON_LOADED",
    "PLAYER_LOGIN",
    "PLAYER_LOGOUT",
    "PLAYER_ENTERING_WORLD",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
}
for _, event in ipairs(RQ.Util.Keys(eventSections)) do
    events[#events + 1] = event
end
RQ.eventFrame = RQ.Api.Subscribe(events, onEvent)
