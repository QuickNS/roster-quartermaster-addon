local Window = {
    tab = "roster",
    dirty = true,
    scheduled = false,
    status = "",
    rosterSort = "priority",
    rosterFilter = "all",
    realm = "all",
    bagQuery = "",
    bagSource = "all",
    inventorySection = "upgrades",
    inventoryPage = 1,
    recipePage = 1,
    groceryFilter = "all",
    groceryExpanded = {},
    inventoryExpanded = {},
}
RQ.MainWindow = Window

local function model()
    if not RQ.RosterPanel or not RQ.CharacterCard then
        return nil, "Dashboard modules did not load; reinstall the complete addon."
    end
    local report, err = RQ.PlanningService.Evaluate()
    if not report then
        return nil, err
    end
    if Window.group == nil then
        local current = RQ.Database.Current()
        Window.group = current and RQ.Character.TradeGroup(current.identity) or "~unknown"
        Window.realm = current and RQ.Character.Realm(current.identity) or "~unknown"
    end
    local account = RQ.WorkspaceScope.Account(RQDB, Window.realm, Window.group)
    local recommendations = {}
    for _, recommendation in ipairs(report.recommendations) do
        if account.characters[recommendation.characterId] then
            recommendations[#recommendations + 1] = recommendation
        end
    end
    report.recommendations = recommendations
    local view = RQ.RosterPanel.Build(RQDB, RQ.Database.activeId, report.now, Window.selectedId, report.estimates, {
        sort = Window.rosterSort,
        filter = Window.tab == "today" and "all" or Window.rosterFilter,
        realm = Window.realm,
        group = Window.group,
        selectVisible = true,
    }, report.recommendations)
    view.characterIds = RQ.Util.Keys(account.characters)
    if not account.characters[view.selectedId] then
        Window.selectedId = view.characterIds[1]
        view = RQ.RosterPanel.Build(RQDB, RQ.Database.activeId, report.now, Window.selectedId, report.estimates, {
            sort = Window.rosterSort,
            filter = Window.rosterFilter,
            realm = Window.realm,
            group = Window.group,
        }, report.recommendations)
        view.characterIds = RQ.Util.Keys(account.characters)
        if #view.characterIds == 0 then
            view.selectedId, view.isMember, view.isMain = nil, false, false
            view.characterLabel, view.characterDetails = "No characters in this scope", ""
            view.canSetCook, view.canSetRuleset = false, false
        end
    end
    if Window.tab == "today" or Window.tab == "roster" then
        if not RQ.TodayPanel then
            return nil, "Today module did not load; reinstall the complete addon."
        end
        local scopedCards = {}
        for _, card in ipairs(view.cards) do
            if account.characters[card.id] then
                scopedCards[#scopedCards + 1] = card
            end
        end
        view.cards = scopedCards
        RQ.WorkspaceView.Roster(
            account,
            view,
            report,
            RQ.Database.activeId,
            RQ.SuppliesService.Plan(account, report.now, RQ.MailService.Verified())
        )
        if Window.tab == "today" then
            table.sort(view.cards, function(a, b)
                local first, second = a.visual.rank or math.huge, b.visual.rank or math.huge
                if first ~= second then
                    return first < second
                end
                return a.id < b.id
            end)
        end
        view.rows = RQ.RosterPanel.SelectRows(
            view.cards,
            { realm = Window.realm, group = Window.group, sort = Window.rosterSort, filter = Window.rosterFilter },
            Window.tab == "today"
        )
    elseif Window.tab == "supplies" then
        view.cards = RQ.SuppliesService.Cards(RQDB)
    elseif Window.tab == "recipes" then
        if Window.recipeCharacterId and not account.roster[Window.recipeCharacterId] then
            Window.recipeCharacterId = nil
        end
        view.cards = RQ.WorkspaceView.Recipes(account, Window.recipeCharacterId, report.now)
    elseif Window.tab == "mail" then
        view.cards = account.characters[RQ.Database.activeId] and RQ.SuppliesService.MailCards(account, report.now)
            or {
                {
                    title = "Active character is outside this filter",
                    body = "Choose the active character's realm/faction to review its mail suggestions.",
                    action = "Manage roster",
                },
            }
        table.insert(view.cards, 1, {
            title = "Tracked shipments",
            body = "Observe roster-to-roster shipments, inbox contents and unresolved transfers.",
            action = "View shipments",
            actionKind = "shipments",
        })
    elseif Window.tab == "shipments" then
        view.cards = RQ.ShipmentPanel.Build(account, report.now, RQ.MailService.Verified())
    elseif Window.tab == "professions" then
        view.cards = RQ.WorkspaceView.Recipes(account, Window.recipeCharacterId, report.now)
    elseif Window.tab == "advice" then
        local id = account.roster[Window.professionCharacterId] and Window.professionCharacterId or view.selectedId
        view.professionAdvice = RQ.ProfessionAdvisor.Evaluate(account, id, report.now)
        view.cards = RQ.ProfessionPanel.Build(account, view.professionAdvice)
    elseif Window.tab == "bags" then
        view.inventorySection = Window.inventorySection
        view.bagOwnerIds = RQ.InventorySearch.CharacterIds(account)
        local owner = Window.bagCharacterId and account.characters[Window.bagCharacterId]
        if owner and owner.registration ~= "member" then
            owner = nil
        end
        if Window.bagCharacterId and (not owner or not RQDB.roster[Window.bagCharacterId]) then
            Window.bagCharacterId = nil
            owner = nil
            if Window.status == "" then
                Window.status = "Search owner is outside this scope or no longer registered; showing filtered members."
            end
        end
        view.bagOwnerLabel = owner
                and (RQ.CharacterCard.Text(RQ.Character.DisplayName(owner.identity)) .. " - " .. RQ.CharacterCard.Text(
                    owner.identity.realm
                ))
            or "All registered members, including disabled members"
        view.bagQuery, view.bagCharacterId = Window.bagQuery, Window.bagCharacterId
        view.bagSource = Window.bagSource
        if Window.inventorySection == "recorded" then
            if Window.bagQuery ~= "" then
                view.inventorySearch, err = RQ.SuppliesService.SearchInventory(
                    account,
                    Window.bagQuery,
                    report.now,
                    Window.bagCharacterId,
                    Window.bagSource
                )
                if not view.inventorySearch then
                    return nil, err
                end
            end
            view.cards = RQ.WorkspaceView.Inventory(
                account,
                Window.bagCharacterId,
                report.now,
                Window.bagQuery,
                Window.bagSource,
                Window.inventoryExpanded
            )
        elseif Window.bagQuery ~= "" then
            view.inventorySearch, err = RQ.SuppliesService.SearchInventory(
                account,
                Window.bagQuery,
                report.now,
                Window.bagCharacterId,
                Window.bagSource
            )
            if not view.inventorySearch then
                return nil, err
            end
            view.cards = RQ.BagPanel.SearchCards(view.inventorySearch, report.now)
            RQ.WorkspaceView.Search(view.cards, view.inventorySearch, report.now)
        elseif Window.inventorySection == "stock" then
            view.groceryFilter = Window.groceryFilter
            view.cards = RQ.WorkspaceView.Stock(
                account,
                RQ.SuppliesService.ReviewGroceries(
                    account,
                    report.now,
                    Window.bagCharacterId,
                    RQ.MailService.Verified()
                ),
                Window.bagCharacterId,
                report.now,
                Window.groceryFilter,
                Window.groceryExpanded
            )
        else
            view.cards = RQ.BagPanel.Build(
                account,
                RQ.SuppliesService.Plan(account, report.now, RQ.MailService.Verified()),
                report.now
            )
        end
        view.allCards = view.cards
        local pageSize = Window.inventorySection == "recorded" and 60 or 12
        view.inventoryPageCount = math.max(1, math.ceil(#view.allCards / pageSize))
        Window.inventoryPage = math.min(Window.inventoryPage, view.inventoryPageCount)
        view.inventoryPage, view.cards = Window.inventoryPage, {}
        local last = math.min(Window.inventoryPage * pageSize, #view.allCards)
        for index = (Window.inventoryPage - 1) * pageSize + 1, last do
            local card = view.allCards[index]
            if card.itemId then
                if not card.compact then
                    card.title = RQ.CharacterCard.Text(RQ.SuppliesService.ItemLabel(account, card.itemId))
                end
                card.icon = view.inventorySearch and view.inventorySearch.icons[card.itemId]
                    or RQ.Api.GetItemIcon(card.itemId)
            end
            view.cards[#view.cards + 1] = card
        end
    end
    if Window.tab == "recipes" then
        local cards = view.cards
        view.recipePageCount = math.max(1, math.ceil(#cards / 12))
        Window.recipePage = math.min(Window.recipePage, view.recipePageCount)
        view.recipePage, view.cards = Window.recipePage, {}
        for index = (Window.recipePage - 1) * 12 + 1, math.min(Window.recipePage * 12, #cards) do
            view.cards[#view.cards + 1] = cards[index]
        end
    end
    view.realms, view.groups = { all = "All realms" }, { all = "All trade groups" }
    for _, record in pairs(RQDB.characters) do
        view.realms[RQ.Character.Realm(record.identity) or "~unknown"] = record.identity.realm or "Unknown realm"
        view.groups[RQ.Character.TradeGroup(record.identity) or "~unknown"] =
            RQ.Character.TradeGroupLabel(record.identity)
    end
    view.realms[Window.realm] = view.realms[Window.realm] or Window.realm
    view.groups[Window.group] = view.groups[Window.group] or Window.group
    view.realm, view.group = Window.realm, Window.group
    Window.selectedId = view.selectedId
    Window.realm = view.realm
    Window.group = view.group
    view.detail = nil
    for _, card in ipairs(view.cards) do
        if card.id and card.id == view.selectedId then
            view.detail = card
        end
    end
    view.warnings = table.concat(report.warnings, "\n")
    view.tab = Window.tab
    view.primaryTab = Window.tab == "bags" and (Window.inventorySection == "stock" and "professions" or "bags")
        or (Window.tab == "recipes" or Window.tab == "professions" or Window.tab == "advice") and "professions"
        or (Window.tab == "planning" or Window.tab == "manage") and "settings"
        or (Window.tab == "roster" or Window.tab == "today") and "roster"
        or "bags"
    view.status = Window.status
    return view
end

local handlers = {}

function Window.SearchBags(query, open)
    local normalized, err = RQ.InventorySearch.NormalizeQuery(query)
    if not normalized then
        Window.status = "Inventory search: " .. err
        RQ.Api.Print(Window.status)
        Window.Invalidate()
        return false
    end
    if normalized ~= Window.bagQuery then
        Window.inventoryExpanded = {}
    end
    Window.bagQuery, Window.status = normalized, ""
    Window.inventorySection = "recorded"
    Window.inventoryPage = 1
    if open or normalized == "" then
        Window.bagCharacterId = nil
        Window.bagSource = "all"
    end
    if open then
        return Window.Open("bags")
    end
    Window.Invalidate()
    return true
end

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
        Window.view = view
        if RQ.Api.IsGroceryWindowShown() then
            handlers.compactGroceries()
        end
    end
    return ok, err
end

function Window.OpenGroceries(id)
    Window.bagCharacterId, Window.bagSource = id, "all"
    Window.groceryFilter, Window.groceryExpanded = "all", {}
    return Window.Open("inventory")
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
    if tab == "inventory" or tab == "supplies" then
        tab, Window.inventorySection, Window.bagQuery = "bags", "stock", ""
        Window.inventoryPage = 1
    elseif tab == "bags" then
        Window.inventorySection = "recorded"
        Window.inventoryPage = 1
    elseif tab == "settings" then
        tab = "planning"
    elseif tab == "professions" then
        tab, Window.recipeCharacterId = "recipes", nil
    end
    if tab == "recipes" then
        Window.recipePage = 1
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
    if (not RQ.Api.IsRosterWindowShown() and not RQ.Api.IsGroceryWindowShown()) or Window.scheduled then
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
        elseif RQ.Api.IsGroceryWindowShown() then
            handlers.compactGroceries()
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

handlers.searchBags = function(query)
    return Window.SearchBags(query)
end
handlers.bagOwner = function()
    local ids = { "" }
    for _, id in ipairs(Window.view.bagOwnerIds or {}) do
        ids[#ids + 1] = id
    end
    local id = cycle(ids, Window.bagCharacterId or "", 1)
    Window.bagCharacterId = id ~= "" and id or nil
    Window.inventoryPage = 1
    Window.Invalidate()
end
handlers.copyBagSearch = function()
    RQ.SuppliesService.FindItems(
        Window.bagQuery,
        Window.bagCharacterId,
        true,
        Window.bagSource,
        RQ.WorkspaceScope.Account(RQDB, Window.realm, Window.group)
    )
end
handlers.bagSource = function()
    Window.inventoryPage = 1
    Window.bagSource = cycle(RQ.InventorySearch.sources, Window.bagSource, 1)
    Window.Invalidate()
end
handlers.tab = function(tab)
    Window.status = ""
    Window.Open(tab)
end
handlers.configure = function(id)
    Window.selectedId = id or Window.selectedId
    Window.status = ""
    Window.Open("manage")
end
handlers.select = function(id)
    if id then
        Window.selectedId = id
    end
    Window.Invalidate()
end
handlers.selectRelative = function(delta)
    local rows = Window.view and Window.view.rows or {}
    if #rows == 0 then
        return
    end
    local selected
    for index, row in ipairs(rows) do
        if row.id and row.id == Window.selectedId then
            selected = index
        end
    end
    local index = selected and (selected - 1 + delta) % #rows + 1 or (delta > 0 and 1 or #rows)
    handlers.select(rows[index].id)
end
handlers.rosterSort = function()
    Window.tab = "roster"
    Window.rosterSort = cycle(RQ.RosterPanel.sorts, Window.rosterSort, 1)
    Window.Invalidate()
end
handlers.rosterFilter = function()
    Window.rosterFilter = cycle(RQ.RosterPanel.filters, Window.rosterFilter, 1)
    Window.Invalidate()
end
handlers.tradeGroup = function()
    Window.group = cycle(RQ.Util.Keys(Window.view.groups), Window.group, 1)
    Window.inventoryPage = 1
    Window.recipePage = 1
    Window.Invalidate()
end
handlers.inventorySection = function(section)
    Window.inventoryPage = 1
    Window.inventorySection, Window.bagQuery = section, ""
    Window.tab = "bags"
    Window.Invalidate()
end
handlers.inventoryPage = function(delta)
    Window.inventoryPage = math.max(1, math.min(Window.view.inventoryPageCount, Window.inventoryPage + delta))
    Window.Invalidate()
end
handlers.manageRoster = function()
    Window.Open("manage")
end
handlers.mainFor = function(id)
    result(RQ.Database.SetMain(id))
end
handlers.configTransfer = function(command)
    local ok, err = RQ.ConfigTransferService.Command(command, "")
    if not ok then
        result(false, err)
    end
end
handlers.realm = function()
    Window.realm = cycle(RQ.Util.Keys(Window.view.realms), Window.realm, 1)
    Window.inventoryPage = 1
    Window.recipePage = 1
    Window.Invalidate()
end
handlers.supplies = function(id)
    RQ.SuppliesService.Open(id, false, true)
end
handlers.groceries = function(id)
    RQ.SuppliesService.Open(id)
end
handlers.groceryFilter = function()
    Window.groceryFilter = cycle({ "all", "missing", "collection", "covered", "unknown" }, Window.groceryFilter, 1)
    Window.inventoryPage = 1
    Window.Invalidate()
end
handlers.groceryDetails = function(id, item)
    local key = id .. ":" .. item
    Window.groceryExpanded[key] = not Window.groceryExpanded[key]
    Window.Invalidate()
end
handlers.recipes = function(id)
    RQ.SuppliesService.OpenTargets(id)
end
handlers.mail = function(textOnly)
    RQ.SuppliesService.Mail(textOnly)
end
handlers.shipments = function()
    RQ.ShipmentPanel.Open()
end
handlers.inbox = function()
    result(RQ.MailService.Scan())
end
handlers.shipmentConfirm = function(id)
    result(RQ.MailService.Resolve(id, "sent"))
end
handlers.shipmentClose = function(id)
    result(RQ.MailService.Resolve(id, "close"))
end
handlers.professionAdvice = function(id)
    RQ.ProfessionAdviceService.Open(id)
end
handlers.professionPlan = function(id, choices)
    result(RQ.ProfessionAdviceService.Plan(id, choices))
end
handlers.professionFocus = function(id)
    result(RQ.ProfessionAdviceService.CycleFocus(id))
end
handlers.attach = function(id, itemId)
    local ok, message = RQ.SuppliesService.Attach(id, itemId)
    Window.status = message
    RQ.Api.Print(message)
    Window.Invalidate()
    return ok
end
handlers.recipeGoal = function(id, professionId, recipeId, targetSkill)
    local ok, err = RQ.SuppliesService.SetOrangeGoal(professionId, recipeId, targetSkill, id)
    if ok then
        Window.status = "Recipe goal saved; groceries updated. Rescan as recipe difficulty changes."
        Window.Invalidate()
    else
        result(false, err)
    end
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
    Window.selectedId = cycle(Window.view.characterIds, Window.selectedId, delta)
    Window.status = ""
    Window.Invalidate()
end
handlers.professionCeiling = function(value)
    if value == nil then
        result(false, "Enter a numeric profession ceiling.")
        return
    end
    local settings = RQ.Util.Copy(RQDB.settings.professionLag)
    settings.ceiling = value
    result(RQ.Database.SetProfessionConfig(settings))
end
handlers.register = function(action)
    if not Window.selectedId then
        result(false, "Select a character first.")
        return
    end
    result(RQ.SnapshotService.Register(action, Window.selectedId))
end
handlers.main = function()
    result(RQ.Database.SetMain(Window.selectedId))
end
handlers.role = function()
    local entry = RQDB.roster[Window.selectedId]
    local role = cycle(RQ.Character.roles, entry and entry.role, 1)
    result(RQ.Database.SetRole(Window.selectedId, role))
end
handlers.ruleset = function()
    local record = Window.selectedId and RQDB.characters[Window.selectedId]
    result(RQ.Database.SetRuleset(Window.selectedId, record and record.identity.ruleset == "PVE" and "PVP" or "PVE"))
end
handlers.cook = function()
    result(RQ.Database.SetCook(Window.selectedId))
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

handlers.inventoryExpand = function(id, source)
    local key = id .. ":" .. source
    local open = Window.inventoryExpanded[key]
    if open == nil then
        open = Window.bagQuery ~= ""
    end
    Window.inventoryExpanded[key] = not open
    Window.Invalidate()
end
handlers.recipePage = function(delta)
    Window.recipePage = math.max(1, math.min(Window.view.recipePageCount, Window.recipePage + delta))
    Window.Invalidate()
end
handlers.need = function(id, item, quantity)
    local record = RQDB.characters[id]
    if not record or not RQ.WorkspaceScope.Matches(record.identity, Window.realm, Window.group) then
        return result(false, "Grocery owner is outside the current realm/faction scope. Reopen the editor.")
    end
    return result(RQ.SuppliesService.SetNeed(item, quantity, id))
end
handlers.compactGroceries = function()
    local account = RQ.WorkspaceScope.Account(RQDB, Window.realm, Window.group)
    local owner = account.roster[Window.bagCharacterId] and Window.bagCharacterId or nil
    local plan = RQ.SuppliesService.ReviewGroceries(account, RQ.Api.GetServerTime(), owner, RQ.MailService.Verified())
    RQ.Api.ShowGroceryWindow(
        (Window.view.realms[Window.realm] or Window.realm)
            .. " | "
            .. (Window.view.groups[Window.group] or Window.group)
            .. " | "
            .. (
                owner and RQ.CharacterCard.Text(RQ.Character.DisplayName(account.characters[owner].identity))
                or "All members"
            ),
        RQ.WorkspaceView.CompactGroceries(account, plan, owner)
    )
end
