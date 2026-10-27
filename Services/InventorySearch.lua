local Search = {}
RQ.InventorySearch = Search
Search.sources = { "all", "bags", "bank", "mail" }

local function sources(filter)
    return filter == "bags" and { "bags" }
        or filter == "bank" and { "bank" }
        or filter == "mail" and { "mail" }
        or { "bags", "bank", "mail" }
end

local function sourceData(account, id, source, now, verified)
    local data = account.characters[id].inventory[source]
    if source ~= "mail" then
        return data
    end
    data = RQ.Util.Copy(data)
    local coverage = RQ.MailTracker.Coverage(account, id, now, verified)
    data.pending = coverage.pending
    data.origins = coverage.pendingSources
    for _, message in ipairs(data.messages or {}) do
        for item, count in pairs(message.items) do
            data.origins[item] = data.origins[item] or {}
            table.insert(data.origins[item], {
                sender = message.sender,
                quantity = count,
                state = message.returned and "returned inbox" or message.cod > 0 and "COD inbox" or "observed inbox",
                at = data.scannedAt,
            })
        end
    end
    for _, entries in pairs(data.origins) do
        table.sort(entries, function(a, b)
            if a.sender ~= b.sender then
                return a.sender < b.sender
            end
            if a.state ~= b.state then
                return a.state < b.state
            end
            return (a.transferId or 0) < (b.transferId or 0)
        end)
    end
    for item, count in pairs(coverage.pending) do
        data.items[item] = (data.items[item] or 0) + count
    end
    return data
end

function Search.NormalizeQuery(query)
    if type(query) ~= "string" or #query > 128 then
        return nil, "Search must be text of at most 128 bytes."
    end
    query = query:match("^%s*(.-)%s*$")
    if query:match("^%d+$") and not RQ.SuppliesConfig.Id(tonumber(query)) then
        return nil, "Search item ID must be an integer from 1 to 2147483647."
    end
    return query
end

function Search.CharacterIds(account)
    local ids = {}
    for _, id in ipairs(RQ.Util.Keys(account.characters)) do
        if account.characters[id].registration == "member" and account.roster[id] then
            ids[#ids + 1] = id
        end
    end
    return ids
end

function Search.ItemIds(account, characterId, sourceFilter)
    local items = {}
    for _, id in ipairs(Search.CharacterIds(account)) do
        if not characterId or characterId == id then
            local record = account.characters[id]
            for _, source in ipairs(sources(sourceFilter)) do
                local bags = record.inventory and record.inventory[source]
                for itemId, count in pairs(bags and bags.items or {}) do
                    if count > 0 then
                        items[itemId] = true
                    end
                end
            end
        end
    end
    if sourceFilter == nil or sourceFilter == "all" or sourceFilter == "mail" then
        for _, transfer in pairs(account.mailTracking and account.mailTracking.transfers or {}) do
            if not characterId or characterId == transfer.recipientId then
                for id in pairs(transfer.remaining) do
                    items[id] = true
                end
            end
        end
    end
    return RQ.Util.Keys(items)
end

local function state(bags, now, hours, source)
    if not bags or not bags.scannedAt or bags.scannedAt == 0 then
        return "UNKNOWN"
    end
    if not bags.complete or (source ~= "bags" and bags.coherent ~= true) then
        return "INCOMPLETE"
    end
    return RQ.SuppliesConfig.IsFresh(bags, now, hours) and "RECENT" or "STALE"
end

function Search.Evaluate(account, query, now, characterId, labels, sourceFilter, verified)
    local err
    query, err = Search.NormalizeQuery(query)
    if not query then
        return nil, err
    end
    if query == "" then
        return nil, "Enter an item name or exact item ID."
    end
    sourceFilter = sourceFilter or "all"
    if sourceFilter ~= "all" and sourceFilter ~= "bags" and sourceFilter ~= "bank" and sourceFilter ~= "mail" then
        return nil, "Inventory source must be all, bags, bank or mail."
    end
    local ids = Search.CharacterIds(account)
    if characterId then
        local found = false
        for _, id in ipairs(ids) do
            found = found or id == characterId
        end
        if not found then
            return nil, "Search owner is no longer a registered roster member."
        end
    end
    local result = {
        query = query,
        sourceFilter = sourceFilter,
        ownerCount = 0,
        matches = {},
        coverage = {},
        unresolvedNames = 0,
        ownersWithMatches = 0,
        states = { RECENT = 0, STALE = 0, INCOMPLETE = 0, UNKNOWN = 0 },
    }
    local numeric = query:match("^%d+$") and tonumber(query)
    local needle, unresolved, matchedOwners = query:lower(), {}, {}
    for _, id in ipairs(ids) do
        if not characterId or characterId == id then
            result.ownerCount = result.ownerCount + 1
            local record = account.characters[id]
            for _, source in ipairs(sources(sourceFilter)) do
                local bags = sourceData(account, id, source, now, verified)
                local coverage = {
                    characterId = id,
                    characterName = RQ.Character.DisplayName(record.identity) or id,
                    realm = record.identity.realm or "Unknown realm",
                    realmKey = RQ.Character.Realm(record.identity) or "~unknown",
                    enabled = account.roster[id].enabled == true,
                    source = source,
                    scannedAt = bags and bags.scannedAt or 0,
                    state = state(bags, now, account.policies.staleSnapshotHours, source),
                    error = bags and bags.error,
                    coherent = source == "bags" or (bags and bags.coherent == true),
                }
                result.coverage[#result.coverage + 1] = coverage
                result.states[coverage.state] = result.states[coverage.state] + 1
                for _, itemId in ipairs(RQ.Util.Keys(bags and bags.items or {})) do
                    local quantity = bags.items[itemId]
                    if quantity > 0 then
                        local detail = bags.details and bags.details[itemId]
                        local name = detail and detail.name or labels and labels[itemId]
                        if not name then
                            unresolved[itemId] = true
                        end
                        if
                            (numeric and itemId == numeric)
                            or (not numeric and name and name:lower():find(needle, 1, true))
                        then
                            local match = RQ.Util.Copy(coverage)
                            match.itemId, match.itemName, match.quantity = itemId, name, quantity
                            if source == "mail" then
                                match.pending = bags.pending[itemId] or 0
                                match.origins = bags.origins[itemId]
                            end
                            if source == "bank" then
                                match.containers = {}
                                for _, containerId in ipairs(RQ.Util.Keys(bags.containers or {})) do
                                    local container = bags.containers[containerId]
                                    if (container.items[itemId] or 0) > 0 then
                                        match.containers[#match.containers + 1] = {
                                            id = containerId,
                                            count = container.items[itemId],
                                            capacity = container.capacity,
                                        }
                                    end
                                end
                            end
                            result.matches[#result.matches + 1] = match
                            matchedOwners[id] = true
                        end
                    end
                end
            end
        end
    end
    table.sort(result.matches, function(a, b)
        if a.realmKey ~= b.realmKey then
            return a.realmKey < b.realmKey
        end
        if a.characterName:lower() ~= b.characterName:lower() then
            return a.characterName:lower() < b.characterName:lower()
        end
        if a.characterId ~= b.characterId then
            return a.characterId < b.characterId
        end
        local first, second = (a.itemName or ""):lower(), (b.itemName or ""):lower()
        if first ~= second then
            return first < second
        end
        if a.itemId ~= b.itemId then
            return a.itemId < b.itemId
        end
        return a.source < b.source
    end)
    result.unresolvedNames = #RQ.Util.Keys(unresolved)
    result.ownersWithMatches = #RQ.Util.Keys(matchedOwners)
    return result
end
