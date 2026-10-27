local Panel = {}
RQ.BagPanel = Panel

local function name(account, id)
    local record = account.characters[id]
    return record and RQ.Character.DisplayName(record.identity) or id
end

local function sourceText(source, now)
    return "Source: "
        .. (source.source == "bank" and "Bank" or source.source == "mail" and "In mail" or "Bags")
        .. " | "
        .. source.state
        .. " | Observed "
        .. RQ.CharacterCard.Age(source.scannedAt, now)
        .. " (timestamp "
        .. source.scannedAt
        .. ")"
        .. (source.error and ("\nLast scan error: " .. RQ.CharacterCard.Text(source.error)) or "")
        .. (
            source.source == "bank"
                and source.coherent == false
                and "\nBank/carried totals are unconfirmed; cached counts are not credited for planning."
            or ""
        )
end

function Panel.SearchCards(result, now)
    local text = RQ.CharacterCard.Text
    local states = result.states
    local cards = {
        {
            title = "Inventory search: " .. text(result.query),
            body = #result.matches
                .. " item/owner match(es) across "
                .. result.ownersWithMatches
                .. " character(s).\n"
                .. "Coverage: "
                .. result.ownerCount
                .. " registered member(s), "
                .. #result.coverage
                .. " source snapshot(s); "
                .. states.RECENT
                .. " recent, "
                .. states.STALE
                .. " stale, "
                .. states.INCOMPLETE
                .. " incomplete, "
                .. states.UNKNOWN
                .. " unknown.\n"
                .. "Unresolved item names: "
                .. result.unresolvedNames
                .. " distinct item ID(s); name matches may be incomplete. Exact item IDs remain searchable.\n"
                .. "Sources: "
                .. result.sourceFilter
                .. ". Bank and inbox contents are cached while offline; pending mail is provisional.\n"
                .. "Bags, bank and mail are separate observations, not a combined available-stock total.\n"
                .. "Bound/reserved items and disabled members are included. "
                .. "Counts are observations, not available surplus."
                .. (#result.matches == 0 and "\nNo known matches; this does not prove the item is absent." or ""),
            action = "Copy results",
            actionKind = "inventory-copy",
        },
    }
    for _, match in ipairs(result.matches) do
        local containers = {}
        local mailNote = ""
        if match.source == "mail" then
            mailNote = "\nIncludes pending shipment stock: "
                .. (match.pending or 0)
                .. ". Inbox observations may be stale, COD or returned; inspect mailbox before use."
            for _, origin in ipairs(match.origins or {}) do
                mailNote = mailNote
                    .. "\nFrom "
                    .. text(origin.sender)
                    .. ": "
                    .. origin.quantity
                    .. " | "
                    .. origin.state
                    .. " | observed "
                    .. origin.at
                    .. (origin.transferId and (" | shipment " .. origin.transferId) or "")
            end
        end
        for _, container in ipairs(match.containers or {}) do
            containers[#containers + 1] = "Bank container "
                .. container.id
                .. ": "
                .. container.count
                .. " item(s), "
                .. container.capacity
                .. " slots"
        end
        cards[#cards + 1] = {
            id = match.characterId,
            itemId = match.itemId,
            icon = result.icons and result.icons[match.itemId],
            title = match.quantity
                .. " x "
                .. text(match.itemName or "Unknown item name")
                .. " ["
                .. match.itemId
                .. "]",
            body = "Owner: "
                .. text(match.characterName)
                .. " - "
                .. text(match.realm)
                .. (not match.enabled and " [DISABLED FOR PLANNING]" or "")
                .. "\nCharacter ID: "
                .. text(match.characterId)
                .. "\n"
                .. sourceText(match, now)
                .. mailNote
                .. (#containers > 0 and ("\n" .. table.concat(containers, "\n")) or "")
                .. (match.source == "bank" and "\nWithdraw manually before crafting or attaching mail." or ""),
            action = "Configure owner",
            actionKind = "inventory-owner",
        }
    end
    for _, coverage in ipairs(result.coverage) do
        if coverage.state ~= "RECENT" then
            cards[#cards + 1] = {
                id = coverage.characterId,
                title = "Uncertain coverage: " .. text(coverage.characterName) .. " - " .. text(coverage.realm),
                body = sourceText(coverage, now)
                    .. "\nCached matches, if any, are shown above. "
                    .. "Visit this character and rescan for current contents.",
                action = "Configure owner",
                actionKind = "inventory-owner",
            }
        end
    end
    return cards
end

function Panel.SearchReport(result, now)
    local lines = {}
    for _, card in ipairs(Panel.SearchCards(result, now)) do
        lines[#lines + 1] = card.title
        lines[#lines + 1] = card.body
    end
    return lines
end

function Panel.Build(account, plan, now)
    local cards = {
        {
            title = "Roster bag upgrades",
            body = "Regular equipped bags only (not the backpack or bank). Existing upgrades before new crafts; "
                .. "otherwise largest observed craftable general-purpose bag, smallest equipped bags first.\n"
                .. "Rescan each member. Open Tailoring and /rq scan-recipes on tailors. "
                .. "Unknown output, capacity or transfer binding stays unknown.\n"
                .. "Stale/incomplete data blocks plans. Materials take mail priority; crafting/equipping are manual.\n"
                .. "Verified personal-bank materials can cover targets after withdrawal. "
                .. "Ready upgrades use carried bags only. Eligible pending/inbox bags can suppress duplicates "
                .. "but stay provisional; drafts never count.",
            action = "Refresh bags",
            actionKind = "bag-refresh",
        },
    }
    for _, id in ipairs(RQ.Util.Keys(plan.bags.members)) do
        local member = plan.bags.members[id]
        local lines = {
            "Bag observation: " .. member.scannedAt .. (member.recent and " | RECENT" or " | STALE / INCOMPLETE"),
        }
        for _, slot in ipairs(RQ.Util.Keys(member.equipped)) do
            local size = member.equipped[slot]
            lines[#lines + 1] = "Bag " .. slot .. ": " .. (size == 0 and "empty" or size .. " slots")
        end
        if not next(member.equipped) then
            lines[#lines + 1] = "Equipped bag sizes unknown; rescan this character."
        end
        local upgrades = 0
        for _, upgrade in ipairs(plan.bags.upgrades) do
            if upgrade.characterId == id then
                upgrades = upgrades + 1
                local action = upgrade.kind == "equip" and "Equip from own bags"
                    or upgrade.kind == "mail" and ("Mail from " .. name(account, upgrade.sourceId))
                    or ("Craft on " .. name(account, upgrade.sourceId) .. " (recipe " .. upgrade.recipeId .. ")")
                lines[#lines + 1] = "Bag "
                    .. upgrade.slot
                    .. ": "
                    .. upgrade.from
                    .. " -> "
                    .. upgrade.to
                    .. " slots | item "
                    .. upgrade.itemId
                    .. " | "
                    .. action
            end
        end
        if upgrades == 0 then
            lines[#lines + 1] =
                "No verified upgrade currently planned; this does not prove better bags are unavailable."
        end
        for _, coverage in ipairs(plan.bags.covered or {}) do
            if coverage.characterId == id then
                lines[#lines + 1] = "PROVISIONAL bag slot "
                    .. coverage.slot
                    .. ": "
                    .. coverage.from
                    .. " -> "
                    .. coverage.to
                    .. " slots | item "
                    .. coverage.itemId
                    .. " | "
                    .. (coverage.state == "pending" and "confirmed pending mail" or "observed inbox mail")
                    .. ". Collect and verify manually; not equip/craft ready."
            end
        end
        for _, recipeId in ipairs(RQ.Util.Keys(plan.bags.crafts[id] or {})) do
            local job = plan.bags.crafts[id][recipeId]
            local recipe = account.characters[id].recipes.professions[197].recipes[recipeId]
            lines[#lines + 1] = "PRIORITY: craft "
                .. job.crafts
                .. " x "
                .. recipe.name
                .. " ["
                .. recipeId
                .. "] for "
                .. job.bags
                .. " bag upgrade(s), "
                .. job.capacity
                .. " slots each."
        end
        for _, recipeId in ipairs(RQ.Util.Keys(plan.bags.conversions[id] or {})) do
            local recipe = account.characters[id].recipes.professions[197].recipes[recipeId]
            lines[#lines + 1] = "First craft material: "
                .. plan.bags.conversions[id][recipeId]
                .. " x "
                .. recipe.name
                .. " ["
                .. recipeId
                .. "]."
        end
        for _, item in ipairs(RQ.Util.Keys(plan.bags.materials[id] or {})) do
            local need = plan.groceries[id][item]
            if need and need.bagPriority then
                lines[#lines + 1] = RQ.SuppliesService.ItemLabel(account, item, account.characters[id])
                    .. " ["
                    .. item
                    .. "]: bag materials "
                    .. need.bagPriority
                    .. ", total reserved target "
                    .. need.target
                    .. ", in bags "
                    .. tostring(need.have or "unknown")
                    .. ", missing "
                    .. tostring(need.missing or "unknown")
                    .. ", bank "
                    .. tostring(need.bankHave or "unknown")
                    .. ", withdraw "
                    .. (need.withdraw or 0)
            end
        end
        for _, note in ipairs(plan.bags.notes[id] or {}) do
            lines[#lines + 1] = note
        end
        cards[#cards + 1] = {
            id = id,
            title = name(account, id),
            body = table.concat(lines, "\n"),
            summary = (member.recent and "RECENT" or "STALE / INCOMPLETE")
                .. "  |  "
                .. upgrades
                .. " planned upgrades\nCraft, collect and equip manually. Details show provisional mail coverage.",
            metrics = {},
            action = "View supplies",
            actionKind = "supplies",
        }
        local card = cards[#cards]
        for _, slot in ipairs(RQ.Util.Keys(member.equipped)) do
            local value = tostring(member.equipped[slot]) .. " slots"
            for _, upgrade in ipairs(plan.bags.upgrades) do
                if upgrade.characterId == id and upgrade.slot == slot then
                    value = value .. " -> " .. upgrade.to
                end
            end
            for _, coverage in ipairs(plan.bags.covered or {}) do
                if coverage.characterId == id and coverage.slot == slot then
                    value = value .. " (mail pending)"
                end
            end
            card.metrics[#card.metrics + 1] = { label = "Bag " .. slot, value = value }
        end
    end
    for _, id in ipairs(RQ.InventorySearch.CharacterIds(account)) do
        local record, lines = account.characters[id], {}
        local bank = record.inventory.bank
        lines[#lines + 1] = "Last personal-bank scan: "
            .. bank.scannedAt
            .. " | "
            .. (bank.complete and bank.coherent and "cached" or "UNKNOWN / INCOMPLETE")
        lines[#lines + 1] = RQ.InventoryAvailability.BankEligible(record, now, account.policies.staleSnapshotHours)
                and "Recent coherent stock: manually withdraw required materials before use."
            or "Not credited for planning; visit the personal bank to verify both sources."
        if bank.error then
            lines[#lines + 1] = bank.error
        end
        for _, containerId in ipairs(RQ.Util.Keys(bank.containers or {})) do
            lines[#lines + 1] = "Bank container "
                .. containerId
                .. ": "
                .. bank.containers[containerId].capacity
                .. " slots"
        end
        cards[#cards + 1] = {
            id = id,
            title = "Personal bank: " .. name(account, id),
            body = table.concat(lines, "\n"),
            summary = lines[2] .. (bank.error and ("\n" .. RQ.CharacterCard.Text(bank.error)) or ""),
            metrics = {
                { label = "Last bank observation", value = RQ.CharacterCard.Age(bank.scannedAt, now) },
                { label = "Coverage", value = bank.complete and bank.coherent and "Cached" or "Unknown" },
            },
            action = "Configure owner",
            actionKind = "inventory-owner",
        }
    end
    return cards
end
