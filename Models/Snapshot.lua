local Snapshot = {}
RQ.Snapshot = Snapshot

function Snapshot.EmptySource()
    return { scannedAt = 0, complete = false, items = {} }
end

function Snapshot.NewInventory()
    local inventory = {}
    for _, source in ipairs({ "bags", "bank", "mail" }) do
        inventory[source] = Snapshot.EmptySource()
    end
    return inventory
end

Snapshot.fields = {
    progression = { "level", "xp", "xpMax" },
    rested = { "restedXp" },
    location = { "zone", "subZone", "wasResting" },
    money = { "money" },
    bags = { "bagSlots", "freeBagSlots" },
    professions = { "professions" },
}

function Snapshot.Apply(snapshot, section, values, now)
    snapshot.sections = snapshot.sections or {}
    local state = snapshot.sections[section] or {}
    local complete = true
    for _, field in ipairs(Snapshot.fields[section]) do
        if values[field] == nil then
            complete = false
        else
            snapshot[field] = RQ.Util.Copy(values[field])
        end
    end
    state.complete = complete
    state.attemptedAt = now
    if complete then
        state.observedAt = now
    end
    snapshot.sections[section] = state
    return complete
end

function Snapshot.SectionState(snapshot, section, now, hours)
    local value = snapshot.sections and snapshot.sections[section]
    if not value or not value.complete or not RQ.Util.IsNumber(value.observedAt) or value.observedAt == 0 then
        return "UNKNOWN"
    end
    if not RQ.Util.IsNumber(now) or now < value.observedAt or now - value.observedAt >= hours * 3600 then
        return "STALE"
    end
    return "RECENT"
end

function Snapshot.Freshness(snapshot, now, staleHours)
    if not RQ.Util.IsNumber(now) or not RQ.Util.IsNumber(snapshot.lastSeen) or snapshot.lastSeen == 0 then
        return "UNKNOWN"
    end
    if now < snapshot.lastSeen then
        return "CLOCK MISMATCH"
    end
    if now - snapshot.lastSeen >= staleHours * 3600 then
        return "STALE"
    end
    return "RECENT"
end
