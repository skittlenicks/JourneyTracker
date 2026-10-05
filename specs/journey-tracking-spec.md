# Journey Tracker: Stats to Track (1-60)

Items marked **[probe]** depend on data that may be secret or restricted in combat under the Forever/Midnight API. Confirm with the probe addon before building them. Event/API hints are starting points, not guarantees.

## Status tracking (read this first, every session)
Every item has a status tag. This file is the source of truth for what's done.

| Tag | Meaning |
| --- | --- |
| `TODO` | Not started |
| `BUILT` | Code written, not yet tested in game |
| `VERIFIED` | Tested in game and confirmed saving correct data |
| `BLOCKED` | Data is secret/restricted on Forever. Add a short note why |
| `SKIP` | Decided not to track |

Rules for Claude:
1. Before writing any code, read this file and the existing addon code. Do NOT rewrite, refactor, or "improve" anything tagged `VERIFIED` unless I explicitly ask. If a change truly requires touching verified code, stop and tell me first.
2. Only work on `TODO` items, plus `BUILT` items I report as broken.
3. Before adding tracking for an item, search the code for an existing handler for that event or field so you don't duplicate it. Several items share one event (e.g. PLAYER_MONEY), so extend the existing handler instead of registering a new one.
4. After writing code for an item, change its tag to `BUILT`. Never mark anything `VERIFIED` yourself. Only I do that after testing in game.
5. When I report test results, update tags to `VERIFIED` or `BLOCKED` with a short note, e.g. `BLOCKED` (mob name is SECRET in combat, build 69913).
6. Keep a short "Changelog" section at the bottom of this file: date, items touched, one line each.
7. Add a comment in the Lua next to each tracker with its item number (e.g. `-- #44 total deaths`) so items can be traced between this file and the code.

## Implementation notes
- Snapshot key stats at every ding so the website can chart per-level.
- Never index, compare, or store a value without checking issecretvalue() first.
- Queue in-combat data and process it on PLAYER_REGEN_ENABLED.
- Don't store other players' names. Counts only.
- Sample player position on a timer (every ~5s, out of combat only) instead of every frame.
- Version the saved data schema so old exports still parse.

## Time and pace
1. `BUILT` Total /played from 1 to 60 (TIME_PLAYED_MSG)
2. `BUILT` /played at each level ding (RequestTimePlayed on PLAYER_LEVEL_UP)
3. `BUILT` /played spent on each individual level
4. `BUILT` Real-world calendar time from first login to 60
5. `BUILT` Real-world timestamp of every ding
6. `BUILT` Number of play sessions (PLAYER_LOGIN / PLAYER_LOGOUT)
7. `BUILT` Average session length
8. `BUILT` Longest single session
9. `BUILT` Most levels gained in one session
10. `BUILT` Time spent AFK (UnitIsAFK)
11. `BUILT` Time resting in inns/cities (IsResting)
12. `BUILT` Time spent dead (death to resurrect)
13. `BUILT` Time on flight paths (UnitOnTaxi)
14. `BUILT` Time mounted (IsMounted)
15. `BUILT` XP per hour, overall and per level
16. `BUILT` Fastest and slowest level
17. `BUILT` Distinct calendar days played
18. `BUILT` Playtime by hour of day (for a heatmap)

## Leveling
19. `BUILT` Zone at each ding
20. `BUILT` Map coordinates at each ding (C_Map.GetPlayerMapPosition)
21. `BUILT` What caused each ding: quest, kill, exploration, other
22. `BUILT` Total rested XP used (GetXPExhaustion)
23. `BUILT` XP split: quests vs kills vs exploration vs other
24. `BUILT` Total XP earned
25. `BUILT` XP earned solo vs grouped

## Combat and kills
26. `BUILT` Total XP-granting kills (CHAT_MSG_COMBAT_XP_GAIN)
27. `BUILT` Kills per level
28. `BUILT` Kill counts by mob name [probe] (name parsed from the XP kill message; probe build 70124: mob names, classification, type and level readable in combat)
29. `BUILT` Most killed mob [probe]
30. `BUILT` Elite kills (UnitClassification) [probe]
31. `BUILT` Rare and rare-elite kills [probe]
32. `BUILT` Kills by creature type: beast, humanoid, undead, etc. (UnitCreatureType) [probe]
33. `BUILT` Highest level mob killed relative to your level [probe]
34. `BUILT` Total combats entered (PLAYER_REGEN_DISABLED)
35. `BUILT` Longest single fight
36. `BUILT` Average fight duration
37. `BUILT` Total time in combat
38. `BUILT` Fights that ended in your death
39. `BUILT` Mobs that aggroed before you targeted them [probe] (threat on nameplates; needs enemy nameplates on)
40. `BUILT` Multi-mob pulls, using nameplates in combat [probe] (2+ mobs with threat at once; needs enemy nameplates on)
41. `BUILT` Dungeon boss kills (ENCOUNTER_END success)
42. `BUILT` Dungeon boss wipes and attempts per boss
43. `BUILT` PvP honorable kills (PLAYER_PVP_KILLS_CHANGED)

## Deaths
44. `BUILT` Total deaths (PLAYER_DEAD)
45. `BUILT` Deaths per level
46. `BUILT` Zone and coordinates of every death
47. `BUILT` What killed you: last cached target or mob in that fight [probe] (a hostile targeted more than a minute before isn't used)
48. `BUILT` Deaths solo vs grouped vs in dungeons
49. `BUILT` Resurrection type: corpse run, spirit healer, player res (AcceptXPLoss missing on Forever; spirit healer detected from its dialog)
50. `BUILT` Time spent on corpse runs
51. `BUILT` Deadliest zone
52. `BUILT` Longest streak of levels with no deaths

## Quests
53. `BUILT` Quests completed (QUEST_TURNED_IN)
54. `BUILT` Quests completed per level
55. `BUILT` Quests completed per zone
56. `BUILT` XP earned from quests
57. `BUILT` Gold earned from quests
58. `BUILT` Quests accepted (QUEST_ACCEPTED)
59. `BUILT` Quests abandoned (hook AbandonQuest)
60. `BUILT` Longest-held quest, accept to turn-in
61. `BUILT` Group/elite quests completed [probe]
62. `BUILT` Dungeon quests completed

## Exploration and travel
63. `BUILT` Zones visited, with first-visit timestamp (ZONE_CHANGED_NEW_AREA)
64. `BUILT` Subzones discovered
65. `BUILT` XP earned from exploration
66. `BUILT` Time spent in each zone
67. `BUILT` Zone order: your path through the world
68. `BUILT` Hearthstone uses (UNIT_SPELLCAST_SUCCEEDED)
69. `BUILT` Flight paths discovered
70. `BUILT` Flights taken
71. `BUILT` Approximate distance traveled (sampled positions via C_Map.GetWorldPosFromMapPos) (uses UnitPosition instead, confirmed readable outdoors by the probe; ground and taxi kept separate)
72. `BUILT` Graveyards used
101. `BUILT` Total distance fallen (no fall event or readable height: IsFalling() is timed each frame and the drop worked out from WoW's fall speed; a jump's own rise is subtracted; Slow Fall/Levitate/Noggenfogger's slow fall ignored, whether on you as the fall starts, cast or given on the way down, or on you as you land; a fall with a loading screen or a freeze in it isn't timed; a ghost's drops aren't falls) (confirmed in game before the 2026-10-05 change, which needs checking again)
102. `BUILT` Longest distance fallen and lived (alive 1.5s after landing; fatal falls counted separately and shown as "Falling" in the death log; a ghost's drops are neither) (confirmed in game before the 2026-10-05 change, which needs checking again)
108. `BUILT` Where you spent your time on each zone's map: every 5s tick, the square of the map you're in (25 x 25 squares, C_Map.GetPlayerMapPosition read out of combat; a fight's time goes to the square it started in; not on a flight path, AFK or in instances), db.where[uiMapID][square] = seconds. For the website's heat map; the window's Zones page shows the time placed

## Dungeons
73. `BUILT` Dungeons entered (GetInstanceInfo)
74. `BUILT` Dungeon runs completed and time per run (the time logged in during the run)
75. `BUILT` Deaths per dungeon

## Economy
76. `BUILT` Gold on hand at every ding
77. `BUILT` Total gold earned and total gold spent (PLAYER_MONEY deltas)
78. `BUILT` Gold from looting (CHAT_MSG_MONEY) (money delta while the loot window is open; probe showed PLAYER_MONEY arrives before CHAT_MSG_MONEY)
79. `BUILT` Gold from vendor sales (money delta while merchant is open)
80. `BUILT` Gold spent on class training (not at profession trainers)
81. `VERIFIED` Gold spent on repairs (Repair All, plus single items fixed with the repair cursor) (single-item repair confirmed in game)
82. `BUILT` Gold spent on flights
83. `BUILT` Auction house sales and purchases (sale income = money taken from mail with a "seller" invoice; sale count = "buyer found" messages and Forever's auction house notifications (AUCTION_HOUSE_SHOW_NOTIFICATION / _FORMATTED_NOTIFICATION, AuctionSold), each way counted for 3 seconds and the most any one way saw being the count, so a sale seen both ways is one and two sales of the same item are two; purchases = spending while the AH is open) (auction sale income confirmed in game; the sale count changed 2026-10-05 and needs checking)
84. `BUILT` Level and /played when you bought your first mount (approximated as the first time you're mounted)
85. `BUILT` Peak gold held at once

## Loot and gear
86. `BUILT` Total items looted (CHAT_MSG_LOOT)
87. `BUILT` Items looted by quality: green, blue, purple
88. `VERIFIED` Best item looted, plus where and at what level (confirmed in game, with the item tooltip on hover)
89. `VERIFIED` Gear snapshot every 10 levels (GetInventoryItemLink) (confirmed in game via the level 20 snapshot taken after login)
90. `BUILT` Level of your first blue and first epic
104. `BUILT` Gear worn the longest: the item with the most levels gained while equipped, and the item with the most /played while equipped, each with its slot and the levels it was worn (shirts and tabards left out; also covers wrapped W-396)

## Professions and skills
91. `BUILT` Professions learned and the level you learned them
92. `BUILT` Profession skill progression over time
93. `BUILT` Items crafted
94. `BUILT` Fish caught
95. `BUILT` Spells and abilities learned, with level learned
96. `BUILT` Weapon skill-ups (CHAT_MSG_SKILL) (GetNumSkillLines is missing on Forever; the chat message is the only source)
103. `VERIFIED` Nodes gathered: herbs picked, ore nodes mined, corpses skinned, and the items each gave (gathering casts via UNIT_SPELLCAST_SUCCEEDED; repeat swings at one vein count once) (confirmed in game)

## Social and fun
97. `BUILT` Time spent grouped vs solo
98. `BUILT` Number of unique players grouped with (count only, no names)
99. `BUILT` Level you joined a guild
100. `BUILT` Times jumped (hooksecurefunc on JumpOrAscendStart)

## Sharing
105. `BUILT` Journey saved at every milestone (levels 10, 20 ... 60): the export as it stood at the level-up, in db.milestones[level] (waits for the ding's /played and Statistics pane read, at most 20s, then for combat to end; a milestone missed that way is saved at the next login while you're still at that level, marked late)
106. `BUILT` Export window: choose the journey of now or one saved at a milestone; /journey export 30 opens at 30
107. `BUILT` A chat note when a milestone is saved
109. `BUILT` A reminder as each milestone is saved: a small window with Export now (the export window, open at that milestone), Later, and a link to Options. It's on unless turned off on the window's new Options page (db.ui.exportReminder = false), which also has the screenshot at every ding (wrapped W-494) and a button to show the reminder. /journey options opens the page
110. `BUILT` How long after reaching its milestone each export was made (sinceMilestone: the milestone, /played seconds since its level-up's own /played, and real seconds since), 0 in a milestone's own save. The export window notes it when the journey of now was made long after reaching its milestone. The website ranks a journey exported at its milestone's level more than 2 hours of /played after reaching it only on what was settled then (the time it took, the levels it did things at), and each character's freshest upload stands for it at a milestone

## Changelog
- 2026-10-01: Spec created, all items `TODO`.
- 2026-10-01: #1-100 `BUILT` in new addon JourneyTracker (Interface/AddOns/JourneyTracker, per-character SavedVariables JourneyTrackerDB, schema 1).
- 2026-10-01: #7-9, #15-16, #29, #36, #51-52 are stored as raw data (sessions, per-level stats, kill/death lists) and derived at export; `/jt` prints several of them for testing.
- 2026-10-01: Added in-game window (JourneyTrackerUI.lua, `/jt`): Classic quest-log layout showing every item, plus a Levels tab. `/jt summary` prints to chat.
- 2026-10-01: #101-103 added and `BUILT` (falls, longest fall survived, gathering). #81 now includes single-item repairs; #83 now records auction sale income separately from other mail. #47 reports "Falling" for fatal falls.
- 2026-10-01: UI shows #101-103 (new Falls and Gathering pages), money with coin icons, and every stored field (session start levels, ding totals, death details, boss pulls, dungeon run levels, skill rank by level).
- 2026-10-01: #89 a missing snapshot for your current milestone level is taken at login (marked late). #91 now also stores current and max skill, shown as bars. UI: #94 moved to Gathering, #100 to Falls; Social shows campfire time (wrapped W-009). Main file now shares its events and ding snapshots with the class and wrapped trackers.
- 2026-10-01: #14 fixed: the game reports flight paths as mounted, so taxi time had counted as mounted and could set #84 first mount. Schema 2 migration takes taxi time back out and clears a first mount with no real mounted time. #89 fixed: snapshots taken before equipment loads are no longer saved empty; a missing or empty milestone snapshot is retaken a few seconds after login. Added a minimap button (gold "JT") that opens the window.
- 2026-10-01: Sharing prep, part 1 (versioning and data safety): TOC "## Version: 0.1.0", read with C_AddOns.GetAddOnMetadata and shown by /journey version (/journey now works alongside /jt). Root fields schemaVersion and characterId (random UUID v4, never regenerated). Ordered MIGRATIONS run on a copy at ADDON_LOADED; a failure leaves the saved data untouched and turns tracking off for the session. Migration 1 stamps today's layout, folds in the old flight-path fix (keeping the uncorrected values under legacy), renames schema to legacySchema and assigns the characterId. JourneyTrackerBackup (per character): an automatic copy before any upgrade, and /journey backup.
- 2026-10-01: Part 2 (export): /journey export (blocked in combat) builds an anonymous summary (no character name/realm, other players' names, chat text or hashed group IDs; skill history summarized to rank per level; name maps capped at 200), then JSON (hand-written encoder) > LibDeflate CompressDeflate > base64 > "JT1:" prefix, shown in a copy window with its length. Warns with the largest sections over 100k characters. Bundles Libs/LibDeflate (zlib license kept) and Libs/LibStub (public domain), which LibDeflate needs to be reachable in game.
- 2026-10-01: Part 3 (packaging): build/build.ps1 makes dist/JourneyTracker-<version>.zip from the TOC version, with only the TOC, Lua, textures, Libs/ and README.txt. README.txt for friends. Note: data is saved per character, at WTF\Account\<account>\<realm>\<character>\SavedVariables\JourneyTracker.lua.
- 2026-10-01: Part 4 (import): tools/import with decode.js (decode/validate/row mapping, reusable by the website), import.js (--dry-run, --print, duplicate skipping by character_id + exported_at), .env.example, .gitignore.
- 2026-10-01: Part 5 (round trip): /journey testexport (dev only) and tools/import/test/roundtrip.test.js. The fixture was made by running the addon's own Lua encoder and LibDeflate in a Lua VM; Node decodes it to the expected JSON (5/5 tests pass). Also checked outside the game: migrations on real saved data, and a real export decoding and validating.
- 2026-10-01: To check on Forever in game: C_AddOns.GetAddOnMetadata (falls back to GetAddOnMetadata); math.randomseed (may be missing or ignored, guarded); debugprofilestop; the export window (BackdropTemplate, UIPanelScrollFrameTemplate, multi-line EditBox, ScrollingEdit_OnCursorChanged / ScrollingEdit_OnUpdate, ChatFontNormal, UIPanelButtonTemplate, UIPanelCloseButton); BreakUpLargeNumbers; UnitFactionGroup; and that SavedVariablesPerCharacter accepts the second table (JourneyTrackerBackup).
- 2026-10-01: Checked in game: /journey version, stable characterId across logins, /journey backup, export window and combat block, /journey testexport, and the data upgrade on a second character. No Lua errors on login.
- 2026-10-01: VERIFIED in game: #81, #83, #88, #89, #101, #102, #103. Also confirmed: minimap button, item tooltips on the Gear and Loot pages, Class Stats page opens without errors.
- 2026-10-01: Round trip confirmed: the in-game /journey testexport string is identical to the one made outside the game, and npm test passes 7/7 (Node 26).
- 2026-10-01: #104 added and `BUILT`: gear worn the longest, by levels gained and by /played while equipped (db.worn: one record per item ID and random suffix, kept to the 200 most worn; updated on gear changes, every tick and at logout). Shown at the top of the Gear Snapshots page. Wrapped W-396 marked `SKIP` (covered by #104).
- 2026-10-01: Statistics pane, phase 1 (wrapped W-501): `/journey statprobe` (dev only, new JourneyTrackerStats.lua) checks the statistics API, walks every category and statistic, prints a summary (counts, secrets, errors, per-character hints) and saves everything to JourneyTrackerDB.dev.statProbe. `dev` is never exported. Not confirmed on Forever: GetStatisticsCategoryList, GetCategoryInfo, GetCategoryNumAchievements (and its includeAll argument), GetAchievementInfo (retail return order, including isStatistic), GetStatistic (value format, "--" for none), the account-wide achievement flag (0x20000 in retail), bit.band and GetBuildInfo.
- 2026-10-01: Statistics pane, phase 2 (wrapped W-502..W-507 `BUILT`): JourneyTrackerStats.lua reads the whole pane on its own (baseline at first load, a diff at every ding, a snapshot at every export) into db.statistics, and the export gets a `statistics` section. The window shows the game's "all time" numbers under ours (Summary, Kills, Deaths, Quests, Travel) and has a new Lifetime > Statistics Pane page. `/journey stats` added. No saved-data migration (new table filled from defaults) and no export format change. Not confirmed on Forever: that statistics are loaded 10s after login; that a ding is counted in them 2s after PLAYER_LEVEL_UP; GetStatistic's value types beyond the probe's strings; coroutines and C_Timer.After(0) for spreading reads over frames; date().
- 2026-10-02: Window (no tracking changed): an Export button at the bottom left (Print to Chat moved beside it) and right-click on the minimap button both open the export, which is now a step-by-step dialog: Ctrl+C, paste at www.journeytracker.dev, Show my journey, with the website's address in a box to copy and a "Copied" line when Ctrl+C (or Cmd+C) is pressed. Consistency pass: numbers get thousands separators everywhere, empty headings get a note, the "Unknown" stand-in zone is left out of zone counts, lists and the path, resurrection bars say "Corpse run" etc., days played read "Oct 01", the Summary's distance row matches Travel's ("on foot and mounted"), and class swap pairs read "Caster Form to Cat Form". Version 0.3.0. Not confirmed on Forever: OnKeyUp on an EditBox seeing Ctrl+C, and InputBoxTemplate.
- 2026-10-02: Window (no tracking changed): every bar on the pages now sits in the same thin bordered box as the header's "Level: x/60" counter (one shared function makes both; bars are 22px tall, rows 25px apart). Kill classification bars read "Normal", "Elite", "Rare elite" and so on.
- 2026-10-03: #105-107 added and `BUILT` (milestone exports, JourneyTrackerExport.lua): every 10 levels the export of that moment is saved to db.milestones[level] (about 15k characters each at level 20-30), with its /played from the level-up. The export window has a row of choices under its steps, "Now (34)" and "At 30" etc. (newest first), and a hint when none is saved yet; /journey export 30 opens at 30. A milestone's export has `milestone = 30` at its top level; exports never carry the saved milestones themselves. No saved-data migration (new table filled at load) and no export format change. Version 0.4.0. Checked outside the game (fengari, real saved data, fake clock): saved once the /played reply is in, held through combat, saved late at a login at that level, nothing at level 35, and /journey export 30 shows it. Not confirmed on Forever: Button:LockHighlight/UnlockHighlight, date("%b %d").
- 2026-10-03: #108 added and `BUILT` (where you spent your time): each 5s tick out of combat, the square of the zone map you're in (25 x 25, from C_Map.GetPlayerMapPosition, the same reading as deaths and dings) gets the time, in db.where[uiMapID][square]; a fight's time goes to the square it started in; flights, AFK and instances get none. The window's Zones page shows the time placed and the number of squares. The export carries it as stats.where (about 10 characters per square). No saved-data migration (new table filled from defaults) and no export format change. Version 0.5.0. Checked outside the game (fengari, real saved data, fake clock): a minute standing still is a minute in one square, a fight stays with its square, flights, AFK and instances add nothing, and the export carries the squares. Not confirmed on Forever: C_Map.GetPlayerMapPosition every 5s out of combat (deaths and dings already read it).
- 2026-10-05: #109 and #110 added and `BUILT` (addon 0.6.1). #109: as each milestone is saved, a small window offers Export now (the export window, open at that milestone) or Later, with a link to the window's new Options page, where the reminder can be turned off (db.ui.exportReminder = false, never exported); Options also has the wrapped screenshot at every ding and a button to show the reminder, and /journey options opens it. #110: every export carries sinceMilestone (its milestone, /played seconds since that level-up's /played, real seconds since), 0 in a milestone's own save, and the export window notes when the journey of now was made more than 2 hours of /played after reaching its milestone. The website (MODEL 4) ranks a journey exported at its milestone's level more than 2 hours of /played after reaching it only on the rankings settled by then (the time it took, "at level N" firsts, slowest level, first mount's /played, Hyjal), keeps it out of the rest, says so on its page, and has each character's freshest upload stand for it at a milestone instead of its latest.
- 2026-10-05: Fixes from a bug review of the addon and the website (addon 0.6.2, site MODEL 5). Addon: map positions a little past a map's edge read as the edge, and the export drops a negative number wherever one slipped in (only a level "diff" keeps its sign), since the website turns away an export with one; #74 counts the time logged in during a run, not a night logged off inside it; #80 leaves out profession trainers; a ding's kill total includes the fight still going; the XP that finishes a level goes to that level (#15, #23); #47 only falls back to a hostile targeted in the last minute; every event listener, ding and load callback runs protected (errors in /journey status); /journey status also lists the game functions the tracker asked for that the client doesn't have; the export carries the different mobs killed before the 200-name cap (stats.kills.uniqueNames) and only the top 10 typed words; the milestone reminder's example in Options says what's to come before a milestone is saved; the TOC names its author. Website: share pages no longer show the character's ID (they carry the upload's) or more than the top typed word; uploads only from the site's own pages, duplicates turned away, exports capped at 4 MB unpacked, 32 tables deep and an export time from 2020; ranked values can't be negative or past what the game allows; Hyjal only after 60; old profiles reworked before a character's upload is chosen at a milestone; auction sales no longer counted twice in what's earned; 29 rankings filled from exports that only the sample had (XP per hour, dungeons and runs, racials, the class counters); W-293 messages per hour and W-357 time between deaths worked out; the page draws each section on its own so one bad value can't blank the rest, and the road chart, NaN and phone-width overflows are fixed. Not changed, needing a decision: #101/#102 (VERIFIED) miss Slow Fall cast mid-fall, count a loading screen in mid-air and lag as falling, and count a ghost's drops as fatal falls; #83's sale count (VERIFIED, only its income confirmed) may never see its "buyer found" lines on Forever, whose auction house UI prints them itself. Checked outside the game (fengari, real saved data): every existing test plus 181 new checks; site: 67 new checks and 29 hostile journeys in headless Edge.
- 2026-10-05: #101, #102 and #83 changed on request (they were `VERIFIED`; now `BUILT` until checked in game again; addon 0.6.3). #101/#102: a slow fall is caught however it comes (Slow Fall or Levitate cast on the way down, from the cast itself; any Slow Fall, Levitate or Noggenfogger slow fall on you, looked for every 0.1 s in the air and again on landing); a fall with a loading screen (PLAYER_LEAVING_WORLD) or a freeze of more than half a second between frames isn't timed, so a zeppelin, portal or summon in mid-air isn't a huge fall; a ghost's drops on a corpse run aren't falls, so they no longer count as fatal ones. #83: the sale count also reads Forever's auction house notifications (its UI doesn't print the "buyer found" line itself), and each way a sale can arrive is counted for 3 seconds with the most any one way saw being the count, so a sale seen both ways is one; two sales of the same item, which send the same line, are no longer one (the one-identical-line-a-second rule no longer applies to them). W-368 gets its sold, expired and cancelled counts the same way. Checked outside the game (fengari, real saved data): 16 new checks, 12 of which the old code fails, and every existing test.
