local Bank = { generation = 0, dirty = false }
RQ.BankService = Bank

local function persist(inventory)
    local ok, err = RQ.Database.SaveLogistics(RQ.Database.activeId, "inventory", inventory)
    if not ok then
        RQ.Api.Print("Bank snapshot not saved: " .. err)
    end
    return ok, err
end

function Bank.MarkDirty(reason)
    local record = RQ.Database.Current()
    if not record or record.registration == "ignored" then
        return
    end
    Bank.dirty = true
    local inventory = RQ.Util.Copy(record.inventory)
    inventory.bank.coherent, inventory.bank.complete = false, false
    inventory.bank.error = reason or "Bank update pending; combined stock is unconfirmed."
    inventory.bank.attemptedAt = RQ.Api.GetServerTime() or inventory.bank.attemptedAt or 0
    inventory.bags.complete = false
    inventory.bags.error = "Bag/bank update pending; rescan before using carried stock."
    return persist(inventory)
end

function Bank.Scan()
    local record = RQ.Database.Current()
    if not record or record.registration == "ignored" then
        return false, "Current character is not tracked."
    end
    if not RQ.Api.IsBankSessionOpen() then
        return false, "Open the personal bank to scan it."
    end
    local pair, err = RQ.Api.GetBankInventory(RQ.Database.activeId)
    if not pair then
        if Bank.lastError ~= err then
            RQ.Api.Print("Bank contents unavailable: " .. err)
        end
        Bank.lastError = err
        Bank.MarkDirty(err)
        return false, err
    end
    local inventory = RQ.Util.Copy(record.inventory)
    for _, source in ipairs({ "bags", "bank" }) do
        for id, detail in pairs(pair[source].details) do
            local previous = inventory[source].details and inventory[source].details[id]
            if not detail.name and previous then
                detail.name = previous.name
            end
        end
        inventory[source] = pair[source]
    end
    local ok, saveError = persist(inventory)
    if ok then
        Bank.dirty, Bank.lastError = false, nil
    else
        Bank.MarkDirty("Bank scan could not be validated: " .. saveError)
    end
    return ok, saveError
end

function Bank.Cancel()
    Bank.generation = Bank.generation + 1
    Bank.scheduled = false
end

function Bank.Changed()
    Bank.MarkDirty()
    if not RQ.Api.IsBankSessionOpen() or Bank.scheduled then
        return
    end
    Bank.scheduled = true
    local generation, characterId = Bank.generation, RQ.Database.activeId
    local function refresh()
        if generation ~= Bank.generation then
            return
        end
        Bank.scheduled = false
        if characterId == RQ.Database.activeId and RQ.Api.IsBankSessionOpen() then
            Bank.Scan()
        end
    end
    if not RQ.Api.After(0.25, refresh) then
        refresh()
    end
end

function Bank.Closed()
    Bank.Cancel()
    if Bank.dirty then
        Bank.MarkDirty("Bank closed before a coherent refresh; reopen it to verify cached contents.")
    end
end
