local Supplies = { generation = 0 }
RQ.SuppliesService = Supplies

local function save(id, field, value)
    local ok, err = RQ.Database.SaveLogistics(id, field, value)
    if not ok then
        RQ.Api.Print("Supplies not saved: " .. err)
    end
    return ok, err
end

function Supplies.ScanBags()
    local record = RQ.Database.Current()
    if not record or record.registration == "ignored" then
        return
    end
    local scan, err = RQ.Api.GetBagItems()
    local inventory = RQ.Util.Copy(record.inventory)
    if scan then
        inventory.bags = scan
    else
        inventory.bags.complete, inventory.bags.error = false, err
        if record.inventory.bags.error ~= err then
            RQ.Api.Print("Bag contents unavailable: " .. err)
        end
    end
    return save(RQ.Database.activeId, "inventory", inventory)
end

function Supplies.ScanRecipes()
    local record = RQ.Database.Current()
    if not record or record.registration == "ignored" then
        return
    end
    local observation, err = RQ.Api.GetProfessionRecipes()
    local recipes = RQ.Util.Copy(record.recipes)
    if observation then
        recipes.professions[observation.professionId] = observation.scan
        recipes.scannedAt, recipes.error = observation.scan.scannedAt, nil
    else
        recipes.error = err
        if record.recipes.error ~= err then
            RQ.Api.Print("Recipes not refreshed: " .. err)
        end
    end
    -- Opening one profession never proves that every profession has been scanned.
    recipes.complete = false
    return save(RQ.Database.activeId, "recipes", recipes)
end

function Supplies.QueueRecipes()
    if Supplies.scheduled then
        return
    end
    Supplies.scheduled = true
    local generation = Supplies.generation
    local function scan()
        if generation ~= Supplies.generation then
            return
        end
        Supplies.scheduled = false
        Supplies.ScanRecipes()
    end
    if not RQ.Api.After(0.5, scan) then
        scan()
    end
end

function Supplies.Cancel()
    Supplies.generation = Supplies.generation + 1
    Supplies.scheduled = false
end

local function selected(query)
    if query and query ~= "" then
        return RQ.Database.ResolveMember(query)
    end
    local id = RQ.Database.activeId
    if not id then
        return nil, "Current character unavailable."
    end
    return RQ.Database.ResolveMember(id)
end

function Supplies.SetNeed(itemId, count, query)
    local id, err = selected(query)
    if not id then
        return false, err
    end
    if not RQ.SuppliesConfig.Id(itemId) or not RQ.SuppliesConfig.Count(count) then
        return false, "Use /rq need <item ID> <target quantity; 0 clears> [name|slot|ID]."
    end
    local config = RQ.Util.Copy(RQDB.characters[id].supplies)
    config.needs[itemId] = count > 0 and count or nil
    return save(id, "supplies", config)
end

function Supplies.SetGoal(professionId, recipeId, targetSkill, query)
    local id, err = selected(query)
    if not id then
        return false, err
    end
    if
        not RQ.SuppliesConfig.Id(professionId)
        or not RQ.SuppliesConfig.Count(targetSkill)
        or (targetSkill > 0 and not RQ.SuppliesConfig.Id(recipeId))
    then
        return false, "Use /rq goal <profession ID> <recipe ID> <target skill; 0 clears> [member]."
    end
    local record = RQDB.characters[id]
    local scan = record.recipes.professions[professionId]
    if targetSkill > 0 and (not scan or not scan.recipes[recipeId]) then
        return false, "Open and scan that character's profession first; use /rq recipes for observed recipe IDs."
    end
    local config = RQ.Util.Copy(record.supplies)
    config.goals[professionId] = targetSkill > 0 and { recipeId = recipeId, targetSkill = targetSkill } or nil
    return save(id, "supplies", config)
end

local function fresh(source, now, hours)
    return source.complete
        and RQ.Util.IsNumber(now)
        and source.scannedAt > 0
        and now >= source.scannedAt
        and now - source.scannedAt < hours * 3600
end

function Supplies.Grocery(record, now, hours)
    local targets, planned, notes = RQ.Util.Copy(record.supplies.needs), {}, {}
    for _, professionId in ipairs(RQ.Util.Keys(record.supplies.goals)) do
        local goal = record.supplies.goals[professionId]
        local profession = record.snapshot.professions and record.snapshot.professions[professionId]
        local scan = record.recipes.professions[professionId]
        local recipe = scan and scan.recipes[goal.recipeId]
        if not profession or not recipe or not recipe.reagentsComplete or recipe.skillUps == 0 then
            notes[#notes + 1] = "Goal "
                .. professionId
                .. ": missing skill/material data or no skill-up; rescan or change recipe."
        else
            local section = record.snapshot.sections and record.snapshot.sections.professions
            if not section or not section.complete then
                notes[#notes + 1] = "Profession skill observation is incomplete; targets use cached data."
            end
            if now and hours then
                local skillSource = {
                    complete = section and section.complete or false,
                    scannedAt = section and section.observedAt or 0,
                }
                if not fresh(skillSource, now, hours) or not fresh(scan, now, hours) or record.recipes.error then
                    notes[#notes + 1] =
                        "STALE / uncertain profession evidence: rescan this character before relying on the goal."
                end
            end
            local crafts = math.ceil(math.max(0, goal.targetSkill - profession.skill) / recipe.skillUps)
            notes[#notes + 1] = scan.name
                .. ": "
                .. profession.skill
                .. " -> "
                .. goal.targetSkill
                .. " using "
                .. recipe.name
                .. " ["
                .. goal.recipeId
                .. "], approximately "
                .. crafts
                .. " crafts."
            notes[#notes + 1] = "Estimate assumes "
                .. recipe.skillUps
                .. " skill point(s) per craft; skill-ups are not guaranteed."
            if goal.targetSkill > profession.maxSkill then
                notes[#notes + 1] = "Current profession cap is "
                    .. profession.maxSkill
                    .. "; train/unlock a higher cap first."
            end
            if not recipe.learned then
                notes[#notes + 1] = "Recipe not learned. Acquire: "
                    .. (recipe.source or "source unknown; consult a verified guide")
                if recipe.sourceItem and crafts > 0 then
                    targets[recipe.sourceItem] = math.max(1, targets[recipe.sourceItem] or 0)
                end
            end
            for itemId, quantity in pairs(recipe.reagents) do
                planned[itemId] = (planned[itemId] or 0) + crafts * quantity
            end
        end
    end
    for item, quantity in pairs(planned) do
        targets[item] = math.max(targets[item] or 0, quantity)
    end
    local grocery = {}
    for item, target in pairs(targets) do
        local have = record.inventory.bags.complete and (record.inventory.bags.items[item] or 0) or nil
        grocery[item] = { target = target, have = have, missing = have and math.max(0, target - have) or nil }
    end
    return grocery, notes
end

function Supplies.Evaluate(account, sourceId, now)
    local groceries, notes, ids = {}, {}, {}
    for _, id in ipairs(RQ.Util.Keys(account.roster)) do
        local record = account.characters[id]
        if account.roster[id].enabled and record and record.registration == "member" then
            ids[#ids + 1] = id
            groceries[id], notes[id] = Supplies.Grocery(record, now, account.policies.staleSnapshotHours)
        end
    end
    local result = { groceries = groceries, notes = notes, proposals = {}, warnings = {} }
    local source = account.characters[sourceId]
    local hours = account.policies.staleSnapshotHours
    if not source or source.registration == "ignored" or not fresh(source.inventory.bags, now, hours) then
        result.warnings[1] = "Scan the active character's bags before generating mail proposals."
        return result
    end
    local available = {}
    local reserves = groceries[sourceId] or Supplies.Grocery(source)
    for item, count in pairs(source.inventory.bags.tradable) do
        local surplus =
            math.max(0, (source.inventory.bags.items[item] or 0) - (reserves[item] and reserves[item].target or 0))
        available[item] = math.min(count, surplus)
    end
    local ownEmpty = 0
    for _, slots in pairs(source.inventory.bags.equipped) do
        if slots == 0 then
            ownEmpty = ownEmpty + 1
        end
    end
    for _, item in ipairs(RQ.Util.Keys(available)) do
        local detail = source.inventory.bags.details[item] or {}
        if detail.classId == 1 and detail.subclassId == 0 then
            local keep = math.min(ownEmpty, available[item])
            available[item], ownEmpty = available[item] - keep, ownEmpty - keep
        elseif detail.classId == 9 and not reserves[item] then
            local needed = false
            for _, scan in pairs(source.recipes.professions) do
                for _, recipe in pairs(scan.recipes) do
                    needed = needed or (recipe.sourceItem == item and not recipe.learned)
                end
            end
            if needed then
                available[item] = math.max(0, available[item] - 1)
            end
        end
    end
    local function propose(id, item, count, reason)
        count = math.min(count, available[item] or 0)
        if count < 1 then
            return 0
        end
        result.proposals[#result.proposals + 1] = {
            characterId = id,
            itemId = item,
            count = count,
            reason = reason,
            stale = not fresh(account.characters[id].inventory.bags, now, hours),
        }
        available[item] = available[item] - count
        return count
    end
    for _, id in ipairs(ids) do
        if id ~= sourceId then
            local record = account.characters[id]
            for _, item in ipairs(RQ.Util.Keys(groceries[id])) do
                local need = groceries[id][item]
                if need.missing then
                    propose(id, item, need.missing, "Grocery list / profession milestone")
                end
            end
            if record.inventory.bags.complete then
                local empty, spare = 0, 0
                for _, slots in pairs(record.inventory.bags.equipped) do
                    if slots == 0 then
                        empty = empty + 1
                    end
                end
                for item, detail in pairs(record.inventory.bags.details) do
                    if detail.classId == 1 and detail.subclassId == 0 then
                        spare = spare + (record.inventory.bags.items[item] or 0)
                    end
                end
                for _, proposal in ipairs(result.proposals) do
                    local detail = source.inventory.bags.details[proposal.itemId] or {}
                    if proposal.characterId == id and detail.classId == 1 and detail.subclassId == 0 then
                        spare = spare + proposal.count
                    end
                end
                for _, item in ipairs(RQ.Util.Keys(available)) do
                    local detail = source.inventory.bags.details[item] or {}
                    if detail.classId == 1 and detail.subclassId == 0 and empty > spare then
                        spare = spare + propose(id, item, empty - spare, "Empty equipped bag slots; verify bag size")
                    elseif
                        detail.classId == 9
                        and (record.inventory.bags.items[item] or 0) == 0
                        and not groceries[id][item]
                    then
                        local missingRecipe, recipeStale
                        for _, profession in ipairs(RQ.Util.Keys(record.recipes.professions)) do
                            local scan = record.recipes.professions[profession]
                            for _, recipeId in ipairs(RQ.Util.Keys(scan.recipes)) do
                                local recipe = scan.recipes[recipeId]
                                if recipe.sourceItem == item and not recipe.learned then
                                    missingRecipe = recipe.name
                                    recipeStale = not fresh(scan, now, hours) or record.recipes.error ~= nil
                                    break
                                end
                            end
                            if missingRecipe then
                                break
                            end
                        end
                        if missingRecipe then
                            local sent = propose(
                                id,
                                item,
                                1,
                                "Last observed recipe not learned: "
                                    .. missingRecipe
                                    .. "; verify current recipe knowledge"
                            )
                            if sent > 0 and recipeStale then
                                result.proposals[#result.proposals].stale = true
                            end
                        end
                    end
                end
            end
        end
    end
    result.warnings[#result.warnings + 1] =
        "Manual review only: confirm full recipient name, realm/faction rules, binding and quantities."
    result.warnings[#result.warnings + 1] =
        "Bags only: bank, mail, auctions and in-transit items are not counted. Rescan after sending."
    result.warnings[#result.warnings + 1] =
        "Bound, locked or unknown-binding stacks are excluded; source grocery quantities are reserved."
    return result
end

local function name(record)
    return RQ.Character.DisplayName(record.identity) or "Unknown"
end

function Supplies.Report(id, recipesOnly)
    local record = RQDB.characters[id]
    local lines = { name(record) .. " - " .. (record.identity.realm or "unknown realm"), "Character ID: " .. id }
    if recipesOnly then
        lines[#lines + 1] = "Open each profession on this character to refresh known recipes."
        for _, professionId in ipairs(RQ.Util.Keys(record.recipes.professions)) do
            local scan = record.recipes.professions[professionId]
            lines[#lines + 1] = "\n" .. scan.name .. " [" .. professionId .. "], observed " .. scan.scannedAt
            for _, recipeId in ipairs(RQ.Util.Keys(scan.recipes)) do
                local recipe = scan.recipes[recipeId]
                lines[#lines + 1] = recipeId
                    .. ": "
                    .. recipe.name
                    .. (recipe.learned and " [KNOWN]" or " [NOT LEARNED]")
                lines[#lines + 1] = "  Acquire: " .. (recipe.source or "source unavailable")
                lines[#lines + 1] = "  Materials: "
                    .. (recipe.reagentsComplete and "observed" or "incomplete / alternatives")
                for _, item in ipairs(RQ.Util.Keys(recipe.reagents)) do
                    lines[#lines + 1] = "    Item " .. item .. " x" .. recipe.reagents[item]
                end
            end
        end
        if record.recipes.error then
            lines[#lines + 1] = "Last scan: " .. record.recipes.error
        end
        lines[#lines + 1] = "\nFocus: /rq goal <profession ID> <recipe ID> <target skill> [member]"
    else
        local grocery, notes = Supplies.Grocery(record, RQ.Api.GetServerTime(), RQDB.policies.staleSnapshotHours)
        local bags = record.inventory.bags
        lines[#lines + 1] = "Bag scan: "
            .. bags.scannedAt
            .. " | "
            .. (fresh(bags, RQ.Api.GetServerTime(), RQDB.policies.staleSnapshotHours) and "RECENT" or "STALE / UNKNOWN")
        if bags.error then
            lines[#lines + 1] = bags.error
        end
        for _, professionId in ipairs(RQ.Util.Keys(record.snapshot.professions or {})) do
            local profession = record.snapshot.professions[professionId]
            local target
            for _, milestone in ipairs(RQDB.settings.planning.professionMilestones) do
                if milestone > profession.skill then
                    target = milestone
                    break
                end
            end
            lines[#lines + 1] = profession.name
                .. " ["
                .. professionId
                .. "]: "
                .. profession.skill
                .. ", next milestone "
                .. tostring(target or "complete")
        end
        for _, item in ipairs(RQ.Util.Keys(grocery)) do
            local need = grocery[item]
            local label = bags.details[item] and bags.details[item].name or ("Item " .. item)
            lines[#lines + 1] = label
                .. " ["
                .. item
                .. "]: target "
                .. need.target
                .. ", in bags "
                .. tostring(need.have or "unknown")
                .. ", missing "
                .. tostring(need.missing or "unknown")
        end
        for _, note in ipairs(notes) do
            lines[#lines + 1] = note
        end
        if not next(grocery) then
            lines[#lines + 1] = "No grocery targets. Set item needs or a profession recipe goal."
        end
        lines[#lines + 1] = "Set minimum stock: /rq need <item ID> <quantity> [member]; quantity 0 removes it."
        lines[#lines + 1] =
            "Recipe focus: /rq goal <profession ID> <recipe ID> <target skill> [member]; skill 0 clears."
        lines[#lines + 1] = "Use /rq recipes [member] for recipe IDs and acquisition information."
    end
    return lines
end

function Supplies.Open(query, recipesOnly)
    if not RQ.Database.initialized then
        RQ.Api.Print(RQ.Database.status)
        return false
    end
    local id, err = selected(query)
    if not id then
        RQ.Api.Print(err)
        return false
    end
    return RQ.Api.ShowCopyWindow(
        recipesOnly and "Profession recipes - selectable report" or "Grocery list - selectable report",
        table.concat(Supplies.Report(id, recipesOnly), "\n")
    )
end

function Supplies.Mail()
    if not RQ.Database.initialized then
        RQ.Api.Print(RQ.Database.status)
        return false
    end
    Supplies.ScanBags()
    local report = Supplies.Evaluate(RQDB, RQ.Database.activeId, RQ.Api.GetServerTime())
    local lines = { "MAIL PROPOSALS - nothing is attached, filled in, or sent automatically." }
    for _, proposal in ipairs(report.proposals) do
        local recipient = RQDB.characters[proposal.characterId]
        local detail = RQ.Database.Current().inventory.bags.details[proposal.itemId]
        local label = detail and detail.name or "Unknown item name"
        lines[#lines + 1] = proposal.count
            .. " x "
            .. label
            .. " ["
            .. proposal.itemId
            .. "] -> "
            .. name(recipient)
            .. " - "
            .. (recipient.identity.realm or "unknown realm")
            .. "\n  "
            .. proposal.reason
            .. (proposal.stale and " [STALE / uncertain recipient data: verify]" or "")
    end
    if #report.proposals == 0 then
        lines[#lines + 1] = "No safe matching proposals from the available bag snapshots."
    end
    for _, warning in ipairs(report.warnings) do
        lines[#lines + 1] = warning
    end
    return RQ.Api.ShowCopyWindow("Mail assistant - review and send manually", table.concat(lines, "\n"))
end

function Supplies.Cards(account)
    local cards = {}
    for _, id in ipairs(RQ.Util.Keys(account.roster)) do
        local record = account.characters[id]
        if account.roster[id].enabled and record and record.registration == "member" then
            cards[#cards + 1] = {
                id = id,
                actionKind = "supplies",
                action = "View supplies",
                title = name(record),
                body = table.concat(Supplies.Report(id), "\n"),
            }
        end
    end
    if #cards == 0 then
        cards[1] = {
            title = "Register characters before planning supplies",
            action = "Configure roster",
            body = "Use /rq add or link a slot. Then open professions and scan bags on each character.",
        }
    end
    return cards
end
