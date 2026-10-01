-- JourneyTracker export: /journey export builds a summary of this
-- character's data, encodes it (JourneyTrackerSerialize.lua) and shows the
-- "JT1:..." string in a window to copy. /journey testexport does the same
-- with fixed fake data, to check the encoder against tools/import.
--
-- The summary is the saved stats, not a raw event log, and leaves out
-- anything that could identify a person: the character's name and realm,
-- other players' names (never stored), chat text (never stored) and the
-- hashed IDs used to count group members.

local ADDON_NAME, ns = ...
local Serialize = ns.Serialize
local PREFIX = "|cff33ff99Journey|r"
local WARN_LENGTH = 100000 -- characters; bigger exports get a heads-up

---------------------------------------------------------------------------
-- Summary
---------------------------------------------------------------------------

local function BuildSummary(db)
    local Copy, cap = Serialize.Copy, Serialize.MAP_CAP

    local stats = Copy(db)
    -- These get their own places in the summary.
    for _, key in ipairs({ "characterId", "schemaVersion", "dings", "levels", "class", "wrapped" }) do
        stats[key] = nil
    end
    -- Never exported: the character's name and realm (exports are anonymous),
    -- window settings, internal bookkeeping, and the hashed IDs used to count
    -- players you grouped with (only the count goes out).
    for _, key in ipairs({ "char", "ui", "legacy", "legacySchema" }) do stats[key] = nil end
    if stats.money then stats.money.last = nil end
    if stats.quests then stats.quests.open = nil end
    if stats.social then stats.social.seen = nil end
    -- Skill-ups summarized to the highest rank reached at each level.
    for _, skill in pairs(stats.skills or {}) do
        local byLevel = {}
        for _, h in ipairs(skill.history or {}) do
            if h.level and h.rank and (not byLevel[h.level] or h.rank > byLevel[h.level]) then
                byLevel[h.level] = h.rank
            end
        end
        skill.history = nil
        skill.rankByLevel = byLevel
    end
    if stats.kills then stats.kills.byName = Serialize.Capped(stats.kills.byName, cap) end

    local class = Copy(db.class or {})
    if class.ALL then
        local all = class.ALL
        all.trainerNPCs, all.classQuestIDs, all.deathsSeen = nil, nil, nil
        if all.buffs then all.buffs.bySpell = Serialize.Capped(all.buffs.bySpell, cap) end
        all.food = Serialize.Capped(all.food, cap)
    end

    local wrapped = Copy(db.wrapped or {})
    wrapped.flags, wrapped.wasNeutral, wrapped.autoFlagged = nil, nil, nil

    local _, classToken = ns.Call("UnitClass", "player")
    local _, raceToken = ns.Call("UnitRace", "player")
    local played = ns.PlayedNow() or (db.played and db.played.total) or 0
    return {
        format = 1,
        characterId = db.characterId,
        addonVersion = ns.VERSION,
        schemaVersion = db.schemaVersion,
        exportedAt = time(),
        character = {
            class = ns.Str(classToken) or (db.char and db.char.class),
            race = ns.Str(raceToken) or (db.char and db.char.race),
            faction = ns.Str(ns.Call("UnitFactionGroup", "player")),
            level = ns.Level(),
            played = math.floor(played),
            ruleset = wrapped["W-020"],
        },
        levels = { snapshots = Copy(db.dings or {}), stats = Copy(db.levels or {}) },
        stats = stats,
        class = class,
        wrapped = wrapped,
    }
end

---------------------------------------------------------------------------
-- Export window: a movable dialog with the string pre-selected
---------------------------------------------------------------------------

local window, exportText

local function CreateWindow()
    local f = CreateFrame("Frame", "JourneyTrackerExportFrame", UIParent, "BackdropTemplate")
    f:SetSize(600, 400)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    table.insert(UISpecialFrames, "JourneyTrackerExportFrame") -- Escape closes it

    f.title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    f.title:SetPoint("TOP", 0, -18)
    local hint = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("TOP", f.title, "BOTTOM", 0, -6)
    hint:SetText("The text is selected: press Ctrl+C to copy it, then paste it to me in Discord.")

    local closeX = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeX:SetPoint("TOPRIGHT", -6, -6)

    local scroll = CreateFrame("ScrollFrame", "JourneyTrackerExportScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 22, -60)
    scroll:SetPoint("BOTTOMRIGHT", -40, 52)

    local box = CreateFrame("EditBox", nil, scroll)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetFontObject(ChatFontNormal)
    box:SetWidth(530)
    box:SetScript("OnEscapePressed", function() f:Hide() end)
    -- Read-only: typing puts the export back.
    box:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            self:SetText(exportText or "")
            self:HighlightText()
        end
    end)
    if ScrollingEdit_OnCursorChanged then box:SetScript("OnCursorChanged", ScrollingEdit_OnCursorChanged) end
    if ScrollingEdit_OnUpdate then
        box:SetScript("OnUpdate", function(self, elapsed) ScrollingEdit_OnUpdate(self, elapsed, scroll) end)
    end
    scroll:SetScrollChild(box)
    f.box = box

    local selectAll = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    selectAll:SetSize(120, 22)
    selectAll:SetPoint("BOTTOMLEFT", 20, 20)
    selectAll:SetText("Select All")
    selectAll:SetScript("OnClick", function()
        box:SetFocus()
        box:HighlightText()
    end)

    local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    close:SetSize(100, 22)
    close:SetPoint("BOTTOMRIGHT", -20, 20)
    close:SetText(CLOSE or "Close")
    close:SetScript("OnClick", function() f:Hide() end)

    f.length = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    f.length:SetPoint("BOTTOM", 0, 25)
    return f
end

local function Show(text, title)
    window = window or CreateWindow()
    exportText = text
    window.title:SetText(title)
    local count = BreakUpLargeNumbers and BreakUpLargeNumbers(#text) or tostring(#text)
    window.length:SetText(count .. " characters")
    window.box:SetText(text)
    window:Show()
    window.box:SetFocus()
    window.box:HighlightText()
end

---------------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------------

-- /journey export
function ns.Export()
    if InCombatLockdown() then
        print(PREFIX, "Can't export in combat.")
        return
    end
    local db = ns.GetDB()
    if not db then return end
    local summary = BuildSummary(db)
    local text, problem = Serialize.Encode(summary)
    if not text then
        print(PREFIX, "Export failed: " .. tostring(problem))
        return
    end
    Show(text, "Journey Export")
    if #text > WARN_LENGTH then
        print(PREFIX, string.format("Heads up: this export is %d characters, which is very large. Biggest sections:", #text))
        for i, section in ipairs(Serialize.SectionSizes(summary)) do
            if i > 5 then break end
            print(string.format("   %s: %d bytes of data", section[1], section[2]))
        end
    end
end

-- /journey testexport (dev only): fixed fake data, to check that the Lua
-- encoder and the Node decoder agree.
function ns.TestExport()
    if InCombatLockdown() then
        print(PREFIX, "Can't export in combat.")
        return
    end
    local text, problem = Serialize.Encode(Serialize.TestSummary())
    if not text then
        print(PREFIX, "Test export failed: " .. tostring(problem))
        return
    end
    Show(text, "Test Export (fake data)")
end
