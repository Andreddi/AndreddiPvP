local _, ns = ...
local UI = ns.UI

-- Main window: History / Players / Guilds / Statistics / Settings tabs.
-- The first three share a table layout with a detail panel on the right.

local win
local pages = {}
local pageBuilders = {}
local currentTab

local WIDTH, HEIGHT = 900, 540
local DETAIL_WIDTH = 300

local TABS = {
    { key = "history",  label = "History" },
    { key = "players",  label = "Players" },
    { key = "guilds",   label = "Guilds" },
    { key = "stats",    label = "Statistics", width = 90 },
    { key = "settings", label = "Settings" },
}

-- Other files register full-width pages (stats, settings) here.
function ns:RegisterPage(key, builder)
    pageBuilders[key] = builder
end

local function Lower(s) return s and s:lower() or "" end

local function Matches(search, ...)
    if search == "" then return true end
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if v and Lower(v):find(search, 1, true) then return true end
    end
    return false
end

local function ListText(list)
    return list and ns:ListTag(list) or ""
end

--------------------------------------------------------------------------------
-- Detail panel (player or guild)
--------------------------------------------------------------------------------

local detail

local function BuildDetail(parent)
    local d = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    UI.SetBackdrop(d, UI.colors.panel)
    d:SetWidth(DETAIL_WIDTH)
    d:SetPoint("TOPRIGHT", -12, -62)
    d:SetPoint("BOTTOMRIGHT", -12, 12)

    d.empty = UI.Text(d, "GameFontDisable", "Select a player or guild", "CENTER")
    d.empty:SetPoint("CENTER")

    local c = CreateFrame("Frame", nil, d)
    c:SetPoint("TOPLEFT", 10, -10)
    c:SetPoint("BOTTOMRIGHT", -10, 10)
    d.content = c

    c.name = UI.Text(c, "GameFontNormalLarge")
    c.name:SetPoint("TOPLEFT")
    c.name:SetPoint("RIGHT")
    c.sub = UI.Text(c, "GameFontHighlightSmall")
    c.sub:SetPoint("TOPLEFT", c.name, "BOTTOMLEFT", 0, -4)
    c.sub:SetPoint("RIGHT")

    c.guildButton = UI.Button(c, "", 200, 18, function(self)
        if self.guildKey then ns:ShowMainWindow("guilds", self.guildKey) end
    end)
    c.guildButton:SetPoint("TOPLEFT", c.sub, "BOTTOMLEFT", 0, -6)
    c.guildButton.tooltip = "Open guild"

    c.record = UI.Text(c, "GameFontHighlight")
    c.record:SetPoint("TOPLEFT", c.guildButton, "BOTTOMLEFT", 0, -10)
    c.record:SetPoint("RIGHT")
    c.seen = UI.Text(c, "GameFontDisableSmall")
    c.seen:SetPoint("TOPLEFT", c.record, "BOTTOMLEFT", 0, -4)
    c.seen:SetPoint("RIGHT")
    c.seen:SetSpacing(2)

    c.listLabel = UI.Text(c, "GameFontNormalSmall", "List")
    c.listLabel:SetPoint("TOPLEFT", c.seen, "BOTTOMLEFT", 0, -12)
    c.list = UI.ListSelector(c, function(list)
        if d.kind == "player" then ns:SetPlayerList(d.key, list) else ns:SetGuildList(d.key, list) end
    end, 66)
    c.list:SetPoint("TOPLEFT", c.listLabel, "BOTTOMLEFT", 0, -4)
    c.inherited = UI.Text(c, "GameFontDisableSmall")
    c.inherited:SetPoint("TOPLEFT", c.list, "BOTTOMLEFT", 0, -3)

    c.noteLabel = UI.Text(c, "GameFontNormalSmall", "Note")
    c.noteLabel:SetPoint("TOPLEFT", c.list, "BOTTOMLEFT", 0, -18)
    c.note = UI.EditBox(c, DETAIL_WIDTH - 20, 22, function(text)
        if not d.key then return end
        if d.kind == "player" then ns:SetPlayerNote(d.key, text) else ns:SetGuildNote(d.key, text) end
    end)
    c.note:SetPlaceholder("Something to remember (Enter to save)")
    c.note:SetPoint("TOPLEFT", c.noteLabel, "BOTTOMLEFT", 0, -4)

    c.recentLabel = UI.Text(c, "GameFontNormalSmall", "Recent encounters")
    c.recentLabel:SetPoint("TOPLEFT", c.note, "BOTTOMLEFT", 0, -12)
    c.recent = UI.Text(c, "GameFontHighlightSmall")
    c.recent:SetPoint("TOPLEFT", c.recentLabel, "BOTTOMLEFT", 0, -4)
    c.recent:SetPoint("RIGHT")
    c.recent:SetSpacing(3)
    c.recent:SetJustifyV("TOP")

    c.delete = UI.ConfirmButton(c, "Delete", 80, 20, function()
        if d.kind == "player" then ns:DeletePlayer(d.key) else ns:DeleteGuild(d.key) end
        ns:ShowDetail(nil)
    end)
    c.delete:SetPoint("BOTTOMRIGHT")

    d.kind, d.key = nil, nil
    return d
end

local function RecentLines(filterFn, max)
    local out = {}
    local enc = ns.db.encounters
    for i = #enc, 1, -1 do
        local e = enc[i]
        if filterFn(e) then
            local what = e.kind == "kill" and "|cff40ff40Kill|r" or "|cffff4040Death|r"
            local line = date("%m-%d %H:%M", e.t) .. "  " .. what
            if e.zone and e.zone ~= "" then line = line .. "  |cff999999" .. e.zone .. "|r" end
            table.insert(out, line)
            if #out >= max then break end
        end
    end
    return out
end

function ns:ShowDetail(kind, key)
    if not detail then return end
    local c = detail.content
    -- Commit a half-typed note to the record it belongs to before switching.
    if c.note:HasFocus() then c.note:ClearFocus() end
    detail.kind, detail.key = kind, key
    local rec = kind == "player" and ns:GetPlayer(key) or (kind == "guild" and ns:GetGuild(key))
    if not rec then
        detail.kind, detail.key = nil, nil
        c:Hide()
        detail.empty:Show()
        return
    end
    detail.empty:Hide()
    c:Show()

    if kind == "player" then
        local _, _, _, hex = ns:ClassColor(rec.class)
        c.name:SetText("|c" .. hex .. ns:ShortName(key) .. "|r")
        local bits = {}
        if rec.level then table.insert(bits, "Level " .. rec.level) end
        if rec.race then table.insert(bits, rec.race) end
        if rec.class then table.insert(bits, ns:ClassName(rec.class)) end
        if rec.faction then table.insert(bits, "|cff999999" .. rec.faction .. "|r") end
        c.sub:SetText(#bits > 0 and table.concat(bits, " ") or "|cff999999Unknown level and class|r")
        local g = ns:GetGuild(rec.guildKey)
        if rec.guildKey then
            c.guildButton:SetText("<" .. (rec.guild or ns:ShortName(rec.guildKey)) .. ">" .. (g and g.list and (" " .. ns:ListTag(g.list)) or ""))
            c.guildButton.guildKey = rec.guildKey
            c.guildButton:Show()
            c.guildButton:SetHeight(18)
        else
            c.guildButton:Hide()
            c.guildButton:SetHeight(1)
        end
        c.record:SetText("You vs them: " .. ns:KDText(rec.kills, rec.deaths) .. "   K/D " .. ns:KD(rec.kills, rec.deaths))
        c.seen:SetText("First seen " .. ns:FormatTime(rec.firstSeen or time()) .. "\nLast seen " .. ns:Ago(rec.lastSeen))
        c.list:SetValue(rec.list)
        if not rec.list and g and g.list then
            c.inherited:SetText("Inherits " .. ns.LIST_INFO[g.list].label .. " from guild")
        else
            c.inherited:SetText("")
        end
        c.note:SetText(rec.note or "")
        local lines = RecentLines(function(e) return e.key == key end, 8)
        c.recent:SetText(#lines > 0 and table.concat(lines, "\n") or "|cff777777None|r")
        c.delete.tooltip = "Delete this player and all encounters with them"
    else
        c.name:SetText("|cffd4a017<" .. rec.name .. ">|r")
        local members = 0
        for _ in pairs(rec.members or {}) do members = members + 1 end
        c.sub:SetText((rec.realm or "") .. "   " .. members .. " known members")
        c.guildButton:Hide()
        c.guildButton:SetHeight(1)
        c.record:SetText("You vs guild: " .. ns:KDText(rec.kills, rec.deaths) .. "   K/D " .. ns:KD(rec.kills, rec.deaths))
        c.seen:SetText("First seen " .. ns:FormatTime(rec.firstSeen or time()) .. "\nLast seen " .. ns:Ago(rec.lastSeen))
        c.list:SetValue(rec.list)
        c.inherited:SetText(rec.list and "Applies to every member without their own list" or "")
        c.note:SetText(rec.note or "")

        -- Members ranked by encounters, then recent guild encounters.
        local ranked = {}
        for mkey in pairs(rec.members or {}) do
            local p = ns:GetPlayer(mkey)
            if p then table.insert(ranked, { key = mkey, p = p }) end
        end
        table.sort(ranked, function(a, b)
            return (a.p.kills + a.p.deaths) > (b.p.kills + b.p.deaths)
        end)
        local lines = {}
        for i = 1, math.min(6, #ranked) do
            local r = ranked[i]
            table.insert(lines, ns:ColoredName(r.key, r.p.class) .. "  " .. ns:KDText(r.p.kills, r.p.deaths) .. " " .. ListText(r.p.list))
        end
        c.recentLabel:SetText("Members you've met")
        c.recent:SetText(#lines > 0 and table.concat(lines, "\n") or "|cff777777None yet|r")
        c.delete.tooltip = "Delete the guild record (list, note, counters). Players are kept."
    end
    if kind == "player" then c.recentLabel:SetText("Recent encounters") end

    for _, page in pairs(pages) do
        if page.list then page.list:Refresh() end
    end
end

--------------------------------------------------------------------------------
-- Table pages
--------------------------------------------------------------------------------

-- spec: { columns = { {title, width, justify} }, rows = fn(search, filter) -> items,
--         cells = fn(item) -> { strings }, select = fn(item), isSelected = fn(item),
--         filters = { {key,label} }, sorts = { {key,label} } }
local function BuildTablePage(parent, spec)
    local page = CreateFrame("Frame", nil, parent)
    page:SetPoint("TOPLEFT", 12, -62)
    page:SetPoint("BOTTOMRIGHT", -(12 + DETAIL_WIDTH + 8), 12)
    page.filter = spec.filters and spec.filters[1][1] or nil
    page.sort = spec.sorts and spec.sorts[1][1] or nil

    page.search = UI.EditBox(page, 170, 22)
    page.search:SetPlaceholder("Search...")
    page.search:SetPoint("TOPLEFT")
    page.search:HookScript("OnTextChanged", function() page:Refresh() end)

    local x = 178
    if spec.filters then
        page.filterButtons = {}
        for _, f in ipairs(spec.filters) do
            local b = UI.Button(page, f[2], f[3] or 58, 22, function()
                page.filter = f[1]
                page:Refresh()
            end)
            b:SetPoint("TOPLEFT", x, 0)
            b.key = f[1]
            x = x + (f[3] or 58) + 3
            table.insert(page.filterButtons, b)
        end
    end
    if spec.sorts then
        local sortLabel = UI.Text(page, "GameFontDisableSmall", "Sort")
        sortLabel:SetPoint("TOPLEFT", x + 6, -5)
        page.sorter = UI.Cycler(page, 110, spec.sorts, function(v)
            page.sort = v
            page:Refresh()
        end)
        page.sorter:SetPoint("TOPRIGHT", 0, -1)
        page.sorter:SetValue(page.sort)
    end

    -- Column header
    local header = CreateFrame("Frame", nil, page)
    header:SetPoint("TOPLEFT", 0, -28)
    header:SetPoint("TOPRIGHT", 0, -28)
    header:SetHeight(18)
    local hx = 6
    for _, col in ipairs(spec.columns) do
        local t = UI.Text(header, "GameFontNormalSmall", col[1], col[3])
        t:SetPoint("LEFT", hx, 0)
        if col[2] then t:SetWidth(col[2]) else t:SetPoint("RIGHT", -14, 0) end
        hx = hx + (col[2] or 0) + 4
    end

    local function BuildRow(row)
        row.cells = {}
        local cx = 4
        for i, col in ipairs(spec.columns) do
            local t = UI.Text(row, "GameFontHighlightSmall", "", col[3])
            t:SetPoint("LEFT", cx, 0)
            if col[2] then t:SetWidth(col[2]) else t:SetPoint("RIGHT", -4, 0) end
            t:SetWordWrap(false)
            row.cells[i] = t
            cx = cx + (col[2] or 0) + 4
        end
    end
    local function UpdateRow(row, item)
        local cells = spec.cells(item)
        for i, t in ipairs(row.cells) do t:SetText(cells[i] or "") end
    end

    page.list = UI.ScrollList(page, 18, BuildRow, UpdateRow, function(_, item)
        spec.select(item)
    end)
    page.list:SetPoint("TOPLEFT", 0, -48)
    page.list:SetPoint("BOTTOMRIGHT", 0, spec.footer and 32 or 0)
    page.list.isSelected = spec.isSelected
    page.list:SetEmptyText(spec.emptyText or "Nothing here yet")

    page.count = UI.Text(page, "GameFontDisableSmall", "", "RIGHT")
    page.count:SetPoint("BOTTOMRIGHT", page.list, "TOPRIGHT", -4, 4)

    function page:Refresh()
        local search = Lower(strtrim(self.search:GetText() or ""))
        local items = spec.rows(search, self.filter, self.sort)
        self.list:SetData(items)
        self.count:SetText(#items .. " shown")
        if self.filterButtons then
            for _, b in ipairs(self.filterButtons) do b:SetActive(b.key == self.filter) end
        end
    end

    if spec.footer then spec.footer(page) end
    return page
end

--------------------------------------------------------------------------------
-- History page
--------------------------------------------------------------------------------

local selectedEncounter

local function BuildHistory(parent)
    return BuildTablePage(parent, {
        columns = {
            { "When", 92 }, { "", 38 }, { "Player", 112 }, { "Lvl", 24, "CENTER" },
            { "Guild", 104 }, { "Zone", nil },
        },
        filters = { { "all", "All", 44 }, { "kill", "Kills", 50 }, { "death", "Deaths", 56 }, { "me", "This char", 70 } },
        emptyText = "No kills or deaths recorded yet. Go fight someone!",
        rows = function(search, filter)
            local out = {}
            local me = ns:MyKey()
            local enc = ns.db.encounters
            for i = #enc, 1, -1 do
                local e = enc[i]
                if (filter == "all" or e.kind == filter or (filter == "me" and e.me == me)) then
                    local p = ns:GetPlayer(e.key)
                    local g = ns:GetGuild(e.guildKey)
                    if Matches(search, e.key, g and g.name, e.zone, e.sub, p and p.note) then
                        table.insert(out, e)
                    end
                end
            end
            return out
        end,
        cells = function(e)
            local g = ns:GetGuild(e.guildKey)
            local p = ns:GetPlayer(e.key)
            local list = ns:EffectiveList(e.key, e.guildKey)
            return {
                date("%y-%m-%d %H:%M", e.t),
                e.kind == "kill" and "|cff40ff40Kill|r" or "|cffff4040Death|r",
                ns:ColoredName(e.key, e.class or (p and p.class)) .. (list and (" " .. ns:ListTag(list)) or ""),
                e.level and tostring(e.level) or "",
                g and g.name or "",
                (e.zone or "") .. (e.sub and ("|cff888888 - " .. e.sub .. "|r") or ""),
            }
        end,
        select = function(e)
            selectedEncounter = e
            ns:ShowDetail("player", e.key)
        end,
        isSelected = function(e) return e == selectedEncounter end,
        footer = function(page)
            local del = UI.ConfirmButton(page, "Delete encounter", 120, 22, function()
                if selectedEncounter then
                    ns:DeleteEncounter(selectedEncounter)
                    selectedEncounter = nil
                end
            end)
            del:SetPoint("BOTTOMLEFT")
            del.tooltip = "Remove the selected kill/death (e.g. a wrong guess)"
            local death = UI.Button(page, "Record a death...", 120, 22, function() ns:ShowDeathPicker() end)
            death:SetPoint("LEFT", del, "RIGHT", 6, 0)
            death.tooltip = "Pick or type who killed you, if it wasn't recorded"
        end,
    })
end

--------------------------------------------------------------------------------
-- Players page
--------------------------------------------------------------------------------

local function SortRecords(out, sort)
    table.sort(out, function(a, b)
        local ra, rb = a.rec, b.rec
        if sort == "kills" and ra.kills ~= rb.kills then return ra.kills > rb.kills end
        if sort == "deaths" and ra.deaths ~= rb.deaths then return ra.deaths > rb.deaths end
        if sort == "name" then return a.key < b.key end
        if sort ~= "name" and (ra.lastSeen or 0) ~= (rb.lastSeen or 0) then
            return (ra.lastSeen or 0) > (rb.lastSeen or 0)
        end
        return a.key < b.key
    end)
end

local SORTS = { { "seen", "Last seen" }, { "kills", "Most kills" }, { "deaths", "Most deaths" }, { "name", "Name" } }
local LIST_FILTERS = {
    { "all", "All", 40 }, { "kos", "KOS", 44 }, { "friendly", "Friendly", 60 }, { "ignore", "Ignore", 52 },
}

local function AddByNameFooter(page, label, placeholder, onAdd)
    local box = UI.EditBox(page, 180, 22)
    box:SetPlaceholder(placeholder)
    box:SetPoint("BOTTOMLEFT")
    local function Add()
        local text = strtrim(box:GetText() or "")
        if text == "" then return end
        onAdd(text)
        box:SetText("")
        box:ClearFocus()
    end
    box:SetScript("OnEnterPressed", Add)
    local b = UI.Button(page, label, 90, 22, Add)
    b:SetPoint("LEFT", box, "RIGHT", 4, 0)
    return box
end

local function BuildPlayers(parent)
    return BuildTablePage(parent, {
        columns = {
            { "Player", 130 }, { "Lvl", 24, "CENTER" }, { "Guild", 112 }, { "K / D", 54, "CENTER" },
            { "List", 56 }, { "Last seen", nil },
        },
        filters = LIST_FILTERS,
        sorts = SORTS,
        emptyText = "No players yet",
        rows = function(search, filter, sort)
            local out = {}
            for key, p in pairs(ns.db.players) do
                local list = ns:EffectiveList(key, p.guildKey)
                if (filter == "all" or list == filter) and Matches(search, key, p.guild, p.note, ns:ClassName(p.class)) then
                    table.insert(out, { key = key, rec = p })
                end
            end
            SortRecords(out, sort)
            return out
        end,
        cells = function(item)
            local p = item.rec
            local list, source = ns:EffectiveList(item.key, p.guildKey)
            local listText = ListText(list)
            if source == "guild" then listText = listText .. "|cff777777*|r" end
            return {
                ns:ColoredName(item.key, p.class) .. (p.note and " |cffffd100*|r" or ""),
                p.level and tostring(p.level) or "",
                p.guild or "",
                ns:KDText(p.kills, p.deaths),
                listText,
                ns:Ago(p.lastSeen),
            }
        end,
        select = function(item) ns:ShowDetail("player", item.key) end,
        isSelected = function(item) return detail.kind == "player" and detail.key == item.key end,
        footer = function(page)
            AddByNameFooter(page, "Add player", ns:UsesSurnames() and "First and last name" or "Name or Name-Realm", function(text)
                local key = ns:FindPlayerKey(text)
                ns:TouchPlayer(ns:SeenByKey(key) or { key = key })
                ns:Fire("DATA_CHANGED", "player", key)
                ns:ShowDetail("player", key)
            end)
            local hint = UI.Text(page, "GameFontDisableSmall", "* note    |cff777777*|r list from guild", "RIGHT")
            hint:SetPoint("BOTTOMRIGHT", 0, 6)
        end,
    })
end

--------------------------------------------------------------------------------
-- Guilds page
--------------------------------------------------------------------------------

local function BuildGuilds(parent)
    return BuildTablePage(parent, {
        columns = {
            { "Guild", 170 }, { "List", 60 }, { "K / D", 60, "CENTER" }, { "Members", 56, "CENTER" },
            { "Last seen", nil },
        },
        filters = LIST_FILTERS,
        sorts = SORTS,
        emptyText = "No guilds yet",
        rows = function(search, filter, sort)
            local out = {}
            for key, g in pairs(ns.db.guilds) do
                if (filter == "all" or g.list == filter) and Matches(search, g.name, g.note) then
                    table.insert(out, { key = key, rec = g })
                end
            end
            SortRecords(out, sort)
            return out
        end,
        cells = function(item)
            local g = item.rec
            local members = 0
            for _ in pairs(g.members or {}) do members = members + 1 end
            return {
                "|cffd4a017" .. g.name .. "|r" .. (g.note and " |cffffd100*|r" or ""),
                ListText(g.list),
                ns:KDText(g.kills, g.deaths),
                tostring(members),
                ns:Ago(g.lastSeen),
            }
        end,
        select = function(item) ns:ShowDetail("guild", item.key) end,
        isSelected = function(item) return detail.kind == "guild" and detail.key == item.key end,
        footer = function(page)
            AddByNameFooter(page, "Add guild", "Exact guild name", function(text)
                local gkey = ns:GuildKey(text, nil)
                ns:TouchGuild(gkey)
                ns:Fire("DATA_CHANGED", "guild", gkey)
                ns:ShowDetail("guild", gkey)
            end)
        end,
    })
end

--------------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------------

local function Build()
    win = UI.CreateWindow("AndreddiPvPMainWindow", "AndreddiPvP", WIDTH, HEIGHT, "main")
    win.title:SetText(ns.color .. "Andreddi|r|cffe03030PvP|r  |cff777777open-world PvP history|r")

    win.summary = UI.Text(win, "GameFontHighlightSmall", "", "RIGHT")
    win.summary:SetPoint("TOPRIGHT", -36, -12)

    win.tabs = UI.TabBar(win, TABS, function(key) ns:ShowMainWindow(key) end)
    win.tabs:SetPoint("TOPLEFT", 12, -32)

    detail = BuildDetail(win)
    pages.history = BuildHistory(win)
    pages.players = BuildPlayers(win)
    pages.guilds = BuildGuilds(win)
    for key, builder in pairs(pageBuilders) do
        local page = CreateFrame("Frame", nil, win)
        page:SetPoint("TOPLEFT", 12, -62)
        page:SetPoint("BOTTOMRIGHT", -12, 12)
        builder(page)
        pages[key] = page
    end
    for _, page in pairs(pages) do page:Hide() end
    ns:ShowDetail(nil)

    win:SetScript("OnShow", function() ns:RefreshMainWindow() end)
    UI.RestorePosition(win, { "CENTER" })
end

function ns:RefreshMainWindow()
    if not win or not win:IsShown() then return end
    local k, d = ns:Totals()
    win.summary:SetText("Total " .. ns:KDText(k, d) .. "   K/D " .. ns:KD(k, d))
    local page = pages[currentTab]
    if page and page.Refresh then page:Refresh() end
    if detail.kind then ns:ShowDetail(detail.kind, detail.key) end
end

function ns:ShowMainWindow(tab, key)
    if not win then Build() end
    tab = tab or currentTab or "history"
    currentTab = tab
    for k, page in pairs(pages) do page:SetShown(k == tab) end
    detail:SetShown(tab == "history" or tab == "players" or tab == "guilds")
    win.tabs:SetSelected(tab)
    win:Show()
    if key then
        if tab == "guilds" then ns:ShowDetail("guild", key) else ns:ShowDetail("player", key) end
    end
    ns:RefreshMainWindow()
end

function ns:ToggleMainWindow(tab)
    if win and win:IsShown() then
        win:Hide()
    else
        ns:ShowMainWindow(tab)
    end
end

-- Coalesce bursts of data changes into one refresh.
local pending = false
ns:Listen("DATA_CHANGED", function()
    if pending or not win or not win:IsShown() then return end
    pending = true
    C_Timer.After(0.1, function()
        pending = false
        -- Don't wipe the note the user is typing.
        if detail and detail.content.note:HasFocus() then
            local page = pages[currentTab]
            if page and page.Refresh then page:Refresh() end
            return
        end
        ns:RefreshMainWindow()
    end)
end)
