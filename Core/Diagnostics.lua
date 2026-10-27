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

function Diagnostics.Roster(silent, includeIgnored)
    local lines = {}
    local function output(text)
        lines[#lines + 1] = text
        if not silent then
            RQ.Api.Print(text)
        end
    end
    if not RQ.Database.initialized then
        output("Roster unavailable: " .. RQ.Database.status)
        return lines
    end
    local now = RQ.Api.GetServerTime()
    local planning, planningError = RQ.PlanningService.Evaluate()
    if not planning then
        output("Rested planning unavailable: " .. planningError)
    end
    local count = 0
    for _, id in ipairs(RQ.Util.Keys(RQDB.characters)) do
        local record = RQDB.characters[id]
        if includeIgnored or record.registration ~= "ignored" then
            count = count + 1
            local entry = RQDB.roster[id] or {}
            local snapshot = record.snapshot
            local freshness = RQ.Snapshot.Freshness(snapshot, now, RQDB.policies.staleSnapshotHours)
            output(
                display(RQ.Character.DisplayName(record.identity))
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
            output("Trade group: " .. RQ.Character.TradeGroupLabel(record.identity))
            local cook = RQ.LogisticsPolicies.Cook(RQDB, record.identity)
            if cook then
                output("Cooking/Fishing: " .. display(RQ.Character.DisplayName(RQDB.characters[cook].identity)))
            end
            output(
                "  ID: "
                    .. id
                    .. "; planned: "
                    .. display(entry.plannedName)
                    .. "; role: "
                    .. display(entry.role)
                    .. "; main: "
                    .. display(entry.isMain == true)
            )
            output(
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
            output(
                "  Money: "
                    .. display(snapshot.money)
                    .. "; free/total bag slots: "
                    .. display(snapshot.freeBagSlots)
                    .. "/"
                    .. display(snapshot.bagSlots)
                    .. "; last logout: "
                    .. display(snapshot.lastLogout)
            )
            for _, professionId in ipairs(RQ.Util.Keys(snapshot.professions or {})) do
                local profession = snapshot.professions[professionId]
                output(
                    "  Profession "
                        .. professionId
                        .. ": "
                        .. profession.name
                        .. " "
                        .. profession.skill
                        .. "/"
                        .. profession.maxSkill
                )
            end
            if planning then
                output("  " .. RQ.RestedEstimator.Describe(planning.estimates[id]))
            end
            for _, line in
                ipairs(
                    RQ.ProfessionStatus.Lines(
                        snapshot,
                        now,
                        RQDB.policies.staleSnapshotHours,
                        RQDB.settings.professionLag
                    )
                )
            do
                output("  " .. line)
            end
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
                    output(
                        "  "
                            .. section
                            .. ": incomplete, stale, or never observed; last successful scan: "
                            .. display(state and state.observedAt)
                    )
                end
            end
        end
    end
    output(
        tostring(count)
            .. " tracked character(s); "
            .. (includeIgnored and "includes ignored characters." or "ignored characters omitted.")
            .. " Use /rq slots for provisional entries."
    )
    return lines
end

function Diagnostics.Report(silent)
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
        "Character: " .. display(RQ.Character.DisplayName(identity)) .. "; realm: " .. display(identity.realm),
        "Class: " .. display(identity.class) .. "; race: " .. display(identity.race),
        "Trade group: " .. RQ.Character.TradeGroupLabel(identity) .. "; ruleset source: " .. display(
            identity.rulesetSource
        ),
        "Level: " .. display(snapshot.level) .. "; XP: " .. display(snapshot.xp) .. "/" .. display(snapshot.xpMax),
        "Rested XP (observed): " .. display(snapshot.restedXp) .. "; resting: " .. display(snapshot.wasResting),
        "SavedVariables: " .. database.message,
        "Schemas: account=" .. display(database.accountSchema) .. "; character=" .. display(database.characterSchema),
        "Last saved observation (server timestamp): " .. display(database.lastSeen),
        "Optional integrations: none loaded",
        "Registration UI module: " .. (RQ.RegistrationPrompt and "loaded" or "NOT LOADED; reinstall complete addon"),
        "Dashboard modules: "
            .. (
                RQ.MainWindow and RQ.RosterPanel and RQ.CharacterCard and RQ.TodayPanel and "loaded"
                or "NOT LOADED; reinstall complete addon"
            ),
    }
    local record = RQ.Database.Current()
    if record then
        lines[#lines + 1] = "Profession advice: reference model v"
            .. RQ.ProfessionRelationships.version
            .. "; focus: "
            .. record.professionIntent.focus
        lines[#lines + 1] = "Planned profession IDs (not learned): "
            .. table.concat(RQ.Util.Keys(record.professionIntent.planned), ",")
        lines[#lines + 1] = "Preferred profession IDs: "
            .. table.concat(RQ.Util.Keys(record.professionIntent.preferred), ",")
            .. "; excluded new choices: "
            .. table.concat(RQ.Util.Keys(record.professionIntent.excluded), ",")
        lines[#lines + 1] = "Mail tracking: "
            .. (RQ.MailService.Verified() and "verified build" or "observation mode")
            .. "; shipments: "
            .. #RQ.Util.Keys(RQDB.mailTracking.transfers)
        lines[#lines + 1] = "Inbox/carried coherence: "
            .. tostring(record.inventory.mail.coherent)
            .. "; attempted: "
            .. display(record.inventory.mail.attemptedAt)
        if record.inventory.mail.error then
            lines[#lines + 1] = "Inbox scan: " .. record.inventory.mail.error
        end
        local calibration = record.restedState.calibration
        local comparison = record.restedState.comparison
        lines[#lines + 1] = "Rested assumptions: unverified; configure rates/cap in /rq planning"
        lines[#lines + 1] = "Calibration samples: inn=" .. #calibration.inside .. "; outside=" .. #calibration.outside
        lines[#lines + 1] = "Last calibration: " .. display(comparison and comparison.reason)
        if comparison then
            lines[#lines + 1] = "Calibration predicted="
                .. display(comparison.estimated)
                .. "; observed="
                .. display(comparison.actual)
                .. "; error="
                .. display(comparison.error)
        end
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
                .. (inventory.complete and "cached" or "UNKNOWN / incomplete")
                .. "; scanned: "
                .. display(inventory.scannedAt)
        end
        lines[#lines + 1] = "Recipes: "
            .. "observed per profession; unscanned professions remain unknown"
            .. "; scanned: "
            .. display(record.recipes.scannedAt)
        if record.inventory.bags.error then
            lines[#lines + 1] = "Bag scan: " .. record.inventory.bags.error
        end
        local bank = record.inventory.bank
        lines[#lines + 1] = "Bank/carried coherence: "
            .. tostring(bank.coherent)
            .. "; last bank attempt: "
            .. display(bank.attemptedAt)
        if bank.error then
            lines[#lines + 1] = "Bank scan: " .. bank.error
        end
        for _, id in ipairs(RQ.Util.Keys(bank.containers or {})) do
            lines[#lines + 1] = "Bank container " .. id .. ": " .. bank.containers[id].capacity .. " slots"
        end
        for _, id in ipairs(RQ.Util.Keys(bank.items)) do
            lines[#lines + 1] = "Bank item " .. id .. ": " .. bank.items[id]
        end
        if record.recipes.error then
            lines[#lines + 1] = "Recipe scan: " .. record.recipes.error
        end
        for _, professionId in ipairs(RQ.Util.Keys(record.recipes.professions)) do
            local scan = record.recipes.professions[professionId]
            local known = 0
            for _, recipe in pairs(scan.recipes) do
                if recipe.learned then
                    known = known + 1
                end
            end
            lines[#lines + 1] = scan.name .. " recipes known: " .. known .. "; observed: " .. scan.scannedAt
        end
    end
    for _, line in ipairs(api.GetNameEvidence()) do
        lines[#lines + 1] = line
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
    if not silent then
        for _, line in ipairs(lines) do
            api.Print(line)
        end
    end
    return lines
end

function Diagnostics.Copy()
    local lines = Diagnostics.Report(true)
    if RQ.Database.initialized then
        lines[#lines + 1] = "\nACCOUNT ROSTER (includes character names, GUIDs and realms)"
        for _, line in ipairs(Diagnostics.Roster(true, true)) do
            lines[#lines + 1] = line
        end
        for _, id in ipairs(RQ.Util.Keys(RQDB.characters)) do
            lines[#lines + 1] = "\nSUPPLIES"
            for _, line in ipairs(RQ.SuppliesService.Report(id)) do
                lines[#lines + 1] = line
            end
        end
    end
    return RQ.Api.ShowCopyWindow(
        "Copy addon report - review personal information before sharing",
        table.concat(lines, "\n")
    )
end
