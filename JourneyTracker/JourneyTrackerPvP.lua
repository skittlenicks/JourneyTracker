-- JourneyTracker wrapped stats: PvP. IDs match wrapped-tracking-spec.md:
--   World PvP and ganking (W-140..W-169), plus the faction iconic ones
--   (W-080, W-091, W-100)
--   Battlegrounds and duels (W-170..W-190)
--   PvP firsts (W-468, W-469, W-479, W-480)
--
-- Players are never stored by name: a kill or death keeps the other
-- player's class and level only, looked up from the session's own cache
-- (ns.PlayerInfo). An enemy player killed shows up as an honorable kill
-- message, as a target you attacked dying, or in the combat log where
-- Forever lets addons read it; the same player within 10 seconds counts
-- once. Your health is secret on Forever, so W-164 (kills while under 20%
-- health) can't be tracked.

local ADDON_NAME, ns = ...
local Track = ns.Track
local Safe, Call, Num, Str, IsSecret = ns.Safe, ns.Call, ns.Num, ns.Str, ns.IsSecret
local On, Protect = ns.WrappedOn, ns.Protect

local GANK_GAP = 10       -- levels apart for a gank
local FAIR_GAP = 3        -- levels apart for a fair fight
local CAMP_WINDOW = 600   -- seconds: deaths to the same class and level this close are a camp
local TOWN_GAP = 600      -- seconds before attacking the same town counts again

local CAPITALS = { Alliance = { "Stormwind City", "Ironforge", "Darnassus" },
                   Horde = { "Orgrimmar", "Thunder Bluff", "Undercity" } }
-- Towns of each faction, for W-162 (attacking an enemy town).
local TOWNS = {
    Alliance = { "Goldshire", "Lakeshire", "Darkshire", "Sentinel Hill", "Southshore", "Menethil Harbor", "Astranaar",
        "Auberdine", "Theramore Isle", "Thelsamar", "Kharanos", "Dolanaar", "Refuge Pointe", "Nijel's Point",
        "Feathermoon Stronghold", "Stormwind City", "Ironforge", "Darnassus" },
    Horde = { "The Crossroads", "Razor Hill", "Tarren Mill", "Brill", "The Sepulcher", "Bloodhoof Village",
        "Camp Taurajo", "Sun Rock Retreat", "Splintertree Post", "Hammerfall", "Kargath", "Stonard",
        "Grom'gol Base Camp", "Freewind Post", "Camp Mojache", "Shadowprey Village", "Orgrimmar", "Thunder Bluff",
        "Undercity" },
}
-- Guards, by the faction they guard (W-160, W-161).
local GUARDS = {
    Alliance = { "City Guard", "Ironforge Guard", "Mountaineer", "Darnassus Sentinel", "Southshore Guard",
        "Theramore Guard", "Royal Guard", "Watchman" },
    Horde = { "Grunt", "Deathguard", "Bluffwatcher", "Kor'kron" },
}
local LEADERS = { "Thrall", "Cairne Bloodhoof", "Lady Sylvanas Windrunner", "Vol'jin", "Highlord Bolvar Fordragon",
    "King Magni Bronzebeard", "Tyrande Whisperwind", "High Tinker Mekkatorque", "Fandral Staghelm" }
local ESCAPES = { ["Feign Death"] = true, ["Vanish"] = true, ["Ice Block"] = true, ["Divine Shield"] = true,
    ["Blessing of Protection"] = true, ["Invisibility"] = true }
local MARK_ITEMS = "Mark of Honor"

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function Faction() return Str(Call("UnitFactionGroup", "player")) end
local function Enemy() return Faction() == "Alliance" and "Horde" or "Alliance" end
local function IsIn(value, list)
    if value == nil or not list then return false end
    for _, v in ipairs(list) do if v == value then return true end end
    return false
end
local function HasAny(text, list)
    if not text or not list then return nil end
    for _, word in ipairs(list) do if text:find(word, 1, true) then return word end end
end

local function InBattleground()
    local inInstance, kind = Call("IsInInstance")
    return inInstance == true and kind == "pvp"
end

local function MyName() return Str(Call("UnitName", "player")) end

-- A pattern for a game message whose format may use numbered parts
-- ("%1$s has defeated %2$s"): returns the pattern and which part each
-- capture is, in order.
local function NumberedPattern(fmt, english)
    if type(fmt) ~= "string" then fmt = english end
    local order, i = {}, 0
    -- Escape the pattern characters ("$" too, so "%1$s" becomes "%1%$s"),
    -- then turn each %N$s, %s and %d into a capture.
    local p = fmt:gsub("[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0")
    p = p:gsub("%%(%d)%%%$s", function(n) order[#order + 1] = tonumber(n); return "(.-)" end)
    p = p:gsub("%%s", function() i = i + 1; order[#order + 1] = i; return "(.-)" end)
    p = p:gsub("%%d", "(%%d+)")
    return "^" .. p .. "$", order
end

local HONOR_KILL = ns.PatternFrom(COMBATLOG_HONORGAIN, "%s dies, honorable kill Rank: %s (Estimated Honor Points: %d)")
-- (a victim with no PvP rank, where the client has the string for it)
local HONOR_KILL_NO_RANK = type(COMBATLOG_HONORGAIN_NO_RANK) == "string" and ns.PatternFrom(COMBATLOG_HONORGAIN_NO_RANK)
local DISHONOR_KILL = ns.PatternFrom(COMBATLOG_DISHONORGAIN, "%s dies, dishonorable kill.")
local HONOR_AWARD = ns.PatternFrom(COMBATLOG_HONORAWARD, "You have been awarded %d honor points.")
local DUEL_WIN, DUEL_WIN_ORDER = NumberedPattern(DUEL_WINNER_KNOCKOUT, "%1$s has defeated %2$s in a duel")
local DUEL_FLED, DUEL_FLED_ORDER = NumberedPattern(DUEL_WINNER_RETREAT, "%2$s has fled from %1$s in a duel")

-- The two names in a duel message, as (winner, loser).
local function DuelNames(msg, pattern, order)
    local caps = { msg:match(pattern) }
    if #caps < 2 then return nil end
    local parts = {}
    for i, n in ipairs(order) do parts[n] = caps[i] end
    return parts[1], parts[2]
end

---------------------------------------------------------------------------
-- Killing enemy players
---------------------------------------------------------------------------

local recentKills = {}    -- [GUID or name] = GetTime(), so one kill isn't counted twice (this session only)
local lastKill            -- { t, guid, name } the last kill counted
local streak = 0          -- W-169 enemy players killed since you last died
local stealthOpen = false -- the current fight began from stealth (W-142)

-- W-140 one kill can arrive three ways (the honor message, your target
-- dying, the combat log), with a GUID or not, and a name with or without
-- its realm, or none: it's the same kill by GUID or name within 10
-- seconds, and one with no name to compare is the kill just before it,
-- within 2.
local function SameKill(guid, name, now)
    if guid and recentKills[guid] and now - recentKills[guid] < 10 then return true end
    if name and recentKills[name] and now - recentKills[name] < 10 then return true end
    local last = lastKill
    return last ~= nil and now - last.t < 2 and not (name and last.name)
        and not (guid and last.guid and guid ~= last.guid)
end

local function PvPKill(name, info, guid)
    local now = GetTime()
    name = name and (name:match("^(.-)%-") or name)
    if SameKill(guid, name, now) then return end
    if guid then recentKills[guid] = now end
    if name then recentKills[name] = now end
    lastKill = { t = now, guid = guid, name = name }
    info = info or (name and ns.PlayerInfo(name)) or {}
    local me, zone, subzone = ns.Level(), ns.Zone(), ns.SubZone()
    local level, class = info.level, info.class
    local world = not InBattleground()
    Track.count("W-140")                                      -- W-140 enemy players killed
    -- (A level of -1 is a skull: 10 or more above you. Exports carry no
    -- negative numbers, so it's kept as `skull`.)
    Track.first("W-468", { class = class, theirLevel = level and level > 0 and level or nil,
                           skull = level == -1 or nil })      -- W-468 first enemy player killed
    streak = streak + 1
    Track.max("W-169", streak)                                -- W-169 longest kill streak
    if level and level > 0 then
        local gap = me - level
        if gap >= GANK_GAP then
            Track.count("W-141")                              -- W-141 lowbies ganked
            if stealthOpen then Track.count("W-142") end      -- W-142 from stealth
            Track.max("W-143", gap, { class = class })        -- W-143 biggest gap
        end
        if math.abs(gap) <= FAIR_GAP then Track.count("W-148") end -- W-148 fair fights won
    end
    if world then
        if class then Track.count("W-150", class) end         -- W-150 kills by class (W-153 favorite victim)
        Track.count("W-154", zone)                            -- W-154 by zone
        if IsIn(zone, CAPITALS[Enemy()]) then Track.count("W-168") end -- W-168 in their own capital
        local f = Faction()
        if f == "Alliance" and zone == "Hillsbrad Foothills" then Track.count("W-080") end
        if f == "Horde" and subzone == "The Crossroads" then Track.count("W-091") end
        if f == "Horde" and zone == "Hillsbrad Foothills" then Track.count("W-100") end
    end
    if info.fightingMob then Track.count("W-166") end         -- W-166 they were busy with a mob
end

-- A target you attacked dying: the enemy player kills that give no honor.
local watched, watchTicker, attackedAt = nil, nil, 0
local function StopWatch()
    if watchTicker then watchTicker:Cancel() end
    watchTicker, watched = nil, nil
end
local function CheckWatched()
    if not watched then return StopWatch() end
    if Str(Call("UnitGUID", "target")) ~= watched.guid then return StopWatch() end
    -- Remember whether they were fighting a mob (W-166).
    if Call("UnitIsPlayer", "targettarget") == false and Call("UnitCanAttack", "target", "targettarget") == true then
        watched.fightingMob = true
    end
    if Call("UnitIsDeadOrGhost", "target") == true then
        local w = watched
        StopWatch()
        if GetTime() - attackedAt < 30 then PvPKill(w.name, w, w.guid) end
    end
end
local function WatchTarget()
    StopWatch()
    if Call("UnitIsPlayer", "target") ~= true or Call("UnitIsEnemy", "player", "target") ~= true then return end
    if Call("UnitIsDeadOrGhost", "target") == true then return end -- already dead: not a kill to watch for
    local guid = Str(Call("UnitGUID", "target"))
    if not guid then return end
    local _, class = Call("UnitClass", "target")
    watched = { guid = guid, name = Str(Call("UnitName", "target")), class = Str(class), level = Num(Call("UnitLevel", "target")) }
end
local function Attacked()
    attackedAt = GetTime()
    if watched and not watchTicker and C_Timer and C_Timer.NewTicker then
        watchTicker = C_Timer.NewTicker(0.5, Protect(CheckWatched))
    end
end

---------------------------------------------------------------------------
-- Being killed by players
---------------------------------------------------------------------------

local pvpDeaths = {}      -- recent { key = class|level, t } for corpse camping (W-146)

local function OnDeath(rec, extra)
    streak = 0
    local killer = rec.killer or ""
    local f = Faction()
    local mob = extra and extra.mob
    if HasAny(killer, GUARDS[Enemy()]) and mob and mob.faction == Enemy() then
        Track.count("W-161")                                  -- W-161 killed by enemy guards (of their faction)
    end
    if killer ~= "Player (PvP)" then return end
    local p = extra and extra.player or {}
    local me, level, class = ns.Level(), p.level, p.class
    local world = not InBattleground()
    Track.first("W-469", { class = class, theirLevel = level and level > 0 and level or nil,
                           skull = level == -1 or nil })      -- W-469 first killed by a player
    if level and level > 0 then
        if level - me >= GANK_GAP then Track.count("W-144") end -- W-144 ganked
        if math.abs(level - me) <= FAIR_GAP then Track.count("W-149") end -- W-149 fair fights lost
        if level > me then
            Track.max("W-145", level - me, { class = class }) -- W-145 biggest gap when ganked
        end
    elseif level == -1 then
        Track.count("W-144")                                  -- a skull is at least 10 above you
    end
    if world then
        if class then Track.count("W-151", class) end         -- W-151 deaths by class (W-152 nemesis)
        Track.count("W-155", rec.zone or "?")                 -- W-155 deaths by zone
    end
    -- W-165 third-partied: a mob was in the fight too
    local fight = extra and extra.fight
    if fight and fight.names then
        for name in pairs(fight.names) do
            if name ~= "Player (PvP)" then Track.count("W-165"); break end
        end
    end
    -- W-146 corpse camped: the same class and level three times in 10
    -- minutes, out in the world (a killer not seen can't be matched)
    local key = world and class and level and (class .. "|" .. level) or nil
    local now = time()
    local n = 1
    for i = #pvpDeaths, 1, -1 do
        if now - pvpDeaths[i].t > CAMP_WINDOW then table.remove(pvpDeaths, i)
        elseif key and pvpDeaths[i].key == key then n = n + 1 end
    end
    table.insert(pvpDeaths, { key = key, t = now })
    if key and n == 3 then Track.count("W-146") end
end

-- W-147 spirit healer rezzes taken to get away from players: a spirit
-- healer after at least two PvP deaths in 10 minutes.
local function OnRevived()
    if #pvpDeaths < 2 then return end
    if not (C_Timer and C_Timer.After) then return end
    C_Timer.After(0.5, Protect(function()
        local deaths = ns.GetDB().deaths
        local last = deaths[#deaths]
        if last and last.rez == "spirit healer" and last.killer == "Player (PvP)" then Track.count("W-147") end
    end))
end

---------------------------------------------------------------------------
-- Flags, towns, guards, leaders, escapes
---------------------------------------------------------------------------

local manualUntil, wasPvP = 0, nil
local function CheckFlag()
    local pvp = Call("UnitIsPVP", "player")
    if pvp == nil then return end
    pvp = pvp and true or false
    if wasPvP == false and pvp then
        if GetTime() < manualUntil then
            Track.count("W-157")                              -- W-157 flagged yourself
        else
            local zoneType = ns.ZonePvP()
            if zoneType ~= "contested" and zoneType ~= "hostile" then
                Track.count("W-158")                          -- W-158 by accident (contested and enemy zones are W-021)
            end
        end
    end
    wasPvP = pvp
end

local lastTownAttack = {}
local function OnCombatStart()
    stealthOpen = Call("IsStealthed") == true
    Attacked()
    -- (a capital is one town, whichever district you're in)
    local town = IsIn(ns.Zone(), CAPITALS[Enemy()]) and ns.Zone() or ns.SubZone() or ns.Zone()
    if IsIn(town, TOWNS[Enemy()]) or IsIn(ns.Zone(), TOWNS[Enemy()]) then
        local now = GetTime()
        if not lastTownAttack[town] or now - lastTownAttack[town] > TOWN_GAP then
            Track.count("W-162", town)                        -- W-162 attacked an enemy town
        end
        lastTownAttack[town] = now
    end
end

-- Kills from the main tracker, and those without experience (Iconic's
-- ns.OnNoXPKill: every kill at 60).
local function OnKill(k)
    local mob = ns.MobInfo(k.name)
    if HasAny(k.name, GUARDS[Enemy()]) and mob and mob.faction == Enemy() then
        Track.count("W-160")                                  -- W-160 enemy guards killed (a Blackrock Grunt isn't one)
    end
    if IsIn(k.name, LEADERS) then Track.count("W-163", k.name) end  -- W-163 faction leaders
end

-- W-167 an escape: Feign Death, Vanish and the like in a fight with a
-- player, and out of combat alive soon after.
local escape
local function OnCast(name)
    if not ESCAPES[name] then return end
    local fight = ns.CurrentFight()
    if fight and fight.names and fight.names["Player (PvP)"] then escape = { name = name, t = GetTime() } end
end
local function OnCombatEnd()
    stealthOpen = false
    if escape and GetTime() - escape.t < 10 and Call("UnitIsDeadOrGhost", "player") ~= true then
        Track.count("W-167", escape.name)
    end
    escape = nil
end

---------------------------------------------------------------------------
-- Messages: honor, duels
---------------------------------------------------------------------------

local duel -- { started, opponent class } while a duel runs

local function OnCombatMessage(msg)
    msg = Str(Safe(msg))
    if not msg then return end
    local victim, _, honor = msg:match(HONOR_KILL)
    if not victim and HONOR_KILL_NO_RANK then victim, honor = msg:match(HONOR_KILL_NO_RANK) end
    if victim then
        PvPKill(victim)
        if tonumber(honor) then Track.count("W-182", nil, tonumber(honor)) end -- W-182 honor
        return
    end
    if msg:match(DISHONOR_KILL) then Track.count("W-159") return end -- W-159 dishonorable kills
    local award = msg:match(HONOR_AWARD)
    if tonumber(award) then Track.count("W-182", nil, tonumber(award)) end
end

local function OnSystem(msg)
    msg = Str(Safe(msg))
    if not msg then return end
    local me = MyName()
    local winner, loser = DuelNames(msg, DUEL_WIN, DUEL_WIN_ORDER)
    local fled = false
    if not winner then
        winner, loser = DuelNames(msg, DUEL_FLED, DUEL_FLED_ORDER)
        fled = winner ~= nil
    end
    if not winner or not me or (winner ~= me and loser ~= me) then return end
    local opponent = winner == me and loser or winner
    local class = (duel and duel.class) or (ns.PlayerInfo(opponent) or {}).class or "Unknown"
    if winner == me then
        Track.count("W-186", "won")                           -- W-186 duels won and lost
        Track.count("W-187", class .. " won")                 -- W-187 by opponent class
        Track.first("W-480", { class = class })               -- W-480 first duel won
    else
        Track.count("W-186", "lost")
        Track.count("W-187", class .. " lost")
        if fled then Track.count("W-188") end                 -- W-188 duels you fled
    end
    if duel and duel.started then
        Track.max("W-189", GetTime() - duel.started, { class = class }) -- W-189 longest duel
    end
    duel = nil
end

local function DuelTarget()
    if Call("UnitIsPlayer", "target") == true then
        local _, class = Call("UnitClass", "target")
        return Str(class)
    end
end

---------------------------------------------------------------------------
-- Battlegrounds
---------------------------------------------------------------------------

-- { name, decided, wantScore } for the battleground you're in, kept in
-- db.wrapped (bgMatch) so a /reload there carries on with the same match.
local match

local function OnZone()
    if InBattleground() then
        local name = Str(Call("GetInstanceInfo")) or ns.Zone()
        if not match or match.name ~= name then
            local saved = Track.get("bgMatch")
            if type(saved) == "table" and saved.name == name then
                match = saved                                 -- back after a /reload: not a new one
            else
                match = { name = name }
                Track.set("bgMatch", match)
                Track.count("W-170", name)                    -- W-170 battlegrounds entered
                local level = ns.Level()
                local bracket = math.floor(level / 10) * 10
                Track.count("W-181", name .. " " .. bracket .. "-" .. (bracket + 9)) -- W-181 brackets
                Track.first("W-479", { battleground = name }) -- W-479 first battleground
            end
        end
    else
        match = nil
        Track.set("bgMatch", nil)
    end
end

-- The scoreboard at the end: your killing blows, honorable kills, deaths
-- and each objective column, by battleground.
local function ReadScore()
    if not match then return end
    local me = MyName()
    local n = Num(Call("GetNumBattlefieldScores")) or 0
    for i = 1, n do
        local name, kb, hk, deaths = Call("GetBattlefieldScore", i)
        if Str(name) and me and (name == me or Str(name):match("^(.-)%-") == me) then
            local s = Track.get("W-174")
            s = type(s) == "table" and s or {}
            local row = s[match.name] or { killingBlows = 0, honorableKills = 0, deaths = 0 }
            row.killingBlows = row.killingBlows + (Num(kb) or 0)          -- W-174 killing blows and HKs
            row.honorableKills = row.honorableKills + (Num(hk) or 0)
            row.deaths = row.deaths + (Num(deaths) or 0)                  -- W-175 battleground deaths
            s[match.name] = row
            Track.set("W-174", s)
            Track.count("W-175", match.name, Num(deaths) or 0)
            -- W-176..W-179 the objective columns, whatever this battleground reports
            local id = (match.name:find("Warsong") and "W-176") or (match.name:find("Arathi") and "W-177")
                or (match.name:find("Alterac") and "W-179") or "W-178"
            local columns = Num(Call("GetNumBattlefieldStats")) or 0
            for c = 1, columns do
                local label = Str(Call("GetBattlefieldStatInfo", c))
                local value = Num(Call("GetBattlefieldStatData", i, c))
                if label and value and value > 0 then Track.count(id, match.name .. ": " .. label, value) end
            end
            return true
        end
    end
end

local function OnBattlefieldStatus()
    if not match or match.decided then return end
    local winner = Num(Call("GetBattlefieldWinner"))
    if not winner then return end
    match.decided = true
    local mine = Faction() == "Horde" and 0 or 1
    Track.count("W-171", match.name .. (winner == mine and " won" or " lost")) -- W-171 wins and losses
    Call("RequestBattlefieldScoreData")
    match.wantScore = true
end

local lastXP, lastXPMax
local function OnXP()
    local xp, xpMax = Num(Call("UnitXP", "player")), Num(Call("UnitXPMax", "player"))
    if not xp then return end
    if lastXP and InBattleground() then
        local gained = xp >= lastXP and xp - lastXP or (lastXPMax and (lastXPMax - lastXP) + xp) or 0
        if gained > 0 then Track.count("W-184", nil, gained) end -- W-184 XP earned in battlegrounds
    end
    lastXP, lastXPMax = xp, xpMax
end

---------------------------------------------------------------------------
-- Every 5 seconds: time flagged, in battlegrounds, in queues; rank
---------------------------------------------------------------------------

-- Your PvP rank (1 for the first; 0 none) and its title. Forever keeps it
-- as the renown level of its rank points faction, as its character sheet's
-- PvP tab reads it; older clients have UnitPVPRank.
local PVP_RANK_FACTION = 2800
local function PvPRank()
    if C_MajorFactions and C_MajorFactions.GetMajorFactionProgressionInfo then
        local info = Call("C_MajorFactions.GetMajorFactionProgressionInfo", PVP_RANK_FACTION)
        local rank = type(info) == "table" and Num(Safe(info.renownLevel))
        if not rank or rank <= 0 then return rank end
        local first = Enum and Enum.PvPRanks and Num(Enum.PvPRanks.Rank_1)
        local alliance = Faction() == "Alliance" and 1 or 0
        local title = first and Str(Call("GetText", "PVP_RANK_" .. (first + rank - 1) .. "_" .. alliance,
            Num(Call("UnitSex", "player")) or 2))
        return rank, title
    end
    local rank = Num(Call("UnitPVPRank", "player"))
    return rank, rank and rank > 0 and Str(Call("GetPVPRankInfo", rank)) or nil
end

local function Tick(dt)
    local s = math.floor(dt + 0.5)
    if Call("UnitIsPVP", "player") == true then Track.count("W-156", nil, s) end -- W-156 time flagged
    if match then Track.count("W-172", match.name, s) end    -- W-172 time in battlegrounds
    local queues = Num(Call("GetMaxBattlefieldID")) or 0
    for i = 1, queues do
        if Str(Call("GetBattlefieldStatus", i)) == "queued" then
            Track.count("W-173", nil, s)                      -- W-173 time in queues
            break
        end
    end
    local rank, name = PvPRank()
    if rank and rank > 0 then
        Track.max("W-183", rank, { name = name })             -- W-183 highest rank while leveling
    end
end

---------------------------------------------------------------------------
-- Window page
---------------------------------------------------------------------------

local function DrawPvP(B)
    local rows = {
        { heading = "World PvP" },
        { "W-140", "Enemy players killed" }, { "W-468", "First enemy player killed" },
        { "W-141", "Lowbies ganked (10+ levels below)" }, { "W-142", "...opened from stealth" },
        { "W-143", "Biggest level gap in a gank" }, { "W-144", "Times you got ganked" },
        { "W-145", "Biggest level gap when ganked" }, { "W-469", "First time killed by a player" },
        { "W-146", "Times corpse camped" }, { "W-147", "Spirit healer to escape a camp" },
        { "W-148", "Fair fights won (within 3 levels)" }, { "W-149", "Fair fights lost" },
        { "W-150", "Kills by class" }, { "W-151", "Deaths by class" },
        { "W-154", "Kills by zone" }, { "W-155", "Deaths by zone" },
        { "W-156", "Time flagged for PvP", "time" }, { "W-157", "Times you flagged yourself" },
        { "W-158", "Times flagged by accident" }, { "W-159", "Dishonorable kills" },
        { "W-160", "Enemy guards killed" }, { "W-161", "Times killed by enemy guards" },
        { "W-162", "Enemy towns attacked" }, { "W-163", "Faction leaders killed" },
        { "W-165", "Killed by a player while fighting a mob" }, { "W-166", "Killed a player who was fighting a mob" },
        { "W-167", "Escapes from players" }, { "W-168", "Kills in their own capital" },
        { "W-169", "Longest kill streak" },
    }
    if Faction() == "Alliance" then
        rows[#rows + 1] = { "W-080", "Horde killed in Hillsbrad" }
    elseif Faction() == "Horde" then
        rows[#rows + 1] = { "W-091", "Alliance killed in the Crossroads" }
        rows[#rows + 1] = { "W-100", "Alliance killed in Hillsbrad" }
    end
    ns.ShowItems(B, rows)
end

local function DrawBattlegrounds(B)
    ns.ShowItems(B, {
        { heading = "Battlegrounds" },
        { "W-170", "Battlegrounds entered" }, { "W-479", "First battleground" },
        { "W-171", "Wins and losses" }, { "W-172", "Time in battlegrounds", "timemap" },
        { "W-173", "Time in queues", "time" }, { "W-175", "Deaths" },
        { "W-176", "Warsong Gulch objectives" }, { "W-177", "Arathi Basin objectives" },
        { "W-178", "Darkspear Islands objectives" }, { "W-179", "Alterac Valley objectives" },
        { "W-180", "Marks of Honor received" }, { "W-181", "Level brackets played" },
        { "W-182", "Honor earned" }, { "W-183", "Highest PvP rank" },
        { "W-184", "Experience earned in battlegrounds" },
        { heading = "Duels" },
        { "W-185", "Duels you asked for and accepted" }, { "W-190", "Times challenged" },
        { "W-186", "Duels won and lost" }, { "W-187", "By opponent class" },
        { "W-188", "Duels you fled" }, { "W-189", "Longest duel", "time" }, { "W-480", "First duel won" },
    })
    local scores = Track.get("W-174")
    if type(scores) == "table" then
        B:Heading("Scoreboard Totals")                                     -- W-174
        for name, row in pairs(scores) do
            B:Row(name, string.format("%d killing blows, %d honorable kills, %d deaths",
                row.killingBlows or 0, row.honorableKills or 0, row.deaths or 0))
        end
    end
end

ns.WrappedPage("Wrapped Stats", "World PvP", DrawPvP)
ns.WrappedPage("Wrapped Stats", "Battlegrounds & Duels", DrawBattlegrounds)

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------

ns.OnDeathRecord(OnDeath)
ns.OnKill(OnKill)
ns.OnPartyKill(function(guid, name) PvPKill(name, nil, guid) end)
ns.OnNoXPKill(OnKill) -- at 60 no kill gives experience
ns.OnCast(Protect(function(name)
    OnCast(name)
    if watched and Str(Call("UnitGUID", "target")) == watched.guid then Attacked() end
end))
ns.OnItemChange(Protect(function(c)
    if c.delta > 0 and c.name and c.name:find(MARK_ITEMS, 1, true) then
        Track.count("W-180", c.name, c.delta)                 -- W-180 marks earned, by battleground
    end
end))

On("PLAYER_ENTERING_WORLD", function()
    wasPvP = Call("UnitIsPVP", "player") and true or false
    lastXP, lastXPMax = Num(Call("UnitXP", "player")), Num(Call("UnitXPMax", "player"))
    OnZone()
end)
On("ZONE_CHANGED_NEW_AREA", OnZone)
On("PLAYER_TARGET_CHANGED", WatchTarget)
On("PLAYER_ENTER_COMBAT", Attacked)
On("PLAYER_REGEN_DISABLED", function()
    OnCombatStart()
    if duel and not duel.started then duel.started = GetTime() end
end)
On("PLAYER_REGEN_ENABLED", OnCombatEnd)
On("PLAYER_UNGHOST", OnRevived)
On("PLAYER_ALIVE", OnRevived)
On("CHAT_MSG_COMBAT_HONOR_GAIN", OnCombatMessage)
On("CHAT_MSG_SYSTEM", OnSystem)
On("UNIT_FACTION", CheckFlag, "player")
On("PLAYER_FLAGS_CHANGED", CheckFlag)
On("UPDATE_BATTLEFIELD_STATUS", OnBattlefieldStatus)
On("UPDATE_BATTLEFIELD_SCORE", function()
    if match and match.wantScore and ReadScore() then match.wantScore = false end
end)
On("PLAYER_XP_UPDATE", OnXP)
On("DUEL_REQUESTED", function(challenger)
    Track.count("W-190")                                      -- W-190 challenged to a duel
    -- W-187 the challenger's class, from the session's cache (your target may be anyone)
    challenger = Str(Safe(challenger))
    challenger = challenger and (challenger:match("^(.-)%-") or challenger)
    duel = { class = (ns.PlayerInfo(challenger) or {}).class }
end)
On("DUEL_FINISHED", function()
    if C_Timer and C_Timer.After then
        C_Timer.After(2, Protect(function() duel = nil end))  -- after the result message
    end
end)
ns.OnLoad(function()
    local function Manual() manualUntil = GetTime() + 3 end
    ns.Hook("TogglePVP", Protect(Manual))
    ns.Hook("SetPVP", Protect(Manual))
    ns.Hook("StartDuel", Protect(function()
        Track.count("W-185", "asked")                         -- W-185 duels you asked for
        duel = { class = DuelTarget() }
    end))
    ns.Hook("AcceptDuel", Protect(function()
        Track.count("W-185", "accepted")                      -- W-185 duels you accepted
        duel = duel or { class = DuelTarget() }
    end))
end)
ns.WrappedTick(Tick)
