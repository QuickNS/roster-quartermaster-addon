local Character = {}
RQ.Character = Character

function Character.DisplayName(identity)
    return identity.fullName or identity.displayName
end

function Character.Realm(identity)
    if not identity or not RQ.Util.IsText(identity.realm) then
        return nil
    end
    local realm = identity.realm:lower():gsub("[%s%-]", "")
    return realm ~= "" and realm or nil
end

function Character.SameRealm(first, second)
    local realm = Character.Realm(first)
    return realm ~= nil and realm == Character.Realm(second)
end

function Character.RulesetFromRealm(realm)
    if type(realm) ~= "string" then
        return nil
    end
    local text = realm:upper()
    local pvp, pve = text:find("%f[%a]PVP%f[%A]"), text:find("%f[%a]PVE%f[%A]")
    if pvp and pve then
        return nil
    elseif pvp then
        return "PVP"
    elseif pve then
        return "PVE"
    end
end

function Character.TradeGroup(identity)
    if
        identity
        and (identity.ruleset == "PVE" or identity.ruleset == "PVP")
        and (identity.faction == "Alliance" or identity.faction == "Horde")
    then
        return identity.ruleset .. ":" .. identity.faction
    end
end

function Character.TradeGroupLabel(identity)
    return Character.TradeGroup(identity) or "Unknown ruleset / faction"
end

function Character.RosterGroupKey(identity)
    identity = identity or {}
    return (Character.Realm(identity) or "~unknown")
        .. ":"
        .. (identity.ruleset or "~unknown")
        .. ":"
        .. (identity.faction or "~unknown")
end

function Character.CanTrade(first, second)
    local group = Character.TradeGroup(first)
    return group ~= nil and group == Character.TradeGroup(second) and Character.SameRealm(first, second)
end

Character.roles = { "UNASSIGNED", "TANK", "HEALER", "DPS", "HEALER_DPS", "FLEX" }
Character.roleLabels = {
    UNASSIGNED = "Unassigned",
    TANK = "Tank",
    HEALER = "Healer",
    DPS = "DPS",
    HEALER_DPS = "Healer / DPS",
    FLEX = "Flexible",
}

function Character.FallbackId(identity)
    if not RQ.Util.IsText(identity.displayName) or not RQ.Util.IsText(identity.realm) then
        return nil
    end
    local name = identity.displayName:lower():gsub("^%s+", ""):gsub("%s+$", "")
    local realm = identity.realm:lower():gsub("%s+", "")
    return "name:" .. name .. "-" .. realm
end

function Character.Id(identity, previous)
    if RQ.Util.IsText(identity.guid) then
        return identity.guid
    end
    local fallback = Character.FallbackId(identity)
    if fallback and previous and RQ.Util.IsText(previous.guid) and fallback == Character.FallbackId(previous) then
        return previous.guid
    end
    return fallback
end
