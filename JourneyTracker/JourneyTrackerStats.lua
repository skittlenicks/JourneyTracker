-- JourneyTracker statistics: WoW Forever's Statistics pane on the character
-- page (combat, PvP, creatures, gold, consumables, factions, items,
-- professions, dungeons/raids, emotes). IDs W-501..W-508 match the
-- "Blizzard Statistics pane" section of wrapped-tracking-spec.md.
--
-- So far: /journey statprobe (dev only, W-501) checks whether the
-- achievement-statistics API exists and works on Forever, prints a summary
-- and saves every statistic to JourneyTrackerDB.dev.statProbe. None of this
-- API is confirmed on Forever, so every call is nil-checked and pcall'd,
-- secret values are never kept, and nothing is read in combat.

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
local COMPARE = {
    { label = "deaths", names = { "Total deaths" },
      ours = function(db) return #db.deaths end },
    { label = "quests completed", names = { "Quests completed" },
      ours = function(db) return db.quests.completed end },
    { label = "XP kills", names = { "Total kills that grant experience or honor", "Total kills" },
      ours = function(db) return db.kills.total end },
    { label = "flights", names = { "Flight paths taken" },
      ours = function(db) return db.travel.flights end },
    { label = "hearthstone uses", names = { "Number of times hearthed" },
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
