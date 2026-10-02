local Panel = {}
RQ.RosterPanel = Panel

function Panel.Build(account, activeId, now, selectedId, selectedSlot, estimates)
    local characterIds = RQ.Util.Keys(account.characters)
    local slotIds = RQ.Util.Keys(account.plannedRoster)
    if not selectedId or not account.characters[selectedId] then
        selectedId = activeId and account.characters[activeId] and activeId or characterIds[1]
    end
    if not selectedSlot or not account.plannedRoster[selectedSlot] then
        selectedSlot = slotIds[1]
    end
    local cards = {}
    for _, id in ipairs(characterIds) do
        cards[#cards + 1] = RQ.CharacterCard.Build(
            id,
            account.characters[id],
            account.roster[id],
            now,
            activeId,
            account.policies.staleSnapshotHours,
            estimates and estimates[id]
        )
    end
    for _, id in ipairs(slotIds) do
        local slot = account.plannedRoster[id]
        if not slot.claimedBy or not account.characters[slot.claimedBy] then
            cards[#cards + 1] = RQ.CharacterCard.Planned(id, slot)
        end
    end
    local record = selectedId and account.characters[selectedId]
    local entry = selectedId and account.roster[selectedId]
    local slot = selectedSlot and account.plannedRoster[selectedSlot]
    local text = RQ.CharacterCard.Text
    local characterLabel = "No character snapshots yet"
    local characterDetails = "Log in and run /rq rescan."
    if record then
        characterLabel = text(record.identity.displayName)
            .. " - "
            .. text(record.identity.realm)
            .. " ["
            .. record.registration
            .. "]"
        characterDetails = "ID: "
            .. text(selectedId)
            .. "\nLink: "
            .. text(entry and entry.slotId)
            .. " | Main: "
            .. (entry and entry.isMain and "Yes" or "No")
    end
    return {
        cards = cards,
        characterIds = characterIds,
        slotIds = slotIds,
        selectedId = selectedId,
        selectedSlot = selectedSlot,
        characterLabel = characterLabel,
        characterDetails = characterDetails,
        role = entry and entry.role or "UNASSIGNED",
        roleLabel = text(entry and (RQ.Character.roleLabels[entry.role] or entry.role) or "Unassigned"),
        isMember = record and record.registration == "member" and entry and entry.enabled == true or false,
        isMain = entry and entry.isMain == true or false,
        multiplier = entry and entry.restedMultiplier or 1,
        resourceBlocker = entry and entry.resourceBlocker == true or false,
        dungeonReady = entry and entry.dungeonReady == true or false,
        isPinned = selectedId ~= nil and account.settings.planning.pinnedCharacterId == selectedId,
        planning = account.settings.planning,
        isIgnored = record and record.registration == "ignored" or false,
        canUnlink = entry and entry.slotId ~= nil or false,
        canLink = record ~= nil
            and slot ~= nil
            and (not slot.claimedBy or slot.claimedBy == selectedId)
            and (not entry or not entry.slotId or entry.slotId == selectedSlot),
        slotName = slot and slot.plannedName or "",
        slotLabel = slot and text(selectedSlot) .. " [" .. text(slot.class) .. "]" or "No provisional slots",
        slotDetails = slot and (slot.claimedBy and "Linked to: " .. text(slot.claimedBy) or "Available to link")
            or "No provisional configuration available.",
    }
end
