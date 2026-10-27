local Status = {}
RQ.ProfessionStatus = Status

function Status.Evaluate(snapshot, now, hours, settings)
    settings = settings or { ceiling = 300, ceilings = {}, secondary = {} }
    local scanState = RQ.Snapshot.SectionState(snapshot, "professions", now, hours)
    local levelState = RQ.Snapshot.SectionState(snapshot, "progression", now, hours)
    local result = { professions = {}, scanState = scanState, primaryCount = 0 }
    local classified = true
    for _, id in ipairs(RQ.Util.Keys(snapshot.professions or {})) do
        local profession = snapshot.professions[id]
        local kind = RQ.ProfessionConfig.Kind(id, profession)
        local status = {
            id = id,
            name = profession.name,
            kind = kind,
            skill = profession.skill,
            trainedCap = profession.maxSkill,
            state = "NOT_ASSESSED",
        }
        if kind == "primary" then
            result.primaryCount = result.primaryCount + 1
        elseif kind == "unknown" then
            classified = false
        end
        if kind == "primary" or (kind == "secondary" and settings.secondary[id] == true) then
            status.state = scanState ~= "RECENT" and scanState or levelState
            if status.state == "RECENT" then
                if
                    not RQ.Util.IsNumber(snapshot.level)
                    or snapshot.level < 1
                    or not RQ.Util.IsNumber(profession.skill)
                    or not RQ.Util.IsNumber(profession.maxSkill)
                    or profession.maxSkill < profession.skill
                    or profession.maxSkill == 0
                then
                    status.state = "UNKNOWN"
                else
                    status.ceiling = settings.ceilings[id] or settings.ceiling
                    status.benchmark = math.min(5 * snapshot.level, status.ceiling)
                    status.deficit = math.max(0, status.benchmark - profession.skill)
                    status.state = status.deficit > 0 and "BEHIND" or "ON_TRACK"
                    status.needsTraining = profession.maxSkill < status.benchmark
                end
            end
        end
        result.professions[#result.professions + 1] = status
    end
    if scanState == "RECENT" and classified then
        result.freePrimarySlots = math.max(0, 2 - result.primaryCount)
    end
    return result
end

function Status.Describe(status)
    if status.state == "BEHIND" or status.state == "ON_TRACK" then
        return (status.state == "BEHIND" and ("BEHIND by " .. status.deficit) or "ON TRACK")
            .. " | benchmark "
            .. status.benchmark
            .. " (5 x level; configured ceiling "
            .. status.ceiling
            .. ")"
            .. (status.needsTraining and "; train next rank (level/trainer requirements unverified)" or "")
    elseif status.state == "NOT_ASSESSED" then
        return status.kind == "secondary" and "Secondary benchmark not enabled" or "Unknown profession classification"
    end
    return status.state .. " benchmark evidence; rescan level and professions"
end

function Status.Lines(snapshot, now, hours, settings)
    local result = Status.Evaluate(snapshot, now, hours, settings)
    local lines = {}
    for _, status in ipairs(result.professions) do
        lines[#lines + 1] = (status.name or ("Profession " .. status.id))
            .. " ["
            .. status.id
            .. "]: "
            .. Status.Describe(status)
    end
    if result.freePrimarySlots and result.freePrimarySlots > 0 then
        lines[#lines + 1] = "Choose profession: " .. result.freePrimarySlots .. " primary slot(s) available."
    elseif result.scanState ~= "RECENT" then
        lines[#lines + 1] = result.scanState .. " profession scan; free primary slots unknown."
    end
    return lines
end
