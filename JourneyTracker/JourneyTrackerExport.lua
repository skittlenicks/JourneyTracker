-- JourneyTracker export: /journey export (or the Export button in the
-- window, or right-clicking the minimap button) builds a summary of this
-- character's data, encodes it (JourneyTrackerSerialize.lua) and shows the
-- "JT1:..." string in a window to copy and paste at www.journeytracker.dev.
-- /journey testexport does the same with fixed fake data, to check the
-- encoder against tools/import.
--
-- Milestones (#105-107): at every 10 levels, the export as it stood when
-- you got there is saved, so "your road to 30" can still be shared after
-- 30. The export window offers each saved one beside the export of now, and
-- /journey export 30 opens straight to it. A small reminder pops up as each
-- is saved, with a button to export it there and then (off in the window's
-- Options, db.ui.exportReminder = false).
--
-- Every export says how long after reaching its milestone it was made, in
-- /played (sinceMilestone): the website ranks a journey exported at 60 long
-- after reaching it only on what was settled by then.
--
-- The summary is the saved stats, not a raw event log, and leaves out
-- anything that could identify a person: the character's name and realm,
-- other players' names (never stored), chat text (never stored) and the
-- hashed IDs used to count group members.

local ADDON_NAME, ns = ...
local Serialize = ns.Serialize
local PREFIX = "|cff33ff99Journey|r"
local WARN_LENGTH = 100000 -- characters; bigger exports get a heads-up
local MILESTONE_EVERY = 10 -- #105 levels between milestones
local MILESTONE_WAIT = 20  -- seconds a milestone waits for its ding's /played and statistics
-- /played after reaching a milestone past which an export made at that
-- level is "late" on the website (site/model.js's LATE_AFTER).
local LATE_AFTER = 2 * 3600
local TYPED_WORDS = 10 -- W-292 words in an export

---------------------------------------------------------------------------
-- Summary
---------------------------------------------------------------------------

-- #110 how long after reaching its milestone (10, 20 ... 60, the last one at
-- or below `level`) a journey is being exported: /played seconds since the
-- level-up's own /played, and real seconds since. Nil without a milestone
-- or the level-up's /played.
local function SinceMilestone(db, level, played)
    local m = level - level % MILESTONE_EVERY
    if m < MILESTONE_EVERY or not played then return nil end
    local ding, saved = db.dings[m], db.milestones and db.milestones[m]
    local reached = (ding and ding.played) or (saved and saved.played)
    if not reached then return nil end
    local t = (ding and ding.t) or (saved and saved.t)
    return { level = m, played = math.max(0, math.floor(played - reached)), seconds = t and math.max(0, time() - t) or nil }
end

-- The website turns away an export with a negative number anywhere in it
-- (only a "diff", a level difference, may be one), and no stat is
-- negative: drop any that slipped in rather than lose the whole export. In
-- a list it becomes 0, so the list stays a list.
local function DropNegatives(t)
    local n = #t
    for k, v in pairs(t) do
        if k == "diff" then
            -- left as it is
        elseif type(v) == "number" and v < 0 then
            if type(k) == "number" and k >= 1 and k <= n then t[k] = 0 else t[k] = nil end
        elseif type(v) == "table" then
            DropNegatives(v)
        end
    end
end

local function CountOf(map)
    local n = 0
    for _ in pairs(map or {}) do n = n + 1 end
    return n
end

-- The summary of everything so far. `milestone` (a level) marks one saved
-- as you reached that level (#105).
local function BuildSummary(db, milestone)
    local Copy, cap = Serialize.Copy, Serialize.MAP_CAP

    local stats = Copy(db)
    -- These get their own places in the summary, or (the saved milestone
    -- exports) none.
    for _, key in ipairs({ "characterId", "schemaVersion", "dings", "levels", "class", "wrapped", "statistics",
                           "milestones" }) do
        stats[key] = nil
    end
    -- Never exported: the character's name and realm (exports are anonymous),
    -- window settings, dev probe dumps, internal bookkeeping, and the hashed
    -- IDs used to count players you grouped with (only the count goes out).
    for _, key in ipairs({ "char", "ui", "dev", "legacy", "legacySchema" }) do stats[key] = nil end
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
    if stats.kills then
        stats.kills.uniqueNames = CountOf(stats.kills.byName)   -- #28 how many different mobs, before the cap
        stats.kills.byName = Serialize.Capped(stats.kills.byName, cap)
    end

    local class = Copy(db.class or {})
    if class.ALL then
        local all = class.ALL
        all.trainerNPCs, all.classQuestIDs, all.deathsSeen = nil, nil, nil
        if all.buffs then all.buffs.bySpell = Serialize.Capped(all.buffs.bySpell, cap) end
        all.food = Serialize.Capped(all.food, cap)
    end

    local wrapped = Copy(db.wrapped or {})
    -- Settings and bookkeeping the wrapped trackers keep for themselves.
    for _, key in ipairs({ "flags", "wasNeutral", "autoFlagged", "uiFolded", "logout", "rewardIDs", "bagsSeen",
                         "lootedRecipes", "professionsKnown", "questsTurnedIn", "goldSeen", "goldFromStart",
                         "bracketsSeen", "bindName", "bindPlace" }) do
        wrapped[key] = nil
    end
    -- W-292 your most typed words: the website shows the top one, so only
    -- the top few go out.
    wrapped["W-292"] = Serialize.Capped(wrapped["W-292"], TYPED_WORDS)

    -- W-505 the Statistics pane: the names lookup, the baseline, the latest
    -- snapshot and what changed at each level (JourneyTrackerStats.lua).
    -- Left out until something has been read.
    local S = db.statistics
    local statistics = S and S.latest and {
        names = Copy(S.names), categories = Copy(S.categories), order = Copy(S.order),
        baseline = S.baseline and Copy(S.baseline), latest = Copy(S.latest),
        levels = Copy(S.levels), skipped = Copy(S.skipped),
    } or nil

    local _, classToken = ns.Call("UnitClass", "player")
    local _, raceToken = ns.Call("UnitRace", "player")
    local played = ns.PlayedNow() or (db.played and db.played.total) or 0
    local summary = {
        format = 1,
        characterId = db.characterId,
        addonVersion = ns.VERSION,
        schemaVersion = db.schemaVersion,
        exportedAt = time(),
        milestone = milestone,
        sinceMilestone = SinceMilestone(db, ns.Level(), played > 0 and played or nil),
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
        statistics = statistics,
    }
    DropNegatives(summary)
    return summary
end

---------------------------------------------------------------------------
-- Export window: a classic dialog with the steps to follow, the export
-- (already selected, ready for Ctrl+C) and the website's address. WoW can't
-- open links, so the address is in a box of its own to copy.
---------------------------------------------------------------------------

ns.WEBSITE = "www.journeytracker.dev"
local GOLD = "|cffffd100"   -- the game's own highlight gold
local GREEN = "|cff20ff20"

local window, exportText
local CHOICES = 7 -- now and up to six milestones (10-60)

-- Read-only: anything typed puts the text back, selected.
local function ReadOnly(box, text)
    box:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            self:SetText(text())
            self:HighlightText()
        end
    end)
end

-- Ctrl+C (Cmd+C on a Mac) in `box` calls copied(). The key is read as it's
-- released, so the box has already copied the text.
local function OnCopy(box, copied)
    box:SetScript("OnKeyUp", function(_, key)
        if key == "C" and (IsControlKeyDown() or (IsMetaKeyDown and IsMetaKeyDown())) then copied() end
    end)
end

local function CreateWindow()
    local f = CreateFrame("Frame", "JourneyTrackerExportFrame", UIParent, "BackdropTemplate")
    f:SetSize(560, 462)
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
    f.title:SetPoint("TOP", 0, -20)

    local closeX = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeX:SetPoint("TOPRIGHT", -6, -6)

    -- The three steps: white text with what to press or type in gold, like
    -- the game's own help.
    local steps = {
        "Press " .. GOLD .. "Ctrl+C|r to copy your journey. It's already selected below.",
        "Go to " .. GOLD .. ns.WEBSITE .. "|r and paste it into the box at the top.",
        "Click " .. GOLD .. "Show my journey|r to see your recap and get a link to share.",
    }
    local above
    for i, text in ipairs(steps) do
        local line = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        line:SetJustifyH("LEFT")
        if above then
            line:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -6)
        else
            line:SetPoint("TOPLEFT", f, "TOPLEFT", 28, -52)
        end
        line:SetWidth(504)
        line:SetText(GOLD .. i .. ".|r  " .. text)
        above = line
    end

    -- #106 which journey: now, or as it was at a saved milestone. Shown
    -- under the steps; the one showing stays lit.
    f.choices = {}
    for i = 1, CHOICES do
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(64, 22)
        b:SetPoint("TOPLEFT", 26 + (i - 1) * 68, -118)
        b:Hide()
        f.choices[i] = b
    end
    f.choiceHint = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    f.choiceHint:SetPoint("LEFT", f.choices[1], "RIGHT", 10, 0)
    f.choiceHint:SetText("Every 10 levels, your journey so far is saved here too.")

    -- The export, in a dark inset like a chat box.
    local inset = CreateFrame("Frame", nil, f, "BackdropTemplate")
    inset:SetPoint("TOPLEFT", 22, -148)
    inset:SetPoint("BOTTOMRIGHT", -22, 112)
    inset:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    inset:SetBackdropColor(0, 0, 0, 0.6)
    inset:SetBackdropBorderColor(0.6, 0.55, 0.45)

    local scroll = CreateFrame("ScrollFrame", "JourneyTrackerExportScroll", inset, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -28, 8)

    local box = CreateFrame("EditBox", nil, scroll)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetFontObject(ChatFontNormal)
    box:SetWidth(470)
    box:SetScript("OnEscapePressed", function() f:Hide() end)
    ReadOnly(box, function() return exportText or "" end)
    OnCopy(box, function()
        f.status:SetText(GREEN .. "Copied.|r Now paste it at " .. GOLD .. ns.WEBSITE .. "|r")
    end)
    if ScrollingEdit_OnCursorChanged then box:SetScript("OnCursorChanged", ScrollingEdit_OnCursorChanged) end
    if ScrollingEdit_OnUpdate then
        box:SetScript("OnUpdate", function(self, elapsed) ScrollingEdit_OnUpdate(self, elapsed, scroll) end)
    end
    scroll:SetScrollChild(box)
    f.box = box

    -- Under the inset: how long the export is, or that it's been copied.
    f.status = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    f.status:SetPoint("TOP", inset, "BOTTOM", 0, -8)
    f.status:SetWidth(500)

    -- The website's address, to copy into a browser.
    local label = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("BOTTOMLEFT", 28, 64)
    label:SetText("Website")
    local site = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    site:SetSize(190, 20)
    site:SetPoint("LEFT", label, "RIGHT", 14, 0)
    site:SetAutoFocus(false)
    site:SetFontObject(ChatFontNormal)
    site:SetText(ns.WEBSITE)
    site:SetCursorPosition(0)
    ReadOnly(site, function() return ns.WEBSITE end)
    site:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    site:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    OnCopy(site, function() f.status:SetText(GREEN .. "Copied the address.|r Paste it into your browser.") end)
    local siteHint = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    siteHint:SetPoint("LEFT", site, "RIGHT", 10, 0)
    siteHint:SetText("Click it, then Ctrl+C to copy.")

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
    return f
end

-- One export in the window: its text (selected), title and length.
local function Put(text, title, note)
    exportText = text
    window.title:SetText(title)
    local count = BreakUpLargeNumbers and BreakUpLargeNumbers(#text) or tostring(#text)
    window.status:SetText(count .. " characters" .. (note and ("  ·  " .. note) or ""))
    window.box:SetText(text)
    window.box:SetFocus()
    window.box:HighlightText()
end

local function Show(text, title)
    window = window or CreateWindow()
    for _, b in ipairs(window.choices) do b:Hide() end
    window.choiceHint:Hide()
    Put(text, title)
    window:Show()
end

-- #106 the window with a choice of journey: now (`now` is its export, and
-- `nowNote` a line to go with it) or one saved at a milestone, newest
-- first. Opens at milestone `pick`, if it's saved.
local function ShowChoices(db, now, pick, nowNote)
    window = window or CreateWindow()
    local list, levels = { { label = "Now (" .. ns.Level() .. ")" } }, {}
    for level in pairs(db.milestones) do levels[#levels + 1] = level end
    table.sort(levels, function(a, b) return a > b end)
    for _, level in ipairs(levels) do
        if #list < CHOICES then list[#list + 1] = { label = "At " .. level, level = level } end
    end
    local function Pick(choice)
        for i, b in ipairs(window.choices) do
            if list[i] == choice then b:LockHighlight() else b:UnlockHighlight() end
        end
        local saved = choice.level and db.milestones[choice.level]
        if saved then
            Put(saved.text, "Your Road to " .. choice.level,
                "saved " .. date("%b %d", saved.t) .. (saved.late and ", a while after the level-up" or ""))
        else
            Put(now, "Export Your Journey", nowNote)
        end
    end
    local first = list[1]
    for i, b in ipairs(window.choices) do
        local choice = list[i]
        if choice then
            b:SetText(choice.label)
            b:SetScript("OnClick", function() Pick(choice) end)
            b:Show()
            if pick and choice.level == pick then first = choice end
        else
            b:Hide()
        end
    end
    if #list == 1 then window.choiceHint:Show() else window.choiceHint:Hide() end
    Pick(first)
    window:Show()
end

---------------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------------

-- /journey export, or /journey export 30 to open at the journey saved at 30.
function ns.Export(pick)
    if InCombatLockdown() then
        print(PREFIX, "Can't export in combat.")
        return
    end
    local db = ns.GetDB()
    if not db then return end
    if ns.StatsSnapshot then ns.StatsSnapshot("export") end   -- W-504
    local summary = BuildSummary(db)
    local text, problem = Serialize.Encode(summary)
    if not text then
        print(PREFIX, "Export failed: " .. tostring(problem))
        return
    end
    if pick and not db.milestones[pick] then
        print(PREFIX, "No journey is saved at level " .. pick .. ". Every 10 levels, your journey so far is saved as you reach it.")
        pick = nil
    end
    -- #110 exported at a milestone's level long after reaching it: the
    -- website ranks the journey saved at the level-up against fresh ones.
    local since, note = summary.sinceMilestone, nil
    if since and since.level == ns.Level() and since.played > LATE_AFTER then
        note = string.format("%s of play since you reached %d. For every ranking, share \"At %d\".",
            ns.FormatDuration(since.played), since.level, since.level)
        if not db.milestones[since.level] then note = nil end
    end
    ShowChoices(db, text, pick, note)
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

---------------------------------------------------------------------------
-- #109 the milestone reminder: a small window as each milestone is saved, with a
-- button to export it there and then, while it's fresh. On unless it's
-- turned off in the window's Options (db.ui.exportReminder = false).
---------------------------------------------------------------------------

function ns.ExportReminderOn()
    local db = ns.GetDB()
    return not (db and db.ui and db.ui.exportReminder == false)
end

function ns.SetExportReminder(on)
    local db = ns.GetDB()
    if not db then return end
    db.ui = db.ui or {}
    if on then db.ui.exportReminder = nil else db.ui.exportReminder = false end
end

local reminder

local function CreateReminder()
    local f = CreateFrame("Frame", "JourneyTrackerReminderFrame", UIParent, "BackdropTemplate")
    f:SetSize(360, 160)
    f:SetPoint("TOP", 0, -170)
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
    table.insert(UISpecialFrames, "JourneyTrackerReminderFrame") -- Escape closes it

    f.title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    f.title:SetPoint("TOP", 0, -20)
    f.text = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    f.text:SetPoint("TOP", f.title, "BOTTOM", 0, -8)
    f.text:SetWidth(312)
    f.text:SetJustifyH("CENTER")

    local closeX = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeX:SetPoint("TOPRIGHT", -6, -6)

    f.export = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.export:SetSize(120, 22)
    f.export:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -4, 38)
    f.export:SetText("Export now")
    local later = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    later:SetSize(120, 22)
    later:SetPoint("BOTTOMLEFT", f, "BOTTOM", 4, 38)
    later:SetText("Later")
    later:SetScript("OnClick", function() f:Hide() end)

    -- A line under the buttons that opens the window's Options page.
    local options = CreateFrame("Button", nil, f)
    options:SetSize(280, 14)
    options:SetPoint("BOTTOM", 0, 18)
    local hint = options:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetAllPoints()
    hint:SetText("You can turn this reminder off in Options.")
    local r, g, b = hint:GetTextColor()
    options:SetScript("OnEnter", function() hint:SetTextColor(1, 0.82, 0) end)
    options:SetScript("OnLeave", function() hint:SetTextColor(r, g, b) end)
    options:SetScript("OnClick", function()
        f:Hide()
        if ns.ShowOptions then ns.ShowOptions() end
    end)
    return f
end

-- The reminder for milestone `level`. With none, the newest one saved (or
-- the next to come): what the Options page shows as an example.
function ns.ShowMilestoneReminder(level)
    local db = ns.GetDB()
    if not db then return end
    if not level then
        for saved in pairs(db.milestones) do level = math.max(level or 0, saved) end
        level = level or math.min(ns.MAX_LEVEL, ns.Level() - ns.Level() % MILESTONE_EVERY + MILESTONE_EVERY)
    end
    -- Before a milestone is saved, the example says what's to come, and its
    -- button opens the export of now.
    local saved = db.milestones[level] ~= nil
    reminder = reminder or CreateReminder()
    reminder.title:SetText(string.format("Level %d!", level))
    reminder.text:SetText(string.format(saved and "Your road to %d is saved. Export it now for your recap at %s%s|r, "
        .. "ranked against other level %d journeys while it's fresh." or "When you reach %d, your road there is "
        .. "saved and this offers to export it for your recap at %s%s|r, ranked against other level %d journeys "
        .. "while it's fresh.", level, GOLD, ns.WEBSITE, level))
    reminder:SetHeight(math.ceil(tonumber(reminder.text:GetStringHeight()) or 42) + 122)
    reminder.export:SetScript("OnClick", function()
        if InCombatLockdown() then
            print(PREFIX, "Can't export in combat.")
            return
        end
        reminder:Hide()
        ns.Export(saved and level or nil)
    end)
    reminder:Show()
end

---------------------------------------------------------------------------
-- Milestones (#105, #107): db.milestones[level] = { text = the export,
-- t = when it was saved, played = /played then, late = saved after the
-- level-up itself }
---------------------------------------------------------------------------

local function IsMilestone(level)
    return level ~= nil and level >= MILESTONE_EVERY and level <= ns.MAX_LEVEL and level % MILESTONE_EVERY == 0
end

-- #105 save the export of now as the journey at milestone `level`.
local function SaveMilestone(level, late)
    local db = ns.GetDB()
    if not db or db.milestones[level] then return end
    local summary, ding = BuildSummary(db, level), db.dings[level]
    -- Its /played is the one at the level-up (it's saved a few seconds
    -- after), so it was made no time after reaching the milestone.
    if not late and ding and ding.played then
        summary.character.played = math.floor(ding.played)
        summary.sinceMilestone = { level = level, played = 0, seconds = 0 } -- #110
    end
    local text = Serialize.Encode(summary)
    if not text then return end
    db.milestones[level] = { text = text, t = summary.exportedAt, played = summary.character.played, late = late or nil }
    -- #107 a note in chat
    print(PREFIX, string.format("Level %d! Your road to %d is saved. Type %s/journey export|r to share it.",
        level, level, GOLD))
    if ns.ExportReminderOn() then ns.ShowMilestoneReminder(level) end -- #109
end

-- A level-up's milestone waits for the ding's /played and its Statistics
-- pane read (at most MILESTONE_WAIT seconds), then for combat to end.
local pending -- { level, since, late }
local function TrySave()
    local p, db = pending, ns.GetDB()
    if not p or not db then return end
    local ding, S = db.dings[p.level], db.statistics
    local ready = ding and ding.played and (not (S and S.latest) or (S.levels and S.levels[p.level]))
    if ns.InCombat() or (not ready and GetTime() - p.since < MILESTONE_WAIT) then
        if C_Timer and C_Timer.After then C_Timer.After(2, TrySave) end
        return
    end
    pending = nil
    SaveMilestone(p.level, p.late)
end
local function SaveSoon(level, late, delay)
    pending = { level = level, since = GetTime(), late = late }
    if C_Timer and C_Timer.After then C_Timer.After(delay, TrySave) else TrySave() end
end

ns.OnLoad(function(db)
    db.milestones = type(db.milestones) == "table" and db.milestones or {}
end)

ns.Listen("PLAYER_LEVEL_UP", function(level)
    level = ns.Num(ns.Safe(level)) or ns.Level()
    if IsMilestone(level) then SaveSoon(level, false, 3) end
end)

-- At login: a milestone reached in a session that ended before it was
-- saved (or before milestones were), while you're still at that level.
ns.Listen("PLAYER_ENTERING_WORLD", function(isInitialLogin, isReload)
    local db, level = ns.GetDB(), ns.Level()
    if (isInitialLogin or isReload) and db and not pending and IsMilestone(level)
        and db.dings[level] and not db.milestones[level] then
        SaveSoon(level, true, 15)
    end
end)
