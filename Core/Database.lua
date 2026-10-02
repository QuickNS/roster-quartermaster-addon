local Database = { initialized = false, status = "waiting for ADDON_LOADED" }
RQ.Database = Database

local function prepare(value, label, fields)
    if value ~= nil and type(value) ~= "table" then
        return nil, label .. " is not a table; original data preserved."
    end
    value = value or {}
    if value.schemaVersion ~= nil and value.schemaVersion ~= RQ.schemaVersion then
        return nil, label .. " has an unsupported schema; original data preserved."
    end
    for _, field in ipairs(fields) do
        if value[field] ~= nil and type(value[field]) ~= "table" then
            return nil, label .. "." .. field .. " is not a table; original data preserved."
        end
    end

    local prepared = {}
    for key, item in pairs(value) do
        prepared[key] = item
    end
    prepared.schemaVersion = RQ.schemaVersion
    for _, field in ipairs(fields) do
        prepared[field] = prepared[field] or {}
    end
    return prepared
end

function Database.Initialize()
    if Database.initialized then
        return true
    end
    local account, accountError = prepare(RQDB, "RQDB", { "settings" })
    local character, characterError = prepare(RQCharDB, "RQCharDB", { "identity", "snapshot" })
    if not account or not character then
        Database.status = accountError or characterError
        RQ.Api.Print("SavedVariables disabled: " .. Database.status)
        return false
    end
    RQDB = account
    RQCharDB = character
    Database.initialized = true
    Database.status = "initialized"
    return true
end

function Database.SaveProbe(identity, snapshot)
    if not Database.initialized then
        return false
    end
    -- Missing identity data must not erase a previously observed identity.
    for key, value in pairs(identity) do
        RQCharDB.identity[key] = value
    end
    RQCharDB.snapshot = snapshot
    return true
end

function Database.GetStatus()
    return {
        initialized = Database.initialized,
        message = Database.status,
        accountSchema = type(RQDB) == "table" and RQDB.schemaVersion or nil,
        characterSchema = type(RQCharDB) == "table" and RQCharDB.schemaVersion or nil,
        lastSeen = type(RQCharDB) == "table" and type(RQCharDB.snapshot) == "table" and RQCharDB.snapshot.lastSeen
            or nil,
    }
end
