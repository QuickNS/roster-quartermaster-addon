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
            professionIntent = matching and RQ.Util.Copy(RQCharDB.professionIntent) or nil,
            registration = RQDB.roster[id] and "member" or "pending",
        }
        local ok, err = RQ.SuppliesConfig.Prepare(record)
        if not ok then
            return nil, err
        end
        RQDB.characters[id] = record
    end
    local previousGroup = RQ.Character.RosterGroupKey(record.identity)
    if identity.realm and not RQ.Character.SameRealm(identity, record.identity) then
        record.identity.ruleset, record.identity.rulesetSource = nil, nil
        if RQDB.roster[id] then
            RQDB.roster[id].ruleset, RQDB.roster[id].rulesetSource = nil, nil
        end
    end
    for key, value in pairs(identity) do
        record.identity[key] = value
        if RQDB.roster[id] then
            RQDB.roster[id][key] = value
        end
        if previousGroup ~= RQ.Character.RosterGroupKey(record.identity) and RQDB.roster[id] then
            RQDB.roster[id].isMain = false
        end
    end
    RQCharDB.characterId = id
    RQCharDB.identity = RQ.Util.Copy(record.identity)
    RQCharDB.snapshot = RQ.Util.Copy(record.snapshot)
    RQCharDB.inventory = RQ.Util.Copy(record.inventory)
    RQCharDB.recipes = RQ.Util.Copy(record.recipes)
    RQCharDB.restedState = RQ.Util.Copy(record.restedState)
    RQCharDB.supplies = RQ.Util.Copy(record.supplies)
    RQCharDB.professionIntent = RQ.Util.Copy(record.professionIntent)
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

function Database.Register(action, characterId)
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
        end
        Database.NotifyChanged()
        return true
    end
    if action ~= "add" then
        return false, "Unknown registration action."
    end
    entry = entry or { role = "UNASSIGNED" }
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

function Database.SetProfessionConfig(values)
    if not Database.initialized then
        return false, Database.status
    end
    local settings, err = RQ.ProfessionConfig.Prepare(values)
    if not settings then
        return false, err
    end
    RQDB.settings.professionLag = settings
    Database.NotifyChanged()
    return true
end

function Database.SetLogisticsPolicies(values)
    if not Database.initialized then
        return false, Database.status
    end
    local settings, err = RQ.LogisticsPolicies.Prepare(values)
    if not settings then
        return false, err
    end
    RQDB.settings.logistics = settings
    Database.NotifyChanged()
    return true
end

local function member(id, includeDisabled)
    if not Database.initialized then
        return nil, Database.status
    end
    local record = id and RQDB.characters[id]
    if
        not record
        or record.registration ~= "member"
        or not RQDB.roster[id]
        or (not includeDisabled and not RQDB.roster[id].enabled)
    then
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
        local identity = RQDB.characters[otherId] and RQDB.characters[otherId].identity
        local selected = RQDB.characters[id].identity
        if
            otherId == id
            or (identity and RQ.Character.RosterGroupKey(selected) == RQ.Character.RosterGroupKey(identity))
        then
            other.isMain = otherId == id
        end
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
    Database.NotifyChanged()
    return true
end

function Database.SetRuleset(id, ruleset)
    local entry, err = member(id, true)
    if not entry then
        return false, err
    end
    if ruleset ~= "PVE" and ruleset ~= "PVP" then
        return false, "Choose PVE or PVP."
    end
    local identity = RQDB.characters[id].identity
    if RQ.Character.RulesetFromRealm(identity.realm) then
        return false, "Ruleset is identified by the realm name; rescan this character to refresh it."
    end
    if identity.ruleset ~= ruleset then
        entry.isMain = false
    end
    identity.ruleset, identity.rulesetSource = ruleset, "manual"
    entry.ruleset, entry.rulesetSource = ruleset, "manual"
    if id == Database.activeId then
        RQCharDB.identity = RQ.Util.Copy(identity)
    end
    Database.NotifyChanged()
    return true
end

function Database.SetCook(id)
    local entry, err = member(id)
    if not entry then
        return false, err
    end
    local identity = RQDB.characters[id].identity
    local group = RQ.Character.TradeGroup(identity)
    if not group or not identity.guid or identity.guid ~= id or not id:match("^Player%-[%w%-]+$") or #id > 128 then
        return false, "Cooking/Fishing requires a known ruleset, faction and character GUID; visit and rescan first."
    end
    local cooks = RQDB.settings.logistics.cooks
    cooks[group] = cooks[group] ~= id and id or nil
    Database.NotifyChanged()
    return true
end

function Database.SaveMinimapAngle(angle)
    if not Database.initialized then
        return false, Database.status
    end
    if not RQ.Util.IsMinimapAngle(angle) then
        return false, "Invalid minimap angle; previous position preserved."
    end
    RQDB.settings.minimapAngle = angle
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
    if field ~= "inventory" and field ~= "recipes" and field ~= "supplies" and field ~= "professionIntent" then
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

function Database.SaveMailTracking(ledger, inventory, id)
    local prepared, err = RQ.MailConfig.Prepare(RQ.Util.Copy(ledger))
    if not prepared then
        return false, err
    end
    local candidate
    if inventory then
        local record = RQDB.characters[id]
        if not record then
            return false, "Mail inventory owner unavailable."
        end
        candidate = RQ.Util.Copy(record)
        candidate.inventory = RQ.Util.Copy(inventory)
        local ok
        ok, err = RQ.SuppliesConfig.Prepare(candidate)
        if not ok then
            return false, err
        end
    end
    RQDB.mailTracking = prepared
    if candidate then
        RQDB.characters[id].inventory = candidate.inventory
        if id == Database.activeId then
            RQCharDB.inventory = RQ.Util.Copy(candidate.inventory)
        end
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

function Database.ResolveMember(query, includeDisabled)
    if not Database.initialized then
        return nil, Database.status
    end
    if not RQ.Util.IsText(query) then
        return nil, "Specify a character name or GUID."
    end
    local direct = member(query, includeDisabled)
    if direct then
        return query
    end
    local normalized = query:lower()
    local matches = {}
    for _, id in ipairs(RQ.Util.Keys(RQDB.roster)) do
        local entry = member(id, includeDisabled)
        if entry then
            local identity = RQDB.characters[id].identity
            local name = RQ.Character.DisplayName(identity)
            local full = name and identity.realm and (name .. "-" .. identity.realm)
            for _, candidate in pairs({ name, identity.displayName, full }) do
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
    return nil,
        includeDisabled and "No registered roster member matches; use /rq roster text."
            or "No enabled roster member matches; use /rq roster text."
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
