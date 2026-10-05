# Journey Tracker: Wrapped Stats (500)

Third spec file, alongside journey-tracking-spec.md and class-tracking-spec.md. Same status workflow and rules apply (read the "Status tracking" section in journey-tracking-spec.md first). Items use IDs `W-001` to `W-500` so they never collide with the other lists. Tag each tracker in the Lua with its ID, e.g. `-- W-001 murlocs slain`.

Built for WoW Forever: all Classic dungeons plus the 9 new ones, Forever's battlegrounds (WSG, AB, Darkspear Islands, AV), the post-launch raids, and Forever-only systems like Skyborne, camping, and Legacy. Goal: track as much as possible, even if the website doesn't use it yet. This is the raw material for a "Spotify Wrapped" style recap.

## Prompt for Claude Code

> Read journey-tracking-spec.md (status rules), class-tracking-spec.md, and wrapped-tracking-spec.md. Implement `TODO` items in wrapped-tracking-spec.md one section at a time, in order, reusing the shared helpers (cast counter, state timer, item diff, pet tracker) and existing event handlers. Do not touch anything tagged `VERIFIED` in any spec file. Skip any item that duplicates something already tracked in the other two files and mark it `SKIP` with a note pointing to the existing ID. Items or sections marked `[probe]` need data that might be secret in combat: build them behind a feature flag so they can be disabled without breaking anything. After each section, stop and summarize what you built so I can test it in game before you continue.

## Architecture notes

- **Storage budget.** 500 stats can bloat SavedVariables. Store counters as numbers, use short keys, and cap any name-keyed map (mob names, words, items) at the top 200 entries, evicting the smallest. Roll raw events into totals at each ding.
- **Generic counters.** Most items are "count X" or "time in Y". Build a small registry: `Track.count(id, key)`, `Track.time(id, on/off)`, `Track.max(id, value)`, `Track.first(id, context)`. Each item is then a few lines wired to an event.
- **Name matching tables.** Creature-family and iconic-mob items should use one lookup table of keywords to stat IDs (e.g. "Murloc" to W-001), not one handler per mob. Forever may rename mobs, so keep the table easy to edit.
- **Faction gating.** Alliance and Horde sections only load for that faction (`UnitFactionGroup("player")`).
- **Privacy.** Never store other players' names or message text. Store counts, classes, and levels only.
- **Combat safety.** Anything that reads chat, unit names, or enemy players must check `issecretvalue` and queue work until `PLAYER_REGEN_ENABLED`.
- **Context snapshot.** Many items need "what was happening right before" (deaths, dings). Keep a small rolling context: last target, last 10 seconds of state (falling, swimming, mounted, AFK, health %, group), and attach it to death and ding records.
- **Blizzard statistics.** Where Blizzard's Statistics pane already tracks something (W-501 onward), use its number for lifetime totals, and keep our own tracking for per-level detail and for anything it doesn't cover. Don't remove any existing items because of the overlap.

## WoW Forever exclusives
_Content that only exists in Forever. Zone names via GetZoneText/GetSubZoneText. Verify system APIs (camping, Legacy, transmog) in the probe addon, since they're new._

1. `BUILT` `W-001` Skyborne: time on Zephras Isle and level you left it (level you left from zone changes; time on the isle from #66)
2. `BUILT` `W-002` Skyborne faction alignment chosen (Alliance or Horde) (first Alliance/Horde faction after being Neutral, or at first login as a Skyborne)
3. `VERIFIED` `W-003` New race/class combo played (Gnome Priest, Human Hunter, Dwarf Shaman, Orc Mage, Troll Warlock, Undead Paladin, any Skyborne class) (race and class checked at login against the new combos) (confirmed in game)
4. `SKIP` `W-004` Riverglades: level of first arrival, time spent, quests completed (covered by #63 (first arrival level), #66 (time) and #55 (quests per zone); shown on the WoW Forever page)
5. `SKIP` `W-005` Shen'dralas: level you discovered it, time spent, quests completed (covered by #63, #66 and #55; shown on the WoW Forever page)
6. `BUILT` `W-006` Mount Hyjal: /played and days after 60 when you first arrived (level, /played and days after 60 on first arrival)
7. `BUILT` `W-007` New Forever quests completed vs Classic quests completed (split by quest ID: Classic IDs are below 10000; heuristic)
8. `BUILT` `W-008` Camps set up (Campfire casts that do not create a campfire item)
9. `VERIFIED` `W-009` Time spent resting at camps vs inns (camp time from the Campfire Nearby / Welcoming Campfire / Camp Benefits buffs, checked out of combat; inns from #11) (confirmed in game)
10. `BUILT` `W-010` Camp vendors and repairs used (vendor windows opened and Repair All used while at a camp)
11. `VERIFIED` `W-011` Camp buffs received (camp buffs landing on you (UNIT_AURA), by name) (confirmed in game)
12. `BUILT` `W-012` Camping objects crafted with professions (camp objects and campfires created, by item)
13. `TODO` `W-013` Legacy challenges completed while leveling (class levels 25/45/60, tradeskills 150/225/300, etc.) (Legacy API unknown; /jprobe api will find its functions and events)
14. `TODO` `W-014` Legacy points earned and when (Legacy API unknown; waiting on /jprobe api)
15. `TODO` `W-015` Legacy perks chosen, by tree (Professions, Adventure, Resourcefulness), and the level each was picked (Legacy API unknown; waiting on /jprobe api)
16. `BUILT` `W-016` Lord Valthalak questline progress (quests with Valthalak in the title or turned in to Bodley)
17. `BUILT` `W-017` World map exploration percentage at each ding (Legacy Adventure challenge) (explored map areas counted at each ding; percentage left to the website)
18. `SKIP` `W-018` Racial abilities used: each of Forever's active racials (duplicates ALL-09; every cast is counted in db.class, so new racials show up once named)
19. `BUILT` `W-019` Transmog changes made and gold spent on transmog (retail transmog events (TRANSMOGRIFY_*); unverified on Forever)
20. `VERIFIED` `W-020` Ruleset played (Normal, PvP, Roleplaying, Hardcore when it arrives) (Hardcore from C_GameRules, PvP/RP from the realm name or an auto-flag) (confirmed in game)
21. `BUILT` `W-021` Times auto-flagged for PvP by entering a contested or enemy zone (PvP ruleset) (PvP flag turned on in a contested or hostile zone without /pvp)

## Creature kills: meme families
_[probe] Kill attribution by mob name/type. Match on name keywords plus UnitCreatureType/UnitCreatureFamily cached at target time._

22. `BUILT` `W-022` Murlocs slain (kills matched on name keywords, creature type or beast family from FAMILIES in JourneyTrackerIconic.lua; kills without experience counted when a target you attacked dies, or from the combat log where Forever allows it)
23. `BUILT` `W-023` Most murlocs in a single combat (the classic murloc train) (murloc kills per fight, best kept with level and zone)
24. `BUILT` `W-024` Kobolds slain (FAMILIES keywords)
25. `BUILT` `W-025` Gnolls slain (FAMILIES keywords)
26. `BUILT` `W-026` Defias Brotherhood members slain (FAMILIES keywords)
27. `BUILT` `W-027` Harpies slain (FAMILIES keywords)
28. `BUILT` `W-028` Centaurs slain (Kolkar, Galak, Maraudine, Magram, Gelkis) (FAMILIES keywords)
29. `BUILT` `W-029` Quilboar slain (Razormane, Bristleback, Razorfen) (FAMILIES keywords)
30. `BUILT` `W-030` Trolls slain, any tribe (FAMILIES keywords)
31. `BUILT` `W-031` Ogres slain (FAMILIES keywords)
32. `BUILT` `W-032` Naga slain (FAMILIES keywords)
33. `BUILT` `W-033` Satyrs slain (FAMILIES keywords)
34. `BUILT` `W-034` Furbolgs slain (FAMILIES keywords)
35. `BUILT` `W-035` Troggs slain (FAMILIES keywords)
36. `BUILT` `W-036` Dark Iron dwarves slain (FAMILIES keywords)
37. `BUILT` `W-037` Scarlet Crusade members slain (FAMILIES keywords)
38. `BUILT` `W-038` Syndicate members slain (FAMILIES keywords)
39. `BUILT` `W-039` Venture Co. goblins slain (FAMILIES keywords)
40. `BUILT` `W-040` Bloodsail Buccaneers slain (FAMILIES keywords)
41. `BUILT` `W-041` Burning Blade cultists slain (FAMILIES keywords)
42. `BUILT` `W-042` Scourge undead slain (creature type Undead)
43. `BUILT` `W-043` Spiders slain (Spider family or name)
44. `BUILT` `W-044` Raptors slain (Raptor family or name)
45. `BUILT` `W-045` Crocolisks slain (Crocolisk family or name)
46. `BUILT` `W-046` Wolves and worgs slain (Wolf family or wolf/worg names, not worgen)
47. `BUILT` `W-047` Boars slain (Boar family or name)
48. `BUILT` `W-048` Bears slain (Bear family or name)
49. `BUILT` `W-049` Gorillas slain (Gorilla family or name)
50. `BUILT` `W-050` Scorpids slain (Scorpid family or name)
51. `BUILT` `W-051` Kodos slain (name)
52. `BUILT` `W-052` Big cats slain (panthers, tigers, lions, nightsabers) (Cat family or cat names)
53. `BUILT` `W-053` Whelps and dragonkin slain (creature type Dragonkin or whelp/drake/dragon names)
54. `BUILT` `W-054` Elementals slain (creature type Elemental)
55. `BUILT` `W-055` Demons slain (creature type Demon)
56. `BUILT` `W-056` Yetis slain (name)
57. `BUILT` `W-057` Critters killed total (UnitCreatureType Critter) (creature type Critter; critters give no experience, so these come from the no-experience kill watch; Blizzard's pane also counts critters (statistic 108))
58. `BUILT` `W-058` Chickens killed (no-experience kill watch)
59. `BUILT` `W-059` Rabbits and squirrels killed (no-experience kill watch)

## Alliance iconic
_Only active for Alliance characters. [probe] for anything keyed on a mob name._

60. `BUILT` `W-060` Hogger: level and /played at first kill (first kill by name, with level and /played)
61. `BUILT` `W-061` Hogger: attempts (combats with Hogger) and deaths to Hogger (fights with Hogger in them, and deaths with Hogger as the killer)
62. `BUILT` `W-062` Princess (Elwynn boar) killed (exact name, so Princess Theradras doesn't count)
63. `BUILT` `W-063` Edwin VanCleef killed: level and /played at first kill (first kill)
64. `BUILT` `W-064` Kobold candle meme: Kobolds killed in Elwynn mines (kobold kills in Fargodeep and Jasperlode Mines)
65. `BUILT` `W-065` Harvest Watchers (Westfall scarecrows) slain (name)
66. `BUILT` `W-066` Defias Pillagers and Defias Messengers slain in Westfall (names, in Westfall)
67. `BUILT` `W-067` Bellygrub (Redridge boar) killed (first kill)
68. `BUILT` `W-068` Blackrock orcs slain in Redridge (Blackrock names, in Redridge)
69. `BUILT` `W-069` Stitches killed (Duskwood) (first kill)
70. `BUILT` `W-070` Mor'Ladim killed (Duskwood) (first kill)
71. `BUILT` `W-071` Worgen slain in Duskwood (worgen and Nightbane names, in Duskwood)
72. `BUILT` `W-072` Deeprun Tram rides (entering the Deeprun Tram zone; a new visit after 10 minutes away)
73. `BUILT` `W-073` Times entered Ironforge, Stormwind, and Darnassus (entries by city, a new visit after 10 minutes away)
74. `BUILT` `W-074` Time AFK in Ironforge (5-second ticks AFK in Ironforge)
75. `BUILT` `W-075` Boat rides: Menethil to Auberdine, Menethil to Theramore, Auberdine to Rut'theran (dock to dock on a known route within 8 minutes, with no flight or hearth between (subzones Menethil Harbor, Auberdine, Theramore Isle, Rut'theran Village))
76. `BUILT` `W-076` Rut'theran portal uses to Darnassus (Darnassus moments after Rut'theran Village)
77. `BUILT` `W-077` Times visited Southshore (subzone visits)
78. `BUILT` `W-078` Times visited Theramore (subzone visits)
79. `BUILT` `W-079` Times you entered Orgrimmar, Thunder Bluff, or Undercity (enemy capitals) (entries by city)
80. `BUILT` `W-080` Horde players killed in Southshore or Hillsbrad [probe] (enemy players killed in Hillsbrad Foothills (JourneyTrackerPvP.lua))
81. `BUILT` `W-081` Racial mount bought: horse, ram, mechanostrider, or nightsaber (a mount item (class 15, subclass 5) bought from a vendor, with its price)
82. `BUILT` `W-082` Level you left your starting zone (first move from your race's starting zone and capital to anywhere else; not recorded if the tracker already saw you elsewhere)
83. `BUILT` `W-083` Dragonmaw orcs slain in the Wetlands (Dragonmaw names, in the Wetlands)

## Horde iconic
_Only active for Horde characters. [probe] for anything keyed on a mob name._

84. `BUILT` `W-084` Mankrik's wife found (Lost in Battle quest): level and /played (quest 'Lost in Battle' turned in, with level and /played)
85. `BUILT` `W-085` Kolkar centaurs slain in the Barrens (Kolkar names, in the Barrens)
86. `BUILT` `W-086` Echeyakee killed (Barrens) (first kill)
87. `BUILT` `W-087` Lakota'mani killed (Barrens rare kodo) (first kill)
88. `BUILT` `W-088` Plainstriders slain in the Barrens (Plainstrider names, in the Barrens)
89. `BUILT` `W-089` Barrens General chat messages seen (count only) (General channel messages while you're in the Barrens; counted, text never kept)
90. `BUILT` `W-090` Barrens chat messages mentioning Chuck Norris (count only) (the same messages containing 'chuck norris'; counted, text never kept)
91. `BUILT` `W-091` Alliance players killed in the Crossroads [probe] (enemy players killed in the Crossroads)
92. `BUILT` `W-092` Gamon slain in Orgrimmar (kills by name, with or without experience)
93. `BUILT` `W-093` Zeppelin rides by route: Orgrimmar to Undercity, Orgrimmar to Grom'gol, Undercity to Grom'gol (zeppelin docks: Durotar, Tirisfal Glades, Grom'gol Base Camp; same rules as W-075)
94. `BUILT` `W-094` Undercity elevator rides (moving between Undercity and Tirisfal Glades)
95. `BUILT` `W-095` Deaths falling from the Undercity elevator [probe] (deaths by falling in Undercity or the Ruins of Lordaeron)
96. `BUILT` `W-096` Thunder Bluff elevator rides and falls off Thunder Bluff (moving between Thunder Bluff and Mulgore not by air; falls of 30+ yards landing in Mulgore within 15 seconds of being in Thunder Bluff)
97. `BUILT` `W-097` Times entered Orgrimmar, Thunder Bluff, and Undercity (entries by city)
98. `BUILT` `W-098` Time AFK in Orgrimmar (5-second ticks AFK in Orgrimmar)
99. `BUILT` `W-099` Times visited Tarren Mill (subzone visits)
100. `BUILT` `W-100` Alliance players killed in Tarren Mill or Hillsbrad [probe] (enemy players killed in Hillsbrad Foothills)
101. `BUILT` `W-101` Times visited Grom'gol, Kargath, Hammerfall, and Stonard (subzone visits by outpost)
102. `BUILT` `W-102` Times you entered Stormwind, Ironforge, or Darnassus (enemy capitals) (entries by city)
103. `BUILT` `W-103` Racial mount bought: wolf, kodo, raptor, or skeletal horse (as W-081)
104. `BUILT` `W-104` Scorpids slain in Durotar (scorpids, in Durotar)
105. `BUILT` `W-105` Scarlet Crusaders slain in Tirisfal (Scarlet names, in Tirisfal Glades)
106. `BUILT` `W-106` Worgen slain in Silverpine (Arugal's pack) (Moonrage, worgen and Son of Arugal names, in Silverpine)
107. `BUILT` `W-107` Times visited the Kodo Graveyard (subzone visits)

## Neutral zone iconic
_[probe] for name-based kills. Zone/subzone detection via ZONE_CHANGED_NEW_AREA and GetSubZoneText._

108. `BUILT` `W-108` Green Hills of Stranglethorn pages looted (loot named 'Green Hills of Stranglethorn - Page')
109. `BUILT` `W-109` Green Hills of Stranglethorn chapters completed (quests titled 'Chapter I' to 'Chapter IV')
110. `BUILT` `W-110` Nesingwary hunts: tigers, panthers, raptors slain in Stranglethorn (tiger, panther and raptor kills in Stranglethorn, by kind)
111. `BUILT` `W-111` King Bangalash killed (first kill)
112. `BUILT` `W-112` Gurubashi Arena entries and Arena Master trinket looted (subzone visits to Gurubashi Arena; the first Arena Master looted as W-112.trinket)
113. `SKIP` `W-113` Deaths in Stranglethorn Vale (covered by #46: every death's zone is recorded)
114. `SKIP` `W-114` Time spent in Stranglethorn Vale (the gankfest) (covered by #66: time spent in each zone)
115. `BUILT` `W-115` Booty Bay visits and Booty Bay boat rides to Ratchet (subzone visits; Booty Bay to Ratchet boat rides as W-115.rides)
116. `BUILT` `W-116` Times killed by Booty Bay or other goblin town guards (deaths with a Bruiser as the killer, by name)
117. `BUILT` `W-117` Devilsaurs slain in Un'Goro (Devilsaur names, in Un'Goro Crater)
118. `BUILT` `W-118` Deaths to Devilsaurs (deaths with a Devilsaur as the killer)
119. `BUILT` `W-119` Un'Goro crystals collected (Power Crystals looted, by color)
120. `BUILT` `W-120` Un'Goro pylons activated (the three pylon quests turned in)
121. `BUILT` `W-121` A-Me 01 escorted (quests with 'A-Me 01' in the title)
122. `BUILT` `W-122` Gadgetzan water quests completed ('Water Pouch Bounty' turned in)
123. `BUILT` `W-123` Dark Portal visits (Blasted Lands) (subzone visits)
124. `BUILT` `W-124` Karazhan entrance visits (Deadwind Pass) (subzone visits)
125. `BUILT` `W-125` Onyxia's Lair entrance visits (Dustwallow) (visits to the Wyrmbog or Onyxia's Lair)
126. `BUILT` `W-126` Yetis slain in Winterspring (yetis, in Winterspring)
127. `BUILT` `W-127` Desolace centaur faction kills (Magram vs Gelkis) (Magram and Gelkis kills in Desolace, by clan)
128. `BUILT` `W-128` Zone you spent the most time in at each 10-level bracket (time per zone in each 10-level bracket from the 5-second ticks; the website picks the top zone)
129. `BUILT` `W-129` Time spent in contested zones vs friendly zones (time by GetZonePVPInfo (friendly, contested, hostile, sanctuary))

## Rares and named mobs
_[probe] Use UnitClassification and nameplate/target info._

130. `BUILT` `W-130` Rare spawns seen (targeted or nameplate) vs killed (rares on nameplates or targeted, once per spawn; rare kills)
131. `BUILT` `W-131` Rare kills by zone (rare kills by zone)
132. `BUILT` `W-132` Named quest-boss mobs killed (mobs from 'Wanted' posters) (kills of the mobs named in your 'Wanted:' quests)
133. `BUILT` `W-133` First rare you ever killed: name, level, zone (first rare kill: name, its level, your level, zone)
134. `BUILT` `W-134` Rares that killed you (deaths to a rare, by name)
135. `BUILT` `W-135` Elite mobs soloed (only you in combat, no group) (elite kills while not in a group)
136. `BUILT` `W-136` Elite deaths: times an elite killed you (deaths to an elite, rare elite or boss)
137. `BUILT` `W-137` Highest-level elite soloed (highest mob level of an elite killed solo)
138. `BUILT` `W-138` Mobs killed that were 5+ levels above you (kills of mobs 5+ levels above you (skull included))
139. `BUILT` `W-139` Times you were attacked by a mob 10+ levels above you (fights where a mob 10+ levels above you (or a skull) had threat on you, read from nameplates)

## World PvP and ganking
_[probe] Player kills need target caching: UnitIsPlayer, UnitIsEnemy, UnitLevel, stealth state at combat start, UnitIsDeadOrGhost after combat. Store levels and classes only, never names._

140. `BUILT` `W-140` Enemy players killed total (honorable or not) (honorable kill messages, enemy player targets you attacked dying, and the combat log where Forever allows it; the same player within 10 seconds counts once; class and level kept, never names (JourneyTrackerPvP.lua))
141. `BUILT` `W-141` Lowbies ganked: enemy players 10+ levels below you killed (victims 10+ levels below you)
142. `BUILT` `W-142` Stealth ganks: lowbies killed where you opened from stealth (rogue/druid) (lowbie kills in a fight that began while you were stealthed)
143. `BUILT` `W-143` Biggest level gap in a gank (your level minus theirs) (biggest gap, with the victim's class)
144. `BUILT` `W-144` Times you were ganked: killed by an enemy player 10+ levels above you (deaths to a player 10+ levels above you (or a skull))
145. `BUILT` `W-145` Biggest level gap when you got ganked (biggest gap, with the killer's class)
146. `BUILT` `W-146` Times corpse camped: killed by the same enemy player class/level combo 3+ times within 10 minutes (three deaths to the same class and level within 10 minutes)
147. `BUILT` `W-147` Spirit healer rezzes taken to escape a camp (spirit healer after two or more PvP deaths in 10 minutes)
148. `BUILT` `W-148` Fair fights won: enemy players within 3 levels killed (kills of players within 3 levels)
149. `BUILT` `W-149` Fair fights lost (deaths to players within 3 levels)
150. `BUILT` `W-150` World PvP kills by enemy class (outside battlegrounds, by class)
151. `BUILT` `W-151` World PvP deaths by enemy class (outside battlegrounds, by class)
152. `BUILT` `W-152` Your PvP nemesis class (class that killed you most) (the top class in W-151)
153. `BUILT` `W-153` Your favorite PvP victim class (the top class in W-150)
154. `BUILT` `W-154` Zone with the most world PvP kills (kills by zone, outside battlegrounds)
155. `BUILT` `W-155` Zone with the most world PvP deaths (deaths by zone, outside battlegrounds)
156. `BUILT` `W-156` Time spent PvP flagged (UnitIsPVP) (5-second ticks with UnitIsPVP)
157. `BUILT` `W-157` Times you flagged yourself for PvP (flag turned on within 3 seconds of TogglePVP or SetPVP)
158. `BUILT` `W-158` Times you accidentally flagged (attacked a flagged player or entered a hostile town) (flag turned on without that, outside contested zones (those are W-021))
159. `BUILT` `W-159` Dishonorable kills (civilian NPCs killed) (dishonorable kill messages)
160. `BUILT` `W-160` Enemy guards killed (kills of the other faction's guards, by name)
161. `BUILT` `W-161` Times killed by enemy guards (deaths to the other faction's guards)
162. `BUILT` `W-162` Times you attacked an enemy town (entering combat in an enemy town, once per town per 10 minutes)
163. `BUILT` `W-163` Faction leaders killed (Thrall, Cairne, Sylvanas, Bolvar, Magni, Tyrande, etc.) (kills by name, by leader)
164. `BLOCKED` `W-164` Enemy players killed while you were at less than 20% health (clutch wins) (your health is SECRET on Forever (probe), so it can't be read at a kill)
165. `BUILT` `W-165` Times you died to an enemy player while fighting a mob (third-partied) (deaths to a player in a fight that also had a mob)
166. `BUILT` `W-166` Times you killed an enemy player who was fighting a mob (enemy players who were targeting a mob when they died on your target)
167. `BUILT` `W-167` Times you used Feign Death, Vanish, or similar to escape an enemy player (Feign Death, Vanish, Ice Block, Divine Shield, Blessing of Protection or Invisibility in a fight with a player, then out of combat alive within 10 seconds)
168. `BUILT` `W-168` Enemy players killed in their own capital (kills in the other faction's capitals)
169. `BUILT` `W-169` Kill streaks: most enemy players killed without dying (kills since your last death, best kept)

## Battlegrounds and duels
_Forever battlegrounds: Warsong Gulch (10v10, brackets from 10-19), Arathi Basin (15v15, from 20-29), Darkspear Islands (15v15, from 30-39), Alterac Valley (40v40, 51-60). No arenas. Use GetBattlefieldStatus, GetBattlefieldWinner, UPDATE_BATTLEFIELD_SCORE, and duel events._

170. `BUILT` `W-170` Battlegrounds entered, by battleground (WSG, AB, Darkspear Islands, AV) (entering a pvp instance, by name)
171. `BUILT` `W-171` Battleground wins and losses, by battleground (GetBattlefieldWinner at the end, by battleground)
172. `BUILT` `W-172` Time spent in battlegrounds (5-second ticks in a battleground, by name)
173. `BUILT` `W-173` Time spent in battleground queues (5-second ticks while any queue says queued)
174. `BUILT` `W-174` Battleground killing blows and honorable kills (from the scoreboard) (your scoreboard row at the end (GetBattlefieldScore): killing blows, honorable kills, deaths, by battleground)
175. `BUILT` `W-175` Battleground deaths (deaths from your scoreboard row)
176. `BUILT` `W-176` Flags captured and returned in Warsong Gulch (Warsong Gulch's scoreboard columns (GetBattlefieldStatInfo/Data), whatever they're called)
177. `BUILT` `W-177` Bases assaulted and defended in Arathi Basin (Arathi Basin's scoreboard columns)
178. `BUILT` `W-178` Darkspear Islands objectives (whatever scoreboard columns it reports) (any other battleground's scoreboard columns)
179. `BUILT` `W-179` Alterac Valley towers and graveyards assaulted or defended, captains and generals killed (Alterac Valley's scoreboard columns)
180. `BUILT` `W-180` Battleground marks earned, by battleground (3 per win, 1 per loss) (Mark of Honor items received, by item)
181. `BUILT` `W-181` Level brackets you played each battleground in (battleground and 10-level bracket on entry)
182. `BUILT` `W-182` Honor earned while leveling (honor from kill messages and 'You have been awarded' messages)
183. `BUILT` `W-183` Highest seasonal PvP rank reached while leveling (highest UnitPVPRank seen, with its name)
184. `BUILT` `W-184` XP earned in battlegrounds, if Forever grants it (XP gained while in a battleground)
185. `BUILT` `W-185` Duels requested and accepted (StartDuel (asked) and AcceptDuel (accepted) hooks)
186. `BUILT` `W-186` Duels won and lost (duel result messages compared with your own name)
187. `BUILT` `W-187` Duels won and lost by opponent class (won and lost by the opponent's class (your target at the challenge, or the session's cache))
188. `BUILT` `W-188` Duels fled (left the area) ('has fled from' messages where you're the one who fled)
189. `BUILT` `W-189` Longest duel (from entering combat during the duel to the result)
190. `BUILT` `W-190` Times someone challenged you to a duel (DUEL_REQUESTED)

## Dungeons deep dive
_Forever keeps every Classic dungeon and adds 9 new ones. Use GetInstanceInfo and ENCOUNTER_START/END. Read boss names from the encounter events instead of hardcoding, since the new dungeons' full boss rosters aren't published yet and Forever may rename Classic bosses._

191. `SKIP` `W-191` Runs per dungeon: Classic (RFC, WC, Deadmines, SFK, BFD, Stockade, Gnomeregan, RFK, SM wings, RFD, Uldaman, ZF, Maraudon, Temple of Atal'Hakkar, BRD, LBRS, UBRS, Dire Maul wings, Stratholme, Scholomance) and new (see below) (covered by #73: dungeons entered, by name, every run)
192. `BUILT` `W-192` Clear time per dungeon run (enter to final boss) (time from entering to the final boss's kill, each run kept (newest 100) with your level; final bosses listed in JourneyTrackerDungeons.lua, wings by their bosses, Forever's new dungeons to their last boss)
193. `BUILT` `W-193` Fastest clear per dungeon (fastest clear per dungeon or wing)
194. `BUILT` `W-194` Wipes per dungeon (failed encounters per dungeon)
195. `BUILT` `W-195` Dungeon runs abandoned (left before final boss) (runs that ended without the final boss (or with no boss at all for an unlisted dungeon))
196. `SKIP` `W-196` Every boss killed, keyed by the encounter name the game reports (covered by #41: every boss kill by its encounter name)
197. `BUILT` `W-197` First kill of each dungeon's final boss: level and /played (first kill of each dungeon's (or wing's) final boss, with level and /played)
198. `SKIP` `W-198` Hall of Thanes runs (13-18, beneath Ironforge) (covered by #73: runs by dungeon name)
199. `SKIP` `W-199` Ruins of Lordaeron runs (15-20, Tirisfal Glades) (covered by #73: runs by dungeon name)
200. `SKIP` `W-200` Excavation Site runs (24-29, Wetlands) (covered by #73: runs by dungeon name)
201. `SKIP` `W-201` City of Dalaran runs (28-33, Alterac Mountains) and Shade of the Archmage kills (covered by #73 (runs by dungeon name) and #41 (Shade of the Archmage kills))
202. `SKIP` `W-202` The Drowned City runs (35-40, Stranglethorn Vale) (covered by #73: runs by dungeon name)
203. `SKIP` `W-203` Krol'dok Stronghold runs (40-45, Riverglades) (covered by #73: runs by dungeon name)
204. `SKIP` `W-204` Alcaz Island Prison runs (48-53, Dustwallow Marsh) (covered by #73: runs by dungeon name)
205. `SKIP` `W-205` Blackmaw Hold runs (55-60, Azshara) (covered by #73: runs by dungeon name)
206. `SKIP` `W-206` Shaper's Terrace runs (58-60, Un'Goro Crater) (covered by #73: runs by dungeon name)
207. `BUILT` `W-207` New Forever dungeons vs Classic dungeons: runs and time split (runs and seconds, Forever's new dungeons vs Classic's)
208. `BUILT` `W-208` Scarlet Monastery runs per wing: Graveyard, Library, Armory, Cathedral (Scarlet Monastery runs by wing, told apart by the bosses killed)
209. `BUILT` `W-209` Dire Maul runs per wing and Stratholme runs per side (Dire Maul and Stratholme runs by wing, the same way)
210. `SKIP` `W-210` Herod killed (covered by #28 and #41: kills by name and boss kills)
211. `SKIP` `W-211` Mograine and Whitemane killed (covered by #28 and #41)
212. `SKIP` `W-212` Arugal killed (Shadowfang Keep) (covered by #28 and #41)
213. `SKIP` `W-213` Mr. Smite and Cookie killed (Deadmines) (covered by #28 and #41)
214. `BUILT` `W-214` Mutanus the Devourer killed and Naralex awakened (Wailing Caverns) (Naralex awakened: his disciple's last words in Wailing Caverns; Mutanus kills are #28 and #41)
215. `SKIP` `W-215` Aku'mai killed (Blackfathom Deeps) (covered by #28 and #41)
216. `SKIP` `W-216` Mekgineer Thermaplugg killed (Gnomeregan) (covered by #28 and #41)
217. `SKIP` `W-217` Charlga Razorflank killed (Razorfen Kraul) (covered by #28 and #41)
218. `SKIP` `W-218` Amnennar the Coldbringer killed (Razorfen Downs) (covered by #28 and #41)
219. `SKIP` `W-219` Archaedas killed (Uldaman) (covered by #28 and #41)
220. `BUILT` `W-220` Zul'Farrak graveyard stair event survived (killing Nekrum Gutchewer or Shadowpriest Sezz'ziz, who end the stair event, once a run)
221. `SKIP` `W-221` Chief Ukorz Sandscalp killed (Zul'Farrak) (covered by #28 and #41)
222. `SKIP` `W-222` Princess Theradras killed (Maraudon) (covered by #28 and #41)
223. `SKIP` `W-223` Shade of Eranikus killed (Temple of Atal'Hakkar) (covered by #28 and #41)
224. `SKIP` `W-224` Emperor Dagran Thaurissan killed (BRD) (covered by #28 and #41)
225. `BUILT` `W-225` Times you were the last party member alive in a wipe (everyone in the group dead and you last, from each member's death time, checked every second in instance fights)
226. `BUILT` `W-226` Times you died first in a wipe (the same, you first)
227. `BUILT` `W-227` Dungeon deaths by boss (your deaths during an encounter, by its name)
228. `BUILT` `W-228` Dungeon XP earned per run (Forever shifts XP toward quests, so this is interesting to compare) (XP gained during each run (newest 100))
229. `BUILT` `W-229` Rare-quality boss drops looted per dungeon (blue or better items looted within a minute of a boss dying, by dungeon)
230. `BUILT` `W-230` Dungeon quests completed per dungeon (Dungeon-tagged quests (or quests under a dungeon's quest log header), by that header)
231. `BUILT` `W-231` Times you ran a dungeon 5+ levels over (boosting or farming) (runs at 5+ levels over the dungeon's range)
232. `BUILT` `W-232` Times you were boosted through a dungeon by a much higher player [probe] (runs with a group member 10+ levels above you)
233. `BUILT` `W-233` Party compositions run with (class counts only) (class lists, sorted, per run)
234. `BUILT` `W-234` Tank, healer, or DPS role per run (by spec or self-assigned) (UnitGroupRolesAssigned, or your class and biggest talent tree)
235. `BUILT` `W-235` Times you hearthed out of a dungeon (Hearthstone within 20 seconds of a run ending)
236. `BUILT` `W-236` Instance lockouts hit ('too many instances') ('too many instances' messages)
237. `SKIP` `W-237` Times you released and corpse-ran into a dungeon (covered by #48 and #49: each death's dungeon and how you came back)
238. `SKIP` `W-238` Dungeon you ran most at each 10-level bracket (derived from #74's run list (name and level))
239. `BUILT` `W-239` Dungeon bosses defeated per Legacy bracket (15-25, 26-45, 46-60) (boss kills by bracket (15-25, 26-45, 46-60))

## Raids (post-launch, level 60)
_Raids open December 9, 2026: Onyxia's Lair (40-player), The Barrow Deeps (10-player), Hyjal Summit (20-player). Optional for a 1-60 recap, but cheap to add with the same encounter events._

240. `SKIP` `W-240` Raid runs by raid (covered by #73: raids are counted with the dungeons)
241. `SKIP` `W-241` Raid bosses killed, by encounter name (covered by #41)
242. `BUILT` `W-242` Onyxia killed: /played and days after hitting 60 (first Onyxia kill, with /played and days after 60)
243. `SKIP` `W-243` Raid wipes by boss (covered by #42: wipes by boss, raids included)
244. `BUILT` `W-244` Time from hitting 60 to first raid boss kill (first raid boss kill, days after 60)
245. `BUILT` `W-245` Deaths in raids, and deaths to Onyxia's Deep Breath and whelps (deaths in raids by raid; deaths to whelps; Deep Breath from the combat log where Forever allows it)

## Loot rolls and group life
_START_LOOT_ROLL, CHAT_MSG_LOOT, CHAT_MSG_SYSTEM for /roll results, GROUP_ROSTER_UPDATE._

246. `TODO` `W-246` Need rolls, Greed rolls, and Passes
247. `TODO` `W-247` Rolls won and lost
248. `TODO` `W-248` Highest roll ever and lowest roll ever
249. `TODO` `W-249` Times you won a roll with under 10
250. `TODO` `W-250` Times you lost a roll with over 95
251. `TODO` `W-251` /roll uses and average /roll result
252. `TODO` `W-252` Blue items won on Need
253. `TODO` `W-253` Items you passed on that someone else won
254. `TODO` `W-254` Groups joined
255. `TODO` `W-255` Groups left and times removed from a group
256. `TODO` `W-256` Groups you formed as leader
257. `TODO` `W-257` Time spent in a group with guild members (count, no names)
258. `TODO` `W-258` Times you were the highest level in your party
259. `TODO` `W-259` Times you were the lowest level in your party

## Bloopers (UI error messages)
_UI_ERROR_MESSAGE gives the error type/text. Pure counts, very cheap, and great Wrapped material._

260. `TODO` `W-260` 'You are facing the wrong way' / 'Target needs to be in front of you'
261. `TODO` `W-261` 'Out of range'
262. `TODO` `W-262` 'Not enough mana / rage / energy'
263. `TODO` `W-263` 'Spell is not ready yet' (button mashing)
264. `TODO` `W-264` 'Inventory is full'
265. `TODO` `W-265` 'Can't do that while moving'
266. `TODO` `W-266` 'Invalid target'
267. `TODO` `W-267` 'You can't do that yet' / ability on cooldown
268. `TODO` `W-268` 'Interrupted' cast fails
269. `TODO` `W-269` 'Target not in line of sight'
270. `TODO` `W-270` 'You are too far away'
271. `TODO` `W-271` 'Can't attack while mounted' / 'You are mounted'
272. `TODO` `W-272` 'You are dead' (tried to act while dead)
273. `TODO` `W-273` Hearthstone pressed while on cooldown
274. `TODO` `W-274` 'Not enough money' (tried to buy something you couldn't afford)
275. `TODO` `W-275` 'Can't carry any more of those items' (unique items)
276. `TODO` `W-276` Total errors and your single most common blooper

## Social and chat
_Counts only. Never store message contents or other players' names. Chat may be restricted in combat, so queue and process after combat._

277. `TODO` `W-277` Messages you sent in /say
278. `TODO` `W-278` Messages you sent in /yell
279. `TODO` `W-279` Messages you sent in party chat
280. `TODO` `W-280` Messages you sent in guild chat
281. `TODO` `W-281` Whispers sent
282. `TODO` `W-282` Whispers received
283. `TODO` `W-283` Messages you sent in General/Trade/LFG channels
284. `TODO` `W-284` Times you typed 'lol', 'lmao', or 'haha'
285. `TODO` `W-285` Times you typed 'gz' or 'grats'
286. `TODO` `W-286` Times you typed 'ty' or 'thanks'
287. `TODO` `W-287` Times you typed 'inc' or 'help'
288. `TODO` `W-288` Times you typed 'LFG' or 'LFM'
289. `TODO` `W-289` Times you typed 'brb' or 'afk'
290. `TODO` `W-290` Guild 'gz' messages received within 60 seconds of your ding
291. `TODO` `W-291` Most 'gz' received on a single ding
292. `TODO` `W-292` Your most typed word (top word from your own messages, stored as a word count map, capped)
293. `TODO` `W-293` Messages sent per hour played
294. `TODO` `W-294` Friends added
295. `TODO` `W-295` Players inspected (INSPECT_READY)
296. `TODO` `W-296` Trades completed
297. `TODO` `W-297` Gold given away in trades
298. `TODO` `W-298` Gold received in trades
299. `TODO` `W-299` Items given away in trades
300. `TODO` `W-300` Guilds joined and left
301. `TODO` `W-301` Time in a guild vs unguilded

## Emotes
_CHAT_MSG_TEXT_EMOTE from the player, and emotes targeted at you (count only)._

302. `TODO` `W-302` Total emotes used
303. `TODO` `W-303` Your most used emote
304. `TODO` `W-304` /dance count
305. `TODO` `W-305` /lol and /laugh count
306. `TODO` `W-306` /spit count
307. `TODO` `W-307` /cheer and /applaud count
308. `TODO` `W-308` /hug count
309. `TODO` `W-309` /sit and /sleep count
310. `TODO` `W-310` /train count (the classic choo choo)
311. `TODO` `W-311` Emotes other players directed at you
312. `TODO` `W-312` Most received emote

## Movement and world mechanics
_IsSwimming, IsFalling, IsFlying, IsIndoors, IsOutdoors, MIRROR_TIMER_START (BREATH, EXHAUSTION, FEIGNDEATH), sampled positions._

313. `TODO` `W-313` Time spent swimming
314. `TODO` `W-314` Distance swum
315. `TODO` `W-315` Time underwater (breath bar active)
316. `TODO` `W-316` Times your breath bar ran out
317. `TODO` `W-317` Times you entered fatigue (deep water)
318. `TODO` `W-318` Time spent falling
319. `TODO` `W-319` Longest single fall (time airborne)
320. `TODO` `W-320` Times you fell more than 5 seconds
321. `TODO` `W-321` Fall damage taken out of combat (health drop on landing) [probe]
322. `TODO` `W-322` Distance traveled on foot vs mounted
323. `TODO` `W-323` Times your hearthstone location changed (HEARTHSTONE_BOUND)
324. `TODO` `W-324` Inn you bound to most
325. `TODO` `W-325` Time spent at your bound inn
326. `TODO` `W-326` Times you logged out in an inn vs in the field
327. `TODO` `W-327` Rested XP gained while logged out
328. `TODO` `W-328` Times you hit max rested XP
329. `BUILT` `W-329` Boat rides total (boat rides from the dock-to-dock detector in JourneyTrackerIconic.lua)
330. `BUILT` `W-330` Zeppelin rides total (zeppelin rides, same detector)
331. `TODO` `W-331` Portal uses (mage portals, Rut'theran, etc.)
332. `TODO` `W-332` Summons accepted
333. `TODO` `W-333` Times you used a meeting stone
334. `TODO` `W-334` Corpse run distance total
335. `TODO` `W-335` Times you got lost: time in a subzone with no quest objective or kill for 5+ minutes

## Death memes
_Build on PLAYER_DEAD plus context cached before death. [probe] where cause needs combat info._

336. `TODO` `W-336` Deaths by falling [probe]
337. `TODO` `W-337` Deaths by drowning (breath timer ran out before death)
338. `TODO` `W-338` Deaths by fatigue
339. `TODO` `W-339` Deaths to guards
340. `TODO` `W-340` Deaths to elites
341. `TODO` `W-341` Deaths to murlocs [probe]
342. `TODO` `W-342` Deaths to critters (yes, it happens) [probe]
343. `TODO` `W-343` Deaths within 10 seconds of dinging
344. `TODO` `W-344` Deaths within 60 seconds of logging in
345. `TODO` `W-345` Deaths while AFK
346. `TODO` `W-346` Deaths during escort quests
347. `TODO` `W-347` Deaths with Resurrection Sickness still active
348. `TODO` `W-348` Deaths right after a spirit healer rez (within 2 minutes)
349. `TODO` `W-349` Deaths in a sanctuary or friendly town
350. `TODO` `W-350` Deaths with a full health bar 5 seconds earlier (one-shots) [probe]
351. `TODO` `W-351` Deaths while a healthstone or potion was in your bags and off cooldown
352. `TODO` `W-352` Deaths with Hearthstone off cooldown
353. `TODO` `W-353` Deaths while mounted (dismounted and killed)
354. `TODO` `W-354` Times you died twice in one minute
355. `TODO` `W-355` Longest time alive without dying (/played)
356. `TODO` `W-356` Death count at each 10 levels
357. `TODO` `W-357` Death clock: average /played between deaths
358. `TODO` `W-358` Ghost time: time spent as a ghost total

## Economy, vendors, AH, mail
_PLAYER_MONEY deltas with context (merchant open, mail open, AH open, trade, quest)._

359. `TODO` `W-359` Gray (junk) items sold and gold from junk
360. `TODO` `W-360` Most valuable gray item sold
361. `TODO` `W-361` Items bought from vendors
362. `TODO` `W-362` Most expensive vendor purchase
363. `TODO` `W-363` Items destroyed (deleted)
364. `TODO` `W-364` Gold spent on bags
365. `TODO` `W-365` First bag of each size: 6, 8, 10, 12, 14, 16 slot
366. `TODO` `W-366` Bank slots bought and gold spent
367. `TODO` `W-367` Auctions posted
368. `TODO` `W-368` Auctions sold, expired, and cancelled
369. `TODO` `W-369` Gold lost to auction deposits and cuts
370. `TODO` `W-370` Most expensive item you sold on the AH
371. `TODO` `W-371` Most expensive item you bought on the AH
372. `TODO` `W-372` Mail sent and received
373. `TODO` `W-373` COD mail sent and received
374. `TODO` `W-374` Gold sent and received by mail
375. `BUILT` `W-375` Gold spent on mounts (price of a mount bought from a vendor (JourneyTrackerIconic.lua))
376. `TODO` `W-376` Gold spent on talent respecs
377. `TODO` `W-377` Gold earned from quests per level
378. `TODO` `W-378` Times you went broke (under 1 silver)
379. `TODO` `W-379` Richest moment relative to level (gold per level)
380. `TODO` `W-380` Lockboxes looted
381. `TODO` `W-381` Treasure chests looted in the world
382. `TODO` `W-382` Gold looted from chests

## Gear and character stats
_Snapshot out of combat at each ding: UnitStat, UnitArmor, UnitAttackPower, GetCritChance, UnitResistance, durability, item links._

383. `TODO` `W-383` Strength, Agility, Stamina, Intellect, Spirit at each ding
384. `TODO` `W-384` Armor at each ding
385. `TODO` `W-385` Max health and max mana at each ding
386. `TODO` `W-386` Attack power and spell power at each ding
387. `TODO` `W-387` Crit chance at each ding
388. `TODO` `W-388` Resistances at each ding
389. `TODO` `W-389` Main hand weapon DPS at each ding
390. `TODO` `W-390` Average item level at each ding
391. `TODO` `W-391` Gear rarity breakdown at each ding (grays, whites, greens, blues, purples worn)
392. `TODO` `W-392` 'of the Monkey', 'of the Bear', 'of the Eagle', 'of the Whale' and other suffix items looted
393. `TODO` `W-393` Your most common gear suffix
394. `TODO` `W-394` Items equipped total
395. `TODO` `W-395` Gear swaps per level
396. `SKIP` `W-396` Longest worn item (by /played) and its slot (covered by #104 in journey-tracking-spec.md, which also tracks levels gained while worn)
397. `TODO` `W-397` First two-handed weapon equipped
398. `TODO` `W-398` Times an item broke (durability 0)
399. `TODO` `W-399` Times your gear went yellow or red (low durability)
400. `TODO` `W-400` Biggest repair bill
401. `TODO` `W-401` Enchants applied to your gear
402. `TODO` `W-402` Armor kits, sharpening stones, and weightstones used
403. `TODO` `W-403` BoE items sold or vendored instead of equipped
404. `TODO` `W-404` Quest reward choices: which slot you picked most
405. `TODO` `W-405` Quest reward items vendored without ever equipping
406. `TODO` `W-406` Talent points spent, in order, with level spent
407. `TODO` `W-407` Talent respecs
408. `TODO` `W-408` Talent tree split at 60
409. `TODO` `W-409` Spells learned at trainers vs from items/books
410. `TODO` `W-410` Most cast spell overall

## Professions deep dive
_Item diffs, CHAT_MSG_LOOT, CHAT_MSG_SKILL, TRADE_SKILL events, UNIT_SPELLCAST_SUCCEEDED for gathering._

411. `TODO` `W-411` Herbs picked by type (Peacebloom, Silverleaf, Earthroot, Mageroyal, Briarthorn, Bruiseweed, Kingsblood, Fadeleaf, Goldthorn, Firebloom, Sungrass, and more)
412. `TODO` `W-412` Black Lotus picked
413. `TODO` `W-413` Ore mined by type (Copper, Tin, Silver, Iron, Gold, Mithril, Truesilver, Thorium)
414. `TODO` `W-414` Truesilver and Silver veins found
415. `TODO` `W-415` Gems found while mining
416. `TODO` `W-416` Skins gathered by type (Light, Medium, Heavy, Thick, Rugged leather)
417. `TODO` `W-417` Cloth looted by type (Linen, Wool, Silk, Mageweave, Runecloth)
418. `TODO` `W-418` Total cloth looted
419. `TODO` `W-419` Gathering nodes by zone
420. `TODO` `W-420` Nodes you lost to another player (node vanished mid-gather) [probe]
421. `TODO` `W-421` Fishing casts and catch rate
422. `TODO` `W-422` Fish caught by type
423. `TODO` `W-423` Junk vs fish from fishing
424. `TODO` `W-424` Fishing pools fished
425. `TODO` `W-425` Longest fishing session
426. `TODO` `W-426` Items cooked and most cooked recipe
427. `TODO` `W-427` Recipes learned per profession
428. `TODO` `W-428` Rare recipes learned from drops
429. `TODO` `W-429` Profession skill at each ding
430. `TODO` `W-430` Items disenchanted and materials gained
431. `TODO` `W-431` Enchants cast on other players' gear
432. `TODO` `W-432` Engineering explosives thrown
433. `TODO` `W-433` Target Dummies deployed
434. `TODO` `W-434` Goblin Jumper Cables used: successes vs failures
435. `TODO` `W-435` Gnomish gadgets used (Mind Control Cap, Death Ray, Net-o-Matic, etc.)
436. `TODO` `W-436` Potions and elixirs crafted
437. `TODO` `W-437` Gold earned from selling gathered materials
438. `TODO` `W-438` Professions dropped (unlearned)

## Reputation and factions
_CHAT_MSG_COMBAT_FACTION_CHANGE and the reputation API._

439. `TODO` `W-439` Reputation gained by faction
440. `TODO` `W-440` Level reached Friendly, Honored, Revered, and Exalted with each faction
441. `TODO` `W-441` Reputation lost by faction
442. `TODO` `W-442` Times you turned on Booty Bay (Bloodsail Buccaneers rep gained)
443. `TODO` `W-443` Timbermaw Hold reputation progression
444. `TODO` `W-444` Cenarion Circle reputation progression
445. `TODO` `W-445` Argent Dawn reputation progression
446. `TODO` `W-446` Thorium Brotherhood reputation progression
447. `TODO` `W-447` Ravenholdt reputation (rogues)
448. `TODO` `W-448` Steamwheedle Cartel reputation progression
449. `TODO` `W-449` Home city reputation at 60
450. `TODO` `W-450` Other faction cities reputation at 60
451. `TODO` `W-451` Faction you gained the most reputation with
452. `TODO` `W-452` Reputation turn-ins (cloth donations, etc.)
453. `TODO` `W-453` Cloth donated to city quartermasters
454. `TODO` `W-454` Desolace centaur faction chosen

## Holidays and world events
_Forever's holiday calendar isn't confirmed yet. Build these behind a flag and mark BLOCKED if an event never shows up._

455. `TODO` `W-455` Darkmoon Faire visits
456. `TODO` `W-456` Darkmoon Faire tickets turned in
457. `TODO` `W-457` Darkmoon Faire fortune received
458. `TODO` `W-458` Hallow's End candy buckets looted and tricks/treats
459. `TODO` `W-459` Winter Veil presents opened
460. `TODO` `W-460` Stranglethorn Fishing Extravaganza participation
461. `TODO` `W-461` Holiday quests completed total

## Milestones and firsts
_Each records level, /played, zone, and real timestamp._

462. `TODO` `W-462` First quest completed
463. `TODO` `W-463` First death
464. `TODO` `W-464` First group joined
465. `TODO` `W-465` First dungeon entered
466. `TODO` `W-466` First green item looted
467. `TODO` `W-467` First time reaching 1 gold, 10 gold, 100 gold
468. `BUILT` `W-468` First enemy player killed (first enemy player kill, with their class and level (JourneyTrackerPvP.lua))
469. `BUILT` `W-469` First time killed by an enemy player (first death to a player, with their class and level)
470. `TODO` `W-470` First trip to each capital city
471. `TODO` `W-471` First flight path taken
472. `BUILT` `W-472` First boat or zeppelin ride (first boat or zeppelin ride, with the route)
473. `TODO` `W-473` First mount summoned
474. `TODO` `W-474` First profession maxed for its bracket (75, 150, 225, 300)
475. `TODO` `W-475` First time hitting Exalted with any faction
476. `TODO` `W-476` First talent point
477. `TODO` `W-477` First class quest completed
478. `TODO` `W-478` First rare killed
479. `BUILT` `W-479` First time in a battleground (first battleground entered)
480. `BUILT` `W-480` First duel won (first duel won, with the opponent's class)
481. `TODO` `W-481` First time reaching rested max
482. `TODO` `W-482` Last death before 60
483. `TODO` `W-483` The ding to 60: zone, subzone, coords, time of day, cause, who was in your group (count/classes only)

## Sessions and habits
_From login/logout timestamps and per-session counters._

484. `TODO` `W-484` Day of week you played most
485. `TODO` `W-485` Longest gap between sessions
486. `TODO` `W-486` Longest streak of consecutive days played
487. `TODO` `W-487` Late-night dings (between midnight and 5am local time)
488. `TODO` `W-488` Weekend vs weekday playtime
489. `TODO` `W-489` Session with the most deaths
490. `TODO` `W-490` Session with the most kills
491. `TODO` `W-491` Average time from login to first kill
492. `TODO` `W-492` Reloads (/reload) count
493. `TODO` `W-493` Screenshots taken (SCREENSHOT_SUCCEEDED)
494. `TODO` `W-494` Auto-screenshot at every ding (optional setting, Screenshot())
495. `TODO` `W-495` Times you logged in, played under 5 minutes, and logged out
496. `TODO` `W-496` Most productive hour of /played (most XP in one hour)
497. `TODO` `W-497` Percentage of time spent in combat vs out
498. `TODO` `W-498` Percentage of time spent questing vs grinding (quest objective active vs not)
499. `TODO` `W-499` Percentage of time spent in town
500. `TODO` `W-500` Playtime per real-world week

## Blizzard Statistics pane
_WoW Forever's Statistics pane on the character page (combat, PvP, creatures, gold, consumables, factions, items, professions, dungeons/raids, emotes), read with the retail statistics API: GetStatisticsCategoryList, GetCategoryInfo, GetCategoryNumAchievements, GetAchievementInfo, GetStatistic. Never read in combat; secret values are skipped; values are stored raw and parsed on the website._

501. `BUILT` `W-501` Statistics API availability on Forever (probe result) (`/journey statprobe`, dev only; full results in JourneyTrackerDB.dev.statProbe)
502. `BUILT` `W-502` Full statistics baseline at first load, with level and /played (db.statistics.baseline, read 10s after the first login with this version; never replaced; also records our own counts and trackedSince)
503. `BUILT` `W-503` Statistics snapshot at every ding (diff only) (db.statistics.levels[level].changed, against the previous ding or the baseline; queued until combat ends)
504. `BUILT` `W-504` Statistics snapshot at every export
505. `BUILT` `W-505` Statistics included in the export string (`statistics` section: names lookup, categories, baseline, latest, per-level diffs, skipped)
506. `BUILT` `W-506` Lifetime totals backfill for players who installed mid-leveling (baseline and latest in the export; in the window, rows both sides count show the bigger number, and every other statistic shows on the page it fits)
507. `BUILT` `W-507` Cross-check: our kill, death, and quest counts vs Blizzard's for the same period (our counts are kept with each snapshot; `/journey stats` prints the comparison since the baseline)
508. `BUILT` `W-508` Combat stats our tracking can't see: total damage dealt and received, largest hit, largest heal, total healing (Forever's pane has them, read with every snapshot: IDs 197/528 total damage done/received, 193/527 largest hit dealt/received, 198/830 total healing done/received, 189/829 largest heal cast/received; all still "--" on a level 20 character in the beta, so Forever may not count them yet)

## Changelog
- 2026-10-01: Wrapped spec created, all items `TODO`. Revised for Forever content: new dungeons, raids, battlegrounds, and Forever exclusives.
- 2026-10-01: Section 1 (WoW Forever exclusives) done in JourneyTrackerWrapped.lua with the Track registry (count/time/max/first, maps capped at 200) and a [probe] feature flag. W-001..003, 006..012, 016, 017, 019..021 `BUILT`; W-004, 005, 018 `SKIP`; W-013..015 left `TODO` until the Legacy API is found.
- 2026-10-01: Camping (W-008..012) now shown on the Social page, since camping is a social mechanic; the WoW Forever page keeps the rest of section 1.
- 2026-10-01: VERIFIED in game: W-003, W-009, W-011, W-020.
- 2026-10-01: W-396 `SKIP`: built as journey #104 (gear worn the longest, by /played and by levels gained).
- 2026-10-01: Added the "Blizzard Statistics pane" section (W-501..W-508) and an architecture note on using Blizzard's statistics for lifetime totals. W-501 `BUILT`: `/journey statprobe` (dev only) in JourneyTrackerStats.lua. W-502..W-508 wait for the probe result.
- 2026-10-01: Probe run in game on Forever (client 1.60.1): all 5 statistics functions exist, 26 categories, 195 statistics read in 11 ms, none secret.
- 2026-10-01: W-502..W-507 `BUILT` in JourneyTrackerStats.lua (statistics snapshots): every statistic keyed by ID with raw values, names and categories stored once in db.statistics; a baseline 10s after login, a diff at every ding (queued until combat ends), a full snapshot at every export and every 5 minutes as `latest`. Reads are spread over frames (4 ms each), stop if combat starts, and skip secret values (listed in db.statistics.skipped). `/journey stats` prints the count, baseline level, last snapshot and the cross-check. The export carries a `statistics` section (format unchanged; no migration needed, the new table is filled from defaults). tools/import: `--stats` prints the baseline level and statistic counts per export. W-508 stays `TODO` until the probe dump shows whether Forever's pane has the combat statistics.
- 2026-10-01: Probe dump and first snapshots read from a level 20 character (client 1.60.1, build 70170): 195 statistics in 26 categories, every value text, 167 of them "--"; no hidden, secret or account-flagged statistics; no C_ statistics namespace (GetComparisonStatistic also exists). The baseline and a later login snapshot both saved all 195. Findings that matter for the website: "Total kills that grant experience or honor" includes honorable kills (52 here, all PvP), and some counters look like they started when Forever added the pane (Creatures killed is 3 at level 20) while others cover the whole character (Quests completed 133), so not every "lifetime" number is lifetime. Deaths and flights changed in step with our own counts. Fixes: the window's "all time" rows use Creatures killed (Summary, Kills) and add Total Honorable Kills (Bosses & PvP); the W-507 cross-check takes honorable kills off Blizzard's kill count. W-508 `BUILT`: the combat statistics exist and are read with everything else.
- 2026-10-01: The window's separate Lifetime > Statistics Pane page is gone. Every statistic now shows on the existing page it fits (category to page by category ID; one with no page goes where its parent goes, else on the Summary), all of them, "--" included. Rows both sides count show the bigger of the two numbers (both start partway through a character's life): Summary, Quests completed/abandoned/gold, Total deaths, Deaths from falling, XP-granting kills (the game's experience-or-honor kills less honorable kills), Honorable kills, Hearthstone uses, Flights taken, the Gold page's earned/spent rows, profession skill bars, Fish caught, and health/mana potions; those statistics aren't listed again. The window reads the pane again when it opens and every 20 seconds while it's open (out of combat only).
- 2026-10-05: Sections 2-6 (creature families, Alliance, Horde and neutral iconic, rares) done in the new JourneyTrackerIconic.lua, plus boats and zeppelins (W-329, W-330, W-472) and gold spent on mounts (W-375), which the iconic routes and racial mounts needed. W-022..W-139 `BUILT` except the world PvP ones (W-080, W-091, W-100, left for the PvP section); W-113 and W-114 `SKIP` (covered by #46 and #66). The main tracker now passes kills (with zone, creature type and beast family), fights (with who was in them and the highest mob level), deaths, falls, loot and money changes to the wrapped files (ns.OnKill and friends, each run protected so a wrapped tracker can't break the main one), and remembers enemy players' class and level for the session only. Kills without experience (critters, Gamon) are counted when a target you attacked dies, and from the combat log where Forever lets addons read it ([probe]); neither counts a kill the experience message already did. The window has a new Wrapped Stats section (folded at first) with Creature Families, Iconic Moments and Rares & Elites pages. Checked outside the game (fengari, real saved data): murlocs in and out of a fight, wolves vs worgen, Hogger and the two Princesses, a chicken and a kobold, capital visits, a boat and a zeppelin ride, a guard death, quests, a Wanted target, loot, a rare, the Horde items, the export and every page.
- 2026-10-05: Sections 7-8 (world PvP, battlegrounds and duels) done in the new JourneyTrackerPvP.lua, with the iconic PvP items (W-080, W-091, W-100) and the PvP firsts (W-468, W-469, W-479, W-480). W-140..W-190 `BUILT` except W-164 `BLOCKED` (health is secret on Forever). Enemy players killed come from honorable kill messages, enemy player targets you attacked dying, and the combat log where allowed; one player within 10 seconds counts once, and only class and level are kept. Battleground objectives come from your scoreboard row at the end, column by column, so Darkspear Islands' columns are kept whatever they're called. Duel results come from the system messages; the client's format there uses numbered parts (%1$s), so the pattern builder handles those. Checked outside the game: a stealth gank and an honorable kill (and the same player not counted twice), a corpse camp, two duels, a Warsong Gulch win with its scoreboard, and every page.
- 2026-10-05: Sections 9-10 (dungeons deep dive, raids) done in the new JourneyTrackerDungeons.lua. `BUILT`: clear times, fastest clears, wipes and abandoned runs per dungeon, first final-boss kills, Forever vs Classic runs, Scarlet Monastery, Dire Maul and Stratholme wings (told apart by the bosses killed), Naralex awakened, the Zul'Farrak stairs, last one standing and first to fall in a wipe, deaths by boss, XP per run, blue boss drops, dungeon quests by dungeon, runs over level or boosted, party compositions (classes only), your role, hearthing out, lockouts, bosses by Legacy bracket, Onyxia and the first raid boss after 60, deaths in raids. `SKIP`: runs per dungeon and the nine new dungeons' runs (#73), each named boss (#28, #41), corpse runs into dungeons (#48-49), most-run dungeon per bracket (#74), raid runs, kills and wipes (#73, #41-42). The window can now draw maps of records (the Forever vs Classic split) as rows. Checked outside the game: a Deadmines run with a trash wipe, a death on Mr. Smite, VanCleef, a blue drop, a dungeon quest and a hearth out; a Scarlet Monastery Armory run from Herod's kill; Shadowfang Keep left early; a lockout; Onyxia. No stray globals.
