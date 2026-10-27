local Card = {}
RQ.CharacterCard = Card

local function text(value)
    if value == nil then
        return "Unknown"
    end
    return (tostring(value):gsub("|", "||"))
end
Card.Text = text

function Card.Age(timestamp, now)
    if not RQ.Util.IsNumber(timestamp) or timestamp == 0 or not RQ.Util.IsNumber(now) then
        return "Unknown"
    end
    local elapsed = now - timestamp
    if elapsed < 0 then
        return "Clock mismatch"
    elseif elapsed < 60 then
        return math.floor(elapsed) .. "s ago"
    elseif elapsed < 3600 then
        return math.floor(elapsed / 60) .. "m ago"
    elseif elapsed < 86400 then
        return math.floor(elapsed / 3600) .. "h ago"
    end
    return math.floor(elapsed / 86400) .. "d ago"
end

function Card.Rested(estimate)
    return text(RQ.RestedEstimator.Describe(estimate))
end

function Card.RestedVisual(estimate)
    if not estimate or estimate.amount == nil then
        return {
            label = "Rested XP: unknown",
            badge = "UNKNOWN",
            note = text(estimate and estimate.reason or "No rested observation"),
        }
    end
    local badge = not estimate.isEstimated and "OBSERVED"
        or estimate.cachedBaseline and "CACHED ESTIMATE"
        or "ESTIMATED"
    return {
        label = "Rested: " .. text(estimate.amount) .. " XP" .. (estimate.percentageOfLevel and string.format(
            " | %.1f%% of a level",
            estimate.percentageOfLevel
        ) or " | level percentage unknown"),
        badge = badge .. " / " .. text(estimate.confidence),
        ratio = estimate.capRatio,
        note = "Bar uses the configured rested cap, not a verified Forever cap.",
    }
end

local function visual(record, entry, now, activeId, id, staleHours, professionSettings, estimate)
    local identity, snapshot = record.identity, record.snapshot
    local assessment = RQ.ProfessionStatus.Evaluate(snapshot, now, staleHours, professionSettings)
    local professions, behind, deficit = {}, 0, 0
    local uncertain = assessment.scanState ~= "RECENT"
        or RQ.Snapshot.SectionState(snapshot, "progression", now, staleHours) ~= "RECENT"
        or RQ.Snapshot.Freshness(snapshot, now, staleHours) ~= "RECENT"
    for _, status in ipairs(assessment.professions) do
        local label = text(status.name) .. " " .. text(status.skill)
        if status.benchmark then
            label = label
                .. " / benchmark "
                .. status.benchmark
                .. (status.deficit > 0 and (" Behind " .. status.deficit) or " On track")
            if status.needsTraining then
                label = label .. " / Train rank"
            end
        elseif status.state == "NOT_ASSESSED" then
            label = label .. " / cap " .. text(status.trainedCap)
            if status.kind == "unknown" then
                uncertain = true
            end
        else
            label = label .. " " .. status.state
            uncertain = true
        end
        if status.deficit and status.deficit > 0 then
            behind, deficit = behind + 1, math.max(deficit, status.deficit)
        end
        local short = text(status.name) .. " " .. text(status.skill) .. "/" .. text(status.trainedCap)
        if status.state == "BEHIND" then
            short = short .. " | Behind " .. status.deficit
        elseif status.state ~= "ON_TRACK" and status.state ~= "NOT_ASSESSED" then
            short = short .. " | " .. status.state
        end
        if status.needsTraining then
            short = short .. " | Train"
        end
        professions[#professions + 1] = { id = status.id, label = label, shortLabel = short, state = status.state }
    end
    local badges = {}
    if id == activeId then
        badges[#badges + 1] = "ACTIVE"
    end
    if entry.isMain then
        badges[#badges + 1] = "MAIN"
    end
    if record.registration ~= "member" or entry.enabled ~= true then
        badges[#badges + 1] = record.registration == "ignored" and "IGNORED"
            or record.registration == "member" and "DISABLED"
            or "PENDING"
    end
    return {
        name = text(RQ.Character.DisplayName(identity)),
        class = identity.class,
        role = entry.role and entry.role ~= "UNASSIGNED" and text(RQ.Character.roleLabels[entry.role] or entry.role)
            or nil,
        level = snapshot.level,
        realm = text(identity.realm),
        realmKey = RQ.Character.Realm(identity) or "~unknown",
        groupKey = RQ.Character.TradeGroup(identity) or "~unknown",
        groupLabel = RQ.Character.TradeGroupLabel(identity),
        badges = table.concat(badges, " / "),
        freshness = RQ.Snapshot.Freshness(snapshot, now, staleHours),
        age = Card.Age(snapshot.lastSeen, now),
        professions = professions,
        professionNote = assessment.freePrimarySlots
                and assessment.freePrimarySlots > 0
                and ("Choose profession: " .. assessment.freePrimarySlots .. " free primary slot(s)")
            or (#professions == 0 and "Professions unknown; rescan" or nil),
        behind = behind,
        deficit = deficit,
        uncertain = uncertain,
        member = record.registration == "member" and entry.enabled == true,
        rested = Card.RestedVisual(estimate),
    }
end

function Card.Build(id, record, entry, now, activeId, staleHours, estimate, professionSettings)
    entry = entry or {}
    local identity, snapshot = record.identity, record.snapshot
    local lines = {
        "Trade group: " .. RQ.Character.TradeGroupLabel(identity),
        text(identity.race) .. " / " .. text(identity.class),
        "Role: "
            .. text(RQ.Character.roleLabels[entry.role] or entry.role)
            .. " | Registration: "
            .. record.registration,
        "Level: " .. text(snapshot.level) .. " | XP: " .. text(snapshot.xp) .. " / " .. text(snapshot.xpMax),
        "Rested XP: "
            .. text(snapshot.restedXp)
            .. (id == activeId and " (last observed on this character)" or " (last observed offline; not an estimate)"),
        "Last seen: "
            .. Card.Age(snapshot.lastSeen, now)
            .. " | Timestamp: "
            .. text(snapshot.lastSeen)
            .. " | "
            .. RQ.Snapshot.Freshness(snapshot, now, staleHours)
            .. " | Last logout: "
            .. text(snapshot.lastLogout),
        "Location: "
            .. text(snapshot.zone)
            .. " / "
            .. text(snapshot.subZone)
            .. " | Resting: "
            .. (snapshot.wasResting == nil and "Unknown" or snapshot.wasResting and "Yes" or "No"),
        "Money (copper): "
            .. text(snapshot.money)
            .. " | Free bag slots: "
            .. text(snapshot.freeBagSlots)
            .. " / "
            .. text(snapshot.bagSlots),
    }
    local professions = {}
    if estimate then
        lines[4] = Card.Rested(estimate)
    end
    for _, professionId in ipairs(RQ.Util.Keys(snapshot.professions or {})) do
        local profession = snapshot.professions[professionId]
        professions[#professions + 1] = text(profession.name)
            .. " "
            .. text(profession.skill)
            .. "/"
            .. text(profession.maxSkill)
    end
    lines[#lines + 1] = "Professions (skill/cap): "
        .. (#professions > 0 and table.concat(professions, ", ") or "None observed")
    for _, line in ipairs(RQ.ProfessionStatus.Lines(snapshot, now, staleHours, professionSettings)) do
        lines[#lines + 1] = text(line)
    end
    lines[#lines + 1] = "Stock targets: Inventory | Recipes: /rq recipes | Session tasks: /rq tasks"
    lines[#lines + 1] = "Profession coverage and free-slot advice: /rq professions " .. text(id)
    local bags = record.inventory and record.inventory.bags
    local sizes = {}
    for _, index in ipairs(RQ.Util.Keys(bags and bags.equipped or {})) do
        local capacity = bags.equipped[index]
        sizes[#sizes + 1] = "Slot " .. index .. ": " .. (capacity == 0 and "empty" or capacity .. " slots")
    end
    lines[#lines + 1] = "Equipped bags (last observed): " .. (#sizes > 0 and table.concat(sizes, ", ") or "Unknown")
    lines[#lines + 1] = "Bag scan: "
        .. Card.Age(bags and bags.scannedAt, now)
        .. (bags and bags.complete and "" or " / incomplete or unknown")
    for _, professionId in ipairs(RQ.Util.Keys(record.supplies and record.supplies.goals or {})) do
        local goal = record.supplies.goals[professionId]
        lines[#lines + 1] = "Configured goal: profession "
            .. professionId
            .. ", recipe "
            .. goal.recipeId
            .. " -> skill "
            .. goal.targetSkill
    end
    for _, itemId in ipairs(RQ.Util.Keys(record.supplies and record.supplies.needs or {})) do
        lines[#lines + 1] = "Stock target: item " .. itemId .. " x" .. record.supplies.needs[itemId]
    end
    local uncertain = {}
    for _, section in ipairs(RQ.Util.Keys(RQ.Snapshot.fields)) do
        local state = (snapshot.sections or {})[section]
        if
            not state
            or not state.complete
            or not state.observedAt
            or not now
            or now < state.observedAt
            or now - state.observedAt >= staleHours * 3600
        then
            uncertain[#uncertain + 1] = section
        end
    end
    if #uncertain > 0 then
        lines[#lines + 1] = "Incomplete, stale, or unknown sections: " .. table.concat(uncertain, ", ")
    end
    lines[#lines + 1] = "ID: " .. text(id)
    return {
        id = id,
        title = text(RQ.Character.DisplayName(identity))
            .. " - "
            .. text(identity.realm)
            .. (entry.isMain and " [MAIN]" or "")
            .. (id == activeId and " [ACTIVE]" or ""),
        body = table.concat(lines, "\n"),
        action = "Configure",
        visual = visual(record, entry, now, activeId, id, staleHours, professionSettings, estimate),
    }
end
