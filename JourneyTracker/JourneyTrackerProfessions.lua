-- JourneyTracker wrapped stats: professions, reputation and holidays. IDs
-- match wrapped-tracking-spec.md:
--   Professions deep dive (W-411..W-438)
--   Reputation and factions (W-439..W-454)
--   Holidays and world events (W-455..W-461), behind the "holiday" flag
--   until Forever's calendar is known
-- Herbs, ore and skins by type are the main tracker's (#103), and skill at
-- each level is #92.

local ADDON_NAME, ns = ...
local Track = ns.Track
local Safe, Call, Num, Str, IsSecret = ns.Safe, ns.Call, ns.Num, ns.Str, ns.IsSecret
local On, Protect = ns.WrappedOn, ns.Protect

local RECIPE, TRADE_GOODS = 9, 7          -- item classes
local GATHERED = { [5] = true, [6] = true, [7] = true, [9] = true } -- trade goods: cloth, leather, metal & stone, herb
local FISHING_BOBBER = 35591              -- the bobber's object ID; loot from another object is a pool
local FISHING_GAP = 120                   -- seconds between casts that still make one session
local VISIT_GAP = 600                     -- a new Darkmoon Faire visit after this long away
local CLOTH = { ["Linen Cloth"] = true, ["Wool Cloth"] = true, ["Silk Cloth"] = true, ["Mageweave Cloth"] = true,
    ["Runecloth"] = true, ["Felcloth"] = true }
local EXPLOSIVES = { "Dynamite", "Bomb", "Grenade", "Sapper Charge", "Land Mine", "Explosive Sheep" }
local GADGETS = { "Gnomish", "Goblin Rocket", "Goblin Dragon Gun", "Goblin Bomb Dispenser", "Goblin Mortar",
    "Net-o-Matic", "Death Ray", "Mind Control Cap", "Shrink Ray", "Discombobulator", "Dimensional Ripper",
    "Ultrasafe Transporter", "World Enlarger", "Battle Chicken", "Dragonling" }
local POTIONS = { "Potion", "Elixir", "Flask" }
local CABLES = { "Defibrillate", "Jumper Cables" }
-- Turn-in quests that are about reputation (W-452).
local TURN_IN_WORDS = { "Donation", "Additional", "Insignia", "Feathers", "Beads", "Texts", "Dark Iron Ore",
    "Resonite", "Supplies for", "Minion's Scourgestones", "Invader's Scourgestones", "Corruptor's Scourgestones" }
local DONATION_WORDS = { "Donation", "Runecloth" }

-- Factions by ID, with the name to look for if the game can't look up IDs.
local FACTIONS = {
    [576] = "Timbermaw Hold", [609] = "Cenarion Circle", [529] = "Argent Dawn", [59] = "Thorium Brotherhood",
    [349] = "Ravenholdt", [21] = "Booty Bay", [577] = "Everlook", [369] = "Gadgetzan", [470] = "Ratchet",
    [72] = "Stormwind", [47] = "Ironforge", [69] = "Darnassus", [54] = "Gnomeregan Exiles",
    [76] = "Orgrimmar", [81] = "Thunder Bluff", [68] = "Undercity", [530] = "Darkspear Trolls",
}
local PROGRESSION = { ["W-443"] = { 576 }, ["W-444"] = { 609 }, ["W-445"] = { 529 }, ["W-446"] = { 59 },
    ["W-447"] = { 349 }, ["W-448"] = { 21, 577, 369, 470 } }
local HOME_CITY = { Human = 72, Dwarf = 47, NightElf = 69, Gnome = 54, Orc = 76, Tauren = 81, Scourge = 68, Troll = 530 }
local CITIES = { Alliance = { 72, 47, 69, 54 }, Horde = { 76, 81, 68, 530 } }
local CENTAURS = { ["Magram Clan Centaur"] = true, ["Gelkis Clan Centaur"] = true }

-- Holidays (English names).
local FAIRE_NPCS = { ["Silas Darkmoon"] = true, ["Sayge"] = true, ["Lhara"] = true, ["Burth"] = true,
    ["Yebb Neblegear"] = true, ["Kerri Hicks"] = true, ["Rinling"] = true, ["Flik"] = true, ["Morja"] = true,
    ["Gelvas Grimegate"] = true, ["Stamp Thunderhorn"] = true, ["Maxima Blastenheimer"] = true,
    ["Professor Thaddeus Paleo"] = true, ["Chronos"] = true, ["Felinda Frye"] = true }
local HALLOWS = { "Treat Bag", "Candy", "Pumpkin Treat", "Hallowed Wand", "Tricky Treat" }
local PRESENTS = { "Gaily Wrapped Present", "Festive Gift", "Gently Shaken Gift", "Ticking Present",
    "Winter Veil Gift", "Carefully Wrapped Present", "Smokywood Pastures", "Stolen Present" }
local HOLIDAY_WORDS = { "Darkmoon", "Hallow", "Winter Veil", "Greatfather Winter", "Lunar", "Elune's Blessing",
    "Children's Week", "Harvest Festival", "Love is in the Air", "Noblegarden", "Midsummer", "Fire Festival",
    "Master Angler", "Treats for" }

local INCREASED = ns.PatternFrom(FACTION_STANDING_INCREASED, "Your %s reputation has increased by %d.")
local DECREASED = ns.PatternFrom(FACTION_STANDING_DECREASED, "Your %s reputation has decreased by %d.")
local STANDING = ns.PatternFrom(FACTION_STANDING_CHANGED, "You are now %s with %s.")
local LEARNED_RECIPE = ns.PatternFrom(ERR_LEARN_RECIPE_S, "You have learned how to create a new item: %s.")

local function HasAny(text, words)
    if not text then return false end
    for _, w in ipairs(words) do
        if text:find(w, 1, true) then return true end
    end
    return false
end

local function NameOf(link) return link and link:match("%[(.-)%]") end

local function ItemClass(item)
    local _, _, _, _, _, classID, subClassID = Call("C_Item.GetItemInfoInstant", item)
    if not classID then _, _, _, _, _, classID, subClassID = Call("GetItemInfoInstant", item) end
    return Num(classID), Num(subClassID)
end

local function SellPrice(item)
    local price = select(11, Call("C_Item.GetItemInfo", item))
    if Num(price) == nil then price = select(11, Call("GetItemInfo", item)) end
    return Num(price)
end

local function Gathered(item)
    local classID, subClassID = ItemClass(item)
    return classID == TRADE_GOODS and GATHERED[subClassID] == true
end

---------------------------------------------------------------------------
-- Gathering (W-414, W-415, W-419, W-420)
---------------------------------------------------------------------------

local node = {}            -- the node your last gathering cast was aimed at: name, t
local gatherCast            -- a gathering cast in progress: castGUID
local GATHER_SPELLS = { ["Herb Gathering"] = true, ["Mining"] = true, ["Skinning"] = true }

local function OnSent(unit, target, castGUID, spellID)
    local name = ns.SpellName(Num(Safe(spellID)) or 0)
    if not GATHER_SPELLS[name or ""] then return end
    node = { name = not IsSecret(target) and Str(target) or nil, t = GetTime() }
end

local function OnGather(kind)
    Track.count("W-419", ns.Zone())                           -- W-419 nodes by zone
    if kind == "mining" and node.name and GetTime() - node.t < 10 then
        if node.name:find("Truesilver", 1, true) then
            Track.count("W-414", "Truesilver")                -- W-414 Truesilver and Silver veins
        elseif node.name:find("Silver", 1, true) then
            Track.count("W-414", "Silver")
        end
    end
end

---------------------------------------------------------------------------
-- Fishing (W-421..W-425)
---------------------------------------------------------------------------

local FISHING = { [7620] = true, [7731] = true, [7732] = true, [18248] = true }
local fishingSince, lastCast = nil, -1000

local function OnChannelStart(unit, castGUID, spellID)
    spellID = Num(Safe(spellID))
    if not spellID or not (FISHING[spellID] or ns.SpellName(spellID) == "Fishing") then return end
    local now = GetTime()
    Track.count("W-421", "casts")                             -- W-421 fishing casts
    if not fishingSince or now - lastCast > FISHING_GAP then fishingSince = now end
    lastCast = now
    if now > fishingSince then
        Track.max("W-425", math.floor(now - fishingSince + 0.5)) -- W-425 longest fishing session
    end
end

---------------------------------------------------------------------------
-- Loot: gems, cloth, fishing, disenchanting, recipes (W-415..W-423,
-- W-428, W-430, W-460)
---------------------------------------------------------------------------

local lastDisenchant = -1000

local function OnLoot(link, count, quality, extra)
    local name = NameOf(link)
    if not name then return end
    count = count or 1
    extra = extra or {}
    if extra.gather == "mining" and (quality or 0) >= 2 then
        Track.count("W-415", name, count)                     -- W-415 gems found mining
    end
    if CLOTH[name] and not extra.gather then
        Track.count("W-417", name, count)                     -- W-417 cloth by type (total: W-418)
    end
    if extra.fishing then
        Track.count("W-422", name, count)                     -- W-422 caught, by type
        Track.count("W-423", quality == 0 and "junk" or "fish", count) -- W-423 junk vs fish
        if name == "Speckled Tastyfish" and Track.enabled("holiday") then
            Track.count("W-460", "Speckled Tastyfish", count) -- W-460 the Fishing Extravaganza
        end
    end
    if GetTime() - lastDisenchant < 5 then
        Track.count("W-430.mats", name, count)                -- W-430 what disenchanting gave
    end
    if ItemClass(link) == RECIPE then
        local id = tonumber(link:match("item:(%d+)"))
        local looted = Track.get("lootedRecipes")
        if type(looted) ~= "table" then looted = {} end
        if id then looted[id] = true end
        Track.set("lootedRecipes", looted)
    end
end

-- Fishing loot windows: catches (W-421) and pools (W-424).
local function OnLootOpened()
    if Call("IsFishingLoot") ~= true then return end
    Track.count("W-421", "catches")                           -- catch rate: catches / casts
    for slot = 1, Num(Call("GetNumLootItems")) or 0 do
        local guid = Str(Call("GetLootSourceInfo", slot))
        local object = guid and tonumber(guid:match("^GameObject%-%d+%-%d+%-%d+%-%d+%-(%d+)"))
        if object and object ~= FISHING_BOBBER then
            Track.count("W-424")                              -- W-424 fished from a pool
            return
        end
    end
end

---------------------------------------------------------------------------
-- Crafting (W-426, W-427, W-436)
---------------------------------------------------------------------------

local tradeSkill -- the profession whose window is open

-- W-427 recipes known per profession: the most the window has listed (a
-- collapsed header hides some).
local function CountRecipes(profession, n, info)
    if not profession or profession == "Beast Training" then return end
    local known = 0
    for i = 1, n do
        local _, kind = info(i)
        if kind ~= "header" then known = known + 1 end
    end
    local map = Track.get("W-427")
    if type(map) ~= "table" then map = {} end
    if known > (map[profession] or 0) then
        map[profession] = known
        Track.set("W-427", map)
    end
end

local function OnTradeSkill()
    tradeSkill = Str(Call("GetTradeSkillLine"))
    CountRecipes(tradeSkill, Num(Call("GetNumTradeSkills")) or 0, function(i)
        local name, kind = Call("GetTradeSkillInfo", i)
        return Str(name), Str(kind)
    end)
end

local function OnCraft()
    tradeSkill = Str(Call("GetCraftDisplaySkillLine")) or Str(Call("GetCraftName"))
    CountRecipes(tradeSkill, Num(Call("GetNumCrafts")) or 0, function(i)
        local name, _, kind = Call("GetCraftInfo", i)
        return Str(name), Str(kind)
    end)
end

local function OnCreated(name, count)
    if tradeSkill == "Cooking" then Track.count("W-426", name, count) end -- W-426 cooked, by item
    if HasAny(name, POTIONS) then Track.count("W-436", name, count) end    -- W-436 potions and elixirs
end

---------------------------------------------------------------------------
-- Items used: recipes, explosives, dummies, holiday items (W-428,
-- W-432, W-433, W-453, W-456, W-459), and gadgets (W-435)
---------------------------------------------------------------------------

local questDoneAt, questTitle = -1000, nil
local faireAt = -1000      -- last seen at the Darkmoon Faire
local recentCloth = {}     -- cloth just handed over: { name, n, t }, matched to a donation quest

local function DonationJustNow() return GetTime() - questDoneAt < 2 and HasAny(questTitle, DONATION_WORDS) end

local function OnItemChange(c)
    local name, n, kind = c.name, math.abs(c.delta), c.kind
    if not name then return end
    if kind == "used" then
        if c.classID == RECIPE then
            local looted = Track.get("lootedRecipes")
            if type(looted) == "table" and looted[c.id] then
                looted[c.id] = nil
                Track.count("W-428", name)                    -- W-428 recipes learned from drops
            end
        end
        if HasAny(name, EXPLOSIVES) then Track.count("W-432", name, n) end -- W-432 explosives
        if name:find("Target Dummy", 1, true) then Track.count("W-433", name, n) end -- W-433 dummies
        if CLOTH[name] then
            if DonationJustNow() then
                Track.count("W-453", name, n)                 -- W-453 cloth donated
            else
                table.insert(recentCloth, { name = name, n = n, t = GetTime() }) -- the quest may come next
                if #recentCloth > 5 then table.remove(recentCloth, 1) end
            end
        end
        if Track.enabled("holiday") and HasAny(name, PRESENTS) then
            Track.count("W-459", name, n)                     -- W-459 presents opened
        end
    end
    if Track.enabled("holiday") then
        if c.delta < 0 and name == "Darkmoon Faire Prize Ticket" then
            Track.count("W-456", nil, n)                      -- W-456 tickets turned in
        elseif c.delta > 0 and name:find("Fortune", 1, true) and (name:find("Sayge", 1, true) or name:find("Darkmoon", 1, true)) then
            Track.count("W-457", name, n)                     -- W-457 fortunes
        elseif c.delta > 0 and HasAny(name, HALLOWS) then
            Track.count("W-458", name, n)                     -- W-458 Hallow's End treats
        end
    end
    if kind == "sold" and Gathered(c.id) then
        local price = SellPrice(c.id)
        if price then Track.count("W-437", "vendor", price * n) end -- W-437 gold from gathered goods
    end
end

-- Gadgets: an item use (a link, an item ID or a name), then the cast it
-- makes.
local gadget
local function TryGadget(item)
    if not item then return end
    local name = type(item) == "string" and (NameOf(item) or item) or Str(Call("GetItemInfo", item))
    if not HasAny(name, GADGETS) then return end
    gadget = { name = name, spell = Str(Call("GetItemSpell", item)), t = GetTime() }
end

-- An auction sale of gathered goods (W-437), as its money is taken.
local function OnTakeMoney(index)
    index = Num(Safe(index))
    if not index then return end
    local money = Num(select(5, Call("GetInboxHeaderInfo", index)))
    if not money or money <= 0 then return end
    local kind, item = Call("GetInboxInvoiceInfo", index)
    if Str(kind) == "seller" and Str(item) and Gathered(Str(item)) then
        Track.count("W-437", "auction house", money)
    end
end

---------------------------------------------------------------------------
-- Casts: disenchanting, enchanting for others, cables, gadgets (W-430,
-- W-431, W-434, W-435) and lost nodes (W-420)
---------------------------------------------------------------------------

local tradeOpen = false

local function OnCast(name)
    if not name then return end
    local now = GetTime()
    if name == "Disenchant" then
        lastDisenchant = now
        Track.count("W-430")                                  -- W-430 items disenchanted
    elseif name:find("^Enchant ") and tradeOpen then
        Track.count("W-431", name)                            -- W-431 enchants for other players
    end
    if HasAny(name, CABLES) then Track.count("W-434", "used") end -- W-434 jumper cables
    if gadget and now - gadget.t < 2 and (not gadget.spell or gadget.spell == name) then
        Track.count("W-435", gadget.name)                     -- W-435 gadgets used
        gadget = nil
    end
end

-- Casts that started and didn't finish, on a frame of their own (the
-- shared one listens to some of these for your target).
local castFrame = CreateFrame("Frame")
for _, event in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED" }) do
    pcall(castFrame.RegisterUnitEvent, castFrame, event, "player")
end
castFrame:SetScript("OnEvent", Protect(function(_, event, unit, castGUID, spellID)
    local name = ns.SpellName(Num(Safe(spellID)) or 0)
    if not name then return end
    if event == "UNIT_SPELLCAST_START" then
        if GATHER_SPELLS[name] then gatherCast = Str(Safe(castGUID)) end
        return
    end
    if HasAny(name, CABLES) then Track.count("W-434", "failed") end
    -- W-420 [probe] a gathering cast cut short while you stood still out
    -- of combat: someone else took the node.
    if event == "UNIT_SPELLCAST_INTERRUPTED" and GATHER_SPELLS[name] and Track.enabled("probe")
        and gatherCast and gatherCast == Str(Safe(castGUID)) and not ns.InCombat()
        and (Num(Call("GetUnitSpeed", "player")) or 0) == 0 then
        Track.count("W-420")
    end
    gatherCast = nil
end))

---------------------------------------------------------------------------
-- Professions dropped (W-438)
---------------------------------------------------------------------------

local function CheckProfessions()
    local list = { Call("GetProfessions") }
    if #list == 0 then return end
    local now = {}
    for _, index in pairs(list) do
        local name = Str(Call("GetProfessionInfo", index))
        if name then now[name] = true end
    end
    local before = Track.get("professionsKnown")
    if type(before) == "table" then
        for name in pairs(before) do
            if not now[name] then Track.firstOf("W-438", name) end -- W-438 professions dropped
        end
    end
    Track.set("professionsKnown", now)
end

---------------------------------------------------------------------------
-- Reputation (W-439..W-454)
---------------------------------------------------------------------------

local repGainAt = -1000

local function RepOf(id)
    local data = Call("C_Reputation.GetFactionDataByID", id)
    if type(data) == "table" then return Num(Safe(data.currentStanding)) end
    local name, _, _, _, _, value = Call("GetFactionInfoByID", id)
    if Str(name) then return Num(value) end
    for i = 1, Num(Call("GetNumFactions")) or 0 do
        local rowName, _, _, _, _, rowValue, _, _, isHeader = Call("GetFactionInfo", i)
        if Str(rowName) == FACTIONS[id] and isHeader ~= true then return Num(rowValue) end
    end
end

local function OnFactionMessage(msg)
    msg = Str(Safe(msg))
    if not msg then return end
    local faction, amount = msg:match(INCREASED)
    if faction then
        amount = tonumber(amount) or 0
        Track.count("W-439", faction, amount)                 -- W-439 reputation gained (top: W-451)
        repGainAt = GetTime()
        if faction == "Bloodsail Buccaneers" then Track.count("W-442") end -- W-442 turned on Booty Bay
        if CENTAURS[faction] then
            -- W-454 the centaur clan you sided with: the one you've gained more with
            local gained = Track.get("W-439")
            local best, most = nil, -1
            for clan in pairs(CENTAURS) do
                if (gained[clan] or 0) > most then best, most = clan, gained[clan] or 0 end
            end
            local current = Track.get("W-454")
            if type(current) ~= "table" or current.name ~= best then
                Track.set("W-454", Track.context({ name = best }))
            end
        end
        return
    end
    faction, amount = msg:match(DECREASED)
    if faction then
        Track.count("W-441", faction, tonumber(amount) or 0)  -- W-441 reputation lost
        return
    end
    local standing
    standing, faction = msg:match(STANDING)
    if standing and faction then
        local map = Track.get("W-440")
        if type(map) ~= "table" then map = {} end
        map[faction] = map[faction] or {}
        if not map[faction][standing] then
            map[faction][standing] = Track.context()          -- W-440 level you reached each standing
            Track.set("W-440", map)
        end
        if standing == (FACTION_STANDING_LABEL8 or "Exalted") then
            Track.firstEver("W-475", { name = faction })      -- W-475 first time Exalted
        end
    end
end

-- W-452 reputation turn-ins, W-453 cloth donations: a quest turned in that
-- gave reputation.
local function OnQuestTurnedIn(questID)
    questID = Num(Safe(questID))
    questDoneAt = GetTime()
    questTitle = questID and Str(Call("C_QuestLog.GetTitleForQuestID", questID))
    if DonationJustNow() then
        for _, cloth in ipairs(recentCloth) do
            if questDoneAt - cloth.t < 2 then Track.count("W-453", cloth.name, cloth.n) end
        end
    end
    recentCloth = {}
    local seen = Track.get("questsTurnedIn")
    if type(seen) ~= "table" then seen = {} end
    local again = questID and seen[questID]
    if questID then seen[questID] = true end
    Track.set("questsTurnedIn", seen)
    local title = questTitle
    if C_Timer and C_Timer.After then
        C_Timer.After(2, Protect(function()
            if repGainAt >= questDoneAt - 1 and (again or HasAny(title, TURN_IN_WORDS)) then
                Track.count("W-452")                          -- W-452 reputation turn-ins
                if title then Track.count("W-452.byQuest", title) end
            end
        end))
    end
    -- W-461 holiday quests, by title or at the Darkmoon Faire
    if Track.enabled("holiday") and title and (HasAny(title, HOLIDAY_WORDS) or GetTime() - faireAt < VISIT_GAP) then
        Track.count("W-461", title)
    end
    if Track.enabled("holiday") and title == "Master Angler" then Track.count("W-460", "Master Angler") end
end

-- Reputation with the progression factions at each ding (W-443..W-448),
-- and the cities at 60 (W-449, W-450).
local function OnDing(snapshot, level)
    for id, list in pairs(PROGRESSION) do
        local row = {}
        for _, factionID in ipairs(list) do
            local value = RepOf(factionID)
            if value and value ~= 0 then row[FACTIONS[factionID]] = value end
        end
        if next(row) then
            local map = Track.get(id)
            if type(map) ~= "table" then map = {} end
            map[level] = row
            Track.set(id, map)
        end
    end
    if level >= 60 and Track.get("W-449") == nil then
        local _, race = Call("UnitRace", "player")
        local home = HOME_CITY[Str(race) or ""]
        if home then Track.set("W-449", Track.context({ name = FACTIONS[home], value = RepOf(home) })) end -- W-449
        local others = {}
        for _, id in ipairs(CITIES[Str(Call("UnitFactionGroup", "player")) or ""] or {}) do
            if id ~= home then others[FACTIONS[id]] = RepOf(id) end
        end
        if next(others) then Track.set("W-450", others) end   -- W-450 the other cities at 60
    end
end

---------------------------------------------------------------------------
-- The Darkmoon Faire (W-455)
---------------------------------------------------------------------------

local function FaireVisit()
    local now = GetTime()
    if now - faireAt > VISIT_GAP then Track.count("W-455") end -- W-455 visits
    faireAt = now
end

local function CheckFaire()
    if not Track.enabled("holiday") then return end
    if ns.SubZone() == "Darkmoon Faire" then FaireVisit() end
end

---------------------------------------------------------------------------
-- Window pages
---------------------------------------------------------------------------

local function Total(id)
    local n = 0
    for _, v in pairs(type(Track.get(id)) == "table" and Track.get(id) or {}) do
        if type(v) == "number" then n = n + v end
    end
    return n
end

local function DrawProfessions(B)
    local fishing = Track.get("W-421")
    local casts = type(fishing) == "table" and fishing.casts or 0
    local catches = type(fishing) == "table" and fishing.catches or 0
    ns.ShowItems(B, {
        { heading = "Gathering" },
        { "W-419", "Nodes by zone", "map" }, { "W-414", "Truesilver and Silver veins", "map" },
        { "W-415", "Gems found mining", "map" }, { "W-420", "Nodes lost to someone else" },
        { "W-417", "Cloth looted", "map" },
    })
    B:Row("Cloth in all", ns.UI.Num(Total("W-417")))          -- W-418
    ns.ShowItems(B, { { heading = "Fishing" } })
    B:Row("Casts, catches", casts .. " / " .. catches .. (casts > 0 and (" (" .. math.floor(catches / casts * 100 + 0.5) .. "%)") or ""))
    ns.ShowItems(B, {
        { "W-422", "Caught, by type", "map" }, { "W-423", "Fish and junk", "map" },
        { "W-424", "Pools fished" }, { "W-425", "Longest fishing session", "time" },
        { heading = "Crafting" },
        { "W-426", "Cooked (the top one is your favorite)", "map" }, { "W-427", "Recipes known", "map" },
        { "W-428", "Recipes learned from drops", "map" }, { "W-436", "Potions and elixirs made", "map" },
        { "W-430", "Items disenchanted" }, { "W-430.mats", "What they gave", "map" },
        { "W-431", "Enchants for other players", "map" }, { "W-437", "Gold from gathered goods", "moneymap" },
        { "W-438", "Professions dropped", "firsts" },
        { heading = "Engineering" },
        { "W-432", "Explosives thrown", "map" }, { "W-433", "Target dummies", "map" },
        { "W-434", "Jumper cables", "map" }, { "W-435", "Gadgets used", "map" },
    })
end

local function DrawReputation(B)
    ns.ShowItems(B, {
        { heading = "Reputation" },
        { "W-439", "Gained (the top one is your best friend)", "map" }, { "W-441", "Lost", "map" },
        { "W-442", "Times you turned on Booty Bay" }, { "W-454", "Desolace centaurs you sided with" },
        { "W-452", "Reputation turn-ins" }, { "W-453", "Cloth donated", "map" },
        { "W-449", "Home city at 60" }, { "W-450", "Other cities at 60", "map" },
    })
    local standings = Track.get("W-440")
    if type(standings) == "table" and next(standings) then
        B:Row("Standings reached", "")
        for faction, reached in pairs(standings) do
            local parts = {}
            for standing, ctx in pairs(reached) do parts[#parts + 1] = standing .. " at " .. tostring(ctx.level) end
            table.sort(parts)
            B:Note(faction .. ": " .. table.concat(parts, ", "))
        end
    end
    ns.ShowItems(B, {
        { heading = "Holidays" },
        { "W-455", "Darkmoon Faire visits" }, { "W-456", "Faire tickets turned in" },
        { "W-457", "Fortunes", "map" }, { "W-458", "Hallow's End treats", "map" },
        { "W-459", "Winter Veil presents opened", "map" }, { "W-460", "Fishing Extravaganza", "map" },
        { "W-461", "Holiday quests", "map" },
    })
end

ns.WrappedPage("Wrapped Stats", "Professions", DrawProfessions)
ns.WrappedPage("Wrapped Stats", "Reputation & Holidays", DrawReputation)

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------

ns.OnGather(OnGather)
ns.OnLootItem(OnLoot)
ns.OnItemChange(Protect(OnItemChange))
ns.OnCast(Protect(OnCast))
ns.OnDing(Protect(OnDing))

On("UNIT_SPELLCAST_SENT", OnSent, "player")
On("UNIT_SPELLCAST_CHANNEL_START", OnChannelStart, "player")
On("LOOT_OPENED", OnLootOpened)
On("TRADE_SKILL_SHOW", OnTradeSkill)
On("TRADE_SKILL_UPDATE", OnTradeSkill)
On("TRADE_SKILL_CLOSE", function() tradeSkill = nil end)
On("CRAFT_SHOW", OnCraft)
On("CRAFT_UPDATE", OnCraft)
On("CRAFT_CLOSE", function() tradeSkill = nil end)
On("TRADE_SHOW", function() tradeOpen = true end)
On("TRADE_CLOSED", function() tradeOpen = false end)
On("CHAT_MSG_LOOT", function(msg)
    msg = Str(Safe(msg))
    if not msg then return end
    local P = ns.PATTERNS
    local link, n = msg:match(P.createMulti)
    if not link then link = msg:match(P.create) end
    if link then OnCreated(NameOf(link) or link, tonumber(n) or 1) end
end)
On("CHAT_MSG_COMBAT_FACTION_CHANGE", OnFactionMessage)
On("QUEST_TURNED_IN", OnQuestTurnedIn)
On("SKILL_LINES_CHANGED", CheckProfessions)
On("PLAYER_ENTERING_WORLD", function()
    if C_Timer and C_Timer.After then C_Timer.After(5, Protect(CheckProfessions)) end
end)
On("ZONE_CHANGED", CheckFaire)
On("ZONE_CHANGED_NEW_AREA", CheckFaire)
On("PLAYER_TARGET_CHANGED", function()
    if Track.enabled("holiday") and FAIRE_NPCS[Str(Call("UnitName", "target")) or ""] then FaireVisit() end
end)
ns.OnLoad(function()
    ns.Hook("TakeInboxMoney", Protect(OnTakeMoney))
    ns.Hook("AutoLootMailItem", Protect(OnTakeMoney))
    ns.Hook("UseInventoryItem", Protect(function(slot)
        TryGadget(Str(Call("GetInventoryItemLink", "player", Num(Safe(slot)) or 0)))
    end))
    ns.Hook("UseContainerItem", Protect(function(bag, slot)
        local _, _, _, _, _, _, link = Call("GetContainerItemInfo", bag, slot)
        TryGadget(Str(link))
    end))
    ns.Hook("C_Container.UseContainerItem", Protect(function(bag, slot)
        local info = Call("C_Container.GetContainerItemInfo", bag, slot)
        if type(info) == "table" then TryGadget(Str(Safe(info.hyperlink))) end
    end))
    ns.Hook("UseAction", Protect(function(slot)
        local kind, id = Call("GetActionInfo", slot)
        if kind == "item" then TryGadget(Num(id)) end
    end))
    ns.Hook("UseItemByName", Protect(function(name) TryGadget(Str(Safe(name))) end))
end)
