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
    return RQ.Snapshot.SectionState(snapshot, name, now, hours) == "RECENT"
end

function Engine.Evaluate(account, records, settings, context)
    local validated, err = RQ.PlanningConfig.Prepare(settings)
    if not validated then
        return nil, err
    end
    settings, context = validated, context or {}
    local candidates, warnings = {}, {}
    for _, id in ipairs(RQ.Util.Keys(account.roster)) do
        local entry, record = account.roster[id], records[id]
        if entry.enabled and record and record.registration == "member" then
            local snapshot = record.snapshot or {}
            candidates[#candidates + 1] = {
                id = id,
                entry = entry,
                record = record,
                snapshot = snapshot,
                level = RQ.Util.IsNumber(snapshot.level) and snapshot.level or nil,
            }
        end
    end
    local results, estimates = {}, {}
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
        local capEligible = level and level < settings.maxLevel
        local nearCap = capEligible and estimate.capRatio and estimate.capRatio >= settings.nearCapRatio
        local blocker = entry.resourceBlocker == true
        local tier = nearCap and 4 or blocker and 2 or 0
        local firstReason
        if capEligible and estimate.capRatio then
            local source = estimate.isEstimated and "Estimated" or "Observed"
            local description = nearCap and " rested XP is near the configured cap" or " rested XP is available"
            add(settings.weights.rested * estimate.capRatio, source .. description)
            if nearCap then
                firstReason = factors[#factors].reason
            end
        end
        if blocker then
            add(settings.weights.blocker, "Manually marked as needed for a roster resource or profession blocker")
            if not firstReason then
                firstReason = factors[#factors].reason
            end
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
        local professionSettings = account.settings and account.settings.professionLag
        if professionSettings and professionSettings.rankingEnabled then
            local status = RQ.ProfessionStatus.Evaluate(
                candidate.snapshot,
                context.now,
                account.policies.staleSnapshotHours,
                professionSettings
            )
            local deficit = 0
            for _, profession in ipairs(status.professions) do
                if profession.kind == "primary" and profession.state == "BEHIND" and profession.benchmark > 0 then
                    deficit = math.max(deficit, profession.deficit / profession.benchmark)
                end
            end
            if deficit > 0 then
                add(
                    professionSettings.rankingWeight * deficit,
                    "Opt-in profession lag contribution against the configured 5 x level benchmark"
                )
            end
        end
        local freshness = RQ.Snapshot.Freshness(candidate.snapshot, context.now, account.policies.staleSnapshotHours)
        local uncertain = freshness ~= "RECENT"
            or not level
            or not sectionFresh(candidate.snapshot, "progression", context.now, account.policies.staleSnapshotHours)
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
            reason(
                "Lowest level first; Main wins equal-level ties within its realm/faction."
                    .. " Other ties use signals then character ID"
            )
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
    table.sort(results, function(a, b)
        local first, second = records[a.characterId], records[b.characterId]
        local leftGroup = RQ.Character.RosterGroupKey(first.identity)
        local rightGroup = RQ.Character.RosterGroupKey(second.identity)
        if leftGroup ~= rightGroup then
            return leftGroup < rightGroup
        end
        local leftLevel = first.snapshot and first.snapshot.level or math.huge
        local rightLevel = second.snapshot and second.snapshot.level or math.huge
        if leftLevel ~= rightLevel then
            return leftLevel < rightLevel
        end
        local leftMain, rightMain =
            account.roster[a.characterId].isMain == true, account.roster[b.characterId].isMain == true
        if leftMain ~= rightMain then
            return leftMain
        end
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
