-- JourneyTracker wrapped stats: dungeons and raids. IDs match
-- wrapped-tracking-spec.md:
--   Dungeons deep dive (W-191..W-239)
--   Raids (W-240..W-245)
-- The main tracker already keeps runs by name (#73-75), boss kills and
-- wipes by encounter (#41-42) and each death's dungeon and how you came
-- back (#48-49); this file adds what happens inside each run. A run starts
-- when you enter a dungeon or raid and ends when you leave it alive (a
-- corpse run is the same run).

local ADDON_NAME, ns = ...
local Track = ns.Track
local Safe, Call, Num, Str, IsSecret = ns.Safe, ns.Call, ns.Num, ns.Str, ns.IsSecret
local On, Protect = ns.WrappedOn, ns.Protect

-- Each dungeon's final boss (by the name the game uses for the encounter
-- or the kill), for clear times and abandoned runs. Forever's new
-- dungeons: the last in the client's own encounter list (DungeonEncounter,
-- which has the Classic ones' final bosses last too), for the ones its
-- beta client has; City of Dalaran's last is unclear. A dungeon not listed
-- counts as cleared at its last boss.
local FINAL_BOSSES = {
    ["Ragefire Chasm"] = "Taragaman the Hungerer", ["Wailing Caverns"] = "Mutanus the Devourer",
    ["The Deadmines"] = "Edwin VanCleef", ["Shadowfang Keep"] = "Archmage Arugal",
    ["Blackfathom Deeps"] = "Aku'mai", ["The Stockade"] = "Bazil Thredd", ["Stormwind Stockade"] = "Bazil Thredd",
    ["Gnomeregan"] = "Mekgineer Thermaplugg", ["Razorfen Kraul"] = "Charlga Razorflank",
    ["Razorfen Downs"] = "Amnennar the Coldbringer", ["Uldaman"] = "Archaedas", ["Zul'Farrak"] = "Chief Ukorz Sandscalp",
    ["Maraudon"] = "Princess Theradras", ["The Temple of Atal'Hakkar"] = "Shade of Eranikus",
    ["Sunken Temple"] = "Shade of Eranikus", ["Blackrock Depths"] = "Emperor Dagran Thaurissan",
    ["Lower Blackrock Spire"] = "Overlord Wyrmthalak", ["Upper Blackrock Spire"] = "General Drakkisath",
    ["Scholomance"] = "Darkmaster Gandling",
    ["Hall of Thanes"] = "Durgen Dirgehammer", ["Ruins of Lordaeron"] = "Bjork", ["Excavation Site"] = "Relic Guardian",
}
-- Wings, told apart by the bosses killed in them (W-208, W-209); a wing's
-- last boss also ends it for clear times. Blackrock Spire is one instance
-- to the game, so its halves are told apart the same way.
local WINGS = {
    ["Blackrock Spire"] = {
        { "Upper", { "Pyroguard Emberseer", "Solakar Flamewreath", "Goraluk Anvilcrack", "Warchief Rend Blackhand",
            "The Beast", "General Drakkisath" }, "General Drakkisath" },
        { "Lower", { "Highlord Omokk", "Shadow Hunter Vosh'gajin", "War Master Voone", "Mother Smolderweb",
            "Urok Doomhowl", "Quartermaster Zigris", "Halycon", "Gizrul the Slavener", "Overlord Wyrmthalak" },
            "Overlord Wyrmthalak" },
    },
    ["Scarlet Monastery"] = {
        { "Graveyard", { "Interrogator Vishas", "Bloodmage Thalnos" }, "Bloodmage Thalnos" },
        { "Library", { "Houndmaster Loksey", "Arcanist Doan" }, "Arcanist Doan" },
        { "Armory", { "Herod" }, "Herod" },
        { "Cathedral", { "Scarlet Commander Mograine", "High Inquisitor Whitemane", "High Inquisitor Fairbanks" },
            "High Inquisitor Whitemane" },
    },
    ["Dire Maul"] = {
        { "East", { "Pusillin", "Zevrim Thornhoof", "Hydrospawn", "Lethtendris", "Alzzin the Wildshaper" },
            "Alzzin the Wildshaper" },
        { "West", { "Tendris Warpwood", "Illyanna Ravenoak", "Magister Kalendris", "Immol'thar", "Prince Tortheldrin" },
            "Prince Tortheldrin" },
        { "North", { "Guard Mol'dar", "Stomper Kreeg", "Guard Fengus", "Guard Slip'kik", "Captain Kromcrush",
            "King Gordok" }, "King Gordok" },
    },
    ["Stratholme"] = {
        { "Live", { "The Unforgiven", "Timmy the Cruel", "Malor the Zealous", "Cannon Master Willey",
            "Archivist Galford", "Balnazzar" }, "Balnazzar" },
        { "Undead", { "Baroness Anastari", "Nerub'enkan", "Maleki the Pallid", "Magistrate Barthilas",
            "Ramstein the Gorger", "Baron Rivendare" }, "Baron Rivendare" },
    },
}
-- Forever's new dungeons (W-207), with their level ranges.
local NEW_DUNGEONS = { ["Hall of Thanes"] = { 13, 18 }, ["Ruins of Lordaeron"] = { 15, 20 },
    ["Excavation Site"] = { 24, 29 }, ["City of Dalaran"] = { 28, 33 }, ["The Drowned City"] = { 35, 40 },
    ["Krol'dok Stronghold"] = { 40, 45 }, ["Alcaz Island Prison"] = { 48, 53 }, ["Blackmaw Hold"] = { 55, 60 },
    ["Shaper's Terrace"] = { 58, 60 } }
-- Classic dungeons' level ranges, for runs far above them (W-231).
local LEVELS = { ["Ragefire Chasm"] = { 13, 18 }, ["Wailing Caverns"] = { 17, 24 }, ["The Deadmines"] = { 17, 26 },
    ["Shadowfang Keep"] = { 22, 30 }, ["Blackfathom Deeps"] = { 24, 32 }, ["The Stockade"] = { 24, 32 },
    ["Stormwind Stockade"] = { 24, 32 }, ["Gnomeregan"] = { 29, 38 }, ["Razorfen Kraul"] = { 29, 38 },
    ["Scarlet Monastery"] = { 34, 45 }, ["Razorfen Downs"] = { 37, 46 }, ["Uldaman"] = { 41, 51 },
    ["Zul'Farrak"] = { 42, 46 }, ["Maraudon"] = { 46, 55 }, ["The Temple of Atal'Hakkar"] = { 50, 56 },
    ["Sunken Temple"] = { 50, 56 }, ["Blackrock Depths"] = { 52, 60 }, ["Lower Blackrock Spire"] = { 55, 60 },
    ["Upper Blackrock Spire"] = { 55, 60 }, ["Blackrock Spire"] = { 55, 60 }, ["Dire Maul"] = { 55, 60 },
    ["Stratholme"] = { 58, 60 }, ["Scholomance"] = { 58, 60 } }
for name, range in pairs(NEW_DUNGEONS) do LEVELS[name] = range end
-- A table's entry for a dungeon, by the name the game gives it: Forever
-- adds the zone to some ("Excavation Site: Wetlands") and "The" to others
-- ("The Hall of Thanes").
local function Known(t, name)
    if type(name) ~= "string" then return nil end
    local base = name:match("^(.-):") or name
    return t[name] or t[base] or t[(base:gsub("^The ", ""))]
end
-- W-220 the Zul'Farrak stair event ends with these two coming down.
local ZF_STAIRS = { ["Nekrum Gutchewer"] = true, ["Shadowpriest Sezz'ziz"] = true }
-- Roles by talent tree, for W-234 when the game has no role set.
local ROLES = { WARRIOR = { "DPS", "DPS", "Tank" }, PALADIN = { "Healer", "Tank", "DPS" },
    PRIEST = { "Healer", "Healer", "DPS" }, DRUID = { "DPS", "Tank", "Healer" }, SHAMAN = { "DPS", "DPS", "Healer" } }
local BLUE = 3

---------------------------------------------------------------------------
-- Runs
---------------------------------------------------------------------------

-- The run you're in: { name, kind, start, level, killed = { [boss] = time() }, ... },
-- kept in db.wrapped (dungeonRun) with real times, so a /reload or a relog
-- inside carries on with the same run (W-192..W-235).
local run
local lastXP, lastXPMax
local hearthAt = 0
local encounter -- the encounter in progress: name
local lastBossKillAt = 0
local lastHitBy, lastHitAt -- the last spell that hit you and when, from the combat log where readable
local deadAt = {} -- party deaths in a fight, in order, for W-225 and W-226

local function InInstance()
    local inInstance, kind = Call("IsInInstance")
    if inInstance == true and (kind == "party" or kind == "raid") then return kind end
end

local function GroupUnits()
    local units, n = {}, Num(Call("GetNumGroupMembers")) or 0
    local raid = Call("IsInRaid") == true
    for i = 1, raid and n or (n - 1) do units[#units + 1] = (raid and "raid" or "party") .. i end
    return units
end

local function Role()
    local role = Str(Call("UnitGroupRolesAssigned", "player"))
    if role and role ~= "NONE" then
        return role == "TANK" and "Tank" or role == "HEALER" and "Healer" or "DPS"
    end
    local _, class = Call("UnitClass", "player")
    -- The tree with the most points (JourneyTrackerEconomy.lua reads them,
    -- on Classic clients or Forever's trait tree).
    local best, most = nil, -1
    for tab, tree in ipairs(ns.TalentTrees and ns.TalentTrees() or {}) do
        if tab <= 3 and tree.points > most then best, most = tab, tree.points end
    end
    local roles = ROLES[Str(class) or ""]
    if roles and best and most > 0 then return roles[best] end
    return "DPS"
end

-- Who's in the group: class counts only (W-233), and whether someone 10+
-- levels above you is carrying you (W-232).
local function LookAtGroup()
    if not run then return end
    local classes, me = {}, ns.Level()
    local _, myClass = Call("UnitClass", "player")
    classes[#classes + 1] = Str(myClass) or "?"
    for _, unit in ipairs(GroupUnits()) do
        if Call("UnitIsUnit", unit, "player") ~= true then
            local _, class = Call("UnitClass", unit)
            if Str(class) then classes[#classes + 1] = Str(class) end
            local level = Num(Call("UnitLevel", unit))
            if Track.enabled("probe") and level and level - me >= 10 then run.boosted = true end
        end
    end
    if #classes > #(run.party or {}) then
        table.sort(classes)
        run.party = classes
    end
end

local function WingOf(name, killed)
    for _, wing in ipairs(Known(WINGS, name) or {}) do
        for _, boss in ipairs(wing[2]) do
            if killed[boss] then return wing[1], wing[3] end
        end
    end
end

local function StartRun(kind)
    local name = Str(Call("GetInstanceInfo")) or ns.Zone()
    if run and run.name == name then return end
    run = { name = name, kind = kind, start = time(), t = time(), level = ns.Level(), bosses = {}, killed = {},
            deaths = 0, wipes = 0, xp = 0, role = Role() }
    Track.set("dungeonRun", run)
    deadAt = {}
    lastXP, lastXPMax = Num(Call("UnitXP", "player")), Num(Call("UnitXPMax", "player"))
    LookAtGroup()
end

local function FinishRun()
    local r = run
    run = nil
    Track.set("dungeonRun", nil)
    if not r then return end
    local duration = time() - r.start
    local wing, wingFinal = WingOf(r.name, r.killed)
    local key = wing and (r.name .. ": " .. wing) or r.name
    local final = wingFinal or Known(FINAL_BOSSES, r.name)
    local clear
    if final then
        clear = r.killed[final] and r.killed[final] - r.start or nil
    elseif r.lastBoss then
        clear = r.lastBoss - r.start                          -- dungeons not listed: to the last boss
    end
    if r.kind == "party" then
        if wing and r.name ~= "Blackrock Spire" then
            Track.count(r.name == "Scarlet Monastery" and "W-208" or "W-209", key) -- W-208 SM wings, W-209 DM and Strat
        end
        if clear then
            Track.list("W-192", { name = key, level = r.level, clear = math.floor(clear), t = r.t }, 100) -- W-192 clear times
            local fastest = Track.get("W-193")
            fastest = type(fastest) == "table" and fastest or {}
            if not fastest[key] or clear < fastest[key] then fastest[key] = math.floor(clear) end -- W-193 fastest
            Track.set("W-193", fastest)
        elseif (final and not r.killed[final]) or (not final and not r.lastBoss) then
            Track.count("W-195", key)                         -- W-195 runs abandoned
        end
        local new = Known(NEW_DUNGEONS, r.name) and "Forever" or "Classic"
        local split = Track.get("W-207")
        split = type(split) == "table" and split or {}
        split[new] = split[new] or { runs = 0, seconds = 0 }
        split[new].runs = split[new].runs + 1                 -- W-207 new vs Classic dungeons
        split[new].seconds = split[new].seconds + math.floor(duration)
        Track.set("W-207", split)
        if r.xp > 0 then Track.list("W-228", { name = key, level = r.level, xp = r.xp }, 100) end -- W-228 XP per run
        local range = Known(LEVELS, r.name)
        if range and r.level >= range[2] + 5 then Track.count("W-231", key) end -- W-231 run 5+ levels over
        if r.boosted then Track.count("W-232", key) end       -- W-232 boosted through it
        if r.party and #r.party >= 2 then Track.count("W-233", table.concat(r.party, ", ")) end -- W-233 compositions
        Track.count("W-234", r.role)                          -- W-234 role per run
        if GetTime() - hearthAt < 20 then Track.count("W-235", key) end -- W-235 hearthed out
    end
end

local function OnZone()
    -- After a /reload or relog: the run you were in, to carry on (still
    -- inside) or finish (back outside).
    if not run and type(Track.get("dungeonRun")) == "table" then
        run = Track.get("dungeonRun")
        lastXP, lastXPMax = Num(Call("UnitXP", "player")), Num(Call("UnitXPMax", "player"))
    end
    local kind = InInstance()
    if kind then
        StartRun(kind)
    elseif run and Call("UnitIsDeadOrGhost", "player") ~= true then
        FinishRun()
    end
end

---------------------------------------------------------------------------
-- Bosses, wipes and deaths
---------------------------------------------------------------------------

local wipeTicker

local function BossKilled(name)
    -- An encounter's end and its kill message both land here: once a run.
    if not run or not name or run.killed[name] then return end
    local now = time()
    run.killed[name] = now
    run.lastBoss = now
    lastBossKillAt = GetTime()
    local level = ns.Level()
    -- W-239 by Legacy bracket
    local bracket = level <= 25 and "15-25" or level <= 45 and "26-45" or "46-60"
    Track.count("W-239", bracket)
    -- W-197 the first kill of a dungeon's final boss
    local wing, wingFinal = WingOf(run.name, run.killed)
    if name == (wingFinal or Known(FINAL_BOSSES, run.name)) then
        Track.firstOf("W-197", wing and (run.name .. ": " .. wing) or run.name, { boss = name })
    end
    if ZF_STAIRS[name] and run.name == "Zul'Farrak" and not run.stairs then
        run.stairs = true
        Track.count("W-220")                                  -- W-220 the stair event survived
    end
    if run.kind == "raid" then
        local reached = ns.GetDB().reachedMax
        local extra = { boss = name, raid = run.name }
        if reached then extra.daysAfter60 = math.floor((time() - reached) / 86400) end
        Track.first("W-244", extra)                           -- W-244 60 to first raid boss
        if name == "Onyxia" then Track.first("W-242", extra) end -- W-242 Onyxia
    end
end

local function OnEncounterStart(_, name)
    name = Str(Safe(name))
    encounter = name
    deadAt = {}
end

local function OnEncounterEnd(_, name, _, _, success)
    name, success = Str(Safe(name)), Safe(success)
    encounter = nil
    if success == 1 or success == true then
        BossKilled(name)
    elseif run then
        Track.count("W-194", run.name)                        -- W-194 wipes per dungeon
    end
end

-- Kills by name catch bosses the game doesn't send encounter events for.
local function OnKill(k)
    if not run or not k.name then return end
    if Known(FINAL_BOSSES, run.name) == k.name or ZF_STAIRS[k.name] or k.name == "Onyxia" then BossKilled(k.name) end
    for _, wing in ipairs(Known(WINGS, run.name) or {}) do
        for _, boss in ipairs(wing[2]) do
            if boss == k.name then BossKilled(k.name) end
        end
    end
end

-- W-225 last one standing and W-226 first to fall in a wipe: who died
-- when, checked every second in a group fight in an instance.
local function CheckWipe()
    if not run then return end
    local now = GetTime()
    local units, allDead, any = GroupUnits(), true, false
    for _, unit in ipairs(units) do
        if Call("UnitIsUnit", unit, "player") ~= true then
            any = true
            local guid = Str(Call("UnitGUID", unit)) or unit
            if Call("UnitIsDeadOrGhost", unit) == true then
                deadAt[guid] = deadAt[guid] or now
            else
                deadAt[guid] = nil                            -- alive again: a later death is a new one
                allDead = false
            end
        end
    end
    local meDead = Call("UnitIsDeadOrGhost", "player") == true
    if meDead then deadAt.me = deadAt.me or now else deadAt.me = nil end
    if not any then return end
    if allDead and meDead and not run.wiped then
        run.wiped = true
        run.wipes = run.wipes + 1
        local first, last = true, true
        for who, at in pairs(deadAt) do
            if who ~= "me" then
                if at < deadAt.me then first = false end
                if at > deadAt.me then last = false end
            end
        end
        if first then Track.count("W-226") end
        if last then Track.count("W-225") end
    elseif not meDead and not allDead and run.wiped then
        run.wiped = false
        deadAt = {}
    end
end

local function OnDeath(rec, extra)
    if not run then return end
    if encounter then Track.count("W-227", encounter) end     -- W-227 dungeon deaths by boss
    if run.kind == "raid" then
        Track.count("W-245", run.name)                        -- W-245 deaths in raids
        local killer = rec.killer or ""
        if killer:find("Whelp", 1, true) then Track.count("W-245", "Onyxian whelps") end
        if lastHitBy == "Deep Breath" and GetTime() - (lastHitAt or 0) < 5 then
            Track.count("W-245", "Deep Breath")                -- the breath hit you moments before
        end
    end
end

---------------------------------------------------------------------------
-- XP, loot, quests, messages
---------------------------------------------------------------------------

local function OnXP()
    local xp, xpMax = Num(Call("UnitXP", "player")), Num(Call("UnitXPMax", "player"))
    if not xp then return end
    if run and lastXP then
        local gained = xp >= lastXP and xp - lastXP or (lastXPMax and (lastXPMax - lastXP) + xp) or 0
        if gained > 0 then run.xp = run.xp + gained end
    end
    lastXP, lastXPMax = xp, xpMax
end

-- W-229 blue (or better) items looted within a minute of a boss dying.
local function OnLoot(link, count, quality)
    if run and quality and quality >= BLUE and GetTime() - lastBossKillAt < 60 then
        Track.count("W-229", run.name, count)
    end
end

-- W-230 dungeon quests by dungeon: the quest log's header (the dungeon's
-- name) is remembered when you take the quest.
local questHeaders = {}
local function HeaderOf(questID)
    local index = Num(Call("C_QuestLog.GetLogIndexForQuestID", questID))
    if not index then return nil end
    for i = index, 1, -1 do
        local info = Call("C_QuestLog.GetInfo", i)
        if type(info) == "table" and Safe(info.isHeader) then return Str(Safe(info.title)) end
    end
end
local function OnQuestAccepted(a, b)
    local questID = Num(Safe(b)) or Num(Safe(a))
    if questID then questHeaders[questID] = HeaderOf(questID) end
end
local function OnQuestTurnedIn(questID)
    questID = Num(Safe(questID))
    if not questID then return end
    local info = Call("C_QuestLog.GetQuestTagInfo", questID)
    local tag = type(info) == "table" and Str(Safe(info.tagName))
    local header = questHeaders[questID] or HeaderOf(questID)
    if tag == "Dungeon" or (header and Known(LEVELS, header)) then
        Track.count("W-230", header or "Unknown")
    end
end

local TOO_MANY = "too many instances"
local lockoutAt = -10
local function OnMessage(msg)
    msg = Str(Safe(msg))
    if not msg or not msg:lower():find(TOO_MANY, 1, true) then return end
    -- The red error and the chat line are one lockout.
    if GetTime() - lockoutAt > 1 then Track.count("W-236") end -- W-236 instance lockouts
    lockoutAt = GetTime()
end

-- W-214 Naralex awakened: his disciple's last words in Wailing Caverns
-- ("awake" itself: on the way there they talk of awakening him).
local function OnMonsterSay(msg, speaker)
    msg, speaker = Str(Safe(msg)), Str(Safe(speaker))
    if not msg or not speaker or not run or run.name ~= "Wailing Caverns" then return end
    if speaker:find("Naralex", 1, true) and msg:lower():find("%f[%a]awake%f[%A]") and not run.naralex then
        run.naralex = true
        Track.count("W-214", "Naralex awakened")
    end
end

-- The combat log where Forever allows it: the last spell that hit you
-- (Onyxia's Deep Breath, W-245).
local myGUID
local function OnCombatLog()
    if not run or run.kind ~= "raid" or not Track.enabled("probe") or not CombatLogGetCurrentEventInfo then return end
    local _, sub, _, _, _, _, _, dst, _, _, _, _, spell = CombatLogGetCurrentEventInfo()
    if IsSecret(sub) or IsSecret(dst) or sub ~= "SPELL_DAMAGE" then return end
    myGUID = myGUID or Str(Call("UnitGUID", "player"))
    if dst == myGUID and not IsSecret(spell) then lastHitBy, lastHitAt = spell, GetTime() end
end

---------------------------------------------------------------------------
-- Window page
---------------------------------------------------------------------------

local function DrawDungeons(B)
    ns.ShowItems(B, {
        { heading = "Dungeons" },
        { "W-193", "Fastest clear per dungeon", "timemap" }, { "W-195", "Runs left before the final boss" },
        { "W-197", "First final-boss kills", "firsts" }, { "W-194", "Wipes per dungeon" },
        { "W-208", "Scarlet Monastery runs by wing" }, { "W-209", "Dire Maul and Stratholme runs" },
        { "W-207", "New Forever dungeons vs Classic" }, { "W-214", "Naralex awakened" },
        { "W-220", "Zul'Farrak stair events survived" }, { "W-225", "Last one standing in a wipe" },
        { "W-226", "First to fall in a wipe" }, { "W-227", "Deaths by boss" },
        { "W-229", "Blue boss drops looted, by dungeon" }, { "W-230", "Dungeon quests, by dungeon" },
        { "W-231", "Runs 5+ levels over" }, { "W-232", "Runs boosted by a much higher player" },
        { "W-233", "Party compositions" }, { "W-234", "Your role per run" },
        { "W-235", "Hearthed out of a dungeon" }, { "W-236", "'Too many instances' lockouts" },
        { "W-239", "Bosses by Legacy bracket" },
        { heading = "Raids" },
        { "W-242", "Onyxia, first kill" }, { "W-244", "First raid boss after 60" }, { "W-245", "Deaths in raids" },
    })
    local clears = Track.get("W-192")
    if type(clears) == "table" and #clears > 0 then
        B:Heading("Recent Clears")                                         -- W-192
        for i = #clears, math.max(1, #clears - 9), -1 do
            local c = clears[i]
            B:Row(c.name, string.format("%s at level %d", ns.UI.Dur(c.clear), c.level or 0))
        end
    end
end

ns.WrappedPage("Wrapped Stats", "Dungeons & Raids", DrawDungeons)

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------

ns.OnKill(OnKill)
ns.OnDeathRecord(OnDeath)
ns.OnLootItem(OnLoot)
ns.OnCast(Protect(function(name) if name == "Hearthstone" then hearthAt = GetTime() end end))
On("PLAYER_ENTERING_WORLD", OnZone)
On("ZONE_CHANGED_NEW_AREA", OnZone)
On("ENCOUNTER_START", OnEncounterStart)
On("ENCOUNTER_END", OnEncounterEnd)
On("GROUP_ROSTER_UPDATE", LookAtGroup)
On("PLAYER_XP_UPDATE", OnXP)
On("QUEST_ACCEPTED", OnQuestAccepted)
On("QUEST_TURNED_IN", OnQuestTurnedIn)
On("UI_ERROR_MESSAGE", function(_, msg) OnMessage(msg) end)
On("CHAT_MSG_SYSTEM", OnMessage)
On("CHAT_MSG_MONSTER_YELL", OnMonsterSay)
On("CHAT_MSG_MONSTER_SAY", OnMonsterSay)
On("COMBAT_LOG_EVENT_UNFILTERED", OnCombatLog)
On("PLAYER_DEAD", CheckWipe)
On("PLAYER_REGEN_DISABLED", function()
    if run and not wipeTicker and #GroupUnits() > 0 and C_Timer and C_Timer.NewTicker then
        wipeTicker = C_Timer.NewTicker(1, Protect(function()
            CheckWipe()
            if not run then wipeTicker:Cancel(); wipeTicker = nil end
        end))
    end
end)
On("PLAYER_ALIVE", CheckWipe)
On("PLAYER_UNGHOST", CheckWipe)
