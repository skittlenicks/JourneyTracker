-- JourneyTracker wrapped stats: getting around and dying. IDs match
-- wrapped-tracking-spec.md:
--   Movement and world mechanics (W-313..W-335; boat and zeppelin rides,
--   W-329 and W-330, are in JourneyTrackerIconic.lua)
--   Death memes (W-336..W-358)
-- Your health is secret on Forever, so fall damage (W-321) and one-shots
-- (W-350) can't be tracked.

local ADDON_NAME, ns = ...
local Track = ns.Track
local Safe, Call, Num, Str = ns.Safe, ns.Call, ns.Num, ns.Str
local On, Protect = ns.WrappedOn, ns.Protect

local HEARTHSTONE_ITEM = 6948
local JUMP_YARDS = 200     -- a bigger jump between samples is a teleport, not travel (as #71)
local LOST_AFTER = 300     -- seconds in one subzone with nothing done (W-335)
local LOST_YARDS = 150     -- ...while moving around at least this far
local DROWN_WINDOW = 30    -- seconds of drowning damage after the breath bar empties (W-337)
local ESCORT_WINDOW = 1200 -- an escort quest counts as under way this long after you take it (W-346)
-- Guards, as whole words in the killer's name, checked against its faction (W-339).
local GUARD_WORDS = { "Guard", "Grunt", "Deathguard", "Bluffwatcher", "Kor'kron", "Mountaineer",
    "Sentinel", "Watchman", "Brave", "Bruiser" }
-- Escort quests, from their objectives (English).
local ESCORT_WORDS = { "escort", "protect" }

local function Round(v) return math.floor(v + 0.5) end
local function Faction() return Str(Call("UnitFactionGroup", "player")) end
local function Resting() return Call("IsResting") == true end
local function Ghost() return Call("UnitIsGhost", "player") == true end

local function HasWord(text, words)
    for _, w in ipairs(words) do
        if text:find("%f[%w]" .. w .. "%f[%W]") then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Breath and fatigue (W-315..W-317)
---------------------------------------------------------------------------

-- The game's mirror timers: BREATH under water, EXHAUSTION in deep water.
-- One counting down from `value` milliseconds runs out at `expires`; one
-- filling back up means you're out of it again.
local mirrors = { BREATH = {}, EXHAUSTION = {} }

local function EndMirror(name, now)
    local m = mirrors[name]
    if not m.since then return end
    if name == "BREATH" then Track.count("W-315", nil, Round(now - m.since)) end -- W-315 time underwater
    if m.expires and now >= m.expires - 0.5 then
        m.ranOutAt = m.expires
        if name == "BREATH" then Track.count("W-316") end     -- W-316 breath ran out
    end
    m.since, m.expires = nil, nil
end

local function OnMirrorStart(timer, value, maxValue, scale)
    local name = Str(Safe(timer))
    local m = name and mirrors[name]
    if not m then return end
    value, scale = Num(Safe(value)), Num(Safe(scale))
    local now = GetTime()
    if scale and scale < 0 and value then
        if not m.since then
            m.since = now
            if name == "EXHAUSTION" then Track.count("W-317") end -- W-317 swam into fatigue
        end
        m.expires = now + value / 1000 / -scale
    else
        EndMirror(name, now)                                  -- filling back up: you're out
        m.out = now
    end
end

local function OnMirrorStop(timer)
    local name = Str(Safe(timer))
    if name and mirrors[name] then EndMirror(name, GetTime()) end
end

-- At a death: had this timer run out, with you still in it?
local function RanOut(name, now)
    local m = mirrors[name]
    if m.since then return m.expires ~= nil and now >= m.expires - 0.5 end
    return m.ranOutAt ~= nil and now - m.ranOutAt < DROWN_WINDOW and not (m.out and m.out >= m.ranOutAt)
end

---------------------------------------------------------------------------
-- Falls (W-318..W-320), from the main tracker's fall timer
---------------------------------------------------------------------------

local function OnFall(fall, airTime)
    if not airTime then return end
    local seconds = math.floor(airTime * 10 + 0.5) / 10
    Track.count("W-318", nil, seconds)                        -- W-318 time spent falling
    Track.max("W-319", seconds, { yards = Round(fall.yards) }) -- W-319 longest fall, in seconds
    if airTime > 5 then Track.count("W-320") end              -- W-320 falls over 5 seconds
end

---------------------------------------------------------------------------
-- Hearthstone, inns, logging out and rested XP (W-323..W-328)
---------------------------------------------------------------------------

local function BindLocation() return Str(Call("GetBindLocation")) end
local function RestedNow() return Num(Call("GetXPExhaustion")) or 0 end
-- Rested XP stops at a level and a half.
local function RestedFull()
    local max = Num(Call("UnitXPMax", "player"))
    return max ~= nil and max > 0 and RestedNow() >= max * 1.5 - 1
end
local wasFull -- nil until known after login

local function Capped()
    Track.count("W-328")                                      -- W-328 rested XP capped
    Track.firstEver("W-481", nil, (Track.get("W-328") or 0) > 1) -- W-481 the first time
end

local function OnBound()
    local where = BindLocation()
    if not where then return end
    if where ~= Track.get("bindName") then Track.count("W-323") end -- W-323 hearthstone moved
    Track.set("bindName", where)
    Track.set("bindPlace", { zone = ns.Zone(), subzone = ns.SubZone() })
    Track.count("W-324", where)                               -- W-324 binds, by inn
end

-- At the inn your hearthstone is set to: resting where you bound it, or
-- in the place it's named after.
local function AtBoundInn()
    if not Resting() then return false end
    local zone, sub = ns.Zone(), ns.SubZone()
    local place = Track.get("bindPlace")
    if type(place) == "table" and place.zone == zone and place.subzone == sub then return true end
    local bind = BindLocation()
    return bind ~= nil and (bind == sub or bind == zone)
end

---------------------------------------------------------------------------
-- The 5-second tick: swimming, on foot or mounted, corpse runs, the inn,
-- rested XP, Resurrection Sickness, getting lost
---------------------------------------------------------------------------

local lastPos
local lastSubzone, subzoneSince, activityAt, wander, lostCounted = nil, 0, 0, 0, false
local sickUntil = 0

local function MarkActive() activityAt, wander = GetTime(), 0 end

-- Resurrection Sickness's end, read out of combat (W-347).
local function ReadSickness()
    local fn = C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName
    if not fn then return end
    local ok, aura = pcall(fn, "player", "Resurrection Sickness", "HARMFUL")
    aura = ok and Safe(aura)
    local expires = type(aura) == "table" and Num(Safe(aura.expirationTime))
    if expires and expires > 0 then sickUntil = expires end
end

local function Tick(dt)
    local s, now = Round(dt), GetTime()
    local swimming = Call("IsSwimming") == true
    local onTaxi = Call("UnitOnTaxi", "player") == true
    local ghost, combat = Ghost(), ns.InCombat()
    if swimming then Track.count("W-313", nil, s) end         -- W-313 time swimming
    -- Distance by how you moved, sampled out of combat like #71 (on foot,
    -- mounted and swum add up to its ground distance).
    if not combat then
        local x, y, inst = ns.WorldPos()
        if x and lastPos and lastPos.inst == inst and not onTaxi then
            local d = math.sqrt((x - lastPos.x) ^ 2 + (y - lastPos.y) ^ 2)
            if d <= JUMP_YARDS and d >= 0.5 then
                wander = wander + d
                if ghost then
                    Track.count("W-334", nil, Round(d))       -- W-334 corpse run yards
                elseif swimming then
                    Track.count("W-314", nil, Round(d))       -- W-314 yards swum
                else
                    Track.count("W-322", Call("IsMounted") == true and "mounted" or "on foot", Round(d)) -- W-322
                end
            end
        end
        lastPos = x and { x = x, y = y, inst = inst } or nil
        ReadSickness()
    end
    if AtBoundInn() then Track.count("W-325", nil, s) end     -- W-325 time at your bound inn
    if wasFull ~= nil then
        local full = RestedFull()
        if full and not wasFull then Capped() end
        wasFull = full
    end
    -- W-335 lost: five minutes moving around one subzone with no kill,
    -- loot or quest progress, out in the world and not AFK or fighting.
    local sub = ns.SubZone() or ns.Zone()
    if sub ~= lastSubzone then
        lastSubzone, subzoneSince, wander, lostCounted = sub, now, 0, false
    end
    if not lostCounted and now - subzoneSince >= LOST_AFTER and now - activityAt >= LOST_AFTER
        and wander >= LOST_YARDS and not Resting() and not combat and not onTaxi and not ghost
        and Call("UnitIsAFK", "player") ~= true and Call("IsInInstance") ~= true then
        lostCounted = true
        Track.count("W-335", sub)                             -- W-335 times lost, by subzone
    end
end

---------------------------------------------------------------------------
-- Death memes (W-336..W-358)
---------------------------------------------------------------------------

local loginAt, dingAt, spiritRezAt = -1000, -1000, -1000
local mountedFight, combatEndedAt = false, nil
local escorts = {}         -- [questID] = when you took it, for escort quests
local ghostSince

-- Is an item in your bags that matches, and off cooldown?
local function ReadyInBags(match)
    for bag = 0, NUM_BAG_SLOTS or 4 do
        local slots = Num(Call("C_Container.GetContainerNumSlots", bag)) or Num(Call("GetContainerNumSlots", bag)) or 0
        for slot = 1, slots do
            local id, link
            local info = Call("C_Container.GetContainerItemInfo", bag, slot)
            if type(info) == "table" then
                id, link = Num(Safe(info.itemID)), Str(Safe(info.hyperlink))
            else
                local _, _, _, _, _, _, l, _, _, i = Call("GetContainerItemInfo", bag, slot)
                id, link = Num(i), Str(l)
            end
            if id and match(id, link and link:match("%[(.-)%]") or "") then
                local start = Num(Call("C_Container.GetItemCooldown", id)) or Num(Call("GetItemCooldown", id))
                if start == 0 then return true end
            end
        end
    end
    return false
end

local function IsHealing(id, name)
    return name:find("Healthstone", 1, true) ~= nil or name:find("Healing Potion", 1, true) ~= nil
end
local function IsHearthstone(id) return id == HEARTHSTONE_ITEM end

-- A town guard: the name says so, and it's the other faction's (or a
-- goblin town's Bruiser). With no faction seen, the zone must be hostile.
local function IsGuard(killer, mob)
    if not HasWord(killer, GUARD_WORDS) then return false end
    if killer:find("Bruiser", 1, true) then return true end
    local faction = mob and mob.faction
    if faction == "Alliance" or faction == "Horde" then return faction ~= Faction() end
    return Str(Call("GetZonePVPInfo")) == "hostile"
end

local function EscortUnderWay(now)
    for questID, at in pairs(escorts) do
        if now - at <= ESCORT_WINDOW then return true end
        escorts[questID] = nil
    end
    return false
end

local function OnDeath(rec, extra)
    local now = GetTime()
    local killer = rec.killer or ""
    local mob = extra and extra.mob
    local played = ns.PlayedNow()
    if played then rec.played = math.floor(played) end       -- /played at each death (W-355, W-357)
    if RanOut("BREATH", now) then Track.count("W-337") end    -- W-337 drowned
    if RanOut("EXHAUSTION", now) then Track.count("W-338") end -- W-338 fatigue
    if IsGuard(killer, mob) then Track.count("W-339") end     -- W-339 guards
    if Track.enabled("probe") then
        for _, id in ipairs(ns.FamiliesOf(killer, mob and mob.ctype, mob and mob.family)) do
            if id == "W-022" then Track.count("W-341") end    -- W-341 murlocs
        end
        if mob and mob.ctype == "Critter" then Track.count("W-342") end -- W-342 critters
    end
    if now - dingAt <= 10 then Track.count("W-343") end       -- W-343 within 10 seconds of a ding
    if now - loginAt <= 60 then Track.count("W-344") end      -- W-344 within a minute of logging in
    if Call("UnitIsAFK", "player") == true then Track.count("W-345") end -- W-345 while AFK
    if EscortUnderWay(now) then Track.count("W-346") end      -- W-346 during an escort
    if now < sickUntil then Track.count("W-347") end          -- W-347 with Resurrection Sickness
    if now - spiritRezAt <= 120 then Track.count("W-348") end -- W-348 soon after a spirit healer
    local pvp = Str(Call("GetZonePVPInfo"))
    if pvp == "sanctuary" or (Resting() and pvp ~= "hostile") then
        Track.count("W-349")                                  -- W-349 in a sanctuary or friendly town
    end
    if ReadyInBags(IsHealing) then Track.count("W-351") end   -- W-351 healthstone or potion ready
    if ReadyInBags(IsHearthstone) then Track.count("W-352") end -- W-352 Hearthstone ready
    if mountedFight and (ns.InCombat() or (combatEndedAt and now - combatEndedAt < 2)) then
        Track.count("W-353")                                  -- W-353 mounted when the fight began
    end
    local deaths = ns.GetDB().deaths
    local before = deaths[#deaths] == rec and deaths[#deaths - 1]
    if before then
        local gap = rec.t and before.t and rec.t - before.t
        if gap and gap >= 0 and gap <= 60 then Track.count("W-354") end -- W-354 twice in a minute
        if rec.played and before.played and rec.played > before.played then
            Track.max("W-355", rec.played - before.played)    -- W-355 longest stretch alive
        end
    end
end

-- W-358 time as a ghost, from releasing to being alive again. A spirit
-- healer brings you back with Resurrection Sickness: a minute for each
-- level over 10, up to 10 minutes (W-347, W-348).
local function OnUnghost()
    local now = GetTime()
    if ghostSince then
        Track.count("W-358", nil, Round(now - ghostSince))
        ghostSince = nil
    end
    local deaths = ns.GetDB().deaths
    local last = deaths[#deaths]
    if last and last.rez == "spirit healer" then
        spiritRezAt = now
        sickUntil = math.max(sickUntil, now + math.min(10, math.max(0, ns.Level() - 10)) * 60)
    end
end

-- W-346 escort quests: ones whose objectives say escort or protect.
local function ObjectiveTexts(questID, logIndex)
    local out = {}
    local objectives = Call("C_QuestLog.GetQuestObjectives", questID)
    if type(objectives) == "table" then
        for _, o in ipairs(objectives) do
            if type(o) == "table" then out[#out + 1] = Str(Safe(o.text)) end
        end
    elseif logIndex then
        for i = 1, Num(Call("GetNumQuestLeaderBoards", logIndex)) or 0 do
            out[#out + 1] = Str(Call("GetQuestLogLeaderBoard", i, logIndex))
        end
    end
    return out
end

local function CheckEscort(questID, logIndex)
    for _, text in ipairs(ObjectiveTexts(questID, logIndex)) do
        local lower = text:lower()
        for _, w in ipairs(ESCORT_WORDS) do
            if lower:find(w, 1, true) then
                escorts[questID] = GetTime()
                return
            end
        end
    end
end

local function OnQuestAccepted(a, b)
    MarkActive()
    -- Classic: (questLogIndex, questID). Newer clients: (questID).
    local logIndex, questID = Num(Safe(a)), Num(Safe(b))
    if not questID then questID, logIndex = logIndex, nil end
    if not questID then return end
    if C_Timer and C_Timer.After then
        C_Timer.After(1, Protect(function() CheckEscort(questID, logIndex) end))
    else
        CheckEscort(questID, logIndex)
    end
end

---------------------------------------------------------------------------
-- Logging in and out (W-326..W-328)
---------------------------------------------------------------------------

-- Where you logged out is counted at the next login, so a /reload (which
-- also logs out) isn't counted.
local function OnLogin()
    loginAt, wasFull = GetTime(), nil
    if Ghost() then ghostSince = GetTime() end
    if not Track.get("bindName") then Track.set("bindName", BindLocation()) end
    local out = Track.get("logout")
    Track.set("logout", nil)
    if type(out) ~= "table" then
        wasFull = RestedFull()
        return
    end
    Track.count("W-326", out.resting and "inn or city" or "in the field") -- W-326 where you logged out
    -- Rested XP from the time away arrives a moment after login.
    local function Away()
        if out.level == ns.Level() then
            local gained = RestedNow() - (out.rested or 0)
            if gained > 0 then Track.count("W-327", nil, gained) end -- W-327 rested XP while logged out
        end
        local full = RestedFull()
        if full and not out.full then Capped() end            -- capped while away
        wasFull = full
    end
    if C_Timer and C_Timer.After then C_Timer.After(5, Protect(Away)) else Away() end
end

local function OnLogout()
    Track.set("logout", { resting = Resting() or nil, rested = RestedNow(), full = RestedFull() or nil,
                          level = ns.Level() })
end

---------------------------------------------------------------------------
-- Window pages
---------------------------------------------------------------------------

local function DrawWorld(B)
    ns.ShowItems(B, {
        { heading = "Water" },
        { "W-313", "Time swimming", "time" }, { "W-314", "Yards swum" }, { "W-315", "Time underwater", "time" },
        { "W-316", "Times your breath ran out" }, { "W-317", "Times you swam into fatigue" },
        { heading = "Falling" },
        { "W-318", "Time spent falling", "time" }, { "W-319", "Longest fall (seconds in the air)" },
        { "W-320", "Falls longer than 5 seconds" },
        { heading = "On the Road" },
        { "W-322", "Yards on foot and mounted" }, { "W-331", "Portals taken" },
        { "W-333", "Meeting stones used" }, { "W-334", "Corpse run yards" },
        { "W-335", "Times you got lost, by subzone" },
        { heading = "Inns and Rest" },
        { "W-323", "Times you moved your hearthstone" }, { "W-324", "Inns you bound to" },
        { "W-325", "Time at your bound inn", "time" }, { "W-326", "Where you logged out" },
        { "W-327", "Rested XP gained while logged out" }, { "W-328", "Times your rested XP hit the cap" },
    })
end

local function DrawDeathMemes(B)
    ns.ShowItems(B, {
        { heading = "How You Died" },
        { "W-337", "Drowned" }, { "W-338", "Fatigue" }, { "W-339", "Town guards" }, { "W-341", "Murlocs" },
        { "W-342", "Critters" }, { "W-353", "Mounted when the fight began" },
        { heading = "When You Died" },
        { "W-343", "Within 10 seconds of a ding" }, { "W-344", "Within a minute of logging in" },
        { "W-345", "While AFK" }, { "W-346", "During an escort" },
        { "W-347", "With Resurrection Sickness" }, { "W-348", "Within 2 minutes of a spirit healer" },
        { "W-349", "In a sanctuary or friendly town" }, { "W-354", "Twice in a minute" },
        { heading = "What You Had Left" },
        { "W-351", "A healthstone or potion ready" }, { "W-352", "Your Hearthstone ready" },
        { heading = "Between Deaths" },
        { "W-355", "Longest stretch alive (/played)", "time" }, { "W-358", "Time as a ghost", "time" },
    })
end

ns.WrappedPage("Wrapped Stats", "Getting Around", DrawWorld)
ns.WrappedPage("Wrapped Stats", "Death Memes", DrawDeathMemes)

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------

ns.OnFall(OnFall)
ns.OnDeathRecord(OnDeath)
ns.OnKill(MarkActive)
ns.OnLootItem(MarkActive)
ns.OnMoneyChange(MarkActive)
ns.OnCast(Protect(function(name)
    if not name then return end
    -- A portal you click casts its "Portal Effect" on you. Your own
    -- teleports and portals are the class tracker's (MAG-04, MAG-05).
    if name:find("^Portal Effect") then
        Track.count("W-331", name:match(":%s*(.+)$") or name) -- W-331 portals used, by where to
    end
    if name:find("Meeting Stone", 1, true) then Track.count("W-333") end -- W-333 meeting stones
end))

On("PLAYER_ENTERING_WORLD", function(isInitialLogin, isReload)
    if isInitialLogin then
        OnLogin()
    elseif isReload then
        if Ghost() then ghostSince = GetTime() end
        wasFull = RestedFull()
    end
end)
On("PLAYER_LOGOUT", OnLogout)
On("MIRROR_TIMER_START", OnMirrorStart)
On("MIRROR_TIMER_STOP", OnMirrorStop)
On("HEARTHSTONE_BOUND", OnBound)
On("PLAYER_LEVEL_UP", function() dingAt = GetTime() end)
On("PLAYER_REGEN_DISABLED", function() mountedFight, combatEndedAt = Call("IsMounted") == true, nil end)
On("PLAYER_REGEN_ENABLED", function() combatEndedAt = GetTime() end)
On("PLAYER_ALIVE", function() if Ghost() then ghostSince = ghostSince or GetTime() end end)
On("PLAYER_UNGHOST", OnUnghost)
On("QUEST_ACCEPTED", OnQuestAccepted)
On("QUEST_WATCH_UPDATE", MarkActive)
On("QUEST_TURNED_IN", function(questID)
    escorts[Num(Safe(questID)) or 0] = nil
    MarkActive()
end)
On("QUEST_REMOVED", function(questID) escorts[Num(Safe(questID)) or 0] = nil end)
ns.WrappedTick(Tick)
