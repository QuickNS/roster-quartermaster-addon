local Util = {}
RQ.Util = Util

function Util.Copy(value, seen)
    if type(value) ~= "table" then
        return value
    end
    seen = seen or {}
    if seen[value] then
        return seen[value]
    end
    local copy = {}
    seen[value] = copy
    for key, item in pairs(value) do
        copy[key] = Util.Copy(item, seen)
    end
    return copy
end

function Util.IsNumber(value)
    return type(value) == "number" and value == value and value >= 0 and value < math.huge
end

function Util.IsFinite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

function Util.DefaultWindowPosition()
    return { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 }
end

function Util.IsMinimapAngle(value)
    return Util.IsNumber(value) and value < 360
end

function Util.IsWindowPosition(value)
    local points = {
        TOPLEFT = true,
        TOP = true,
        TOPRIGHT = true,
        LEFT = true,
        CENTER = true,
        RIGHT = true,
        BOTTOMLEFT = true,
        BOTTOM = true,
        BOTTOMRIGHT = true,
    }
    return type(value) == "table"
        and points[value.point] == true
        and points[value.relativePoint] == true
        and Util.IsFinite(value.x)
        and Util.IsFinite(value.y)
end

function Util.IsText(value)
    return type(value) == "string" and value:match("%S") ~= nil
end

function Util.Keys(value)
    local keys = {}
    for key in pairs(value) do
        keys[#keys + 1] = key
    end
    table.sort(keys)
    return keys
end
function RQ.Util.Money(value)
    if not RQ.Util.IsNumber(value) or value % 1 ~= 0 then
        return "unavailable"
    end
    return string.format("%dg %ds %dc", math.floor(value / 10000), math.floor(value / 100) % 100, value % 100)
end
