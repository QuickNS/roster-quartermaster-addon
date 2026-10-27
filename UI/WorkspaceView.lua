local View = {}
RQ.WorkspaceView = View

local text = RQ.CharacterCard.Text

function View.Roster(account, view, report, activeId, plan)
    local recommendations = {}
    for _, card in ipairs(RQ.TodayPanel.Build(account, report, view.cards, activeId, plan)) do
        if card.id then
            recommendations[card.id] = card
        end
    end
    for _, card in ipairs(view.cards) do
        local suggested = recommendations[card.id]
        if suggested then
            card.detail = suggested.detail
            card.action, card.actionKind = suggested.action, suggested.actionKind
            card.visual = suggested.visual
        end
        local record = account.characters[card.id]
        if record then
            local snapshot = record.snapshot
            card.visual.money = RQ.Util.Money(snapshot.money)
            card.groceriesAction = record.registration == "member" and account.roster[card.id] ~= nil
            card.summary = table.concat({
                card.visual.badges,
                "Level " .. text(snapshot.level) .. "  |  " .. text(snapshot.zone),
                "Wallet  "
                    .. RQ.Util.Money(snapshot.money)
                    .. "  |  "
                    .. RQ.Snapshot.SectionState(snapshot, "money", report.now, account.policies.staleSnapshotHours),
                "Free bag slots  "
                    .. text(snapshot.freeBagSlots)
                    .. " / "
                    .. text(snapshot.bagSlots)
                    .. "  |  "
                    .. RQ.Snapshot.SectionState(snapshot, "bags", report.now, account.policies.staleSnapshotHours),
                card.visual.rested.label .. "  (" .. card.visual.rested.badge .. ")",
                card.visual.freshness .. "  |  " .. card.visual.age,
                suggested and ("Next session: " .. text(suggested.visual.reason)) or "Not in the play-next rotation.",
                "Grocery list: "
                    .. #RQ.Util.Keys(
                        plan.groceries[card.id]
                            or RQ.SuppliesService.Grocery(record, report.now, account.policies.staleSnapshotHours)
                    )
                    .. " material/stock target(s). Use Grocery list below to review quantities and recipe sources.",
            }, "\n\n")
        end
    end
    local first
    for _, recommendation in ipairs(report.recommendations) do
        local identity = account.characters[recommendation.characterId].identity
        if not view.group or view.group == "all" or (RQ.Character.TradeGroup(identity) or "~unknown") == view.group then
            first = recommendation
            break
        end
    end
    if first then
        local identity = account.characters[first.characterId].identity
        view.headline = "PLAY NEXT  " .. text(RQ.Character.DisplayName(identity)) .. " - " .. text(identity.realm)
    else
        view.headline = "YOUR ROSTER  |  Add a character"
    end
end

View.groceryFilters = {
    all = "All",
    missing = "Shortages",
    collection = "Collect / incoming",
    covered = "Covered",
    unknown = "Unknown",
}

function View.Stock(account, plan, owner, now, filter, expanded)
    local cards = {}
    filter = filter or "all"
    local ranks = { missing = 1, unknown = 2, collection = 3, covered = 4 }
    for _, id in ipairs(plan.ids) do
        if not owner or owner == id then
            local record = account.characters[id]
            local label = text(RQ.Character.DisplayName(record.identity))
            local stockState = RQ.SuppliesConfig.IsFresh(
                record.inventory.bags,
                now,
                account.policies.staleSnapshotHours
            ) and "RECENT" or "STALE / INCOMPLETE"
            local counts, items = { missing = 0, collection = 0, covered = 0, unknown = 0 }, {}
            for item, need in pairs(plan.groceries[id]) do
                local state = RQ.SuppliesService.GroceryState(need)
                counts[state] = counts[state] + 1
                if filter == "all" or filter == state then
                    items[#items + 1] = item
                end
            end
            table.sort(items, function(a, b)
                local left = ranks[RQ.SuppliesService.GroceryState(plan.groceries[id][a])]
                local right = ranks[RQ.SuppliesService.GroceryState(plan.groceries[id][b])]
                if left ~= right then
                    return left < right
                end
                return a < b
            end)
            cards[#cards + 1] = {
                id = id,
                title = label .. " - Grocery list",
                summary = (
                    next(plan.groceries[id])
                        and "Shortages first. Select Recipes / details on an item for its sources."
                    or "No current targets. Scan learned orange recipes or set /rq need."
                )
                    .. "\n"
                    .. stockState
                    .. " | "
                    .. counts.unknown
                    .. " unknown | Showing: "
                    .. View.groceryFilters[filter]
                    .. (not account.roster[id].enabled and "\nDisabled member: review only; no mail proposals." or "")
                    .. (next(plan.groceries[id]) and #items == 0 and "\nNo items match this filter." or ""),
                body = table.concat(plan.notes[id], "\n"),
                metrics = {
                    {
                        label = "Shortages",
                        value = tostring(counts.missing),
                        tone = counts.missing > 0 and "warning" or nil,
                    },
                    { label = "Collect / incoming", value = tostring(counts.collection) },
                    { label = "Covered", value = tostring(counts.covered), tone = "positive" },
                },
                actionKind = "supplies",
                action = "Full report",
                recipesAction = true,
            }
            for _, item in ipairs(items) do
                local need = plan.groceries[id][item]
                local state = RQ.SuppliesService.GroceryState(need)
                cards[#cards + 1] = {
                    id = id,
                    itemId = item,
                    title = "Item " .. item,
                    groceryItem = true,
                    expanded = expanded and expanded[id .. ":" .. item] == true,
                    summary = View.groceryFilters[state]
                        .. " | "
                        .. label
                        .. "  |  "
                        .. stockState
                        .. (need.reserveKind and ("  |  " .. need.reserveKind .. " reserve") or "")
                        .. ((need.orangeTarget or 0) > 0 and "  |  Auto orange recipes" or "")
                        .. (need.orangeStale and "  |  Recipe evidence STALE" or "")
                        .. (
                            state == "collection"
                                and "\nWithdraw or collect manually; incoming mail is provisional."
                            or ""
                        ),
                    body = table.concat({
                        "Item ID: " .. item,
                        "Owner: " .. label .. " [" .. id .. "]",
                        "Bag scan: " .. record.inventory.bags.scannedAt,
                        "Bank observed: " .. text(need.bankHave),
                        "Pending/inbox amounts are provisional. Missing counts use known eligible stock only.",
                        table.concat(RQ.SuppliesService.OrangeSourceLines(need), "\n"),
                        #(need.orangeRecipes or {}) == 0 and "Manual stock/reserve, recipe goal or bag-upgrade target."
                            or "Orange recipe quantities are for one craft each, not guaranteed skill gains.",
                    }, "\n"),
                    metrics = {
                        { label = "Target", value = text(need.target) },
                        { label = "In bags", value = text(need.have) },
                        {
                            label = "Still needed",
                            value = text(need.missing),
                            tone = state == "missing" and "warning" or state == "covered" and "positive" or nil,
                        },
                        { label = "Withdraw", value = text(need.withdraw) },
                        { label = "Collect mail", value = text(need.collect) },
                        { label = "In transit", value = text(need.inTransit) },
                    },
                    actionKind = "grocery-need",
                    action = "Save stock",
                    stockTarget = record.supplies.needs[item] or 0,
                }
            end
        end
    end
    if #cards == 0 then
        cards[1] = {
            title = "No stock targets in this scope",
            summary = "Choose an enabled roster member to plan supplies.",
            body = "Disabled members remain searchable but do not participate in supply planning.",
            action = "Manage roster",
        }
    end
    return cards
end

function View.Search(cards, result, now)
    cards[1].summary = "Observed items, not available surplus. Bank and mail are separate cached sources."
        .. (result.unresolvedNames > 0 and "\nSome item names are unavailable; name matches may be incomplete." or "")
    cards[1].metrics = {
        { label = "Matches", value = tostring(#result.matches) },
        { label = "Stale sources", value = tostring(result.states.STALE), tone = "warning" },
        { label = "Unknown / partial sources", value = result.states.UNKNOWN .. " / " .. result.states.INCOMPLETE },
    }
    for index, match in ipairs(result.matches) do
        local card = cards[index + 1]
        card.title = text(match.itemName or ("Item " .. match.itemId))
        card.body = "Item ID: " .. match.itemId .. "\n" .. card.body
        card.summary = text(match.characterName)
            .. "  |  "
            .. text(match.realm)
            .. "  |  "
            .. match.state
            .. "\nCached observations, not transferable surplus."
        card.metrics = {
            { label = "Quantity", value = tostring(match.quantity) },
            { label = "Storage", value = match.source },
            { label = "Observed", value = RQ.CharacterCard.Age(match.scannedAt, now) },
        }
    end
end

function View.Inventory(account, owner, now, query, sourceFilter, expanded)
    local cards = {}
    local numeric = query:match("^%d+$") and tonumber(query)
    for _, id in ipairs(RQ.InventorySearch.CharacterIds(account)) do
        if not owner or owner == id then
            local record = account.characters[id]
            for _, source in ipairs({ "bags", "bank", "mail" }) do
                if sourceFilter == "all" or sourceFilter == source then
                    local scan = record.inventory[source]
                    local key = id .. ":" .. source
                    local open = expanded[key]
                    if open == nil then
                        open = query ~= ""
                    end
                    local state = scan.scannedAt == 0 and "UNKNOWN"
                        or not scan.complete and "INCOMPLETE"
                        or RQ.SuppliesConfig.IsFresh(scan, now, account.policies.staleSnapshotHours) and "RECENT"
                        or "STALE"
                    local containers = {}
                    if source == "bags" then
                        for slot, capacity in ipairs(scan.equipped or {}) do
                            containers[#containers + 1] = "Bag " .. slot .. ": " .. capacity .. " slots"
                        end
                    end
                    for _, containerId in ipairs(RQ.Util.Keys(scan.containers or {})) do
                        local container = scan.containers[containerId]
                        containers[#containers + 1] = "Bag "
                            .. containerId
                            .. ": "
                            .. text(container.capacity)
                            .. " slots"
                    end
                    cards[#cards + 1] = {
                        id = id,
                        source = source,
                        actionKind = "inventory-expand",
                        title = text(RQ.Character.DisplayName(record.identity)) .. " - " .. source,
                        summary = table.concat(containers, " | ")
                            .. (#containers > 0 and "\n" or "")
                            .. state
                            .. " | Observed "
                            .. RQ.CharacterCard.Age(scan.scannedAt, now)
                            .. " | "
                            .. #RQ.Util.Keys(scan.items)
                            .. " item types",
                        body = table.concat(containers, "\n")
                            .. (scan.error and ("\nScan error: " .. text(scan.error)) or "")
                            .. "\nRecorded snapshot, not live stock. Visit the character/bank to refresh.",
                        action = open and "Collapse" or "Expand",
                    }
                    if open then
                        for _, item in ipairs(RQ.Util.Keys(scan.items)) do
                            local label, known = RQ.SuppliesService.ItemLabel(account, item, record)
                            local match = query == ""
                                or (numeric and numeric == item)
                                or (not numeric and known and label:lower():find(query:lower(), 1, true) ~= nil)
                            cards[#cards + 1] = {
                                id = id,
                                itemId = item,
                                compact = true,
                                actionKind = "inventory-owner",
                                muted = not match,
                                title = scan.items[item] .. " x " .. text(label) .. " [" .. item .. "]",
                                body = source .. " | " .. state,
                                summary = "",
                                action = "Details",
                                disabled = true,
                            }
                        end
                    end
                end
            end
        end
    end
    if #cards == 0 then
        cards[1] = {
            title = "No recorded inventory in this scope",
            body = "Choose a roster group or register a character.",
            action = "Manage roster",
        }
    end
    return cards
end

function View.Recipes(account, owner, now)
    local cards = {}
    for _, id in ipairs(RQ.InventorySearch.CharacterIds(account)) do
        if not owner or owner == id then
            local prices = {}
            local recipeCards = RQ.SuppliesService.RecipeCards(account, id, now)
            for _, card in ipairs(recipeCards) do
                if card.recipeId then
                    local recipe = account.characters[id].recipes.professions[card.professionId].recipes[card.recipeId]
                    local unavailable
                    for item in pairs(recipe.reagents) do
                        if prices[item] == nil then
                            local price, reason = RQ.Api.GetAuctionPrice(item, account.characters[id].identity)
                            prices[item] = price or false
                            unavailable = reason or unavailable
                        end
                    end
                    local cost, missing = RQ.WorkspaceScope.CraftCost(recipe.reagents, prices)
                    card.summary = (card.disabled and "Disabled member: review only.\n" or "")
                        .. "ORANGE | Estimated craft cost: "
                        .. (cost and RQ.Util.Money(cost) or ("unavailable (" .. #missing .. " reagent prices missing)"))
                        .. "\nAuctionator cached unit prices; not a live quote or guaranteed purchase price."
                        .. (unavailable and ("\n" .. unavailable) or "")
                    card.expanded = true
                else
                    card.title = text(RQ.Character.DisplayName(account.characters[id].identity)) .. " - " .. card.title
                end
                cards[#cards + 1] = card
            end
        end
    end
    if #cards == 0 then
        cards[1] = {
            title = "No members in this scope",
            body = "Choose a realm/faction group or register a character.",
            action = "Manage roster",
        }
    end
    return cards
end

function View.CompactGroceries(account, plan, owner)
    local lines = {
        "Missing / target | Item | Character",
        "Cached stock; bank and incoming mail may be provisional.",
    }
    for _, id in ipairs(plan.ids) do
        if not owner or owner == id then
            local record = account.characters[id]
            for _, item in ipairs(RQ.Util.Keys(plan.groceries[id])) do
                local need = plan.groceries[id][item]
                lines[#lines + 1] = text(need.missing)
                    .. " / "
                    .. text(need.target)
                    .. " | "
                    .. text(RQ.SuppliesService.ItemLabel(account, item, record))
                    .. " | "
                    .. text(RQ.Character.DisplayName(record.identity))
            end
        end
    end
    if #lines == 2 then
        lines[#lines + 1] = "No grocery targets in this scope."
    end
    return lines
end
