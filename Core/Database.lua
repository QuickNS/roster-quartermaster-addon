local Database = { initialized = false, status = "waiting for ADDON_LOADED" }
RQ.Database = Database

function Database.NotifyChanged()
    if Database.onChanged then
        Database.onChanged()
    end
end

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
    Database.NotifyChanged()
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
    Database.NotifyChanged()
    return true
end

function Database.Register(action, slotId, characterId)
    local id = characterId or Database.activeId
    local record = Database.initialized and id and RQDB.characters[id]
    if not record then
        return false, "Character identity unavailable; use /rq rescan, then /rq register."
    end
    local entry = RQDB.roster[id]
    if action == "ignore" then
        record.registration = "ignored"
        if entry then
            entry.enabled = false
            entry.isMain = false
            if entry.slotId then
                RQDB.plannedRoster[entry.slotId].isMain = false
            end
        end
        Database.NotifyChanged()
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
        local wasMain = entry and entry.isMain
        if not entry or entry.slotId ~= slotId then
            local merged = RQ.Util.Copy(entry or {})
            for key, value in pairs(slot) do
                merged[key] = RQ.Util.Copy(value)
            end
            entry = merged
        end
        entry.claimedBy = nil
        entry.slotId = slotId
        if wasMain then
            entry.isMain = true
        else
            for otherId, other in pairs(RQDB.roster) do
                if otherId ~= id and other.isMain then
                    entry.isMain = false
                    slot.isMain = false
                    break
                end
            end
        end
        slot.claimedBy = id
    end
    entry = entry or { role = "UNASSIGNED", plannedName = record.identity.displayName }
    for key, value in pairs(record.identity) do
        entry[key] = value
    end
    entry.enabled = true
    RQDB.roster[id] = entry
    record.registration = "member"
    if entry.isMain then
        Database.SetMain(id)
    else
        Database.NotifyChanged()
    end
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
    Database.NotifyChanged()
    return true
end

local function member(id)
    if not Database.initialized then
        return nil, Database.status
    end
    local record = id and RQDB.characters[id]
    if not record or record.registration ~= "member" or not RQDB.roster[id] or not RQDB.roster[id].enabled then
        return nil, "Select a registered, enabled roster member first."
    end
    return RQDB.roster[id]
end

function Database.SetMain(id)
    local entry, err = member(id)
    if not entry then
        return false, err
    end
    for otherId, other in pairs(RQDB.roster) do
        other.isMain = otherId == id
    end
    for slotId, slot in pairs(RQDB.plannedRoster) do
        slot.isMain = slotId == entry.slotId
    end
    Database.NotifyChanged()
    return true
end

function Database.SetRole(id, role)
    local entry, err = member(id)
    if not entry then
        return false, err
    end
    if not RQ.Character.roleLabels[role] then
        return false, "Unknown role. Use UNASSIGNED, TANK, HEALER, DPS, HEALER_DPS, or FLEX."
    end
    entry.role = role
    if entry.slotId then
        RQDB.plannedRoster[entry.slotId].role = role
    end
    Database.NotifyChanged()
    return true
end

function Database.Unlink(id)
    if not Database.initialized then
        return false, Database.status
    end
    local entry = id and RQDB.roster[id]
    if not entry or not entry.slotId then
        return false, "This character has no provisional link."
    end
    local slot = RQDB.plannedRoster[entry.slotId]
    slot.claimedBy = nil
    slot.isMain = false
    entry.slotId = nil
    entry.plannedName = nil
    Database.NotifyChanged()
    return true
end

function Database.SaveWindowPosition(position)
    if not Database.initialized then
        return false, Database.status
    end
    if not RQ.Util.IsWindowPosition(position) then
        return false, "Invalid window position; previous position preserved."
    end
    RQDB.settings.window = RQ.Util.Copy(position)
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
