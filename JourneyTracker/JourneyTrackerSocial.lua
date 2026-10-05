-- JourneyTracker wrapped stats: groups, chat and the odd moment. IDs match
-- wrapped-tracking-spec.md:
--   Loot rolls and group life (W-246..W-259)
--   Bloopers, the game's red error messages (W-260..W-276)
--   Social and chat (W-277..W-301)
--   Emotes (W-302..W-312)
--   Legacy, from the game's own messages ([probe], W-013..W-015)
--
-- Chat is counted, never kept. What you send is read once as it goes out
-- (to count channels and a few words), and no message text, and no other
-- player's name, is ever stored. Your own most-typed words are kept as a
-- word count map (W-292), capped like every name map.

local ADDON_NAME, ns = ...
local Track = ns.Track
local Safe, Call, Num, Str, IsSecret = ns.Safe, ns.Call, ns.Num, ns.Str, ns.IsSecret
local On, Protect = ns.WrappedOn, ns.Protect

local HEARTHSTONE_ITEM = 6948
local GZ_WINDOW = 60       -- seconds after a ding that a guild "gz" counts (W-290)

local function MyName() return Str(Call("UnitName", "player")) end
-- A message in lower case without color codes or link wrappers (one value).
local function Words(text)
    return (text:lower():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|h.-|h(.-)|h", "%1"))
end

-- Whole-word match, case-insensitive.
local function HasWord(text, words)
    for _, w in ipairs(words) do
        if text:find("%f[%w]" .. w .. "%f[%W]") then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Loot rolls (W-246..W-253)
---------------------------------------------------------------------------

local ROLL_TYPES = { [0] = "pass", [1] = "need", [2] = "greed", [3] = "disenchant" }
local rolls = {}          -- [item name] = { type, value } for items you rolled on

-- Anchored at the end: these end in a name, which would otherwise match empty.
local NEED_ROLLED = ns.PatternFrom(LOOT_ROLL_ROLLED_NEED, "Need Roll - %d for %s by %s", true)
local GREED_ROLLED = ns.PatternFrom(LOOT_ROLL_ROLLED_GREED, "Greed Roll - %d for %s by %s", true)
local YOU_WON = ns.PatternFrom(LOOT_ROLL_YOU_WON, "You won: %s", true)
local SOMEONE_WON = ns.PatternFrom(LOOT_ROLL_WON, "%s won: %s", true)
local RANDOM_ROLL = ns.PatternFrom(RANDOM_ROLL_RESULT, "%s rolls %d (%d-%d)")

local function ItemName(link) return link and (link:match("%[(.-)%]") or link) end

local function OnRollChoice(rollID, rollType)
    rollID, rollType = Num(Safe(rollID)), Num(Safe(rollType))
    if not rollType then return end
    Track.count("W-246", ROLL_TYPES[rollType] or tostring(rollType)) -- W-246 need, greed, pass
    local link = rollID and Str(Call("GetLootRollItemLink", rollID))
    local name = ItemName(link)
    if name then rolls[name] = { type = ROLL_TYPES[rollType], quality = ns.ItemQuality(link) } end
end

local function RollResult(name, won)
    local r = rolls[name]
    if not r then return end
    rolls[name] = nil
    if r.type == "pass" then
        if not won then Track.count("W-253") end              -- W-253 passed, someone else won
        return
    end
    Track.count("W-247", won and "won" or "lost")             -- W-247 rolls won and lost
    if r.value then
        if won and r.value < 10 then Track.count("W-249") end -- W-249 won with under 10
        if not won and r.value > 95 then Track.count("W-250") end -- W-250 lost with over 95
    end
    if won and r.type == "need" and r.quality == 3 then Track.count("W-252") end -- W-252 blues won on Need
end

local function OnLootMessage(msg)
    msg = Str(Safe(msg))
    if not msg then return end
    local me = MyName()
    local value, item, who = msg:match(NEED_ROLLED)
    if not value then value, item, who = msg:match(GREED_ROLLED) end
    value = tonumber(value)
    if value and who == me then
        local name = ItemName(item)
        if rolls[name] then rolls[name].value = value end
        Track.max("W-248", value, { item = name })            -- W-248 highest roll
        Track.min("W-248.lowest", value, { item = name })     -- and lowest
        return
    end
    local won = msg:match(YOU_WON)
    if won then RollResult(ItemName(won), true) return end
    local winner, lost = msg:match(SOMEONE_WON)
    if winner and winner ~= me then RollResult(ItemName(lost), false) end
end

---------------------------------------------------------------------------
-- Groups (W-254..W-259)
---------------------------------------------------------------------------

local grouped = nil       -- were you in a group at the last roster update
local function OnRoster()
    local now = Call("IsInGroup") == true
    if grouped == false and now then
        Track.count("W-254")                                  -- W-254 groups joined
        if Call("UnitIsGroupLeader", "player") == true then Track.count("W-256") end -- W-256 formed as leader
        -- W-258/W-259 highest or lowest level in the party, once per group
        if C_Timer and C_Timer.After then
            C_Timer.After(3, Protect(function()
                local me, highest, lowest, any = ns.Level(), true, true, false
                local n = Num(Call("GetNumGroupMembers")) or 0
                local raid = Call("IsInRaid") == true
                for i = 1, raid and n or (n - 1) do
                    local unit = (raid and "raid" or "party") .. i
                    if Call("UnitIsUnit", unit, "player") ~= true then
                        local level = Num(Call("UnitLevel", unit))
                        if level then
                            any = true
                            if level > me then highest = false end
                            if level < me then lowest = false end
                        end
                    end
                end
                if any and highest then Track.count("W-258") end
                if any and lowest then Track.count("W-259") end
            end))
        end
    elseif grouped and not now then
        Track.count("W-255", "left")                          -- W-255 groups left
    end
    grouped = now
end

---------------------------------------------------------------------------
-- Bloopers (W-260..W-276)
---------------------------------------------------------------------------

-- Each blooper, by the game's own error strings (English as a fallback).
local function Strings(...)
    local out = {}
    for i = 1, select("#", ...), 2 do
        local global, english = select(i, ...)
        out[#out + 1] = type(global) == "string" and global or english
        out[#out + 1] = english
    end
    return out
end
local BLOOPERS = {
    { "W-260", Strings(ERR_BADATTACKFACING, "You are facing the wrong way!",
        SPELL_FAILED_UNIT_NOT_INFRONT, "Target needs to be in front of you.") },
    { "W-261", Strings(ERR_OUT_OF_RANGE, "Out of range.", SPELL_FAILED_OUT_OF_RANGE, "Out of range") },
    { "W-262", Strings(ERR_OUT_OF_MANA, "Not enough mana", ERR_OUT_OF_RAGE, "Not enough rage",
        ERR_OUT_OF_ENERGY, "Not enough energy") },
    { "W-263", Strings(SPELL_FAILED_NOT_READY, "Spell is not ready yet.", ERR_SPELL_COOLDOWN, "Spell is not ready yet.") },
    { "W-264", Strings(ERR_INV_FULL, "Inventory is full.") },
    { "W-265", Strings(SPELL_FAILED_MOVING, "Can't do that while moving") },
    { "W-266", Strings(ERR_INVALID_ATTACK_TARGET, "You cannot attack that target.",
        SPELL_FAILED_BAD_TARGETS, "Invalid target") },
    { "W-267", Strings(ERR_ABILITY_COOLDOWN, "Ability is not ready yet.", ERR_GENERIC_NO_TARGET, "You have no target.",
        SPELL_FAILED_SPELL_IN_PROGRESS, "Another action is in progress") },
    { "W-269", Strings(SPELL_FAILED_LINE_OF_SIGHT, "Target not in line of sight") },
    { "W-270", Strings(ERR_TOOFARAWAY, "You are too far away!", ERR_USE_TOO_FAR, "You are too far away.") },
    { "W-271", Strings(ERR_ATTACK_MOUNTED, "Can't attack while mounted.", SPELL_FAILED_NOT_MOUNTED, "You are mounted",
        ERR_NOT_WHILE_MOUNTED, "You can't do that while mounted.") },
    { "W-272", Strings(ERR_PLAYER_DEAD, "You are dead.", SPELL_FAILED_CASTER_DEAD, "You are dead") },
    { "W-274", Strings(ERR_NOT_ENOUGH_MONEY, "You don't have enough money.") },
    { "W-275", Strings(ERR_ITEM_MAX_COUNT, "You can't carry any more of those items.") },
}
local ITEM_NOT_READY = Strings(ERR_ITEM_COOLDOWN, "Item is not ready yet.")
local lastItemUse = { id = nil, t = 0 }

local function IsOneOf(msg, list)
    for _, s in ipairs(list) do if msg == s then return true end end
    return false
end

local function OnError(_, msg)
    msg = Str(Safe(msg))
    if not msg then return end
    Track.count("W-276", nil)                                 -- W-276 total errors
    Track.count("W-276.byMessage", msg)                       -- and which (the most common is the top one)
    for _, b in ipairs(BLOOPERS) do
        if IsOneOf(msg, b[2]) then Track.count(b[1]) end
    end
    -- W-273 the Hearthstone pressed while on cooldown
    if IsOneOf(msg, ITEM_NOT_READY) and lastItemUse.id == HEARTHSTONE_ITEM and GetTime() - lastItemUse.t < 1 then
        Track.count("W-273")
    end
end

-- Which item you just tried to use (bags or action bar), for W-273.
local function UsedItem(id)
    id = Num(Safe(id))
    if id then lastItemUse = { id = id, t = GetTime() } end
end

---------------------------------------------------------------------------
-- Chat (W-277..W-301)
---------------------------------------------------------------------------

local CHANNELS = { SAY = "W-277", YELL = "W-278", PARTY = "W-279", RAID = "W-279", INSTANCE_CHAT = "W-279",
    GUILD = "W-280", OFFICER = "W-280", WHISPER = "W-281" }
local TYPED = {
    { "W-284", { "lol", "lmao", "haha", "rofl" } }, { "W-285", { "gz", "grats", "gratz", "congrats" } },
    { "W-286", { "ty", "thanks", "thx" } }, { "W-287", { "inc", "help" } }, { "W-288", { "lfg", "lfm" } },
    { "W-289", { "brb", "afk" } },
}
-- Words too common to be anyone's "most typed word".
local STOP = {}
for w in ("the and you for that this with have are was not but all can just like get got its it's what " ..
          "out your from they will one would there their when then them how who why yes yeah"):gmatch("%S+") do
    STOP[w] = true
end

-- A message you sent: counted by where it went, a few words matched, and
-- your own words tallied. Nothing is kept but the counts.
local function OnSent(msg, chatType, _, target)
    msg, chatType = Str(Safe(msg)), Str(Safe(chatType))
    if not msg or not chatType then return end
    chatType = chatType:upper()
    if chatType == "EMOTE" then
        Track.count("W-302")                                  -- W-302 emotes (typed /e ones too)
        return
    end
    local id = CHANNELS[chatType]
    if chatType == "CHANNEL" then
        local _, name = Call("GetChannelName", Safe(target))
        name = Str(name) or ""
        if name:find("General", 1, true) or name:find("Trade", 1, true) or name:find("LookingForGroup", 1, true) then
            id = "W-283"                                      -- W-283 General/Trade/LFG
        end
    end
    if id then Track.count(id) end
    local text = Words(msg)
    for _, t in ipairs(TYPED) do
        if HasWord(text, t[2]) then Track.count(t[1]) end     -- W-284..W-289
    end
    for word in text:gmatch("[%a']+") do
        if #word >= 3 and not STOP[word] then Track.count("W-292", word) end -- W-292 your words
    end
end

-- W-290/W-291 guildmates' "gz" after your ding.
local lastDing, dingGz = 0, 0
local function OnGuildChat(msg, sender)
    if GetTime() - lastDing > GZ_WINDOW then return end
    msg, sender = Str(Safe(msg)), Str(Safe(sender))
    if not msg or not sender then return end
    local me = MyName()
    if me and (sender == me or sender:match("^(.-)%-") == me) then return end
    if HasWord(Words(msg), { "gz", "grats", "gratz", "congrats", "congratulations", "ding" }) then
        Track.count("W-290")
        dingGz = dingGz + 1
        Track.max("W-291", dingGz)
    end
end

-- Trades (W-296..W-299): the window's money changes and what you handed over.
local tradeOpen, tradeUntil = false, 0
local function InTrade() return tradeOpen or GetTime() < tradeUntil end

local wasInGuild
local function CheckGuild()
    local inGuild = Call("IsInGuild") == true
    if wasInGuild ~= nil and inGuild ~= wasInGuild then
        Track.count("W-300", inGuild and "joined" or "left")  -- W-300 guilds joined and left
    end
    wasInGuild = inGuild
end

local inspected = {}

---------------------------------------------------------------------------
-- Emotes (W-302..W-312)
---------------------------------------------------------------------------

local function OnEmote(token)
    token = Str(Safe(token))
    if not token then return end
    Track.count("W-302")                                      -- W-302 total emotes
    Track.count("W-303", token:upper())                       -- W-303 by emote (W-304..W-310 read from this)
end

-- Emotes aimed at you: the sender's name is dropped and only the verb kept
-- ("hugs"), for W-311 and W-312.
local function OnTextEmote(text, sender)
    text, sender = Str(Safe(text)), Str(Safe(sender))
    if not text or not sender then return end
    local me = MyName()
    if sender == me or (me and sender:match("^(.-)%-") == me) then return end
    if not text:find("%f[%w]you%f[%W]") then return end
    Track.count("W-311")
    local rest = text:sub(#sender + 1)
    local verb = rest:match("^%s*(%a+)")
    if verb then Track.count("W-312", verb:lower()) end
end

---------------------------------------------------------------------------
-- Legacy ([probe], W-013..W-015): the game's messages that mention it
---------------------------------------------------------------------------

local function OnSystemForLegacy(msg)
    msg = Str(Safe(msg))
    if not msg or not msg:find("Legacy", 1, true) then return end
    local kind = (msg:lower():find("perk", 1, true) and "W-015") or (msg:lower():find("point", 1, true) and "W-014")
        or "W-013"
    Track.list(kind, { text = msg:sub(1, 120), level = ns.Level(), t = time() }, 60)
end

-- Which Legacy functions this client has, so the next probe knows where
-- to look (names only).
local function FindLegacyApi()
    local found = {}
    for name, value in pairs(_G) do
        if type(name) == "string" and name:find("Legacy", 1, true) and (type(value) == "function" or type(value) == "table") then
            found[#found + 1] = name
            if #found >= 30 then break end
        end
    end
    table.sort(found)
    Track.set("legacyApi", found)
end

---------------------------------------------------------------------------
-- Every 5 seconds: group with guildmates, guild time
---------------------------------------------------------------------------

local function Tick(dt)
    local s = math.floor(dt + 0.5)
    Track.count("W-301", Call("IsInGuild") == true and "in a guild" or "unguilded", s) -- W-301
    if Call("IsInGroup") ~= true then return end
    local n = Num(Call("GetNumGroupMembers")) or 0
    local raid = Call("IsInRaid") == true
    for i = 1, raid and n or (n - 1) do
        local unit = (raid and "raid" or "party") .. i
        if Call("UnitIsUnit", unit, "player") ~= true and Call("UnitIsInMyGuild", unit) == true then
            Track.count("W-257", nil, s)                      -- W-257 grouped with guildmates
            return
        end
    end
end

---------------------------------------------------------------------------
-- Window page
---------------------------------------------------------------------------

local function DrawSocial(B)
    ns.ShowItems(B, {
        { heading = "Loot Rolls" },
        { "W-246", "Need, Greed and Pass" }, { "W-247", "Rolls won and lost" },
        { "W-248", "Highest roll" }, { "W-248.lowest", "Lowest roll" },
        { "W-249", "Won with under 10" }, { "W-250", "Lost with over 95" },
        { "W-251", "/roll: rolls and their total" }, { "W-252", "Blue items won on Need" },
        { "W-253", "Passed, and someone else won it" },
        { heading = "Groups" },
        { "W-254", "Groups joined" }, { "W-255", "Groups left and removed from" },
        { "W-256", "Groups you started as leader" }, { "W-257", "Time grouped with guildmates", "time" },
        { "W-258", "Highest level in the group" }, { "W-259", "Lowest level in the group" },
        { heading = "Chat (counts only)" },
        { "W-277", "/say" }, { "W-278", "/yell" }, { "W-279", "Party and raid" }, { "W-280", "Guild" },
        { "W-281", "Whispers sent" }, { "W-282", "Whispers received" }, { "W-283", "General, Trade and LFG" },
        { "W-284", "'lol' and friends" }, { "W-285", "'gz'" }, { "W-286", "'ty'" }, { "W-287", "'inc' or 'help'" },
        { "W-288", "'LFG' or 'LFM'" }, { "W-289", "'brb' or 'afk'" },
        { "W-290", "Guild 'gz' after your dings" }, { "W-291", "Most 'gz' on one ding" },
        { "W-292", "Your most typed words" },
        { "W-294", "Friends added" }, { "W-295", "Players inspected" }, { "W-296", "Trades completed" },
        { "W-297", "Gold given in trades", "money" }, { "W-298", "Gold received in trades", "money" },
        { "W-299", "Items given in trades" }, { "W-300", "Guilds joined and left" },
        { "W-301", "Time in a guild and without", "timemap" },
        { heading = "Emotes" },
        { "W-302", "Emotes used" }, { "W-303", "By emote" }, { "W-311", "Emotes aimed at you" },
        { "W-312", "Aimed at you, by emote" },
    })
end

local function DrawBloopers(B)
    ns.ShowItems(B, {
        { heading = "Bloopers" },
        { "W-260", "Facing the wrong way" }, { "W-261", "Out of range" }, { "W-262", "Not enough mana, rage or energy" },
        { "W-263", "Spell not ready" }, { "W-264", "Inventory full" }, { "W-265", "Can't do that while moving" },
        { "W-266", "Invalid target" }, { "W-267", "Can't do that yet" }, { "W-268", "Casts interrupted" },
        { "W-269", "Not in line of sight" }, { "W-270", "Too far away" }, { "W-271", "You're mounted" },
        { "W-272", "You're dead" }, { "W-273", "Hearthstone on cooldown" }, { "W-274", "Not enough money" },
        { "W-275", "Can't carry any more of those" }, { "W-276", "Errors in all" },
        { "W-276.byMessage", "Most common" },
        { heading = "Legacy (from the game's messages)" },
        { "W-013", "Legacy challenges" }, { "W-014", "Legacy points" }, { "W-015", "Legacy perks" },
    })
end

ns.WrappedPage("Wrapped Stats", "Groups & Chat", DrawSocial)
ns.WrappedPage("Wrapped Stats", "Bloopers", DrawBloopers)

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------

On("PLAYER_ENTERING_WORLD", function(isInitialLogin, isReload)
    if grouped == nil then grouped = Call("IsInGroup") == true end
    if isInitialLogin or isReload then
        if C_Timer and C_Timer.After then C_Timer.After(10, Protect(CheckGuild)) end
        FindLegacyApi()
    end
end)
On("GROUP_ROSTER_UPDATE", OnRoster)
On("CHAT_MSG_LOOT", OnLootMessage)
On("CHAT_MSG_SYSTEM", function(msg)
    OnSystemForLegacy(msg)
    msg = Str(Safe(msg))
    if not msg then return end
    local who, value, low, high = msg:match(RANDOM_ROLL)
    if who and who == MyName() then
        Track.count("W-251", "rolls")                         -- W-251 /roll uses and their total (average on the website)
        Track.count("W-251", "total", tonumber(value) or 0)
        return
    end
    if msg == (type(ERR_UNINVITE_YOU) == "string" and ERR_UNINVITE_YOU or "You have been removed from the group.") then
        Track.count("W-255", "removed")                       -- W-255 removed from a group
    elseif msg == (type(ERR_TRADE_COMPLETE) == "string" and ERR_TRADE_COMPLETE or "Trade complete.") then
        Track.count("W-296")                                  -- W-296 trades completed
    end
end)
On("UI_ERROR_MESSAGE", OnError)
-- W-268 your casts interrupted. On a frame of its own: the class tracker
-- listens to the same event for your target, and the shared frame keeps
-- one unit filter per event.
local interrupts = CreateFrame("Frame")
if pcall(interrupts.RegisterUnitEvent, interrupts, "UNIT_SPELLCAST_INTERRUPTED", "player") then
    interrupts:SetScript("OnEvent", Protect(function() Track.count("W-268") end))
end
On("CHAT_MSG_WHISPER", function() Track.count("W-282") end)                    -- W-282 whispers received
On("CHAT_MSG_GUILD", OnGuildChat)
On("CHAT_MSG_TEXT_EMOTE", OnTextEmote)
On("PLAYER_LEVEL_UP", function() lastDing, dingGz = GetTime(), 0 end)
On("INSPECT_READY", function(guid)
    guid = Str(Safe(guid))
    if guid and not inspected[guid] then
        inspected[guid] = true
        Track.count("W-295")                                  -- W-295 players inspected
    end
end)
On("PLAYER_GUILD_UPDATE", CheckGuild)
On("TRADE_SHOW", function() tradeOpen = true end)
On("TRADE_CLOSED", function() tradeOpen, tradeUntil = false, GetTime() + 2 end)
ns.OnMoneyChange(function(delta)
    if not InTrade() then return end
    if delta < 0 then Track.count("W-297", nil, -delta) else Track.count("W-298", nil, delta) end -- W-297/W-298
end)
ns.OnItemChange(Protect(function(c)
    if c.kind == "traded" and c.delta < 0 then Track.count("W-299", nil, -c.delta) end -- W-299 items given
end))
ns.WrappedTick(Tick)
ns.OnLoad(function()
    local function Sent(msg, chatType, language, target) OnSent(msg, chatType, language, target) end
    ns.Hook("SendChatMessage", Protect(Sent))
    ns.Hook("C_ChatInfo.SendChatMessage", Protect(Sent))
    ns.Hook("RollOnLoot", Protect(OnRollChoice))
    ns.Hook("DoEmote", Protect(OnEmote))
    ns.Hook("AddFriend", Protect(function() Track.count("W-294") end))        -- W-294 friends added
    ns.Hook("C_FriendList.AddFriend", Protect(function() Track.count("W-294") end))
    ns.Hook("UseContainerItem", Protect(function(bag, slot)
        local _, _, _, _, _, _, _, _, _, id = Call("GetContainerItemInfo", bag, slot)
        UsedItem(id)
    end))
    ns.Hook("C_Container.UseContainerItem", Protect(function(bag, slot)
        local info = Call("C_Container.GetContainerItemInfo", bag, slot)
        if type(info) == "table" then UsedItem(info.itemID) end
    end))
    ns.Hook("UseAction", Protect(function(slot)
        local kind, id = Call("GetActionInfo", slot)
        if kind == "item" then UsedItem(id) end
    end))
    ns.Hook("UseItemByName", Protect(function(name)
        if Str(Safe(name)) == "Hearthstone" then UsedItem(HEARTHSTONE_ITEM) end
    end))
end)
