local Config = {}
RQ.SuppliesConfig = Config

function Config.Count(value)
    return RQ.Util.IsNumber(value) and value % 1 == 0 and value <= 1000000
end

function Config.Id(value)
    return RQ.Util.IsNumber(value) and value % 1 == 0 and value > 0 and value <= 2147483647
end

function Config.IsFresh(source, now, hours)
    return source
        and source.complete
        and RQ.Util.IsNumber(now)
        and source.scannedAt > 0
        and now >= source.scannedAt
        and now - source.scannedAt < hours * 3600
end

local function counts(values)
    if type(values) ~= "table" then
        return false
    end
    for id, count in pairs(values) do
        if not Config.Id(id) or not Config.Count(count) then
            return false
        end
    end
    return true
end

local function container(parent, key)
    if parent[key] == nil then
        parent[key] = {}
    end
    return type(parent[key]) == "table"
end

function Config.PrepareReserves(value)
    if value ~= nil and type(value) ~= "table" then
        return nil, "Invalid First Aid reserves."
    end
    local reserves, seen = RQ.Util.Copy(value or {}), {}
    for key in pairs(reserves) do
        if key ~= "potions" and key ~= "bandages" then
            return nil, "Use separate potions or bandages reserve lists."
        end
    end
    for _, kind in ipairs({ "potions", "bandages" }) do
        if not container(reserves, kind) or not counts(reserves[kind]) then
            return nil, "Reserves require explicit item IDs and integer quantities from 0 to 1000000."
        end
        for item in pairs(reserves[kind]) do
            if seen[item] then
                return nil, "An item cannot be both a potion and a bandage reserve."
            end
            seen[item] = true
        end
    end
    return reserves
end

local function prepareBank(bank)
    if not container(bank, "details") or not container(bank, "tradable") or not container(bank, "containers") then
        return false, "Invalid bank metadata."
    end
    if bank.coherent == nil then
        bank.coherent = false
    end
    if bank.attemptedAt == nil then
        bank.attemptedAt = 0
    end
    if
        not counts(bank.items)
        or not counts(bank.tradable)
        or type(bank.coherent) ~= "boolean"
        or not RQ.Util.IsNumber(bank.attemptedAt)
        or (bank.error ~= nil and not RQ.Util.IsText(bank.error))
    then
        return false, "Invalid bank inventory or coherence."
    end
    for id, detail in pairs(bank.details) do
        if not Config.Id(id) or type(detail) ~= "table" or (detail.name ~= nil and not RQ.Util.IsText(detail.name)) then
            return false, "Invalid bank item metadata."
        end
    end
    for id, count in pairs(bank.tradable) do
        if count > (bank.items[id] or 0) then
            return false, "Bank transferable counts exceed stock."
        end
    end
    local totals = {}
    for id, bag in pairs(bank.containers) do
        if
            not Config.Id(id)
            or type(bag) ~= "table"
            or not Config.Id(bag.capacity)
            or bag.capacity > 1000
            or not counts(bag.items)
        then
            return false, "Invalid personal bank container."
        end
        for item, count in pairs(bag.items) do
            totals[item] = (totals[item] or 0) + count
        end
    end
    if bank.coherent then
        if not bank.complete or bank.scannedAt == 0 or bank.attemptedAt < bank.scannedAt then
            return false, "Coherent bank requires a complete timestamped observation."
        end
        for id, count in pairs(bank.items) do
            if count ~= (totals[id] or 0) then
                return false, "Bank container totals do not match stock."
            end
        end
        for id, count in pairs(totals) do
            if count ~= (bank.items[id] or 0) then
                return false, "Bank container totals do not match stock."
            end
        end
    end
    return true
end

function Config.Prepare(record)
    local intent, intentError = RQ.ProfessionConfig.PrepareIntent(record.professionIntent)
    if not intent then
        return false, intentError
    end
    record.professionIntent = intent
    if type(record.inventory) ~= "table" or type(record.recipes) ~= "table" then
        return false, "Invalid inventory or recipe ledger."
    end
    for _, key in ipairs({ "bags", "bank", "mail" }) do
        local source = record.inventory[key]
        if
            type(source) ~= "table"
            or type(source.complete) ~= "boolean"
            or not RQ.Util.IsNumber(source.scannedAt)
            or type(source.items) ~= "table"
        then
            return false, "Invalid inventory source: " .. key
        end
    end
    local bankOk, bankError = prepareBank(record.inventory.bank)
    if not bankOk then
        return false, bankError
    end
    local mailOk, mailError = RQ.MailConfig.PrepareInbox(record.inventory.mail)
    if not mailOk then
        return false, mailError
    end
    if
        type(record.recipes.complete) ~= "boolean"
        or not RQ.Util.IsNumber(record.recipes.scannedAt)
        or type(record.recipes.items) ~= "table"
    then
        return false, "Invalid recipe source metadata."
    end
    if not container(record, "supplies") then
        return false, "Invalid supplies configuration."
    end
    local supplies = record.supplies
    local reserves, reserveError = Config.PrepareReserves(supplies.reserves)
    if not reserves then
        return false, reserveError
    end
    supplies.reserves = reserves
    if not container(supplies, "needs") or not counts(supplies.needs) or not container(supplies, "goals") then
        return false, "Invalid grocery needs or profession goals."
    end
    for profession, goal in pairs(supplies.goals) do
        if
            not Config.Id(profession)
            or type(goal) ~= "table"
            or not Config.Id(goal.recipeId)
            or not Config.Id(goal.targetSkill)
        then
            return false, "Invalid profession milestone goal."
        end
    end
    local bags = record.inventory.bags
    for _, key in ipairs({ "items", "tradable", "details", "equipped", "lockedContainers" }) do
        if not container(bags, key) then
            return false, "Invalid bag ledger: " .. key
        end
    end
    if not counts(bags.items) or not counts(bags.tradable) or not counts(bags.equipped) then
        return false, "Invalid item counts or equipped bag sizes."
    end
    if not counts(bags.lockedContainers) then
        return false, "Invalid locked-container counts."
    end
    for id, count in pairs(bags.lockedContainers) do
        if count > (bags.items[id] or 0) or count > (bags.tradable[id] or 0) then
            return false, "Locked-container counts exceed eligible bag stock."
        end
    end
    for id, detail in pairs(bags.details) do
        if not Config.Id(id) or type(detail) ~= "table" then
            return false, "Invalid item metadata."
        end
        if detail.name ~= nil and not RQ.Util.IsText(detail.name) then
            return false, "Invalid item name."
        end
        for _, key in ipairs({ "classId", "subclassId", "quality", "bindType" }) do
            if detail[key] ~= nil and not Config.Count(detail[key]) then
                return false, "Invalid item class."
            end
            if
                detail.bagSlots ~= nil
                and (
                    not Config.Id(detail.bagSlots)
                    or detail.bagSlots > 100
                    or detail.classId ~= 1
                    or detail.subclassId ~= 0
                )
            then
                return false, "Invalid general-purpose bag capacity."
            end
        end
    end
    for _, source in ipairs({ bags, record.recipes }) do
        if source.error ~= nil and not RQ.Util.IsText(source.error) then
            return false, "Invalid scan error."
        end
    end
    if not container(record.recipes, "professions") then
        return false, "Invalid recipe ledger."
    end
    for profession, scan in pairs(record.recipes.professions) do
        if
            not Config.Id(profession)
            or type(scan) ~= "table"
            or type(scan.complete) ~= "boolean"
            or not RQ.Util.IsNumber(scan.scannedAt)
            or not RQ.Util.IsText(scan.name)
            or type(scan.recipes) ~= "table"
        then
            return false, "Invalid profession recipe scan."
        end
        for id, recipe in pairs(scan.recipes) do
            if
                not Config.Id(id)
                or type(recipe) ~= "table"
                or not RQ.Util.IsText(recipe.name)
                or type(recipe.learned) ~= "boolean"
                or type(recipe.reagentsComplete) ~= "boolean"
                or not counts(recipe.reagents)
                or not Config.Count(recipe.skillUps)
                or (recipe.source ~= nil and type(recipe.source) ~= "string")
                or (recipe.sourceItem ~= nil and not Config.Id(recipe.sourceItem))
                or (recipe.difficulty ~= nil and (not Config.Count(recipe.difficulty) or recipe.difficulty > 3))
                or (recipe.outputItemId ~= nil and not Config.Id(recipe.outputItemId))
                or (recipe.outputCount ~= nil and (not Config.Id(recipe.outputCount) or recipe.outputCount > 1000000))
                or ((recipe.outputItemId == nil) ~= (recipe.outputCount == nil))
                or (recipe.outputBindType ~= nil and not Config.Count(recipe.outputBindType))
                or (recipe.outputBindType ~= nil and recipe.outputItemId == nil)
                or (
                    recipe.bagSlots ~= nil
                    and (not Config.Id(recipe.bagSlots) or recipe.bagSlots > 100 or recipe.outputItemId == nil)
                )
            then
                return false, "Invalid recipe observation."
            end
        end
    end
    return true
end
