local Bags = {}
RQ.BagPlanner = Bags

local fresh = RQ.SuppliesConfig.IsFresh

local function readyRecipes(record, now, hours)
    local section = record.snapshot.sections and record.snapshot.sections.professions
    local scan = record.recipes.professions[197]
    return record.snapshot.professions
            and record.snapshot.professions[197]
            and section
            and fresh({ complete = section.complete, scannedAt = section.observedAt or 0 }, now, hours)
            and fresh(scan, now, hours)
            and not record.recipes.error
            and scan.recipes
        or nil
end

local function usable(recipe)
    return recipe.learned and recipe.reagentsComplete and recipe.outputItemId and recipe.outputCount
end

local function materials(record, recipes, jobs, reserved, now, hours)
    local needs, stock, generated, conversions, notes = {}, {}, {}, {}, {}
    for item, count in pairs(RQ.InventoryAvailability.Materials(record, now, hours)) do
        stock[item] = math.max(0, count - (reserved[item] and reserved[item].target or 0))
    end
    local converters = {}
    for _, id in ipairs(RQ.Util.Keys(recipes)) do
        local recipe = recipes[id]
        if usable(recipe) and not recipe.bagSlots and not converters[recipe.outputItemId] then
            converters[recipe.outputItemId] = id
        end
    end
    local valid, operations = true, 0
    local function requireItem(item, count, path, depth)
        operations = operations + 1
        if not valid or count > 1000000 or depth > 8 or operations > 10000 then
            valid = false
            return
        end
        local produced = math.min(count, generated[item] or 0)
        generated[item], count = (generated[item] or 0) - produced, count - produced
        local have = math.min(count, stock[item] or 0)
        stock[item], count = (stock[item] or 0) - have, count - have
        needs[item] = (needs[item] or 0) + have
        if count <= 0 then
            return
        end
        local id = converters[item]
        if id and not path[item] then
            local recipe = recipes[id]
            local crafts = math.ceil(count / recipe.outputCount)
            path[item] = true
            conversions[id] = (conversions[id] or 0) + crafts
            for _, reagent in ipairs(RQ.Util.Keys(recipe.reagents)) do
                requireItem(reagent, recipe.reagents[reagent] * crafts, path, depth + 1)
            end
            path[item] = nil
            generated[item] = (generated[item] or 0) + crafts * recipe.outputCount - count
        else
            needs[item] = (needs[item] or 0) + count
            if path[item] then
                notes[#notes + 1] = "Cyclic material recipe: acquire item " .. item .. " directly."
            end
        end
    end
    local demand = {}
    for id, job in pairs(jobs) do
        for item, count in pairs(recipes[id].reagents) do
            demand[item] = (demand[item] or 0) + count * job.crafts
        end
    end
    for _, item in ipairs(RQ.Util.Keys(demand)) do
        requireItem(item, demand[item], {}, 0)
    end
    for _, count in pairs(needs) do
        if count > 1000000 then
            valid = false
        end
    end
    if not valid then
        return {}, {}, { "Bag material expansion exceeded safe limits; configure these materials manually." }
    end
    return needs, conversions, notes
end

local function bagCapacity(detail)
    return detail
            and detail.classId == 1
            and detail.subclassId == 0
            and RQ.SuppliesConfig.Id(detail.bagSlots)
            and detail.bagSlots <= 100
            and detail.bagSlots
        or nil
end

local function observedCapacity(item, detail, capacities)
    local observed = bagCapacity(detail)
    if observed then
        return (capacities[item] == nil or capacities[item] == observed) and observed or nil
    end
    if not detail or (detail.classId == nil and detail.subclassId == nil and detail.bagSlots == nil) then
        return capacities[item] or nil
    end
end

local function mailPool(account, id, coverage, groceries, capacities)
    local pool = {}
    local record = account.characters[id]
    for _, state in ipairs({ "inbox", "pending" }) do
        for _, item in ipairs(RQ.Util.Keys(coverage[state])) do
            local reserved = groceries[item]
            local keep = reserved and (state == "inbox" and reserved.collect or reserved.inTransit) or 0
            local count = math.max(0, coverage[state][item] - (keep or 0))
            if state == "inbox" then
                local capacity = observedCapacity(item, record.inventory.mail.details[item], capacities)
                if capacity and count > 0 then
                    pool[#pool + 1] = { itemId = item, capacity = capacity, count = count, state = state }
                end
            else
                for _, origin in ipairs(coverage.pendingSources[item] or {}) do
                    local transfer = account.mailTracking.transfers[origin.transferId]
                    local quantity = math.min(count, origin.quantity)
                    local capacity = observedCapacity(item, transfer.details and transfer.details[item], capacities)
                    if capacity and quantity > 0 then
                        pool[#pool + 1] = {
                            itemId = item,
                            capacity = capacity,
                            count = quantity,
                            state = state,
                            transferId = origin.transferId,
                        }
                        count = count - quantity
                    end
                end
            end
        end
    end
    table.sort(pool, function(a, b)
        if a.capacity ~= b.capacity then
            return a.capacity > b.capacity
        elseif a.itemId ~= b.itemId then
            return a.itemId < b.itemId
        elseif a.state ~= b.state then
            return a.state < b.state
        end
        return (a.transferId or 0) < (b.transferId or 0)
    end)
    return pool
end

function Bags.Evaluate(account, now, groceries, verifiedMail)
    groceries = groceries or {}
    local result = {
        members = {},
        upgrades = {},
        crafts = {},
        materials = {},
        conversions = {},
        notes = {},
        covered = {},
    }
    local ids, slots, pool, candidates = {}, {}, {}, {}
    local delivery = {}
    local hours = account.policies.staleSnapshotHours
    for _, id in ipairs(RQ.Util.Keys(account.roster)) do
        local record = account.characters[id]
        if account.roster[id].enabled and record and record.registration == "member" then
            ids[#ids + 1] = id
            local bags = record.inventory.bags
            local recent = fresh(bags, now, hours)
            result.members[id] = { equipped = RQ.Util.Copy(bags.equipped), recent = recent, scannedAt = bags.scannedAt }
            if recent then
                for _, index in ipairs(RQ.Util.Keys(bags.equipped)) do
                    slots[#slots + 1] = { characterId = id, slot = index, from = bags.equipped[index] }
                end
                for _, item in ipairs(RQ.Util.Keys(bags.items)) do
                    local detail = bags.details[item]
                    if detail and detail.classId == 1 and detail.subclassId == 0 and detail.bagSlots then
                        local reserved = groceries[id] and groceries[id][item]
                        local count = math.max(0, bags.items[item] - (reserved and reserved.target or 0))
                        pool[#pool + 1] = {
                            ownerId = id,
                            itemId = item,
                            capacity = detail.bagSlots,
                            count = count,
                            tradable = math.min(count, bags.tradable[item] or 0),
                        }
                    end
                end
                local recipes = readyRecipes(record, now, hours) or {}
                for _, recipeId in ipairs(RQ.Util.Keys(recipes)) do
                    local recipe = recipes[recipeId]
                    if usable(recipe) and recipe.bagSlots then
                        candidates[#candidates + 1] = {
                            crafterId = id,
                            recipeId = recipeId,
                            capacity = recipe.bagSlots,
                            itemId = recipe.outputItemId,
                            outputCount = recipe.outputCount,
                            transferable = recipe.outputBindType == 0
                                or recipe.outputBindType == 2
                                or recipe.outputBindType == 3,
                        }
                    end
                end
            end
        end
    end
    local capacities = {}
    for _, observations in ipairs({ pool, candidates }) do
        for _, bag in ipairs(observations) do
            local previous = capacities[bag.itemId]
            capacities[bag.itemId] = (previous == nil or previous == bag.capacity) and bag.capacity or false
        end
    end
    for _, id in ipairs(ids) do
        delivery[id] = mailPool(
            account,
            id,
            RQ.MailTracker.Coverage(account, id, now, verifiedMail),
            groceries[id] or {},
            capacities
        )
    end
    table.sort(candidates, function(a, b)
        if a.capacity ~= b.capacity then
            return a.capacity > b.capacity
        end
        if a.crafterId ~= b.crafterId then
            return a.crafterId < b.crafterId
        end
        return a.recipeId < b.recipeId
    end)
    table.sort(pool, function(a, b)
        if a.capacity ~= b.capacity then
            return a.capacity > b.capacity
        end
        if a.ownerId ~= b.ownerId then
            return a.ownerId < b.ownerId
        end
        return a.itemId < b.itemId
    end)
    table.sort(slots, function(a, b)
        if a.from ~= b.from then
            return a.from < b.from
        end
        if a.characterId ~= b.characterId then
            return a.characterId < b.characterId
        end
        return a.slot < b.slot
    end)
    local function assign(slot, bag, kind, sourceId, recipeId)
        slot.assigned = true
        result.upgrades[#result.upgrades + 1] = {
            characterId = slot.characterId,
            slot = slot.slot,
            from = slot.from,
            to = bag.capacity,
            itemId = bag.itemId,
            sourceId = sourceId,
            recipeId = recipeId,
            kind = kind,
        }
    end
    -- Mail is only duplicate-work suppression, never an equip/craft-ready action.
    for _, slot in ipairs(slots) do
        for _, bag in ipairs(delivery[slot.characterId] or {}) do
            if bag.count > 0 and bag.capacity > slot.from then
                slot.assigned, bag.count = true, bag.count - 1
                result.covered[#result.covered + 1] = {
                    characterId = slot.characterId,
                    slot = slot.slot,
                    from = slot.from,
                    to = bag.capacity,
                    itemId = bag.itemId,
                    state = bag.state,
                    transferId = bag.transferId,
                }
                break
            end
        end
    end
    -- Reserve local usable bags first; never mail away an owner's own upgrade.
    for _, slot in ipairs(slots) do
        for _, bag in ipairs(pool) do
            if not slot.assigned and bag.ownerId == slot.characterId and bag.count > 0 and bag.capacity > slot.from then
                assign(slot, bag, "equip", bag.ownerId)
                bag.count = bag.count - 1
                bag.tradable = math.min(bag.tradable, bag.count)
                break
            end
        end
    end
    for _, slot in ipairs(slots) do
        if not slot.assigned then
            for _, bag in ipairs(pool) do
                if
                    bag.ownerId ~= slot.characterId
                    and bag.tradable > 0
                    and bag.capacity > slot.from
                    and RQ.Character.CanTrade(
                        account.characters[bag.ownerId].identity,
                        account.characters[slot.characterId].identity
                    )
                then
                    assign(slot, bag, "mail", bag.ownerId)
                    bag.tradable, bag.count = bag.tradable - 1, bag.count - 1
                    break
                end
            end
        end
        local best
        for _, candidate in ipairs(candidates) do
            if
                candidate.crafterId == slot.characterId
                or (
                    candidate.transferable
                    and RQ.Character.CanTrade(
                        account.characters[candidate.crafterId].identity,
                        account.characters[slot.characterId].identity
                    )
                )
            then
                best = candidate
                break
            end
        end
        if not slot.assigned and best and best.capacity > slot.from then
            assign(slot, best, "craft", best.crafterId, best.recipeId)
            local jobs = result.crafts[best.crafterId] or {}
            local job = jobs[best.recipeId] or { bags = 0, crafts = 0, itemId = best.itemId, capacity = best.capacity }
            job.bags = job.bags + 1
            job.crafts = math.ceil(job.bags / best.outputCount)
            jobs[best.recipeId], result.crafts[best.crafterId] = job, jobs
        end
    end
    for _, id in ipairs(ids) do
        if result.crafts[id] then
            result.materials[id], result.conversions[id], result.notes[id] = materials(
                account.characters[id],
                readyRecipes(account.characters[id], now, hours),
                result.crafts[id],
                groceries[id] or {},
                now,
                hours
            )
        end
    end
    return result
end
