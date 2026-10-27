local Planning = {}
RQ.PlanningService = Planning

function Planning.Evaluate()
    if not RQ.Database.initialized then
        return nil, RQ.Database.status
    end
    local settings, now = RQDB.settings.planning, RQ.Api.GetServerTime()
    local progression = RQ.Api.GetCharacterProgression()
    local live = { restedXp = RQ.Api.GetRestedXP(), xpMax = progression.xpMax }
    local results, err, estimates, warnings = RQ.PriorityEngine.Evaluate(RQDB, RQDB.characters, settings, {
        now = now,
        activeId = RQ.Database.activeId,
        live = live,
    })
    if not results then
        return nil, err
    end
    for id, record in pairs(RQDB.characters) do
        if not estimates[id] then
            if record.registration == "ignored" and id ~= RQ.Database.activeId then
                estimates[id] = {
                    isEstimated = true,
                    confidence = "UNKNOWN",
                    reason = "Character is ignored; tracking is paused",
                    warnings = {},
                }
            else
                estimates[id] = RQ.RestedEstimator.Estimate(record, RQDB.roster[id], settings, {
                    now = now,
                    active = id == RQ.Database.activeId,
                    restedXp = live.restedXp,
                    xpMax = live.xpMax,
                    staleHours = RQDB.policies.staleSnapshotHours,
                })
            end
        end
    end
    return { recommendations = results, estimates = estimates, warnings = warnings, now = now, settings = settings }
end

function Planning.Login(captured)
    RQ.Database.BeginSession()
    local record = RQ.Database.Current()
    local state
    if captured then
        state = RQ.RestedEstimator.Calibrate(
            record.restedState,
            record.snapshot,
            RQDB.settings.planning,
            RQDB.roster[RQ.Database.activeId],
            record.snapshot.lastSeen
        )
    else
        state = RQ.Util.Copy(record.restedState)
        state.logout = nil
    end
    local ok, err = RQ.Database.SaveRestedState(RQ.Database.activeId, state)
    if not ok then
        RQ.Api.Print("Rested calibration not saved: " .. err)
    end
end

function Planning.Logout(snapshot, cached)
    local record = RQ.Database.Current()
    local state = RQ.Util.Copy(record.restedState)
    state.logout, state.logoutReason =
        RQ.RestedEstimator.LogoutSample(snapshot, RQDB.settings.planning, RQDB.roster[RQ.Database.activeId], cached)
    local ok, err = RQ.Database.SaveRestedState(RQ.Database.activeId, state)
    if not ok then
        RQ.Api.Print("Rested logout sample not saved: " .. err)
    end
end

function Planning.TextReport()
    local report, err = Planning.Evaluate()
    if not report then
        RQ.Api.Print("Recommendation unavailable: " .. err)
        return
    end
    if #report.recommendations == 0 then
        RQ.Api.Print("No recommendation: register an enabled member using /rq add.")
    end
    for index, result in ipairs(report.recommendations) do
        local identity = RQDB.characters[result.characterId].identity
        RQ.Api.Print(
            index
                .. ". "
                .. (RQ.Character.DisplayName(identity) or result.characterId)
                .. " ["
                .. result.confidence
                .. "] score "
                .. string.format("%.1f", result.score)
        )
        RQ.Api.Print("  " .. RQ.RestedEstimator.Describe(result.estimate))
        for _, reason in ipairs(result.reasons) do
            RQ.Api.Print("  - " .. reason)
        end
        for _, line in
            ipairs(
                RQ.ProfessionStatus.Lines(
                    RQDB.characters[result.characterId].snapshot,
                    report.now,
                    RQDB.policies.staleSnapshotHours,
                    RQDB.settings.professionLag
                )
            )
        do
            RQ.Api.Print("  " .. line)
        end
    end
    for _, warning in ipairs(report.warnings) do
        RQ.Api.Print(warning)
    end
end
