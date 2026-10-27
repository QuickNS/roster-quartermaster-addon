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
        RQ.Api.Print("Registration still works: /rq add or /rq ignore.")
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

local loggedOut = false
local function onEvent(event, argument, success)
    RQ.Api.MarkEventObserved(event)
    if event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_LIST_UPDATE" then
        RQ.SuppliesService.QueueRecipes()
    end
    if event == "ADDON_LOADED" then
        if argument == RQ.name then
            RQ.Database.Initialize()
        end
    elseif event == "PLAYER_LOGIN" then
        loggedOut = false
        if RQ.Database.Initialize() then
            refresh()
            RQ.MailService.Initialize()
            showRegistration()
        end
        ensureMinimapButton()
        RQ.Api.Print("Roster ready. Click the RQ minimap button or use /rq; /rq diag shows API status.")
    elseif event == "PLAYER_LOGOUT" then
        loggedOut = true
        RQ.Api.StopMinimapDrag()
        RQ.MailService.Closed()
        RQ.BankService.Closed()
        RQ.SuppliesService.Cancel()
        RQ.ConfigTransferService.ClearPending()
        RQ.SnapshotService.Logout()
    elseif event == "BANKFRAME_OPENED" then
        if not loggedOut then
            RQ.BankService.Changed()
        end
    elseif event == "BANKFRAME_CLOSED" then
        RQ.BankService.Closed()
    elseif
        event == "PLAYERBANKSLOTS_CHANGED"
        or event == "PLAYERBANKBAGSLOTS_CHANGED"
        or event == "BANK_TABS_CHANGED"
    then
        if not loggedOut then
            RQ.BankService.Changed()
        end
    elseif event == "BAG_UPDATE" then
        if not loggedOut and RQ.Api.IsBankSessionOpen() then
            RQ.BankService.Changed()
        elseif not loggedOut and RQ.Api.IsMailboxOpen() then
            RQ.MailService.Changed()
        end
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        if not loggedOut then
            RQ.SuppliesService.ItemInfoReceived(argument, success)
        end
    elseif event == "TRADE_SKILL_CLOSE" then
        RQ.SuppliesService.Cancel()
    elseif event == "MAIL_SHOW" then
        if not loggedOut then
            RQ.MailService.Changed()
        end
        RQ.Api.Print("Use /rq mail for Attach item / Attach all. No items are attached or sent automatically.")
    elseif event == "MAIL_SEND_SUCCESS" or event == "MAIL_FAILED" or event == "MAIL_SEND_FAILED" then
        if not loggedOut and RQ.Database.initialized then
            RQ.MailService.SendResult(event == "MAIL_SEND_SUCCESS")
        end
    elseif event == "MAIL_INBOX_UPDATE" then
        if not loggedOut and RQ.Api.IsMailboxOpen() then
            RQ.MailService.Changed()
        end
    elseif event == "MAIL_CLOSED" or event == "MAIL_SEND_INFO_UPDATE" then
        if event == "MAIL_CLOSED" and RQ.Database.initialized then
            RQ.MailService.Closed()
        end
        if RQ.MainWindow then
            RQ.MainWindow.Invalidate()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        ensureMinimapButton()
        if RQ.Database.initialized then
            refresh()
            showRegistration()
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        RQ.Api.StopMinimapDrag()
        RQ.Api.HideRegistrationPrompt()
        RQ.Api.HideRosterWindow()
        RQ.Api.HideCopyWindow()
        RQ.Api.HideGroceryWindows()
    elseif event == "PLAYER_REGEN_ENABLED" then
        showRegistration()
    elseif eventSections[event] then
        if loggedOut then
            return
        end
        if event == "BAG_UPDATE_DELAYED" and RQ.Api.IsBankSessionOpen() then
            RQ.BankService.Changed()
            return
        end
        if event == "BAG_UPDATE_DELAYED" and RQ.Api.IsMailboxOpen() then
            RQ.MailService.Changed()
            return
        end
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
    elseif command == "copy" then
        RQ.Diagnostics.Copy()
    elseif command == "fullname" then
        configurationResult(RQ.Database.SetFullName(argument))
    elseif command == "supplies" then
        if argument == "" then
            openDashboard("supplies")
        else
            RQ.SuppliesService.Open(argument)
        end
    elseif command == "bags" then
        if argument ~= "" and RQ.MainWindow then
            RQ.MainWindow.SearchBags(argument, true)
        else
            openDashboard("bags")
        end
    elseif command == "find" then
        RQ.SuppliesService.FindItems(argument)
    elseif command == "recipes" then
        RQ.SuppliesService.Open(argument, true)
    elseif
        command == "export"
        or command == "import"
        or command == "import-confirm"
        or command == "import-cancel"
        or command == "import-rollback"
    then
        local ok, err = RQ.ConfigTransferService.Command(command, argument)
        if not ok then
            RQ.Api.Print("Configuration transfer: " .. err)
        end
    elseif
        command == "routing"
        or command == "routing-item"
        or command == "routing-priority"
        or command == "reserve"
        or command == "reserves"
        or command == "material-totals"
    then
        local ok, err = RQ.LogisticsPolicyService.Command(command, argument)
        if not ok then
            RQ.Api.Print("Logistics: " .. err)
        end
    elseif command == "professions" then
        local textQuery = argument == "text" and "" or argument:match("^text%s+(.+)$")
        RQ.ProfessionAdviceService.Open(textQuery or argument, textQuery ~= nil)
    elseif
        command == "profession-plan"
        or command == "profession-focus"
        or command == "profession-prefer"
        or command == "profession-avoid"
    then
        configurationResult(RQ.ProfessionAdviceService.Command(command, argument))
    elseif command == "targets" then
        RQ.SuppliesService.OpenTargets(argument)
    elseif command == "scan-recipes" then
        local record = RQ.Database.Current()
        if not record or record.registration == "ignored" then
            RQ.Api.Print("Recipe scan unavailable: log into a tracked character and open their profession.")
        else
            RQ.SuppliesService.ScanRecipes()
        end
    elseif command == "mail" then
        RQ.SuppliesService.Mail(argument == "text")
    elseif command == "shipments" then
        RQ.ShipmentPanel.Open(argument == "text")
    elseif command == "mail-tracking" then
        if argument ~= "verify" and argument ~= "off" then
            RQ.Api.Print(
                "After completing the mail smoke test: /rq mail-tracking verify; disable: /rq mail-tracking off."
            )
        else
            configurationResult(RQ.MailService.Verify(argument == "verify"))
        end
    elseif command == "shipment" then
        if not RQ.Database.initialized then
            configurationResult(false, RQ.Database.status)
        elseif argument == "prune" then
            configurationResult(RQ.MailService.Prune())
        else
            local id, action = argument:match("^(%d+)%s+(%S+)$")
            configurationResult(RQ.MailService.Resolve(tonumber(id), action))
        end
    elseif command == "need" then
        local item, count, member = argument:match("^(%d+)%s+(%d+)%s*(.-)$")
        configurationResult(RQ.SuppliesService.SetNeed(tonumber(item), tonumber(count), member))
    elseif command == "goal" then
        local profession, recipe, skill, member = argument:match("^(%d+)%s+(%d+)%s+(%d+)%s*(.-)$")
        configurationResult(RQ.SuppliesService.SetGoal(tonumber(profession), tonumber(recipe), tonumber(skill), member))
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
    elseif command == "add" or command == "ignore" then
        RQ.SnapshotService.Register(command)
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
    elseif command == "close" then
        RQ.Api.HideRosterWindow()
        RQ.Api.HideCopyWindow()
    elseif command == "main" then
        configurationResult(RQ.Database.SetMain(argument ~= "" and argument or RQ.Database.activeId))
    elseif command == "role" then
        local role, id = argument:match("^(%S+)%s*(.-)$")
        if not role then
            RQ.Api.Print("Usage: /rq role <UNASSIGNED|TANK|HEALER|DPS|HEALER_DPS|FLEX> [character ID]")
            return
        end
        configurationResult(RQ.Database.SetRole(id ~= "" and id or RQ.Database.activeId, role:upper()))
    elseif command == "reset-window" then
        local ok, err = RQ.Database.SaveWindowPosition(RQ.Util.DefaultWindowPosition())
        if not ok then
            RQ.Api.Print("Window position not changed: " .. err)
        elseif RQ.Api.ResetRosterWindowPosition() then
            RQ.Api.Print("Window position reset to center.")
        end
    elseif command == "profession-ranking" then
        local enabled, weight = argument:match("^(%S+)%s*(%d*)$")
        if not RQ.Database.initialized then
            RQ.Api.Print("Profession ranking unavailable: " .. RQ.Database.status)
        elseif enabled ~= "on" and enabled ~= "off" then
            RQ.Api.Print("Usage: /rq profession-ranking on|off [weight 0-100]. Default: off.")
        else
            local settings = RQ.Util.Copy(RQDB.settings.professionLag)
            settings.rankingEnabled = enabled == "on"
            if weight ~= "" then
                settings.rankingWeight = tonumber(weight)
            end
            configurationResult(RQ.Database.SetProfessionConfig(settings))
        end
    elseif command == "profession-cap" or command == "profession-track" then
        if not RQ.Database.initialized then
            configurationResult(false, RQ.Database.status)
            return
        end
        local profession, value = argument:match("^(%d+)%s+(%S+)$")
        profession = tonumber(profession)
        if
            not RQ.SuppliesConfig.Id(profession)
            or (command == "profession-cap" and not tonumber(value))
            or (command == "profession-track" and value ~= "on" and value ~= "off")
        then
            configurationResult(
                false,
                "Usage: /rq profession-cap <profession ID> <ceiling>; /rq profession-track <secondary ID> on|off"
            )
            return
        end
        local settings = RQ.Util.Copy(RQDB.settings.professionLag)
        if command == "profession-cap" then
            settings.ceilings[profession] = tonumber(value)
        else
            settings.secondary[profession] = value == "on"
        end
        configurationResult(RQ.Database.SetProfessionConfig(settings))
    else
        RQ.Api.Print(
            "Available commands: /rq, diag, rescan, roster [text], settings, close, register, add, "
                .. "ignore, main [ID], role <role> [ID], reset-window, "
                .. "today [text], planning, copy, fullname <first and last name>, "
                .. "supplies, bags [search], find <name or item ID>, recipes [member], "
                .. "targets [member], scan-recipes, mail, shipments [text], shipment <ID> sent|close, "
                .. "mail-tracking verify|off, "
                .. "need <item> <count> [member], "
                .. "goal <profession> <recipe> <skill> [member]."
                .. "profession-cap <ID> <ceiling>, profession-track <secondary ID> <on|off>."
                .. " professions [text] [member], profession-plan <ID[,ID]|clear> [member], "
                .. "profession-focus <balanced|gathering|self-sufficient> [member], "
                .. "profession-prefer|profession-avoid <ID> on|off [member]."
                .. "reset-session [member]. routing [copy], "
                .. "routing-item <category> <item> on|off, routing-priority <category> <members|clear>, "
                .. "reserve <potions|bandages> <item> <count> [member], reserves [copy] [member], "
                .. "material-totals [copy] [item|category], profession-ranking on|off [weight]."
                .. " export, import, import-confirm <token>, import-cancel, import-rollback."
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
    "TRADE_SKILL_SHOW",
    "TRADE_SKILL_CLOSE",
    "MAIL_SHOW",
    "MAIL_CLOSED",
    "MAIL_SEND_INFO_UPDATE",
    "MAIL_SEND_SUCCESS",
    "MAIL_SEND_FAILED",
    "MAIL_FAILED",
    "MAIL_INBOX_UPDATE",
    "GET_ITEM_INFO_RECEIVED",
    "BANKFRAME_OPENED",
    "BANKFRAME_CLOSED",
    "PLAYERBANKSLOTS_CHANGED",
    "PLAYERBANKBAGSLOTS_CHANGED",
    "BANK_TABS_CHANGED",
    "BAG_UPDATE",
}
for _, event in ipairs(RQ.Util.Keys(eventSections)) do
    events[#events + 1] = event
end
RQ.eventFrame = RQ.Api.Subscribe(events, onEvent)
