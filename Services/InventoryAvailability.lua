local Stock = {}
RQ.InventoryAvailability = Stock

function Stock.BankEligible(record, now, hours)
    local inventory = record.inventory
    return inventory.bank.coherent == true
            and RQ.SuppliesConfig.IsFresh(inventory.bank, now, hours)
            and RQ.SuppliesConfig.IsFresh(inventory.bags, now, hours)
        or false
end

function Stock.Need(record, itemId, target, now, hours)
    local bags = record.inventory.bags
    local have = bags.complete and (bags.items[itemId] or 0) or nil
    local bank = Stock.BankEligible(record, now, hours) and (record.inventory.bank.items[itemId] or 0) or nil
    local deficit = have and math.max(0, target - have) or nil
    local withdraw = bank and deficit and math.min(bank, deficit) or 0
    return {
        target = target,
        have = have,
        bankHave = bank,
        withdraw = withdraw,
        missing = deficit and math.max(0, deficit - withdraw) or nil,
    }
end

function Stock.Materials(record, now, hours)
    local items = RQ.Util.Copy(record.inventory.bags.items)
    if Stock.BankEligible(record, now, hours) then
        for id, count in pairs(record.inventory.bank.items) do
            items[id] = (items[id] or 0) + count
        end
    end
    return items
end
