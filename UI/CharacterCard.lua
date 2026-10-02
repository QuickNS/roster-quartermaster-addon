local Card = {}
RQ.CharacterCard = Card

local function text(value)
    if value == nil then
        return "Unknown"
    end
    return (tostring(value):gsub("|", "||"))
end
Card.Text = text

function Card.Age(timestamp, now)
    if not RQ.Util.IsNumber(timestamp) or timestamp == 0 or not RQ.Util.IsNumber(now) then
        return "Unknown"
    end
    local elapsed = now - timestamp
    if elapsed < 0 then
        return "Clock mismatch"
    elseif elapsed < 60 then
        return math.floor(elapsed) .. "s ago"
    elseif elapsed < 3600 then
        return math.floor(elapsed / 60) .. "m ago"
    elseif elapsed < 86400 then
        return math.floor(elapsed / 3600) .. "h ago"
    end
    return math.floor(elapsed / 86400) .. "d ago"
end

function Card.Rested(estimate)
    return text(RQ.RestedEstimator.Describe(estimate))
end

function Card.Build(id, record, entry, now, activeId, staleHours, estimate)
    entry = entry or {}
    local identity, snapshot = record.identity, record.snapshot
    local lines = {
        "Planned name: " .. text(entry.plannedName) .. " | " .. text(identity.race) .. " / " .. text(identity.class),
        "Role: "
            .. text(RQ.Character.roleLabels[entry.role] or entry.role)
            .. " | Registration: "
            .. record.registration
            .. " | Slot: "
            .. text(entry.slotId),
        "Level: " .. text(snapshot.level) .. " | XP: " .. text(snapshot.xp) .. " / " .. text(snapshot.xpMax),
        "Rested XP: "
            .. text(snapshot.restedXp)
            .. (id == activeId and " (last observed on this character)" or " (last observed offline; not an estimate)"),
        "Last seen: "
            .. Card.Age(snapshot.lastSeen, now)
            .. " | Timestamp: "
            .. text(snapshot.lastSeen)
            .. " | "
            .. RQ.Snapshot.Freshness(snapshot, now, staleHours)
            .. " | Last logout: "
            .. text(snapshot.lastLogout),
        "Location: "
            .. text(snapshot.zone)
            .. " / "
            .. text(snapshot.subZone)
            .. " | Resting: "
            .. (snapshot.wasResting == nil and "Unknown" or snapshot.wasResting and "Yes" or "No"),
        "Money (copper): "
            .. text(snapshot.money)
            .. " | Free bag slots: "
            .. text(snapshot.freeBagSlots)
            .. " / "
            .. text(snapshot.bagSlots),
    }
    local professions = {}
    if estimate then
        lines[4] = Card.Rested(estimate)
    end
    for _, professionId in ipairs(RQ.Util.Keys(snapshot.professions or {})) do
        local profession = snapshot.professions[professionId]
        professions[#professions + 1] = text(profession.name)
            .. " "
            .. text(profession.skill)
            .. "/"
            .. text(profession.maxSkill)
    end
    lines[#lines + 1] = "Professions (skill/cap): "
        .. (#professions > 0 and table.concat(professions, ", ") or "None observed")
    lines[#lines + 1] = "Profession targets / session objective: not configured (later milestones)"
    local uncertain = {}
    for _, section in ipairs(RQ.Util.Keys(RQ.Snapshot.fields)) do
        local state = (snapshot.sections or {})[section]
        if
            not state
            or not state.complete
            or not state.observedAt
            or not now
            or now < state.observedAt
            or now - state.observedAt >= staleHours * 3600
        then
            uncertain[#uncertain + 1] = section
        end
    end
    if #uncertain > 0 then
        lines[#lines + 1] = "Incomplete, stale, or unknown sections: " .. table.concat(uncertain, ", ")
    end
    lines[#lines + 1] = "ID: " .. text(id)
    return {
        id = id,
        title = text(identity.displayName)
            .. " - "
            .. text(identity.realm)
            .. (entry.isMain and " [MAIN]" or "")
            .. (id == activeId and " [ACTIVE]" or ""),
        body = table.concat(lines, "\n"),
        action = "Configure",
    }
end

function Card.Planned(id, slot)
    return {
        slotId = id,
        title = text(slot.plannedName) .. " [PLANNED]" .. (slot.isMain and " [INTENDED MAIN]" or ""),
        body = text(slot.race)
            .. " / "
            .. text(slot.class)
            .. " | Role: "
            .. text(RQ.Character.roleLabels[slot.role] or slot.role)
            .. "\nSlot: "
            .. text(id)
            .. "\n"
            .. (
                slot.claimedBy and "Linked to " .. text(slot.claimedBy) .. "; no account snapshot available."
                or "Not linked. Select an actual character in Settings and explicitly link this slot."
            ),
        action = "Edit slot",
    }
end
