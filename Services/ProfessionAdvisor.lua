local Advisor = {}
RQ.ProfessionAdvisor = Advisor

local function member(account, id)
    local record, entry = account.characters[id], account.roster[id]
    return record and record.registration == "member" and entry and entry.enabled
end

local function learned(record, now, hours)
    local result, valid = {}, RQ.Snapshot.SectionState(record.snapshot, "professions", now, hours) == "RECENT"
    if type(record.snapshot.professions) ~= "table" then
        valid = false
    end
    for id, profession in pairs(record.snapshot.professions or {}) do
        local kind = RQ.ProfessionConfig.Kind(id, profession)
        if kind == "primary" or RQ.ProfessionConfig.primary[id] then
            result[id] = true
            if
                kind ~= "primary"
                or not RQ.ProfessionRelationships.professions[id]
                or not RQ.Util.IsNumber(profession.skill)
                or not RQ.Util.IsNumber(profession.maxSkill)
                or profession.maxSkill <= 0
                or profession.skill > profession.maxSkill
            then
                valid = false
            end
        elseif kind ~= "secondary" then
            valid = false
        end
    end
    return result, valid and #RQ.Util.Keys(result) <= 2
end

function Advisor.Coverage(account, identity, now)
    local coverage = { professions = {}, members = 0, uncertain = 0, demand = {}, recipeOutputs = {} }
    for id in pairs(RQ.ProfessionRelationships.professions) do
        coverage.professions[id] = { owners = {}, uncertainOwners = {} }
    end
    for _, id in ipairs(RQ.Util.Keys(account.roster)) do
        local record = account.characters[id]
        if member(account, id) and RQ.Character.CanTrade(identity, record.identity) then
            coverage.members = coverage.members + 1
            local known, valid = learned(record, now, account.policies.staleSnapshotHours)
            if not valid then
                coverage.uncertain = coverage.uncertain + 1
            end
            for profession in pairs(known) do
                local entry = coverage.professions[profession]
                if entry then
                    local owners = valid and entry.owners or entry.uncertainOwners
                    owners[#owners + 1] = id
                end
            end
            local needs = RQ.SuppliesService.Grocery(record, now, account.policies.staleSnapshotHours)
            for item, need in pairs(needs) do
                if
                    need.missing
                    and need.missing > 0
                    and RQ.SuppliesConfig.IsFresh(record.inventory.bags, now, account.policies.staleSnapshotHours)
                then
                    coverage.demand[item] = true
                end
            end
            for profession, scan in pairs(record.recipes.professions or {}) do
                if
                    known[profession]
                    and valid
                    and RQ.SuppliesConfig.IsFresh(scan, now, account.policies.staleSnapshotHours)
                then
                    for _, recipe in pairs(scan.recipes) do
                        if recipe.learned and recipe.outputItemId then
                            coverage.recipeOutputs[profession] = coverage.recipeOutputs[profession] or {}
                            coverage.recipeOutputs[profession][recipe.outputItemId] = true
                        end
                    end
                end
            end
        end
    end
    return coverage
end

local function score(record, entry, intent, additions, existing, coverage)
    local choice =
        { additions = additions, professions = RQ.Util.Copy(existing), score = 0, factors = {}, tradeoffs = {} }
    local function factor(points, reason)
        choice.score = choice.score + points
        choice.factors[#choice.factors + 1] = { points = points, reason = reason }
    end
    for _, id in ipairs(additions) do
        choice.professions[id] = true
        local data, owners = RQ.ProfessionRelationships.professions[id], coverage.professions[id].owners
        if #owners == 0 then
            factor(
                coverage.uncertain > 0 and 3 or 10,
                data.name
                    .. (
                        coverage.uncertain > 0 and ": not observed; roster coverage is uncertain"
                        or ": fills a coverage gap"
                    )
            )
        else
            factor(data.gathering and -1 or -4, data.name .. ": duplicate coverage")
            choice.tradeoffs[#choice.tradeoffs + 1] = data.name
                .. (
                    data.gathering
                        and ": another gatherer can still supply the roster while playing this character."
                    or ": existing crafters may already provide this service."
                )
        end
        if not data.gathering then
            factor(2, data.name .. ": " .. data.utility)
        end
        if data.classes and data.classes[record.identity.class] then
            factor(
                3,
                data.name .. ": soft class/gear fit (reference only; actual recipes and equip eligibility unverified)"
            )
        end
        if id == 171 and (entry.role == "HEALER" or entry.role == "HEALER_DPS") then
            factor(2, "Alchemy: soft consumable preference for the configured healer role")
        end
        if intent.preferred[id] then
            factor(30, data.name .. ": explicit user preference")
        end
        if intent.focus == "gathering" and data.gathering then
            factor(18, data.name .. ": gathering focus")
        end
        local matches = {}
        for item in pairs(coverage.recipeOutputs[id] or {}) do
            if coverage.demand[item] then
                matches[#matches + 1] = item
            end
        end
        table.sort(matches)
        if #matches > 0 then
            factor(7, data.name .. ": observed roster recipe output matches demand for item " .. matches[1])
            choice.tradeoffs[#choice.tradeoffs + 1] =
                "Recipe demand is evidence of utility, not proof you know that recipe."
        end
    end
    for _, link in ipairs(RQ.ProfessionRelationships.links) do
        local newSource, newTarget = false, false
        for _, id in ipairs(additions) do
            newSource, newTarget = newSource or id == link.source, newTarget or id == link.target
        end
        if (newSource or newTarget) and choice.professions[link.source] and choice.professions[link.target] then
            factor(intent.focus == "self-sufficient" and 16 or 6, link.label .. " on this character (reference)")
        elseif newSource and #coverage.professions[link.target].owners > 0 then
            factor(5, link.label .. " for an observed roster crafter (manual transfer required)")
        elseif newTarget and #coverage.professions[link.source].owners > 0 then
            factor(4, link.label .. " from an observed roster supplier (manual transfer required)")
        end
    end
    choice.tradeoffs[#choice.tradeoffs + 1] =
        "Training, materials and gathering take time; no gold/profit or globally optimal assignment is claimed."
    return choice
end

function Advisor.ValidatePlan(account, id, planned, now)
    if not member(account, id) then
        return false, "Choose an enabled, registered roster member."
    end
    local record = account.characters[id]
    local existing, valid = learned(record, now, account.policies.staleSnapshotHours)
    if not valid then
        return false, "Rescan professions before planning new choices."
    end
    local combined, added = RQ.Util.Copy(existing), 0
    for profession in pairs(planned) do
        if not RQ.ProfessionRelationships.professions[profession] or record.professionIntent.excluded[profession] then
            return false, "Unsupported or excluded profession."
        end
        if not existing[profession] then
            added = added + 1
        end
        combined[profession] = true
    end
    if added == 0 or #RQ.Util.Keys(combined) > 2 then
        return false, "Plan only additions fitting confirmed free slots; learned professions stay locked."
    end
    return true
end

function Advisor.Evaluate(account, id, now)
    local record = account.characters[id]
    local result = {
        id = id,
        choices = {},
        evidence = RQ.ProfessionRelationships.evidence,
        version = RQ.ProfessionRelationships.version,
    }
    if not member(account, id) then
        result.blocker = "Choose an enabled, registered roster member."
        return result
    end
    result.coverage = Advisor.Coverage(account, record.identity, now)
    result.intent = RQ.Util.Copy(record.professionIntent)
    result.learned, result.valid = learned(record, now, account.policies.staleSnapshotHours)
    if not RQ.Character.Realm(record.identity) then
        result.blocker = "Realm unknown; compatible roster coverage cannot be established."
    elseif not RQ.Character.TradeGroup(record.identity) then
        result.blocker = "Ruleset or faction unknown; visit and rescan, then confirm ruleset in Manage roster."
    elseif not result.valid then
        result.blocker = "Rescan professions: stale, incomplete or unsupported data cannot prove free primary slots."
    else
        result.freeSlots = 2 - #RQ.Util.Keys(result.learned)
        if result.freeSlots == 0 then
            result.blocker = "Both primary slots are learned and locked; no replacements suggested."
        end
    end
    if result.blocker then
        return result
    end
    local eligible = {}
    for _, profession in ipairs(RQ.Util.Keys(RQ.ProfessionRelationships.professions)) do
        if not result.learned[profession] and not result.intent.excluded[profession] then
            eligible[#eligible + 1] = profession
        end
    end
    local function offer(additions)
        local selected = RQ.Util.Copy(result.learned)
        for _, profession in ipairs(additions) do
            selected[profession] = true
        end
        for profession in pairs(result.intent.planned) do
            if not selected[profession] then
                return
            end
        end
        result.choices[#result.choices + 1] =
            score(record, account.roster[id], result.intent, additions, result.learned, result.coverage)
    end
    for index, profession in ipairs(eligible) do
        if result.freeSlots == 1 then
            offer({ profession })
        else
            for other = index + 1, #eligible do
                offer({ profession, eligible[other] })
            end
        end
    end
    table.sort(result.choices, function(a, b)
        if a.score ~= b.score then
            return a.score > b.score
        end
        for index, profession in ipairs(a.additions) do
            if profession ~= b.additions[index] then
                return profession < b.additions[index]
            end
        end
        return false
    end)
    result.candidateCount = #result.choices
    while #result.choices > 3 do
        table.remove(result.choices)
    end
    if #result.choices == 0 then
        result.blocker = "Planned/excluded choices conflict with free slots; clear or revise intent."
    end
    return result
end
