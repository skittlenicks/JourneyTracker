-- JourneyTracker UI: a Classic-style window showing everything tracked.
--
-- Layout follows the Classic quest log / character frame:
--   * portrait frame with title, subtitle and a filled "Level x/60" bar
--   * left: dark list of collapsible categories (quest log style)
--   * right: parchment page with dark ink text, gold-free headings, and
--     blue skill-style bars
--   * red buttons along the bottom (Export, Print to Chat, Close), tabs
--     underneath (Journey / Levels)
--
-- The UI only reads JourneyTrackerDB, which holds plain (non-secret) values,
-- so nothing here touches restricted data. Templates and textures are tried
-- in order with fallbacks, since Forever's UI art may differ from retail's.

local ADDON_NAME, ns = ...

local frame        -- main window, built on first open
local listPane, pagePane, pageScroll, pageChild, listScroll, listChild
local tabs = {}

-- Classic parchment palette
local INK      = { 0.24, 0.16, 0.07 }  -- body text on parchment
local INK_DARK = { 0.08, 0.05, 0.02 }  -- titles and values
local BAR_BLUE = { 0.20, 0.35, 0.85 }  -- profession/skill bar blue
local LIST_HEADER = { 0.85, 0.85, 0.85 }
local LIST_ITEM   = { 1.00, 0.82, 0.00 }

-- Fonts. Body and table text use the game's own UI typeface (the one
-- GameFontNormal uses) without a drop shadow, so dark ink stays sharp on
-- parchment. Titles and headings keep the quest log's title font. Alignment
-- is set on the font objects as well as on each FontString so it can't drift.
local UI_FACE, _, UI_FLAGS = GameFontNormal:GetFont()

local function ParchmentFont(name, size)
    local font = CreateFont(name)
    font:SetFont(UI_FACE or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, UI_FLAGS or "")
    font:SetShadowOffset(0, 0)
    font:SetJustifyH("LEFT")
    font:SetJustifyV("TOP")
    return font
end

local TITLE_FONT = CreateFont("JourneyTrackerTitleFont")
TITLE_FONT:CopyFontObject(QuestTitleFont or GameFontNormalLarge)
TITLE_FONT:SetJustifyH("LEFT")
TITLE_FONT:SetJustifyV("TOP")
local BODY_FONT  = ParchmentFont("JourneyTrackerBodyFont", 13)
local TABLE_FONT = ParchmentFont("JourneyTrackerTableFont", 12)
local SMALL_FONT = ParchmentFont("JourneyTrackerSmallFont", 11)

local SLOT_NAMES = {
    "Head", "Neck", "Shoulder", "Shirt", "Chest", "Waist", "Legs", "Feet", "Wrist",
    "Hands", "Finger", "Finger", "Trinket", "Trinket", "Back", "Main Hand",
    "Off Hand", "Ranged", "Tabard",
}
local QUALITY_NAMES = { [0] = "Poor", "Common", "Uncommon", "Rare", "Epic", "Legendary" }

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------

local function Dur(s) return s and ns.FormatDuration(s) or "-" end
-- Money with the game's gold/silver/copper coin icons, as the default UI shows it.
local function Money(c)
    if not c then return "-" end
    if GetCoinTextureString then
        local ok, text = pcall(GetCoinTextureString, c)
        if ok and type(text) == "string" and text ~= "" then return text end
    end
    return ns.FormatMoney(c)
end
local function Date(t) return t and date("%b %d, %Y", t) or "-" end
local function DateTime(t) return t and date("%b %d %Y, %H:%M", t) or "-" end
-- Whole numbers, with the game's thousands separators (12,347).
local function Num(v)
    if not v then return "-" end
    local n = math.floor(v + 0.5)
    return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)
end
local function Yards(v) return v and (Num(v) .. " yd") or "-" end

local function Count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

-- Array of { key, value } sorted by score(value), highest first.
local function Sorted(t, score)
    local out = {}
    for k, v in pairs(t or {}) do out[#out + 1] = { k, v } end
    score = score or function(v) return v end
    table.sort(out, function(a, b) return score(a[2]) > score(b[2]) end)
    return out
end

local function QualityColor(q)
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c then return { c.r, c.g, c.b } end
    return BAR_BLUE
end

local function QuestTitle(questID)
    local title = ns.Str(ns.Call("C_QuestLog.GetTitleForQuestID", questID))
    return title or ("Quest #" .. tostring(questID))
end

-- "Level 5 Dwarf Shaman", using the game's display names for race and class.
local function CharLine()
    local race = ns.Str(ns.Call("UnitRace", "player"))
    local class = ns.Str(ns.Call("UnitClass", "player"))
    return string.format("Level %d %s %s", ns.Level(), race or "", class or "")
end

-- Shared with the class and wrapped trackers' pages.
ns.UI = { Dur = Dur, Money = Money, Date = Date, DateTime = DateTime, Num = Num, Yards = Yards,
          Sorted = Sorted, Count = Count }

-- The usual cap for a profession's skill (Apprentice 75, Journeyman 150,
-- Expert 225, Artisan 300), for when the game doesn't report the real one.
local function ProfessionCap(rank)
    for _, cap in ipairs({ 75, 150, 225, 300 }) do
        if rank <= cap then return cap end
    end
    return 300
end

-- Try templates in order; fall back to a plain frame.
local function TryCreate(ftype, name, parent, templates)
    for _, t in ipairs(templates) do
        local ok, f = pcall(CreateFrame, ftype, name, parent, t)
        if ok and f then return f, t end
    end
    return CreateFrame(ftype, name, parent), nil
end

---------------------------------------------------------------------------
-- Page builder: lays out text, rows and bars on the parchment, top to
-- bottom, reusing pooled widgets on every redraw.
--
-- The open page redraws every second. Each FontString gets its font and
-- alignment once, when it's created; after that only its text, color and
-- position change, and only when they differ. Re-applying font and
-- alignment on every redraw made numbers jump sideways in game.
-- Positions are whole pixels so text stays sharp.
---------------------------------------------------------------------------

-- What each kind of text looks like.
local KINDS = {
    title = { font = TITLE_FONT, wrap = true },  -- page titles and headings
    text  = { font = BODY_FONT,  wrap = true },  -- paragraphs and notes
    label = { font = BODY_FONT,  wrap = false }, -- left side of a row
    value = { font = BODY_FONT,  wrap = false }, -- value column of a row
    cell  = { font = TABLE_FONT, wrap = false }, -- table cells
    small = { font = SMALL_FONT, wrap = true },  -- footnotes
}

local B = { pools = {}, bars = { n = 0 }, hovers = { n = 0 } }

function B:Begin(child, width)
    self.child, self.width, self.y = child, width, -10
    for _, pool in pairs(self.pools) do pool.n = 0 end
    self.bars.n = 0
    self.hovers.n = 0
end

-- Next pooled FontString of a kind, created and configured on first use.
function B:Get(kind, color)
    local pool = self.pools[kind]
    if not pool then
        pool = { n = 0 }
        self.pools[kind] = pool
    end
    pool.n = pool.n + 1
    local fs = pool[pool.n]
    if not fs then
        fs = self.child:CreateFontString(nil, "ARTWORK")
        fs:SetFontObject(KINDS[kind].font)
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("TOP")
        fs:SetWordWrap(KINDS[kind].wrap)
        pool[pool.n] = fs
    end
    if fs.jtColor ~= color then
        fs:SetTextColor(color[1], color[2], color[3])
        fs.jtColor = color
    end
    if not fs:IsShown() then fs:Show() end
    return fs
end

-- Anchor and size a widget, skipping the calls when nothing moved.
local function Place(region, x, y, width)
    if region.jtX ~= x or region.jtY ~= y then
        region:ClearAllPoints()
        region:SetPoint("TOPLEFT", B.child, "TOPLEFT", x, y)
        region.jtX, region.jtY = x, y
    end
    if region.jtWidth ~= width then
        region:SetWidth(width)
        region.jtWidth = width
    end
end

-- Numbers show as whole numbers with separators, like the game's own.
local function SetText(fs, text)
    if type(text) == "number" then text = Num(text) end
    text = text == nil and "-" or tostring(text)
    if fs.jtText ~= text then
        fs:SetText(text)
        fs.jtText = text
    end
end

-- Height a FontString takes up, in whole pixels.
local function Height(fs, min)
    return math.max(math.ceil(fs:GetStringHeight()), min or 0)
end

function B:Gap(h) self.y = self.y - (h or 8) end

-- Big page title, like a quest name.
function B:Title(text)
    local fs = self:Get("title", INK_DARK)
    Place(fs, 10, self.y, self.width - 20)
    SetText(fs, text)
    self.y = self.y - Height(fs) - 8
end

-- Section heading, like "Description" / "Rewards".
function B:Heading(text)
    self:Gap(6)
    local fs = self:Get("title", INK_DARK)
    Place(fs, 10, self.y, self.width - 20)
    SetText(fs, text)
    self.y = self.y - Height(fs) - 4
end

-- Wrapped paragraph.
function B:Text(text)
    local fs = self:Get("text", INK)
    Place(fs, 14, self.y, self.width - 28)
    SetText(fs, text)
    self.y = self.y - Height(fs) - 4
end

-- Notes use the same ink as rows so they're just as easy to read.
function B:Note(text) self:Text(text) end

-- "Label        value" row. Values line up in a column.
function B:Row(label, value)
    local labelWidth = math.floor((self.width - 28) * 0.6)
    local left = self:Get("label", INK)
    Place(left, 14, self.y, labelWidth)
    SetText(left, label)
    local right = self:Get("value", INK_DARK)
    Place(right, 14 + labelWidth, self.y, self.width - 28 - labelWidth)
    SetText(right, value)
    self.y = self.y - Height(left, 14) - 3
    return left, right
end

-- Small print, e.g. a footnote at the bottom of a page.
function B:Footnote(text)
    self:Gap(8)
    local fs = self:Get("small", INK)
    Place(fs, 14, self.y, self.width - 28)
    SetText(fs, text)
    self.y = self.y - Height(fs) - 4
end

-- An invisible area over an item link: hovering it shows the item's tooltip.
function B:ItemHover(fs, link)
    local hovers = self.hovers
    hovers.n = hovers.n + 1
    local h = hovers[hovers.n]
    if not h then
        h = CreateFrame("Frame", nil, self.child)
        h:EnableMouse(true)
        h:SetScript("OnEnter", function(frame)
            if not frame.link then return end
            GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(frame.link)
            GameTooltip:Show()
        end)
        h:SetScript("OnLeave", function() GameTooltip:Hide() end)
        hovers[hovers.n] = h
    end
    h.link = link
    local w = math.max(math.ceil(math.min(fs:GetStringWidth(), fs:GetWidth())), 10)
    local ht = math.max(math.ceil(fs:GetStringHeight()), 12)
    if h.jtAnchor ~= fs or h.jtW ~= w or h.jtH ~= ht then
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", fs, "TOPLEFT")
        h:SetSize(w, ht)
        h.jtAnchor, h.jtW, h.jtH = fs, w, ht
    end
    if not h:IsShown() then h:Show() end
end

-- "Slot ........ [Item]" row whose item shows its tooltip on hover.
function B:ItemRow(label, link)
    local _, right = self:Row(label, link)
    self:ItemHover(right, link)
end

-- An item link on its own line, with its tooltip on hover.
function B:ItemLine(link)
    local fs = self:Get("text", INK)
    Place(fs, 14, self.y, self.width - 28)
    SetText(fs, link)
    self:ItemHover(fs, link)
    self.y = self.y - Height(fs) - 4
end

-- Columns for tables. cells and widths are parallel arrays.
function B:Cols(cells, widths, color)
    local x, h = 14, 14
    for i, text in ipairs(cells) do
        local fs = self:Get("cell", color or INK)
        Place(fs, x, self.y, widths[i] - 4)
        SetText(fs, text)
        h = math.max(h, Height(fs))
        x = x + widths[i]
    end
    self.y = self.y - h - 3
end

-- Classic profession-style bar: blue fill, white "Label   value" text.
function B:Bar(label, value, max, text, color)
    local bars = self.bars
    bars.n = bars.n + 1
    local bar = bars[bars.n]
    if not bar then
        bar = CreateFrame("StatusBar", nil, self.child)
        bar:SetHeight(16)
        bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        bar.bg = bar:CreateTexture(nil, "BACKGROUND")
        bar.bg:SetAllPoints()
        bar.bg:SetColorTexture(0, 0, 0, 0.55)
        bar.left = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        bar.left:SetPoint("LEFT", 6, 0)
        bar.right = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        bar.right:SetPoint("RIGHT", -6, 0)
        bars[bars.n] = bar
    end
    color = color or BAR_BLUE
    if bar.jtColor ~= color then
        bar:SetStatusBarColor(color[1], color[2], color[3])
        bar.jtColor = color
    end
    local top = (max and max > 0) and max or 1
    local v = math.min(value or 0, top)
    if bar.jtMax ~= top or bar.jtValue ~= v then
        bar:SetMinMaxValues(0, top)
        bar:SetValue(v)
        bar.jtMax, bar.jtValue = top, v
    end
    Place(bar, 14, self.y, self.width - 28)
    SetText(bar.left, label)
    SetText(bar.right, text or Num(value))
    if not bar:IsShown() then bar:Show() end
    self.y = self.y - 20
end

-- Bars for a { name = number } table, biggest first.
function B:BarList(t, fmt, color, limit)
    local list = Sorted(t)
    local max = list[1] and list[1][2] or 0
    if #list == 0 then self:Note("Nothing yet.") return end
    for i, kv in ipairs(list) do
        if limit and i > limit then break end
        self:Bar(tostring(kv[1]), kv[2], max, fmt and fmt(kv[2]) or Num(kv[2]), color)
    end
end

-- Hide whatever this draw didn't use and size the page to fit.
function B:End()
    for _, pool in pairs(self.pools) do
        for i = pool.n + 1, #pool do pool[i]:Hide() end
    end
    for i = self.bars.n + 1, #self.bars do self.bars[i]:Hide() end
    for i = self.hovers.n + 1, #self.hovers do self.hovers[i]:Hide() end
    local height = math.max(-self.y + 10, 1)
    if self.child.jtHeight ~= height then
        self.child:SetHeight(height)
        self.child.jtHeight = height
    end
end

---------------------------------------------------------------------------
-- Pages. Each takes (B, db) and draws one category.
---------------------------------------------------------------------------

local function SessionLength(s)
    return (s.last or s.start) - s.start
end

local function AllSessions(db)
    local list = {}
    for _, s in ipairs(db.sessions.list) do list[#list + 1] = s end
    if db.sessions.current then list[#list + 1] = db.sessions.current end
    return list
end

local function Played(db)
    return ns.PlayedNow() or db.played.total
end

-- Zones without "Unknown", the stand-in name the game gives for a moment
-- while it loads a zone.
local function Zones(db)
    local zones = {}
    for name, z in pairs(db.zones) do
        if name ~= "Unknown" then zones[name] = z end
    end
    return zones
end

-- The game's Statistics pane (JourneyTrackerStats.lua, W-506). Stat(id) is a
-- statistic as a number (gold in copper), or nil before the pane is read.
local function Stat(id) return ns.StatNumber and ns.StatNumber(id) or nil end
-- For a row both sides count, the bigger of ours and the game's: each
-- starts partway through a character's life, so the bigger is closer to the
-- real total.
local function Best(ours, theirs)
    if theirs and (not ours or theirs > ours) then return theirs end
    return ours
end
-- The rest of the pane's statistics that belong on a page; `skip` is a set
-- of the ones the page already shows in its own rows.
local function Block(B, page, skip)
    if ns.DrawStatistics then ns.DrawStatistics(B, page, skip) end
end
-- The game's XP-granting kills: its "kills that grant experience or honor"
-- less honorable kills.
local function StatXPKills()
    local all, honor = Stat(1198), Stat(588)
    if all then return all - (honor or 0) end
end
ns.UI.Stat, ns.UI.Best, ns.UI.Block = Stat, Best, Block

local function PageSummary(B, db)
    local c = db.char
    B:Title(c.name or "Your Journey")
    B:Text(CharLine() .. " of " .. (c.realm or "?"))
    B:Bar("Progress to " .. ns.MAX_LEVEL, ns.Level(), ns.MAX_LEVEL,
        ns.Level() .. " / " .. ns.MAX_LEVEL)
    B:Heading("Your Journey So Far")
    B:Row("Time played", Dur(Played(db)))
    B:Row("Journey began", Date(db.firstSeen))
    B:Row("Reached " .. ns.MAX_LEVEL, db.reachedMax and Date(db.reachedMax) or "Not yet")
    B:Row("Play sessions", #AllSessions(db))
    B:Row("Experience earned", Num(db.xp.total))
    B:Row("Monsters slain", Best(db.kills.total, StatXPKills()))
    B:Row("Deaths", Best(#db.deaths, Stat(60)))
    B:Row("Quests completed", Best(db.quests.completed, Stat(98)))
    B:Row("Zones visited", Count(Zones(db)))
    B:Row("Distance on foot and mounted", Yards(db.travel.ground))
    B:Row("Distance fallen", Yards(db.falls.total))
    B:Row("Gold earned", Money(Best(db.money.earned, Stat(328))))
    B:Row("Items looted", db.loot.items)
    local G = db.gathering
    B:Row("Nodes gathered", G.herb.nodes + G.mining.nodes + G.skinning.nodes)
    Block(B, "summary") -- anything in the pane with no page of its own
    if Stat(98) then
        B:Footnote("Where the game's own Statistics pane has a bigger number than Journey Tracker, that's the one shown: it counts play from before you installed Journey Tracker.")
    end
end

local function PagePlayed(B, db)
    B:Title("Played & Sessions")
    B:Row("Total /played", Dur(Played(db)))                                 -- #1
    local cur = db.played.levelStart and (Played(db) - db.played.levelStart)
    B:Row("/played this level", Dur(cur))
    B:Row("First login", DateTime(db.firstSeen))                            -- #4
    if db.reachedMax then
        B:Row("Calendar time to " .. ns.MAX_LEVEL, Dur(db.reachedMax - db.firstSeen))
    else
        B:Row("Calendar time so far", Dur(time() - db.firstSeen))
    end
    B:Row("Distinct days played", Count(db.days))                           -- #17

    local sessions = AllSessions(db)
    local total, longest, mostLevels = 0, 0, 0
    for _, s in ipairs(sessions) do
        local len = SessionLength(s)
        total = total + len
        longest = math.max(longest, len)
        mostLevels = math.max(mostLevels, s.levels or 0)
    end
    B:Heading("Sessions")
    B:Row("Sessions", #sessions)                                            -- #6
    B:Row("Average length", Dur(#sessions > 0 and total / #sessions or 0))  -- #7
    B:Row("Longest session", Dur(longest))                                  -- #8
    B:Row("Most levels in one session", mostLevels)                         -- #9
    if db.sessions.current then
        B:Row("This session", Dur(SessionLength(db.sessions.current)))
    end
    B:Heading("Every Session")
    local widths = { 170, 110, 80, 60 }
    B:Cols({ "Started", "Length", "From level", "Levels" }, widths, INK_DARK)
    for i = #sessions, 1, -1 do
        local s = sessions[i]
        B:Cols({ DateTime(s.start), Dur(SessionLength(s)), s.startLevel or "-", s.levels or 0 }, widths)
    end
end

local function PageTime(B, db)
    local T = db.time
    B:Title("Time Spent")
    local total = T.grouped + T.solo
    B:Note("Share of time tracked while logged in (" .. Dur(total) .. ").")
    local rows = {
        { "Resting in inns and cities", T.resting },    -- #11
        { "Mounted", T.mounted },                       -- #14
        { "In combat", T.combat },                      -- #37
        { "On flight paths", T.taxi },                  -- #13
        { "Away (AFK)", T.afk },                        -- #10
        { "Dead", T.dead },                             -- #12
        { "Corpse runs", T.corpseRuns },                -- #50
        { "Grouped", T.grouped },                       -- #97
        { "Solo", T.solo },
    }
    for _, r in ipairs(rows) do
        B:Bar(r[1], r[2], total, Dur(r[2]))
    end
end

local function PageHabits(B, db)
    B:Title("Play Habits")
    B:Heading("Playtime by Hour of Day")                                     -- #18
    local max = 0
    for h = 0, 23 do max = math.max(max, db.hours[h] or 0) end
    for h = 0, 23 do
        B:Bar(string.format("%02d:00", h), db.hours[h] or 0, max, Dur(db.hours[h] or 0))
    end
    B:Heading("Days Played")                                                 -- #17
    local days = {}
    for d in pairs(db.days) do days[#days + 1] = d end
    table.sort(days)
    -- "2026-10-01" as "Oct 01", with the year too once the days span more
    -- than one.
    local years = #days > 0 and days[1]:sub(1, 4) ~= days[#days]:sub(1, 4)
    for i, d in ipairs(days) do
        local y, m, dd = d:match("^(%d+)-(%d+)-(%d+)$")
        if y then
            local t = time({ year = tonumber(y), month = tonumber(m), day = tonumber(dd), hour = 12 })
            days[i] = date(years and "%b %d %Y" or "%b %d", t)
        end
    end
    B:Text(#days > 0 and table.concat(days, ", ") or "None yet.")
end

local function PageTimeline(B, db)
    B:Title("Level Timeline")
    -- #15 XP per hour, #16 fastest and slowest level, from per-level /played.
    local fastest, slowest, xpSum, timeSum
    xpSum, timeSum = 0, 0
    for level, s in pairs(db.levels) do
        if s.played and s.played > 0 then
            if not fastest or s.played < fastest[2] then fastest = { level, s.played } end
            if not slowest or s.played > slowest[2] then slowest = { level, s.played } end
            xpSum, timeSum = xpSum + (s.xp or 0), timeSum + s.played
        end
    end
    B:Row("Fastest level", fastest and ("Level " .. fastest[1] .. " in " .. Dur(fastest[2])) or "-")
    B:Row("Slowest level", slowest and ("Level " .. slowest[1] .. " in " .. Dur(slowest[2])) or "-")
    B:Row("XP per hour (tracked levels)", timeSum > 0 and Num(xpSum / timeSum * 3600) or "-")

    local levels = {}
    for level in pairs(db.dings) do levels[#levels + 1] = level end
    table.sort(levels, function(a, b) return a > b end)
    if #levels == 0 then
        B:Heading("No Dings Yet")
        B:Note("Each level-up is recorded here with where, when and why it happened.")
        return
    end
    for _, level in ipairs(levels) do
        local d = db.dings[level]
        B:Heading("Level " .. level)                                         -- #5, #19-21
        B:Row("Reached", DateTime(d.t))
        B:Row("Where", (d.subzone and (d.subzone .. ", ") or "") .. (d.zone or "?"))
        if d.x and d.y then B:Row("Coordinates", string.format("%.1f, %.1f", d.x, d.y)) end
        B:Row("Final XP from", d.cause or "-")
        B:Row("/played", Dur(d.played))                                      -- #2
        local prev = db.levels[level - 1]
        if prev and prev.played then B:Row("Time on level " .. (level - 1), Dur(prev.played)) end -- #3
        B:Row("Gold on hand", Money(d.gold))                                 -- #76
        B:Row("Grouped at the time", d.grouped and "Yes" or "No")
        B:Note(string.format("Journey totals by then: %s XP, %d kills, %d quests, %d deaths",
            Num(d.xpTotal), d.kills or 0, d.quests or 0, d.deaths or 0))
    end
end

local function PageXP(B, db)
    local X = db.xp
    B:Title("Experience")
    B:Row("Total XP earned", Num(X.total))                                   -- #24
    B:Row("Rested XP used", Num(X.restedUsed))                               -- #22
    B:Row("XP from quests (rewards)", Num(db.quests.xp))                     -- #56
    B:Heading("Where It Came From")                                          -- #23, #65
    B:Bar("Kills", X.kill, X.total, Num(X.kill))
    B:Bar("Quests", X.quest, X.total, Num(X.quest))
    B:Bar("Exploration", X.explore, X.total, Num(X.explore))
    B:Bar("Other", X.other, X.total, Num(X.other))
    B:Heading("Solo or Grouped")                                             -- #25
    B:Bar("Solo", X.solo, X.total, Num(X.solo))
    B:Bar("Grouped", X.grouped, X.total, Num(X.grouped))
end

local function PageFights(B, db)
    local C = db.combat
    B:Title("Fights")
    B:Row("Combats entered", C.fights)                                       -- #34
    B:Row("Time in combat", Dur(db.time.combat))                             -- #37
    B:Row("Average fight", Dur(C.fights > 0 and db.time.combat / C.fights or 0)) -- #36
    B:Row("Longest fight", Dur(C.longest))                                   -- #35
    B:Row("Fights ending in death", C.died)                                  -- #38
    B:Row("Multi-mob pulls", C.multiPulls)                                   -- #40
    B:Row("Most mobs at once", C.maxMobs)
    B:Row("Mobs that jumped you", C.ambushMobs)                              -- #39
    B:Note("Multi-mob pulls and ambushes are read from enemy nameplates, so keep them turned on.")
    Block(B, "fights")
end

local function PageKills(B, db)
    local K = db.kills
    B:Title("Kills")
    B:Row("XP-granting kills", Best(K.total, StatXPKills()))                 -- #26
    local top = Sorted(K.byName)[1]
    B:Row("Most killed", top and (top[1] .. " x" .. top[2]) or "-")          -- #29
    local m = K.maxLevelDiff
    B:Row("Toughest kill", m and string.format("%s (level %d at %d, %+d)",
        m.name, m.mobLevel, m.level, m.diff) or "-")                         -- #33
    B:Heading("By Classification")                                           -- #30-31
    B:BarList(K.byClass)
    B:Heading("By Creature Type")                                            -- #32
    B:BarList(K.byType)
    B:Heading("By Monster")                                                  -- #28
    B:BarList(K.byName)
    Block(B, "kills")
end

local function PageBosses(B, db)
    B:Title("Bosses & PvP")
    B:Heading("Dungeon Bosses")                                              -- #41-42
    local list = Sorted(db.bosses, function(b) return b.attempts end)
    if #list == 0 then B:Note("No boss encounters yet.") end
    for _, kv in ipairs(list) do
        local b = kv[2]
        B:Row(kv[1], string.format("%d kills, %d wipes, %d pulls", b.kills, b.wipes, b.attempts))
    end
    Block(B, "bosses")
    B:Heading("Player vs. Player")                                           -- #43
    B:Row("Honorable kills", Best(db.pvp.honorableKills or 0, Stat(588)))
    Block(B, "pvp", { [588] = true })
end

local function PageDeaths(B, db)
    B:Title("Deaths")
    local byZone, solo, grouped, dungeon = {}, 0, 0, 0
    for _, d in ipairs(db.deaths) do
        byZone[d.zone or "?"] = (byZone[d.zone or "?"] or 0) + 1
        if d.dungeon then dungeon = dungeon + 1
        elseif d.grouped then grouped = grouped + 1
        else solo = solo + 1 end
    end
    local worst = Sorted(byZone)[1]
    -- #52 longest streak of levels without dying, over the levels tracked.
    local streak, best, first = 0, 0, nil
    for level in pairs(db.levels) do first = math.min(first or level, level) end
    for level = first or 1, ns.Level() do
        local s = db.levels[level]
        if s and s.deaths > 0 then streak = 0 else streak = streak + 1 end
        best = math.max(best, streak)
    end
    B:Row("Total deaths", Best(#db.deaths, Stat(60)))                        -- #44
    B:Row("Deadliest zone", worst and (worst[1] .. " (" .. worst[2] .. ")") or "-") -- #51
    B:Row("Solo / grouped / in dungeons", solo .. " / " .. grouped .. " / " .. dungeon) -- #48
    B:Row("Fights that ended in death", db.combat.died)                      -- #38
    B:Row("Longest death-free streak", best .. " levels")                    -- #52
    Block(B, "deaths", { [60] = true, [114] = true }) -- deaths from falling are on the Falls page
    B:Heading("Deaths by Level")                                             -- #45
    local any = false
    for level = 1, ns.MAX_LEVEL do
        local s = db.levels[level]
        if s and s.deaths > 0 then
            B:Row("Level " .. level, s.deaths)
            any = true
        end
    end
    if not any then B:Note("Not a single death. Well done.") end
    B:Heading("Death Log")                                                   -- #46-47, #49
    for i = #db.deaths, 1, -1 do
        local d = db.deaths[i]
        B:Text(string.format("|cff1a0d00Level %d, %s%s|r", d.level or 0,
            d.subzone and (d.subzone .. ", ") or "", d.zone or "?"))
        local where = (d.x and d.y) and string.format(" at %.1f, %.1f", d.x, d.y) or ""
        local company = d.dungeon and ("in " .. d.dungeon) or (d.grouped and "grouped" or "solo")
        B:Note(string.format("Killed by %s on %s%s (%s). %s%s%s%s", d.killer or "Unknown",
            DateTime(d.t), where, company,
            d.rez and ("Came back by " .. d.rez) or "",
            d.deadFor and (" after " .. Dur(d.deadFor) .. ".") or "",
            d.graveyard and (" Graveyard: " .. d.graveyard .. ".") or "",
            d.corpseRun and (" Corpse run: " .. Dur(d.corpseRun) .. ".") or ""))
    end
end

-- How a death ended, as saved (JourneyTracker.lua's FinishDeath), in words.
local REZ_NAMES = { ["corpse run"] = "Corpse run", ["spirit healer"] = "Spirit healer",
    ["player rez"] = "Rezzed by a player", ["self-res/other"] = "Soulstone, Ankh or other", unknown = "Unknown" }

local function PageRez(B, db)
    B:Title("Resurrections")
    B:Heading("How You Came Back")                                           -- #49
    local ways = {}
    for how, n in pairs(db.rez) do ways[REZ_NAMES[how] or how] = n end
    B:BarList(ways)
    B:Heading("Time")
    B:Row("Total time dead", Dur(db.time.dead))                              -- #12
    B:Row("Time on corpse runs", Dur(db.time.corpseRuns))                    -- #50
    local runs = db.rez["corpse run"] or 0
    B:Row("Average corpse run", Dur(runs > 0 and db.time.corpseRuns / runs or 0))
    B:Heading("Graveyards Used")                                             -- #72
    B:BarList(db.graveyards)
    Block(B, "rez")
end

local function PageQuests(B, db)
    local Q = db.quests
    B:Title("Quests")
    B:Row("Completed", Best(Q.completed, Stat(98)))                          -- #53
    B:Row("Accepted", Q.accepted)                                            -- #58
    B:Row("Abandoned", Best(Q.abandoned, Stat(94)))                          -- #59
    B:Row("XP from quests", Num(Q.xp))                                       -- #56
    B:Row("Gold from quests", Money(Best(Q.money, Stat(326))))               -- #57
    B:Row("In your log (tracked)", Count(Q.open))
    if Q.longest then                                                        -- #60
        B:Row("Longest held", QuestTitle(Q.longest.questID))
        B:Note("Accepted to turn-in: " .. Dur(Q.longest.seconds))
    end
    Block(B, "quests", { [98] = true, [94] = true })
    B:Heading("By Type")                                                     -- #61-62
    B:BarList(Q.byTag)
    B:Heading("By Zone")                                                     -- #55
    B:BarList(Q.byZone)
    B:Heading("By Level")                                                    -- #54
    local any = false
    for level = 1, ns.MAX_LEVEL do
        local s = db.levels[level]
        if s and s.quests > 0 then
            B:Row("Level " .. level, s.quests)
            any = true
        end
    end
    if not any then B:Note("Nothing yet.") end
end

local function PageZones(B, db)
    B:Title("Zones")
    local zones = Zones(db)
    B:Row("Zones visited", Count(zones))                                     -- #63
    local list = Sorted(zones, function(z) return z.seconds end)
    local max = list[1] and list[1][2].seconds or 0
    B:Heading("Time Spent in Each Zone")                                     -- #66
    for _, kv in ipairs(list) do
        B:Bar(kv[1], kv[2].seconds, max, Dur(kv[2].seconds))
        B:Note(string.format("First visited %s at level %d", Date(kv[2].first), kv[2].firstLevel or 0))
    end
end

local function PagePath(B, db)
    B:Title("Path & Discovery")
    B:Row("Places discovered", db.discovered)                                -- #64
    B:Row("Subzones visited", Count(db.subzones))
    B:Row("XP from exploration", Num(db.xp.explore))                         -- #65
    B:Heading("Your Path Through the World")                                 -- #67
    local widths = { 150, 50, 220 }
    B:Cols({ "When", "Level", "Zone" }, widths, INK_DARK)
    for i = #db.path, 1, -1 do
        local p = db.path[i]
        if p.zone ~= "Unknown" then B:Cols({ DateTime(p.t), p.level, p.zone }, widths) end
    end
    B:Heading("Subzones")
    local subs = Sorted(db.subzones, function(t) return -t end) -- oldest first
    for _, kv in ipairs(subs) do
        B:Cols({ Date(kv[2]), kv[1] }, { 110, 340 })
    end
end

local function PageTravel(B, db)
    local T = db.travel
    B:Title("Travel")
    B:Row("Distance on foot and mounted", Yards(T.ground))                   -- #71
    B:Row("Distance by flight", Yards(T.taxi))
    B:Row("Time on flight paths", Dur(db.time.taxi))                         -- #13
    B:Row("Time mounted", Dur(db.time.mounted))                              -- #14
    B:Row("Hearthstone uses", Best(T.hearths, Stat(353)))                    -- #68
    B:Row("Flights taken", Best(T.flights, Stat(349)))                       -- #70
    Block(B, "travel", { [353] = true, [349] = true })
    B:Heading("Flight Paths Discovered")                                     -- #69
    if #T.flightPaths == 0 then B:Note("None yet.") end
    for _, fp in ipairs(T.flightPaths) do
        B:Row((fp.subzone and (fp.subzone .. ", ") or "") .. (fp.zone or "?"),
            string.format("Level %s, %s", fp.level or "?", Date(fp.t)))
    end
end

local function FallPlace(f)
    return string.format("Level %d in %s%s, %s", f.level or 0,
        f.subzone and (f.subzone .. ", ") or "", f.zone or "?", DateTime(f.t))
end

local function PageFalls(B, db)
    local F = db.falls
    B:Title("Falls")
    B:Row("Times jumped", db.social.jumps)                                   -- #100
    B:Row("Total distance fallen", Yards(F.total))                           -- #101
    B:Row("Falls", F.count)
    B:Row("Longest fall survived", F.longestSurvived and Yards(F.longestSurvived.yards) or "-") -- #102
    if F.longestSurvived then B:Note(FallPlace(F.longestSurvived)) end
    B:Row("Deaths from falling", Best(F.fatal, Stat(114)))
    if F.longestFatal then
        B:Row("Longest fatal fall", Yards(F.longestFatal.yards))
        B:Note(FallPlace(F.longestFatal))
    end
    B:Note("Height can't be read in game, so each fall is timed and the drop is worked out from WoW's fall speed. Expect it to be close, not exact.")
end

local function PageDungeons(B, db)
    local D = db.dungeons
    B:Title("Dungeons")
    B:Heading("Times Entered")                                               -- #73
    B:BarList(D.entered)
    Block(B, "dungeons")
    if D.current then
        B:Heading("Current Run")
        B:Row(D.current.name, Dur(time() - D.current.start))
    end
    B:Heading("Runs")                                                        -- #74-75
    local widths = { 130, 96, 34, 66, 48, 48 }
    B:Cols({ "Dungeon", "Date", "Lvl", "Time", "Bosses", "Deaths" }, widths, INK_DARK)
    for i = #D.runs, 1, -1 do
        local r = D.runs[i]
        B:Cols({ r.name, Date(r.start), r.level or "-", Dur(r.duration), r.bosses, r.deaths }, widths)
    end
    if #D.runs == 0 then B:Note("No finished runs yet.") end
end

local function PageGold(B, db)
    local M = db.money
    B:Title("Gold")
    B:Row("On hand", Money(ns.Num(ns.Call("GetMoney"))))
    B:Row("Most ever held", Money(Best(M.peak, Stat(334))))                  -- #85
    B:Row("Total earned", Money(Best(M.earned, Stat(328))))                  -- #77
    B:Row("Total spent", Money(M.spent))
    B:Heading("Earned From")
    B:Row("Quest rewards", Money(Best(db.quests.money, Stat(326))))          -- #57
    B:Row("Looting", Money(Best(M.loot, Stat(333))))                         -- #78
    B:Row("Selling to vendors", Money(Best(M.vendor, Stat(921))))            -- #79
    B:Row("Auction house sales", Money(Best(M.auctionIncome, Stat(919))))    -- #83
    B:Row("Other mail", Money(math.max(M.mail - M.auctionIncome, 0)))
    B:Row("Auctions sold", M.auctionsSold)
    B:Heading("Spent On")
    B:Row("Class training", Money(M.training))                               -- #80
    B:Row("Repairs", Money(M.repairs))                                       -- #81
    B:Row("Flights", Money(Best(M.flights, Stat(1146))))                     -- #82
    B:Row("Auction house", Money(M.auctionSpent))                            -- #83
    B:Row("Vendor purchases", Money(M.vendorSpent))
    Block(B, "gold", { [334] = true, [328] = true, [326] = true, [333] = true, [921] = true,
                       [919] = true, [1146] = true })
    B:Heading("First Mount")                                                 -- #84
    if db.firstMount then
        B:Row("Level", db.firstMount.level)
        B:Row("/played", Dur(db.firstMount.played))
        B:Row("Date", Date(db.firstMount.t))
    else
        B:Note("Not yet.")
    end
    B:Heading("Gold at Each Level")                                          -- #76
    local any = false
    for level = 1, ns.MAX_LEVEL do
        local d = db.dings[level]
        if d and d.gold then
            B:Row("Level " .. level, Money(d.gold))
            any = true
        end
    end
    if not any then B:Note("Saved at each level-up from now on.") end
end

local function PageLoot(B, db)
    local L = db.loot
    B:Title("Loot")
    B:Row("Items looted", L.items)                                           -- #86
    B:Heading("By Quality")                                                  -- #87
    local max = 0
    for q = 0, 5 do max = math.max(max, L.byQuality[q] or 0) end
    for q = 0, 5 do
        if L.byQuality[q] then
            B:Bar(QUALITY_NAMES[q] or ("Quality " .. q), L.byQuality[q], max, nil, QualityColor(q))
        end
    end
    if max == 0 then B:Note("Nothing yet.") end
    B:Heading("Best Item Looted")                                            -- #88
    if L.best then
        B:ItemLine(L.best.link)
        B:Note(string.format("Level %d in %s, %s%s", L.best.level or 0, L.best.zone or "?",
            Date(L.best.t), L.best.ilvl and (", item level " .. L.best.ilvl) or ""))
    else
        B:Note("Nothing yet.")
    end
    B:Heading("Milestones")                                                  -- #90
    B:Row("First blue", L.firstBlue and ("Level " .. L.firstBlue.level) or "Not yet")
    if L.firstBlue then B:ItemLine(L.firstBlue.link) end
    B:Row("First epic", L.firstEpic and ("Level " .. L.firstEpic.level) or "Not yet")
    if L.firstEpic then B:ItemLine(L.firstEpic.link) end
    Block(B, "loot")
end

-- #104 the gear worn the longest: the most levels gained while equipped,
-- and the most /played while equipped (wrapped W-396).
local function WornLongest(B, db)
    B:Heading("Worn the Longest")
    local byLevels, byPlayed
    for _, w in pairs(db.worn or {}) do
        if w.link then
            if (w.levels or 0) >= 0.1 and (not byLevels or w.levels > byLevels.levels) then byLevels = w end
            if (w.played or 0) >= 1 and (not byPlayed or w.played > byPlayed.played) then byPlayed = w end
        end
    end
    -- "at level 20" or "levels 12 to 24"
    local function Range(w)
        local from, to = w.first or 0, w.last or w.first or 0
        if from == to then return "at level " .. from end
        return "levels " .. from .. " to " .. to
    end
    if byLevels then
        B:ItemRow("Most levels", byLevels.link)
        B:Note(string.format("%s, worn for %.1f levels (%s).", SLOT_NAMES[byLevels.slot] or "?",
            byLevels.levels, Range(byLevels)))
    else
        B:Row("Most levels", "-")
        B:Note("Counts the levels you gain while wearing each item.")
    end
    if byPlayed then
        B:ItemRow("Most /played", byPlayed.link)
        B:Note(string.format("%s, worn for %s of /played (%s).", SLOT_NAMES[byPlayed.slot] or "?",
            Dur(byPlayed.played), Range(byPlayed)))
    else
        B:Row("Most /played", "-")
        B:Note("Counts your /played while wearing each item.")
    end
end

local function PageGear(B, db)
    B:Title("Gear Snapshots")                                                -- #89
    WornLongest(B, db)                                                       -- #104
    local levels = {}
    for level in pairs(db.gear) do levels[#levels + 1] = level end
    table.sort(levels)
    if #levels == 0 then
        B:Note("Your equipped gear is saved at levels 10, 20, 30, 40, 50 and 60.")
        return
    end
    for _, level in ipairs(levels) do
        B:Heading("Level " .. level)
        local g = db.gear[level]
        if g.late then B:Note("Saved after you reached this level, not at the ding.") end
        local any = false
        for slot = 1, 19 do
            if g[slot] then
                B:ItemRow(SLOT_NAMES[slot], g[slot]) -- hover for the item's tooltip
                any = true
            end
        end
        if not any then
            B:Note("Your gear hadn't loaded when this was taken; it's taken again a few seconds after you log in.")
        end
    end
end

local function PageSkills(B, db)
    B:Title("Skills")
    B:Row("Total skill-ups", db.skillUps)                                    -- #96
    local list = Sorted(db.skills, function(s) return s.rank or 0 end)
    if #list == 0 then B:Note("Skill-ups appear here as they happen.") end
    for _, kv in ipairs(list) do                                             -- #92
        local name, s = kv[1], kv[2]
        -- Weapon and defense skills cap at 5x your level; professions at 300.
        local max = ns.PROFESSIONS[name] and 300 or ns.Level() * 5
        B:Bar(name, s.rank or 0, max, (s.rank or 0) .. " / " .. max)
        B:Note(string.format("First skill-up at level %d, %d gains so far", s.firstLevel or 0, #s.history))
        -- Progression: the highest rank reached at each character level.
        local byLevel = {}
        for _, h in ipairs(s.history) do
            if not byLevel[h.level] or h.rank > byLevel[h.level] then byLevel[h.level] = h.rank end
        end
        local steps = {}
        for level = 1, ns.MAX_LEVEL do
            if byLevel[level] then steps[#steps + 1] = "level " .. level .. ": " .. byLevel[level] end
        end
        if #steps > 0 then B:Note("Rank by " .. table.concat(steps, ", ")) end
    end
    Block(B, "skills")
end

-- The game's "highest skill" statistic for each profession.
local SKILL_STATS = { Alchemy = 1527, Blacksmithing = 1532, Enchanting = 1535, Engineering = 1544,
    Herbalism = 1538, Inscription = 1539, Leatherworking = 1536, Mining = 1537, Skinning = 1541,
    Tailoring = 1542, Cooking = 1524, ["First Aid"] = 281, Fishing = 1519 }

local function PageProfs(B, db)
    B:Title("Professions & Spells")
    B:Heading("Professions")                                                 -- #91
    local profs = Sorted(db.professions, function(p) return p.rank or 0 end)
    if #profs == 0 then B:Note("None yet.") end
    local shown = { [1518] = true } -- fish caught is on the Gathering page
    for _, kv in ipairs(profs) do
        local name, p = kv[1], kv[2]
        local skill = db.skills[name]
        local statID = SKILL_STATS[name]
        local rank = Best(p.rank or (skill and skill.rank) or 0, statID and Stat(statID))
        local max = math.max(p.maxRank or ProfessionCap(rank), rank)
        B:Bar(name, rank, max, rank .. " / " .. max)
        if statID then shown[statID] = true end
    end
    B:Row("Items crafted", db.crafted)                                       -- #93
    Block(B, "professions", shown)
    B:Heading("Spells and Abilities Learned")                                -- #95
    local spells = Sorted(db.spells, function(s) return -(s.level or 0) end)
    if #spells == 0 then B:Note("New spells appear here as you learn them.") end
    for _, kv in ipairs(spells) do B:Row(kv[1], "Level " .. (kv[2].level or "?")) end
end

local function PageGathering(B, db)
    local G = db.gathering
    B:Title("Gathering")                                                     -- #103
    B:Row("Herbs picked", G.herb.nodes)
    B:Row("Ore nodes mined", G.mining.nodes)
    B:Row("Corpses skinned", G.skinning.nodes)
    B:Heading("Herbalism")
    B:BarList(G.herb.items)
    B:Heading("Mining")
    B:Row("Swings (a vein can take several)", G.mining.swings)
    B:BarList(G.mining.items)
    B:Heading("Skinning")
    B:BarList(G.skinning.items)
    B:Heading("Fishing")
    B:Row("Fish caught", Best(db.fish, Stat(1518)))                          -- #94
end

local function PageSocial(B, db)
    local S = db.social
    B:Title("Social")
    B:Bar("Grouped", db.time.grouped, db.time.grouped + db.time.solo, Dur(db.time.grouped)) -- #97
    B:Bar("Solo", db.time.solo, db.time.grouped + db.time.solo, Dur(db.time.solo))
    B:Row("Different players grouped with", S.unique)                        -- #98
    if S.guildJoinLevel then                                                 -- #99
        B:Row("Joined a guild", "Level " .. S.guildJoinLevel
            .. (S.guildJoinTime and (", " .. Date(S.guildJoinTime)) or ""))
    elseif S.guildBeforeTracking then
        B:Row("Joined a guild", "Before tracking began")
    else
        B:Row("Joined a guild", "Not yet")
    end
    if ns.DrawCamping then ns.DrawCamping(B) end                             -- W-008..012
    Block(B, "social")
end

local SECTIONS = {
    { name = "Overview", pages = { { "Summary", PageSummary } } },
    { name = "Time & Pace", pages = {
        { "Played & Sessions", PagePlayed }, { "Time Spent", PageTime }, { "Play Habits", PageHabits } } },
    { name = "Leveling", pages = { { "Level Timeline", PageTimeline }, { "Experience", PageXP } } },
    { name = "Combat & Kills", pages = {
        { "Fights", PageFights }, { "Kills", PageKills }, { "Bosses & PvP", PageBosses } } },
    { name = "Deaths", pages = { { "Death Log", PageDeaths }, { "Resurrections", PageRez } } },
    { name = "Quests", pages = { { "Quests", PageQuests } } },
    { name = "Exploration & Travel", pages = {
        { "Zones", PageZones }, { "Path & Discovery", PagePath }, { "Travel", PageTravel },
        { "Falls", PageFalls } } },
    { name = "Dungeons", pages = { { "Dungeon Runs", PageDungeons } } },
    { name = "Economy", pages = { { "Gold", PageGold } } },
    { name = "Loot & Gear", pages = { { "Loot", PageLoot }, { "Gear Snapshots", PageGear } } },
    { name = "Skills & Professions", pages = {
        { "Skills", PageSkills }, { "Professions & Spells", PageProfs },
        { "Gathering", PageGathering } } },
    { name = "Social", pages = { { "Social", PageSocial } } },
}

-- Levels tab: one row per level, like a ledger.
local LEVEL_COLS = { 34, 110, 92, 60, 50, 56, 56, 150, 80 }
local function PageLevels(B, db)
    B:Title("Level by Level")
    B:Cols({ "Lvl", "Reached", "Time on level", "XP", "Kills", "Quests", "Deaths", "Ding zone", "Ding from" },
        LEVEL_COLS, INK_DARK)
    local first
    for level in pairs(db.levels) do first = math.min(first or level, level) end
    for level in pairs(db.dings) do first = math.min(first or level, level) end
    for level = first or 1, ns.Level() do
        local s, d = db.levels[level] or {}, db.dings[level] or {}
        B:Cols({ level, d.t and Date(d.t) or "-", s.played and Dur(s.played) or "-",
            Num(s.xp), s.kills or "-", s.quests or "-", s.deaths or "-",
            d.zone or "-", d.cause or "-" }, LEVEL_COLS)
    end
    B:Note("Time on level comes from /played at each ding, so it starts with the first level you finish while tracking.")
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

local currentTab = 1

local function UIState()
    local db = ns.GetDB()
    db.ui = db.ui or { collapsed = {}, page = "Summary" }
    db.ui.collapsed = db.ui.collapsed or {}
    return db.ui
end

local function FindPage(name)
    for _, sec in ipairs(SECTIONS) do
        for _, p in ipairs(sec.pages) do
            if p[1] == name then return p[2] end
        end
    end
    return PageSummary
end

local function RenderPage()
    if not frame or not frame:IsShown() then return end
    local db = ns.GetDB()
    local width = math.floor(pageScroll:GetWidth() or 0)
    if width < 50 then width = 440 end
    if pageChild.jtWidth ~= width then
        pageChild:SetWidth(width)
        pageChild.jtWidth = width
    end
    B:Begin(pageChild, width)
    if currentTab == 2 then
        PageLevels(B, db)
    else
        FindPage(UIState().page)(B, db)
    end
    B:End()
end

-- Left list: section headers with +/- and yellow page entries.
local listButtons = {}
local function RenderList()
    local ui = UIState()
    local rows = {}
    for _, sec in ipairs(SECTIONS) do
        rows[#rows + 1] = { header = true, name = sec.name }
        if not ui.collapsed[sec.name] then
            for _, p in ipairs(sec.pages) do rows[#rows + 1] = { name = p[1] } end
        end
    end
    for i, row in ipairs(rows) do
        local b = listButtons[i]
        if not b then
            b = CreateFrame("Button", nil, listChild)
            b:SetHeight(16)
            b.icon = b:CreateTexture(nil, "ARTWORK")
            b.icon:SetSize(14, 14)
            b.icon:SetPoint("LEFT", 2, 0)
            b.text = b:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            b.text:SetJustifyH("LEFT")
            b.selected = b:CreateTexture(nil, "BACKGROUND")
            b.selected:SetAllPoints()
            b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            b:SetScript("OnClick", function(self)
                local state = UIState()
                if self.isHeader then
                    state.collapsed[self.name] = not state.collapsed[self.name] or nil
                else
                    state.page = self.name
                end
                RenderList()
                RenderPage()
            end)
            listButtons[i] = b
        end
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", listChild, "TOPLEFT", 0, -(i - 1) * 17 - 4)
        b:SetPoint("RIGHT", listChild, "RIGHT", 0, 0)
        b.isHeader, b.name = row.header, row.name
        b.text:ClearAllPoints()
        if row.header then
            b.icon:Show()
            b.icon:SetTexture(ui.collapsed[row.name] and "Interface\\Buttons\\UI-PlusButton-Up"
                or "Interface\\Buttons\\UI-MinusButton-Up")
            b.text:SetPoint("LEFT", b.icon, "RIGHT", 4, 0)
            b.text:SetTextColor(LIST_HEADER[1], LIST_HEADER[2], LIST_HEADER[3])
            b.selected:Hide()
        else
            b.icon:Hide()
            b.text:SetPoint("LEFT", 22, 0)
            b.text:SetTextColor(LIST_ITEM[1], LIST_ITEM[2], LIST_ITEM[3])
            -- Selected entry: the quest log's golden bar.
            b.selected:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
            b.selected:SetBlendMode("ADD")
            b.selected:SetShown(row.name == ui.page)
        end
        b.text:SetPoint("RIGHT", -4, 0)
        b.text:SetText(row.name)
        b:Show()
    end
    for i = #rows + 1, #listButtons do listButtons[i]:Hide() end
    listChild:SetHeight(#rows * 17 + 8)
end

-- Subtitle and the top-right level bar. Runs every second while the window
-- is open, but only changes anything when the level does.
local function UpdateProgress(force)
    local level = ns.Level()
    local counter = frame.counter
    if counter.level == level and not force then return end
    counter.level = level
    counter.bar:SetValue(math.min(level, ns.MAX_LEVEL))
    counter.text:SetText(string.format("Level: %d/%d", level, ns.MAX_LEVEL))
    frame.subtitle:SetText(CharLine())
end

local function UpdateHeader()
    local db = ns.GetDB()
    local c = db.char
    local title = (c.name or "Your") .. "'s Journey"
    if frame.SetTitle then
        frame:SetTitle(title)
    elseif frame.TitleText then
        frame.TitleText:SetText(title)
    elseif frame.fallbackTitle then
        frame.fallbackTitle:SetText(title)
    end
    UpdateProgress(true)
    -- Portrait: the template's own method if it has one, else the texture.
    if frame.SetPortraitToUnit then
        pcall(frame.SetPortraitToUnit, frame, "player")
    else
        local tex = frame.portrait or (frame.PortraitContainer and frame.PortraitContainer.portrait)
            or frame.fallbackPortrait
        if tex then SetPortraitTexture(tex, "player") end
    end
end

-- Dark or parchment panel with a thin classic border.
local function Panel(parent, parchment)
    local p = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    p:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    p:SetBackdropBorderColor(0.55, 0.5, 0.45)
    if parchment then
        p:SetBackdropColor(0.86, 0.76, 0.56, 1)
        -- Parchment grain on top of the tan base, if this client has the art.
        local tex = p:CreateTexture(nil, "BORDER")
        tex:SetPoint("TOPLEFT", 4, -4)
        tex:SetPoint("BOTTOMRIGHT", -4, 4)
        tex:SetTexture("Interface\\AchievementFrame\\UI-Achievement-Parchment-Horizontal")
        tex:SetVertexColor(1, 0.95, 0.85, 0.9)
    else
        p:SetBackdropColor(0.04, 0.04, 0.04, 0.92)
    end
    return p
end

local function ScrollArea(parent)
    local sf, template = TryCreate("ScrollFrame", nil, parent, { "UIPanelScrollFrameTemplate" })
    sf:SetPoint("TOPLEFT", 6, -6)
    sf:SetPoint("BOTTOMRIGHT", template and -28 or -6, 6)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(10, 10)
    sf:SetScrollChild(child)
    if not template then
        sf:EnableMouseWheel(true)
        sf:SetScript("OnMouseWheel", function(self, delta)
            local range = self:GetVerticalScrollRange()
            local v = math.max(0, math.min(range, self:GetVerticalScroll() - delta * 40))
            self:SetVerticalScroll(v)
        end)
    end
    return sf, child
end

local function SelectTab(index)
    currentTab = index
    for i, tab in ipairs(tabs) do
        if i == index then
            if PanelTemplates_SelectTab then pcall(PanelTemplates_SelectTab, tab) end
        else
            if PanelTemplates_DeselectTab then pcall(PanelTemplates_DeselectTab, tab) end
        end
    end
    pagePane:ClearAllPoints()
    pagePane:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 34)
    if index == 2 then
        listPane:Hide()
        pagePane:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -64)
    else
        listPane:Show()
        pagePane:SetPoint("TOPLEFT", listPane, "TOPRIGHT", 4, 0)
    end
    pageScroll:SetVerticalScroll(0)
    RenderPage()
end

local function CreateWindow()
    -- Your class, the cross-class pages and WoW Forever go after the Overview.
    local extra = {}
    for _, source in ipairs({ ns.ClassSections or false, ns.WrappedSections or false }) do
        if source then
            for _, section in ipairs(source()) do table.insert(extra, section) end
        end
    end
    for i, section in ipairs(extra) do table.insert(SECTIONS, 1 + i, section) end

    local f, template = TryCreate("Frame", "JourneyTrackerFrame", UIParent,
        { "ButtonFrameTemplate", "PortraitFrameTemplate", "BackdropTemplate" })
    frame = f
    f:SetSize(780, 540)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    table.insert(UISpecialFrames, "JourneyTrackerFrame") -- Escape closes it

    if template == "ButtonFrameTemplate" or template == "PortraitFrameTemplate" then
        if f.Inset then f.Inset:Hide() end -- we draw our own panes
    else
        -- Fallback dressing: dialog border, round portrait, title, close.
        if f.SetBackdrop then
            f:SetBackdrop({
                bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 32,
                insets = { left = 11, right = 12, top = 12, bottom = 11 },
            })
        end
        f.fallbackPortrait = f:CreateTexture(nil, "ARTWORK")
        f.fallbackPortrait:SetSize(58, 58)
        f.fallbackPortrait:SetPoint("TOPLEFT", -6, 8)
        f.fallbackTitle = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        f.fallbackTitle:SetPoint("TOP", 0, -14)
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -4, -4)
    end

    -- Subtitle under the title bar, like "Level 60 Human Paladin".
    f.subtitle = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    f.subtitle:SetPoint("TOP", f, "TOP", 0, -34)

    -- "Level: 20/60" box in the quest log's counter spot, filled toward 60
    -- like the Progress to 60 bar.
    local counter = CreateFrame("Frame", nil, f, "BackdropTemplate")
    counter:SetSize(130, 22)
    counter:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -32)
    counter:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    counter:SetBackdropColor(0, 0, 0, 0.8)
    counter:SetBackdropBorderColor(0.6, 0.55, 0.45)
    counter.bar = CreateFrame("StatusBar", nil, counter)
    counter.bar:SetPoint("TOPLEFT", 4, -4)
    counter.bar:SetPoint("BOTTOMRIGHT", -4, 4)
    counter.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    counter.bar:SetStatusBarColor(BAR_BLUE[1], BAR_BLUE[2], BAR_BLUE[3])
    counter.bar:SetMinMaxValues(0, ns.MAX_LEVEL)
    counter.text = counter.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    counter.text:SetPoint("CENTER")
    f.counter = counter

    -- Left list and right parchment page.
    listPane = Panel(f, false)
    listPane:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -64)
    listPane:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 34)
    listPane:SetWidth(230)
    listScroll, listChild = ScrollArea(listPane)
    listChild:SetWidth(190)

    pagePane = Panel(f, true)
    pageScroll, pageChild = ScrollArea(pagePane)

    -- Red classic buttons along the bottom: Export and Print to Chat on the
    -- left, Close on the right.
    local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    close:SetSize(110, 22)
    close:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 8)
    close:SetText(CLOSE or "Close")
    close:SetScript("OnClick", function() f:Hide() end)

    local export = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    export:SetSize(110, 22)
    export:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 8)
    export:SetText("Export")
    export:SetScript("OnClick", function() if ns.Export then ns.Export() end end)
    export:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Export")
        GameTooltip:AddLine("Copy your journey to paste at " .. (ns.WEBSITE or "the website")
            .. ", for your recap and a link to share.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    export:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local printButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    printButton:SetSize(120, 22)
    printButton:SetPoint("LEFT", export, "RIGHT", 6, 0)
    printButton:SetText("Print to Chat")
    printButton:SetScript("OnClick", function() ns.PrintSummary() end)

    -- Tabs under the frame, like Character / Reputation / Skills / Honor.
    local names = { "Journey", "Levels" }
    for i, name in ipairs(names) do
        local tab, tabTemplate = TryCreate("Button", "JourneyTrackerFrameTab" .. i, f,
            { "PanelTabButtonTemplate", "CharacterFrameTabButtonTemplate", "UIPanelButtonTemplate" })
        tab:SetID(i)
        tab:SetText(name)
        if tabTemplate == "UIPanelButtonTemplate" then tab:SetSize(90, 22) end
        if PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, tab, 0) end
        if i == 1 then
            tab:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 12, 2)
        else
            -- Old Classic tab art is drawn to overlap its neighbour; the
            -- modern tab template and plain buttons need a gap instead.
            local gap = tabTemplate == "CharacterFrameTabButtonTemplate" and -15 or 4
            tab:SetPoint("LEFT", tabs[i - 1], "RIGHT", gap, 0)
        end
        tab:SetScript("OnClick", function() SelectTab(i) end)
        tabs[i] = tab
    end
    f.numTabs = #tabs

    -- Keep the open page live (once a second) while the window is shown.
    local elapsed = 0
    f:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed >= 1 then
            elapsed = 0
            if ns.RefreshStatistics then ns.RefreshStatistics() end -- every 20s or so while open
            RenderPage()
            UpdateProgress()
        end
    end)
    f:SetScript("OnShow", function()
        if ns.RefreshStatistics then ns.RefreshStatistics() end -- the game's statistics, fresh
        UpdateHeader()
        RenderList()
        RenderPage()
    end)

    f:Hide()
end

function ns.ToggleUI()
    if not ns.GetDB() then return end
    if not frame then
        CreateWindow()
        frame:Show()
        SelectTab(1)
        return
    end
    frame:SetShown(not frame:IsShown())
end

---------------------------------------------------------------------------
-- Minimap button: "JT" in the style of the World of Warcraft logo. Click to
-- open the window; drag to move it around the minimap (the spot is saved).
---------------------------------------------------------------------------

local LOGO_GOLD = { 1.00, 0.84, 0.24 } -- tooltip title, matching the icon's gold

local function PlaceMinimapButton(button, angle)
    local radius = Minimap:GetWidth() / 2 + 10
    local rad = math.rad(angle)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * radius, math.sin(rad) * radius)
end

local function CreateMinimapButton()
    if not Minimap then return end
    local ui = UIState()
    ui.minimapAngle = ui.minimapAngle or 200

    local b = CreateFrame("Button", "JourneyTrackerMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    -- The standard round minimap button: dark disc and gold tracking ring.
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    -- "JT" drawn in the style of the World of Warcraft logo (JT.tga, made
    -- for this addon), centered exactly on the dark disc.
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\AddOns\\JourneyTracker\\JT")
    icon:SetSize(22, 22)
    icon:SetPoint("CENTER", bg, "CENTER", 0, 0)

    b:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" and ns.Export then
            ns.Export()
        else
            ns.ToggleUI()
        end
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Journey Tracker", LOGO_GOLD[1], LOGO_GOLD[2], LOGO_GOLD[3])
        GameTooltip:AddLine("Click to open your journey.", 1, 1, 1)
        GameTooltip:AddLine("Right-click to export it for the website.", 1, 1, 1)
        GameTooltip:AddLine("Drag to move this button.", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self:SetScript("OnUpdate", function(button)
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            ui.minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
            PlaceMinimapButton(button, ui.minimapAngle)
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    PlaceMinimapButton(b, ui.minimapAngle)
end

ns.OnLoad(function() CreateMinimapButton() end)
