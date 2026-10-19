local _, ns = ...
local UI = ns.UI

-- Small window shown after a kill or death. Lets the user list the player or
-- their guild and write a note straight away. Entries queue up when several
-- encounters happen close together.

local queue = {}
local popup
local WIDTH = 340

local function CurrentEntry() return queue[1] end

local function Build()
    popup = UI.CreateWindow("AndreddiPvPPopup", "", WIDTH, 200, "popup")
    popup:SetFrameStrata("DIALOG")
    popup.closeButton:SetScript("OnClick", function() ns:ClosePopup() end)

    popup.counter = UI.Text(popup, "GameFontDisableSmall", "", "RIGHT")
    popup.counter:SetPoint("TOPRIGHT", -30, -12)

    ----------------------------------------------------------------------------
    -- Info panel (kill / death)
    ----------------------------------------------------------------------------
    local info = CreateFrame("Frame", nil, popup)
    info:SetPoint("TOPLEFT", 12, -30)
    info:SetPoint("BOTTOMRIGHT", -12, 36)
    popup.info = info

    info.name = UI.Text(info, "GameFontNormalLarge")
    info.name:SetPoint("TOPLEFT", 0, 0)
    info.detail = UI.Text(info, "GameFontHighlightSmall")
    info.detail:SetPoint("TOPLEFT", info.name, "BOTTOMLEFT", 0, -3)
    info.detail:SetPoint("RIGHT", info, "RIGHT")
    info.record = UI.Text(info, "GameFontHighlightSmall")
    info.record:SetPoint("TOPLEFT", info.detail, "BOTTOMLEFT", 0, -3)
    info.record:SetPoint("RIGHT", info, "RIGHT")

    local pl = UI.Text(info, "GameFontNormalSmall", "Player")
    pl:SetPoint("TOPLEFT", info.record, "BOTTOMLEFT", 0, -12)
    info.playerList = UI.ListSelector(info, function(list)
        local e = CurrentEntry()
        if e and e.enc then ns:SetPlayerList(e.enc.key, list) end
        if e then e.touched = true end
    end, 58)
    info.playerList:SetPoint("LEFT", pl, "LEFT", 70, 0)

    info.guildLabel = UI.Text(info, "GameFontNormalSmall", "Guild")
    info.guildLabel:SetPoint("TOPLEFT", pl, "BOTTOMLEFT", 0, -12)
    info.guildList = UI.ListSelector(info, function(list)
        local e = CurrentEntry()
        if e and e.enc and e.enc.guildKey then ns:SetGuildList(e.enc.guildKey, list) end
        if e then e.touched = true end
    end, 58)
    info.guildList:SetPoint("LEFT", info.guildLabel, "LEFT", 70, 0)

    info.note = UI.EditBox(info, WIDTH - 24, 22, function(text)
        local e = CurrentEntry()
        if e and e.enc then ns:SetPlayerNote(e.enc.key, text) end
    end)
    info.note:SetPlaceholder("Note about this player (Enter to save)")
    info.note:SetPoint("TOPLEFT", info.guildLabel, "BOTTOMLEFT", 0, -10)

    info.wrong = UI.Button(info, "Wrong player?", 100, 18, function()
        local e = CurrentEntry()
        if e and e.death then
            e.mode = "pick"
            ns:RefreshPopup()
        end
    end)
    info.wrong:SetPoint("TOPRIGHT", info, "TOPRIGHT", 0, 0)

    ----------------------------------------------------------------------------
    -- Pick panel (choose the killer)
    ----------------------------------------------------------------------------
    local pick = CreateFrame("Frame", nil, popup)
    pick:SetPoint("TOPLEFT", 12, -30)
    pick:SetPoint("BOTTOMRIGHT", -12, 36)
    popup.pick = pick

    pick.help = UI.Text(pick, "GameFontHighlightSmall",
        "Enemy players that were targeting you. Pick the one who killed you:")
    pick.help:SetPoint("TOPLEFT")
    pick.help:SetPoint("RIGHT")
    pick.buttons = {}
    for i = 1, 6 do
        local b = UI.Button(pick, "", (WIDTH - 30) / 2, 20, function(self)
            ns:PickKiller(self.candidate)
        end)
        local col = (i - 1) % 2
        local rowIdx = math.floor((i - 1) / 2)
        b:SetPoint("TOPLEFT", pick.help, "BOTTOMLEFT", col * ((WIDTH - 30) / 2 + 6), -8 - rowIdx * 23)
        pick.buttons[i] = b
    end
    pick.manualLabel = UI.Text(pick, "GameFontNormalSmall", "Or type a name:")
    pick.manual = UI.EditBox(pick, 190, 22)
    pick.manual:SetPlaceholder("Name or Name-Realm")
    pick.manual:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        local text = strtrim(self:GetText() or "")
        if text ~= "" then
            ns:PickKiller({ key = ns:PlayerKey(text, nil) })
            self:SetText("")
        end
    end)
    pick.manualButton = UI.Button(pick, "Record", 70, 22, function()
        local text = strtrim(pick.manual:GetText() or "")
        if text ~= "" then
            ns:PickKiller({ key = ns:PlayerKey(text, nil) })
            pick.manual:SetText("")
        end
    end)

    ----------------------------------------------------------------------------
    -- Footer
    ----------------------------------------------------------------------------
    popup.details = UI.Button(popup, "Open history", 100, 20, function()
        local e = CurrentEntry()
        local key = e and e.enc and e.enc.key
        ns:ShowMainWindow("players", key)
    end)
    popup.details:SetPoint("BOTTOMLEFT", 12, 10)

    popup.dismiss = UI.Button(popup, "Close", 80, 20, function() ns:ClosePopup() end)
    popup.dismiss:SetPoint("BOTTOMRIGHT", -12, 10)

    popup.timer = UI.Text(popup, "GameFontDisableSmall", "", "RIGHT")
    popup.timer:SetPoint("RIGHT", popup.dismiss, "LEFT", -8, 0)

    popup:SetScript("OnUpdate", function(self, elapsed)
        local e = CurrentEntry()
        local limit = ns.db.settings.popupAutoClose or 0
        if not e or limit <= 0 or e.touched then
            self.timer:SetText("")
            return
        end
        if self:IsMouseOver() or info.note:HasFocus() or pick.manual:HasFocus() then
            e.touched = true
            self.timer:SetText("")
            return
        end
        e.remaining = (e.remaining or limit) - elapsed
        self.timer:SetText(("closes in %d"):format(math.ceil(e.remaining)))
        if e.remaining <= 0 then ns:ClosePopup() end
    end)

    UI.RestorePosition(popup, { "TOP", UIParent, "TOP", 0, -140 })
end

local function SetupInfo(e)
    local info = popup.info
    local enc = e.enc
    local p = ns:GetPlayer(enc.key) or {}
    local g = ns:GetGuild(enc.guildKey)

    local title
    if enc.kind == "kill" then
        title = "|cff40ff40You killed|r"
    else
        title = "|cffff4040Killed by|r"
        if enc.how == "auto" then title = title .. " |cff999999(best guess)|r" end
    end
    popup.title:SetText(title)

    local _, _, _, hex = ns:ClassColor(p.class)
    info.name:SetText("|c" .. hex .. ns:ShortName(enc.key) .. "|r")

    local bits = {}
    if enc.level or p.level then table.insert(bits, "Level " .. (enc.level or p.level)) end
    if p.race then table.insert(bits, p.race) end
    if p.class then table.insert(bits, ns:ClassName(p.class)) end
    local line = table.concat(bits, " ")
    if g then line = line .. "  |cffd4a017<" .. g.name .. ">|r" end
    info.detail:SetText(line ~= "" and line or "Unknown level and class")

    local rec = "You vs them: " .. ns:KDText(p.kills, p.deaths)
    if g then rec = rec .. "     Guild: " .. ns:KDText(g.kills, g.deaths) end
    info.record:SetText(rec)

    info.playerList:SetValue(p.list)
    info.guildLabel:SetShown(g ~= nil)
    info.guildList:SetShown(g ~= nil)
    if g then
        info.guildList:SetValue(g.list)
        info.note:ClearAllPoints()
        info.note:SetPoint("TOPLEFT", info.guildLabel, "BOTTOMLEFT", 0, -10)
    else
        info.note:ClearAllPoints()
        info.note:SetPoint("TOPLEFT", info.guildLabel, "TOPLEFT", 0, 0)
    end
    info.note:SetText(p.note or "")
    info.wrong:SetShown(e.death ~= nil)

    popup:SetHeight(g and 214 or 182)
end

local function SetupPick(e)
    local pick = popup.pick
    local candidates = e.death and e.death.candidates or {}
    popup.title:SetText("|cffff4040Who killed you?|r")

    local shown = 0
    for i, b in ipairs(pick.buttons) do
        local c = candidates[i]
        if c then
            local _, _, _, hex = ns:ClassColor(c.class)
            local label = "|c" .. hex .. ns:ShortName(c.key) .. "|r"
            if c.level then label = label .. " |cff999999" .. c.level .. "|r" end
            b:SetText(label)
            b.candidate = c
            b:Show()
            shown = i
        else
            b:Hide()
        end
    end
    pick.help:SetText(shown > 0
        and "Enemy players that were targeting you. Pick the one who killed you:"
        or "No enemy players were seen targeting you. Type the killer's name:")

    local rows = math.ceil(shown / 2)
    local anchorY = -8 - rows * 23 - (shown > 0 and 6 or 0)
    pick.manualLabel:ClearAllPoints()
    pick.manualLabel:SetPoint("TOPLEFT", pick.help, "BOTTOMLEFT", 0, anchorY - 4)
    pick.manual:ClearAllPoints()
    pick.manual:SetPoint("LEFT", pick.manualLabel, "RIGHT", 8, 0)
    pick.manualButton:ClearAllPoints()
    pick.manualButton:SetPoint("LEFT", pick.manual, "RIGHT", 4, 0)
    pick.manual:SetWidth(WIDTH - 24 - pick.manualLabel:GetStringWidth() - 8 - 74)

    popup:SetHeight(30 + 30 + rows * 23 + 40 + 40)
    popup.dismiss:SetText(e.death and e.death.enc and "Close" or "Not a player")
end

function ns:RefreshPopup()
    if not popup then return end
    local e = CurrentEntry()
    if not e then
        popup:Hide()
        return
    end
    popup.counter:SetText(#queue > 1 and ("1 of " .. #queue) or "")
    local isPick = e.mode == "pick"
    popup.info:SetShown(not isPick)
    popup.pick:SetShown(isPick)
    popup.details:SetShown(not isPick)
    if isPick then SetupPick(e) else SetupInfo(e) end
    popup:Show()
end

function ns:QueuePopup(entry)
    if not popup then Build() end
    -- A new pick for the same death replaces the old one.
    for i = #queue, 1, -1 do
        if entry.death and queue[i].death == entry.death then table.remove(queue, i) end
    end
    table.insert(queue, entry)
    ns:RefreshPopup()
end

function ns:ClosePopup()
    if not popup then return end
    local e = CurrentEntry()
    if e and e.enc and popup.info.note:HasFocus() then
        popup.info.note:ClearFocus() -- commits the note
    end
    table.remove(queue, 1)
    ns:RefreshPopup()
end

function ns:PickKiller(candidate)
    local e = CurrentEntry()
    if not e or not e.death or not candidate or not candidate.key then return end
    local enc = ns:AttributeDeath(e.death, candidate, "picked")
    e.enc = enc
    e.mode = "death"
    e.touched = true
    ns:Print("Death recorded: killed by " .. ns:ColoredName(enc.key, enc.class))
    ns:RefreshPopup()
end

-- Keep the popup in sync when the data is changed from elsewhere.
ns:Listen("DATA_CHANGED", function()
    if popup and popup:IsShown() then
        local e = CurrentEntry()
        if e and e.mode ~= "pick" and not popup.info.note:HasFocus() then SetupInfo(e) end
    end
end)
