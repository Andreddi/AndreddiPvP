local _, ns = ...
local UI = ns.UI

-- Statistics tab: headline tiles, kills per period, a 14-day chart, class
-- breakdown and top players/guilds.

local KILL = UI.colors.kill
local DEATH = UI.colors.death

local function Panel(parent, title)
    local p = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    UI.SetBackdrop(p, UI.colors.panel)
    p.title = UI.Text(p, "GameFontNormalSmall", title)
    p.title:SetPoint("TOPLEFT", 8, -7)
    return p
end

local function Tile(parent, label)
    local t = Panel(parent, label)
    t.title:SetFontObject("GameFontDisableSmall")
    t.value = UI.Text(t, "GameFontHighlightLarge")
    t.value:SetPoint("BOTTOMLEFT", 8, 8)
    return t
end

-- A grid of font strings: rows x columns, columns = { {width, justify} }.
local function TextTable(parent, rows, columns, rowHeight)
    local tbl = { rows = {} }
    for r = 1, rows do
        local row = {}
        local x = 8
        for c, col in ipairs(columns) do
            local fs = UI.Text(parent, r == 1 and "GameFontNormalSmall" or "GameFontHighlightSmall", "", col[2])
            fs:SetPoint("TOPLEFT", x, -24 - (r - 1) * rowHeight)
            fs:SetWidth(col[1])
            fs:SetWordWrap(false)
            row[c] = fs
            x = x + col[1] + 4
        end
        tbl.rows[r] = row
    end
    function tbl:Set(r, values)
        local row = self.rows[r]
        if not row then return end
        for c, fs in ipairs(row) do fs:SetText(values and values[c] or "") end
    end
    return tbl
end

local function Build(page)
    local scopeMe = false

    ----------------------------------------------------------------------------
    -- Scope toggle
    ----------------------------------------------------------------------------
    local allBtn, meBtn
    allBtn = UI.Button(page, "All characters", 100, 20, function()
        scopeMe = false
        page:Refresh()
    end)
    allBtn:SetPoint("TOPRIGHT", -106, 0)
    meBtn = UI.Button(page, "This character", 100, 20, function()
        scopeMe = true
        page:Refresh()
    end)
    meBtn:SetPoint("TOPRIGHT", 0, 0)

    ----------------------------------------------------------------------------
    -- Headline tiles
    ----------------------------------------------------------------------------
    local tiles = {}
    local tileDefs = { "Overall K/D", "Kills", "Deaths", "Players met", "Kills per day (avg)", "Kills per week (avg)" }
    local tileW = (876 - 5 * 6) / 6
    for i, label in ipairs(tileDefs) do
        local t = Tile(page, label)
        t:SetSize(tileW, 50)
        t:SetPoint("TOPLEFT", (i - 1) * (tileW + 6), -26)
        tiles[i] = t
    end

    ----------------------------------------------------------------------------
    -- Periods
    ----------------------------------------------------------------------------
    local periods = Panel(page, "By period")
    periods:SetPoint("TOPLEFT", 0, -84)
    periods:SetSize(270, 224)
    local periodTable = TextTable(periods, 6, { { 90, "LEFT" }, { 50, "RIGHT" }, { 50, "RIGHT" }, { 50, "RIGHT" } }, 18)
    periodTable:Set(1, { "", "Kills", "Deaths", "K/D" })
    local averages = UI.Text(periods, "GameFontDisableSmall")
    averages:SetPoint("BOTTOMLEFT", 8, 8)
    averages:SetPoint("RIGHT", -8, 0)
    averages:SetSpacing(2)

    ----------------------------------------------------------------------------
    -- Classes
    ----------------------------------------------------------------------------
    local classes = Panel(page, "By class")
    classes:SetPoint("TOPLEFT", periods, "TOPRIGHT", 6, 0)
    classes:SetSize(270, 224)
    local CLASS_ROWS = 14 -- header + all 13 retail classes
    local classTable = TextTable(classes, CLASS_ROWS, { { 90, "LEFT" }, { 50, "RIGHT" }, { 50, "RIGHT" }, { 50, "RIGHT" } }, 14)
    classTable:Set(1, { "Class", "Kills", "Deaths", "K/D" })

    ----------------------------------------------------------------------------
    -- Top lists
    ----------------------------------------------------------------------------
    local tops = {}
    local topDefs = {
        { key = "playersDiedTo", title = "Nemeses (killed you most)", field = "deaths", kind = "player" },
        { key = "playersKilled", title = "Favourite victims",         field = "kills",  kind = "player" },
        { key = "guildsDiedTo",  title = "Guilds that killed you most", field = "deaths", kind = "guild" },
        { key = "guildsKilled",  title = "Guilds you killed most",    field = "kills",  kind = "guild" },
    }
    local topW = 876 - 270 * 2 - 12
    for i, def in ipairs(topDefs) do
        local p = Panel(page, def.title)
        p:SetSize((topW - 6) / 2, 109)
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        p:SetPoint("TOPLEFT", classes, "TOPRIGHT", 6 + col * ((topW - 6) / 2 + 6), -row * 115)
        p.lines = {}
        for l = 1, 5 do
            local b = CreateFrame("Button", nil, p)
            b:SetHeight(16)
            b:SetPoint("TOPLEFT", 6, -22 - (l - 1) * 17)
            b:SetPoint("RIGHT", -6, 0)
            b.left = UI.Text(b, "GameFontHighlightSmall")
            b.left:SetPoint("LEFT", 2, 0)
            b.left:SetPoint("RIGHT", -40, 0)
            b.left:SetWordWrap(false)
            b.right = UI.Text(b, "GameFontHighlightSmall", "", "RIGHT")
            b.right:SetPoint("RIGHT", -2, 0)
            local hl = b:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0.06)
            b:SetScript("OnClick", function(self)
                if self.key then ns:ShowMainWindow(def.kind == "guild" and "guilds" or "players", self.key) end
            end)
            p.lines[l] = b
        end
        p.def = def
        tops[i] = p
    end

    ----------------------------------------------------------------------------
    -- 14 day chart: kills rise above the baseline, deaths hang below it, so the
    -- two series are told apart by position as well as colour.
    ----------------------------------------------------------------------------
    local chart = Panel(page, "Last 14 days")
    chart:SetPoint("TOPLEFT", periods, "BOTTOMLEFT", 0, -6)
    chart:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)

    local legend = UI.Text(chart, "GameFontHighlightSmall", "", "RIGHT")
    legend:SetPoint("TOPRIGHT", -8, -7)
    legend:SetText(("|cff%02x%02x%02x\226\150\160|r Kills (up)   |cff%02x%02x%02x\226\150\160|r Deaths (down)"):format(
        KILL[1] * 255, KILL[2] * 255, KILL[3] * 255, DEATH[1] * 255, DEATH[2] * 255, DEATH[3] * 255))

    local plot = CreateFrame("Frame", nil, chart)
    plot:SetPoint("TOPLEFT", 8, -26)
    plot:SetPoint("BOTTOMRIGHT", -8, 22)

    local baseline = plot:CreateTexture(nil, "ARTWORK")
    baseline:SetColorTexture(1, 1, 1, 0.25)
    baseline:SetHeight(1)
    baseline:SetPoint("LEFT")
    baseline:SetPoint("RIGHT")

    local scaleText = UI.Text(chart, "GameFontDisableSmall", "", "LEFT")
    scaleText:SetPoint("BOTTOMLEFT", 8, 6)

    local bars = {}
    for i = 1, 14 do
        local slot = CreateFrame("Frame", nil, plot)
        slot:EnableMouse(true)
        slot.kill = slot:CreateTexture(nil, "ARTWORK")
        slot.kill:SetColorTexture(KILL[1], KILL[2], KILL[3], 0.9)
        slot.death = slot:CreateTexture(nil, "ARTWORK")
        slot.death:SetColorTexture(DEATH[1], DEATH[2], DEATH[3], 0.9)
        slot.hl = slot:CreateTexture(nil, "BACKGROUND")
        slot.hl:SetAllPoints()
        slot.hl:SetColorTexture(1, 1, 1, 0.06)
        slot.hl:Hide()
        slot.label = UI.Text(chart, "GameFontDisableSmall", "", "CENTER")
        slot:SetScript("OnEnter", function(self)
            self.hl:Show()
            if not self.day then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(date("%A %d %B", self.day.from))
            GameTooltip:AddDoubleLine("Kills", self.day.kills, 1, 1, 1, 1, 1, 1)
            GameTooltip:AddDoubleLine("Deaths", self.day.deaths, 1, 1, 1, 1, 1, 1)
            GameTooltip:Show()
        end)
        slot:SetScript("OnLeave", function(self)
            self.hl:Hide()
            GameTooltip:Hide()
        end)
        bars[i] = slot
    end

    local function DrawChart(daily)
        local w, h = plot:GetWidth(), plot:GetHeight()
        if w <= 0 or h <= 0 then return end
        local maxK, maxD = 0, 0
        for _, d in ipairs(daily) do
            maxK = math.max(maxK, d.kills)
            maxD = math.max(maxD, d.deaths)
        end
        local maxV = math.max(1, maxK, maxD)
        -- Split the plot height in proportion to the larger side of each series.
        local upShare = (maxK + maxD) > 0 and math.max(0.25, math.min(0.75, maxK / (maxK + maxD))) or 0.5
        local upH, downH = (h - 2) * upShare, (h - 2) * (1 - upShare)
        baseline:ClearAllPoints()
        baseline:SetPoint("TOPLEFT", 0, -upH)
        baseline:SetPoint("TOPRIGHT", 0, -upH)
        local scaleUp = maxK > 0 and upH / maxK or 0
        local scaleDown = maxD > 0 and downH / maxD or 0
        local scale = math.min(scaleUp > 0 and scaleUp or math.huge, scaleDown > 0 and scaleDown or math.huge)
        if scale == math.huge then scale = 0 end

        local slotW = w / #daily
        local barW = math.max(3, math.min(16, slotW - 8))
        for i, d in ipairs(daily) do
            local slot = bars[i]
            slot.day = d
            slot:ClearAllPoints()
            slot:SetPoint("TOPLEFT", (i - 1) * slotW, 0)
            slot:SetSize(slotW, h)

            slot.kill:ClearAllPoints()
            slot.kill:SetSize(barW, math.max(0.01, d.kills * scale))
            slot.kill:SetPoint("BOTTOM", slot, "TOPLEFT", slotW / 2, -upH + 1)
            slot.kill:SetShown(d.kills > 0)

            slot.death:ClearAllPoints()
            slot.death:SetSize(barW, math.max(0.01, d.deaths * scale))
            slot.death:SetPoint("TOP", slot, "TOPLEFT", slotW / 2, -upH - 1)
            slot.death:SetShown(d.deaths > 0)

            slot.label:ClearAllPoints()
            slot.label:SetPoint("TOP", slot, "BOTTOM", 0, -3)
            slot.label:SetText(i == #daily and "Today" or date("%a %d", d.from))
        end
        scaleText:SetText(maxV > 0 and ("peak " .. maxK .. " kills / " .. maxD .. " deaths in a day") or "")
    end

    ----------------------------------------------------------------------------
    -- Refresh
    ----------------------------------------------------------------------------
    function page:Refresh()
        allBtn:SetActive(not scopeMe)
        meBtn:SetActive(scopeMe)
        local s = ns:ComputeStats(scopeMe and ns:MyKey() or nil)

        local met = {}
        local metCount = 0
        for _, e in ipairs(ns.db.encounters) do
            if (not scopeMe or e.me == ns:MyKey()) and not met[e.key] then
                met[e.key] = true
                metCount = metCount + 1
            end
        end

        tiles[1].value:SetText(ns:KD(s.total.kills, s.total.deaths))
        tiles[2].value:SetText("|cff40ff40" .. s.total.kills .. "|r")
        tiles[3].value:SetText("|cffff4040" .. s.total.deaths .. "|r")
        tiles[4].value:SetText(metCount)
        tiles[5].value:SetText(s.averages and ("%.1f"):format(s.averages.perDay) or "-")
        tiles[6].value:SetText(s.averages and ("%.1f"):format(s.averages.perWeek) or "-")

        for i, p in ipairs(s.periods) do
            periodTable:Set(i + 1, { p.label, p.kills, p.deaths, ns:KD(p.kills, p.deaths) })
        end
        if s.averages then
            averages:SetText(("Average kills: %.1f a day, %.1f a week, %.1f a month\nTracking since %s"):format(
                s.averages.perDay, s.averages.perWeek, s.averages.perMonth, date("%Y-%m-%d", s.firstT)))
        else
            averages:SetText("")
        end

        for r = 2, CLASS_ROWS do
            local c = s.classes[r - 1]
            if c then
                local _, _, _, hex = ns:ClassColor(c.class)
                classTable:Set(r, { "|c" .. hex .. ns:ClassName(c.class) .. "|r", c.kills, c.deaths, ns:KD(c.kills, c.deaths) })
            else
                classTable:Set(r, r == 2 and { "|cff777777No data yet|r" } or nil)
            end
        end

        for _, p in ipairs(tops) do
            local list = s[p.def.key]
            for l, b in ipairs(p.lines) do
                local item = list[l]
                if item then
                    b.key = item.key
                    if p.def.kind == "guild" then
                        local g = ns:GetGuild(item.key)
                        b.left:SetText("|cffd4a017" .. (g and g.name or ns:ShortName(item.key)) .. "|r")
                    else
                        b.left:SetText(ns:ColoredName(item.key, item.class))
                    end
                    b.right:SetText(p.def.field == "kills" and ("|cff40ff40" .. item.kills .. "|r") or ("|cffff4040" .. item.deaths .. "|r"))
                    b:Show()
                elseif l == 1 then
                    b.key = nil
                    b.left:SetText("|cff777777None yet|r")
                    b.right:SetText("")
                    b:Show()
                else
                    b:Hide()
                end
            end
        end

        DrawChart(s.daily)
    end

    page:SetScript("OnShow", function(self) self:Refresh() end)
    plot:SetScript("OnSizeChanged", function() if page:IsShown() then page:Refresh() end end)
end

ns:RegisterPage("stats", Build)
