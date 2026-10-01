-- JourneyTracker "Wrapped" stats. IDs W-001..W-500 match
-- wrapped-tracking-spec.md, which is built one section at a time. This file
-- currently covers:
--   Section 1: WoW Forever exclusives (W-001..W-021)
--
-- Counters live in db.wrapped, keyed by item ID, through a small registry:
--   Track.count(id, key?, n?)  add to a number, or to a capped name map
--   Track.time(id, state)      seconds in a state (the class tracker's timer)
--   Track.max(id, value, ctx)  the biggest value seen, with context
--   Track.first(id, ctx)       the first time something happened
-- Name-keyed maps keep their 200 biggest entries. Spec [probe] items sit
-- behind db.wrapped.flags so they can be switched off.

local ADDON_NAME, ns = ...
local Safe, Call, Num, Str, IsSecret = ns.Safe, ns.Call, ns.Num, ns.Str, ns.IsSecret

local MAP_CAP = 200
local db, W -- JourneyTrackerDB, db.wrapped

-- Forever names, from Blizzard's and guide sites' coverage. Easy to edit if
-- the game spells them differently.
local ZEPHRAS = "Zephras Isle"
local RIVERGLADES = "Riverglades"
local SHENDRALAS = "Shen'dralas"
local HYJAL = "Mount Hyjal"
local CAMP_AURAS = { "Campfire Nearby", "Welcoming Campfire", "Camp Benefits" }
local CAMP_BUFFS = { ["Welcoming Campfire"] = true, ["Camp Benefits"] = true, ["Mana Well"] = true,
    ["Sharpening Wheel"] = true, ["Enchanted Lute"] = true, ["First Aid Kit"] = true, ["Fish Bowl"] = true,
    ["Incense Candle"] = true, ["Camp Tent"] = true, ["Lodestone"] = true, ["Camp Chair"] = true,
    ["Faction Banner"] = true }
local CAMP_OBJECTS = { ["Iron Oven"] = true, ["Sharpening Wheel"] = true, ["Faction Banner"] = true,
    ["Incense Candle"] = true, ["Alchemy Lab"] = true, ["Mana Well"] = true, ["Tanning Rack"] = true,
    ["Camp Tent"] = true, ["Lodestone"] = true, ["Camp Chair"] = true, ["Fish Bowl"] = true,
    ["Enchanted Lute"] = true, ["Reagent Bot"] = true, ["Repair Bot"] = true, ["First Aid Kit"] = true }
-- W-003: race (token) and class Forever newly allows. Skyborne: any class.
local NEW_COMBOS = { Gnome = "PRIEST", Human = "HUNTER", Dwarf = "SHAMAN", Orc = "MAGE",
    Troll = "WARLOCK", Scourge = "PALADIN" }
-- W-007: Classic's quest IDs stop below this; Forever's new quests are above it.
local FOREVER_QUEST_ID = 10000

---------------------------------------------------------------------------
-- Track: the counter registry
---------------------------------------------------------------------------

local Track = {}
local timers = {}

-- Keep only the MAP_CAP biggest entries of a name-keyed map.
local function Cap(map)
    local count = 0
    for _ in pairs(map) do count = count + 1 end
    while count > MAP_CAP do
        local smallest, value
        for k, v in pairs(map) do
            if type(v) == "number" and (not value or v < value) then smallest, value = k, v end
        end
        if not smallest then return end
        map[smallest] = nil
        count = count - 1
    end
end

function Track.count(id, key, n)
    n = n or 1
    if key == nil then
        W[id] = (type(W[id]) == "number" and W[id] or 0) + n
        return
    end
    local map = type(W[id]) == "table" and W[id] or {}
    W[id] = map
    map[key] = (map[key] or 0) + n
    Cap(map)
end

function Track.time(id, state)
    local t = timers[id]
    if not t then
        W[id] = type(W[id]) == "table" and W[id] or {}
        t = ns.MakeTimer(W[id])
        timers[id] = t
    end
    t:Set(state)
end

-- Level, /played, zone and time, plus any extra fields.
local function Context(extra)
    local played = ns.PlayedNow()
    local ctx = { level = ns.Level(), played = played and math.floor(played) or nil,
                  zone = ns.Zone(), t = time() }
    for k, v in pairs(extra or {}) do ctx[k] = v end
    return ctx
end

function Track.max(id, value, extra)
    local current = W[id]
    if type(current) == "table" and current.value and current.value >= value then return false end
    local ctx = Context(extra)
    ctx.value = value
    W[id] = ctx
    return true
end

function Track.first(id, extra)
    if W[id] ~= nil then return false end
    W[id] = Context(extra)
    return true
end

function Track.enabled(flag)
    return W.flags[flag] ~= false
end

---------------------------------------------------------------------------
-- Section 1: WoW Forever exclusives
---------------------------------------------------------------------------

local function IsSkyborne()
    local name, token = Call("UnitRace", "player")
    return ((Str(name) or "") .. (Str(token) or "")):find("Skyborne", 1, true) ~= nil
end

-- W-001 level you left Zephras Isle, W-006 first arrival on Mount Hyjal.
local currentZone
local function OnZone()
    local zone = ns.Zone()
    if currentZone == ZEPHRAS and zone ~= ZEPHRAS then
        Track.first("W-001", { to = zone })                   -- W-001 left Zephras Isle
    end
    if zone == HYJAL or (zone:find("Hyjal", 1, true) and not zone:find("Summit", 1, true)) then
        local reached = db.reachedMax
        Track.first("W-006", {                                -- W-006 Mount Hyjal arrival
            daysAfter60 = reached and math.floor((time() - reached) / 86400) or nil })
    end
    currentZone = zone
end

-- W-002 the faction a Skyborne character chose.
local function CheckFaction()
    if W["W-002"] then return end
    local faction = Str(Call("UnitFactionGroup", "player"))
    if not faction then return end
    if faction == "Neutral" then
        W.wasNeutral = true
    elseif W.wasNeutral then
        Track.first("W-002", { faction = faction })
    elseif IsSkyborne() then
        Track.first("W-002", { faction = faction, before = true }) -- chosen before tracking
    end
end

-- W-003 is this race/class combination new in Forever?
local function CheckCombo()
    local raceName, raceToken = Call("UnitRace", "player")
    local className, classToken = Call("UnitClass", "player")
    raceName, raceToken = Str(raceName), Str(raceToken)
    className, classToken = Str(className), Str(classToken)
    if not raceName or not className then return end
    local new = IsSkyborne() or (raceToken ~= nil and NEW_COMBOS[raceToken] == classToken)
    W["W-003"] = { combo = raceName .. " " .. className, new = new and true or false }
end

-- W-020 ruleset: Hardcore from the game, PvP/RP from the realm name or from
-- being auto-flagged by a zone (W-021).
local function DetectRuleset()
    local realm = Str(Call("GetRealmName")) or ""
    local rules = "Normal"
    if Call("C_GameRules.IsHardcoreActive") == true then
        rules = "Hardcore"
    elseif realm:find("PvP", 1, true) or W.autoFlagged then
        rules = "PvP"
    elseif realm:find("RP", 1, true) or realm:find("Roleplay", 1, true) then
        rules = "Roleplaying"
    end
    W["W-020"] = rules
end

-- W-021 flagged for PvP by walking into a contested or enemy zone.
local wasPvP, manualFlagUntil = nil, 0
local function CheckPvPFlag()
    local pvp = Call("UnitIsPVP", "player")
    if pvp == nil then return end
    pvp = pvp and true or false
    if wasPvP == false and pvp and GetTime() > manualFlagUntil then
        local zoneType = Str(Call("GetZonePVPInfo"))
        if zoneType == "contested" or zoneType == "hostile" then
            Track.count("W-021")
            if not W.autoFlagged then
                W.autoFlagged = true
                DetectRuleset()
            end
        end
    end
    wasPvP = pvp
end

-- W-007 new Forever quests vs Classic quests, W-016 Lord Valthalak questline.
local function OnQuestTurnedIn(questID)
    questID = Num(Safe(questID))
    if not questID then return end
    Track.count("W-007", questID > FOREVER_QUEST_ID and "forever" or "classic")
    local title = Str(Call("C_QuestLog.GetTitleForQuestID", questID))
    local npc = Str(Call("UnitName", "npc"))
    if (title and title:find("Valthalak", 1, true)) or npc == "Bodley" then
        W["W-016"] = W["W-016"] or {}
        local list = W["W-016"]
        if #list < 50 then
            table.insert(list, { title = title or ("Quest #" .. questID), level = ns.Level(), t = time() })
        end
    end
end

-- W-008 camps set up vs W-012 camping objects crafted. A campfire cast that
-- makes a campfire item was crafting; one that doesn't was setting up camp.
local campCast
local function OnCast(name)
    if not name:find("Campfire", 1, true) then return end
    campCast = { name = name }
    local this = campCast
    if C_Timer and C_Timer.After then
        C_Timer.After(2, function()
            if not this.created then Track.count("W-008", this.name) end -- W-008 camps set up
            if campCast == this then campCast = nil end
        end)
    end
end

local function OnItemChange(c)
    if c.kind ~= "created" or not c.name then return end
    if c.name:find("Campfire", 1, true) or CAMP_OBJECTS[c.name] then
        Track.count("W-012", c.name, c.delta)                 -- W-012 camping objects crafted
        if campCast and c.name:find("Campfire", 1, true) then campCast.created = true end
    end
end

-- W-009 time at camps (sitting by a campfire gives "Campfire Nearby", then
-- "Welcoming Campfire"). Buffs can only be read out of combat.
local function AtCamp()
    for _, name in ipairs(CAMP_AURAS) do
        local has = ns.HasAura(name)
        if has == nil then return nil end
        if has then return true end
    end
    return false
end

local function IsAtCamp()
    local t = timers["W-009"]
    return t ~= nil and t.state ~= nil
end

local function CampTick()
    if ns.InCombat() then return end
    local at = AtCamp()
    if at ~= nil then Track.time("W-009", at and "Camp" or nil) end
end

-- W-010 camp vendors and repairs (Engineering's bots).
local function OnMerchant()
    if IsAtCamp() then Track.count("W-010", "vendor") end
end

-- W-011 camp buffs received.
local function OnAura(unit, info)
    if not W or IsSecret(info) or type(info) ~= "table" then return end
    local ok, added = pcall(function() return info.addedAuras end)
    if not ok or IsSecret(added) or type(added) ~= "table" then return end
    for _, aura in ipairs(added) do
        local fine, name = pcall(function() return Safe(aura.name) end)
        name = fine and Str(name)
        if name and (CAMP_BUFFS[name] or name:find("Camp", 1, true)) then
            Track.count("W-011", name)
        end
    end
end

-- W-017 world map areas explored, at each ding. The game reports which
-- overlays of each zone map you've uncovered; the website turns the count
-- into a percentage.
local function ExploredAreas()
    local textures = C_MapExplorationInfo and C_MapExplorationInfo.GetExploredMapTextures
    local children = C_Map and C_Map.GetMapChildrenInfo
    if not textures or not children then return nil end
    local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
    local total, seen = 0, {}
    for _, root in ipairs({ 947, 1414, 1415 }) do -- Azeroth, Kalimdor, Eastern Kingdoms
        local ok, zones = pcall(children, root, zoneType, true)
        if ok and type(zones) == "table" then
            for _, info in ipairs(zones) do
                local mapID = Num(Safe(info.mapID))
                if mapID and not seen[mapID] then
                    seen[mapID] = true
                    local fine, list = pcall(textures, mapID)
                    if fine and type(list) == "table" then total = total + #list end
                end
            end
        end
    end
    return total
end

-- W-019 transmog changes and gold spent at the transmogrifier.
local transmogMoney
local function TransmogOpened() transmogMoney = Num(Call("GetMoney")) end
local function TransmogClosed()
    local now = Num(Call("GetMoney"))
    if transmogMoney and now and transmogMoney > now then
        Track.count("W-019", "gold", transmogMoney - now)
    end
    transmogMoney = nil
end

local function Interaction(itype, open)
    local E = Enum and Enum.PlayerInteractionType
    if not E or IsSecret(itype) or itype == nil then return end
    if itype == E.Merchant and open then
        OnMerchant()
    elseif itype == E.Transmogrifier then
        if open then TransmogOpened() else TransmogClosed() end
    end
end

---------------------------------------------------------------------------
-- Pages: WoW Forever, and camping (drawn on the Social page)
---------------------------------------------------------------------------

local function Map(id) return type(W[id]) == "table" and W[id] or {} end

-- Camping is a social mechanic, so W-008..012 live on the Social page.
local function DrawCamping(B)
    local U = ns.UI
    B:Heading("Camping")
    local camps = 0
    for _, n in pairs(Map("W-008")) do camps = camps + n end
    B:Row("Camps set up", camps)                                       -- W-008
    B:Row("Time at campfires", U.Dur(Map("W-009").Camp or 0))          -- W-009
    B:Row("Time resting in inns and cities", U.Dur(db.time.resting))
    local services = Map("W-010")
    B:Row("Camp vendor visits", services.vendor or 0)                  -- W-010
    B:Row("Camp repairs", services.repair or 0)
    B:Heading("Camp Buffs Received")                                   -- W-011
    B:BarList(Map("W-011"))
    B:Heading("Camping Objects Crafted")                               -- W-012
    B:BarList(Map("W-012"))
end

local function DrawForever(B)
    local U = ns.UI
    local Z = db.zones
    local function TimeIn(zone) return Z[zone] and U.Dur(Z[zone].seconds) or "-" end
    local function ZoneVisit(zone)
        local z = Z[zone]
        if not z then
            B:Row(zone, "Not visited yet")
            return
        end
        B:Row(zone, "Arrived at level " .. (z.firstLevel or "?"))
        B:Note(string.format("Time there: %s. Quests turned in there: %d.", U.Dur(z.seconds),
            db.quests.byZone[zone] or 0))
    end

    B:Title("WoW Forever")
    B:Heading("Skyborne")                                     -- W-001..003
    local combo = W["W-003"]
    B:Row("Race and class", combo and (combo.combo .. (combo.new and " (new in Forever)" or "")) or "-")
    B:Row("Time on Zephras Isle", TimeIn(ZEPHRAS))
    local left = W["W-001"]
    B:Row("Left Zephras Isle", left and ("Level " .. left.level) or "-")
    local faction = W["W-002"]
    B:Row("Faction chosen", faction and (faction.faction .. (faction.before and " (before tracking)" or "")) or "-")

    B:Heading("New Zones")                                    -- W-004..006
    ZoneVisit(RIVERGLADES)
    ZoneVisit(SHENDRALAS)
    local hyjal = W["W-006"]
    if hyjal then
        B:Row(HYJAL, "Arrived at level " .. hyjal.level)
        B:Note(string.format("/played %s%s.", U.Dur(hyjal.played),
            hyjal.daysAfter60 and (", " .. hyjal.daysAfter60 .. " days after reaching 60") or ""))
    else
        B:Row(HYJAL, "Not visited yet")
    end

    B:Heading("Quests")                                       -- W-007
    local quests = Map("W-007")
    B:Row("New Forever quests", quests.forever or 0)
    B:Row("Classic quests", quests.classic or 0)
    B:Note("Told apart by quest ID: Classic's IDs stop below 10,000.")

    B:Heading("Legacy")                                       -- W-013..017
    B:Note("Legacy challenges, points and perks will appear here once the tracker is wired to the game's Legacy system.")
    local valthalak = W["W-016"] or {}
    B:Row("Lord Valthalak quests done", #valthalak)
    for _, q in ipairs(valthalak) do
        B:Note(string.format("%s, level %d, %s", q.title, q.level or 0, U.Date(q.t)))
    end
    local explored = Map("W-017")
    if next(explored) then
        B:Cols({ "Level", "Map areas explored" }, { 60, 200 })
        for level = 1, ns.MAX_LEVEL do
            if explored[level] then B:Cols({ level, explored[level] }, { 60, 200 }) end
        end
    else
        B:Note("Map areas explored are recorded at each ding.")
    end

    B:Heading("Transmog")                                     -- W-019
    local transmog = Map("W-019")
    B:Row("Appearance changes", transmog.changes or 0)
    B:Row("Gold spent", U.Money(transmog.gold or 0))

    B:Heading("Ruleset")                                      -- W-020, W-021
    B:Row("Ruleset", W["W-020"] or "-")
    B:Row("Auto-flagged for PvP by a zone", type(W["W-021"]) == "number" and W["W-021"] or 0)
end

function ns.WrappedSections()
    if not W then return {} end
    return { { name = "WoW Forever", pages = { { "Forever Exclusives", DrawForever } } } }
end

function ns.DrawCamping(B)
    if W then DrawCamping(B) end
end

---------------------------------------------------------------------------
-- Wiring (shared with the main tracker's registrations)
---------------------------------------------------------------------------

local started = false
ns.Listen("PLAYER_ENTERING_WORLD", function(isInitialLogin, isReload)
    if not W then return end
    OnZone()
    if not (isInitialLogin or isReload) or started then return end
    started = true
    CheckCombo()
    CheckFaction()
    DetectRuleset()
    wasPvP = Call("UnitIsPVP", "player") and true or false
    if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(5, CampTick) end
end)
ns.Listen("ZONE_CHANGED_NEW_AREA", function()
    if not W then return end
    OnZone()
    CheckPvPFlag()
end)
ns.Listen("UNIT_FACTION", function()
    if not W then return end
    CheckFaction()
    CheckPvPFlag()
end, "player")
ns.Listen("PLAYER_FLAGS_CHANGED", function() if W then CheckPvPFlag() end end)
ns.Listen("NEUTRAL_FACTION_SELECT_RESULT", function() if W then CheckFaction() end end)
ns.Listen("QUEST_TURNED_IN", function(questID) if W then OnQuestTurnedIn(questID) end end)
ns.Listen("UNIT_AURA", OnAura, "player")
ns.Listen("MERCHANT_SHOW", function() if W then OnMerchant() end end)
ns.Listen("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(itype) if W then Interaction(itype, true) end end)
ns.Listen("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(itype) if W then Interaction(itype, false) end end)
ns.Listen("TRANSMOGRIFY_OPEN", function() if W then TransmogOpened() end end)
ns.Listen("TRANSMOGRIFY_CLOSE", function() if W then TransmogClosed() end end)
ns.Listen("TRANSMOGRIFY_SUCCESS", function() if W then Track.count("W-019", "changes") end end)

ns.OnCast(function(name) if W then OnCast(name) end end)
ns.OnItemChange(function(c) if W then OnItemChange(c) end end)

ns.OnDing(function(snapshot, level)
    if not W then return end
    local explored = ExploredAreas()
    if explored then
        snapshot.explored = explored
        W["W-017"] = type(W["W-017"]) == "table" and W["W-017"] or {}
        W["W-017"][level] = explored                          -- W-017 exploration at each ding
    end
end)

ns.OnLoad(function(saved)
    db = saved
    db.wrapped = db.wrapped or {}
    W = db.wrapped
    W.flags = W.flags or { probe = true } -- [probe] sections can be switched off here
    -- W-010 repairs at a camp's Repair Bot
    ns.Hook("RepairAllItems", function() if IsAtCamp() then Track.count("W-010", "repair") end end)
    -- W-021 flagging yourself on purpose isn't an auto-flag
    local function Manual() manualFlagUntil = GetTime() + 3 end
    ns.Hook("TogglePVP", Manual)
    ns.Hook("SetPVP", Manual)
end)
