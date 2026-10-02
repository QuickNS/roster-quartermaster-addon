local Migrations = {}
RQ.Migrations = Migrations

local function tableField(parent, key, path, default)
    if parent[key] == nil then
        parent[key] = RQ.Util.Copy(default or {})
    elseif type(parent[key]) ~= "table" then
        return nil, path .. "." .. key .. " is not a table; original data preserved."
    end
    return parent[key]
end

local function validateIdentity(identity)
    for _, field in ipairs({ "guid", "displayName", "realm", "class", "race" }) do
        if identity[field] ~= nil and not RQ.Util.IsText(identity[field]) then
            return false
        end
    end
    return true
end

local function validateSnapshot(snapshot)
    for _, field in ipairs({
        "level",
        "xp",
        "xpMax",
        "restedXp",
        "money",
        "bagSlots",
        "freeBagSlots",
        "lastSeen",
        "lastLogout",
    }) do
        if snapshot[field] ~= nil and not RQ.Util.IsNumber(snapshot[field]) then
            return false
        end
    end
    for _, field in ipairs({ "zone", "subZone" }) do
        if snapshot[field] ~= nil and type(snapshot[field]) ~= "string" then
            return false
        end
    end
    if snapshot.wasResting ~= nil and type(snapshot.wasResting) ~= "boolean" then
        return false
    end
    if not tableField(snapshot, "sections", "snapshot") or not tableField(snapshot, "professions", "snapshot") then
        return false
    end
    for name, state in pairs(snapshot.sections) do
        if type(name) ~= "string" or type(state) ~= "table" then
            return false
        end
        if state.complete ~= nil and type(state.complete) ~= "boolean" then
            return false
        end
        for _, field in ipairs({ "attemptedAt", "observedAt" }) do
            if state[field] ~= nil and not RQ.Util.IsNumber(state[field]) then
                return false
            end
        end
    end
    for id, profession in pairs(snapshot.professions) do
        if not RQ.Util.IsNumber(id) or type(profession) ~= "table" then
            return false
        end
        if
            not RQ.Util.IsText(profession.name)
            or not RQ.Util.IsNumber(profession.skill)
            or not RQ.Util.IsNumber(profession.maxSkill)
        then
            return false
        end
    end
    return true
end

local function prepareRecord(record, path)
    local identity, err = tableField(record, "identity", path)
    if not identity then
        return nil, err
    end
    local snapshot
    snapshot, err = tableField(record, "snapshot", path)
    if not snapshot then
        return nil, err
    end
    if not validateIdentity(identity) or not validateSnapshot(snapshot) then
        return nil, path .. " contains invalid identity or snapshot values; original data preserved."
    end
    local inventory
    inventory, err = tableField(record, "inventory", path, RQ.Snapshot.NewInventory())
    if not inventory then
        return nil, err
    end
    for _, source in ipairs({ "bags", "bank", "mail" }) do
        local entry
        entry, err = tableField(inventory, source, path .. ".inventory", RQ.Snapshot.EmptySource())
        if not entry then
            return nil, err
        end
        if entry.scannedAt == nil then
            entry.scannedAt = 0
        end
        if entry.complete == nil then
            entry.complete = false
        end
        if
            not RQ.Util.IsNumber(entry.scannedAt)
            or type(entry.complete) ~= "boolean"
            or not tableField(entry, "items", path .. ".inventory." .. source)
        then
            return nil, path .. ".inventory." .. source .. " is invalid; original data preserved."
        end
    end
    local recipes
    recipes, err = tableField(record, "recipes", path, RQ.Snapshot.EmptySource())
    if not recipes then
        return nil, err
    end
    if recipes.scannedAt == nil then
        recipes.scannedAt = 0
    end
    if recipes.complete == nil then
        recipes.complete = false
    end
    if
        not RQ.Util.IsNumber(recipes.scannedAt)
        or type(recipes.complete) ~= "boolean"
        or not tableField(recipes, "items", path .. ".recipes")
    then
        return nil, path .. ".recipes is invalid; original data preserved."
    end
    local restedState, restedError = RQ.PlanningConfig.PrepareState(record.restedState)
    if not restedState then
        return nil, path .. ": " .. restedError .. " Original data preserved."
    end
    record.restedState = restedState
    return record
end

local function root(value, label)
    if value ~= nil and type(value) ~= "table" then
        return nil, label .. " is not a table; original data preserved."
    end
    value = RQ.Util.Copy(value or {})
    if
        value.schemaVersion ~= nil
        and value.schemaVersion ~= 1
        and value.schemaVersion ~= 2
        and value.schemaVersion ~= 3
        and value.schemaVersion ~= 4
    then
        return nil, label .. " has an unsupported schema; original data preserved."
    end
    return value
end

function Migrations.Prepare(accountValue, characterValue)
    local account, err = root(accountValue, "RQDB")
    if not account then
        return nil, nil, err
    end
    local character
    character, err = root(characterValue, "RQCharDB")
    if not character then
        return nil, nil, err
    end
    local seedLegacy = (account.schemaVersion or 1) < 4
    for _, field in ipairs({ "settings", "roster", "characters", "policies", "session" }) do
        local value
        value, err = tableField(account, field, "RQDB")
        if not value then
            return nil, nil, err
        end
    end
    local planning, planningError = RQ.PlanningConfig.Prepare(account.settings.planning)
    if not planning then
        return nil, nil, planningError .. " Original data preserved."
    end
    account.settings.planning = planning
    for _, field in ipairs({ "currentCharacterId", "previousCharacterId" }) do
        if account.session[field] ~= nil and not RQ.Util.IsText(account.session[field]) then
            return nil, nil, "Invalid session character ID; original data preserved."
        end
    end
    local window
    window, err = tableField(account.settings, "window", "RQDB.settings", RQ.Util.DefaultWindowPosition())
    if not window then
        return nil, nil, err
    end
    for key, value in pairs(RQ.Util.DefaultWindowPosition()) do
        if window[key] == nil then
            window[key] = value
        end
    end
    if not RQ.Util.IsWindowPosition(window) then
        return nil, nil, "RQDB.settings.window is invalid; original data preserved."
    end
    local slots
    slots, err = tableField(account, "plannedRoster", "RQDB", RQ.DefaultRoster)
    if not slots then
        return nil, nil, err
    end
    if account.policies.staleSnapshotHours == nil then
        account.policies.staleSnapshotHours = 48
    end
    if not RQ.Util.IsNumber(account.policies.staleSnapshotHours) then
        return nil, nil, "RQDB.policies.staleSnapshotHours is invalid; original data preserved."
    end
    for _, entries in ipairs({ slots, account.roster }) do
        for id, entry in pairs(entries) do
            if not RQ.Util.IsText(id) or type(entry) ~= "table" or not validateIdentity(entry) then
                return nil, nil, "RQDB contains an invalid roster entry; original data preserved."
            end
            for _, field in ipairs({ "plannedName", "claimedBy", "slotId", "role" }) do
                if entry[field] ~= nil and not RQ.Util.IsText(entry[field]) then
                    return nil, nil, "RQDB contains invalid roster metadata; original data preserved."
                end
            end
            for _, field in ipairs({ "enabled", "isMain" }) do
                if entry[field] ~= nil and type(entry[field]) ~= "boolean" then
                    return nil, nil, "RQDB contains invalid roster flags; original data preserved."
                end
            end
        end
    end
    local prepared
    prepared, err = prepareRecord(character, "RQCharDB")
    if not prepared then
        return nil, nil, err
    end
    if character.characterId ~= nil and not RQ.Util.IsText(character.characterId) then
        return nil, nil, "RQCharDB.characterId is invalid; original data preserved."
    end
    for id, entry in pairs(account.roster) do
        for key, default in pairs({
            restedMultiplier = 1,
            restedRevision = 0,
            resourceBlocker = false,
            dungeonReady = false,
        }) do
            if entry[key] == nil then
                entry[key] = default
            end
        end
        if not RQ.PlanningConfig.ValidEntry(entry) then
            return nil, nil, "Invalid character planning settings; original data preserved."
        end
        if entry.enabled == nil then
            entry.enabled = true
        end
        if account.characters[id] == nil then
            local identity = {}
            for _, field in ipairs({ "guid", "displayName", "realm", "class", "race" }) do
                identity[field] = entry[field]
            end
            account.characters[id] = {
                identity = identity,
                registration = entry.enabled and "member" or "ignored",
            }
        end
    end
    for id, record in pairs(account.characters) do
        if not RQ.Util.IsText(id) or type(record) ~= "table" then
            return nil, nil, "RQDB.characters contains an invalid record; original data preserved."
        end
        prepared, err = prepareRecord(record, "RQDB.characters." .. id)
        if not prepared then
            return nil, nil, err
        end
        if seedLegacy and record.restedState.logout == nil then
            record.restedState.logout = RQ.RestedEstimator.LogoutSample(record.snapshot, planning, account.roster[id])
        end
        if record.registration == nil then
            record.registration = account.roster[id] and "member" or "pending"
        end
        if
            record.registration ~= "member"
            and record.registration ~= "pending"
            and record.registration ~= "ignored"
        then
            return nil, nil, "RQDB.characters contains an invalid registration; original data preserved."
        end
        if record.registration == "member" and not account.roster[id] then
            return nil, nil, "RQDB.characters has a member without roster configuration; original data preserved."
        end
    end
    if (character.schemaVersion or 1) < 4 and character.restedState.logout == nil then
        local id = RQ.Character.Id(character.identity)
        character.restedState.logout =
            RQ.RestedEstimator.LogoutSample(character.snapshot, planning, id and account.roster[id])
    end
    for id, slot in pairs(slots) do
        if slot.claimedBy and (not account.roster[slot.claimedBy] or account.roster[slot.claimedBy].slotId ~= id) then
            return nil, nil, "RQDB contains an inconsistent provisional link; original data preserved."
        end
    end
    for id, entry in pairs(account.roster) do
        if entry.slotId and (not slots[entry.slotId] or slots[entry.slotId].claimedBy ~= id) then
            return nil, nil, "RQDB contains an inconsistent roster link; original data preserved."
        end
    end
    -- Validate both copies before publishing either SavedVariables root.
    account.schemaVersion = RQ.schemaVersion
    character.schemaVersion = RQ.schemaVersion
    return account, character
end
