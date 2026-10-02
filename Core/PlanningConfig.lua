local Config = { sampleLimit = 8, minimumCalibrationSeconds = 300 }
RQ.PlanningConfig = Config

local function numericArray(value, limit, maximum, ordered)
    if type(value) ~= "table" then
        return false
    end
    local count, previous = 0, 0
    for index, item in ipairs(value) do
        if not RQ.Util.IsNumber(item) or item > maximum or (ordered and (item <= previous or item % 1 ~= 0)) then
            return false
        end
        count, previous = index, item
    end
    for key in pairs(value) do
        if not RQ.Util.IsNumber(key) or key % 1 ~= 0 or key < 1 or key > count then
            return false
        end
    end
    return count <= limit and (not ordered or count > 0)
end

function Config.Prepare(value)
    if value ~= nil and type(value) ~= "table" then
        return nil, "Planning settings must be a table."
    end
    local settings = RQ.Util.Copy(value or {})
    for key, default in pairs(RQ.DefaultPlanning) do
        if settings[key] == nil then
            settings[key] = RQ.Util.Copy(default)
        end
    end
    for _, field in ipairs(RQ.PlanningFields) do
        local number = settings[field.key]
        if
            not RQ.Util.IsNumber(number)
            or number < field.min
            or number > field.max
            or (field.integer and number % 1 ~= 0)
        then
            return nil, "Invalid planning setting: " .. field.key
        end
    end
    if
        not numericArray(settings.levelMilestones, 20, 1000, true)
        or not numericArray(settings.professionMilestones, 20, 100000, true)
    then
        return nil, "Milestones must be nonempty, ascending arrays of positive integers."
    end
    if type(settings.weights) ~= "table" then
        return nil, "Planning weights must be a table."
    end
    for key, default in pairs(RQ.DefaultPlanning.weights) do
        if settings.weights[key] == nil then
            settings.weights[key] = default
        end
        if not RQ.Util.IsFinite(settings.weights[key]) or math.abs(settings.weights[key]) > 100000 then
            return nil, "Invalid planning weight: " .. key
        end
    end
    if settings.pinnedCharacterId ~= nil and not RQ.Util.IsText(settings.pinnedCharacterId) then
        return nil, "Invalid pinned character ID."
    end
    return settings
end

function Config.ValidEntry(entry)
    return RQ.Util.IsNumber(entry.restedMultiplier)
        and entry.restedMultiplier >= 0.01
        and entry.restedMultiplier <= 100
        and RQ.Util.IsNumber(entry.restedRevision)
        and entry.restedRevision % 1 == 0
        and type(entry.resourceBlocker) == "boolean"
        and type(entry.dungeonReady) == "boolean"
end

function Config.PrepareState(value)
    if value ~= nil and type(value) ~= "table" then
        return nil, "Rested state must be a table."
    end
    local state = RQ.Util.Copy(value or {})
    if state.logoutReason ~= nil and not RQ.Util.IsText(state.logoutReason) then
        return nil, "Invalid rested logout reason."
    end
    if state.calibration == nil then
        state.calibration = { profile = "", inside = {}, outside = {} }
    end
    local calibration = state.calibration
    if
        type(calibration) ~= "table"
        or type(calibration.profile) ~= "string"
        or not numericArray(calibration.inside, Config.sampleLimit, math.huge, false)
        or not numericArray(calibration.outside, Config.sampleLimit, math.huge, false)
    then
        return nil, "Invalid rested calibration samples."
    end
    local sample = state.logout
    if sample ~= nil then
        if type(sample) ~= "table" or type(sample.wasResting) ~= "boolean" or type(sample.profile) ~= "string" then
            return nil, "Invalid rested logout sample."
        end
        for _, key in ipairs({ "at", "level", "xp", "xpMax", "restedXp", "multiplier", "revision" }) do
            if not RQ.Util.IsNumber(sample[key]) then
                return nil, "Invalid rested logout field: " .. key
            end
        end
        if
            sample.at == 0
            or sample.xpMax < 1
            or sample.multiplier < 0.01
            or sample.multiplier > 100
            or sample.revision % 1 ~= 0
        then
            return nil, "Invalid rested logout bounds."
        end
        if sample.cached ~= nil and type(sample.cached) ~= "boolean" then
            return nil, "Invalid cached logout flag."
        end
        if sample.observedAt ~= nil or sample.cached then
            if not RQ.Util.IsNumber(sample.observedAt) or sample.observedAt == 0 or sample.observedAt > sample.at then
                return nil, "Invalid logout observation timestamp."
            end
        end
    end
    if state.comparison ~= nil then
        local comparison = state.comparison
        if
            type(comparison) ~= "table"
            or type(comparison.reason) ~= "string"
            or type(comparison.accepted) ~= "boolean"
        then
            return nil, "Invalid rested calibration comparison."
        end
        for _, key in ipairs({ "at", "actual", "estimated", "observedRate" }) do
            if comparison[key] ~= nil and not RQ.Util.IsNumber(comparison[key]) then
                return nil, "Invalid calibration comparison field: " .. key
            end
        end
        if comparison.error ~= nil and not RQ.Util.IsFinite(comparison.error) then
            return nil, "Invalid calibration error."
        end
    end
    return state
end
