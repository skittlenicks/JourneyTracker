-- JourneyTracker wrapped stats: firsts and habits. IDs match
-- wrapped-tracking-spec.md:
--   Milestones and firsts (W-462..W-483; the PvP firsts are in
--   JourneyTrackerPvP.lua, the first boat in JourneyTrackerIconic.lua, the
--   first talent point in JourneyTrackerEconomy.lua, first Exalted in
--   JourneyTrackerProfessions.lua, first rested max in JourneyTrackerWorld.lua)
--   Sessions and habits (W-484..W-500)
-- Firsts are marked late when the tracker may have missed the real one
-- (Track.firstEver). Each session record also gets its kills, deaths and
-- the seconds to its first kill.

local ADDON_NAME, ns = ...
local Track = ns.Track
local Safe, Call, Num, Str = ns.Safe, ns.Call, ns.Num, ns.Str
local On, Protect = ns.WrappedOn, ns.Protect

local PREFIX = "|cff33ff99Journey|r"
local GOLD = { { 10000, "1g" }, { 100000, "10g" }, { 1000000, "100g" } } -- W-467
local BRACKETS = { [75] = true, [150] = true, [225] = true, [300] = true } -- W-474
local LATE_NIGHT = 5        -- dings before 5am count as late-night (W-487)
local HOUR = 3600           -- W-496 most XP in one hour of play
local ACTIVITY = 120        -- seconds a quest objective or kill keeps you "questing" or "grinding" (W-498)

local function Session() return ns.GetDB().sessions.current end

---------------------------------------------------------------------------
-- Firsts (W-462..W-483)
---------------------------------------------------------------------------

local wasGrouped

local function OnQuestTurnedIn(questID)
    questID = Num(Safe(questID))
    local title = questID and Str(Call("C_QuestLog.GetTitleForQuestID", questID))
    -- The main tracker has counted this one already.
    Track.firstEver("W-462", { name = title }, (ns.GetDB().quests.completed or 0) > 1) -- W-462 first quest
end

local function OnRoster()
    local grouped = Call("IsInGroup") == true
    if grouped and wasGrouped == false then
        Track.firstEver("W-464", { size = Num(Call("GetNumGroupMembers")) },
            (ns.GetDB().time.grouped or 0) > 0)               -- W-464 first group
    end
    wasGrouped = grouped
end

local function OnLoot(link, count, quality)
    if quality == 2 then
        -- The main tracker counts this loot by quality just after.
        local L = ns.GetDB().loot
        Track.firstEver("W-466", { name = link:match("%[(.-)%]") }, ((L.byQuality or {})[2] or 0) > 0) -- W-466 first green
    end
end

-- W-467 gold reached: any amount already reached when this began
-- (#85's peak) is marked as before tracking.
local function CheckGold(total)
    local reached = Track.get("W-467")
    local baseline = Track.get("goldSeen") == nil
    for _, g in ipairs(GOLD) do
        local done = type(reached) == "table" and reached[g[2]] ~= nil
        if not done then
            if baseline and (ns.GetDB().money.peak or 0) >= g[1] then
                Track.firstOf("W-467", g[2], { before = true })
            elseif total and total >= g[1] then
                Track.firstOf("W-467", g[2], not Track.get("goldFromStart") and { late = true } or nil)
            end
        end
        reached = Track.get("W-467")
    end
    if baseline then
        Track.set("goldSeen", true)
        -- Gold reached from here on is only a real first if the tracker saw
        -- the whole journey.
        local S = ns.GetDB().sessions
        local first = S.list[1] or S.current
        Track.set("goldFromStart", first ~= nil and first.startLevel == 1 or nil)
    end
end

-- W-474 the first profession to reach each bracket's top (75, 150, 225,
-- 300); brackets already reached when this began are marked before.
local function CheckBrackets()
    if Track.get("bracketsSeen") then return end
    local db = ns.GetDB()
    for name, P in pairs(db.professions or {}) do
        local rank = math.max(P.rank or 0, (db.skills[name] or {}).rank or 0)
        for top in pairs(BRACKETS) do
            if rank >= top then Track.firstOf("W-474", top, { name = name, before = true }) end
        end
    end
    Track.set("bracketsSeen", true)
end

local function OnSkill(msg)
    msg = Str(Safe(msg))
    if not msg then return end
    local name, rank = msg:match(ns.PATTERNS.skill)
    rank = tonumber(rank)
    if name and rank and BRACKETS[rank] and ns.PROFESSIONS[name] then
        Track.firstOf("W-474", rank, { name = name })
    end
end

-- W-483 the ding to 60: where, when and who with (classes only, not your
-- own: in a raid you're one of the raid units).
local function DingTo60(snapshot)
    local party, size = {}, Num(Call("GetNumGroupMembers")) or 0
    local raid = Call("IsInRaid") == true
    for i = 1, raid and size or (size - 1) do
        local unit = (raid and "raid" or "party") .. i
        if Call("UnitIsUnit", unit, "player") ~= true then
            local _, class = Call("UnitClass", unit)
            class = Str(class)
            if class then party[class] = (party[class] or 0) + 1 end
        end
    end
    Track.first("W-483", { subzone = snapshot.subzone, x = snapshot.x, y = snapshot.y, cause = snapshot.cause,
        hour = tonumber(date("%H")), size = size, party = next(party) and party or nil })
end

---------------------------------------------------------------------------
-- Sessions (W-487..W-496)
---------------------------------------------------------------------------

local xpWindow, xpSum, lastXP = {}, 0, nil

local function OnKill()
    local sess = Session()
    if not sess then return end
    sess.kills = (sess.kills or 0) + 1
    Track.max("W-490", sess.kills, { start = sess.start })    -- W-490 most kills in a session
    if not sess.firstKill then
        sess.firstKill = math.max(0, time() - sess.start)
        Track.count("W-491", "seconds", sess.firstKill)       -- W-491 login to first kill
        Track.count("W-491", "sessions")
    end
end

local function OnDeath()
    local sess = Session()
    if not sess then return end
    sess.deaths = (sess.deaths or 0) + 1
    Track.max("W-489", sess.deaths, { start = sess.start })   -- W-489 most deaths in a session
end

-- W-496 the most XP in an hour of play: XP gains this session, the oldest
-- dropped as they pass an hour.
local function OnXP()
    local total = ns.GetDB().xp.total
    if not total then return end
    local gained = lastXP and total - lastXP or 0
    lastXP = total
    if gained <= 0 then return end
    local now = GetTime()
    table.insert(xpWindow, { t = now, xp = gained })
    xpSum = xpSum + gained
    while xpWindow[1] and now - xpWindow[1].t > HOUR do
        xpSum = xpSum - table.remove(xpWindow, 1).xp
    end
    Track.max("W-496", xpSum)
end

local function OnDing(snapshot, level)
    local hour = tonumber(date("%H"))
    if hour and hour < LATE_NIGHT then
        Track.list("W-487", { level = level, hour = hour }, 60) -- W-487 late-night dings
    end
    if level >= ns.MAX_LEVEL then DingTo60(snapshot) end
    -- W-494 a screenshot of each ding, if you turned it on
    local flags = Track.get("flags")
    if type(flags) == "table" and flags.screenshots == true and C_Timer and C_Timer.After then
        C_Timer.After(1, function() pcall(Screenshot) end)
    end
end

-- W-494 the setting, for /journey screenshots and the window's Options.
function ns.DingScreenshotsOn()
    local flags = Track.get("flags")
    return type(flags) == "table" and flags.screenshots == true
end

function ns.SetDingScreenshots(on)
    local flags = Track.get("flags")
    if type(flags) == "table" then flags.screenshots = on and true or nil end
end

function ns.ToggleDingScreenshots()
    ns.SetDingScreenshots(not ns.DingScreenshotsOn())
    print(PREFIX, ns.DingScreenshotsOn() and "A screenshot will be taken at every ding."
        or "Screenshots at each ding are off.")
end

---------------------------------------------------------------------------
-- Questing or grinding (W-498)
---------------------------------------------------------------------------

local questAt, killAt = -1000, -1000

local function Tick(dt)
    local now, s = GetTime(), math.floor(dt + 0.5)
    if Call("UnitIsAFK", "player") == true or Call("UnitOnTaxi", "player") == true or Call("IsResting") == true then return end
    if now - questAt < ACTIVITY then
        Track.count("W-498", "questing", s)
    elseif now - killAt < ACTIVITY then
        Track.count("W-498", "grinding", s)
    end
end

---------------------------------------------------------------------------
-- Window page
---------------------------------------------------------------------------

local function DrawHabits(B)
    local U = ns.UI
    ns.ShowItems(B, {
        { heading = "Firsts" },
        { "W-462", "First quest" }, { "W-464", "First group" }, { "W-466", "First green item" },
        { "W-467", "First 1, 10 and 100 gold", "firsts" }, { "W-471", "First flight" },
        { "W-474", "First profession at each bracket's top", "firsts" }, { "W-475", "First time Exalted" },
        { "W-476", "First talent point" }, { "W-481", "First time your rested XP was full" },
        { "W-483", "The ding to 60" },
        { heading = "Sessions" },
        { "W-489", "Most deaths in a session" }, { "W-490", "Most kills in a session" },
        { "W-492", "Reloads" }, { "W-493", "Screenshots taken" },
        { "W-496", "Most XP in an hour" }, { "W-498", "Questing and grinding", "timemap" },
    })
    local first = Track.get("W-491")
    if type(first) == "table" and (first.sessions or 0) > 0 then
        B:Row("Average time to your first kill", U.Dur((first.seconds or 0) / first.sessions))
    end
    local late = Track.get("W-487")
    B:Row("Late-night dings (midnight to 5am)", type(late) == "table" and #late or 0)
    local flags = Track.get("flags")
    B:Note("Screenshots at each ding are " .. ((type(flags) == "table" and flags.screenshots) and "on" or "off")
        .. ": /journey screenshots")
end

ns.WrappedPage("Wrapped Stats", "Firsts & Habits", DrawHabits)

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------

ns.OnKill(function() killAt = GetTime(); OnKill() end)
ns.OnDeathRecord(OnDeath)
ns.OnLootItem(OnLoot)
ns.OnMoneyChange(function(delta, where, total) CheckGold(total) end)
ns.OnDing(Protect(OnDing))
ns.WrappedTick(Tick)

On("PLAYER_ENTERING_WORLD", function(isInitialLogin, isReload)
    if isReload then Track.count("W-492") end                 -- W-492 reloads
    if isInitialLogin then xpWindow, xpSum = {}, 0 end
    lastXP = ns.GetDB().xp.total
    wasGrouped = Call("IsInGroup") == true
    if C_Timer and C_Timer.After then
        C_Timer.After(3, Protect(function()
            CheckGold(Num(Call("GetMoney")))
            CheckBrackets()
        end))
    end
end)
On("QUEST_TURNED_IN", function(questID) questAt = GetTime(); OnQuestTurnedIn(questID) end)
On("QUEST_ACCEPTED", function() questAt = GetTime() end)
On("QUEST_WATCH_UPDATE", function() questAt = GetTime() end)
On("UI_INFO_MESSAGE", function(_, msg)
    msg = Str(Safe(msg))
    if msg and msg:find("%d+/%d+") then questAt = GetTime() end -- objective progress
end)
On("GROUP_ROSTER_UPDATE", OnRoster)
On("PLAYER_XP_UPDATE", OnXP)
On("CHAT_MSG_SKILL", OnSkill)
On("SCREENSHOT_SUCCEEDED", function() Track.count("W-493") end) -- W-493 screenshots
ns.OnLoad(function()
    ns.Hook("TakeTaxiNode", Protect(function(index)
        local to = Str(Call("TaxiNodeName", Num(Safe(index)) or 0))
        -- The main tracker has counted this flight already.
        Track.firstEver("W-471", { to = to }, (ns.GetDB().travel.flights or 0) > 1) -- W-471 first flight
    end))
end)
