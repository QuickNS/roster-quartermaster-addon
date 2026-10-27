local Panel = {}
RQ.TodayPanel = Panel

function Panel.Build(account, report, rosterCards, activeId, supplies)
    local cards = {}
    local text = RQ.CharacterCard.Text
    local byId = {}
    for _, card in ipairs(rosterCards or {}) do
        if card.id then
            byId[card.id] = card
        end
    end
    for index, recommendation in ipairs(report.recommendations) do
        local id = recommendation.characterId
        local record = account.characters[id]
        local base = byId[id]
            or RQ.CharacterCard.Build(
                id,
                record,
                account.roster[id],
                report.now,
                activeId,
                account.policies.staleSnapshotHours,
                recommendation.estimate,
                account.settings.professionLag
            )
        local visual = RQ.Util.Copy(base.visual)
        visual.rank = index
        visual.reason = text(recommendation.reasons[1])
        visual.priorityConfidence = text(recommendation.confidence)
        visual.rested = RQ.CharacterCard.RestedVisual(recommendation.estimate)
        local lines = {
            RQ.CharacterCard.Rested(recommendation.estimate),
            "Confidence: " .. recommendation.confidence .. " | Score: " .. string.format("%.1f", recommendation.score),
        }
        for _, reason in ipairs(recommendation.reasons) do
            lines[#lines + 1] = "- " .. text(reason)
        end
        for _, line in
            ipairs(
                RQ.ProfessionStatus.Lines(
                    record.snapshot,
                    report.now,
                    account.policies.staleSnapshotHours,
                    account.settings.professionLag
                )
            )
        do
            lines[#lines + 1] = text(line)
        end
        local comparison = record.restedState.comparison
        if supplies then
            for _, line in ipairs(RQ.SuppliesService.WithdrawalLines(account, supplies, id)) do
                lines[#lines + 1] = text(line)
            end
        end
        if comparison then
            lines[#lines + 1] = "Last login calibration: " .. text(comparison.reason)
            if comparison.actual and comparison.estimated then
                lines[#lines + 1] = "Predicted "
                    .. text(comparison.estimated)
                    .. " XP; observed "
                    .. text(comparison.actual)
            end
        end
        cards[#cards + 1] = {
            id = id,
            actionKind = "configure",
            action = "Configure",
            title = (index == 1 and "Play next: " or index .. ". ")
                .. text(RQ.Character.DisplayName(record.identity))
                .. " - "
                .. text(record.identity.realm),
            body = table.concat(lines, "\n"),
            detail = table.concat(lines, "\n") .. "\n\n" .. base.body,
            visual = visual,
        }
    end
    if #cards == 0 then
        cards[1] = {
            title = "No enabled roster members",
            action = "Configure roster",
            body = "Add characters in Manage roster, or use /rq add.",
        }
    end
    if #report.warnings > 0 then
        cards[1].body = cards[1].body .. "\n" .. table.concat(report.warnings, "\n")
    end
    return cards
end
