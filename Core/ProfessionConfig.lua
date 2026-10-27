local Config = {}
RQ.ProfessionConfig = Config

-- Skill-line IDs, not localized names. Unknown IDs need observed classification.
Config.primary = {
    [164] = true,
    [165] = true,
    [171] = true,
    [182] = true,
    [186] = true,
    [197] = true,
    [202] = true,
    [333] = true,
    [393] = true,
}
Config.secondary = { [129] = true, [185] = true, [356] = true }

function Config.Prepare(value)
    if value ~= nil and type(value) ~= "table" then
        return nil, "Invalid profession benchmark settings."
    end
    local settings = RQ.Util.Copy(value or {})
    if settings.rankingEnabled == nil then
        settings.rankingEnabled = false
    end
    if settings.rankingWeight == nil then
        settings.rankingWeight = 10
    end
    if
        type(settings.rankingEnabled) ~= "boolean"
        or not RQ.Util.IsNumber(settings.rankingWeight)
        or settings.rankingWeight > 100
    then
        return nil, "Profession ranking requires an explicit enabled flag and a weight from 0 to 100."
    end
    if settings.ceiling == nil then
        settings.ceiling = 300
    end
    if not RQ.SuppliesConfig.Id(settings.ceiling) or settings.ceiling > 10000 then
        return nil, "Profession ceiling must be an integer from 1 to 10000."
    end
    for _, field in ipairs({ "ceilings", "secondary" }) do
        if settings[field] == nil then
            settings[field] = {}
        end
        if type(settings[field]) ~= "table" then
            return nil, "Invalid profession " .. field .. " settings."
        end
        for id, entry in pairs(settings[field]) do
            if
                not RQ.SuppliesConfig.Id(id)
                or (field == "secondary" and type(entry) ~= "boolean")
                or (field == "ceilings" and (not RQ.SuppliesConfig.Id(entry) or entry > 10000))
            then
                return nil, "Invalid profession " .. field .. " entry."
            end
        end
    end
    return settings
end

function Config.PrepareIntent(value)
    if value ~= nil and type(value) ~= "table" then
        return nil, "Invalid profession intent."
    end
    local intent = RQ.Util.Copy(value or {})
    if intent.focus == nil then
        intent.focus = "balanced"
    end
    if intent.focus ~= "balanced" and intent.focus ~= "gathering" and intent.focus ~= "self-sufficient" then
        return nil, "Profession focus must be balanced, gathering or self-sufficient."
    end
    for _, field in ipairs({ "planned", "preferred", "excluded" }) do
        if intent[field] == nil then
            intent[field] = {}
        end
        if type(intent[field]) ~= "table" then
            return nil, "Invalid profession " .. field .. " choices."
        end
        for id, enabled in pairs(intent[field]) do
            if not Config.primary[id] or enabled ~= true then
                return nil, "Use supported primary profession IDs."
            end
        end
    end
    if #RQ.Util.Keys(intent.planned) > 2 then
        return nil, "Plan at most two primary professions."
    end
    for id in pairs(intent.excluded) do
        if intent.planned[id] or intent.preferred[id] then
            return nil, "A planned/preferred profession cannot also be excluded."
        end
    end
    return intent
end

function Config.Kind(id, profession)
    if profession.kind then
        return profession.kind
    elseif Config.primary[id] then
        return "primary"
    elseif Config.secondary[id] then
        return "secondary"
    end
    return "unknown"
end
