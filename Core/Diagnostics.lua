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

function Diagnostics.Slots()
    if not RQ.Database.initialized then
        RQ.Api.Print("Roster unavailable: " .. RQ.Database.status)
        return
    end
    for _, id in ipairs(RQ.Util.Keys(RQDB.plannedRoster)) do
        local slot = RQDB.plannedRoster[id]
        RQ.Api.Print(
            id
                .. ": "
                .. display(slot.plannedName)
                .. " ["
                .. display(slot.class)
                .. "] - "
                .. (slot.claimedBy and "linked to " .. slot.claimedBy or "available")
        )
    end
    RQ.Api.Print("Use /rq link <slot> for this character, or /rq name <slot> <planned name> to edit a label.")
end

function Diagnostics.Roster()
    if not RQ.Database.initialized then
        RQ.Api.Print("Roster unavailable: " .. RQ.Database.status)
        return
    end
    local now = RQ.Api.GetServerTime()
    local count = 0
    for _, id in ipairs(RQ.Util.Keys(RQDB.characters)) do
        local record = RQDB.characters[id]
        if record.registration ~= "ignored" then
            count = count + 1
            local entry = RQDB.roster[id] or {}
            local snapshot = record.snapshot
            local freshness = RQ.Snapshot.Freshness(snapshot, now, RQDB.policies.staleSnapshotHours)
            RQ.Api.Print(
                display(record.identity.displayName)
                    .. " - "
                    .. display(record.identity.realm)
                    .. " ["
                    .. record.registration
                    .. ", "
                    .. freshness
                    .. "]"
                    .. " level "
                    .. display(snapshot.level)
                    .. "; last seen: "
                    .. display(snapshot.lastSeen)
            )
            RQ.Api.Print(
                "  ID: "
                    .. id
                    .. "; planned: "
                    .. display(entry.plannedName)
                    .. "; role: "
                    .. display(entry.role)
                    .. "; main: "
                    .. display(entry.isMain == true)
            )
            RQ.Api.Print(
                "  Last observed XP: "
                    .. display(snapshot.xp)
                    .. "/"
                    .. display(snapshot.xpMax)
                    .. "; rested XP: "
                    .. display(snapshot.restedXp)
                    .. "; zone: "
                    .. display(snapshot.zone)
                    .. "; resting: "
                    .. display(snapshot.wasResting)
            )
            for _, section in ipairs(RQ.Util.Keys(RQ.Snapshot.fields)) do
                local state = snapshot.sections[section]
                if
                    not state
                    or not state.complete
                    or not state.observedAt
                    or not now
                    or now < state.observedAt
                    or now - state.observedAt >= RQDB.policies.staleSnapshotHours * 3600
                then
                    RQ.Api.Print(
                        "  "
                            .. section
                            .. ": incomplete, stale, or never observed; last successful scan: "
                            .. display(state and state.observedAt)
                    )
                end
            end
        end
    end
    RQ.Api.Print(
        tostring(count) .. " tracked character(s); ignored characters omitted. Use /rq slots for provisional entries."
    )
end

function Diagnostics.Report()
    local api = RQ.Api
    local build = api.GetBuildInfo()
    local project = api.GetClientProject()
    local identity, snapshot = Diagnostics.Capture()
    local database = RQ.Database.GetStatus()
    local lines = {
        "Roster Quartermaster " .. RQ.version .. " - roster snapshots",
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
        "Registration UI module: " .. (RQ.RegistrationPrompt and "loaded" or "NOT LOADED; reinstall complete addon"),
        "Dashboard modules: "
            .. (
                RQ.MainWindow and RQ.RosterPanel and RQ.CharacterCard and "loaded"
                or "NOT LOADED; reinstall complete addon"
            ),
    }
    local record = RQ.Database.Current()
    if record then
        lines[#lines + 1] = "Record: " .. RQCharDB.characterId .. "; registration: " .. record.registration
        lines[#lines + 1] = "Saved snapshot: "
            .. RQ.Snapshot.Freshness(record.snapshot, api.GetServerTime(), RQDB.policies.staleSnapshotHours)
            .. "; last logout: "
            .. display(record.snapshot.lastLogout)
        for _, section in ipairs(RQ.Util.Keys(RQ.Snapshot.fields)) do
            local state = record.snapshot.sections[section] or {}
            lines[#lines + 1] = "Snapshot "
                .. section
                .. ": "
                .. (state.complete and "complete" or "INCOMPLETE")
                .. "; observed: "
                .. display(state.observedAt)
                .. "; attempted: "
                .. display(state.attemptedAt)
        end
        local saved = record.snapshot
        lines[#lines + 1] = "Saved location: " .. display(saved.zone) .. " / " .. display(saved.subZone)
        lines[#lines + 1] = "Saved money (copper): "
            .. display(saved.money)
            .. "; free bag slots: "
            .. display(saved.freeBagSlots)
            .. "/"
            .. display(saved.bagSlots)
        for _, id in ipairs(RQ.Util.Keys(saved.professions or {})) do
            local profession = saved.professions[id]
            lines[#lines + 1] = "Profession "
                .. id
                .. ": "
                .. profession.name
                .. " "
                .. profession.skill
                .. "/"
                .. profession.maxSkill
        end
        for _, source in ipairs({ "bags", "bank", "mail" }) do
            local inventory = record.inventory[source]
            lines[#lines + 1] = "Inventory "
                .. source
                .. ": "
                .. (inventory.complete and "cached (not refreshed by this milestone)" or "UNKNOWN / not scanned")
                .. "; scanned: "
                .. display(inventory.scannedAt)
        end
        lines[#lines + 1] = "Recipes: "
            .. (record.recipes.complete and "cached (not refreshed by this milestone)" or "UNKNOWN / not scanned")
            .. "; scanned: "
            .. display(record.recipes.scannedAt)
    end
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
