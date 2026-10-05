-- JourneyTracker statistics: WoW Forever's Statistics pane on the character
-- page (combat, PvP, creatures, gold, consumables, factions, items,
-- professions, dungeons/raids, emotes). IDs W-501..W-508 match the
-- "Blizzard Statistics pane" section of wrapped-tracking-spec.md.
--
-- /journey statprobe (dev only, W-501) checks the achievement-statistics API
-- and saves every statistic to JourneyTrackerDB.dev.statProbe. The snapshot
-- module below (W-502..W-507) reads the whole pane on its own: a baseline
-- the first time, then at every ding and export, so players who installed
-- mid-leveling still get lifetime totals. Every call is nil-checked and
-- pcall'd, secret values are never kept, and nothing is read in combat.

local ADDON_NAME, ns = ...
local IsSecret = ns.IsSecret
local PREFIX = "|cff33ff99Journey|r"

-- What the Statistics pane needs, as named in the retail API.
local API = { "GetStatisticsCategoryList", "GetCategoryInfo", "GetCategoryNumAchievements",
              "GetAchievementInfo", "GetStatistic" }
local ACCOUNT_FLAG = 0x20000 -- ACHIEVEMENT_FLAGS_ACCOUNT in Blizzard's achievement UI
local MAX_ERRORS = 50        -- errors kept in the dump; the rest are only counted

-- Our own counts, compared with Blizzard's statistic of the same name as a
-- hint for whether the statistics are per character. First name found wins.
-- `key` is the count's name in a snapshot's `ours` (W-507); `minus` is a
-- statistic to take off Blizzard's number for the like-for-like check (on
-- Forever "kills that grant experience or honor" includes honorable kills).
local COMPARE = {
    { label = "deaths", key = "deaths", names = { "Total deaths" },
      ours = function(db) return #db.deaths end },
    { label = "quests completed", key = "quests", names = { "Quests completed" },
      ours = function(db) return db.quests.completed end },
    { label = "XP kills", key = "kills", names = { "Total kills that grant experience or honor", "Total kills" },
      minus = { "Total Honorable Kills" },
      ours = function(db) return db.kills.total end },
    { label = "flights", key = "flights", names = { "Flight paths taken" },
      ours = function(db) return db.travel.flights end },
    { label = "hearthstone uses", key = "hearths", names = { "Number of times hearthed" },
      ours = function(db) return db.travel.hearths end },
}

-- A value that's safe to keep: a string, number or boolean that isn't secret.
local function Plain(v)
    if IsSecret(v) then return nil end
    local t = type(v)
    if t == "string" or t == "number" or t == "boolean" then return v end
end

-- The Lua type of any value, secret or not.
local function TypeOf(v)
    local ok, t = pcall(type, v)
    if ok and not IsSecret(t) then return t end
    return "unknown"
end

-- Call a global function by name. Returns a list of its returns (n = how
-- many, so nils in the middle survive) in which each secret return is
-- replaced by nil and its type noted in .secret[i]. On failure returns nil,
-- an error message, and whether the function is simply missing. (ns.Call
-- hides errors; the probe reports them.)
local function Try(name, ...)
    local fn = _G[name]
    if type(fn) ~= "function" then return nil, name .. " is missing", true end
    local out = { secret = {} }
    local function Keep(ok, ...)
        out.ok, out.n = ok, select("#", ...)
        for i = 1, out.n do
            local v = (select(i, ...))
            if IsSecret(v) then out.secret[i] = TypeOf(v) else out[i] = v end
        end
    end
    Keep(pcall(fn, ...))
    if not out.ok then return nil, name .. ": " .. tostring(out[1]) end
    return out
end

-- Globals whose names mention statistics, in case Forever's pane uses an
-- API of its own: functions and tables in _G, and functions in C_ namespaces.
local function StatisticGlobals()
    local found = {}
    local function Match(name)
        return type(name) == "string" and name:find("[Ss][Tt][Aa][Tt][Ii][Ss][Tt][Ii][Cc]") ~= nil
    end
    for k, v in pairs(_G) do
        local t = TypeOf(v)
        if (t == "function" or t == "table") and Match(k) then
            found[#found + 1] = k .. (t == "table" and " (table)" or "")
        end
        if t == "table" and type(k) == "string" and k:find("^C_") then
            pcall(function()
                for fk, fv in pairs(v) do
                    if Match(fk) and TypeOf(fv) == "function" then found[#found + 1] = k .. "." .. fk end
                end
            end)
        end
    end
    table.sort(found)
    return found
end

-- W-501 /journey statprobe: walk every statistic, save the lot, print a summary.
function ns.StatProbe()
    local db = ns.GetDB()
    if not db then return end
    if ns.InCombat() then
        print(PREFIX, "Can't read statistics in combat. Try again once the fight is over.")
        return
    end
    local clock = type(debugprofilestop) == "function" and debugprofilestop or nil
    local started = clock and clock()
    local played = ns.PlayedNow()
    local probe = {
        takenAt = time(), level = ns.Level(), played = played and math.floor(played) or nil,
        missing = {}, categories = {}, stats = {}, errors = {}, compare = {},
        counts = { categories = 0, stats = 0, value = 0, empty = 0, secret = 0, errors = 0,
                   hidden = 0, accountFlag = 0, notStatistic = 0 },
    }
    local C = probe.counts
    local function Err(text)
        C.errors = C.errors + 1
        if #probe.errors < MAX_ERRORS then probe.errors[#probe.errors + 1] = text end
    end
    -- A failed call is an error, unless the function is missing (listed once instead).
    local function Failed(message, missing)
        if not missing then Err(message) end
    end

    local build = Try("GetBuildInfo")
    if build then probe.client, probe.build = Plain(build[1]), Plain(build[2]) end
    for _, name in ipairs(API) do
        if type(_G[name]) ~= "function" then probe.missing[#probe.missing + 1] = name end
    end

    -- Category IDs: one table of them, or (on some clients) one per return.
    local ids = {}
    local list, err, missing = Try("GetStatisticsCategoryList")
    if not list then
        Failed(err, missing)
    else
        local source, n = list, list.n
        if type(list[1]) == "table" then source, n = list[1], #list[1] end
        for i = 1, n do
            local id = Plain(source[i])
            if type(id) == "number" then ids[#ids + 1] = id end
        end
    end

    local band = bit and bit.band
    local accountFlag = Plain(_G.ACHIEVEMENT_FLAGS_ACCOUNT) or ACCOUNT_FLAG
    for _, catID in ipairs(ids) do
        local cat = { id = catID }
        probe.categories[#probe.categories + 1] = cat
        local info, e1, m1 = Try("GetCategoryInfo", catID)
        if info then
            cat.name, cat.parent, cat.flags = Plain(info[1]), Plain(info[2]), Plain(info[3])
        else
            Failed(e1, m1)
        end
        local num, e2, m2 = Try("GetCategoryNumAchievements", catID)
        if not num then Failed(e2, m2) end
        local count = num and Plain(num[1])
        if type(count) ~= "number" then count = 0 end
        cat.count = count
        -- With includeAll the count can be bigger: hidden statistics.
        local all = Try("GetCategoryNumAchievements", catID, true)
        local countAll = all and Plain(all[1])
        if type(countAll) == "number" and countAll > count then
            cat.countAll = countAll
            C.hidden = C.hidden + countAll - count
        end
        for index = 1, count do
            local a, e3, m3 = Try("GetAchievementInfo", catID, index)
            if not a then
                Failed(e3, m3)
            else
                -- id, name, points, completed, month, day, year, description,
                -- flags, icon, rewardText, isGuild, wasEarnedByMe, earnedBy, isStatistic
                local stat = { cat = catID, category = cat.name, id = Plain(a[1]), name = Plain(a[2]),
                               flags = Plain(a[9]), isStatistic = Plain(a[15]) }
                probe.stats[#probe.stats + 1] = stat
                C.stats = C.stats + 1
                if band and type(stat.flags) == "number" and band(stat.flags, accountFlag) ~= 0 then
                    C.accountFlag = C.accountFlag + 1
                end
                if stat.isStatistic == false then C.notStatistic = C.notStatistic + 1 end
                if type(stat.id) ~= "number" then
                    Err(string.format("GetAchievementInfo(%d, %d) gave no statistic ID", catID, index))
                else
                    local v, e4, m4 = Try("GetStatistic", stat.id)
                    if not v then
                        Failed(e4, m4)
                    elseif v.secret[1] then
                        stat.secret, stat.type = true, v.secret[1] -- the value itself is never kept
                        C.secret = C.secret + 1
                    else
                        local value = v[1]
                        stat.value, stat.type = Plain(value), type(value) -- raw, as the game gave it
                        if v.n > 1 then stat.returns = v.n end
                        if value == nil or value == "" or value == "--" then
                            C.empty = C.empty + 1
                        else
                            C.value = C.value + 1
                        end
                    end
                end
            end
        end
    end
    C.categories = #probe.categories
    if clock then probe.ms = math.floor(clock() - started + 0.5) end

    -- Per character or account-wide? Blizzard's numbers next to ours.
    local byName = {}
    for _, s in ipairs(probe.stats) do
        if s.name and s.value ~= nil then byName[s.name:lower()] = s.value end
    end
    for _, c in ipairs(COMPARE) do
        for _, name in ipairs(c.names) do
            local raw = byName[name:lower()]
            if raw ~= nil then
                probe.compare[#probe.compare + 1] = { label = c.label, stat = name, blizzard = raw, ours = c.ours(db) }
                break
            end
        end
    end
    local first = db.sessions.list[1] or db.sessions.current
    probe.trackedSinceLevel = first and first.startLevel
    probe.globals = StatisticGlobals()

    db.dev = db.dev or {}
    db.dev.statProbe = probe

    -- Summary
    local function p(text) print(PREFIX, text) end
    p("Statistics probe" .. (probe.client and (" (client " .. probe.client .. ")") or "") .. ":")
    if #probe.missing == 0 then
        p("  All 5 statistics functions exist.")
    else
        p("  Missing: " .. table.concat(probe.missing, ", "))
    end
    p(string.format("  %d categories, %d statistics%s.", C.categories, C.stats,
        probe.ms and string.format(" (read in %d ms)", probe.ms) or ""))
    p(string.format("  %d with a value, %d \"--\" or empty, %d secret, %d errors.",
        C.value, C.empty, C.secret, C.errors))
    for i = 1, math.min(3, #probe.errors) do p("  Error: " .. probe.errors[i]) end
    if C.hidden > 0 then
        p(string.format("  %d more statistics are hidden (only counted with includeAll).", C.hidden))
    end
    if C.notStatistic > 0 then
        p(string.format("  %d entries say they aren't statistics.", C.notStatistic))
    end
    if band and C.stats > 0 then
        p(string.format("  Account-wide flag: on %d of %d statistics.", C.accountFlag, C.stats))
    end
    if #probe.compare > 0 then
        local parts = {}
        for _, c in ipairs(probe.compare) do
            parts[#parts + 1] = string.format("%s %s vs %s", c.label, tostring(c.blizzard), tostring(c.ours))
        end
        p("  Blizzard vs Journey Tracker"
            .. (probe.trackedSinceLevel and (" (tracking since level " .. probe.trackedSinceLevel .. ")") or "")
            .. ": " .. table.concat(parts, ", ") .. ".")
        p("  Equal numbers fit per-character stats; much bigger ones mean account-wide, or history from before the addon.")
    end
    if #probe.globals > 0 then
        local shown = {}
        for i = 1, math.min(8, #probe.globals) do shown[i] = probe.globals[i] end
        p("  Statistics globals: " .. table.concat(shown, ", ") .. (#probe.globals > 8 and ", ..." or ""))
    end
    p("  Everything is saved to JourneyTrackerDB.dev.statProbe; /reload writes it to disk.")
end

---------------------------------------------------------------------------
-- Statistics snapshots (W-502..W-507)
--
-- Values are keyed by statistic ID and kept exactly as the game returns
-- them ("--" for none, gold as formatted text); the website parses them.
-- Names are stored once, in a lookup table:
--
--   db.statistics = {
--     names      = { [statID] = name },
--     categories = { [categoryID] = { name, parent, stats = { statID, ... } } },
--     order      = { categoryID, ... },  -- as the pane lists them
--     baseline   = snapshot,  -- W-502 the first read, never replaced
--     latest     = snapshot,  -- the most recent read, whatever the reason
--     levels     = { [level] = { t, played, changed = { [statID] = value } } }, -- W-503
--     skipped    = { [statID] = true },  -- secret when read, so never stored
--   }
--   snapshot = { t, level, played, reason, values = { [statID] = value },
--                ours = { kills, deaths, quests, flights, hearths } }
--
-- The baseline also has trackedSince (when our own tracking began). `ours`
-- is our own counts at the time, so the website can line the two up (W-506
-- lifetime totals, W-507 cross-check). A ding stores only what changed
-- since the previous ding, or the baseline.
---------------------------------------------------------------------------

local LOGIN_DELAY = 10      -- seconds after login, once statistics and /played have loaded
local DING_DELAY = 2        -- seconds after a ding, so it's counted
local REFRESH_SECONDS = 300 -- keeps `latest` current while you play
local REFRESH_GAP = 20      -- the window asks for a read at most this often (seconds)
local FRAME_BUDGET_MS = 4   -- longest a read runs in one frame before it waits for the next
local lastRead = -math.huge -- GetTime() of the last read, stored or not

local Num, Str, Safe, Call = ns.Num, ns.Str, ns.Safe, ns.Call

local function After(seconds, fn)
    if C_Timer and C_Timer.After then C_Timer.After(seconds, fn) end
end

local function HasAPI()
    for _, name in ipairs(API) do
        if type(_G[name]) ~= "function" then return false end
    end
    return true
end

local function Count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

local function CopyTable(t)
    local c = {}
    for k, v in pairs(t) do c[k] = type(v) == "table" and CopyTable(v) or v end
    return c
end

local function When(t) return t and date("%b %d, %H:%M", t) or "-" end

-- Statistics category IDs, whether the list comes back as one table or as
-- separate returns.
local function CategoryIDs()
    local ids = {}
    local function Add(v)
        v = Num(Safe(v))
        if v then ids[#ids + 1] = v end
    end
    local function Collect(ok, ...)
        if not ok then return end
        local first = Safe((...))
        if type(first) == "table" then
            for _, v in ipairs(first) do Add(v) end
        else
            for i = 1, select("#", ...) do Add((select(i, ...))) end
        end
    end
    if type(_G.GetStatisticsCategoryList) == "function" then Collect(pcall(_G.GetStatisticsCategoryList)) end
    return ids
end

-- One statistic's value as the game returns it; nil and true when it's secret.
local function ReadStatistic(id)
    local ok, v = pcall(_G.GetStatistic, id)
    if not ok then return nil end
    if IsSecret(v) then return nil, true end
    local t = type(v)
    if t == "string" or t == "number" or t == "boolean" then return v end
end

-- Read the whole pane: values, plus the names and categories for the lookup
-- table. Given a budget (ms per frame) it yields between chunks, so it then
-- has to run in a coroutine.
local function ReadPane(budget)
    local clock = type(debugprofilestop) == "function" and debugprofilestop or nil
    local read = { values = {}, skipped = {}, names = {}, categories = {}, order = {}, count = 0 }
    local started = clock and clock()
    for _, catID in ipairs(CategoryIDs()) do
        local name, parent = Call("GetCategoryInfo", catID)
        local stats = {}
        for index = 1, Num(Call("GetCategoryNumAchievements", catID)) or 0 do
            local id, statName = Call("GetAchievementInfo", catID, index)
            id = Num(id)
            if id then
                stats[#stats + 1] = id
                read.names[id] = Str(statName)
                local value, secret = ReadStatistic(id)
                if secret then
                    read.skipped[id] = true
                elseif value ~= nil then
                    read.values[id] = value
                    read.count = read.count + 1
                end
            end
            if budget and clock and clock() - started > budget then
                coroutine.yield()
                started = clock()
            end
        end
        parent = Num(parent)
        -- Top-level categories have a parent of -1; exports never carry negatives.
        read.categories[catID] = { name = Str(name), parent = parent and parent > 0 and parent or nil,
                                   stats = stats }
        read.order[#read.order + 1] = catID
    end
    return read
end

-- Our own running totals, to set beside Blizzard's (W-507).
local function Ours(db)
    return { kills = db.kills.total, deaths = #db.deaths, quests = db.quests.completed,
             flights = db.travel.flights, hearths = db.travel.hearths }
end

-- The values as of the last ding before `level`: the baseline with every
-- per-level change applied in order.
local function DingState(S, level)
    local state = {}
    for id, v in pairs(S.baseline and S.baseline.values or {}) do state[id] = v end
    local earlier = {}
    for l in pairs(S.levels) do
        if l < level then earlier[#earlier + 1] = l end
    end
    table.sort(earlier)
    for _, l in ipairs(earlier) do
        for id, v in pairs(S.levels[l].changed or {}) do state[id] = v end
    end
    return state
end

-- Save a read as a snapshot. Returns it, or nil if the read found nothing.
local function Store(read, reason)
    lastRead = GetTime()                                      -- whether or not it found anything
    local db = ns.GetDB()
    if not db or read.count == 0 then return nil end
    local S = db.statistics
    S.names, S.categories, S.order = read.names, read.categories, read.order
    for id in pairs(read.skipped) do S.skipped[id] = true end
    local played = ns.PlayedNow()
    local snap = { t = time(), level = ns.Level(), played = played and math.floor(played) or nil,
                   reason = reason, values = read.values, ours = Ours(db) }
    if not S.baseline then                                    -- W-502 the first read, kept for good
        S.baseline = CopyTable(snap)
        S.baseline.trackedSince = db.firstSeen
    end
    if reason == "ding" then                                  -- W-503 what changed this level
        local before = DingState(S, snap.level)
        local changed = {}
        for id, v in pairs(snap.values) do
            if before[id] ~= v then changed[id] = v end
        end
        S.levels[snap.level] = { t = snap.t, played = snap.played, changed = changed }
    end
    S.latest = snap
    return snap
end

-- Reads run one at a time, spread over frames, and never in combat: a
-- reason that comes up in combat waits for it to end ("refresh" is just
-- dropped), and one that comes up during a read gets a read of its own after.
local reading -- { [reason] = true } for the read in progress
local waiting, again = {}, {}
local Request

local function Hold(reasons)
    for reason in pairs(reasons) do
        if reason ~= "refresh" then waiting[reason] = true end
    end
end

Request = function(reason)
    if not ns.GetDB() or not HasAPI() then return end
    if ns.InCombat() then
        Hold({ [reason] = true })
        return
    end
    if reading then
        again[reason] = true
        return
    end
    local co = coroutine.create(ReadPane)
    reading = { [reason] = true }
    local function Step()
        if ns.InCombat() then
            Hold(reading)                                     -- read after the fight, with any asked for meanwhile
            Hold(again)
            reading, again = nil, {}
            return
        end
        local ok, read = coroutine.resume(co, FRAME_BUDGET_MS)
        if not ok then
            Hold(reading)                                     -- couldn't read the pane; try after the next fight
            reading, lastRead = nil, GetTime()
            return
        end
        if coroutine.status(co) ~= "dead" then
            if C_Timer and C_Timer.After then C_Timer.After(0, Step) else reading = nil end
            return
        end
        -- One read serves every reason that asked for it; a ding's records its changes.
        local reasons = reading
        reading = nil
        Store(read, reasons.ding and "ding" or reasons.login and "login" or next(reasons))
        local more = again
        again = {}
        for r in pairs(more) do Request(r) end
    end
    Step()
end

-- W-504 a snapshot right now (the export takes one). Out of combat only.
function ns.StatsSnapshot(reason)
    if not ns.GetDB() or ns.InCombat() or not HasAPI() then return nil end
    return Store(ReadPane(nil), reason or "export")
end

ns.OnLoad(function(db)
    db.statistics = type(db.statistics) == "table" and db.statistics or {}
    ns.Fill(db.statistics, { names = {}, categories = {}, order = {}, levels = {}, skipped = {} })
end)

ns.Listen("PLAYER_ENTERING_WORLD", function(isInitialLogin, isReload)
    if isInitialLogin or isReload then
        After(LOGIN_DELAY, function() Request("login") end)   -- the baseline, the first time
    end
end)

ns.Listen("PLAYER_LEVEL_UP", function()
    After(DING_DELAY, function() Request("ding") end)
end)

ns.Listen("PLAYER_REGEN_ENABLED", function()
    local held = waiting
    waiting = {}
    for reason in pairs(held) do Request(reason) end
end)

-- If /played wasn't known when the baseline was read, work it out from the
-- next reply.
ns.Listen("TIME_PLAYED_MSG", function(total)
    total = Num(Safe(total))
    local db = ns.GetDB()
    local base = db and db.statistics and db.statistics.baseline
    if total and base and not base.played then
        base.played = math.max(0, math.floor(total - (time() - base.t)))
    end
end)

if C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(REFRESH_SECONDS, function() Request("refresh") end)
end

---------------------------------------------------------------------------
-- In the window (W-506) and /journey stats (W-507)
--
-- Every statistic shows on the window page it fits, in its category. Where
-- a page already has a row for the same thing, that row shows the bigger
-- of our count and the game's (each starts partway through a character's
-- life, so the bigger is closest to the real total), and the page leaves
-- the statistic out of its list.
---------------------------------------------------------------------------

-- The window page each of the pane's categories goes on, by category ID.
-- One not listed goes where its parent goes, or else on the Summary.
local PAGE_OF = {
    [133] = "quests",
    [122] = "deaths", [126] = "deaths", [125] = "deaths", [124] = "deaths", [21] = "deaths",
    [127] = "rez",
    [141] = "fights",
    [128] = "kills", [135] = "kills",
    [136] = "pvp", [137] = "pvp", [154] = "pvp", [153] = "pvp",
    [14821] = "bosses", [14807] = "dungeons",
    [140] = "gold", [191] = "loot", [145] = "consumables",
    [132] = "skills", [130] = "skills", [173] = "professions", [178] = "professions",
    [134] = "travel", [147] = "social", [131] = "social",
}
-- Their headings in the window; any other category uses the pane's names.
local TITLES = {
    [133] = "Quest Pace", [126] = "Deaths in the World", [125] = "Deaths in Dungeons and Raids",
    [124] = "Deaths in Battlegrounds", [21] = "Deaths to Other Players", [127] = "Resurrected By",
    [141] = "Damage and Healing", [128] = "All Kills", [135] = "Creatures", [136] = "Honorable Kills",
    [137] = "Killing Blows", [154] = "Duels", [153] = "Battlegrounds", [14821] = "Boss Kills by Dungeon",
    [14807] = "Dungeons and Raids Entered", [140] = "Wealth", [191] = "Gear and Collections",
    [145] = "Consumables Used", [132] = "Skill Totals", [130] = "Talents", [173] = "Profession Records",
    [178] = "Cooking, First Aid and Fishing", [134] = "Summons and Portals", [147] = "Reputation",
    [131] = "Emotes",
}

local function PageOf(S, catID)
    if PAGE_OF[catID] then return PAGE_OF[catID] end
    local cat = S.categories[catID]
    return cat and cat.parent and PAGE_OF[cat.parent] or "summary"
end

local function Title(S, catID)
    if TITLES[catID] then return TITLES[catID] end
    local cat = S.categories[catID] or {}
    local parent = cat.parent and S.categories[cat.parent]
    local name = cat.name or ("Category " .. catID)
    return parent and parent.name and (parent.name .. ": " .. name) or name
end

-- Every statistic the pane puts on this page, under its category's heading,
-- exactly as the game shows it. `skip` is a set of statistic IDs the page
-- already shows in rows of its own.
function ns.DrawStatistics(B, page, skip)
    local db = ns.GetDB()
    local S = db and db.statistics
    if not (S and S.latest) then return end
    for _, catID in ipairs(S.order) do
        local cat = S.categories[catID]
        if cat and PageOf(S, catID) == page then
            local list = {}
            for _, id in ipairs(cat.stats or {}) do
                if not (skip and skip[id]) then list[#list + 1] = id end
            end
            if #list > 0 then
                B:Heading(Title(S, catID))
                for _, id in ipairs(list) do
                    local v = S.latest.values[id]
                    B:Row(S.names[id] or ("Statistic " .. id), v ~= nil and tostring(v) or (S.skipped[id] and "Hidden" or "--"))
                end
            end
        end
    end
end

-- A raw value as a number: counts ("1,204" is 1204, "--" is 0) and gold
-- (the amounts beside the coin icons, in copper). Nil for text like "3 (Beasts)".
local COIN = { Gold = 10000, Silver = 100, Copper = 1 }
local function AsNumber(v)
    if type(v) == "number" then return v end
    if type(v) ~= "string" then return nil end
    if v == "--" or v == "" then return 0 end
    local copper, coins = 0, false
    for amount, coin in v:gmatch("([%d,]+)%s*|T[^|]-UI%-(%a+)Icon[^|]*|t") do
        local n, unit = tonumber((amount:gsub(",", ""))), COIN[coin]
        if n and unit then copper, coins = copper + n * unit, true end
    end
    if coins then return copper end
    return tonumber((v:gsub(",", "")))
end

-- A statistic's latest value as a number (as above), or nil.
function ns.StatNumber(id)
    local db = ns.GetDB()
    local S = db and db.statistics
    local v = S and S.latest and S.latest.values[id]
    if v == nil then return nil end
    return AsNumber(v)
end

-- Read the pane again for the window, unless it was read moments ago.
function ns.RefreshStatistics()
    if not reading and GetTime() - lastRead >= REFRESH_GAP then Request("refresh") end
end

-- Statistic ID by name (any case), first in the pane's order.
local byName, byNameFor
local function StatID(S, name)
    if byNameFor ~= S.names then
        byName, byNameFor = {}, S.names
        for _, catID in ipairs(S.order) do
            local cat = S.categories[catID]
            for _, id in ipairs(cat and cat.stats or {}) do
                local n = S.names[id]
                if type(n) == "string" and not byName[n:lower()] then byName[n:lower()] = id end
            end
        end
    end
    return byName[name:lower()]
end

-- A statistic as a number in one snapshot: the first of `names` the pane
-- has, less the first of `minus` it has.
local function NumberIn(S, snap, names, minus)
    local value
    for _, name in ipairs(names) do
        local id = StatID(S, name)
        if id then
            value = AsNumber(snap.values[id])
            break
        end
    end
    if value and minus then value = value - (NumberIn(S, snap, minus) or 0) end
    return value
end

-- W-507 Blizzard's change since the baseline, next to ours over the same time.
local function CrossCheck(S)
    local parts, base, latest = {}, S.baseline, S.latest
    if not (base and latest and base.ours and latest.ours) then return parts end
    for _, c in ipairs(COMPARE) do
        local from, to = NumberIn(S, base, c.names, c.minus), NumberIn(S, latest, c.names, c.minus)
        if from and to then
            parts[#parts + 1] = string.format("%s %d vs %d", c.label, math.floor(to - from),
                math.floor((latest.ours[c.key] or 0) - (base.ours[c.key] or 0)))
        end
    end
    return parts
end

-- /journey stats
function ns.StatsStatus()
    local db = ns.GetDB()
    local S = db and db.statistics
    if not HasAPI() then
        print(PREFIX, "This client has no statistics functions, so the Statistics pane can't be read.")
        return
    end
    if not (S and S.latest) then
        print(PREFIX, "No statistics read yet. They're read about ten seconds after you log in, out of combat.")
        return
    end
    local base, latest = S.baseline, S.latest
    print(PREFIX, string.format("Statistics: %d read from %d categories%s.", Count(latest.values), #S.order,
        Count(S.skipped) > 0 and string.format(", %d skipped as secret", Count(S.skipped)) or ""))
    if base then
        -- On a fresh install the first read comes seconds after tracking starts.
        local before = base.trackedSince and base.trackedSince > 0 and base.t - base.trackedSince > 600
        print(PREFIX, string.format("Baseline: level %d, %s /played, read %s%s.", base.level or 0,
            base.played and ns.FormatDuration(base.played) or "unknown", When(base.t),
            before and " (Journey Tracker was already tracking)" or ""))
    end
    print(PREFIX, string.format("Last snapshot: %s (%s) at level %d. Changes recorded at %d level-ups.",
        When(latest.t), latest.reason or "?", latest.level or 0, Count(S.levels)))
    local check = CrossCheck(S)
    if #check > 0 then
        print(PREFIX, "Since the baseline, Blizzard vs Journey Tracker: " .. table.concat(check, ", ") .. ".")
    end
end
