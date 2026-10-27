local Transfer = {
    formatVersion = 1,
    limits = { bytes = 262144, depth = 16, nodes = 20000, entries = 4096, string = 4096, characters = 200 },
}
RQ.ConfigTransfer = Transfer

-- Length-prefixed data, never Lua source. Hex strings keep chat markup/control bytes off the wire.
-- Adler-32 detects accidental corruption; it is not an authenticity/signature check.
function Transfer.Checksum(text)
    local a, b = 1, 0
    for index = 1, #text do
        a = (a + text:byte(index)) % 65521
        b = (b + a) % 65521
    end
    return string.format("%08x", b * 65536 + a)
end

local function fail(message)
    error("Configuration transfer: " .. message, 0)
end

local function bounded(run)
    local ok, value = pcall(run)
    if not ok then
        return nil, tostring(value)
    end
    return value
end

local function budget(state, depth)
    state.nodes = state.nodes + 1
    if depth > Transfer.limits.depth or state.nodes > Transfer.limits.nodes then
        fail("nesting or value limit exceeded.")
    end
end

local function serialize(value)
    local chunks, size, state, seen = {}, 0, { nodes = 0 }, {}
    local function emit(text)
        size = size + #text
        if size > Transfer.limits.bytes - 16 then
            fail("encoded size limit exceeded.")
        end
        chunks[#chunks + 1] = text
    end
    local function write(item, depth)
        budget(state, depth)
        local kind = type(item)
        if kind == "boolean" then
            emit(item and "b1" or "b0")
        elseif kind == "number" then
            if not RQ.Util.IsFinite(item) then
                fail("non-finite number.")
            end
            local text = item == 0 and "0" or string.format("%.17g", item)
            emit("n" .. #text .. ":" .. text)
        elseif kind == "string" then
            if #item > Transfer.limits.string then
                fail("string limit exceeded.")
            end
            emit("s" .. #item .. ":")
            emit((item:gsub(".", function(byte)
                return string.format("%02x", byte:byte())
            end)))
        elseif kind == "table" then
            if seen[item] or getmetatable(item) then
                fail("cyclic tables and metatables are not supported.")
            end
            seen[item] = true
            local keys = {}
            for key in pairs(item) do
                if type(key) ~= "string" and (type(key) ~= "number" or not RQ.Util.IsFinite(key)) then
                    fail("invalid table key.")
                end
                keys[#keys + 1] = key
                if #keys > Transfer.limits.entries then
                    fail("table entry limit exceeded.")
                end
            end
            table.sort(keys, function(a, b)
                if type(a) ~= type(b) then
                    return type(a) < type(b)
                end
                return a < b
            end)
            emit("t" .. #keys .. ":")
            for _, key in ipairs(keys) do
                write(key, depth + 1)
                write(item[key], depth + 1)
            end
            seen[item] = nil
        else
            fail("unsupported value type: " .. kind)
        end
    end
    write(value, 1)
    return table.concat(chunks)
end

local function parse(text)
    local position, state = 1, { nodes = 0 }
    local function length(maximum)
        local ending = text:find(":", position, true)
        if not ending or ending - position > 6 then
            fail("invalid length.")
        end
        local digits = text:sub(position, ending - 1)
        if not digits:match("^%d+$") or (#digits > 1 and digits:sub(1, 1) == "0") then
            fail("invalid length.")
        end
        local count = tonumber(digits)
        if count > maximum then
            fail("length limit exceeded.")
        end
        position = ending + 1
        return count
    end
    local function take(count)
        if position + count - 1 > #text then
            fail("truncated data.")
        end
        local value = text:sub(position, position + count - 1)
        position = position + count
        return value
    end
    local function read(depth)
        budget(state, depth)
        local tag = take(1)
        if tag == "b" then
            local value = take(1)
            if value ~= "0" and value ~= "1" then
                fail("invalid boolean.")
            end
            return value == "1"
        elseif tag == "s" then
            local hex = take(length(Transfer.limits.string) * 2)
            if hex:find("[^0-9a-f]") then
                fail("invalid string encoding.")
            end
            return (
                hex:gsub("..", function(pair)
                    return string.char(tonumber(pair, 16))
                end)
            )
        elseif tag == "n" then
            local token = take(length(32))
            local value = tonumber(token)
            if not RQ.Util.IsFinite(value) then
                fail("invalid number.")
            end
            local canonical = value == 0 and "0" or string.format("%.17g", value)
            if token ~= canonical then
                fail("noncanonical number.")
            end
            return value
        elseif tag == "t" then
            local count, result = length(Transfer.limits.entries), {}
            for _ = 1, count do
                local key = read(depth + 1)
                if type(key) ~= "string" and type(key) ~= "number" then
                    fail("invalid table key.")
                end
                if result[key] ~= nil then
                    fail("duplicate table key.")
                end
                result[key] = read(depth + 1)
            end
            return result
        end
        fail("unknown data tag.")
    end
    local result = read(1)
    if position ~= #text + 1 then
        fail("trailing data.")
    end
    return result
end

local function map(key, value)
    return { key = key, value = value }
end

local identity = {
    guid = "guid",
    displayName = "text",
    fullName = "text",
    nameComplete = "boolean",
    realm = "text",
    class = "text",
    race = "text",
    faction = "text",
    ruleset = "text",
    rulesetSource = "text",
}
local roster = RQ.Util.Copy(identity)
roster.role = "text"
for _, field in ipairs({ "enabled", "isMain", "resourceBlocker", "dungeonReady" }) do
    roster[field] = "boolean"
end
for _, field in ipairs({ "restedMultiplier", "restedRevision", "targetLead" }) do
    roster[field] = "number"
end
roster.professions = { primary = map("id", "id"), secondary = map("id", "id") }

local planning = {
    levelMilestones = map("id", "id"),
    professionMilestones = map("id", "id"),
    weights = {},
}
for key, value in pairs(RQ.DefaultPlanning) do
    if type(value) == "number" then
        planning[key] = "number"
    end
end
for key in pairs(RQ.DefaultPlanning.weights) do
    planning.weights[key] = "number"
end

local logistics = { categories = {}, cooks = map("text", "guid") }
for _, category in ipairs({ "herbs", "leather", "food", "engineering", "blacksmithing" }) do
    logistics.categories[category] = { items = map("id", "boolean"), recipients = map("id", "guid") }
end

local schema = {
    schemaVersion = "id",
    settings = {
        planning = planning,
        logistics = logistics,
        window = { point = "text", relativePoint = "text", x = "number", y = "number" },
        minimapAngle = "number",
        professionLag = {
            ceiling = "id",
            rankingEnabled = "boolean",
            rankingWeight = "number",
            ceilings = map("id", "id"),
            secondary = map("id", "boolean"),
        },
    },
    policies = { staleSnapshotHours = "number" },
    roster = map("guid", roster),
    characters = map("guid", {
        identity = identity,
        registration = "text",
        supplies = {
            needs = map("id", "number"),
            goals = map("id", { recipeId = "id", targetSkill = "id" }),
            reserves = { potions = map("id", "number"), bandages = map("id", "number") },
        },
        professionIntent = {
            focus = "text",
            planned = map("id", "boolean"),
            preferred = map("id", "boolean"),
            excluded = map("id", "boolean"),
        },
    }),
}

local function scalar(value, rule)
    if rule == "boolean" then
        return type(value) == "boolean"
    elseif rule == "number" then
        return RQ.Util.IsFinite(value)
    elseif rule == "id" then
        return RQ.SuppliesConfig.Id(value)
    elseif rule == "guid" then
        return type(value) == "string" and #value <= 128 and value:match("^Player%-[%w%-]+$") ~= nil
    elseif rule == "signature" then
        return RQ.Util.IsText(value) and #value <= 2048 and not value:gsub("[\n\r\t]", ""):find("[%c|]")
    end
    return RQ.Util.IsText(value) and #value <= 4096 and not value:find("[%c|]")
end

-- Only named configuration fields cross the boundary, even if a local record has extra data.
local function project(value, rule, strict, state, depth)
    budget(state, depth)
    if type(rule) == "string" then
        if not scalar(value, rule) then
            fail("invalid " .. rule .. " value.")
        end
        return value
    end
    if type(value) ~= "table" or getmetatable(value) then
        fail("expected a plain configuration table.")
    end
    local result, count = {}, 0
    for key, item in pairs(value) do
        count = count + 1
        if count > Transfer.limits.entries then
            fail("table entry limit exceeded.")
        end
        local child = rule.value or rule[key]
        if rule.key and not scalar(key, rule.key) then
            fail("invalid configuration identifier.")
        end
        if child then
            result[key] = project(item, child, strict, state, depth + 1)
        elseif strict then
            fail("unknown configuration field.")
        end
    end
    return result
end

local function validate(config)
    local result = project(config, schema, true, { nodes = 0 }, 1)
    if result.schemaVersion ~= RQ.schemaVersion then
        fail("unsupported database schema version.")
    end
    for _, field in ipairs({ "settings", "policies", "roster", "characters" }) do
        if not result[field] then
            fail("missing configuration section: " .. field)
        end
    end
    local count = 0
    for id, record in pairs(result.characters) do
        count = count + 1
        if count > Transfer.limits.characters then
            fail("character limit exceeded.")
        end
        if not record.identity or record.identity.guid ~= id then
            fail("character identity must match its GUID key.")
        end
        if not record.supplies or not record.professionIntent then
            fail("missing character configuration.")
        end
        local reserves, reserveError = RQ.SuppliesConfig.PrepareReserves(record.supplies.reserves)
        if not reserves then
            fail(reserveError)
        end
        record.supplies.reserves = reserves
        if
            record.registration ~= "member"
            and record.registration ~= "pending"
            and record.registration ~= "ignored"
        then
            fail("invalid registration.")
        end
        local entry = result.roster[id]
        if record.registration == "member" and not entry then
            fail("member missing roster entry.")
        end
        if
            entry
            and (record.registration == "pending" or (record.registration == "ignored" and entry.enabled ~= false))
        then
            fail("roster entry conflicts with registration.")
        end
    end
    for id, entry in pairs(result.roster) do
        if not result.characters[id] or (entry.guid and entry.guid ~= id) or entry.claimedBy then
            fail("roster identity or character reference is inconsistent.")
        end
        if entry.role and not RQ.Character.roleLabels[entry.role] then
            fail("invalid roster role.")
        end
    end
    if not RQ.LogisticsPolicies then
        fail("logistics policies must be loaded before configuration transfer.")
    end
    local policies, policyError = RQ.LogisticsPolicies.Prepare(result.settings.logistics)
    if not policies or not policies.categories then
        return fail(policyError or "Invalid logistics categories.")
    end
    for _, rule in pairs(policies.categories) do
        for _, id in ipairs(rule.recipients) do
            if not result.characters[id] then
                fail("routing recipient must reference an exported character GUID; names are never remapped.")
            end
        end
    end
    result.settings.logistics = policies
    for _, id in pairs(policies.cooks) do
        if not result.characters[id] then
            fail("Cooking/Fishing recipient must reference an exported character GUID.")
        end
    end
    return result
end

function Transfer.Extract(account)
    return bounded(function()
        return validate(project(account, schema, false, { nodes = 0 }, 1))
    end)
end

function Transfer.Encode(config)
    return bounded(function()
        local payload = serialize(validate(config))
        return "RQCFG1:" .. Transfer.Checksum(payload) .. ":" .. payload
    end)
end

function Transfer.Export(account)
    local config, err = Transfer.Extract(account)
    if not config then
        return nil, err
    end
    return Transfer.Encode(config)
end

function Transfer.MirrorKey(character)
    return bounded(function()
        return serialize(project(character, schema.characters.value, false, { nodes = 0 }, 1))
    end)
end

function Transfer.Decode(text)
    return bounded(function()
        if type(text) ~= "string" or #text > Transfer.limits.bytes then
            fail("paste must be a string of at most " .. Transfer.limits.bytes .. " bytes.")
        end
        local version, checksum, payload = text:match("^RQCFG(%d+):([0-9a-f]+):(.*)$")
        if version ~= "1" or not checksum or #checksum ~= 8 then
            fail("unsupported format or invalid header.")
        end
        if Transfer.Checksum(payload) ~= checksum then
            fail("checksum mismatch; paste the complete export.")
        end
        return validate(parse(payload))
    end)
end

function Transfer.Prepare(config, account, character, activeId)
    local checked, err = bounded(function()
        return validate(config)
    end)
    if not checked then
        return nil, nil, err
    end
    local candidate, mirror = RQ.Util.Copy(account), RQ.Util.Copy(character)
    for section, fields in pairs({ settings = schema.settings, policies = schema.policies }) do
        for key in pairs(fields) do
            candidate[section][key] = RQ.Util.Copy(checked[section][key])
        end
    end
    candidate.roster = checked.roster
    for id, values in pairs(checked.characters) do
        if not candidate.characters[id] then
            candidate.characters[id] = { identity = RQ.Util.Copy(values.identity) }
        end
    end
    for id, record in pairs(candidate.characters) do
        local values = checked.characters[id]
        record.registration = values and values.registration or "pending"
        record.supplies = values and RQ.Util.Copy(values.supplies) or { needs = {}, goals = {} }
        record.professionIntent = values and RQ.Util.Copy(values.professionIntent)
            or RQ.ProfessionConfig.PrepareIntent(nil)
    end
    local current = activeId and candidate.characters[activeId]
    if current then
        mirror.supplies = RQ.Util.Copy(current.supplies)
        mirror.professionIntent = RQ.Util.Copy(current.professionIntent)
    end
    -- Validate both complete roots, including the observations retained from the latest live state.
    return RQ.Migrations.Prepare(candidate, mirror)
end

function Transfer.Preview(before, after)
    local lines = {
        "Configuration preview (replacement, not a merge). No changes have been applied.",
        "Snapshots, inventories, recipes, rested evidence and mail ledgers are preserved.",
        "Omitted characters retain observations but become pending with empty supplies/default profession intent.",
    }
    for _, section in ipairs({
        "settings",
        "policies",
        "roster",
        "characters",
    }) do
        local added, removed, changed = 0, 0, 0
        for key, value in pairs(after[section]) do
            if before[section][key] == nil then
                added = added + 1
            elseif serialize(before[section][key]) ~= serialize(value) then
                changed = changed + 1
            end
        end
        for key in pairs(before[section]) do
            if after[section][key] == nil then
                removed = removed + 1
            end
        end
        lines[#lines + 1] = string.format("%s: %d added, %d changed, %d removed.", section, added, changed, removed)
    end
    lines[#lines + 1] = "Rollback restores configuration only, including undoing later configuration edits."
    lines[#lines + 1] = "Only the most recent import can be rolled back, until logout/reload."
    return lines
end
