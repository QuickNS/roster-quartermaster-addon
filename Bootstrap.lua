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

local function openDashboard(tab, toggle)
    if RQ.MainWindow then
        if RQ.MainWindow.Open(tab, toggle) then
            RQ.Api.HideRegistrationPrompt()
            return
        end
    else
        RQ.Api.Print("Dashboard module did not load; reinstall all UI files and the TOC. Showing text fallback.")
    end
    if tab == "today" or (not tab and (not RQ.MainWindow or RQ.MainWindow.tab == "today")) then
        RQ.PlanningService.TextReport()
    else
        RQ.Diagnostics.Roster()
    end
end

local minimapWarning = false
local function ensureMinimapButton()
    if not RQ.Api.CreateMinimapButton(function()
        openDashboard(nil, true)
    end) and not minimapWarning then
        RQ.Api.Print("Minimap launcher unavailable; use /rq and check /rq diag.")
        minimapWarning = true
    end
end

local function configurationResult(ok, err)
    RQ.Api.Print(ok and "Roster configuration saved." or "Configuration not changed: " .. err)
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
        ensureMinimapButton()
        RQ.Api.Print("Roster ready. Click the RQ minimap button or use /rq; /rq diag shows API status.")
    elseif event == "PLAYER_LOGOUT" then
        RQ.SnapshotService.Logout()
    elseif event == "PLAYER_ENTERING_WORLD" then
        ensureMinimapButton()
        if RQ.Database.initialized then
            refresh()
            showRegistration()
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        RQ.Api.HideRegistrationPrompt()
        RQ.Api.HideRosterWindow()
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
    if command == "" then
        openDashboard(nil, true)
    elseif command == "diag" then
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
        if argument:lower() == "text" then
            RQ.Diagnostics.Roster()
        else
            openDashboard("roster")
        end
    elseif command == "settings" then
        openDashboard("settings")
    elseif command == "planning" then
        openDashboard("planning")
    elseif command == "today" then
        if argument:lower() == "text" then
            RQ.PlanningService.TextReport()
        else
            openDashboard("today")
        end
    elseif command == "pin" then
        local id, err = RQ.Database.ResolveMember(argument)
        if not id then
            configurationResult(false, err)
        else
            configurationResult(RQ.Database.Pin(id))
        end
    elseif command == "unpin" then
        configurationResult(RQ.Database.Unpin())
    elseif command == "close" then
        RQ.Api.HideRosterWindow()
    elseif command == "main" then
        configurationResult(RQ.Database.SetMain(argument ~= "" and argument or RQ.Database.activeId))
    elseif command == "role" then
        local role, id = argument:match("^(%S+)%s*(.-)$")
        if not role then
            RQ.Api.Print("Usage: /rq role <UNASSIGNED|TANK|HEALER|DPS|HEALER_DPS|FLEX> [character ID]")
            return
        end
        configurationResult(RQ.Database.SetRole(id ~= "" and id or RQ.Database.activeId, role:upper()))
    elseif command == "unlink" then
        configurationResult(RQ.Database.Unlink(argument ~= "" and argument or RQ.Database.activeId))
    elseif command == "reset-window" then
        local ok, err = RQ.Database.SaveWindowPosition(RQ.Util.DefaultWindowPosition())
        if not ok then
            RQ.Api.Print("Window position not changed: " .. err)
        elseif RQ.Api.ResetRosterWindowPosition() then
            RQ.Api.Print("Window position reset to center.")
        end
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
            "Available commands: /rq, diag, rescan, roster [text], settings, close, slots, register, add, "
                .. "link <slot>, ignore, name <slot> <name>, main [ID], role <role> [ID], unlink [ID], reset-window, "
                .. "today [text], planning, pin <name|slot|ID>, unpin."
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
