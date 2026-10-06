// Journey Tracker's journey model, shared by the recap page and the website's
// functions: an export as the journey the page shows (journeyFromExport), the
// numbers it's ranked on (profileOf) and where it places among everyone
// else's (placesFor). site/build.ps1 puts this file into the page;
// site/deploy.ps1 gives each function that needs it a copy.
var JourneyModel = (function () {
  "use strict";

  // Bump when a ranked value changes meaning or the rankings gain keys:
  // profiles saved under an older model get worked out again (site/api/ranks.js).
  // 2: ranked per milestone; "played" and "days" are the time to it.
  // 3: the wrapped stats' rankings (addon 0.6.0).
  // 4: how long after its milestone a journey was exported (since), and
  //    late ones ranked only on what was settled by then.
  // 5: the class, dungeon and XP-per-hour rankings filled in; auction sales
  //    no longer counted twice in what's earned; no more days played than
  //    days counted; kinds of mob past the export's 200; no Hyjal before 60;
  //    Statistics pane values and level times past belief left out.
  var MODEL = 5;
  // /played seconds after reaching a milestone past which a journey
  // exported at that level is late (the addon's LATE_AFTER).
  var LATE_AFTER = 2 * 3600;
  // A place needs this many players on the ranking, you included: being 1st
  // of 2 says nothing.
  var MIN_PLAYERS = 3;
  // The addon's squares across each zone's map, for where you spent your
  // time (its SPOT_GRID).
  var SPOT_GRID = 25;
  // From this many players up, a place reads as a share ("Top 3%") instead
  // of a place ("2nd of 9").
  var SHARE_FROM = 100;
  // A level's /played past this is a broken record, not a slow level.
  var LEVEL_TIME_MAX = 30 * 86400;
  // A Statistics pane value past this is no count or copper amount a
  // character has.
  var PANE_MAX = 1e12;

  function sum(list) { return list.reduce(function (t, v) { return t + v; }, 0); }
  function num(n) { return Math.round(n).toLocaleString("en-US"); }
  // The addon's own duration format: 6d 12h 40m, 2h 51m, 9m 36s.
  function dur(seconds) {
    var s = Math.round(seconds);
    var d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
    if (d) return d + "d " + h + "h " + m + "m";
    if (h) return h + "h " + m + "m";
    return m + "m " + (s % 60) + "s";
  }
  function coins(copper) {
    if (copper >= 10000) return num(Math.floor(copper / 10000)) + " gold";
    if (copper >= 100) return Math.floor(copper / 100) + " silver";
    return Math.round(copper) + " copper";
  }

  // Lua tables arrive as JSON objects, or as arrays when their keys run 1..n
  // (and an empty table is []). Exports are pasted by anyone and shared
  // pages show them to everyone, so every number read from one goes
  // through number() (it ends up in the page's HTML), and tables keyed by
  // names from an export have no prototype ("__proto__" is just a name).
  function named(x) { return x && typeof x === "object" && !Array.isArray(x) ? x : {}; }
  function number(v) { v = Number(v); return isFinite(v) ? v : 0; }
  function numbered(x) {
    var out = Object.create(null);
    if (Array.isArray(x)) x.forEach(function (v, i) { out[i + 1] = v; });
    else Object.keys(named(x)).forEach(function (k) { out[k] = x[k]; });
    return out;
  }
  function listOf(x) { return Array.isArray(x) ? x : Object.keys(named(x)).map(function (k) { return x[k]; }); }
  // The sum of a map's numbers (or of one field of each entry).
  function addUp(map, field) {
    return listOf(map).reduce(function (t, v) { var n = number(field ? named(v)[field] : v); return t + (n > 0 ? n : 0); }, 0);
  }
  // A { name: count } map as [name, count] rows, biggest first.
  function topRows(map, n) {
    var m = named(map);
    return Object.keys(m).map(function (k) { return [k, number(m[k])]; })
      .filter(function (r) { return r[1] > 0; }).sort(function (a, b) { return b[1] - a[1]; }).slice(0, n || 5);
  }
  function tally(records, field) {
    var out = Object.create(null);
    records.forEach(function (r) { if (r && typeof r[field] === "string") out[r[field]] = (out[r[field]] || 0) + 1; });
    return out;
  }
  function capFirst(text) { return text.charAt(0).toUpperCase() + text.slice(1); }
  // Every ten levels is a milestone. A journey counts toward the last one
  // its level reached (one at 34 toward 30; one under 10 toward none, 0).
  function milestoneOf(level) { return level >= 60 ? 60 : Math.max(0, Math.floor(level / 10) * 10); }
  // "October 5". One formatter for every date: toLocaleDateString makes one
  // each time, which is slow, and an export can bring thousands of dates.
  var DAY_FORMAT = new Intl.DateTimeFormat("en-US", { month: "long", day: "numeric" });
  function dayOf(t) { var d = new Date(t * 1000); return isNaN(d) ? "Invalid Date" : DAY_FORMAT.format(d); }
  function own(map, key) { return Object.prototype.hasOwnProperty.call(map, key) ? map[key] : undefined; }
  var QUALITY = ["poor", "common", "uncommon", "rare", "epic", "legendary"];
  var QUALITY_BY_COLOR = { "9d9d9d": 0, ffffff: 1, "1eff00": 2, "0070dd": 3, a335ee: 4, ff8000: 5 };
  // An item link ("|cnIQ3:|Hitem:...|h[Name]|h|r") as { name, q }.
  function itemOf(link) {
    var s = String(link || ""), name = (s.match(/\[([^\]]+)\]/) || [])[1];
    if (!name) return null;
    var q = s.match(/\|cnIQ(\d):/);
    q = q ? Number(q[1]) : QUALITY_BY_COLOR[((s.match(/\|cff([0-9a-f]{6})/i) || [])[1] || "").toLowerCase()];
    return { name: name, q: QUALITY[q] || "common" };
  }
  // A Statistics pane value as a number: "--" is none, money is in copper.
  // Null (unknown) for anything no statistic is: longer than gold, silver
  // and copper written out (about 150 characters), negative or past PANE_MAX.
  function paneNumber(value) {
    var s = String(value == null ? "" : value).trim(), n = 0;
    if (s === "--" || s === "") return 0;
    if (s.length > 200) return null;
    if (s.indexOf("|T") >= 0) {
      s.replace(/([\d,]+)\s*\|T[^|]*?(Gold|Silver|Copper)Icon[^|]*\|t/gi, function (all, digits, coin) {
        n += Number(digits.replace(/,/g, "")) * { gold: 10000, silver: 100, copper: 1 }[coin.toLowerCase()];
      });
    } else {
      n = Number(s.replace(/,/g, ""));
    }
    return n >= 0 && n <= PANE_MAX ? n : null;
  }
  var CLASS_NAMES = { WARRIOR: "Warrior", PALADIN: "Paladin", HUNTER: "Hunter", ROGUE: "Rogue", PRIEST: "Priest",
                      SHAMAN: "Shaman", MAGE: "Mage", WARLOCK: "Warlock", DRUID: "Druid" };
  var RACE_NAMES = { NightElf: "Night Elf", Scourge: "Undead" };
  var PRIMARY = ["Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Herbalism", "Leatherworking", "Mining",
                 "Skinning", "Tailoring"];
  var SLOTS = { 1: "Head", 2: "Neck", 3: "Shoulder", 4: "Shirt", 5: "Chest", 6: "Waist", 7: "Legs", 8: "Feet",
                9: "Wrist", 10: "Hands", 11: "Finger", 12: "Finger", 13: "Trinket", 14: "Trinket", 15: "Back",
                16: "Main hand", 17: "Off hand", 18: "Ranged", 19: "Tabard" };

  // A decoded export as a journey for the page: the sample's fields, from
  // what the addon saved (JourneyTracker.lua's DEFAULTS describe the stats).
  // Anything the export doesn't have stays empty, and the page leaves it out.
  function journeyFromExport(data) {
    var st = named(data.stats), ch = named(data.character), lv = named(data.levels), wr = named(data.wrapped);
    var classToken = String(ch.class || ""), classes = named(data.class);
    var cls = named(own(classes, classToken)), all = named(classes.ALL);
    var now = number(data.exportedAt) || Math.floor(Date.now() / 1000), since = number(st.firstSeen) || now;
    var reachedMax = number(st.reachedMax);
    var level = number(ch.level), className = own(CLASS_NAMES, classToken) || capFirst(classToken.toLowerCase());
    var race = own(RACE_NAMES, ch.race) || String(ch.race || "").replace(/([a-z])([A-Z])/g, "$1 $2");
    var J = { imported: true, level: level, played: number(ch.played), className: className, classToken: classToken,
              race: race, faction: String(ch.faction || ""), ruleset: String(ch.ruleset || "Normal"), hoursAreSeconds: true,
              exportedAt: number(data.exportedAt) || undefined };
    J.who = [race + " " + className, J.faction, J.ruleset + " realm"].filter(Boolean).join(" · ");
    // The Statistics pane, by statistic ID. It has counted since before the
    // tracker was installed, so where both count the same thing the page
    // shows the bigger of the two, as the addon's own window does.
    var paneValues = named(named(named(data.statistics).latest).values), pane = Object.create(null);
    Object.keys(paneValues).forEach(function (id) {
      var n = paneNumber(paneValues[id]);
      if (n !== null) pane[id] = n;
    });
    function best(tracked, id) { return Math.max(number(tracked), pane[id] || 0); }
    J.pane = pane;
    J.firstLogin = dayOf(since);
    J.reached60 = reachedMax ? dayOf(reachedMax) : null;
    J.calendarDays = Math.max(1, Math.ceil(((reachedMax || now) - since) / 86400));
    // The days played among them: the player's own dates ("2026-10-01"), so
    // one counts if it could have begun by the last of those days anywhere
    // (UTC+14), and there are never more of them than there were days.
    var daysEnd = new Date(((reachedMax || now) + 14 * 3600) * 1000);
    var lastDay = isNaN(daysEnd) ? "" : daysEnd.toISOString().slice(0, 10);
    J.daysPlayed = Math.min(J.calendarDays,
      Object.keys(named(st.days)).filter(function (d) { return d <= lastDay; }).length);

    // Each level's time: from the level's own counters, or the /played at
    // the level-ups on either side. Levels before the tracker stay empty,
    // and so does one past LEVEL_TIME_MAX.
    var levelStats = numbered(lv.stats), dings = numbered(lv.snapshots), L;
    function levelTime(t) { return t > 0 && t <= LEVEL_TIME_MAX; }
    J.perLevel = [];
    for (L = 1; L <= 59; L++) {
      var took = number(named(levelStats[L]).played);
      var a = number(named(dings[L]).played), b = number(named(dings[L + 1]).played);
      if (!levelTime(took) && a > 0 && b > a) took = b - a;
      J.perLevel.push(levelTime(took) ? took : null);
    }
    var path = listOf(st.path);
    J.firstLevel = path.reduce(function (lowest, p) {
      var l = number(named(p).level);
      return l > 0 && (!lowest || l < lowest) ? l : lowest;
    }, 0) || level;

    // The milestone it counts toward, and whether it's "at" it: exported at
    // that level, as the addon does when you reach one (data.milestone).
    // The time to it is from the level-up there, where the tracker saw it.
    J.milestone = milestoneOf(level);
    J.atMilestone = level === J.milestone;
    J.savedAtMilestone = J.atMilestone && number(data.milestone) === level;
    // Without the level-up's own record, an export made at the milestone
    // stands in for it, but only if the tracker saw the character below it:
    // one picked up at 20 didn't reach 20 on the day it was exported.
    var reach = named(dings[J.milestone]), sawIt = J.atMilestone && J.milestone && J.firstLevel < J.milestone;
    var reachedAt = number(reach.t) || (J.milestone === 60 && reachedMax) || (sawIt ? now : 0);
    J.complete = J.firstLevel <= 2 && J.milestone >= 10;   // tracked from the start to its milestone
    // Calendar days from the tracker's first day: the journey's own first
    // day only when it's complete, so only then "Level 30 in 12 days".
    function daysTo(t) { return Math.max(1, Math.ceil((t - since) / 86400)); }
    J.daysTo = J.milestone && reachedAt ? daysTo(reachedAt) : undefined;
    J.reachedMilestone = J.milestone && reachedAt ? dayOf(reachedAt) : null;
    // How long after reaching its milestone it was exported, in /played
    // seconds: the addon says (0.6.0 on), or the level-up's own /played does.
    // One exported at its milestone's level long after reaching it (a 60
    // that's been 60 for weeks) is late: its totals kept growing after, so
    // it's ranked only on what was settled when it got there (profileOf).
    var sinceIt = named(data.sinceMilestone);
    J.since = J.milestone && number(sinceIt.level) === J.milestone && typeof sinceIt.played === "number" ?
      Math.max(0, number(sinceIt.played)) :
      J.savedAtMilestone ? 0 :
      J.milestone && number(reach.played) > 0 && J.played >= number(reach.played) ? J.played - number(reach.played) :
      undefined;
    J.late = J.atMilestone && J.milestone >= 10 && J.since !== undefined && J.since > LATE_AFTER;
    // The /played it took: the level-up's, or standing in for it, the
    // export's own less the time since (when the addon says how long).
    var standIn = sawIt && J.played > (J.since || 0) ? J.played - (J.since || 0) : 0;
    J.playedTo = J.milestone ? number(reach.played) || standIn || undefined : undefined;
    // Then and now: each milestone the tracker saw you reach, with how far
    // you'd come by then (the running totals saved at the level-up).
    J.milestoneRows = [];
    for (var m = 10; m <= J.milestone; m += 10) {
      var at = named(dings[m]);
      if (!(number(at.t) > 0)) continue;
      J.milestoneRows.push({ level: m, t: number(at.t), date: dayOf(number(at.t)), days: daysTo(number(at.t)),
                             played: number(at.played) || null, kills: number(at.kills), deaths: number(at.deaths),
                             quests: number(at.quests) });
    }
    function mostIn(field) {
      return Object.keys(levelStats).reduce(function (m, k) { return Math.max(m, number(named(levelStats[k])[field])); }, 0);
    }

    // Time
    var T = named(st.time);
    J.trackedTime = number(T.solo) + number(T.grouped) || J.played;
    J.timeSpent = [["Mounted", T.mounted], ["In combat", T.combat], ["Resting in inns and cities", T.resting],
                   ["On flight paths", T.taxi], ["AFK", T.afk], ["Dead", T.dead]]
      .map(function (r) { return [r[0], number(r[1])]; })
      .filter(function (r) { return r[1] > 0; }).sort(function (x, y) { return y[1] - x[1]; });
    var hours = numbered(st.hours);
    J.hourWeights = [];
    for (var h = 0; h < 24; h++) J.hourWeights.push(number(hours[h]));
    var sessions = named(st.sessions), runs = listOf(sessions.list).concat(sessions.current ? [sessions.current] : []);
    var lengths = runs.map(function (r) { return number(named(r).last) - number(named(r).start); })
      .filter(function (s) { return s > 0; });
    J.sessions = runs.length;
    J.longestSession = lengths.reduce(function (most, s) { return Math.max(most, s); }, 0);
    J.avgSession = lengths.length ? sum(lengths) / lengths.length : 0;   // 0: no session has a length
    J.bestSession = null;
    runs.forEach(function (r) {
      var gained = number(named(r).levels), from = number(named(r).startLevel);
      if (gained > 0 && (!J.bestSession || gained > J.bestSession.levels)) J.bestSession = { levels: gained, from: from, to: from + gained };
    });

    // Milestones the tracker saw happen
    var loot = named(st.loot), social = named(st.social), professions = named(st.professions), marks = [];
    function mark(when, text) { when = number(when); if (when > 0) marks.push([when, text]); }
    Object.keys(professions).forEach(function (name) {
      if (number(named(professions[name]).t) - since > 60) mark(professions[name].level, "Took up " + name);
    });
    mark(named(loot.firstBlue).level, "First blue");
    mark(named(loot.firstEpic).level, "First epic");
    mark(social.guildJoinLevel, "Joined a guild");
    mark(named(st.firstMount).level, "First mount");
    mark(named(wr["W-001"]).level, "Left Zephras Isle");
    mark(named(wr["W-006"]).level, "Reached Mount Hyjal");
    ICONIC_MARKS.forEach(function (m) { mark(named(wr[m[0]]).level, m[1]); });
    if (reachedMax) mark(60, "Level 60");
    J.milestones = marks.sort(function (x, y) { return x[0] - y[0]; });

    // Combat
    var kills = named(st.kills), byClass = named(kills.byClass), combat = named(st.combat);
    J.kills = Math.max(number(kills.total), (pane[1198] || 0) - (pane[588] || 0));   // kills that give XP
    J.topMobs = topRows(kills.byName, 5);
    // How many kinds: the addon's own count where the export has it (it keeps
    // only the 200 most killed by name), or the names it kept.
    J.mobKinds = typeof kills.uniqueNames === "number" ? number(kills.uniqueNames) :
      Object.keys(named(kills.byName)).length;
    J.killTypes = Object.create(null);
    topRows(kills.byType, 50).forEach(function (r) { J.killTypes[r[0]] = r[1]; });
    J.elites = number(byClass.elite) + number(byClass.rareelite) + number(byClass.worldboss);
    J.rares = number(byClass.rare) + number(byClass.rareelite);
    J.bosses = addUp(st.bosses, "kills");
    J.wipes = addUp(st.bosses, "wipes");
    J.honorKills = best(named(st.pvp).honorableKills, 588);
    J.fights = number(combat.fights);
    J.longestFight = number(combat.longest);
    J.ambushes = number(combat.ambushMobs);
    J.multiPulls = number(combat.multiPulls);
    J.maxMobs = number(combat.maxMobs);
    var gap = named(kills.maxLevelDiff);
    J.bestKill = number(gap.diff) > 0 ? { mob: number(gap.mobLevel), you: number(gap.level) } : null;
    J.levelKills = mostIn("kills");

    // Dungeons: the times you went in, and the runs, each with how long it
    // took. Only a run with a boss killed counts as done (walking in and
    // out again isn't a run).
    var dungeons = named(st.dungeons), entered = named(dungeons.entered);
    var done = listOf(dungeons.runs).filter(function (r) { return number(named(r).bosses) > 0; });
    J.dungeonsEntered = addUp(entered);
    J.dungeonTypes = Object.keys(entered).length;
    J.dungeonRuns = done.length;
    J.fastestRun = done.reduce(function (fastest, r) {
      var took = number(named(r).duration);
      return took > 0 && (!fastest || took < fastest) ? took : fastest;
    }, 0) || undefined;

    // Deaths
    var deaths = listOf(st.deaths), rez = named(st.rez);
    J.deaths = best(deaths.length, 60);
    J.deathZones = topRows(tally(deaths, "zone"), 4);
    J.killers = topRows(tally(deaths, "killer"), 4);
    J.rez = { corpse: number(rez["corpse run"]), spirit: number(rez["spirit healer"]), player: number(rez["player rez"]) };
    // Where each death happened: the zone map (UiMapID) and the spot on it, 0 to 100.
    J.deathSpots = deaths.filter(function (d) {
      return d && number(d.mapID) > 0 && typeof d.x === "number" && typeof d.y === "number" &&
        d.x >= 0 && d.x <= 100 && d.y >= 0 && d.y <= 100;
    }).map(function (d) {
      return { map: number(d.mapID), x: number(d.x), y: number(d.y), level: number(d.level), killer: String(d.killer || "") };
    });
    J.dungeonDeaths = deaths.filter(function (d) { return d && d.dungeon; }).length;
    J.groupDeaths = deaths.filter(function (d) { return d && d.grouped; }).length;
    J.timeDead = number(T.dead);
    J.corpseTime = number(T.corpseRuns);
    J.graveyards = Object.keys(named(st.graveyards)).length;
    J.levelDeaths = mostIn("deaths");
    J.streak = null;
    for (var run = null, lvl = 1; lvl <= 60; lvl++) {
      var s = levelStats[lvl];
      if (!s || number(named(s).deaths) > 0) { run = null; continue; }
      run = run ? { levels: run.levels + 1, from: run.from, to: lvl } : { levels: 1, from: lvl, to: lvl };
      if (!J.streak || run.levels > J.streak.levels) J.streak = run;
    }

    // Quests and XP
    var quests = named(st.quests), tags = named(quests.byTag), forever = named(wr["W-007"]);
    J.quests = { completed: best(quests.completed, 98), accepted: number(quests.accepted), abandoned: best(quests.abandoned, 94),
                 group: addUp(tags) - number(tags.Dungeon), dungeon: number(tags.Dungeon),
                 forever: number(forever.forever), classic: number(forever.classic) };
    // Then and now's last row: the tracker's own counts now, as the
    // level-ups saved them (not the Statistics pane's).
    J.nowRow = { level: level, date: dayOf(now), days: daysTo(now), played: J.played || null, kills: number(kills.total),
                 deaths: deaths.length, quests: number(quests.completed) };
    var heldFor = number(named(quests.longest).seconds);
    J.longestQuest = heldFor > 0 ? { days: Math.round(heldFor / 86400), seconds: heldFor } : null;
    J.questZones = topRows(quests.byZone, 5);
    J.questGold = best(quests.money, 326);
    J.levelQuests = mostIn("quests");
    var xp = named(st.xp), xpTotal = number(xp.total);
    J.xpTotal = xpTotal;
    function xpShare(v) { return xpTotal ? Math.round(number(v) / xpTotal * 100) : 0; }
    J.xpSplit = [["Quests", xpShare(xp.quest), "var(--gold)"], ["Kills", xpShare(xp.kill), "var(--gold-deep)"],
                 ["Exploration", xpShare(xp.explore), "var(--gold-pale)"], ["Other", xpShare(xp.other), "var(--ink-soft)"]]
      .filter(function (p) { return p[1] > 0; });
    J.restedShare = xpShare(xp.restedUsed);
    J.groupXP = xpShare(xp.grouped);
    // XP per hour over the levels with a time and their XP, as the addon's
    // Level Timeline works it out.
    var timedXP = 0, timedFor = 0;
    J.perLevel.forEach(function (sec, i) {
      var gained = number(named(levelStats[i + 1]).xp);
      if (sec > 0 && gained > 0) { timedXP += gained; timedFor += sec; }
    });
    J.xpRate = timedFor > 0 ? timedXP / timedFor * 3600 : undefined;

    // The road: zones in the order you first reached them, the levels you
    // were while there, and the time spent in each.
    var zones = named(st.zones), stops = [], stopOf = Object.create(null);
    path.forEach(function (p, i) {
      p = named(p);
      if (typeof p.zone !== "string" || !p.zone || p.zone === "Unknown") return;
      var at = number(p.level), stop = stopOf[p.zone];
      if (!stop) stops.push(stop = stopOf[p.zone] = [p.zone, at, at, number(named(own(zones, p.zone)).seconds)]);
      var next = named(path[i + 1]), left = number(next.level) || (i === path.length - 1 ? level : at);
      stop[2] = Math.max(stop[2], at, left);
    });
    J.path = stops;
    J.heat = [];
    J.zoneHeat = true;
    // Where you spent your time (addon 0.5.0 on): the seconds in each square
    // of each zone's map (SPOT_GRID x SPOT_GRID, numbered from 1 at the top
    // left), as [uiMapID, x %, y %, seconds] at each square's middle.
    J.where = [];
    var where = named(st.where);
    Object.keys(where).forEach(function (id) {
      var map = Number(id), squares = numbered(where[id]);
      if (!(map > 0) || Math.floor(map) !== map) return;
      Object.keys(squares).forEach(function (k) {
        var n = Number(k), seconds = number(squares[k]);
        if (!(n >= 1 && n <= SPOT_GRID * SPOT_GRID) || Math.floor(n) !== n || !(seconds > 0)) return;
        J.where.push([map, ((n - 1) % SPOT_GRID + 0.5) * 100 / SPOT_GRID,
                      (Math.floor((n - 1) / SPOT_GRID) + 0.5) * 100 / SPOT_GRID, seconds]);
      });
    });
    J.zonesVisited = Object.keys(zones).filter(function (z) { return z !== "Unknown"; }).length;
    J.subzones = Object.keys(named(st.subzones)).length;
    // The level you were at a moment: the last level-up or zone change the
    // tracker saw before it (levels only go up). The places below ask in
    // time order, so it reads through those once, oldest first.
    var seen = Object.keys(dings).map(function (l) { return [number(named(dings[l]).t), Number(l)]; })
      .filter(function (u) { return u[0] > 0; })
      .concat(path.map(function (p) { return [number(named(p).t), number(named(p).level)]; }))
      .sort(function (x, y) { return x[0] - y[0]; });
    var seenTo = 0, levelThen = J.firstLevel || 0;
    function levelAt(t) {
      for (; seenTo < seen.length && seen[seenTo][0] <= t; seenTo++) {
        if (seen[seenTo][1] > levelThen) levelThen = seen[seenTo][1];
      }
      return levelThen;
    }
    // The places found in each zone ("Zone: Subzone" keys, each with when you
    // first went in), in the order you found them: [{ name, date, level }].
    J.places = Object.create(null);
    var subzones = named(st.subzones);
    Object.keys(subzones).sort(function (a, b) { return number(subzones[a]) - number(subzones[b]); }).forEach(function (key) {
      var at = key.indexOf(": "), t = number(subzones[key]);
      if (at < 1) return;
      var zone = key.slice(0, at);
      if (!J.places[zone]) J.places[zone] = [];
      J.places[zone].push({ name: key.slice(at + 2), date: t > 0 ? dayOf(t) : null, level: t > 0 ? levelAt(t) : null });
    });
    J.zoneChanges = path.length;
    var travel = named(st.travel), falls = named(st.falls);
    J.travel = { groundYards: number(travel.ground), airYards: number(travel.taxi), flights: best(travel.flights, 349),
                 flightPaths: listOf(travel.flightPaths).length, hearths: best(travel.hearths, 353),
                 longestFall: Math.round(number(named(falls.longestSurvived).yards)), fallen: Math.round(number(falls.total)) };
    J.fallDeaths = best(falls.fatal, 114);

    // Gold, with what the tracker couldn't place as "Other"
    var money = named(st.money);
    function withOther(rows, whole) {
      rows = rows.map(function (r) { return [r[0], number(r[1])]; })
        .filter(function (r) { return r[1] > 0; }).sort(function (x, y) { return y[1] - x[1]; });
      var rest = number(whole) - sum(rows.map(function (r) { return r[1]; }));
      return rest > 0 ? rows.concat([["Other", rest]]) : rows;
    }
    // The addon's mail income includes auction sales, which have their own row.
    J.earned = withOther([["Quest rewards", J.questGold], ["Selling to vendors", best(money.vendor, 921)],
                          ["Looting", best(money.loot, 333)], ["Auction house sales", best(money.auctionIncome, 919)],
                          ["Mail", Math.max(0, number(money.mail) - number(money.auctionIncome))]], best(money.earned, 328));
    J.spent = withOther([["Vendor purchases", money.vendorSpent], ["Auction house", money.auctionSpent],
                         ["Class training", money.training], ["Repairs", money.repairs], ["Flights", best(money.flights, 1146)]],
                        money.spent);
    J.earnedTotal = sum(J.earned.map(function (r) { return r[1]; }));
    J.spentTotal = sum(J.spent.map(function (r) { return r[1]; }));
    J.peakGold = best(money.peak, 334) > 0 ? { copper: best(money.peak, 334) } : null;
    J.auctionsSold = number(money.auctionsSold);
    J.firstMountLevel = number(named(st.firstMount).level) || null;
    J.firstMountPlayed = number(named(st.firstMount).played) || null;

    // Gear and loot
    var worn = listOf(st.worn).filter(function (w) { return w && itemOf(w.link); });
    function wornItem(w) {
      var it = itemOf(w.link);
      it.slot = own(SLOTS, w.slot) || "Gear";
      it.levels = number(w.levels);
      it.played = number(w.played);
      it.from = number(w.first);
      it.to = number(w.last);
      return it;
    }
    var mostLevels = worn.slice().sort(function (x, y) { return number(y.levels) - number(x.levels); })[0];
    var mostPlayed = worn.slice().sort(function (x, y) { return number(y.played) - number(x.played); })[0];
    J.wornLevels = mostLevels && number(mostLevels.levels) >= 1 ? wornItem(mostLevels) : null;
    J.wornPlayed = mostPlayed && number(mostPlayed.played) > 0 ? wornItem(mostPlayed) : null;
    function found(record) {
      var it = record && itemOf(record.link);
      if (it) { it.level = number(record.level); it.where = String(record.zone || "somewhere"); it.ilvl = number(record.ilvl); }
      return it;
    }
    J.bestLoot = found(loot.best);
    J.firstBlue = found(loot.firstBlue);
    J.firstEpic = found(loot.firstEpic);
    J.looted = number(loot.items);
    var byQuality = numbered(loot.byQuality);
    J.loot = QUALITY.map(function (q, i) { return [capFirst(q), number(byQuality[i]), "var(--q-" + q + ")"]; })
      .filter(function (r) { return r[1] > 0; });

    // Professions
    J.professions = Object.keys(professions).map(function (name) { return [name, number(named(professions[name]).rank)]; })
      .filter(function (r) { return r[1] > 0; }).sort(function (x, y) { return y[1] - x[1]; });
    J.trades = Object.keys(professions).filter(function (name) { return PRIMARY.indexOf(name) >= 0; });
    var gathering = named(st.gathering);
    J.skinned = number(named(gathering.skinning).nodes);
    J.herbs = number(named(gathering.herb).nodes);
    J.ore = number(named(gathering.mining).nodes);
    J.fish = best(st.fish, 1518);
    J.crafted = number(st.crafted);
    J.skillUps = number(st.skillUps);

    // Class: what the class tracker saved (spells cast, time in each form,
    // stance or aspect, healing, power spent), plus what every class shares
    J.casts = named(cls.casts);
    J.classTime = named(cls.time);
    J.swaps = named(cls.swaps);
    J.targets = named(cls.targets);
    J.powerSpent = named(cls.powerSpent);
    J.healing = addUp(cls.healing);
    J.classStats = cls;
    J.classAll = all;

    // WoW Forever and friends
    J.camps = addUp(wr["W-008"]);
    J.campTime = number(named(wr["W-009"]).Camp);
    J.campShops = number(named(wr["W-010"]).vendor);
    J.campBuffs = addUp(wr["W-011"]);
    J.campCrafts = addUp(wr["W-012"]);
    J.valthalak = listOf(wr["W-016"]).length;
    J.transmog = number(named(wr["W-019"]).changes);
    J.autoFlagged = number(wr["W-021"]);
    J.zephras = number(named(wr["W-001"]).level) || null;
    // Days after 60 you first reached Mount Hyjal: the addon notes the
    // arrival before 60 too, without them.
    var hyjal = named(wr["W-006"]);
    J.hyjal = typeof hyjal.daysAfter60 === "number" ? number(hyjal.daysAfter60) : undefined;
    J.grouped = number(T.grouped);
    J.groupedWith = number(social.unique);
    J.guildLevel = number(social.guildJoinLevel) || null;
    J.guildBefore = !!social.guildBeforeTracking;
    J.jumps = number(social.jumps);
    // Everything else the wrapped stats hold, for the page's chapters
    J.little = littleOf(wr, J.played, deaths);
    return J;
  }

  // ---- The little things: the addon's wrapped stats ----
  // db.wrapped is keyed by spec item ID (wrapped-tracking-spec.md). The page
  // shows these, chapter by chapter, as [id, label, how]. An id can add up
  // several ("W-277+W-278"). How to read each:
  //   n  a count (a map's counts add up)   t  seconds   g  copper
  //   max, tmax, gmax  a record's value (a count, seconds or copper)
  //   sec  a record's value in seconds, to a tenth
  //   top  a map's biggest entry, with its count
  //   lvl  a record's level (a first), with its name if it has one
  //   rec:<k>  the level of one record in a map of them ("1g")
  //   key:<k>  one entry of a map    ends:<s>  the entries whose key ends so
  //   keys  how many entries a map has    list  how many a list has
  //   avg:<total>:<count>  one entry of a map over another
  var LITTLE = {
    combat: [["W-023", "Most murlocs in one fight", "max"], ["W-135", "Elites soloed", "n"],
      ["W-137", "Highest-level elite soloed", "max"], ["W-138", "Mobs killed 5+ levels above you", "n"],
      ["W-130", "Rares spotted", "key:seen"], ["W-061", "Fights with Hogger", "key:attempts"]],
    deaths: [["W-337", "Drowned", "n"], ["W-338", "Swam into fatigue", "n"], ["W-339", "Town guards", "n"],
      ["W-136", "Elites", "n"], ["W-341", "Murlocs", "n"], ["W-342", "Critters", "n"], ["W-118", "Devilsaurs", "n"],
      ["W-343", "Within 10 seconds of a ding", "n"], ["W-344", "Within a minute of logging in", "n"],
      ["W-345", "While AFK", "n"], ["W-346", "During an escort", "n"], ["W-347", "With Resurrection Sickness", "n"],
      ["W-354", "Twice in one minute", "n"], ["W-352", "With your Hearthstone ready", "n"],
      ["W-355", "Longest stretch alive", "tmax"], ["W-357", "Average /played between deaths", "t"],
      ["W-358", "Time as a ghost", "t"]],
    travel: [["W-313", "Time swimming", "t"], ["W-315", "Time underwater", "t"], ["W-316", "Breath ran out", "n"],
      ["W-319", "Longest fall", "sec"], ["W-335", "Times you got lost", "n"], ["W-329", "Boat rides", "n"],
      ["W-330", "Zeppelin rides", "n"], ["W-331", "Portals taken", "n"], ["W-333", "Meeting stones used", "n"],
      ["W-324", "Inn you bound to most", "top"], ["W-327", "Rested XP gained while away", "n"]],
    gold: [["W-359", "Junk sold", "n"], ["W-359.gold", "Gold from junk", "g"], ["W-362", "Biggest vendor purchase", "gmax"],
      ["W-367", "Auctions posted", "n"], ["W-370", "Best auction sale", "gmax"], ["W-371", "Biggest auction buy", "gmax"],
      ["W-378", "Times you went broke", "n"], ["W-381", "Treasure chests opened", "n"], ["W-382", "Gold from chests", "g"],
      ["W-380", "Lockboxes looted", "n"], ["W-376", "Spent on respecs", "g"]],
    gear: [["W-394", "Items equipped", "n"], ["W-401", "Enchants applied", "n"], ["W-392", "Favorite suffix", "top"],
      ["W-397", "First two-hander", "lvl"], ["W-398", "Items broken", "n"], ["W-400", "Biggest repair bill", "gmax"],
      ["W-363", "Items destroyed", "n"], ["W-403", "BoE gear sold unworn", "n"], ["W-407", "Talent respecs", "n"]],
    skills: [["W-421", "Fishing casts", "key:casts"], ["W-421", "Catches", "key:catches"], ["W-424", "Pools fished", "n"],
      ["W-425", "Longest fishing session", "tmax"], ["W-426", "Dishes cooked", "n"], ["W-426", "Favorite dish", "top"],
      ["W-417", "Cloth looted", "n"], ["W-415", "Gems found mining", "n"], ["W-430", "Items disenchanted", "n"],
      ["W-436", "Potions and elixirs made", "n"], ["W-432", "Explosives thrown", "n"], ["W-435", "Gadgets used", "n"]],
    social: [["W-254", "Groups joined", "n"], ["W-246", "Need rolls", "key:need"], ["W-247", "Loot rolls won", "key:won"],
      ["W-248", "Highest roll", "max"], ["W-277+W-278+W-279+W-280+W-281+W-283", "Chat messages sent", "n"],
      ["W-293", "Messages sent per hour played", "n"],
      ["W-302", "Emotes used", "n"], ["W-303", "Favorite emote", "top"], ["W-311", "Emotes aimed at you", "n"],
      ["W-296", "Trades", "n"], ["W-439", "Reputation earned", "n"], ["W-439", "Best friends with", "top"],
      ["W-442", "Bloodsail reputation gains", "n"], ["W-455", "Darkmoon Faire visits", "n"]],
    fun: [["W-276", "Red error messages", "n", "errors"], ["W-276.byMessage", "Most common error", "top", "topError"],
      ["W-264", "Inventory full", "n"], ["W-273", "Hearthstone on cooldown", "n"],
      ["W-268", "Casts interrupted", "n"], ["W-284", "Typed 'lol'", "n", "lols"], ["W-285", "Typed 'gz'", "n"],
      ["W-290", "Guild 'gz' on your dings", "n"], ["W-292", "Your most typed word", "top"],
      ["W-090", "Barrens chat about Chuck Norris", "n"]],
    pvp: [["W-140", "Enemy players killed", "n", "pvpKills"], ["W-141", "Lowbies ganked", "n"], ["W-144", "Times you got ganked", "n"],
      ["W-146", "Times corpse camped", "n"], ["W-169", "Longest kill streak", "max"], ["W-160", "Enemy guards killed", "n"],
      ["W-186", "Duels won", "key:won", "duelsWon"], ["W-186", "Duels lost", "key:lost"], ["W-171", "Battlegrounds won", "ends: won"],
      ["W-171", "Battlegrounds lost", "ends: lost"], ["W-182", "Honor earned", "n"], ["W-156", "Time flagged for PvP", "t"]],
    dungeons: [["W-194", "Wipes", "n", "wipes"], ["W-195", "Runs left before the last boss", "n"],
      ["W-226", "First to fall in a wipe", "n"], ["W-225", "Last one standing", "n"], ["W-229", "Blue boss drops", "n"],
      ["W-235", "Hearthed out of a dungeon", "n"], ["W-197", "Last bosses killed", "keys"], ["W-242", "Onyxia, first kill", "lvl"]],
    firsts: [["W-462", "First quest", "lvl", "firstQuest"], ["W-464", "First group", "lvl"], ["W-466", "First green item", "lvl"],
      ["W-471", "First flight", "lvl"], ["W-476", "First talent point", "lvl"], ["W-133", "First rare killed", "lvl"],
      ["W-468", "First enemy player killed", "lvl"], ["W-469", "First death to a player", "lvl"],
      ["W-472", "First boat or zeppelin", "lvl"], ["W-479", "First battleground", "lvl"],
      ["W-480", "First duel won", "lvl"], ["W-475", "First time Exalted", "lvl"], ["W-481", "First full rested bar", "lvl"]],
    habits: [["W-490", "Most kills in one session", "max", "sessionKills"], ["W-489", "Most deaths in one session", "max"],
      ["W-491", "Average time to your first kill", "avg:seconds:sessions"], ["W-496", "Most XP in one hour", "max"],
      ["W-498", "Time questing", "key:questing"], ["W-498", "Time grinding", "key:grinding"],
      ["W-487", "Dings after midnight", "list"], ["W-492", "Reloads", "n"], ["W-493", "Screenshots", "n"]]
  };
  // What each of those reads as: seconds, copper, a level, a name with a
  // count, or a plain number.
  var LITTLE_KIND = { t: "t", tmax: "t", "key:questing": "t", "key:grinding": "t", avg: "t", g: "g", gmax: "g",
                      sec: "s", lvl: "lvl", top: "top" };
  // Creature families (W-022..W-059), as the addon names them.
  var FAMILIES = { "W-022": "Murlocs", "W-024": "Kobolds", "W-025": "Gnolls", "W-026": "Defias", "W-027": "Harpies",
    "W-028": "Centaurs", "W-029": "Quilboar", "W-030": "Trolls", "W-031": "Ogres", "W-032": "Naga", "W-033": "Satyrs",
    "W-034": "Furbolgs", "W-035": "Troggs", "W-036": "Dark Iron dwarves", "W-037": "Scarlet Crusade",
    "W-038": "Syndicate", "W-039": "Venture Co.", "W-040": "Bloodsail pirates", "W-041": "Burning Blade",
    "W-042": "Undead", "W-043": "Spiders", "W-044": "Raptors", "W-045": "Crocolisks", "W-046": "Wolves",
    "W-047": "Boars", "W-048": "Bears", "W-049": "Gorillas", "W-050": "Scorpids", "W-051": "Kodos",
    "W-052": "Big cats", "W-053": "Dragonkin", "W-054": "Elementals", "W-055": "Demons", "W-056": "Yetis",
    "W-057": "Critters", "W-058": "Chickens", "W-059": "Rabbits and squirrels" };
  // Iconic firsts for the hero's milestones.
  var ICONIC_MARKS = [["W-060", "Killed Hogger"], ["W-063", "Killed VanCleef"], ["W-084", "Found Mankrik's wife"],
    ["W-086", "Killed Echeyakee"], ["W-111", "Killed King Bangalash"], ["W-242", "Killed Onyxia"],
    ["W-468", "First enemy player killed"], ["W-480", "First duel won"]];

  // One wrapped value, read as `how` says (see LITTLE).
  function littleValue(wr, id, how) {
    if (id.indexOf("+") >= 0) {
      return sum(id.split("+").map(function (one) { return number(littleValue(wr, one, how)); }));
    }
    var v = own(wr, id), map = named(v), rec = named(v);
    var kind = how.split(":")[0], arg = how.slice(kind.length + 1);
    if (kind === "n" || kind === "t" || kind === "g") return typeof v === "number" ? number(v) : addUp(map);
    if (kind === "max" || kind === "tmax" || kind === "gmax") return number(rec.value);
    if (kind === "sec") return Math.round(number(rec.value) * 10) / 10;
    if (kind === "key") return number(own(map, arg));
    if (kind === "ends") {
      return Object.keys(map).reduce(function (t, k) { return t + (k.slice(-arg.length) === arg ? number(map[k]) : 0); }, 0);
    }
    if (kind === "keys") return Object.keys(map).length;
    if (kind === "list") return listOf(v).length;
    if (kind === "avg") {
      var total = number(own(map, arg.split(":")[0])), count = number(own(map, arg.split(":")[1]));
      return count > 0 ? total / count : 0;
    }
    if (kind === "top") {
      var top = topRows(map, 1)[0];
      // An emote's token ("DANCE") reads as its name.
      return top ? { name: /^[A-Z]+$/.test(top[0]) ? capFirst(top[0].toLowerCase()) : top[0], n: top[1] } : null;
    }
    if (kind === "rec") rec = named(own(map, arg));   // one record of a map of them ("1g")
    if (kind === "lvl" || kind === "rec") {
      if (!(number(rec.level) > 0) || rec.before) return null;
      return { level: number(rec.level), name: typeof rec.name === "string" ? rec.name : null, late: !!rec.late };
    }
    return 0;
  }
  // The wrapped stats as the page shows them: { chapter: [[label, value,
  // kind]] } with only what has something in it, the creature families as
  // bars, the values a row's fourth field names for the chapter titles
  // (`at`), and the values the rankings read (`v`, `best`). Two the spec
  // leaves to the website are worked out here, given the journey's /played
  // and death records: chat messages sent per hour played (W-293), and the
  // average /played between deaths (W-357), from the /played each death
  // has (addon 0.6.0 on).
  function littleOf(wr, played, deaths) {
    var stats = Object.create(null);
    Object.keys(named(wr)).forEach(function (k) { stats[k] = wr[k]; });
    var sent = littleValue(stats, "W-277+W-278+W-279+W-280+W-281+W-283", "n");
    stats["W-293"] = played > 0 ? Math.round(sent / (played / 3600)) : 0;
    var between = 0, gaps = 0, last = null;
    listOf(deaths).forEach(function (d) {
      var at = named(d).played;
      if (typeof at !== "number" || !isFinite(at)) { last = null; return; }
      if (last !== null && at > last) { between += at - last; gaps++; }
      last = at;
    });
    stats["W-357"] = gaps ? between / gaps : 0;
    wr = stats;
    var out = { families: [], v: Object.create(null), at: Object.create(null) };
    Object.keys(LITTLE).forEach(function (chapter) {
      out[chapter] = [];
      LITTLE[chapter].forEach(function (r) {
        var value = littleValue(wr, r[0], r[2]);
        if (r[3]) out.at[r[3]] = value;
        if (value && (typeof value !== "number" || value > 0)) {
          out[chapter].push([r[1], value, own(LITTLE_KIND, r[2]) || own(LITTLE_KIND, r[2].split(":")[0]) || "n"]);
        }
      });
    });
    // The firsts in the order they happened.
    out.firsts.sort(function (a, b) { return a[1].level - b[1].level; });
    out.families = Object.keys(FAMILIES).map(function (id) { return [FAMILIES[id], number(own(wr, id))]; })
      .filter(function (r) { return r[1] > 0; }).sort(function (a, b) { return b[1] - a[1]; }).slice(0, 8);
    Object.keys(LITTLE_RANKED).forEach(function (key) {
      var spec = LITTLE_RANKED[key], value = littleValue(wr, spec[0], spec[1]);
      if (value && typeof value === "object") value = value.late ? undefined : value.level;
      if (typeof value === "number" && value > 0) out.v[key] = value;
    });
    out.best = Object.create(null);
    Object.keys(LITTLE_BEST).forEach(function (key) {
      var value = littleValue(wr, LITTLE_BEST[key][0], LITTLE_BEST[key][1]);
      if (value > 0) out.best[key] = value;
    });
    return out;
  }
  // Rankings the Statistics pane answers that the wrapped stats count too:
  // the bigger of the two counts (both start partway through a character).
  var LITTLE_BEST = {
    drownings: ["W-337", "n"], fatigueDeaths: ["W-338", "n"], duelsWon: ["W-186", "key:won"],
    duelsLost: ["W-186", "key:lost"], bgsWon: ["W-171", "ends: won"], needRolls: ["W-246", "key:need"],
    greedRolls: ["W-246", "key:greed"], portalsTaken: ["W-331", "n"], respecs: ["W-407", "n"],
    auctionsPosted: ["W-367", "n"], hugs: ["W-303", "key:HUG"], lols: ["W-303", "key:LOL"],
    cheers: ["W-303", "key:CHEER"], waves: ["W-303", "key:WAVE"], respecGold: ["W-376", "g"]
  };
  // The wrapped values the rankings use (site/rankings.js), by ranking key.
  var LITTLE_RANKED = {
    murlocs: ["W-022", "n"], murlocTrain: ["W-023", "max"], hogger: ["W-060", "lvl"], vanCleef: ["W-063", "lvl"],
    mankrik: ["W-084", "lvl"], echeyakee: ["W-086", "lvl"], bangalash: ["W-111", "lvl"], elevator: ["W-095", "n"],
    boat: ["W-075", "n"], zeppelins: ["W-330", "n"], soloElites: ["W-135", "n"],
    guardDeaths: ["W-339", "n"], afkDeaths: ["W-345", "n"], dingDeaths: ["W-343", "n"], loginDeaths: ["W-344", "n"],
    aliveStretch: ["W-355", "tmax"], swimming: ["W-313", "t"], lost: ["W-335", "n"],
    ganks: ["W-141", "n"], corpseCamped: ["W-146", "n"], killStreak: ["W-169", "max"],
    firstToFall: ["W-226", "n"], lastStanding: ["W-225", "n"], rollWins: ["W-247", "key:won"],
    chatty: ["W-277+W-278+W-279+W-280+W-281+W-283", "n"], typedLol: ["W-284", "n"], gz: ["W-285", "n"],
    guildGz: ["W-290", "n"], emotes: ["W-302", "n"], bloopers: ["W-276", "n"], hearthCooldown: ["W-273", "n"],
    junkSold: ["W-359", "n"], bigPurchase: ["W-362", "gmax"], broke: ["W-378", "n"], chests: ["W-381", "n"],
    itemsEquipped: ["W-394", "n"], repairBill: ["W-400", "gmax"], enchanted: ["W-401", "n"],
    fishingSession: ["W-425", "tmax"], cooked: ["W-426", "n"], explosives: ["W-432", "n"], gems: ["W-415", "n"],
    repGained: ["W-439", "n"], bloodsail: ["W-442", "n"], sessionKills: ["W-490", "max"], xpHour: ["W-496", "max"],
    reloads: ["W-492", "n"], screenshots: ["W-493", "n"], lateDings: ["W-487", "list"],
    firstGold: ["W-467", "rec:1g"], firstFlight: ["W-471", "lvl"]
  };

  // ---- What a journey is ranked on ----
  // Class rankings an export can answer, from what the class tracker saved:
  // spells cast, time in each state, buffs cast on others, swaps and power
  // spent. "Teleport: *" counts every spell starting so, "*Totem" every one
  // ending so.
  var CLASS_CASTS = {
    charges: ["Charge", "Intercept"], overpowers: ["Overpower"], executes: ["Execute"],
    shouts: ["Battle Shout", "Demoralizing Shout", "Intimidating Shout", "Challenging Shout"],
    sunders: ["Sunder Armor", "Rend"], hamstrings: ["Hamstring", "Piercing Howl"],
    panicButtons: ["Shield Wall", "Last Stand", "Retaliation", "Recklessness", "Berserker Rage"],
    warriorInterrupts: ["Pummel", "Shield Bash"], cleaves: ["Thunder Clap", "Cleave", "Whirlwind"],
    judgements: ["Judgement"], layOnHands: ["Lay on Hands"], bubbles: ["Divine Shield", "Divine Protection"],
    hammers: ["Hammer of Justice"], paladinHeals: ["Holy Light", "Flash of Light"], redemptions: ["Redemption"],
    exorcisms: ["Exorcism", "Turn Undead"], consecrations: ["Consecration"], cleanses: ["Cleanse", "Purify"],
    warhorse: ["Summon Warhorse", "Summon Charger"],
    feeds: ["Feed Pet"], mends: ["Mend Pet"], feigns: ["Feign Death"],
    traps: ["Freezing Trap", "Immolation Trap", "Frost Trap", "Explosive Trap"],
    shots: ["Arcane Shot", "Aimed Shot", "Multi-Shot", "Concussive Shot", "Scatter Shot", "Serpent Sting"],
    marks: ["Hunter's Mark"],
    openers: ["Cheap Shot", "Ambush", "Garrote", "Sap"], pickPockets: ["Pick Pocket"], locks: ["Pick Lock"],
    finishers: ["Eviscerate", "Slice and Dice", "Kidney Shot", "Rupture", "Expose Armor"],
    escapes: ["Vanish", "Sprint", "Evasion"], kicks: ["Kick"], blinds: ["Gouge", "Blind"],
    stabs: ["Sinister Strike", "Backstab", "Hemorrhage"],
    shields: ["Power Word: Shield"], priestHeals: ["Renew", "Lesser Heal", "Heal", "Flash Heal", "Greater Heal"],
    resurrections: ["Resurrection"], shadowSpells: ["Shadow Word: Pain", "Mind Blast", "Mind Flay"],
    screams: ["Psychic Scream", "Fade"], mindControls: ["Mind Control"], levitates: ["Levitate"],
    wandShots: ["Shoot"], holyNovas: ["Holy Nova"],
    totems: ["*Totem"], reincarnations: ["Reincarnation"],
    imbues: ["Rockbiter Weapon", "Flametongue Weapon", "Frostbrand Weapon", "Windfury Weapon"],
    shocks: ["Earth Shock", "Flame Shock", "Frost Shock"], lightning: ["Lightning Bolt", "Chain Lightning"],
    shamanHeals: ["Healing Wave", "Lesser Healing Wave", "Chain Heal"], lightningShields: ["Lightning Shield"],
    astralRecalls: ["Astral Recall"], ancestralSpirits: ["Ancestral Spirit"],
    waterWalks: ["Water Walking", "Water Breathing"],
    teleports: ["Teleport: *"], portals: ["Portal: *"], polymorphs: ["Polymorph*"],
    novas: ["Frost Nova", "Blink", "Ice Block", "Ice Barrier"], counterspells: ["Counterspell"],
    evocations: ["Evocation"], fireballs: ["Fireball"], frostbolts: ["Frostbolt"],
    mageAoE: ["Arcane Explosion", "Blizzard"], slowFalls: ["Slow Fall"],
    summonings: ["Ritual of Summoning"], lifeTaps: ["Life Tap"], fears: ["Fear", "Howl of Terror", "Death Coil"],
    dots: ["Corruption", "Curse of Agony", "Immolate", "Siphon Life"], felsteed: ["Summon Felsteed"],
    demonsSummoned: ["Summon Imp", "Summon Voidwalker", "Summon Succubus", "Summon Felhunter", "Inferno", "Ritual of Doom"],
    rebirths: ["Rebirth", "Innervate"], moonfires: ["Wrath", "Moonfire", "Starfire", "Insect Swarm"],
    catAbilities: ["Claw", "Shred", "Rake", "Rip", "Ferocious Bite", "Ravage", "Pounce"],
    bearAbilities: ["Maul", "Swipe", "Growl", "Demoralizing Roar", "Bash", "Feral Charge"],
    roots: ["Entangling Roots", "Hibernate"], moonglade: ["Teleport: Moonglade"], faerieFires: ["Faerie Fire*"],
    // Racial abilities, whatever the class (ALL-09: the addon's list, Classic's names)
    racials: ["Will of the Forsaken", "Cannibalize", "Stoneform", "Find Treasure", "Escape Artist", "Perception",
              "Shadowmeld", "War Stomp", "Berserking", "Blood Fury"]
  };
  var CLASS_TIMES = {   // [state group, state names...]; no names = the whole group
    battleStance: ["stance", "Battle Stance"], defensiveStance: ["stance", "Defensive Stance"],
    berserkerStance: ["stance", "Berserker Stance"], sealTime: ["seal"], auraTime: ["aura", "Devotion Aura"],
    hawk: ["aspect", "Aspect of the Hawk"], cheetah: ["aspect", "Aspect of the Cheetah"],
    stealth: ["stealth", "Stealth"], prowl: ["stealth", "Prowl"], shadowform: ["shadowform"], ghostWolf: ["ghostwolf"],
    cat: ["form", "Cat Form"], bear: ["form", "Bear Form", "Dire Bear Form"], travelForm: ["form", "Travel Form"],
    aquatic: ["form", "Aquatic Form"], casterForm: ["form", "Caster Form"]
  };
  var CLASS_BUFFS = { blessings: ["Blessing of*", "Greater Blessing of*"],
    fortitudes: ["Power Word: Fortitude", "Prayer of Fortitude", "Divine Spirit"],
    intellects: ["Arcane Intellect", "Arcane Brilliance"], wildMarks: ["Mark of the Wild", "Gift of the Wild", "Thorns"] };
  function spellIn(name, patterns) {
    return patterns.some(function (p) {
      if (p.charAt(p.length - 1) === "*") return name.indexOf(p.slice(0, -1)) === 0;
      if (p.charAt(0) === "*") return name.slice(1 - p.length) === p.slice(1);
      return name === p;
    });
  }
  function classValues(J, v) {
    function spells(map, patterns, read) {
      return Object.keys(map).reduce(function (t, name) { return t + (spellIn(name, patterns) ? number(read(map[name])) : 0); }, 0);
    }
    Object.keys(CLASS_CASTS).forEach(function (key) { v[key] = spells(J.casts, CLASS_CASTS[key], Number); });
    Object.keys(CLASS_TIMES).forEach(function (key) {
      var spec = CLASS_TIMES[key], group = named(own(J.classTime, spec[0]));
      v[key] = spec.length > 1 ? spec.slice(1).reduce(function (t, name) { return t + number(own(group, name)); }, 0) : addUp(group);
    });
    Object.keys(CLASS_BUFFS).forEach(function (key) {
      v[key] = spells(J.targets, CLASS_BUFFS[key], function (t) { return named(t).other; });
    });
    v.stanceSwaps = number(named(own(J.swaps, "stance")).total);
    v.shifts = number(named(own(J.swaps, "form")).total);
    v.rage = number(own(J.powerSpent, "RAGE"));
    v.priestMana = number(own(J.powerSpent, "MANA"));
    // The class's own counters (JourneyTrackerClass.lua): weapon swaps, the
    // class quest weapon, bubble hearths, ammo, pets and demons (a hunter's
    // by name, a warlock's by family; the favorite is the one out longest),
    // pockets, poisons, combo points, conjuring, shards and stones.
    var c = named(J.classStats), obtained = named(c.obtained), ammo = named(c.ammo), pets = named(c.pets);
    var conjured = named(c.conjured), shards = named(c.shards), stones = named(c.stones);
    v.weaponSwaps = number(c.weaponSwaps);
    v.whirlwindAxe = ["Whirlwind Axe", "Whirlwind Sword", "Whirlwind Heart"].reduce(function (first, name) {
      var got = named(own(obtained, name)), at = number(got.level);
      return at > 0 && !got.before && (!first || at < first) ? at : first;
    }, 0) || undefined;
    v.bubbleHearths = number(c.bubbleHearths);
    v.ammo = addUp(ammo.used);
    v.ammoGold = number(ammo.gold);
    v.outOfAmmo = number(ammo.outOfAmmo);
    v.tamed = listOf(pets.tamed).length;
    v.petTime = listOf(pets.time).reduce(function (most, s) { return Math.max(most, number(s)); }, 0);
    v.petDeaths = v.demonDeaths = addUp(pets.deaths);
    v.voidwalker = number(own(named(pets.time), "Voidwalker"));
    v.pocketGold = number(named(c.pickpocket).gold);
    v.poisons = addUp(named(c.poisons).applied);
    var points = 0, finishers = 0;
    listOf(c.combo).forEach(function (f) { points += number(named(f).points); finishers += number(named(f).casts); });
    v.comboPoints = finishers > 0 ? points / finishers : undefined;
    v.conjured = addUp(conjured.water);
    v.conjuredFood = addUp(conjured.food);
    v.givenAway = addUp(conjured.given);
    v.manaGems = addUp(conjured.gemsUsed);
    v.shards = addUp(shards.gained);
    v.shardsPeak = number(shards.peak);
    v.healthstonesMade = addUp(own(stones, "Healthstone"));
    v.soulstones = addUp(own(stones, "Soulstone"));
    v.selfRez = number(c.soulstoneRez);
    var all = J.classAll, potions = named(all.potions);
    v.bandages = addUp(all.bandages);
    v.healPotions = Math.max(addUp(potions.healing), J.pane[345] || 0);
    v.manaPotions = Math.max(addUp(potions.mana), J.pane[922] || 0);
    v.cookies = addUp(all.healthstones);
    v.mageFood = addUp(all.conjured);
    v.food = addUp(all.food);
    v.buffs = addUp(named(all.buffs).bySpell);
    v.summoned = typeof all.summons === "number" ? number(all.summons) : listOf(all.summons).length;
    v.trainerVisits = listOf(all.trainerVisits).length;
    v.classQuests = listOf(all.classQuests).length;
  }
  var PROFESSION_KEYS = { Alchemy: "alchemy", Blacksmithing: "blacksmithing", Enchanting: "enchanting",
    Engineering: "engineering", Herbalism: "herbalism", Leatherworking: "leatherworking", Mining: "mining",
    Skinning: "skinning", Tailoring: "tailoring", Cooking: "cooking", "First Aid": "firstAid", Fishing: "fishing" };

  // A journey's values, keyed like the rankings, and who it is (class, race,
  // faction, realm type, primary professions) for the rankings that only
  // apply to some. The sample journey has about a third of the values; the
  // page makes up the rest. An export is ranked only on what it has. Rates
  // are per hour of /played, since an export's counts include the game's
  // lifetime statistics. A share (of XP, of playtime) needs enough behind it
  // first: 100% of 200 XP from exploring isn't a ranking.
  function profileOf(J, rankings) {
    var total = J.played, rateTime = total / 3600, trackedTime = J.trackedTime || total, perLevel = J.perLevel;
    var slowest = -1;
    perLevel.forEach(function (sec, i) { if (sec > 0 && (slowest < 0 || sec > perLevel[slowest])) slowest = i; });
    // The zone you spent longest in (from an export's own zone times).
    var home = J.path.reduce(function (best, p) { return p[3] > 0 && (!best || p[3] > best[3]) ? p : best; }, null);
    var earned = J.earnedTotal !== undefined ? J.earnedTotal : sum(J.earned.map(function (r) { return r[1]; }));
    var spent = J.spentTotal !== undefined ? J.spentTotal : sum(J.spent.map(function (r) { return r[1]; }));
    function part(rows, name) {
      var row = rows.filter(function (r) { return r[0] === name; })[0];
      return row ? row[1] : 0;
    }
    function first(rows) { return rows.length ? rows[0][1] : undefined; }
    var hourSum = sum(J.hourWeights);
    var enoughXP = !J.imported || J.xpTotal >= 10000;
    var enoughHours = !J.imported || hourSum >= 5 * 3600;
    var enoughTime = !J.imported || trackedTime >= 5 * 3600;
    function when(enough, value) { return enough ? value : undefined; }
    // An export is ranked against others at its milestone (the sample is a 60).
    var p = {
      label: "You", classToken: J.classToken, className: J.className, race: J.race, faction: J.faction,
      ruleset: J.ruleset, trades: J.trades, partial: !J.complete, milestone: J.imported ? J.milestone : 60,
      names: { mob: J.topMobs.length ? J.topMobs[0][0] : "", zone: J.deathZones.length ? J.deathZones[0][0] : "",
               quest: J.longestQuest && J.longestQuest.title || "Your longest quest",
               item: J.wornPlayed ? "[" + J.wornPlayed.name + "]" : "", kept: J.wornLevels ? "[" + J.wornLevels.name + "]" : "",
               fav: home ? home[0] : "" },
      values: {
        // Time to the milestone: from its level-up (none before level 10).
        played: J.imported ? J.playedTo : total, days: J.imported ? J.daysTo : J.calendarDays, sessions: J.sessions,
        avgSession: J.imported ? J.avgSession || undefined : J.avgSession || total / J.sessions,   // an export's 0: unknown
        session: J.longestSession, sessionLevels: J.bestSession && J.bestSession.levels, daysPlayed: J.daysPlayed,
        afk: part(J.timeSpent, "AFK"), resting: part(J.timeSpent, "Resting in inns and cities"),
        taxiTime: part(J.timeSpent, "On flight paths"), mounted: part(J.timeSpent, "Mounted"),
        combatTime: part(J.timeSpent, "In combat"), timeDead: J.timeDead, slowestLevel: perLevel[slowest],
        nightOwl: when(hourSum && enoughHours, sum(J.hourWeights.slice(0, 5)) / hourSum * 100),
        earlyBird: when(hourSum && enoughHours, sum(J.hourWeights.slice(5, 9)) / hourSum * 100),
        rested: when(enoughXP, J.restedShare), questXP: when(enoughXP, part(J.xpSplit, "Quests")),
        killXP: when(enoughXP, part(J.xpSplit, "Kills")), exploreXP: when(enoughXP, part(J.xpSplit, "Exploration")),
        kills: J.kills, killRate: J.kills / rateTime, topMob: first(J.topMobs), elites: J.elites, rares: J.rares,
        gap: J.bestKill ? J.bestKill.mob - J.bestKill.you : undefined, fight: J.longestFight, bosses: J.bosses,
        honor: J.honorKills, deaths: J.deaths, zoneDeaths: first(J.deathZones), dungeonDeaths: J.dungeonDeaths,
        corpseRuns: J.rez.corpse, spiritRez: J.rez.spirit, playerRez: J.rez.player, streak: J.streak && J.streak.levels,
        pvpDeaths: part(J.killers, "Players (PvP)") || part(J.killers, "Player (PvP)"),
        fallDeaths: J.fallDeaths !== undefined ? J.fallDeaths : part(J.killers, "Falling"),
        quests: J.quests.completed, questRate: J.quests.completed / rateTime, zoneQuests: first(J.questZones),
        questGold: part(J.earned, "Quest rewards"), accepted: J.quests.accepted, abandoned: J.quests.abandoned,
        questDays: J.longestQuest && J.longestQuest.days, groupQuests: J.quests.group, forever: J.quests.forever,
        zoneTime: home ? home[3] : undefined, hearths: J.travel.hearths, flightPaths: J.travel.flightPaths,
        flights: J.travel.flights, ground: J.travel.groundYards / 1760, air: J.travel.airYards / 1760,
        fallen: J.travel.fallen, longestFall: J.travel.longestFall,
        earned: earned, spent: spent, saved: earned - spent, peakGold: J.peakGold && J.peakGold.copper,
        lootGold: part(J.earned, "Looting"), vendorGold: part(J.earned, "Selling to vendors"),
        auctions: part(J.earned, "Auction house sales"), auctionSpend: part(J.spent, "Auction house"),
        training: part(J.spent, "Class training"), repairs: part(J.spent, "Repairs"),
        flightGold: part(J.spent, "Flights"), mount: J.firstMountLevel || undefined,
        looted: J.looted !== undefined ? J.looted : sum(J.loot.map(function (l) { return l[1]; })),
        grays: part(J.loot, "Poor"), greens: part(J.loot, "Uncommon"), rareLoot: part(J.loot, "Rare"),
        epics: part(J.loot, "Epic"), firstBlue: J.firstBlue && J.firstBlue.level,
        worn: J.wornPlayed && J.wornPlayed.played, wornLevels: J.wornLevels && J.wornLevels.levels,
        crafted: J.crafted, fish: J.fish, skillUps: J.skillUps, skinned: J.skinned,
        maxed: J.professions.filter(function (r) { return r[1] >= 300; }).length,
        grouped: when(enoughTime, J.grouped / trackedTime * 100), solo: when(enoughTime, (1 - J.grouped / trackedTime) * 100),
        groupedWith: J.groupedWith,
        guild: J.guildLevel || undefined, jumps: J.jumps, jumpEvery: J.jumps ? trackedTime / J.jumps : undefined,
        camps: J.camps, campTime: J.campTime, campBuffs: J.campBuffs, transmog: J.transmog, healing: J.healing
      }
    };
    J.professions.forEach(function (r) { if (own(PROFESSION_KEYS, r[0])) p.values[PROFESSION_KEYS[r[0]]] = r[1]; });
    if (J.imported) {
      var types = J.killTypes;
      Object.assign(p.values, {
        beasts: types.Beast || 0, humanoids: types.Humanoid || 0, undead: types.Undead || 0, demons: types.Demon || 0,
        elementals: types.Elemental || 0, dragonkin: types.Dragonkin || 0, mobTypes: J.mobKinds,
        levelKills: J.levelKills, levelDeaths: J.levelDeaths, levelQuests: J.levelQuests, fights: J.fights,
        avgFight: J.fights ? part(J.timeSpent, "In combat") / J.fights : undefined, ambushes: J.ambushes,
        multiPulls: J.multiPulls, maxMobs: J.maxMobs, wipes: J.wipes, groupDeaths: J.groupDeaths,
        corpseTime: J.corpseTime, graveyards: J.graveyards, zonesVisited: J.zonesVisited, subzones: J.subzones,
        zoneChanges: J.zoneChanges, dungeonQuests: J.quests.dungeon, groupXP: when(enoughXP, J.groupXP),
        auctionsSold: J.auctionsSold,
        mountPlayed: J.firstMountPlayed || undefined, firstEpic: J.firstEpic && J.firstEpic.level,
        bestItem: J.bestLoot && J.bestLoot.ilvl, herbs: J.herbs, ore: J.ore, campShops: J.campShops,
        campCrafts: J.campCrafts, valthalak: J.valthalak, autoFlagged: J.autoFlagged, zephras: J.zephras || undefined,
        hyjal: J.hyjal, xpRate: J.xpRate, dungeonsEntered: J.dungeonsEntered, dungeonTypes: J.dungeonTypes,
        runs: J.dungeonRuns, fastRun: J.fastestRun
      });
      classValues(J, p.values);
    }
    // The wrapped stats' own rankings.
    var little = J.little || { v: {}, best: {} };
    Object.keys(little.v).forEach(function (k) { p.values[k] = little.v[k]; });
    // Every ranking from the game's Statistics pane, by statistic ID, or the
    // wrapped stats' count of the same thing if that's bigger.
    rankings.forEach(function (r) {
      var id = /^P-(\d+)$/.exec(r.source);
      if (id && J.pane[id[1]] !== undefined) p.values[r.key] = J.pane[id[1]];
    });
    Object.keys(little.best).forEach(function (k) { p.values[k] = Math.max(number(p.values[k]), little.best[k]); });
    // A late journey (J.late) is ranked only on what was settled when it
    // reached its milestone: the time it took and the levels it did things
    // at (the rankings marked `fixed`). Its other totals kept growing after.
    if (J.late) {
      var fixed = Object.create(null);
      rankings.forEach(function (r) { if (r.fixed) fixed[r.key] = true; });
      Object.keys(p.values).forEach(function (k) { if (!fixed[k]) delete p.values[k]; });
    }
    p.since = J.since;
    p.late = !!J.late;
    return p;
  }

  // A profile as saved with its upload, for ranking others against: who it
  // is, its ranked values (to three decimals, the same for everyone), and
  // how long after its milestone it was exported (site/api/ranks.js picks
  // each character's freshest).
  function rounded(v) { return Math.round(v * 1000) / 1000; }
  function saved(p, rankings) {
    var values = {};
    rankings.forEach(function (r) {
      var v = p.values[r.key];
      if (typeof v === "number" && isFinite(v)) values[r.key] = rounded(v);
    });
    return { model: MODEL, classToken: p.classToken, race: p.race, faction: p.faction, ruleset: p.ruleset,
             trades: p.trades.slice(), partial: p.partial, milestone: p.milestone,
             since: typeof p.since === "number" && isFinite(p.since) ? Math.round(p.since) : undefined,
             late: p.late || undefined, values: values };
  }

  // Whether a ranking applies: a number to rank that the game allows (none
  // is negative; levels, skills and shares have their limits), the right
  // class, race, faction or realm, the profession it's about, the milestone
  // it's for (some only mean something at 60), and (where more is notable)
  // something to count. Where less is notable (fewest deaths, fastest to
  // 30), only a journey tracked from level 1 to its milestone counts.
  function applies(r, p) {
    var v = p.values[r.key];
    if (typeof v !== "number" || !isFinite(v) || v < 0) return false;
    if ((r.min !== undefined && v < r.min) || (r.max !== undefined && v > r.max)) return false;
    if (r.trade && p.trades.indexOf(r.trade) < 0) return false;
    if (r.at60 && p.milestone !== undefined && p.milestone !== 60) return false;
    if (r.high ? !(v > 0) : p.partial) return false;
    return !r.only || Object.keys(r.only).every(function (k) { return [].concat(r.only[k]).indexOf(p[k]) >= 0; });
  }
  var COHORT_FIELDS = { class: "classToken", race: "race", faction: "faction", ruleset: "ruleset" };
  var RACE_PLURAL = { "Night Elf": "Night Elves", Dwarf: "Dwarves", Undead: "Undead", Tauren: "Tauren", Skyborne: "Skyborne" };
  // Who a place is among: "Druids", or below 60 "Level 30 Druids".
  function cohortLabel(r, p) {
    var at = p.milestone === undefined || p.milestone >= 60 ? "" : p.milestone ? "Level " + p.milestone + " " : "Level 1-9 ";
    if (r.cohort === "class") return at + p.className + "s";
    if (r.cohort === "race") return at + (own(RACE_PLURAL, p.race) || (p.race + "s"));
    if (r.cohort === "faction") return at + p.faction + " players";
    if (r.cohort === "ruleset") return at + p.ruleset + " realm players";
    return at ? at + "players" : "All players";
  }

  // Where a saved profile places on each ranking that applies to it, against
  // the others at its milestone in its cohort (its class, race, faction,
  // realm type or everyone) that the ranking applies to: { ranking id:
  // [place, players] }, 1 the best and ties sharing the better place.
  // Rankings with fewer than MIN_PLAYERS players are left out.
  function placesFor(me, others, rankings) {
    var out = {};
    others = others.filter(function (q) {
      return q.milestone === undefined || me.milestone === undefined || q.milestone === me.milestone;
    });
    rankings.forEach(function (r) {
      if (!applies(r, me)) return;
      var field = COHORT_FIELDS[r.cohort], mine = me.values[r.key], place = 1, players = 1;
      others.forEach(function (q) {
        if ((field && q[field] !== me[field]) || !applies(r, q)) return;
        players++;
        if (r.high ? q.values[r.key] > mine : q.values[r.key] < mine) place++;
      });
      if (players >= MIN_PLAYERS) out[r.id] = [place, players];
    });
    return out;
  }
  function ordinal(n) {
    var ends = ["th", "st", "nd", "rd"], v = n % 100;
    return n + (ends[(v - 20) % 10] || ends[v] || ends[0]);
  }

  // A ranking's text, with the player's number and names filled in ("1
  // deaths" reads "1 death"). Below 10 a journey has no milestone yet, so
  // "kept at {m}" reads "kept before 10" and "on the way to {m}" "on the
  // way to 10".
  function fill(text, v, p) {
    if (Math.round(v) === 1) {
      text = text.replace(/\{n\} ([a-z\/]*[^su\W]s)\b(?!,| and | [a-z]+s\b)/gi, function (all, word) { return "{n} " + word.slice(0, -1); });
    }
    if (p.milestone === 0) text = text.replace(/\bat \{m\}/g, "before {m}");
    return text.replace(/\{(\w+)\}/g, function (all, k) {
      if (k === "m") return String(p.milestone === 0 ? 10 : p.milestone || 60);
      if (k === "n") return num(v);
      if (k === "t") return dur(v);
      if (k === "g") return coins(v);
      if (k === "p") return String(Math.round(v));
      if (k === "d") return (Math.round(v * 10) / 10).toFixed(1);
      return p.names[k] !== undefined ? p.names[k] : all;
    });
  }
  // One ranking for a profile, ready to show. `place` is [place, players]
  // from placesFor; without one, `share` (the made-up share of players at or
  // past the value) says where it stands. big + who read as "Top 3%" "of
  // monster slayers" or "2nd" "of 9 monster slayers".
  function standing(r, p, place, share) {
    var v = p.values[r.key], name = fill(r.name, v, p), x;
    if (place && place[1] < SHARE_FROM) {
      x = { place: place[0], players: place[1], big: ordinal(place[0]), who: "of " + place[1] + " " + name };
    } else {
      if (place) share = place[0] / place[1];
      x = { share: share, top: Math.max(1, Math.ceil(share * 100)), who: "of " + name };
      x.big = "Top " + x.top + "%";
      if (place) { x.place = place[0]; x.players = place[1]; }
    }
    // Best first: the share of players ahead, counting from the middle of a
    // place (1st of 3 comes after 1st of 50).
    x.score = place ? (place[0] - 0.5) / place[1] : share;
    x.r = r;
    x.name = name;
    x.detail = fill(r.detail, v, p);
    x.line = fill(r.line, v, p);
    x.cohort = cohortLabel(r, p);
    return x;
  }
  // The ones to show: the best, at most two from any one part of the game and
  // one from any family.
  function picksFor(all, count) {
    var picks = [], perGroup = {}, families = {};
    all.forEach(function (x) {
      var family = x.r.family || x.r.key;
      if (picks.length >= count || (perGroup[x.r.group] || 0) >= 2 || families[family]) return;
      picks.push(x);
      perGroup[x.r.group] = (perGroup[x.r.group] || 0) + 1;
      families[family] = true;
    });
    return picks;
  }
  function bestFirst(a, b) { return a.score - b.score || (b.players || 0) - (a.players || 0); }

  // A journey in brief, kept with each saved one (payload.summary, from
  // site/api/ranks.js) for its character's page: what changed between two of
  // its saves, and how it compares with another character's. A few KB, so a
  // page reads that instead of each save's export in full. Bump SUMMARY when
  // it changes: older ones are worked out again (site/api/character.js).
  var SUMMARY = 1;
  function summaryOf(J) {
    return {
      v: SUMMARY, level: J.level, played: J.played, exportedAt: J.exportedAt,
      race: J.race, className: J.className, classToken: J.classToken, faction: J.faction, ruleset: J.ruleset,
      milestone: J.milestone, atMilestone: J.atMilestone, playedTo: J.playedTo, daysTo: J.daysTo, complete: J.complete,
      kills: J.kills, deaths: J.deaths, quests: J.quests.completed, earned: J.earnedTotal, bosses: J.bosses,
      runs: J.dungeonRuns, honor: J.honorKills, elites: J.elites, jumps: J.jumps,
      miles: Math.round((J.travel.groundYards + J.travel.airYards) / 176) / 10,
      // The zones in the order reached, and the moments along the way: [level, what].
      zones: J.path.map(function (p) { return p[0]; }),
      marks: J.milestones.map(function (m) { return [m[0], m[1]]; }),
      // Each tenth level-up the tracker saw, with its running totals.
      tens: J.milestoneRows.map(function (r) {
        return { level: r.level, t: r.t, days: r.days, played: r.played || 0, kills: r.kills, deaths: r.deaths, quests: r.quests };
      })
    };
  }

  return {
    MODEL: MODEL, MIN_PLAYERS: MIN_PLAYERS, SHARE_FROM: SHARE_FROM, LATE_AFTER: LATE_AFTER, SUMMARY: SUMMARY,
    summaryOf: summaryOf,
    sum: sum, num: num, dur: dur, coins: coins, named: named, number: number, numbered: numbered, listOf: listOf,
    addUp: addUp, topRows: topRows, tally: tally, capFirst: capFirst, dayOf: dayOf, own: own, itemOf: itemOf,
    milestoneOf: milestoneOf,
    paneNumber: paneNumber, CLASS_NAMES: CLASS_NAMES, RACE_NAMES: RACE_NAMES,
    journeyFromExport: journeyFromExport, littleOf: littleOf, profileOf: profileOf, saved: saved, applies: applies,
    cohortLabel: cohortLabel, placesFor: placesFor, ordinal: ordinal, fill: fill, standing: standing,
    picksFor: picksFor, bestFirst: bestFirst
  };
})();
if (typeof module === "object" && module.exports) module.exports = JourneyModel;
