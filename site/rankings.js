// Journey Tracker rankings: every stat the addon tracks that a player can
// stand out in, each with who the top players are and a line to go with it.
// site/build.ps1 puts this file into the recap page. A journey's values for
// them come from site/model.js (profileOf).
//
// R(key, source, group, who, detail, direction, median, spread, line, extra)
//   key        the value it ranks, from the export (same key = same number)
//   source     where it comes from: a spec item (J26 = journey #26, DRU-01,
//              W-009) or a Statistics pane ID (P-98)
//   group      the part of the game; a page shows at most two from one group
//   who        who the top players are, read as "the top 1% of <who>"
//   detail     the player's number: {n} count, {t} time, {g} money (from copper),
//              {p} whole number, {d} one decimal; {mob} {zone} {quest} {item}
//              {kept} {fav} are the player's own names; {m} the milestone the
//              journey is ranked at (30 for one at level 30-39, as it was
//              at 30; 60 at 60; none below 10)
//   direction  "+" when more is the notable way, "-" when less is. A "+"
//              ranking skips players at 0: nobody is top 1% of Onyxia
//              slayers without killing her.
//   median, spread  how players spread out: the median, and sigma of the
//              log. Made up: only the sample journey and the example players
//              are ranked on them. A saved journey gets its real place.
//   line       a line to go with it (it can use the names too)
//   extra      { id, family, only, cohort, trade, min, max, at60, fixed }: `id`
//              when two rankings share a key, `family` for rankings that
//              measure the same thing (only one is shown), `only`/`cohort` for
//              class, race, faction and realm rankings (`only` can list
//              several), `trade` for a profession's own rankings (only players
//              with it), `min`/`max` for the values the game allows (levels,
//              skill, percentages; site/model.js's applies() leaves out a
//              value past them), `at60` for rankings that only mean
//              something at level 60, `fixed` for values settled by the time
//              a journey reaches its milestone (the time to it, the level you
//              did something at): what a journey exported past its milestone,
//              or there long after reaching it, is ranked on, with what else
//              is known as of the milestone (site/model.js's asOfValues).
//              "at level {n}" details are fixed, kept to levels 1-60 and
//              marked `atLevel` (counted at a milestone only if done by it)
//              by themselves, "{p}%" ones to 100.
var RANKINGS = (function () {
  function R(key, source, group, who, detail, direction, median, spread, line, extra) {
    var r = { id: key, key: key, source: source, group: group, name: who, detail: detail,
              high: direction === "+", pop: [median, spread], line: line };
    if (/at level \{n\}/.test(detail)) { r.min = 1; r.max = 60; r.fixed = true; r.atLevel = true; }   // not "item level {n}"
    if (/\{p\}%/.test(detail)) r.max = 100;
    for (var k in extra || {}) r[k] = extra[k];
    return r;
  }
  function more(e, extra) {
    for (var k in extra || {}) e[k] = extra[k];
    return e;
  }
  // A class's own ranking, against that class; a faction's, against that faction.
  function C(token, extra) { return more({ only: { classToken: token }, cohort: "class" }, extra); }
  function F(faction, extra) { return more({ only: { faction: faction }, cohort: "faction" }, extra); }
  // A profession's own ranking; SKILL for its skill level, which tops out at 300.
  function T(trade, extra) { return more({ trade: trade }, extra); }
  function SKILL(trade) { return { trade: trade, max: 300 }; }
  var CLASS = { cohort: "class" };

  return [
    // ---- Time and pace (journey #1-18) ----
    R("played", "J1", "pace", "speed-levelers", "{m} in {t} /played", "-", 864000, 0.3, "Azeroth barely had time to learn your name.", { fixed: true }),
    R("played", "J1", "pace", "speed-levelers", "{m} in {t} /played", "-", 850000, 0.28, "The fastest of your class. Your trainer barely kept up.", { id: "playedClass", cohort: "class", fixed: true }),
    R("days", "J4", "pace", "fast finishers", "{m} in {n} calendar days", "-", 62, 0.5, "Some take a season. You took a few weeks.", { fixed: true }),
    R("sessions", "J6", "pace", "frequent visitors", "{n} play sessions", "+", 90, 0.4, "You clocked in like it was a job. It kind of was."),
    R("avgSession", "J7", "pace", "settlers-in", "{t} per session on average", "+", 6000, 0.4, "When you sit down, you sit down."),
    R("session", "J8", "pace", "marathon players", "{t} in one sitting", "+", 16200, 0.4, "Hydration is a buff too, you know."),
    R("sessionLevels", "J9", "pace", "power levelers", "{n} levels in one session", "+", 2.5, 0.35, "One sitting, several dings, zero regrets."),
    R("afk", "J10", "pace", "professional AFKers", "{t} away from the keyboard", "+", 20000, 0.6, "Your character has memorized the inn's ceiling."),
    R("resting", "J11", "pace", "inn regulars", "{t} resting in inns and cities", "+", 40000, 0.5, "The innkeeper starts pouring when you walk in."),
    R("timeDead", "J12", "deaths", "quick recoverers", "only {t} spent dead", "-", 18000, 0.5, "The Spirit Healer barely knows your face."),
    R("taxiTime", "J13", "travel", "sky commuters", "{t} on flight paths", "+", 25000, 0.5, "You've seen every rooftop in Azeroth from above."),
    R("mounted", "J14", "travel", "riders", "{t} in the saddle", "+", 90000, 0.5, "Your mount has more /played than some alts."),
    R("xpRate", "J15", "pace", "XP machines", "{n} XP per hour", "+", 30000, 0.25, "The XP bar moved like it owed you money."),
    R("slowestLevel", "J16", "pace", "steady climbers", "your slowest level took only {t}", "-", 32000, 0.35, "Even your worst level was a brisk one.", { fixed: true }),
    R("daysPlayed", "J17", "pace", "regulars", "played on {n} different days", "+", 30, 0.4, "Azeroth was part of the daily routine."),
    R("nightOwl", "J18", "pace", "night owls", "{p}% of your playtime after midnight", "+", 4, 0.7, "The moon over Darnassus knows you well."),
    R("earlyBird", "J18", "pace", "early birds", "{p}% of your playtime before 9 AM", "+", 3, 0.8, "First worm, first quest, first ding."),

    // ---- Leveling (#21-25) ----
    R("rested", "J22", "xp", "well-rested players", "{p}% of your XP from rested bonus", "+", 8, 0.5, "You treated the inn like a power-up."),
    R("questXP", "J23", "xp", "story followers", "{p}% of your XP from quests", "+", 50, 0.2, "You read the quest text. Some of it, anyway."),
    R("killXP", "J23", "xp", "XP grinders", "{p}% of your XP from kills", "+", 40, 0.25, "Why read quests when the mobs are right there?"),
    R("exploreXP", "J65", "xp", "explorers", "{p}% of your XP from discovering places", "+", 3, 0.4, "If there was a hill, you climbed it."),
    R("groupXP", "J25", "xp", "party levelers", "{p}% of your XP earned in a group", "+", 20, 0.6, "Leveling is better with friends, and their heals."),

    // ---- Combat and kills (#26-43) ----
    R("kills", "J26", "combat", "monster slayers", "{n} kills", "+", 8200, 0.3, "The local wildlife has started a support group."),
    R("killRate", "J26", "combat", "efficient killers", "{n} kills per hour played", "+", 52, 0.3, "Pull, kill, loot, repeat. Beautifully.", { family: "kills" }),
    R("levelKills", "J27", "combat", "rampagers", "{n} kills in a single level", "+", 400, 0.4, "One level, one very long trail."),
    R("topMob", "J29", "combat", "{mob} hunters", "{n} slain", "+", 110, 0.4, "Somewhere, every {mob} has your face on a wanted poster."),
    R("mobTypes", "J28", "combat", "collectors of foes", "{n} different kinds of mob killed", "+", 600, 0.3, "Your bestiary would make a scholar weep."),
    R("elites", "J30", "combat", "elite hunters", "{n} elites killed", "+", 320, 0.5, "Gold dragon around the portrait? Sounds like a challenge."),
    R("rares", "J31", "combat", "rare spawn hunters", "{n} rare mobs killed", "+", 4, 0.6, "You checked every spawn point. Twice."),
    R("beasts", "J32", "combat", "beast hunters", "{n} beasts killed", "+", 3000, 0.4, "Nature has filed a restraining order."),
    R("humanoids", "J32", "combat", "bandit busters", "{n} humanoids killed", "+", 2500, 0.4, "Defias, Syndicate, cultists: none of them stood a chance."),
    R("undead", "J32", "combat", "undead slayers", "{n} undead put back to rest", "+", 900, 0.5, "The Scourge would like its minions back."),
    R("demons", "J32", "combat", "demon hunters", "{n} demons killed", "+", 200, 0.7, "You were hunting demons before it was cool."),
    R("elementals", "J32", "combat", "elemental breakers", "{n} elementals killed", "+", 300, 0.6, "Earth, wind, fire and water, all defeated."),
    R("dragonkin", "J32", "combat", "dragon slayers", "{n} dragonkin killed", "+", 80, 0.8, "Whelps, beware."),
    R("gap", "J33", "combat", "underdogs", "beat a mob {n} levels above you", "+", 3, 0.35, "Level is just a number. A scary, red number."),
    R("fights", "J34", "combat", "brawlers", "{n} fights", "+", 9000, 0.3, "You never met a mob you didn't want to fight."),
    R("fight", "J35", "combat", "endurance fighters", "one fight lasted {t}", "+", 85, 0.4, "That wasn't a fight, it was a saga."),
    R("avgFight", "J36", "combat", "swift finishers", "fights over in {d} seconds on average", "-", 22, 0.3, "In, out, loot. Efficient."),
    R("combatTime", "J37", "combat", "battle-hardened", "{t} in combat", "+", 80000, 0.35, "You spent more time swinging than sitting."),
    R("ambushes", "J39", "combat", "mob magnets", "{n} mobs jumped you before you saw them", "+", 300, 0.6, "Situational awareness: optional."),
    R("multiPulls", "J40", "combat", "multi-pullers", "{n} pulls of two or more mobs", "+", 800, 0.5, "Why fight one when you can fight four?"),
    R("maxMobs", "J40", "combat", "crowd fighters", "{n} mobs on you at once", "+", 5, 0.35, "That's not a pull, that's a parade."),
    R("bosses", "J41", "dungeons", "dungeon crawlers", "{n} dungeon bosses downed", "+", 55, 0.45, "Bosses saw you coming and checked their loot tables."),
    R("wipes", "J42", "dungeons", "wipe veterans", "{n} boss wipes", "+", 12, 0.7, "Every wipe is a lesson. You learned a lot."),
    R("honor", "J43", "pvp", "world PvPers", "{n} honorable kills on the way to {m}", "+", 35, 0.9, "Leveling was the side quest. The other faction was the main one."),

    // ---- Deaths (#44-52) ----
    R("deaths", "J44", "deaths", "survivors", "only {n} deaths", "-", 60, 0.45, "The Spirit Healer has your number but never calls."),
    R("levelDeaths", "J45", "deaths", "unlucky streakers", "{n} deaths in a single level", "+", 6, 0.5, "That level was personal."),
    R("zoneDeaths", "J51", "deaths", "{zone} casualties", "{n} deaths there", "+", 5, 0.6, "{zone} owes you a few corpse runs."),
    R("dungeonDeaths", "J48", "deaths", "dungeon divers", "{n} deaths in dungeons", "+", 8, 0.6, "Every dungeon floor has your outline in chalk."),
    R("groupDeaths", "J48", "deaths", "team players", "{n} deaths while grouped", "+", 10, 0.6, "You took one for the team. Several times."),
    R("corpseRuns", "J49", "deaths", "marathon ghosts", "{n} corpse runs", "+", 30, 0.5, "You know every graveyard path by heart."),
    R("spiritRez", "J49", "deaths", "Spirit Healer regulars", "{n} spirit healer resurrections", "+", 3, 0.8, "Resurrection sickness is a lifestyle."),
    R("playerRez", "J49", "deaths", "well-loved adventurers", "{n} resurrections from other players", "+", 3, 0.8, "Someone always had your back, and a rez."),
    R("corpseTime", "J50", "deaths", "ghost joggers", "{t} on corpse runs", "+", 6000, 0.6, "You've run further dead than some do alive."),
    R("streak", "J52", "deaths", "untouchables", "{n} levels in a row without dying", "+", 8, 0.5, "Death tried. Death failed."),
    R("pvpDeaths", "J47", "deaths", "gank magnets", "killed by other players {n} times", "+", 4, 0.8, "Rogues saw you and smiled."),
    R("fallDeaths", "J102", "deaths", "victims of gravity", "{n} deaths from falling", "+", 1, 0.9, "Gravity: still undefeated."),

    // ---- Quests (#53-62) ----
    R("quests", "J53", "quests", "questers", "{n} quests completed", "+", 520, 0.25, "Every exclamation mark in Azeroth fears your approach."),
    R("questRate", "J53", "quests", "quest machines", "{d} quests per hour played", "+", 3.1, 0.3, "You hand them in faster than NPCs can write them.", { family: "quests" }),
    R("levelQuests", "J54", "quests", "quest sprinters", "{n} quests in a single level", "+", 30, 0.4, "One level, a whole stack of turn-ins."),
    R("zoneQuests", "J55", "quests", "zone completionists", "{n} quests in one zone", "+", 45, 0.35, "You didn't leave until that zone ran out of problems."),
    R("questGold", "J57", "quests", "paid adventurers", "{g} from quest rewards", "+", 4000000, 0.45, "Heroism pays. Literally."),
    R("accepted", "J58", "quests", "yes-sayers", "{n} quests accepted", "+", 560, 0.25, "You never met a quest giver you could say no to."),
    R("abandoned", "J59", "quests", "finishers", "abandoned only {n} quests", "-", 45, 0.6, "If you started it, you finished it."),
    R("abandoned", "J59", "quests", "quest quitters", "{n} quests abandoned", "+", 45, 0.6, "Some quests aren't worth it. You found most of them.", { id: "abandonedMany" }),
    R("questDays", "J60", "quests", "procrastinators", "{quest} sat in your log for {n} days", "+", 7, 0.8, "The quest giver assumed you were dead."),
    R("groupQuests", "J61", "quests", "group questers", "{n} group and elite quests", "+", 22, 0.5, "\"Group recommended\" was never a warning to you."),
    R("dungeonQuests", "J62", "quests", "dungeon questers", "{n} dungeon quests completed", "+", 25, 0.5, "You actually remembered to pick up the dungeon quests."),

    // ---- Exploration and travel (#63-72, 101-102) ----
    R("zonesVisited", "J63", "travel", "wanderers", "visited {n} zones", "+", 30, 0.25, "There's very little fog left on your map."),
    R("subzones", "J64", "travel", "cartographers", "{n} places discovered", "+", 250, 0.3, "If it has a name, you've stood in it."),
    R("zoneTime", "J66", "travel", "{fav} locals", "{t} spent there", "+", 50000, 0.5, "{fav} should give you the key to the city."),
    R("zoneChanges", "J67", "travel", "zone hoppers", "{n} zone changes", "+", 400, 0.4, "You treated zone borders like revolving doors."),
    R("hearths", "J68", "travel", "homebodies", "hearthed home {n} times", "+", 115, 0.4, "Home is where the hearthstone is."),
    R("flightPaths", "J69", "travel", "flight path collectors", "{n} flight paths found", "+", 21, 0.25, "Every flight master knows your face."),
    R("flights", "J70", "travel", "flight path regulars", "{n} flights taken", "+", 90, 0.4, "Your gryphon has frequent flyer miles."),
    R("ground", "J71", "travel", "long-distance runners", "{n} miles on foot and mounted", "+", 460, 0.35, "Your boots have stories to tell."),
    R("air", "J71", "travel", "frequent flyers", "{n} miles by flight path", "+", 400, 0.5, "You've seen most of Azeroth from above."),
    R("graveyards", "J72", "travel", "graveyard tourists", "used {n} different graveyards", "+", 15, 0.4, "You've reviewed every graveyard in Azeroth. Mostly two stars."),
    R("fallen", "J101", "fun", "free fallers", "{n} yards fallen in all", "+", 8000, 0.6, "Parachutes are for the weak.", { family: "falls" }),
    R("longestFall", "J102", "fun", "daredevils", "survived a {n}-yard fall", "+", 35, 0.3, "Your knees would like a word.", { family: "falls" }),

    // ---- Dungeons (#73-75) ----
    R("dungeonsEntered", "J73", "dungeons", "dungeon regulars", "entered dungeons {n} times", "+", 60, 0.45, "You and the instance portal are on first-name terms."),
    R("dungeonTypes", "J73", "dungeons", "dungeon tourists", "{n} different dungeons", "+", 12, 0.3, "You collected dungeons like trading cards."),
    R("runs", "J74", "dungeons", "run finishers", "{n} dungeon runs completed", "+", 35, 0.5, "You didn't just go in. You finished."),
    R("fastRun", "J74", "dungeons", "speedrunners", "your fastest run took {t}", "-", 1800, 0.4, "In and out before the tank finished his speech."),

    // ---- Economy (#76-85) ----
    R("earned", "J77", "gold", "earners", "{g} earned", "+", 9000000, 0.4, "Goblins study your business model."),
    R("spent", "J77", "gold", "big spenders", "{g} spent", "+", 8000000, 0.4, "Vendors light candles in your honor."),
    R("lootGold", "J78", "gold", "coin collectors", "{g} looted from mobs", "+", 3000000, 0.4, "Every corpse checked, every copper pocketed."),
    R("vendorGold", "J79", "gold", "vendor whisperers", "{g} from selling to vendors", "+", 3500000, 0.4, "Gray items are just gold you haven't sold yet."),
    R("training", "J80", "gold", "eager students", "{g} spent on training", "+", 2200000, 0.2, "You never skipped a trainer visit."),
    R("repairs", "J81", "gold", "careful adventurers", "only {g} on repairs", "-", 1200000, 0.45, "Your armor is suspiciously intact."),
    R("repairs", "J81", "gold", "armor shredders", "{g} on repairs", "+", 1200000, 0.45, "Blacksmiths retire on your repair bills.", { id: "repairsMany" }),
    R("flightGold", "J82", "gold", "air fare payers", "{g} on flights", "+", 400000, 0.4, "Gryphons don't run on goodwill."),
    R("auctions", "J83", "gold", "auction house barons", "{g} from auctions", "+", 600000, 1, "The auction house is your second home."),
    R("auctionsSold", "J83", "gold", "merchants", "{n} auctions sold", "+", 60, 0.9, "Buy low, sell high, repeat."),
    R("auctionSpend", "J83", "gold", "bargain hunters", "{g} spent at the auction house", "+", 2500000, 0.6, "You kept the economy going single-handedly."),
    R("mount", "J84", "gold", "early riders", "first mount at level {n}", "-", 40, 0.06, "Walking is for people without a plan.", { min: 40 }),
    R("mountPlayed", "J84", "gold", "quick saddlers", "mounted after {t} /played", "-", 500000, 0.25, "Saddled up before most had worn in their boots.", { fixed: true }),
    R("peakGold", "J85", "gold", "hoarders", "{g} at your richest", "+", 1200000, 0.6, "A dragon would be jealous of that hoard."),
    R("saved", "J77", "gold", "savers", "{g} kept at {m}", "+", 800000, 0.8, "Ready for that epic mount. Almost."),

    // ---- Loot and gear (#86-90, 104) ----
    R("looted", "J86", "loot", "looters", "{n} items looted", "+", 3000, 0.3, "If it dropped, it's in your bags."),
    R("grays", "J87", "loot", "vendor trash collectors", "{n} gray items picked up", "+", 1250, 0.4, "One player's trash is another player's three copper."),
    R("greens", "J87", "loot", "green collectors", "{n} green items looted", "+", 500, 0.4, "Of the Monkey, of the Bear, of the Whale: all yours."),
    R("rareLoot", "J87", "loot", "treasure hunters", "{n} blue items looted", "+", 45, 0.5, "Blue drops follow you around."),
    R("epics", "J87", "loot", "epic finders", "{n} epic items looted", "+", 0.5, 0.9, "Purple, before {m}. Some people just have it."),
    R("bestItem", "J88", "loot", "loot legends", "best item looted: item level {n}", "+", 40, 0.15, "The drop rate gods smiled on you."),
    R("firstBlue", "J90", "loot", "early blues", "first blue at level {n}", "-", 22, 0.2, "Blue before most had their first green."),
    R("firstEpic", "J90", "loot", "early epics", "first epic at level {n}", "-", 55, 0.1, "Purple pixels, early."),
    R("worn", "J104", "loot", "gear loyalists", "{item} worn for {t}", "+", 108000, 0.6, "Why upgrade what already works?"),
    R("wornLevels", "J104", "loot", "faithful wearers", "{kept} stayed on for {d} levels", "+", 12, 0.5, "That item saw everything you saw."),
    // The character sheet as it was a few seconds after the milestone's
    // level-up (W-383..W-391), so the same for a journey exported there or
    // later (`fixed`). Health, power and crit against your own class.
    R("sheetIlvl", "W-390", "sheet", "best-geared", "average item level {d} at {m}", "+", 55, 0.12, "Dressed for the level after next.", { fixed: true, min: 1, max: 200 }),
    R("sheetIlvl", "W-390", "sheet", "best-geared", "average item level {d} at {m}", "+", 55, 0.12, "The sharpest-dressed of your class.", more({ id: "sheetIlvlClass", fixed: true, min: 1, max: 200 }, CLASS)),
    R("sheetHealth", "W-385", "sheet", "toughest", "{n} health at {m}", "+", 4200, 0.2, "Built to take a hit, and then another.", more({ fixed: true, max: 30000 }, CLASS)),
    R("sheetMana", "W-385", "sheet", "deepest wells", "{n} mana at {m}", "+", 4500, 0.25, "You ran out of mobs before you ran out of mana.",
      more({ fixed: true, max: 30000, only: { classToken: ["MAGE", "WARLOCK", "PRIEST", "DRUID", "SHAMAN", "PALADIN", "HUNTER"] } }, CLASS)),
    R("sheetAP", "W-386", "sheet", "hardest hitters", "{n} attack power at {m}", "+", 1000, 0.3, "Every swing a statement.",
      more({ fixed: true, max: 5000, only: { classToken: ["WARRIOR", "ROGUE", "HUNTER", "PALADIN", "SHAMAN", "DRUID"] } }, CLASS)),
    R("sheetSP", "W-386", "sheet", "strongest casters", "{n} spell power at {m}", "+", 250, 0.5, "Your spells land before the cast bar finishes.",
      more({ fixed: true, max: 2000, only: { classToken: ["MAGE", "WARLOCK", "PRIEST", "DRUID", "SHAMAN", "PALADIN"] } }, CLASS)),
    R("sheetCrit", "W-387", "sheet", "critical strikers", "{d}% crit chance at {m}", "+", 12, 0.35, "Big numbers, and often.", more({ fixed: true, max: 100 }, CLASS)),

    // ---- Professions and skills (#91-96, 103) ----
    R("crafted", "J93", "crafts", "crafters", "{n} items crafted", "+", 240, 0.7, "Your hands are never idle."),
    R("fish", "J94", "crafts", "anglers", "{n} fish caught", "+", 80, 1, "The fish of Azeroth whisper your name."),
    R("skillUps", "J96", "crafts", "weapon masters", "{n} weapon skill-ups", "+", 1100, 0.3, "You practiced every swing."),
    R("herbs", "J103", "crafts", "herbalists", "{n} herbs picked", "+", 400, 0.9, "Peacebloom fears you.", T("Herbalism")),
    R("ore", "J103", "crafts", "miners", "{n} ore nodes mined", "+", 350, 0.9, "You can hear a copper vein from three zones away.", T("Mining")),
    R("skinned", "J103", "crafts", "skinners", "{n} creatures skinned", "+", 650, 0.8, "Nothing goes to waste. Nothing.", T("Skinning")),
    R("maxed", "J92", "crafts", "master artisans", "{n} professions at 300 by level 60", "+", 1, 0.6, "Max level and max skill. Overachiever.", { at60: true }),

    // ---- Social and fun (#97-100) ----
    R("grouped", "J97", "social", "party people", "{p}% of your time in a group", "+", 25, 0.5, "Better together."),
    R("solo", "J97", "social", "lone wolves", "{p}% of your time solo", "+", 75, 0.12, "Who needs a party when you have yourself?"),
    R("groupedWith", "J98", "social", "socializers", "{n} different players grouped with", "+", 120, 0.5, "Half the server has you on their friends list."),
    R("guild", "J99", "social", "early guild joiners", "joined a guild at level {n}", "-", 18, 0.5, "Found your people early."),
    R("jumps", "J100", "fun", "jumpers", "{n} jumps", "+", 20000, 0.45, "Your space bar has filed a formal complaint."),
    R("jumpEvery", "J100", "fun", "bunny hoppers", "a jump every {n} seconds", "-", 25, 0.5, "Walking is just jumping with extra steps.", { family: "jumps" }),

    // ---- WoW Forever (wrapped W-001..W-021) ----
    R("zephras", "W-001", "forever", "quick fledglings", "left Zephras Isle at level {n}", "-", 10, 0.2, "The nest was nice, but the world was waiting.", { only: { race: "Skyborne" }, cohort: "race" }),
    R("hyjal", "W-006", "forever", "Hyjal pioneers", "reached Mount Hyjal {n} days after 60", "-", 5, 0.8, "You didn't even unpack at 60.", { at60: true, fixed: true }),
    R("forever", "W-007", "forever", "Forever explorers", "{n} new Forever quests done", "+", 55, 0.45, "You went looking for what's new, and found it."),
    R("camps", "W-008", "forever", "campers", "{n} campfires set up", "+", 10, 0.7, "Why pay for an inn when you can bring your own?"),
    R("campTime", "W-009", "forever", "fireside regulars", "{t} at campfires", "+", 7200, 0.6, "Marshmallows were toasted. Probably.", { family: "camps" }),
    R("campShops", "W-010", "forever", "camp shoppers", "{n} camp vendor visits", "+", 20, 0.8, "Shopping in the wilderness. Very civilized."),
    R("campBuffs", "W-011", "forever", "well-fed campers", "{n} camp buffs", "+", 30, 0.6, "The campfire takes care of its own."),
    R("campCrafts", "W-012", "forever", "camp builders", "{n} camping objects crafted", "+", 5, 0.9, "Home is wherever you set it up."),
    R("valthalak", "W-016", "forever", "Valthalak chasers", "{n} Lord Valthalak quests done", "+", 2, 0.9, "Bodley would be proud."),
    R("explored", "W-017", "forever", "map completionists", "{p}% of the world map explored", "+", 60, 0.25, "Fog of war? Never heard of it."),
    R("transmog", "W-019", "forever", "fashionistas", "{n} transmog changes", "+", 5, 0.9, "Fashion is the true endgame."),
    R("autoFlagged", "W-021", "pvp", "danger zone tourists", "flagged for PvP by a zone {n} times", "+", 25, 0.7, "You saw the red border and went anyway.", { only: { ruleset: "PvP" }, cohort: "ruleset" }),

    // ---- Warrior ----
    R("battleStance", "WAR-01", "class", "Battle Stance purists", "{t} in Battle Stance", "+", 200000, 0.4, "Why switch? Battle Stance never let you down.", C("WARRIOR")),
    R("defensiveStance", "WAR-01", "class", "shield walls", "{t} in Defensive Stance", "+", 60000, 0.7, "You were tanking before anyone asked.", C("WARRIOR")),
    R("berserkerStance", "WAR-01", "class", "berserkers", "{t} in Berserker Stance", "+", 40000, 0.8, "Rage isn't a resource. It's a lifestyle.", C("WARRIOR")),
    R("stanceSwaps", "WAR-02", "class", "stance dancers", "{n} stance swaps", "+", 2000, 0.6, "Your stance bar is worn smooth.", C("WARRIOR")),
    R("charges", "WAR-04", "class", "chargers", "{n} Charges and Intercepts", "+", 2500, 0.5, "Distance is just a suggestion.", C("WARRIOR")),
    R("overpowers", "WAR-05", "class", "opportunists", "{n} Overpowers", "+", 1500, 0.5, "Dodge? Not today.", C("WARRIOR")),
    R("executes", "WAR-06", "class", "executioners", "{n} Executes", "+", 800, 0.6, "Twenty percent health is your favorite number.", C("WARRIOR")),
    R("shouts", "WAR-07", "class", "loud ones", "{n} shouts", "+", 3000, 0.5, "The whole zone heard your Battle Shout.", C("WARRIOR")),
    R("sunders", "WAR-08", "class", "armor breakers", "{n} Sunder Armors and Rends", "+", 4000, 0.5, "Five stacks, or it didn't happen.", C("WARRIOR")),
    R("hamstrings", "WAR-09", "class", "runner catchers", "{n} Hamstrings and Piercing Howls", "+", 900, 0.6, "Fleeing mobs never got far.", C("WARRIOR")),
    R("panicButtons", "WAR-10", "class", "panic button pressers", "{n} Shield Walls, Last Stands and friends", "+", 60, 0.7, "You pressed every button in the emergency kit.", C("WARRIOR")),
    R("warriorInterrupts", "WAR-11", "class", "spell stoppers", "{n} Pummels and Shield Bashes", "+", 150, 0.7, "Casters hate this one trick.", C("WARRIOR")),
    R("cleaves", "WAR-12", "class", "cleavers", "{n} Thunder Claps, Cleaves and Whirlwinds", "+", 1500, 0.6, "Single target is for the weak.", C("WARRIOR")),
    R("weaponSwaps", "WAR-13", "class", "weapon jugglers", "{n} weapon swaps", "+", 300, 0.8, "Sword and board, two-hander, back again.", C("WARRIOR")),
    R("rage", "WAR-14", "class", "rage spenders", "{n} rage spent", "+", 150000, 0.4, "Calm is overrated.", C("WARRIOR")),
    R("whirlwindAxe", "WAR-15", "class", "Whirlwind Axe early birds", "Whirlwind Axe at level {n}", "-", 30, 0.1, "That quest chain is long. You made it look short.", C("WARRIOR", { min: 30 })),

    // ---- Paladin ----
    R("sealTime", "PAL-01", "class", "seal keepers", "{t} with a seal up", "+", 200000, 0.4, "Never without a seal. Never.", C("PALADIN")),
    R("judgements", "PAL-02", "class", "judges", "{n} Judgements", "+", 3000, 0.5, "Judgement was passed. A lot.", C("PALADIN")),
    R("auraTime", "PAL-03", "class", "aura bearers", "{t} with Devotion Aura up", "+", 300000, 0.3, "Your party felt safer standing near you.", C("PALADIN")),
    R("blessings", "PAL-04", "class", "blessing givers", "{n} Blessings cast on others", "+", 600, 0.8, "Kings for everyone!", C("PALADIN")),
    R("layOnHands", "PAL-05", "class", "last-ditch heroes", "{n} Lay on Hands", "+", 15, 0.7, "Saved a life. Maybe your own.", C("PALADIN")),
    R("bubbles", "PAL-06", "class", "bubble lovers", "{n} Divine Shields and Protections", "+", 80, 0.6, "Can't touch this.", C("PALADIN")),
    R("bubbleHearths", "PAL-07", "class", "bubble hearthers", "{n} bubble hearths", "+", 3, 1, "A classic for a reason.", C("PALADIN")),
    R("hammers", "PAL-08", "class", "stunners", "{n} Hammers of Justice", "+", 500, 0.6, "Stop. Hammer time.", C("PALADIN")),
    R("paladinHeals", "PAL-09", "class", "Holy Light shiners", "{n} heals cast", "+", 2500, 0.6, "Even the Light is impressed.", C("PALADIN")),
    R("redemptions", "PAL-10", "class", "redeemers", "{n} Redemptions", "+", 15, 0.8, "Death was only a minor setback for your friends.", C("PALADIN")),
    R("exorcisms", "PAL-11", "class", "exorcists", "{n} Exorcisms and Turn Undeads", "+", 400, 0.7, "The undead have filed a complaint.", C("PALADIN")),
    R("consecrations", "PAL-12", "class", "holy ground keepers", "{n} Consecrations", "+", 600, 0.8, "The ground you walk on is literally holy.", C("PALADIN")),
    R("cleanses", "PAL-13", "class", "cleansers", "{n} Cleanses and Purifies", "+", 200, 0.8, "Poison? Disease? Not on your watch.", C("PALADIN")),
    R("warhorse", "PAL-14", "class", "warhorse riders", "{n} Warhorse summons", "+", 400, 0.6, "Your steed comes when called.", C("PALADIN")),

    // ---- Hunter ----
    R("ammo", "HUN-01", "class", "sharpshooters", "{n} arrows and bullets fired", "+", 40000, 0.4, "The quiver never empties. Well, almost.", C("HUNTER")),
    R("ammoGold", "HUN-02", "class", "ammo buyers", "{g} on ammo", "+", 300000, 0.5, "Arrows aren't free, sadly.", C("HUNTER")),
    R("outOfAmmo", "HUN-03", "class", "empty quivers", "ran out of ammo {n} times", "+", 4, 0.9, "Melee hunter, by necessity.", C("HUNTER")),
    R("tamed", "HUN-04", "class", "beast collectors", "{n} pets tamed", "+", 8, 0.6, "The stable master needs a bigger stable.", C("HUNTER")),
    R("petTime", "HUN-05", "class", "pet loyalists", "{t} with your favorite pet", "+", 300000, 0.4, "Best friend, best tank.", C("HUNTER")),
    R("petDeaths", "HUN-06", "class", "pet resurrectors", "{n} pet deaths", "+", 60, 0.6, "Your pet has seen the other side. Repeatedly.", C("HUNTER")),
    R("feeds", "HUN-08", "class", "pet chefs", "fed your pet {n} times", "+", 400, 0.6, "A happy pet is a loyal pet.", C("HUNTER")),
    R("mends", "HUN-09", "class", "pet medics", "{n} Mend Pets", "+", 600, 0.6, "Your pet's health is your health.", C("HUNTER")),
    R("hawk", "HUN-10", "class", "hawk eyes", "{t} in Aspect of the Hawk", "+", 200000, 0.4, "Sharp eyes, sharper arrows.", C("HUNTER")),
    R("cheetah", "HUN-10", "class", "speedsters", "{t} in Aspect of the Cheetah", "+", 60000, 0.6, "Dazed? Worth it.", C("HUNTER")),
    R("feigns", "HUN-11", "class", "actors", "{n} Feign Deaths", "+", 300, 0.7, "And the award goes to...", C("HUNTER")),
    R("traps", "HUN-12", "class", "trappers", "{n} traps laid", "+", 200, 0.8, "The ground was never safe around you.", C("HUNTER")),
    R("shots", "HUN-13", "class", "shot callers", "{n} special shots", "+", 6000, 0.5, "Aimed, Arcane, Multi: you used them all.", C("HUNTER")),
    R("marks", "HUN-14", "class", "markers", "{n} Hunter's Marks", "+", 2000, 0.6, "Nothing escapes your mark.", C("HUNTER")),

    // ---- Rogue ----
    R("stealth", "ROG-01", "class", "shadows", "{t} in Stealth", "+", 60000, 0.5, "Nobody saw you. Nobody ever does.", C("ROGUE")),
    R("openers", "ROG-02", "class", "ambushers", "{n} openers", "+", 3000, 0.5, "Every fight started on your terms.", C("ROGUE")),
    R("pickPockets", "ROG-03", "class", "pickpockets", "{n} pockets picked", "+", 800, 0.8, "Your fingers are lighter than air.", C("ROGUE")),
    R("pocketGold", "ROG-03", "class", "light-fingered earners", "{g} from pockets", "+", 200000, 0.8, "Crime pays. In copper.", C("ROGUE")),
    R("locks", "ROG-04", "class", "safecrackers", "{n} locks picked", "+", 100, 0.9, "No box can keep you out.", C("ROGUE")),
    R("poisons", "ROG-05", "class", "poisoners", "{n} poisons applied", "+", 800, 0.5, "Every blade comes with a side effect.", C("ROGUE")),
    R("finishers", "ROG-07", "class", "Eviscerate enthusiasts", "{n} finishing moves", "+", 4000, 0.5, "Five combo points, one very bad day for them.", C("ROGUE")),
    R("comboPoints", "ROG-08", "class", "patient finishers", "{d} combo points per finisher", "+", 3.6, 0.12, "You wait for five. Always.", C("ROGUE", { max: 5 })),
    R("escapes", "ROG-09", "class", "escape artists", "{n} Vanishes, Sprints and Evasions", "+", 300, 0.6, "Now you see me...", C("ROGUE")),
    R("kicks", "ROG-10", "class", "kickers", "{n} Kicks", "+", 400, 0.6, "Spellcasting is a privilege you revoke.", C("ROGUE")),
    R("blinds", "ROG-11", "class", "blinders", "{n} Gouges and Blinds", "+", 300, 0.7, "They never saw it coming. Literally.", C("ROGUE")),
    R("stabs", "ROG-13", "class", "sinister strikers", "{n} Sinister Strikes and Backstabs", "+", 15000, 0.4, "Stab, stab, stab, Eviscerate.", C("ROGUE")),

    // ---- Priest ----
    R("shields", "PRI-01", "class", "shield givers", "{n} Power Word: Shields", "+", 3000, 0.5, "Weakened Soul is a badge of honor.", C("PRIEST")),
    R("priestHeals", "PRI-02", "class", "heal slingers", "{n} heals cast", "+", 5000, 0.5, "Your party never knew how close it came.", C("PRIEST")),
    R("resurrections", "PRI-03", "class", "resurrectors", "{n} Resurrections", "+", 30, 0.7, "Death is basically your coworker.", C("PRIEST")),
    R("fortitudes", "PRI-04", "class", "buff bots", "{n} Fortitudes on others", "+", 800, 0.7, "Free Stamina for everyone you passed.", C("PRIEST")),
    R("shadowform", "PRI-05", "class", "shadow dwellers", "{t} in Shadowform", "+", 100000, 0.8, "The Light? Never heard of her.", C("PRIEST")),
    R("shadowSpells", "PRI-06", "class", "mind melters", "{n} Shadow Word: Pains, Mind Blasts and Flays", "+", 8000, 0.5, "Minds were blasted. Thoroughly.", C("PRIEST")),
    R("screams", "PRI-07", "class", "screamers", "{n} Psychic Screams and Fades", "+", 400, 0.7, "AAAAAH! (That's the Fear.)", C("PRIEST")),
    R("mindControls", "PRI-08", "class", "puppet masters", "{n} Mind Controls", "+", 40, 0.9, "Why fight them when you can be them?", C("PRIEST")),
    R("levitates", "PRI-09", "class", "floaters", "{n} Levitates", "+", 50, 0.9, "Gravity is optional for you.", C("PRIEST")),
    R("wandShots", "PRI-12", "class", "wand wavers", "{n} wand shots", "+", 5000, 0.6, "Pew. Pew pew.", C("PRIEST")),
    R("holyNovas", "PRI-14", "class", "nova bursters", "{n} Holy Novas", "+", 100, 1, "Hold on, I'll light everyone up.", C("PRIEST")),
    R("priestMana", "PRI-15", "class", "mana spenders", "{n} mana spent", "+", 2000000, 0.5, "Drink, cast, drink, cast.", C("PRIEST")),

    // ---- Shaman ----
    R("totems", "SHA-01", "class", "totem planters", "{n} totems dropped", "+", 4000, 0.5, "Your totems could fill a forest.", C("SHAMAN")),
    R("ghostWolf", "SHA-04", "class", "ghost wolves", "{t} in Ghost Wolf", "+", 60000, 0.6, "Four legs good.", C("SHAMAN")),
    R("reincarnations", "SHA-05", "class", "reincarnators", "{n} Reincarnations", "+", 15, 0.7, "Death? Already used my Ankh.", C("SHAMAN")),
    R("imbues", "SHA-06", "class", "weapon imbuers", "{n} weapon imbues", "+", 800, 0.5, "Windfury! (We all heard it.)", C("SHAMAN")),
    R("shocks", "SHA-07", "class", "shockers", "{n} shocks", "+", 3000, 0.5, "Earth Shock, right to the face.", C("SHAMAN")),
    R("lightning", "SHA-08", "class", "storm callers", "{n} Lightning Bolts and Chain Lightnings", "+", 5000, 0.5, "The sky answers to you.", C("SHAMAN")),
    R("shamanHeals", "SHA-09", "class", "wave healers", "{n} Healing Waves and Chain Heals", "+", 2500, 0.6, "Chain Heal bounces, you take the credit.", C("SHAMAN")),
    R("lightningShields", "SHA-10", "class", "living batteries", "{n} Lightning Shields", "+", 1500, 0.6, "Touch me and find out.", C("SHAMAN")),
    R("astralRecalls", "SHA-11", "class", "double hearthers", "{n} Astral Recalls", "+", 40, 0.7, "Two hearthstones? Yes please.", C("SHAMAN")),
    R("ancestralSpirits", "SHA-12", "class", "spirit callers", "{n} Ancestral Spirits", "+", 20, 0.8, "The ancestors work overtime for you.", C("SHAMAN")),
    R("waterWalks", "SHA-14", "class", "water walkers", "{n} Water Walkings and Breathings", "+", 60, 0.9, "Lakes are just very wet roads.", C("SHAMAN")),

    // ---- Mage ----
    R("conjured", "MAG-01", "class", "water bakers", "{n} drinks conjured", "+", 2500, 0.6, "Water? Water. WATER?", C("MAGE")),
    R("conjuredFood", "MAG-02", "class", "bread bakers", "{n} food conjured", "+", 1200, 0.6, "Muffins for everyone.", C("MAGE")),
    R("givenAway", "MAG-03", "class", "generous mages", "{n} conjured items given away", "+", 400, 0.9, "Your party never had to buy water.", C("MAGE")),
    R("teleports", "MAG-04", "class", "teleporters", "{n} teleports", "+", 80, 0.6, "Walking is for other classes.", C("MAGE")),
    R("portals", "MAG-05", "class", "portal taxis", "{n} portals cast", "+", 30, 1, "Tips appreciated.", C("MAGE")),
    R("polymorphs", "MAG-07", "class", "sheep makers", "{n} Polymorphs", "+", 600, 0.7, "Baa.", C("MAGE")),
    R("novas", "MAG-08", "class", "frost novas", "{n} Frost Novas, Blinks and Ice Blocks", "+", 3000, 0.5, "Nova, blink, repeat. A classic.", C("MAGE")),
    R("counterspells", "MAG-09", "class", "counterspellers", "{n} Counterspells", "+", 200, 0.7, "Spells cancelled. Dreams too.", C("MAGE")),
    R("intellects", "MAG-10", "class", "brain buffers", "{n} Arcane Intellects on others", "+", 500, 0.8, "Everyone's smarter around you.", C("MAGE")),
    R("evocations", "MAG-11", "class", "evokers", "{n} Evocations", "+", 100, 0.7, "Recharging... please wait.", C("MAGE")),
    R("manaGems", "MAG-12", "class", "gem crafters", "{n} mana gems used", "+", 150, 0.8, "Shiny and refreshing.", C("MAGE")),
    R("fireballs", "MAG-13", "class", "pyromancers", "{n} Fireballs", "+", 6000, 0.8, "Some mages just want to watch the world burn.", C("MAGE")),
    R("frostbolts", "MAG-13", "class", "frost mages", "{n} Frostbolts", "+", 8000, 0.7, "Chill out.", C("MAGE")),
    R("mageAoE", "MAG-14", "class", "AoE farmers", "{n} Arcane Explosions and Blizzards", "+", 3000, 0.9, "Why kill one when you can kill twelve?", C("MAGE")),
    R("slowFalls", "MAG-15", "class", "featherfallers", "{n} Slow Falls", "+", 80, 0.9, "Gravity bows to you.", C("MAGE")),

    // ---- Warlock ----
    R("shards", "WLK-01", "class", "soul collectors", "{n} soul shards gathered", "+", 800, 0.5, "Your bags are full of other people's souls.", C("WARLOCK")),
    R("shardsPeak", "WLK-03", "class", "shard hoarders", "{n} soul shards held at once", "+", 28, 0.3, "Bag space? Who needs bag space?", C("WARLOCK")),
    R("healthstonesMade", "WLK-04", "class", "cookie bakers", "{n} healthstones made", "+", 150, 0.7, "Cookies for the whole group.", C("WARLOCK")),
    R("soulstones", "WLK-06", "class", "soulstoners", "{n} soulstones made", "+", 30, 0.8, "An insurance policy, signed and sealed.", C("WARLOCK")),
    R("selfRez", "WLK-07", "class", "self-resurrectors", "{n} times your own soulstone brought you back", "+", 4, 0.9, "You came back. Of course you did.", C("WARLOCK")),
    R("summonings", "WLK-09", "class", "summoners", "{n} Rituals of Summoning", "+", 30, 0.9, "Click the portal. Click it!", C("WARLOCK")),
    R("demonsSummoned", "WLK-10", "class", "demon tamers", "{n} demons summoned", "+", 600, 0.5, "Your minions have minions.", C("WARLOCK")),
    R("voidwalker", "WLK-11", "class", "Voidwalker loyalists", "{t} with your Voidwalker", "+", 250000, 0.5, "Blue, loyal and very good at being hit.", C("WARLOCK")),
    R("demonDeaths", "WLK-12", "class", "demon expenders", "{n} demon deaths", "+", 80, 0.6, "There are plenty more in the Twisting Nether.", C("WARLOCK")),
    R("lifeTaps", "WLK-14", "class", "life tappers", "{n} Life Taps", "+", 6000, 0.5, "Health is just mana you haven't tapped yet.", C("WARLOCK")),
    R("fears", "WLK-15", "class", "fear mongers", "{n} Fears, Howls and Death Coils", "+", 1500, 0.6, "Run, little mob, run.", C("WARLOCK")),
    R("dots", "WLK-16", "class", "DoT stackers", "{n} Corruptions, Curses and Immolates", "+", 15000, 0.5, "Apply, wait, loot.", C("WARLOCK")),
    R("felsteed", "WLK-19", "class", "Felsteed riders", "{n} Felsteed summons", "+", 400, 0.6, "Flaming hooves, coming through.", C("WARLOCK")),

    // ---- Druid ----
    R("cat", "DRU-01", "class", "Cat Form loyalists", "{t} in Cat Form", "+", 108000, 0.4, "If it fits, you sits. In Cat Form.", C("DRUID")),
    R("bear", "DRU-01", "class", "bears", "{t} in Bear Form", "+", 60000, 0.6, "Fuzzy, sturdy and not to be poked.", C("DRUID")),
    R("travelForm", "DRU-01", "class", "travel formers", "{t} in Travel Form", "+", 40000, 0.5, "Who needs a mount?", C("DRUID")),
    R("aquatic", "DRU-01", "class", "seals", "{t} in Aquatic Form", "+", 4000, 0.8, "Most at home in the water.", C("DRUID")),
    R("casterForm", "DRU-01", "class", "caster purists", "{t} in caster form", "+", 250000, 0.3, "Robes over fur.", C("DRUID")),
    R("shifts", "DRU-02", "class", "shapeshifters", "{n} shapeshifts", "+", 5000, 0.5, "Bear, cat, bear, cat, travel, cat.", C("DRUID")),
    R("prowl", "DRU-04", "class", "prowlers", "{t} in Prowl", "+", 10800, 0.7, "Stealthy kitty, sneaky kitty.", C("DRUID")),
    R("healing", "ALL-13", "class", "healers", "{n} healing done", "+", 900000, 0.6, "Somebody had to keep everyone alive. Usually you.", C(["DRUID", "PRIEST", "PALADIN", "SHAMAN"], { family: "healing" })),
    R("rebirths", "DRU-06", "class", "battle rezzers", "{n} Rebirths and Innervates", "+", 40, 0.8, "Back on your feet, mid-fight.", C("DRUID")),
    R("wildMarks", "DRU-07", "class", "gift givers", "{n} Marks of the Wild on others", "+", 800, 0.7, "Everyone gets a paw print.", C("DRUID")),
    R("moonfires", "DRU-08", "class", "moonfirers", "{n} Wraths and Moonfires", "+", 6000, 0.6, "Moonfire spam is a valid strategy.", C("DRUID")),
    R("catAbilities", "DRU-09", "class", "claws out", "{n} cat abilities", "+", 20000, 0.5, "Shred, Rake, Rip. Kitty's angry.", C("DRUID")),
    R("bearAbilities", "DRU-10", "class", "maulers", "{n} bear abilities", "+", 5000, 0.7, "Maul now, ask questions later.", C("DRUID")),
    R("roots", "DRU-11", "class", "gardeners", "{n} Entangling Roots and Hibernates", "+", 1200, 0.6, "Stay. Right. There.", C("DRUID")),
    R("moonglade", "DRU-12", "class", "Moonglade commuters", "{n} teleports to Moonglade", "+", 30, 0.8, "The druids of Moonglade know you by name.", C("DRUID")),
    R("faerieFires", "DRU-13", "class", "fairy lights", "{n} Faerie Fires", "+", 2000, 0.6, "Sparkly, and armor-shredding.", C("DRUID")),

    // ---- Every class (ALL-01..ALL-12) ----
    R("bandages", "ALL-01", "consumables", "bandage users", "{n} bandages used", "+", 200, 0.7, "Self-sufficient. Slightly sticky."),
    R("healPotions", "ALL-02", "consumables", "potion drinkers", "{n} healing potions", "+", 60, 0.7, "Glug, glug, still alive."),
    R("manaPotions", "ALL-02", "consumables", "mana sippers", "{n} mana potions", "+", 40, 0.8, "Blue tastes better."),
    R("cookies", "ALL-03", "consumables", "cookie eaters", "{n} warlock healthstones eaten", "+", 15, 0.8, "The warlock's cookies are the best cookies."),
    R("mageFood", "ALL-04", "consumables", "mage food fans", "{n} conjured food and drinks", "+", 120, 0.8, "Why buy water when mages exist?"),
    R("food", "ALL-05", "consumables", "foodies", "{n} food and drinks", "+", 800, 0.5, "Nom.", { family: "food" }),
    R("buffs", "ALL-06", "social", "buff magnets", "{n} buffs from other players", "+", 400, 0.6, "People just like buffing you."),
    R("summoned", "ALL-08", "social", "summoned travelers", "summoned {n} times", "+", 10, 0.8, "Why walk when warlocks exist?"),
    R("racials", "ALL-09", "class", "proud ancestry", "{n} racial abilities used", "+", 300, 0.8, "Your heritage is a cooldown.", CLASS),
    R("trainerVisits", "ALL-11", "class", "trainer regulars", "{n} class trainer visits", "+", 30, 0.25, "Always first in line for the new ranks.", CLASS),
    R("classQuests", "ALL-12", "class", "class questers", "{n} class quests completed", "+", 10, 0.4, "Your trainer is very proud.", CLASS),

    // ---- The game's Statistics pane (wrapped W-501..W-508) ----
    // Combat
    R("largestHit", "P-193", "combat", "heavy hitters", "one hit for {n}", "+", 1800, 0.35, "Someone felt that one in the next zone."),
    R("largestHitTaken", "P-527", "combat", "punching bags", "took a {n}-damage hit", "+", 1500, 0.4, "And you lived to tell the tale."),
    R("damageDone", "P-197", "combat", "damage dealers", "{n} damage done", "+", 3000000, 0.4, "Numbers went up. A lot."),
    R("damageTaken", "P-528", "combat", "damage sponges", "{n} damage taken", "+", 2500000, 0.4, "Ouch, cumulatively."),
    R("largestHeal", "P-189", "combat", "big healers", "one heal for {n}", "+", 1200, 0.5, "One big heal, one very grateful friend."),
    R("largestHealTaken", "P-829", "combat", "lucky receivers", "healed for {n} at once", "+", 1500, 0.5, "Somebody really loved you."),
    R("healingDone", "P-198", "combat", "healing pros", "{n} healing done", "+", 600000, 0.8, "Every health bar you touched went up.", { family: "healing" }),
    R("healingTaken", "P-830", "combat", "well-healed", "{n} healing received", "+", 800000, 0.6, "Healers kept you upright."),
    R("critters", "P-108", "fun", "critter menaces", "{n} critters killed", "+", 15, 0.8, "No rabbit was safe."),
    R("creatureTypes", "P-1337", "combat", "variety hunters", "{n} creature types killed", "+", 10, 0.2, "A little bit of everything."),
    R("allKills", "P-1197", "combat", "creature cullers", "{n} kills of every kind", "+", 9000, 0.3, "If it moved, it was a target.", { family: "kills" }),
    // Deaths
    R("drownings", "P-112", "deaths", "deep divers", "{n} deaths from drowning", "+", 0.5, 0.9, "Breath bar? What breath bar?"),
    R("hoggerDeaths", "P-594", "deaths", "Hogger's victims", "{n} deaths to Hogger", "+", 0.4, 1, "Hogger remembers. Hogger always remembers."),
    R("fatigueDeaths", "P-113", "deaths", "open sea explorers", "{n} deaths from fatigue", "+", 0.3, 0.9, "There's nothing out there. You checked."),
    R("lavaDeaths", "P-115", "deaths", "lava waders", "{n} deaths from fire and lava", "+", 0.4, 0.9, "The floor really was lava."),
    R("raidDeaths10", "P-917", "deaths", "raid floor inspectors", "{n} deaths in 10-player raids", "+", 0.3, 0.9, "Raid floors are comfy."),
    R("raidDeaths20", "P-64183", "deaths", "20-player raid casualties", "{n} deaths in 20-player raids", "+", 0.3, 0.9, "Twenty people saw it happen."),
    R("raidDeaths40", "P-64185", "deaths", "40-player raid casualties", "{n} deaths in 40-player raids", "+", 0.3, 0.9, "Thirty-nine people saw it happen."),
    R("avDeaths", "P-57", "pvp", "Alterac Valley casualties", "{n} deaths in Alterac Valley", "+", 10, 1, "Alterac is cold. And deadly."),
    R("abDeaths", "P-59", "pvp", "Arathi Basin casualties", "{n} deaths in Arathi Basin", "+", 8, 1, "Every flag had a price."),
    R("wsgDeaths", "P-56", "pvp", "Warsong Gulch casualties", "{n} deaths in Warsong Gulch", "+", 8, 1, "The flag was worth it. Probably."),
    R("drekDeaths", "P-58", "pvp", "Drek'Thar's victims", "{n} deaths to Drek'Thar", "+", 0.5, 1, "He's old, but he's mean.", F("Alliance")),
    R("diDeaths", "P-64182", "pvp", "Darkspear Islands casualties", "{n} deaths in Darkspear Islands", "+", 6, 1, "Paradise has teeth."),
    // Resurrection
    R("priestRez", "P-796", "deaths", "priests' favorite patients", "resurrected by priests {n} times", "+", 3, 0.9, "Priests keep a file on you."),
    R("druidRebirth", "P-798", "deaths", "battle-rezzed heroes", "rebirthed by druids {n} times", "+", 0.5, 1.2, "Mid-fight resurrections, your specialty."),
    R("druidRevive", "P-1229", "deaths", "druid-revived", "revived by druids {n} times", "+", 1, 1.1, "Nature brought you back."),
    R("shamanRez", "P-799", "deaths", "shaman-revived", "spirit returned by shamans {n} times", "+", 2, 1, "The ancestors sent you back."),
    R("paladinRez", "P-800", "deaths", "paladin-redeemed", "redeemed by paladins {n} times", "+", 2, 1, "The Light has plans for you."),
    R("soulstoneRez", "P-801", "deaths", "soulstone users", "brought back by soulstones {n} times", "+", 0.5, 1.2, "A warlock's insurance paid out."),
    // Character (the pane's "average quests completed per day" and "average
    // gold earned per day" aren't here: on Forever they hold the totals)
    R("respecs", "P-1149", "class", "talent rethinkers", "{n} talent respecs", "+", 2, 0.9, "Your talent tree has been replanted a few times.", CLASS),
    // Wealth
    R("auctionsPosted", "P-329", "gold", "auction posters", "{n} auctions posted", "+", 80, 1, "The auction house is basically your shop."),
    R("auctionsBought", "P-330", "gold", "auction shoppers", "{n} auction purchases", "+", 40, 1, "Why farm when you can buy?"),
    R("biggestBid", "P-331", "gold", "high rollers", "{g} on a single bid", "+", 200000, 1, "Go big or go home."),
    R("biggestSale", "P-332", "gold", "jackpot sellers", "{g} for a single auction", "+", 300000, 1, "Somebody really wanted that."),
    R("barber", "P-1147", "gold", "makeover fans", "{g} at the barber", "+", 10000, 1.2, "New hair, new you."),
    R("postage", "P-1148", "gold", "pen pals", "{g} on postage", "+", 2000, 1, "You keep the mail carriers busy."),
    R("respecGold", "P-1150", "gold", "respec spenders", "{g} on talent respecs", "+", 50000, 1, "Finding yourself is expensive."),
    // Player vs. player
    R("duelsWon", "P-319", "pvp", "duelists", "{n} duels won", "+", 8, 1, "Outside Ironforge, they still talk about you.", { family: "duels" }),
    R("duelsLost", "P-320", "pvp", "duel enthusiasts", "{n} duels lost", "+", 6, 1, "You lose some, you lose some more.", { family: "duels" }),
    R("worldHonor", "P-381", "pvp", "world PvP hunters", "{n} world honorable kills", "+", 30, 1, "The whole world is your battleground."),
    R("bgHonor", "P-382", "pvp", "battleground slayers", "{n} battleground honorable kills", "+", 50, 1.2, "Graveyard campers fear you."),
    R("avHonor", "P-1113", "pvp", "Alterac slayers", "{n} honorable kills in Alterac Valley", "+", 30, 1.2, "Frostwolf or Stormpike, they all fell.", { family: "bgHonor" }),
    R("abHonor", "P-1114", "pvp", "Arathi slayers", "{n} honorable kills in Arathi Basin", "+", 20, 1.2, "Guarding the Blacksmith with extreme prejudice.", { family: "bgHonor" }),
    R("wsgHonor", "P-1115", "pvp", "Warsong slayers", "{n} honorable kills in Warsong Gulch", "+", 20, 1.2, "Midfield was your office.", { family: "bgHonor" }),
    R("diHonor", "P-64180", "pvp", "Darkspear slayers", "{n} honorable kills in Darkspear Islands", "+", 15, 1.2, "The islands ran red.", { family: "bgHonor" }),
    R("killingBlows", "P-1487", "pvp", "killing blow dealers", "{n} killing blows", "+", 30, 1.2, "You always land the last hit.", { family: "killingBlows" }),
    R("worldKillingBlows", "P-1488", "pvp", "world finishers", "{n} world killing blows", "+", 20, 1.2, "Out in the world, you finished what others started.", { family: "killingBlows" }),
    R("bgKillingBlows", "P-1491", "pvp", "battleground finishers", "{n} battleground killing blows", "+", 15, 1.2, "Last hit, every time.", { family: "killingBlows" }),
    R("bgsPlayed", "P-839", "pvp", "battleground regulars", "{n} battlegrounds played", "+", 20, 1.2, "The queue pops, you answer."),
    R("bgsWon", "P-840", "pvp", "battleground winners", "{n} battlegrounds won", "+", 10, 1.2, "Victory tastes like honor points."),
    R("avBattles", "P-53", "pvp", "Alterac veterans", "{n} Alterac Valley battles", "+", 6, 1.2, "Hours of your life spent in that valley. Worth it.", { family: "av" }),
    R("avWins", "P-49", "pvp", "Alterac victors", "{n} Alterac Valley victories", "+", 3, 1.2, "Vanndar and Drek'Thar both know your name.", { family: "av" }),
    R("abBattles", "P-55", "pvp", "Arathi regulars", "{n} Arathi Basin battles", "+", 6, 1.2, "Farm, Stables, Mine, Blacksmith, Lumber Mill: seen them all.", { family: "ab" }),
    R("abWins", "P-51", "pvp", "Arathi victors", "{n} Arathi Basin victories", "+", 3, 1.2, "Two thousand resources, again and again.", { family: "ab" }),
    R("wsgBattles", "P-52", "pvp", "Warsong regulars", "{n} Warsong Gulch battles", "+", 6, 1.2, "You know every tunnel by heart.", { family: "wsg" }),
    R("wsgWins", "P-105", "pvp", "Warsong victors", "{n} Warsong Gulch victories", "+", 3, 1.2, "Three caps, one happy team.", { family: "wsg" }),
    R("diBattles", "P-64179", "pvp", "Darkspear Islands regulars", "{n} Darkspear Islands battles", "+", 5, 1.2, "Forever's newest battleground is your old haunt.", { family: "di" }),
    R("diWins", "P-64176", "pvp", "Darkspear Islands victors", "{n} Darkspear Islands victories", "+", 2, 1.2, "The islands bow to you.", { family: "di" }),
    R("towersDefended", "P-393", "pvp", "tower defenders", "{n} Alterac towers defended", "+", 1, 1.2, "The tower still stands because you stood."),
    R("towersCaptured", "P-394", "pvp", "tower takers", "{n} Alterac towers captured", "+", 2, 1.2, "Burn it down, take it over."),
    R("flagsCaptured", "P-395", "pvp", "flag runners", "{n} Warsong flags captured", "+", 1, 1.2, "Run, run, cap!"),
    R("flagsReturned", "P-586", "pvp", "flag savers", "{n} Warsong flags returned", "+", 2, 1.2, "Not today, flag carrier."),
    // Dungeons and raids
    R("raids10", "P-933", "dungeons", "small-raid regulars", "{n} 10-player raids entered", "+", 0.3, 0.8, "Ten people, one plan, many wipes."),
    R("raids20", "P-934", "dungeons", "20-player raiders", "{n} 20-player raids entered", "+", 0.3, 0.8, "Twenty players, one loot table."),
    R("raids40", "P-64184", "dungeons", "40-player raiders", "{n} 40-player raids entered", "+", 0.3, 0.8, "Forty people and somehow you were on time."),
    R("mograine", "P-1093", "bosses", "Mograine slayers", "{n} Scarlet Commander Mograine kills", "+", 3, 0.9, "The Scarlet Commander had a very bad month."),
    R("vanCleefKills", "P-63570", "bosses", "VanCleef slayers", "{n} Edwin VanCleef kills", "+", 3, 0.8, "The Defias Brotherhood is short one leader. Again.", { family: "vanCleef" }),
    R("rathmael", "P-63571", "bosses", "Rath'mael slayers", "{n} Rath'mael kills", "+", 1, 1, "The ruins of Lordaeron are a little quieter."),
    R("archmageShade", "P-63572", "bosses", "ghostbusters of Dalaran", "{n} Shade of the Archmage kills", "+", 1, 1, "Dalaran's ghosts lock their doors at night."),
    R("lyn", "P-63589", "bosses", "Lyn's slayers", "{n} Lyn the Ignored kills", "+", 1, 1, "Lyn the Ignored was not ignored by you."),
    R("dirgehammer", "P-63573", "bosses", "Dirgehammer breakers", "{n} Durgen Dirgehammer kills", "+", 1, 1, "The Hall of Thanes sings about you now."),
    R("nanaya", "P-63574", "bosses", "Nanaya slayers", "{n} Nanaya kills", "+", 1, 1, "Shaper's Terrace remembers."),
    R("blazeroar", "P-63575", "bosses", "Blazeroar's wardens", "{n} Blazeroar kills", "+", 1, 1, "Alcaz Prison's worst inmate met its warden."),
    R("wildKing", "P-63580", "bosses", "kingslayers", "{n} Wild King kills", "+", 1, 1, "Long live the king? Not this one."),
    R("darkhallow", "P-63581", "bosses", "Darkhallow slayers", "{n} Sonya Darkhallow kills", "+", 1, 1, "The Barrow Deeps are a little brighter."),
    R("bazzalan", "P-15027", "bosses", "Bazzalan slayers", "{n} Bazzalan kills", "+", 2, 0.8, "Ragefire Chasm has a vacancy.", F("Horde")),
    R("mutanus", "P-15028", "bosses", "Mutanus slayers", "{n} Mutanus the Devourer kills", "+", 2, 0.8, "The Nightmare is over. For now."),
    R("arugal", "P-1092", "bosses", "Arugal slayers", "{n} Archmage Arugal kills", "+", 2, 0.8, "Shadowfang Keep's worgen have no master now."),
    R("thredd", "P-15029", "bosses", "Stockade wardens", "{n} Bazil Thredd kills", "+", 2, 0.8, "Order restored in the Stockade.", F("Alliance")),
    R("akumai", "P-6137", "bosses", "Aku'mai slayers", "{n} Aku'mai kills", "+", 1.5, 0.8, "Blackfathom Deeps is safe for swimming."),
    R("charlga", "P-6139", "bosses", "Charlga slayers", "{n} Charlga Razorflank kills", "+", 1.5, 0.8, "The quilboar need a new leader."),
    R("thermaplugg", "P-6140", "bosses", "Thermaplugg breakers", "{n} Mekgineer Thermaplugg kills", "+", 1, 0.9, "Gnomeregan's traitor got what he had coming."),
    R("amnennar", "P-6141", "bosses", "Amnennar slayers", "{n} Amnennar the Coldbringer kills", "+", 1, 0.9, "The Coldbringer has been put on ice."),
    R("whitemane", "P-6786", "bosses", "Whitemane slayers", "{n} High Inquisitor Whitemane kills", "+", 2, 0.9, "Arise, champions? Not anymore."),
    R("archaedas", "P-6142", "bosses", "Archaedas breakers", "{n} Archaedas kills", "+", 1, 0.9, "The titans' watcher has stood down."),
    R("ukorz", "P-1094", "bosses", "Sandscalp slayers", "{n} Chief Ukorz Sandscalp kills", "+", 1.5, 0.9, "Zul'Farrak's chief has some stairs to answer for."),
    R("theradras", "P-6143", "bosses", "Theradras slayers", "{n} Princess Theradras kills", "+", 1, 0.9, "Maraudon's waters run clean again."),
    R("eranikus", "P-6144", "bosses", "Eranikus slayers", "{n} Shade of Eranikus kills", "+", 1, 0.9, "The Sunken Temple's dragon finally rests."),
    R("thaurissan", "P-1095", "bosses", "Thaurissan slayers", "{n} Emperor Dagran Thaurissan kills", "+", 0.8, 0.7, "The Emperor's reign is over."),
    R("gordok", "P-6146", "bosses", "Gordok slayers", "{n} King Gordok kills", "+", 0.8, 0.7, "Long live the new king: you."),
    R("wyrmthalak", "P-6145", "bosses", "Wyrmthalak slayers", "{n} Overlord Wyrmthalak kills", "+", 0.8, 0.7, "Lower Spire: cleared."),
    R("drakkisath", "P-1096", "bosses", "Drakkisath slayers", "{n} General Drakkisath kills", "+", 0.6, 0.7, "The General has been relieved of duty."),
    R("gandling", "P-15030", "bosses", "Gandling slayers", "{n} Darkmaster Gandling kills", "+", 0.6, 0.7, "School's out. Forever."),
    R("rivendare", "P-15031", "bosses", "Rivendare slayers", "{n} Baron Rivendare kills", "+", 0.6, 0.7, "Still no mount? Same."),
    R("onyxia", "P-1098", "bosses", "Onyxia slayers", "{n} Onyxia kills", "+", 0.2, 0.8, "Many whelps! You handled it."),
    // Consumables
    R("elixirs", "P-923", "consumables", "alchemy fans", "{n} elixirs", "+", 40, 0.9, "Better living through alchemy."),
    R("flasks", "P-811", "consumables", "flask drinkers", "{n} flasks", "+", 0.5, 1.2, "Flasks before {m}? Fancy."),
    R("drinks", "P-346", "consumables", "the well-hydrated", "{n} drinks", "+", 600, 0.6, "Stay hydrated, adventurer."),
    R("meals", "P-347", "consumables", "eaters", "{n} meals eaten", "+", 500, 0.6, "Second breakfast is a real meal.", { family: "food" }),
    // Reputation
    R("exalted", "P-377", "social", "the exalted", "{n} factions at Exalted", "+", 1, 1, "Everyone loves you. Officially."),
    R("revered", "P-378", "social", "revered heroes", "{n} factions at Revered or higher", "+", 2, 0.8, "Respected far and wide."),
    R("honored", "P-529", "social", "honored guests", "{n} factions at Honored or higher", "+", 4, 0.5, "Welcome everywhere you go."),
    R("allianceExalted", "P-1466", "social", "Alliance darlings", "{n} Alliance factions at Exalted", "+", 2, 0.8, "Stormwind throws you parades.", F("Alliance")),
    R("factions", "P-931", "social", "diplomats", "{n} factions met", "+", 15, 0.3, "You know absolutely everybody."),
    // Gear and collections
    R("epicsWorn", "P-927", "loot", "purple people", "{n} epic items equipped", "+", 0.3, 0.9, "Dressed in purple."),
    R("epicsAcquired", "P-342", "loot", "epic collectors", "{n} epic items acquired", "+", 0.5, 0.9, "Your bags glow purple.", { family: "epics" }),
    R("legendaries", "P-336", "loot", "legend holders", "{n} legendary items", "+", 0.05, 1, "Did you just... how?"),
    R("mounts", "P-339", "loot", "stable owners", "{n} mounts", "+", 1, 0.6, "One mount for every mood."),
    R("pets", "P-338", "loot", "pet collectors", "{n} vanity pets", "+", 2, 0.9, "Your bags squeak."),
    R("bankSlots", "P-928", "loot", "bank expanders", "{n} extra bank slots", "+", 2, 0.8, "Hoarding, but organized."),
    R("greedRolls", "P-1043", "loot", "greedy rollers", "{n} greed rolls", "+", 300, 0.8, "Greed is good."),
    R("needRolls", "P-1044", "loot", "needy rollers", "{n} need rolls", "+", 150, 0.8, "You really did need it. Every time."),
    // Skills and professions
    R("professions", "P-1199", "crafts", "jacks of all trades", "{n} professions learned", "+", 4, 0.3, "Master of several, at least.", { max: 5 }),
    R("secondaryMaxed", "P-1200", "crafts", "hobbyists", "{n} secondary skills maxed", "+", 1, 0.8, "Cooking, fishing, first aid: the side hustles.", { max: 3 }),
    R("weaponsMaxed", "P-1202", "crafts", "weapon collectors", "{n} weapon skills maxed", "+", 4, 0.5, "Swords, axes, maces: pick a weapon, any weapon.", { max: 12 }),
    R("alchemy", "P-1527", "crafts", "master alchemists", "Alchemy {n}", "+", 200, 0.3, "Everything's a potion if you try hard enough.", SKILL("Alchemy")),
    R("alchemyRecipes", "P-1729", "crafts", "potion scholars", "{n} Alchemy recipes", "+", 50, 0.6, "Your recipe book is bigger than your backpack.", T("Alchemy")),
    R("blacksmithing", "P-1532", "crafts", "master smiths", "Blacksmithing {n}", "+", 200, 0.3, "Clang, clang, clang. Perfection.", SKILL("Blacksmithing")),
    R("smithingPlans", "P-1730", "crafts", "plan collectors", "{n} Blacksmithing plans", "+", 60, 0.6, "Every anvil in Azeroth wants your plans.", T("Blacksmithing")),
    R("enchanting", "P-1535", "crafts", "master enchanters", "Enchanting {n}", "+", 200, 0.3, "Sparkles on everything.", SKILL("Enchanting")),
    R("enchantingFormulae", "P-178", "crafts", "formula collectors", "{n} Enchanting formulae", "+", 40, 0.6, "Crusader? Someday.", T("Enchanting")),
    R("disenchantMats", "P-183", "crafts", "dust gatherers", "{n} materials from disenchanting", "+", 300, 0.9, "One green in, a pile of dust out.", T("Enchanting")),
    R("disenchanted", "P-181", "crafts", "item shredders", "{n} items disenchanted", "+", 200, 0.9, "Greens fear your bags.", T("Enchanting")),
    R("engineering", "P-1544", "crafts", "master engineers", "Engineering {n}", "+", 200, 0.3, "If it explodes, it's working.", SKILL("Engineering")),
    R("schematics", "P-1734", "crafts", "schematic hoarders", "{n} Engineering schematics", "+", 50, 0.6, "Gnomish or Goblin? Both.", T("Engineering")),
    R("herbalism", "P-1538", "crafts", "master herbalists", "Herbalism {n}", "+", 200, 0.3, "Flowers bloom where you walk. Then you pick them.", SKILL("Herbalism")),
    R("leatherworking", "P-1536", "crafts", "master leatherworkers", "Leatherworking {n}", "+", 200, 0.3, "Fine leather goods, ethically skinned.", SKILL("Leatherworking")),
    R("leatherPatterns", "P-1740", "crafts", "pattern collectors", "{n} Leatherworking patterns", "+", 50, 0.6, "Devilsaur leather is your dream.", T("Leatherworking")),
    R("mining", "P-1537", "crafts", "master miners", "Mining {n}", "+", 200, 0.3, "Dig, dig, dig, Thorium.", SKILL("Mining")),
    R("smelting", "P-3216", "crafts", "smelters", "{n} smelting recipes", "+", 8, 0.4, "Ore in, bars out.", T("Mining")),
    R("skinning", "P-1541", "crafts", "master skinners", "Skinning {n}", "+", 200, 0.3, "Clean cuts, every time.", SKILL("Skinning")),
    R("tailoring", "P-1542", "crafts", "master tailors", "Tailoring {n}", "+", 200, 0.3, "Runecloth, stitched to perfection.", SKILL("Tailoring")),
    R("tailoringPatterns", "P-1741", "crafts", "pattern hoarders", "{n} Tailoring patterns", "+", 60, 0.6, "Your sewing kit needs its own bag.", T("Tailoring")),
    R("cooking", "P-1524", "crafts", "master chefs", "Cooking {n}", "+", 150, 0.5, "A five-star chef of the open road.", { max: 300 }),
    R("cookingDailies", "P-1525", "crafts", "daily cooks", "{n} cooking daily quests", "+", 3, 1, "Someone has to feed the city."),
    R("recipes", "P-1745", "crafts", "recipe collectors", "{n} cooking recipes known", "+", 25, 0.6, "Azeroth's finest, from your campfire."),
    R("firstAid", "P-281", "crafts", "field medics", "First Aid {n}", "+", 225, 0.25, "Bandages are your love language.", { max: 300 }),
    R("firstAidManuals", "P-1748", "crafts", "manual readers", "{n} First Aid manuals learned", "+", 3, 0.5, "Heavy Runecloth Bandage, ready."),
    R("fishing", "P-1519", "crafts", "master anglers", "Fishing {n}", "+", 150, 0.6, "The patience of a saint, the skill of a pro.", { max: 300 }),
    R("fishedUp", "P-1456", "crafts", "treasure fishers", "{n} things fished up", "+", 100, 1, "Fish, boots, old crates: all treasure.", { family: "fish" }),
    R("fishingDailies", "P-1526", "crafts", "daily anglers", "{n} fishing daily quests", "+", 3, 1, "The fishing trainer's favorite student."),
    // Travel and social
    R("portalsTaken", "P-350", "travel", "portal hitchhikers", "{n} mage portals taken", "+", 3, 1, "Mages are your favorite taxi."),
    R("hugs", "P-1042", "fun", "huggers", "{n} hugs given", "+", 15, 1, "Free hugs, no questions asked."),
    R("facepalms", "P-1047", "fun", "facepalmers", "{n} facepalms", "+", 10, 1, "Some days, the party earns it."),
    R("violins", "P-1067", "fun", "tiny violinists", "{n} world's smallest violins", "+", 3, 1.2, "Your sympathy is legendary."),
    R("lols", "P-1066", "fun", "laughers", "{n} /lols", "+", 80, 0.9, "Laughter is the best buff."),
    R("cheers", "P-1045", "fun", "cheerleaders", "{n} cheers", "+", 20, 1, "Hip hip hooray!"),
    R("waves", "P-1065", "fun", "wavers", "{n} waves", "+", 40, 0.9, "Hello, Azeroth!"),

    // ---- Iconic moments ----
    R("vanCleef", "W-063", "iconic", "VanCleef's first visitors", "killed Edwin VanCleef at level {n}", "-", 24, 0.1, "The Defias never stood a chance.", F("Alliance", { family: "vanCleef" })),
    R("hogger", "W-060", "iconic", "Hogger hunters", "killed Hogger at level {n}", "-", 11, 0.12, "Elwynn can sleep at night again.", F("Alliance")),
    R("boat", "W-075", "iconic", "sailors", "{n} boat rides", "+", 6, 0.5, "You know the boat schedule by heart.", F("Alliance")),
    R("zeppelins", "W-330", "iconic", "zeppelin riders", "{n} zeppelin rides", "+", 8, 0.6, "Goblin engineering: terrifying, but on time.", F("Horde")),
    R("bangalash", "W-111", "iconic", "big game hunters", "killed King Bangalash at level {n}", "-", 43, 0.05, "The king of the jungle bowed to you."),
    R("mankrik", "W-084", "iconic", "friends of Mankrik", "found Mankrik's wife at level {n}", "-", 18, 0.15, "Barrens chat can finally rest.", F("Horde")),
    R("echeyakee", "W-086", "iconic", "Barrens hunters", "killed Echeyakee at level {n}", "-", 19, 0.1, "The white lion of the Barrens met its match.", F("Horde")),
    R("elevator", "W-095", "iconic", "elevator jumpers", "died falling off the Undercity elevator {n} times", "+", 0.8, 0.9, "Wait for the platform. Next time. Maybe.", F("Horde")),
    R("murlocs", "W-022", "iconic", "murloc hunters", "{n} murlocs slain", "+", 150, 0.6, "Mrglglgl. (That's a complaint.)"),
    R("murlocTrain", "W-023", "iconic", "murloc train survivors", "{n} murlocs in a single fight", "+", 4, 0.35, "You heard the gurgle and stayed anyway."),

    // ---- The little things (wrapped W-022..W-500) ----
    // Combat and deaths
    R("soloElites", "W-135", "combat", "elite soloists", "{n} elites killed without a group", "+", 40, 0.7, "\"Group recommended\" was a suggestion."),
    R("guardDeaths", "W-339", "deaths", "guard magnets", "killed by town guards {n} times", "+", 1, 0.9, "The guards were just doing their job."),
    R("afkDeaths", "W-345", "deaths", "AFK casualties", "{n} deaths while AFK", "+", 0.5, 1, "Be right back. Your corpse won't be."),
    R("dingDeaths", "W-343", "deaths", "short-lived celebrations", "{n} deaths within 10 seconds of a ding", "+", 0.5, 1, "Ding! Oh no."),
    R("loginDeaths", "W-344", "deaths", "rough landings", "{n} deaths within a minute of logging in", "+", 0.5, 1, "You had barely loaded in."),
    R("aliveStretch", "W-355", "deaths", "long-lived adventurers", "{t} of /played without dying", "+", 72000, 0.6, "Not a scratch for days on end.", { family: "streak" }),
    // Travel
    R("swimming", "W-313", "travel", "swimmers", "{t} swimming", "+", 3600, 0.7, "Gills would have been handy."),
    R("lost", "W-335", "travel", "scenic route takers", "got lost {n} times", "+", 8, 0.8, "Not lost. Exploring. Loudly."),
    // PvP and dungeons
    R("ganks", "W-141", "pvp", "lowbie hunters", "{n} players ganked 10+ levels below you", "+", 5, 1, "They were green. You were not."),
    R("corpseCamped", "W-146", "pvp", "corpse-camp survivors", "corpse camped {n} times", "+", 1, 1, "They waited. You waited longer."),
    R("killStreak", "W-169", "pvp", "unstoppables", "{n} players killed in a row", "+", 3, 0.8, "One after another after another."),
    R("firstToFall", "W-226", "dungeons", "floor inspectors", "first to die in {n} wipes", "+", 3, 0.8, "Someone has to check the floor first."),
    R("lastStanding", "W-225", "dungeons", "last ones standing", "last one alive in {n} wipes", "+", 2, 0.8, "You saw it all go wrong. Every time."),
    // Groups, chat and bloopers
    R("rollWins", "W-247", "social", "lucky rollers", "{n} loot rolls won", "+", 60, 0.6, "Lady Luck owes you nothing."),
    R("chatty", "W-277", "social", "chatterboxes", "{n} chat messages sent", "+", 800, 0.9, "Your keyboard got as much use as your hotbar."),
    R("gz", "W-285", "social", "congratulators", "said 'gz' {n} times", "+", 40, 1, "Every ding in earshot got your blessing."),
    R("guildGz", "W-290", "social", "guild favorites", "{n} 'gz' from your guild on your dings", "+", 30, 0.9, "Your guild cheered every step."),
    R("typedLol", "W-284", "fun", "lol typers", "typed 'lol' {n} times", "+", 60, 1, "Laughing out loud, or at least typing it."),
    R("emotes", "W-302", "fun", "emoters", "{n} emotes", "+", 150, 0.8, "/dance, /cheer, /hug: a full vocabulary."),
    R("bloopers", "W-276", "fun", "button mashers", "{n} red error messages", "+", 1500, 0.6, "Not enough rage. Out of range. Not in line of sight."),
    R("hearthCooldown", "W-273", "fun", "impatient hearthers", "pressed your Hearthstone on cooldown {n} times", "+", 3, 1, "It's still not ready."),
    R("reloads", "W-492", "fun", "UI tinkerers", "{n} /reloads", "+", 40, 0.9, "Just one more addon tweak."),
    R("screenshots", "W-493", "fun", "photographers", "{n} screenshots", "+", 30, 1, "Pics, or it didn't happen."),
    // Gold, gear and professions
    R("junkSold", "W-359", "gold", "junk dealers", "{n} gray items sold", "+", 1100, 0.5, "Every gray has a price."),
    R("bigPurchase", "W-362", "gold", "splurgers", "{g} on one vendor purchase", "+", 50000, 0.9, "Some things are worth every copper."),
    R("broke", "W-378", "gold", "broke adventurers", "went broke {n} times", "+", 2, 0.9, "Under a silver to your name. Again."),
    R("repairBill", "W-400", "gold", "repair bill record holders", "a {g} repair bill", "+", 30000, 0.7, "That one hurt.", { family: "repairs" }),
    R("chests", "W-381", "loot", "chest crackers", "{n} treasure chests opened", "+", 20, 0.7, "If it has a lid, you opened it."),
    R("itemsEquipped", "W-394", "loot", "gear swappers", "{n} items equipped", "+", 250, 0.4, "Upgrade, upgrade, upgrade."),
    R("enchanted", "W-401", "loot", "enchanted adventurers", "{n} enchants on your gear", "+", 6, 0.8, "A little sparkle on everything."),
    R("fishingSession", "W-425", "crafts", "patient anglers", "fished for {t} in one go", "+", 1800, 0.7, "The fish weren't biting. You stayed anyway."),
    R("cooked", "W-426", "crafts", "camp cooks", "{n} dishes cooked", "+", 120, 0.8, "Something smells good."),
    R("explosives", "W-432", "crafts", "demolition experts", "{n} explosives thrown", "+", 40, 0.9, "Fire in the hole!", T("Engineering")),
    R("gems", "W-415", "crafts", "gem finders", "{n} gems found mining", "+", 25, 0.8, "Something shiny in every vein.", T("Mining")),
    // Reputation and habits
    R("repGained", "W-439", "social", "faction favorites", "{n} reputation earned", "+", 60000, 0.5, "Everyone knows your name."),
    R("bloodsail", "W-442", "fun", "pirates at heart", "{n} Bloodsail reputation gains", "+", 5, 1.2, "Yarr. Booty Bay is not amused."),
    R("sessionKills", "W-490", "pace", "session slayers", "{n} kills in one session", "+", 300, 0.5, "One sitting, one very long kill list."),
    R("xpHour", "W-496", "pace", "power hours", "{n} XP in one hour", "+", 60000, 0.4, "The best hour of your whole journey."),
    R("lateDings", "W-487", "pace", "midnight dingers", "{n} dings after midnight", "+", 2, 0.9, "Level up now, sleep later."),
    R("firstGold", "W-467", "gold", "early earners", "your first gold at level {n}", "-", 14, 0.25, "The first gold is the hardest."),
    R("firstFlight", "W-471", "travel", "early flyers", "your first flight at level {n}", "-", 10, 0.3, "Walking was never your thing.")
  ];
})();
// The site's functions load it too (site/api/ranks.js).
if (typeof module === "object" && module.exports) module.exports = RANKINGS;
