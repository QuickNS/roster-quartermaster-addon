local Engine = {}
RQ.PriorityEngine = Engine

local function nextMilestone(value, milestones, distance)
    if not RQ.Util.IsNumber(value) then
        return nil
    end
    for _, milestone in ipairs(milestones) do
        if milestone > value and milestone - value <= distance then
            return milestone
        end
    end
end

local function sectionFresh(snapshot, name, now, hours)
    local section = snapshot.sections and snapshot.sections[name]
    return section
        and section.complete
        and RQ.Util.IsNumber(section.observedAt)
        and section.observedAt > 0
        and RQ.Util.IsNumber(now)
        and now >= section.observedAt
        and now - section.observedAt < hours * 3600
end

function Engine.Evaluate(account, records, settings, context)
    local validated, err = RQ.PlanningConfig.Prepare(settings)
    if not validated then
        return nil, err
    end
    settings, context = validated, context or {}
    local candidates, mainIds, warnings = {}, {}, {}
    local lowest, unknownLevel, uncertainRoster = math.huge, false, false
    for _, id in ipairs(RQ.Util.Keys(account.roster)) do
        local entry, record = account.roster[id], records[id]
        if entry.enabled == true and record and record.registration == "member" then
            local snapshot = record.snapshot or {}
            local level = snapshot.level
            if not RQ.Util.IsNumber(level) then
                level, unknownLevel = nil, true
            end
            if level then
                lowest = math.min(lowest, level)
            end
            uncertainRoster = uncertainRoster
                or not sectionFresh(snapshot, "progression", context.now, account.policies.staleSnapshotHours)
            candidates[#candidates + 1] =
                { id = id, entry = entry, record = record, level = level, snapshot = snapshot }
            if entry.isMain then
                mainIds[#mainIds + 1] = id
            end
        end
    end
    local mainId = #mainIds == 1 and mainIds[1] or nil
    local mainLevel = mainId and records[mainId].snapshot and records[mainId].snapshot.level
    if not RQ.Util.IsNumber(mainLevel) then
        mainLevel = nil
    end
    if #mainIds == 0 then
        warnings[#warnings + 1] = "No main configured; main-lead rule is inactive"
    end
    if #mainIds > 1 then
        warnings[#warnings + 1] = "Multiple mains configured; choose one before using the lead rule"
    end
    local leadActive = #candidates > 1
        and not unknownLevel
        and lowest >= settings.leadStartLevel
        and mainLevel
        and mainLevel < settings.maxLevel
    local highestAlt = 0
    for _, candidate in ipairs(candidates) do
        if candidate.id ~= mainId and candidate.level then
            highestAlt = math.max(highestAlt, candidate.level)
        end
    end
    local needsLead = leadActive and mainLevel < math.min(settings.maxLevel, highestAlt + settings.mainLeadLevels)
    local results, estimates, pinFound = {}, {}, false
    for _, candidate in ipairs(candidates) do
        local id, entry, record, level = candidate.id, candidate.entry, candidate.record, candidate.level
        local live = context.live or {}
        local estimate = RQ.RestedEstimator.Estimate(record, entry, settings, {
            now = context.now,
            active = id == context.activeId,
            restedXp = live.restedXp,
            xpMax = live.xpMax,
            staleHours = account.policies.staleSnapshotHours,
        })
        estimates[id] = estimate
        local score, factors = 0, {}
        local function add(amount, reason)
            score = score + amount
            factors[#factors + 1] = { amount = amount, reason = reason, order = #factors + 1 }
        end
        local pinned = settings.pinnedCharacterId == id
        pinFound = pinFound or pinned
        local capEligible = level and level < settings.maxLevel
        local nearCap = capEligible and estimate.capRatio and estimate.capRatio >= settings.nearCapRatio
        local lead = needsLead and id == mainId
        local blocker = entry.resourceBlocker == true
        local tier = pinned and 5 or nearCap and 4 or lead and 3 or blocker and 2 or 0
        local firstReason
        if pinned then
            add(settings.weights.pinned, "Manually pinned; this overrides automatic rotation")
            firstReason = factors[#factors].reason
        end
        if capEligible and estimate.capRatio then
            local source = estimate.isEstimated and "Estimated" or "Observed"
            local description = nearCap and " rested XP is near the configured cap" or " rested XP is available"
            add(settings.weights.rested * estimate.capRatio, source .. description)
            if nearCap and not firstReason then
                firstReason = factors[#factors].reason
            end
        end
        if lead then
            add(settings.weights.mainLead, "Main is below the configured " .. settings.mainLeadLevels .. "-level lead")
            if not firstReason then
                firstReason = factors[#factors].reason
            end
        end
        if blocker then
            add(settings.weights.blocker, "Manually marked as needed for a roster resource or profession blocker")
            if not firstReason then
                firstReason = factors[#factors].reason
            end
        end
        if level and mainLevel and id ~= mainId and mainLevel - level > settings.maxAltLag then
            add(
                settings.weights.altLag * math.min(1, (mainLevel - level - settings.maxAltLag) / settings.maxAltLag),
                "Character is " .. (mainLevel - level) .. " levels behind the main"
            )
        end
        local milestone = nextMilestone(level, settings.levelMilestones, 2)
        if milestone and level < settings.maxLevel then
            add(settings.weights.levelMilestone, "Within two levels of the level-" .. milestone .. " milestone")
        end
        if entry.dungeonReady then
            add(settings.weights.dungeon, "Manually marked as ready for a dungeon quest bundle")
        end
        if sectionFresh(candidate.snapshot, "professions", context.now, account.policies.staleSnapshotHours) then
            for _, profession in pairs(candidate.snapshot.professions or {}) do
                if nextMilestone(profession.skill, settings.professionMilestones, 10) then
                    add(settings.weights.professionMilestone, "A profession is within ten points of its next milestone")
                    break
                end
            end
        end
        if account.session and account.session.previousCharacterId == id then
            add(settings.weights.lastSession, "Played in the previous character session")
        end
        local freshness = RQ.Snapshot.Freshness(candidate.snapshot, context.now, account.policies.staleSnapshotHours)
        local uncertain = freshness ~= "RECENT"
            or not level
            or not sectionFresh(candidate.snapshot, "progression", context.now, account.policies.staleSnapshotHours)
            or (uncertainRoster and (lead or (mainLevel and level and mainLevel - level > settings.maxAltLag)))
        if uncertain then
            add(settings.weights.stale, "Snapshot is stale, incomplete, or has an uncertain timestamp")
        end
        local warning
        if uncertain then
            warning = "Low confidence: ranking uses stale, incomplete, or uncertain level observations"
        elseif estimate.confidence == "UNKNOWN" then
            warning = "Rested XP unavailable: " .. estimate.reason
        elseif estimate.confidence == "LOW" then
            warning = "Low confidence: " .. table.concat(estimate.warnings, "; ")
        end
        table.sort(factors, function(a, b)
            if a.amount ~= b.amount then
                return a.amount > b.amount
            end
            return a.order < b.order
        end)
        local reasons, seen = {}, {}
        local function reason(text)
            if text and not seen[text] then
                reasons[#reasons + 1], seen[text] = text, true
            end
        end
        reason(firstReason)
        for _, factor in ipairs(factors) do
            if #reasons >= (warning and 2 or 3) then
                break
            end
            if factor.amount > 0 then
                reason(factor.reason)
            end
        end
        if #reasons == 0 then
            reason(
                level and level >= settings.maxLevel and "At the configured level cap; focus on non-XP objectives"
                    or "Available roster member; no stronger priority signal"
            )
        end
        reason(warning)
        if #reasons < 2 then
            reason("Ties use a stable character-ID order; no random rotation")
        end
        results[#results + 1] = {
            characterId = id,
            score = score,
            priorityTier = tier,
            reasons = reasons,
            confidence = (uncertain or estimate.confidence == "UNKNOWN") and "LOW" or estimate.confidence,
            estimate = estimate,
        }
    end
    if settings.pinnedCharacterId and not pinFound then
        warnings[#warnings + 1] = "Pinned character is not an enabled member; select a new pin"
    end
    table.sort(results, function(a, b)
        if a.priorityTier ~= b.priorityTier then
            return a.priorityTier > b.priorityTier
        end
        if a.score ~= b.score then
            return a.score > b.score
        end
        return a.characterId < b.characterId
    end)
    return results, nil, estimates, warnings
end
