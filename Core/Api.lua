local Api = {}
RQ.Api = Api

local capabilities = {}

local function lookup(name)
    local value = _G
    for part in name:gmatch("[^.]+") do
        if type(value) ~= "table" then
            return nil
        end
        value = value[part]
    end
    return value
end

local function call(name, ...)
    local fn = lookup(name)
    if type(fn) ~= "function" then
        capabilities[name] = "missing"
        return nil
    end

    local result = { pcall(fn, ...) }
    if not result[1] then
        capabilities[name] = "error: " .. tostring(result[2]):sub(1, 160)
        return nil
    end
    if type(_G.issecretvalue) == "function" then
        for index, value in pairs(result) do
            if index ~= 1 then
                local ok, secret = pcall(_G.issecretvalue, value)
                if not ok or secret then
                    capabilities[name] = "restricted value"
                    return nil
                end
            end
        end
    end
    capabilities[name] = "available"
    return result
end

local function scalar(name, expectedType, ...)
    local result = call(name, ...)
    if not result then
        return nil
    end
    local value = result[2]
    if type(value) ~= expectedType then
        capabilities[name] = "unexpected return type"
        return nil
    end
    if expectedType == "number" and (value ~= value or value < 0 or value == math.huge) then
        capabilities[name] = "invalid numeric value"
        return nil
    end
    return value
end

function Api.GetBuildInfo()
    local result = call("GetBuildInfo")
    if not result then
        return {}
    end
    if type(result[2]) ~= "string" or type(result[5]) ~= "number" then
        capabilities.GetBuildInfo = "unexpected return type"
        return {}
    end
    return {
        version = result[2],
        build = result[3],
        date = result[4],
        interface = result[5],
    }
end

function Api.GetClientProject()
    local value = _G.WOW_PROJECT_ID
    if type(_G.issecretvalue) == "function" then
        local ok, secret = pcall(_G.issecretvalue, value)
        if not ok or secret then
            capabilities.WOW_PROJECT_ID = "restricted value"
            return nil
        end
    end
    if type(value) ~= "number" then
        capabilities.WOW_PROJECT_ID = "missing or unexpected type"
        return nil
    end
    capabilities.WOW_PROJECT_ID = "available"
    return value
end

local function hasForeverNameParts()
    local build = Api.GetBuildInfo()
    return build.interface == 16001 and build.version:match("^1%.60%.") ~= nil,
        build.version ~= nil and build.interface ~= nil
end

function Api.GetCharacterIdentity()
    local function identityText(name, ...)
        local value = scalar(name, "string", ...)
        if value ~= nil and not RQ.Util.IsText(value) then
            capabilities[name] = "empty identity value"
            return nil
        end
        return value
    end
    local identity = {
        guid = identityText("UnitGUID", "player"),
        realm = identityText("GetRealmName"),
    }
    local faction = identityText("UnitFactionGroup", "player")
    if faction == "Alliance" or faction == "Horde" or faction == "Neutral" then
        identity.faction = faction
    elseif faction then
        capabilities.UnitFactionGroup = "unrecognized faction; no new observation"
    end
    identity.ruleset = RQ.Character.RulesetFromRealm(identity.realm)
    identity.rulesetSource = identity.ruleset and "realm-name" or nil
    local splitName, knownBuild = hasForeverNameParts()
    local preferredFirst
    for _, apiName in ipairs({ "UnitNameUnmodified", "UnitName", "UnitFullName" }) do
        local result = call(apiName, "player")
        if result and RQ.Util.IsText(result[2]) then
            local first = result[2]:match("^%s*(.-)%s*$")
            local second = RQ.Util.IsText(result[3]) and result[3]:match("^%s*(.-)%s*$") or nil
            local sameName = not preferredFirst
                or first == preferredFirst
                or first:sub(1, #preferredFirst + 1) == preferredFirst .. " "
            -- Forever 1.60 returns first name and surname; the realm has its own API.
            if splitName and second and identity.realm and not first:find("%s") then
                local normalizedRealm = identity.realm:lower():gsub("[%s%-]", "")
                if second:lower():gsub("[%s%-]", "") ~= normalizedRealm then
                    first = first .. " " .. second
                end
            end
            if sameName then
                identity.displayName = first
                identity.nameComplete = knownBuild and (not splitName or first:find("%s") ~= nil)
                if identity.nameComplete then
                    break
                end
                preferredFirst = preferredFirst or first
            end
        elseif result then
            capabilities[apiName] = "empty identity value"
        end
    end
    local class = call("UnitClass", "player")
    if class and RQ.Util.IsText(class[3]) then
        identity.class = class[3]
    elseif class then
        capabilities.UnitClass = "unexpected return type"
    end

    local race = call("UnitRace", "player")
    if race and RQ.Util.IsText(race[2]) then
        identity.race = race[2]
    elseif race then
        capabilities.UnitRace = "unexpected return type"
    end
    return identity
end

function Api.GetNameEvidence()
    local lines = {
        hasForeverNameParts() and "Name handling: Forever first name + surname; realm from GetRealmName."
            or "Name handling: standard name/realm returns.",
    }
    for _, name in ipairs({ "UnitName", "UnitNameUnmodified", "UnitFullName" }) do
        local result = call(name, "player")
        lines[#lines + 1] = name
            .. ": "
            .. (result and tostring(result[2]) or "unavailable")
            .. "; second return: "
            .. (result and tostring(result[3]) or "unavailable")
    end
    return lines
end

function Api.GetCharacterProgression()
    return {
        level = scalar("UnitLevel", "number", "player"),
        xp = scalar("UnitXP", "number", "player"),
        xpMax = scalar("UnitXPMax", "number", "player"),
    }
end

function Api.GetRestedXP()
    local result = call("GetXPExhaustion")
    if not result then
        return nil
    end
    -- The candidate WoW API uses nil for no rested XP, not for a missing API.
    if result[2] == nil then
        return 0
    end
    local value = result[2]
    if type(value) ~= "number" or value ~= value or value < 0 or value == math.huge then
        capabilities.GetXPExhaustion = "invalid numeric value"
        return nil
    end
    return value
end

function Api.IsResting()
    return scalar("IsResting", "boolean")
end

function Api.GetServerTime()
    return scalar("GetServerTime", "number")
end

function Api.GetMoney()
    local value = scalar("GetMoney", "number")
    if value ~= nil and (not RQ.Util.IsNumber(value) or value % 1 ~= 0) then
        capabilities.GetMoney = "invalid integer copper amount"
        return nil
    end
    return value
end

function Api.GetLocation()
    return {
        zone = scalar("GetZoneText", "string"),
        subZone = scalar("GetSubZoneText", "string"),
    }
end

function Api.GetBagCapacity()
    local constant = _G.NUM_TOTAL_EQUIPPED_BAG_SLOTS ~= nil and "NUM_TOTAL_EQUIPPED_BAG_SLOTS" or "NUM_BAG_SLOTS"
    local count = _G[constant]
    if type(_G.issecretvalue) == "function" then
        local ok, secret = pcall(_G.issecretvalue, count)
        if not ok or secret then
            capabilities[constant] = "restricted value"
            return nil
        end
    end
    if not RQ.Util.IsNumber(count) or count > 20 or count % 1 ~= 0 then
        capabilities[constant] = "missing or invalid bag count"
        return nil
    end
    capabilities[constant] = "available"
    local slotsApi = type(lookup("C_Container.GetContainerNumSlots")) == "function"
            and "C_Container.GetContainerNumSlots"
        or "GetContainerNumSlots"
    local freeApi = type(lookup("C_Container.GetContainerNumFreeSlots")) == "function"
            and "C_Container.GetContainerNumFreeSlots"
        or "GetContainerNumFreeSlots"
    local capacity = { bagSlots = 0, freeBagSlots = 0 }
    for bag = 0, count do
        local slots = scalar(slotsApi, "number", bag)
        if slots == nil then
            return nil
        end
        local free = slots == 0 and 0 or scalar(freeApi, "number", bag)
        if free == nil then
            return nil
        end
        if free > slots or free % 1 ~= 0 or slots % 1 ~= 0 then
            capabilities[freeApi] = "invalid bag capacity"
            return nil
        end
        capacity.bagSlots = capacity.bagSlots + slots
        capacity.freeBagSlots = capacity.freeBagSlots + free
    end
    return capacity
end

function Api.GetProfessions()
    local indices = call("GetProfessions")
    if not indices then
        return nil
    end
    local professions = {}
    -- GetProfessions may contain nil holes between its six profession slots.
    for slot = 2, 7 do
        local index = indices[slot]
        if index ~= nil then
            if not RQ.Util.IsNumber(index) or index % 1 ~= 0 then
                capabilities.GetProfessions = "invalid profession index"
                return nil
            end
            local info = call("GetProfessionInfo", index)
            if not info then
                return nil
            end
            local id, name, skill, maxSkill = info[8], info[2], info[4], info[5]
            if
                not RQ.Util.IsNumber(id)
                or id == 0
                or id % 1 ~= 0
                or not RQ.Util.IsText(name)
                or not RQ.Util.IsNumber(skill)
                or not RQ.Util.IsNumber(maxSkill)
                or skill > maxSkill
                or professions[id] ~= nil
            then
                capabilities.GetProfessionInfo = "invalid profession data or missing skill-line ID"
                return nil
            end
            professions[id] = {
                name = name,
                skill = skill,
                maxSkill = maxSkill,
                kind = slot <= 3 and "primary" or "secondary",
            }
        end
    end
    return professions
end

local function publicData(value, depth)
    if type(_G.issecretvalue) == "function" then
        local ok, secret = pcall(_G.issecretvalue, value)
        if not ok or secret then
            return false
        end
    end
    if type(value) ~= "table" then
        return true
    end
    if depth > 8 then
        return false
    end
    for key, child in pairs(value) do
        if not publicData(key, depth + 1) or not publicData(child, depth + 1) then
            return false
        end
    end
    return true
end

local function dataCall(name, ...)
    local result = call(name, ...)
    if not result then
        return nil, name .. ": " .. capabilities[name]
    end

    if not publicData(result, 0) then
        capabilities[name] = "restricted or unsupported nested data"
        return nil, name .. ": " .. capabilities[name]
    end
    return result
end

function Api.GetAuctionPrice(itemId, identity)
    local current = RQ.Database.Current()
    if not current or not RQ.Character.CanTrade(current.identity, identity) then
        return nil, "Prices unavailable for a different or unknown realm/faction market."
    end
    local values, err = dataCall("Auctionator.API.v1.GetAuctionPriceByItemID", "RosterQuartermaster", itemId)
    if not values then
        return nil, "Auctionator price API unavailable: " .. tostring(err)
    end
    local price = values[2]
    if price == nil then
        return nil, "Auctionator has no cached price for item " .. itemId .. "."
    end
    if not RQ.Util.IsNumber(price) or price % 1 ~= 0 or price <= 0 then
        capabilities.auctionatorPrices = "invalid price; cost unavailable"
        return nil, "Auctionator returned an invalid unit price."
    end
    capabilities.auctionatorPrices = "available: cached copper/unit"
    return price
end

local requestedItemNames, resolvedItemNames, resolvedItemIcons = {}, {}, {}
local bankOpen = false

function Api.IsBankSessionOpen()
    return bankOpen
end

local function requestItemName(id)
    if not requestedItemNames[id] then
        requestedItemNames[id] = true
        call("C_Item.RequestLoadItemDataByID", id)
    end
end

local function fullItemInfo(id)
    for _, apiName in ipairs({ "C_Item.GetItemInfo", "GetItemInfo" }) do
        local result = dataCall(apiName, id)
        if result and RQ.Util.IsText(result[2]) then
            return result
        end
    end
end

function Api.GetItemName(id)
    if not RQ.SuppliesConfig.Id(id) then
        capabilities.itemName = "invalid item ID"
        return nil
    end
    if resolvedItemNames[id] then
        return resolvedItemNames[id]
    end
    local info = fullItemInfo(id)
    if info then
        resolvedItemNames[id] = info[2]
        return info[2]
    end
    requestItemName(id)
end

function Api.GetItemIcon(id)
    if not RQ.SuppliesConfig.Id(id) then
        capabilities.itemIcon = "invalid item ID"
        return nil
    end
    if resolvedItemIcons[id] then
        capabilities.itemIcon = "available"
        return resolvedItemIcons[id]
    end
    local info = dataCall("C_Item.GetItemInfoInstant", id)
    local icon = info and info[6]
    if not RQ.SuppliesConfig.Id(icon) and not RQ.Util.IsText(icon) then
        info = fullItemInfo(id)
        icon = info and info[11]
    end
    if RQ.SuppliesConfig.Id(icon) or RQ.Util.IsText(icon) then
        capabilities.itemIcon = "available"
        resolvedItemIcons[id] = icon
        return icon
    end
    capabilities.itemIcon = "unavailable; item text retained"
end

local function bagCapacity(itemId)
    local item = dataCall("C_Item.GetItemInfoInstant", itemId)
    if not item or item[7] ~= 1 or item[8] ~= 0 then
        return nil
    end
    local tooltip = dataCall("C_TooltipInfo.GetItemByID", itemId)
    tooltip = tooltip and tooltip[2]
    if type(tooltip) ~= "table" or type(tooltip.lines) ~= "table" then
        return nil
    end
    for _, key in ipairs({ "CONTAINER_SLOTS", "NUM_SLOTS" }) do
        local format = lookup(key)
        if publicData(format, 0) and type(format) == "string" then
            local before, after = format:match("^(.-)%%d(.-)$")
            if before then
                local function escape(text)
                    return (text:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", ".-"))
                end
                local pattern = "^" .. escape(before) .. "(%d+)" .. escape(after) .. "$"
                for _, line in pairs(tooltip.lines) do
                    if type(line) == "table" and type(line.leftText) == "string" then
                        local text = line.leftText:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                        local capacity = tonumber(text:match(pattern))
                        if RQ.SuppliesConfig.Id(capacity) and capacity <= 100 then
                            return capacity
                        end
                    end
                end
            end
        end
    end
    capabilities.bagCapacity = "unavailable: no supported localized slot-count line; capacity remains unknown"
end

local function bagNeedsUnlocking(bag, slot)
    local labels = {}
    for _, key in ipairs({ "LOCKED", "ITEM_LOCKED" }) do
        local label = lookup(key)
        if publicData(label, 0) and RQ.Util.IsText(label) then
            labels[label] = true
        end
    end
    if not next(labels) then
        capabilities.lockedContainerTooltip = "unavailable: localized locked-item label missing"
        return nil
    end
    local data, err = dataCall("C_TooltipInfo.GetBagItem", bag, slot)
    local tooltip = data and data[2]
    if type(tooltip) ~= "table" or type(tooltip.lines) ~= "table" then
        capabilities.lockedContainerTooltip = err or "unavailable: bag-item tooltip not ready"
        return nil
    end
    capabilities.lockedContainerTooltip = "available"
    for index, line in pairs(tooltip.lines) do
        if index ~= 1 and type(line) == "table" and type(line.leftText) == "string" then
            local text = line.leftText:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^%s*(.-)%s*$")
            if labels[text] then
                return true
            end
        end
    end
    return false
end

local function scanContainers(ids, regular, includeSlots, bank)
    local now = Api.GetServerTime()
    if not now or now == 0 then
        return nil, "Bag scan timestamp unavailable."
    end
    local scan = {
        complete = true,
        scannedAt = now,
        items = {},
        tradable = {},
        details = {},
        equipped = {},
        lockedContainers = {},
    }
    if includeSlots then
        scan.locations = {}
    end
    if bank then
        scan.containers, scan.coherent, scan.attemptedAt = {}, true, now
    end
    for _, bag in ipairs(ids) do
        local slots = scalar("C_Container.GetContainerNumSlots", "number", bag)
        if
            not RQ.SuppliesConfig.Count(slots)
            or slots > (bank and 1000 or 100)
            or ((bag == 0 or bank) and slots == 0)
        then
            return nil, "Container slots unavailable; previous inventory retained."
        end
        if bank then
            scan.containers[bag] = { capacity = slots, items = {} }
        end
        if regular and bag > 0 and bag <= regular then
            scan.equipped[bag] = slots
        end
        for slot = 1, slots do
            local result, err = dataCall("C_Container.GetContainerItemInfo", bag, slot)
            if not result then
                return nil, err
            end
            local info = result[2]
            if info ~= nil then
                if
                    type(info) ~= "table"
                    or not RQ.SuppliesConfig.Id(info.itemID)
                    or not RQ.SuppliesConfig.Count(info.stackCount)
                    or info.stackCount == 0
                then
                    return nil, "Invalid item data; previous inventory retained."
                end
                local id = info.itemID
                scan.items[id] = (scan.items[id] or 0) + info.stackCount
                if bank then
                    local items = scan.containers[bag].items
                    items[id] = (items[id] or 0) + info.stackCount
                end
                if info.isBound == false and info.isLocked == false then
                    scan.tradable[id] = (scan.tradable[id] or 0) + info.stackCount
                    local needsUnlocking = not bank and bagNeedsUnlocking(bag, slot)
                    if needsUnlocking then
                        scan.lockedContainers[id] = (scan.lockedContainers[id] or 0) + info.stackCount
                    end
                    if includeSlots then
                        scan.locations[#scan.locations + 1] = {
                            bag = bag,
                            slot = slot,
                            itemId = id,
                            count = info.stackCount,
                            needsUnlocking = needsUnlocking,
                        }
                    end
                end
                local detail = scan.details[id] or {}
                if RQ.Util.IsText(info.itemName) then
                    detail.name = info.itemName
                end
                if not detail.name and type(info.hyperlink) == "string" then
                    local linkId, label = info.hyperlink:match("|Hitem:(%d+)[^|]*|h%[(.-)%]|h")
                    if tonumber(linkId) == id and RQ.Util.IsText(label) then
                        detail.name = label
                    end
                end
                local item = dataCall("C_Item.GetItemInfoInstant", id)
                if item and RQ.SuppliesConfig.Count(item[7]) and RQ.SuppliesConfig.Count(item[8]) then
                    detail.classId, detail.subclassId = item[7], item[8]
                end
                if detail.classId == 1 and detail.subclassId == 0 then
                    detail.bagSlots = bagCapacity(id)
                end
                if RQ.SuppliesConfig.Count(info.quality) then
                    detail.quality = info.quality
                end
                local greenEquipment = detail.quality == 2 and (detail.classId == 2 or detail.classId == 4)
                if not detail.name or greenEquipment then
                    local full = fullItemInfo(id)
                    if not detail.name and full then
                        detail.name = full[2]
                    end
                    if full and RQ.SuppliesConfig.Count(full[15]) then
                        detail.bindType = full[15]
                    end
                end
                if not detail.name then
                    requestItemName(id)
                end
                scan.details[id] = detail
            end
        end
    end
    return scan
end

function Api.GetBagItems(includeSlots)
    local count = _G.NUM_TOTAL_EQUIPPED_BAG_SLOTS or _G.NUM_BAG_SLOTS
    if not publicData(count, 0) or not RQ.SuppliesConfig.Count(count) or count > 20 then
        return nil, "Equipped bag count unavailable."
    end
    local regular = _G.NUM_BAG_SLOTS
    if not publicData(regular, 0) or not RQ.SuppliesConfig.Count(regular) or regular > count then
        regular = nil
    end
    local ids = {}
    for id = 0, count do
        ids[#ids + 1] = id
    end
    return scanContainers(ids, regular, includeSlots)
end

local function dataArray(value, maximum)
    if type(value) ~= "table" or #value > maximum then
        return false
    end
    local count = 0
    for key in pairs(value) do
        if not RQ.SuppliesConfig.Id(key) or key > #value then
            return false
        end
        count = count + 1
    end
    return count == #value
end

local function personalBankIds()
    if not bankOpen then
        return nil, "Personal bank is closed."
    end
    local kind, indices = lookup("Enum.BankType.Character"), lookup("Enum.BagIndex")
    if
        not publicData(kind, 0)
        or not RQ.SuppliesConfig.Count(kind)
        or not publicData(indices, 0)
        or type(indices) ~= "table"
    then
        return nil, "Personal-bank enum contract unavailable; no bank indices guessed."
    end
    if scalar("C_Bank.CanUseBank", "boolean", kind) ~= true then
        return nil, "Personal bank is not accessible."
    end
    local result = dataCall("C_Bank.FetchPurchasedBankTabIDs", kind)
    local ids = result and result[2]
    local count = scalar("C_Bank.FetchNumPurchasedBankTabs", "number", kind)
    if not dataArray(ids, 20) or not RQ.SuppliesConfig.Count(count) or count ~= #ids then
        return nil, "Personal-bank tab list is incomplete or unavailable."
    end
    local allowed, seen = {}, {}
    for name, id in pairs(indices) do
        if type(name) == "string" and name:match("^CharacterBankTab_%d+$") and RQ.SuppliesConfig.Id(id) then
            allowed[id] = true
        end
    end
    local carried = _G.NUM_TOTAL_EQUIPPED_BAG_SLOTS or _G.NUM_BAG_SLOTS
    if not publicData(carried, 0) or not RQ.SuppliesConfig.Count(carried) or not next(allowed) then
        return nil, "Bank and carried-container ranges cannot be verified."
    end
    for _, id in ipairs(ids) do
        if not allowed[id] or id <= carried or seen[id] then
            return nil, "Unexpected or duplicate personal-bank tab; scan rejected."
        end
        seen[id] = true
    end
    local sorted = RQ.Util.Copy(ids)
    table.sort(sorted)
    return sorted
end

local function equalData(first, second)
    if type(first) ~= type(second) then
        return false
    end
    if type(first) ~= "table" then
        return first == second
    end
    for key, value in pairs(first) do
        if not equalData(value, second[key]) then
            return false
        end
    end
    for key in pairs(second) do
        if first[key] == nil then
            return false
        end
    end
    return true
end

function Api.GetBankInventory(characterId)
    local function readPair()
        if not characterId or scalar("UnitGUID", "string", "player") ~= characterId then
            return nil, "Bank scan requires the verified active character GUID."
        end
        local ids, err = personalBankIds()
        if not ids then
            return nil, err
        end
        local bags
        bags, err = Api.GetBagItems()
        if not bags then
            return nil, err
        end
        local bank
        bank, err = scanContainers(ids, nil, false, true)
        if not bank then
            return nil, err
        end
        return { bags = bags, bank = bank, ids = ids }
    end
    local first, err = readPair()
    if not first then
        capabilities.bankInventory = err
        return nil, err
    end
    local second
    second, err = readPair()
    if second then
        local lastIds = personalBankIds()
        if
            not lastIds
            or not equalData(lastIds, second.ids)
            or not equalData(first.ids, second.ids)
            or scalar("UnitGUID", "string", "player") ~= characterId
        then
            err = "Bank access or tab layout changed during scan."
        else
            for _, key in ipairs({ "items", "tradable", "equipped", "lockedContainers", "containers" }) do
                if
                    not equalData(first.bags[key], second.bags[key])
                    or not equalData(first.bank[key], second.bank[key])
                then
                    err = "Bag/bank contents changed during scan; retry while the bank is open."
                end
            end
        end
    end
    if err then
        capabilities.bankInventory = err
        return nil, err
    end
    capabilities.bankInventory = "available: coherent personal-bank and carried snapshot"
    return { bags = second.bags, bank = second.bank }
end
function Api.GetProfessionRecipes()
    if
        scalar("C_TradeSkillUI.IsTradeSkillReady", "boolean") ~= true
        or scalar("C_TradeSkillUI.IsTradeSkillLinked", "boolean") ~= false
        or scalar("C_TradeSkillUI.IsTradeSkillGuild", "boolean") ~= false
        or scalar("C_TradeSkillUI.IsTradeSkillGuildMember", "boolean") ~= false
    then
        return nil, "Open your own ready profession window; linked/guild recipes are not recorded as yours."
    end
    local base, err = dataCall("C_TradeSkillUI.GetBaseProfessionInfo")
    if not base then
        return nil, err
    end
    base = base[2]
    if
        type(base) ~= "table"
        or not RQ.SuppliesConfig.Id(base.professionID)
        or not RQ.Util.IsText(base.professionName)
    then
        return nil, "Profession identity unavailable."
    end
    local ids
    ids, err = dataCall("C_TradeSkillUI.GetAllRecipeIDs")
    if not ids then
        return nil, err
    end
    ids = ids[2]
    if not dataArray(ids, 10000) then
        return nil, "Recipe list unavailable or too large."
    end
    local now = Api.GetServerTime()
    if not now or now == 0 then
        return nil, "Recipe scan timestamp unavailable."
    end
    local scan = { name = base.professionName, complete = true, scannedAt = now, recipes = {} }
    for _, id in ipairs(ids) do
        if not RQ.SuppliesConfig.Id(id) then
            return nil, "Invalid recipe ID."
        end
        local info
        info, err = dataCall("C_TradeSkillUI.GetRecipeInfo", id)
        if not info then
            return nil, err
        end
        info = info[2]
        if type(info) ~= "table" or not RQ.Util.IsText(info.name) or type(info.learned) ~= "boolean" then
            return nil, "Recipe data is still loading; previous recipes retained."
        end
        local recipe = {
            name = info.name,
            learned = info.learned,
            reagents = {},
            reagentsComplete = false,
            skillUps = RQ.SuppliesConfig.Count(info.numSkillUps) and info.numSkillUps or 1,
        }
        if RQ.SuppliesConfig.Count(info.relativeDifficulty) and info.relativeDifficulty <= 3 then
            recipe.difficulty = info.relativeDifficulty
        end
        local source = scalar("C_TradeSkillUI.GetRecipeSourceText", "string", id)
        recipe.source = source
        if source then
            local found, ambiguous
            for rawId in source:gmatch("|Hitem:(%d+)") do
                local itemId = tonumber(rawId)
                if itemId and RQ.SuppliesConfig.Id(itemId) then
                    local item = dataCall("C_Item.GetItemInfoInstant", itemId)
                    if item and item[7] == 9 then
                        if found and found ~= itemId then
                            ambiguous = true
                        end
                        found = itemId
                    end
                end
            end
            if not ambiguous then
                recipe.sourceItem = found
            end
        end
        local schematic = dataCall("C_TradeSkillUI.GetRecipeSchematic", id, false)
        schematic = schematic and schematic[2]
        if
            type(schematic) == "table"
            and RQ.SuppliesConfig.Id(schematic.outputItemID)
            and RQ.SuppliesConfig.Id(schematic.quantityMin)
            and schematic.quantityMin == schematic.quantityMax
        then
            recipe.outputItemId = schematic.outputItemID
            recipe.outputCount = schematic.quantityMin
            recipe.bagSlots = bagCapacity(recipe.outputItemId)
            if recipe.bagSlots then
                local output = fullItemInfo(recipe.outputItemId)
                if output and RQ.SuppliesConfig.Count(output[15]) then
                    recipe.outputBindType = output[15]
                end
            end
        end
        if type(schematic) == "table" and dataArray(schematic.reagentSlotSchematics, 100) then
            recipe.reagentsComplete = true
            for _, reagentSlot in ipairs(schematic.reagentSlotSchematics) do
                if type(reagentSlot) ~= "table" or type(reagentSlot.required) ~= "boolean" then
                    recipe.reagentsComplete = false
                elseif reagentSlot.required then
                    local reagents = reagentSlot.reagents
                    if
                        not dataArray(reagents, 100)
                        or #reagents ~= 1
                        or type(reagents[1]) ~= "table"
                        or not RQ.SuppliesConfig.Id(reagents[1].itemID)
                        or not RQ.SuppliesConfig.Count(reagentSlot.quantityRequired)
                    then
                        recipe.reagentsComplete = false
                    else
                        local item = reagents[1].itemID
                        recipe.reagents[item] = (recipe.reagents[item] or 0) + reagentSlot.quantityRequired
                    end
                end
            end
        end
        scan.recipes[id] = recipe
    end
    return { professionId = base.professionID, scan = scan }
end

function Api.After(seconds, callback)
    return call("C_Timer.After", seconds, callback) ~= nil
end

function Api.IsInCombat()
    return scalar("InCombatLockdown", "boolean")
end

local registrationFrame

function Api.HideRegistrationPrompt()
    if registrationFrame then
        registrationFrame:Hide()
    end
end

function Api.ShowRegistrationPrompt(title, choices)
    if Api.IsInCombat() ~= false then
        return false
    end
    local ok, err = pcall(function()
        if not registrationFrame then
            local created = call("CreateFrame", "Frame", nil, _G.UIParent)
            if not created or not created[2] then
                error("CreateFrame unavailable")
            end
            local frame = created[2]
            frame:Hide()
            frame:SetPoint("CENTER")
            frame:SetFrameStrata("DIALOG")
            frame:EnableMouse(true)
            local background = frame:CreateTexture(nil, "BACKGROUND")
            background:SetAllPoints()
            background:SetColorTexture(0.05, 0.05, 0.05, 0.95)
            frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            frame.title:SetPoint("TOPLEFT", 16, -16)
            frame.title:SetWidth(328)
            frame.buttons = {}
            registrationFrame = frame
        end
        local frame = registrationFrame
        frame:SetSize(360, 104 + #choices * 28)
        frame.title:SetText(title)
        for _, button in ipairs(frame.buttons) do
            button:Hide()
        end
        for index, choice in ipairs(choices) do
            local button = frame.buttons[index]
            if not button then
                local created = call("CreateFrame", "Button", nil, frame, "UIPanelButtonTemplate")
                if not created or not created[2] then
                    error("Button creation unavailable")
                end
                button = created[2]
                button:SetSize(328, 24)
                button:SetPoint("TOPLEFT", 16, -64 - (index - 1) * 28)
                frame.buttons[index] = button
            end
            button:SetText(choice.label)
            button:SetScript("OnClick", function()
                if choice.run() then
                    Api.HideRegistrationPrompt()
                end
            end)
            button:Show()
        end
        frame:Show()
    end)
    if not ok then
        capabilities.registrationPrompt = "error: " .. tostring(err):sub(1, 160)
        Api.HideRegistrationPrompt()
        Api.Print("Registration window unavailable; use /rq add or /rq ignore.")
        return false
    end
    capabilities.registrationPrompt = "available"
    return true
end

function Api.Print(message)
    local text = "RQ: " .. message
    if _G.DEFAULT_CHAT_FRAME and type(_G.DEFAULT_CHAT_FRAME.AddMessage) == "function" then
        local ok, err = pcall(_G.DEFAULT_CHAT_FRAME.AddMessage, _G.DEFAULT_CHAT_FRAME, text)
        if ok then
            capabilities.chat = "available"
            return
        end
        capabilities.chat = "error: " .. tostring(err):sub(1, 160)
    else
        capabilities.chat = "missing"
    end
    call("print", text)
end

function Api.RegisterSlashCommand(handler)
    if type(_G.SlashCmdList) ~= "table" then
        capabilities.SlashCmdList = "missing"
        Api.Print("Cannot register /rq: SlashCmdList is unavailable.")
        return false
    end
    _G.SLASH_ROSTERQUARTERMASTER1 = "/rq"
    _G.SlashCmdList.ROSTERQUARTERMASTER = handler
    capabilities.SlashCmdList = "available"
    return true
end

function Api.Subscribe(events, handler)
    local result = call("CreateFrame", "Frame")
    if not result or not result[2] then
        Api.Print("Cannot subscribe to events: CreateFrame is unavailable.")
        return nil
    end
    local frame = result[2]
    local ok, err = pcall(function()
        frame:SetScript("OnEvent", function(_, event, ...)
            handler(event, ...)
        end)
    end)
    if not ok then
        capabilities.OnEvent = "error: " .. tostring(err):sub(1, 160)
        Api.Print("Cannot install event handler; see /rq diag.")
        return nil
    end
    for _, event in ipairs(events) do
        local registered, reason = pcall(function()
            frame:RegisterEvent(event)
        end)
        capabilities["event:" .. event] = registered and "registered (not yet observed)"
            or "error: " .. tostring(reason):sub(1, 160)
        if not registered then
            Api.Print("Event " .. event .. " unavailable; see /rq diag.")
        end
    end
    return frame
end

local mailboxOpen = false

function Api.IsMailboxOpen()
    if not mailboxOpen or not _G.MailFrame then
        return false
    end
    local ok, shown = pcall(function()
        return _G.MailFrame:IsShown()
    end)
    if not ok then
        capabilities.mailboxFrame = "error: " .. tostring(shown):sub(1, 160)
        return false
    end
    return shown == true
end

function Api.MarkEventObserved(event)
    capabilities["event:" .. event] = "observed"
    if event == "MAIL_SHOW" then
        mailboxOpen = true
    elseif event == "MAIL_CLOSED" or event == "PLAYER_LOGOUT" then
        mailboxOpen = false
    end
    if event == "BANKFRAME_OPENED" then
        bankOpen = true
    elseif event == "BANKFRAME_CLOSED" or event == "PLAYER_LOGOUT" or event == "PLAYER_LOGIN" then
        bankOpen = false
    end
end

function Api.GetCapabilities()
    local copy = {}
    for key, value in pairs(capabilities) do
        copy[key] = value
    end
    return copy
end

local dashboard
local dashboardFailure
local minimapButton
local minimapFailure

local function uiOperation(name, operation)
    local ok, err = pcall(operation)
    if not ok then
        local message = tostring(err):sub(1, 200)
        capabilities[name] = "error: " .. message
        return false, message
    end
    capabilities[name] = "available"
    return true
end

function Api.GetMailDraft()
    if not Api.IsMailboxOpen() then
        return nil, "Open the mailbox first."
    end
    local draft = { items = {}, slots = {}, free = {}, counts = {} }
    local ok, err = uiOperation("mailDraft", function()
        local limit = _G.ATTACHMENTS_MAX_SEND
        if not publicData(limit, 0) or not RQ.SuppliesConfig.Id(limit) or limit > 100 then
            error("Mail attachment limit unavailable.")
        end
        if not _G.SendMailNameEditBox then
            error("Send Mail recipient field unavailable; open the Send Mail tab.")
        end
        draft.recipient = _G.SendMailNameEditBox:GetText()
        if not publicData(draft.recipient, 0) or type(draft.recipient) ~= "string" then
            error("Mail recipient is unavailable.")
        end
        for slot = 1, limit do
            local info, reason = dataCall("GetSendMailItem", slot)
            if not info then
                error(reason)
            end
            if info[2] == nil and info[3] == nil then
                draft.free[#draft.free + 1] = slot
            else
                if not RQ.SuppliesConfig.Id(info[3]) or not RQ.SuppliesConfig.Id(info[5]) then
                    error("Attachment data is still loading; review the Send Mail tab.")
                end
                local item = { itemId = info[3], count = info[5] }
                item.name = RQ.Util.IsText(info[2]) and info[2] or nil
                draft.slots[slot] = item
                draft.items[#draft.items + 1] = item
                draft.counts[item.itemId] = (draft.counts[item.itemId] or 0) + item.count
            end
        end
    end)
    if not ok then
        return nil, err
    end
    return draft
end

function Api.MailBuildKey()
    local build = Api.GetBuildInfo()
    if type(build.version) ~= "string" or type(build.build) ~= "string" or type(build.interface) ~= "number" then
        return nil
    end
    return build.version .. "/" .. build.build .. "/" .. build.interface
end

function Api.GetInboxHeader(index)
    local values, err = dataCall("GetInboxHeaderInfo", index)
    if not values then
        return nil, err
    end

    if
        not RQ.Util.IsText(values[4])
        or type(values[5]) ~= "string"
        or #values[5] > 512
        or not RQ.Util.IsNumber(values[7])
        or not RQ.Util.IsNumber(values[8])
        or (values[9] ~= nil and not RQ.SuppliesConfig.Count(values[9]))
        or (values[11] ~= nil and type(values[11]) ~= "boolean")
    then
        return nil, "Inbox header contract is unavailable or still loading."
    end
    return {
        sender = values[4],
        subject = values[5],
        cod = values[7],
        daysLeft = values[8],
        returned = values[11] == true,
        attachmentCount = values[9] or 0,
        items = {},
    }
end

function Api.CanObserveInbox()
    for _, name in ipairs({ "GetInboxNumItems", "GetInboxHeaderInfo", "GetInboxItem", "C_Mail.IsCommandPending" }) do
        if type(lookup(name)) ~= "function" then
            capabilities.inboxInventory = "missing " .. name .. "; bag-only assistance remains available"
            return false
        end
    end
    return true
end

local function readInbox(characterId)
    if not Api.IsMailboxOpen() or scalar("UnitGUID", "string", "player") ~= characterId then
        return nil, "Open this character's mailbox to scan inbox contents."
    end
    if scalar("C_Mail.IsCommandPending", "boolean") ~= false then
        return nil, "Mail command pending or command-state API unavailable."
    end
    local counts = dataCall("GetInboxNumItems")
    if not counts or not RQ.SuppliesConfig.Count(counts[2]) or counts[2] ~= counts[3] or counts[2] > 1000 then
        return nil, "Inbox is incomplete or not fully downloaded; wait and refresh."
    end
    local limit = lookup("ATTACHMENTS_MAX_RECEIVE")
    if not publicData(limit, 0) or not RQ.SuppliesConfig.Id(limit) or limit > 100 then
        return nil, "Inbox attachment limit unavailable."
    end
    local now = Api.GetServerTime()
    if not now or now == 0 then
        return nil, "Inbox timestamp unavailable."
    end
    local scan = {
        complete = true,
        coherent = true,
        scannedAt = now,
        attemptedAt = now,
        items = {},
        details = {},
        messages = {},
    }
    for index = 1, counts[2] do
        local message, err = Api.GetInboxHeader(index)
        if not message then
            return nil, err
        end
        local attachments = 0
        for slot = 1, limit do
            local item, itemError = dataCall("GetInboxItem", index, slot)
            if not item then
                return nil, itemError
            end
            if item[2] ~= nil or item[3] ~= nil then
                if
                    not RQ.SuppliesConfig.Id(item[3])
                    or not RQ.SuppliesConfig.Id(item[5])
                    or not RQ.SuppliesConfig.Count(item[5])
                then
                    return nil, "Inbox attachment is loading or invalid."
                end
                local id, quantity = item[3], item[5]
                message.items[id] = (message.items[id] or 0) + quantity
                scan.items[id] = (scan.items[id] or 0) + quantity
                scan.details[id] = RQ.Util.IsText(item[2]) and { name = item[2] } or {}
                attachments = attachments + 1
            end
        end
        if attachments ~= message.attachmentCount then
            return nil, "Inbox attachment/header counts disagree."
        end
        message.attachmentCount = nil
        scan.messages[#scan.messages + 1] = message
    end
    return scan
end

function Api.GetMailInventory(characterId)
    local first, err = readInbox(characterId)
    if not first then
        capabilities.inboxInventory = err
        return nil, err
    end
    local bags
    bags, err = Api.GetBagItems()
    if not bags then
        return nil, err
    end
    local second
    second, err = readInbox(characterId)
    if not second then
        capabilities.inboxInventory = err
        return nil, err
    end
    local bagsAgain
    bagsAgain, err = Api.GetBagItems()
    if not bagsAgain then
        return nil, err
    end
    local stable = #first.messages == #second.messages
    for index, message in ipairs(first.messages) do
        local other = second.messages[index]
        stable = stable
            and other ~= nil
            and message.sender == other.sender
            and message.subject == other.subject
            and message.cod == other.cod
            and message.returned == other.returned
            and equalData(message.items, other.items)
    end
    if
        not stable
        or not equalData(bags.items, bagsAgain.items)
        or not equalData(bags.tradable, bagsAgain.tradable)
        or not Api.IsMailboxOpen()
        or scalar("C_Mail.IsCommandPending", "boolean") ~= false
        or scalar("UnitGUID", "string", "player") ~= characterId
    then
        return nil, "Inbox/carried contents changed during scan; retry after mail actions finish."
    end
    capabilities.inboxInventory = "available: paired inbox and carried observation"
    return { bags = bagsAgain, mail = second }
end

local mailHooksInstalled = false
function Api.ObserveMail(handlers)
    if mailHooksInstalled then
        return true
    end
    if type(lookup("SendMail")) ~= "function" or type(lookup("hooksecurefunc")) ~= "function" then
        capabilities.mailTrackingHooks = "unavailable; automatic send tracking disabled"
        return false
    end
    local ok = call("hooksecurefunc", "SendMail", function(address, subject)
        if not publicData(address, 0) or not publicData(subject, 0) then
            capabilities.mailTrackingHooks = "restricted send arguments; attempt not captured"
            return
        end
        handlers.attempt(address, subject)
    end)
    if not ok then
        return false
    end
    mailHooksInstalled = true
    for _, action in ipairs({ "TakeInboxItem", "ReturnInboxItem" }) do
        local name = action
        if type(lookup(name)) == "function" then
            call("hooksecurefunc", name, function(index)
                local header = Api.IsMailboxOpen() and Api.GetInboxHeader(index)
                handlers.action(name, header)
            end)
        else
            capabilities[name .. ":observer"] = "unavailable; collection remains uncertain"
        end
    end
    capabilities.mailTrackingHooks = "passive observers installed; send-success contract requires verification"
    return true
end

function Api.GetOutgoingCOD()
    return scalar("GetSendMailCOD", "number")
end

local function normalizedRecipient(name)
    return name:match("^%s*(.-)%s*$"):lower()
end

local function compatibleDraft(draft, recipient)
    if
        normalizedRecipient(draft.recipient) ~= ""
        and normalizedRecipient(draft.recipient) ~= normalizedRecipient(recipient)
    then
        return false, "A different recipient is already entered. Send or clear that draft before switching characters."
    end
    if #draft.items > 0 and normalizedRecipient(draft.recipient) == "" then
        return false, "Existing attachments have no recipient. Review or remove them before using Attach."
    end
    return true
end

function Api.AttachMailItems(recipient, requests, unlocking)
    if Api.IsInCombat() ~= false then
        return 0, "Attachments are unavailable in combat or with unknown combat state."
    end
    if not RQ.Util.IsText(recipient) or recipient:find("[%c|]") or type(requests) ~= "table" then
        return 0, "Invalid mail recipient or item request."
    end
    if unlocking ~= nil and type(unlocking) ~= "table" then
        return 0, "Invalid locked-container attachment requirements."
    end
    unlocking = unlocking or {}
    for item, count in pairs(unlocking) do
        if
            not RQ.SuppliesConfig.Id(item)
            or not RQ.SuppliesConfig.Id(count)
            or not RQ.SuppliesConfig.Id(requests[item])
            or count > requests[item]
        then
            return 0, "Invalid locked-container attachment requirements."
        end
    end
    local draft, err = Api.GetMailDraft()
    if not draft then
        return 0, err
    end
    local compatible
    compatible, err = compatibleDraft(draft, recipient)
    if not compatible then
        return 0, err
    end
    local cursor = dataCall("GetCursorInfo")
    if not cursor or cursor[2] ~= nil then
        return 0, "Clear the cursor before attaching items."
    end
    local scan
    scan, err = Api.GetBagItems(true)
    if not scan then
        return 0, err
    end
    local remaining, steps, lockedRemaining = {}, {}, RQ.Util.Copy(unlocking)
    for item, count in pairs(requests) do
        if not RQ.SuppliesConfig.Id(item) or not RQ.SuppliesConfig.Id(count) then
            return 0, "Invalid attachment quantity."
        end
        if draft.counts[item] then
            return 0, "This item is already attached. Review/remove it before attaching more of the same item."
        end
        remaining[item] = count
    end
    table.sort(scan.locations, function(a, b)
        local first = unlocking[a.itemId] ~= nil and a.needsUnlocking == true
        local second = unlocking[b.itemId] ~= nil and b.needsUnlocking == true
        if first ~= second then
            return first
        elseif a.bag ~= b.bag then
            return a.bag < b.bag
        end
        return a.slot < b.slot
    end)
    for _, location in ipairs(scan.locations) do
        local needed = remaining[location.itemId] or 0
        if needed > 0 then
            local count = math.min(needed, location.count)
            local lockedCount = location.needsUnlocking and math.min(count, lockedRemaining[location.itemId] or 0) or 0
            lockedRemaining[location.itemId] = (lockedRemaining[location.itemId] or 0) - lockedCount
            steps[#steps + 1] = {
                bag = location.bag,
                slot = location.slot,
                itemId = location.itemId,
                count = count,
                originalCount = location.count,
                needsUnlocking = lockedCount > 0,
            }
            remaining[location.itemId] = needed - count
        end
        for _, count in pairs(lockedRemaining) do
            if count > 0 then
                return 0, "Locked-container evidence changed or is unavailable. Refresh the proposals."
            end
        end
    end
    for _, count in pairs(remaining) do
        if count > 0 then
            return 0, "Bag contents changed or stacks are locked/bound. Refresh the proposals."
        end
    end
    if #steps == 0 then
        return 0, "No new items to attach."
    end
    if #steps > #draft.free then
        return 0, "Not enough free mail attachment slots. Attach individual items or send/clear this draft first."
    end
    for _, step in ipairs(steps) do
        local method = step.count == step.originalCount and "C_Container.PickupContainerItem"
            or "C_Container.SplitContainerItem"
        if
            type(lookup(method)) ~= "function"
            or type(lookup("ClickSendMailItemButton")) ~= "function"
            or type(lookup("ClearCursor")) ~= "function"
        then
            return 0, "Mail attachment APIs unavailable; attach items manually."
        end
    end
    local ok
    ok, err = uiOperation("mailRecipient", function()
        if not _G.SendMailFrame or not _G.SendMailFrame:IsShown() then
            if not _G.MailFrameTab2 then
                error("Open the Send Mail tab before attaching.")
            end
            _G.MailFrameTab2:Click()
        end
        if not _G.SendMailFrame or not _G.SendMailFrame:IsShown() then
            error("Send Mail tab did not open.")
        end
        _G.SendMailNameEditBox:SetText(recipient)
    end)
    if not ok then
        return 0, err
    end
    local attached = 0
    local function stop(reason, itemId)
        local held = dataCall("GetCursorInfo")
        if held and held[2] == "item" and held[3] == itemId then
            local cleared = call("ClearCursor")
            held = dataCall("GetCursorInfo")
            if not cleared or not held or held[2] ~= nil then
                reason = reason .. " Cursor could not be restored; place the held item back in your bags."
            end
        end
        return attached, reason .. " Review the current draft; nothing was sent."
    end
    for index, step in ipairs(steps) do
        local current
        current, err = Api.GetMailDraft()
        if not current or Api.IsInCombat() ~= false then
            return stop(err or "Combat interrupted attachment.", step.itemId)
        end
        compatible, err = compatibleDraft(current, recipient)
        if not compatible or current.recipient ~= recipient or current.slots[draft.free[index]] then
            return stop(err or "Mail draft changed during attachment.", step.itemId)
        end
        local info = dataCall("C_Container.GetContainerItemInfo", step.bag, step.slot)
        info = info and info[2]
        if
            type(info) ~= "table"
            or info.itemID ~= step.itemId
            or info.stackCount ~= step.originalCount
            or info.isBound ~= false
            or info.isLocked ~= false
            or (step.needsUnlocking and bagNeedsUnlocking(step.bag, step.slot) ~= true)
        then
            return stop("A bag stack changed; refresh before retrying.", step.itemId)
        end
        cursor = dataCall("GetCursorInfo")
        if not cursor or cursor[2] ~= nil then
            return attached, "Cursor changed. Attachment stopped; review the draft and cursor."
        end
        local picked
        if step.count == step.originalCount then
            picked = call("C_Container.PickupContainerItem", step.bag, step.slot)
        else
            picked = call("C_Container.SplitContainerItem", step.bag, step.slot, step.count)
        end
        if not picked then
            return stop("Item pickup was blocked or failed.", step.itemId)
        end
        cursor = dataCall("GetCursorInfo")
        if not cursor or cursor[2] ~= "item" or cursor[3] ~= step.itemId then
            return stop("Item pickup was not confirmed.", step.itemId)
        end
        -- Recheck after pickup: another addon or a mailbox-close event may have changed the draft.
        current, err = Api.GetMailDraft()
        if
            not current
            or current.recipient ~= recipient
            or current.slots[draft.free[index]]
            or Api.IsInCombat() ~= false
        then
            return stop(err or "Mail draft or combat state changed after pickup.", step.itemId)
        end
        if not call("ClickSendMailItemButton", draft.free[index]) then
            return stop("Attaching the item was blocked or failed.", step.itemId)
        end
        local added = dataCall("GetSendMailItem", draft.free[index])
        cursor = dataCall("GetCursorInfo")
        if not added or added[3] ~= step.itemId or added[5] ~= step.count or not cursor or cursor[2] ~= nil then
            return stop("Attachment not yet confirmed; check its item and quantity before retrying.", step.itemId)
        end
        attached = attached + 1
    end
    return attached
end

local function uiFrame(kind, parent, template, name)
    local created = call("CreateFrame", kind, name, parent, template)
    if not created or not created[2] then
        error("CreateFrame unavailable for " .. kind)
    end
    return created[2]
end

local function uiText(parent, x, y, width, template)
    local label = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", x, y)
    label:SetWidth(width)
    label:SetJustifyH("LEFT")
    label:SetJustifyV("TOP")
    return label
end

local function uiButton(parent, text, x, y, width, click)
    local button = uiFrame("Button", parent, "UIPanelButtonTemplate")
    button:SetPoint("TOPLEFT", x, y)
    button:SetSize(width, 24)
    button:SetText(text)
    button:SetScript("OnClick", click)
    return button
end

local function enable(button, enabled)
    if enabled then
        button:Enable()
    else
        button:Disable()
    end
end

function Api.IsRosterWindowShown()
    return dashboard ~= nil and dashboard.frame:IsShown()
end

function Api.HideRosterWindow()
    if dashboard then
        dashboard.frame:Hide()
    end
end

function Api.ResetRosterWindowPosition()
    if dashboard then
        local ok, err = uiOperation("rosterWindowPosition", function()
            dashboard.frame:ClearAllPoints()
            dashboard.frame:SetPoint("CENTER", _G.UIParent, "CENTER", 0, 0)
        end)
        if not ok then
            Api.Print("Cannot reset window position: " .. err)
        end
        return ok
    end
    return true
end

local function planningControls(frame)
    local panel = uiFrame("Frame", frame)
    panel:SetPoint("TOPLEFT", 18, -128)
    panel:SetPoint("BOTTOMRIGHT", -18, 42)
    dashboard.planningPanel, dashboard.planningInputs = panel, {}
    uiText(panel, 0, 0, 400, "GameFontNormal"):SetText("RESTED ESTIMATES  |  Advanced assumptions")
    uiText(panel, 430, 0, 310, "GameFontNormal"):SetText("CHARACTER OVERRIDES")
    uiButton(panel, "Export configuration", 0, -422, 210, function()
        dashboard.handlers.configTransfer("export")
    end)
    uiButton(panel, "Import configuration", 220, -422, 210, function()
        dashboard.handlers.configTransfer("import")
    end)
    uiButton(panel, "Manage roster", 442, -422, 190, function()
        dashboard.handlers.manageRoster()
    end)
    for index, field in ipairs(RQ.PlanningFields) do
        local y = -36 - (index - 1) * 34
        uiText(panel, 0, y - 7, 300):SetText(field.label)
        local edit = uiFrame("EditBox", panel, "InputBoxTemplate")
        edit:SetSize(84, 28)
        edit:SetPoint("TOPLEFT", 310, y)
        edit:SetAutoFocus(false)
        edit:SetMaxLetters(16)
        edit:SetScript("OnEscapePressed", function()
            edit:ClearFocus()
            Api.HideRosterWindow()
        end)
        dashboard.planningInputs[field.key] = edit
    end
    uiButton(panel, "Save assumptions", 0, -316, 220, function()
        local values = {}
        for _, field in ipairs(RQ.PlanningFields) do
            local edit = dashboard.planningInputs[field.key]
            local value = tonumber(edit:GetText())
            values[field.key] = value and value / field.scale
            edit:ClearFocus()
        end
        dashboard.handlers.planning(values)
    end)
    uiText(panel, 0, -358, 400):SetText(
        "Rates are percentages of a level per hour. Cap and rates are unverified.\n"
            .. "Saving changed mechanics resets learned rates. A changed perk needs a new logout baseline."
    )
    dashboard.planningCharacter = uiText(panel, 430, -36, 310, "GameFontNormal")
    dashboard.planningPrevious = uiButton(panel, "Previous", 430, -92, 100, function()
        dashboard.handlers.character(-1)
    end)
    dashboard.planningNext = uiButton(panel, "Next", 540, -92, 100, function()
        dashboard.handlers.character(1)
    end)
    uiText(panel, 430, -140, 175):SetText("Rested rate multiplier")
    local edit = uiFrame("EditBox", panel, "InputBoxTemplate")
    edit:SetSize(88, 28)
    edit:SetPoint("TOPLEFT", 640, -132)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(16)
    edit:SetScript("OnEscapePressed", function()
        edit:ClearFocus()
        Api.HideRosterWindow()
    end)
    dashboard.multiplierInput = edit
    dashboard.saveMultiplier = uiButton(panel, "Save multiplier", 430, -174, 144, function()
        local value = tonumber(edit:GetText())
        edit:ClearFocus()
        dashboard.handlers.multiplier(value)
    end)
    dashboard.resetCalibration = uiButton(panel, "Reset calibration", 584, -174, 156, function()
        dashboard.handlers.resetCalibration()
    end)
    dashboard.blocker = uiButton(panel, "Resource blocker", 430, -218, 310, function()
        dashboard.handlers.signal("resourceBlocker")
    end)
    dashboard.dungeon = uiButton(panel, "Dungeon ready", 430, -256, 310, function()
        dashboard.handlers.signal("dungeonReady")
    end)
    uiText(panel, 430, -344, 310):SetText(
        "Blocker and dungeon signals are manual, not quest or inventory scans.\n"
            .. "After a rested perk changes, update the multiplier or reset calibration."
    )
end

local professionIcons = {
    [129] = "Spell_Holy_SealOfSacrifice",
    [164] = "Trade_BlackSmithing",
    [165] = "Trade_LeatherWorking",
    [171] = "Trade_Alchemy",
    [182] = "Trade_Herbalism",
    [185] = "INV_Misc_Food_15",
    [186] = "Trade_Mining",
    [197] = "Trade_Tailoring",
    [202] = "Trade_Engineering",
    [333] = "Trade_Engraving",
    [356] = "Trade_Fishing",
    [393] = "INV_Misc_Pelt_Wolf_01",
}

local function graphicTexture(texture, path, coords)
    if type(texture.SetTexture) ~= "function" or type(texture.SetTexCoord) ~= "function" then
        texture:Hide()
        capabilities.dashboardIcons = "unavailable: texture methods missing; text labels retained"
        return false
    end
    local ok = uiOperation("dashboardIcons", function()
        texture:SetTexCoord(unpack(coords or { 0, 1, 0, 1 }))
        if not path or texture:SetTexture(path) == false then
            error("Texture unavailable; text label retained")
        end
    end)
    if ok then
        texture:Show()
    else
        texture:Hide()
    end
    return ok
end

local function classAppearance(token)
    local label = token or "Unknown class"
    local names = lookup("LOCALIZED_CLASS_NAMES_MALE")
    if type(names) == "table" and publicData(names[token], 0) and RQ.Util.IsText(names[token]) then
        label = names[token]
    end
    local colors = lookup("RAID_CLASS_COLORS")
    local color = type(colors) == "table" and colors[token]
    if
        not publicData(color, 0)
        or type(color) ~= "table"
        or not RQ.Util.IsNumber(color.r)
        or not RQ.Util.IsNumber(color.g)
        or not RQ.Util.IsNumber(color.b)
        or color.r > 1
        or color.g > 1
        or color.b > 1
    then
        color = { r = 0.7, g = 0.7, b = 0.7 }
    end
    return label, color
end

local function graphicPortrait(texture, card, activeGuid)
    local atlas = lookup("CLASS_ICON_TCOORDS")
    local coords = type(atlas) == "table" and atlas[card.visual.class]
    local valid = publicData(coords, 0) and type(coords) == "table"
    for index = 1, 4 do
        valid = valid and RQ.Util.IsNumber(coords[index]) and coords[index] <= 1
    end
    graphicTexture(texture, valid and "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES", valid and coords)
    if
        card.id
        and card.id == activeGuid
        and type(lookup("SetPortraitTexture")) == "function"
        and type(texture.SetTexCoord) == "function"
    then
        local ok = uiOperation("dashboardPortrait", function()
            texture:SetTexCoord(0, 1, 0, 1)
            local result = call("SetPortraitTexture", texture, "player")
            if not result or result[2] == false then
                error("Portrait unavailable; class icon retained")
            end
        end)
        if ok then
            texture:Show()
        else
            graphicTexture(
                texture,
                valid and "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES",
                valid and coords
            )
        end
    end
end

local function dashboardGraphics(frame)
    dashboard.graphicControls = uiFrame("Frame", frame)
    local controls = dashboard.graphicControls
    controls:SetPoint("TOPLEFT", 0, -40)
    controls:SetPoint("BOTTOMRIGHT", 0, 0)
    dashboard.realmControl = uiButton(frame, "All realms", 18, -48, 342, function()
        dashboard.handlers.realm()
    end)
    dashboard.sortControl = uiButton(controls, "Sort: name", 204, -88, 130, function()
        dashboard.handlers.rosterSort()
    end)
    dashboard.filterControl = uiButton(controls, "Show: all", 342, -88, 140, function()
        dashboard.handlers.rosterFilter()
    end)
    dashboard.groupControl = uiButton(frame, "All trade groups", 372, -48, 412, function()
        dashboard.handlers.tradeGroup()
    end)
    dashboard.previousDetail = uiButton(controls, "Previous row", 490, -88, 140, function()
        dashboard.handlers.selectRelative(-1)
    end)
    dashboard.nextDetail = uiButton(controls, "Next row", 638, -88, 140, function()
        dashboard.handlers.selectRelative(1)
    end)
    uiButton(controls, "Manage roster", 18, -122, 146, function()
        dashboard.handlers.manageRoster()
    end)
    uiButton(controls, "Suggested order", 176, -122, 184, function()
        dashboard.handlers.tab("today")
    end)
    dashboard.rosterHeadline = uiText(controls, 18, -160, 756, "GameFontNormal")
    dashboard.detailScroll = uiFrame("ScrollFrame", frame, "UIPanelScrollFrameTemplate")
    dashboard.detailScroll:SetPoint("TOPLEFT", 494, -132)
    dashboard.detailScroll:SetPoint("BOTTOMRIGHT", -38, 42)
    local detail = uiFrame("Frame", dashboard.detailScroll)
    detail:SetSize(250, 1)
    dashboard.detailScroll:SetScrollChild(detail)
    dashboard.detailScroll:EnableMouseWheel(true)
    dashboard.detailScroll:SetScript("OnMouseWheel", function(_, delta)
        local maximum = math.max(0, detail:GetHeight() - dashboard.detailScroll:GetHeight())
        dashboard.detailScroll:SetVerticalScroll(
            math.max(0, math.min(maximum, dashboard.detailScroll:GetVerticalScroll() - delta * 40))
        )
    end)
    dashboard.detailContent = detail
    dashboard.detailTitle = uiText(detail, 0, -4, 250, "GameFontNormal")
    dashboard.detailText = uiText(detail, 0, -36, 250)
    dashboard.detailAction = uiButton(detail, "Configure selected", 0, -60, 180, function()
        local card = dashboard.detailCard
        if card then
            dashboard.handlers.configure(card.id)
        end
    end)
    dashboard.detailProfessions = uiButton(detail, "Profession advice", 0, -94, 180, function()
        local card = dashboard.detailCard
        if card and card.id then
            dashboard.handlers.professionAdvice(card.id)
        end
    end)
    dashboard.detailGroceries = uiButton(detail, "Grocery list", 0, -94, 180, function()
        local card = dashboard.detailCard
        if card and card.id then
            dashboard.handlers.groceries(card.id)
        end
    end)
    dashboard.detailMain = uiButton(detail, "Make main", 0, -162, 180, function()
        local card = dashboard.detailCard
        if card and card.id then
            dashboard.handlers.mainFor(card.id)
        end
    end)
    dashboard.detailEvidence = uiButton(detail, "Details / copy", 0, -196, 180, function()
        local card = dashboard.detailCard
        if card then
            Api.ShowCopyWindow(card.title, card.detail or card.body)
        end
    end)
    dashboard.graphicEmpty = uiText(dashboard.content, 8, -8, 430)
    dashboard.graphicRows = {}
    if type(frame.EnableKeyboard) == "function" and type(frame.SetPropagateKeyboardInput) == "function" then
        frame:EnableKeyboard(true)
        frame:SetPropagateKeyboardInput(true)
        frame:SetScript("OnKeyDown", function(_, key)
            frame:SetPropagateKeyboardInput(true)
            if
                Api.IsInCombat() == false
                and dashboard.renderedTab == "activity"
                and (
                    key == "PAGEUP"
                    or key == "PAGEDOWN"
                    or (dashboard.activitySection == "history" and (key == "LEFT" or key == "RIGHT"))
                )
            then
                local focus = call("GetCurrentKeyBoardFocus")
                if focus and focus[2] == nil then
                    frame:SetPropagateKeyboardInput(false)
                    if key == "LEFT" or key == "RIGHT" then
                        dashboard.handlers.activityMonth(key == "LEFT" and -1 or 1)
                    else
                        dashboard.handlers.activityPage(key == "PAGEUP" and -1 or 1)
                    end
                end
                return
            end
            if
                Api.IsInCombat() == false
                and (dashboard.renderedTab == "roster" or dashboard.renderedTab == "today")
                and (key == "UP" or key == "DOWN")
            then
                local focus = call("GetCurrentKeyBoardFocus")
                if focus and focus[2] == nil then
                    frame:SetPropagateKeyboardInput(false)
                    dashboard.handlers.selectRelative(key == "DOWN" and 1 or -1)
                end
            end
        end)
    else
        capabilities.dashboardKeyboard = "unavailable; use Previous row / Next row buttons"
    end
end

local function createGraphicRow()
    local row = uiFrame("Frame", dashboard.content)
    row:SetWidth(442)
    row.background = row:CreateTexture(nil, "BACKGROUND")
    row.background:SetAllPoints()
    row.accent = row:CreateTexture(nil, "ARTWORK")
    row.accent:SetPoint("TOPLEFT", 0, 0)
    row.realm = uiText(row, 10, -6, 420, "GameFontNormal")
    row.portrait = row:CreateTexture(nil, "ARTWORK")
    row.portrait:SetSize(40, 40)
    row.heading = uiText(row, 60, -8, 370, "GameFontNormal")
    row.identity = uiText(row, 60, -28, 370, "GameFontHighlightSmall")
    row.freshness = uiText(row, 10, -58, 420, "GameFontHighlightSmall")
    row.note = uiText(row, 10, -80, 420)
    row.restLabel = uiText(row, 10, -100, 420)
    row.restBadge = uiText(row, 10, -120, 420, "GameFontHighlightSmall")
    row.restTrack = row:CreateTexture(nil, "BACKGROUND")
    row.restTrack:SetColorTexture(0.16, 0.16, 0.18, 1)
    row.restTrack:SetSize(420, 9)
    row.restFill = row:CreateTexture(nil, "ARTWORK")
    row.restFill:SetColorTexture(0.25, 0.55, 0.95, 1)
    row.restFill:SetHeight(9)
    row.professions = {}
    row.select = uiButton(row, "Details", 10, -10, 110, function()
        dashboard.handlers.select(row.card.id)
    end)
    row.action = uiButton(row, "Configure", 310, -10, 120, function()
        dashboard.handlers.configure(row.card.id)
    end)
    return row
end

local function place(widget, x, y)
    widget:ClearAllPoints()
    widget:SetPoint("TOPLEFT", x, -y)
end

local function renderGraphicRow(row, card, group, today, selected, activeGuid)
    local visual = card.visual
    row.card, row.characterId = card, card.id
    row.background:SetColorTexture(selected and 0.18 or 0.10, selected and 0.22 or 0.12, 0.17, 0.95)
    local label, color = classAppearance(visual.class)
    row.accent:SetColorTexture(color.r, color.g, color.b, 1)
    row.realm:SetText(group and visual.realm or "")
    local y = group and row.realm:GetStringHeight() + 12 or 8
    place(row.portrait, 10, y)
    graphicPortrait(row.portrait, card, activeGuid)
    place(row.heading, 60, y)
    row.heading:SetText(
        (today and visual.rank and (visual.rank == 1 and "1. PLAY NEXT: " or visual.rank .. ". ") or "") .. visual.name
    )
    if type(row.heading.SetTextColor) == "function" then
        row.heading:SetTextColor(color.r, color.g, color.b)
    end
    place(row.identity, 60, y + row.heading:GetStringHeight() + 3)
    row.identity:SetText(
        RQ.CharacterCard.Text(label)
            .. " | Level "
            .. (visual.level or "?")
            .. (visual.role and (" | " .. visual.role) or "")
            .. "\n"
            .. (visual.groupLabel or "Unknown ruleset / faction")
            .. (visual.badges ~= "" and ("\n" .. visual.badges) or "")
    )
    y = y + math.max(42, row.heading:GetStringHeight() + row.identity:GetStringHeight() + 6) + 6
    place(row.freshness, 10, y)
    row.freshness:SetText(visual.freshness .. " | " .. visual.age .. "\nGold: " .. (visual.money or "unavailable"))
    y = y + row.freshness:GetStringHeight() + 8
    local count = #visual.professions
    local pairHeight = 0
    for index = 1, count do
        local profession = visual.professions[index]
        local cell = row.professions[index]
        if not cell then
            cell = { icon = row:CreateTexture(nil, "ARTWORK"), text = uiText(row, 0, 0, 182, "GameFontHighlightSmall") }
            cell.icon:SetSize(24, 24)
            row.professions[index] = cell
        end
        local x = index % 2 == 1 and 10 or 226
        place(cell.icon, x, y)
        place(cell.text, x + 30, y)
        local icon = professionIcons[profession.id]
        graphicTexture(cell.icon, icon and "Interface\\Icons\\" .. icon)
        cell.text:SetText(profession.shortLabel or profession.label)
        if type(cell.text.SetTextColor) == "function" then
            if profession.state == "BEHIND" then
                cell.text:SetTextColor(1, 0.70, 0.25)
            else
                cell.text:SetTextColor(0.85, 0.85, 0.85)
            end
        end
        cell.text:Show()
        pairHeight = math.max(pairHeight, cell.text:GetStringHeight(), 24)
        if index % 2 == 0 or index == count then
            y, pairHeight = y + pairHeight + 6, 0
        end
    end
    for index = count + 1, #row.professions do
        row.professions[index].icon:Hide()
        row.professions[index].text:Hide()
    end
    local note = visual.professionNote or ""
    if visual.rank == 1 and visual.reason then
        note = visual.reason
    end
    row.note:SetText(note)
    place(row.note, 10, y)
    if note ~= "" then
        y = y + row.note:GetStringHeight() + 8
    end
    row.restLabel:Hide()
    row.restBadge:Hide()
    row.restTrack:Hide()
    row.restFill:Hide()
    if visual.rested then
        local rested = visual.rested
        row.restLabel:SetText(rested.label)
        place(row.restLabel, 10, y)
        row.restLabel:Show()
        y = y + row.restLabel:GetStringHeight() + 4
        row.restBadge:SetText(rested.badge .. (rested.ratio == nil and " | Progress scale unknown" or ""))
        place(row.restBadge, 10, y)
        row.restBadge:Show()
        y = y + row.restBadge:GetStringHeight() + 4
        place(row.restTrack, 10, y)
        row.restTrack:Show()
        if RQ.Util.IsNumber(rested.ratio) and rested.ratio > 0 then
            row.restFill:SetWidth(420 * math.min(1, rested.ratio))
            place(row.restFill, 10, y)
            row.restFill:Show()
        end
        y = y + 18
    end
    place(row.select, 10, y)
    row.select:SetText(selected and "Selected" or "Details")
    place(row.action, 310, y)
    row.action:SetText(card.action)
    row:SetHeight(y + 36)
    row.accent:SetSize(3, y + 36)
    row:Show()
end

local function renderGraphics(view)
    dashboard.graphicControls:Show()
    dashboard.detailScroll:Show()
    dashboard.realmControl:SetText(view.realms[view.realm])
    dashboard.groupControl:SetText(view.groups[view.group])
    dashboard.sortControl:SetText("Sort: " .. view.sort)
    dashboard.filterControl:SetText("Show: " .. view.filter)
    enable(dashboard.sortControl, true)
    enable(dashboard.filterControl, true)
    dashboard.rosterHeadline:SetText(view.headline)
    local rosterTop = math.max(230, 212 + dashboard.rosterHeadline:GetStringHeight())
    enable(dashboard.previousDetail, #view.rows > 0)
    enable(dashboard.nextDetail, #view.rows > 0)
    dashboard.scroll:ClearAllPoints()
    dashboard.scroll:SetPoint("TOPLEFT", 18, -rosterTop)
    dashboard.scroll:SetPoint("BOTTOMRIGHT", -328, 42)
    dashboard.content:SetWidth(442)
    dashboard.detailScroll:ClearAllPoints()
    dashboard.detailScroll:SetPoint("TOPLEFT", 494, -rosterTop)
    dashboard.detailScroll:SetPoint("BOTTOMRIGHT", -38, 42)
    for _, row in ipairs(dashboard.cards) do
        row:Hide()
    end
    local y, previousRealm, selectedTop, selectedHeight = 0
    local activeGuid = scalar("UnitGUID", "string", "player")
    for index, card in ipairs(view.rows) do
        local row = dashboard.graphicRows[index] or createGraphicRow()
        dashboard.graphicRows[index] = row
        local selected = view.detail == card
        renderGraphicRow(row, card, previousRealm ~= card.visual.realmKey, true, selected, activeGuid)
        place(row, 0, y)
        if selected then
            selectedTop, selectedHeight = y, row:GetHeight()
        end
        y, previousRealm = y + row:GetHeight() + 8, card.visual.realmKey
    end
    for index = #view.rows + 1, #dashboard.graphicRows do
        dashboard.graphicRows[index]:Hide()
    end
    dashboard.graphicEmpty:SetText(
        #view.cards == 0 and "Your roster starts here. Use Manage roster to add this character."
            or "No matching characters. Change trade group/realm/show filters or use Manage roster."
    )
    if #view.rows == 0 then
        dashboard.graphicEmpty:Show()
    else
        dashboard.graphicEmpty:Hide()
    end
    dashboard.content:SetHeight(math.max(60, y))
    local detail = view.detail
    local key = view.tab .. ":" .. (detail and detail.id or "")
    local layoutKey = view.tab .. ":" .. view.sort .. ":" .. view.filter .. ":" .. view.realm
    if key ~= dashboard.detailKey then
        dashboard.detailScroll:SetVerticalScroll(0)
    end
    if key ~= dashboard.detailKey or layoutKey ~= dashboard.layoutKey then
        if selectedTop then
            local scroll, height = dashboard.scroll:GetVerticalScroll(), dashboard.scroll:GetHeight()
            if selectedTop < scroll or selectedTop + selectedHeight > scroll + height then
                dashboard.scroll:SetVerticalScroll(selectedTop)
            end
        end
    end
    dashboard.detailKey, dashboard.detailCard = key, detail
    dashboard.layoutKey = layoutKey
    dashboard.detailAction:SetText("Configure selected")
    dashboard.detailTitle:SetText(detail and detail.title or "Select a character")
    local body = detail and (detail.summary or detail.body)
        or "Select a character to see their session and roster controls."
    if detail and not selectedTop then
        body = "Selection is hidden by the current filters.\n\n" .. body
    end
    if view.warnings ~= "" then
        body = body .. "\n\n" .. view.warnings
    end
    dashboard.detailText:SetText(body)
    place(dashboard.detailText, 0, dashboard.detailTitle:GetStringHeight() + 16)
    local height = dashboard.detailTitle:GetStringHeight() + dashboard.detailText:GetStringHeight() + 28
    place(dashboard.detailGroceries, 0, height)
    enable(dashboard.detailGroceries, detail ~= nil and detail.groceriesAction == true)
    height = height + 34
    place(dashboard.detailAction, 0, height)
    enable(dashboard.detailAction, detail ~= nil)
    place(dashboard.detailProfessions, 0, height + 34)
    enable(dashboard.detailProfessions, detail ~= nil and detail.id ~= nil)
    place(dashboard.detailMain, 0, height + 102)
    enable(dashboard.detailMain, detail ~= nil and detail.id ~= nil and view.isMember and not view.isMain)
    dashboard.detailMain:SetText(view.isMain and "Current main" or "Make main")
    place(dashboard.detailEvidence, 0, height + 136)
    enable(dashboard.detailEvidence, detail ~= nil)
    dashboard.detailContent:SetHeight(height + 172)
    dashboard.detailScroll:SetVerticalScroll(
        math.min(
            dashboard.detailScroll:GetVerticalScroll(),
            math.max(0, height + 172 - dashboard.detailScroll:GetHeight())
        )
    )
    dashboard.scroll:SetVerticalScroll(
        math.min(dashboard.scroll:GetVerticalScroll(), math.max(0, y - dashboard.scroll:GetHeight()))
    )
end

local function createDashboard(position, handlers)
    local frame = uiFrame("Frame", _G.UIParent, nil, "RQMainWindow")
    frame:Hide()
    dashboard = { frame = frame, cards = {}, handlers = handlers }
    frame:SetSize(800, 600)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetPoint(position.point, _G.UIParent, position.relativePoint, position.x, position.y)
    frame:SetScript("OnDragStart", function()
        if Api.IsInCombat() == false then
            frame:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function()
        local saved
        local ok, err = uiOperation("rosterWindowPosition", function()
            frame:StopMovingOrSizing()
            local point, _, relativePoint, x, y = frame:GetPoint(1)
            saved = { point = point, relativePoint = relativePoint, x = x, y = y }
            if not RQ.Util.IsWindowPosition(saved) then
                error("Invalid native window position")
            end
        end)
        if ok then
            dashboard.handlers.position(saved)
        else
            Api.Print("Window position not saved: " .. err)
        end
    end)
    frame:SetScript("OnHide", function()
        frame:StopMovingOrSizing()
    end)
    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.035, 0.042, 0.055, 0.98)
    local header = frame:CreateTexture(nil, "BACKGROUND")
    header:SetPoint("TOPLEFT", 0, 0)
    header:SetSize(800, 122)
    header:SetColorTexture(0.075, 0.092, 0.12, 1)
    local rule = frame:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("TOPLEFT", 0, -120)
    rule:SetSize(800, 2)
    rule:SetColorTexture(0.64, 0.51, 0.28, 1)
    dashboard.title = uiText(frame, 18, -16, 410, "GameFontNormalLarge")
    uiButton(frame, "Rescan current", 436, -12, 116, function()
        dashboard.handlers.rescan()
    end)
    uiButton(frame, "Diagnostics", 560, -12, 140, function()
        RQ.Diagnostics.Copy()
    end)
    uiButton(frame, "Close", 712, -12, 72, Api.HideRosterWindow)
    dashboard.rosterTab = uiButton(frame, "Roster", 18, -88, 180, function()
        dashboard.handlers.tab("roster")
    end)
    dashboard.settingsTab = uiButton(frame, "Settings", 606, -88, 178, function()
        dashboard.handlers.tab("settings")
    end)
    dashboard.suppliesTab = uiButton(frame, "Bags and Inventory", 214, -88, 180, function()
        dashboard.handlers.tab("bags")
    end)
    dashboard.professionsTab = uiButton(frame, "Professions", 410, -88, 180, function()
        dashboard.handlers.tab("professions")
    end)
    dashboard.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dashboard.status:SetPoint("BOTTOMLEFT", 18, 12)
    dashboard.status:SetWidth(650)
    dashboard.status:SetJustifyH("LEFT")
    uiButton(frame, "Center", 698, -564, 86, function()
        dashboard.handlers.resetPosition()
    end)
    local scroll = uiFrame("ScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 18, -88)
    scroll:SetPoint("BOTTOMRIGHT", -38, 42)
    local content = uiFrame("Frame", scroll)
    content:SetSize(728, 1)
    scroll:SetScrollChild(content)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta)
        local maximum = math.max(0, content:GetHeight() - scroll:GetHeight())
        scroll:SetVerticalScroll(math.max(0, math.min(maximum, scroll:GetVerticalScroll() - delta * 40)))
    end)
    dashboard.scroll, dashboard.content = scroll, content
    dashboard.professionControls = uiFrame("Frame", frame)
    dashboard.professionControls:SetPoint("TOPLEFT", 18, -128)
    dashboard.professionControls:SetSize(760, 30)
    uiButton(dashboard.professionControls, "Orange recipes", 0, 0, 160, function()
        dashboard.handlers.tab("professions")
    end)
    uiButton(dashboard.professionControls, "Grocery list", 170, 0, 160, function()
        dashboard.handlers.tab("inventory")
    end)
    uiButton(dashboard.professionControls, "Compact list", 340, 0, 150, function()
        dashboard.handlers.compactGroceries()
    end)
    dashboard.newNeed = uiButton(dashboard.professionControls, "Set item stock", 500, 0, 230, function()
        Api.ShowStockEditor(dashboard.groceryOwner, dashboard.groceryOwnerName, dashboard.handlers.need)
    end)
    dashboard.recipePrevious = uiButton(dashboard.professionControls, "Prev recipes", 500, 0, 110, function()
        dashboard.handlers.recipePage(-1)
    end)
    dashboard.recipeNext = uiButton(dashboard.professionControls, "Next recipes", 620, 0, 110, function()
        dashboard.handlers.recipePage(1)
    end)
    local bagSearch = uiFrame("Frame", frame)
    bagSearch:SetPoint("TOPLEFT", 0, -40)
    bagSearch:SetPoint("BOTTOMRIGHT", 0, 0)
    dashboard.bagSearch = bagSearch
    dashboard.inventorySections = {}
    for index, entry in ipairs({ { "recorded", "Recorded items" }, { "upgrades", "Bag upgrades" } }) do
        local section = entry[1]
        dashboard.inventorySections[section] = uiButton(
            bagSearch,
            entry[2],
            18 + (index - 1) * 154,
            -88,
            146,
            function()
                dashboard.handlers.inventorySection(section)
            end
        )
    end
    uiButton(bagSearch, "Mail / transfers", 326, -88, 150, function()
        dashboard.handlers.mail(false)
    end)
    uiButton(bagSearch, "Shipments", 488, -88, 130, function()
        dashboard.handlers.shipments()
    end)
    dashboard.inventoryPrevious = uiButton(bagSearch, "Prev items", 626, -88, 76, function()
        dashboard.handlers.inventoryPage(-1)
    end)
    dashboard.inventoryNext = uiButton(bagSearch, "Next items", 708, -88, 76, function()
        dashboard.handlers.inventoryPage(1)
    end)
    dashboard.inventoryPage = uiText(bagSearch, 344, -192, 270, "GameFontHighlightSmall")
    dashboard.copyInventory = uiButton(bagSearch, "Copy results", 210, -192, 126, function()
        dashboard.handlers.copyBagSearch()
    end)
    local searchLabel = uiText(bagSearch, 18, -94, 90)
    searchLabel:ClearAllPoints()
    searchLabel:SetPoint("TOPLEFT", 18, -130)
    searchLabel:SetText("Find item:")
    local query = uiFrame("EditBox", bagSearch, "InputBoxTemplate")
    query:SetPoint("TOPLEFT", 110, -124)
    query:SetSize(250, 24)
    query:SetAutoFocus(false)
    query:SetMaxLetters(128)
    dashboard.bagQueryInput = query
    local function search()
        query:ClearFocus()
        dashboard.handlers.searchBags(query:GetText())
    end
    query:SetScript("OnEnterPressed", search)
    query:SetScript("OnEscapePressed", function()
        query:ClearFocus()
        Api.HideRosterWindow()
    end)
    uiButton(bagSearch, "Search", 370, -124, 80, search)
    uiButton(bagSearch, "Clear search", 458, -124, 130, function()
        query:ClearFocus()
        query:SetText("")
        dashboard.handlers.searchBags("")
    end)
    dashboard.bagOwnerButton = uiButton(bagSearch, "Next owner", 596, -124, 180, function()
        dashboard.handlers.bagOwner()
    end)
    dashboard.bagOwnerLabel = uiText(bagSearch, 18, -162, 744, "GameFontHighlightSmall")
    dashboard.bagSourceButton = uiButton(bagSearch, "Source: all", 18, -154, 180, function()
        if dashboard.inventorySection == "stock" and dashboard.bagQuery == "" then
            dashboard.handlers.groceryFilter()
        else
            dashboard.handlers.bagSource()
        end
    end)
    local settings = uiFrame("Frame", frame)
    settings:SetPoint("TOPLEFT", 18, -128)
    settings:SetPoint("BOTTOMRIGHT", -18, 42)
    dashboard.settings = settings
    dashboard.characterLabel = uiText(settings, 0, 0, 720, "GameFontNormal")
    dashboard.previousCharacter = uiButton(settings, "Previous", 0, -34, 100, function()
        dashboard.handlers.character(-1)
    end)
    dashboard.nextCharacter = uiButton(settings, "Next", 108, -34, 100, function()
        dashboard.handlers.character(1)
    end)
    dashboard.characterDetails = uiText(settings, 228, -32, 500)
    dashboard.add = uiButton(settings, "Add / resume", 0, -100, 160, function()
        dashboard.handlers.register("add")
    end)
    dashboard.ignore = uiButton(settings, "Ignore", 170, -100, 130, function()
        dashboard.handlers.register("ignore")
    end)
    dashboard.main = uiButton(settings, "Make main", 310, -100, 160, function()
        dashboard.handlers.main()
    end)
    dashboard.role = uiButton(settings, "Role", 0, -140, 300, function()
        dashboard.handlers.role()
    end)
    dashboard.ruleset = uiButton(settings, "Ruleset", 0, -180, 300, function()
        dashboard.handlers.ruleset()
    end)
    dashboard.cook = uiButton(settings, "Assign Cooking/Fishing", 0, -220, 300, function()
        dashboard.handlers.cook()
    end)
    dashboard.cookLabel = uiText(settings, 310, -220, 410, "GameFontHighlightSmall")
    uiText(settings, 0, -264, 720):SetText(
        "Each ruleset/faction group has one Cooking/Fishing recipient. Click again to clear.\n"
            .. "Faction is observed on login. Confirm ruleset here if absent from the realm name."
    )
    uiText(settings, 0, -324, 320):SetText("5 x level benchmark ceiling (assumption)")
    local ceiling = uiFrame("EditBox", settings, "InputBoxTemplate")
    ceiling:SetSize(80, 28)
    ceiling:SetPoint("TOPLEFT", 330, -314)
    ceiling:SetAutoFocus(false)
    ceiling:SetMaxLetters(5)
    ceiling:SetScript("OnEscapePressed", function()
        ceiling:ClearFocus()
    end)
    local function saveCeiling()
        local value = tonumber(ceiling:GetText())
        ceiling:ClearFocus()
        dashboard.handlers.professionCeiling(value)
    end
    ceiling:SetScript("OnEnterPressed", saveCeiling)
    dashboard.professionCeiling = ceiling
    uiButton(settings, "Save ceiling", 430, -316, 140, saveCeiling)
    planningControls(frame)
    dashboardGraphics(frame)
    if type(_G.UISpecialFrames) == "table" then
        local found = false
        for _, name in ipairs(_G.UISpecialFrames) do
            found = found or name == "RQMainWindow"
        end
        if not found then
            table.insert(_G.UISpecialFrames, "RQMainWindow")
        end
        capabilities.rosterWindowEscape = "available"
    else
        capabilities.rosterWindowEscape = "missing UISpecialFrames; use Close or /rq close"
    end
end

function Api.RenderRosterWindow(view, handlers, position)
    if Api.IsInCombat() ~= false then
        return false, "Combat or combat-state API unavailable."
    end
    if dashboardFailure then
        return false, dashboardFailure
    end
    local ok, err = uiOperation("rosterWindow", function()
        if not dashboard then
            createDashboard(position, handlers)
        end
        dashboard.handlers = handlers
        dashboard.groceryOwner = view.bagCharacterId or view.selectedId
        dashboard.groceryOwnerName = view.bagCharacterId and view.bagOwnerLabel or view.characterLabel
        dashboard.title:SetText("ROSTER QUARTERMASTER")
        dashboard.realmControl:SetText(view.realms[view.realm])
        dashboard.groupControl:SetText(view.groups[view.group])
        dashboard.status:SetText(
            view.status ~= "" and view.status or "Cached observations  |  " .. RQ.version .. "  |  Drag to move"
        )
        enable(dashboard.rosterTab, view.tab ~= "roster" and view.tab ~= "today")
        enable(dashboard.settingsTab, view.primaryTab ~= "settings")
        enable(dashboard.suppliesTab, view.primaryTab ~= "bags")
        enable(dashboard.professionsTab, view.primaryTab ~= "professions")
        if view.tab ~= "planning" then
            dashboard.planningPanel:Hide()
        end
        if dashboard.renderedTab ~= view.tab then
            dashboard.scroll:SetVerticalScroll(0)
        end
        local graphical = view.tab == "roster" or view.tab == "today"
        dashboard.professionControls:Hide()
        dashboard.recipePrevious:Hide()
        dashboard.recipeNext:Hide()
        dashboard.newNeed:Hide()
        if view.tab ~= "bags" then
            dashboard.bagSearch:Hide()
            dashboard.bagQueryInput:ClearFocus()
        end
        if not graphical then
            dashboard.graphicControls:Hide()
            dashboard.detailScroll:Hide()
            dashboard.graphicEmpty:Hide()
            for _, row in ipairs(dashboard.graphicRows) do
                row:Hide()
            end
            dashboard.scroll:ClearAllPoints()
            dashboard.scroll:SetPoint("TOPLEFT", 18, -128)
            dashboard.scroll:SetPoint("BOTTOMRIGHT", -38, 42)
            dashboard.content:SetWidth(728)
        end
        if view.tab == "bags" then
            dashboard.bagSearch:Show()
            dashboard.bagSearch:ClearAllPoints()
            dashboard.bagSearch:SetPoint("TOPLEFT", 0, view.inventorySection == "stock" and -80 or -40)
            dashboard.bagSearch:SetPoint("BOTTOMRIGHT", 0, 0)
            if dashboard.bagQuery ~= view.bagQuery then
                dashboard.bagQueryInput:SetText(view.bagQuery)
            end
            if
                dashboard.bagQuery ~= view.bagQuery
                or dashboard.bagOwner ~= view.bagCharacterId
                or dashboard.bagSource ~= view.bagSource
                or dashboard.inventoryPageIndex ~= view.inventoryPage
                or dashboard.inventorySection ~= view.inventorySection
                or dashboard.groceryFilter ~= view.groceryFilter
            then
                dashboard.scroll:SetVerticalScroll(0)
            end
            dashboard.bagQuery, dashboard.bagOwner = view.bagQuery, view.bagCharacterId
            dashboard.bagSource = view.bagSource
            dashboard.inventoryPageIndex, dashboard.inventorySection = view.inventoryPage, view.inventorySection
            dashboard.groceryFilter = view.groceryFilter
            enable(dashboard.inventoryPrevious, view.inventoryPage > 1)
            enable(dashboard.inventoryNext, view.inventoryPage < view.inventoryPageCount)
            enable(dashboard.copyInventory, view.bagQuery ~= "")
            dashboard.inventoryPage:SetText(
                "Page "
                    .. view.inventoryPage
                    .. " / "
                    .. view.inventoryPageCount
                    .. "  |  "
                    .. #view.allCards
                    .. " entries"
            )
            dashboard.bagOwnerLabel:SetText("Owner: " .. view.bagOwnerLabel)
            place(dashboard.inventoryPage, 344, 182 + dashboard.bagOwnerLabel:GetStringHeight())
            for section, button in pairs(dashboard.inventorySections) do
                enable(button, view.inventorySection ~= section or view.bagQuery ~= "")
            end
            local groceries = view.inventorySection == "stock" and view.bagQuery == ""
            dashboard.bagSourceButton:SetText(
                groceries and ("Show: " .. RQ.WorkspaceView.groceryFilters[view.groceryFilter])
                    or ("Source: " .. view.bagSource)
            )
            enable(dashboard.bagSourceButton, groceries or view.inventorySection == "recorded" or view.bagQuery ~= "")
            place(dashboard.bagSourceButton, 18, 174 + dashboard.bagOwnerLabel:GetStringHeight())
            enable(dashboard.bagOwnerButton, #view.bagOwnerIds > 0)
            dashboard.scroll:ClearAllPoints()
            dashboard.scroll:SetPoint(
                "TOPLEFT",
                18,
                (groceries and -290 or -250) - dashboard.bagOwnerLabel:GetStringHeight()
            )
            dashboard.scroll:SetPoint("BOTTOMRIGHT", -38, 42)
        end
        if view.primaryTab == "professions" then
            dashboard.professionControls:Show()
            enable(dashboard.newNeed, view.tab == "bags" and view.isMember)
            if view.tab == "bags" then
                dashboard.newNeed:Show()
            elseif view.tab == "recipes" then
                dashboard.recipePrevious:Show()
                dashboard.recipeNext:Show()
                enable(dashboard.recipePrevious, view.recipePage > 1)
                enable(dashboard.recipeNext, view.recipePage < view.recipePageCount)
                if dashboard.recipePage ~= view.recipePage then
                    dashboard.scroll:SetVerticalScroll(0)
                end
                dashboard.recipePage = view.recipePage
                if view.status == "" then
                    dashboard.status:SetText(
                        "Recipes page "
                            .. view.recipePage
                            .. " / "
                            .. view.recipePageCount
                            .. " | Cached recipe and price observations"
                    )
                end
            end
            if view.tab ~= "bags" then
                dashboard.scroll:ClearAllPoints()
                dashboard.scroll:SetPoint("TOPLEFT", 18, -166)
                dashboard.scroll:SetPoint("BOTTOMRIGHT", -38, 42)
            end
        end
        if
            view.tab == "roster"
            or view.tab == "today"
            or view.tab == "supplies"
            or view.tab == "recipes"
            or view.tab == "mail"
            or view.tab == "shipments"
            or view.tab == "professions"
            or view.tab == "advice"
            or view.tab == "bags"
        then
            dashboard.settings:Hide()
            dashboard.scroll:Show()
            if graphical then
                renderGraphics(view)
            else
                local y = 0
                for index, card in ipairs(view.cards) do
                    local row = dashboard.cards[index]
                    if not row then
                        row = uiFrame("Frame", dashboard.content)
                        row:SetWidth(724)
                        local background = row:CreateTexture(nil, "BACKGROUND")
                        background:SetAllPoints()
                        background:SetColorTexture(0.075, 0.092, 0.115, 0.95)
                        row.title = uiText(row, 12, -10, 696, "GameFontNormal")
                        row.body = uiText(row, 12, -36, 696)
                        row.metrics = {}
                        row.details = uiButton(row, "Details", 12, -10, 120, function()
                            if row.card then
                                if row.card.groceryItem then
                                    dashboard.handlers.groceryDetails(row.card.id, row.card.itemId)
                                else
                                    Api.ShowCopyWindow(row.card.title, row.card.body)
                                end
                            end
                        end)
                        row.button = uiButton(row, "Configure", 580, -10, 130, function()
                            if row.actionKind == "inventory-expand" then
                                dashboard.handlers.inventoryExpand(row.card.id, row.card.source)
                            elseif row.actionKind == "grocery-need" then
                                dashboard.handlers.need(
                                    row.characterId,
                                    row.itemId,
                                    tonumber(row.targetInput:GetText())
                                )
                                row.targetInput:ClearFocus()
                            elseif row.actionKind == "supplies" then
                                dashboard.handlers.supplies(row.characterId)
                            elseif row.actionKind == "recipe-goal" then
                                local target = tonumber(row.targetInput:GetText())
                                row.targetInput:ClearFocus()
                                dashboard.handlers.recipeGoal(row.characterId, row.professionId, row.recipeId, target)
                            elseif row.actionKind == "back-supplies" then
                                dashboard.handlers.tab("supplies")
                            elseif row.actionKind == "mail-attach" then
                                dashboard.handlers.attach(row.characterId, row.itemId)
                            elseif row.actionKind == "shipments" then
                                dashboard.handlers.shipments()
                            elseif row.actionKind == "inbox-refresh" then
                                dashboard.handlers.inbox()
                            elseif row.actionKind == "shipment-confirm" then
                                dashboard.handlers.shipmentConfirm(row.shipmentId)
                            elseif row.actionKind == "shipment-close" then
                                dashboard.handlers.shipmentClose(row.shipmentId)
                            elseif row.actionKind == "profession-plan" then
                                dashboard.handlers.professionPlan(row.characterId, row.professionChoices)
                            elseif row.actionKind == "profession-clear" then
                                dashboard.handlers.professionPlan(row.characterId, {})
                            elseif row.actionKind == "profession-focus" then
                                dashboard.handlers.professionFocus(row.characterId)
                            elseif row.actionKind == "mail-refresh" or row.actionKind == "mail-text" then
                                dashboard.handlers.mail(row.actionKind == "mail-text")
                            elseif row.actionKind == "bag-refresh" then
                                dashboard.handlers.rescan()
                            elseif row.actionKind == "inventory-copy" then
                                dashboard.handlers.copyBagSearch()
                            else
                                dashboard.handlers.configure(row.characterId)
                            end
                        end)
                        row.recipesButton = uiButton(row, "Orange recipes", 12, -10, 140, function()
                            dashboard.handlers.recipes(row.characterId)
                        end)
                        row.recipesButton:ClearAllPoints()
                        row.recipesButton:SetPoint("BOTTOMLEFT", 12, 10)
                        row.targetLabel = uiText(row, 12, -10, 100)
                        row.targetLabel:ClearAllPoints()
                        row.targetLabel:SetPoint("BOTTOMLEFT", 12, 16)
                        row.targetLabel:SetText("Target skill:")
                        row.targetInput = uiFrame("EditBox", row, "InputBoxTemplate")
                        row.targetInput:SetSize(80, 24)
                        row.targetInput:SetPoint("BOTTOMLEFT", 120, 10)
                        row.targetInput:SetAutoFocus(false)
                        row.targetInput:SetMaxLetters(7)
                        row.targetInput:SetScript("OnEscapePressed", function()
                            row.targetInput:ClearFocus()
                            Api.HideRosterWindow()
                        end)
                        dashboard.cards[index] = row
                    end
                    local sameRecipe = row.characterId == card.id
                        and row.professionId == card.professionId
                        and row.recipeId == card.recipeId
                        and row.itemId == card.itemId
                        and row.actionKind == card.actionKind
                    row.characterId = card.id
                    row.card = card
                    row.professionId, row.recipeId = card.professionId, card.recipeId
                    row.itemId = card.itemId
                    row.actionKind = card.actionKind
                    row.taskId, row.taskState, row.signature = card.taskId, card.taskState, card.signature
                    row.shipmentId = card.shipmentId
                    row.professionChoices = card.professionChoices
                    enable(row.button, not card.disabled)
                    row.recipesButton:Hide()
                    row.recipesButton:SetText(card.dismissAction and "Dismiss" or "Orange recipes")
                    if card.recipesAction or card.dismissAction then
                        row.recipesButton:Show()
                    end
                    if card.actionKind == "recipe-goal" or card.actionKind == "grocery-need" then
                        row.targetLabel:SetText(card.actionKind == "grocery-need" and "Min stock:" or "Target skill:")
                        if not sameRecipe then
                            row.targetInput:ClearFocus()
                        end
                        if not sameRecipe or not row.targetInput:HasFocus() then
                            row.targetInput:SetText(tostring(card.targetSkill or card.stockTarget or 0))
                        end
                        row.targetLabel:Show()
                        row.targetInput:Show()
                    else
                        row.targetInput:ClearFocus()
                        row.targetInput:Hide()
                        row.targetLabel:Hide()
                    end
                    if (card.icon or card.itemId) and not row.itemIcon then
                        row.itemIcon = row:CreateTexture(nil, "ARTWORK")
                        row.itemIcon:SetPoint("TOPLEFT", 12, -10)
                        row.itemIcon:SetSize(32, 32)
                    end
                    if row.itemIcon then
                        if card.icon or card.itemId then
                            graphicTexture(row.itemIcon, card.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                        else
                            row.itemIcon:Hide()
                        end
                    end
                    row.title:ClearAllPoints()
                    local hasIcon = card.icon or card.itemId
                    row.title:SetPoint("TOPLEFT", hasIcon and 52 or 12, -10)
                    row.title:SetWidth(hasIcon and 656 or 696)
                    row.title:SetText(card.title)
                    local titleHeight = row.title:GetStringHeight()
                    if hasIcon then
                        titleHeight = math.max(32, titleHeight)
                    end
                    row.body:ClearAllPoints()
                    row.body:SetPoint("TOPLEFT", 12, -titleHeight - 20)
                    row.body:SetText(
                        card.expanded and (card.summary .. "\n\n" .. card.body) or card.summary or card.body
                    )
                    local metricY = titleHeight + row.body:GetStringHeight() + 32
                    local bandHeight, metricHeight = 0, 0
                    local columns = card.groceryItem and 6 or 3
                    local cellWidth = 702 / columns
                    for metricIndex, metric in ipairs(card.metrics or {}) do
                        local cell = row.metrics[metricIndex]
                        if not cell then
                            cell = {
                                label = uiText(row, 0, 0, 212, "GameFontHighlightSmall"),
                                value = uiText(row, 0, 0, 212, "GameFontNormalLarge"),
                            }
                            row.metrics[metricIndex] = cell
                        end
                        local x = 16 + ((metricIndex - 1) % columns) * cellWidth
                        cell.label:SetWidth(cellWidth - 22)
                        cell.value:SetWidth(cellWidth - 22)
                        place(cell.label, x, metricY + metricHeight)
                        cell.label:SetText(metric.label)
                        place(cell.value, x, metricY + metricHeight + cell.label:GetStringHeight() + 6)
                        cell.value:SetText(metric.value)
                        if type(cell.value.SetTextColor) == "function" then
                            if metric.tone == "positive" then
                                cell.value:SetTextColor(0.45, 0.85, 0.65)
                            elseif metric.tone == "warning" then
                                cell.value:SetTextColor(1, 0.70, 0.30)
                            else
                                cell.value:SetTextColor(0.92, 0.82, 0.56)
                            end
                        end
                        cell.label:Show()
                        cell.value:Show()
                        bandHeight =
                            math.max(bandHeight, cell.label:GetStringHeight() + cell.value:GetStringHeight() + 22)
                        if metricIndex % columns == 0 or metricIndex == #card.metrics then
                            metricHeight, bandHeight = metricHeight + bandHeight, 0
                        end
                    end
                    for metricIndex = #(card.metrics or {}) + 1, #row.metrics do
                        row.metrics[metricIndex].label:Hide()
                        row.metrics[metricIndex].value:Hide()
                    end
                    row.details:ClearAllPoints()
                    row.details:SetWidth(card.groceryItem and 170 or 120)
                    row.details:SetText(
                        card.groceryItem and (card.expanded and "Hide details" or "Recipes / details") or "Details"
                    )
                    row.details:SetPoint(
                        "BOTTOMLEFT",
                        (card.actionKind == "recipe-goal" or card.actionKind == "grocery-need") and 224
                            or (card.recipesAction or card.dismissAction) and 168
                            or 12,
                        10
                    )
                    if card.summary and card.body ~= "" then
                        row.details:Show()
                    else
                        row.details:Hide()
                    end
                    local height = metricY + metricHeight + 40
                    if card.compact then
                        height = math.max(48, titleHeight + 16)
                        row.body:Hide()
                        row.details:Hide()
                        row.recipesButton:Hide()
                        row.button:Hide()
                    else
                        row.body:Show()
                    end
                    row:SetAlpha(card.muted and 0.30 or 1)
                    row:SetHeight(height)
                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT", 0, -y)
                    row.button:ClearAllPoints()
                    row.button:SetPoint("BOTTOMRIGHT", -12, 10)
                    row.button:SetText(card.action)
                    if card.compact then
                        row.button:Hide()
                    else
                        row.button:Show()
                    end

                    row:Show()
                    y = y + height + 10
                end
                for index = #view.cards + 1, #dashboard.cards do
                    dashboard.cards[index]:Hide()
                end
                dashboard.content:SetHeight(math.max(1, y))
                dashboard.scroll:SetVerticalScroll(
                    math.min(dashboard.scroll:GetVerticalScroll(), math.max(0, y - dashboard.scroll:GetHeight()))
                )
            end
        elseif view.tab == "planning" then
            dashboard.scroll:Hide()
            dashboard.settings:Hide()
            dashboard.planningPanel:Show()
            for _, field in ipairs(RQ.PlanningFields) do
                local edit = dashboard.planningInputs[field.key]
                if not edit:HasFocus() then
                    edit:SetText(tostring(view.planning[field.key] * field.scale))
                end
            end
            dashboard.planningCharacter:SetText(view.characterLabel)
            enable(dashboard.planningPrevious, #view.characterIds > 1)
            enable(dashboard.planningNext, #view.characterIds > 1)
            for _, button in ipairs({
                dashboard.saveMultiplier,
                dashboard.resetCalibration,
                dashboard.blocker,
                dashboard.dungeon,
            }) do
                enable(button, view.isMember)
            end
            if dashboard.multiplierCharacter ~= view.selectedId or not dashboard.multiplierInput:HasFocus() then
                dashboard.multiplierInput:SetText(tostring(view.multiplier))
                dashboard.multiplierCharacter = view.selectedId
            end
            dashboard.blocker:SetText("Resource blocker: " .. (view.resourceBlocker and "Yes" or "No"))
            dashboard.dungeon:SetText("Dungeon ready: " .. (view.dungeonReady and "Yes" or "No"))
        else
            dashboard.scroll:Hide()
            dashboard.settings:Show()
            dashboard.characterLabel:SetText("Character: " .. view.characterLabel)
            dashboard.characterDetails:SetText(view.characterDetails)
            dashboard.role:SetText("Role: " .. view.roleLabel .. " (next)")
            dashboard.ruleset:SetText("Ruleset: " .. view.ruleset .. (view.canSetRuleset and " (next)" or " (realm)"))
            dashboard.cook:SetText(view.isCook and "Clear Cooking/Fishing assignment" or "Assign Cooking/Fishing")
            dashboard.cookLabel:SetText("Group Cooking/Fishing: " .. view.cookLabel)
            enable(dashboard.ruleset, view.canSetRuleset)
            enable(dashboard.cook, view.canSetCook)
            dashboard.main:SetText(view.isMain and "Current main" or "Make main")
            enable(dashboard.previousCharacter, #view.characterIds > 1)
            enable(dashboard.nextCharacter, #view.characterIds > 1)
            enable(dashboard.add, view.selectedId ~= nil and not view.isMember)
            enable(dashboard.ignore, view.selectedId ~= nil and not view.isIgnored)
            enable(dashboard.main, view.isMember and not view.isMain)
            enable(dashboard.role, view.isMember)
            if not dashboard.professionCeiling:HasFocus() then
                dashboard.professionCeiling:SetText(tostring(view.professionCeiling))
            end
        end
        if view.tab == "activity" then
            dashboard.scroll:SetVerticalScroll(
                math.min(
                    dashboard.scroll:GetVerticalScroll(),
                    math.max(0, dashboard.content:GetHeight() - dashboard.scroll:GetHeight())
                )
            )
        end
        dashboard.frame:Show()
        dashboard.renderedTab = view.tab
    end)
    if not ok then
        dashboardFailure = err
        Api.HideRosterWindow()
    end
    return ok, err
end

local copyWindow

local groceryWindow
local stockEditor
function Api.HideGroceryWindows()
    if groceryWindow then
        groceryWindow:StopMovingOrSizing()
        groceryWindow:Hide()
    end
    if stockEditor then
        stockEditor.item:ClearFocus()
        stockEditor.quantity:ClearFocus()
        stockEditor:Hide()
    end
end

function Api.ShowStockEditor(id, label, save)
    if Api.IsInCombat() ~= false then
        Api.Print("Grocery editor not opened: combat or combat-state API unavailable.")
        return false
    end
    local ok, err = uiOperation("stockEditor", function()
        if not stockEditor then
            local frame = uiFrame("Frame", _G.UIParent, nil, "RQStockEditor")
            stockEditor = frame
            frame:SetSize(360, 190)
            frame:SetPoint("CENTER", _G.UIParent, "CENTER", 0, 0)
            frame:SetFrameStrata("FULLSCREEN_DIALOG")
            frame:EnableMouse(true)
            local background = frame:CreateTexture(nil, "BACKGROUND")
            background:SetAllPoints()
            background:SetColorTexture(0.035, 0.042, 0.055, 1)
            frame.label = uiText(frame, 14, -14, 332)
            uiText(frame, 14, -64, 150):SetText("Item ID")
            uiText(frame, 14, -99, 150):SetText("Minimum (0 clears)")
            frame.item = uiFrame("EditBox", frame, "InputBoxTemplate")
            frame.quantity = uiFrame("EditBox", frame, "InputBoxTemplate")
            for index, edit in ipairs({ frame.item, frame.quantity }) do
                edit:SetSize(130, 26)
                edit:SetPoint("TOPLEFT", 192, -56 - (index - 1) * 35)
                edit:SetAutoFocus(false)
                edit:SetMaxLetters(10)
                edit:SetScript("OnEscapePressed", function()
                    frame:Hide()
                end)
            end
            uiButton(frame, "Save minimum", 14, -144, 155, function()
                if frame.save(frame.owner, tonumber(frame.item:GetText()), tonumber(frame.quantity:GetText())) then
                    frame:Hide()
                end
            end)
            uiButton(frame, "Cancel", 188, -144, 150, function()
                frame:Hide()
            end)
            if type(_G.UISpecialFrames) == "table" then
                table.insert(_G.UISpecialFrames, "RQStockEditor")
            end
        end
        stockEditor.owner, stockEditor.save = id, save
        stockEditor.label:SetText("Grocery minimum: " .. (label or "No character selected"))
        stockEditor.item:SetText("")
        stockEditor.quantity:SetText("")
        stockEditor:Show()
        stockEditor.item:SetFocus()
    end)
    if not ok then
        Api.Print("Grocery editor unavailable: " .. err)
    end
    return ok
end

function Api.IsGroceryWindowShown()
    return groceryWindow ~= nil and groceryWindow:IsShown()
end

function Api.ShowGroceryWindow(scope, lines)
    if Api.IsInCombat() ~= false then
        Api.Print("Compact groceries not opened: combat or combat-state API unavailable.")
        return false
    end
    local ok, err = uiOperation("groceryWindow", function()
        if not groceryWindow then
            local frame = uiFrame("Frame", _G.UIParent, nil, "RQGroceryWindow")
            groceryWindow = frame
            frame:SetSize(390, 420)
            frame:SetPoint("RIGHT", _G.UIParent, "RIGHT", -20, 0)
            frame:SetFrameStrata("DIALOG")
            frame:SetClampedToScreen(true)
            frame:SetMovable(true)
            frame:EnableMouse(true)
            frame:RegisterForDrag("LeftButton")
            frame:SetScript("OnDragStart", function()
                frame:StartMoving()
            end)
            frame:SetScript("OnDragStop", function()
                frame:StopMovingOrSizing()
            end)
            local background = frame:CreateTexture(nil, "BACKGROUND")
            background:SetAllPoints()
            background:SetColorTexture(0.035, 0.042, 0.055, 0.98)
            frame.heading = uiText(frame, 12, -12, 366, "GameFontNormal")
            uiButton(frame, "Close", 294, -380, 80, function()
                frame:Hide()
            end)
            uiButton(frame, "Refresh list", 12, -380, 140, function()
                dashboard.handlers.compactGroceries()
            end)
            local scroll = uiFrame("ScrollFrame", frame, "UIPanelScrollFrameTemplate")
            scroll:SetPoint("TOPLEFT", 12, -62)
            scroll:SetPoint("BOTTOMRIGHT", -32, 48)
            frame.scroll = scroll
            local content = uiFrame("Frame", scroll)
            content:SetWidth(338)
            frame.text = uiText(content, 0, 0, 338, "GameFontHighlightSmall")
            frame.content = content
            scroll:SetScrollChild(content)
            scroll:EnableMouseWheel(true)
            scroll:SetScript("OnMouseWheel", function(_, delta)
                scroll:SetVerticalScroll(
                    math.max(
                        0,
                        math.min(
                            math.max(0, content:GetHeight() - scroll:GetHeight()),
                            scroll:GetVerticalScroll() - delta * 24
                        )
                    )
                )
            end)
        end
        groceryWindow.heading:SetText("GROCERIES\n" .. scope)
        groceryWindow.scroll:ClearAllPoints()
        groceryWindow.scroll:SetPoint("TOPLEFT", 12, -24 - groceryWindow.heading:GetStringHeight())
        groceryWindow.scroll:SetPoint("BOTTOMRIGHT", -32, 48)
        groceryWindow.text:SetText(table.concat(lines, "\n\n"))
        groceryWindow.content:SetHeight(groceryWindow.text:GetStringHeight())
        local maximum = math.max(0, groceryWindow.content:GetHeight() - groceryWindow.scroll:GetHeight())
        groceryWindow.scroll:SetVerticalScroll(
            scope ~= groceryWindow.scope and 0 or math.min(groceryWindow.scroll:GetVerticalScroll(), maximum)
        )
        groceryWindow.scope = scope
        groceryWindow:Show()
    end)
    if not ok then
        Api.Print("Compact groceries unavailable: " .. err)
    end
    return ok
end

function Api.HideCopyWindow()
    if copyWindow then
        copyWindow.frame:Hide()
    end
end

function Api.ShowCopyWindow(title, text, onSubmit)
    if Api.IsInCombat() ~= false then
        Api.Print("Copy window unavailable during combat or without a combat-state API.")
        return false
    end
    local ok, err = uiOperation("copyWindow", function()
        if not copyWindow then
            local frame = uiFrame("Frame", _G.UIParent, nil, "RQCopyWindow")
            frame:Hide()
            frame:SetSize(800, 600)
            frame:SetPoint("CENTER")
            frame:SetFrameStrata("FULLSCREEN_DIALOG")
            frame:EnableMouse(true)
            local background = frame:CreateTexture(nil, "BACKGROUND")
            background:SetAllPoints()
            background:SetColorTexture(0.035, 0.035, 0.045, 0.99)
            local heading = uiText(frame, 18, -16, 650, "GameFontNormal")
            uiButton(frame, "Close", 710, -12, 72, Api.HideCopyWindow)
            local scroll = uiFrame("ScrollFrame", frame, "UIPanelScrollFrameTemplate")
            scroll:SetPoint("TOPLEFT", 20, -65)
            scroll:SetPoint("BOTTOMRIGHT", -40, 55)
            local edit = uiFrame("EditBox", scroll)
            edit:SetMultiLine(true)
            edit:SetFontObject("ChatFontNormal")
            edit:SetAutoFocus(false)
            edit:SetMaxLetters(0)
            edit:SetWidth(720)
            edit:SetScript("OnEscapePressed", Api.HideCopyWindow)
            scroll:SetScrollChild(edit)
            frame:SetScript("OnHide", function()
                edit:ClearFocus()
            end)
            uiButton(frame, "Select all - Ctrl+C to copy", 18, -556, 280, function()
                edit:SetFocus()
                edit:HighlightText()
            end)
            local hint = uiText(frame, 450, -556, 330)
            local submit = uiButton(frame, "Preview import", 320, -556, 120, function()
                if copyWindow.onSubmit then
                    copyWindow.onSubmit(edit:GetText())
                end
            end)
            copyWindow = {
                frame = frame,
                edit = edit,
                heading = heading,
                scroll = scroll,
                hint = hint,
                submit = submit,
            }
            if type(_G.UISpecialFrames) == "table" then
                table.insert(_G.UISpecialFrames, "RQCopyWindow")
            end
        end
        copyWindow.heading:SetText(title)
        copyWindow.onSubmit = onSubmit
        if onSubmit then
            copyWindow.submit:Show()
        else
            copyWindow.submit:Hide()
        end
        copyWindow.hint:SetText(
            onSubmit and "Paste configuration, then preview. Nothing is applied yet."
                or "Paste outside the game; editing here does not change saved data."
        )
        copyWindow.edit:SetText(text)
        local rows = 0
        for line in (text .. "\n"):gmatch("(.-)\n") do
            rows = rows + math.max(1, math.ceil(#line / 85))
        end
        copyWindow.edit:SetHeight(math.max(460, rows * 18))
        copyWindow.scroll:SetVerticalScroll(0)
        copyWindow.frame:Show()
        copyWindow.edit:SetFocus()
        copyWindow.edit:HighlightText()
    end)
    if not ok then
        Api.HideCopyWindow()
        Api.Print("Copy window unavailable: " .. err .. ". Use /rq diag or /rq roster text.")
    end
    return ok
end

local stopMinimapDrag

function Api.StopMinimapDrag()
    if stopMinimapDrag then
        stopMinimapDrag(true)
    end
end

local function ownsMinimapPosition(button)
    if button:GetParent() ~= _G.Minimap then
        return false
    end
    local point, relative = button:GetPoint()
    return point == "CENTER" and relative == _G.Minimap
end

local function placeMinimapButton(button, angle)
    local width, height = _G.Minimap:GetWidth(), _G.Minimap:GetHeight()
    if not RQ.Util.IsNumber(width) or width == 0 or not RQ.Util.IsNumber(height) or height == 0 then
        error("Minimap size unavailable.")
    end
    local radians = math.rad(angle)
    button:ClearAllPoints()
    button:SetPoint(
        "CENTER",
        _G.Minimap,
        "CENTER",
        math.cos(radians) * (width / 2 + 5),
        math.sin(radians) * (height / 2 + 5)
    )
end

function Api.RefreshMinimapPosition()
    if not minimapButton then
        return true
    end
    local ok, err = uiOperation("minimapPosition", function()
        if stopMinimapDrag then
            stopMinimapDrag(false)
        end
        if ownsMinimapPosition(minimapButton) then
            placeMinimapButton(minimapButton, RQ.Database.initialized and RQDB.settings.minimapAngle or 225)
        end
    end)
    if not ok then
        Api.Print("Minimap position unavailable: " .. err)
    end
    return ok
end

function Api.CreateMinimapButton(onClick)
    if minimapButton then
        return true
    end
    if minimapFailure then
        return false
    end
    if not _G.Minimap then
        capabilities.minimapButton = "missing Minimap; use /rq"
        return false
    end
    local created
    local ok, err = uiOperation("minimapButton", function()
        -- Minimap collectors use stable frame names to discover and remember buttons.
        created = uiFrame("Button", _G.Minimap, nil, "RQMinimapButton")
        created:Hide()
        local strata = _G.Minimap:GetFrameStrata()
        if strata == "BACKGROUND" or strata == "LOW" then
            strata = "MEDIUM"
        end
        created:SetFrameStrata(strata)
        created:SetFrameLevel(_G.Minimap:GetFrameLevel() + 8)
        created:SetSize(32, 32)
        created:EnableMouse(true)
        created:SetMovable(true)
        placeMinimapButton(created, RQ.Database.initialized and RQDB.settings.minimapAngle or 225)
        local background = created:CreateTexture(nil, "BACKGROUND")
        background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
        background:SetSize(24, 24)
        background:SetPoint("CENTER", created, "CENTER", 1, 1)
        local icon = created:CreateTexture(nil, "ARTWORK")
        icon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
        icon:SetSize(20, 20)
        icon:SetPoint("CENTER", created, "CENTER", 1, 1)
        icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
        created.icon = icon
        if type(created.CreateMaskTexture) == "function" and type(icon.AddMaskTexture) == "function" then
            local masked, maskError = uiOperation("minimapMask", function()
                local mask = created:CreateMaskTexture()
                mask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
                mask:SetAllPoints(icon)
                icon:AddMaskTexture(mask)
            end)
            if not masked then
                Api.Print("Minimap icon mask unavailable; using native round border: " .. maskError)
            end
        else
            capabilities.minimapMask = "unavailable; native round border retained"
        end
        local border = created:CreateTexture(nil, "OVERLAY")
        border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
        border:SetSize(54, 54)
        border:SetPoint("TOPLEFT", created, "TOPLEFT", 0, 0)
        created:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
        local label = created:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("CENTER")
        label:SetText("RQ")
        created:RegisterForClicks("LeftButtonUp")
        created:RegisterForDrag("LeftButton")
        local dragging, suppressClick, pendingAngle = false, false, nil
        stopMinimapDrag = function(save)
            dragging = false
            created:SetScript("OnUpdate", nil)
            if save and pendingAngle ~= nil then
                local saved, saveError = RQ.Database.SaveMinimapAngle(pendingAngle)
                if not saved then
                    Api.Print("Minimap position not saved: " .. saveError)
                end
            end
            pendingAngle = nil
        end
        local function updateDrag()
            local updated, dragError = uiOperation("minimapDrag", function()
                if not ownsMinimapPosition(created) or Api.IsInCombat() ~= false then
                    stopMinimapDrag(true)
                    return
                end
                local cursor = call("GetCursorPosition")
                local scale = _G.Minimap:GetEffectiveScale()
                local centerX, centerY = _G.Minimap:GetCenter()
                if
                    not cursor
                    or not RQ.Util.IsFinite(cursor[2])
                    or not RQ.Util.IsFinite(cursor[3])
                    or not RQ.Util.IsNumber(scale)
                    or scale == 0
                    or not RQ.Util.IsFinite(centerX)
                    or not RQ.Util.IsFinite(centerY)
                then
                    error("Cursor position or minimap geometry unavailable.")
                end
                local x, y = cursor[2] / scale - centerX, cursor[3] / scale - centerY
                if x == 0 and y == 0 then
                    return
                end
                local angle = math.deg(math.atan2(y, x)) % 360
                placeMinimapButton(created, angle)
                pendingAngle = angle
            end)
            if not updated then
                stopMinimapDrag(true)
                Api.Print("Minimap drag unavailable: " .. dragError)
            end
        end
        created:SetScript("OnDragStart", function()
            if not ownsMinimapPosition(created) then
                return
            end
            if Api.IsInCombat() ~= false or not RQ.Database.initialized then
                Api.Print("Minimap dragging requires being out of combat and initialized SavedVariables.")
                return
            end
            dragging, suppressClick, pendingAngle = true, true, nil
            created:SetScript("OnUpdate", updateDrag)
            updateDrag()
        end)
        created:SetScript("OnDragStop", function()
            stopMinimapDrag(true)
        end)
        created:SetScript("OnHide", function()
            stopMinimapDrag(true)
        end)
        created:SetScript("OnMouseDown", function()
            if not dragging then
                suppressClick = false
            end
        end)
        created:SetScript("OnClick", function(...)
            if dragging or suppressClick then
                suppressClick = false
                return
            end
            onClick(...)
        end)
        created:SetScript("OnEnter", function()
            if not _G.GameTooltip then
                capabilities.minimapTooltip = "missing GameTooltip"
                return
            end
            local shown, tooltipError = uiOperation("minimapTooltip", function()
                _G.GameTooltip:SetOwner(created, "ANCHOR_LEFT")
                _G.GameTooltip:SetText("Roster Quartermaster")
                _G.GameTooltip:AddLine("Click to open or close the roster dashboard.", 1, 1, 1)
                _G.GameTooltip:AddLine("Drag with the left mouse button to move around the minimap.", 1, 1, 1)
                _G.GameTooltip:Show()
            end)
            if not shown then
                Api.Print("Minimap tooltip unavailable: " .. tooltipError)
            end
        end)
        created:SetScript("OnLeave", function()
            if _G.GameTooltip then
                local hidden, tooltipError = uiOperation("minimapTooltip", function()
                    _G.GameTooltip:Hide()
                end)
                if not hidden then
                    Api.Print("Cannot hide minimap tooltip: " .. tooltipError)
                end
            end
        end)
        created:Show()
    end)
    if not ok then
        minimapFailure = err
        if created then
            created:Hide()
        end
        Api.Print("Minimap button unavailable: " .. err .. " Use /rq.")
        return false
    end
    minimapButton = created
    return true
end
