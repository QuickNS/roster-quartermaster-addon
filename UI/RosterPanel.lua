local Panel = {}
RQ.RosterPanel = Panel

Panel.sorts = { "name", "level", "priority", "profession", "class" }
Panel.filters = { "all", "members", "behind", "uncertain" }

function Panel.SelectRows(cards, options, preserveOrder)
    options = options or {}
    local rows, realms, groups = {}, { all = "All realms" }, { all = "All trade groups" }
    for _, card in ipairs(cards) do
        local item = card.visual
        if item then
            realms[item.realmKey] = item.realm
            groups[item.groupKey or "~unknown"] = item.groupLabel or "Unknown ruleset / faction"
        end
    end
    local realm = realms[options.realm] and options.realm or "all"
    local group = groups[options.group] and options.group or "all"
    local filter = options.filter or "all"
    for _, card in ipairs(cards) do
        local item = card.visual
        if
            item
            and (realm == "all" or item.realmKey == realm)
            and (group == "all" or (item.groupKey or "~unknown") == group)
            and (
                filter == "all"
                or (filter == "members" and item.member)
                or (filter == "behind" and item.behind > 0)
                or (filter == "uncertain" and item.uncertain)
            )
        then
            rows[#rows + 1] = card
        end
    end
    if not preserveOrder then
        table.sort(rows, function(a, b)
            local first, second = a.visual, b.visual
            if group == "all" and first.groupKey ~= second.groupKey then
                return (first.groupKey or "~unknown") < (second.groupKey or "~unknown")
            end
            if realm == "all" and first.realmKey ~= second.realmKey then
                return first.realmKey < second.realmKey
            end
            local left, right
            if options.sort == "level" then
                left, right = first.level or math.huge, second.level or math.huge
            elseif options.sort == "priority" then
                left, right = first.rank or math.huge, second.rank or math.huge
            elseif options.sort == "profession" then
                left, right = -first.deficit, -second.deficit
            elseif options.sort == "class" then
                left, right = first.class or "~unknown", second.class or "~unknown"
            else
                left, right = first.name:lower(), second.name:lower()
            end
            if left ~= right then
                return left < right
            end
            return a.id < b.id
        end)
    end
    return rows, realms, realm, groups, group
end

function Panel.Build(account, activeId, now, selectedId, estimates, options, recommendations)
    local characterIds = RQ.Util.Keys(account.characters)
    if not selectedId or not account.characters[selectedId] then
        selectedId = activeId and account.characters[activeId] and activeId or characterIds[1]
    end
    local cards = {}
    for _, id in ipairs(characterIds) do
        if account.characters[id].registration == "member" and account.roster[id] then
            cards[#cards + 1] = RQ.CharacterCard.Build(
                id,
                account.characters[id],
                account.roster[id],
                now,
                activeId,
                account.policies.staleSnapshotHours,
                estimates and estimates[id],
                account.settings.professionLag
            )
        end
    end
    local ranks = {}
    for index, recommendation in ipairs(recommendations or {}) do
        ranks[recommendation.characterId] = index
    end
    for _, card in ipairs(cards) do
        card.visual.rank = ranks[card.id]
        if RQ.LogisticsPolicies.Cook(account, account.characters[card.id].identity) == card.id then
            card.visual.badges = card.visual.badges == "" and "COOK / FISH" or card.visual.badges .. " / COOK / FISH"
        end
    end
    local rows, realms, realm, groups, group = Panel.SelectRows(cards, options)
    if options and options.selectVisible and group ~= "all" then
        local selected = selectedId and account.characters[selectedId]
        if not selected or (RQ.Character.TradeGroup(selected.identity) or "~unknown") ~= group then
            selectedId = nil
            for _, card in ipairs(cards) do
                if card.visual.groupKey == group then
                    selectedId = card.id
                    break
                end
            end
        end
    end
    local record = selectedId and account.characters[selectedId]
    local entry = selectedId and account.roster[selectedId]
    local text = RQ.CharacterCard.Text
    local characterLabel = "No character snapshots yet"
    local characterDetails = "Log in and run /rq rescan."
    if record then
        characterLabel = text(RQ.Character.DisplayName(record.identity))
            .. " - "
            .. text(record.identity.realm)
            .. " ["
            .. record.registration
            .. "]"
        characterDetails = "ID: " .. text(selectedId) .. "\nTrade: " .. RQ.Character.TradeGroupLabel(record.identity)
    end
    local cook = record and RQ.LogisticsPolicies.Cook(account, record.identity)
    return {
        cards = cards,
        rows = rows,
        realms = realms,
        realm = realm,
        groups = groups,
        group = group,
        ruleset = record and record.identity.ruleset or "Unknown",
        canSetRuleset = record and record.registration == "member" and entry and not RQ.Character.RulesetFromRealm(
            record.identity.realm
        ) or false,
        canSetCook = record
                and entry
                and entry.enabled
                and record.registration == "member"
                and record.identity.guid == selectedId
                and RQ.Character.TradeGroup(record.identity) ~= nil
            or false,
        isCook = cook ~= nil and cook == selectedId,
        cookLabel = cook and text(RQ.Character.DisplayName(account.characters[cook].identity)) or "Unassigned",
        sort = options and options.sort or "name",
        filter = options and options.filter or "all",
        characterIds = characterIds,
        selectedId = selectedId,
        characterLabel = characterLabel,
        characterDetails = characterDetails,
        role = entry and entry.role or "UNASSIGNED",
        roleLabel = text(entry and (RQ.Character.roleLabels[entry.role] or entry.role) or "Unassigned"),
        isMember = record and record.registration == "member" and entry and entry.enabled == true or false,
        isMain = entry and entry.isMain == true or false,
        multiplier = entry and entry.restedMultiplier or 1,
        resourceBlocker = entry and entry.resourceBlocker == true or false,
        dungeonReady = entry and entry.dungeonReady == true or false,
        planning = account.settings.planning,
        professionCeiling = account.settings.professionLag and account.settings.professionLag.ceiling or 300,
        isIgnored = record and record.registration == "ignored" or false,
    }
end
