local Estimator = {}
RQ.RestedEstimator = Estimator

function Estimator.Describe(estimate)
    if estimate.amount == nil then
        return "Rested XP: unknown - " .. estimate.reason
    end
    local percentage = estimate.percentageOfLevel and string.format(" | %.1f%% of a level", estimate.percentageOfLevel)
        or ""
    return "Rested XP: "
        .. tostring(estimate.amount)
        .. (estimate.isEstimated and " (estimated offline)" or " (observed live)")
        .. percentage
        .. " ["
        .. estimate.confidence
        .. "]"
end

function Estimator.Profile(settings, entry)
    entry = entry or {}
    return table.concat({
        settings.innRate,
        settings.outsideRate,
        settings.capLevels,
        settings.maxLevel,
        entry.restedMultiplier or 1,
        entry.restedRevision or 0,
    }, ":")
end

function Estimator.EmptyCalibration(settings, entry)
    return { profile = Estimator.Profile(settings, entry), inside = {}, outside = {} }
end

local function complete(snapshot, section, at)
    local state = snapshot.sections and snapshot.sections[section]
    return state and state.complete == true and state.observedAt == at
end

function Estimator.LogoutSample(snapshot, settings, entry)
    local at = snapshot.lastLogout
    if
        not RQ.Util.IsNumber(at)
        or at == 0
        or snapshot.lastSeen ~= at
        or not complete(snapshot, "progression", at)
        or not complete(snapshot, "rested", at)
        or not complete(snapshot, "location", at)
    then
        return nil
    end
    for _, key in ipairs({ "level", "xp", "xpMax", "restedXp" }) do
        if not RQ.Util.IsNumber(snapshot[key]) then
            return nil
        end
    end
    if snapshot.xpMax < 1 or type(snapshot.wasResting) ~= "boolean" then
        return nil
    end
    entry = entry or {}
    return {
        at = at,
        level = snapshot.level,
        xp = snapshot.xp,
        xpMax = snapshot.xpMax,
        restedXp = snapshot.restedXp,
        wasResting = snapshot.wasResting,
        multiplier = entry.restedMultiplier or 1,
        revision = entry.restedRevision or 0,
        profile = Estimator.Profile(settings, entry),
    }
end

function Estimator.Estimate(record, entry, settings, context)
    entry, context = entry or {}, context or {}
    local estimated = context.active ~= true
    local result = {
        isEstimated = estimated,
        confidence = "UNKNOWN",
        calculatedAt = context.now,
        warnings = {},
        source = estimated and "configured" or "observed",
    }
    local function unknown(reason)
        result.reason = reason
        return result
    end
    if not estimated then
        if not RQ.Util.IsNumber(context.restedXp) then
            return unknown("Live rested XP unavailable")
        end
        result.amount = context.restedXp
        result.confidence = "HIGH"
        local maximum = context.xpMax
        if RQ.Util.IsNumber(maximum) and maximum >= 1 and RQ.Util.IsNumber(maximum * settings.capLevels) then
            local percentage = context.restedXp / maximum * 100
            if RQ.Util.IsNumber(percentage) then
                result.percentageOfLevel = percentage
            end
            result.capRatio = math.min(1, context.restedXp / (maximum * settings.capLevels))
        end

        return result
    end
    local state, err = RQ.PlanningConfig.PrepareState(record.restedState)
    if not state then
        return unknown(err)
    end
    local sample = state.logout
    if not sample then
        return unknown("No complete logout observation; log in and out to establish one")
    end
    if not RQ.Util.IsNumber(context.now) or context.now < sample.at then
        return unknown("Offline clock unavailable or reversed")
    end
    if sample.multiplier ~= (entry.restedMultiplier or 1) or sample.revision ~= (entry.restedRevision or 0) then
        return unknown("Rested modifier changed; a new logout observation is required")
    end
    local cap = sample.xpMax * settings.capLevels
    if not RQ.Util.IsNumber(cap) or cap <= 0 then
        return unknown("Invalid XP or rested-cap data")
    end
    local calibration = state.calibration
    local samples = calibration
            and calibration.profile == Estimator.Profile(settings, entry)
            and calibration[sample.wasResting and "inside" or "outside"]
        or {}
    local rate = sample.wasResting and settings.innRate or settings.outsideRate
    result.confidence = "LOW"
    if #samples > 0 then
        rate = 0
        for _, observed in ipairs(samples) do
            rate = rate + observed / #samples
        end
        result.source, result.confidence = "calibrated", "MEDIUM"
    else
        result.warnings[#result.warnings + 1] = "Rested rates and cap are unverified assumptions"
    end
    local hours = (context.now - sample.at) / 3600
    local levels = math.min(settings.capLevels, sample.restedXp / sample.xpMax + hours * rate * sample.multiplier)
    result.amount = math.floor(math.max(0, levels * sample.xpMax))
    result.percentageOfLevel = result.amount / sample.xpMax * 100
    result.capRatio = math.min(1, result.amount / cap)
    result.ratePerHour = rate
    if sample.restedXp > cap then
        result.capRatio = nil
        result.confidence = "LOW"
        result.warnings[#result.warnings + 1] = "Last observation exceeds configured cap; review assumptions"
    end
    if context.staleHours and context.now - sample.at >= context.staleHours * 3600 then
        result.confidence = "LOW"
        result.warnings[#result.warnings + 1] = "Logout observation is stale"
    end
    return result
end

function Estimator.Calibrate(state, snapshot, settings, entry, now)
    local updated = RQ.Util.Copy(state)
    local sample = updated.logout
    local estimate = Estimator.Estimate({ restedState = state }, entry, settings, { now = now })
    updated.logout = nil
    local profile = Estimator.Profile(settings, entry)
    if updated.calibration.profile ~= profile then
        updated.calibration = Estimator.EmptyCalibration(settings, entry)
    end
    local comparison = { at = now, accepted = false, reason = "", estimated = estimate.amount }
    if complete(snapshot, "rested", now) and RQ.Util.IsNumber(snapshot.restedXp) then
        comparison.actual = snapshot.restedXp
        if estimate.amount then
            comparison.error = snapshot.restedXp - estimate.amount
        end
    end
    updated.comparison = comparison
    local function skip(reason)
        comparison.reason = reason
        return updated
    end
    if not sample then
        return skip("No prior complete logout sample")
    end
    if sample.profile ~= profile then
        return skip("Rested assumptions or perk profile changed")
    end
    if not RQ.Util.IsNumber(now) or now - sample.at < RQ.PlanningConfig.minimumCalibrationSeconds then
        return skip("Offline interval shorter than five minutes or clock invalid")
    end
    if not complete(snapshot, "progression", now) or not complete(snapshot, "rested", now) then
        return skip("Login progression or rested observation is incomplete")
    end
    if snapshot.level ~= sample.level or snapshot.xp ~= sample.xp or snapshot.xpMax ~= sample.xpMax then
        return skip("Level, XP, or XP-per-level changed while offline")
    end
    if not RQ.Util.IsNumber(snapshot.restedXp) or snapshot.restedXp <= sample.restedXp then
        return skip("No measurable positive rested gain")
    end
    local cap = sample.xpMax * settings.capLevels
    if sample.level >= settings.maxLevel or snapshot.restedXp >= cap or sample.restedXp >= cap then
        return skip("Level cap or rested cap censors the observed rate")
    end
    local rate = ((snapshot.restedXp - sample.restedXp) / sample.xpMax) / ((now - sample.at) / 3600) / sample.multiplier
    if not RQ.Util.IsNumber(rate) then
        return skip("Invalid observed accumulation rate")
    end
    local samples = updated.calibration[sample.wasResting and "inside" or "outside"]
    samples[#samples + 1] = rate
    if #samples > RQ.PlanningConfig.sampleLimit then
        table.remove(samples, 1)
    end
    comparison.accepted, comparison.observedRate = true, rate
    comparison.reason = "Accepted an uncapped, unchanged-XP offline observation"
    return updated
end
