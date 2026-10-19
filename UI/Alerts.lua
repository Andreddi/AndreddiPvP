local _, ns = ...
local UI = ns.UI

-- Proximity alerts: a toast (plus optional sound and chat line) when a player
-- from the history or the lists shows up on a nameplate, target or mouseover.

--------------------------------------------------------------------------------
-- Sounds
--------------------------------------------------------------------------------

-- kit: SOUNDKIT constant name, id: fallback sound kit id, file: a sound file
-- path. Add your own entries here, e.g.
--   { key = "mine", label = "My sound", file = "Interface\\AddOns\\AndreddiPvP\\Sounds\\mine.ogg" },
local SOUND_CATALOG = {
    { key = "none",          label = "No sound" },
    { key = "raidwarning",   label = "Raid warning",       kit = "RAID_WARNING", id = 8959 },
    { key = "bosswhisper",   label = "Boss whisper alarm", kit = "UI_RAID_BOSS_WHISPER_WARNING", id = 37881 },
    { key = "alarm",         label = "Alarm clock",        kit = "ALARM_CLOCK_WARNING_3", id = 12889 },
    { key = "readycheck",    label = "Ready check",        kit = "READY_CHECK", id = 8960 },
    { key = "questfailed",   label = "Quest failed",       kit = "IG_QUEST_FAILED", id = 847 },
    { key = "pvpqueue",      label = "PvP queue pop",      kit = "PVP_THROUGH_QUEUE" },
    { key = "friendtoast",   label = "Friend online chime", kit = "UI_BNET_TOAST", id = 18019 },
    { key = "tell",          label = "Whisper",            kit = "TELL_MESSAGE", id = 3081 },
    { key = "mapping",       label = "Map ping",           kit = "MAP_PING", id = 3175 },
    { key = "questcomplete", label = "Quest complete",     kit = "IG_QUEST_LIST_COMPLETE" },
    { key = "coin",          label = "Coins",              kit = "LOOT_WINDOW_COIN_SOUND", id = 120 },
    { key = "levelup",       label = "Level up",           kit = "LEVEL_UP" },
}

ns.sounds = {}
ns.soundByKey = {}

local function BuildSoundList()
    wipe(ns.sounds)
    for _, s in ipairs(SOUND_CATALOG) do
        local entry = { key = s.key, label = s.label, file = s.file }
        if s.kit and SOUNDKIT and SOUNDKIT[s.kit] then
            entry.id = SOUNDKIT[s.kit]
        elseif s.id then
            entry.id = s.id
        end
        if s.key == "none" or entry.id or entry.file then
            table.insert(ns.sounds, entry)
            ns.soundByKey[s.key] = entry
        end
    end
end

function ns:PlayAlertSound(key)
    local s = ns.soundByKey[key]
    if not s or s.key == "none" then return end
    local channel = ns.db.settings.soundChannel or "Master"
    if s.file then
        pcall(PlaySoundFile, s.file, channel)
    elseif s.id then
        pcall(PlaySound, s.id, channel)
    end
end

--------------------------------------------------------------------------------
-- Toasts
--------------------------------------------------------------------------------

local anchor
local toasts = {}   -- visible, newest first
local pool = {}
local TOAST_WIDTH = 300

local CATEGORY = {
    kos      = { title = "Kill on sight nearby", color = ns.LIST_INFO.kos.color },
    friendly = { title = "Friendly nearby",      color = ns.LIST_INFO.friendly.color },
    history  = { title = "Known player nearby",  color = { 0.83, 0.63, 0.09 } },
}

local function Layout()
    local prev
    for _, t in ipairs(toasts) do
        t:ClearAllPoints()
        if prev then
            t:SetPoint("TOP", prev, "BOTTOM", 0, -4)
        else
            t:SetPoint("TOP", anchor, "TOP", 0, 0)
        end
        prev = t
    end
end

local function Release(t)
    for i, v in ipairs(toasts) do
        if v == t then table.remove(toasts, i) break end
    end
    t:Hide()
    t.key = nil
    table.insert(pool, t)
    Layout()
end

local function CreateToast()
    local t = CreateFrame("Button", nil, UIParent, "BackdropTemplate")
    t:SetWidth(TOAST_WIDTH)
    t:SetFrameStrata("HIGH")
    t:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    UI.SetBackdrop(t)

    t.stripe = t:CreateTexture(nil, "ARTWORK")
    t.stripe:SetPoint("TOPLEFT", 1, -1)
    t.stripe:SetPoint("BOTTOMLEFT", 1, 1)
    t.stripe:SetWidth(4)

    t.header = UI.Text(t, "GameFontNormalSmall")
    t.header:SetPoint("TOPLEFT", 12, -7)
    t.tag = UI.Text(t, "GameFontNormalSmall", "", "RIGHT")
    t.tag:SetPoint("TOPRIGHT", -8, -7)

    t.name = UI.Text(t, "GameFontNormalLarge")
    t.name:SetPoint("TOPLEFT", t.header, "BOTTOMLEFT", 0, -3)
    t.name:SetPoint("RIGHT", -8, 0)

    t.body = UI.Text(t, "GameFontHighlightSmall")
    t.body:SetPoint("TOPLEFT", t.name, "BOTTOMLEFT", 0, -3)
    t.body:SetPoint("RIGHT", -8, 0)
    t.body:SetSpacing(2)
    t.body:SetWordWrap(true)

    t:SetScript("OnClick", function(self, button)
        if button == "LeftButton" and self.key and ns:GetPlayer(self.key) then
            ns:ShowMainWindow("players", self.key)
        end
        Release(self)
    end)
    t:SetScript("OnUpdate", function(self, elapsed)
        if self:IsMouseOver() then
            self:SetAlpha(1)
            return
        end
        self.remaining = self.remaining - elapsed
        if self.remaining <= 0 then
            Release(self)
        elseif self.remaining < 1 then
            self:SetAlpha(self.remaining)
        end
    end)
    return t
end

local function ShowToast(data)
    -- Replace an existing toast for the same player.
    for _, t in ipairs(toasts) do
        if t.key == data.key then Release(t) break end
    end
    local t = table.remove(pool) or CreateToast()
    local cat = CATEGORY[data.category]
    t.key = data.key
    t.stripe:SetColorTexture(cat.color[1], cat.color[2], cat.color[3], 1)
    t.header:SetText(cat.title)
    t.header:SetTextColor(cat.color[1], cat.color[2], cat.color[3])
    t.tag:SetText(data.tag or "")
    t.name:SetText(data.name)
    t.body:SetText(data.body)
    t:SetHeight(7 + t.header:GetStringHeight() + 3 + t.name:GetStringHeight() + 3 + t.body:GetStringHeight() + 9)
    t.remaining = ns.db.settings.alertDuration or 10
    t:SetAlpha(1)
    t:Show()

    table.insert(toasts, 1, t)
    local max = ns.db.settings.alertMax or 3
    while #toasts > max do Release(toasts[#toasts]) end
    Layout()
end

--------------------------------------------------------------------------------
-- Alert logic
--------------------------------------------------------------------------------

local lastAlert = {}

-- Builds the toast text for a player. Returns nil if there is nothing to say.
function ns:BuildAlert(info)
    local key = info.key
    local p = ns:GetPlayer(key)
    local gkey = info.guildKey or (p and p.guildKey)
    local g = ns:GetGuild(gkey)
    local list, source = ns:EffectiveList(key, gkey)
    local category = list or "history"
    if category == "ignore" then return nil end

    local class = info.class or (p and p.class)
    local level = info.level or (p and p.level)
    local name = ns:ColoredName(key, class)
    if level then name = name .. " |cffbbbbbb" .. level .. "|r" end

    local lines = {}
    local who = {}
    if class then table.insert(who, ns:ClassName(class)) end
    local guildName = (info.guild) or (g and g.name)
    if guildName then table.insert(who, "|cffd4a017<" .. guildName .. ">|r") end
    if #who > 0 then table.insert(lines, table.concat(who, "  ")) end

    if p and ((p.kills or 0) + (p.deaths or 0)) > 0 then
        local line = "You vs them: " .. ns:KDText(p.kills, p.deaths)
        local last = ns:LastEncounterText(key)
        if last then line = line .. "  |cff999999" .. last .. "|r" end
        table.insert(lines, line)
    end
    if g and ((g.kills or 0) + (g.deaths or 0)) > 0 then
        table.insert(lines, "You vs guild: " .. ns:KDText(g.kills, g.deaths))
    end
    if p and p.note then table.insert(lines, "|cffffd100Note:|r " .. p.note) end
    if g and g.note then table.insert(lines, "|cffffd100Guild note:|r " .. g.note) end

    local tag = list and ns:ListTag(list) or nil
    if tag and source == "guild" then tag = tag .. " |cff999999guild|r" end

    return {
        key = key,
        category = category,
        name = name,
        tag = tag,
        body = table.concat(lines, "\n"),
    }
end

function ns:MaybeAlert(info, source)
    local s = ns.db.settings
    if not s.alertsEnabled or not info or not info.key then return end
    if not s.alertInInstances and ns:InAnyInstance() then return end
    if not ns:IsInteresting(info.key, info.guildKey) then return end

    local list = ns:EffectiveList(info.key, info.guildKey)
    if list == "ignore" then return end
    if list == "kos" and not s.alertKOS then return end
    if list == "friendly" and not s.alertFriendly then return end
    if not list and not s.alertHistory then return end

    local now = GetTime()
    if lastAlert[info.key] and now - lastAlert[info.key] < (s.alertCooldown or 300) then return end
    lastAlert[info.key] = now

    local data = ns:BuildAlert(info)
    if not data then return end
    ShowToast(data)

    if s.soundsEnabled then
        local soundKey = (list == "kos" and s.soundKOS) or (list == "friendly" and s.soundFriendly) or s.soundHistory
        ns:PlayAlertSound(soundKey)
    end
    if s.alertChat then
        local tag = data.tag and (data.tag .. " ") or ""
        ns:Print(tag .. data.name .. " is nearby" .. (source and (" |cff777777(" .. source .. ")|r") or ""))
    end
end

--------------------------------------------------------------------------------
-- Anchor and test
--------------------------------------------------------------------------------

local function BuildAnchor()
    anchor = CreateFrame("Frame", "AndreddiPvPAlertAnchor", UIParent, "BackdropTemplate")
    anchor:SetSize(TOAST_WIDTH, 30)
    anchor:SetMovable(true)
    anchor:SetClampedToScreen(true)
    anchor:RegisterForDrag("LeftButton")
    anchor:SetScript("OnDragStart", anchor.StartMoving)
    anchor:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint(1)
        ns.db.frames.alertAnchor = { point = point, relPoint = relPoint, x = x, y = y }
    end)
    anchor.saveKey = "alertAnchor"
    UI.RestorePosition(anchor, { "TOP", UIParent, "TOP", 280, -180 })
    anchor.label = UI.Text(anchor, "GameFontNormalSmall", "AndreddiPvP alerts. Drag me, then type /apvp lock", "CENTER")
    anchor.label:SetPoint("CENTER")
    anchor.label:Hide()
    anchor:EnableMouse(false)
end

-- force: true = unlock, false = lock, nil = toggle.
function ns:ToggleAlertAnchor(force)
    local unlocked = not anchor.unlocked
    if force ~= nil then unlocked = force end
    anchor.unlocked = unlocked
    anchor:EnableMouse(unlocked)
    anchor.label:SetShown(unlocked)
    if unlocked then
        UI.SetBackdrop(anchor, { 0.83, 0.63, 0.09, 0.3 }, { 0.83, 0.63, 0.09, 1 })
    else
        anchor:SetBackdrop(nil)
    end
    ns:Print(unlocked and "Alert anchor unlocked. Drag it, then /apvp lock." or "Alert anchor locked.")
end

function ns:TestAlert()
    local key = ns:PlayerKey("Testgnome", nil)
    ShowToast({
        key = "test:kos",
        category = "kos",
        name = ns:ColoredName(key, "ROGUE") .. " |cffbbbbbb60|r",
        tag = ns:ListTag("kos"),
        body = "Rogue  |cffd4a017<Example Guild>|r\nYou vs them: " .. ns:KDText(2, 5)
            .. "  |cff999999They killed you 3 days ago|r\n|cffffd100Note:|r Camps the flight master.",
    })
    ShowToast({
        key = "test:friendly",
        category = "friendly",
        name = ns:ColoredName(key, "PRIEST") .. " |cffbbbbbb58|r",
        tag = ns:ListTag("friendly"),
        body = "Priest\n|cffffd100Note:|r Healed me at Tarren Mill.",
    })
    if ns.db.settings.soundsEnabled then ns:PlayAlertSound(ns.db.settings.soundKOS) end
end

ns:Listen("DB_READY", function()
    BuildSoundList()
    BuildAnchor()
end)
