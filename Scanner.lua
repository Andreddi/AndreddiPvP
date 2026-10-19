local _, ns = ...
local SafeCall = ns.SafeCall

-- Watches the units the client exposes (nameplates, target, focus, mouseover)
-- to keep records fresh, spot enemies targeting us, and trigger alerts.

local plates = {} -- active nameplate unit tokens

local SINGLE_UNITS = { "target", "focus", "mouseover", "softenemy", "softfriend" }

function ns:FindUnitByGUID(guid)
    if not guid then return nil end
    for _, u in ipairs(SINGLE_UNITS) do
        if SafeCall(UnitGUID, u) == guid then return u end
    end
    for u in pairs(plates) do
        if SafeCall(UnitGUID, u) == guid then return u end
    end
    return nil
end

local function IsTargetingMe(unit)
    return SafeCall(UnitIsUnit, unit .. "target", "player") and true or false
end

-- Reads a unit and feeds every module that cares. Returns the info.
function ns:ScanUnit(unit, source)
    local info = ns:ReadUnit(unit)
    if not info then return nil end
    info = ns:Remember(info)
    ns:UpdateKnownPlayer(info)
    if info.hostile and IsTargetingMe(unit) then
        ns:NoteThreat(info)
    end
    ns:MaybeAlert(info, source)
    return info
end

ns:On("NAME_PLATE_UNIT_ADDED", function(_, unit)
    plates[unit] = true
    -- Forever can fire this before the unit is populated; look again shortly.
    if not ns:ScanUnit(unit, "nameplate") then
        C_Timer.After(0.3, function()
            if plates[unit] then ns:ScanUnit(unit, "nameplate") end
        end)
    end
end)

ns:On("NAME_PLATE_UNIT_REMOVED", function(_, unit)
    plates[unit] = nil
end)

ns:On("PLAYER_TARGET_CHANGED", function() ns:ScanUnit("target", "target") end)
ns:On("PLAYER_FOCUS_CHANGED", function() ns:ScanUnit("focus", "focus") end)
ns:On("UPDATE_MOUSEOVER_UNIT", function() ns:ScanUnit("mouseover", "mouseover") end)

-- Catch enemies switching target onto us between ticks.
ns:On("UNIT_TARGET", function(_, unit)
    if not unit then return end
    if plates[unit] or unit == "target" or unit == "focus" then
        if IsTargetingMe(unit) then
            local info = ns:ReadUnit(unit)
            if info and info.hostile then ns:NoteThreat(ns:Remember(info)) end
        end
    end
end)

-- Periodic sweep: enemies already on screen may start targeting us, and guild
-- info often arrives a moment after the nameplate.
local function Sweep()
    for unit in pairs(plates) do
        if SafeCall(UnitExists, unit) then
            ns:ScanUnit(unit, "nameplate")
        else
            plates[unit] = nil
        end
    end
    ns:ScanUnit("target", "target")
end

ns:Listen("LOGIN", function()
    C_Timer.NewTicker(1, Sweep)
end)
