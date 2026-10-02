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
        displayName = identityText("UnitName", "player"),
        realm = identityText("GetRealmName"),
    }
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
    return scalar("GetMoney", "number")
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
            then
                capabilities.GetProfessionInfo = "invalid profession data or missing skill-line ID"
                return nil
            end
            professions[id] = { name = name, skill = skill, maxSkill = maxSkill }
        end
    end
    return professions
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
        Api.Print("Registration window unavailable; use /rq add, /rq link <slot>, or /rq ignore.")
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

function Api.MarkEventObserved(event)
    capabilities["event:" .. event] = "observed"
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
    background:SetColorTexture(0.035, 0.035, 0.045, 0.97)
    dashboard.title = uiText(frame, 18, -16, 610, "GameFontNormalLarge")
    uiButton(frame, "Close", 712, -12, 72, Api.HideRosterWindow)
    dashboard.rosterTab = uiButton(frame, "Roster", 18, -48, 120, function()
        dashboard.handlers.tab("roster")
    end)
    dashboard.settingsTab = uiButton(frame, "Settings", 146, -48, 120, function()
        dashboard.handlers.tab("settings")
    end)
    uiButton(frame, "Rescan current", 618, -48, 166, function()
        dashboard.handlers.rescan()
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
    local settings = uiFrame("Frame", frame)
    settings:SetPoint("TOPLEFT", 18, -88)
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
    dashboard.unlink = uiButton(settings, "Unlink slot", 310, -140, 160, function()
        dashboard.handlers.unlink()
    end)
    dashboard.slotLabel = uiText(settings, 0, -208, 720, "GameFontNormal")
    dashboard.previousSlot = uiButton(settings, "Previous", 0, -238, 100, function()
        dashboard.handlers.slot(-1)
    end)
    dashboard.nextSlot = uiButton(settings, "Next", 108, -238, 100, function()
        dashboard.handlers.slot(1)
    end)
    dashboard.slotDetails = uiText(settings, 228, -236, 500)
    uiText(settings, 0, -288, 112):SetText("Planned name")
    local edit = uiFrame("EditBox", settings, "InputBoxTemplate")
    edit:SetSize(380, 28)
    edit:SetPoint("TOPLEFT", 120, -278)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(64)
    edit:SetScript("OnEscapePressed", function()
        edit:ClearFocus()
        Api.HideRosterWindow()
    end)
    local function rename()
        local name = edit:GetText()
        edit:ClearFocus()
        dashboard.handlers.rename(name)
    end
    edit:SetScript("OnEnterPressed", rename)
    dashboard.name = edit
    dashboard.saveName = uiButton(settings, "Save name", 516, -280, 130, rename)
    dashboard.link = uiButton(settings, "Link selected character", 0, -328, 240, function()
        dashboard.handlers.register("link")
    end)
    uiText(settings, 0, -374, 720):SetText(
        "Role button cycles through the supported roles. Main/role controls require an enabled member.\n"
            .. "To change slots, unlink first. Ignore keeps the existing link; Add / resume enables tracking again.\n"
            .. "Selecting an offline character changes configuration only; it never logs into that character."
    )
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
        dashboard.title:SetText("Roster Quartermaster " .. RQ.version)
        dashboard.status:SetText(
            view.status ~= "" and view.status
                or "Last observed snapshots. Drag the window to move it; Esc or Close to dismiss."
        )
        enable(dashboard.rosterTab, view.tab ~= "roster")
        enable(dashboard.settingsTab, view.tab ~= "settings")
        if view.tab == "roster" then
            dashboard.settings:Hide()
            dashboard.scroll:Show()
            local y = 0
            for index, card in ipairs(view.cards) do
                local row = dashboard.cards[index]
                if not row then
                    row = uiFrame("Frame", dashboard.content)
                    row:SetWidth(724)
                    local background = row:CreateTexture(nil, "BACKGROUND")
                    background:SetAllPoints()
                    background:SetColorTexture(0.12, 0.12, 0.14, 0.8)
                    row.title = uiText(row, 12, -10, 696, "GameFontNormal")
                    row.body = uiText(row, 12, -36, 696)
                    row.button = uiButton(row, "Configure", 580, -10, 130, function()
                        dashboard.handlers.configure(row.characterId, row.slotId)
                    end)
                    dashboard.cards[index] = row
                end
                row.characterId, row.slotId = card.id, card.slotId
                row.title:SetText(card.title)
                local titleHeight = row.title:GetStringHeight()
                row.body:ClearAllPoints()
                row.body:SetPoint("TOPLEFT", 12, -titleHeight - 20)
                row.body:SetText(card.body)
                local height = titleHeight + row.body:GetStringHeight() + 64
                row:SetHeight(height)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, -y)
                row.button:ClearAllPoints()
                row.button:SetPoint("BOTTOMRIGHT", -12, 10)
                row.button:SetText(card.action)
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
        else
            dashboard.scroll:Hide()
            dashboard.settings:Show()
            dashboard.characterLabel:SetText("Character: " .. view.characterLabel)
            dashboard.characterDetails:SetText(view.characterDetails)
            dashboard.slotLabel:SetText("Provisional slot: " .. view.slotLabel)
            dashboard.slotDetails:SetText(view.slotDetails)
            dashboard.role:SetText("Role: " .. view.roleLabel .. " (next)")
            dashboard.main:SetText(view.isMain and "Current main" or "Make main")
            enable(dashboard.previousCharacter, #view.characterIds > 1)
            enable(dashboard.nextCharacter, #view.characterIds > 1)
            enable(dashboard.previousSlot, #view.slotIds > 1)
            enable(dashboard.nextSlot, #view.slotIds > 1)
            enable(dashboard.add, view.selectedId ~= nil and not view.isMember)
            enable(dashboard.ignore, view.selectedId ~= nil and not view.isIgnored)
            enable(dashboard.main, view.isMember and not view.isMain)
            enable(dashboard.role, view.isMember)
            enable(dashboard.unlink, view.canUnlink)
            enable(dashboard.link, view.canLink)
            enable(dashboard.saveName, view.selectedSlot ~= nil)
            if dashboard.editingSlot ~= view.selectedSlot or not dashboard.name:HasFocus() then
                dashboard.name:SetText(view.slotName)
                dashboard.editingSlot = view.selectedSlot
            end
        end
        dashboard.frame:Show()
    end)
    if not ok then
        dashboardFailure = err
        Api.HideRosterWindow()
    end
    return ok, err
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
        created = uiFrame("Button", _G.Minimap)
        created:Hide()
        created:SetSize(28, 28)
        created:SetPoint("BOTTOMLEFT", _G.Minimap, "BOTTOMLEFT", -8, -8)
        created:SetNormalTexture("Interface\\Icons\\INV_Misc_Note_01")
        created:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
        local label = created:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("CENTER")
        label:SetText("RQ")
        created:RegisterForClicks("LeftButtonUp")
        created:SetScript("OnClick", onClick)
        created:SetScript("OnEnter", function()
            if not _G.GameTooltip then
                capabilities.minimapTooltip = "missing GameTooltip"
                return
            end
            local shown, tooltipError = uiOperation("minimapTooltip", function()
                _G.GameTooltip:SetOwner(created, "ANCHOR_LEFT")
                _G.GameTooltip:SetText("Roster Quartermaster")
                _G.GameTooltip:AddLine("Click to open or close the roster dashboard.", 1, 1, 1)
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
