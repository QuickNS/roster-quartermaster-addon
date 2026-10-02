local Database = { initialized = false, status = "waiting for ADDON_LOADED" }
RQ.Database = Database

function Database.Initialize()
    if Database.initialized then
        return true
    end
    local account, character, err = RQ.Migrations.Prepare(RQDB, RQCharDB)
    if not account or not character then
        Database.status = err
        RQ.Api.Print("SavedVariables disabled: " .. Database.status)
        return false
    end
    RQDB = account
    RQCharDB = character
    Database.initialized = true
    Database.status = "initialized"
    return true
end

function Database.Attach(identity)
    Database.activeId = nil
    if not Database.initialized then
        return nil, Database.status
    end
    local id = RQ.Character.Id(identity, RQCharDB.identity)
    if not id then
        return nil, "Current character identity unavailable; see /rq diag."
    end
    local fallback = RQ.Character.FallbackId(identity)
    if id ~= fallback and fallback and RQDB.characters[fallback] then
        if RQDB.characters[id] or RQDB.roster[id] then
            return nil, "GUID and fallback records both exist; data preserved. Resolve the conflict before capturing."
        end
        RQDB.characters[id] = RQDB.characters[fallback]
        RQDB.characters[fallback] = nil
        if RQDB.roster[fallback] then
            RQDB.roster[id] = RQDB.roster[fallback]
            RQDB.roster[fallback] = nil
        end
        for _, slot in pairs(RQDB.plannedRoster) do
            if slot.claimedBy == fallback then
                slot.claimedBy = id
            end
        end
    end
    local record = RQDB.characters[id]
    if not record then
        local previousId = RQ.Character.Id(RQCharDB.identity)
        local matching = previousId == id or previousId == fallback
        record = {
            identity = matching and RQ.Util.Copy(RQCharDB.identity) or {},
            snapshot = matching and RQ.Util.Copy(RQCharDB.snapshot) or { sections = {} },
            inventory = matching and RQ.Util.Copy(RQCharDB.inventory) or RQ.Snapshot.NewInventory(),
            recipes = matching and RQ.Util.Copy(RQCharDB.recipes) or RQ.Snapshot.EmptySource(),
            registration = RQDB.roster[id] and "member" or "pending",
        }
        RQDB.characters[id] = record
    end
    for key, value in pairs(identity) do
        record.identity[key] = value
        if RQDB.roster[id] then
            RQDB.roster[id][key] = value
        end
    end
    RQCharDB.characterId = id
    RQCharDB.identity = RQ.Util.Copy(record.identity)
    RQCharDB.snapshot = RQ.Util.Copy(record.snapshot)
    RQCharDB.inventory = RQ.Util.Copy(record.inventory)
    RQCharDB.recipes = RQ.Util.Copy(record.recipes)
    Database.activeId = id
    return record, nil, id
end

function Database.Current()
    if not Database.initialized or not Database.activeId then
        return nil
    end
    return RQDB.characters[Database.activeId]
end

function Database.SaveSnapshot(snapshot)
    local record = Database.Current()
    if not record then
        return false, "No current character record."
    end
    if record.registration == "ignored" then
        return false, "Character is ignored; use /rq register to enable tracking."
    end
    record.snapshot = RQ.Util.Copy(snapshot)
    RQCharDB.snapshot = RQ.Util.Copy(snapshot)
    return true
end

function Database.Register(action, slotId)
    local record = Database.Current()
    if not record then
        return false, "Character identity unavailable; use /rq rescan, then /rq register."
    end
    local id = RQCharDB.characterId
    local entry = RQDB.roster[id]
    if action == "ignore" then
        record.registration = "ignored"
        if entry then
            entry.enabled = false
        end
        return true
    end
    if action ~= "add" and action ~= "link" then
        return false, "Unknown registration action."
    end
    if action == "link" then
        local slot = RQDB.plannedRoster[slotId]
        if not slot then
            return false, "Unknown provisional slot; use /rq slots."
        end
        if slot.claimedBy and slot.claimedBy ~= id then
            return false, "That provisional slot is already linked to another character."
        end
        if entry and entry.slotId and entry.slotId ~= slotId then
            return false, "This character is already linked to a different slot."
        end
        entry = entry and entry.slotId == slotId and entry or RQ.Util.Copy(slot)
        entry.claimedBy = nil
        entry.slotId = slotId
        slot.claimedBy = id
    end
    entry = entry or { role = "UNASSIGNED", plannedName = record.identity.displayName }
    for key, value in pairs(record.identity) do
        entry[key] = value
    end
    entry.enabled = true
    RQDB.roster[id] = entry
    record.registration = "member"
    return true
end

function Database.RenameSlot(slotId, name)
    if not Database.initialized then
        return false, Database.status
    end
    local slot = RQDB.plannedRoster[slotId]
    if not slot then
        return false, "Unknown provisional slot; use /rq slots."
    end
    if not RQ.Util.IsText(name) or #name > 64 or name:find("[%c|]") then
        return false, "Planned name must contain 1-64 bytes without control characters or chat markup."
    end
    slot.plannedName = name
    if slot.claimedBy and RQDB.roster[slot.claimedBy] then
        RQDB.roster[slot.claimedBy].plannedName = name
    end
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
