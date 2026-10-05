-- JourneyTracker: records one character's 1-60 journey for charting.
-- Item numbers (#N) match journey-tracking-spec.md.
--
-- Ground rules (from the spec and what JourneyProbe found on Forever):
--  * Every value from the game goes through Safe()/Call() first. Secret
--    values become nil and simply aren't counted, so nothing secret is ever
--    indexed, compared or stored.
--  * Kills made in combat are queued on the current fight and committed on
--    PLAYER_REGEN_ENABLED.
--  * Other players' names are never stored. Group members are counted by a
--    hash of their GUID; a PvP killer is recorded as "Player (PvP)".
--  * Health, power and auras are SECRET or blocked on Forever, so nothing
--    here depends on them.

local ADDON_NAME, ns = ... -- ns is shared with JourneyTrackerUI.lua
local SCHEMA_VERSION = 1      -- saved data layout; bump it with a new entry in MIGRATIONS
-- Addon version from the TOC's "## Version", e.g. "0.1.0".
local GetMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
local VERSION = GetMetadata and GetMetadata(ADDON_NAME, "Version") or "unknown"
local MAX_LEVEL = 60
local TICK_SECONDS = 5         -- time/position sampling interval
local FIGHT_SAMPLE_SECONDS = 1 -- nameplate threat sampling while in combat
local XP_SOURCE_WINDOW = 2     -- seconds an XP source (kill/quest/explore) stays "fresh"
local TELEPORT_YARDS = 200     -- a jump bigger than this between samples isn't travel
local SPOT_GRID = 25           -- #108 each zone map in 25 x 25 squares (4% of it each way)
local HEARTHSTONE = 8690
local FISHING = { [7620] = true, [7731] = true, [7732] = true, [18248] = true }
local PROFESSIONS = {
    Alchemy = true, Blacksmithing = true, Enchanting = true, Engineering = true,
    Herbalism = true, Leatherworking = true, Mining = true, Skinning = true,
    Tailoring = true, Cooking = true, ["First Aid"] = true, Fishing = true,
}
local PREFIX = "|cff33ff99Journey|r"

local db -- JourneyTrackerDB, set on ADDON_LOADED

-- What this file records, passed on to the other files (ns.OnKill and
-- friends). Each callback runs protected: an error in one of them can't
-- stop this file recording the kill, death or loot. The first errors are
-- kept for /journey status.
local hooks = { kill = {}, fight = {}, death = {}, fall = {}, loot = {}, money = {}, gather = {}, auction = {} }
local hookErrors = {}
local function Run(kind, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok and #hookErrors < 10 then table.insert(hookErrors, kind .. ": " .. tostring(err)) end
end
local function Fire(kind, ...)
    for _, fn in ipairs(hooks[kind]) do Run(kind, fn, ...) end
end

---------------------------------------------------------------------------
-- Safe access helpers
---------------------------------------------------------------------------

-- issecretvalue() exists on Forever (confirmed by JourneyProbe); guarded anyway.
local function IsSecret(v)
    if issecretvalue and issecretvalue(v) then
        return true
    end
    return false
end

-- The value, or nil if it's secret.
local function Safe(v)
    if IsSecret(v) then return nil end
    return v
end

-- Safe() applied to every value in a list of returns.
local function Clean(...)
    if select("#", ...) == 0 then return end
    return Safe((...)), Clean(select(2, ...))
end

-- Find a global function by name. Supports "C_Namespace.Func".
local function Lookup(name)
    local ns, fname = name:match("^([%w_]+)%.([%w_]+)$")
    if ns then
        local t = _G[ns]
        return type(t) == "table" and t[fname] or nil
    end
    return _G[name]
end

-- Always at least one value back (nil), even when the API returns nothing,
-- so results can be passed straight to type() and friends.
local function Unwrap(ok, ...)
    if not ok or select("#", ...) == 0 then return nil end
    return Clean(...)
end

-- Game functions asked for that this client doesn't have, for /journey
-- status (some are only fallbacks for others that it does have).
local missingAPIs, missingAPIList = {}, {}

-- Call a game API by name. Missing functions, errors and secret return
-- values all come back as nil, so callers only ever see plain values.
local function Call(name, ...)
    local fn = Lookup(name)
    if type(fn) ~= "function" then
        if not missingAPIs[name] and #missingAPIList < 40 then
            missingAPIs[name] = true
            table.insert(missingAPIList, name)
        end
        return nil
    end
    return Unwrap(pcall(fn, ...))
end

-- Type filters for values that have already been through Safe()/Call().
local function Num(v) if type(v) == "number" then return v end end
local function Str(v) if type(v) == "string" and v ~= "" then return v end end

local function Inc(t, key, amount)
    t[key] = (t[key] or 0) + (amount or 1)
end

-- Map coordinate (0-1) to a percentage with one decimal, like 45.3. The
-- game can place you a little past a map's edge; that reads as the edge
-- (an export with a negative number in it is turned away).
local function Pct(v)
    if v then return math.floor(math.max(0, math.min(1, v)) * 1000 + 0.5) / 10 end
end

-- Turn a Blizzard format string ("%s dies, you gain %d experience.") into a
-- Lua pattern. Uses the client's own global string so it matches the
-- client's wording; falls back to the English text if the global is missing.
-- Positional formats (%1$s, used by some locales) aren't handled.
local function PatternFrom(fmt, english, anchorEnd)
    if type(fmt) ~= "string" then fmt = english end
    local p = fmt:gsub("[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0")
    p = p:gsub("%%s", "(.-)")
    p = p:gsub("%%d", "(%%d+)")
    return "^" .. p .. (anchorEnd and "$" or "")
end

local PATTERNS = {
    kill        = PatternFrom(COMBATLOG_XPGAIN_FIRSTPERSON, "%s dies, you gain %d experience."),
    lootMulti   = PatternFrom(LOOT_ITEM_SELF_MULTIPLE, "You receive loot: %sx%d.", true),
    loot        = PatternFrom(LOOT_ITEM_SELF, "You receive loot: %s.", true),
    createMulti = PatternFrom(LOOT_ITEM_CREATED_SELF_MULTIPLE, "You create: %sx%d.", true),
    create      = PatternFrom(LOOT_ITEM_CREATED_SELF, "You create: %s.", true),
    skill       = PatternFrom(SKILL_RANK_UP, "Your skill in %s has increased to %d."),
    exploreXP   = PatternFrom(ERR_ZONE_EXPLORED_XP, "Discovered %s: %d experience gained"),
    explore     = PatternFrom(ERR_ZONE_EXPLORED, "Discovered: %s"),
    learnSpell  = PatternFrom(ERR_LEARN_SPELL_S, "You have learned a new spell: %s."),
    learnAbility = PatternFrom(ERR_LEARN_ABILITY_S, "You have learned a new ability: %s."),
    learnRecipe = PatternFrom(ERR_LEARN_RECIPE_S, "You have learned how to create a new item: %s."),
    auctionSold = PatternFrom(ERR_AUCTION_SOLD_S, "A buyer has been found for your auction of %s."),
    auctionExpired = PatternFrom(ERR_AUCTION_EXPIRED_S, "Your auction of %s has expired.", true),
    auctionRemoved = PatternFrom(ERR_AUCTION_REMOVED, "Auction cancelled.", true),
}
local NEW_TAXI_PATH = type(ERR_NEWTAXIPATH) == "string" and ERR_NEWTAXIPATH
    or "New flight path discovered!"

-- Small non-reversible string hash, so group members can be counted without
-- storing who they are.
local function Hash(s)
    local h = 5381
    for i = 1, #s do
        h = (h * 33 + s:byte(i)) % 4294967296
    end
    return string.format("%08x", h)
end

local function FormatDuration(sec)
    sec = math.floor(sec or 0)
    local d, h, m = math.floor(sec / 86400), math.floor(sec % 86400 / 3600), math.floor(sec % 3600 / 60)
    if d > 0 then return string.format("%dd %dh %dm", d, h, m) end
    if h > 0 then return string.format("%dh %dm", h, m) end
    return string.format("%dm %ds", m, sec % 60)
end

local function FormatMoney(copper)
    copper = copper or 0
    return string.format("%dg %ds %dc", math.floor(copper / 10000),
        math.floor(copper % 10000 / 100), copper % 100)
end

---------------------------------------------------------------------------
-- Saved data layout. The root also holds schemaVersion and characterId,
-- which the migrations below set (they're never filled from defaults).
---------------------------------------------------------------------------

local DEFAULTS = {
    firstSeen = 0,          -- #4 epoch of first login with the tracker
    -- reachedMax           -- #4 epoch of dinging MAX_LEVEL
    char = {},              -- your own name/realm/class/race
    played = { total = 0 }, -- #1 latest /played; levelStart = /played when current level began
    dings = {},             -- [level] = snapshot at the ding, see OnLevelUp()
    levels = {},            -- [level] = per-level counters, see LevelStats()
    sessions = { list = {} }, -- #6-9; .current = the open session
    time = { afk = 0, resting = 0, taxi = 0, mounted = 0, dead = 0, grouped = 0,
             solo = 0, combat = 0, corpseRuns = 0 },
    hours = {},             -- #18 [0-23] = seconds played in that hour of day
    days = {},              -- #17 ["YYYY-MM-DD"] = true
    xp = { total = 0, quest = 0, kill = 0, explore = 0, other = 0,
           solo = 0, grouped = 0, restedUsed = 0 },
    kills = { total = 0, byName = {}, byClass = {}, byType = {} },
    combat = { fights = 0, longest = 0, died = 0, ambushMobs = 0, multiPulls = 0, maxMobs = 0 },
    bosses = {},            -- #41-42 [boss] = { attempts, kills, wipes }
    pvp = {},               -- #43 honorableKills
    deaths = {},            -- #44-50 list of death records
    rez = {},               -- #49 [type] = count
    graveyards = {},        -- #72 ["zone: subzone"] = count
    quests = { completed = 0, xp = 0, money = 0, accepted = 0, abandoned = 0,
               byZone = {}, byTag = {}, open = {} },
    zones = {},             -- #63/#66 [zone] = { first, seconds, firstLevel }
    subzones = {},          -- #64 ["zone: subzone"] = first visit epoch
    discovered = 0,         -- #64 "Discovered ..." exploration messages
    path = {},              -- #67 zone changes in order
    where = {},             -- #108 [uiMapID] = { [square] = seconds }, see SpotOf()
    travel = { hearths = 0, flights = 0, flightPaths = {}, ground = 0, taxi = 0 },
    dungeons = { entered = {}, runs = {} }, -- #73-75; .current = run in progress
    money = { earned = 0, spent = 0, loot = 0, vendor = 0, vendorSpent = 0,
              training = 0, repairs = 0, flights = 0, auctionSpent = 0,
              mail = 0, auctionIncome = 0, auctionsSold = 0, peak = 0 },
    loot = { items = 0, byQuality = {} },
    gear = {},              -- #89 [level] = { [slot] = itemLink }
    worn = {},              -- #104 [item] = { link, slot, played, levels, first, last }
    skills = {},            -- #92/#96 [skill] = { rank, firstLevel, firstTime, history }
    skillUps = 0,
    professions = {},       -- #91 [name] = { level, time }
    crafted = 0,            -- #93
    fish = 0,               -- #94
    spells = {},            -- #95 [spell name] = { level, time }
    social = { seen = {}, unique = 0, jumps = 0 },
    falls = { count = 0, total = 0, fatal = 0 }, -- #101-102; plus longestSurvived, longestFatal
    gathering = {                                 -- #103 nodes and what they gave
        herb = { nodes = 0, items = {} },
        mining = { nodes = 0, swings = 0, items = {} },
        skinning = { nodes = 0, items = {} },
    },
}

local function Copy(t)
    local c = {}
    for k, v in pairs(t) do
        c[k] = type(v) == "table" and Copy(v) or v
    end
    return c
end

-- Add any missing keys from defaults without touching existing data.
local function Fill(t, defaults)
    for k, v in pairs(defaults) do
        if t[k] == nil then
            t[k] = type(v) == "table" and Copy(v) or v
        elseif type(v) == "table" and type(t[k]) == "table" then
            Fill(t[k], v)
        end
    end
end

---------------------------------------------------------------------------
-- Saved data versioning
--
-- schemaVersion says which layout the saved data uses; MIGRATIONS[n]
-- upgrades data from version n-1 to n. Every migration must:
--   * never wipe or reset existing data;
--   * on a rename, copy the old value over before removing the old key.
-- Migrations run on a copy. If one fails, the saved table is left exactly
-- as it was and tracking stays off for the session, so a half-migrated
-- table is never saved.
---------------------------------------------------------------------------

local randomSeeded = false

-- Random UUID v4 (8-4-4-4-12 hex). Anonymous: not derived from the
-- character's name or realm.
local function NewCharacterId()
    if not randomSeeded then
        randomSeeded = true
        -- Mix the clock, session time and a high-resolution timer. Some
        -- clients ignore randomseed because they're already randomly seeded.
        local seed = time() + math.floor(GetTime() * 1000)
            + math.floor((debugprofilestop and debugprofilestop() or 0) * 1000)
        if math.randomseed then pcall(math.randomseed, seed % 2147483647) end
    end
    local id = ("xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"):gsub("[xy]", function(c)
        return string.format("%x", c == "x" and math.random(0, 15) or math.random(8, 11))
    end)
    return id
end

local MIGRATIONS = {
    -- 1: stamp the layout as it is today. Folds in the one fix made before
    -- versioning existed (flight paths had counted as mounted time, #14/#84),
    -- keeping the uncorrected values; renames the old "schema" field to
    -- legacySchema; and gives the character its ID.
    [1] = function(data)
        if data.schema == 1 and type(data.time) == "table" then
            local T = data.time
            data.legacy = data.legacy or {}
            data.legacy.mountedWithTaxi = T.mounted
            data.legacy.firstMount = data.firstMount
            T.mounted = math.max((T.mounted or 0) - (T.taxi or 0), 0)
            if T.mounted == 0 then data.firstMount = nil end
        end
        if data.schema ~= nil then
            data.legacySchema = data.schema
            data.schema = nil
        end
        if data.characterId == nil then data.characterId = NewCharacterId() end
    end,
}

-- The saved data upgraded to SCHEMA_VERSION (the same table if it's already
-- current), or nil and the reason a migration failed.
local function UpgradeSavedData(saved)
    local from = tonumber(saved.schemaVersion) or 0
    if from >= SCHEMA_VERSION then return saved end
    local working = Copy(saved)
    for version = from + 1, SCHEMA_VERSION do
        local migrate = MIGRATIONS[version]
        if not migrate then return nil, "no migration to version " .. version end
        local ok, err = pcall(migrate, working)
        if not ok then return nil, "version " .. version .. ": " .. tostring(err) end
        working.schemaVersion = version
    end
    return working
end

-- /journey backup: a full copy of this character's data in a second saved
-- table (JourneyTrackerBackup), as a safety net before risky updates.
local function Backup()
    JourneyTrackerBackup = type(JourneyTrackerBackup) == "table" and JourneyTrackerBackup or {}
    JourneyTrackerBackup.manual = { takenAt = time(), addonVersion = VERSION,
        schemaVersion = db.schemaVersion, data = Copy(db) }
    print(PREFIX, "Backup saved. It's written to disk when you log out or /reload.")
end

---------------------------------------------------------------------------
-- Context helpers
---------------------------------------------------------------------------

local function Level() return Num(Call("UnitLevel", "player")) or 0 end
local function Zone() return Str(Call("GetZoneText")) or "Unknown" end
local function SubZone() return Str(Call("GetSubZoneText")) end
local function InGroup() return Call("IsInGroup") == true end
local function InCombat() return InCombatLockdown() == true end

-- Zone map position as percentages. Nil inside instances where it's hidden.
local function MapPos()
    local mapID = Num(Call("C_Map.GetBestMapForUnit", "player"))
    if not mapID then return nil end
    local pos = Call("C_Map.GetPlayerMapPosition", mapID, "player")
    if type(pos) ~= "table" then return mapID end
    local ok, x, y = pcall(pos.GetXY, pos)
    if not ok then return mapID end
    return mapID, Pct(Num(Safe(x))), Pct(Num(Safe(y)))
end

-- #108 the square of a zone map a position (percentages) is in: 1 to 625,
-- row by row from the top left.
local function SpotOf(x, y)
    local col = math.min(SPOT_GRID - 1, math.max(0, math.floor(x / 100 * SPOT_GRID)))
    local row = math.min(SPOT_GRID - 1, math.max(0, math.floor(y / 100 * SPOT_GRID)))
    return row * SPOT_GRID + col + 1
end

-- World position in yards (readable outdoors on Forever, per the probe).
local function WorldPos()
    local y, x, _, inst = Call("UnitPosition", "player")
    if Num(x) and Num(y) then return x, y, inst end
end

-- Per-level counters for charts.
local function LevelStats(level)
    level = level or Level()
    local s = db.levels[level]
    if not s then
        s = { xp = 0, kills = 0, quests = 0, deaths = 0 }
        db.levels[level] = s
    end
    return s
end

-- /played right now, if we've had a TIME_PLAYED_MSG this session.
local playedBase, playedAt
local function PlayedNow()
    if playedBase then return playedBase + (GetTime() - playedAt) end
end

---------------------------------------------------------------------------
-- XP (#21-25, #56, #65)
---------------------------------------------------------------------------

-- The most recent XP source event. Kill/quest/explore events arrive just
-- before PLAYER_XP_UPDATE (confirmed by the probe), so the update can be
-- attributed to whatever fired in the last couple of seconds.
local xpSource = { t = 0 }
local function MarkXPSource(kind)
    xpSource.kind, xpSource.t = kind, GetTime()
end
local function FreshXPSource(window)
    if xpSource.kind and GetTime() - xpSource.t <= (window or XP_SOURCE_WINDOW) then
        return xpSource.kind
    end
end

local lastXP, lastXPMax, lastRested, lastLevel
local function ReadXP()
    local xp = Num(Call("UnitXP", "player"))
    local xpMax = Num(Call("UnitXPMax", "player"))
    local rested = Num(Call("GetXPExhaustion")) or 0 -- nil = no rested pool
    return xp, xpMax, rested
end

local function SeedXP()
    lastXP, lastXPMax, lastRested = ReadXP()
    lastLevel = Level()
end

local function OnXPUpdate()
    local xp, xpMax, rested = ReadXP()
    if not xp then return end
    if lastXP then
        local gained
        if xp >= lastXP then
            gained = xp - lastXP
        elseif lastXPMax then
            gained = (lastXPMax - lastXP) + xp -- the bar rolled over at a ding
        end
        if gained and gained > 0 then
            local X = db.xp
            local kind = FreshXPSource() or "other"
            X.total = X.total + gained                            -- #24 total XP
            Inc(X, kind, gained)                                  -- #23 split (#65 explore)
            if InGroup() then                                     -- #25 solo vs grouped
                X.grouped = X.grouped + gained
            else
                X.solo = X.solo + gained
            end
            if xp < lastXP and lastLevel and lastLevel > 0 then
                -- A ding: what finished the old level is that level's, the
                -- rest the new one's.
                local old = LevelStats(lastLevel)
                old.xp = old.xp + (gained - xp)
                local new = LevelStats(lastLevel + 1)
                new.xp = new.xp + xp
            else
                local L = LevelStats()
                L.xp = L.xp + gained
            end
            if lastRested and rested < lastRested then            -- #22 rested XP used
                X.restedUsed = X.restedUsed + (lastRested - rested)
            end
        end
    end
    lastXP, lastXPMax, lastRested = xp, xpMax, rested
    lastLevel = Level()
end

---------------------------------------------------------------------------
-- Falls (#101-102)
--
-- There's no fall event and height can't be read, so falls are timed: an
-- OnUpdate watches IsFalling() every frame (a fall lasts a second or two)
-- and the drop is worked out from time in the air using WoW's movement
-- constants. A jump's own rise is taken off, so hopping on flat ground
-- doesn't count as falling.
---------------------------------------------------------------------------

local GRAVITY = 19.2911    -- yd/s^2
local TERMINAL = 60.148    -- yd/s, top fall speed
local JUMP_SPEED = 7.95554 -- yd/s, upward speed when a jump starts
local MIN_FALL = 1         -- yards; smaller drops (steps, bumps) are ignored
local DAMAGE_FALL = 15     -- yards; roughly where fall damage starts
local FATAL_CHECK = 1.5    -- seconds after landing before deciding we survived
-- Slow Fall, Levitate and Noggenfogger's slow fall (by spell, and by name
-- whatever the rank or source): timing would overstate these.
local SLOW_FALL = { 130, 1706, 16593 }
local SLOW_FALL_NAMES = { "Slow Fall", "Levitate" }
local FALL_LOOK = 0.1      -- seconds between looks for a slow fall while in the air
local STALL = 0.5          -- seconds between frames past which a fall's timing can't be trusted

local lastJump, jumpHeld = 0, false -- set by the jump key hooks (see InstallHooks)
local fallStart, fallJumped, fallSlowed, fallStalled, fallLookAt
local lastFrame = 0
local lastLanding -- { at, fall } for the most recent real fall

-- A slow fall on you now, cast by you or anyone, or from an item. (In
-- combat the aura API can't be read, and this says no.)
local function SlowFalling()
    for _, id in ipairs(SLOW_FALL) do
        if Call("C_UnitAuras.GetPlayerAuraBySpellID", id) then return true end
    end
    for _, name in ipairs(SLOW_FALL_NAMES) do
        if Call("C_UnitAuras.GetAuraDataBySpellName", "player", name, "HELPFUL") then return true end
    end
    return false
end

-- Yards fallen from rest in t seconds, capped at top fall speed.
local function DropFromTime(t)
    local tTop = TERMINAL / GRAVITY
    if t <= tTop then return 0.5 * GRAVITY * t * t end
    return 0.5 * GRAVITY * tTop * tTop + TERMINAL * (t - tTop)
end

local function OnLanded(airTime)
    local drop
    if fallJumped then
        local rise = JUMP_SPEED / GRAVITY -- seconds spent going up
        drop = DropFromTime(math.max(airTime - rise, 0)) - 0.5 * JUMP_SPEED * rise
    else
        drop = DropFromTime(airTime)
    end
    if drop < MIN_FALL then return end
    local F = db.falls
    F.count = F.count + 1
    F.total = F.total + drop                                  -- #101 total distance fallen
    local fall = { yards = drop, t = time(), level = Level(), zone = Zone(), subzone = SubZone() }
    lastLanding = { at = GetTime(), fall = fall }
    Fire("fall", fall, airTime)
    if not (C_Timer and C_Timer.After) then return end
    -- #102 longest fall survived: still alive a moment after landing?
    C_Timer.After(FATAL_CHECK, function()
        if Call("UnitIsDeadOrGhost", "player") == true then
            if drop >= DAMAGE_FALL then
                F.fatal = F.fatal + 1
                if not F.longestFatal or drop > F.longestFatal.yards then F.longestFatal = fall end
            end
        elseif not F.longestSurvived or drop > F.longestSurvived.yards then
            F.longestSurvived = fall
        end
    end)
end

local function WatchFalling()
    local falling = IsFalling and Safe(IsFalling()) -- true/false (or 1/nil on older clients)
    local now = GetTime()
    local stalled = now - lastFrame > STALL   -- a loading screen or a freeze since the last frame
    lastFrame = now
    if falling then
        if not fallStart then
            -- A ghost's drops on a corpse run aren't falls.
            if Call("UnitIsDeadOrGhost", "player") == true then return end
            fallStart, fallLookAt, fallStalled = now, now, false
            fallJumped = jumpHeld or now - lastJump < 0.25
            fallSlowed = SlowFalling()
        else
            if stalled then fallStalled = true end
            -- Slow Fall can come on the way down (yours is also caught as
            -- you cast it, in UNIT_SPELLCAST_SUCCEEDED).
            if not fallSlowed and now - fallLookAt >= FALL_LOOK then
                fallLookAt = now
                fallSlowed = SlowFalling()
            end
        end
    elseif fallStart then
        local airTime = now - fallStart
        fallStart = nil
        -- Not timed: a slow fall (on the way down, or on you as you land),
        -- or one with a loading screen or a freeze in it, whose time isn't
        -- time in the air.
        if not fallSlowed and not fallStalled and not stalled and not SlowFalling() and airTime < 30 then
            OnLanded(airTime)
        end
    end
end

-- True when a fall is the likely cause of a death happening now (#47).
local function FellToDeath()
    local now = GetTime()
    if fallStart and not fallSlowed and not fallStalled and now - fallStart > 1 then return true end
    return lastLanding ~= nil and now - lastLanding.at <= FATAL_CHECK
        and lastLanding.fall.yards >= DAMAGE_FALL
end

---------------------------------------------------------------------------
-- Kills and fights (#26-40, #47)
---------------------------------------------------------------------------

local mobInfo = {}   -- session cache: [mob name] = { class, ctype, family, level }
local playerInfo = {} -- session cache, never saved: [player name] = { class, level, enemy }
local plates = {}    -- active nameplate unit tokens
local fight          -- the current fight while in combat
local lastHostile    -- last attackable thing we targeted (name or "Player (PvP)")
local lastHostileAt = 0 -- GetTime() it was targeted
local lastTargetGUID, lastTargetTime
local HOSTILE_FRESH = 60 -- seconds a targeted hostile can still be what you fight or die to

local function RecentHostile()
    if lastHostile and GetTime() - lastHostileAt <= HOSTILE_FRESH then return lastHostile end
end

-- A unit's name, or "Player (PvP)" so player names are never stored.
local function UnitLabel(unit)
    if Call("UnitIsPlayer", unit) == true then return "Player (PvP)" end
    return Str(Call("UnitName", unit))
end

-- Remember what a mob is, so the kill message (which only has its name)
-- can be matched to elite/rare, creature type, beast family and level. A
-- player's class and level are remembered for this session only, so a PvP
-- kill or death can be counted by class; their names are never saved.
local function CacheUnit(unit)
    local isPlayer = Call("UnitIsPlayer", unit)
    if isPlayer == true then
        local name = Str(Call("UnitName", unit))
        local _, class = Call("UnitClass", unit)
        if name then
            playerInfo[name] = { class = Str(class), level = Num(Call("UnitLevel", unit)),
                                 enemy = Call("UnitIsEnemy", "player", unit) == true }
        end
        return
    end
    if isPlayer ~= false then return end
    local name = Str(Call("UnitName", unit))
    if not name then return end
    mobInfo[name] = {
        class = Str(Call("UnitClassification", unit)),
        ctype = Str(Call("UnitCreatureType", unit)),
        family = Str(Call("UnitCreatureFamily", unit)),
        level = Num(Call("UnitLevel", unit)),
        faction = Str(Call("UnitFactionGroup", unit)),        -- guards (wrapped W-339)
    }
end

local function CommitKill(k)
    local K = db.kills
    K.total = K.total + 1                                     -- #26 XP-granting kills
    local L = LevelStats(k.level)
    L.kills = L.kills + 1                                     -- #27 kills per level
    Inc(K.byName, k.name)                                     -- #28 by name (#29 most killed = max)
    if k.class then Inc(K.byClass, k.class) end               -- #30/#31 elite, rare, rareelite
    if k.ctype then Inc(K.byType, k.ctype) end                -- #32 creature type
    if k.mobLevel and k.mobLevel > 0 then                     -- #33 (-1 = skull level, skipped)
        local diff = k.mobLevel - k.level
        if not K.maxLevelDiff or diff > K.maxLevelDiff.diff then
            K.maxLevelDiff = { diff = diff, name = k.name, mobLevel = k.mobLevel, level = k.level }
        end
    end
    Fire("kill", k)
end

local function QueueKill(name)
    local info = mobInfo[name]
    local k = {
        name = name, level = Level(), t = time(), zone = Zone(), subzone = SubZone(), grouped = InGroup(),
        class = info and info.class, ctype = info and info.ctype, family = info and info.family,
        mobLevel = info and info.level,
    }
    if fight then
        table.insert(fight.kills, k) -- committed on PLAYER_REGEN_ENABLED
    else
        CommitKill(k)
    end
end

-- Sample nameplates for mobs with threat on us. Threat and GUIDs are
-- readable in combat on Forever (probe); needs enemy nameplates enabled.
local function SampleFight()
    if not fight then return end
    local count = 0
    for unit in pairs(plates) do
        local threat = Num(Call("UnitThreatSituation", "player", unit))
        local guid = Str(Call("UnitGUID", unit))
        if threat and guid then
            count = count + 1
            if not fight.threat[guid] then
                fight.threat[guid] = true
                -- #39 had threat on us before we ever targeted it
                if not fight.targeted[guid] then
                    fight.ambush = fight.ambush + 1
                end
                -- Who was in the fight, and the highest level that came at us
                -- (-1 is a skull), for the other files.
                local label = UnitLabel(unit)
                if label then fight.names[label] = true end
                local level = Num(Call("UnitLevel", unit))
                if level and (level == -1 or fight.maxMobLevel ~= -1 and level > (fight.maxMobLevel or 0)) then
                    fight.maxMobLevel = level
                end
            end
            if threat >= 2 then
                fight.lastHostile = UnitLabel(unit) or fight.lastHostile -- #47 candidate
            end
        end
    end
    if count > fight.maxMobs then fight.maxMobs = count end
end

local fightTicker
local function StartFight()
    fight = { start = GetTime(), kills = {}, threat = {}, targeted = {},
              ambush = 0, maxMobs = 0, lastHostile = RecentHostile(), names = {}, grouped = InGroup(),
              zone = Zone(), subzone = SubZone() }
    -- Whatever we targeted just before the pull counts as "targeted".
    if lastTargetGUID and GetTime() - lastTargetTime <= 10 then
        fight.targeted[lastTargetGUID] = true
    end
    local cur = Str(Call("UnitGUID", "target"))
    if cur then fight.targeted[cur] = true end
    if Call("UnitCanAttack", "player", "target") == true then
        local label = UnitLabel("target")
        if label then fight.names[label] = true end
    end
    db.combat.fights = db.combat.fights + 1                   -- #34 combats entered
    if not fightTicker and C_Timer and C_Timer.NewTicker then
        fightTicker = C_Timer.NewTicker(FIGHT_SAMPLE_SECONDS, SampleFight)
    end
end

local function EndFight()
    if fightTicker then
        fightTicker:Cancel()
        fightTicker = nil
    end
    if not fight then return end
    local C = db.combat
    local dur = GetTime() - fight.start
    db.time.combat = db.time.combat + dur                     -- #37 total combat time (#36 avg = /fights)
    if dur > C.longest then C.longest = dur end               -- #35 longest fight
    if fight.died then C.died = C.died + 1 end                -- #38 fights ending in death
    C.ambushMobs = C.ambushMobs + fight.ambush                -- #39
    if fight.maxMobs >= 2 then C.multiPulls = C.multiPulls + 1 end -- #40 multi-mob pulls
    if fight.maxMobs > C.maxMobs then C.maxMobs = fight.maxMobs end
    for _, k in ipairs(fight.kills) do
        CommitKill(k)
    end
    fight.duration = dur
    Fire("fight", fight)
    fight = nil
end

-- #47 best guess at what killed us: a big fall, else a hostile target, else
-- the last mob seen attacking us, else the last hostile we targeted.
local function KillerName()
    if FellToDeath() then return "Falling" end
    if Call("UnitCanAttack", "player", "target") == true and Call("UnitIsDead", "target") ~= true then
        local n = UnitLabel("target")
        if n then return n end
    end
    return (fight and fight.lastHostile) or RecentHostile() or "Unknown"
end

---------------------------------------------------------------------------
-- Dungeons (#73-75)
---------------------------------------------------------------------------

local function FinishRun()
    local D = db.dungeons
    local run = D.current
    if not run then return end
    -- #74 time per run: the time you were logged in during it, or for a run
    -- begun before that was counted, the clock time since it began.
    run.duration = run.active and math.floor(run.active + 0.5) or (time() - run.start)
    run.active = nil
    table.insert(D.runs, run)
    D.current = nil
end

local function CheckDungeon()
    local D = db.dungeons
    local inInstance, itype = Call("IsInInstance")
    if inInstance == true and (itype == "party" or itype == "raid") then
        local name = Str(Call("GetInstanceInfo")) or "Unknown"
        if not D.current or D.current.name ~= name then
            FinishRun()
            D.current = { name = name, start = time(), level = Level(), bosses = 0, deaths = 0, active = 0 }
            Inc(D.entered, name)                              -- #73 dungeons entered
        end
    elseif D.current then
        -- Corpse runs leave the instance as a ghost; that's still the same run.
        if Call("UnitIsDeadOrGhost", "player") == true then return end
        FinishRun()
    end
end

---------------------------------------------------------------------------
-- Deaths and resurrection (#12, #44-50, #72)
---------------------------------------------------------------------------

local death = {} -- the current death: rec, start, released, hint, accepted

local function OnDeath()
    local level = Level()
    local mapID, x, y = MapPos()
    local inInstance = Call("IsInInstance")
    local rec = {
        t = time(), level = level,
        zone = Zone(), subzone = SubZone(), mapID = mapID, x = x, y = y, -- #46
        killer = KillerName(),                                -- #47
        grouped = InGroup(),                                  -- #48
        dungeon = inInstance == true and Str(Call("GetInstanceInfo")) or nil, -- #48/#75
    }
    table.insert(db.deaths, rec)                              -- #44 total deaths
    local L = LevelStats(level)
    L.deaths = L.deaths + 1                                   -- #45 deaths per level
    if fight then fight.died = true end                       -- #38
    local run = db.dungeons.current
    if run then run.deaths = run.deaths + 1 end               -- #75 deaths per dungeon
    death = { rec = rec, start = GetTime() }
    -- For the other files: what the killer was (if we saw it), and whether
    -- a fall or a fight was going on. They may add fields to rec.
    Fire("death", rec, { mob = mobInfo[rec.killer], fell = FellToDeath(), fight = fight,
                         player = rec.killer == "Player (PvP)" and Call("UnitIsPlayer", "target") == true
                             and { class = select(2, Call("UnitClass", "target")), level = Num(Call("UnitLevel", "target")) } })
end

-- Called once we're alive again. `how` is the resurrection type.
local function FinishDeath(how)
    local now = GetTime()
    Inc(db.rez, how)                                          -- #49 resurrection type
    local rec = death.rec
    if rec then
        rec.rez = how
        if death.start then
            rec.deadFor = now - death.start
            db.time.dead = db.time.dead + rec.deadFor         -- #12 time spent dead
        end
        if death.released and how == "corpse run" then
            rec.corpseRun = now - death.released
            db.time.corpseRuns = db.time.corpseRuns + rec.corpseRun -- #50 corpse run time
        end
    end
    death = {}
end

-- The Accept buttons call these functions; hooking them tells us exactly
-- which way back was used. AcceptXPLoss is missing on Forever (probe), so
-- the spirit healer falls back to the CONFIRM_XP_LOSS dialog hint.
local function OnRezAccept(how)
    death.accepted = how
end

---------------------------------------------------------------------------
-- Quests (#53-62)
---------------------------------------------------------------------------

local function QuestTag(questID)
    local info = Call("C_QuestLog.GetQuestTagInfo", questID)
    if type(info) == "table" then
        return Str(Safe(info.tagName)) -- "Elite", "Group", "Dungeon", ...
    end
end

local pendingAbandon
local function OnAbandon()
    local Q = db.quests
    Q.abandoned = Q.abandoned + 1                             -- #59 quests abandoned
    if pendingAbandon then
        Q.open[pendingAbandon] = nil
        pendingAbandon = nil
    end
end

---------------------------------------------------------------------------
-- Zones, exploration and travel (#63-72)
---------------------------------------------------------------------------

local currentZone
local function OnZoneChange()
    local z = Zone()
    if not db.zones[z] then                                   -- #63 first visit
        db.zones[z] = { first = time(), seconds = 0, firstLevel = Level() }
    end
    if z ~= currentZone then
        currentZone = z
        local last = db.path[#db.path]
        if not last or last.zone ~= z then                    -- #67 path through the world
            table.insert(db.path, { zone = z, t = time(), level = Level() })
        end
    end
    CheckDungeon()
end

local function OnSubZoneChange()
    local sub = SubZone()
    if not sub then return end
    local key = Zone() .. ": " .. sub
    if not db.subzones[key] then db.subzones[key] = time() end -- #64 subzones visited
end

-- #83 auctions sold (and the expiries and cancels W-368 counts, through
-- ns.OnAuctionNotice). Each can come as a system message, as Forever's
-- auction house notifications (AUCTION_HOUSE_SHOW_NOTIFICATION and
-- AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION) or as more than one of them,
-- so each way is counted for a few seconds and the most any one way saw is
-- how many there were. (Two sales of the same item send the same line, so
-- these lines aren't held to the one-a-second rule below.)
local NOTICE_WINDOW = 3
local noticesNow = {} -- [kind] = { [way] = count } for notices arriving now

local function AuctionNotice(kind, way)
    local seen = noticesNow[kind]
    local first = not seen
    if first then
        seen = {}
        noticesNow[kind] = seen
    end
    seen[way] = (seen[way] or 0) + 1
    if not first then return end
    local function Settle()
        noticesNow[kind] = nil
        local n = 0
        for _, count in pairs(seen) do n = math.max(n, count) end
        if kind == "sold" then db.money.auctionsSold = db.money.auctionsSold + n end -- #83 auctions sold
        Fire("auction", kind, n)
    end
    if C_Timer and C_Timer.After then C_Timer.After(NOTICE_WINDOW, Settle) else Settle() end
end

local function AuctionLine(msg)
    return (msg:match(PATTERNS.auctionSold) and "sold") or (msg:match(PATTERNS.auctionExpired) and "expired")
        or (msg:match(PATTERNS.auctionRemoved) and "cancelled") or nil
end

-- An auction house notification's kind (Enum.AuctionHouseNotification).
local function NoticeKind(notification)
    local n, E = Num(Safe(notification)), Enum and Enum.AuctionHouseNotification
    if not n then return nil end
    local sold, expired, removed = E and E.AuctionSold or 4, E and E.AuctionExpired or 5, E and E.AuctionRemoved or 1
    return (n == sold and "sold") or (n == expired and "expired") or (n == removed and "cancelled") or nil
end

-- Exploration and other system messages can arrive as both UI_INFO_MESSAGE
-- and CHAT_MSG_SYSTEM; ignore an identical repeat within a second.
local lastSysMsg, lastSysTime = nil, 0
local function OnSystemMessage(msg)
    msg = Str(Safe(msg))
    if not msg then return end
    if msg == lastSysMsg and GetTime() - lastSysTime < 1 then return end
    lastSysMsg, lastSysTime = msg, GetTime()

    if msg:match(PATTERNS.exploreXP) then                     -- #64/#65 discovery with XP
        db.discovered = db.discovered + 1
        MarkXPSource("explore")
    elseif msg:match(PATTERNS.explore) then
        db.discovered = db.discovered + 1                     -- #64
    elseif msg == NEW_TAXI_PATH then                          -- #69 flight paths discovered
        table.insert(db.travel.flightPaths, { zone = Zone(), subzone = SubZone(), level = Level(), t = time() })
    else
        -- #95 spells and abilities learned (the %s is a spell link)
        local learned = msg:match(PATTERNS.learnSpell) or msg:match(PATTERNS.learnAbility)
            or msg:match(PATTERNS.learnRecipe)
        if learned then
            local name = learned:match("%[(.-)%]") or learned
            if not db.spells[name] then
                db.spells[name] = { level = Level(), t = time() }
            end
        end
    end
end

---------------------------------------------------------------------------
-- Money (#76-85)
---------------------------------------------------------------------------

-- Which window is open, so a money change can be attributed.
local ctx = { merchant = false, trainer = false, auction = false, mail = false,
              loot = false, lootUntil = 0, repairUntil = 0, flightUntil = 0,
              tradeskill = false } -- the open trainer teaches a profession, not your class

local function OnMoney()
    local now = Num(Call("GetMoney"))
    if not now then return end
    local M = db.money
    local last = M.last
    M.last = now
    if now > M.peak then M.peak = now end                     -- #85 peak gold
    if not last then return end
    local d = now - last
    local t = GetTime()
    -- For the other files: the change, where it happened and the new total.
    local where = (ctx.loot or t < ctx.lootUntil) and "loot" or (t < ctx.repairUntil and "repair")
        or (t < ctx.flightUntil and "flight") or (ctx.trainer and "trainer") or (ctx.auction and "auction")
        or (ctx.mail and "mail") or (ctx.merchant and "merchant") or nil
    Fire("money", d, where, now)
    if d > 0 then
        M.earned = M.earned + d                               -- #77 total earned
        if ctx.loot or t < ctx.lootUntil then
            M.loot = M.loot + d                               -- #78 gold from looting
        elseif ctx.merchant then
            M.vendor = M.vendor + d                           -- #79 vendor sales
        elseif ctx.mail then
            M.mail = M.mail + d                               -- #83 all mail income (see OnTakeMail)
        end
        -- Quest gold (#57) comes straight from QUEST_TURNED_IN.
    elseif d < 0 then
        d = -d
        M.spent = M.spent + d                                 -- #77 total spent
        if t < ctx.repairUntil or (ctx.merchant and Call("InRepairMode") == true) then
            M.repairs = M.repairs + d                         -- #81 repairs (all, or one item)
        elseif t < ctx.flightUntil then
            M.flights = M.flights + d                         -- #82 flights
        elseif ctx.trainer and not ctx.tradeskill then
            M.training = M.training + d                       -- #80 class training
        elseif ctx.auction then
            M.auctionSpent = M.auctionSpent + d               -- #83 bids, buyouts, deposits
        elseif ctx.merchant then
            M.vendorSpent = M.vendorSpent + d
        end
    end
end

-- #83 money from auction sales. Runs as a mail's money is taken, while the
-- inbox entry should still describe the mail: an auction sale carries a
-- "seller" invoice (or the "Auction successful" subject).
local AUCTION_SOLD_SUBJECT = PatternFrom(AUCTION_SOLD_MAIL_SUBJECT, "Auction successful: %s")
local function OnTakeMail(index)
    index = Num(Safe(index))
    if not index then return end
    local _, _, _, subject, money = Call("GetInboxHeaderInfo", index)
    money = Num(money)
    if not money or money <= 0 then return end
    subject = Str(subject)
    local invoice = Str(Call("GetInboxInvoiceInfo", index))
    if invoice == "seller" or (subject and subject:match(AUCTION_SOLD_SUBJECT)) then
        db.money.auctionIncome = db.money.auctionIncome + money
    end
end

---------------------------------------------------------------------------
-- Loot and gear (#86-90, #93-94, #104), gathering (#103)
---------------------------------------------------------------------------

local fishingUntil = 0

-- #103 gathering spells (Classic ranks). Their names are also looked up at
-- login, so a gathering cast is still recognised if its ID differs.
local GATHER_SPELLS = {
    [2366] = "herb", [2368] = "herb", [3570] = "herb", [11993] = "herb",
    [2575] = "mining", [2576] = "mining", [3564] = "mining", [10248] = "mining",
    [8613] = "skinning", [8617] = "skinning", [8618] = "skinning", [10768] = "skinning",
}
local gatherNames = { ["Herb Gathering"] = "herb", Mining = "mining", Skinning = "skinning" }
local gatherKind, gatherUntil = nil, 0 -- loot inside this window came from a node
local lastVein -- last mining spot, so repeat swings at one vein count once

local function SpellName(id)
    return Str(Call("C_Spell.GetSpellName", id)) or Str(Call("GetSpellInfo", id))
end

local function BuildGatherNames()
    for id, kind in pairs(GATHER_SPELLS) do
        local name = SpellName(id)
        if name then gatherNames[name] = kind end
    end
end

local function OnGather(kind)
    local G = db.gathering[kind]
    gatherKind, gatherUntil = kind, GetTime() + 5
    if kind == "mining" then
        G.swings = G.swings + 1
        -- A vein can take several swings: the same spot within a minute is
        -- the same node.
        local x, y, inst = WorldPos()
        local now = GetTime()
        if x and lastVein and inst == lastVein.inst and now - lastVein.t < 60
            and math.sqrt((x - lastVein.x) ^ 2 + (y - lastVein.y) ^ 2) < 5 then
            lastVein.t = now
            return
        end
        lastVein = x and { x = x, y = y, inst = inst, t = now } or nil
    end
    G.nodes = G.nodes + 1                                     -- #103 nodes gathered
    Fire("gather", kind)
end

local function ItemQuality(link)
    -- Forever's links carry quality as "|cnIQ<n>:" (seen in the probe log).
    local q = tonumber(link:match("|cnIQ(%d+):") or "")
    if q then return q end
    q = Num((select(3, Call("GetItemInfo", link))))
    return q or Num(Call("C_Item.GetItemQualityByID", link))
end

local function ItemLevel(link)
    return Num(Call("C_Item.GetDetailedItemLevelInfo", link))
        or Num(Call("GetDetailedItemLevelInfo", link))
end

local function OnLoot(link, count)
    local L = db.loot
    L.items = L.items + count                                 -- #86 items looted
    if GetTime() < fishingUntil then
        db.fish = db.fish + count                             -- #94 fish caught
    end
    if gatherKind and GetTime() < gatherUntil then            -- #103 what each node gave
        Inc(db.gathering[gatherKind].items, link:match("%[(.-)%]") or link, count)
    end
    local q = ItemQuality(link)
    Fire("loot", link, count, q, { fishing = GetTime() < fishingUntil,
                                   gather = GetTime() < gatherUntil and gatherKind or nil })
    if not q then return end
    Inc(L.byQuality, q, count)                                -- #87 by quality
    local ilvl = ItemLevel(link)
    local best = L.best                                       -- #88 best item: quality, then item level
    if not best or q > best.quality or (q == best.quality and (ilvl or 0) > (best.ilvl or 0)) then
        L.best = { link = link, quality = q, ilvl = ilvl, zone = Zone(), level = Level(), t = time() }
    end
    if q == 3 and not L.firstBlue then                        -- #90 first blue / epic
        L.firstBlue = { level = Level(), link = link, t = time() }
    elseif q == 4 and not L.firstEpic then
        L.firstEpic = { level = Level(), link = link, t = time() }
    end
end

local function OnLootMessage(msg)
    msg = Str(Safe(msg))
    if not msg then return end
    -- Multiple-item forms first: the single form would also match "linkx2".
    local link, n = msg:match(PATTERNS.createMulti)
    if not link then link = msg:match(PATTERNS.create) end
    if link then
        db.crafted = db.crafted + (tonumber(n) or 1)          -- #93 items crafted
        return
    end
    link, n = msg:match(PATTERNS.lootMulti)
    if not link then link = msg:match(PATTERNS.loot) end
    if link then
        OnLoot(link, tonumber(n) or 1)
    end
end

-- #89 equipped gear every 10 levels. Returns false (and saves nothing) if
-- the game hasn't loaded your equipment yet, as happens right at login.
local function GearSnapshot(level)
    local g, any = {}, false
    for slot = 1, 19 do
        g[slot] = Str(Call("GetInventoryItemLink", "player", slot))
        if g[slot] then any = true end
    end
    if not any then return false end
    db.gear[level] = g
    return true
end

local function HasGear(g)
    for slot = 1, 19 do
        if g and g[slot] then return true end
    end
    return false
end

-- #89 for a milestone level reached before tracking (or saved empty):
-- snapshot once your equipment has loaded, retrying for a short while.
-- Marked as taken late, since it isn't from the ding itself.
local function LateGearSnapshot(attempt)
    local level = Level()
    if level <= 0 or level % 10 ~= 0 or HasGear(db.gear[level]) then return end
    if GearSnapshot(level) then
        db.gear[level].late = true
    elseif attempt < 6 and C_Timer and C_Timer.After then
        C_Timer.After(5, function() LateGearSnapshot(attempt + 1) end)
    end
end

-- #104 gear worn the longest (wrapped W-396 is the /played half): the
-- /played and the levels gained while each item was equipped. Items are
-- keyed by item ID and random suffix, so moving a ring to the other finger
-- or enchanting it keeps its history. Shirts and tabards are left out:
-- they're cosmetic and would always win.
local WORN_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }
local WORN_CAP = 200          -- items kept; past this the least worn are dropped
local wornNow = {}            -- [item] = true for each item equipped right now
local wornSeen = false        -- a scan this session has found gear
local wornTick, wornProgress  -- GetTime() and LevelProgress() at the last update

-- "12345", or "12345:678" for an item with a random suffix ("of the Bear").
local function ItemKey(link)
    local fields = link:match("|Hitem:([^|]+)")
    if not fields then return nil end
    local id, suffix, i = nil, nil, 0
    for field in (fields .. ":"):gmatch("([^:]*):") do
        i = i + 1
        if i == 1 then
            id = tonumber(field)
        elseif i == 7 then -- after the enchant and the four gem fields
            suffix = tonumber(field)
            break
        end
    end
    if not id then return nil end
    if suffix and suffix ~= 0 then return id .. ":" .. suffix end
    return tostring(id)
end

-- How far through leveling you are, in levels: 12.5 is halfway through
-- level 12. Nil if XP can't be read right now.
local function LevelProgress()
    local level = Level()
    if level <= 0 then return nil end
    if level >= MAX_LEVEL then return MAX_LEVEL end
    local xp, xpMax = ReadXP()
    if not xp or not xpMax or xpMax <= 0 then return nil end
    return level + math.min(xp / xpMax, 1)
end

-- Credit everything worn right now with the time and levels since the last
-- update. Runs on every gear change, every tick and at logout.
local function UpdateWorn()
    local now, progress = GetTime(), LevelProgress()
    local dt = wornTick and (now - wornTick) or 0
    if dt < 0 or dt > 60 then dt = 0 end -- odd gaps (loading screens), as in Tick()
    wornTick = now
    -- Progress only moves forward: at a ding the level and the XP bar can
    -- update a moment apart.
    local gained = 0
    if progress and (not wornProgress or progress > wornProgress) then
        if wornProgress then gained = progress - wornProgress end
        wornProgress = progress
    end
    local level = Level()
    for key in pairs(wornNow) do
        local w = db.worn[key]
        if w then
            w.played = w.played + dt                          -- W-396 /played while worn
            w.levels = w.levels + gained                      -- #104 levels gained while worn
            if level > (w.last or 0) then w.last = level end
        end
    end
end

-- Keep the WORN_CAP most-worn items (by /played), never dropping what's on.
local function CapWorn()
    local spare, count = {}, 0
    for key, w in pairs(db.worn) do
        count = count + 1
        if not wornNow[key] then spare[#spare + 1] = { key = key, played = w.played or 0 } end
    end
    if count <= WORN_CAP then return end
    table.sort(spare, function(a, b) return a.played < b.played end)
    for i = 1, math.min(count - WORN_CAP, #spare) do db.worn[spare[i].key] = nil end
end

-- Look at what's equipped now. Returns false (changing nothing) if no gear
-- has been readable yet this session, as happens right at login.
local function ScanWorn()
    local found = {}
    for _, slot in ipairs(WORN_SLOTS) do
        local link = Str(Call("GetInventoryItemLink", "player", slot))
        local key = link and ItemKey(link)
        if key and not found[key] then found[key] = { link = link, slot = slot } end
    end
    if not wornSeen and next(found) == nil then return false end
    UpdateWorn() -- credit the gear that was on until now
    wornSeen = true
    local level, added = Level(), false
    wornNow = {}
    for key, item in pairs(found) do
        local w = db.worn[key]
        if not w then
            w = { played = 0, levels = 0, first = level, last = level } -- #104 level first worn
            db.worn[key] = w
            added = true
        end
        w.link, w.slot = item.link, item.slot -- newest link (shows enchants) and its slot
        if level > (w.last or 0) then w.last = level end
        wornNow[key] = true
    end
    if added then CapWorn() end
    return true
end

-- #104 first look at your gear this session, once the game has loaded it.
local function FirstWornScan(attempt)
    if wornSeen or ScanWorn() then return end
    if attempt < 10 and C_Timer and C_Timer.After then
        C_Timer.After(3, function() FirstWornScan(attempt + 1) end)
    end
end

---------------------------------------------------------------------------
-- Skills, professions, spells (#91-96)
---------------------------------------------------------------------------

local function OnSkillMessage(msg)
    msg = Str(Safe(msg))
    if not msg then return end
    local name, rank = msg:match(PATTERNS.skill)
    rank = tonumber(rank)
    if not name or not rank then return end
    local S = db.skills[name]
    if not S then
        S = { firstLevel = Level(), firstTime = time(), history = {} }
        db.skills[name] = S
    end
    S.rank = rank
    table.insert(S.history, { rank = rank, level = Level(), t = time() }) -- #92/#96 progression
    db.skillUps = db.skillUps + 1                             -- #96 skill-ups
    -- #91 fallback when GetProfessions isn't available: first skill-up of a
    -- known profession name marks it learned.
    if PROFESSIONS[name] and not db.professions[name] then
        db.professions[name] = { level = Level(), t = time() }
    end
    if db.professions[name] then db.professions[name].rank = rank end
end

-- #91 professions learned, plus current and max skill, via the modern
-- profession API when present.
local function ScanProfessions()
    local list = { Call("GetProfessions") }
    for _, index in pairs(list) do
        local name, _, rank, maxRank = Call("GetProfessionInfo", index)
        name = Str(name)
        if name then
            local P = db.professions[name]
            if not P then
                P = { level = Level(), t = time() }
                db.professions[name] = P
            end
            P.rank, P.maxRank = Num(rank) or P.rank, Num(maxRank) or P.maxRank
        end
    end
end

local function OnSpellLearned(spellID)
    spellID = Num(Safe(spellID))
    if not spellID then return end
    local name = Str(Call("C_Spell.GetSpellName", spellID))
    if name and not db.spells[name] then                      -- #95
        db.spells[name] = { level = Level(), t = time() }
    end
end

---------------------------------------------------------------------------
-- Group and guild (#97-99)
---------------------------------------------------------------------------

local function ScanGroup()
    local n = Num(Call("GetNumGroupMembers")) or 0
    local raid = Call("IsInRaid") == true
    local S = db.social
    for i = 1, raid and n or (n - 1) do
        local unit = (raid and "raid" or "party") .. i
        if Call("UnitIsPlayer", unit) == true and Call("UnitIsUnit", unit, "player") ~= true then
            local guid = Str(Call("UnitGUID", unit))
            if guid then
                local h = Hash(guid)
                if not S.seen[h] then                         -- #98 unique players (hashes only)
                    S.seen[h] = true
                    S.unique = S.unique + 1
                end
            end
        end
    end
end

-- Guild status can read false for a moment at login, so the first check is
-- delayed (see PLAYER_ENTERING_WORLD) and only a later false -> true change
-- counts as joining.
local guildSeeded = false
local function CheckGuild()
    local inGuild = Call("IsInGuild") == true
    local S = db.social
    if S.wasInGuild == nil then
        S.wasInGuild = inGuild
        if inGuild then S.guildBeforeTracking = true end
    elseif inGuild and not S.wasInGuild and not S.guildJoinLevel then
        S.guildJoinLevel = Level()                            -- #99 level you joined a guild
        S.guildJoinTime = time()
    end
    S.wasInGuild = inGuild
    guildSeeded = true
end

---------------------------------------------------------------------------
-- Sessions and the 5-second ticker (#6-14, #17-18, #66, #71, #84, #97)
---------------------------------------------------------------------------

local function StartSession()
    db.sessions.current = { start = time(), last = time(), startLevel = Level(), levels = 0 }
end

-- Close the open session using its last-seen time (also handles crashes).
local function CloseSession()
    local c = db.sessions.current
    if c then
        table.insert(db.sessions.list, c)                     -- #6-9 (avg/longest derived)
        db.sessions.current = nil
    end
end

local lastTick, lastPos, spot
local function Tick()
    local now = GetTime()
    local dt = lastTick and (now - lastTick) or 0
    lastTick = now
    if dt <= 0 or dt > 60 then return end -- skip odd gaps (loading screens)

    local T = db.time
    local sess = db.sessions.current
    if sess then sess.last = time() end
    db.days[date("%Y-%m-%d")] = true                          -- #17 distinct days
    Inc(db.hours, tonumber(date("%H")), dt)                   -- #18 hour-of-day heatmap

    local afk = Call("UnitIsAFK", "player") == true
    if afk then T.afk = T.afk + dt end                                     -- #10
    if Call("IsResting") == true then T.resting = T.resting + dt end       -- #11
    local onTaxi = Call("UnitOnTaxi", "player") == true
    if onTaxi then T.taxi = T.taxi + dt end                                -- #13
    -- The game reports a flight path as being mounted, so taxis don't count.
    if not onTaxi and Call("IsMounted") == true then
        T.mounted = T.mounted + dt                                         -- #14
        if not db.firstMount then                                          -- #84 first mount
            db.firstMount = { level = Level(), played = PlayedNow(), t = time() }
        end
    end
    if InGroup() then T.grouped = T.grouped + dt else T.solo = T.solo + dt end -- #97
    local Z = currentZone and db.zones[currentZone]
    if Z then Z.seconds = Z.seconds + dt end                               -- #66 time per zone
    local run = db.dungeons.current
    if run and run.active then run.active = run.active + dt end            -- #74 time in the run

    -- #108 where you spend your time: the square of the zone's map you're
    -- in, read out of combat like the distance below, so a fight's time
    -- goes to the square it started in. Not on a flight path or AFK, and
    -- nowhere the map can't place you (instances).
    if onTaxi then
        spot = nil
    elseif not afk then
        if not InCombat() then
            local mapID, x, y = MapPos()
            spot = x and y and { map = mapID, square = SpotOf(x, y) } or nil
        end
        if spot then
            local squares = db.where[spot.map]
            if not squares then squares = {}; db.where[spot.map] = squares end
            Inc(squares, spot.square, math.floor(dt + 0.5))
        end
    end

    -- #71 distance, sampled out of combat only.
    if not InCombat() then
        local x, y, inst = WorldPos()
        if x and lastPos and lastPos.inst == inst then
            local d = math.sqrt((x - lastPos.x) ^ 2 + (y - lastPos.y) ^ 2)
            if onTaxi then
                db.travel.taxi = db.travel.taxi + d
            elseif d <= TELEPORT_YARDS then
                db.travel.ground = db.travel.ground + d
            end
        end
        lastPos = x and { x = x, y = y, inst = inst } or nil
    end

    UpdateWorn()                                                           -- #104 gear worn
end

---------------------------------------------------------------------------
-- Level up (#2-5, #19-21, #76, #89)
---------------------------------------------------------------------------

local pendingDing -- level waiting for its /played reply
local dingCallbacks = {} -- other files add their totals to each snapshot (ns.OnDing)

local function OnLevelUp(level)
    level = Num(Safe(level)) or Level()
    local mapID, x, y = MapPos()
    local snapshot = {
        t = time(),                                           -- #5 real-world timestamp
        zone = Zone(), subzone = SubZone(),                   -- #19 zone
        mapID = mapID, x = x, y = y,                          -- #20 coordinates
        cause = FreshXPSource(3) or "other",                  -- #21 what caused the ding
        gold = Num(Call("GetMoney")),                         -- #76 gold at ding
        -- Running totals so the website can chart per level (with the kills
        -- of a fight still going, which count when it ends):
        xpTotal = db.xp.total, kills = db.kills.total + (fight and #fight.kills or 0), deaths = #db.deaths,
        quests = db.quests.completed, grouped = InGroup(),
    }
    db.dings[level] = snapshot
    for _, fn in ipairs(dingCallbacks) do Run("ding", fn, snapshot, level) end
    pendingDing = level
    Call("RequestTimePlayed")                                 -- #2 reply fills in .played
    local sess = db.sessions.current
    if sess then sess.levels = sess.levels + 1 end            -- #9 levels per session
    if level % 10 == 0 and not GearSnapshot(level) and C_Timer and C_Timer.After then
        C_Timer.After(3, function() GearSnapshot(level) end)  -- #89, retry if gear wasn't ready
    end
    if level >= MAX_LEVEL and not db.reachedMax then
        db.reachedMax = time()                                -- #4 first login to 60
    end
end

local function OnTimePlayed(total, thisLevel)
    total, thisLevel = Num(Safe(total)), Num(Safe(thisLevel))
    if not total then return end
    playedBase, playedAt = total, GetTime()
    local P = db.played
    P.total = total                                           -- #1 total /played
    if pendingDing then
        local d = db.dings[pendingDing]
        if d then d.played = total end                        -- #2 /played at each ding
        -- #3 /played spent on the level just finished
        if P.levelStart and thisLevel then
            LevelStats(pendingDing - 1).played = math.max(0, (total - thisLevel) - P.levelStart)
        end
        pendingDing = nil
    end
    if thisLevel then P.levelStart = total - thisLevel end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local handlers = {}

handlers.PLAYER_XP_UPDATE = function() OnXPUpdate() end
handlers.PLAYER_LEVEL_UP = function(level) OnLevelUp(level) end
handlers.TIME_PLAYED_MSG = function(total, thisLevel) OnTimePlayed(total, thisLevel) end

handlers.CHAT_MSG_COMBAT_XP_GAIN = function(msg)
    msg = Str(Safe(msg))
    if not msg then return end
    local mob = msg:match(PATTERNS.kill)
    if mob then
        MarkXPSource("kill")
        QueueKill(mob)                                        -- #26-33
    end
end

handlers.PLAYER_REGEN_DISABLED = function() StartFight() end
handlers.PLAYER_REGEN_ENABLED = function() EndFight() end

handlers.PLAYER_TARGET_CHANGED = function()
    CacheUnit("target")
    if Call("UnitCanAttack", "player", "target") ~= true then return end
    local label = UnitLabel("target")
    if label then lastHostile, lastHostileAt = label, GetTime() end
    local guid = Str(Call("UnitGUID", "target"))
    if guid then
        lastTargetGUID, lastTargetTime = guid, GetTime()
        if fight then fight.targeted[guid] = true end
    end
    if fight then
        fight.lastHostile = lastHostile
        if lastHostile then fight.names[lastHostile] = true end
    end
end

handlers.NAME_PLATE_UNIT_ADDED = function(unit)
    unit = Str(Safe(unit))
    if not unit then return end
    plates[unit] = true
    CacheUnit(unit)
end

handlers.NAME_PLATE_UNIT_REMOVED = function(unit)
    unit = Str(Safe(unit))
    if unit then plates[unit] = nil end
end

-- #41-42 dungeon bosses
handlers.ENCOUNTER_START = function(_, name)
    name = Str(Safe(name))
    if not name then return end
    db.bosses[name] = db.bosses[name] or { attempts = 0, kills = 0, wipes = 0 }
    local B = db.bosses[name]
    B.attempts = B.attempts + 1
end

handlers.ENCOUNTER_END = function(_, name, _, _, success)
    name, success = Str(Safe(name)), Safe(success)
    if not name then return end
    db.bosses[name] = db.bosses[name] or { attempts = 0, kills = 0, wipes = 0 }
    local B = db.bosses[name]
    if success == 1 or success == true then
        B.kills = B.kills + 1
        local run = db.dungeons.current
        if run then run.bosses = run.bosses + 1 end
    else
        B.wipes = B.wipes + 1
    end
end

-- #43 PvP honorable kills (lifetime count from the game)
handlers.PLAYER_PVP_KILLS_CHANGED = function()
    local hk = Num(Call("GetPVPLifetimeStats"))
    if hk then db.pvp.honorableKills = hk end
end

-- Deaths
handlers.PLAYER_DEAD = function() OnDeath() end
-- #101 a loading screen ends any fall (a zeppelin, a portal or a summon in
-- mid-air isn't a fall to time).
handlers.PLAYER_LEAVING_WORLD = function() fallStart = nil end

handlers.PLAYER_ALIVE = function()
    local ghost = Call("UnitIsGhost", "player")
    if ghost == true then
        death.released = GetTime()
        -- #72 graveyard. Position lags the release by a moment (probe), so
        -- read where we are after the teleport.
        if C_Timer and C_Timer.After then
            C_Timer.After(2, function()
                local key = Zone() .. ": " .. (SubZone() or "?")
                Inc(db.graveyards, key)
                if death.rec then death.rec.graveyard = key end
            end)
        end
    elseif ghost == false and death.rec then
        -- Alive without becoming a ghost: rezzed where we died.
        FinishDeath(death.accepted or (death.hint == "player rez" and "player rez") or "self-res/other")
    end
end

handlers.PLAYER_UNGHOST = function()
    FinishDeath(death.accepted or death.hint or "unknown")
end

handlers.CONFIRM_XP_LOSS = function() death.hint = "spirit healer" end
handlers.CORPSE_IN_RANGE = function() death.hint = "corpse run" end
handlers.CORPSE_OUT_OF_RANGE = function()
    if death.hint == "corpse run" then death.hint = nil end
end
handlers.RESURRECT_REQUEST = function() death.hint = "player rez" end -- rezzer's name not stored

-- Quests
handlers.QUEST_ACCEPTED = function(a, b)
    -- Modern: (questID). Classic: (questLogIndex, questID).
    local questID = Num(Safe(b)) or Num(Safe(a))
    local Q = db.quests
    Q.accepted = Q.accepted + 1                               -- #58 quests accepted
    if questID then
        Q.open[questID] = { t = time(), level = Level(), tag = QuestTag(questID) }
    end
end

handlers.QUEST_TURNED_IN = function(questID, xp, money)
    questID, xp, money = Num(Safe(questID)), Num(Safe(xp)), Num(Safe(money))
    local Q = db.quests
    Q.completed = Q.completed + 1                             -- #53 quests completed
    local L = LevelStats()
    L.quests = L.quests + 1                                   -- #54 per level
    Inc(Q.byZone, Zone())                                     -- #55 per zone
    if xp then Q.xp = Q.xp + xp end                           -- #56 quest XP
    if money then Q.money = Q.money + money end               -- #57 quest gold
    MarkXPSource("quest")
    if not questID then return end
    local open = Q.open[questID]
    local tag = open and open.tag or QuestTag(questID)
    if tag then Inc(Q.byTag, tag) end                         -- #61 group/elite, #62 dungeon
    if open then
        local held = time() - open.t                          -- #60 longest-held quest
        if not Q.longest or held > Q.longest.seconds then
            Q.longest = { questID = questID, seconds = held }
        end
        Q.open[questID] = nil
    end
end

-- Zones and exploration
handlers.ZONE_CHANGED_NEW_AREA = function() OnZoneChange(); OnSubZoneChange() end
handlers.ZONE_CHANGED = function() OnSubZoneChange() end
handlers.ZONE_CHANGED_INDOORS = function() OnSubZoneChange() end
handlers.UI_INFO_MESSAGE = function(_, msg) OnSystemMessage(msg) end
handlers.CHAT_MSG_SYSTEM = function(msg)
    local text = Str(Safe(msg))
    local kind = text and AuctionLine(text)
    if kind then AuctionNotice(kind, "chat") else OnSystemMessage(msg) end -- #83
end
handlers.AUCTION_HOUSE_SHOW_NOTIFICATION = function(notification)
    local kind = NoticeKind(notification)
    if kind then AuctionNotice(kind, "notice") end            -- #83
end
handlers.AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION = function(notification)
    local kind = NoticeKind(notification)
    if kind then AuctionNotice(kind, "formatted") end         -- #83
end

-- Your own casts: hearthstone, gathering and fishing.
handlers.UNIT_SPELLCAST_SUCCEEDED = function(_, _, spellID)
    spellID = Num(Safe(spellID))
    if not spellID then return end
    if fallStart then
        for _, id in ipairs(SLOW_FALL) do
            if spellID == id then fallSlowed = true end       -- #101 Slow Fall cast on the way down
        end
    end
    if spellID == HEARTHSTONE then
        db.travel.hearths = db.travel.hearths + 1             -- #68 hearthstone uses
    end
    local kind = GATHER_SPELLS[spellID] or gatherNames[SpellName(spellID) or ""]
    if kind then OnGather(kind) end                           -- #103 gathering
end

handlers.UNIT_SPELLCAST_CHANNEL_START = function(_, _, spellID)
    spellID = Num(Safe(spellID))
    if spellID and FISHING[spellID] then
        fishingUntil = GetTime() + 30 -- #94 bobber window; loot inside it is fish
    end
end

-- Money and windows
handlers.PLAYER_MONEY = function() OnMoney() end
handlers.MERCHANT_SHOW = function() ctx.merchant = true end
handlers.MERCHANT_CLOSED = function() ctx.merchant = false end
handlers.TRAINER_SHOW = function()
    ctx.trainer, ctx.tradeskill = true, Call("IsTradeskillTrainer") == true
end
handlers.TRAINER_CLOSED = function() ctx.trainer = false end
handlers.AUCTION_HOUSE_SHOW = function() ctx.auction = true end
handlers.AUCTION_HOUSE_CLOSED = function() ctx.auction = false end
handlers.MAIL_SHOW = function() ctx.mail = true end
handlers.MAIL_CLOSED = function() ctx.mail = false end

-- Modern clients may report those windows through the interaction manager
-- instead; this keeps the same flags in sync either way.
local function InteractionKey(itype)
    local E = Enum and Enum.PlayerInteractionType
    itype = Safe(itype)
    if not E or itype == nil then return end
    if itype == E.Merchant then return "merchant" end
    if itype == E.Trainer then return "trainer" end
    if itype == E.Auctioneer then return "auction" end
    if itype == E.MailInfo then return "mail" end
end
handlers.PLAYER_INTERACTION_MANAGER_FRAME_SHOW = function(itype)
    local key = InteractionKey(itype)
    if key then ctx[key] = true end
    if key == "trainer" then ctx.tradeskill = Call("IsTradeskillTrainer") == true end
end
handlers.PLAYER_INTERACTION_MANAGER_FRAME_HIDE = function(itype)
    local key = InteractionKey(itype)
    if key then ctx[key] = false end
end

-- Loot
handlers.LOOT_OPENED = function()
    ctx.loot = true
    if Call("IsFishingLoot") == true then fishingUntil = GetTime() + 5 end -- #94
end
handlers.LOOT_CLOSED = function()
    ctx.loot = false
    ctx.lootUntil = GetTime() + 2 -- money can land just after the window closes
    gatherUntil = math.min(gatherUntil, GetTime() + 1) -- so the next mob's loot isn't counted as a node's
end
handlers.CHAT_MSG_LOOT = function(msg) OnLootMessage(msg) end
handlers.PLAYER_EQUIPMENT_CHANGED = function() ScanWorn() end -- #104 gear worn

-- Skills and spells
handlers.CHAT_MSG_SKILL = function(msg) OnSkillMessage(msg) end
handlers.SKILL_LINES_CHANGED = function() ScanProfessions() end
handlers.LEARNED_SPELL_IN_TAB = function(spellID) OnSpellLearned(spellID) end
handlers.LEARNED_SPELL_IN_SKILL_LINE = function(spellID) OnSpellLearned(spellID) end

-- Group and guild
handlers.GROUP_ROSTER_UPDATE = function() ScanGroup() end
handlers.PLAYER_GUILD_UPDATE = function()
    if guildSeeded then CheckGuild() end
end

handlers.PLAYER_LOGOUT = function()
    EndFight()
    local sess = db.sessions.current
    if sess then sess.last = time() end -- closed on next login
    UpdateWorn()                        -- #104 credit the gear worn until now
end

---------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------

local frame = CreateFrame("Frame")
local unknownEvents, missingHooks = {}, {}

-- Unit events we only want for one unit, not every nearby unit.
local UNIT_FILTERS = { UNIT_SPELLCAST_SUCCEEDED = "player", UNIT_SPELLCAST_CHANNEL_START = "player" }

-- Listeners added by the other files (class and wrapped trackers). They
-- share this frame's event registrations and run after the main handler.
local listeners = {}
local loadCallbacks = {}
local eventsRegistered = false

local function RegisterOne(event)
    -- Unknown event names throw on modern clients; skip them quietly
    -- (several events here are Classic-only or modern-only).
    local unit = UNIT_FILTERS[event]
    local ok
    if unit then
        ok = pcall(frame.RegisterUnitEvent, frame, event, unit)
    else
        ok = pcall(frame.RegisterEvent, frame, event)
    end
    if not ok then table.insert(unknownEvents, event) end
end

local function RegisterEvents()
    for event in pairs(handlers) do RegisterOne(event) end
    for event in pairs(listeners) do
        if not handlers[event] then RegisterOne(event) end
    end
    eventsRegistered = true
end

-- Listen to an event alongside the main handlers. `unit` limits a unit
-- event to one unit ("player", "pet", "target"). Works before or after load.
function ns.Listen(event, fn, unit)
    local first = not listeners[event]
    listeners[event] = listeners[event] or {}
    table.insert(listeners[event], fn)
    if unit and not UNIT_FILTERS[event] then UNIT_FILTERS[event] = unit end
    if eventsRegistered and first and not handlers[event] then RegisterOne(event) end
end

function ns.OnLoad(fn) table.insert(loadCallbacks, fn) end -- runs once saved data is ready
function ns.OnDing(fn) table.insert(dingCallbacks, fn) end -- adds fields to each ding snapshot

local function Dispatch(event, ...)
    local list = listeners[event]
    if not list then return end
    for _, fn in ipairs(list) do Run(event, fn, ...) end
end

-- Post-hook a function if it exists. hooksecurefunc runs after Blizzard's
-- code and doesn't taint it.
local function Hook(path, fn)
    local ns, fname = path:match("^([%w_]+)%.([%w_]+)$")
    if ns then
        local t = _G[ns]
        if type(t) == "table" and type(t[fname]) == "function" then
            hooksecurefunc(t, fname, fn)
            return true
        end
    elseif type(_G[path]) == "function" then
        hooksecurefunc(path, fn)
        return true
    end
    table.insert(missingHooks, path)
    return false
end

local function InstallHooks()
    -- #49 resurrection type
    Hook("RetrieveCorpse", function() OnRezAccept("corpse run") end)
    Hook("AcceptResurrect", function() OnRezAccept("player rez") end)
    Hook("AcceptXPLoss", function() OnRezAccept("spirit healer") end)
    Hook("C_DeathInfo.UseSelfResurrectOption", function() OnRezAccept("self-res") end)
    -- #59 quests abandoned. Hook only one abandon function so nothing
    -- counts twice.
    Hook("C_QuestLog.SetAbandonQuest", function()
        pendingAbandon = Num(Call("C_QuestLog.GetAbandonQuest"))
    end)
    if not Hook("C_QuestLog.AbandonQuest", OnAbandon) then
        Hook("AbandonQuest", OnAbandon)
    end
    -- #81 repairs
    Hook("RepairAllItems", function() ctx.repairUntil = GetTime() + 3 end)
    -- #70 flights taken, #82 gold on flights
    Hook("TakeTaxiNode", function()
        db.travel.flights = db.travel.flights + 1
        ctx.flightUntil = GetTime() + 3
    end)
    -- #100 times jumped. Also tells the fall timer (#101) a fall began with
    -- a jump; holding the key keeps jumping, so track when it's released.
    Hook("JumpOrAscendStart", function()
        db.social.jumps = db.social.jumps + 1
        lastJump, jumpHeld = GetTime(), true
    end)
    Hook("AscendStop", function() jumpHeld = false end)
    -- #83 auction sale proceeds, read as mail money is taken
    Hook("TakeInboxMoney", OnTakeMail)
    Hook("AutoLootMailItem", OnTakeMail)
end

local ticker
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= ADDON_NAME then return end
        self:UnregisterEvent("ADDON_LOADED")
        local saved = type(JourneyTrackerDB) == "table" and JourneyTrackerDB or {}
        local upgraded, problem = UpgradeSavedData(saved)
        if not upgraded then
            -- The saved data stays exactly as it was and nothing is tracked
            -- this session, so a half-migrated table is never written.
            print(PREFIX .. " |cffff5555Couldn't update your saved data (" .. problem .. ").|r"
                .. " Your data hasn't been changed, and tracking is off this session.")
            return
        end
        if upgraded ~= saved and next(saved) ~= nil then
            -- Safety net: the data as it was before this upgrade.
            JourneyTrackerBackup = type(JourneyTrackerBackup) == "table" and JourneyTrackerBackup or {}
            JourneyTrackerBackup.beforeUpgrade = { takenAt = time(), addonVersion = VERSION,
                fromVersion = tonumber(saved.schemaVersion) or 0, data = Copy(saved) }
        end
        JourneyTrackerDB = upgraded
        db = upgraded
        if db.characterId == nil then db.characterId = NewCharacterId() end -- set once, never replaced
        if (tonumber(db.schemaVersion) or 0) > SCHEMA_VERSION then
            print(PREFIX, "Your saved data is from a newer version of Journey Tracker. Please update the addon.")
        end
        Fill(db, DEFAULTS)
        if db.firstSeen == 0 then db.firstSeen = time() end   -- #4
        RegisterEvents()
        InstallHooks()
        if IsFalling then self:SetScript("OnUpdate", WatchFalling) end -- #101-102
        for _, fn in ipairs(loadCallbacks) do Run("load", fn, db) end
        return
    end

    if not db then return end -- saved data couldn't be loaded; nothing to track

    if event == "PLAYER_ENTERING_WORLD" then
        local isInitialLogin, isReload = ...
        if isInitialLogin then
            CloseSession()                                    -- #6 new play session
            StartSession()
        elseif not db.sessions.current then
            StartSession()
        end
        if isInitialLogin or isReload then
            local _, class = Call("UnitClass", "player")
            local _, race = Call("UnitRace", "player")
            db.char.name = Str(Call("UnitName", "player"))
            db.char.realm = Str(Call("GetRealmName"))
            db.char.class, db.char.race = Str(class), Str(race)
            SeedXP()
            db.money.last = Num(Call("GetMoney"))             -- don't count offline changes
            Call("RequestTimePlayed")                         -- #1 baseline /played
            ScanGroup()
            ScanProfessions()
            BuildGatherNames()
            if C_Timer and C_Timer.After then
                C_Timer.After(10, CheckGuild)                 -- #99, after guild data loads
            end
            -- #89 a milestone level reached before tracking gets its gear
            -- snapshot once your equipment has loaded.
            if C_Timer and C_Timer.After then
                C_Timer.After(5, function() LateGearSnapshot(1) end)
            end
            FirstWornScan(1)                                  -- #104 what you're wearing now
        end
        OnZoneChange()
        OnSubZoneChange()
        if not ticker and C_Timer and C_Timer.NewTicker then
            ticker = C_Timer.NewTicker(TICK_SECONDS, Tick)
        end
        Dispatch(event, ...)
        return
    end

    local handler = handlers[event]
    if handler then handler(...) end
    Dispatch(event, ...)
end)

---------------------------------------------------------------------------
-- /jt: quick in-game summary for testing
---------------------------------------------------------------------------

local function Summary()
    local p = function(...) print(PREFIX, ...) end
    p("Played:", FormatDuration(PlayedNow() or db.played.total),
        "| level", Level(), "| dings logged:", (function()
            local n = 0 for _ in pairs(db.dings) do n = n + 1 end return n end)())

    local list = db.sessions.list
    local total, longest = 0, 0
    for _, s in ipairs(list) do
        local len = (s.last or s.start) - s.start
        total, longest = total + len, math.max(longest, len)
    end
    p("Sessions:", #list + (db.sessions.current and 1 or 0),
        "| avg", FormatDuration(#list > 0 and total / #list or 0),
        "| longest", FormatDuration(longest))

    local X = db.xp
    p(string.format("XP: %d total | kill %d, quest %d, explore %d, other %d | rested used %d",
        X.total, X.kill, X.quest, X.explore, X.other, X.restedUsed))

    local K, C = db.kills, db.combat
    local top, topN = nil, 0
    for name, n in pairs(K.byName) do
        if n > topN then top, topN = name, n end
    end
    p(string.format("Kills: %d (most: %s x%d) | fights %d, longest %.0fs, multi-pulls %d, ambush mobs %d",
        K.total, top or "-", topN, C.fights, C.longest, C.multiPulls, C.ambushMobs))

    local byZone = {}
    for _, d in ipairs(db.deaths) do Inc(byZone, d.zone or "?") end
    local dz, dzN = nil, 0
    for z, n in pairs(byZone) do
        if n > dzN then dz, dzN = z, n end
    end
    local rez = {}
    for how, n in pairs(db.rez) do table.insert(rez, how .. " " .. n) end
    p(string.format("Deaths: %d (deadliest: %s) | rez: %s | dead %s",
        #db.deaths, dz or "-", #rez > 0 and table.concat(rez, ", ") or "-",
        FormatDuration(db.time.dead)))

    local Q = db.quests
    p(string.format("Quests: %d done, %d accepted, %d abandoned | %d XP, %s",
        Q.completed, Q.accepted, Q.abandoned, Q.xp, FormatMoney(Q.money)))

    local M = db.money
    p("Gold: earned", FormatMoney(M.earned), "| spent", FormatMoney(M.spent),
        "| loot", FormatMoney(M.loot), "| peak", FormatMoney(M.peak))

    local zones = 0
    for _ in pairs(db.zones) do zones = zones + 1 end
    p(string.format("Travel: %d zones | %.0f yd ground, %.0f yd taxi | %d hearths, %d flights | %d jumps",
        zones, db.travel.ground, db.travel.taxi, db.travel.hearths, db.travel.flights, db.social.jumps))

    p(string.format("Loot: %d items | crafted %d | fish %d | skill-ups %d",
        db.loot.items, db.crafted, db.fish, db.skillUps))

    local F, G = db.falls, db.gathering
    p(string.format("Falls: %.0f yd total, longest survived %.0f yd | Gathered: %d herbs, %d ore nodes, %d skins",
        F.total, F.longestSurvived and F.longestSurvived.yards or 0,
        G.herb.nodes, G.mining.nodes, G.skinning.nodes))
end

local function Status()
    print(PREFIX, "version " .. VERSION .. ", data version " .. tostring(db.schemaVersion)
        .. ", character ID " .. tostring(db.characterId))
    print(PREFIX, "events not on this client:",
        #unknownEvents > 0 and table.concat(unknownEvents, ", ") or "none")
    print(PREFIX, "functions not on this client:",
        #missingHooks > 0 and table.concat(missingHooks, ", ") or "none")
    print(PREFIX, "game functions asked for but not on this client:",
        #missingAPIList > 0 and table.concat(missingAPIList, ", ") or "none")
    for _, err in ipairs(hookErrors) do print(PREFIX, "tracker error:", err) end
    if ns.WrappedErrors then
        for _, err in ipairs(ns.WrappedErrors()) do print(PREFIX, "tracker error:", err) end
    end
end

-- Shared with the other files (class and wrapped trackers, UI).
ns.GetDB = function() return db end
ns.FormatDuration, ns.FormatMoney = FormatDuration, FormatMoney
ns.PlayedNow, ns.Level, ns.Zone, ns.SubZone = PlayedNow, Level, Zone, SubZone
ns.InGroup, ns.InCombat = InGroup, InCombat
ns.IsSecret, ns.Safe, ns.Call, ns.Str, ns.Num, ns.Inc = IsSecret, Safe, Call, Str, Num, Inc
ns.Fill, ns.Hook, ns.ctx, ns.PATTERNS = Fill, Hook, ctx, PATTERNS
ns.MAX_LEVEL, ns.PROFESSIONS = MAX_LEVEL, PROFESSIONS
ns.PatternFrom, ns.MapPos, ns.WorldPos, ns.ItemQuality = PatternFrom, MapPos, WorldPos, ItemQuality
-- What this file records, for the other files: fn(kill), fn(fight) as it
-- ends, fn(deathRecord, extra), fn(fall, airTime), fn(link, count,
-- quality, extra), fn(moneyChange, where, total), fn(kind) for each new
-- node gathered (herb, mining, skinning).
function ns.OnKill(fn) table.insert(hooks.kill, fn) end
function ns.OnGather(fn) table.insert(hooks.gather, fn) end
function ns.OnFightEnd(fn) table.insert(hooks.fight, fn) end
function ns.OnDeathRecord(fn) table.insert(hooks.death, fn) end
function ns.OnFall(fn) table.insert(hooks.fall, fn) end
function ns.OnLootItem(fn) table.insert(hooks.loot, fn) end
function ns.OnMoneyChange(fn) table.insert(hooks.money, fn) end
function ns.OnAuctionNotice(fn) table.insert(hooks.auction, fn) end -- (kind, count): "sold", "expired", "cancelled"
function ns.MobInfo(name) return name and mobInfo[name] end
function ns.PlayerInfo(name) return name and playerInfo[name] end
function ns.CurrentFight() return fight end
function ns.HookErrors() return hookErrors end
ns.VERSION, ns.SCHEMA_VERSION = VERSION, SCHEMA_VERSION
ns.PrintSummary = Summary

-- /journey (or /jt) opens the window. Subcommands: version, backup, export,
-- summary (print to chat), status (events/functions this client lacks),
-- class (which of your class's tracked spells the game knows), stats (what's
-- been read from the Statistics pane), screenshots (a screenshot at every
-- ding, on or off), options (the window's Options page), and the dev-only
-- testexport and statprobe.
SLASH_JOURNEYTRACKER1 = "/journey"
SLASH_JOURNEYTRACKER2 = "/jt"
SlashCmdList.JOURNEYTRACKER = function(msg)
    local cmd = (msg or ""):lower():match("^%s*(%S*)")
    if cmd == "version" then
        print(PREFIX, "Journey Tracker " .. VERSION .. ", data version "
            .. tostring(db and db.schemaVersion or SCHEMA_VERSION))
        return
    end
    if not db then
        print(PREFIX, "Tracking is off this session because your saved data couldn't be updated.")
        return
    end
    if cmd == "backup" then
        Backup()
    elseif cmd == "export" and ns.Export then
        ns.Export(tonumber((msg or ""):match("^%s*%S+%s+(%d+)")))       -- #106 /journey export 30
    elseif cmd == "testexport" and ns.TestExport then
        ns.TestExport()
    elseif cmd == "statprobe" and ns.StatProbe then
        ns.StatProbe()                                        -- W-501 statistics API probe
    elseif cmd == "stats" and ns.StatsStatus then
        ns.StatsStatus()                                      -- W-502..W-507 statistics snapshots
    elseif cmd == "status" then
        Status()
    elseif cmd == "class" and ns.ClassStatus then
        ns.ClassStatus()
    elseif cmd == "screenshots" and ns.ToggleDingScreenshots then
        ns.ToggleDingScreenshots()                            -- W-494 screenshot at every ding
    elseif cmd == "options" and ns.ShowOptions then
        ns.ShowOptions()
    elseif cmd == "summary" or not ns.ToggleUI then
        Summary()
    else
        ns.ToggleUI()
    end
end
