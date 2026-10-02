local Api = {}
RQ.Api = Api

local capabilities = {}

local function lookup(name)
    local value = _G
    for part in name:gmatch("[^.]+") do
        if type(value) ~= "table" then
            return nil
        end
        value = value[part]
    end
    return value
end

local function call(name, ...)
    local fn = lookup(name)
    if type(fn) ~= "function" then
        capabilities[name] = "missing"
        return nil
    end

    local result = { pcall(fn, ...) }
    if not result[1] then
        capabilities[name] = "error: " .. tostring(result[2]):sub(1, 160)
        return nil
    end
    if type(_G.issecretvalue) == "function" then
        for index, value in pairs(result) do
            if index ~= 1 then
                local ok, secret = pcall(_G.issecretvalue, value)
                if not ok or secret then
                    capabilities[name] = "restricted value"
                    return nil
                end
            end
        end
    end
    capabilities[name] = "available"
    return result
end

local function scalar(name, expectedType, ...)
    local result = call(name, ...)
    if not result then
        return nil
    end
    local value = result[2]
    if type(value) ~= expectedType then
        capabilities[name] = "unexpected return type"
        return nil
    end
    if expectedType == "number" and (value ~= value or value < 0 or value == math.huge) then
        capabilities[name] = "invalid numeric value"
        return nil
    end
    return value
end

function Api.GetBuildInfo()
    local result = call("GetBuildInfo")
    if not result then
        return {}
    end
    if type(result[2]) ~= "string" or type(result[5]) ~= "number" then
        capabilities.GetBuildInfo = "unexpected return type"
        return {}
    end
    return {
        version = result[2],
        build = result[3],
        date = result[4],
        interface = result[5],
    }
end

function Api.GetClientProject()
    local value = _G.WOW_PROJECT_ID
    if type(_G.issecretvalue) == "function" then
        local ok, secret = pcall(_G.issecretvalue, value)
        if not ok or secret then
            capabilities.WOW_PROJECT_ID = "restricted value"
            return nil
        end
    end
    if type(value) ~= "number" then
        capabilities.WOW_PROJECT_ID = "missing or unexpected type"
        return nil
    end
    capabilities.WOW_PROJECT_ID = "available"
    return value
end

function Api.GetCharacterIdentity()
    local function identityText(name, ...)
        local value = scalar(name, "string", ...)
        if value ~= nil and not RQ.Util.IsText(value) then
            capabilities[name] = "empty identity value"
            return nil
        end
        return value
    end
    local identity = {
        guid = identityText("UnitGUID", "player"),
        displayName = identityText("UnitName", "player"),
        realm = identityText("GetRealmName"),
    }
    local class = call("UnitClass", "player")
    if class and RQ.Util.IsText(class[3]) then
        identity.class = class[3]
    elseif class then
        capabilities.UnitClass = "unexpected return type"
    end
    local race = call("UnitRace", "player")
    if race and RQ.Util.IsText(race[2]) then
        identity.race = race[2]
    elseif race then
        capabilities.UnitRace = "unexpected return type"
    end
    return identity
end

function Api.GetCharacterProgression()
    return {
        level = scalar("UnitLevel", "number", "player"),
        xp = scalar("UnitXP", "number", "player"),
        xpMax = scalar("UnitXPMax", "number", "player"),
    }
end

function Api.GetRestedXP()
    local result = call("GetXPExhaustion")
    if not result then
        return nil
    end
    -- The candidate WoW API uses nil for no rested XP, not for a missing API.
    if result[2] == nil then
        return 0
    end
    local value = result[2]
    if type(value) ~= "number" or value ~= value or value < 0 or value == math.huge then
        capabilities.GetXPExhaustion = "invalid numeric value"
        return nil
    end
    return value
end

function Api.IsResting()
    return scalar("IsResting", "boolean")
end

function Api.GetServerTime()
    return scalar("GetServerTime", "number")
end

function Api.GetMoney()
    return scalar("GetMoney", "number")
end

function Api.GetLocation()
    return {
        zone = scalar("GetZoneText", "string"),
        subZone = scalar("GetSubZoneText", "string"),
    }
end

function Api.GetBagCapacity()
    local constant = _G.NUM_TOTAL_EQUIPPED_BAG_SLOTS ~= nil and "NUM_TOTAL_EQUIPPED_BAG_SLOTS" or "NUM_BAG_SLOTS"
    local count = _G[constant]
    if type(_G.issecretvalue) == "function" then
        local ok, secret = pcall(_G.issecretvalue, count)
        if not ok or secret then
            capabilities[constant] = "restricted value"
            return nil
        end
    end
    if not RQ.Util.IsNumber(count) or count > 20 or count % 1 ~= 0 then
        capabilities[constant] = "missing or invalid bag count"
        return nil
    end
    capabilities[constant] = "available"
    local slotsApi = type(lookup("C_Container.GetContainerNumSlots")) == "function"
            and "C_Container.GetContainerNumSlots"
        or "GetContainerNumSlots"
    local freeApi = type(lookup("C_Container.GetContainerNumFreeSlots")) == "function"
            and "C_Container.GetContainerNumFreeSlots"
        or "GetContainerNumFreeSlots"
    local capacity = { bagSlots = 0, freeBagSlots = 0 }
    for bag = 0, count do
        local slots = scalar(slotsApi, "number", bag)
        if slots == nil then
            return nil
        end
        local free = slots == 0 and 0 or scalar(freeApi, "number", bag)
        if free == nil then
            return nil
        end
        if free > slots or free % 1 ~= 0 or slots % 1 ~= 0 then
            capabilities[freeApi] = "invalid bag capacity"
            return nil
        end
        capacity.bagSlots = capacity.bagSlots + slots
        capacity.freeBagSlots = capacity.freeBagSlots + free
    end
    return capacity
end

function Api.GetProfessions()
    local indices = call("GetProfessions")
    if not indices then
        return nil
    end
    local professions = {}
    -- GetProfessions may contain nil holes between its six profession slots.
    for slot = 2, 7 do
        local index = indices[slot]
        if index ~= nil then
            if not RQ.Util.IsNumber(index) or index % 1 ~= 0 then
                capabilities.GetProfessions = "invalid profession index"
                return nil
            end
            local info = call("GetProfessionInfo", index)
            if not info then
                return nil
            end
            local id, name, skill, maxSkill = info[8], info[2], info[4], info[5]
            if
                not RQ.Util.IsNumber(id)
                or id == 0
                or id % 1 ~= 0
                or not RQ.Util.IsText(name)
                or not RQ.Util.IsNumber(skill)
                or not RQ.Util.IsNumber(maxSkill)
                or skill > maxSkill
            then
                capabilities.GetProfessionInfo = "invalid profession data or missing skill-line ID"
                return nil
            end
            professions[id] = { name = name, skill = skill, maxSkill = maxSkill }
        end
    end
    return professions
end

function Api.After(seconds, callback)
    return call("C_Timer.After", seconds, callback) ~= nil
end

function Api.IsInCombat()
    return scalar("InCombatLockdown", "boolean")
end

local registrationFrame

function Api.HideRegistrationPrompt()
    if registrationFrame then
        registrationFrame:Hide()
    end
end

function Api.ShowRegistrationPrompt(title, choices)
    if Api.IsInCombat() ~= false then
        return false
    end
    local ok, err = pcall(function()
        if not registrationFrame then
            local created = call("CreateFrame", "Frame", nil, _G.UIParent)
            if not created or not created[2] then
                error("CreateFrame unavailable")
            end
            local frame = created[2]
            frame:Hide()
            frame:SetPoint("CENTER")
            frame:SetFrameStrata("DIALOG")
            frame:EnableMouse(true)
            local background = frame:CreateTexture(nil, "BACKGROUND")
            background:SetAllPoints()
            background:SetColorTexture(0.05, 0.05, 0.05, 0.95)
            frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            frame.title:SetPoint("TOPLEFT", 16, -16)
            frame.title:SetWidth(328)
            frame.buttons = {}
            registrationFrame = frame
        end
        local frame = registrationFrame
        frame:SetSize(360, 104 + #choices * 28)
        frame.title:SetText(title)
        for _, button in ipairs(frame.buttons) do
            button:Hide()
        end
        for index, choice in ipairs(choices) do
            local button = frame.buttons[index]
            if not button then
                local created = call("CreateFrame", "Button", nil, frame, "UIPanelButtonTemplate")
                if not created or not created[2] then
                    error("Button creation unavailable")
                end
                button = created[2]
                button:SetSize(328, 24)
                button:SetPoint("TOPLEFT", 16, -64 - (index - 1) * 28)
                frame.buttons[index] = button
            end
            button:SetText(choice.label)
            button:SetScript("OnClick", function()
                if choice.run() then
                    Api.HideRegistrationPrompt()
                end
            end)
            button:Show()
        end
        frame:Show()
    end)
    if not ok then
        capabilities.registrationPrompt = "error: " .. tostring(err):sub(1, 160)
        Api.HideRegistrationPrompt()
        Api.Print("Registration window unavailable; use /rq add, /rq link <slot>, or /rq ignore.")
        return false
    end
    capabilities.registrationPrompt = "available"
    return true
end

function Api.Print(message)
    local text = "RQ: " .. message
    if _G.DEFAULT_CHAT_FRAME and type(_G.DEFAULT_CHAT_FRAME.AddMessage) == "function" then
        local ok, err = pcall(_G.DEFAULT_CHAT_FRAME.AddMessage, _G.DEFAULT_CHAT_FRAME, text)
        if ok then
            capabilities.chat = "available"
            return
        end
        capabilities.chat = "error: " .. tostring(err):sub(1, 160)
    else
        capabilities.chat = "missing"
    end
    call("print", text)
end

function Api.RegisterSlashCommand(handler)
    if type(_G.SlashCmdList) ~= "table" then
        capabilities.SlashCmdList = "missing"
        Api.Print("Cannot register /rq: SlashCmdList is unavailable.")
        return false
    end
    _G.SLASH_ROSTERQUARTERMASTER1 = "/rq"
    _G.SlashCmdList.ROSTERQUARTERMASTER = handler
    capabilities.SlashCmdList = "available"
    return true
end

function Api.Subscribe(events, handler)
    local result = call("CreateFrame", "Frame")
    if not result or not result[2] then
        Api.Print("Cannot subscribe to events: CreateFrame is unavailable.")
        return nil
    end
    local frame = result[2]
    local ok, err = pcall(function()
        frame:SetScript("OnEvent", function(_, event, ...)
            handler(event, ...)
        end)
    end)
    if not ok then
        capabilities.OnEvent = "error: " .. tostring(err):sub(1, 160)
        Api.Print("Cannot install event handler; see /rq diag.")
        return nil
    end
    for _, event in ipairs(events) do
        local registered, reason = pcall(function()
            frame:RegisterEvent(event)
        end)
        capabilities["event:" .. event] = registered and "registered (not yet observed)"
            or "error: " .. tostring(reason):sub(1, 160)
        if not registered then
            Api.Print("Event " .. event .. " unavailable; see /rq diag.")
        end
    end
    return frame
end

function Api.MarkEventObserved(event)
    capabilities["event:" .. event] = "observed"
end

function Api.GetCapabilities()
    local copy = {}
    for key, value in pairs(capabilities) do
        copy[key] = value
    end
    return copy
end
