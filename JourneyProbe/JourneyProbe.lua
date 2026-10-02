-- JourneyProbe: throwaway probe addon.
-- Logs what events/APIs return so we can see which values are readable and
-- which come back as "secret" under the Midnight-style API.
--
-- Golden rule in this file: every value that came from the game goes through
-- Display() BEFORE we compare, concatenate, index, or do math with it.

local ADDON_NAME = ...
local MAX_LOG = 20000      -- combat ticks add a lot of entries, so keep plenty
local TICK_SECONDS = 2     -- how often to snapshot player/target during combat
local GCD_SPELL_ID = 61304 -- the global-cooldown "spell" on modern clients
local PREFIX = "|cff33ff99JP|r"

-- Sentinels: API() returns these instead of erroring.
local MISSING = {} -- function doesn't exist on this client
local ERRORED = {} -- function exists but threw an error

-- Fields we pull out of table-returning APIs.
local AURA_KEYS = { "name", "spellId", "duration", "expirationTime", "sourceUnit" }
local CD_KEYS   = { "startTime", "duration", "isEnabled" }

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

-- issecretvalue() is the Midnight-era secret check (confirmed present on
-- Forever, but still guarded in case a build drops it).
local function IsSecret(v)
    if issecretvalue and issecretvalue(v) then
        return true
    end
    return false
end

-- Find a global function by name. Supports "C_Namespace.Func" names.
local function Lookup(name)
    local ns, fname = name:match("^([%w_]+)%.([%w_]+)$")
    if ns then
        local t = _G[ns]
        return type(t) == "table" and t[fname] or nil
    end
    return _G[name]
end

local function Unwrap(ok, ...)
    if ok then return ... end
    return ERRORED
end

-- Call an API by name, safely. Missing functions return MISSING and errors
-- return ERRORED, so one bad API never breaks the rest of the probe.
local function API(name, ...)
    local fn = Lookup(name)
    if type(fn) ~= "function" then
        return MISSING
    end
    return Unwrap(pcall(fn, ...))
end

-- Turn any value into a safe display string. The secret check comes first,
-- so nothing below it ever touches a secret value.
-- Returns: text, wasSecret
local function Display(v)
    if IsSecret(v) then
        return "SECRET", true
    end
    if v == MISSING then return "MISSING", false end
    if v == ERRORED then return "ERROR", false end
    if v == nil then return "nil", false end
    return tostring(v), false
end

local function InCombat()
    return InCombatLockdown() and true or false
end

---------------------------------------------------------------------------
-- Logging
---------------------------------------------------------------------------

-- One "record" per event firing. Each field becomes its own log entry, and
-- the record collects the display strings for the single chat line.
local function NewRecord(event, quiet)
    JourneyProbeDB.serial = (JourneyProbeDB.serial or 0) + 1
    return { event = event, n = JourneyProbeDB.serial, parts = {}, quiet = quiet }
end

local function Append(entry)
    local log = JourneyProbeDB.log
    log[#log + 1] = entry
    -- Drop oldest entries past the cap.
    while #log > MAX_LOG do
        table.remove(log, 1)
    end
end

-- Record a single field. `value` may be secret; it only ever goes to Display().
local function AddField(rec, field, value)
    local text, secret = Display(value)
    Append({
        t  = time(),        -- wall clock (epoch seconds)
        n  = rec.n,         -- event firing serial, groups fields together
        ev = rec.event,
        f  = field,
        v  = text,          -- display string, or "SECRET"
        s  = secret or nil, -- only stored when true, keeps SavedVariables small
        c  = InCombat(),    -- InCombatLockdown() at this moment
    })
    rec.parts[#rec.parts + 1] = field .. "=" .. text
end

-- Log selected keys of a table-returning API (auras, cooldowns).
-- The table itself is checked for secrecy before we index it, and each
-- index is pcall'd in case Forever hands back a restricted table.
local function AddTable(rec, prefix, tbl, keys)
    if IsSecret(tbl) or tbl == nil or tbl == MISSING or tbl == ERRORED
        or type(tbl) ~= "table" then
        AddField(rec, prefix, tbl)
        return
    end
    for _, key in ipairs(keys) do
        local ok, v = pcall(function() return tbl[key] end)
        if ok then
            AddField(rec, prefix .. "." .. key, v)
        else
            AddField(rec, prefix .. "." .. key, ERRORED)
        end
    end
end

-- Print the compact chat line for a record (if printing is on).
-- Quiet records (combat ticks) are logged but never printed.
local function Finish(rec)
    if rec.quiet or not JourneyProbeDB.print then return end
    local tag = InCombat() and " |cffff5555[C]|r" or ""
    print(PREFIX .. " " .. rec.event .. tag .. " " .. table.concat(rec.parts, " "))
end

---------------------------------------------------------------------------
-- Snapshot builders (shared by several events)
---------------------------------------------------------------------------

-- Everything we can think of to read about one unit. `p` is a field prefix
-- such as "t." for target or "p." for player.
local function AddUnit(rec, unit, p)
    local exists = API("UnitExists", unit)
    if IsSecret(exists) then
        AddField(rec, p .. "exists", exists) -- logs SECRET; still try the rest
    elseif not exists then
        AddField(rec, p .. "exists", false)
        return
    end

    -- Parentheses keep only the first return value.
    AddField(rec, p .. "name",      (API("UnitName", unit)))
    AddField(rec, p .. "level",     (API("UnitLevel", unit)))
    AddField(rec, p .. "class",     (API("UnitClassification", unit)))
    AddField(rec, p .. "guid",      (API("UnitGUID", unit)))
    AddField(rec, p .. "canAttack", (API("UnitCanAttack", "player", unit)))
    AddField(rec, p .. "inCombat",  (API("UnitAffectingCombat", unit)))
    AddField(rec, p .. "health",    (API("UnitHealth", unit)))
    AddField(rec, p .. "healthMax", (API("UnitHealthMax", unit)))
    AddField(rec, p .. "power",     (API("UnitPower", unit)))
    AddField(rec, p .. "powerMax",  (API("UnitPowerMax", unit)))
    AddField(rec, p .. "powerType", (select(2, API("UnitPowerType", unit))))
    -- Newer percentage APIs; maybe readable where raw values are SECRET.
    AddField(rec, p .. "healthPct", (API("UnitHealthPercent", unit)))
    AddField(rec, p .. "powerPct",  (API("UnitPowerPercent", unit)))
    AddField(rec, p .. "dead",      (API("UnitIsDeadOrGhost", unit)))
    AddField(rec, p .. "ghost",     (API("UnitIsGhost", unit)))
    AddField(rec, p .. "reaction",  (API("UnitReaction", unit, "player")))
    AddField(rec, p .. "creature",  (API("UnitCreatureType", unit)))
    AddField(rec, p .. "isPlayer",  (API("UnitIsPlayer", unit)))
    AddField(rec, p .. "threat",    (API("UnitThreatSituation", "player", unit)))
    -- First buff and first debuff. C_UnitAuras is the modern aura API.
    AddTable(rec, p .. "buff1",
        API("C_UnitAuras.GetAuraDataByIndex", unit, 1, "HELPFUL"), AURA_KEYS)
    AddTable(rec, p .. "debuff1",
        API("C_UnitAuras.GetAuraDataByIndex", unit, 1, "HARMFUL"), AURA_KEYS)
end

-- Rested state and XP bar.
local function AddRested(rec)
    AddField(rec, "resting",  (API("IsResting")))         -- in an inn/city?
    AddField(rec, "restedXP", (API("GetXPExhaustion")))   -- rested pool; nil = none
    local id, name, mult = API("GetRestState")            -- 1 = rested, 2 = normal
    AddField(rec, "restState", id)
    AddField(rec, "restName", name)
    AddField(rec, "restMult", mult)
    AddField(rec, "xp",    (API("UnitXP", "player")))
    AddField(rec, "xpMax", (API("UnitXPMax", "player")))
end

-- Where we are.
local function AddZone(rec)
    AddField(rec, "zone",    (API("GetZoneText")))
    AddField(rec, "subzone", (API("GetSubZoneText")))
    AddField(rec, "mapID",   (API("C_Map.GetBestMapForUnit", "player")))
    local inInstance, instType = API("IsInInstance")
    AddField(rec, "inInstance", inInstance)
    AddField(rec, "instType", instType)
    local instName, _, _, diffName = API("GetInstanceInfo")
    AddField(rec, "instName", instName)
    AddField(rec, "difficulty", diffName)
end

-- Weapon/defense skills. GetSkillLineInfo is the Classic-era skill API; I'm
-- not sure Forever's modern API keeps it, so everything is guarded. Only
-- skills whose rank changed since the last scan are logged.
local skillCache = {}
local function AddSkillChanges(rec)
    local num = API("GetNumSkillLines")
    if IsSecret(num) or type(num) ~= "number" then
        -- SECRET, MISSING or ERROR. rec is nil during the silent login seed.
        if rec then
            AddField(rec, "numSkills", num)
        end
        return
    end
    local changed = 0
    for i = 1, num do
        local name, isHeader, _, rank, _, _, maxRank = API("GetSkillLineInfo", i)
        if IsSecret(name) or IsSecret(isHeader) or IsSecret(rank) then
            if rec then
                AddField(rec, "skill" .. i, "SECRET")
                changed = changed + 1
            end
        elseif type(name) == "string" and not isHeader then
            if skillCache[name] ~= rank then
                -- First scan only seeds the cache (rec == nil).
                if rec then
                    AddField(rec, name, Display(rank) .. "/" .. Display(maxRank))
                    changed = changed + 1
                end
                skillCache[name] = rank
            end
        end
    end
    if rec and changed == 0 then
        AddField(rec, "changed", "none")
    end
end

---------------------------------------------------------------------------
-- Combat ticker: quiet snapshots every TICK_SECONDS while in combat
---------------------------------------------------------------------------

local ticker
local function StartTicker()
    -- C_Timer is standard on modern clients; guarded anyway.
    if ticker or not (C_Timer and C_Timer.NewTicker) then return end
    ticker = C_Timer.NewTicker(TICK_SECONDS, function()
        local rec = NewRecord("COMBAT_TICK", true)
        AddUnit(rec, "player", "p.")
        AddUnit(rec, "target", "t.")
        -- C_Spell.GetSpellCooldown returns a table on modern clients.
        AddTable(rec, "gcd", API("C_Spell.GetSpellCooldown", GCD_SPELL_ID), CD_KEYS)
        Finish(rec)
    end)
end

local function StopTicker()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

local combatStart       -- GetTime() when combat began
local lastXP            -- last readable UnitXP("player") value
local unknownEvents = {} -- events this client refused to register

---------------------------------------------------------------------------
-- Event handlers
---------------------------------------------------------------------------

local handlers = {}

---------------------------------------------------------------------------
-- Power spent tracking
--
-- UnitPower("player") is SECRET on Forever (even out of combat), so instead
-- we add up the cost of every spell we cast, using the readable spellID from
-- UNIT_SPELLCAST_SUCCEEDED and C_Spell.GetSpellPowerCost. That counts power
-- SPENT; regen and rage generation can't be seen this way.
---------------------------------------------------------------------------

local PULL_WINDOW = 3 -- seconds: a cast this soon before combat counts as the pull

local spend = {
    fight = {},   -- [powerName] = amount spent this fight
    session = {}, -- [powerName] = amount spent since login/reload
    casts = 0,    -- casts this fight
    recent = {},  -- out-of-combat casts: { t, name, amount }, for the pull
}

local function AddSpend(name, amount, inFight)
    spend.session[name] = (spend.session[name] or 0) + amount
    if inFight then
        spend.fight[name] = (spend.fight[name] or 0) + amount
    end
end

-- Log the cost(s) of a spell and add readable ones to the totals.
local function AddSpellCosts(rec, spellID)
    if IsSecret(spellID) then
        AddField(rec, "cost", spellID)
        return
    end
    -- Modern API: returns an array of cost tables (a spell can cost more
    -- than one power type). Unsure of Forever's version, so guarded.
    local costs = API("C_Spell.GetSpellPowerCost", spellID)
    if IsSecret(costs) or type(costs) ~= "table" then
        AddField(rec, "cost", costs) -- SECRET, MISSING, ERROR or nil
        return
    end
    if #costs == 0 then
        AddField(rec, "cost", "free")
        return
    end
    local inFight = InCombat()
    if inFight then spend.casts = spend.casts + 1 end
    for i, c in ipairs(costs) do
        local ok, name, amount = pcall(function() return c.name, c.cost end)
        if not ok then
            AddField(rec, "cost" .. i, ERRORED)
        else
            AddField(rec, "cost" .. i .. ".type", name)
            AddField(rec, "cost" .. i .. ".amount", amount)
            -- Only add to totals once both values are known-readable.
            if not IsSecret(name) and not IsSecret(amount)
                and type(name) == "string" and type(amount) == "number" then
                AddSpend(name, amount, inFight)
                if not inFight then
                    table.insert(spend.recent, { t = GetTime(), name = name, amount = amount })
                    if #spend.recent > 5 then table.remove(spend.recent, 1) end
                end
            end
        end
    end
end

-- Current power plus the percentage/regen APIs, in case those aren't secret.
local function AddPowerProbe(rec)
    AddField(rec, "power",     (API("UnitPower", "player")))
    AddField(rec, "powerMax",  (API("UnitPowerMax", "player")))
    AddField(rec, "powerPct",  (API("UnitPowerPercent", "player")))   -- newer API
    AddField(rec, "healthPct", (API("UnitHealthPercent", "player")))  -- newer API
    local baseRegen, castingRegen = API("GetManaRegen")               -- mana/sec
    AddField(rec, "manaRegen", baseRegen)
    AddField(rec, "manaRegenCasting", castingRegen)
end

-- "MANA=120 RAGE=45", or "none".
local function SpendText(t)
    local parts = {}
    for name, amount in pairs(t) do
        parts[#parts + 1] = name .. "=" .. amount
    end
    table.sort(parts)
    return #parts > 0 and table.concat(parts, " ") or "none"
end

handlers.PLAYER_REGEN_DISABLED = function(event)
    local rec = NewRecord(event)
    combatStart = GetTime()
    AddField(rec, "start", date("%H:%M:%S"))
    AddPowerProbe(rec) -- power going into the fight

    -- New fight. The pull spell usually lands just BEFORE combat starts, so
    -- carry over any cast from the last few seconds.
    spend.fight, spend.casts = {}, 0
    for _, r in ipairs(spend.recent) do
        if GetTime() - r.t <= PULL_WINDOW then
            spend.fight[r.name] = (spend.fight[r.name] or 0) + r.amount
            spend.casts = spend.casts + 1
        end
    end
    spend.recent = {}

    Finish(rec)
    StartTicker()
end

handlers.PLAYER_REGEN_ENABLED = function(event)
    StopTicker()
    local rec = NewRecord(event)
    AddField(rec, "end", date("%H:%M:%S"))
    if combatStart then
        AddField(rec, "duration", string.format("%.1fs", GetTime() - combatStart))
    else
        AddField(rec, "duration", "unknown (no start seen)")
    end
    combatStart = nil
    AddField(rec, "spent", SpendText(spend.fight))
    AddField(rec, "casts", spend.casts)
    AddField(rec, "sessionSpent", SpendText(spend.session))
    AddPowerProbe(rec) -- power coming out of the fight
    Finish(rec)
end

handlers.PLAYER_TARGET_CHANGED = function(event)
    local rec = NewRecord(event)
    AddField(rec, "playerInCombat", InCombat())
    AddUnit(rec, "target", "")
    Finish(rec)
end

handlers.CHAT_MSG_COMBAT_XP_GAIN = function(event, text)
    local rec = NewRecord(event)
    AddField(rec, "msg", text)
    Finish(rec)
end

handlers.PLAYER_XP_UPDATE = function(event, unit)
    local rec = NewRecord(event)
    AddField(rec, "unit", unit)

    local xp = API("UnitXP", "player")
    AddField(rec, "xp", xp)

    -- Only do math once we know both values are readable numbers.
    if IsSecret(xp) or type(xp) ~= "number" then
        AddField(rec, "delta", "n/a (xp unreadable)")
        lastXP = nil
    elseif lastXP == nil then
        AddField(rec, "delta", "n/a (no baseline)")
        lastXP = xp
    else
        -- Negative delta = XP bar rolled over on level-up.
        AddField(rec, "delta", xp - lastXP)
        lastXP = xp
    end
    AddField(rec, "restedXP", (API("GetXPExhaustion")))
    Finish(rec)
end

handlers.QUEST_TURNED_IN = function(event, questID, xpReward, moneyReward)
    local rec = NewRecord(event)
    AddField(rec, "questID", questID)
    AddField(rec, "xp", xpReward)
    AddField(rec, "money", moneyReward)
    Finish(rec)
end

handlers.NAME_PLATE_UNIT_ADDED = function(event, unit)
    local rec = NewRecord(event)
    AddField(rec, "unit", unit)
    if IsSecret(unit) then
        -- Can't pass a token we can't read back into Unit APIs meaningfully.
        Finish(rec)
        return
    end
    AddField(rec, "name",     (API("UnitName", unit)))
    AddField(rec, "level",    (API("UnitLevel", unit)))
    AddField(rec, "inCombat", (API("UnitAffectingCombat", unit)))
    AddField(rec, "health",   (API("UnitHealth", unit)))
    AddField(rec, "healthMax", (API("UnitHealthMax", unit)))
    Finish(rec)
end

handlers.PLAYER_LEVEL_UP = function(event, level)
    local rec = NewRecord(event)
    AddField(rec, "level", level)
    Finish(rec)

    -- The answer arrives via TIME_PLAYED_MSG (Blizzard also prints it to chat).
    if RequestTimePlayed then
        RequestTimePlayed()
    end
end

handlers.TIME_PLAYED_MSG = function(event, total, thisLevel)
    local rec = NewRecord(event)
    AddField(rec, "total", total)
    AddField(rec, "thisLevel", thisLevel)
    Finish(rec)
end

---------------------------------------------------------------------------
-- Death and resurrection tracking
--
-- How each way back looks:
--   release spirit   : PLAYER_ALIVE while a ghost
--   corpse run       : CORPSE_IN_RANGE -> RetrieveCorpse()  -> PLAYER_UNGHOST
--   spirit healer    : CONFIRM_XP_LOSS -> AcceptXPLoss()    -> PLAYER_UNGHOST
--   player rez       : RESURRECT_REQUEST -> AcceptResurrect() -> PLAYER_ALIVE
--                      (or PLAYER_UNGHOST if we'd already released)
--   self-res         : C_DeathInfo.UseSelfResurrectOption() -> PLAYER_ALIVE
--
-- The Accept* hooks (see InstallRezHooks) are the strongest signal; the
-- prompts are a fallback hint if a hook isn't available on Forever.
---------------------------------------------------------------------------

local death = {} -- state for the current death; emptied after we come back

-- Player position in world yards. UnitPosition is restricted in instances on
-- modern clients (returns nil), so this returns nil when it can't be read.
local function PlayerPos()
    local y, x, _, inst = API("UnitPosition", "player")
    if IsSecret(y) or IsSecret(x) or IsSecret(inst) then return nil end
    if type(x) ~= "number" or type(y) ~= "number" then return nil end
    return x, y, inst
end

-- Straight-line yards between two saved points, or nil if not comparable.
local function Distance(x1, y1, inst1, x2, y2, inst2)
    if not (x1 and x2) or inst1 ~= inst2 then return nil end
    return math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
end

local GHOST_SAMPLE_SECONDS = 0.5
local GHOST_MAX_STEP = 50 -- yards per sample; bigger jumps are teleports, not running

-- While a ghost, sample position and add up the path walked.
local ghostTicker
local function GhostSample()
    local x, y, inst = PlayerPos()
    if not x then
        death.noPos = (death.noPos or 0) + 1
        return
    end
    local d = Distance(death.lastX, death.lastY, death.lastInst, x, y, inst)
    if d then
        if d <= GHOST_MAX_STEP then
            death.ghostRun = death.ghostRun + d
        else
            death.jumps = (death.jumps or 0) + 1
            -- A jump before any running is the teleport to the graveyard:
            -- treat the new spot as the real release point.
            if death.ghostRun == 0 then
                death.releaseX, death.releaseY, death.releaseInst = x, y, inst
            end
        end
    end
    death.lastX, death.lastY, death.lastInst = x, y, inst
end

local function StartGhostTracking()
    death.ghostRun = 0
    death.ghostStart = GetTime()
    death.releaseX, death.releaseY, death.releaseInst = PlayerPos()
    death.lastX, death.lastY, death.lastInst = death.releaseX, death.releaseY, death.releaseInst
    if not ghostTicker and C_Timer and C_Timer.NewTicker then
        ghostTicker = C_Timer.NewTicker(GHOST_SAMPLE_SECONDS, GhostSample)
    end
end

local function StopGhostTracking()
    if ghostTicker then
        ghostTicker:Cancel()
        ghostTicker = nil
    end
end

local function ResetDeath()
    StopGhostTracking()
    death = {}
end

-- Format yards for the log, or explain why there's no number.
local function Yards(d)
    if d then return string.format("%.0f", d) end
    return "n/a (no position)"
end

-- Shared logging for "we're alive again". Best guess at how we came back:
-- the accept button we clicked, else the last prompt we saw.
local function LogRezResult(rec, fallback)
    AddField(rec, "result", death.accepted or death.hint or fallback)
    if death.from then AddField(rec, "rezzer", death.from) end
    AddField(rec, "released", death.released and true or false)
    if death.time then
        AddField(rec, "deadFor", string.format("%.1fs", GetTime() - death.time))
    else
        AddField(rec, "deadFor", "unknown (no death seen)")
    end

    -- Distances. The death spot is where the corpse lies.
    StopGhostTracking()
    local x, y, inst = PlayerPos()
    AddField(rec, "yardsFromCorpse",
        Yards(Distance(death.deathX, death.deathY, death.deathInst, x, y, inst)))
    if death.released then
        GhostSample() -- count the last stretch before the rez
        AddField(rec, "ghostRunYards", death.ghostRun and Yards(death.ghostRun) or "n/a")
        if death.ghostStart then
            AddField(rec, "ghostTime", string.format("%.1fs", GetTime() - death.ghostStart))
        end
        AddField(rec, "releaseToCorpseYards", Yards(Distance(
            death.releaseX, death.releaseY, death.releaseInst,
            death.deathX, death.deathY, death.deathInst)))
        AddField(rec, "noPosSamples", death.noPos or 0)
        AddField(rec, "teleportJumps", death.jumps or 0)
    end
    AddUnit(rec, "player", "p.") -- health/mana after rez, debuff1 = rez sickness
    AddZone(rec)
    ResetDeath()
end

handlers.PLAYER_DEAD = function(event)
    ResetDeath()
    death.time = GetTime()
    death.deathX, death.deathY, death.deathInst = PlayerPos() -- corpse location
    local rec = NewRecord(event)
    AddField(rec, "positionReadable", death.deathX ~= nil)
    AddField(rec, "inCombat", InCombat())
    AddField(rec, "releaseTimer", (API("GetReleaseTimeRemaining")))
    -- Self-res options (Soulstone, Reincarnation...). Modern API; guarded.
    local opts = API("C_DeathInfo.GetSelfResurrectOptions")
    if IsSecret(opts) or type(opts) ~= "table" then
        AddField(rec, "selfResOptions", opts)
    else
        AddField(rec, "selfResOptions", #opts)
    end
    AddZone(rec)
    Finish(rec)
end

-- Fires when we release (become a ghost) AND when we're rezzed in place.
handlers.PLAYER_ALIVE = function(event)
    local rec = NewRecord(event)
    local ghost = API("UnitIsGhost", "player")
    if IsSecret(ghost) then
        AddField(rec, "ghost", ghost)
        AddField(rec, "result", "unknown (ghost state SECRET)")
    elseif ghost == true then
        death.released = true
        StartGhostTracking()
        AddField(rec, "result", "released spirit")
        AddField(rec, "graveyardToCorpseYards", Yards(Distance(
            death.releaseX, death.releaseY, death.releaseInst,
            death.deathX, death.deathY, death.deathInst)))
    elseif death.time then
        -- Alive without ever being a ghost: someone (or something) rezzed us.
        LogRezResult(rec, "self-res or unknown")
    else
        AddField(rec, "result", "alive (no death seen this session)")
    end
    Finish(rec)
end

-- Fires when a ghost becomes alive again.
handlers.PLAYER_UNGHOST = function(event)
    local rec = NewRecord(event)
    LogRezResult(rec, "unknown")
    Finish(rec)
end

-- Prompts: hints about which way back is on offer.
handlers.CONFIRM_XP_LOSS = function(event)
    death.hint = "spirit healer"
    local rec = NewRecord(event)
    AddField(rec, "note", "spirit healer dialog opened")
    Finish(rec)
end

handlers.CORPSE_IN_RANGE = function(event)
    death.hint = "corpse run"
    local rec = NewRecord(event)
    AddField(rec, "note", "near corpse")
    Finish(rec)
end

handlers.CORPSE_OUT_OF_RANGE = function(event)
    if death.hint == "corpse run" then death.hint = nil end
    local rec = NewRecord(event)
    AddField(rec, "note", "left corpse range")
    Finish(rec)
end

handlers.RESURRECT_REQUEST = function(event, inviter)
    death.hint = "player rez"
    -- Store only the display string, never the raw (possibly secret) value.
    death.from = Display(inviter)
    local rec = NewRecord(event)
    AddField(rec, "from", inviter)
    Finish(rec)
end

-- Post-hooks on the functions the Accept buttons call. hooksecurefunc runs
-- our code after Blizzard's and doesn't taint anything. Each target is
-- nil-checked because I'm not certain all of them exist on Forever.
local rezHooks = {} -- names of hooks that installed, logged in PROBE_INFO

local function OnRezAccept(method)
    death.accepted = method
    local rec = NewRecord("REZ_ACCEPT")
    AddField(rec, "method", method)
    if death.from then AddField(rec, "rezzer", death.from) end
    Finish(rec)
end

local function InstallRezHooks()
    local globals = {
        RetrieveCorpse  = "corpse run",
        AcceptXPLoss    = "spirit healer",
        AcceptResurrect = "player rez",
    }
    for fname, method in pairs(globals) do
        if type(_G[fname]) == "function" then
            hooksecurefunc(fname, function() OnRezAccept(method) end)
            rezHooks[#rezHooks + 1] = fname
        end
    end
    if C_DeathInfo and type(C_DeathInfo.UseSelfResurrectOption) == "function" then
        hooksecurefunc(C_DeathInfo, "UseSelfResurrectOption",
            function() OnRezAccept("self-res") end)
        rezHooks[#rezHooks + 1] = "C_DeathInfo.UseSelfResurrectOption"
    end
end

-- Rested state.
handlers.PLAYER_UPDATE_RESTING = function(event)
    local rec = NewRecord(event)
    AddRested(rec)
    AddZone(rec)
    Finish(rec)
end

handlers.UPDATE_EXHAUSTION = function(event)
    local rec = NewRecord(event)
    AddRested(rec)
    Finish(rec)
end

---------------------------------------------------------------------------
-- Reputation
--
-- Modern clients use C_Reputation.GetFactionDataByIndex (returns a table);
-- Classic used GetFactionInfo (multiple returns). Unsure which Forever has,
-- so try modern first and fall back. Only factions visible in the rep panel
-- are listed: children of a collapsed header are skipped by the game.
---------------------------------------------------------------------------

local repCache = {} -- [factionName] = last readable standing value

local function RepAPI()
    if type(Lookup("C_Reputation.GetNumFactions")) == "function" then return "modern" end
    if type(GetNumFactions) == "function" then return "classic" end
    return "none"
end

-- Returns name, standing (total rep value), reaction (1-8: Hated..Exalted).
local function ReadFaction(i, api)
    if api == "modern" then
        local d = API("C_Reputation.GetFactionDataByIndex", i)
        if IsSecret(d) then return d, d, d end
        if type(d) ~= "table" then return nil end
        local ok, name, standing, reaction =
            pcall(function() return d.name, d.currentStanding, d.reaction end)
        if not ok then return ERRORED, ERRORED, ERRORED end
        return name, standing, reaction
    end
    local name, _, reaction, _, _, standing = API("GetFactionInfo", i)
    return name, standing, reaction
end

-- Scan every listed faction; log those whose standing changed since the last
-- scan. rec == nil seeds the cache silently. Returns the number of changes.
local function ScanReputation(rec)
    local api = RepAPI()
    local num = api == "modern" and API("C_Reputation.GetNumFactions")
        or api == "classic" and API("GetNumFactions") or MISSING
    if IsSecret(num) or type(num) ~= "number" then
        if rec then AddField(rec, "numFactions", num) end
        return 0
    end
    local changed = 0
    for i = 1, num do
        local name, standing, reaction = ReadFaction(i, api)
        if IsSecret(name) or IsSecret(standing) then
            if rec then
                AddField(rec, "faction" .. i, "SECRET")
                changed = changed + 1
            end
        elseif type(name) == "string" and type(standing) == "number" then
            local old = repCache[name]
            if old ~= standing then
                if rec and old then
                    AddField(rec, name, string.format("%d (%+d) reaction=%s",
                        standing, standing - old, (Display(reaction))))
                    changed = changed + 1
                end
                repCache[name] = standing
            end
        end
    end
    return changed
end

-- The faction shown on the XP-bar-style rep tracker, if any.
local function AddWatchedFaction(rec)
    local d = API("C_Reputation.GetWatchedFactionData")
    if IsSecret(d) or d ~= MISSING then
        AddTable(rec, "watched", d, { "name", "reaction", "currentStanding",
            "currentReactionThreshold", "nextReactionThreshold" })
        return
    end
    local name, reaction, min, max, value = API("GetWatchedFactionInfo")
    AddField(rec, "watched.name", name)
    AddField(rec, "watched.reaction", reaction)
    AddField(rec, "watched.value", value)
    AddField(rec, "watched.min", min)
    AddField(rec, "watched.max", max)
end

-- "Your reputation with X has increased by N."
handlers.CHAT_MSG_COMBAT_FACTION_CHANGE = function(event, text)
    local rec = NewRecord(event)
    AddField(rec, "msg", text)
    Finish(rec)
end

-- Fires often (login, zoning, any rep tick). Only print when something moved.
handlers.UPDATE_FACTION = function(event)
    local rec = NewRecord(event)
    local changed = ScanReputation(rec)
    if changed == 0 then
        rec.quiet = true
    end
    Finish(rec)
end

-- Weapon/defense skill gains.
handlers.CHAT_MSG_SKILL = function(event, text)
    local rec = NewRecord(event)
    AddField(rec, "msg", text)
    Finish(rec)
end

handlers.SKILL_LINES_CHANGED = function(event)
    local rec = NewRecord(event)
    AddSkillChanges(rec)
    Finish(rec)
end

-- Money and loot.
handlers.PLAYER_MONEY = function(event)
    local rec = NewRecord(event)
    AddField(rec, "money", (API("GetMoney")))
    Finish(rec)
end

handlers.CHAT_MSG_LOOT = function(event, text)
    local rec = NewRecord(event)
    AddField(rec, "msg", text)
    Finish(rec)
end

handlers.CHAT_MSG_MONEY = function(event, text)
    local rec = NewRecord(event)
    AddField(rec, "msg", text)
    Finish(rec)
end

-- Forever's new systems: keep any system message about them, so the tracker
-- can be wired to their exact wording.
handlers.CHAT_MSG_SYSTEM = function(event, text)
    if IsSecret(text) or type(text) ~= "string" then return end
    for _, word in ipairs({ "Legacy", "Challenge", "Camp", "Transmog" }) do
        if text:find(word, 1, true) then
            local rec = NewRecord(event)
            AddField(rec, "msg", text)
            Finish(rec)
            return
        end
    end
end

-- Zones and dungeon bosses.
handlers.ZONE_CHANGED_NEW_AREA = function(event)
    local rec = NewRecord(event)
    AddZone(rec)
    Finish(rec)
end

handlers.ENCOUNTER_START = function(event, encounterID, name, difficultyID, groupSize)
    local rec = NewRecord(event)
    AddField(rec, "encounterID", encounterID)
    AddField(rec, "name", name)
    AddField(rec, "difficultyID", difficultyID)
    AddField(rec, "groupSize", groupSize)
    Finish(rec)
end

handlers.ENCOUNTER_END = function(event, encounterID, name, difficultyID, groupSize, success)
    local rec = NewRecord(event)
    AddField(rec, "encounterID", encounterID)
    AddField(rec, "name", name)
    AddField(rec, "difficultyID", difficultyID)
    AddField(rec, "groupSize", groupSize)
    AddField(rec, "success", success)
    Finish(rec)
end

-- Your own spell casts (registered for "player" only; see RegisterProbeEvents).
handlers.UNIT_SPELLCAST_SUCCEEDED = function(event, unit, castGUID, spellID)
    local rec = NewRecord(event)
    AddField(rec, "unit", unit)
    AddField(rec, "spellID", spellID)
    AddField(rec, "spell", (API("C_Spell.GetSpellName", spellID)))
    AddSpellCosts(rec, spellID)
    Finish(rec)
end

---------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------

local frame = CreateFrame("Frame")

-- Events that should only fire for the player, not every nearby unit.
local PLAYER_UNIT_EVENTS = { UNIT_SPELLCAST_SUCCEEDED = true }

local function RegisterProbeEvents()
    for event in pairs(handlers) do
        -- Modern clients throw on unknown event names, so pcall it. Any event
        -- that doesn't exist on Forever gets reported instead of breaking load.
        local ok
        if PLAYER_UNIT_EVENTS[event] then
            ok = pcall(frame.RegisterUnitEvent, frame, event, "player")
        else
            ok = pcall(frame.RegisterEvent, frame, event)
        end
        if not ok then
            unknownEvents[#unknownEvents + 1] = event
            print(PREFIX .. " |cffff5555unknown event:|r " .. event)
        end
    end
end

-- Logged on every login/reload/zone-in: who, what client, what's available.
local function LogProbeInfo(isInitialLogin, isReloadingUi)
    local rec = NewRecord("PROBE_INFO")
    AddField(rec, "character", (API("UnitName", "player")))
    AddField(rec, "realm", (API("GetRealmName")))
    AddField(rec, "level", (API("UnitLevel", "player")))
    local version, build, _, toc = API("GetBuildInfo")
    AddField(rec, "version", version)
    AddField(rec, "build", build)
    AddField(rec, "toc", toc)
    AddField(rec, "initialLogin", isInitialLogin)
    AddField(rec, "reload", isReloadingUi)
    AddField(rec, "hasIsSecretValue", issecretvalue ~= nil)
    AddField(rec, "hasCTimer", C_Timer ~= nil)
    AddField(rec, "hasSkillLines", type(GetNumSkillLines) == "function")
    AddField(rec, "unknownEvents",
        #unknownEvents > 0 and table.concat(unknownEvents, ",") or "none")
    AddField(rec, "rezHooks", #rezHooks > 0 and table.concat(rezHooks, ",") or "none")
    AddField(rec, "repAPI", RepAPI())
    AddField(rec, "powerCostAPI", type(Lookup("C_Spell.GetSpellPowerCost")) == "function")
    AddWatchedFaction(rec)
    AddPowerProbe(rec)
    AddRested(rec)
    AddZone(rec)
    Finish(rec)
end

-- "Interface action failed because of an AddOn": the game's message doesn't
-- say which addon, or what it was doing; these two events do. Printed even
-- with /jprobe off, and the last 20 are kept in JourneyProbeDB.blocked.
local blockWatch = CreateFrame("Frame")
for _, event in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do
    pcall(blockWatch.RegisterEvent, blockWatch, event)
end
blockWatch:SetScript("OnEvent", function(_, event, addon, func)
    local kind = event == "ADDON_ACTION_FORBIDDEN" and "Forbidden" or "Blocked"
    print(string.format("%s %s: %s tried %s", PREFIX, kind, tostring(addon), tostring(func)))
    if JourneyProbeDB then
        JourneyProbeDB.blocked = JourneyProbeDB.blocked or {}
        local list = JourneyProbeDB.blocked
        table.insert(list, { t = time(), event = event, addon = tostring(addon), func = tostring(func),
            combat = (InCombatLockdown and InCombatLockdown()) or nil })
        while #list > 20 do table.remove(list, 1) end
    end
end)

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= ADDON_NAME then return end
        -- SavedVariables are available now.
        JourneyProbeDB = JourneyProbeDB or {}
        JourneyProbeDB.log = JourneyProbeDB.log or {}
        if JourneyProbeDB.print == nil then JourneyProbeDB.print = true end
        RegisterProbeEvents()
        InstallRezHooks()
        self:UnregisterEvent("ADDON_LOADED")
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        -- Seed the XP baseline so the first PLAYER_XP_UPDATE has a delta.
        local xp = API("UnitXP", "player")
        if not IsSecret(xp) and type(xp) == "number" then
            lastXP = xp
        end
        -- Seed the skill cache silently so later changes can be spotted.
        AddSkillChanges(nil)
        -- Seed rep the same way. Rep data may not be ready yet at login; if
        -- not, the first UPDATE_FACTION seeds it silently instead.
        ScanReputation(nil)
        LogProbeInfo(...)
        return
    end

    local handler = handlers[event]
    if handler then
        handler(event, ...)
    end
end)

---------------------------------------------------------------------------
-- Slash command: /jprobe on | off | clear | stats | snap
---------------------------------------------------------------------------

local function PrintStats()
    local byEvent = {}
    for _, e in ipairs(JourneyProbeDB.log) do
        local s = byEvent[e.ev]
        if not s then
            s = { fields = 0, secret = 0, firings = {}, nFirings = 0 }
            byEvent[e.ev] = s
        end
        s.fields = s.fields + 1
        if e.s then s.secret = s.secret + 1 end
        if not s.firings[e.n] then
            s.firings[e.n] = true
            s.nFirings = s.nFirings + 1
        end
    end

    local names = {}
    for name in pairs(byEvent) do names[#names + 1] = name end
    table.sort(names)

    print(PREFIX .. " " .. #JourneyProbeDB.log .. " entries (cap " .. MAX_LOG .. ")")
    for _, name in ipairs(names) do
        local s = byEvent[name]
        print(string.format("  %s: %d events, %d fields, %d SECRET",
            name, s.nFirings, s.fields, s.secret))
    end
end

-- Manual snapshot: everything about you, your rest state, zone and target.
local function Snapshot()
    local rec = NewRecord("SNAPSHOT")
    AddRested(rec)
    AddZone(rec)
    AddPowerProbe(rec)
    AddWatchedFaction(rec)
    AddUnit(rec, "player", "p.")
    AddUnit(rec, "target", "t.")
    Finish(rec)
end

-- /jprobe api: find the game's functions and events for Forever's new
-- systems (Legacy, camping, transmog, rulesets) by name, and log them.
local API_WORDS = { "Legacy", "Camp", "Transmog", "GameRules", "Ruleset", "Skyborne" }

local function Matches(name)
    if type(name) ~= "string" then return false end
    for _, word in ipairs(API_WORDS) do
        if name:find(word, 1, true) then return true end
    end
    return false
end

local function ApiScan()
    local rec = NewRecord("API_SCAN", true)
    local found = 0
    -- C_ namespaces (with their functions) and global functions.
    local names = {}
    for name, value in pairs(_G) do
        if Matches(name) and (type(value) == "function"
            or (type(value) == "table" and name:find("^C_"))) then
            names[#names + 1] = name
        end
    end
    table.sort(names)
    for _, name in ipairs(names) do
        local value = _G[name]
        if type(value) == "table" then
            local fns = {}
            for k, v in pairs(value) do
                if type(v) == "function" then fns[#fns + 1] = tostring(k) end
            end
            table.sort(fns)
            AddField(rec, name, table.concat(fns, ", "))
        else
            AddField(rec, name, "function")
        end
        found = found + 1
    end
    -- Events, from the game's built-in API documentation.
    local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
    if load then pcall(load, "Blizzard_APIDocumentationGenerated") end
    local doc = _G.APIDocumentation
    if type(doc) == "table" and type(doc.systems) == "table" then
        for _, system in ipairs(doc.systems) do
            local systemName = system.Namespace or system.Name
            for _, ev in ipairs(system.Events or {}) do
                if Matches(ev.LiteralName) or Matches(systemName) then
                    AddField(rec, "event", ev.LiteralName or "?")
                    found = found + 1
                end
            end
        end
    else
        AddField(rec, "events", "API documentation not available")
    end
    AddField(rec, "matches", found)
    print(PREFIX .. " API scan done: " .. found .. " matches saved. /reload so they're written to disk.")
end

SLASH_JPROBE1 = "/jprobe"
SlashCmdList.JPROBE = function(msg)
    local cmd = (msg or ""):lower():match("^%s*(%S*)")
    if cmd == "on" then
        JourneyProbeDB.print = true
        print(PREFIX .. " chat printing ON")
    elseif cmd == "off" then
        JourneyProbeDB.print = false
        print(PREFIX .. " chat printing OFF (still logging)")
    elseif cmd == "clear" then
        JourneyProbeDB.log = {}
        print(PREFIX .. " log cleared")
    elseif cmd == "stats" then
        PrintStats()
    elseif cmd == "snap" then
        Snapshot()
    elseif cmd == "api" then
        ApiScan()
    else
        print(PREFIX .. " usage: /jprobe on | off | clear | stats | snap | api")
    end
end
