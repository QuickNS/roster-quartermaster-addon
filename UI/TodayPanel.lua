local Panel = {}
RQ.TodayPanel = Panel

function Panel.Build(account, report)
    local cards = {}
    local text = RQ.CharacterCard.Text
    for index, recommendation in ipairs(report.recommendations) do
        local id = recommendation.characterId
        local record = account.characters[id]
        local pinned = account.settings.planning.pinnedCharacterId == id
        local lines = {
            RQ.CharacterCard.Rested(recommendation.estimate),
            "Confidence: " .. recommendation.confidence .. " | Score: " .. string.format("%.1f", recommendation.score),
        }
        for _, reason in ipairs(recommendation.reasons) do
            lines[#lines + 1] = "- " .. text(reason)
        end
        local comparison = record.restedState.comparison
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
            actionKind = "pin",
            action = pinned and "Unpin" or "Pin next",
            title = (index == 1 and "Play next: " or index .. ". ")
                .. text(record.identity.displayName)
                .. " - "
                .. text(record.identity.realm)
                .. (pinned and " [PINNED]" or ""),
            body = table.concat(lines, "\n"),
        }
    end
    if #cards == 0 then
        cards[1] = {
            title = "No enabled roster members",
            action = "Configure roster",
            body = "Add or link characters in Settings, or use /rq add and /rq link <slot>.",
        }
    end
    if #report.warnings > 0 then
        cards[1].body = cards[1].body .. "\n" .. table.concat(report.warnings, "\n")
    end
    return cards
end
