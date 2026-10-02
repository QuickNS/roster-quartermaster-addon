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
        local planning = RQDB.settings.planning
        if planning.pinnedCharacterId == fallback then
            planning.pinnedCharacterId = id
        end
        for _, field in ipairs({ "currentCharacterId", "previousCharacterId" }) do
            if RQDB.session[field] == fallback then
                RQDB.session[field] = id
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
            restedState = matching and RQ.Util.Copy(RQCharDB.restedState) or RQ.PlanningConfig.PrepareState(nil),
            supplies = matching and RQ.Util.Copy(RQCharDB.supplies) or { needs = {}, goals = {} },
            registration = RQDB.roster[id] and "member" or "pending",
        }
        local ok, err = RQ.SuppliesConfig.Prepare(record)
        if not ok then
            return nil, err
        end
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
    RQCharDB.restedState = RQ.Util.Copy(record.restedState)
    RQCharDB.supplies = RQ.Util.Copy(record.supplies)
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

function Database.SetFullName(name)
    local record = Database.Current()
    if not record then
        return false, "Current character unavailable; use /rq rescan."
    end
    if not RQ.Util.IsText(name) or #name > 128 or name:find("[%c|]") then
        return false, "Enter the full character name without chat markup (maximum 128 bytes)."
    end
    record.identity.fullName = name:match("^%s*(.-)%s*$")
    RQCharDB.identity.fullName = record.identity.fullName
    Database.NotifyChanged()
    return true
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
            if RQDB.settings.planning.pinnedCharacterId == id then
                RQDB.settings.planning.pinnedCharacterId = nil
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
                if
                    key ~= "restedMultiplier"
                    and key ~= "restedRevision"
                    and key ~= "resourceBlocker"
                    and key ~= "dungeonReady"
                then
                    merged[key] = RQ.Util.Copy(value)
                end
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

function Database.SaveLogistics(id, field, value)
    if not Database.initialized or not id or not RQDB.characters[id] then
        return false, "Character record unavailable."
    end
    if field ~= "inventory" and field ~= "recipes" and field ~= "supplies" then
        return false, "Invalid logistics field."
    end
    local candidate = RQ.Util.Copy(RQDB.characters[id])
    candidate[field] = RQ.Util.Copy(value)
    local ok, err = RQ.SuppliesConfig.Prepare(candidate)
    if not ok then
        return false, err
    end
    RQDB.characters[id][field] = candidate[field]
    if id == Database.activeId then
        RQCharDB[field] = RQ.Util.Copy(candidate[field])
    end
    Database.NotifyChanged()
    return true
end

function Database.SaveRestedState(id, state)
    if not Database.initialized or not RQDB.characters[id] then
        return false, "Character record unavailable."
    end
    local prepared, err = RQ.PlanningConfig.PrepareState(state)
    if not prepared then
        return false, err
    end
    RQDB.characters[id].restedState = prepared
    if id == Database.activeId then
        RQCharDB.restedState = RQ.Util.Copy(prepared)
    end
    Database.NotifyChanged()
    return true
end

function Database.BeginSession()
    if not Database.Current() then
        return
    end
    if RQDB.session.currentCharacterId ~= Database.activeId then
        RQDB.session.previousCharacterId = RQDB.session.currentCharacterId
        RQDB.session.currentCharacterId = Database.activeId
    end
end

function Database.ResolveMember(query)
    if not Database.initialized then
        return nil, Database.status
    end
    if not RQ.Util.IsText(query) then
        return nil, "Specify a character name, GUID, or linked slot."
    end
    local direct = member(query)
    if direct then
        return query
    end
    local normalized = query:lower()
    local slot = RQDB.plannedRoster[normalized]
    if slot and slot.claimedBy and member(slot.claimedBy) then
        return slot.claimedBy
    end
    local matches = {}
    for _, id in ipairs(RQ.Util.Keys(RQDB.roster)) do
        local entry = member(id)
        if entry then
            local identity = RQDB.characters[id].identity
            local name = RQ.Character.DisplayName(identity)
            local full = name and identity.realm and (name .. "-" .. identity.realm)
            for _, candidate in pairs({ name, identity.displayName, full, entry.plannedName }) do
                if candidate:lower() == normalized then
                    matches[#matches + 1] = id
                    break
                end
            end
        end
    end
    if #matches == 1 then
        return matches[1]
    end
    if #matches > 1 then
        return nil, "Ambiguous character; use a GUID: " .. table.concat(matches, ", ")
    end
    return nil, "No enabled roster member matches; use /rq roster text."
end

function Database.Pin(id)
    local entry, err = member(id)
    if not entry then
        return false, err
    end
    RQDB.settings.planning.pinnedCharacterId = id
    Database.NotifyChanged()
    return true
end

function Database.Unpin()
    if not Database.initialized then
        return false, Database.status
    end
    RQDB.settings.planning.pinnedCharacterId = nil
    Database.NotifyChanged()
    return true
end

function Database.SetPlanning(values)
    if not Database.initialized then
        return false, Database.status
    end
    local updated = RQ.Util.Copy(RQDB.settings.planning)
    for _, field in ipairs(RQ.PlanningFields) do
        if values[field.key] == nil then
            return false, "Missing planning value: " .. field.key
        end
        updated[field.key] = values[field.key]
    end
    local prepared, err = RQ.PlanningConfig.Prepare(updated)
    if not prepared then
        return false, err
    end
    local changed = false
    for _, key in ipairs({ "innRate", "outsideRate", "capLevels", "maxLevel" }) do
        changed = changed or prepared[key] ~= RQDB.settings.planning[key]
    end
    RQDB.settings.planning = prepared
    if changed then
        for id, record in pairs(RQDB.characters) do
            record.restedState.calibration = RQ.RestedEstimator.EmptyCalibration(prepared, RQDB.roster[id])
            if id == Database.activeId then
                RQCharDB.restedState = RQ.Util.Copy(record.restedState)
            end
        end
    end
    Database.NotifyChanged()
    return true
end

function Database.ResetCalibration(id, multiplier)
    local entry, err = member(id)
    if not entry then
        return false, err
    end
    if multiplier ~= nil and (not RQ.Util.IsNumber(multiplier) or multiplier < 0.01 or multiplier > 100) then
        return false, "Rested rate multiplier must be between 0.01 and 100."
    end
    entry.restedMultiplier = multiplier or entry.restedMultiplier
    entry.restedRevision = entry.restedRevision + 1
    return Database.SaveRestedState(id, {
        calibration = RQ.RestedEstimator.EmptyCalibration(RQDB.settings.planning, entry),
    })
end

function Database.SetPlanningSignal(id, signal, enabled)
    local entry, err = member(id)
    if not entry then
        return false, err
    end
    if (signal ~= "resourceBlocker" and signal ~= "dungeonReady") or type(enabled) ~= "boolean" then
        return false, "Invalid manual planning signal."
    end
    entry[signal] = enabled
    Database.NotifyChanged()
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
