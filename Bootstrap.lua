local function capture(logout)
    if not RQ.Database.initialized then
        return false
    end
    local identity, snapshot = RQ.Diagnostics.Capture()
    if logout then
        snapshot.lastLogout = snapshot.lastSeen
    elseif type(RQCharDB.snapshot) == "table" then
        snapshot.lastLogout = RQCharDB.snapshot.lastLogout
    end
    return RQ.Database.SaveProbe(identity, snapshot)
end

local function onEvent(event, addonName)
    RQ.Api.MarkEventObserved(event)
    if event == "ADDON_LOADED" then
        if addonName == RQ.name then
            RQ.Database.Initialize()
        end
    elseif event == "PLAYER_LOGIN" then
        if RQ.Database.Initialize() then
            capture(false)
        end
        RQ.Api.Print("Compatibility probe loaded. Use /rq diag; the roster dashboard is not implemented yet.")
    elseif event == "PLAYER_LOGOUT" then
        capture(true)
    end
end

RQ.Api.RegisterSlashCommand(function(message)
    local command = (message or ""):match("^%s*(.-)%s*$"):lower()
    if command == "" or command == "diag" then
        RQ.Diagnostics.Report()
    elseif command == "rescan" then
        if capture(false) then
            RQ.Api.Print("Compatibility snapshot refreshed. Use /rq diag to inspect API availability.")
        else
            RQ.Api.Print("Snapshot not saved: " .. RQ.Database.status)
        end
    else
        RQ.Api.Print("Available commands: /rq, /rq diag, /rq rescan. Other commands arrive in later milestones.")
    end
end)

RQ.eventFrame = RQ.Api.Subscribe({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_LOGOUT" }, onEvent)
