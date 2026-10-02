local Window = { tab = "today", dirty = true, scheduled = false, status = "" }
RQ.MainWindow = Window

local function model()
    if not RQ.RosterPanel or not RQ.CharacterCard then
        return nil, "Dashboard modules did not load; reinstall the complete addon."
    end
    local report, err = RQ.PlanningService.Evaluate()
    if not report then
        return nil, err
    end
    local view = RQ.RosterPanel.Build(
        RQDB,
        RQ.Database.activeId,
        report.now,
        Window.selectedId,
        Window.selectedSlot,
        report.estimates
    )
    if Window.tab == "today" then
        if not RQ.TodayPanel then
            return nil, "Today module did not load; reinstall the complete addon."
        end
        view.cards = RQ.TodayPanel.Build(RQDB, report)
    end
    Window.selectedId, Window.selectedSlot = view.selectedId, view.selectedSlot
    view.tab = Window.tab
    view.status = Window.status
    return view
end

local handlers = {}

function Window.Render()
    if not RQ.Database.initialized then
        return false, RQ.Database.status
    end
    local view, err = model()
    if not view then
        return false, err
    end
    local ok
    ok, err = RQ.Api.RenderRosterWindow(view, handlers, RQDB.settings.window)
    if ok then
        Window.dirty = false
    end
    return ok, err
end

function Window.Open(tab, toggle)
    if toggle and RQ.Api.IsRosterWindowShown() then
        RQ.Api.HideRosterWindow()
        return true
    end
    if not RQ.Database.initialized then
        RQ.Api.Print("Dashboard unavailable: " .. RQ.Database.status)
        return false
    end
    if RQ.Api.IsInCombat() ~= false then
        RQ.Api.Print("Dashboard not opened: combat or unavailable combat-state API. Use /rq roster text.")
        return false
    end
    if tab then
        Window.tab = tab
    end
    local ok, err = Window.Render()
    if not ok then
        RQ.Api.Print("Dashboard unavailable: " .. err .. " Use /rq roster text or /rq diag.")
    end
    return ok
end

function Window.Invalidate()
    Window.dirty = true
    if not RQ.Api.IsRosterWindowShown() or Window.scheduled then
        return
    end
    Window.scheduled = true
    local function refresh()
        Window.scheduled = false
        if Window.dirty and RQ.Api.IsRosterWindowShown() then
            local ok, err = Window.Render()
            if not ok then
                RQ.Api.Print("Dashboard refresh failed: " .. err)
            end
        end
    end
    if not RQ.Api.After(0, refresh) then
        refresh()
    end
end

local function result(ok, err)
    Window.status = ok and "Saved." or (err or "Action failed; see chat for details.")
    if not ok then
        RQ.Api.Print(Window.status)
    end
    Window.Invalidate()
    return ok
end

local function cycle(keys, current, delta)
    if #keys == 0 then
        return nil
    end
    local index = 1
    for position, key in ipairs(keys) do
        if key == current then
            index = position
            break
        end
    end
    return keys[(index - 1 + delta) % #keys + 1]
end

handlers.tab = function(tab)
    Window.status = ""
    Window.Open(tab)
end
handlers.configure = function(id, slotId)
    Window.selectedId = id or Window.selectedId
    Window.selectedSlot = slotId or Window.selectedSlot
    Window.status = ""
    Window.Open("settings")
end
handlers.pin = function(id)
    if id == RQDB.settings.planning.pinnedCharacterId then
        result(RQ.Database.Unpin())
    else
        result(RQ.Database.Pin(id))
    end
end
handlers.pinSelected = function()
    handlers.pin(Window.selectedId)
end
handlers.planning = function(values)
    result(RQ.Database.SetPlanning(values))
end
handlers.multiplier = function(value)
    if value == nil then
        result(false, "Enter a numeric rested rate multiplier.")
        return
    end
    result(RQ.Database.ResetCalibration(Window.selectedId, value))
end
handlers.resetCalibration = function()
    result(RQ.Database.ResetCalibration(Window.selectedId))
end
handlers.signal = function(signal)
    local entry = RQDB.roster[Window.selectedId]
    result(RQ.Database.SetPlanningSignal(Window.selectedId, signal, entry and not entry[signal]))
end
handlers.character = function(delta)
    Window.selectedId = cycle(RQ.Util.Keys(RQDB.characters), Window.selectedId, delta)
    Window.status = ""
    Window.Invalidate()
end
handlers.slot = function(delta)
    Window.selectedSlot = cycle(RQ.Util.Keys(RQDB.plannedRoster), Window.selectedSlot, delta)
    Window.status = ""
    Window.Invalidate()
end
handlers.rename = function(name)
    result(RQ.Database.RenameSlot(Window.selectedSlot, name))
end
handlers.register = function(action)
    if not Window.selectedId then
        result(false, "Select a character first.")
        return
    end
    result(RQ.SnapshotService.Register(action, Window.selectedSlot, Window.selectedId))
end
handlers.unlink = function()
    result(RQ.Database.Unlink(Window.selectedId))
end
handlers.main = function()
    result(RQ.Database.SetMain(Window.selectedId))
end
handlers.role = function()
    local entry = RQDB.roster[Window.selectedId]
    local role = cycle(RQ.Character.roles, entry and entry.role, 1)
    result(RQ.Database.SetRole(Window.selectedId, role))
end
handlers.rescan = function()
    result(RQ.SnapshotService.Refresh())
end
handlers.position = function(position)
    local ok, err = RQ.Database.SaveWindowPosition(position)
    if not ok then
        RQ.Api.Print("Window position not saved: " .. err)
    end
end
handlers.resetPosition = function()
    result(RQ.Database.SaveWindowPosition(RQ.Util.DefaultWindowPosition()))
    RQ.Api.ResetRosterWindowPosition()
end

RQ.Database.onChanged = Window.Invalidate
