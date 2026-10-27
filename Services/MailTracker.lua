local Tracker = {}
RQ.MailTracker = Tracker

local function normalize(value)
    return value:match("^%s*(.-)%s*$"):lower()
end

function Tracker.Resolve(account, address, sourceId)
    if type(address) ~= "string" then
        return nil
    end
    local source, found = account.characters[sourceId]
    if not source or source.registration ~= "member" or not account.roster[sourceId] then
        return nil
    end
    for _, id in ipairs(RQ.Util.Keys(account.roster)) do
        local record = account.characters[id]
        if record and record.registration == "member" and RQ.Character.CanTrade(source.identity, record.identity) then
            local name = RQ.Character.DisplayName(record.identity)
            if
                name
                and (record.identity.fullName or record.identity.nameComplete == true)
                and (
                    normalize(address) == normalize(name)
                    or normalize(address) == normalize(name .. "-" .. record.identity.realm)
                )
            then
                if found then
                    return nil
                end
                found = id
            end
        end
    end
    return found
end

function Tracker.Key(message)
    local sender, subject = normalize(message.sender), message.subject
    return #sender .. ":" .. sender .. #subject .. ":" .. subject
end

function Tracker.SameItems(first, second)
    for id, count in pairs(first) do
        if count ~= (second[id] or 0) then
            return false
        end
    end
    for id, count in pairs(second) do
        if count ~= (first[id] or 0) then
            return false
        end
    end
    return true
end

local function groups(messages)
    local result = {}
    for _, message in ipairs(messages) do
        local key = Tracker.Key(message)
        result[key] = result[key] or {}
        result[key][#result[key] + 1] = message
    end

    return result
end

local function recentTake(takes, key, now)
    local time = takes[key]
    return RQ.Util.IsNumber(time) and now >= time and now - time <= 30
end

function Tracker.Reconcile(account, ledger, recipientId, oldInventory, inventory, takes, verified)
    for _, message in ipairs(inventory.mail.messages) do
        if message.returned then
            for _, transfer in pairs(ledger.transfers) do
                if
                    transfer.sourceId == recipientId
                    and transfer.subject == message.subject
                    and (transfer.status == "sent" or transfer.status == "inbox")
                then
                    transfer.status, transfer.reason =
                        "uncertain",
                        "Returned mail with the same subject observed at sender; reconcile before crediting delivery."
                    transfer.ambiguous = true
                end
            end
        end
    end
    local before, after = groups(oldInventory.mail.messages or {}), groups(inventory.mail.messages)
    local linked, candidates = {}, {}
    for id, transfer in pairs(ledger.transfers) do
        if
            transfer.recipientId == recipientId
            and (transfer.status == "sent" or transfer.status == "inbox" or transfer.status == "uncertain")
        then
            candidates[id] = transfer
            for key, messages in pairs(after) do
                for _, message in ipairs(messages) do
                    if
                        Tracker.Resolve(account, message.sender, recipientId) == transfer.sourceId
                        and message.subject == transfer.subject
                    then
                        linked[key] = linked[key] or {}
                        linked[key][id] = true
                    end
                end
            end
        end
    end
    local usedGains = {}
    for _, id in ipairs(RQ.Util.Keys(candidates)) do
        local transfer = candidates[id]
        local occurrences = 0
        for key, matches in pairs(linked) do
            if matches[id] then
                occurrences = occurrences + #after[key]
            end
        end
        if occurrences > 1 then
            transfer.ambiguous = true
        end
        local found
        for key, matches in pairs(linked) do
            if matches[id] then
                found = true
                local message = after[key][1]
                if #RQ.Util.Keys(matches) ~= 1 then
                    transfer.ambiguous = true
                end
                if
                    not verified
                    or transfer.ambiguous
                    or #after[key] ~= 1
                    or #RQ.Util.Keys(matches) ~= 1
                    or message.returned
                    or message.cod > 0
                then
                    transfer.status, transfer.reason =
                        "uncertain", "Inbox attribution is unverified, ambiguous, returned or COD."
                elseif Tracker.SameItems(transfer.remaining, message.items) then
                    transfer.status, transfer.reason = "inbox", "Observed unique matching recipient inbox attachments."
                else
                    local previous = before[key] and #before[key] == 1 and before[key][1]
                    local valid = previous
                        and transfer.status == "inbox"
                        and recentTake(takes, key, inventory.mail.scannedAt)
                        and oldInventory.mail.coherent
                        and oldInventory.bags.complete
                    local removed = {}
                    for item, count in pairs(transfer.remaining) do
                        local left = message.items[item] or 0
                        local gain = (inventory.bags.items[item] or 0) - (oldInventory.bags.items[item] or 0)
                        if left > count or count - left > gain - (usedGains[item] or 0) then
                            valid = false
                        end
                        removed[item] = count - left
                    end
                    for item in pairs(message.items) do
                        if not transfer.remaining[item] then
                            valid = false
                        end
                    end
                    if valid then
                        transfer.remaining = RQ.Util.Copy(message.items)
                        transfer.status = next(message.items) and "inbox" or "collected"
                        transfer.reason =
                            "Partial collection matched inbox removal and carried gain after a manual take."
                        for item, count in pairs(removed) do
                            usedGains[item] = (usedGains[item] or 0) + count
                        end
                    else
                        transfer.status, transfer.reason =
                            "uncertain", "Changed inbox attachments require reconciliation."
                    end
                end
            end
        end
        if not found then
            local previousKey
            for key, messages in pairs(before) do
                if
                    #messages == 1
                    and Tracker.Resolve(account, messages[1].sender, recipientId) == transfer.sourceId
                    and messages[1].subject == transfer.subject
                    and Tracker.SameItems(messages[1].items, transfer.remaining)
                then
                    if previousKey then
                        previousKey = false
                        break
                    end
                    previousKey = key
                end
            end
            local valid = verified
                and not transfer.ambiguous
                and transfer.status == "inbox"
                and previousKey
                and recentTake(takes, previousKey, inventory.mail.scannedAt)
                and oldInventory.mail.coherent
                and oldInventory.bags.complete
            for item, count in pairs(transfer.remaining) do
                local gain = (inventory.bags.items[item] or 0) - (oldInventory.bags.items[item] or 0)
                if count > gain - (usedGains[item] or 0) then
                    valid = false
                end
            end
            if valid then
                for item, count in pairs(transfer.remaining) do
                    usedGains[item] = (usedGains[item] or 0) + count
                end
                transfer.status, transfer.reason, transfer.remaining =
                    "collected", "Manual take, inbox removal and coherent carried gain verified.", {}
            else
                transfer.status, transfer.reason =
                    "uncertain",
                    "Not uniquely present in the observed inbox; delivery, return or collection is unconfirmed."
            end
        end
    end
    return ledger
end

function Tracker.Coverage(account, recipientId, now, verified)
    local result = { pending = {}, inbox = {}, pendingSources = {} }
    local record, hours = account.characters[recipientId], account.policies.staleSnapshotHours
    if not record or record.registration ~= "member" then
        return result
    end
    local mail, bags = record.inventory.mail, record.inventory.bags
    if
        verified
        and mail.coherent
        and RQ.SuppliesConfig.IsFresh(mail, now, hours)
        and RQ.SuppliesConfig.IsFresh(bags, now, hours)
    then
        for _, message in ipairs(mail.messages) do
            if message.cod == 0 and not message.returned then
                for item, count in pairs(message.items) do
                    result.inbox[item] = (result.inbox[item] or 0) + count
                end
            end
        end
    end
    for id, transfer in pairs(account.mailTracking and account.mailTracking.transfers or {}) do
        local source = account.characters[transfer.sourceId]
        local confirmed = transfer.manualConfirmed
            or (verified and transfer.confirmedBuild == account.mailTracking.verifiedBuild)
        if
            transfer.recipientId == recipientId
            and transfer.status == "sent"
            and not transfer.ambiguous
            and confirmed
            and source
            and source.registration == "member"
            and RQ.Character.CanTrade(source.identity, record.identity)
            and RQ.Util.IsNumber(now)
            and now >= transfer.attemptedAt
            and now - transfer.attemptedAt < hours * 3600
            and RQ.SuppliesConfig.IsFresh(source.inventory.bags, now, hours)
            and source.inventory.bags.scannedAt >= transfer.attemptedAt
            and RQ.SuppliesConfig.IsFresh(bags, now, hours)
            and (mail.scannedAt or 0) < transfer.attemptedAt
            and (mail.attemptedAt or 0) < transfer.attemptedAt
        then
            for item, count in pairs(transfer.remaining) do
                result.pending[item] = (result.pending[item] or 0) + count
                result.pendingSources[item] = result.pendingSources[item] or {}
                table.insert(result.pendingSources[item], {
                    sender = RQ.Character.DisplayName(source.identity) or transfer.sourceId,
                    quantity = count,
                    state = "confirmed pending",
                    transferId = id,
                    at = transfer.attemptedAt,
                })
            end
        end
    end
    return result
end
