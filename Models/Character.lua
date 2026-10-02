local Character = {}
RQ.Character = Character

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
