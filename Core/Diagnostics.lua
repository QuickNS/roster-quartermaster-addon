local Diagnostics = {}
RQ.Diagnostics = Diagnostics

local function display(value)
    if value == nil then
        return "unavailable"
    end
    return tostring(value)
end

function Diagnostics.Capture()
    local api = RQ.Api
    local snapshot = api.GetCharacterProgression()
    snapshot.restedXp = api.GetRestedXP()
    snapshot.wasResting = api.IsResting()
    snapshot.lastSeen = api.GetServerTime()
    return api.GetCharacterIdentity(), snapshot
end

function Diagnostics.Report()
    local api = RQ.Api
    local build = api.GetBuildInfo()
    local project = api.GetClientProject()
    local identity, snapshot = Diagnostics.Capture()
    local database = RQ.Database.GetStatus()
    local lines = {
        "Roster Quartermaster " .. RQ.version .. " - compatibility spike",
        "Client version: " .. display(build.version) .. "; build: " .. display(build.build),
        "Interface: " .. display(build.interface) .. "; project ID: " .. display(project),
        "Target: Forever; client flavour is not inferred from the project ID.",
        "GUID: " .. display(identity.guid),
        "Character: " .. display(identity.displayName) .. "; realm: " .. display(identity.realm),
        "Class: " .. display(identity.class) .. "; race: " .. display(identity.race),
        "Level: " .. display(snapshot.level) .. "; XP: " .. display(snapshot.xp) .. "/" .. display(snapshot.xpMax),
        "Rested XP (observed): " .. display(snapshot.restedXp) .. "; resting: " .. display(snapshot.wasResting),
        "SavedVariables: " .. database.message,
        "Schemas: account=" .. display(database.accountSchema) .. "; character=" .. display(database.characterSchema),
        "Last saved observation (server timestamp): " .. display(database.lastSeen),
        "Optional integrations: none loaded",
    }
    local capabilities = api.GetCapabilities()
    local names = {}
    for name in pairs(capabilities) do
        names[#names + 1] = name
    end
    table.sort(names)
    for _, name in ipairs(names) do
        lines[#lines + 1] = name .. ": " .. capabilities[name]
    end
    for _, line in ipairs(lines) do
        api.Print(line)
    end
    return lines
end
