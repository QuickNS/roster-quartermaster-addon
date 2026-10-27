local Mail = { generation = 0, takes = {} }
RQ.MailService = Mail

local function save(ledger, inventory, id)
    local ok, err = RQ.Database.SaveMailTracking(ledger, inventory, id)
    if not ok then
        RQ.Api.Print("Mail tracking not saved: " .. err)
    end
    return ok, err
end

function Mail.Verified(account)
    account = account or RQDB
    return account
            and account.mailTracking
            and account.mailTracking.verifiedBuild ~= nil
            and account.mailTracking.verifiedBuild == RQ.Api.MailBuildKey()
        or false
end

function Mail.Verify(enable)
    if not RQ.Database.initialized then
        return false, RQ.Database.status
    end
    local ledger = RQ.Util.Copy(RQDB.mailTracking)
    local build = enable and RQ.Api.MailBuildKey()
    if enable and not build then
        return false, "Client build identity unavailable."
    end
    ledger.verifiedBuild = build or nil
    return save(ledger)
end

function Mail.Initialize()
    local ledger, changed = RQ.Util.Copy(RQDB.mailTracking), false
    local record = RQ.Database.Current()
    local invalidate = record and record.inventory.mail.scannedAt > 0
    for _, transfer in pairs(ledger.transfers) do
        if transfer.recipientId == RQ.Database.activeId and transfer.status == "sent" then
            invalidate = true
        end
        if transfer.status == "awaiting" then
            transfer.status, transfer.reason = "uncertain", "Reload/logout interrupted send confirmation."
            changed = true
        end
    end
    if invalidate then
        local inventory = RQ.Util.Copy(record.inventory)
        inventory.mail.complete, inventory.mail.coherent = false, false
        inventory.mail.attemptedAt = RQ.Api.GetServerTime() or inventory.mail.attemptedAt
        inventory.mail.error = "New login: revisit the mailbox before crediting cached inbox or incoming transfers."
        save(ledger, inventory, RQ.Database.activeId)
    elseif changed then
        save(ledger)
    end
    Mail.attemptId = nil
    if not RQ.Api.ObserveMail({ attempt = Mail.Attempt, action = Mail.Action }) then
        RQ.Api.Print("Passive mail tracking unavailable; existing manual mail assistance remains usable.")
    end
end

function Mail.Interrupt(reason)
    if Mail.attemptId and RQDB.mailTracking.transfers[Mail.attemptId] then
        local ledger = RQ.Util.Copy(RQDB.mailTracking)
        local transfer = ledger.transfers[Mail.attemptId]
        if transfer.status == "awaiting" then
            transfer.status, transfer.reason = "uncertain", reason
        end
        save(ledger)
    end
    Mail.attemptId = nil
end

function Mail.Attempt(address, subject)
    if not RQ.Database.initialized then
        return
    end
    local overlapping = Mail.attemptId ~= nil
    Mail.Interrupt("Overlapping send attempts cannot be correlated safely.")
    local sourceId = RQ.Database.activeId
    local recipientId = RQ.MailTracker.Resolve(RQDB, address, sourceId)
    if not recipientId or recipientId == sourceId then
        return
    end
    local draft, err = RQ.Api.GetMailDraft()
    if not draft or #draft.items == 0 or RQ.MailTracker.Resolve(RQDB, draft.recipient, sourceId) ~= recipientId then
        RQ.Api.Print("Roster mail not tracked: " .. (err or "final attachments/address unavailable after SendMail."))
        return
    end
    if RQ.Api.GetOutgoingCOD() ~= 0 then
        RQ.Api.Print("Roster COD mail is not tracked for material coverage.")
        return
    end
    local now = RQ.Api.GetServerTime()
    if not now or now == 0 or type(subject) ~= "string" or #subject > 512 then
        RQ.Api.Print("Roster mail not tracked: send timestamp or subject unavailable.")
        return
    end
    local ledger = RQ.Util.Copy(RQDB.mailTracking)
    local id = ledger.nextId
    ledger.nextId = id + 1
    ledger.transfers[id] = {
        sourceId = sourceId,
        recipientId = recipientId,
        address = address,
        realm = RQDB.characters[sourceId].identity.realm,
        subject = subject,
        items = RQ.Util.Copy(draft.counts),
        remaining = RQ.Util.Copy(draft.counts),
        details = {},
        attemptedAt = now,
        status = overlapping and "uncertain" or "awaiting",
        signal = false,
        reason = overlapping and "Overlapping attempt; confirmation must be manual." or "Awaiting send result.",
    }
    for _, item in ipairs(draft.items) do
        ledger.transfers[id].details[item.itemId] = { name = item.name }
    end
    local inventory = RQ.Util.Copy(RQ.Database.Current().inventory)
    inventory.bags.complete, inventory.bags.error = false, "Send attempt pending; carried stock needs refresh."
    if save(ledger, inventory, sourceId) and not overlapping then
        Mail.attemptId = id
    end
    RQ.SnapshotService.Queue({ "bags" })
end

function Mail.SendResult(success)
    local id, now = Mail.attemptId, RQ.Api.GetServerTime()
    Mail.attemptId = nil
    local original = id and RQDB.mailTracking.transfers[id]
    if not original or original.status ~= "awaiting" then
        return
    end
    local ledger = RQ.Util.Copy(RQDB.mailTracking)
    local transfer = ledger.transfers[id]
    transfer.signal = success
    if not success then
        transfer.status, transfer.reason = "failed", "Native send failure observed; no pending credit."
    elseif
        not now
        or now < transfer.attemptedAt
        or now - transfer.attemptedAt > 30
        or RQ.Database.activeId ~= transfer.sourceId
        or RQ.MailTracker.Resolve(RQDB, transfer.address, transfer.sourceId) ~= transfer.recipientId
    then
        transfer.status, transfer.reason = "uncertain", "Send result timing or roster attribution is uncertain."
    elseif Mail.Verified() then
        transfer.status, transfer.reason = "sent", "Correlated MAIL_SEND_SUCCESS on a user-verified client build."
        transfer.confirmedBuild = RQ.Api.MailBuildKey()
    else
        transfer.status, transfer.reason =
            "uncertain", "MAIL_SEND_SUCCESS observed; verify this client contract or confirm this shipment manually."
    end
    save(ledger)
    RQ.SnapshotService.Queue({ "bags" })
end

function Mail.Resolve(id, action)
    local original = RQDB.mailTracking.transfers[id]
    if not original then
        return false, "Unknown shipment ID."
    end
    local ledger = RQ.Util.Copy(RQDB.mailTracking)
    local transfer = ledger.transfers[id]
    if action == "sent" then
        if transfer.status ~= "uncertain" or not transfer.signal or transfer.ambiguous then
            return false, "Only unambiguous uncertain transfers with a send-success observation can be confirmed."
        end
        transfer.status, transfer.reason = "sent", "User explicitly confirmed this successful shipment."
        transfer.manualConfirmed = true
    elseif action == "close" then
        transfer.status, transfer.reason = "closed", "User stopped shipment credit; collection is not inferred."
    else
        return false, "Use /rq shipment <ID> sent|close."
    end
    return save(ledger)
end

function Mail.Prune()
    local ledger = RQ.Util.Copy(RQDB.mailTracking)
    for id, transfer in pairs(ledger.transfers) do
        if transfer.status == "closed" or transfer.status == "failed" or transfer.status == "collected" then
            ledger.transfers[id] = nil
        end
    end
    return save(ledger)
end

function Mail.MarkDirty()
    local record = RQ.Database.Current()
    if not record or record.registration == "ignored" then
        return
    end
    if not Mail.baseline then
        Mail.baseline = RQ.Util.Copy(record.inventory)
    end
    local inventory = RQ.Util.Copy(record.inventory)
    inventory.mail.complete, inventory.mail.coherent = false, false
    inventory.mail.attemptedAt = RQ.Api.GetServerTime() or inventory.mail.attemptedAt
    inventory.mail.error = "Inbox/carried update pending; mail stock is not credited."
    if RQ.Api.CanObserveInbox() then
        inventory.bags.complete = false
        inventory.bags.error = "Inbox/carried update pending; rescan before using carried stock."
    else
        inventory.mail.error = "Inbox APIs unavailable; cached mail remains unconfirmed."
    end
    save(RQDB.mailTracking, inventory, RQ.Database.activeId)
end

function Mail.Scan()
    local record = RQ.Database.Current()
    if not record or record.registration == "ignored" or not RQ.Api.IsMailboxOpen() then
        return false, "Open this tracked character's mailbox."
    end
    local pair, err = RQ.Api.GetMailInventory(RQ.Database.activeId)
    if not pair then
        if err ~= Mail.lastError then
            RQ.Api.Print("Inbox not refreshed: " .. err)
        end
        Mail.lastError = err
        Mail.MarkDirty()
        return false, err
    end
    local inventory = RQ.Util.Copy(record.inventory)
    inventory.bags, inventory.mail = pair.bags, pair.mail
    local ledger = RQ.MailTracker.Reconcile(
        RQDB,
        RQ.Util.Copy(RQDB.mailTracking),
        RQ.Database.activeId,
        Mail.baseline or record.inventory,
        inventory,
        Mail.takes,
        Mail.Verified()
    )
    local ok, saveError = save(ledger, inventory, RQ.Database.activeId)
    if ok then
        Mail.baseline, Mail.lastError, Mail.takes = nil, nil, {}
    else
        Mail.MarkDirty()
    end
    return ok, saveError
end

function Mail.Changed()
    Mail.MarkDirty()
    if not RQ.Api.CanObserveInbox() then
        RQ.SuppliesService.ScanBags()
        return
    end
    if Mail.scheduled or not RQ.Api.IsMailboxOpen() then
        return
    end
    Mail.scheduled = true
    local generation, id = Mail.generation, RQ.Database.activeId
    local function refresh()
        if generation ~= Mail.generation then
            return
        end
        Mail.scheduled = false
        if id == RQ.Database.activeId and RQ.Api.IsMailboxOpen() then
            Mail.Scan()
        end
    end
    if not RQ.Api.After(0.25, refresh) then
        refresh()
    end
end

function Mail.Action(action, header)
    if not RQ.Database.Current() or RQ.Database.Current().registration == "ignored" then
        return
    end
    if action == "TakeInboxItem" and header then
        Mail.takes[RQ.MailTracker.Key(header)] = RQ.Api.GetServerTime()
    else
        Mail.takes = {}
    end
    Mail.Changed()
end

function Mail.Closed()
    Mail.Interrupt("Mailbox closed before confirmed send result.")
    Mail.generation = Mail.generation + 1
    Mail.scheduled, Mail.baseline, Mail.takes = false, nil, {}
end
