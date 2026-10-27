local Scope = {}
RQ.WorkspaceScope = Scope

function Scope.Matches(identity, realm, group)
    return (realm == "all" or (RQ.Character.Realm(identity) or "~unknown") == realm)
        and (group == "all" or (RQ.Character.TradeGroup(identity) or "~unknown") == group)
end

function Scope.Account(account, realm, group)
    if realm == "all" and group == "all" then
        return account
    end
    local scoped = {}
    for key, value in pairs(account) do
        scoped[key] = value
    end
    scoped.characters, scoped.roster = {}, {}
    for id, record in pairs(account.characters) do
        if Scope.Matches(record.identity, realm, group) then
            scoped.characters[id], scoped.roster[id] = record, account.roster[id]
        end
    end
    scoped.mailTracking = RQ.Util.Copy(account.mailTracking)
    for id, transfer in pairs(scoped.mailTracking.transfers) do
        if not scoped.characters[transfer.sourceId] or not scoped.characters[transfer.recipientId] then
            scoped.mailTracking.transfers[id] = nil
        end
    end
    return scoped
end

function Scope.CraftCost(reagents, prices)
    local total, missing = 0, {}
    for item, quantity in pairs(reagents) do
        if prices[item] then
            total = total + quantity * prices[item]
        else
            missing[#missing + 1] = item
        end
    end
    table.sort(missing)
    return #missing == 0 and total or nil, missing
end
