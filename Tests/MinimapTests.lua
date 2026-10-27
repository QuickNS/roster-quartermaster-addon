return function(h)
    local test, equal, contains = h.test, h.equal, h.contains
    local function start(strata, level)
        h.fakeCharacter()
        local frames = assert(loadfile("Tests/fixtures/Frames.lua"))()()
        _G.Minimap:SetSize(140, 140)
        _G.Minimap:SetFrameStrata(strata or "LOW")
        _G.Minimap:SetFrameLevel(level or 5)
        local cursor = { x = 200, y = 100 }
        _G.GetCursorPosition = function()
            return cursor.x, cursor.y
        end
        h.loadAddon()
        frames.Emit("PLAYER_LOGIN")
        return frames, frames.MinimapButton(), cursor
    end
    local function near(actual, expected)
        assert(math.abs(actual - expected) < 0.00001, tostring(actual) .. " differs from " .. expected)
    end
    local function position(button, x, y)
        local point, relative, relativePoint, actualX, actualY = button:GetPoint()
        equal(point, "CENTER")
        equal(relative, _G.Minimap)
        equal(relativePoint, "CENTER")
        near(actualX, x)
        near(actualY, y)
    end
    local function drag(button)
        assert(button.scripts.OnDragStart, "Minimap launcher has no drag handler")
        button.scripts.OnDragStart(button)
    end

    test("round minimap button uses native circular border and masked centered icon", function()
        local frames, button = start()
        local border, icon
        for _, widget in ipairs(frames.widgets) do
            if widget.parent == button and widget.kind == "Texture" then
                if widget.texture == "Interface\\Minimap\\MiniMap-TrackingBorder" then
                    border = widget
                elseif widget.texture == "Interface\\Icons\\INV_Misc_Note_01" then
                    icon = widget
                end
            end
        end
        assert(border, "Missing native round tracking-button border")
        assert(icon and icon.mask, "Icon must be circularly masked when mask APIs exist")
        equal(button:GetName(), "RQMinimapButton")
        equal(button:GetWidth(), 32)
        equal(button:GetHeight(), 32)
        equal(icon:GetWidth(), 20)
        equal(icon.mask.texture, "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
        equal(button.dragButtons[1], "LeftButton")
        equal(button.scripts.OnUpdate, nil)
        position(button, math.cos(math.rad(225)) * 75, math.sin(math.rad(225)) * 75)
    end)

    test("launcher renders above minimap layers without overriding collector layering", function()
        for _, strata in ipairs({ "BACKGROUND", "LOW", "MEDIUM", "HIGH" }) do
            local frames, button = start(strata, 20)
            equal(button:GetFrameStrata(), (strata == "BACKGROUND" or strata == "LOW") and "MEDIUM" or strata)
            equal(button:GetFrameLevel(), 28)
            local drawer = _G.CreateFrame("Frame", nil, _G.UIParent)
            button:SetParent(drawer)
            button:SetFrameStrata("LOW")
            button:SetFrameLevel(3)
            frames.Emit("PLAYER_ENTERING_WORLD")
            assert(RQ.Api.RefreshMinimapPosition())
            equal(button:GetFrameStrata(), "LOW")
            equal(button:GetFrameLevel(), 3)
            equal(button:GetParent(), drawer)
        end
    end)

    test("minimap dragging follows scaled cursor around rim and persists angle without opening dashboard", function()
        local frames, button, cursor = start()
        _G.Minimap.scale = 2
        cursor.x, cursor.y = 400, 200
        drag(button)
        position(button, 75, 0)
        equal(RQDB.settings.minimapAngle, 225)
        cursor.x, cursor.y = 200, 400
        button.scripts.OnUpdate(button)
        position(button, 0, 75)
        button.scripts.OnDragStop(button)
        equal(button.scripts.OnUpdate, nil)
        near(RQDB.settings.minimapAngle, 90)
        frames.Click(button)
        equal(RQ.Api.IsRosterWindowShown(), false)
        button.scripts.OnMouseDown(button)
        frames.Click(button)
        equal(RQ.Api.IsRosterWindowShown(), true)
        local account, character = RQ.Migrations.Prepare(RQDB, RQCharDB)
        RQDB, RQCharDB = account, character
        frames = assert(loadfile("Tests/fixtures/Frames.lua"))()()
        _G.Minimap:SetSize(140, 140)
        h.loadAddon()
        frames.Emit("PLAYER_LOGIN")
        position(frames.MinimapButton(), 0, 75)
    end)

    test("minimap drag handles every quadrant and center without jumps", function()
        local _, button, cursor = start()
        drag(button)
        for _, sample in ipairs({
            { 100, 200, 90 },
            { 0, 100, 180 },
            { 100, 0, 270 },
            { 200, 100, 0 },
        }) do
            cursor.x, cursor.y = sample[1], sample[2]
            button.scripts.OnUpdate(button)
            position(button, math.cos(math.rad(sample[3])) * 75, math.sin(math.rad(sample[3])) * 75)
        end
        cursor.x, cursor.y = 100, 100
        button.scripts.OnUpdate(button)
        position(button, 75, 0)
        button.scripts.OnDragStop(button)
        near(RQDB.settings.minimapAngle, 0)
    end)

    test("drawer ownership stops native drag and later world entries never reclaim the button", function()
        local frames, button = start()
        drag(button)
        local drawer = _G.CreateFrame("Frame", nil, _G.UIParent)
        button:SetParent(drawer)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", drawer, "TOPLEFT", 3, -5)
        button.scripts.OnUpdate(button)
        equal(button.scripts.OnUpdate, nil)
        button:Hide()
        frames.Emit("PLAYER_ENTERING_WORLD")
        drag(button)
        equal(button.scripts.OnUpdate, nil)
        equal(button:GetParent(), drawer)
        equal(button:IsShown(), false)
        local point, relative, _, x, y = button:GetPoint()
        equal(point, "TOPLEFT")
        equal(relative, drawer)
        equal(x, 3)
        equal(y, -5)
        assert(RQ.Api.RefreshMinimapPosition())
        equal(button:GetPoint(), "TOPLEFT")
        button:SetParent(_G.Minimap)
        assert(RQ.Api.RefreshMinimapPosition())
        equal(button:GetPoint(), "TOPLEFT")
    end)

    test("combat and hiding stop minimap dragging with no background update loop", function()
        local frames, button, cursor = start()
        frames.combat = true
        drag(button)
        equal(button.scripts.OnUpdate, nil)
        equal(RQDB.settings.minimapAngle, 225)
        frames.combat = false
        drag(button)
        frames.combat = true
        cursor.x, cursor.y = 100, 200
        button.scripts.OnUpdate(button)
        equal(button.scripts.OnUpdate, nil)
        position(button, 75, 0)
        frames.combat = false
        drag(button)
        button:Hide()
        equal(button.scripts.OnUpdate, nil)
        near(RQDB.settings.minimapAngle, 90)
    end)

    test("missing or invalid cursor geometry reports drag failure without losing saved angle", function()
        local _, button = start()
        _G.GetCursorPosition = nil
        drag(button)
        equal(button.scripts.OnUpdate, nil)
        equal(RQDB.settings.minimapAngle, 225)
        contains(h.messages(), "Minimap drag unavailable")
        _G.GetCursorPosition = function()
            return 0 / 0, 100
        end
        drag(button)
        equal(button.scripts.OnUpdate, nil)
        equal(RQDB.settings.minimapAngle, 225)
        _G.GetCursorPosition = function()
            return 200, 100
        end
        _G.Minimap.scale = 0
        drag(button)
        equal(button.scripts.OnUpdate, nil)
        equal(RQDB.settings.minimapAngle, 225)
    end)

    test("combat entry and logout end dragging and save the last successful sample immediately", function()
        local frames, button, cursor = start()
        drag(button)
        cursor.x, cursor.y = 100, 200
        button.scripts.OnUpdate(button)
        frames.combat = true
        frames.Emit("PLAYER_REGEN_DISABLED")
        equal(button.scripts.OnUpdate, nil)
        near(RQDB.settings.minimapAngle, 90)
        frames.combat = false
        cursor.x, cursor.y = 0, 100
        drag(button)
        frames.Emit("PLAYER_LOGOUT")
        equal(button.scripts.OnUpdate, nil)
        near(RQDB.settings.minimapAngle, 180)
    end)

    test("missing and failing texture masks retain round native frame and working launcher", function()
        for _, mode in ipairs({ "missing", "error" }) do
            h.fakeCharacter()
            local frames = assert(loadfile("Tests/fixtures/Frames.lua"))()()
            local create = _G.CreateFrame
            _G.CreateFrame = function(kind, name, parent, template)
                local widget = create(kind, name, parent, template)
                if name == "RQMinimapButton" then
                    if mode == "missing" then
                        widget.CreateMaskTexture = nil
                    else
                        widget.CreateMaskTexture = function()
                            error("Mask unsupported")
                        end
                    end
                end
                return widget
            end
            h.loadAddon()
            frames.Emit("PLAYER_LOGIN")
            local button = frames.MinimapButton()
            equal(button:IsShown(), true)
            equal(button.icon.mask, nil)
            local border
            for _, widget in ipairs(frames.widgets) do
                if widget.parent == button and widget.texture == "Interface\\Minimap\\MiniMap-TrackingBorder" then
                    border = widget
                end
            end
            assert(border)
            contains({ RQ.Api.GetCapabilities().minimapMask }, mode == "missing" and "unavailable" or "error")
            button.scripts.OnMouseDown(button)
            frames.Click(button)
            equal(RQ.Api.IsRosterWindowShown(), true)
        end
    end)

    test("minimap position migration is idempotent and rejects invalid angles atomically", function()
        start()
        local old, mirror = RQ.Util.Copy(RQDB), RQ.Util.Copy(RQCharDB)
        old.schemaVersion, mirror.schemaVersion = 17, 17
        old.settings.minimapAngle = nil
        local migrated, character = RQ.Migrations.Prepare(old, mirror)
        equal(migrated.settings.minimapAngle, 225)
        equal(old.settings.minimapAngle, nil)
        equal(old.schemaVersion, 17)
        migrated.settings.minimapAngle = 123.5
        local second = RQ.Migrations.Prepare(migrated, character)
        equal(second.settings.minimapAngle, 123.5)
        for _, angle in ipairs({ -1, 360, math.huge, 0 / 0, "90", false }) do
            local invalid = RQ.Util.Copy(old)
            invalid.settings.minimapAngle = angle
            local account, char, err = RQ.Migrations.Prepare(invalid, mirror)
            equal(account, nil)
            equal(char, nil)
            contains({ err }, "minimap")
            equal(invalid.schemaVersion, 17)
            equal(RQ.Database.SaveMinimapAngle(angle), false)
            equal(RQDB.settings.minimapAngle, 225)
        end
    end)

    test("configuration import and rollback refresh native minimap position without moving drawer buttons", function()
        local frames, button = start()
        assert(RQ.Database.Register("add"))
        local config = assert(RQ.ConfigTransfer.Extract(RQDB))
        config.settings.minimapAngle = 180
        local encoded = assert(RQ.ConfigTransfer.Encode(config))
        local ok, err, token = RQ.ConfigTransferService.Preview(encoded)
        assert(ok, err)
        assert(RQ.ConfigTransferService.Confirm(token))
        position(button, -75, 0)
        assert(RQ.ConfigTransferService.Rollback())
        near(RQDB.settings.minimapAngle, 225)
        position(button, math.cos(math.rad(225)) * 75, math.sin(math.rad(225)) * 75)
        local drawer = _G.CreateFrame("Frame", nil, _G.UIParent)
        button:SetParent(drawer)
        button:ClearAllPoints()
        button:SetPoint("CENTER", drawer, "CENTER", 0, 0)
        ok, err, token = RQ.ConfigTransferService.Preview(encoded)
        assert(ok, err)
        assert(RQ.ConfigTransferService.Confirm(token))
        equal(button:GetParent(), drawer)
        local _, relative, _, x, y = button:GetPoint()
        equal(relative, drawer)
        equal(x, 0)
        equal(y, 0)
        frames.Emit("PLAYER_ENTERING_WORLD")
        equal(button:GetParent(), drawer)
    end)
end
