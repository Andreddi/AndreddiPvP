local _, ns = ...

-- Database layout (AndreddiPvPDB, account wide):
--   players[key]  = { name, realm, guid, class, race, level, faction, guild, guildKey,
--                     firstSeen, lastSeen, kills, deaths, list, note }
--   guilds[gkey]  = { name, realm, list, note, kills, deaths, firstSeen, lastSeen, members = { [key] = true } }
--   encounters[i] = { t, kind = "kill"|"death", key, guildKey, class, race, level,
--                     zone, sub, me, how }

function ns:GetPlayer(key)
    return key and ns.db.players[key]
end

function ns:GetGuild(gkey)
    return gkey and ns.db.guilds[gkey]
end

local function SplitKey(key)
    return ns:SplitKey(key)
end

-- Key for a name the user typed. Matches an existing record (or a recently
-- seen player) regardless of capitalisation, so "first surname" finds
-- "First Surname".
function ns:FindPlayerKey(text)
    local key = ns:PlayerKey(text, nil)
    if not key or ns.db.players[key] or (ns.seenByKey and ns.seenByKey[key]) then return key end
    local lower = key:lower()
    for k in pairs(ns.db.players) do
        if k:lower() == lower then return k end
    end
    for k in pairs(ns.seenByKey or {}) do
        if k:lower() == lower then return k end
    end
    return key
end

function ns:TouchGuild(gkey)
    if not gkey then return nil end
    local g = ns.db.guilds[gkey]
    if not g then
        local name, realm = SplitKey(gkey)
        g = { name = name, realm = realm, kills = 0, deaths = 0, members = {}, firstSeen = time() }
        ns.db.guilds[gkey] = g
    end
    g.lastSeen = time()
    return g
end

-- Copies whatever is known from info into the record. Guild membership is only
-- changed when info actually carries guild data, because units out of inspect
-- range often report no guild.
local function ApplyInfo(p, key, info)
    if info.guid then p.guid = info.guid end
    if info.class then p.class = info.class end
    if info.race then p.race = info.race end
    if info.level then p.level = info.level end
    if info.faction then p.faction = info.faction end
    if info.guildKey and info.guildKey ~= p.guildKey then
        local old = ns:GetGuild(p.guildKey)
        if old and old.members then old.members[key] = nil end
        p.guildKey = info.guildKey
        p.guild = info.guild
    end
    if p.guildKey then
        local g = ns:GetGuild(p.guildKey)
        if g then
            g.members = g.members or {}
            g.members[key] = true
        end
    end
end

-- Creates or updates a player record. info needs at least .key (or .name).
function ns:TouchPlayer(info)
    local key = info.key or ns:PlayerKey(info.name, info.realm)
    if not key then return nil end
    info.key = key
    local p = ns.db.players[key]
    if not p then
        local name, realm = SplitKey(key)
        p = { name = name, realm = realm, kills = 0, deaths = 0, firstSeen = time() }
        ns.db.players[key] = p
    end
    if info.guildKey then ns:TouchGuild(info.guildKey) end
    ApplyInfo(p, key, info)
    p.lastSeen = time()
    return p
end

-- Refreshes an existing record from a sighting without creating new ones.
function ns:UpdateKnownPlayer(info)
    local p = info.key and ns.db.players[info.key]
    if not p then return nil end
    if info.guildKey and ns.db.guilds[info.guildKey] == nil and info.guildKey ~= p.guildKey then
        ns:TouchGuild(info.guildKey)
    end
    ApplyInfo(p, info.key, info)
    p.lastSeen = time()
    return p
end

--------------------------------------------------------------------------------
-- Lists and notes
--------------------------------------------------------------------------------

function ns:SetPlayerList(key, list)
    local p = ns.db.players[key] or ns:TouchPlayer({ key = key })
    p.list = list
    ns:Fire("DATA_CHANGED", "player", key)
end

function ns:SetGuildList(gkey, list)
    local g = ns:TouchGuild(gkey)
    g.list = list
    ns:Fire("DATA_CHANGED", "guild", gkey)
end

local function CleanNote(text)
    text = text and strtrim(text) or ""
    if text == "" then return nil end
    return text
end

function ns:SetPlayerNote(key, text)
    local p = ns.db.players[key] or ns:TouchPlayer({ key = key })
    p.note = CleanNote(text)
    ns:Fire("DATA_CHANGED", "player", key)
end

function ns:SetGuildNote(gkey, text)
    local g = ns:TouchGuild(gkey)
    g.note = CleanNote(text)
    ns:Fire("DATA_CHANGED", "guild", gkey)
end

-- The list that applies to a player: their own list wins over their guild's.
-- Returns list, source ("player" or "guild").
function ns:EffectiveList(key, guildKey)
    local p = ns.db.players[key]
    if p and p.list then return p.list, "player" end
    local g = ns:GetGuild(guildKey or (p and p.guildKey))
    if g and g.list then return g.list, "guild" end
    return nil
end

function ns:DeletePlayer(key)
    local p = ns.db.players[key]
    if not p then return end
    local g = ns:GetGuild(p.guildKey)
    if g and g.members then g.members[key] = nil end
    ns.db.players[key] = nil
    local enc = ns.db.encounters
    for i = #enc, 1, -1 do
        local e = enc[i]
        if e.key == key then
            local eg = ns:GetGuild(e.guildKey)
            if eg then
                if e.kind == "kill" then eg.kills = math.max(0, (eg.kills or 0) - 1)
                else eg.deaths = math.max(0, (eg.deaths or 0) - 1) end
            end
            table.remove(enc, i)
        end
    end
    ns:Fire("DATA_CHANGED", "player", key)
end

-- Removes the guild record (lists, note, counters). Member players and their
-- encounters stay.
function ns:DeleteGuild(gkey)
    ns.db.guilds[gkey] = nil
    ns:Fire("DATA_CHANGED", "guild", gkey)
end

--------------------------------------------------------------------------------
-- Encounters
--------------------------------------------------------------------------------

local function Count(enc, delta)
    local field = enc.kind == "kill" and "kills" or "deaths"
    local p = ns.db.players[enc.key]
    if p then p[field] = math.max(0, (p[field] or 0) + delta) end
    local g = ns:GetGuild(enc.guildKey)
    if g then g[field] = math.max(0, (g[field] or 0) + delta) end
end

-- kind: "kill" or "death". info: player info table (see ns:ReadUnit).
-- how: how it was detected ("event", "honor", "auto", "picked", "manual").
function ns:RecordEncounter(kind, info, how)
    local p = ns:TouchPlayer(info)
    if not p then return nil end
    local zone, sub = ns:ZoneInfo()
    local enc = {
        t = time(),
        kind = kind,
        key = info.key,
        guildKey = p.guildKey,
        class = p.class,
        race = p.race,
        level = info.level or p.level,
        zone = zone,
        sub = sub ~= "" and sub or nil,
        me = ns:MyKey(),
        how = how,
    }
    table.insert(ns.db.encounters, enc)
    Count(enc, 1)
    ns:Fire("ENCOUNTER", enc)
    ns:Fire("DATA_CHANGED", "encounter", info.key)
    return enc
end

-- Moves a death (or kill) to a different player, e.g. when the killer was
-- guessed wrong.
function ns:ReassignEncounter(enc, info)
    Count(enc, -1)
    local p = ns:TouchPlayer(info)
    enc.key = info.key
    enc.guildKey = p.guildKey
    enc.class = p.class
    enc.race = p.race
    enc.level = info.level or p.level
    enc.how = "picked"
    Count(enc, 1)
    ns:Fire("DATA_CHANGED", "encounter", info.key)
end

function ns:DeleteEncounter(enc)
    local list = ns.db.encounters
    for i = #list, 1, -1 do
        if list[i] == enc then
            Count(enc, -1)
            table.remove(list, i)
            ns:Fire("DATA_CHANGED", "encounter", enc.key)
            return
        end
    end
end

function ns:LastEncounterWith(key)
    local list = ns.db.encounters
    for i = #list, 1, -1 do
        if list[i].key == key then return list[i] end
    end
end

function ns:LastGuildEncounter(gkey)
    local list = ns.db.encounters
    for i = #list, 1, -1 do
        if list[i].guildKey == gkey then return list[i] end
    end
end

function ns:Totals(me)
    local k, d = 0, 0
    for _, e in ipairs(ns.db.encounters) do
        if not me or e.me == me then
            if e.kind == "kill" then k = k + 1 else d = d + 1 end
        end
    end
    return k, d
end

-- Has this player (or their guild) any history or list membership worth
-- telling the user about?
function ns:IsInteresting(key, guildKey)
    local p = ns.db.players[key]
    if p and (p.list or p.note or (p.kills or 0) > 0 or (p.deaths or 0) > 0) then return true end
    local g = ns:GetGuild(guildKey or (p and p.guildKey))
    if g and (g.list or g.note) then return true end
    return false
end

-- One-line summary of our last encounter with a player.
function ns:LastEncounterText(key)
    local e = ns:LastEncounterWith(key)
    if not e then return nil end
    if e.kind == "kill" then
        return "You killed them " .. ns:Ago(e.t)
    end
    return "They killed you " .. ns:Ago(e.t)
end

--------------------------------------------------------------------------------
-- Statistics
--------------------------------------------------------------------------------

local function StartOfDay(t)
    local d = date("*t", t)
    d.hour, d.min, d.sec = 0, 0, 0
    return time(d)
end

local function StartOfWeek(t)
    local d = date("*t", t)
    local offset = (d.wday + 5) % 7 -- days since Monday
    d.day = d.day - offset
    d.hour, d.min, d.sec = 0, 0, 0
    return time(d)
end

local function StartOfMonth(t)
    local d = date("*t", t)
    d.day, d.hour, d.min, d.sec = 1, 0, 0, 0
    return time(d)
end

local function StartOfYear(t)
    local d = date("*t", t)
    d.month, d.day, d.hour, d.min, d.sec = 1, 1, 0, 0, 0
    return time(d)
end

ns.StartOfDay = StartOfDay

-- Builds every number the statistics tab shows. me: restrict to one character
-- key, or nil for all characters.
function ns:ComputeStats(me)
    local now = time()
    local periods = {
        { label = "Today",      from = StartOfDay(now) },
        { label = "This week",  from = StartOfWeek(now) },
        { label = "This month", from = StartOfMonth(now) },
        { label = "This year",  from = StartOfYear(now) },
        { label = "All time",   from = 0 },
    }
    for _, p in ipairs(periods) do p.kills, p.deaths = 0, 0 end

    local DAYS = 14
    local today = StartOfDay(now)
    local daily = {}
    for i = 1, DAYS do
        local d = date("*t", today)
        d.day = d.day - (DAYS - i)
        daily[i] = { from = time(d), kills = 0, deaths = 0 }
    end

    local classes, guilds, players = {}, {}, {}
    local total = { kills = 0, deaths = 0 }
    local firstT

    for _, e in ipairs(ns.db.encounters) do
        if not me or e.me == me then
            local field = e.kind == "kill" and "kills" or "deaths"
            total[field] = total[field] + 1
            firstT = firstT and math.min(firstT, e.t) or e.t
            for _, p in ipairs(periods) do
                if e.t >= p.from then p[field] = p[field] + 1 end
            end
            if e.t >= daily[1].from then
                for i = DAYS, 1, -1 do
                    if e.t >= daily[i].from then
                        daily[i][field] = daily[i][field] + 1
                        break
                    end
                end
            end
            local c = e.class or "UNKNOWN"
            classes[c] = classes[c] or { class = e.class, kills = 0, deaths = 0 }
            classes[c][field] = classes[c][field] + 1
            if e.guildKey then
                guilds[e.guildKey] = guilds[e.guildKey] or { key = e.guildKey, kills = 0, deaths = 0 }
                guilds[e.guildKey][field] = guilds[e.guildKey][field] + 1
            end
            players[e.key] = players[e.key] or { key = e.key, class = e.class, kills = 0, deaths = 0 }
            players[e.key][field] = players[e.key][field] + 1
        end
    end

    local function ToSortedList(map, field)
        local out = {}
        for _, v in pairs(map) do
            if field == nil or v[field] > 0 then table.insert(out, v) end
        end
        table.sort(out, function(a, b)
            if field then
                if a[field] ~= b[field] then return a[field] > b[field] end
            else
                local ta, tb = a.kills + a.deaths, b.kills + b.deaths
                if ta ~= tb then return ta > tb end
            end
            return (a.key or a.class or "") < (b.key or b.class or "")
        end)
        return out
    end

    -- Averages per day/week/month since the first recorded encounter.
    local span = firstT and math.max(1, now - firstT) or nil
    local averages
    if span then
        local days = math.max(1, span / 86400)
        averages = {
            perDay = total.kills / days,
            perWeek = total.kills / math.max(1, days / 7),
            perMonth = total.kills / math.max(1, days / 30.44),
        }
    end

    return {
        total = total,
        periods = periods,
        daily = daily,
        classes = ToSortedList(classes),
        guildsKilled = ToSortedList(guilds, "kills"),
        guildsDiedTo = ToSortedList(guilds, "deaths"),
        playersKilled = ToSortedList(players, "kills"),
        playersDiedTo = ToSortedList(players, "deaths"),
        averages = averages,
        firstT = firstT,
    }
end
