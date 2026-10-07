-- JourneyTracker wrapped stats: gold, gear and your character. IDs match
-- wrapped-tracking-spec.md:
--   Economy, vendors, AH, mail (W-359..W-382; gold spent on mounts, W-375,
--   is in JourneyTrackerIconic.lua)
--   Gear and character stats (W-383..W-410)
-- Your character sheet (W-383..W-391) is added to each ding's snapshot as
-- `sheet`, read out of combat a few seconds after the ding.
-- Mail and auctions are counted, never kept: no sender, recipient, buyer or
-- text is stored.

local ADDON_NAME, ns = ...
local Track = ns.Track
local Safe, Call, Num, Str = ns.Safe, ns.Call, ns.Num, ns.Str
local On, Protect = ns.WrappedOn, ns.Protect

local PAIR_WINDOW = 3      -- seconds between a purchase or posting and its money change
local BROKE = 100          -- copper: under 1 silver (W-378)
local LOW_DURABILITY = 0.2 -- when the game can't say, the armor figure turns yellow here (W-399)
local ALERT_SLOTS = 11     -- the parts of the game's durability figure, head to ranged (W-399)
local REWARD_CAP = 100     -- quest rewards watched for a sale (W-405)
local CONTAINER, QUEST_ITEM = 1, 12 -- item classes
local BIND_ON_EQUIP = 2
local LOOT_ITEM, LOOT_MONEY = 1, 2  -- loot slot types
local RARITY = { [0] = "gray", [1] = "white", [2] = "green", [3] = "blue", [4] = "purple", [5] = "orange",
    [6] = "artifact" }
local STATS = { "str", "agi", "sta", "int", "spi" }
local RESISTANCES = { "holy", "fire", "nature", "frost", "shadow", "arcane" }
local NOT_WORN = { INVTYPE_BAG = true, INVTYPE_AMMO = true, INVTYPE_QUIVER = true, INVTYPE_NON_EQUIP_IGNORE = true }
local ENHANCERS = { "Armor Kit", "Sharpening Stone", "Weightstone" } -- W-402
local LOCKBOXES = { "Lockbox", "Junkbox" }                           -- W-380
local GATHER_CASTS = { ["Herb Gathering"] = true, ["Mining"] = true, ["Fishing"] = true }
local SLOT_NAMES = { "Head", "Neck", "Shoulder", "Shirt", "Chest", "Waist", "Legs", "Feet", "Wrist", "Hands",
    "Finger", "Finger", "Trinket", "Trinket", "Back", "Main Hand", "Off Hand", "Ranged", "Tabard" }

local AUCTION_STARTED = ns.PatternFrom(ERR_AUCTION_STARTED, "Auction created.", true)
local AUCTION_REMOVED = ns.PatternFrom(ERR_AUCTION_REMOVED, "Auction cancelled.", true)
local AUCTION_SOLD = ns.PatternFrom(ERR_AUCTION_SOLD_S, "A buyer has been found for your auction of %s.", true)
local AUCTION_EXPIRED = ns.PatternFrom(ERR_AUCTION_EXPIRED_S, "Your auction of %s has expired.", true)
local AUCTION_WON = ns.PatternFrom(ERR_AUCTION_WON_S, "You won an auction for %s", true)
-- Mail from the auction house, which isn't gold from another player (W-374).
local AUCTION_MAIL = {}
for _, s in ipairs({ { AUCTION_SOLD_MAIL_SUBJECT, "Auction successful: %s" },
                     { AUCTION_OUTBID_MAIL_SUBJECT, "Outbid on %s" },
                     { AUCTION_EXPIRED_MAIL_SUBJECT, "Auction expired: %s" },
                     { AUCTION_REMOVED_MAIL_SUBJECT, "Auction cancelled: %s" },
                     { AUCTION_WON_MAIL_SUBJECT, "Auction won: %s" } }) do
    AUCTION_MAIL[#AUCTION_MAIL + 1] = ns.PatternFrom(s[1], s[2], true)
end

local function HasAny(text, words)
    for _, w in ipairs(words) do
        if text:find(w, 1, true) then return true end
    end
    return false
end

local function Round(v, places)
    if not v then return nil end
    local m = 10 ^ (places or 0)
    return math.floor(v * m + 0.5) / m
end

-- What the game knows about an item (by ID or link).
local function ItemInfo(item)
    local name, _, quality, iLevel, _, _, _, _, equipLoc, _, sellPrice, classID, _, bindType =
        Call("C_Item.GetItemInfo", item)
    if not name then
        name, _, quality, iLevel, _, _, _, _, equipLoc, _, sellPrice, classID, _, bindType = Call("GetItemInfo", item)
    end
    return { name = Str(name), quality = Num(quality), iLevel = Num(iLevel), equipLoc = Str(equipLoc),
             sellPrice = Num(sellPrice), classID = Num(classID), bindType = Num(bindType) }
end

local function Wearable(info) return info.equipLoc ~= nil and not NOT_WORN[info.equipLoc] end

-- Item ID, enchant and random suffix from a link.
local function LinkParts(link)
    local fields = link and link:match("|Hitem:([^|]+)")
    if not fields then return nil end
    local parts, i = {}, 0
    for field in (fields .. ":"):gmatch("([^:]*):") do
        i = i + 1
        parts[i] = tonumber(field) or 0
        if i >= 7 then break end
    end
    if not parts[1] or parts[1] == 0 then return nil end
    return parts[1], parts[2] or 0, parts[7] or 0
end

-- Ever worn (the main tracker's #104 list, keyed by item ID and suffix)?
local function EverWorn(id)
    local worn = ns.GetDB().worn or {}
    if worn[tostring(id)] then return true end
    local prefix = id .. ":"
    for key in pairs(worn) do
        if type(key) == "string" and key:sub(1, #prefix) == prefix then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Vendors (W-359..W-364)
---------------------------------------------------------------------------

-- A purchase and its money change, paired up whichever comes first.
local spend, bought

local function TryPair()
    if not (spend and bought) or math.abs(spend.t - bought.t) > PAIR_WINDOW then return end
    local c = bought.c
    Track.max("W-362", spend.amount, { name = c.name, count = math.abs(c.delta) }) -- W-362 biggest purchase
    if c.classID == CONTAINER then Track.count("W-364", nil, spend.amount) end    -- W-364 gold on bags
    spend, bought = nil, nil
end

-- W-365 the first bag of each size in your bag slots. Bags you had when
-- tracking began are marked as before it.
local function CheckBags()
    local function Size(bag)
        return Num(Call("C_Container.GetContainerNumSlots", bag)) or Num(Call("GetContainerNumSlots", bag)) or 0
    end
    if Size(0) == 0 then return end -- bag data not loaded yet
    local baseline = Track.get("bagsSeen") == nil
    for bag = 1, NUM_BAG_SLOTS or 4 do
        local size = Size(bag)
        if size > 0 then
            local name = Str(Call(C_Container and C_Container.GetBagName and "C_Container.GetBagName" or "GetBagName", bag))
            if baseline then
                local seen = Track.get("W-365")
                if type(seen) ~= "table" then seen = {} end
                if seen[size] == nil then seen[size] = { name = name, before = true } end
                Track.set("W-365", seen)
            else
                Track.firstOf("W-365", size, { name = name })
            end
        end
    end
    Track.set("bagsSeen", true)
end

---------------------------------------------------------------------------
-- Gear, from your bags (W-359..W-363, W-402..W-405)
---------------------------------------------------------------------------

local function OnItemChange(c)
    local name, n, kind = c.name, math.abs(c.delta), c.kind
    if not name or not c.id then return end
    if kind == "bought" then
        Track.count("W-361", nil, n)                          -- W-361 items bought from vendors
        Track.count("W-361.byItem", name, n)
        bought = { c = c, t = GetTime() }
        TryPair()
    elseif kind == "destroyed" then
        Track.count("W-363", nil, n)                          -- W-363 items destroyed
        Track.count("W-363.byItem", name, n)
    elseif kind == "used" then
        if HasAny(name, ENHANCERS) then Track.count("W-402", name, n) end -- W-402 kits and stones
    end
    if kind == "sold" or kind == "posted" then
        local info = ItemInfo(c.id)
        if kind == "sold" and info.quality == 0 then
            Track.count("W-359", nil, n)                      -- W-359 junk sold
            if info.sellPrice then
                Track.count("W-359.gold", nil, info.sellPrice * n) -- and the gold it made
                Track.max("W-360", info.sellPrice, { name = name }) -- W-360 most valuable junk
            end
        end
        if info.bindType == BIND_ON_EQUIP and Wearable(info) and not EverWorn(c.id) then
            Track.count("W-403", kind == "sold" and "vendored" or "auctioned", n) -- W-403 BoE never worn
        end
        local rewards = Track.get("rewardIDs")
        if kind == "sold" and type(rewards) == "table" and rewards[c.id] then
            rewards[c.id] = nil
            if not EverWorn(c.id) then Track.count("W-405") end -- W-405 quest reward sold unworn
        end
    end
end

-- W-404 the quest reward you picked, by slot; W-405 gear rewards to watch.
local function OnQuestReward(choice)
    choice = Num(Safe(choice))
    local rewards = Track.get("rewardIDs")
    if type(rewards) ~= "table" then rewards = {} end
    local function Watch(link)
        local id = LinkParts(link)
        if id and Wearable(ItemInfo(link)) then rewards[id] = time() end
    end
    if choice and choice > 0 then
        local link = Str(Call("GetQuestItemLink", "choice", choice))
        if (Num(Call("GetNumQuestChoices")) or 0) > 1 and link then
            local info = ItemInfo(link)
            local slot = info.equipLoc and Wearable(info) and (Str(_G[info.equipLoc]) or info.equipLoc) or "not gear"
            Track.count("W-404", slot)
        end
        Watch(link)
    end
    for i = 1, Num(Call("GetNumQuestRewards")) or 0 do Watch(Str(Call("GetQuestItemLink", "reward", i))) end
    -- Keep the newest REWARD_CAP.
    local count, oldest, oldestAt = 0, nil, nil
    repeat
        count, oldest, oldestAt = 0, nil, nil
        for id, at in pairs(rewards) do
            count = count + 1
            if not oldestAt or at < oldestAt then oldest, oldestAt = id, at end
        end
        if count > REWARD_CAP then rewards[oldest] = nil end
    until count <= REWARD_CAP
    Track.set("rewardIDs", rewards)
end

---------------------------------------------------------------------------
-- The auction house (W-367..W-371)
---------------------------------------------------------------------------

-- AH spending paired with what it was for: a deposit (posting) or a buyout.
local ahSpend, ahEvent

local function PairAuction()
    if not (ahSpend and ahEvent) or math.abs(ahSpend.t - ahEvent.t) > PAIR_WINDOW then return end
    if ahEvent.kind == "posted" then
        Track.count("W-369", "deposits", ahSpend.amount)      -- W-369 deposits paid
    else
        Track.max("W-371", ahSpend.amount, { name = ahEvent.name }) -- W-371 biggest AH buy
    end
    ahSpend, ahEvent = nil, nil
end

-- An auction posted. Forever's AH sends AUCTION_HOUSE_AUCTION_CREATED (its
-- own UI prints "Auction created."); older clients send only the message,
-- which is left alone once the event has been seen.
local createdEvent = false
local function Posted()
    Track.count("W-367")                                      -- W-367 auctions posted
    ahEvent = { kind = "posted", t = GetTime() }
    PairAuction()
end

-- (Sold, expired and cancelled lines are counted by the main tracker, with
-- Forever's notifications, and come through ns.OnAuctionNotice: W-368.)
local function OnSystemMessage(msg)
    msg = Str(Safe(msg))
    if not msg then return end
    if msg:match(AUCTION_STARTED) then
        if not createdEvent then Posted() end
    elseif msg:match(AUCTION_REMOVED) or msg:match(AUCTION_SOLD) or msg:match(AUCTION_EXPIRED) then
        return
    else
        local item = msg:match(AUCTION_WON)
        if item then
            ahEvent = { kind = "won", name = item:match("%[(.-)%]") or item, t = GetTime() }
            PairAuction()
        end
    end
end

local function IsAuctionMail(subject)
    if not subject then return false end
    for _, p in ipairs(AUCTION_MAIL) do
        if subject:match(p) then return true end
    end
    return false
end

-- An auction invoice: biggest sale and buy (records, so reading one twice
-- changes nothing). The other player on it is never read.
local function ReadInvoice(index)
    local kind, item, _, bid = Call("GetInboxInvoiceInfo", index)
    kind, item, bid = Str(kind), Str(item), Num(bid)
    if bid and bid > 0 then
        if kind == "seller" then Track.max("W-370", bid, { name = item }) end -- W-370 best AH sale
        if kind == "buyer" then Track.max("W-371", bid, { name = item }) end
    end
    return kind
end

---------------------------------------------------------------------------
-- Mail (W-372..W-374, W-369)
---------------------------------------------------------------------------

local pendingMail, inboxCount

-- Money taken from a mail: an auction sale's refunded deposit and the
-- house's cut, or gold from another player.
local function OnTakeMoney(index)
    index = Num(Safe(index))
    if not index then return end
    local _, _, _, subject, money = Call("GetInboxHeaderInfo", index)
    money = Num(money)
    if not money or money <= 0 then return end
    local kind, _, _, _, _, deposit, cut = Call("GetInboxInvoiceInfo", index)
    ReadInvoice(index)
    if Str(kind) == "seller" then
        Track.count("W-369", "refunded", Num(deposit) or 0)   -- W-369 deposits back, the house's cut
        Track.count("W-369", "cuts", Num(cut) or 0)
    elseif not Str(kind) and not IsAuctionMail(Str(subject)) then
        Track.count("W-374", "received", money)               -- W-374 gold received by mail
    end
end

-- An item taken from a mail: COD paid (W-373), an auction bought (W-371).
local function OnTakeItem(index)
    index = Num(Safe(index))
    if not index then return end
    local _, _, _, _, _, cod = Call("GetInboxHeaderInfo", index)
    if (Num(cod) or 0) > 0 then Track.count("W-373", "received") end -- W-373 COD mail paid for
    ReadInvoice(index)
end

local function OnInboxUpdate()
    local n = Num(Call("GetInboxNumItems"))
    if not n then return end
    -- Mail cleared out of your inbox (taken, deleted or returned).
    if inboxCount and n < inboxCount then Track.count("W-372", "received", inboxCount - n) end -- W-372
    inboxCount = n
    for i = 1, n do ReadInvoice(i) end
end

local function OnMailSent()
    local m = pendingMail or {}
    pendingMail = nil
    Track.count("W-372", "sent")                              -- W-372 mail sent
    if (m.cod or 0) > 0 then Track.count("W-373", "sent") end -- W-373 COD mail sent
    if (m.money or 0) > 0 then Track.count("W-374", "sent", m.money) end -- W-374 gold sent
end

---------------------------------------------------------------------------
-- Money (W-362, W-366, W-369, W-371, W-376..W-379, W-382, W-400)
---------------------------------------------------------------------------

local bankBuyAt, wipeCost = -100, nil
local chestOpen, chestUntil, lastGather = false, 0, -100

local function OnMoney(delta, where, total)
    local now = GetTime()
    if delta < 0 then
        local amount = -delta
        local repairing = where == "repair" or (where == "merchant" and Call("InRepairMode") == true)
        if repairing then
            Track.max("W-400", amount)                        -- W-400 biggest repair bill
        elseif where == "merchant" then
            spend = { amount = amount, t = now }
            TryPair()
        elseif where == "auction" then
            ahSpend = { amount = amount, t = now }
            PairAuction()
        elseif now - bankBuyAt <= PAIR_WINDOW then
            Track.count("W-366")                              -- W-366 bank slots bought
            Track.count("W-366.gold", nil, amount)
            bankBuyAt = -100
        end
    elseif delta > 0 and where == "loot" and (chestOpen or now < chestUntil) then
        Track.count("W-382", nil, delta)                      -- W-382 gold from chests
    end
    if total then
        if total < BROKE and total - delta >= BROKE then Track.count("W-378") end -- W-378 went broke
        local level = ns.Level()
        if level > 0 then Track.max("W-379", math.floor(total / level), { money = total }) end -- W-379
    end
end

---------------------------------------------------------------------------
-- Loot: suffixes, lockboxes, chests (W-380..W-382, W-392)
---------------------------------------------------------------------------

local function OnLoot(link, count)
    local name = link and link:match("%[(.-)%]")
    if not name then return end
    count = count or 1
    local _, _, suffix = LinkParts(link)
    local of = suffix and suffix ~= 0 and name:match(" (of .+)$")
    if of then Track.count("W-392", of, count) end            -- W-392 suffixes looted (top: W-393)
    if HasAny(name, LOCKBOXES) then Track.count("W-380", name, count) end -- W-380 lockboxes
end

-- A treasure chest: loot from an object (not a herb, a vein or fishing)
-- with money or anything that isn't a quest item. Opening the same one
-- again (loot left in it) counts once; its gold still counts (W-382).
local chestsSeen = {}       -- [object GUID] = true, this session
local function OnLootOpened()
    chestOpen = false
    if Call("IsFishingLoot") == true or GetTime() - lastGather < 5 then return end
    local object, worth = nil, false
    for slot = 1, Num(Call("GetNumLootItems")) or 0 do
        local guid = Str(Call("GetLootSourceInfo", slot))
        if guid and guid:find("^GameObject") then object = guid end
        local kind = Num(Call("GetLootSlotType", slot))
        if kind == LOOT_MONEY then
            worth = true
        elseif kind == LOOT_ITEM then
            local link = Str(Call("GetLootSlotLink", slot))
            if link and ItemInfo(link).classID ~= QUEST_ITEM then worth = true end
        end
    end
    if object and worth then
        chestOpen = true
        if not chestsSeen[object] then
            chestsSeen[object] = true
            Track.count("W-381")                              -- W-381 treasure chests
        end
    end
end

---------------------------------------------------------------------------
-- Equipment (W-394, W-395, W-397..W-401)
---------------------------------------------------------------------------

local equipped     -- [slot] = { id, key, enchant, link, guid } or false, from the first look this session
local durability, alert = {}, nil -- durability[slot] = { cur, key } as last read

-- The item's own GUID, which tells two copies of one item apart (W-401).
local function SlotGUID(slot)
    local ok, loc = pcall(function() return ItemLocation:CreateFromEquipmentSlot(slot) end)
    return ok and loc and Str(Call("C_Item.GetItemGUID", loc)) or nil
end

local function SlotItem(slot)
    local link = Str(Call("GetInventoryItemLink", "player", slot))
    local id, enchant, suffix = LinkParts(link)
    if not id then return false end
    return { id = id, enchant = enchant, key = id .. ":" .. suffix, link = link, guid = SlotGUID(slot) }
end

local function ScanEquipped()
    local now, any = {}, false
    for slot = 1, 19 do
        now[slot] = SlotItem(slot)
        if now[slot] then any = true end
    end
    return any and now or nil
end

local function IsTwoHander(item) return ItemInfo(item.link).equipLoc == "INVTYPE_2HWEAPON" end

local function Baseline()
    if equipped then return end
    equipped = ScanEquipped()
    -- Already wielding a two-hander when tracking began.
    local main = equipped and equipped[16]
    if main and Track.get("W-397") == nil and IsTwoHander(main) then
        Track.first("W-397", { name = ItemInfo(main.link).name, before = true })
    end
end

local function OnEquipmentChanged(slot)
    slot = Num(Safe(slot))
    if not equipped then
        Baseline()
        return
    end
    if not slot or slot < 1 or slot > 19 then return end
    local old, new = equipped[slot], SlotItem(slot)
    equipped[slot] = new
    if not new then return end
    -- Another copy of the same item swapped in is an item equipped, not an enchant.
    if not old or old.key ~= new.key or (old.guid and new.guid and old.guid ~= new.guid) then
        Track.count("W-394")                                  -- W-394 items equipped
        Track.count("W-395", ns.Level())                      -- W-395 gear swaps per level
        if slot == 16 and IsTwoHander(new) then
            Track.first("W-397", { name = ItemInfo(new.link).name }) -- W-397 first two-hander
        end
    elseif new.enchant ~= old.enchant and new.enchant ~= 0 then
        Track.count("W-401")                                  -- W-401 enchants applied
        Track.count("W-401.bySlot", SLOT_NAMES[slot])
    end
end

local function CheckDurability()
    -- W-399 the game's own alert for each part of its durability figure
    -- (head, shoulders, chest ... ranged), which aren't inventory slots
    local worst, known = 0, false
    for i = 1, ALERT_SLOTS do
        local status = Num(Call("GetInventoryAlertStatus", i))
        if status then
            known = true
            if status > worst then worst = status end
        end
    end
    for slot = 1, 18 do
        local cur, max = Call("GetInventoryItemDurability", slot)
        cur, max = Num(cur), Num(max)
        if cur and max and max > 0 then
            -- W-398 an item broke: the same item, not one put on already broken
            local item = SlotItem(slot)
            local key, was = item and item.key, durability[slot]
            if cur == 0 and was and was.cur > 0 and was.key == key then Track.count("W-398") end
            durability[slot] = { cur = cur, key = key }
            if not known then
                local status = (cur == 0 and 2) or (cur / max <= LOW_DURABILITY and 1) or 0
                if status > worst then worst = status end
            end
        else
            durability[slot] = nil
        end
    end
    if alert and worst > alert then
        Track.count("W-399", worst >= 2 and "red" or "yellow") -- W-399 gear went yellow or red
    end
    alert = worst
end

---------------------------------------------------------------------------
-- Talents and spells (W-406..W-409)
---------------------------------------------------------------------------

local talentRanks, talentLoadout -- [key] = rank as last read, and the loadout it was read from

-- The talents now: the three trees in the game's order, each { name,
-- points }, and each talent with points in it, { tree, talent, rank }, by a
-- key a later read keeps; and which loadout they're from. Classic clients
-- list them by tab; Forever's talents are a trait tree (C_Traits) with the
-- three classic trees as its groups, read as its own talent window reads
-- them. Nil when they can't be read yet.
local function ClassicTalents()
    local tabs = Num(Call("GetNumTalentTabs"))
    if not tabs then return nil end
    local trees, talents = {}, {}
    for tab = 1, tabs do
        local a, b = Call("GetTalentTabInfo", tab)
        local tree = Str(a) or Str(b) or ("Tree " .. tab)
        trees[tab] = { name = tree,
            points = Num(select(3, Call("GetTalentTabInfo", tab))) or Num(select(5, Call("GetTalentTabInfo", tab))) or 0 }
        for i = 1, Num(Call("GetNumTalents", tab)) or 0 do
            local name, _, _, _, rank = Call("GetTalentInfo", tab, i)
            name, rank = Str(name), Num(rank)
            if name and rank then talents[tab .. ":" .. i] = { tree = tree, talent = name, rank = rank } end
        end
    end
    if not next(talents) then return nil end
    return trees, talents, "classic"
end

local function TraitTalents()
    local configID = Num(Call("C_ClassTalents.GetActiveConfigID"))
    local config = configID and Call("C_Traits.GetConfigInfo", configID)
    local treeID = type(config) == "table" and type(config.treeIDs) == "table" and Num(config.treeIDs[1])
    if not treeID then return nil end
    local trees, byGroup, groupIDs = {}, {}, {}
    local groups = Call("C_Traits.GetGroupDisplayInfoByTreeID", treeID)
    for i, g in ipairs(type(groups) == "table" and groups or {}) do
        local id = type(g) == "table" and Num(g.groupID)
        if id then
            byGroup[id] = { name = Str(g.displayName) or ("Tree " .. i), points = 0 }
            trees[#trees + 1] = byGroup[id]
            groupIDs[#groupIDs + 1] = id
        end
    end
    local spent = #groupIDs > 0 and Call("C_Traits.GetGroupCurrencyInfo", configID, groupIDs)
    for _, c in ipairs(type(spent) == "table" and spent or {}) do
        local tree = type(c) == "table" and byGroup[Num(c.traitNodeGroupID) or 0]
        local info = tree and type(c.currencyInfos) == "table" and c.currencyInfos[1]
        if type(info) == "table" then tree.points = Num(info.spent) or 0 end
    end
    local talents = {}
    local nodes = Call("C_Traits.GetTreeNodes", treeID)
    for _, nodeID in ipairs(type(nodes) == "table" and nodes or {}) do
        local node = Call("C_Traits.GetNodeInfo", configID, nodeID)
        local rank = type(node) == "table" and Num(node.ranksPurchased)
        if rank and rank > 0 then
            local entryID = type(node.activeEntry) == "table" and Num(node.activeEntry.entryID)
            local entry = entryID and Call("C_Traits.GetEntryInfo", configID, entryID)
            local def = type(entry) == "table" and Num(entry.definitionID)
            def = def and Call("C_Traits.GetDefinitionInfo", def)
            local name = type(def) == "table" and (Str(def.overrideName) or ns.SpellName(Num(def.spellID) or 0))
            local tree = type(node.groupIDs) == "table" and byGroup[Num(node.groupIDs[1]) or 0]
            talents["node:" .. nodeID] = { tree = tree and tree.name or "?", talent = name or ("Talent " .. nodeID),
                                           rank = rank }
        end
    end
    return trees, talents, configID
end

local function ReadTalents()
    local trees, talents, loadout = ClassicTalents()
    if trees then return trees, talents, loadout end
    return TraitTalents()
end

-- The trees and their points, for the other files (JourneyTrackerDungeons.lua's role).
function ns.TalentTrees() return (ReadTalents()) end

local function CheckTalents()
    local trees, talents, loadout = ReadTalents()
    if not trees then return end
    local ranks = {}
    for key, t in pairs(talents) do ranks[key] = t.rank end
    -- (Switching to your other spec isn't new points: it's just read again.)
    if talentRanks and loadout == talentLoadout then
        for key, rank in pairs(ranks) do
            for r = (talentRanks[key] or 0) + 1, rank do
                Track.list("W-406", { tree = talents[key].tree, talent = talents[key].talent, rank = r,
                                      level = ns.Level() }, 150) -- W-406 talent points in order
                Track.firstEver("W-476", { tree = talents[key].tree, name = talents[key].talent }) -- W-476 the first
            end
        end
    elseif not talentRanks and Track.get("W-476") == nil then
        -- Points already spent when tracking began: the first was before.
        for _, rank in pairs(ranks) do
            if rank > 0 then
                Track.first("W-476", { before = true })
                break
            end
        end
    end
    talentRanks, talentLoadout = ranks, loadout
    if ns.Level() >= 60 then
        local split = {}
        for _, tree in ipairs(trees) do split[tree.name] = tree.points end
        Track.set("W-408", split)                             -- W-408 talent split at 60
    end
end

-- W-409 where each spell (or rank) was learned.
local learned = {}
local lastItemUse, lastQuestDone = -100, -100
local function OnLearned(spellID)
    spellID = Num(Safe(spellID))
    if not spellID or learned[spellID] then return end
    learned[spellID] = true
    local now = GetTime()
    local source = (ns.ctx.trainer and "trainer") or (now - lastItemUse < 5 and "item")
        or (now - lastQuestDone < 5 and "quest") or "other"
    Track.count("W-409", source)
end

---------------------------------------------------------------------------
-- Your character at each ding (W-383..W-391)
---------------------------------------------------------------------------

local function ReadSheet()
    local s = {}
    for i, key in ipairs(STATS) do
        local _, value = Call("UnitStat", "player", i)
        s[key] = Num(value)                                   -- W-383 primary stats
    end
    local _, armor = Call("UnitArmor", "player")
    s.armor = Num(armor)                                      -- W-384 armor
    s.health = Num(Call("UnitHealthMax", "player"))           -- W-385 max health and mana
    local mana = Num(Call("UnitPowerMax", "player", 0))
    if mana and mana > 0 then s.mana = mana end
    -- W-386 attack power, never below 0 (as the character sheet shows it;
    -- a debuff can take more than a low level's base)
    local base, plus, minus = Call("UnitAttackPower", "player")
    if Num(base) then s.ap = math.max(0, Num(base) + (Num(plus) or 0) + (Num(minus) or 0)) end
    base, plus, minus = Call("UnitRangedAttackPower", "player")
    if Num(base) and Num(base) > 0 then s.rap = math.max(0, Num(base) + (Num(plus) or 0) + (Num(minus) or 0)) end
    local sp, spellCrit = 0, 0
    for school = 2, 7 do
        sp = math.max(sp, Num(Call("GetSpellBonusDamage", school)) or 0)
        spellCrit = math.max(spellCrit, Num(Call("GetSpellCritChance", school)) or 0)
    end
    if sp > 0 then s.sp = sp end                              -- and spell power
    local heal = Num(Call("GetSpellBonusHealing"))
    if heal and heal > 0 then s.heal = heal end
    s.crit = Round(Num(Call("GetCritChance")), 2)             -- W-387 crit chance
    if spellCrit > 0 then s.spellCrit = Round(spellCrit, 2) end
    s.rangedCrit = Round(Num(Call("GetRangedCritChance")), 2)
    local res = {}
    for i, name in ipairs(RESISTANCES) do
        local _, total = Call("UnitResistance", "player", i)
        if (Num(total) or 0) > 0 then res[name] = Num(total) end -- W-388 resistances
    end
    if next(res) then s.res = res end
    local weapon = Str(Call("GetInventoryItemLink", "player", 16))
    if weapon then
        local stats = Call("C_Item.GetItemStats", weapon)
        if type(stats) ~= "table" then stats = Call("GetItemStats", weapon) end
        local dps = type(stats) == "table" and Num(Safe(stats.ITEM_MOD_DAMAGE_PER_SECOND_SHORT))
        if dps then s.dps = Round(dps, 1) end                 -- W-389 main hand DPS
    end
    -- W-390 average item level, W-391 rarity, of what you wear (not the
    -- shirt or tabard)
    local total, count, rarity = 0, 0, {}
    for slot = 1, 18 do
        local link = slot ~= 4 and Str(Call("GetInventoryItemLink", "player", slot))
        if link then
            local info = ItemInfo(link)
            local q = Num(Call("GetInventoryItemQuality", "player", slot)) or info.quality
            if q then rarity[RARITY[q] or tostring(q)] = (rarity[RARITY[q] or tostring(q)] or 0) + 1 end
            if info.iLevel then total, count = total + info.iLevel, count + 1 end
        end
    end
    if count > 0 then s.ilvl = Round(total / count, 1) end
    if next(rarity) then s.rarity = rarity end
    return next(s) and s or nil
end

-- Stats settle a moment after a ding, and are read out of combat.
local pendingSheet
local function TakeSheet()
    if not pendingSheet or ns.InCombat() then return end
    pendingSheet.sheet = ReadSheet()
    pendingSheet = nil
end
-- For the milestone saved at a level-up (JourneyTrackerExport.lua), which
-- waits for the ding's sheet: read it now if it's still waiting.
ns.TakeSheet = Protect(TakeSheet)

---------------------------------------------------------------------------
-- Window pages
---------------------------------------------------------------------------

local function DrawGold(B)
    ns.ShowItems(B, {
        { heading = "Vendors" },
        { "W-359", "Junk items sold" }, { "W-359.gold", "Gold from junk", "money" },
        { "W-360", "Most valuable junk sold", "money" },
        { "W-361", "Items bought from vendors" }, { "W-362", "Biggest vendor purchase", "money" },
        { "W-364", "Gold spent on bags", "money" }, { "W-365", "First bag of each size", "firsts" },
        { "W-363", "Items destroyed" },
        { heading = "Auction House" },
        { "W-367", "Auctions posted" }, { "W-368", "Sold, expired and cancelled", "map" },
        { "W-369", "Deposits, refunds and the house's cut", "moneymap" },
        { "W-370", "Best sale", "money" }, { "W-371", "Biggest buy", "money" },
        { heading = "Mail" },
        { "W-372", "Mail sent, and cleared from your inbox", "map" }, { "W-373", "COD mail sent and paid for", "map" },
        { "W-374", "Gold sent and received", "moneymap" },
        { heading = "Gold Moments" },
        { "W-377", "Quest gold by level", "moneymap" }, { "W-376", "Gold spent on respecs", "money" },
        { "W-378", "Times you went broke (under 1 silver)" }, { "W-379", "Richest for your level (gold per level)", "money" },
        { "W-366", "Bank slots bought" }, { "W-366.gold", "Gold spent on bank slots", "money" },
        { "W-380", "Lockboxes looted", "map" }, { "W-381", "Treasure chests looted" },
        { "W-382", "Gold from chests", "money" },
    })
end

local function LatestSheet()
    local best
    for level, d in pairs(ns.GetDB().dings or {}) do
        if type(level) == "number" and type(d) == "table" and d.sheet and (not best or level > best) then best = level end
    end
    return best, best and ns.GetDB().dings[best].sheet
end

local function Pairs(t)
    local parts = {}
    for k, v in pairs(t or {}) do parts[#parts + 1] = k .. " " .. v end
    table.sort(parts)
    return #parts > 0 and table.concat(parts, ", ") or "-"
end

local function DrawGear(B)
    local U = ns.UI
    local level, s = LatestSheet()
    B:Heading(level and ("Your Character at Level " .. level) or "Your Character")
    if not s then
        B:Note("Your stats are saved a few seconds after each ding.")
    else
        local function N(v) return v and U.Num(v) or "-" end
        B:Row("Strength, Agility, Stamina", N(s.str) .. " / " .. N(s.agi) .. " / " .. N(s.sta))
        B:Row("Intellect, Spirit", N(s.int) .. " / " .. N(s.spi))
        B:Row("Armor", N(s.armor))
        B:Row("Health, mana", N(s.health) .. " / " .. N(s.mana))
        B:Row("Attack power", N(s.ap))
        if s.sp or s.heal then B:Row("Spell power, healing", N(s.sp) .. " / " .. N(s.heal)) end
        B:Row("Crit chance", (s.crit and (s.crit .. "%") or "-") .. (s.spellCrit and (", spells " .. s.spellCrit .. "%") or ""))
        B:Row("Resistances", Pairs(s.res))
        B:Row("Main hand DPS", s.dps and tostring(s.dps) or "-")
        B:Row("Average item level", s.ilvl and tostring(s.ilvl) or "-")
        B:Row("Gear by rarity", Pairs(s.rarity))
    end
    local first2H = Track.get("W-397")
    ns.ShowItems(B, {
        { heading = "Gear" },
        { "W-392", "Suffix items looted (the top one is your most common)", "map" },
        { "W-394", "Items equipped" }, { "W-395", "Gear swaps by level", "map" },
    })
    B:Row("First two-hander", type(first2H) == "table"
        and ((first2H.name or "?") .. (first2H.before and " (before tracking)" or (", level " .. tostring(first2H.level))))
        or "-")
    ns.ShowItems(B, {
        { "W-398", "Items broken" }, { "W-399", "Times your gear went yellow or red", "map" },
        { "W-400", "Biggest repair bill", "money" }, { "W-401", "Enchants applied" },
        { "W-402", "Armor kits and stones used", "map" }, { "W-403", "BoE items sold without wearing them", "map" },
        { "W-404", "Quest reward picked, by slot", "map" }, { "W-405", "Quest rewards sold without wearing them" },
        { heading = "Talents and Spells" },
        { "W-407", "Respecs" }, { "W-408", "Talent split at 60", "map" },
        { "W-409", "Spells learned, by where", "map" },
    })
    local talents = Track.get("W-406")
    if type(talents) == "table" and #talents > 0 then
        B:Row("Latest talent points", "")
        for i = math.max(1, #talents - 9), #talents do
            local t = talents[i]
            B:Note(("Level %s: %s %s (%s)"):format(tostring(t.level), tostring(t.talent), tostring(t.rank), tostring(t.tree)))
        end
    end
end

ns.WrappedPage("Wrapped Stats", "Gold & Trade", DrawGold)
ns.WrappedPage("Wrapped Stats", "Gear & Talents", DrawGear)

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------

ns.OnItemChange(Protect(function(c)
    if c.kind == "used" then lastItemUse = GetTime() end
    OnItemChange(c)
end))
ns.OnMoneyChange(Protect(OnMoney))
ns.OnLootItem(Protect(OnLoot))
ns.OnCast(Protect(function(name) if GATHER_CASTS[name] then lastGather = GetTime() end end))
ns.OnDing(Protect(function(snapshot)
    pendingSheet = snapshot
    if C_Timer and C_Timer.After then C_Timer.After(3, Protect(TakeSheet)) end
end))

On("PLAYER_ENTERING_WORLD", function()
    if C_Timer and C_Timer.After then
        C_Timer.After(3, Protect(function()
            Baseline()
            CheckDurability()
            CheckTalents()
            CheckBags()
        end))
    end
end)
On("BAG_UPDATE_DELAYED", CheckBags)
On("PLAYER_REGEN_ENABLED", TakeSheet)
On("PLAYER_EQUIPMENT_CHANGED", OnEquipmentChanged)
On("UPDATE_INVENTORY_DURABILITY", CheckDurability)
On("CHARACTER_POINTS_CHANGED", CheckTalents)
On("PLAYER_TALENT_UPDATE", CheckTalents)
On("TRAIT_CONFIG_UPDATED", CheckTalents)                      -- Forever's talents (C_Traits)
On("CONFIRM_TALENT_WIPE", function(cost) wipeCost = Num(Safe(cost)) end)
On("LEARNED_SPELL_IN_TAB", OnLearned)
On("LEARNED_SPELL_IN_SKILL_LINE", OnLearned)
On("QUEST_TURNED_IN", function(questID, xp, money)
    lastQuestDone = GetTime()
    money = Num(Safe(money))
    if money and money > 0 then Track.count("W-377", ns.Level(), money) end -- W-377 quest gold by level
end)
On("CHAT_MSG_SYSTEM", OnSystemMessage)
-- W-368 auctions sold, expired and cancelled: from the main tracker, which
-- counts each once whether it came as a chat line or a notification (#83).
ns.OnAuctionNotice(Protect(function(kind, n) Track.count("W-368", kind, n) end))
On("AUCTION_HOUSE_AUCTION_CREATED", function()
    createdEvent = true
    Posted()
end)
-- W-371 a commodity bought on Forever's AH (its UI prints the "won" line itself)
On("AUCTION_HOUSE_SHOW_COMMODITY_WON_NOTIFICATION", function(name)
    ahEvent = { kind = "won", name = Str(Safe(name)), t = GetTime() }
    PairAuction()
end)
On("LOOT_OPENED", OnLootOpened)
On("LOOT_CLOSED", function()
    if chestOpen then chestUntil = GetTime() + 2 end
    chestOpen = false
end)
On("MAIL_SHOW", function() inboxCount = nil end)
On("MAIL_CLOSED", function() inboxCount = nil end)
On("MAIL_INBOX_UPDATE", OnInboxUpdate)
On("MAIL_SEND_SUCCESS", OnMailSent)
ns.OnLoad(function()
    ns.Hook("SendMail", Protect(function()
        pendingMail = { money = Num(Call("GetSendMailMoney")) or 0, cod = Num(Call("GetSendMailCOD")) or 0 }
    end))
    ns.Hook("TakeInboxMoney", Protect(OnTakeMoney))
    ns.Hook("TakeInboxItem", Protect(OnTakeItem))
    ns.Hook("AutoLootMailItem", Protect(function(index)
        OnTakeMoney(index)
        OnTakeItem(index)
    end))
    -- W-366 Forever buys bank tabs; PurchaseSlot is the older clients' bank slot
    local function BankBuy() bankBuyAt = GetTime() end
    ns.Hook("C_Bank.PurchaseBankTab", Protect(BankBuy))
    ns.Hook("PurchaseSlot", Protect(BankBuy))
    ns.Hook("ConfirmTalentWipe", Protect(function()
        Track.count("W-407")                                  -- W-407 talent respecs
        if wipeCost then Track.count("W-376", nil, wipeCost) end -- W-376 gold on respecs
        wipeCost = nil
    end))
    ns.Hook("GetQuestReward", Protect(OnQuestReward))
end)
