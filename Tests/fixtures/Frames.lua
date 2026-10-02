return function()
    local state = { widgets = {}, combat = false }
    local create
    create = function(kind, name, parent, template)
        local widget = {
            kind = kind,
            parent = parent,
            template = template,
            name = name,
            shown = true,
            enabled = true,
            scripts = {},
            events = {},
            points = {},
            text = "",
            scroll = 0,
        }
        state.widgets[#state.widgets + 1] = widget
        if name then
            _G[name] = widget
        end
        function widget:SetScript(event, callback)
            self.scripts[event] = callback
        end
        function widget:RegisterEvent(event)
            self.events[event] = true
        end
        function widget:SetPoint(point, relative, relativePoint, x, y)
            if type(relative) == "number" then
                x, y, relative, relativePoint = relative, relativePoint, self.parent, point
            end
            self.points[#self.points + 1] = { point, relative or self.parent, relativePoint or point, x or 0, y or 0 }
        end
        function widget:GetPoint()
            return unpack(self.points[#self.points])
        end
        function widget:ClearAllPoints()
            self.points = {}
        end
        function widget:SetSize(width, height)
            self.width, self.height = width, height
        end
        function widget:SetWidth(width)
            self.width = width
        end
        function widget:SetHeight(height)
            self.height = height
        end
        function widget:GetWidth()
            return self.width or 100
        end
        function widget:GetHeight()
            if self.height then
                return self.height
            end
            if #self.points == 2 and self.parent then
                return self.parent:GetHeight() + self.points[1][5] - self.points[2][5]
            end
            return 20
        end
        function widget:Show()
            self.shown = true
        end
        function widget:Hide()
            local wasShown = self.shown
            self.shown = false
            if wasShown and self.scripts.OnHide then
                self.scripts.OnHide(self)
            end
        end
        function widget:IsShown()
            return self.shown
        end
        function widget:IsVisible()
            return self.shown and (not self.parent or self.parent:IsVisible())
        end
        function widget:Enable()
            self.enabled = true
        end
        function widget:Disable()
            self.enabled = false
        end
        function widget:SetText(text)
            assert(type(text) == "string", "UI text must be a string")
            self.text = text
            self.lines = {}
        end
        function widget:GetText()
            return self.text
        end
        function widget:GetStringHeight()
            local lines = 0
            for line in (self.text .. "\n"):gmatch("(.-)\n") do
                lines = lines + math.max(1, math.ceil(#line * 7 / self:GetWidth()))
            end
            return lines * 14
        end
        function widget:CreateTexture()
            return create("Texture", nil, self)
        end
        function widget:CreateFontString()
            return create("FontString", nil, self)
        end
        function widget:SetScrollChild(child)
            self.scrollChild = child
        end
        function widget:SetVerticalScroll(value)
            self.scroll = value
        end
        function widget:GetVerticalScroll()
            return self.scroll
        end
        function widget:HasFocus()
            return self.focus == true
        end
        function widget:SetFocus()
            self.focus = true
        end
        function widget:ClearFocus()
            self.focus = false
        end
        function widget:HighlightText()
            self.highlighted = true
        end
        function widget:StartMoving()
            self.moving = true
        end
        function widget:StopMovingOrSizing()
            self.moving = false
        end
        function widget:SetOwner(owner)
            self.owner = owner
        end
        function widget:AddLine(line)
            self.lines[#self.lines + 1] = line
        end
        for _, method in ipairs({
            "SetFrameStrata",
            "SetClampedToScreen",
            "SetMovable",
            "EnableMouse",
            "RegisterForDrag",
            "SetAllPoints",
            "SetColorTexture",
            "SetJustifyH",
            "SetJustifyV",
            "EnableMouseWheel",
            "SetAutoFocus",
            "SetMaxLetters",
            "SetMultiLine",
            "SetFontObject",
            "SetNormalTexture",
            "SetHighlightTexture",
            "RegisterForClicks",
        }) do
            widget[method] = function() end
        end
        return widget
    end
    _G.UIParent = create("Frame")
    _G.UIParent:SetSize(1920, 1080)
    _G.Minimap = create("Frame", nil, _G.UIParent)
    _G.GameTooltip = create("Tooltip", nil, _G.UIParent)
    _G.GameTooltip:Hide()
    _G.UISpecialFrames = {}
    _G.CreateFrame = create
    _G.InCombatLockdown = function()
        return state.combat
    end
    function state.Emit(event, ...)
        for _, widget in ipairs(state.widgets) do
            if widget.events[event] then
                widget.scripts.OnEvent(widget, event, ...)
            end
        end
    end
    function state.FindButton(text, occurrence)
        occurrence = occurrence or 1
        for _, widget in ipairs(state.widgets) do
            if widget.kind == "Button" and widget.text == text and widget:IsVisible() then
                occurrence = occurrence - 1
                if occurrence == 0 then
                    return widget
                end
            end
        end
        error("No visible button: " .. text)
    end
    function state.Click(button)
        assert(button.enabled and button:IsVisible(), "button must be enabled and visible")
        button.scripts.OnClick(button, "LeftButton")
    end
    function state.FindKind(kind)
        for _, widget in ipairs(state.widgets) do
            if widget.kind == kind and widget:IsVisible() then
                return widget
            end
        end
        error("No visible widget of kind " .. kind)
    end
    function state.MinimapButton()
        for _, widget in ipairs(state.widgets) do
            if widget.kind == "Button" and widget.parent == _G.Minimap then
                return widget
            end
        end
        error("No minimap button")
    end
    return state
end
