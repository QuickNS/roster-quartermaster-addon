local Config = {}
RQ.MailConfig = Config
Config.states = {
    awaiting = true,
    uncertain = true,
    sent = true,
    inbox = true,
    collected = true,
    failed = true,
    closed = true,
    returned = true,
}

function Config.Counts(items)
    if type(items) ~= "table" then
        return false
    end
    for id, count in pairs(items) do
        if not RQ.SuppliesConfig.Id(id) or not RQ.SuppliesConfig.Count(count) then
            return false
        end
    end
    return true
end

function Config.Prepare(value)
    if value == nil then
        value = { nextId = 1, transfers = {} }
    end
    if
        type(value) ~= "table"
        or not RQ.SuppliesConfig.Id(value.nextId)
        or type(value.transfers) ~= "table"
        or (value.verifiedBuild ~= nil and not RQ.Util.IsText(value.verifiedBuild))
    then
        return nil, "Invalid mail tracking ledger."
    end
    local count = 0
    for id, transfer in pairs(value.transfers) do
        count = count + 1
        if type(transfer) == "table" and transfer.manualConfirmed == nil then
            transfer.manualConfirmed = false
        end
        if type(transfer) == "table" and transfer.ambiguous == nil then
            transfer.ambiguous = false
        end
        if
            not RQ.SuppliesConfig.Id(id)
            or id >= value.nextId
            or type(transfer) ~= "table"
            or not Config.states[transfer.status]
            or not Config.Counts(transfer.items)
            or not next(transfer.items)
            or not Config.Counts(transfer.remaining)
            or not RQ.Util.IsNumber(transfer.attemptedAt)
            or transfer.attemptedAt == 0
            or not RQ.Util.IsText(transfer.sourceId)
            or not RQ.Util.IsText(transfer.recipientId)
            or transfer.sourceId == transfer.recipientId
            or not RQ.Util.IsText(transfer.address)
            or not RQ.Util.IsText(transfer.realm)
            or type(transfer.subject) ~= "string"
            or #transfer.subject > 512
            or type(transfer.signal) ~= "boolean"
            or type(transfer.manualConfirmed) ~= "boolean"
            or type(transfer.ambiguous) ~= "boolean"
            or (transfer.confirmedBuild ~= nil and not RQ.Util.IsText(transfer.confirmedBuild))
            or not RQ.Util.IsText(transfer.reason)
        then
            return nil, "Invalid tracked mail transfer."
        end
        for item, quantity in pairs(transfer.remaining) do
            if quantity > (transfer.items[item] or 0) then
                return nil, "Mail remainder exceeds sent quantity."
            end
        end
        if transfer.details == nil then
            transfer.details = {}
        end
        if type(transfer.details) ~= "table" then
            return nil, "Invalid shipment item metadata."
        end
        for item, detail in pairs(transfer.details) do
            if
                not RQ.SuppliesConfig.Id(item)
                or type(detail) ~= "table"
                or (detail.name ~= nil and not RQ.Util.IsText(detail.name))
            then
                return nil, "Invalid shipment item metadata."
            end
        end
    end
    if count > 500 then
        return nil, "Mail transfer ledger exceeds 500 records; prune resolved transfers."
    end
    return value
end

function Config.PrepareInbox(source)
    if source.messages == nil then
        source.messages = {}
    end
    if source.details == nil then
        source.details = {}
    end
    if source.coherent == nil then
        source.coherent = false
    end
    if source.attemptedAt == nil then
        source.attemptedAt = 0
    end
    if
        type(source.messages) ~= "table"
        or #source.messages > 1000
        or type(source.details) ~= "table"
        or type(source.coherent) ~= "boolean"
        or not Config.Counts(source.items)
        or not RQ.Util.IsNumber(source.attemptedAt)
        or (source.error ~= nil and not RQ.Util.IsText(source.error))
    then
        return false, "Invalid inbox snapshot."
    end
    for id, detail in pairs(source.details) do
        if
            not RQ.SuppliesConfig.Id(id)
            or type(detail) ~= "table"
            or (detail.name ~= nil and not RQ.Util.IsText(detail.name))
        then
            return false, "Invalid inbox item metadata."
        end
    end
    local totals, messages = {}, 0
    for index, message in pairs(source.messages) do
        messages = messages + 1
        if
            not RQ.SuppliesConfig.Id(index)
            or index > #source.messages
            or type(message) ~= "table"
            or not RQ.Util.IsText(message.sender)
            or type(message.subject) ~= "string"
            or #message.subject > 512
            or not Config.Counts(message.items)
            or not RQ.Util.IsNumber(message.cod)
            or type(message.returned) ~= "boolean"
            or not RQ.Util.IsNumber(message.daysLeft)
        then
            return false, "Invalid inbox message."
        end
        for id, count in pairs(message.items) do
            totals[id] = (totals[id] or 0) + count
        end
    end
    if messages ~= #source.messages then
        return false, "Sparse inbox message list."
    end
    if source.coherent then
        if not source.complete or source.scannedAt == 0 or source.attemptedAt < source.scannedAt then
            return false, "Coherent inbox lacks observation."
        end
        for id, count in pairs(totals) do
            if count ~= (source.items[id] or 0) then
                return false, "Inbox message totals disagree."
            end
        end
        for id, count in pairs(source.items) do
            if count ~= (totals[id] or 0) then
                return false, "Inbox message totals disagree."
            end
        end
    end
    return true
end
