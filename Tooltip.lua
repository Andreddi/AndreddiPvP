local _, ns = ...
local Safe = ns.Safe
local SafeCall = ns.SafeCall

-- Adds history, list and note lines to player unit tooltips.

local function AddLines(tooltip, unit)
    if not ns.db or not ns.db.settings.tooltipEnabled then return end
    if not unit then return end
    local info = ns:ReadUnit(unit)
    if not info then return end
    ns:Remember(info)

    local p = ns:GetPlayer(info.key)
    local gkey = info.guildKey or (p and p.guildKey)
    local g = ns:GetGuild(gkey)
    if not ns:IsInteresting(info.key, gkey) then return end

    local list, source = ns:EffectiveList(info.key, gkey)
    local header = ns.color .. "AndreddiPvP|r"
    if list then
        header = header .. " " .. ns:ListTag(list)
        if source == "guild" then header = header .. " |cff999999(guild)|r" end
    end
    tooltip:AddLine(header)

    if p and ((p.kills or 0) + (p.deaths or 0)) > 0 then
        tooltip:AddDoubleLine("You vs them", ns:KDText(p.kills, p.deaths), 0.8, 0.8, 0.8)
        local last = ns:LastEncounterText(info.key)
        if last then tooltip:AddLine(last, 0.7, 0.7, 0.7) end
    end
    if g and ((g.kills or 0) + (g.deaths or 0)) > 0 then
        tooltip:AddDoubleLine("You vs <" .. g.name .. ">", ns:KDText(g.kills, g.deaths), 0.8, 0.8, 0.8)
    end
    if ns.db.settings.tooltipShowNote then
        if p and p.note then tooltip:AddLine("Note: " .. p.note, 1, 0.82, 0, true) end
        if g and g.note then tooltip:AddLine("Guild note: " .. g.note, 1, 0.82, 0, true) end
    end
    tooltip:Show()
end

local function OnUnitTooltip(tooltip)
    if tooltip ~= GameTooltip then return end
    local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
    unit = ok and Safe(unit) or nil
    if not unit then
        -- Some tooltips (e.g. world units under the cursor) report no token.
        if SafeCall(UnitExists, "mouseover") then unit = "mouseover" end
    end
    local okAdd, err = pcall(AddLines, tooltip, unit)
    if not okAdd then ns:Debug("Tooltip error: " .. tostring(err)) end
end

ns:Listen("DB_READY", function()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnUnitTooltip)
    elseif GameTooltip:HasScript("OnTooltipSetUnit") then
        GameTooltip:HookScript("OnTooltipSetUnit", OnUnitTooltip)
    end
end)
