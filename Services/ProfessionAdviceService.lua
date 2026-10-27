local Service = {}
RQ.ProfessionAdviceService = Service

function Service.Plan(id, additions)
    if not RQ.Database.initialized or not RQDB.characters[id] then
        return false, "Character unavailable."
    end
    if type(additions) ~= "table" then
        return false, "Provide profession IDs to plan."
    end
    local count = 0
    for index in pairs(additions) do
        count = count + 1
        if not RQ.SuppliesConfig.Id(index) or index > #additions then
            return false, "Provide a contiguous list of profession IDs."
        end
    end
    if count ~= #additions then
        return false, "Provide a contiguous list of profession IDs."
    end
    local intent = RQ.Util.Copy(RQDB.characters[id].professionIntent)
    intent.planned = {}
    for _, profession in ipairs(additions) do
        if not RQ.ProfessionConfig.primary[profession] then
            return false, "Use supported primary profession IDs."
        end
        if intent.planned[profession] then
            return false, "Duplicate profession ID."
        end
        intent.planned[profession] = true
    end
    if #additions > 0 then
        local ok, err = RQ.ProfessionAdvisor.ValidatePlan(RQDB, id, intent.planned, RQ.Api.GetServerTime())
        if not ok then
            return false, err
        end
    end
    return RQ.Database.SaveLogistics(id, "professionIntent", intent)
end

function Service.Preference(id, field, value, enabled)
    if not RQ.Database.initialized or not RQDB.characters[id] then
        return false, "Character unavailable."
    end
    local intent = RQ.Util.Copy(RQDB.characters[id].professionIntent)
    if field == "focus" then
        if type(value) ~= "string" then
            return false, "Specify balanced, gathering or self-sufficient."
        end
        intent.focus = value
    elseif field == "preferred" or field == "excluded" then
        if type(enabled) ~= "boolean" then
            return false, "Specify whether the preference is on or off."
        end
        if not RQ.ProfessionConfig.primary[value] then
            return false, "Use a supported primary profession ID."
        end
        intent[field][value] = enabled and true or nil
    else
        return false, "Unknown profession preference."
    end
    return RQ.Database.SaveLogistics(id, "professionIntent", intent)
end

function Service.CycleFocus(id)
    local record = RQ.Database.initialized and RQDB.characters[id]
    if not record then
        return false, "Character unavailable."
    end
    local nextFocus = { balanced = "gathering", gathering = "self-sufficient", ["self-sufficient"] = "balanced" }
    return Service.Preference(id, "focus", nextFocus[record.professionIntent.focus])
end

function Service.Open(query, textOnly)
    local id, err = RQ.Database.ResolveMember(query and query ~= "" and query or RQ.Database.activeId)
    if not id then
        RQ.Api.Print("Profession advice unavailable: " .. err)
        return false
    end
    if not textOnly and RQ.MainWindow then
        RQ.MainWindow.professionCharacterId = id
        if RQ.MainWindow.Open("advice") then
            return true
        end
    end
    local report = RQ.ProfessionAdvisor.Evaluate(RQDB, id, RQ.Api.GetServerTime())
    for _, card in ipairs(RQ.ProfessionPanel.Build(RQDB, report)) do
        RQ.Api.Print(card.title)
        RQ.Api.Print(card.body)
    end
    return true
end

function Service.Command(command, argument)
    local value, remainder = argument:match("^(%S+)%s*(.-)$")
    local enabled, query = nil, remainder
    if command == "profession-prefer" or command == "profession-avoid" then
        local toggle
        toggle, query = (remainder or ""):match("^(%S+)%s*(.-)$")
        if toggle ~= "on" and toggle ~= "off" then
            return false, "Use <profession ID> on|off [member]."
        end
        enabled = toggle == "on"
    end
    local id, err = RQ.Database.ResolveMember(query and query ~= "" and query or RQ.Database.activeId)
    if not id then
        return false, err
    end
    if command == "profession-focus" then
        return Service.Preference(id, "focus", value)
    end
    if command == "profession-prefer" or command == "profession-avoid" then
        return Service.Preference(
            id,
            command == "profession-prefer" and "preferred" or "excluded",
            tonumber(value),
            enabled
        )
    end
    if value == "clear" then
        return Service.Plan(id, {})
    end
    if not value or not (value:match("^%d+$") or value:match("^%d+,%d+$")) then
        return false, "Use /rq profession-plan <ID[,ID]|clear> [member]."
    end
    local additions = {}
    for token in value:gmatch("%d+") do
        additions[#additions + 1] = tonumber(token)
    end
    return Service.Plan(id, additions)
end
