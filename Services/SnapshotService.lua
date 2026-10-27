local Service = { pending = {}, generation = 0 }
RQ.SnapshotService = Service

local function collect(section)
    local api = RQ.Api
    if section == "progression" then
        return api.GetCharacterProgression()
    elseif section == "rested" then
        return { restedXp = api.GetRestedXP() }
    elseif section == "location" then
        local location = api.GetLocation()
        location.wasResting = api.IsResting()
        return location
    elseif section == "money" then
        return { money = api.GetMoney() }
    elseif section == "bags" then
        return api.GetBagCapacity() or {}
    elseif section == "professions" then
        return { professions = api.GetProfessions() }
    end
    error("Unknown snapshot section: " .. tostring(section))
end

function Service.Capture(sections, logout)
    local record = RQ.Database.Current()
    if not record then
        return false, "Current character identity unavailable."
    end
    if record.registration == "ignored" then
        return false, "Character is ignored; use /rq register to enable tracking."
    end
    local snapshot = RQ.Util.Copy(record.snapshot)
    local now = RQ.Api.GetServerTime()
    local logoutProgression = logout and collect("progression")
    local cachedLogout = logout
        and (
            not RQ.Util.IsNumber(logoutProgression.level)
            or logoutProgression.level < 1
            or not RQ.Util.IsNumber(logoutProgression.xp)
            or not RQ.Util.IsNumber(logoutProgression.xpMax)
            or logoutProgression.xpMax < 1
        )
    if cachedLogout then
        -- During client teardown, other APIs can also return plausible but empty values.
        snapshot.lastLogout = now
        local ok, err = RQ.Database.SaveSnapshot(snapshot)
        if ok then
            RQ.PlanningService.Logout(snapshot, true)
            RQ.Api.Print("Logout XP unavailable or zero XP maximum; kept the last observed snapshot.")
        end
        return ok, err
    end
    for section in pairs(sections or RQ.Snapshot.fields) do
        local values = section == "progression" and logoutProgression or collect(section)
        RQ.Snapshot.Apply(snapshot, section, values, now)
    end
    snapshot.lastSeen = now or snapshot.lastSeen
    if logout then
        snapshot.lastLogout = now
    end
    local ok, err = RQ.Database.SaveSnapshot(snapshot)
    if ok and not logout and (not sections or sections.bags) then
        RQ.SuppliesService.ScanBags()
    end
    if ok and logout then
        RQ.PlanningService.Logout(snapshot)
    end
    return ok, err
end

function Service.Refresh()
    Service.CancelPending()
    local record, err = RQ.Database.Attach(RQ.Api.GetCharacterIdentity())
    if not record then
        return false, err
    end
    local firstLogin = not Service.sessionStarted
    Service.sessionStarted = true
    local ok, captureError = Service.Capture()
    if firstLogin then
        RQ.PlanningService.Login(ok)
    end
    return ok, captureError
end

function Service.CancelPending()
    Service.pending = {}
    Service.scheduled = false
    Service.generation = Service.generation + 1
end

function Service.Register(action, characterId)
    local ok, err = RQ.Database.Register(action, characterId)
    if not ok then
        RQ.Api.Print("Registration failed: " .. err)
        return false
    end
    local isCurrent = not characterId or characterId == RQ.Database.activeId
    if isCurrent then
        Service.CancelPending()
    end
    if action ~= "ignore" and isCurrent then
        local captured, captureError = Service.Capture()
        if not captured then
            RQ.Api.Print("Snapshot not saved: " .. captureError)
        end
    end
    if isCurrent then
        RQ.Api.HideRegistrationPrompt()
    end
    RQ.Api.Print(
        action == "ignore" and "Character ignored. Use /rq register to reconsider."
            or "Roster registration saved. Use /rq roster."
    )
    return true
end

function Service.Flush()
    local pending = Service.pending
    Service.CancelPending()
    if next(pending) then
        local ok, err = Service.Capture(pending)
        if not ok then
            RQ.Api.Print("Snapshot not saved: " .. err)
        end
    end
end

function Service.Queue(sections)
    local record = RQ.Database.Current()
    if not record or record.registration == "ignored" then
        return
    end
    for _, section in ipairs(sections) do
        Service.pending[section] = true
    end
    if Service.scheduled then
        return
    end
    Service.scheduled = true
    local generation = Service.generation
    if
        not RQ.Api.After(0.25, function()
            if Service.generation == generation then
                Service.Flush()
            end
        end)
    then
        if not Service.timerWarning then
            RQ.Api.Print("Timer API unavailable: event updates run immediately without debouncing; see /rq diag.")
            Service.timerWarning = true
        end
        Service.Flush()
    end
end

function Service.Logout()
    Service.CancelPending()
    local record = RQ.Database.Current()
    if record and record.registration ~= "ignored" then
        local ok, err = Service.Capture(nil, true)
        if not ok then
            RQ.Api.Print("Logout snapshot not saved: " .. err)
        end
    end
end
