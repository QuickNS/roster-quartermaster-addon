local Config = {}
RQ.SuppliesConfig = Config

function Config.Count(value)
    return RQ.Util.IsNumber(value) and value % 1 == 0 and value <= 1000000
end

function Config.Id(value)
    return RQ.Util.IsNumber(value) and value % 1 == 0 and value > 0 and value <= 2147483647
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

function Config.Prepare(record)
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
    for _, key in ipairs({ "items", "tradable", "details", "equipped" }) do
        if not container(bags, key) then
            return false, "Invalid bag ledger: " .. key
        end
    end
    if not counts(bags.items) or not counts(bags.tradable) or not counts(bags.equipped) then
        return false, "Invalid item counts or equipped bag sizes."
    end
    for id, detail in pairs(bags.details) do
        if not Config.Id(id) or type(detail) ~= "table" then
            return false, "Invalid item metadata."
        end
        if detail.name ~= nil and not RQ.Util.IsText(detail.name) then
            return false, "Invalid item name."
        end
        for _, key in ipairs({ "classId", "subclassId" }) do
            if detail[key] ~= nil and not Config.Count(detail[key]) then
                return false, "Invalid item class."
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
            then
                return false, "Invalid recipe observation."
            end
        end
    end
    return true
end
