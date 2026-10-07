-- JourneyTracker wrapped stats: kills and places. IDs match
-- wrapped-tracking-spec.md:
--   Creature kills: meme families (W-022..W-059)
--   Alliance iconic (W-060..W-083), Horde iconic (W-084..W-107), only for
--   that faction; the world PvP ones (W-080, W-091, W-100) are in
--   JourneyTrackerPvP.lua
--   Neutral zone iconic (W-108..W-129)
--   Rares and named mobs (W-130..W-139)
--   Boats and zeppelins (W-075, W-093, W-115, W-329, W-330, W-472)
--
-- Kills come from the main tracker (ns.OnKill), which sees the kills that
-- give experience. Kills that don't (critters, gray mobs, Gamon) are seen
-- when a target you attacked dies, and through the combat log where
-- Forever lets addons read it; both are [probe] and skip any kill the
-- experience message already counted. Mob names are matched on keywords in
-- the tables below, so a renamed mob is a one-line fix.

local ADDON_NAME, ns = ...
local Track = ns.Track
local Safe, Call, Num, Str, IsSecret = ns.Safe, ns.Call, ns.Num, ns.Str, ns.IsSecret
local On, Protect = ns.WrappedOn, ns.Protect

local VISIT_GAP = 600       -- seconds away before coming back counts as a new visit
local RIDE_WINDOW = 480     -- seconds from one port to the next for a boat or zeppelin ride

---------------------------------------------------------------------------
-- Name tables
---------------------------------------------------------------------------

-- W-022..W-059: a kill counts toward a family if its name has one of
-- `names` (and none of `except`), or its creature type is in `types`, or
-- its beast family is in `families`.
local FAMILIES = {
    { id = "W-022", label = "Murlocs", names = { "Murloc", "Bluegill", "Saltscale", "Greymist", "Torn Fin",
        "Mirefin", "Mudfin", "Murkgill" } },
    { id = "W-024", label = "Kobolds", names = { "Kobold", "Tunnel Rat" } },
    { id = "W-025", label = "Gnolls", names = { "Gnoll", "Riverpaw", "Redridge", "Shadowhide", "Mosshide",
        "Rot Hide", "Mudsnout", "Woodpaw", "Hogger" } },
    { id = "W-026", label = "Defias", names = { "Defias" } },
    { id = "W-027", label = "Harpies", names = { "Harpy", "Witchwing", "Bloodfeather", "Windfury", "Dustwind",
        "Roguefeather" } },
    { id = "W-028", label = "Centaurs", names = { "Centaur", "Kolkar", "Galak", "Maraudine", "Magram", "Gelkis" } },
    { id = "W-029", label = "Quilboar", names = { "Quilboar", "Razormane", "Bristleback", "Razorfen", "Death's Head" } },
    { id = "W-030", label = "Trolls", names = { "Troll", "Bloodscalp", "Skullsplitter", "Witherbark", "Vilebranch",
        "Smolderthorn", "Frostmane", "Mossflayer", "Hakkari", "Sandfury", "Gurubashi", "Darkspear" } },
    { id = "W-031", label = "Ogres", names = { "Ogre", "Mo'grosh", "Boulderfist", "Dunemaul", "Gordunni",
        "Splinterfist", "Crushridge", "Dustbelcher" } },
    { id = "W-032", label = "Naga", names = { "Naga", "Daggerspine", "Spitelash", "Slitherblade", "Wrathtail" } },
    { id = "W-033", label = "Satyrs", names = { "Satyr", "Hatefury", "Jadefire", "Bleakheart", "Felmusk" } },
    { id = "W-034", label = "Furbolgs", names = { "Furbolg", "Gnarlpine", "Foulweald", "Blackwood", "Thistlefur",
        "Timbermaw", "Deadwood", "Winterfall" } },
    { id = "W-035", label = "Troggs", names = { "Trogg", "Rockjaw", "Stonesplinter", "Stonevault" } },
    { id = "W-036", label = "Dark Iron dwarves", names = { "Dark Iron" } },
    { id = "W-037", label = "Scarlet Crusade", names = { "Scarlet" } },
    { id = "W-038", label = "Syndicate", names = { "Syndicate" } },
    { id = "W-039", label = "Venture Co.", names = { "Venture Co." } },
    { id = "W-040", label = "Bloodsail Buccaneers", names = { "Bloodsail" } },
    { id = "W-041", label = "Burning Blade", names = { "Burning Blade" } },
    { id = "W-042", label = "Scourge undead", types = { "Undead" } },
    { id = "W-043", label = "Spiders", names = { "Spider", "Widow", "Tarantula", "Recluse" }, families = { "Spider" } },
    { id = "W-044", label = "Raptors", names = { "Raptor" }, families = { "Raptor" } },
    { id = "W-045", label = "Crocolisks", names = { "Crocolisk" }, families = { "Crocolisk" } },
    { id = "W-046", label = "Wolves and worgs", names = { "Wolf", "Worg" }, except = { "Worgen" },
        families = { "Wolf" } },
    { id = "W-047", label = "Boars", names = { "Boar" }, families = { "Boar" } },
    { id = "W-048", label = "Bears", names = { "Bear" }, families = { "Bear" } },
    { id = "W-049", label = "Gorillas", names = { "Gorilla", "Silverback" }, families = { "Gorilla" } },
    { id = "W-050", label = "Scorpids", names = { "Scorpid" }, families = { "Scorpid" } },
    { id = "W-051", label = "Kodos", names = { "Kodo" } },
    { id = "W-052", label = "Big cats", names = { "Panther", "Tiger", "Lion", "Nightsaber", "Frostsaber", "Saber",
        "Cougar", "Puma", "Lynx" }, families = { "Cat" } },
    { id = "W-053", label = "Whelps and dragonkin", names = { "Whelp", "Drake", "Dragon" }, except = { "Dragonmaw" },
        types = { "Dragonkin" } },
    { id = "W-054", label = "Elementals", types = { "Elemental" } },
    { id = "W-055", label = "Demons", types = { "Demon" } },
    { id = "W-056", label = "Yetis", names = { "Yeti" } },
    { id = "W-057", label = "Critters", types = { "Critter" } },
    { id = "W-058", label = "Chickens", names = { "Chicken" } },
    { id = "W-059", label = "Rabbits and squirrels", names = { "Rabbit", "Hare", "Squirrel" } },
}

-- Iconic kills: `exact` names, or `names` keywords; optionally only in
-- `zone` (and `subzones`); for one `faction`. `first` keeps the level,
-- /played and date of the first; `by = true` counts by the keyword matched.
local ICONIC_KILLS = {
    { id = "W-060", faction = "Alliance", exact = { "Hogger" }, first = true },
    { id = "W-062", faction = "Alliance", exact = { "Princess" }, first = true },
    { id = "W-063", faction = "Alliance", exact = { "Edwin VanCleef" }, first = true },
    { id = "W-064", faction = "Alliance", names = { "Kobold" }, zone = "Elwynn Forest",
        subzones = { "Fargodeep Mine", "Jasperlode Mine" } },
    { id = "W-065", faction = "Alliance", names = { "Harvest Watcher" } },
    { id = "W-066", faction = "Alliance", names = { "Defias Pillager", "Defias Messenger" }, zone = "Westfall" },
    { id = "W-067", faction = "Alliance", exact = { "Bellygrub" }, first = true },
    { id = "W-068", faction = "Alliance", names = { "Blackrock" }, zone = "Redridge Mountains" },
    { id = "W-069", faction = "Alliance", exact = { "Stitches" }, first = true },
    { id = "W-070", faction = "Alliance", exact = { "Mor'Ladim" }, first = true },
    { id = "W-071", faction = "Alliance", names = { "Worgen", "Nightbane" }, zone = "Duskwood" },
    { id = "W-083", faction = "Alliance", names = { "Dragonmaw" }, zone = "Wetlands" },
    { id = "W-085", faction = "Horde", names = { "Kolkar" }, zone = "The Barrens" },
    { id = "W-086", faction = "Horde", exact = { "Echeyakee" }, first = true },
    { id = "W-087", faction = "Horde", exact = { "Lakota'mani" }, first = true },
    { id = "W-088", faction = "Horde", names = { "Plainstrider" }, zone = "The Barrens" },
    { id = "W-092", faction = "Horde", exact = { "Gamon" } },
    { id = "W-104", faction = "Horde", names = { "Scorpid" }, zone = "Durotar" },
    { id = "W-105", faction = "Horde", names = { "Scarlet" }, zone = "Tirisfal Glades" },
    { id = "W-106", faction = "Horde", names = { "Moonrage", "Worgen", "Son of Arugal" }, zone = "Silverpine Forest" },
    { id = "W-110", names = { "Tiger", "Panther", "Raptor" }, zone = "Stranglethorn Vale", by = true },
    { id = "W-111", exact = { "King Bangalash" }, first = true },
    { id = "W-117", names = { "Devilsaur" }, zone = "Un'Goro Crater" },
    { id = "W-126", names = { "Yeti" }, zone = "Winterspring" },
    { id = "W-127", names = { "Magram", "Gelkis" }, zone = "Desolace", by = true },
}

-- Visits: entering a zone or subzone, counted again after VISIT_GAP away.
-- `by` counts by place name.
local VISITS = {
    { id = "W-072", faction = "Alliance", zones = { "Deeprun Tram" } },
    { id = "W-073", faction = "Alliance", zones = { "Ironforge", "Stormwind City", "Darnassus" }, by = true },
    { id = "W-077", faction = "Alliance", subzones = { "Southshore" } },
    { id = "W-078", faction = "Alliance", subzones = { "Theramore Isle" } },
    { id = "W-079", faction = "Alliance", zones = { "Orgrimmar", "Thunder Bluff", "Undercity" }, by = true },
    { id = "W-097", faction = "Horde", zones = { "Orgrimmar", "Thunder Bluff", "Undercity" }, by = true },
    { id = "W-099", faction = "Horde", subzones = { "Tarren Mill" } },
    { id = "W-101", faction = "Horde", subzones = { "Grom'gol Base Camp", "Kargath", "Hammerfall", "Stonard" }, by = true },
    { id = "W-102", faction = "Horde", zones = { "Stormwind City", "Ironforge", "Darnassus" }, by = true },
    { id = "W-107", faction = "Horde", subzones = { "Kodo Graveyard" } },
    { id = "W-112", subzones = { "Gurubashi Arena" } },
    { id = "W-115", subzones = { "Booty Bay" } },
    { id = "W-123", subzones = { "The Dark Portal" } },
    { id = "W-124", subzones = { "Karazhan" } },
    { id = "W-125", subzones = { "Wyrmbog" }, zones = { "Onyxia's Lair" } },
}

-- Quests by title: `exact` titles or a `pattern`.
local ICONIC_QUESTS = {
    { id = "W-084", faction = "Horde", exact = { "Lost in Battle" }, first = true },
    { id = "W-109", pattern = "^Chapter [IVX]+$" },
    { id = "W-120", exact = { "The Northern Pylon", "The Eastern Pylon", "The Western Pylon" }, by = true },
    { id = "W-121", pattern = "A%-Me 01" },
    { id = "W-122", exact = { "Water Pouch Bounty" } },
}

-- Loot by item name: `pattern` or `exact`, `by` for a map, `first` for a record.
local ICONIC_LOOT = {
    { id = "W-108", pattern = "^Green Hills of Stranglethorn %- Page" },
    { id = "W-112.trinket", exact = { "Arena Master" }, first = true },
    { id = "W-119", exact = { "Red Power Crystal", "Blue Power Crystal", "Green Power Crystal", "Yellow Power Crystal" },
        by = true },
}

-- Boats and zeppelins: docks by subzone (or by zone for the zeppelin towers
-- outside Orgrimmar and Undercity), and the routes between them.
local DOCKS_BY_SUBZONE = { ["Menethil Harbor"] = "Menethil Harbor", ["Auberdine"] = "Auberdine",
    ["Theramore Isle"] = "Theramore", ["Rut'theran Village"] = "Rut'theran Village", ["Booty Bay"] = "Booty Bay",
    ["Ratchet"] = "Ratchet", ["Grom'gol Base Camp"] = "Grom'gol" }
local DOCKS_BY_ZONE = { ["Durotar"] = "Orgrimmar", ["Tirisfal Glades"] = "Undercity" }
local BOAT_DOCKS = { ["Menethil Harbor"] = true, ["Auberdine"] = true, ["Theramore"] = true,
    ["Rut'theran Village"] = true, ["Booty Bay"] = true, ["Ratchet"] = true }
local ROUTES = {
    ["Menethil Harbor|Auberdine"] = "boat", ["Menethil Harbor|Theramore"] = "boat",
    ["Auberdine|Rut'theran Village"] = "boat", ["Booty Bay|Ratchet"] = "boat",
    ["Orgrimmar|Undercity"] = "zeppelin", ["Orgrimmar|Grom'gol"] = "zeppelin", ["Undercity|Grom'gol"] = "zeppelin",
}

-- Starting zones by race, with the capital next door (W-082).
local HOMES = { Human = { "Elwynn Forest", "Stormwind City" }, Dwarf = { "Dun Morogh", "Ironforge" },
    Gnome = { "Dun Morogh", "Ironforge" }, NightElf = { "Teldrassil", "Darnassus" },
    Orc = { "Durotar", "Orgrimmar" }, Troll = { "Durotar", "Orgrimmar" }, Tauren = { "Mulgore", "Thunder Bluff" },
    Scourge = { "Tirisfal Glades", "Undercity" } }

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function Faction() return Str(Call("UnitFactionGroup", "player")) end
local function ForMe(entry) return not entry.faction or entry.faction == Faction() end

local function HasAny(text, list)
    if not text or not list then return nil end
    for _, word in ipairs(list) do
        if text:find(word, 1, true) then return word end
    end
end
local function IsIn(value, list)
    if value == nil or not list then return false end
    for _, v in ipairs(list) do if v == value then return true end end
    return false
end

-- Which families a kill belongs to.
local function FamiliesOf(name, ctype, family)
    local out = {}
    for _, f in ipairs(FAMILIES) do
        if (HasAny(name, f.names) and not HasAny(name, f.except)) or IsIn(ctype, f.types) or IsIn(family, f.families) then
            out[#out + 1] = f.id
        end
    end
    return out
end

ns.FamiliesOf = FamiliesOf -- the death memes (JourneyTrackerWorld.lua) ask about killers

local function IsElite(class) return class == "elite" or class == "rareelite" or class == "worldboss" end
local function IsRare(class) return class == "rare" or class == "rareelite" end

---------------------------------------------------------------------------
-- Kills
---------------------------------------------------------------------------

local wanted -- W.wanted: names on your "Wanted" quests (W-132)

-- Every kill: XP kills from the main tracker and the ones without XP seen
-- here (`noXP`). k = { name, level, mobLevel, class, ctype, family, zone,
-- subzone, grouped }.
local function CountKill(k)
    local name = k.name
    if not name then return end
    if Track.enabled("probe") then
        for _, id in ipairs(FamiliesOf(name, k.ctype, k.family)) do Track.count(id) end -- W-022..W-059
    end
    for _, e in ipairs(ICONIC_KILLS) do
        if ForMe(e) and (not e.zone or e.zone == k.zone) and (not e.subzones or IsIn(k.subzone, e.subzones)) then
            local hit = (e.exact and IsIn(name, e.exact) and name) or HasAny(name, e.names)
            if hit then
                if e.first then
                    Track.first(e.id, { name = name })
                elseif e.by then
                    Track.count(e.id, hit)
                else
                    Track.count(e.id)
                end
            end
        end
    end
    if k.noXP then return end
    -- Rares and elites (W-130..W-139)
    if IsRare(k.class) then
        Track.count("W-130", "killed")
        Track.count("W-131", k.zone or "?")                   -- W-131 rare kills by zone
        Track.first("W-133", { name = name, mobLevel = k.mobLevel and k.mobLevel > 0 and k.mobLevel or nil,
                               skull = k.mobLevel == -1 or nil }) -- W-133 first rare
    end
    if wanted and wanted[name] then Track.count("W-132", name) end -- W-132 named bounty targets
    if IsElite(k.class) and not k.grouped then
        Track.count("W-135")                                  -- W-135 elites soloed
        if k.mobLevel and k.mobLevel > 0 then
            Track.max("W-137", k.mobLevel, { name = name })   -- W-137 highest-level elite soloed
        end
    end
    if k.mobLevel and (k.mobLevel == -1 or k.mobLevel - (k.level or 0) >= 5) then
        Track.count("W-138")                                  -- W-138 mobs 5+ levels above you
    end
end

-- W-023 the most murlocs in one fight; W-061 fights with Hogger; W-139
-- attacked by something 10+ levels above you.
local function OnFight(fight)
    local murlocs = 0
    for _, k in ipairs(fight.kills or {}) do
        for _, id in ipairs(FamiliesOf(k.name, k.ctype, k.family)) do
            if id == "W-022" then murlocs = murlocs + 1 end
        end
    end
    if murlocs > 0 and Track.enabled("probe") then Track.max("W-023", murlocs) end
    if Faction() == "Alliance" and fight.names and fight.names["Hogger"] then
        Track.count("W-061", "attempts")
    end
    local top = fight.maxMobLevel
    if top and (top == -1 or top - ns.Level() >= 10) then Track.count("W-139") end
end

-- W-130 a rare you saw (on a nameplate or targeted), once per spawn.
local seenRares = {}
local function SeenRare(guid)
    if not guid or seenRares[guid] then return end
    seenRares[guid] = true
    Track.count("W-130", "seen")
end

-- Kills without experience: the target you attacked died and no
-- experience message named it. Checked twice a second while you fight it.
local recentXP = {}       -- [name] = GetTime() of its experience message
local counted = {}        -- [guid] = true, kills already counted (with or without XP)
local watched, watchTicker

-- Kills without experience, for the other files (ns.OnNoXPKill): at 60
-- every kill is one (enemy guards and faction leaders, JourneyTrackerPvP.lua).
local noXPListeners = {}
function ns.OnNoXPKill(fn) table.insert(noXPListeners, Protect(fn)) end

local function CountNoXP(guid, info)
    if not guid or counted[guid] then return end
    counted[guid] = true
    -- Give the experience message a moment: if it names this mob, the main
    -- tracker has the kill.
    local function Decide()
        local seen = info.name and recentXP[info.name]
        if seen and math.abs(GetTime() - seen) < 3 then return end
        local k = { name = info.name, ctype = info.ctype, family = info.family, class = info.class,
                    mobLevel = info.level, level = ns.Level(), zone = ns.Zone(), subzone = ns.SubZone(), noXP = true }
        CountKill(k)
        for _, fn in ipairs(noXPListeners) do fn(k) end
    end
    if C_Timer and C_Timer.After then C_Timer.After(1, Protect(Decide)) else Decide() end
end

local function StopWatch()
    if watchTicker then watchTicker:Cancel() end
    watchTicker, watched = nil, nil
end

local function CheckWatched()
    if not watched then return StopWatch() end
    if Str(Call("UnitGUID", "target")) ~= watched.guid then return StopWatch() end
    if Call("UnitIsTapDenied", "target") == true then return StopWatch() end -- someone else's kill
    if Call("UnitIsDead", "target") == true then
        CountNoXP(watched.guid, watched)
        StopWatch()
    end
end

local function WatchTarget()
    StopWatch()
    if not Track.enabled("probe") or Call("UnitIsPlayer", "target") ~= false then return end
    if Call("UnitCanAttack", "player", "target") ~= true then return end
    local guid = Str(Call("UnitGUID", "target"))
    if not guid or counted[guid] then return end
    watched = { guid = guid, name = Str(Call("UnitName", "target")), ctype = Str(Call("UnitCreatureType", "target")),
                family = Str(Call("UnitCreatureFamily", "target")), class = Str(Call("UnitClassification", "target")),
                level = Num(Call("UnitLevel", "target")) }
    if IsRare(watched.class) then SeenRare(guid) end
    -- A corpse (looted, skinned, or killed before you looked) or a mob
    -- someone else has tagged isn't a kill of yours to wait for.
    if Call("UnitIsDead", "target") == true or Call("UnitIsTapDenied", "target") == true then watched = nil end
end

-- You attacked it: auto-attack started, or a spell went off at it.
local function Attacked()
    if not watched or watchTicker or not (C_Timer and C_Timer.NewTicker) then return end
    watchTicker = C_Timer.NewTicker(0.5, Protect(CheckWatched))
end

-- The combat log, where Forever lets addons read it: PARTY_KILL by you.
-- Kills of players go to the PvP tracker (ns.OnPartyKill).
local partyKillListeners = {}
function ns.OnPartyKill(fn) table.insert(partyKillListeners, Protect(fn)) end
local myGUID
local PLAYER_FLAG = 0x400 -- COMBATLOG_OBJECT_TYPE_PLAYER
local function OnCombatLog()
    if not Track.enabled("probe") or not CombatLogGetCurrentEventInfo then return end
    local _, sub, _, src, _, _, _, dst, dstName, dstFlags = CombatLogGetCurrentEventInfo()
    if IsSecret(sub) or sub ~= "PARTY_KILL" then return end
    if IsSecret(src) or IsSecret(dst) or IsSecret(dstName) or IsSecret(dstFlags) then return end
    myGUID = myGUID or Str(Call("UnitGUID", "player"))
    if not myGUID or src ~= myGUID then return end
    local isPlayer = type(dstFlags) == "number" and bit and bit.band and bit.band(dstFlags, PLAYER_FLAG) ~= 0
    if isPlayer then
        for _, fn in ipairs(partyKillListeners) do fn(dst, dstName) end
        return
    end
    local info = ns.MobInfo(dstName) or {}
    CountNoXP(dst, { name = dstName, ctype = info.ctype, family = info.family, class = info.class, level = info.level })
end

---------------------------------------------------------------------------
-- Deaths
---------------------------------------------------------------------------

local lastInThunderBluff = 0

local function OnDeath(rec, extra)
    local killer = rec.killer or ""
    local mob = extra and extra.mob
    if Faction() == "Alliance" and killer == "Hogger" then Track.count("W-061", "deaths") end -- W-061
    if Faction() == "Horde" and killer == "Falling" and Track.enabled("probe")
        and (rec.zone == "Undercity" or rec.subzone == "Ruins of Lordaeron") then
        Track.count("W-095")                                  -- W-095 fell from the Undercity elevator
    end
    if killer:find("Bruiser", 1, true) then Track.count("W-116", killer) end -- W-116 goblin town guards
    if killer:find("Devilsaur", 1, true) then Track.count("W-118") end       -- W-118 deaths to devilsaurs
    if mob and IsRare(mob.class) then Track.count("W-134", killer) end       -- W-134 rares that killed you
    if mob and IsElite(mob.class) then Track.count("W-136") end              -- W-136 elite deaths
end

-- W-094/W-096 an elevator ride counts a few seconds after the zone
-- changes, unless a long fall lands first: jumping off isn't a ride.
local pendingRide
local function ElevatorRide(id, key)
    local ride = {}
    pendingRide = ride
    local function Count()
        if pendingRide ~= ride then return end
        pendingRide = nil
        Track.count(id, key)
    end
    if C_Timer and C_Timer.After then C_Timer.After(10, Protect(Count)) else Count() end
end

-- W-096 falls off Thunder Bluff: a long fall landing in Mulgore just after
-- being up on the bluffs.
local function OnFall(fall)
    if fall.yards >= 30 then pendingRide = nil end
    if Faction() == "Horde" and fall.zone == "Mulgore" and fall.yards >= 30
        and GetTime() - lastInThunderBluff < 15 then
        Track.count("W-096", "falls")
    end
end

---------------------------------------------------------------------------
-- Places: visits, elevators, portals, boats and zeppelins
---------------------------------------------------------------------------

local lastZone, lastSubZone, lastSubZoneAt
local lastDock            -- { name, t } the last boat or zeppelin dock seen
local travelMark = 0      -- GetTime() of the last flight, hearth, teleport or summon (rides can't follow one)

-- Visits (W-072..W-125): when each place was last seen (time()), kept in
-- db.wrapped (visitsSeen) so a /reload or relog where you stand isn't a
-- new visit. Seen again every 5 seconds while you're there; dropped once
-- older than VISIT_GAP.
local function SeenPlaces()
    local seen = Track.get("visitsSeen")
    if type(seen) ~= "table" then
        seen = {}
        Track.set("visitsSeen", seen)
    end
    return seen
end

-- `already`: you were there already (logging in), so it isn't a visit.
local function Visit(seen, e, place, already)
    local key = e.id .. "|" .. place
    local now = time()
    local away = not seen[key] or now - seen[key] > VISIT_GAP
    seen[key] = now
    if not away or already then return end
    if e.by then Track.count(e.id, place) else Track.count(e.id) end
end

local function CheckVisits(zone, subzone, already)
    local seen, now = SeenPlaces(), time()
    for key, at in pairs(seen) do
        if now - at > VISIT_GAP then seen[key] = nil end
    end
    for _, e in ipairs(VISITS) do
        if ForMe(e) then
            if IsIn(zone, e.zones) then Visit(seen, e, zone, already) end
            if IsIn(subzone, e.subzones) then Visit(seen, e, subzone, already) end
        end
    end
end

local function DockOf(zone, subzone)
    return (subzone and DOCKS_BY_SUBZONE[subzone]) or DOCKS_BY_ZONE[zone]
end

-- A ride: from one dock to another on a known route, with no flight or
-- hearth in between. On a flight path nothing below is a dock you're at.
local function CheckRide(zone, subzone)
    local now = GetTime()
    if Call("UnitOnTaxi", "player") == true then
        travelMark = now
        return
    end
    local dock = DockOf(zone, subzone)
    if not dock then return end
    if lastDock and lastDock.name ~= dock and now - lastDock.t <= RIDE_WINDOW and lastDock.t > travelMark then
        local a, b = lastDock.name, dock
        local kind = ROUTES[a .. "|" .. b] or ROUTES[b .. "|" .. a]
        if kind then
            local route = a .. " to " .. b
            Track.count(kind == "boat" and "W-329" or "W-330")    -- W-329 boat rides, W-330 zeppelin rides
            Track.first("W-472", { ride = route })                -- W-472 first boat or zeppelin ride
            if (a == "Booty Bay" or b == "Booty Bay") and (a == "Ratchet" or b == "Ratchet") then
                Track.count("W-115.rides")                        -- W-115 Booty Bay boat rides
            end
            if kind == "boat" and Faction() == "Alliance" and not IsIn("Booty Bay", { a, b }) then
                Track.count("W-075", route)                       -- W-075 Alliance boat routes
            elseif kind == "zeppelin" and Faction() == "Horde" then
                Track.count("W-093", route)                       -- W-093 zeppelin routes
            end
        end
    end
    lastDock = { name = dock, t = now }
end

-- W-082 the level you left your starting zone, if the tracker saw it.
local function CheckLeftHome(from, to)
    if Faction() ~= "Alliance" or Track.get("W-082") ~= nil or Track.get("outsideHome") then return end
    local _, race = Call("UnitRace", "player")
    local home = HOMES[Str(race) or ""]
    if not home or not IsIn(from, home) then return end
    if to and not IsIn(to, home) and to ~= "Deeprun Tram" then
        Track.first("W-082", { from = from, to = to })
        Track.set("outsideHome", true)
    end
end

-- Zone changes, and every 5 seconds (Tick) to keep "last seen here" times
-- fresh while you stay put. `already`: just logged in where you are.
local function OnZone(already)
    local zone, subzone = ns.Zone(), ns.SubZone()
    if zone == "Unknown" then return end -- the zone's name read empty for a moment: not a place (W-082)
    local now = GetTime()
    local onTaxi = Call("UnitOnTaxi", "player") == true
    if zone ~= lastZone then
        local from = lastZone
        if from then
            CheckLeftHome(from, zone)
            -- W-094 Undercity elevators (between the ruins and the city) and
            -- W-096 Thunder Bluff's (between the bluffs and Mulgore): not by
            -- air, not just after a hearth or teleport, not falling off (OnFall)
            local walked = not onTaxi and now - travelMark > 30
            if Faction() == "Horde" and walked and ((from == "Undercity" and zone == "Tirisfal Glades")
                or (from == "Tirisfal Glades" and zone == "Undercity")) then
                ElevatorRide("W-094")
            end
            if Faction() == "Horde" and walked
                and ((from == "Thunder Bluff" and zone == "Mulgore") or (from == "Mulgore" and zone == "Thunder Bluff")) then
                ElevatorRide("W-096", "elevator rides")
            end
            if from == "Thunder Bluff" then lastInThunderBluff = now end
            -- W-076 the Rut'theran portal: Darnassus moments after Rut'theran
            if Faction() == "Alliance" and zone == "Darnassus" and lastSubZone == "Rut'theran Village"
                and lastSubZoneAt and now - lastSubZoneAt < 15 then
                Track.count("W-076")
                Track.count("W-331", "Rut'theran to Darnassus")  -- W-331 portals used
            end
        end
        lastZone = zone
    end
    if zone == "Thunder Bluff" then lastInThunderBluff = now end
    if subzone ~= lastSubZone then lastSubZone = subzone end
    lastSubZoneAt = now
    if not onTaxi then CheckVisits(zone, subzone, already) end -- towns flown over aren't visits
    CheckRide(zone, subzone)
end

-- A flight, hearth, teleport, portal or summon: a boat ride can't follow one.
local function Traveled() travelMark = GetTime() end

---------------------------------------------------------------------------
-- Quests, loot, chat
---------------------------------------------------------------------------

local function OnQuestAccepted(a, b)
    local questID = Num(Safe(b)) or Num(Safe(a))
    local title = questID and Str(Call("C_QuestLog.GetTitleForQuestID", questID))
    local target = title and (title:match("^[Ww][Aa][Nn][Tt][Ee][Dd]:%s*(.+)$"))
    if target then
        target = target:gsub("[!%.]+$", "")
        wanted = Track.get("wanted") or {}
        local n = 0
        for _ in pairs(wanted) do n = n + 1 end
        if n < 50 then wanted[target] = true end
        Track.set("wanted", wanted)
    end
end

local function OnQuestTurnedIn(questID)
    questID = Num(Safe(questID))
    local title = questID and Str(Call("C_QuestLog.GetTitleForQuestID", questID))
    if not title then return end
    for _, e in ipairs(ICONIC_QUESTS) do
        if ForMe(e) and ((e.exact and IsIn(title, e.exact)) or (e.pattern and title:find(e.pattern))) then
            if e.first then Track.first(e.id) elseif e.by then Track.count(e.id, title) else Track.count(e.id) end
        end
    end
end

local function OnLoot(link, count)
    local name = link and link:match("%[(.-)%]")
    if not name then return end
    for _, e in ipairs(ICONIC_LOOT) do
        if (e.exact and IsIn(name, e.exact)) or (e.pattern and name:find(e.pattern)) then
            if e.first then
                Track.first(e.id, { name = name })
            elseif e.by then
                Track.count(e.id, name, count)
            else
                Track.count(e.id, nil, count)
            end
        end
    end
end

-- W-089 Barrens General messages seen, W-090 the ones about Chuck Norris.
-- Counts only: the text is read to match, never kept.
local function OnChannel(text, _, _, channel)
    if Faction() ~= "Horde" or ns.Zone() ~= "The Barrens" then return end
    channel = Str(Safe(channel))
    if not channel or not channel:find("General", 1, true) then return end
    Track.count("W-089")
    text = Str(Safe(text))
    if text and text:lower():find("chuck norris", 1, true) then Track.count("W-090") end
end

---------------------------------------------------------------------------
-- Every 5 seconds: AFK in the capitals, zones by level bracket, contested time
---------------------------------------------------------------------------

local function Tick(dt)
    OnZone() -- still here: visits, the dock you're at, Rut'theran and Thunder Bluff stay fresh
    local zone = ns.Zone()
    local s = math.floor(dt + 0.5)
    if Call("UnitIsAFK", "player") == true then
        if zone == "Ironforge" and Faction() == "Alliance" then Track.count("W-074", nil, s) end -- W-074
        if zone == "Orgrimmar" and Faction() == "Horde" then Track.count("W-098", nil, s) end    -- W-098
        return
    end
    -- W-128 time per zone in each 10-level bracket (the website picks the top one)
    local bracket = math.floor(ns.Level() / 10) * 10
    local W128 = Track.get("W-128")
    W128 = type(W128) == "table" and W128 or {}
    W128[bracket] = W128[bracket] or {}
    W128[bracket][zone] = (W128[bracket][zone] or 0) + s
    Track.set("W-128", W128)
    -- W-129 contested vs friendly (and hostile, sanctuary) zones; "unknown"
    -- for a place with no type (a dungeon; Forever's own zones before 0.6.9),
    -- "unrestricted" before 0.6.8
    local kind = ns.ZonePvP() or "unknown"
    Track.count("W-129", kind, s)
end

---------------------------------------------------------------------------
-- Window pages
---------------------------------------------------------------------------

local function DrawFamilies(B)
    local rows = { { heading = "Creatures Slain" } }
    for _, f in ipairs(FAMILIES) do
        rows[#rows + 1] = { f.id, f.label }
        if f.id == "W-022" then rows[#rows + 1] = { "W-023", "Most murlocs in one fight" } end
    end
    rows[#rows + 1] = { note = "Kills that give no experience (critters, gray mobs) are counted when a target you attacked dies." }
    ns.ShowItems(B, rows)
end

local function DrawIconic(B)
    local f = Faction()
    if f == "Alliance" then
        ns.ShowItems(B, {
            { heading = "Alliance" },
            { "W-060", "Hogger, first kill" }, { "W-061", "Hogger: fights and deaths" },
            { "W-062", "Princess, first kill" }, { "W-063", "Edwin VanCleef, first kill" },
            { "W-064", "Kobolds slain in Elwynn's mines" }, { "W-065", "Harvest Watchers slain" },
            { "W-066", "Defias Pillagers and Messengers slain in Westfall" }, { "W-067", "Bellygrub, first kill" },
            { "W-068", "Blackrock orcs slain in Redridge" }, { "W-069", "Stitches, first kill" },
            { "W-070", "Mor'Ladim, first kill" }, { "W-071", "Worgen slain in Duskwood" },
            { "W-072", "Deeprun Tram rides" }, { "W-073", "Times you entered the capitals" },
            { "W-074", "Time AFK in Ironforge", "time" }, { "W-075", "Boat rides by route" },
            { "W-076", "Rut'theran portal to Darnassus" }, { "W-077", "Visits to Southshore" },
            { "W-078", "Visits to Theramore" }, { "W-079", "Times you entered Horde capitals" },
            { "W-081", "Racial mount bought" }, { "W-082", "Left your starting zone" },
            { "W-083", "Dragonmaw orcs slain in the Wetlands" },
        })
    elseif f == "Horde" then
        ns.ShowItems(B, {
            { heading = "Horde" },
            { "W-084", "Mankrik's wife found" }, { "W-085", "Kolkar centaurs slain in the Barrens" },
            { "W-086", "Echeyakee, first kill" }, { "W-087", "Lakota'mani, first kill" },
            { "W-088", "Plainstriders slain in the Barrens" }, { "W-089", "Barrens General messages seen" },
            { "W-090", "...mentioning Chuck Norris" }, { "W-092", "Gamon slain" },
            { "W-093", "Zeppelin rides by route" }, { "W-094", "Undercity elevator rides" },
            { "W-095", "Deaths falling from the Undercity elevator" }, { "W-096", "Thunder Bluff elevator rides and falls" },
            { "W-097", "Times you entered the capitals" }, { "W-098", "Time AFK in Orgrimmar", "time" },
            { "W-099", "Visits to Tarren Mill" }, { "W-101", "Visits to Horde outposts" },
            { "W-102", "Times you entered Alliance capitals" }, { "W-103", "Racial mount bought" },
            { "W-104", "Scorpids slain in Durotar" }, { "W-105", "Scarlet Crusaders slain in Tirisfal" },
            { "W-106", "Worgen slain in Silverpine" }, { "W-107", "Visits to the Kodo Graveyard" },
        })
    end
    ns.ShowItems(B, {
        { heading = "Around the World" },
        { "W-108", "Green Hills of Stranglethorn pages looted" }, { "W-109", "Green Hills chapters turned in" },
        { "W-110", "Nesingwary hunts in Stranglethorn" }, { "W-111", "King Bangalash, first kill" },
        { "W-112", "Gurubashi Arena visits" }, { "W-112.trinket", "Arena Master trinket looted" },
        { "W-115", "Booty Bay visits" }, { "W-115.rides", "Boat rides between Booty Bay and Ratchet" },
        { "W-116", "Deaths to goblin town guards" }, { "W-117", "Devilsaurs slain in Un'Goro" },
        { "W-118", "Deaths to devilsaurs" }, { "W-119", "Un'Goro crystals collected" },
        { "W-120", "Un'Goro pylons activated" }, { "W-121", "A-Me 01 escorted" },
        { "W-122", "Gadgetzan water quests" }, { "W-123", "Visits to the Dark Portal" },
        { "W-124", "Visits to Karazhan's gates" }, { "W-125", "Visits to Onyxia's Lair" },
        { "W-126", "Yetis slain in Winterspring" }, { "W-127", "Desolace centaurs slain, by clan" },
        { "W-129", "Time by zone type", "timemap" },
        { heading = "Boats and Zeppelins" },
        { "W-329", "Boat rides" }, { "W-330", "Zeppelin rides" }, { "W-472", "First boat or zeppelin ride" },
    })
end

local function DrawRares(B)
    ns.ShowItems(B, {
        { heading = "Rares" },
        { "W-130", "Rares seen and killed" }, { "W-131", "Rare kills by zone" },
        { "W-133", "First rare killed" }, { "W-134", "Rares that killed you" },
        { "W-132", "Bounty targets killed (from Wanted quests)" },
        { heading = "Elites and Big Pulls" },
        { "W-135", "Elites soloed" }, { "W-137", "Highest-level elite soloed" },
        { "W-136", "Times an elite killed you" }, { "W-138", "Mobs killed 5+ levels above you" },
        { "W-139", "Fights with a mob 10+ levels above you" },
    })
end

ns.WrappedPage("Wrapped Stats", "Creature Families", DrawFamilies)
ns.WrappedPage("Wrapped Stats", "Iconic Moments", DrawIconic)
ns.WrappedPage("Wrapped Stats", "Rares & Elites", DrawRares)

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------

ns.OnKill(CountKill)
ns.OnFightEnd(OnFight)
ns.OnDeathRecord(OnDeath)
ns.OnFall(OnFall)
ns.OnLootItem(OnLoot)

On("PLAYER_ENTERING_WORLD", function(isInitialLogin, isReload)
    wanted = Track.get("wanted")
    if not lastZone and Track.get("W-082") == nil and not Track.get("outsideHome") then
        -- A character the tracker has already seen away from home left it
        -- before this was recorded: don't count a later trip back.
        local _, race = Call("UnitRace", "player")
        local home = HOMES[Str(race) or ""]
        for zone in pairs(home and ns.GetDB().zones or {}) do
            if not IsIn(zone, home) and zone ~= "Unknown" and zone ~= "Deeprun Tram" then
                Track.set("outsideHome", true)
                break
            end
        end
    end
    OnZone(isInitialLogin or isReload)
end)
On("ZONE_CHANGED_NEW_AREA", OnZone)
On("ZONE_CHANGED", OnZone)
On("ZONE_CHANGED_INDOORS", OnZone)
On("PLAYER_TARGET_CHANGED", WatchTarget)
On("NAME_PLATE_UNIT_ADDED", function(unit)
    unit = Str(Safe(unit))
    if not unit or Call("UnitIsPlayer", unit) ~= false then return end
    if IsRare(Str(Call("UnitClassification", unit))) then SeenRare(Str(Call("UnitGUID", unit))) end
end)
On("PLAYER_ENTER_COMBAT", Attacked)
On("PLAYER_REGEN_DISABLED", Attacked)
On("CHAT_MSG_COMBAT_XP_GAIN", function(msg)
    msg = Str(Safe(msg))
    local mob = msg and msg:match(ns.PATTERNS.kill)
    if not mob then return end
    recentXP[mob] = GetTime()
    -- the target being watched gave experience: the main tracker has it
    if watched and watched.name == mob then counted[watched.guid] = true end
end)
On("COMBAT_LOG_EVENT_UNFILTERED", OnCombatLog)
On("QUEST_ACCEPTED", OnQuestAccepted)
On("QUEST_TURNED_IN", OnQuestTurnedIn)
On("CHAT_MSG_CHANNEL", OnChannel)
ns.OnCast(Protect(function(name)
    if watched and Str(Call("UnitGUID", "target")) == watched.guid then Attacked() end
    if name == "Hearthstone" or name == "Astral Recall" then
        Traveled()
        lastSubZoneAt = nil -- hearthed away: arriving in Darnassus next isn't the Rut'theran portal (W-076)
    elseif name and (name:find("Teleport", 1, true) or name:find("^Portal")) then
        Traveled()
    end
end))
ns.Hook("TakeTaxiNode", Protect(Traveled))
if not ns.Hook("C_SummonInfo.ConfirmSummon", Protect(Traveled)) then
    ns.Hook("ConfirmSummon", Protect(Traveled))               -- an accepted summon
end
ns.WrappedTick(Tick)
-- W-081 / W-103 racial mount bought: a mount (item class 15, subclass 5)
-- from a vendor, with what it cost. Each purchase and its payment are
-- paired up whichever comes first (within 3 seconds) and used once, so a
-- mount never takes the price of something bought before it.
local spend, bought
local function PairPurchase()
    if not (spend and bought) or math.abs(spend.t - bought.t) > 3 then return end
    local c, cost = bought.c, spend.amount
    spend, bought = nil, nil
    if c.classID ~= 15 or c.subClassID ~= 5 then return end
    local faction = Faction()
    if faction == "Alliance" or faction == "Horde" then  -- (a Skyborne who hasn't chosen has neither)
        Track.first(faction == "Horde" and "W-103" or "W-081", { name = c.name, cost = cost })
    end
    Track.count("W-375", nil, cost)                           -- W-375 gold spent on mounts
end
ns.OnMoneyChange(Protect(function(delta, where)
    if where ~= "merchant" or delta >= 0 or Call("InRepairMode") == true then return end
    spend = { amount = -delta, t = GetTime() }
    PairPurchase()
end))
ns.OnItemChange(Protect(function(c)
    if c.kind ~= "bought" then return end
    bought = { c = c, t = GetTime() }
    PairPurchase()
end))
-- W-022..W-059 began with the wrapped stats (0.6.0), but the main tracker
-- has every experience kill by name since it began (#28): at load, a
-- family is raised to what its names add up to there, never lowered.
-- Families known only by creature type (undead, elementals, demons,
-- critters) can't be told from a name and are left as they are.
ns.OnLoad(Protect(function(db)
    if not Track.enabled("probe") then return end
    local total = {}
    for name, n in pairs(db.kills and db.kills.byName or {}) do
        if type(name) == "string" and type(n) == "number" and n > 0 then
            for _, id in ipairs(FamiliesOf(name)) do total[id] = (total[id] or 0) + n end
        end
    end
    for id, n in pairs(total) do
        local have = Track.get(id)
        if n > (type(have) == "number" and have or 0) then Track.set(id, n) end
    end
end))
