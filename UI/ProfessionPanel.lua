local Panel = {}
RQ.ProfessionPanel = Panel

local function names(ids)
    local result = {}
    for _, id in ipairs(RQ.Util.Keys(ids)) do
        local data = RQ.ProfessionRelationships.professions[id]
        result[#result + 1] = (data and data.name or "Unknown profession") .. " [" .. id .. "]"
    end
    return #result > 0 and table.concat(result, " + ") or "None"
end

function Panel.Build(account, report)
    local record, text = account.characters[report.id], RQ.CharacterCard.Text
    local cards = {
        {
            id = report.id,
            title = "Profession advice: " .. text(record and RQ.Character.DisplayName(record.identity)),
            body = "Reference model v"
                .. report.version
                .. ": "
                .. report.evidence
                .. "\nDeterministic local advice, not a global roster optimum. "
                .. "Learned professions never change automatically."
                .. "\nEnabled members with the same known ruleset, faction and realm only."
                .. "\nFocus: "
                .. (report.intent and report.intent.focus or "unavailable")
                .. "\nLearned (snapshot): "
                .. names(report.learned or {})
                .. "\nPreferred: "
                .. names(report.intent and report.intent.preferred or {})
                .. " | Avoid new choices: "
                .. names(report.intent and report.intent.excluded or {})
                .. "\n/rq profession-prefer <ID> on|off [member]; /rq profession-avoid <ID> on|off [member]"
                .. "\n/rq profession-focus balanced|gathering|self-sufficient [member]",
            action = "Cycle focus",
            actionKind = "profession-focus",
            disabled = report.intent == nil,
        },
    }
    if report.coverage then
        local lines = {
            "Coverage: "
                .. report.coverage.members
                .. " member(s); "
                .. report.coverage.uncertain
                .. " uncertain profession snapshot(s). Planned choices are not coverage.",
        }
        for _, id in ipairs(RQ.Util.Keys(report.coverage.professions)) do
            local entry, owners = report.coverage.professions[id], {}
            for _, owner in ipairs(entry.owners) do
                owners[#owners + 1] = text(RQ.Character.DisplayName(account.characters[owner].identity))
                    .. " ["
                    .. owner
                    .. "]"
            end
            local state = #owners > 0 and table.concat(owners, ", ")
                or report.coverage.uncertain > 0 and "Not observed; coverage uncertain"
                or "No observed provider"
            lines[#lines + 1] = names({ [id] = true })
                .. ": "
                .. state
                .. (#entry.uncertainOwners > 0 and ("; cached/unconfirmed providers: " .. #entry.uncertainOwners) or "")
        end
        lines[#lines + 1] = "Sources: https://warcraft.wiki.gg/wiki/Profession and linked profession articles."
        cards[#cards + 1] = {
            title = "Same-realm profession coverage",
            body = table.concat(lines, "\n"),
            action = "Reference only",
            disabled = true,
        }
    end
    cards[#cards + 1] = {
        id = report.id,
        title = "Planned intent (not learned)",
        body = names(report.intent and report.intent.planned or {})
            .. "\nLearn manually from a suitable profession trainer, then rescan. Trainer locations, ranks and fees "
            .. "are not yet verified; no travel route is invented."
            .. "\n/rq profession-plan <ID[,ID]|clear> [member]",
        action = "Clear intent",
        actionKind = "profession-clear",
        disabled = not report.intent or not next(report.intent.planned),
    }
    if report.blocker then
        cards[#cards + 1] = {
            title = "No new profession recommendation",
            body = report.blocker,
            action = "Rescan current",
            actionKind = "bag-refresh",
        }
    end
    for index, choice in ipairs(report.choices) do
        local additions = {}
        for _, id in ipairs(choice.additions) do
            additions[id] = true
        end
        local lines = { "Add: " .. names(additions) .. "\nScore: " .. choice.score .. " (advisory weights)" }
        for _, factor in ipairs(choice.factors) do
            lines[#lines + 1] = string.format("%+d", factor.points) .. " | " .. factor.reason
        end
        for _, tradeoff in ipairs(choice.tradeoffs) do
            lines[#lines + 1] = "Trade-off: " .. tradeoff
        end
        cards[#cards + 1] = {
            id = report.id,
            title = "Choice " .. index .. ": " .. names(choice.professions),
            body = table.concat(lines, "\n"),
            action = "Plan professions",
            actionKind = "profession-plan",
            professionChoices = RQ.Util.Copy(choice.additions),
        }
    end
    return cards
end
