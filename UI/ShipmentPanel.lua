local Panel = {}
RQ.ShipmentPanel = Panel

function Panel.Build(account, now, verified)
    local cards = {
        {
            title = "Roster shipments - " .. (verified and "verified client build" or "observation mode"),
            body = "Only roster sends within the same known ruleset, faction and realm are tracked. "
                .. "Sending and collecting remain manual.\n"
                .. "Uncertain, failed and stale shipments never suppress replenishment. "
                .. "Mail is not craft-ready stock.\n"
                .. "After the documented client smoke test: /rq mail-tracking verify. Disable: /rq mail-tracking off.\n"
                .. "Confirm one observed successful send: /rq shipment <ID> sent.\n"
                .. "Stop credit without claiming collection: /rq shipment <ID> close. "
                .. "Prune closed history: /rq shipment prune.",
            action = "Refresh inbox",
            actionKind = "inbox-refresh",
        },
    }
    for _, id in ipairs(RQ.Util.Keys(account.mailTracking.transfers)) do
        local transfer = account.mailTracking.transfers[id]
        local canConfirm = transfer.status == "uncertain" and transfer.signal and not transfer.ambiguous
        local source, recipient = account.characters[transfer.sourceId], account.characters[transfer.recipientId]
        local lines = {
            RQ.CharacterCard.Text(source and RQ.Character.DisplayName(source.identity) or transfer.sourceId)
                .. " -> "
                .. RQ.CharacterCard.Text(
                    recipient and RQ.Character.DisplayName(recipient.identity) or transfer.recipientId
                ),
            "Sender GUID: " .. transfer.sourceId .. " | Recipient GUID: " .. transfer.recipientId,
            "Final address: " .. RQ.CharacterCard.Text(transfer.address) .. " | Realm: " .. RQ.CharacterCard.Text(
                transfer.realm
            ),
            "Subject: " .. RQ.CharacterCard.Text(transfer.subject),
            "Attempt: " .. transfer.attemptedAt .. " | " .. RQ.CharacterCard.Age(transfer.attemptedAt, now),
            "Send-success signal: " .. tostring(transfer.signal) .. ". " .. transfer.reason,
        }
        local coverage = RQ.MailTracker.Coverage(account, transfer.recipientId, now, verified)
        for _, item in ipairs(RQ.Util.Keys(transfer.items)) do
            lines[#lines + 1] = RQ.SuppliesService.ItemLabel(account, item)
                .. " ["
                .. item
                .. "]: sent draft "
                .. transfer.items[item]
                .. ", unresolved remainder "
                .. (transfer.remaining[item] or 0)
                .. "; recipient total provisionally pending "
                .. (coverage.pending[item] or 0)
                .. ", observed eligible inbox "
                .. (coverage.inbox[item] or 0)
        end
        cards[#cards + 1] = {
            title = "Shipment " .. id .. " | " .. transfer.status:upper(),
            body = table.concat(lines, "\n"),
            action = canConfirm and "Confirm sent" or "Stop credit",
            actionKind = canConfirm and "shipment-confirm" or "shipment-close",
            disabled = transfer.status == "failed" or transfer.status == "closed" or transfer.status == "collected",
            shipmentId = id,
        }
    end
    return cards
end

function Panel.Open(textOnly)
    if not RQ.Database.initialized then
        RQ.Api.Print("Shipments unavailable: " .. RQ.Database.status)
        return false
    end
    if not textOnly and RQ.MainWindow.Open("shipments") then
        return true
    end
    for _, card in ipairs(Panel.Build(RQDB, RQ.Api.GetServerTime(), RQ.MailService.Verified())) do
        RQ.Api.Print(card.title)
        RQ.Api.Print(card.body)
    end
    return true
end
