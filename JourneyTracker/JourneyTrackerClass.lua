-- JourneyTracker class tracking. IDs such as WAR-04 match
-- class-tracking-spec.md; ALL-xx are the cross-class stats.
--
-- Four shared helpers do the counting, and each class below is a list of
-- items wired onto them:
--   CountCast  - every successful cast of yours, by spell name (all ranks
--                together) and by rank, plus who it landed on for some spells
--   StateTimer - seconds spent in a state: stance, form, aura, seal, aspect,
--                stealth, wanding, pet out
--   ItemDiff   - bag contents compared after every change, so items created,
--                used, bought, traded or destroyed can be counted
--   PetTracker - which pet or demon is out, for how long, and when it dies
--
-- Only your own class is switched on; its data lives in db.class[CLASS] and
-- the cross-class stats in db.class.ALL. Spells and items are matched by
-- name rather than by Classic database IDs, so anything Forever doesn't have
-- simply never counts (/jt class lists which tracked spells the game knows).
-- As in the main file, every game value goes through Safe()/Call() first.

local ADDON_NAME, ns = ...
local Safe, Call, Num, Str, Inc, IsSecret = ns.Safe, ns.Call, ns.Num, ns.Str, ns.Inc, ns.IsSecret

local PREFIX = "|cff33ff99Journey|r"
local HEARTHSTONE = "Hearthstone"
local SOUL_SHARD = "Soul Shard"
local PROJECTILE = 6 -- item class of arrows and bullets
local AMMO_TYPES = { [2] = "Arrows", [3] = "Bullets" }
local CONSUMABLE, FOOD_AND_DRINK = 0, 5 -- item class and subclass of food and drink

local db          -- JourneyTrackerDB
local classToken  -- "DRUID", "WARRIOR", ...
local def         -- this class's entry in CLASSES, once logged in
local data        -- db.class[classToken]
local all         -- db.class.ALL
local me          -- your character's name, only to tell self-casts apart

---------------------------------------------------------------------------
-- What each class tracks
--
-- Item fields: casts (spells counted), targets (also self vs others),
-- interrupts (also likely interrupts), combo (also combo points), prefix
-- (every spell starting with it), state / swaps (a StateTimer group's time
-- or transitions), learned (level each spell was learned, from #95), items
-- (bag items: how they came and went), obtained (level an item first showed
-- up), power (power type spent), custom (a special counter, see below).
-- Class fields: forms (StateTimer group fed by stance/form changes),
-- formNone (state name with no form), stealth (state name while stealthed),
-- castStates (buff-like states a cast starts), pets ("named" or "family"),
-- store (extra saved tables).
---------------------------------------------------------------------------

local function PetStore()
    return { time = {}, deaths = {}, resummons = {}, tamed = {}, abandoned = {}, fed = {} }
end

local HUNTER_TRACKING = { "Track Beasts", "Track Humanoids", "Track Undead", "Track Hidden",
    "Track Elementals", "Track Demons", "Track Giants", "Track Dragonkin" }

local CLASSES = {
    WARRIOR = {
        forms = "stance",
        store = { weaponSwaps = 0 },
        items = {
            { id = "WAR-01", label = "Time in Each Stance", state = "stance" },
            { id = "WAR-02", label = "Stance Swaps", swaps = "stance" },
            { id = "WAR-03", label = "Stances Learned", learned = { "Defensive Stance", "Berserker Stance" } },
            { id = "WAR-04", label = "Charges and Intercepts", casts = { "Charge", "Intercept" } },
            { id = "WAR-05", label = "Overpower", casts = { "Overpower" } },
            { id = "WAR-06", label = "Executes", casts = { "Execute" } },
            { id = "WAR-07", label = "Shouts", casts = { "Battle Shout", "Demoralizing Shout",
                "Intimidating Shout", "Challenging Shout" } },
            { id = "WAR-08", label = "Sunder Armor and Rend", casts = { "Sunder Armor", "Rend" } },
            { id = "WAR-09", label = "Chasing Runners", casts = { "Hamstring", "Piercing Howl" } },
            { id = "WAR-10", label = "\"Oh No\" Buttons", casts = { "Shield Wall", "Last Stand",
                "Retaliation", "Recklessness", "Berserker Rage" } },
            { id = "WAR-11", label = "Interrupts", casts = { "Pummel", "Shield Bash" }, interrupts = true },
            { id = "WAR-12", label = "Multi-Mob Abilities", casts = { "Thunder Clap", "Cleave", "Whirlwind" } },
            { id = "WAR-13", label = "Weapon Swaps", custom = "weaponSwaps" },
            { id = "WAR-14", label = "Rage Spent", power = "RAGE" },
            { id = "WAR-15", label = "Class Quest Weapon", obtained = { "Whirlwind Axe", "Whirlwind Sword",
                "Whirlwind Heart" } },
        },
    },
    PALADIN = {
        forms = "aura",
        castStates = {
            { group = "seal", duration = 30, endOn = { "Judgement" }, verify = true, spells = {
                "Seal of Righteousness", "Seal of the Crusader", "Seal of Command", "Seal of Wisdom",
                "Seal of Light", "Seal of Justice" } },
            { group = "aura", verify = true, spells = { "Devotion Aura", "Retribution Aura",
                "Concentration Aura", "Shadow Resistance Aura", "Frost Resistance Aura",
                "Fire Resistance Aura", "Sanctity Aura" } },
        },
        store = { judgements = {}, bubbleHearths = 0 },
        items = {
            { id = "PAL-01", label = "Time With Each Seal", state = "seal" },
            { id = "PAL-02", label = "Judgements, by Seal Judged", custom = "judgements" },
            { id = "PAL-03", label = "Time With Each Aura", state = "aura" },
            { id = "PAL-04", label = "Blessings", targets = true, casts = { "Blessing of Might",
                "Blessing of Wisdom", "Blessing of Kings", "Blessing of Salvation", "Blessing of Light",
                "Blessing of Sanctuary", "Blessing of Protection", "Blessing of Freedom",
                "Blessing of Sacrifice" } },
            { id = "PAL-05", label = "Lay on Hands", casts = { "Lay on Hands" } },
            { id = "PAL-06", label = "Divine Shield and Divine Protection", casts = { "Divine Shield",
                "Divine Protection" } },
            { id = "PAL-07", label = "Bubble Hearths", custom = "bubbleHearths" },
            { id = "PAL-08", label = "Hammer of Justice", casts = { "Hammer of Justice" } },
            { id = "PAL-09", label = "Heals", casts = { "Holy Light", "Flash of Light" }, targets = true },
            { id = "PAL-10", label = "Redemption", casts = { "Redemption" } },
            { id = "PAL-11", label = "Exorcism and Turn Undead", casts = { "Exorcism", "Turn Undead" } },
            { id = "PAL-12", label = "Consecration", casts = { "Consecration" } },
            { id = "PAL-13", label = "Cleanse and Purify", casts = { "Cleanse", "Purify" } },
            { id = "PAL-14", label = "Class Mount", learned = { "Summon Warhorse", "Summon Charger" },
                casts = { "Summon Warhorse", "Summon Charger" } },
            { id = "PAL-15", label = "Divine Intervention", casts = { "Divine Intervention" },
                items = { "Symbol of Divinity" } },
        },
    },
    HUNTER = {
        pets = "named",
        castStates = {
            { group = "aspect", verify = true, spells = { "Aspect of the Hawk", "Aspect of the Monkey",
                "Aspect of the Cheetah", "Aspect of the Pack", "Aspect of the Beast", "Aspect of the Wild" } },
            -- HUN-16: profession and racial tracking replace a hunter's.
            { group = "tracking", spells = HUNTER_TRACKING, endOn = { "Find Herbs", "Find Minerals",
                "Find Treasure" } },
        },
        store = { ammo = { used = {}, byType = {}, bought = {}, gold = 0, outOfAmmo = 0 },
                  pets = PetStore(), feignDrops = 0 },
        items = {
            { id = "HUN-01", label = "Ammo Used", custom = "ammoUsed" },
            { id = "HUN-02", label = "Ammo Bought", custom = "ammoBought" },
            { id = "HUN-03", label = "Ran Out of Ammo", custom = "outOfAmmo" },
            { id = "HUN-04", label = "Pets Tamed", casts = { "Tame Beast" }, custom = "tamed" },
            { id = "HUN-05", label = "Time With Each Pet", custom = "petTime" },
            { id = "HUN-06", label = "Pet Deaths and Revives", casts = { "Revive Pet" }, custom = "petDeaths" },
            { id = "HUN-07", label = "Pets Abandoned", custom = "abandoned" },
            { id = "HUN-08", label = "Feeding", casts = { "Feed Pet" }, custom = "fed" },
            { id = "HUN-09", label = "Mend Pet", casts = { "Mend Pet" } },
            { id = "HUN-10", label = "Time in Each Aspect", state = "aspect" },
            { id = "HUN-11", label = "Feign Death", casts = { "Feign Death" }, custom = "feignDrops" },
            { id = "HUN-12", label = "Traps", casts = { "Freezing Trap", "Immolation Trap", "Frost Trap",
                "Explosive Trap" } },
            { id = "HUN-13", label = "Shots", casts = { "Arcane Shot", "Aimed Shot", "Multi-Shot",
                "Concussive Shot", "Scatter Shot", "Serpent Sting" } },
            { id = "HUN-14", label = "Hunter's Mark", casts = { "Hunter's Mark" } },
            { id = "HUN-15", label = "Beast Abilities Learned", learned = { "Bite", "Claw", "Cower", "Dash",
                "Dive", "Growl", "Charge", "Furious Howl", "Lightning Breath", "Prowl", "Scorpid Poison",
                "Screech", "Shell Shield", "Thunderstomp", "Natural Armor", "Great Stamina",
                "Arcane Resistance", "Fire Resistance", "Frost Resistance", "Nature Resistance",
                "Shadow Resistance" } },
            { id = "HUN-16", label = "Tracking", state = "tracking", casts = HUNTER_TRACKING },
            { id = "HUN-17", label = "Eyes of the Beast and Scare Beast", casts = { "Eyes of the Beast",
                "Scare Beast" } },
        },
    },
    ROGUE = {
        stealth = "Stealth",
        store = { poisons = { applied = {}, appliedItems = {}, crafted = {} },
                  pickpocket = { items = {}, gold = 0 } },
        items = {
            { id = "ROG-01", label = "Time in Stealth", state = "stealth" },
            { id = "ROG-02", label = "Openers", casts = { "Cheap Shot", "Ambush", "Garrote", "Sap" } },
            { id = "ROG-03", label = "Pick Pocket", casts = { "Pick Pocket" }, custom = "pickpocket" },
            { id = "ROG-04", label = "Pick Lock", casts = { "Pick Lock" }, custom = "lockpicking" },
            { id = "ROG-05", label = "Poisons Applied", custom = "poisonsApplied" },
            { id = "ROG-06", label = "Poisons Crafted", custom = "poisonsCrafted" },
            { id = "ROG-07", label = "Finishers", combo = true, casts = { "Eviscerate", "Slice and Dice",
                "Kidney Shot", "Rupture", "Expose Armor" } },
            { id = "ROG-08", label = "Combo Points per Finisher", custom = "combo" },
            { id = "ROG-09", label = "Escapes", casts = { "Vanish", "Sprint", "Evasion" },
                items = { "Flash Powder" } },
            { id = "ROG-10", label = "Kick", casts = { "Kick" }, interrupts = true },
            { id = "ROG-11", label = "Gouge and Blind", casts = { "Gouge", "Blind" }, items = { "Blinding Powder" } },
            { id = "ROG-12", label = "Distract and Disarm Trap", casts = { "Distract", "Disarm Trap" } },
            { id = "ROG-13", label = "Combo Builders", casts = { "Sinister Strike", "Backstab", "Hemorrhage" },
                custom = "mainBuilder" },
            { id = "ROG-14", label = "Poisons Class Quest", learned = { "Poisons" } },
            { id = "ROG-15", label = "Rogue Consumables", items = { "Thistle Tea" } },
        },
    },
    PRIEST = {
        forms = "shadowform",
        castStates = {
            { group = "innerfire", duration = 600, verify = true, spells = { "Inner Fire" } },
        },
        items = {
            { id = "PRI-01", label = "Power Word: Shield", casts = { "Power Word: Shield" }, targets = true },
            { id = "PRI-02", label = "Heals", casts = { "Renew", "Lesser Heal", "Heal", "Flash Heal", "Greater Heal" } },
            { id = "PRI-03", label = "Resurrection", casts = { "Resurrection" } },
            { id = "PRI-04", label = "Buffs on Others", casts = { "Power Word: Fortitude", "Divine Spirit" },
                targets = true },
            { id = "PRI-05", label = "Time in Shadowform", state = "shadowform" },
            { id = "PRI-06", label = "Shadow Damage", casts = { "Shadow Word: Pain", "Mind Blast", "Mind Flay" } },
            { id = "PRI-07", label = "Psychic Scream and Fade", casts = { "Psychic Scream", "Fade" } },
            { id = "PRI-08", label = "Mind Control and Mind Vision", casts = { "Mind Control", "Mind Vision" } },
            { id = "PRI-09", label = "Levitate", casts = { "Levitate" } },
            { id = "PRI-10", label = "Inner Fire Uptime", state = "innerfire", casts = { "Inner Fire" } },
            { id = "PRI-11", label = "Racial Priest Spells", casts = { "Desperate Prayer", "Fear Ward",
                "Starshards", "Touch of Weakness", "Devouring Plague", "Hex of Weakness", "Shadowguard",
                "Elune's Grace", "Feedback" } },
            { id = "PRI-12", label = "Wand", custom = "wand" },
            { id = "PRI-13", label = "Dispels", casts = { "Dispel Magic", "Cure Disease", "Abolish Disease" } },
            { id = "PRI-14", label = "Holy Nova", casts = { "Holy Nova" } },
            { id = "PRI-15", label = "Mana Spent", power = "MANA" },
        },
    },
    SHAMAN = {
        forms = "ghostwolf",
        items = {
            { id = "SHA-01", label = "Totems Dropped", custom = "totems" },
            { id = "SHA-02", label = "Favorite Totem per Element", custom = "totemFavorites" },
            { id = "SHA-03", label = "Elemental Totems Obtained", obtained = { "Earth Totem", "Fire Totem",
                "Water Totem", "Air Totem" } },
            { id = "SHA-04", label = "Time in Ghost Wolf", state = "ghostwolf" },
            { id = "SHA-05", label = "Reincarnation", casts = { "Reincarnation" }, items = { "Ankh" } },
            { id = "SHA-06", label = "Weapon Imbues", casts = { "Rockbiter Weapon", "Flametongue Weapon",
                "Frostbrand Weapon", "Windfury Weapon" } },
            { id = "SHA-07", label = "Shocks", casts = { "Earth Shock", "Flame Shock", "Frost Shock" } },
            { id = "SHA-08", label = "Lightning", casts = { "Lightning Bolt", "Chain Lightning" } },
            { id = "SHA-09", label = "Heals", casts = { "Healing Wave", "Lesser Healing Wave", "Chain Heal" } },
            { id = "SHA-10", label = "Lightning Shield", casts = { "Lightning Shield" } },
            { id = "SHA-11", label = "Astral Recall", casts = { "Astral Recall" } },
            { id = "SHA-12", label = "Ancestral Spirit", casts = { "Ancestral Spirit" } },
            { id = "SHA-13", label = "Purge and Cures", casts = { "Purge", "Cure Poison", "Cure Disease" } },
            { id = "SHA-14", label = "Water Walking, Water Breathing, Far Sight", casts = { "Water Walking",
                "Water Breathing", "Far Sight" } },
            { id = "SHA-15", label = "Shaman Reagents", items = { "Ankh", "Fish Oil", "Shiny Fish Scales" } },
        },
    },
    MAGE = {
        store = { conjured = { water = {}, food = {}, gems = {}, gemsUsed = {}, given = {}, ids = {} } },
        items = {
            { id = "MAG-01", label = "Water Conjured", casts = { "Conjure Water" }, custom = "conjuredWater" },
            { id = "MAG-02", label = "Food Conjured", casts = { "Conjure Food" }, custom = "conjuredFood" },
            { id = "MAG-03", label = "Conjured Items Traded Away", custom = "conjuredGiven" },
            { id = "MAG-04", label = "Teleports", prefix = "Teleport: " },
            { id = "MAG-05", label = "Portals", prefix = "Portal: " },
            { id = "MAG-06", label = "Runes", items = { "Rune of Teleportation", "Rune of Portals" } },
            { id = "MAG-07", label = "Polymorph", casts = { "Polymorph", "Polymorph: Pig", "Polymorph: Turtle" } },
            { id = "MAG-08", label = "Frost Nova, Blink, Ice Block, Ice Barrier", casts = { "Frost Nova",
                "Blink", "Ice Block", "Ice Barrier" } },
            { id = "MAG-09", label = "Counterspell", casts = { "Counterspell" }, interrupts = true },
            { id = "MAG-10", label = "Arcane Intellect", casts = { "Arcane Intellect", "Arcane Brilliance" },
                targets = true },
            { id = "MAG-11", label = "Evocation", casts = { "Evocation" } },
            { id = "MAG-12", label = "Mana Gems", custom = "manaGems" },
            { id = "MAG-13", label = "Main Nukes", casts = { "Fireball", "Frostbolt", "Arcane Missiles",
                "Scorch", "Fire Blast" } },
            { id = "MAG-14", label = "AoE Farming", casts = { "Arcane Explosion", "Blizzard" } },
            { id = "MAG-15", label = "Slow Fall and Remove Lesser Curse", casts = { "Slow Fall",
                "Remove Lesser Curse" } },
        },
    },
    WARLOCK = {
        pets = "family",
        store = { shards = { gained = {}, used = {}, peak = 0 }, stones = {}, healthstonesUsed = {},
                  pets = PetStore(), soulstoneRez = 0 },
        items = {
            { id = "WLK-01", label = "Soul Shards Gained", custom = "shardsGained" },
            { id = "WLK-02", label = "Soul Shards Used", custom = "shardsUsed" },
            { id = "WLK-03", label = "Most Soul Shards Held", custom = "shardsPeak" },
            { id = "WLK-04", label = "Healthstones Created", custom = "stones", stones = { "Healthstone" } },
            { id = "WLK-05", label = "Healthstones Used", custom = "healthstonesUsed" },
            { id = "WLK-06", label = "Soulstones Created", custom = "stones", stones = { "Soulstone" } },
            { id = "WLK-07", label = "Saved by Your Soulstone", custom = "soulstoneRez" },
            { id = "WLK-08", label = "Spellstones and Firestones Created", custom = "stones",
                stones = { "Spellstone", "Firestone" } },
            { id = "WLK-09", label = "Ritual of Summoning", casts = { "Ritual of Summoning" } },
            { id = "WLK-10", label = "Demons Summoned", casts = { "Summon Imp", "Summon Voidwalker",
                "Summon Succubus", "Summon Felhunter", "Inferno", "Ritual of Doom" } },
            { id = "WLK-11", label = "Time With Each Demon", custom = "petTime" },
            { id = "WLK-12", label = "Demon Deaths and Resummons", custom = "petDeaths" },
            { id = "WLK-13", label = "Demons Obtained", learned = { "Summon Imp", "Summon Voidwalker",
                "Summon Succubus", "Summon Felhunter", "Inferno", "Ritual of Doom" } },
            { id = "WLK-14", label = "Life Tap", casts = { "Life Tap" } },
            { id = "WLK-15", label = "Fear, Howl of Terror, Death Coil", casts = { "Fear", "Howl of Terror",
                "Death Coil" } },
            { id = "WLK-16", label = "DoTs", casts = { "Corruption", "Curse of Agony", "Immolate", "Siphon Life" } },
            { id = "WLK-17", label = "Enslave Demon and Eye of Kilrogg", casts = { "Enslave Demon",
                "Eye of Kilrogg" } },
            { id = "WLK-18", label = "Utility on Others", targets = true, casts = { "Unending Breath",
                "Detect Invisibility", "Detect Lesser Invisibility", "Detect Greater Invisibility" } },
            { id = "WLK-19", label = "Class Mount", learned = { "Summon Felsteed", "Summon Dreadsteed" },
                casts = { "Summon Felsteed", "Summon Dreadsteed" } },
        },
    },
    DRUID = {
        forms = "form", formNone = "Caster Form",
        stealth = "Prowl",
        items = {
            { id = "DRU-01", label = "Time in Each Form", state = "form" },
            { id = "DRU-02", label = "Form Shifts", swaps = "form" },
            { id = "DRU-03", label = "Forms Learned", learned = { "Bear Form", "Aquatic Form", "Cat Form",
                "Travel Form", "Dire Bear Form", "Moonkin Form" } },
            { id = "DRU-04", label = "Time in Prowl", state = "stealth" },
            { id = "DRU-05", label = "Heals", casts = { "Healing Touch", "Regrowth", "Rejuvenation" }, targets = true },
            { id = "DRU-06", label = "Rebirth and Innervate", casts = { "Rebirth", "Innervate" } },
            { id = "DRU-07", label = "Buffs on Others", casts = { "Mark of the Wild", "Gift of the Wild", "Thorns" },
                targets = true },
            { id = "DRU-08", label = "Caster Damage", casts = { "Wrath", "Moonfire", "Starfire", "Insect Swarm" } },
            { id = "DRU-09", label = "Cat Abilities", casts = { "Claw", "Shred", "Rake", "Rip", "Ferocious Bite",
                "Ravage", "Pounce" } },
            { id = "DRU-10", label = "Bear Abilities", casts = { "Maul", "Swipe", "Growl", "Demoralizing Roar",
                "Bash", "Feral Charge" } },
            { id = "DRU-11", label = "Entangling Roots and Hibernate", casts = { "Entangling Roots", "Hibernate" } },
            { id = "DRU-12", label = "Teleport: Moonglade", casts = { "Teleport: Moonglade" } },
            { id = "DRU-13", label = "Faerie Fire", casts = { "Faerie Fire", "Faerie Fire (Feral)" } },
            { id = "DRU-14", label = "Remove Curse and Abolish Poison", casts = { "Remove Curse",
                "Abolish Poison", "Cure Poison" } },
            { id = "DRU-15", label = "Reagents Used", items = { "Wild Thornroot", "Maple Seed",
                "Stranglethorn Seed", "Ashwood Seed", "Hornbeam Seed", "Ironwood Seed" } },
        },
    },
}

-- ALL-09 racial abilities (Classic names; Forever's Skyborne racials join
-- once their names are known, and every cast is counted anyway).
local RACIALS = { "Will of the Forsaken", "Cannibalize", "Stoneform", "Find Treasure", "Escape Artist",
    "Perception", "Shadowmeld", "War Stomp", "Berserking", "Blood Fury" }

-- WLK-12: which demon each summoning spell brings.
local SUMMON_FAMILY = { ["Summon Imp"] = "Imp", ["Summon Voidwalker"] = "Voidwalker",
    ["Summon Succubus"] = "Succubus", ["Summon Felhunter"] = "Felhunter", ["Inferno"] = "Infernal",
    ["Ritual of Doom"] = "Doomguard" }

local STONES = { "Healthstone", "Soulstone", "Spellstone", "Firestone" }
local POISON_TYPES = { "Instant", "Deadly", "Crippling", "Mind-numbing", "Wound" }

-- SHA-01 totem elements.
local TOTEM_ELEMENTS = {
    ["Stoneskin Totem"] = "Earth", ["Earthbind Totem"] = "Earth", ["Stoneclaw Totem"] = "Earth",
    ["Strength of Earth Totem"] = "Earth", ["Tremor Totem"] = "Earth",
    ["Searing Totem"] = "Fire", ["Fire Nova Totem"] = "Fire", ["Magma Totem"] = "Fire",
    ["Flametongue Totem"] = "Fire", ["Frost Resistance Totem"] = "Fire",
    ["Healing Stream Totem"] = "Water", ["Mana Spring Totem"] = "Water", ["Mana Tide Totem"] = "Water",
    ["Poison Cleansing Totem"] = "Water", ["Disease Cleansing Totem"] = "Water",
    ["Fire Resistance Totem"] = "Water",
    ["Grounding Totem"] = "Air", ["Windfury Totem"] = "Air", ["Grace of Air Totem"] = "Air",
    ["Nature Resistance Totem"] = "Air", ["Windwall Totem"] = "Air", ["Sentry Totem"] = "Air",
    ["Tranquil Air Totem"] = "Air",
}
local ELEMENTS = { "Earth", "Fire", "Water", "Air", "Other" }

-- ALL-13: heals whose amount is estimated from the tooltip.
local HEAL_SPELLS = { ["Holy Light"] = true, ["Flash of Light"] = true, ["Lay on Hands"] = true,
    ["Lesser Heal"] = true, ["Heal"] = true, ["Flash Heal"] = true, ["Greater Heal"] = true,
    ["Renew"] = true, ["Prayer of Healing"] = true, ["Desperate Prayer"] = true, ["Holy Nova"] = true,
    ["Healing Wave"] = true, ["Lesser Healing Wave"] = true, ["Chain Heal"] = true,
    ["Healing Touch"] = true, ["Regrowth"] = true, ["Rejuvenation"] = true }

local CLASS_DEFAULTS = { casts = {}, ranks = {}, targets = {}, interrupts = {}, combo = {},
    powerSpent = {}, time = {}, swaps = {}, items = {}, obtained = {}, healing = {} }

local ALL_DEFAULTS = {
    bandages = {}, potions = { healing = {}, mana = {}, other = {} }, healthstones = {}, conjured = {},
    food = {}, buffs = { bySpell = {}, byClass = {} }, rezzedBy = {}, summons = {}, time = {},
    trainerVisits = {}, trainerNPCs = {}, classQuests = {}, classQuestIDs = {},
}

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------

local function SpellName(id)
    return Str(Call("C_Spell.GetSpellName", id)) or Str(Call("GetSpellInfo", id))
end

-- True if the game can find a spell by this name (known now, or at least
-- present in the client).
local function KnownSpell(name)
    local info = Call("C_Spell.GetSpellInfo", name)
    if type(info) == "table" then return true end
    return Str(Call("GetSpellInfo", name)) ~= nil
end

local function Sum(t)
    local n = 0
    for _, v in pairs(t or {}) do
        if type(v) == "number" then n = n + v end
    end
    return n
end

-- true / false if a buff by that name is on you (with `mine`, one you cast
-- yourself, not a groupmate's aura or aspect), nil if it can't be read (the
-- aura API errors in combat on Forever).
local function HasAura(name, mine)
    local fn = C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName
    if not fn then return nil end
    local ok, aura = pcall(fn, "player", name, mine and "HELPFUL|PLAYER" or "HELPFUL")
    if not ok or IsSecret(aura) then return nil end
    return aura ~= nil
end

local function ClassName(token)
    token = token or classToken
    return (LOCALIZED_CLASS_NAMES_MALE and token and LOCALIZED_CLASS_NAMES_MALE[token]) or token or "Unknown"
end

-- A character's name without the "-Realm" the game can add to it.
local function ShortName(name)
    return type(name) == "string" and name:match("^[^%-]+") or nil
end

-- Class of a group member with this name (counts only; names aren't kept).
local function ClassOfGroupMember(name)
    local n = Num(Call("GetNumGroupMembers")) or 0
    local raid = Call("IsInRaid") == true
    for i = 1, raid and n or (n - 1) do
        local unit = (raid and "raid" or "party") .. i
        if Str(Call("UnitName", unit)) == name then
            local _, token = Call("UnitClass", unit)
            return Str(token)
        end
    end
end

local function QuestTitle(questID)
    return Str(Call("C_QuestLog.GetTitleForQuestID", questID))
end

-- ALL-12: an NPC's ID from its GUID (the rest of a GUID changes when the
-- server restarts).
local function NpcID(guid)
    return type(guid) == "string" and tonumber(guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)")) or nil
end

---------------------------------------------------------------------------
-- StateTimer: seconds spent in a state, flushed every few seconds and on
-- logout so little is lost if the game closes unexpectedly.
---------------------------------------------------------------------------

local Timer = {}
Timer.__index = Timer
local allTimers = {}

local function MakeTimer(store)
    local t = setmetatable({ store = store }, Timer)
    table.insert(allTimers, t)
    return t
end

-- Add the time spent in the current state so far.
function Timer:Flush(now)
    now = now or GetTime()
    if self.since and now < self.since then now = self.since end
    if self.state and self.since then
        Inc(self.store, self.state, now - self.since)
    end
    self.since = now
end

-- Switch state (nil = none). Returns the previous state and whether it changed.
function Timer:Set(state, at)
    if state == self.state then return self.state, false end
    self:Flush(at)
    local previous = self.state
    self.state = state
    return previous, true
end

local stateTimers = {} -- [group] = Timer for this class's states

local function TimeStore(owner, group)
    owner.time[group] = owner.time[group] or {}
    return owner.time[group]
end

local function StateTimer(group)
    local t = stateTimers[group]
    if not t then
        t = MakeTimer(TimeStore(data, group))
        stateTimers[group] = t
    end
    return t
end

-- WAR-02, DRU-02: transitions between states.
local function RecordSwap(group, from, to)
    if not from or not to then return end
    local s = data.swaps[group] or { total = 0, pairs = {} }
    data.swaps[group] = s
    s.total = s.total + 1
    Inc(s.pairs, from .. " > " .. to)
end

local function FlushAll()
    local now = GetTime()
    for _, t in ipairs(allTimers) do t:Flush(now) end
end

---------------------------------------------------------------------------
-- Session state
---------------------------------------------------------------------------

local recent = { t = 0 }           -- your last successful cast: name, t
local castListeners, itemListeners = {}, {} -- other files (ns.OnCast, ns.OnItemChange)
local targetSpells, interruptSpells, comboSpells = {}, {}, {}
local watchItems, obtainedItems = {}, {}
local castState, castEnds, stateUntil = {}, {}, {}
local pendingTarget, pendingCombo, pendingCount = {}, {}, 0
local hearthStart, lastBubble, feignAt = nil, nil, 0
local tamingUntil, dismissUntil, pocketUntil = 0, 0, 0
local lastDrainSoul, lastShadowmeld = 0, 0
local lastKick, lastKickSpell, lastTargetStop = 0, nil, 0
local lastMoney, lastDrop
local tradeOpen, tradeUntil, bankOpen, bankUntil, destroyUntil = false, 0, false, 0, 0
local pendingRezClass, trainerVisit
local wandTimer, petTimer
local pet = { lastHealth = 0 }
local lastDemonDeath = {}
local weaponLinks, swapSettle, lastSwap = {}, 0, 0

local function BuildLookups()
    for _, item in ipairs(def.items) do
        for _, spell in ipairs(item.casts or {}) do
            if item.targets then targetSpells[spell] = true end
            if item.interrupts then interruptSpells[spell] = true end
            if item.combo then comboSpells[spell] = true end
        end
        for _, name in ipairs(item.items or {}) do watchItems[name] = true end
        for _, name in ipairs(item.obtained or {}) do obtainedItems[name] = true end
    end
    for _, cfg in ipairs(def.castStates or {}) do
        for _, spell in ipairs(cfg.spells) do castState[spell] = cfg end
        for _, spell in ipairs(cfg.endOn or {}) do
            castEnds[spell] = castEnds[spell] or {}
            table.insert(castEnds[spell], cfg)
        end
    end
end

---------------------------------------------------------------------------
-- State drivers: forms and stances, stealth, buff-like cast states, wand
---------------------------------------------------------------------------

-- Name of the current shapeshift form / stance / paladin aura.
local function FormName()
    local index = Num(Call("GetShapeshiftForm"))
    if not index or index == 0 then return def.formNone end
    local _, b, _, d = Call("GetShapeshiftFormInfo", index)
    if Num(d) then return SpellName(d) end -- icon, active, castable, spellID
    return Str(b)                          -- older clients: icon, name, ...
end

-- WAR-01/02, PAL-03, PRI-05, SHA-04, DRU-01/02
local function OnFormChanged()
    local name = FormName()
    -- PAL-03: Classic paladin auras aren't stance-bar forms. With no forms at
    -- all, the aura casts drive the state, so "no form" doesn't end it.
    if not name and (Num(Call("GetNumShapeshiftForms")) or 0) == 0 then
        for _, cfg in ipairs(def.castStates or {}) do
            if cfg.group == def.forms then return end
        end
    end
    local previous, changed = StateTimer(def.forms):Set(name)
    if changed then RecordSwap(def.forms, previous, name) end
end

-- ROG-01, DRU-04 (Shadowmeld counts as its own state).
local function OnStealthChanged()
    local name
    if Call("IsStealthed") then
        name = (GetTime() - lastShadowmeld < 2) and "Shadowmeld" or def.stealth
    end
    StateTimer("stealth"):Set(name)
end

-- Seals, auras, aspects, Inner Fire, tracking: a cast starts the state;
-- some end on a timer or another cast (Judgement uses up the seal).
local function ApplyCastState(name)
    local cfg = castState[name]
    if cfg then
        StateTimer(cfg.group):Set(name)
        stateUntil[cfg.group] = cfg.duration and (GetTime() + cfg.duration) or nil
    end
    for _, ended in ipairs(castEnds[name] or {}) do
        StateTimer(ended.group):Set(nil)
        stateUntil[ended.group] = nil
    end
end

-- Buffs drop when you die (tracking doesn't).
local function ClearCastStates()
    if not def then return end
    for _, cfg in ipairs(def.castStates or {}) do
        if cfg.verify then
            StateTimer(cfg.group):Set(nil)
            stateUntil[cfg.group] = nil
        end
    end
end

-- Buff-like states that are up with nothing timing them: at login, and
-- after anything missed (a login in combat, say). Out of combat only.
local function FindCastStates()
    for _, cfg in ipairs(def.castStates or {}) do
        local t = stateTimers[cfg.group]
        if cfg.verify and not (t and t.state) then
            for _, spell in ipairs(cfg.spells) do
                if HasAura(spell, true) then
                    StateTimer(cfg.group):Set(spell)
                    break
                end
            end
        end
    end
end

-- PRI-12, ALL-10: time spent wanding (auto-repeat "Shoot"). Forever has
-- C_Spell.IsAutoRepeatSpell; older clients the global (1 or nil).
local function OnAutoRepeat()
    if not wandTimer then return end
    local wanding
    if C_Spell and C_Spell.IsAutoRepeatSpell then
        wanding = Call("C_Spell.IsAutoRepeatSpell", "Shoot") == true
    else
        wanding = Call("IsAutoRepeatSpell", "Shoot") and true or false
    end
    wandTimer:Set(wanding and "Wanding" or nil)
end

---------------------------------------------------------------------------
-- PetTracker (HUN-04..08, WLK-10..12)
---------------------------------------------------------------------------

local function PetKey()
    if not Call("UnitExists", "pet") then return nil end
    local family = Str(Call("UnitCreatureFamily", "pet"))
    local name = Str(Call("UnitName", "pet"))
    if def.pets == "family" then return family or name end
    if name and family then return name .. " (" .. family .. ")" end
    return name or family
end

local function PetDied()
    if not pet.key or pet.dead then return end
    pet.dead = true
    Inc(data.pets.deaths, pet.key)                            -- HUN-06, WLK-12 pet deaths
    if def.pets == "family" then lastDemonDeath[pet.key] = GetTime() end
    petTimer:Set(nil)
end

-- initial = true at login: note a dead pet without counting a death.
local function SyncPet(initial)
    local key = PetKey()
    if not key then
        -- Gone. If it was hit a moment ago and we didn't dismiss it, it died
        -- (it also goes, alive, when you die or take a flight).
        if pet.key and not pet.dead and not initial and GetTime() > dismissUntil
            and GetTime() - pet.lastHealth < 1.5 and Call("UnitIsDeadOrGhost", "player") ~= true
            and Call("UnitOnTaxi", "player") ~= true and GetTime() > (ns.ctx.flightUntil or 0) then
            PetDied()
        end
        pet.key, pet.dead = nil, false
        petTimer:Set(nil)
        return
    end
    if key ~= pet.key then
        pet.key, pet.dead = key, false
        if GetTime() < tamingUntil then                      -- HUN-04 a freshly tamed pet
            tamingUntil = 0
            table.insert(data.pets.tamed, {
                name = Str(Call("UnitName", "pet")), family = Str(Call("UnitCreatureFamily", "pet")),
                petLevel = Num(Call("UnitLevel", "pet")), level = ns.Level(), zone = ns.Zone(), t = time(),
            })
        end
    end
    if Call("UnitIsDead", "pet") == true then
        if initial then pet.dead = true else PetDied() end
        petTimer:Set(nil)
    else
        pet.dead = false
        petTimer:Set(key)                                     -- HUN-05, WLK-11 time with each pet
    end
end

local function OnPetChanged() SyncPet(false) end

local function OnPetHealth()
    pet.lastHealth = GetTime()
    if not pet.key then return end
    local dead = Call("UnitIsDead", "pet") == true
    if dead then
        PetDied()
    elseif pet.dead then
        pet.dead = false
        petTimer:Set(pet.key)
    end
end

local function OnPetAbandoned()                               -- HUN-07
    if not (data and data.pets and pet.key) then return end
    table.insert(data.pets.abandoned, { pet = pet.key, petLevel = Num(Call("UnitLevel", "pet")),
        level = ns.Level(), t = time() })
end

---------------------------------------------------------------------------
-- ItemDiff: bag contents compared on every BAG_UPDATE_DELAYED
---------------------------------------------------------------------------

local bags = { names = {} } -- .counts = { [itemID] = count } at the last scan
local itemClasses = {}

local function BagList()
    local list = {}
    for b = 0, NUM_BAG_SLOTS or 4 do list[#list + 1] = b end
    local reagent = Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag
    if reagent then list[#list + 1] = reagent end
    return list
end

local function SlotItem(bag, slot)
    local id, link, count = ns.BagItem(bag, slot)
    return id, count, link
end

local function ScanBags()
    local counts, names = {}, {}
    for _, bag in ipairs(BagList()) do
        local slots = Num(Call("C_Container.GetContainerNumSlots", bag))
            or Num(Call("GetContainerNumSlots", bag)) or 0
        for slot = 1, slots do
            local id, count, link = SlotItem(bag, slot)
            if id and count then
                counts[id] = (counts[id] or 0) + count
                if link and not names[id] then names[id] = link:match("%[(.-)%]") end
            end
        end
    end
    return counts, names
end

local function ItemClass(id)
    local cached = itemClasses[id]
    if not cached then
        local _, _, _, _, _, classID, subClassID = Call("C_Item.GetItemInfoInstant", id)
        if not classID then
            _, _, _, _, _, classID, subClassID = Call("GetItemInfoInstant", id)
        end
        cached = { Num(classID), Num(subClassID) }
        itemClasses[id] = cached
    end
    return cached[1], cached[2]
end

local function AmmoCount(counts)
    local total = 0
    for id, n in pairs(counts) do
        if ItemClass(id) == PROJECTILE then total = total + n end
    end
    return total
end

-- What was going on when the bags changed.
local function BagContext()
    local ctx, now = ns.ctx, GetTime()
    if tradeOpen or now < tradeUntil then return "trade" end
    if bankOpen or now < bankUntil then return "bank" end
    if ctx.mail then return "mail" end
    if ctx.auction then return "auction" end
    if ctx.merchant then return "merchant" end
    if now < destroyUntil then return "destroy" end
    if ctx.loot or now < ctx.lootUntil then return "loot" end
end

local GAIN_KINDS = { merchant = "bought", trade = "received", loot = "looted", mail = "from mail",
    bank = "from bank", auction = "gained", destroy = "gained" }
local LOSS_KINDS = { merchant = "sold", trade = "traded", mail = "mailed", bank = "banked",
    auction = "posted", destroy = "destroyed", loot = "used" }

local function KindOf(delta, context, cast)
    if delta > 0 then
        if context then return GAIN_KINDS[context] end
        return cast and "created" or "gained" -- right after a cast: conjured, crafted, created
    end
    return context and LOSS_KINDS[context] or "used"
end

local function PoisonType(name)
    for _, t in ipairs(POISON_TYPES) do
        if name:find(t, 1, true) then return t end
    end
    return "Other"
end

-- Class-specific reactions to an item change.
local CLASS_ITEMS = {
    HUNTER = function(c, name, n, kind)
        if c.classID == PROJECTILE then
            if kind == "used" then
                Inc(data.ammo.used, name, n)                  -- HUN-01 ammo used, by item
                Inc(data.ammo.byType, AMMO_TYPES[c.subClassID] or "Other", n)
            elseif kind == "bought" then
                Inc(data.ammo.bought, name, n)                -- HUN-02 ammo bought
            end
        elseif kind == "used" and c.cast == "Feed Pet" then
            Inc(data.pets.fed, name, n)                       -- HUN-08 food fed
        end
    end,
    WARLOCK = function(c, name, n, kind)
        if name == SOUL_SHARD then
            if c.delta > 0 then
                -- WLK-01: shards come from Drain Soul kills
                Inc(data.shards.gained, GetTime() - lastDrainSoul < 20 and "Drain Soul" or kind, n)
            else
                Inc(data.shards.used, kind == "used" and (c.cast or "Other") or kind, n) -- WLK-02
            end
        elseif kind == "created" and c.cast then
            for _, stone in ipairs(STONES) do
                if c.cast:find(stone, 1, true) and name:find(stone, 1, true) then
                    data.stones[stone] = data.stones[stone] or {}
                    Inc(data.stones[stone], name, n)          -- WLK-04, 06, 08 stones created
                end
            end
        elseif kind == "used" and name:find("Healthstone", 1, true) then
            Inc(data.healthstonesUsed, name, n)               -- WLK-05 healthstones used
        end
    end,
    MAGE = function(c, name, n, kind)
        local C = data.conjured
        if kind == "created" and c.cast then
            local what = (c.cast == "Conjure Water" and "water") or (c.cast == "Conjure Food" and "food")
                or (c.cast:find("^Conjure Mana") and "gems")
            if what then
                Inc(C[what], name, n)                         -- MAG-01, 02, 12 conjured by rank
                C.ids[c.id] = what
            end
        elseif kind == "traded" and (C.ids[c.id] or name:find("^Conjured")) then
            Inc(C.given, name, n)                             -- MAG-03 given away in trades
        elseif kind == "used" and C.ids[c.id] == "gems" then
            Inc(C.gemsUsed, name, n)                          -- MAG-12 gems used
        end
    end,
    ROGUE = function(c, name, n, kind)
        if name:find("Poison", 1, true) then
            if kind == "used" then
                Inc(data.poisons.applied, PoisonType(name), n) -- ROG-05 applied, by type
                Inc(data.poisons.appliedItems, name, n)
            elseif kind == "created" then
                Inc(data.poisons.crafted, name, n)            -- ROG-06 crafted
            end
        end
        if kind == "looted" and GetTime() < pocketUntil then
            Inc(data.pickpocket.items, name, n)               -- ROG-03 items from pockets
        end
    end,
}

-- ALL-01..05: consumables you used, whatever your class.
local function CrossUsed(c, name, n)
    if name:find("Bandage", 1, true) or c.cast == "First Aid" then
        Inc(all.bandages, name, n)                            -- ALL-01 bandages
    elseif name:find("Potion", 1, true) then
        local kind = (name:find("Healing", 1, true) and "healing")
            or (name:find("Mana", 1, true) and "mana") or "other"
        Inc(all.potions[kind], name, n)                       -- ALL-02 potions by type
    end
    if name:find("Healthstone", 1, true) and classToken ~= "WARLOCK" then
        Inc(all.healthstones, name, n)                        -- ALL-03 a warlock's healthstones
    end
    if name:find("^Conjured") and classToken ~= "MAGE" then
        Inc(all.conjured, name, n)                            -- ALL-04 a mage's food and water
    end
    -- Subclass 5 is Food & Drink only for consumables (for weapons it's
    -- two-handed maces, for trade goods cloth); what your pet eats isn't yours.
    if c.cast == "Food" or c.cast == "Drink" or c.cast == "Food & Drink"
        or (c.classID == CONSUMABLE and c.subClassID == FOOD_AND_DRINK and c.cast ~= "Feed Pet") then
        Inc(all.food, name, n)                                -- ALL-05 food and drink
    end
end

-- Other files hear about every change. Each listener runs protected, like
-- the main file's: one that errors can't stop the rest, and the first
-- errors are kept for /journey status.
local function TellItemListeners(c)
    for _, fn in ipairs(itemListeners) do
        local ok, err = pcall(fn, c)
        local errors = not ok and ns.HookErrors and ns.HookErrors()
        if errors and #errors < 10 then table.insert(errors, "item change: " .. tostring(err)) end
    end
end

local function OnItemChange(c)
    local name, n, kind = c.name, math.abs(c.delta), c.kind
    if not name then return end
    if data then
        if watchItems[name] then
            data.items[name] = data.items[name] or {}
            Inc(data.items[name], kind, n)                    -- reagents, runes, powders: in and out
        end
        if c.delta > 0 and obtainedItems[name] and not data.obtained[name] then
            data.obtained[name] = { level = ns.Level(), t = time() } -- WAR-15, SHA-03
        end
        local handler = CLASS_ITEMS[classToken]
        if handler then handler(c, name, n, kind) end
    end
    if kind == "used" then CrossUsed(c, name, n) end
    TellItemListeners(c)
end

-- First scan: what you already had counts as "before tracking".
local function SetBaseline(counts, names)
    bags.counts = counts
    for id, name in pairs(names) do bags.names[id] = name end
    bags.ammo = AmmoCount(counts)
    if not data then return end
    local function Mark(name)
        if name and obtainedItems[name] and not data.obtained[name] then
            data.obtained[name] = { before = true }
        end
    end
    for _, name in pairs(names) do Mark(name) end
    for slot = 16, 18 do
        local link = Str(Call("GetInventoryItemLink", "player", slot))
        Mark(link and link:match("%[(.-)%]"))
    end
end

local function AfterDiff(counts, boughtAmmo, boughtOther, context)
    if not data then return end
    if classToken == "HUNTER" then
        local A = data.ammo
        local total = AmmoCount(counts)
        if (bags.ammo or 0) > 0 and total == 0 and not context then
            A.outOfAmmo = A.outOfAmmo + 1                     -- HUN-03 ran out of ammo
        end
        bags.ammo = total
        if boughtAmmo and not boughtOther and lastDrop and GetTime() - lastDrop.t < 2 then
            A.gold = A.gold + lastDrop.amount                 -- HUN-02 gold spent on ammo
            lastDrop = nil
        end
    elseif classToken == "WARLOCK" then
        local shards = 0
        for id, n in pairs(counts) do
            if bags.names[id] == SOUL_SHARD then shards = shards + n end
        end
        if shards > data.shards.peak then data.shards.peak = shards end -- WLK-03 most shards held
    end
end

local function OnBagsChanged()
    local counts, names = ScanBags()
    -- No baseline yet (or bags weren't loaded when we first looked).
    if not bags.counts or next(bags.counts) == nil or not all then
        SetBaseline(counts, names)
        return
    end
    for id, name in pairs(names) do bags.names[id] = name end
    local context = BagContext()
    local cast = (GetTime() - recent.t <= 3) and recent.name or nil
    local boughtAmmo, boughtOther = false, false
    local function Change(id, delta)
        local classID, subClassID = ItemClass(id)
        local c = { id = id, name = bags.names[id], delta = delta, context = context, cast = cast,
                    classID = classID, subClassID = subClassID, kind = KindOf(delta, context, cast) }
        if c.kind == "bought" then
            if classID == PROJECTILE then boughtAmmo = true else boughtOther = true end
        end
        OnItemChange(c)
    end
    -- The new contents are the baseline before anything reacts, so an error
    -- in a reaction can't book the same changes again on the next scan.
    local before = bags.counts
    bags.counts = counts
    for id, n in pairs(counts) do
        local delta = n - (before[id] or 0)
        if delta ~= 0 then Change(id, delta) end
    end
    for id, old in pairs(before) do
        if not counts[id] then Change(id, -old) end
    end
    AfterDiff(counts, boughtAmmo, boughtOther, context)
end

---------------------------------------------------------------------------
-- CountCast and cast reactions
---------------------------------------------------------------------------

local function ComboPoints()
    return Num(Call("GetComboPoints", "player", "target")) or Num(Call("UnitPower", "player", 4))
end

-- WAR-14, PRI-15: power spent, from each spell's cost (current power is
-- SECRET on Forever, so this is the only way to count it).
local function AddPowerCosts(spellID)
    local costs = Call("C_Spell.GetSpellPowerCost", spellID)
    if type(costs) ~= "table" then return end
    for _, cost in ipairs(costs) do
        local ok, kind, amount = pcall(function() return Safe(cost.name), Safe(cost.cost) end)
        if ok and type(kind) == "string" and type(amount) == "number" and amount > 0 then
            Inc(data.powerSpent, kind, amount)
        end
    end
end

-- ALL-13: estimated healing. Health is SECRET on Forever, so the real amount
-- can't be read; each cast adds the average heal from its tooltip instead
-- ("heals ... for 40 to 55", "for 32 over 12 sec", "of 45 damage over").
local healPerCast = {}  -- [spellID] = average heal, or false if the tooltip has none
local pendingHeals = {} -- [spellID] = { name, casts } until the tooltip has loaded

local function ParseHeal(text)
    text = text:lower():gsub(",", "")
    local start = text:find("heal", 1, true)
    if not start then return nil end
    local rest = text:sub(start)
    local total = 0
    local low, high = rest:match("for (%d+) to (%d+)")
    if low then total = (tonumber(low) + tonumber(high)) / 2 end
    local over = rest:match("another (%d+) over")
    if not low then
        over = over or rest:match("for (%d+) over") or rest:match("of (%d+) damage over")
    end
    if over then total = total + tonumber(over) end
    return total > 0 and total or nil
end

local function HealPerCast(spellID, name)
    if name == "Lay on Hands" then
        return Num(Call("UnitHealthMax", "player")) or false -- heals for your maximum health
    end
    local cached = healPerCast[spellID]
    if cached ~= nil then return cached end
    local text = Str(Call("C_Spell.GetSpellDescription", spellID)) or Str(Call("GetSpellDescription", spellID))
    if not text then
        Call("C_Spell.RequestLoadSpellData", spellID)
        return nil -- tried again on the next tick, once the tooltip has loaded
    end
    cached = ParseHeal(text) or false
    healPerCast[spellID] = cached
    return cached
end

local function AddHealing(name, spellID)
    local amount = HealPerCast(spellID, name)
    if amount == nil then
        local p = pendingHeals[spellID] or { name = name, casts = 0 }
        p.casts = p.casts + 1
        pendingHeals[spellID] = p
    elseif amount then
        Inc(data.healing, name, amount)                       -- ALL-13 estimated healing
    end
end

local function FlushPendingHeals()
    for spellID, p in pairs(pendingHeals) do
        local amount = HealPerCast(spellID, p.name)
        if amount ~= nil then
            if amount then Inc(data.healing, p.name, amount * p.casts) end
            pendingHeals[spellID] = nil
        end
    end
end

local function CountCast(name, spellID, castGUID)
    Inc(data.casts, name)                                     -- every cast, all ranks together
    local rank = Str(Call(C_Spell and C_Spell.GetSpellSubtext and "C_Spell.GetSpellSubtext" or "GetSpellSubtext", spellID))
    if rank and rank:find("%d") then
        data.ranks[name] = data.ranks[name] or {}
        Inc(data.ranks[name], rank)                           -- and per rank
    end
    if castGUID then
        local where = pendingTarget[castGUID]
        if where then
            pendingTarget[castGUID] = nil
            data.targets[name] = data.targets[name] or {}
            Inc(data.targets[name], where)                    -- self vs others
        end
        local points = pendingCombo[castGUID]
        if points ~= nil then
            pendingCombo[castGUID] = nil
            data.combo[name] = data.combo[name] or { points = 0, casts = 0, unknown = 0 }
            local c = data.combo[name]
            if points then
                c.points, c.casts = c.points + points, c.casts + 1 -- ROG-08 combo points
            else
                c.unknown = c.unknown + 1
            end
        end
    end
    AddPowerCosts(spellID)
end

local function Reactions(name, now)
    if name == "Shadowmeld" then lastShadowmeld = now end
    if name == "Drain Soul" then lastDrainSoul = now end
    if name == "Tame Beast" then tamingUntil = now + 30 end
    if name == "Dismiss Pet" then dismissUntil = now + 2 end
    if name == "Feign Death" then feignAt = now end
    if name == "Pick Pocket" then pocketUntil = now + 5 end
    if name == "Divine Shield" then lastBubble = now end
    if name == HEARTHSTONE and data.bubbleHearths and hearthStart and lastBubble
        and hearthStart >= lastBubble and hearthStart - lastBubble <= 10 then
        data.bubbleHearths = data.bubbleHearths + 1           -- PAL-07 bubble hearth
        lastBubble = nil
    end
    local family = SUMMON_FAMILY[name]
    if family and data.pets and lastDemonDeath[family] then
        if now - lastDemonDeath[family] < 600 then
            Inc(data.pets.resummons, family)                  -- WLK-12 resummons
        end
        lastDemonDeath[family] = nil
    end
    -- WAR-11, ROG-10, MAG-09 [probe]: an interrupt "landed" if the target's
    -- cast stopped within half a second of it.
    if interruptSpells[name] then
        if now - lastTargetStop < 0.3 then
            Inc(data.interrupts, name)
        else
            lastKick, lastKickSpell = now, name
        end
    end
end

local function OnSent(unit, target, castGUID, spellID)
    if not data then return end
    castGUID, spellID = Str(Safe(castGUID)), Num(Safe(spellID))
    if not castGUID or not spellID then return end
    local name = SpellName(spellID)
    if not name then return end
    if pendingCount > 64 then pendingTarget, pendingCombo, pendingCount = {}, {}, 0 end
    if targetSpells[name] then
        -- [probe] the target's name may be secret; it's only compared, never
        -- kept. Yours can come with your realm ("Name-Realm").
        if IsSecret(target) then
            pendingTarget[castGUID] = "unknown"
        elseif target == nil or target == "" or (me and ShortName(target) == ShortName(me)) then
            pendingTarget[castGUID] = "self"
        else
            pendingTarget[castGUID] = "other"
        end
        pendingCount = pendingCount + 1
    end
    if comboSpells[name] then
        pendingCombo[castGUID] = ComboPoints() or false
        pendingCount = pendingCount + 1
    end
    if name == HEARTHSTONE then hearthStart = GetTime() end
end

local function OnSucceeded(unit, castGUID, spellID)
    spellID, castGUID = Num(Safe(spellID)), Str(Safe(castGUID))
    if not spellID then return end
    local name = SpellName(spellID)
    if not name then return end
    local now = GetTime()
    recent.name, recent.t = name, now
    if data then
        CountCast(name, spellID, castGUID)
        if HEAL_SPELLS[name] then AddHealing(name, spellID) end
        if name == "Judgement" and data.judgements then
            Inc(data.judgements, StateTimer("seal").state or "No seal") -- PAL-02 seal judged
        end
        ApplyCastState(name)
        Reactions(name, now)
    end
    for _, fn in ipairs(castListeners) do fn(name, spellID) end
end

-- Channels (Drain Soul, Tame Beast) report at the start of the channel.
local function OnChannelStart(unit, castGUID, spellID)
    local name = SpellName(Num(Safe(spellID)) or 0)
    if name == "Drain Soul" then lastDrainSoul = GetTime()
    elseif name == "Tame Beast" then tamingUntil = GetTime() + 30 end
end

local function OnTargetCastStopped()
    if not data then return end
    local now = GetTime()
    if lastKickSpell and now - lastKick < 0.5 then
        Inc(data.interrupts, lastKickSpell)
        lastKickSpell = nil
    else
        lastTargetStop = now
    end
end

-- HUN-11 [probe]: Feign Death "worked" if combat ended right after it.
local function OnCombatEnded()
    if data and data.feignDrops and GetTime() - feignAt < 3
        and Call("UnitIsDeadOrGhost", "player") ~= true then
        data.feignDrops = data.feignDrops + 1
        feignAt = 0
    end
end

-- WAR-13: main/off hand swaps once you're in the world.
local function ReadWeapons()
    for _, slot in ipairs({ 16, 17 }) do
        weaponLinks[slot] = Str(Call("GetInventoryItemLink", "player", slot)) or false
    end
end

local function OnEquipmentChanged(slot)
    slot = Num(Safe(slot))
    if slot ~= 16 and slot ~= 17 then return end
    local link = Str(Call("GetInventoryItemLink", "player", slot)) or false
    local before = weaponLinks[slot]
    weaponLinks[slot] = link
    local now = GetTime()
    if now < swapSettle or before == nil or before == link then return end
    if now - lastSwap > 1 then -- swapping both hands at once is one swap
        data.weaponSwaps = data.weaponSwaps + 1
    end
    lastSwap = now
end

---------------------------------------------------------------------------
-- Cross-class events (ALL-06..12)
---------------------------------------------------------------------------

local function OnMoney()
    local now = Num(Call("GetMoney"))
    if not now then return end
    if lastMoney then
        local d = now - lastMoney
        if d > 0 and GetTime() < pocketUntil and data and data.pickpocket then
            data.pickpocket.gold = data.pickpocket.gold + d   -- ROG-03 gold from pockets
        elseif d < 0 then
            lastDrop = { amount = -d, t = GetTime() }
        end
    end
    lastMoney = now
end

-- ALL-06 [probe]: new buffs on you from other players, by spell and class.
local function OnAura(unit, info)
    if not all or IsSecret(info) or type(info) ~= "table" then return end
    local ok, added = pcall(function() return info.addedAuras end)
    if not ok or IsSecret(added) or type(added) ~= "table" then return end
    for _, aura in ipairs(added) do
        local fine, name, helpful, source = pcall(function()
            return Safe(aura.name), Safe(aura.isHelpful), Safe(aura.sourceUnit)
        end)
        name, source = fine and Str(name), fine and Str(source)
        if name and helpful and source and Call("UnitIsPlayer", source) == true
            and Call("UnitIsUnit", source, "player") ~= true then
            Inc(all.buffs.bySpell, name)
            local _, token = Call("UnitClass", source)
            Inc(all.buffs.byClass, Str(token) or "Unknown")
        end
    end
end

-- ALL-07 [probe]: who's offering a rez (class only, looked up in your group).
local function OnRezRequest(inviter)
    if IsSecret(inviter) or type(inviter) ~= "string" then
        pendingRezClass = nil
        return
    end
    pendingRezClass = ClassOfGroupMember(inviter)
end

-- Runs after the main tracker has recorded how you came back.
local function OnAlive()
    if not all or not db then return end
    local count = #db.deaths
    local rec = db.deaths[count]
    if not rec or not rec.rez or (all.deathsSeen or 0) >= count then return end
    all.deathsSeen = count
    if rec.rez == "player rez" then
        Inc(all.rezzedBy, pendingRezClass or "Unknown")       -- ALL-07 rezzed by class
    elseif rec.rez == "self-res" and data and data.soulstoneRez then
        data.soulstoneRez = data.soulstoneRez + 1             -- WLK-07 your own Soulstone
    end
    pendingRezClass = nil
end

local function OnSummoned()                                   -- ALL-08 summoned by a warlock
    if not all then return end
    table.insert(all.summons, { level = ns.Level(), zone = ns.Zone(), t = time() })
end

-- ALL-11: class trainer visits and what each cost.
local function TrainerOpened()
    if not all or trainerVisit then return end
    if Call("IsTradeskillTrainer") == true then return end    -- profession trainer
    trainerVisit = { money = Num(Call("GetMoney")), t = time(), level = ns.Level(), zone = ns.Zone() }
    local id = NpcID(Str(Call("UnitGUID", "npc")))
    if id then all.trainerNPCs[id] = true end                  -- for ALL-12
end

local function TrainerClosed()
    if not trainerVisit then return end
    local now = Num(Call("GetMoney"))
    trainerVisit.spent = (trainerVisit.money and now) and math.max(trainerVisit.money - now, 0) or 0
    trainerVisit.money = nil
    table.insert(all.trainerVisits, trainerVisit)
    trainerVisit = nil
end

-- ALL-12: class quests are the ones a class trainer gives or takes.
local function NpcIsTrainer()
    local id = NpcID(Str(Call("UnitGUID", "npc")))
    return id ~= nil and all.trainerNPCs[id] == true
end

local function OnQuestAccepted(a, b)
    if not all then return end
    local questID = Num(Safe(b)) or Num(Safe(a))
    if questID and NpcIsTrainer() then all.classQuestIDs[questID] = true end
end

local function OnQuestTurnedIn(questID)
    if not all then return end
    questID = Num(Safe(questID))
    if not questID or not (all.classQuestIDs[questID] or NpcIsTrainer()) then return end
    all.classQuestIDs[questID] = nil
    table.insert(all.classQuests, { questID = questID, title = QuestTitle(questID), level = ns.Level(), t = time() })
end

local function Interaction(itype, open)
    local E = Enum and Enum.PlayerInteractionType
    if not E or IsSecret(itype) or itype == nil then return end
    if itype == E.Banker then
        bankOpen = open
        if not open then bankUntil = GetTime() + 1 end
    elseif itype == E.TradePartner then
        tradeOpen = open
        if not open then tradeUntil = GetTime() + 2 end
    elseif itype == E.Trainer then
        if open then TrainerOpened() else TrainerClosed() end
    end
end

---------------------------------------------------------------------------
-- Ticker, login
---------------------------------------------------------------------------

local function Tick()
    local now = GetTime()
    for group, untilTime in pairs(stateUntil) do
        if now >= untilTime then
            StateTimer(group):Set(nil, untilTime)
            stateUntil[group] = nil
        end
    end
    -- Out of combat, check buff-like states are still up (the aura API is
    -- blocked in combat, so they're trusted until then), and time any that
    -- are up but untimed (PAL-03 auras are rarely cast again).
    if def and not ns.InCombat() then
        for _, cfg in ipairs(def.castStates or {}) do
            local t = cfg.verify and stateTimers[cfg.group]
            if t and t.state and HasAura(t.state) == false then
                t:Set(nil)
                stateUntil[cfg.group] = nil
            end
        end
        FindCastStates()
    end
    if data then FlushPendingHeals() end
    FlushAll()
end

local function StartClassDrivers()
    if def.forms then
        ns.Listen("UPDATE_SHAPESHIFT_FORM", OnFormChanged)
        ns.Listen("UPDATE_SHAPESHIFT_FORMS", OnFormChanged)
        OnFormChanged()
    end
    if def.stealth then
        ns.Listen("UPDATE_STEALTH", OnStealthChanged)
        OnStealthChanged()
    end
    if def.pets then
        petTimer = MakeTimer(data.pets.time)
        ns.Listen("UNIT_PET", OnPetChanged, "player")
        ns.Listen("UNIT_HEALTH", OnPetHealth, "pet")
        SyncPet(true)
    end
    if next(interruptSpells) then
        ns.Listen("UNIT_SPELLCAST_INTERRUPTED", OnTargetCastStopped, "target")
        ns.Listen("UNIT_SPELLCAST_CHANNEL_STOP", OnTargetCastStopped, "target")
    end
    if data.weaponSwaps then
        ReadWeapons()
        swapSettle = GetTime() + 5
        ns.Listen("PLAYER_EQUIPMENT_CHANGED", OnEquipmentChanged)
    end
    -- Buff-like states already up at login (readable out of combat only).
    if not ns.InCombat() then FindCastStates() end
end

-- ALL-05 before 0.6.4 also counted cloth, two-handed maces and cooking
-- recipes (their item subclass has food's number in other item classes).
-- What the game knows has that subclass outside consumables goes; food
-- eaten that isn't a consumable (raw fish is a trade good) stays, and a
-- name it doesn't know yet waits for the next look.
local CLOTH = { ["Linen Cloth"] = true, ["Wool Cloth"] = true, ["Silk Cloth"] = true, ["Mageweave Cloth"] = true,
    ["Runecloth"] = true, ["Felcloth"] = true }
local function CleanFood()
    if type(all) ~= "table" or type(all.food) ~= "table" then return end
    for name in pairs(all.food) do
        local _, _, _, _, _, classID, subClassID = Call("C_Item.GetItemInfoInstant", name)
        if classID == nil then _, _, _, _, _, classID, subClassID = Call("GetItemInfoInstant", name) end
        classID, subClassID = Num(Safe(classID)), Num(Safe(subClassID))
        if CLOTH[name] or (classID and classID ~= CONSUMABLE and subClassID == FOOD_AND_DRINK) then
            all.food[name] = nil
        end
    end
end

local activated = false
local function Activate()
    if activated or not db then return end
    activated = true
    local _, token = Call("UnitClass", "player")
    classToken = Str(token)
    me = Str(Call("UnitName", "player"))
    db.class = db.class or {}
    all = db.class.ALL or {}
    db.class.ALL = all
    ns.Fill(all, ALL_DEFAULTS)
    CleanFood()                                               -- ALL-05 old non-food entries
    if C_Timer and C_Timer.After then C_Timer.After(20, function() pcall(CleanFood) end) end -- (more names known by then)
    -- ALL-12: trainers saved by full GUID are kept by NPC ID from now on.
    local trainers = {}
    for key in pairs(all.trainerNPCs) do trainers[NpcID(key) or key] = true end
    all.trainerNPCs = trainers
    wandTimer = MakeTimer(TimeStore(all, "wand"))
    lastMoney = Num(Call("GetMoney"))
    def = classToken and CLASSES[classToken]
    if def then
        data = db.class[classToken] or {}
        db.class[classToken] = data
        ns.Fill(data, CLASS_DEFAULTS)
        if def.store then ns.Fill(data, def.store) end
        BuildLookups()
        StartClassDrivers()
    end
    OnAutoRepeat()
    SetBaseline(ScanBags())
    if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(5, Tick) end
end

---------------------------------------------------------------------------
-- Ding snapshot: class totals, so the website can chart them per level
---------------------------------------------------------------------------

local function Rounded(t)
    local out = {}
    for k, v in pairs(t or {}) do out[k] = math.floor(v + 0.5) end
    return out
end

local function ClassTotals()
    local out = {}
    if def and data then
        out.healing = math.floor(Sum(data.healing) + 0.5)    -- ALL-13
        for _, item in ipairs(def.items) do
            if item.state then
                out[item.id] = Rounded(data.time[item.state])
            elseif item.swaps then
                out[item.id] = (data.swaps[item.swaps] or {}).total or 0
            else
                local total = 0
                for _, spell in ipairs(item.casts or {}) do total = total + (data.casts[spell] or 0) end
                if item.prefix then
                    for spell, n in pairs(data.casts) do
                        if spell:sub(1, #item.prefix) == item.prefix then total = total + n end
                    end
                end
                -- Items count once used. Where the casts use them up (Vanish's
                -- Flash Powder, Reincarnation's Ankh) they're the same uses, so
                -- the bigger count is kept (the game may not report the cast).
                local used = 0
                for _, name in ipairs(item.items or {}) do used = used + ((data.items[name] or {}).used or 0) end
                total = item.casts and math.max(total, used) or total + used
                if total > 0 then out[item.id] = total end
            end
        end
    end
    if all then
        out["ALL-01"] = Sum(all.bandages)
        out["ALL-02"] = Sum(all.potions.healing) + Sum(all.potions.mana) + Sum(all.potions.other)
        out["ALL-05"] = Sum(all.food)
        out["ALL-08"] = #all.summons
    end
    return out
end

ns.OnDing(function(snapshot)
    if all then snapshot.class = ClassTotals() end
end)

---------------------------------------------------------------------------
-- /jt class: which tracked spells the game knows (helps spot anything
-- Forever has renamed or removed)
---------------------------------------------------------------------------

function ns.ClassStatus()
    if not def then
        print(PREFIX, "Class tracking isn't active for this character.")
        return
    end
    local found, missing, seen = 0, {}, {}
    local function Check(spell)
        if seen[spell] then return end
        seen[spell] = true
        if KnownSpell(spell) then found = found + 1 else missing[#missing + 1] = spell end
    end
    for _, item in ipairs(def.items) do
        for _, spell in ipairs(item.casts or {}) do Check(spell) end
        for _, spell in ipairs(item.learned or {}) do Check(spell) end
    end
    for _, cfg in ipairs(def.castStates or {}) do
        for _, spell in ipairs(cfg.spells) do Check(spell) end
    end
    print(PREFIX, string.format("%s: %d tracked spells found in game, %d not found.",
        ClassName(), found, #missing))
    if #missing > 0 then
        print(PREFIX, "Not found (not learned yet, or not on Forever): " .. table.concat(missing, ", "))
    end
end

---------------------------------------------------------------------------
-- Pages for the window (drawn with the UI's page builder)
---------------------------------------------------------------------------

local U -- ns.UI helpers, set when a page is drawn

-- 4380 -> "4,380"
local function Big(n)
    n = math.floor((n or 0) + 0.5)
    if BreakUpLargeNumbers then return BreakUpLargeNumbers(n) end
    return tostring(n)
end

local function LearnedText(spell)
    local s = db.spells and db.spells[spell]
    if s and s.level then return "Level " .. s.level end
    if KnownSpell(spell) then return "Before tracking" end
    return "Not yet"
end

local function ObtainedText(name)
    local o = data.obtained[name]
    if not o then return "Not yet" end
    if o.before then return "Before tracking" end
    return string.format("Level %d, %s", o.level or 0, U.Date(o.t))
end

local KIND_ORDER = { "bought", "created", "looted", "received", "from mail", "from bank", "gained",
    "used", "sold", "traded", "mailed", "banked", "posted", "destroyed" }

local function ItemText(rec)
    if not rec then return "-" end
    local parts = {}
    for _, kind in ipairs(KIND_ORDER) do
        if rec[kind] then parts[#parts + 1] = kind .. " " .. rec[kind] end
    end
    return #parts > 0 and table.concat(parts, ", ") or "-"
end

-- Times cast (all ranks together). Per-rank and self/others counts are
-- still saved for the website, just not shown here.
local function CastText(spell, item)
    local text = tostring(data.casts[spell] or 0)
    if item.interrupts then
        text = text .. ", " .. (data.interrupts[spell] or 0) .. " interrupted"
    end
    return text
end

local function Localized(byClass)
    local out = {}
    for token, n in pairs(byClass or {}) do out[ClassName(token)] = n end
    return out
end

local function PetLines(B, list, fmt)
    if #list == 0 then B:Note("None yet.") return end
    for i = #list, 1, -1 do B:Note(fmt(list[i])) end
end

-- Pages for each custom counter.
local CUSTOM_DRAW = {
    weaponSwaps = function(B) B:Row("Main or off hand swaps", data.weaponSwaps) end,
    judgements = function(B) B:BarList(data.judgements) end,
    bubbleHearths = function(B)
        B:Row("Divine Shield, then Hearthstone within 10s", data.bubbleHearths)
    end,
    ammoUsed = function(B)
        B:BarList(data.ammo.byType)
        B:BarList(data.ammo.used)
    end,
    ammoBought = function(B)
        B:Row("Gold spent on ammo", U.Money(data.ammo.gold))
        B:BarList(data.ammo.bought)
    end,
    outOfAmmo = function(B) B:Row("Times you ran out", data.ammo.outOfAmmo) end,
    tamed = function(B)
        PetLines(B, data.pets.tamed, function(p)
            return string.format("%s (%s), pet level %s, tamed at level %d in %s, %s", p.name or "?",
                p.family or "?", p.petLevel or "?", p.level or 0, p.zone or "?", U.Date(p.t))
        end)
    end,
    petTime = function(B)
        local list = U.Sorted(data.pets.time)
        B:Row("Favorite", list[1] and list[1][1] or "-")
        local total = Sum(data.pets.time)
        for _, kv in ipairs(list) do B:Bar(kv[1], kv[2], total, U.Dur(kv[2])) end
    end,
    petDeaths = function(B)
        B:Row("Deaths", Sum(data.pets.deaths))
        B:BarList(data.pets.deaths)
        if data.pets.resummons and next(data.pets.resummons) then
            B:Row("Resummoned after dying", Sum(data.pets.resummons))
            B:BarList(data.pets.resummons)
        end
    end,
    abandoned = function(B)
        PetLines(B, data.pets.abandoned, function(p)
            return string.format("%s, pet level %s, abandoned at level %d, %s", p.pet or "?",
                p.petLevel or "?", p.level or 0, U.Date(p.t))
        end)
    end,
    fed = function(B) B:BarList(data.pets.fed) end,
    feignDrops = function(B) B:Row("Combat dropped right after", data.feignDrops) end,
    pickpocket = function(B)
        B:Row("Gold from pockets", U.Money(data.pickpocket.gold))
        B:BarList(data.pickpocket.items)
    end,
    lockpicking = function(B)
        local s = db.skills and db.skills["Lockpicking"]
        B:Row("Lockpicking skill", s and s.rank or "-")
    end,
    poisonsApplied = function(B)
        B:BarList(data.poisons.applied)
        B:BarList(data.poisons.appliedItems)
    end,
    poisonsCrafted = function(B) B:BarList(data.poisons.crafted) end,
    combo = function(B)
        local any = false
        for spell, c in pairs(data.combo) do
            any = true
            B:Row(spell, c.casts > 0 and string.format("%.1f average", c.points / c.casts) or "-")
            if c.unknown > 0 then B:Note(c.unknown .. " casts where combo points couldn't be read") end
        end
        if not any then B:Note("Use a finisher to start counting.") end
    end,
    mainBuilder = function(B)
        local top = U.Sorted({ ["Sinister Strike"] = data.casts["Sinister Strike"] or 0,
            Backstab = data.casts.Backstab or 0, Hemorrhage = data.casts.Hemorrhage or 0 })[1]
        B:Row("Main builder", top and top[2] > 0 and top[1] or "-")
    end,
    wand = function(B)
        B:Row("Wand shots", data.casts.Shoot or 0)
        B:Row("Time wanding", U.Dur((all.time.wand or {}).Wanding or 0))
    end,
    totems = function(B)
        local byElement = {}
        for spell, n in pairs(data.casts) do
            if spell:find("Totem$") then
                local element = TOTEM_ELEMENTS[spell] or "Other"
                byElement[element] = byElement[element] or {}
                byElement[element][spell] = n
            end
        end
        if not next(byElement) then B:Note("No totems dropped yet.") end
        for _, element in ipairs(ELEMENTS) do
            if byElement[element] then
                B:Row(element .. " totems", Sum(byElement[element]))
                B:BarList(byElement[element])
            end
        end
    end,
    totemFavorites = function(B)
        local best = {}
        for spell, n in pairs(data.casts) do
            local element = spell:find("Totem$") and (TOTEM_ELEMENTS[spell] or "Other")
            if element and (not best[element] or n > best[element][2]) then best[element] = { spell, n } end
        end
        for _, element in ipairs(ELEMENTS) do
            if best[element] then B:Row(element, best[element][1] .. " (" .. best[element][2] .. ")") end
        end
        if not next(best) then B:Note("No totems dropped yet.") end
    end,
    conjuredWater = function(B) B:BarList(data.conjured.water) end,
    conjuredFood = function(B) B:BarList(data.conjured.food) end,
    conjuredGiven = function(B) B:BarList(data.conjured.given) end,
    manaGems = function(B)
        B:Row("Conjured", Sum(data.conjured.gems))
        B:BarList(data.conjured.gems)
        B:Row("Used", Sum(data.conjured.gemsUsed))
        B:BarList(data.conjured.gemsUsed)
    end,
    shardsGained = function(B)
        B:Row("Total", Sum(data.shards.gained))
        B:BarList(data.shards.gained)
    end,
    shardsUsed = function(B)
        B:Row("Total", Sum(data.shards.used))
        B:BarList(data.shards.used)
    end,
    shardsPeak = function(B) B:Row("Most held at once", data.shards.peak) end,
    stones = function(B, item)
        for _, stone in ipairs(item.stones) do
            B:Row(stone .. "s", Sum(data.stones[stone]))
            if data.stones[stone] then B:BarList(data.stones[stone]) end
        end
    end,
    healthstonesUsed = function(B) B:BarList(data.healthstonesUsed) end,
    soulstoneRez = function(B) B:Row("Times", data.soulstoneRez) end,
}

local function DrawItem(B, item)
    B:Heading(item.label)
    if item.state then
        local times = data.time[item.state] or {}
        local total = Sum(times)
        local list = U.Sorted(times)
        if #list == 0 then B:Note("Nothing yet.") end
        for _, kv in ipairs(list) do B:Bar(kv[1], kv[2], total, U.Dur(kv[2])) end
    end
    if item.swaps then
        local s = data.swaps[item.swaps]
        B:Row("Total", s and s.total or 0)
        local top = s and U.Sorted(s.pairs)[1]
        -- Saved as "Caster Form > Cat Form"; shown as "Caster Form to Cat Form".
        B:Row("Most common", top and ((top[1]:gsub(" > ", " to ")) .. " (" .. top[2] .. ")") or "-")
    end
    for _, spell in ipairs(item.learned or {}) do B:Row(spell, LearnedText(spell)) end
    for _, spell in ipairs(item.casts or {}) do
        B:Row(spell, CastText(spell, item))
    end
    local healing = {}                                        -- ALL-13 estimated healing
    for _, spell in ipairs(item.casts or {}) do
        if HEAL_SPELLS[spell] and (data.healing[spell] or 0) > 0 then healing[spell] = data.healing[spell] end
    end
    if next(healing) then
        B:Row("Healing done (estimated)*", Big(Sum(healing)))
        B:BarList(healing, Big)
    end
    if item.prefix then
        local found = {}
        for spell, n in pairs(data.casts) do
            if spell:sub(1, #item.prefix) == item.prefix then found[spell:sub(#item.prefix + 1)] = n end
        end
        if next(found) then B:BarList(found) else B:Note("None cast yet.") end
    end
    for _, name in ipairs(item.items or {}) do B:Row(name, ItemText(data.items[name])) end
    for _, name in ipairs(item.obtained or {}) do B:Row(name, ObtainedText(name)) end
    if item.power then
        local label = item.power:sub(1, 1) .. item.power:sub(2):lower()
        B:Row(label .. " spent on abilities", U.Num(data.powerSpent[item.power]))
        B:Note("Your current " .. label:lower() .. " can't be read on Forever, so this adds up the cost of each ability you used.")
    end
    local custom = item.custom and CUSTOM_DRAW[item.custom]
    if custom then custom(B, item) end
end

-- Plain cast counters go on the Abilities page; everything else on Class Stats.
local function IsAbilityItem(item)
    return (item.casts or item.prefix) and not (item.state or item.swaps or item.learned or item.items
        or item.obtained or item.power or item.custom) and true or false
end

local function DrawClassPage(B, abilities)
    U = ns.UI
    B:Title(ClassName() .. (abilities and " Abilities" or " Stats"))
    if abilities then B:Note("Times you've cast each spell, all ranks together.") end
    for _, item in ipairs(def.items) do
        if IsAbilityItem(item) == abilities then DrawItem(B, item) end
    end
    if abilities and Sum(data.healing) > 0 then
        B:Footnote("* Estimated from each heal's tooltip, since health can't be read on Forever. It doesn't include +healing gear, crits or overhealing.")
    end
end

local function SkillByLevel(skill)
    local byLevel, steps = {}, {}
    for _, h in ipairs(skill and skill.history or {}) do
        if not byLevel[h.level] or h.rank > byLevel[h.level] then byLevel[h.level] = h.rank end
    end
    for level = 1, ns.MAX_LEVEL do
        if byLevel[level] then steps[#steps + 1] = "level " .. level .. ": " .. byLevel[level] end
    end
    return #steps > 0 and ("Rank by " .. table.concat(steps, ", ")) or nil
end

local function DrawConsumables(B)
    U = ns.UI
    B:Title("Consumables")
    B:Heading("Bandages")                                     -- ALL-01
    B:BarList(all.bandages)
    local firstAid = db.skills and db.skills["First Aid"]
    B:Row("First Aid skill", firstAid and firstAid.rank or "-")
    local steps = SkillByLevel(firstAid)
    if steps then B:Note(steps) end
    B:Heading("Potions")                                      -- ALL-02
    -- Health and mana potions: the bigger of ours and the game's Statistics pane.
    local paneStat = { healing = 345, mana = 922 }
    for _, kind in ipairs({ "healing", "mana", "other" }) do
        local count = Sum(all.potions[kind])
        if paneStat[kind] and U.Best then count = U.Best(count, U.Stat(paneStat[kind])) end
        B:Row(kind:sub(1, 1):upper() .. kind:sub(2), count)
        if next(all.potions[kind]) then B:BarList(all.potions[kind]) end
    end
    if classToken ~= "WARLOCK" then
        B:Heading("Healthstones From Warlocks")               -- ALL-03
        B:BarList(all.healthstones)
    end
    if classToken ~= "MAGE" then
        B:Heading("Mage Food and Water")                      -- ALL-04
        B:BarList(all.conjured)
    end
    B:Heading("Food and Drink")                               -- ALL-05
    B:BarList(all.food)
    if U.Block then U.Block(B, "consumables", { [345] = true, [922] = true }) end
end

local function DrawFromOthers(B)
    U = ns.UI
    B:Title("From Other Players")
    B:Heading("Buffs Received")                               -- ALL-06
    B:BarList(all.buffs.bySpell)
    B:Heading("Buffs Received, by Their Class")
    B:BarList(Localized(all.buffs.byClass))
    B:Note("Read as buffs land on you. The game may block this in combat, so some can be missed.")
    B:Heading("Resurrected by Other Players")                 -- ALL-07
    B:BarList(Localized(all.rezzedBy))
    B:Heading("Summoned by a Warlock")                        -- ALL-08
    B:Row("Times summoned", #all.summons)
    for i = #all.summons, 1, -1 do
        local s = all.summons[i]
        B:Note(string.format("Level %d, from %s, %s", s.level or 0, s.zone or "?", U.Date(s.t)))
    end
end

local function DrawRacials(B)
    U = ns.UI
    local casts = data and data.casts or {}
    B:Title("Racials & Wands")
    B:Heading("Racial Abilities")                             -- ALL-09
    local any = false
    for _, spell in ipairs(RACIALS) do
        if casts[spell] then
            B:Row(spell, casts[spell])
            any = true
        end
    end
    if not any then B:Note("No racial abilities used yet.") end
    B:Heading("Wand")                                         -- ALL-10
    B:Row("Wand shots", casts.Shoot or 0)
    B:Row("Time wanding", U.Dur((all.time.wand or {}).Wanding or 0))
end

local function DrawTrainers(B)
    U = ns.UI
    B:Title("Trainers & Class Quests")
    local visits = all.trainerVisits
    local spent = 0
    for _, v in ipairs(visits) do spent = spent + (v.spent or 0) end
    B:Heading("Class Trainer Visits")                         -- ALL-11
    B:Row("Visits", #visits)
    B:Row("Spent on training", U.Money(spent))
    local widths = { 110, 50, 150, 120 }
    if #visits > 0 then B:Cols({ "Date", "Level", "Zone", "Spent" }, widths) end
    for i = #visits, 1, -1 do
        local v = visits[i]
        B:Cols({ U.Date(v.t), v.level, v.zone, U.Money(v.spent) }, widths)
    end
    B:Heading("Class Quests Completed")                       -- ALL-12
    B:Row("Completed", #all.classQuests)
    for i = #all.classQuests, 1, -1 do
        local q = all.classQuests[i]
        B:Row(q.title or ("Quest #" .. q.questID), "Level " .. (q.level or "?"))
    end
    B:Note("Class quests are spotted by being given or taken by a class trainer you've trained with.")
end

-- Sections for the window: your class, then the cross-class pages.
function ns.ClassSections()
    local sections = {}
    if def and data then
        table.insert(sections, { name = ClassName(), pages = {
            { "Abilities", function(B) DrawClassPage(B, true) end },
            { "Class Stats", function(B) DrawClassPage(B, false) end },
        } })
    end
    if all then
        table.insert(sections, { name = "Cross-Class", pages = {
            { "Consumables", DrawConsumables },
            { "From Other Players", DrawFromOthers },
            { "Racials & Wands", DrawRacials },
            { "Trainers & Class Quests", DrawTrainers },
        } })
    end
    return sections
end

-- Shared with the wrapped tracker.
ns.MakeTimer, ns.HasAura, ns.SpellName, ns.KnownSpell = MakeTimer, HasAura, SpellName, KnownSpell
ns.ClassToken = function() return classToken end
function ns.OnCast(fn) table.insert(castListeners, fn) end          -- fn(spellName, spellID)
function ns.OnItemChange(fn) table.insert(itemListeners, fn) end    -- fn(change)

---------------------------------------------------------------------------
-- Events (shared with the main tracker's registrations)
---------------------------------------------------------------------------

ns.Listen("PLAYER_ENTERING_WORLD", function(isInitialLogin, isReload)
    if isInitialLogin or isReload then Activate() end
end)
ns.Listen("UNIT_SPELLCAST_SUCCEEDED", OnSucceeded, "player")
ns.Listen("UNIT_SPELLCAST_SENT", OnSent, "player")
ns.Listen("UNIT_SPELLCAST_CHANNEL_START", OnChannelStart, "player")
ns.Listen("BAG_UPDATE_DELAYED", OnBagsChanged)
ns.Listen("PLAYER_MONEY", OnMoney)
ns.Listen("TRADE_SHOW", function() tradeOpen = true end)
ns.Listen("TRADE_CLOSED", function()
    tradeOpen = false
    tradeUntil = GetTime() + 2 -- the trade's items can land just after it closes
end)
ns.Listen("BANKFRAME_OPENED", function() bankOpen = true end)
ns.Listen("BANKFRAME_CLOSED", function()
    bankOpen = false
    bankUntil = GetTime() + 1
end)
ns.Listen("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(itype) Interaction(itype, true) end)
ns.Listen("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(itype) Interaction(itype, false) end)
ns.Listen("TRAINER_SHOW", TrainerOpened)
ns.Listen("TRAINER_CLOSED", TrainerClosed)
ns.Listen("QUEST_ACCEPTED", OnQuestAccepted)
ns.Listen("QUEST_TURNED_IN", OnQuestTurnedIn)
ns.Listen("RESURRECT_REQUEST", OnRezRequest)
ns.Listen("PLAYER_ALIVE", OnAlive)
ns.Listen("PLAYER_UNGHOST", OnAlive)
ns.Listen("PLAYER_DEAD", ClearCastStates)
ns.Listen("UNIT_AURA", OnAura, "player")
ns.Listen("START_AUTOREPEAT_SPELL", OnAutoRepeat)
ns.Listen("STOP_AUTOREPEAT_SPELL", OnAutoRepeat)
ns.Listen("PLAYER_REGEN_ENABLED", OnCombatEnded)
ns.Listen("PLAYER_LOGOUT", FlushAll)

ns.OnLoad(function(saved)
    db = saved
    ns.Hook("DeleteCursorItem", function() destroyUntil = GetTime() + 1 end)
    ns.Hook("PetAbandon", OnPetAbandoned)                     -- HUN-07
    ns.Hook("PetDismiss", function() dismissUntil = GetTime() + 2 end)
    if not ns.Hook("C_SummonInfo.ConfirmSummon", OnSummoned) then
        ns.Hook("ConfirmSummon", OnSummoned)                  -- ALL-08
    end
end)
