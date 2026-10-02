local Api = {}
RQ.Api = Api

local capabilities = {}

local function call(name, ...)
    local fn = _G[name]
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
    local identity = {
        guid = scalar("UnitGUID", "string", "player"),
        displayName = scalar("UnitName", "string", "player"),
        realm = scalar("GetRealmName", "string"),
    }
    local class = call("UnitClass", "player")
    if class and type(class[3]) == "string" then
        identity.class = class[3]
    elseif class then
        capabilities.UnitClass = "unexpected return type"
    end
    local race = call("UnitRace", "player")
    if race and type(race[2]) == "string" then
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
