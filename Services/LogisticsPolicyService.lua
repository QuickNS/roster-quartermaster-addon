local Service = {}
RQ.LogisticsPolicyService = Service

local function trim(value)
    return value:match("^%s*(.-)%s*$")
end

local function settings()
    if not RQ.Database.initialized then
        return nil, "Logistics unavailable: " .. tostring(RQ.Database.status)
    end
    return RQ.LogisticsPolicies.Prepare(RQDB.settings.logistics)
end

local function savePolicies(value)
    local prepared, err = RQ.LogisticsPolicies.Prepare(value)
    if not prepared then
        return false, err
    end
    if not RQ.Database.SetLogisticsPolicies then
        return false, "Logistics policy persistence is unavailable; integrate Database.SetLogisticsPolicies first."
    end
    return RQ.Database.SetLogisticsPolicies(prepared)
end

function Service.SetItem(category, itemId, enabled)
    local value, err = settings()
    if not value then
        return false, err
    end
    if not value.categories[category] or not RQ.SuppliesConfig.Id(itemId) or type(enabled) ~= "boolean" then
        return false, "Use /rq routing-item <herbs|leather|food|engineering|blacksmithing> <item ID> on|off."
    end
    value.categories[category].items[itemId] = enabled and true or nil
    return savePolicies(value)
end

function Service.SetRecipients(category, queries)
    local value, err = settings()
    if not value then
        return false, err
    end
    if not value.categories[category] or type(queries) ~= "table" then
        return false, "Use /rq routing-priority <category> <member[,member...]|clear>."
    end
    local recipients, count = {}, 0
    for index in pairs(queries) do
        count = count + 1
        if not RQ.SuppliesConfig.Id(index) or index > #queries then
            return false, "Provide a contiguous recipient list."
        end
    end
    if count ~= #queries then
        return false, "Provide a contiguous recipient list."
    end
    for _, query in ipairs(queries) do
        if not RQ.Util.IsText(query) then
            return false, "Provide a nonempty recipient name, slot or GUID."
        end
        local id, resolveError = RQ.Database.ResolveMember(query)
        if not id then
            return false, resolveError
        end
        recipients[#recipients + 1] = id
    end
    value.categories[category].recipients = recipients
    return savePolicies(value)
end

function Service.SetReserve(kind, itemId, count, query)
    if not RQ.Database.initialized then
        return false, "Logistics unavailable: " .. tostring(RQ.Database.status)
    end
    if
        (kind ~= "potions" and kind ~= "bandages")
        or not RQ.SuppliesConfig.Id(itemId)
        or not RQ.SuppliesConfig.Count(count)
    then
        return false, "Use /rq reserve <potions|bandages> <item ID> <quantity; 0 clears> [member]."
    end
    local id, err = RQ.Database.ResolveMember(query and query ~= "" and query or RQ.Database.activeId)
    if not id then
        return false, err
    end
    local supplies = RQ.Util.Copy(RQDB.characters[id].supplies)
    local reserves, reserveError = RQ.SuppliesConfig.PrepareReserves(supplies.reserves)
    if not reserves then
        return false, reserveError
    end
    reserves[kind][itemId] = count > 0 and count or nil
    supplies.reserves = reserves
    return RQ.Database.SaveLogistics(id, "supplies", supplies)
end

function Service.MaterialTotals(account, now, verifiedMail)
    local result = { items = {}, sources = {}, partial = false }
    local hours = account.policies.staleSnapshotHours
    local function entry(item)
        if not result.items[item] then
            result.items[item] = { bags = 0, bank = 0, inbox = 0, pending = 0, owned = 0, covered = 0 }
        end
        return result.items[item]
    end
    local function add(items, source)
        for item, count in pairs(items) do
            local row = entry(item)
            row[source] = row[source] + count
        end
    end
    for _, id in ipairs(RQ.Util.Keys(account.roster)) do
        local record = account.characters[id]
        if account.roster[id].enabled and record and record.registration == "member" then
            local inventory = record.inventory
            local bags = RQ.SuppliesConfig.IsFresh(inventory.bags, now, hours) and true or false
            local bank = RQ.InventoryAvailability.BankEligible(record, now, hours)
            local inbox = verifiedMail == true
                    and inventory.mail.coherent
                    and RQ.SuppliesConfig.IsFresh(inventory.mail, now, hours)
                    and bags
                or false
            result.partial = result.partial or not bags or not bank or not inbox
            result.sources[#result.sources + 1] = {
                characterId = id,
                bags = bags,
                bank = bank,
                inbox = inbox,
                bagsAt = inventory.bags.scannedAt,
                bankAt = inventory.bank.scannedAt,
                inboxAt = inventory.mail.scannedAt,
            }
            for _, source in ipairs({ "bags", "bank", "mail" }) do
                for item in pairs(inventory[source].items) do
                    entry(item)
                end
            end
            if bags then
                add(inventory.bags.items, "bags")
                local stock = RQ.InventoryAvailability.Materials(record, now, hours)
                for item, count in pairs(stock) do
                    local row = entry(item)
                    row.bank = row.bank + count - (inventory.bags.items[item] or 0)
                end
            end
            local coverage = RQ.MailTracker.Coverage(account, id, now, verifiedMail)
            add(coverage.inbox, "inbox")
            add(coverage.pending, "pending")
        end
    end
    for _, row in pairs(result.items) do
        row.owned = row.bags + row.bank
        row.covered = row.owned + row.inbox + row.pending
    end
    return result
end

local function memberLabel(account, id)
    local record = account.characters[id]
    return (record and RQ.Character.DisplayName(record.identity) or "Unknown member") .. " [" .. id .. "]"
end

function Service.RoutingReport(account)
    local value, err = RQ.LogisticsPolicies.Prepare(account.settings.logistics)
    if not value then
        return nil, err
    end
    local lines = {
        "Explicit logistics routing",
        "User-configured item references only: category, profession suitability and Forever facts are unverified.",
        "No configured recipients means hold surplus. Explicit grocery deficits still take priority.",
        "Shared Engineering/Blacksmithing materials must be assigned to one category, never both.",
    }
    for _, category in ipairs(RQ.LogisticsPolicies.categories) do
        local rule, items, recipients = value.categories[category], {}, {}
        for _, item in ipairs(RQ.Util.Keys(rule.items)) do
            items[#items + 1] = tostring(item)
        end
        for _, id in ipairs(rule.recipients) do
            local enabled = account.roster[id] and account.roster[id].enabled
            recipients[#recipients + 1] = memberLabel(account, id) .. (not enabled and " (inactive; skipped)" or "")
        end
        lines[#lines + 1] = category .. ": IDs " .. (#items > 0 and table.concat(items, ", ") or "UNKNOWN / unset")
        lines[#lines + 1] = "Priority: " .. (#recipients > 0 and table.concat(recipients, " -> ") or "UNKNOWN / unset")
    end
    lines[#lines + 1] = "/rq routing-item <category> <item ID> on|off"
    lines[#lines + 1] = "/rq routing-priority <category> <member[,member...]|clear>"
    return lines
end

function Service.ReserveReport(account, id, now, verifiedMail)
    local record = account.characters[id]
    local reserves, err = RQ.SuppliesConfig.PrepareReserves(record.supplies.reserves)
    if not reserves then
        return nil, err
    end
    local plan = RQ.SuppliesService.Plan(account, now, verifiedMail)
    local lines = {
        "First Aid reserves: " .. memberLabel(account, id),
        "User-configured stock floors; generic targets overlap by maximum, not addition.",
        "Item type, consumable rank, level suitability and profession requirements: UNKNOWN / unverified.",
    }
    for _, kind in ipairs({ "potions", "bandages" }) do
        lines[#lines + 1] = kind .. (next(reserves[kind]) and ":" or ": UNKNOWN / unset")
        for _, item in ipairs(RQ.Util.Keys(reserves[kind])) do
            local need = plan.groceries[id] and plan.groceries[id][item]
            lines[#lines + 1] = "Item "
                .. item
                .. ": reserve "
                .. reserves[kind][item]
                .. ", generic "
                .. (record.supplies.needs[item] or 0)
                .. ", effective target "
                .. (need and need.target or "unknown")
                .. ", additional needed "
                .. (need and need.missing or "unknown")
        end
    end
    lines[#lines + 1] = "/rq reserve <potions|bandages> <item ID> <quantity; 0 clears> [member]"
    return lines
end

function Service.MaterialReport(account, now, verifiedMail, filter)
    local itemId, rule
    if filter and filter ~= "" then
        itemId = tonumber(filter)
        if not RQ.SuppliesConfig.Id(itemId) then
            local value, err = RQ.LogisticsPolicies.Prepare(account.settings.logistics)
            if not value then
                return nil, err
            end
            rule = value.categories[filter]
            if not rule then
                return nil, "Use /rq material-totals [copy] [item ID|category]."
            end
        end
    end
    local report = Service.MaterialTotals(account, now, verifiedMail)
    local items = RQ.Util.Copy(report.items)
    for id in pairs(rule and rule.items or {}) do
        items[id] = items[id] or {}
    end
    if itemId then
        items[itemId] = items[itemId] or {}
    end
    local lines = {
        "Account material totals - enabled roster members only",
        "Eligible recent/coherent observations only; excluded or absent sources are UNKNOWN, not proven empty.",
        "Owned = carried + eligible bank. Covered = owned + eligible inbox + confirmed pending.",
        "Mail is provisional; bank requires withdrawal. "
            .. "These totals include bound/reserved stock, not exportable surplus.",
        "No auctions, drafts, uncertain shipments or stale/incoherent source credit. No equip/craft-ready claim.",
    }
    for _, item in ipairs(RQ.Util.Keys(items)) do
        if (not itemId or item == itemId) and (not rule or rule.items[item]) then
            local row = report.items[item]
            local detail = row
                    and string.format(
                        ": bags %d, bank %d, inbox %d, pending %d, owned %d, covered %d",
                        row.bags,
                        row.bank,
                        row.inbox,
                        row.pending,
                        row.owned,
                        row.covered
                    )
                or ": UNKNOWN / no eligible observations"
            lines[#lines + 1] = "Item " .. item .. detail
        end
    end
    for _, source in ipairs(report.sources) do
        lines[#lines + 1] = memberLabel(account, source.characterId)
            .. ": bags "
            .. (source.bags and "eligible" or "UNKNOWN / excluded")
            .. " @"
            .. source.bagsAt
            .. "; bank "
            .. (source.bank and "eligible" or "UNKNOWN / excluded")
            .. " @"
            .. source.bankAt
            .. "; inbox "
            .. (source.inbox and "eligible" or "UNKNOWN / excluded")
            .. " @"
            .. source.inboxAt
    end
    return lines
end

local function output(title, lines, copy)
    if copy then
        if not RQ.Api.ShowCopyWindow(title, table.concat(lines, "\n")) then
            return false, "Copy window unavailable; retry without 'copy' for chat output."
        end
    else
        for _, line in ipairs(lines) do
            RQ.Api.Print(line)
        end
    end
    return true
end

function Service.Command(command, argument)
    if not RQ.Database.initialized then
        return false, "Logistics unavailable: " .. tostring(RQ.Database.status)
    end
    argument = trim(argument or "")
    if command == "routing-item" then
        local category, item, toggle = argument:match("^(%S+)%s+(%d+)%s+(%S+)$")
        if toggle ~= "on" and toggle ~= "off" then
            return false, "Use /rq routing-item <category> <item ID> on|off."
        end
        return Service.SetItem(category, tonumber(item), toggle == "on")
    elseif command == "routing-priority" then
        local category, list = argument:match("^(%S+)%s+(.+)$")
        if not list then
            return false, "Use /rq routing-priority <category> <member[,member...]|clear>."
        end
        local queries = {}
        if list ~= "clear" then
            for query in (list .. ","):gmatch("(.-),") do
                queries[#queries + 1] = trim(query)
            end
        end
        return Service.SetRecipients(category, queries)
    elseif command == "reserve" then
        local kind, item, count, query = argument:match("^(%S+)%s+(%d+)%s+(%d+)%s*(.-)$")
        return Service.SetReserve(kind, tonumber(item), tonumber(count), query)
    end
    local copy = argument == "copy" or argument:match("^copy%s") ~= nil
    if copy then
        argument = trim(argument:sub(5))
    end
    local now = RQ.Api.GetServerTime()
    local lines, err
    local verified = RQ.MailService.Verified(RQDB)
    if command == "routing" and argument == "" then
        lines, err = Service.RoutingReport(RQDB)
    elseif command == "reserves" then
        local id
        id, err = RQ.Database.ResolveMember(argument ~= "" and argument or RQ.Database.activeId)
        if id then
            lines, err = Service.ReserveReport(RQDB, id, now, verified)
        end
    elseif command == "material-totals" then
        lines, err = Service.MaterialReport(RQDB, now, verified, argument)
    else
        return false, "Use routing, routing-item, routing-priority, reserve, reserves or material-totals."
    end
    if not lines then
        return false, err
    end
    return output("Logistics: " .. command, lines, copy)
end
