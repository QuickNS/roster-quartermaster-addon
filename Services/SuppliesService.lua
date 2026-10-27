local Supplies = { generation = 0, itemNamesReceived = {}, pendingItemNames = {} }
RQ.SuppliesService = Supplies

function Supplies.ItemLabel(account, itemId, preferred)
    for _, source in ipairs({ "bags", "bank", "mail" }) do
        local details = preferred and preferred.inventory[source].details
        local detail = details and details[itemId]
        if detail and detail.name then
            return detail.name, true
        end
    end
    for _, id in ipairs(RQ.Util.Keys(account.characters)) do
        for _, source in ipairs({ "bags", "bank", "mail" }) do
            local details = account.characters[id].inventory[source].details
            local detail = details and details[itemId]
            if detail and detail.name then
                return detail.name, true
            end
        end
    end
    for _, transfer in pairs(account.mailTracking and account.mailTracking.transfers or {}) do
        local detail = transfer.details and transfer.details[itemId]
        if detail and detail.name then
            return detail.name, true
        end
    end
    local label = RQ.Api.GetItemName(itemId)
    Supplies.pendingItemNames[itemId] = not label or nil
    return label or ("Item " .. itemId), label ~= nil
end

function Supplies.SearchInventory(account, query, now, characterId, sourceFilter)
    local verified = RQ.MailService.Verified(account)
    local result, err = RQ.InventorySearch.Evaluate(account, query, now, characterId, nil, sourceFilter, verified)
    if not result then
        return nil, err
    end
    local labels = {}
    for _, itemId in ipairs(RQ.InventorySearch.ItemIds(account, characterId, sourceFilter)) do
        local label, known = Supplies.ItemLabel(account, itemId)
        if known then
            labels[itemId] = label
        end
    end
    result = RQ.InventorySearch.Evaluate(account, result.query, now, characterId, labels, sourceFilter, verified)
    result.icons = {}
    local seen = {}
    for _, match in ipairs(result.matches) do
        if not seen[match.itemId] then
            seen[match.itemId] = true
            result.icons[match.itemId] = RQ.Api.GetItemIcon(match.itemId)
        end
    end
    return result
end

function Supplies.FindItems(query, characterId, copy, sourceFilter, account)
    if not RQ.Database.initialized then
        RQ.Api.Print("Inventory search unavailable: " .. RQ.Database.status)
        return false
    end
    local now = RQ.Api.GetServerTime()
    local result, err = Supplies.SearchInventory(account or RQDB, query, now, characterId, sourceFilter)
    if not result then
        RQ.Api.Print("Inventory search: " .. err)
        return false
    end
    local lines = RQ.BagPanel.SearchReport(result, now)
    if copy then
        return RQ.Api.ShowCopyWindow("Inventory search - bags and personal bank", table.concat(lines, "\n"))
    end
    for _, line in ipairs(lines) do
        RQ.Api.Print(line)
    end
    return true
end

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
    if RQ.Api.IsBankSessionOpen() then
        return RQ.BankService.Scan()
    end
    if RQ.Api.IsMailboxOpen() and RQ.Api.CanObserveInbox() then
        return RQ.MailService.Scan()
    end
    local scan, err = RQ.Api.GetBagItems()
    local inventory = RQ.Util.Copy(record.inventory)
    if scan then
        for id, detail in pairs(scan.details) do
            local previous = inventory.bags.details[id]
            if not detail.name and previous then
                detail.name = previous.name
            end
        end
        inventory.bags = scan
    else
        inventory.bags.complete, inventory.bags.error = false, err
        if record.inventory.bags.error ~= err then
            RQ.Api.Print("Bag contents unavailable: " .. err)
        end
    end
    return save(RQ.Database.activeId, "inventory", inventory)
end

function Supplies.ItemInfoReceived(itemId, success)
    local record = RQ.Database.Current()
    if not RQ.SuppliesConfig.Id(itemId) or type(success) ~= "boolean" then
        return
    end
    local bags = record and record.registration ~= "ignored" and record.inventory.bags
    local detail = bags and bags.details[itemId]
    local needsBagName = bags and bags.items[itemId] and not (detail and detail.name)
    local bank = record and record.inventory.bank
    local needsBankName = bank and bank.items[itemId] and not (bank.details[itemId] and bank.details[itemId].name)
    if
        (not needsBagName and not needsBankName and not Supplies.pendingItemNames[itemId])
        or Supplies.itemNamesReceived[itemId] == success
    then
        return
    end
    Supplies.itemNamesReceived[itemId] = success
    if success == true then
        if Supplies.pendingItemNames[itemId] and RQ.Api.GetItemName(itemId) then
            Supplies.pendingItemNames[itemId] = nil
            if RQ.MainWindow then
                RQ.MainWindow.Invalidate()
            end
        end
        if needsBagName then
            RQ.SnapshotService.Queue({ "bags" })
        end
        if needsBankName and RQ.Api.IsBankSessionOpen() then
            RQ.BankService.Changed()
        end
    elseif success == false then
        RQ.Api.Print("Item name data unavailable for item " .. itemId .. "; use /rq rescan to retry the lookup.")
    end
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

local fresh = RQ.SuppliesConfig.IsFresh

local difficultyNames = { "ORANGE", "YELLOW", "GREEN", "GRAY" }

local function professionSource(record)
    local section = record.snapshot.sections and record.snapshot.sections.professions
    return { complete = section and section.complete or false, scannedAt = section and section.observedAt or 0 }
end

local function route(detail)
    if detail.classId == 7 and detail.subclassId == 5 then
        return 197, "Cloth surplus for Tailoring"
    elseif detail.classId == 7 and detail.subclassId == 7 then
        return 164, "Ore / bars / stone surplus for Blacksmithing"
    elseif detail.quality == 2 and detail.bindType == 2 and (detail.classId == 2 or detail.classId == 4) then
        return 333, "BoE green equipment for Enchanting; verify upgrades, disenchantability and required skill"
    end
end

local function observedOrangeRecipe(record, professionId, recipeId)
    local scan = record.recipes.professions[professionId]
    local recipe = scan and scan.recipes[recipeId]
    local profession = (record.snapshot.professions or {})[professionId]
    return profession
        and profession.skill < profession.maxSkill
        and scan
        and scan.complete
        and recipe
        and recipe.learned
        and recipe.difficulty == 0
        and recipe.reagentsComplete
        and recipe.skillUps > 0
end

function Supplies.Grocery(record, now, hours)
    local targets, planned, notes = RQ.Util.Copy(record.supplies.needs), {}, {}
    local goalRecipes, automatic, sources, uncertain = {}, {}, {}, {}
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
            if crafts > 0 then
                goalRecipes[professionId] = goal.recipeId
            end
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
            notes[#notes + 1] = "Last observed recipe difficulty: "
                .. (recipe.difficulty and difficultyNames[recipe.difficulty + 1] or "UNKNOWN")
                .. ". Orange can turn yellow before the goal; rescan and adjust the recipe."
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
    for _, professionId in ipairs(RQ.Util.Keys(record.recipes.professions)) do
        local scan = record.recipes.professions[professionId]
        local count = 0
        local stale = record.recipes.error ~= nil
            or not (now and hours and fresh(scan, now, hours) and fresh(professionSource(record), now, hours))
        for _, recipeId in ipairs(RQ.Util.Keys(scan.recipes)) do
            if goalRecipes[professionId] ~= recipeId and observedOrangeRecipe(record, professionId, recipeId) then
                count = count + 1
                local recipe = scan.recipes[recipeId]
                for item, quantity in pairs(recipe.reagents) do
                    if quantity > 0 then
                        planned[item] = (planned[item] or 0) + quantity
                        automatic[item] = (automatic[item] or 0) + quantity
                        sources[item] = sources[item] or {}
                        sources[item][#sources[item] + 1] = {
                            professionId = professionId,
                            recipeId = recipeId,
                            name = recipe.name,
                            quantity = quantity,
                            scannedAt = scan.scannedAt,
                        }
                        uncertain[item] = uncertain[item] or stale
                    end
                end
            end
        end
        if count > 0 then
            notes[#notes + 1] = "Automatic orange groceries: "
                .. scan.name
                .. ", one craft each of "
                .. count
                .. " learned recipe(s), observed "
                .. scan.scannedAt
                .. ". Shared reagents are summed; active recipe goals replace that recipe's one-craft allowance."
            if stale then
                notes[#notes + 1] = "STALE / uncertain automatic orange recipes: cached needs retained; "
                    .. "rescan before mailing or crafting."
            end
        elseif not scan.complete then
            notes[#notes + 1] = scan.name .. ": incomplete recipe scan; automatic orange groceries unavailable."
        end
    end
    for item, quantity in pairs(planned) do
        targets[item] = math.max(targets[item] or 0, quantity)
    end
    local reserveTargets, reserveKinds = {}, {}
    for _, kind in ipairs({ "potions", "bandages" }) do
        for item, target in pairs(record.supplies.reserves and record.supplies.reserves[kind] or {}) do
            reserveTargets[item], reserveKinds[item] = target, kind
            targets[item] = math.max(targets[item] or 0, target)
        end
    end
    local grocery = {}
    for item, target in pairs(targets) do
        grocery[item] = RQ.InventoryAvailability.Need(record, item, target, now, hours)
        grocery[item].genericTarget = record.supplies.needs[item] or 0
        grocery[item].reserveTarget, grocery[item].reserveKind = reserveTargets[item], reserveKinds[item]
        grocery[item].orangeTarget = automatic[item] or 0
        grocery[item].orangeRecipes = sources[item]
        grocery[item].orangeStale = uncertain[item] == true
    end
    if next(reserveTargets) then
        notes[#notes + 1] = "First Aid reserves are user-specified stock floors, not additional consumption. "
            .. "Item category, rank, level suitability and recipe facts are unverified."
    end
    return grocery, notes
end

local function applyMailCoverage(needs, coverage)
    for item, need in pairs(needs) do
        need.pendingMail, need.inboxHave = coverage.pending[item] or 0, coverage.inbox[item] or 0
        need.collect = need.missing and math.min(need.missing, need.inboxHave) or 0
        need.inTransit = need.missing and math.min(need.missing - need.collect, need.pendingMail) or 0
        need.missing = need.missing and math.max(0, need.missing - need.collect - need.inTransit) or nil
    end
end

function Supplies.GroceryState(need)
    if need.missing == nil then
        return "unknown"
    elseif need.missing > 0 then
        return "missing"
    elseif (need.withdraw or 0) + (need.collect or 0) + (need.inTransit or 0) > 0 then
        return "collection"
    end
    return "covered"
end

function Supplies.ReviewGroceries(account, now, owner, verifiedMail)
    local plan = Supplies.Plan(account, now, verifiedMail)
    local record = owner and account.characters[owner]
    if record and record.registration == "member" and account.roster[owner] and not plan.groceries[owner] then
        plan.ids[#plan.ids + 1] = owner
        plan.groceries[owner], plan.notes[owner] = Supplies.Grocery(record, now, account.policies.staleSnapshotHours)
        applyMailCoverage(plan.groceries[owner], RQ.MailTracker.Coverage(account, owner, now, verifiedMail))
    end
    return plan
end

function Supplies.Plan(account, now, verifiedMail)
    local groceries, notes, ids, coverage = {}, {}, {}, {}
    for _, id in ipairs(RQ.Util.Keys(account.roster)) do
        local record = account.characters[id]
        if account.roster[id].enabled and record and record.registration == "member" then
            ids[#ids + 1] = id
            groceries[id], notes[id] = Supplies.Grocery(record, now, account.policies.staleSnapshotHours)
            coverage[id] = RQ.MailTracker.Coverage(account, id, now, verifiedMail)
            applyMailCoverage(groceries[id], coverage[id])
        end
    end
    local bags = RQ.BagPlanner.Evaluate(account, now, groceries, verifiedMail)
    for id, needs in pairs(bags.materials) do
        local record = account.characters[id]
        for item, extra in pairs(needs) do
            if extra > 0 then
                local target = (groceries[id][item] and groceries[id][item].target or 0) + extra
                local previous = groceries[id][item]
                local need =
                    RQ.InventoryAvailability.Need(record, item, target, now, account.policies.staleSnapshotHours)
                need.genericTarget = previous and previous.genericTarget or 0
                need.reserveTarget, need.reserveKind =
                    previous and previous.reserveTarget, previous and previous.reserveKind
                need.orangeTarget, need.orangeRecipes, need.orangeStale =
                    previous and previous.orangeTarget,
                    previous and previous.orangeRecipes,
                    previous and previous.orangeStale
                need.bagPriority = extra
                applyMailCoverage({ [item] = need }, coverage[id])
                groceries[id][item] = need
            end
        end
        notes[id][#notes[id] + 1] =
            "Priority bag-upgrade materials included; see the Bags tab for recipients and crafting."
        for _, note in ipairs(bags.notes[id] or {}) do
            notes[id][#notes[id] + 1] = note
        end
    end
    for _, covered in ipairs(bags.covered) do
        local lines = notes[covered.characterId]
        lines[#lines + 1] = "Bag slot "
            .. covered.slot
            .. ": item "
            .. covered.itemId
            .. " covered by "
            .. covered.state
            .. " mail; collect and verify manually. Not equip/craft ready."
    end
    return { groceries = groceries, notes = notes, ids = ids, bags = bags }
end

function Supplies.WithdrawalLines(account, plan, id)
    local lines = {}
    for _, item in ipairs(RQ.Util.Keys(plan.groceries[id] or {})) do
        local need = plan.groceries[id][item]
        if (need.collect or 0) + (need.inTransit or 0) > 0 then
            lines[#lines + 1] = "Mail coverage: "
                .. Supplies.ItemLabel(account, item, account.characters[id])
                .. " ["
                .. item
                .. "], inbox "
                .. (need.collect or 0)
                .. ", pending "
                .. (need.inTransit or 0)
                .. "; extra needed "
                .. tostring(need.missing or "unknown")
                .. ". Provisional only; collect manually before crafting."
        end
        if need.withdraw and need.withdraw > 0 then
            lines[#lines + 1] = "Withdraw from bank: "
                .. need.withdraw
                .. " x "
                .. Supplies.ItemLabel(account, item, account.characters[id])
                .. " ["
                .. item
                .. "]. "
                .. "Carried "
                .. need.have
                .. "; target "
                .. need.target
                .. "; extra needed "
                .. need.missing
                .. "."
        end
    end
    return lines
end

function Supplies.Evaluate(account, sourceId, now, verifiedMail)
    local result = Supplies.Plan(account, now, verifiedMail)
    local groceries, ids = result.groceries, result.ids
    result.proposals, result.warnings, result.bankTransfers = {}, {}, {}
    local source = account.characters[sourceId]
    local hours = account.policies.staleSnapshotHours
    if not source or source.registration == "ignored" or not fresh(source.inventory.bags, now, hours) then
        result.warnings[1] = "Scan the active character's bags before generating mail proposals."
        return result
    end
    local eligible = {}
    for _, id in ipairs(ids) do
        if id == sourceId or RQ.Character.CanTrade(source.identity, account.characters[id].identity) then
            eligible[#eligible + 1] = id
        end
    end
    ids, result.ids = eligible, eligible
    result.warnings[#result.warnings + 1] = "Transfers require the same known ruleset, faction and realm. "
        .. "Unknown trade groups are excluded; visit each character and set its ruleset in Manage roster if necessary."
    local available = {}
    local reserves = groceries[sourceId] or Supplies.Grocery(source, now, hours)
    for item, count in pairs(source.inventory.bags.tradable) do
        local surplus =
            math.max(0, (source.inventory.bags.items[item] or 0) - (reserves[item] and reserves[item].target or 0))
        available[item] = math.min(count, surplus)
    end
    for _, upgrade in ipairs(result.bags.upgrades) do
        if upgrade.kind == "equip" and upgrade.sourceId == sourceId then
            available[upgrade.itemId] = math.max(0, (available[upgrade.itemId] or 0) - 1)
        end
    end
    local ownEmpty = 0
    for _, slots in pairs(source.inventory.bags.equipped) do
        if slots == 0 then
            ownEmpty = ownEmpty + 1
        end
    end
    for _, item in ipairs(RQ.Util.Keys(available)) do
        local detail = source.inventory.bags.details[item] or {}
        if detail.classId == 1 and detail.subclassId == 0 and not detail.bagSlots then
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
    local allocated = {}
    local function propose(id, item, count, reason)
        if id == sourceId or not RQ.Character.CanTrade(source.identity, account.characters[id].identity) then
            return 0
        end
        count = math.min(count, available[item] or 0)
        if count < 1 then
            return 0
        end
        result.proposals[#result.proposals + 1] = {
            characterId = id,
            itemId = item,
            count = count,
            reason = reason,
            stale = not fresh(account.characters[id].inventory.bags, now, hours)
                or (groceries[id][item] and groceries[id][item].orangeStale == true),
        }
        available[item] = available[item] - count
        allocated[id] = allocated[id] or {}
        allocated[id][item] = (allocated[id][item] or 0) + count
        return count
    end
    for _, upgrade in ipairs(result.bags.upgrades) do
        if upgrade.kind == "mail" and upgrade.sourceId == sourceId then
            propose(
                upgrade.characterId,
                upgrade.itemId,
                1,
                "Priority bag upgrade: equipped slot "
                    .. upgrade.slot
                    .. ", "
                    .. upgrade.from
                    .. " -> "
                    .. upgrade.to
                    .. " slots"
            )
        end
    end
    for _, id in ipairs(ids) do
        if id ~= sourceId then
            for _, item in ipairs(RQ.Util.Keys(groceries[id])) do
                local need = groceries[id][item]
                if need.bagPriority and need.missing then
                    propose(
                        id,
                        item,
                        math.min(need.bagPriority, need.missing),
                        "Priority materials: craft roster bag upgrades"
                    )
                end
            end
        end
    end
    local groceryItems = {}
    for _, id in ipairs(ids) do
        for item in pairs(groceries[id]) do
            groceryItems[item] = true
        end
    end
    local cook = RQ.LogisticsPolicies.Cook(account, source.identity)
    if cook and RQ.Character.CanTrade(source.identity, account.characters[cook].identity) then
        for _, item in ipairs(RQ.Util.Keys(available)) do
            if RQ.LogisticsPolicies.CookingItem(account, item) then
                if cook ~= sourceId then
                    propose(cook, item, available[item], "Cooking/Fishing assignment: raw ingredients / explicit food")
                else
                    available[item] = 0
                end
            end
        end
    end
    local function recipients(item)
        return RQ.LogisticsPolicies and RQ.LogisticsPolicies.Recipients(account, item, ids) or ids
    end
    for _, item in ipairs(RQ.Util.Keys(groceryItems)) do
        for _, id in ipairs(recipients(item)) do
            local need = groceries[id][item]
            if id ~= sourceId and need and need.missing then
                local sent = allocated[id] and allocated[id][item] or 0
                propose(
                    id,
                    item,
                    math.max(0, need.missing - sent),
                    need.reserveKind and ("Grocery / First Aid reserve: " .. need.reserveKind)
                        or ((need.orangeTarget or 0) > 0 and "Grocery / automatic orange recipe materials")
                        or "Grocery list / profession milestone"
                )
            end
        end
    end
    for _, id in ipairs(ids) do
        if id ~= sourceId then
            local record = account.characters[id]
            if record.inventory.bags.complete then
                local empty, spare = 0, 0
                for _, slots in pairs(record.inventory.bags.equipped) do
                    if slots == 0 then
                        empty = empty + 1
                    end
                end
                for _, upgrade in ipairs(result.bags.upgrades) do
                    if upgrade.characterId == id and upgrade.from == 0 then
                        empty = math.max(0, empty - 1)
                    end
                end
                for _, covered in ipairs(result.bags.covered) do
                    if covered.characterId == id and covered.from == 0 then
                        empty = math.max(0, empty - 1)
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
                    if detail.classId == 1 and detail.subclassId == 0 and not detail.bagSlots and empty > spare then
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
    -- Explicit needs across every recipient take priority over profession surplus.
    if source.identity.class and source.identity.class ~= "ROGUE" then
        for _, item in ipairs(RQ.Util.Keys(source.inventory.bags.lockedContainers or {})) do
            local spent = (source.inventory.bags.tradable[item] or 0) - (available[item] or 0)
            local count = math.max(0, source.inventory.bags.lockedContainers[item] - spent)
            for _, id in ipairs(ids) do
                if id ~= sourceId and account.characters[id].identity.class == "ROGUE" then
                    local sent =
                        propose(id, item, count, "Rogue routing: item requires unlocking; verify Lockpicking skill")
                    if sent > 0 then
                        result.proposals[#result.proposals].unlocking = sent
                    end
                    break
                end
            end
        end
    end
    local explicit = {}
    if RQ.LogisticsPolicies then
        local eligibleIds = {}
        for _, id in ipairs(ids) do
            eligibleIds[id] = true
        end
        for _, item in ipairs(RQ.Util.Keys(available)) do
            local rule, category = RQ.LogisticsPolicies.Rule(account, item)
            if rule then
                explicit[item] = true
                for _, id in ipairs(rule.recipients) do
                    if eligibleIds[id] then
                        if id == sourceId then
                            break
                        end
                        local need = groceries[id][item]
                        local sent = allocated[id] and allocated[id][item] or 0
                        local count = need and math.max(0, (need.missing or 0) - sent) or available[item]
                        propose(
                            id,
                            item,
                            count,
                            "Explicit item-ID routing: "
                                .. category
                                .. "; user-assigned category, profession suitability unverified"
                        )
                    end
                end
            end
        end
    end
    if source.identity.class and source.identity.class ~= "MAGE" then
        for _, item in ipairs(RQ.Util.Keys(available)) do
            local detail = source.inventory.bags.details[item] or {}
            local mageItem = item == 17056 and "Light Feather"
                or (type(detail.name) == "string" and detail.name:sub(1, 7) == "Scroll:" and "Scroll: item")
            if not explicit[item] and mageItem then
                for _, id in ipairs(ids) do
                    if id ~= sourceId and account.characters[id].identity.class == "MAGE" then
                        propose(id, item, available[item], "Mage routing: " .. mageItem)
                        break
                    end
                end
            end
        end
    end
    local sourceProfessionsFresh = fresh(professionSource(source), now, hours)
    if not sourceProfessionsFresh then
        result.warnings[#result.warnings + 1] =
            "Refresh sender professions with /rq rescan before surplus routing; explicit needs still apply."
    end
    for _, item in ipairs(RQ.Util.Keys(available)) do
        local profession, reason = route(source.inventory.bags.details[item] or {})
        if
            not explicit[item]
            and sourceProfessionsFresh
            and profession
            and not (source.snapshot.professions or {})[profession]
        then
            for _, id in ipairs(ids) do
                local recipient = account.characters[id]
                if id ~= sourceId and (recipient.snapshot.professions or {})[profession] then
                    local sent = propose(id, item, available[item], "Profession routing: " .. reason)
                    if sent > 0 and not fresh(professionSource(recipient), now, hours) then
                        result.proposals[#result.proposals].stale = true
                    end
                    break
                end
            end
        end
    end
    if RQ.InventoryAvailability.BankEligible(source, now, hours) then
        local bankAvailable = {}
        for item, count in pairs(source.inventory.bank.tradable) do
            bankAvailable[item] = math.min(
                count,
                math.max(
                    0,
                    (source.inventory.bank.items[item] or 0) - (reserves[item] and reserves[item].withdraw or 0)
                )
            )
        end
        if cook and RQ.Character.CanTrade(source.identity, account.characters[cook].identity) then
            for _, item in ipairs(RQ.Util.Keys(bankAvailable)) do
                if RQ.LogisticsPolicies.CookingItem(account, item) then
                    if cook ~= sourceId and bankAvailable[item] > 0 then
                        result.bankTransfers[#result.bankTransfers + 1] = {
                            sourceId = sourceId,
                            characterId = cook,
                            itemId = item,
                            count = bankAvailable[item],
                        }
                    end
                    bankAvailable[item] = 0
                end
            end
        end
        for _, item in ipairs(RQ.Util.Keys(groceryItems)) do
            for _, id in ipairs(recipients(item)) do
                if id ~= sourceId and groceries[id][item] then
                    local need = groceries[id][item]
                    local sent = allocated[id] and allocated[id][item] or 0
                    local count = math.min(bankAvailable[item] or 0, math.max(0, (need.missing or 0) - sent))
                    if count > 0 then
                        result.bankTransfers[#result.bankTransfers + 1] = {
                            sourceId = sourceId,
                            characterId = id,
                            itemId = item,
                            count = count,
                        }
                        bankAvailable[item] = bankAvailable[item] - count
                    end
                end
            end
        end
    end
    result.warnings[#result.warnings + 1] = "Cooking/Fishing receives raw ingredients before other recipients' needs. "
        .. "Sender grocery reserves and priority bag materials are kept first."
    result.warnings[#result.warnings + 1] = "Explicit item-ID policies override profession surplus routes; "
        .. "recipient order is user-configured. "
        .. "Herbs/leather/food and Engineering/Blacksmithing item facts are not inferred."
    result.warnings[#result.warnings + 1] =
        "Bag upgrades and their materials take priority. Crafting/equipping remain manual; see /rq bags."
    result.warnings[#result.warnings + 1] =
        "Cloth/metal classification and green BoE metadata must be observed; unknown items are not guessed."
    result.warnings[#result.warnings + 1] =
        "Manual review only: confirm full recipient name, realm/faction rules, binding and quantities."
    result.warnings[#result.warnings + 1] = "Attachments use carried bags only. "
        .. "Verified local bank stock reduces deficits but requires withdrawal; "
        .. "eligible confirmed mail suppresses duplicate requests but never becomes attachable stock. "
        .. "Auctions and drafts are excluded. Rescan after sending."
    result.warnings[#result.warnings + 1] =
        "Bound, temporarily busy or unknown-binding stacks are excluded; source grocery quantities are reserved."
    result.warnings[#result.warnings + 1] =
        "Locked containers route to Rogues only with bag-tooltip evidence; Lockpicking requirements are unverified."
    result.warnings[#result.warnings + 1] = "Scroll: and Light Feather surplus routes to the first eligible Mage; "
        .. "reserves, explicit needs and item-ID rules take priority."
    return result
end

local function name(record)
    return RQ.Character.DisplayName(record.identity) or "Unknown"
end

local function orangeRecipe(record, professionId, recipeId, now, hours)
    local scan = record.recipes.professions[professionId]
    return observedOrangeRecipe(record, professionId, recipeId)
        and fresh(professionSource(record), now, hours)
        and fresh(scan, now, hours)
        and not record.recipes.error
end

function Supplies.OrangeSourceLines(need)
    local lines = {}
    for _, source in ipairs(need.orangeRecipes or {}) do
        lines[#lines + 1] = "Auto orange: "
            .. source.name
            .. " ["
            .. source.recipeId
            .. "], profession "
            .. source.professionId
            .. ", x"
            .. source.quantity
            .. " for one craft; scanned "
            .. source.scannedAt
            .. (need.orangeStale and " (STALE / uncertain)" or "")
    end
    return lines
end

function Supplies.SetOrangeGoal(professionId, recipeId, targetSkill, query)
    local id, err = selected(query)
    if not id then
        return false, err
    end
    local record = RQDB.characters[id]
    if not orangeRecipe(record, professionId, recipeId, RQ.Api.GetServerTime(), RQDB.policies.staleSnapshotHours) then
        return false, "Recipe no longer eligible: rescan a learned orange recipe with complete reagents and skill data."
    end
    local profession = record.snapshot.professions[professionId]
    if
        not RQ.SuppliesConfig.Id(targetSkill)
        or targetSkill <= profession.skill
        or targetSkill > profession.maxSkill
    then
        return false, "Target skill must be above the observed skill and within the trained profession cap."
    end
    return Supplies.SetGoal(professionId, recipeId, targetSkill, id)
end

function Supplies.OpenTargets(query)
    local id, err = selected(query)
    if not id then
        RQ.Api.Print(err)
        return false
    end
    if not RQ.MainWindow then
        RQ.Api.Print("Recipe picker unavailable; reinstall the complete addon. Use /rq recipes for text.")
        return false
    end
    RQ.MainWindow.recipeCharacterId = id
    return RQ.MainWindow.Open("recipes")
end

function Supplies.RecipeCards(account, id, now)
    local cards, record = {}, account.characters[id]
    local entry = account.roster[id]
    if record and entry and record.registration == "member" then
        for _, professionId in ipairs(RQ.Util.Keys(record.recipes.professions)) do
            local scan = record.recipes.professions[professionId]
            for _, recipeId in ipairs(RQ.Util.Keys(scan.recipes)) do
                if orangeRecipe(record, professionId, recipeId, now, account.policies.staleSnapshotHours) then
                    local recipe = scan.recipes[recipeId]
                    local profession = record.snapshot.professions[professionId]
                    local goal = record.supplies.goals[professionId]
                    local target = math.min(profession.skill + 5, profession.maxSkill)
                    if goal and goal.recipeId == recipeId and goal.targetSkill > profession.skill then
                        target = math.min(goal.targetSkill, profession.maxSkill)
                    end
                    local lines = {
                        scan.name .. ": " .. profession.skill .. "/" .. profession.maxSkill,
                        "ORANGE at last scan (" .. scan.scannedAt .. "); may turn yellow before the target.",
                        "Choose a target skill below, then Set goal. Replaces this profession's previous recipe goal.",
                        "Materials per craft (" .. recipe.skillUps .. " estimated skill point(s)):",
                    }
                    for _, item in ipairs(RQ.Util.Keys(recipe.reagents)) do
                        lines[#lines + 1] = "  "
                            .. Supplies.ItemLabel(account, item, record)
                            .. " ["
                            .. item
                            .. "] x"
                            .. recipe.reagents[item]
                    end
                    cards[#cards + 1] = {
                        id = id,
                        professionId = professionId,
                        recipeId = recipeId,
                        targetSkill = target,
                        title = name(record) .. " - " .. recipe.name,
                        body = table.concat(lines, "\n"),
                        actionKind = "recipe-goal",
                        action = "Set goal",
                        disabled = not entry.enabled,
                    }
                end
            end
        end
    end
    if #cards == 0 then
        cards[1] = {
            title = "No eligible orange recipes",
            body = "Log into this member, /rq rescan, open each profession and /rq scan-recipes. "
                .. "Requires recent learned orange recipes, complete reagents and room below the skill cap. "
                .. "Missing difficulty stays unknown; use /rq recipes for scan errors and recipe details.",
            actionKind = "back-supplies",
            action = "Supplies",
        }
    end
    return cards
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
                lines[#lines + 1] = "  Difficulty: "
                    .. (recipe.difficulty and difficultyNames[recipe.difficulty + 1] or "UNKNOWN")
                if recipe.outputItemId then
                    lines[#lines + 1] = "  Output: "
                        .. Supplies.ItemLabel(RQDB, recipe.outputItemId, record)
                        .. " ["
                        .. recipe.outputItemId
                        .. "]"
                        .. " x"
                        .. recipe.outputCount
                        .. (recipe.bagSlots and ("; general-purpose bag, " .. recipe.bagSlots .. " slots") or "")
                    if recipe.bagSlots then
                        lines[#lines + 1] = "  Bag output binding: " .. tostring(recipe.outputBindType or "unknown")
                    end
                end
                lines[#lines + 1] = "  Acquire: " .. (recipe.source or "source unavailable")
                lines[#lines + 1] = "  Materials: "
                    .. (recipe.reagentsComplete and "observed" or "incomplete / alternatives")
                for _, item in ipairs(RQ.Util.Keys(recipe.reagents)) do
                    lines[#lines + 1] = "    "
                        .. Supplies.ItemLabel(RQDB, item, record)
                        .. " ["
                        .. item
                        .. "] x"
                        .. recipe.reagents[item]
                end
            end
        end
        if record.recipes.error then
            lines[#lines + 1] = "Last scan: " .. record.recipes.error
        end
        lines[#lines + 1] = "\nFocus: /rq goal <profession ID> <recipe ID> <target skill> [member]"
    else
        local plan = Supplies.Plan(RQDB, RQ.Api.GetServerTime(), RQ.MailService.Verified())
        local grocery, notes = plan.groceries[id], plan.notes[id]
        if not grocery then
            grocery, notes = Supplies.Grocery(record, RQ.Api.GetServerTime(), RQDB.policies.staleSnapshotHours)
        end
        local bags = record.inventory.bags
        lines[#lines + 1] = "Bag scan: "
            .. bags.scannedAt
            .. " | "
            .. (fresh(bags, RQ.Api.GetServerTime(), RQDB.policies.staleSnapshotHours) and "RECENT" or "STALE / UNKNOWN")
        if bags.error then
            lines[#lines + 1] = bags.error
        end
        for _, slot in ipairs(RQ.Util.Keys(bags.equipped)) do
            lines[#lines + 1] = "Equipped bag " .. slot .. ": " .. bags.equipped[slot] .. " slots"
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
        for _, line in
            ipairs(
                RQ.ProfessionStatus.Lines(
                    record.snapshot,
                    RQ.Api.GetServerTime(),
                    RQDB.policies.staleSnapshotHours,
                    RQDB.settings.professionLag
                )
            )
        do
            lines[#lines + 1] = line
        end
        for _, item in ipairs(RQ.Util.Keys(grocery)) do
            local need = grocery[item]
            local label = Supplies.ItemLabel(RQDB, item, record)
            lines[#lines + 1] = label
                .. " ["
                .. item
                .. "]: target "
                .. need.target
                .. ", in bags "
                .. tostring(need.have or "unknown")
                .. ", missing "
                .. tostring(need.missing or "unknown")
                .. ", bank "
                .. tostring(need.bankHave or "unknown / not credited")
                .. ", withdraw "
                .. (need.withdraw or 0)
                .. ", inbox "
                .. (need.inboxHave or 0)
                .. ", pending mail "
                .. (need.pendingMail or 0)
            for _, line in ipairs(Supplies.OrangeSourceLines(need)) do
                lines[#lines + 1] = "  " .. line
            end
        end
        for _, line in ipairs(Supplies.WithdrawalLines(RQDB, { groceries = { [id] = grocery } }, id)) do
            lines[#lines + 1] = line
        end
        lines[#lines + 1] = "Bank scan: "
            .. record.inventory.bank.scannedAt
            .. (
                RQ.InventoryAvailability.BankEligible(
                        record,
                        RQ.Api.GetServerTime(),
                        RQDB.policies.staleSnapshotHours
                    )
                    and " | RECENT / COHERENT"
                or " | UNKNOWN / STALE / UNCONFIRMED (not credited)"
            )
        if record.inventory.bank.error then
            lines[#lines + 1] = record.inventory.bank.error
        end
        for _, note in ipairs(notes) do
            lines[#lines + 1] = note
        end
        if not next(grocery) then
            lines[#lines + 1] = "No grocery targets. Scan learned orange recipes, set item needs or a profession goal."
        end
        lines[#lines + 1] = "Set minimum stock: /rq need <item ID> <quantity> [member]; quantity 0 removes it."
        lines[#lines + 1] =
            "Recipe focus: /rq goal <profession ID> <recipe ID> <target skill> [member]; skill 0 clears."
        lines[#lines + 1] = "Use /rq recipes [member] for recipe IDs and acquisition information."
        lines[#lines + 1] = "Use /rq targets [member] or Orange recipes to choose a recipe goal without typing IDs."
        lines[#lines + 1] = "Mail routes surplus cloth to tailors, metals to blacksmiths, "
            .. "BoE greens to enchanters and Scroll: items/Light Feathers to Mages."
    end
    return lines
end

function Supplies.Open(query, recipesOnly, textOnly)
    if not RQ.Database.initialized then
        RQ.Api.Print(RQ.Database.status)
        return false
    end
    local id, err = RQ.Database.ResolveMember(query and query ~= "" and query or RQ.Database.activeId, true)
    if not id then
        RQ.Api.Print(err)
        return false
    end
    if not recipesOnly and not textOnly then
        return RQ.MainWindow.OpenGroceries(id)
    end
    return RQ.Api.ShowCopyWindow(
        recipesOnly and "Profession recipes - selectable report" or "Grocery list - selectable report",
        table.concat(Supplies.Report(id, recipesOnly), "\n")
    )
end

local function mailRecipient(id)
    local resolved, err = selected(id)
    if not resolved then
        return nil, err
    end
    local identity = RQDB.characters[resolved].identity
    local recipient = RQ.Character.DisplayName(identity)
    if not recipient or (not identity.fullName and identity.nameComplete ~= true) then
        return nil, "Recipient full name is unverified. Visit them and /rq rescan, or set /rq fullname First Last."
    end
    local source = RQ.Database.Current()
    if not source or not RQ.Character.CanTrade(identity, source.identity) then
        return nil,
            "Different or unknown recipient realm, ruleset or faction; refresh both characters before attaching."
    end
    for otherId, record in pairs(RQDB.characters) do
        local otherName = RQ.Character.DisplayName(record.identity)
        if
            otherId ~= resolved
            and otherName
            and otherName:lower() == recipient:lower()
            and RQ.Character.CanTrade(record.identity, identity)
        then
            return nil, "Ambiguous recipient name; refresh full names before attaching."
        end
    end
    return recipient, nil, resolved
end

local function mailGroups(report)
    local groups = {}
    for _, proposal in ipairs(report.proposals) do
        local id, item = proposal.characterId, proposal.itemId
        groups[id] = groups[id] or {}
        local entry = groups[id][item] or { count = 0, reasons = {}, stale = false, unlocking = 0 }
        entry.count = entry.count + proposal.count
        entry.reasons[#entry.reasons + 1] = proposal.reason
        entry.stale = entry.stale or proposal.stale
        entry.unlocking = entry.unlocking + (proposal.unlocking or 0)
        groups[id][item] = entry
    end
    return groups
end

function Supplies.Attach(id, itemId)
    local recipient, err, resolved = mailRecipient(id)
    if not recipient then
        return false, err
    end
    id = resolved
    local draft
    draft, err = RQ.Api.GetMailDraft()
    if not draft then
        return false, err
    end
    local ok
    ok, err = Supplies.ScanBags()
    if not ok then
        return false, err or "Sender bags could not be refreshed."
    end
    local report = Supplies.Evaluate(RQDB, RQ.Database.activeId, RQ.Api.GetServerTime(), RQ.MailService.Verified())
    local group = mailGroups(report)[id] or {}
    local requests, unlocking = {}, {}
    for item, proposal in pairs(group) do
        if (not itemId or itemId == item) and not draft.counts[item] then
            requests[item] = proposal.count
            if proposal.unlocking > 0 then
                unlocking[item] = proposal.unlocking
            end
        end
    end
    if not next(requests) then
        return false, "No new eligible items: already attached or proposals changed. Review the draft and refresh."
    end
    local attached
    attached, err = RQ.Api.AttachMailItems(recipient, requests, unlocking)
    Supplies.ScanBags()
    if err then
        return false, attached .. " stack(s) confirmed attached. " .. err
    end
    return true,
        attached .. " stack(s) attached to " .. recipient .. ". Review the mail and click Blizzard's Send yourself."
end

function Supplies.MailCards(account, now)
    local report = Supplies.Evaluate(account, RQ.Database.activeId, now, RQ.MailService.Verified(account))
    local draft, draftError = RQ.Api.GetMailDraft()
    local cards = {
        {
            title = "Mail attachments - review before sending",
            body = (
                draftError or ("Current draft recipient: " .. (draft.recipient ~= "" and draft.recipient or "(empty)"))
            )
                .. "\nAttach item or Attach all adds items and fills the recipient; nothing is sent. "
                .. "Do not change recipients while a draft has attachments. Same-item repeats are blocked."
                .. "\n"
                .. table.concat(report.warnings, "\n"),
            actionKind = "mail-refresh",
            action = "Refresh",
        },
    }
    local groups = mailGroups(report)
    for _, transfer in ipairs(report.bankTransfers) do
        cards[#cards + 1] = {
            id = transfer.sourceId,
            actionKind = "supplies",
            action = "View supplies",
            title = "Withdraw before mailing: " .. transfer.count .. " x " .. Supplies.ItemLabel(
                account,
                transfer.itemId,
                account.characters[transfer.sourceId]
            ) .. " [" .. transfer.itemId .. "]",
            body = "Potential transfer to "
                .. name(account.characters[transfer.characterId])
                .. ". Withdraw manually from your personal bank, then rescan and review new mail proposals. "
                .. "Not attached or credited to the recipient; do not withdraw if already supplied elsewhere.",
        }
    end
    local source = RQ.Database.Current()
    for _, id in ipairs(RQ.Util.Keys(groups)) do
        local recipient, recipientError = mailRecipient(id)
        local ready = false
        for item in pairs(groups[id]) do
            ready = ready or (draft and not draft.counts[item]) or false
        end
        cards[#cards + 1] = {
            id = id,
            actionKind = "mail-attach",
            action = "Attach all",
            disabled = not draft or not recipient or not ready,
            title = name(account.characters[id]) .. " - " .. (account.characters[id].identity.realm or "unknown realm"),
            body = recipientError
                or "Attach all new proposed items below for this recipient. Existing draft contents are preserved.",
        }
        for _, item in ipairs(RQ.Util.Keys(groups[id])) do
            local proposal = groups[id][item]
            local already = draft and draft.counts[item]
            cards[#cards + 1] = {
                id = id,
                itemId = item,
                actionKind = "mail-attach",
                action = "Attach item",
                disabled = not draft or not recipient or already ~= nil,
                title = proposal.count .. " x " .. Supplies.ItemLabel(account, item, source) .. " [" .. item .. "]",
                body = "For "
                    .. name(account.characters[id])
                    .. "\n"
                    .. table.concat(proposal.reasons, "\n")
                    .. (proposal.stale and "\nSTALE / uncertain recipient data: verify before attaching." or "")
                    .. (
                        already
                            and ("\nAlready attached: " .. already .. ". Review/remove before adding this item again.")
                        or ""
                    ),
            }
        end
    end
    if not next(groups) then
        cards[#cards + 1] = {
            title = "No new matching proposals",
            body = "Items may already be attached, reserved, locked or needed by no recipient. "
                .. "Review the native mail draft; open the text report for setup details.",
            actionKind = "mail-text",
            action = "Text report",
        }
    end
    return cards
end

function Supplies.Mail(textOnly)
    if not RQ.Database.initialized then
        RQ.Api.Print(RQ.Database.status)
        return false
    end
    Supplies.ScanBags()
    if not textOnly and RQ.Api.IsMailboxOpen() and RQ.MainWindow then
        RQ.Api.HideCopyWindow()
        return RQ.MainWindow.Open("mail")
    end
    local report = Supplies.Evaluate(RQDB, RQ.Database.activeId, RQ.Api.GetServerTime(), RQ.MailService.Verified())
    local lines = { "MAIL PROPOSALS - nothing is attached, filled in, or sent automatically." }
    for _, transfer in ipairs(report.bankTransfers) do
        lines[#lines + 1] = "Withdraw before mailing: "
            .. transfer.count
            .. " x "
            .. Supplies.ItemLabel(RQDB, transfer.itemId)
            .. " ["
            .. transfer.itemId
            .. "] for "
            .. name(RQDB.characters[transfer.characterId])
            .. "; manually withdraw, rescan, and review. Not attached or credited to recipient."
    end
    for _, proposal in ipairs(report.proposals) do
        local recipient = RQDB.characters[proposal.characterId]
        local label = Supplies.ItemLabel(RQDB, proposal.itemId, RQ.Database.Current())
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
        lines[#lines + 1] =
            "Profession routing found no eligible surplus. For exact quantities, choose /rq need or /rq goal targets."
        local recipients = 0
        for _, id in ipairs(report.ids) do
            if id ~= RQ.Database.activeId then
                recipients = recipients + 1
                local record, grocery = RQDB.characters[id], report.groceries[id]
                local prefix = name(record) .. ": "
                if not next(grocery) then
                    lines[#lines + 1] = prefix
                        .. "no grocery targets could be calculated. Set /rq need <item ID> <quantity> "
                        .. id
                        .. " or a recipe goal."
                elseif record.inventory.bags.complete then
                    local shortage = false
                    for _, need in pairs(grocery) do
                        shortage = shortage or need.missing > 0
                    end
                    lines[#lines + 1] = prefix
                        .. (
                            shortage
                                and "shortages exist, but no safe sender surplus matches; see /rq supplies " .. id
                            or "grocery targets are already covered by the last bag snapshot."
                        )
                end
                if not record.inventory.bags.complete then
                    lines[#lines + 1] = prefix .. "bag contents are incomplete; log into this character and /rq rescan."
                end
                if not next(record.recipes.professions) then
                    lines[#lines + 1] = prefix
                        .. "no recipe catalogs scanned; open each profession on this character, then /rq scan-recipes."
                end
                if record.recipes.error then
                    lines[#lines + 1] = prefix .. "last recipe scan: " .. record.recipes.error
                end
                for _, note in ipairs(report.notes[id]) do
                    lines[#lines + 1] = prefix .. note
                end
            end
        end
        if recipients == 0 then
            lines[#lines + 1] = "No other enabled roster members. Register and enable a recipient first."
        end
        lines[#lines + 1] =
            "Known-capacity bags can replace smaller equipped bags; unknown capacity only supports empty-slot guidance."
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
                recipesAction = true,
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
