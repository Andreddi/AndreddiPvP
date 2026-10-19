local _, ns = ...
local Safe = ns.Safe
local SafeCall = ns.SafeCall

-- WoW: Forever gives addons no combat log. Kills come from the PARTY_KILL
-- frame event (attackerGUID, targetGUID). Deaths come from PLAYER_DEAD, which
-- carries no killer, so we keep a short memory of enemy players that were
-- targeting us and attribute the death to them (or let the user pick).

--------------------------------------------------------------------------------
-- Recently seen players (in memory only)
--------------------------------------------------------------------------------

ns.seen = {}        -- guid -> info (with .t)
ns.seenByKey = {}   -- key  -> info
ns.threats = {}     -- key  -> { info = info, t = time }

local SEEN_TTL = 1800

-- Merges b into a, keeping fields a already has unless b has them too.
local function Merge(a, b)
    if not b then return a end
    if not a then return b end
    for k, v in pairs(b) do
        if v ~= nil then a[k] = v end
    end
    return a
end
ns.MergeInfo = Merge

function ns:Remember(info)
    if not info or not info.key then return info end
    local prev = (info.guid and ns.seen[info.guid]) or ns.seenByKey[info.key]
    local merged = Merge(prev and CopyTable(prev) or {}, info)
    merged.t = GetTime()
    if merged.guid then ns.seen[merged.guid] = merged end
    ns.seenByKey[merged.key] = merged
    return merged
end

function ns:SeenByGUID(guid)
    return guid and ns.seen[guid]
end

function ns:SeenByKey(key)
    return key and ns.seenByKey[key]
end

function ns:PruneSeen()
    local now = GetTime()
    for guid, info in pairs(ns.seen) do
        if now - info.t > SEEN_TTL then ns.seen[guid] = nil end
    end
    for key, info in pairs(ns.seenByKey) do
        if now - info.t > SEEN_TTL then ns.seenByKey[key] = nil end
    end
    local window = ns.db.settings.deathWindow or 20
    for key, th in pairs(ns.threats) do
        if now - th.t > window * 3 then ns.threats[key] = nil end
    end
end

-- Called by the scanner whenever an enemy player is seen targeting us.
function ns:NoteThreat(info)
    if not info or not info.key then return end
    local th = ns.threats[info.key]
    if th then
        th.info = Merge(th.info, info)
        th.t = GetTime()
    else
        ns.threats[info.key] = { info = info, t = GetTime() }
    end
end

-- Enemy players that targeted us within the death window, most recent first.
function ns:RecentThreats()
    local now = GetTime()
    local window = ns.db.settings.deathWindow or 20
    local out = {}
    for _, th in pairs(ns.threats) do
        if now - th.t <= window then table.insert(out, th) end
    end
    table.sort(out, function(a, b) return a.t > b.t end)
    return out
end

-- Best available info about a player GUID: a live unit, then the seen cache,
-- then the client's GUID cache.
function ns:ResolveGUID(guid)
    local unit = ns:FindUnitByGUID(guid)
    local info = unit and ns:ReadUnit(unit)
    info = Merge(CopyTable(ns:SeenByGUID(guid) or {}), info)
    if not info.key then
        info = Merge(ns:ReadGUID(guid) or {}, info)
    end
    if not info.key then return nil end
    -- The GUID cache knows class/race but not guild; fill guild from our records.
    if not info.guildKey then
        local p = ns:GetPlayer(info.key)
        if p and p.guildKey then
            info.guildKey, info.guild = p.guildKey, p.guild
        end
    end
    info.guid = guid
    return info
end

--------------------------------------------------------------------------------
-- Kills
--------------------------------------------------------------------------------

local recentKills = {}

local function IsGroupMember(guid)
    if not IsInGroup() then return false end
    local prefix, count = "party", GetNumSubgroupMembers()
    if IsInRaid() then prefix, count = "raid", GetNumGroupMembers() end
    for i = 1, count do
        local u = prefix .. i
        if SafeCall(UnitGUID, u) == guid then return true end
        if SafeCall(UnitGUID, u .. "pet") == guid then return true end
    end
    return false
end

local function IsMine(guid)
    if guid == SafeCall(UnitGUID, "player") then return true end
    local pet = SafeCall(UnitGUID, "pet")
    return pet ~= nil and guid == pet
end

local function ShouldTrackHere()
    if ns:InInstancedPvP() and not ns.db.settings.trackInstancedPvP then return false end
    return true
end

function ns:OnKill(victimGUID, how)
    if not ShouldTrackHere() then return end
    local now = GetTime()
    if recentKills[victimGUID] and now - recentKills[victimGUID] < 5 then return end
    recentKills[victimGUID] = now

    local info = ns:ResolveGUID(victimGUID)
    if not info then
        ns:Debug("Kill on unknown player GUID", victimGUID)
        return
    end
    ns.threats[info.key] = nil
    local enc = ns:RecordEncounter("kill", info, how or "event")
    if not enc then return end
    ns:Debug("Kill recorded:", info.key)

    local list = ns:EffectiveList(info.key, info.guildKey)
    if ns.db.settings.popupOnKill and list ~= "ignore" then
        ns:QueuePopup({ mode = "kill", enc = enc })
    end
end

ns:On("PARTY_KILL", function(_, attackerGUID, targetGUID)
    attackerGUID, targetGUID = Safe(attackerGUID), Safe(targetGUID)
    if not attackerGUID or not targetGUID then return end
    if not ns:IsPlayerGUID(targetGUID) then return end
    if IsMine(attackerGUID) then
        ns:OnKill(targetGUID, "event")
    elseif ns.db.settings.countGroupKills and IsGroupMember(attackerGUID) then
        ns:OnKill(targetGUID, "group")
    end
end)

--------------------------------------------------------------------------------
-- Deaths
--------------------------------------------------------------------------------

ns.lastDeath = nil -- { t, candidates = { info... }, enc = recorded encounter or nil }

local function OnDeath()
    if not ShouldTrackHere() then return end
    local threats = ns:RecentThreats()
    local candidates = {}
    for _, th in ipairs(threats) do
        table.insert(candidates, th.info)
    end
    -- Our current target counts too if it is a hostile player.
    local target = ns:ReadUnit("target")
    if target and target.hostile then
        local found = false
        for _, c in ipairs(candidates) do
            if c.key == target.key then found = true break end
        end
        if not found then table.insert(candidates, target) end
    end

    local death = { t = time(), candidates = candidates }
    ns.lastDeath = death
    wipe(ns.threats)

    if #candidates == 0 then
        ns:Debug("Died with no enemy player suspects")
        return
    end

    local s = ns.db.settings
    if #candidates == 1 and s.autoAttributeDeath then
        local info = candidates[1]
        death.enc = ns:RecordEncounter("death", info, "auto")
        local list = ns:EffectiveList(info.key, info.guildKey)
        if s.popupOnDeath and list ~= "ignore" then
            ns:QueuePopup({ mode = "death", enc = death.enc, death = death })
        end
    elseif s.popupOnDeath then
        ns:QueuePopup({ mode = "pick", death = death })
    else
        ns:Print("You died with " .. #candidates .. " enemy players nearby. Type /apvp death to record who killed you.")
    end
end

ns:On("PLAYER_DEAD", function() OnDeath() end)

-- Records (or re-records) the last death against info.
function ns:AttributeDeath(death, info, how)
    if death.enc then
        ns:ReassignEncounter(death.enc, info)
    else
        death.enc = ns:RecordEncounter("death", info, how or "picked")
    end
    return death.enc
end

function ns:ShowDeathPicker()
    local death = ns.lastDeath
    if not death then
        death = { t = time(), candidates = {} }
        ns.lastDeath = death
    end
    ns:QueuePopup({ mode = "pick", death = death })
end

ns:Listen("LOGIN", function()
    C_Timer.NewTicker(60, function() ns:PruneSeen() end)
end)
