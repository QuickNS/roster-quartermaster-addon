local Policies = {}
RQ.LogisticsPolicies = Policies

Policies.categories = { "herbs", "leather", "food", "engineering", "blacksmithing" }

function Policies.Defaults()
    local value = { categories = {}, cooks = {} }
    for _, category in ipairs(Policies.categories) do
        value.categories[category] = { items = {}, recipients = {} }
    end
    return value
end

function Policies.Prepare(value)
    if value ~= nil and type(value) ~= "table" then
        return nil, "Invalid logistics policies."
    end
    local result = RQ.Util.Copy(value or {})
    for key in pairs(result) do
        if key ~= "categories" and key ~= "cooks" then
            return nil, "Unknown logistics policy field."
        end
    end
    if result.cooks == nil then
        result.cooks = {}
    end
    if type(result.cooks) ~= "table" then
        return nil, "Invalid Cooking/Fishing assignments."
    end
    for group, id in pairs(result.cooks) do
        if
            (group ~= "PVE:Alliance" and group ~= "PVE:Horde" and group ~= "PVP:Alliance" and group ~= "PVP:Horde")
            or not RQ.Util.IsText(id)
            or not id:match("^Player%-[%w%-]+$")
            or #id > 128
        then
            return nil, "Cooking/Fishing assignments require a ruleset/faction group and character GUID."
        end
    end
    if result.categories == nil then
        result.categories = {}
    end
    if type(result.categories) ~= "table" then
        return nil, "Invalid logistics categories."
    end
    local supported, assigned = {}, {}
    for _, category in ipairs(Policies.categories) do
        supported[category] = true
        local rule = result.categories[category]
        if rule == nil then
            rule = { items = {}, recipients = {} }
            result.categories[category] = rule
        end
        if type(rule) ~= "table" then
            return nil, "Invalid routing rule: " .. category
        end
        for key in pairs(rule) do
            if key ~= "items" and key ~= "recipients" then
                return nil, "Unknown routing rule field."
            end
        end
        if rule.items == nil then
            rule.items = {}
        end
        if rule.recipients == nil then
            rule.recipients = {}
        end
        if type(rule.items) ~= "table" or type(rule.recipients) ~= "table" then
            return nil, "Routing requires item IDs and an ordered recipient GUID list."
        end
        for item, enabled in pairs(rule.items) do
            if not RQ.SuppliesConfig.Id(item) or enabled ~= true then
                return nil, "Routing item IDs must map to true."
            end
            if assigned[item] then
                return nil, "Assign each item ID to only one category; choose Engineering or Blacksmithing explicitly."
            end
            assigned[item] = category
        end
        local seen, count = {}, 0
        for index, id in pairs(rule.recipients) do
            count = count + 1
            if
                not RQ.SuppliesConfig.Id(index)
                or index > #rule.recipients
                or not RQ.Util.IsText(id)
                or not id:match("^Player%-%S+$")
                or #id > 128
                or seen[id]
            then
                return nil, "Use a contiguous ordered list of unique character GUIDs."
            end
            seen[id] = true
        end
        if count ~= #rule.recipients or count > 100 then
            return nil, "Routing supports at most 100 ordered recipient GUIDs."
        end
    end
    for category in pairs(result.categories) do
        if not supported[category] then
            return nil, "Unknown routing category: " .. tostring(category)
        end
    end
    return result
end

function Policies.Rule(account, itemId)
    local settings = account.settings and account.settings.logistics
    for _, category in ipairs(Policies.categories) do
        local rule = settings and settings.categories and settings.categories[category]
        if rule and rule.items[itemId] then
            return rule, category
        end
    end
end

function Policies.Cook(account, identity)
    local group = RQ.Character.TradeGroup(identity)
    local policies = account.settings and account.settings.logistics
    local id = group and policies and policies.cooks and policies.cooks[group]
    local record, entry = id and account.characters[id], id and account.roster[id]
    if
        record
        and record.registration == "member"
        and entry
        and entry.enabled
        and RQ.Character.TradeGroup(record.identity) == group
    then
        return id
    end
end

function Policies.CookingItem(account, itemId)
    local _, category = Policies.Rule(account, itemId)
    return RQ.CookingItems[itemId] == true or category == "food"
end

function Policies.Recipients(account, itemId, ids)
    local rule = Policies.Rule(account, itemId)
    if not rule then
        return ids
    end
    local result, eligible, seen = {}, {}, {}
    for _, id in ipairs(ids) do
        eligible[id] = true
    end
    for _, id in ipairs(rule.recipients) do
        if eligible[id] then
            result[#result + 1], seen[id] = id, true
        end
    end
    for _, id in ipairs(ids) do
        if not seen[id] then
            result[#result + 1] = id
        end
    end
    return result
end
