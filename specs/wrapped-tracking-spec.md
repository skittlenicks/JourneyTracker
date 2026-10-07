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

1. `BUILT` `W-001` Skyborne: time on Zephras Isle and level you left it (level you left from zone changes, not the zone's name reading empty for a moment; time on the isle from #66)
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
13. `BUILT` `W-013` Legacy challenges completed while leveling (class levels 25/45/60, tradeskills 150/225/300, etc.) (Legacy API unknown; /jprobe api will find its functions and events) ([probe] the game's system messages that mention Legacy, kept with level and date (newest 60), until the Legacy API is known; never one with a player in it (a player link, a [name] or <guild> as in /who, or a name seen this session, yours included); the Legacy-named functions this client has are listed in db.wrapped.legacyApi (JourneyTrackerSocial.lua))
14. `BUILT` `W-014` Legacy points earned and when (Legacy API unknown; waiting on /jprobe api) ([probe] Legacy messages that mention points, as W-013)
15. `BUILT` `W-015` Legacy perks chosen, by tree (Professions, Adventure, Resourcefulness), and the level each was picked (Legacy API unknown; waiting on /jprobe api) ([probe] Legacy messages that mention perks, as W-013)
16. `BUILT` `W-016` Lord Valthalak questline progress (quests with Valthalak in the title or turned in to Bodley)
17. `BUILT` `W-017` World map exploration percentage at each ding (Legacy Adventure challenge) (explored map areas counted at each ding; percentage left to the website)
18. `SKIP` `W-018` Racial abilities used: each of Forever's active racials (duplicates ALL-09; every cast is counted in db.class, so new racials show up once named)
19. `BUILT` `W-019` Transmog changes made and gold spent on transmog (retail transmog events (TRANSMOGRIFY_*); unverified on Forever)
20. `VERIFIED` `W-020` Ruleset played (Normal, PvP, Roleplaying, Hardcore when it arrives) (Hardcore from C_GameRules, PvP/RP from the realm name or an auto-flag as W-021 counts them, so a Normal realm's flags from fights don't make it PvP) (confirmed in game, again after the 2026-10-05 change)
21. `BUILT` `W-021` Times auto-flagged for PvP by entering a contested or enemy zone (PvP ruleset) (PvP flag turned on without /pvp in a contested or hostile zone within 10 seconds of arriving, out of a fight and with no fight starting in the next 2 seconds; the zone's type from C_PvP.GetZonePVPInfo, or the older global, or where the game gives none (most zones on Forever; addon 0.6.8 on) Classic's own type for the zone by its map ID: each faction's starting zones, the zones next to them and its capitals friendly to it and hostile to the other, the rest of the old world contested, as the client's own zone data (AreaTable) has them; Forever's new zones from the same data (addon 0.6.9 on): Mount Hyjal, Riverglades and Shen'dralas contested (no faction), Zephras Isle a sanctuary (its sanctuary flag) (ns.ZonePvP))

## Creature kills: meme families
_[probe] Kill attribution by mob name/type. Match on name keywords plus UnitCreatureType/UnitCreatureFamily cached at target time._

22. `BUILT` `W-022` Murlocs slain (kills matched on name keywords, creature type or beast family from FAMILIES in JourneyTrackerIconic.lua; kills without experience counted when a target you attacked dies (not a corpse, or a mob someone else tagged), or from the combat log where Forever allows it; at load, each family is raised to what its names add up to in the whole journey's kills by name (#28), never lowered (families known only by creature type can't be))
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
53. `BUILT` `W-053` Whelps and dragonkin slain (creature type Dragonkin or whelp/drake/dragon names, not Dragonmaw)
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
73. `BUILT` `W-073` Times entered Ironforge, Stormwind, and Darnassus (entries by city, a new visit after 10 minutes away; like every visit, not flown over on a flight path, and not logging in or reloading where you are: when each place was last seen is kept in db.wrapped.visitsSeen and refreshed every 5 seconds)
74. `BUILT` `W-074` Time AFK in Ironforge (5-second ticks AFK in Ironforge)
75. `BUILT` `W-075` Boat rides: Menethil to Auberdine, Menethil to Theramore, Auberdine to Rut'theran (dock to dock on a known route within 8 minutes of leaving the dock, with no flight, hearth, teleport, portal or summon between; docks flown over don't count (subzones Menethil Harbor, Auberdine, Theramore Isle, Rut'theran Village))
76. `BUILT` `W-076` Rut'theran portal uses to Darnassus (Darnassus moments after being in Rut'theran Village, not by hearth)
77. `BUILT` `W-077` Times visited Southshore (subzone visits)
78. `BUILT` `W-078` Times visited Theramore (subzone visits)
79. `BUILT` `W-079` Times you entered Orgrimmar, Thunder Bluff, or Undercity (enemy capitals) (entries by city)
80. `BUILT` `W-080` Horde players killed in Southshore or Hillsbrad [probe] (enemy players killed in Hillsbrad Foothills (JourneyTrackerPvP.lua))
81. `BUILT` `W-081` Racial mount bought: horse, ram, mechanostrider, or nightsaber (a mount item (class 15, subclass 5) bought from a vendor, with its price: the payment paired with it, either order, within 3 seconds; not for a Skyborne who hasn't chosen a side)
82. `BUILT` `W-082` Level you left your starting zone (first move from your race's starting zone and capital to anywhere else, not the zone's name reading empty for a moment; not recorded if the tracker already saw you elsewhere)
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
94. `BUILT` `W-094` Undercity elevator rides (moving between Undercity and Tirisfal Glades, not on a flight path or within 30 seconds of a hearth, teleport or summon; a 30+ yard fall landing in the next 10 seconds makes it a fall, not a ride)
95. `BUILT` `W-095` Deaths falling from the Undercity elevator [probe] (deaths by falling in Undercity or the Ruins of Lordaeron)
96. `BUILT` `W-096` Thunder Bluff elevator rides and falls off Thunder Bluff (moving between Thunder Bluff and Mulgore as W-094; falls of 30+ yards landing in Mulgore within 15 seconds of being in Thunder Bluff)
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
129. `BUILT` `W-129` Time spent in contested zones vs friendly zones (time by the zone's PvP type (friendly, contested, hostile, sanctuary), read as W-021 reads it; "unknown" for a place with no type (a dungeon, or Forever's new zones before addon 0.6.9), "unrestricted" before addon 0.6.8, when Forever's client gave most zones none)

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

140. `BUILT` `W-140` Enemy players killed total (honorable or not) (honorable kill messages, enemy player targets you attacked dying, and the combat log where Forever allows it; the same player (by GUID, or name without its realm) within 10 seconds counts once, and one with no name to compare is the kill just before it within 2 seconds; a target already dead isn't watched; class and level kept, never names (JourneyTrackerPvP.lua))
141. `BUILT` `W-141` Lowbies ganked: enemy players 10+ levels below you killed (victims 10+ levels below you)
142. `BUILT` `W-142` Stealth ganks: lowbies killed where you opened from stealth (rogue/druid) (lowbie kills in a fight that began while you were stealthed)
143. `BUILT` `W-143` Biggest level gap in a gank (your level minus theirs) (biggest gap, with the victim's class)
144. `BUILT` `W-144` Times you were ganked: killed by an enemy player 10+ levels above you (deaths to a player 10+ levels above you (or a skull))
145. `BUILT` `W-145` Biggest level gap when you got ganked (biggest gap, with the killer's class)
146. `BUILT` `W-146` Times corpse camped: killed by the same enemy player class/level combo 3+ times within 10 minutes (three deaths to the same class and level within 10 minutes, outside battlegrounds; a killer whose class or level wasn't seen doesn't count)
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
158. `BUILT` `W-158` Times you accidentally flagged (attacked a flagged player or entered a hostile town) (flag turned on without that, outside contested and enemy zones (those are W-021), the zone's type read as W-021 reads it)
159. `BUILT` `W-159` Dishonorable kills (civilian NPCs killed) (dishonorable kill messages)
160. `BUILT` `W-160` Enemy guards killed (kills of the other faction's guards: a guard's name and the mob's faction seen as the other side's; at 60, where no kill gives experience, from the kills without it (W-022))
161. `BUILT` `W-161` Times killed by enemy guards (deaths to the other faction's guards, name and faction as W-160)
162. `BUILT` `W-162` Times you attacked an enemy town (entering combat in an enemy town, once per town per 10 minutes; a capital is one town)
163. `BUILT` `W-163` Faction leaders killed (Thrall, Cairne, Sylvanas, Bolvar, Magni, Tyrande, etc.) (kills by name, by leader; at 60 as W-160)
164. `BLOCKED` `W-164` Enemy players killed while you were at less than 20% health (clutch wins) (your health is SECRET on Forever (probe), so it can't be read at a kill)
165. `BUILT` `W-165` Times you died to an enemy player while fighting a mob (third-partied) (deaths to a player in a fight that also had a mob)
166. `BUILT` `W-166` Times you killed an enemy player who was fighting a mob (enemy players who were targeting a mob when they died on your target)
167. `BUILT` `W-167` Times you used Feign Death, Vanish, or similar to escape an enemy player (Feign Death, Vanish, Ice Block, Divine Shield, Blessing of Protection or Invisibility in a fight with a player, then out of combat alive within 10 seconds)
168. `BUILT` `W-168` Enemy players killed in their own capital (kills in the other faction's capitals)
169. `BUILT` `W-169` Kill streaks: most enemy players killed without dying (kills since your last death, best kept)

## Battlegrounds and duels
_Forever battlegrounds: Warsong Gulch (10v10, brackets from 10-19), Arathi Basin (15v15, from 20-29), Darkspear Islands (15v15, from 30-39), Alterac Valley (40v40, 51-60). No arenas. Use GetBattlefieldStatus, GetBattlefieldWinner, UPDATE_BATTLEFIELD_SCORE, and duel events._

170. `BUILT` `W-170` Battlegrounds entered, by battleground (WSG, AB, Darkspear Islands, AV) (entering a pvp instance, by name; the match is kept in db.wrapped.bgMatch, so a /reload inside doesn't enter, win or read the scoreboard again)
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
183. `BUILT` `W-183` Highest seasonal PvP rank reached while leveling (highest rank seen, with its title: on Forever the renown level of its PvP rank points faction (2800, C_MajorFactions), as its character sheet's PvP tab reads it; UnitPVPRank on older clients)
184. `BUILT` `W-184` XP earned in battlegrounds, if Forever grants it (XP gained while in a battleground)
185. `BUILT` `W-185` Duels requested and accepted (StartDuel (asked) and AcceptDuel (accepted) hooks)
186. `BUILT` `W-186` Duels won and lost (duel result messages compared with your own name)
187. `BUILT` `W-187` Duels won and lost by opponent class (won and lost by the opponent's class (your target when you challenge, the challenger's from the session's cache when you're challenged, or the cache at the result))
188. `BUILT` `W-188` Duels fled (left the area) ('has fled from' messages where you're the one who fled)
189. `BUILT` `W-189` Longest duel (from entering combat during the duel to the result)
190. `BUILT` `W-190` Times someone challenged you to a duel (DUEL_REQUESTED)

## Dungeons deep dive
_Forever keeps every Classic dungeon and adds 9 new ones. Use GetInstanceInfo and ENCOUNTER_START/END. Read boss names from the encounter events instead of hardcoding, since the new dungeons' full boss rosters aren't published yet and Forever may rename Classic bosses._

191. `SKIP` `W-191` Runs per dungeon: Classic (RFC, WC, Deadmines, SFK, BFD, Stockade, Gnomeregan, RFK, SM wings, RFD, Uldaman, ZF, Maraudon, Temple of Atal'Hakkar, BRD, LBRS, UBRS, Dire Maul wings, Stratholme, Scholomance) and new (see below) (covered by #73: dungeons entered, by name, every run)
192. `BUILT` `W-192` Clear time per dungeon run (enter to final boss) (time from entering to the final boss's kill, each run kept (newest 100) with your level; final bosses listed in JourneyTrackerDungeons.lua, wings by their bosses (Blackrock Spire's Upper and Lower halves too, as the game calls both Blackrock Spire), Forever's new dungeons to their last boss (from addon 0.6.8 on, the Hall of Thanes', Ruins of Lordaeron's and Excavation Site's listed, the last in the client's DungeonEncounter table), each dungeon known by its name however Forever's client gives it ("Excavation Site: Wetlands", "The Hall of Thanes"; addon 0.6.8 on); the run in progress is kept in db.wrapped.dungeonRun with real times, so a /reload or relog inside carries on with it)
193. `BUILT` `W-193` Fastest clear per dungeon (fastest clear per dungeon or wing)
194. `BUILT` `W-194` Wipes per dungeon (failed encounters per dungeon)
195. `BUILT` `W-195` Dungeon runs abandoned (left before final boss) (runs that ended without the final boss (or with no boss at all for an unlisted dungeon))
196. `SKIP` `W-196` Every boss killed, keyed by the encounter name the game reports (covered by #41: every boss kill by its encounter name)
197. `BUILT` `W-197` First kill of each dungeon's final boss: level and /played (first kill of each dungeon's (or wing's) final boss, with level and /played; final bosses and dungeon names as W-192 reads them)
198. `SKIP` `W-198` Hall of Thanes runs (13-18, beneath Ironforge) (covered by #73: runs by dungeon name)
199. `SKIP` `W-199` Ruins of Lordaeron runs (15-20, Tirisfal Glades) (covered by #73: runs by dungeon name)
200. `SKIP` `W-200` Excavation Site runs (24-29, Wetlands) (covered by #73: runs by dungeon name)
201. `SKIP` `W-201` City of Dalaran runs (28-33, Alterac Mountains) and Shade of the Archmage kills (covered by #73 (runs by dungeon name) and #41 (Shade of the Archmage kills))
202. `SKIP` `W-202` The Drowned City runs (35-40, Stranglethorn Vale) (covered by #73: runs by dungeon name)
203. `SKIP` `W-203` Krol'dok Stronghold runs (40-45, Riverglades) (covered by #73: runs by dungeon name)
204. `SKIP` `W-204` Alcaz Island Prison runs (48-53, Dustwallow Marsh) (covered by #73: runs by dungeon name)
205. `SKIP` `W-205` Blackmaw Hold runs (55-60, Azshara) (covered by #73: runs by dungeon name)
206. `SKIP` `W-206` Shaper's Terrace runs (58-60, Un'Goro Crater) (covered by #73: runs by dungeon name)
207. `BUILT` `W-207` New Forever dungeons vs Classic dungeons: runs and time split (runs and seconds, Forever's new dungeons vs Classic's, a dungeon known by its name as W-192 reads it)
208. `BUILT` `W-208` Scarlet Monastery runs per wing: Graveyard, Library, Armory, Cathedral (Scarlet Monastery runs by wing, told apart by the bosses killed)
209. `BUILT` `W-209` Dire Maul runs per wing and Stratholme runs per side (Dire Maul and Stratholme runs by wing, the same way)
210. `SKIP` `W-210` Herod killed (covered by #28 and #41: kills by name and boss kills)
211. `SKIP` `W-211` Mograine and Whitemane killed (covered by #28 and #41)
212. `SKIP` `W-212` Arugal killed (Shadowfang Keep) (covered by #28 and #41)
213. `SKIP` `W-213` Mr. Smite and Cookie killed (Deadmines) (covered by #28 and #41)
214. `BUILT` `W-214` Mutanus the Devourer killed and Naralex awakened (Wailing Caverns) (Naralex awakened: "awake" in his or his disciple's last words in Wailing Caverns, not the talk of awakening him on the way; Mutanus kills are #28 and #41)
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
225. `BUILT` `W-225` Times you were the last party member alive in a wipe (everyone in the group dead and you last, from each member's death time (forgotten once they're up again), checked every second in instance fights)
226. `BUILT` `W-226` Times you died first in a wipe (the same, you first)
227. `BUILT` `W-227` Dungeon deaths by boss (your deaths during an encounter, by its name)
228. `BUILT` `W-228` Dungeon XP earned per run (Forever shifts XP toward quests, so this is interesting to compare) (XP gained during each run (newest 100))
229. `BUILT` `W-229` Rare-quality boss drops looted per dungeon (blue or better items looted within a minute of a boss dying, by dungeon)
230. `BUILT` `W-230` Dungeon quests completed per dungeon (Dungeon-tagged quests (or quests under a dungeon's quest log header, its name read as W-192 reads it), by that header)
231. `BUILT` `W-231` Times you ran a dungeon 5+ levels over (boosting or farming) (runs at 5+ levels over the dungeon's range, the dungeon known by its name as W-192 reads it)
232. `BUILT` `W-232` Times you were boosted through a dungeon by a much higher player [probe] (runs with a group member 10+ levels above you)
233. `BUILT` `W-233` Party compositions run with (class counts only) (class lists, sorted, per run)
234. `BUILT` `W-234` Tank, healer, or DPS role per run (by spec or self-assigned) (UnitGroupRolesAssigned, or your class and biggest talent tree, read as W-408 reads them)
235. `BUILT` `W-235` Times you hearthed out of a dungeon (Hearthstone within 20 seconds of a run ending)
236. `BUILT` `W-236` Instance lockouts hit ('too many instances') ('too many instances' messages; the red error and the chat line within a second are one)
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
245. `BUILT` `W-245` Deaths in raids, and deaths to Onyxia's Deep Breath and whelps (deaths in raids by raid; deaths to whelps; Deep Breath from the combat log where Forever allows it, when it hit you in the 5 seconds before)

## Loot rolls and group life
_START_LOOT_ROLL, CHAT_MSG_LOOT, CHAT_MSG_SYSTEM for /roll results, GROUP_ROSTER_UPDATE._

246. `BUILT` `W-246` Need rolls, Greed rolls, and Passes (RollOnLoot hook, by choice (JourneyTrackerSocial.lua); from addon 0.6.8 on, a choice the hook missed is counted when the roll's result comes (W-247). The website shows the Statistics pane's Need and Greed rolls (1044, 1043) where they're more)
247. `BUILT` `W-247` Rolls won and lost ('You won' and '<someone> won' loot messages for items you rolled on, or from addon 0.6.8 on, whichever comes first of those, LOOT_ITEM_ROLL_WON and the drop's loot history (C_LootHistory.GetSortedInfoForDrop on LOOT_HISTORY_UPDATE_DROP: your roll, its value and who won), which Forever's client keeps and may not print the messages for; each item's result once in 5 seconds)
248. `BUILT` `W-248` Highest roll ever and lowest roll ever (your Need and Greed roll messages, or from addon 0.6.8 on your roll in the result as W-247 reads it; the highest, and the lowest as W-248.lowest)
249. `BUILT` `W-249` Times you won a roll with under 10 (won with a roll under 10, the result as W-247 reads it)
250. `BUILT` `W-250` Times you lost a roll with over 95 (lost with a roll over 95, the result as W-247 reads it)
251. `BUILT` `W-251` /roll uses and average /roll result (your /roll results: how many and their total (the average is total over rolls))
252. `BUILT` `W-252` Blue items won on Need (blue items you won on Need, the result as W-247 reads it)
253. `BUILT` `W-253` Items you passed on that someone else won (items you passed on that someone else won, the result as W-247 reads it)
254. `BUILT` `W-254` Groups joined (going from no group to a group of your own, not a battleground's)
255. `BUILT` `W-255` Groups left and times removed from a group (leaving a group, and 'You have been removed from the group'; being removed isn't also counted as leaving)
256. `BUILT` `W-256` Groups you formed as leader (joined as the group's leader)
257. `BUILT` `W-257` Time spent in a group with guild members (count, no names) (5-second ticks in a group with a member of your guild (UnitIsInMyGuild))
258. `BUILT` `W-258` Times you were the highest level in your party (highest level in a new group, checked 3 seconds after joining)
259. `BUILT` `W-259` Times you were the lowest level in your party (lowest level, the same way)

## Bloopers (UI error messages)
_UI_ERROR_MESSAGE gives the error type/text. Pure counts, very cheap, and great Wrapped material._

260. `BUILT` `W-260` 'You are facing the wrong way' / 'Target needs to be in front of you' (UI_ERROR_MESSAGE matched to the game's own error strings (English fallback))
261. `BUILT` `W-261` 'Out of range' (as W-260)
262. `BUILT` `W-262` 'Not enough mana / rage / energy' (as W-260)
263. `BUILT` `W-263` 'Spell is not ready yet' (button mashing) (as W-260)
264. `BUILT` `W-264` 'Inventory is full' (as W-260)
265. `BUILT` `W-265` 'Can't do that while moving' (as W-260)
266. `BUILT` `W-266` 'Invalid target' (as W-260)
267. `BUILT` `W-267` 'You can't do that yet' / ability on cooldown (as W-260)
268. `BUILT` `W-268` 'Interrupted' cast fails (UNIT_SPELLCAST_INTERRUPTED for you, on a frame of its own (the class tracker listens to it for your target))
269. `BUILT` `W-269` 'Target not in line of sight' (as W-260)
270. `BUILT` `W-270` 'You are too far away' (as W-260)
271. `BUILT` `W-271` 'Can't attack while mounted' / 'You are mounted' (as W-260)
272. `BUILT` `W-272` 'You are dead' (tried to act while dead) (as W-260)
273. `BUILT` `W-273` Hearthstone pressed while on cooldown ('Item is not ready yet' within a second of using the Hearthstone (bags, action bar or by name))
274. `BUILT` `W-274` 'Not enough money' (tried to buy something you couldn't afford) (as W-260)
275. `BUILT` `W-275` 'Can't carry any more of those items' (unique items) (as W-260)
276. `BUILT` `W-276` Total errors and your single most common blooper (every error message; by the game's own string for it as W-276.byMessage (GetGameMessageInfo), so a name filled into one is never kept, and without that only the known bloopers by text; the most common being its top)

## Social and chat
_Counts only. Never store message contents or other players' names. Chat may be restricted in combat, so queue and process after combat._

277. `BUILT` `W-277` Messages you sent in /say (SendChatMessage hook (and C_ChatInfo's; one message seen by both counts once); counted, text never kept)
278. `BUILT` `W-278` Messages you sent in /yell (as W-277)
279. `BUILT` `W-279` Messages you sent in party chat (party, raid and instance chat, as W-277)
280. `BUILT` `W-280` Messages you sent in guild chat (guild and officer chat, as W-277)
281. `BUILT` `W-281` Whispers sent (as W-277; the recipient isn't kept)
282. `BUILT` `W-282` Whispers received (CHAT_MSG_WHISPER, counted)
283. `BUILT` `W-283` Messages you sent in General/Trade/LFG channels (channels named General, Trade or LookingForGroup, as W-277)
284. `BUILT` `W-284` Times you typed 'lol', 'lmao', or 'haha' (whole words in what you send (lol, lmao, haha, rofl))
285. `BUILT` `W-285` Times you typed 'gz' or 'grats' (gz, grats, gratz, congrats)
286. `BUILT` `W-286` Times you typed 'ty' or 'thanks' (ty, thanks, thx)
287. `BUILT` `W-287` Times you typed 'inc' or 'help' (inc, help)
288. `BUILT` `W-288` Times you typed 'LFG' or 'LFM' (lfg, lfm)
289. `BUILT` `W-289` Times you typed 'brb' or 'afk' (brb, afk)
290. `BUILT` `W-290` Guild 'gz' messages received within 60 seconds of your ding (guild messages with gz, grats, congrats or ding from someone else within 60 seconds of your level-up)
291. `BUILT` `W-291` Most 'gz' received on a single ding (the most of those on one level-up)
292. `BUILT` `W-292` Your most typed word (top word from your own messages, stored as a word count map, capped) (your own words of 3+ letters, minus very common ones and never from whispers, as a capped count map; no name: yours, your realm's words, or another player's seen this session (who talked, your group, guild roster and friends, held in memory only), and one tallied before it was known as a name is taken out)
293. `BUILT` `W-293` Messages sent per hour played (the sent counts (W-277..W-283) over /played, worked out on the website)
294. `BUILT` `W-294` Friends added (AddFriend hooks; one friend seen by both counts once)
295. `BUILT` `W-295` Players inspected (INSPECT_READY) (INSPECT_READY, once per player a session (by GUID, not kept))
296. `BUILT` `W-296` Trades completed ('Trade complete' messages)
297. `BUILT` `W-297` Gold given away in trades (money down while a trade window is open (or just closed))
298. `BUILT` `W-298` Gold received in trades (money up while a trade window is open)
299. `BUILT` `W-299` Items given away in trades (items that left your bags in a trade)
300. `BUILT` `W-300` Guilds joined and left (IsInGuild changing, after the login check)
301. `BUILT` `W-301` Time in a guild vs unguilded (5-second ticks in and out of a guild)

## Emotes
_CHAT_MSG_TEXT_EMOTE from the player, and emotes targeted at you (count only)._

302. `BUILT` `W-302` Total emotes used (C_ChatInfo.PerformEmote hook (Forever's client does emotes through it; addon 0.6.8 on) and DoEmote's, the same emote through both at once counted once, and /e messages)
303. `BUILT` `W-303` Your most used emote (the emote tokens W-302's hooks see, counted)
304. `BUILT` `W-304` /dance count (DANCE in W-303)
305. `BUILT` `W-305` /lol and /laugh count (LOL and LAUGH in W-303)
306. `BUILT` `W-306` /spit count (SPIT in W-303)
307. `BUILT` `W-307` /cheer and /applaud count (CHEER and APPLAUD in W-303)
308. `BUILT` `W-308` /hug count (HUG in W-303)
309. `BUILT` `W-309` /sit and /sleep count (SIT and SLEEP in W-303)
310. `BUILT` `W-310` /train count (the classic choo choo) (TRAIN in W-303)
311. `BUILT` `W-311` Emotes other players directed at you (CHAT_MSG_TEXT_EMOTE from someone else that says 'you'; the sender isn't kept)
312. `BUILT` `W-312` Most received emote (those by verb ('hugs'), the top one being the most received)

## Movement and world mechanics
_IsSwimming, IsFalling, IsFlying, IsIndoors, IsOutdoors, MIRROR_TIMER_START (BREATH, EXHAUSTION, FEIGNDEATH), sampled positions._

313. `BUILT` `W-313` Time spent swimming (IsSwimming on the 5-second tick (JourneyTrackerWorld.lua))
314. `BUILT` `W-314` Distance swum (distance between 5-second position samples while swimming, out of combat like #71)
315. `BUILT` `W-315` Time underwater (breath bar active) (the BREATH mirror timer counting down, until it stops or starts filling back up; after a /reload, which doesn't resend the timer, a running one is read back with GetMirrorTimerInfo, as the game's own bars do, its time under worked out from how far the bar has gone down)
316. `BUILT` `W-316` Times your breath bar ran out (the BREATH timer reaching its end before you got out)
317. `BUILT` `W-317` Times you entered fatigue (deep water) (the EXHAUSTION mirror timer starting)
318. `BUILT` `W-318` Time spent falling (seconds in the air of each fall, from the main tracker's fall timer (#101))
319. `BUILT` `W-319` Longest single fall (time airborne) (the most seconds in the air, with the fall's yards; #102 keeps the longest survived by distance)
320. `BUILT` `W-320` Times you fell more than 5 seconds (falls with more than 5 seconds in the air)
321. `BLOCKED` `W-321` Fall damage taken out of combat (health drop on landing) [probe] (your health is secret on Forever)
322. `BUILT` `W-322` Distance traveled on foot vs mounted (distance between position samples out of combat, mounted or on foot (swimming is W-314, ghosts W-334); together they add up to #71's ground distance)
323. `BUILT` `W-323` Times your hearthstone location changed (HEARTHSTONE_BOUND) (HEARTHSTONE_BOUND to a different place than before)
324. `BUILT` `W-324` Inn you bound to most (HEARTHSTONE_BOUND by GetBindLocation; the top one is the inn you bound to most)
325. `BUILT` `W-325` Time spent at your bound inn (5-second ticks resting where you bound your hearthstone, or in the place it's named after)
326. `BUILT` `W-326` Times you logged out in an inn vs in the field (resting or not at PLAYER_LOGOUT, counted at the next login so a /reload isn't)
327. `BUILT` `W-327` Rested XP gained while logged out (rested XP at login minus rested XP at logout)
328. `BUILT` `W-328` Times you hit max rested XP (rested XP reaching a level and a half, while playing or while logged out)
329. `BUILT` `W-329` Boat rides total (boat rides from the dock-to-dock detector in JourneyTrackerIconic.lua)
330. `BUILT` `W-330` Zeppelin rides total (zeppelin rides, same detector)
331. `BUILT` `W-331` Portal uses (mage portals, Rut'theran, etc.) (the 'Portal Effect' spell a clicked portal casts on you, by destination (unverified on Forever), and the Rut'theran portal (W-076); your own teleports and portals are MAG-04, MAG-05 and DRU-12)
332. `SKIP` `W-332` Summons accepted (covered by ALL-08 (accepted summons, ConfirmSummon hook))
333. `BUILT` `W-333` Times you used a meeting stone (Meeting Stone Summon casts)
334. `BUILT` `W-334` Corpse run distance total (distance between position samples while a ghost)
335. `BUILT` `W-335` Times you got lost: time in a subzone with no quest objective or kill for 5+ minutes (five minutes in one subzone moving 150+ yards with no kill, loot, money or quest progress, outside towns, instances and fights, not AFK; by subzone)

## Death memes
_Build on PLAYER_DEAD plus context cached before death. [probe] where cause needs combat info._

336. `SKIP` `W-336` Deaths by falling [probe] (covered by #102 (fatal falls are counted in db.falls.fatal and show as Falling in the #47 death log))
337. `BUILT` `W-337` Deaths by drowning (breath timer ran out before death) (the BREATH timer had run out with you still under (within 30 seconds of the death); a death counts as drowned or fatigue, not both: whichever timer ran out first)
338. `BUILT` `W-338` Deaths by fatigue (the EXHAUSTION timer had run out, the same way; not also counted as drowned when fatigue ran out first)
339. `BUILT` `W-339` Deaths to guards (killer named like a town guard (Guard, Grunt, Deathguard, Bluffwatcher, Kor'kron, Mountaineer, Sentinel, Watchman, Brave, Bruiser) and of the other faction, or a goblin town's Bruiser; with no faction seen, in hostile territory (the zone's type read as W-021 reads it))
340. `SKIP` `W-340` Deaths to elites (covered by W-136 (deaths to an elite, rare elite or boss))
341. `BUILT` `W-341` Deaths to murlocs [probe] ([probe] killer in the murloc family (FAMILIES, as W-022))
342. `BUILT` `W-342` Deaths to critters (yes, it happens) [probe] ([probe] killer's creature type is Critter)
343. `BUILT` `W-343` Deaths within 10 seconds of dinging (death within 10 seconds of PLAYER_LEVEL_UP)
344. `BUILT` `W-344` Deaths within 60 seconds of logging in (death within 60 seconds of logging in (not a /reload))
345. `BUILT` `W-345` Deaths while AFK (UnitIsAFK at the death)
346. `BUILT` `W-346` Deaths during escort quests (death within 20 minutes of taking a quest whose objectives say escort or protect (English), until it's turned in or dropped)
347. `BUILT` `W-347` Deaths with Resurrection Sickness still active (death before Resurrection Sickness ends: read from the debuff out of combat, or a minute per level over 10 (up to 10) after a spirit healer)
348. `BUILT` `W-348` Deaths right after a spirit healer rez (within 2 minutes) (death within 2 minutes of a spirit healer resurrection (#49))
349. `BUILT` `W-349` Deaths in a sanctuary or friendly town (the zone's PvP type (read as W-021 reads it) says sanctuary, or resting in a zone that isn't hostile)
350. `BLOCKED` `W-350` Deaths with a full health bar 5 seconds earlier (one-shots) [probe] (your health is secret on Forever)
351. `BUILT` `W-351` Deaths while a healthstone or potion was in your bags and off cooldown (a Healthstone or Healing Potion in your bags with no cooldown)
352. `BUILT` `W-352` Deaths with Hearthstone off cooldown (the Hearthstone in your bags with no cooldown)
353. `BUILT` `W-353` Deaths while mounted (dismounted and killed) (mounted when the fight started (PLAYER_REGEN_DISABLED) and killed in it)
354. `BUILT` `W-354` Times you died twice in one minute (a death within 60 seconds of the one before)
355. `BUILT` `W-355` Longest time alive without dying (/played) (/played now kept on each death record; the longest gap between two, with level and zone)
356. `SKIP` `W-356` Death count at each 10 levels (covered by #45 (deaths per level); the website adds them up by 10 levels)
357. `BUILT` `W-357` Death clock: average /played between deaths (/played on each death record (W-355); the website averages the gaps)
358. `BUILT` `W-358` Ghost time: time spent as a ghost total (from release (PLAYER_ALIVE as a ghost) to PLAYER_UNGHOST)

## Economy, vendors, AH, mail
_PLAYER_MONEY deltas with context (merchant open, mail open, AH open, trade, quest)._

359. `BUILT` `W-359` Gray (junk) items sold and gold from junk (gray items sold to a vendor (a bag diff while a merchant is open), and the gold from their sell prices as W-359.gold (JourneyTrackerEconomy.lua))
360. `BUILT` `W-360` Most valuable gray item sold (the highest sell price among them, with the item)
361. `BUILT` `W-361` Items bought from vendors (items gained while a merchant is open; by item as W-361.byItem)
362. `BUILT` `W-362` Most expensive vendor purchase (the biggest merchant payment, paired with the item bought within 3 seconds)
363. `BUILT` `W-363` Items destroyed (deleted) (items gone right after DeleteCursorItem; by item as W-363.byItem)
364. `BUILT` `W-364` Gold spent on bags (vendor purchases of bags (item class Container), paired the same way; bags from the AH aren't counted)
365. `BUILT` `W-365` First bag of each size: 6, 8, 10, 12, 14, 16 slot (each new size of bag in your bag slots, with the bag; sizes you had when tracking began are marked before)
366. `BUILT` `W-366` Bank slots bought and gold spent (money spent within 3 seconds of C_Bank.PurchaseBankTab (Forever buys bank tabs) or PurchaseSlot (older clients); the gold as W-366.gold)
367. `BUILT` `W-367` Auctions posted (AUCTION_HOUSE_AUCTION_CREATED on Forever, whose own UI prints 'Auction created.' rather than the game sending it; the 'Auction created.' message on older clients, left alone once the event has been seen so nothing counts twice)
368. `BUILT` `W-368` Auctions sold, expired, and cancelled (the game's sold, expired and cancelled messages and Forever's auction house notifications, counted once each by the main tracker with #83 and passed on through ns.OnAuctionNotice)
369. `BUILT` `W-369` Gold lost to auction deposits and cuts (deposits (AH spending paired with a posting, W-367), and from sale invoices the deposits refunded and the house's cut; lost = deposits - refunded + cuts)
370. `BUILT` `W-370` Most expensive item you sold on the AH (the biggest bid on a seller invoice, with the item; the buyer isn't read)
371. `BUILT` `W-371` Most expensive item you bought on the AH (the biggest buyer invoice, or AH spending paired with 'You won an auction for', or on Forever with a commodity's AUCTION_HOUSE_SHOW_COMMODITY_WON_NOTIFICATION (its UI prints that line itself))
372. `BUILT` `W-372` Mail sent and received (mail sent (MAIL_SEND_SUCCESS), and mail cleared from your inbox (taken, deleted or returned), since new mail can't be counted as it arrives)
373. `BUILT` `W-373` COD mail sent and received (COD mail sent, and COD paid when taking an item)
374. `BUILT` `W-374` Gold sent and received by mail (gold attached to mail you sent, and gold taken from mail that isn't from the auction house)
375. `BUILT` `W-375` Gold spent on mounts (price of a mount bought from a vendor (JourneyTrackerIconic.lua))
376. `BUILT` `W-376` Gold spent on talent respecs (the trainer's price (CONFIRM_TALENT_WIPE), counted when the respec is confirmed)
377. `BUILT` `W-377` Gold earned from quests per level (QUEST_TURNED_IN money, by level; #57 has the total)
378. `BUILT` `W-378` Times you went broke (under 1 silver) (your money dropping below 1 silver)
379. `BUILT` `W-379` Richest moment relative to level (gold per level) (the most copper per level you've held, with the money and level)
380. `BUILT` `W-380` Lockboxes looted (looted items named Lockbox or Junkbox, by name)
381. `BUILT` `W-381` Treasure chests looted in the world (loot from an object (not a herb, a vein or fishing) holding money or anything but quest items; each object (its GUID) once a session, so opening it again with loot left in it isn't another chest)
382. `BUILT` `W-382` Gold looted from chests (money looted from those)

## Gear and character stats
_Snapshot out of combat at each ding: UnitStat, UnitArmor, UnitAttackPower, GetCritChance, UnitResistance, durability, item links._

383. `BUILT` `W-383` Strength, Agility, Stamina, Intellect, Spirit at each ding (UnitStat, read out of combat 3 seconds after each ding into that ding's snapshot (levels.snapshots[level].sheet); from addon 0.6.8 on, the journey saved at a milestone (#105) waits for it)
384. `BUILT` `W-384` Armor at each ding (UnitArmor, in the ding's sheet)
385. `BUILT` `W-385` Max health and max mana at each ding (UnitHealthMax and UnitPowerMax (mana), in the ding's sheet)
386. `BUILT` `W-386` Attack power and spell power at each ding (UnitAttackPower (and ranged), never below 0, as the character sheet shows it, the best school's GetSpellBonusDamage and GetSpellBonusHealing, in the ding's sheet)
387. `BUILT` `W-387` Crit chance at each ding (GetCritChance, the best GetSpellCritChance and GetRangedCritChance, in the ding's sheet)
388. `BUILT` `W-388` Resistances at each ding (UnitResistance for each school above 0, in the ding's sheet)
389. `BUILT` `W-389` Main hand weapon DPS at each ding (the main hand weapon's own DPS (its item stats), in the ding's sheet)
390. `BUILT` `W-390` Average item level at each ding (average item level of what you wear (not the shirt or tabard), in the ding's sheet)
391. `BUILT` `W-391` Gear rarity breakdown at each ding (grays, whites, greens, blues, purples worn) (items worn by rarity, in the ding's sheet)
392. `BUILT` `W-392` 'of the Monkey', 'of the Bear', 'of the Eagle', 'of the Whale' and other suffix items looted (looted items with a random suffix, by suffix ('of the Monkey'))
393. `BUILT` `W-393` Your most common gear suffix (the top of W-392)
394. `BUILT` `W-394` Items equipped total (PLAYER_EQUIPMENT_CHANGED putting a different item in a slot, after the first look at your gear each session; another copy of the same item counts too, told apart by its item GUID (C_Item.GetItemGUID) where the client has it)
395. `BUILT` `W-395` Gear swaps per level (the same, by level)
396. `SKIP` `W-396` Longest worn item (by /played) and its slot (covered by #104 in journey-tracking-spec.md, which also tracks levels gained while worn)
397. `BUILT` `W-397` First two-handed weapon equipped (the first two-hander in your main hand, with level; marked before if you had one when tracking began)
398. `BUILT` `W-398` Times an item broke (durability 0) (an item's durability reaching 0; not an item put on already broken)
399. `BUILT` `W-399` Times your gear went yellow or red (low durability) (your gear's worst state turning yellow or red (GetInventoryAlertStatus for each of the 11 parts of the game's durability figure, head to ranged, which aren't inventory slots; or 20% left if the game can't say))
400. `BUILT` `W-400` Biggest repair bill (the biggest single repair payment (Repair All or one item))
401. `BUILT` `W-401` Enchants applied to your gear (an equipped item's enchant changing to a new one, on the same item (its item GUID, where the client has it), so swapping in another copy with a different enchant isn't one; by slot as W-401.bySlot (armor kits included))
402. `BUILT` `W-402` Armor kits, sharpening stones, and weightstones used (items named Armor Kit, Sharpening Stone or Weightstone used, by name)
403. `BUILT` `W-403` BoE items sold or vendored instead of equipped (bind-on-equip gear sold to a vendor or put up on the AH without ever being worn (#104's list))
404. `BUILT` `W-404` Quest reward choices: which slot you picked most (the GetQuestReward choice when there's more than one, by its slot)
405. `BUILT` `W-405` Quest reward items vendored without ever equipping (gear you got as a quest reward, sold without ever being worn)
406. `BUILT` `W-406` Talent points spent, in order, with level spent (talent ranks compared on each change: tree, talent, rank and level, in order (newest 150); on Forever from its trait tree (C_ClassTalents, C_Traits), the classic trees being its groups, and switching to your other spec isn't new points)
407. `BUILT` `W-407` Talent respecs (ConfirmTalentWipe)
408. `BUILT` `W-408` Talent tree split at 60 (points in each tree, kept current while you're 60; on Forever each group's spent points from C_Traits.GetGroupCurrencyInfo)
409. `BUILT` `W-409` Spells learned at trainers vs from items/books (each spell or rank learned: at a trainer, after using an item, after a quest, or other)
410. `SKIP` `W-410` Most cast spell overall (covered by the class tracker's cast counter (db.class[CLASS].casts counts every cast by name; the top one is the most cast))

## Professions deep dive
_Item diffs, CHAT_MSG_LOOT, CHAT_MSG_SKILL, TRADE_SKILL events, UNIT_SPELLCAST_SUCCEEDED for gathering._

411. `SKIP` `W-411` Herbs picked by type (Peacebloom, Silverleaf, Earthroot, Mageroyal, Briarthorn, Bruiseweed, Kingsblood, Fadeleaf, Goldthorn, Firebloom, Sungrass, and more) (covered by #103 (db.gathering.herb.items: what each herb node gave, by item))
412. `SKIP` `W-412` Black Lotus picked (covered by #103 (Black Lotus is one of the herb items))
413. `SKIP` `W-413` Ore mined by type (Copper, Tin, Silver, Iron, Gold, Mithril, Truesilver, Thorium) (covered by #103 (db.gathering.mining.items, by ore))
414. `BUILT` `W-414` Truesilver and Silver veins found (mining nodes whose name (the gathering cast's target) says Truesilver or Silver (JourneyTrackerProfessions.lua))
415. `BUILT` `W-415` Gems found while mining (uncommon or better items from mining nodes, by name)
416. `SKIP` `W-416` Skins gathered by type (Light, Medium, Heavy, Thick, Rugged leather) (covered by #103 (db.gathering.skinning.items, by leather))
417. `BUILT` `W-417` Cloth looted by type (Linen, Wool, Silk, Mageweave, Runecloth) (Linen, Wool, Silk, Mageweave, Runecloth and Felcloth looted, by type)
418. `BUILT` `W-418` Total cloth looted (the total of W-417)
419. `BUILT` `W-419` Gathering nodes by zone (each new node the main tracker counts (#103), by zone)
420. `BUILT` `W-420` Nodes you lost to another player (node vanished mid-gather) [probe] ([probe] a gathering cast interrupted while you stood still out of combat; matched by its cast GUID, so its own FAILED coming first, or another spell failing, doesn't lose it)
421. `BUILT` `W-421` Fishing casts and catch rate (Fishing casts and fishing loot windows (catch rate = catches / casts))
422. `BUILT` `W-422` Fish caught by type (fishing loot, by item)
423. `BUILT` `W-423` Junk vs fish from fishing (fishing loot that's gray (junk) or not (fish))
424. `BUILT` `W-424` Fishing pools fished (fishing loot from an object that isn't the bobber (unverified on Forever))
425. `BUILT` `W-425` Longest fishing session (the longest run of Fishing casts no more than 2 minutes apart)
426. `BUILT` `W-426` Items cooked and most cooked recipe (items made with the Cooking window open, by item; the top one is the most cooked. On Forever the window is known by C_TradeSkillUI.GetBaseProfessionInfo, Cooking by its profession ID (185), from addon 0.6.8 on)
427. `BUILT` `W-427` Recipes learned per profession (recipes each profession's window lists (the most seen), or from addon 0.6.8 on the Statistics pane's recipes known for each profession (Forever's window can't be counted the Classic way), whichever is more)
428. `BUILT` `W-428` Rare recipes learned from drops (recipe items you looted and then learned, by name)
429. `SKIP` `W-429` Profession skill at each ding (covered by #92 (skill progression; the export has the highest rank at each level))
430. `BUILT` `W-430` Items disenchanted and materials gained (Disenchant casts, and what you looted right after as W-430.mats)
431. `BUILT` `W-431` Enchants cast on other players' gear (Enchant casts while a trade window is open, by enchant)
432. `BUILT` `W-432` Engineering explosives thrown (dynamite, bombs, grenades, sapper charges, land mines and Explosive Sheep used, by item)
433. `BUILT` `W-433` Target Dummies deployed (target dummies used, by item)
434. `BUILT` `W-434` Goblin Jumper Cables used: successes vs failures (Goblin Jumper Cables (Defibrillate) casts that went off and ones that failed (once per cast, though FAILED and INTERRUPTED can both come); whether the player came back can't be read)
435. `BUILT` `W-435` Gnomish gadgets used (Mind Control Cap, Death Ray, Net-o-Matic, etc.) (an engineering gadget used (from your bags, gear, action bar or by name) and its cast going off, by item)
436. `BUILT` `W-436` Potions and elixirs crafted (potions, elixirs and flasks you made, by item)
437. `BUILT` `W-437` Gold earned from selling gathered materials (herbs, ore, leather and cloth sold to vendors (their sell price) and on the auction house (the money from the sale))
438. `BUILT` `W-438` Professions dropped (unlearned) (a profession that's no longer in GetProfessions, with the level; its list can have gaps on Forever (7 values, some nil), so it's read with pairs)

## Reputation and factions
_CHAT_MSG_COMBAT_FACTION_CHANGE and the reputation API._

439. `BUILT` `W-439` Reputation gained by faction (reputation gain messages, by faction)
440. `BUILT` `W-440` Level reached Friendly, Honored, Revered, and Exalted with each faction ('You are now <standing> with <faction>' messages: the level you reached each standing, by faction)
441. `BUILT` `W-441` Reputation lost by faction (reputation loss messages, by faction)
442. `BUILT` `W-442` Times you turned on Booty Bay (Bloodsail Buccaneers rep gained) (Bloodsail Buccaneers reputation gains)
443. `BUILT` `W-443` Timbermaw Hold reputation progression (Timbermaw Hold reputation at each ding, as `{ standing, progress }`: the standing's name (Hated..Exalted, from the game's reaction) and the points into it (current minus where it starts; the older API's barValue minus barMin), so nothing below Neutral is negative (Timbermaw starts Hostile, and the export drops negative numbers); factions at exactly 0 are left out as before; raw values saved by earlier versions are converted once at load on the standard thresholds)
444. `BUILT` `W-444` Cenarion Circle reputation progression (Cenarion Circle reputation at each ding, as standing and progress like W-443)
445. `BUILT` `W-445` Argent Dawn reputation progression (Argent Dawn reputation at each ding, as standing and progress like W-443)
446. `BUILT` `W-446` Thorium Brotherhood reputation progression (Thorium Brotherhood reputation at each ding, as standing and progress like W-443)
447. `BUILT` `W-447` Ravenholdt reputation (rogues) (Ravenholdt reputation at each ding, as standing and progress like W-443)
448. `BUILT` `W-448` Steamwheedle Cartel reputation progression (Booty Bay, Everlook, Gadgetzan and Ratchet reputation at each ding, as standing and progress like W-443 (Booty Bay drops below Neutral after Bloodsail quests))
449. `BUILT` `W-449` Home city reputation at 60 (your race's capital's reputation at the 60 ding, as its name with standing and progress like W-443 (no more raw `value`))
450. `BUILT` `W-450` Other faction cities reputation at 60 (your faction's other capitals' reputation at the 60 ding, each as standing and progress like W-443)
451. `BUILT` `W-451` Faction you gained the most reputation with (the top of W-439)
452. `BUILT` `W-452` Reputation turn-ins (cloth donations, etc.) (quests that gave reputation and were turned in before or have a turn-in name (Donation, Insignia, Feathers...), by quest as W-452.byQuest)
453. `BUILT` `W-453` Cloth donated to city quartermasters (cloth handed over with a donation quest, by type)
454. `BUILT` `W-454` Desolace centaur faction chosen (the Desolace centaur clan you've gained more reputation with)

## Holidays and world events
_Forever's holiday calendar isn't confirmed yet. Build these behind a flag and mark BLOCKED if an event never shows up._

455. `BUILT` `W-455` Darkmoon Faire visits (the Darkmoon Faire subzone or one of its people targeted, once per 10 minutes (behind the holiday flag; unverified on Forever))
456. `BUILT` `W-456` Darkmoon Faire tickets turned in (Darkmoon Faire Prize Tickets leaving your bags (holiday flag))
457. `BUILT` `W-457` Darkmoon Faire fortune received (Sayge's fortunes you got, by name (holiday flag))
458. `BUILT` `W-458` Hallow's End candy buckets looted and tricks/treats (Hallow's End treats you got, by name (holiday flag))
459. `BUILT` `W-459` Winter Veil presents opened (Winter Veil presents opened, by name (holiday flag))
460. `BUILT` `W-460` Stranglethorn Fishing Extravaganza participation (Speckled Tastyfish caught and the Master Angler quest (holiday flag))
461. `BUILT` `W-461` Holiday quests completed total (quests with a holiday's name, or turned in at the Darkmoon Faire (in its subzone, or within a minute of seeing it or one of its people), by title (holiday flag))

## Milestones and firsts
_Each records level, /played, zone, and real timestamp._

462. `BUILT` `W-462` First quest completed (the first quest turned in, with its title; marked late if the tracker may have missed the real first (JourneyTrackerHabits.lua))
463. `SKIP` `W-463` First death (covered by #44-#46 (the first record in the death log has its level, zone and date))
464. `BUILT` `W-464` First group joined (the first time you're in a group, with its size)
465. `SKIP` `W-465` First dungeon entered (covered by #73-#74 (the first dungeon run, with its start time and level))
466. `BUILT` `W-466` First green item looted (the first uncommon item looted)
467. `BUILT` `W-467` First time reaching 1 gold, 10 gold, 100 gold (the first time your money reached 1, 10 and 100 gold; amounts reached before tracking (#85's peak) are marked before)
468. `BUILT` `W-468` First enemy player killed (first enemy player kill, with their class and level (JourneyTrackerPvP.lua))
469. `BUILT` `W-469` First time killed by an enemy player (first death to a player, with their class and level)
470. `SKIP` `W-470` First trip to each capital city (covered by #63 (each zone's first visit, with time and level; capitals are zones))
471. `BUILT` `W-471` First flight path taken (the first flight path taken (TakeTaxiNode), with where to)
472. `BUILT` `W-472` First boat or zeppelin ride (first boat or zeppelin ride, with the route)
473. `SKIP` `W-473` First mount summoned (covered by #84 (level and /played the first time you're mounted))
474. `BUILT` `W-474` First profession maxed for its bracket (75, 150, 225, 300) (the first profession to reach 75, 150, 225 and 300; brackets reached before tracking are marked before)
475. `BUILT` `W-475` First time hitting Exalted with any faction (the first 'You are now Exalted with' message (JourneyTrackerProfessions.lua))
476. `BUILT` `W-476` First talent point (the first talent point (JourneyTrackerEconomy.lua); points already spent when tracking began are marked before)
477. `SKIP` `W-477` First class quest completed (covered by ALL-12 (class quests with the level each was done))
478. `SKIP` `W-478` First rare killed (covered by W-133 (first rare killed: name, its level, your level, zone))
479. `BUILT` `W-479` First time in a battleground (first battleground entered)
480. `BUILT` `W-480` First duel won (first duel won, with the opponent's class)
481. `BUILT` `W-481` First time reaching rested max (the first time your rested XP reached its cap (W-328, JourneyTrackerWorld.lua))
482. `SKIP` `W-482` Last death before 60 (covered by #44-#46 (the last death below 60 in the death log))
483. `BUILT` `W-483` The ding to 60: zone, subzone, coords, time of day, cause, who was in your group (count/classes only) (at the 60 ding: subzone, coordinates, hour, cause, and the group's size and classes (no names; your own class left out, which in a raid is one of the raid units); the ding snapshot has the rest)

## Sessions and habits
_From login/logout timestamps and per-session counters._

484. `SKIP` `W-484` Day of week you played most (covered by #6 (each session's start and end); the website works out the day of the week)
485. `SKIP` `W-485` Longest gap between sessions (covered by #6 (session start and end times))
486. `SKIP` `W-486` Longest streak of consecutive days played (covered by #17 (the days played))
487. `BUILT` `W-487` Late-night dings (between midnight and 5am local time) (dings before 5am local time, with level and hour)
488. `SKIP` `W-488` Weekend vs weekday playtime (covered by #6 (session start and end times))
489. `BUILT` `W-489` Session with the most deaths (deaths in each session, kept on the session record; the most, with when)
490. `BUILT` `W-490` Session with the most kills (kills in each session, the same way)
491. `BUILT` `W-491` Average time from login to first kill (seconds from a session's start to its first kill, on the session record and summed (average = seconds / sessions))
492. `BUILT` `W-492` Reloads (/reload) count (PLAYER_ENTERING_WORLD after a /reload)
493. `BUILT` `W-493` Screenshots taken (SCREENSHOT_SUCCEEDED) (SCREENSHOT_SUCCEEDED)
494. `BUILT` `W-494` Auto-screenshot at every ding (optional setting, Screenshot()) (a screenshot a second after every ding, on unless turned off in the window's Options or with /journey screenshots (flags.screenshots = false))
495. `SKIP` `W-495` Times you logged in, played under 5 minutes, and logged out (covered by #6 (each session's start and end))
496. `BUILT` `W-496` Most productive hour of /played (most XP in one hour) (the most XP gained within any hour of play (a sliding hour, within a session))
497. `SKIP` `W-497` Percentage of time spent in combat vs out (covered by #37 (time in combat) and #1 (/played))
498. `BUILT` `W-498` Percentage of time spent questing vs grinding (quest objective active vs not) (5-second ticks outside towns, not AFK or flying: questing within 2 minutes of quest progress, grinding within 2 minutes of a kill without it)
499. `SKIP` `W-499` Percentage of time spent in town (covered by #11 (time resting in inns and cities) and #1)
500. `SKIP` `W-500` Playtime per real-world week (covered by #6 (session start and end times))

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
- 2026-10-05: Sections 11-14 (loot rolls and group life, bloopers, social and chat, emotes) done in the new JourneyTrackerSocial.lua, all `BUILT`, plus W-013..W-015 (Legacy) as a [probe]: the game's system messages that mention Legacy are kept with level and date, and the Legacy-named functions the client has are listed, until the Legacy API is known. Chat is counted, never kept: what you send is read once as it goes out (SendChatMessage hook) to count channels and a few words, and only your own words are tallied (capped); whispers and emotes aimed at you are counted without the sender. Bloopers match the client's own error strings. Your interrupted casts are counted on a frame of their own, because the class tracker listens to the same event for your target and the shared frame keeps one unit filter per event. Checked outside the game: rolls won and passed, /roll, a group, errors, chat and typed words, guild gz after a ding, emotes, a trade, a Legacy message, joining a guild. No stray globals.
- 2026-10-05: Sections 15-16 (movement and world mechanics, death memes) done in the new JourneyTrackerWorld.lua. `BUILT`: time and yards swimming, time underwater, breath running out, fatigue, falls by seconds in the air (from the main tracker's fall timer), yards on foot and mounted (with swimming they add up to #71's ground distance), hearthstone moves and binds by inn, time at your bound inn, where you logged out and rested XP gained while away (counted at the next login, so a /reload isn't a logout), rested XP reaching its cap, portals clicked and the Rut'theran portal, meeting stones, corpse run yards, getting lost; deaths by drowning, fatigue, town guards, murlocs and critters ([probe]), and deaths within 10 seconds of a ding, within a minute of logging in, while AFK, during an escort, with Resurrection Sickness, soon after a spirit healer, in a friendly town, with a healthstone, potion or Hearthstone ready, mounted when the fight began, twice in a minute, plus the longest stretch alive and time as a ghost. Each death record now keeps /played (for the longest stretch and the website's death clock), and the main tracker remembers a mob's faction for the session, to tell town guards from mobs with the same name. `SKIP`: summons (ALL-08), deaths by falling (#102), deaths to elites (W-136), deaths by 10 levels (#45). `BLOCKED`: fall damage and one-shots (health is secret on Forever). Checked outside the game: a corpse run, a spirit healer and a death with Resurrection Sickness, drowning, fatigue, a guard and a grunt that isn't one, a murloc, a rat, a ding, a mounted fight, an escort, a 6-second fall, swimming, walking, riding and a teleport, getting lost, binding at an inn, rested XP across a logout, a portal and a meeting stone. No stray globals.
- 2026-10-05: Sections 17-18 (economy, vendors, AH and mail; gear and character stats) done in the new JourneyTrackerEconomy.lua, all `BUILT` except W-410 `SKIP` (the class tracker already counts every cast). Vendors: junk sold and its gold, the most valuable junk, items bought, the biggest purchase and gold on bags (a merchant payment paired with the item bought), items destroyed, the first bag of each size, bank slots. The auction house: auctions posted, sold, expired and cancelled, deposits paid and refunded, the house's cut, the best sale and the biggest buy (from invoices, never reading the other player). Mail: sent, cleared from your inbox, COD sent and paid, gold sent and received (auction mail left out); no sender, recipient or text is kept. Gold moments: respecs, quest gold by level, going broke, richest for your level, lockboxes, treasure chests and their gold. Gear: suffixes looted, items equipped and swaps per level, the first two-hander, items broken, gear turning yellow or red, the biggest repair bill, enchants, kits and stones, BoE gear and quest rewards sold without being worn, the quest reward slot you picked. Talents: points in order with level, respecs, the split at 60, and where spells were learned. Your character sheet (stats, armor, health and mana, attack and spell power, crit, resistances, main hand DPS, average item level, gear by rarity) is added to each ding's snapshot, read out of combat a few seconds after the ding. The export leaves out the wrapped trackers' own bookkeeping. Checked outside the game: junk, a bag and a repair at a vendor, a cloak and quest boots sold unworn, a destroyed item, a stone, an auction posted and one bought, sale, expiry and cancel messages, mail in and out, a bank slot, a respec, going broke, a suffix item, a lockbox, a chest (not a herb or a quest object), a two-hander, an enchant, durability, talents, trainer spells, and two dings (one in a fight). No stray globals.
- 2026-10-05: Sections 19-21 (professions deep dive, reputation and factions, holidays and world events) done in the new JourneyTrackerProfessions.lua. `SKIP`: herbs, Black Lotus, ore and skins by type (#103 has what every node gave) and skill at each ding (#92). Everything else `BUILT`. Gathering: Truesilver and Silver veins (from the node your gathering cast was aimed at), gems from mining, cloth by type and in all, nodes by zone (the main tracker now tells the other files about each new node), nodes lost to someone else ([probe]). Fishing: casts and catches, catches by type, fish vs junk, pools, the longest session. Crafting: food cooked, recipes known per profession, dropped recipes learned, potions and elixirs made, disenchanting and what it gave, enchants through the trade window, gathered goods sold. Engineering: explosives, target dummies, jumper cables, gadgets. Professions dropped. Reputation: gained and lost by faction, the level each standing was reached, Bloodsail gains, the progression factions at each ding, the capitals at 60, reputation turn-ins, cloth donations, the Desolace centaur side. Holidays, behind a "holiday" flag until Forever's calendar is known: Darkmoon Faire visits, tickets, fortunes, Hallow's End treats, Winter Veil presents, the Fishing Extravaganza, holiday quests. Checked outside the game: mining with a gem, cloth, fishing a pool and the bobber, disenchanting, an enchant for someone else, cooking, alchemy, a dropped recipe, dynamite, a dummy, cables, the Mind Control Cap, a lost herb, ore and herbs sold, a dropped profession, reputation messages, a cloth donation, dings, the Faire, a present, a treat bag, the Master Angler. No stray globals.
- 2026-10-05: Sections 22-23 (milestones and firsts, sessions and habits) done in the new JourneyTrackerHabits.lua, with three firsts wired into the files that see them (first talent point, first Exalted, first rested max). That finishes every wrapped item: none is left `TODO`. `BUILT`: the first quest, group, green item, 1/10/100 gold, flight, profession at each bracket's top, Exalted, talent point and full rested XP, and the ding to 60 (where, when, the group's classes). Firsts are marked late when the tracker may have missed the real one (it didn't see the journey from level 1, or the existing counts show it already happened), and ones already reached when this began are marked before. Sessions: each session record now keeps its kills, deaths and the seconds to its first kill (most kills and deaths in a session, average time to the first kill); late-night dings, reloads, screenshots, the most XP in an hour of play, questing vs grinding time, and an optional screenshot at every ding (`/journey screenshots`, off by default). `SKIP`, because existing data covers them: the first death, dungeon, capital visits, mount, class quest and rare, the last death before 60, and the session habits the website can work out from the session list, days played, combat time and rest time. Fixed while testing: a skill message's rank was dropped (a Lua `and` keeps one value). Checked outside the game: each first, a first marked late, a session's kills and deaths, the hour of XP, questing and grinding, a late-night ding, the ding to 60 with its screenshot, a reload. No stray globals.
- 2026-10-05: The website shows the wrapped stats (site/model.js `littleOf`): creature families, how you died, getting around, gold, gear, professions, groups and chat in their chapters, and new PvP and dungeons, little things and firsts and habits chapters; 48 new rankings, and the iconic rankings now read exports. Addon 0.6.0. Fixed before release: W-468, W-469 and W-133 kept a skull-level (-1) player or rare as a negative level, and W-145 could record a negative gap when a lower-level player killed you; the website turns away exports with negative numbers, so a skull is now kept as `skull = true`, the gap only when they're higher, and the export drops any negative wrapped number as a safety net.
- 2026-10-05: Fixes from a bug review (addon 0.6.2; each item's note says what changed). Privacy: W-292 leaves out whispers and any word that's a name (yours, your realm's, players seen this session, kept in memory only); W-013..W-015 never keep a message with a player in it; W-276 keeps the game's own error wording. Places: flights no longer make boat rides or visits; hearths, portals, Astral Recall and summons can't be rides; visits remember where you stood across a /reload (visitsSeen); elevator rides aren't flights, hearths or jumps. Kills: the no-XP watcher skips corpses and mobs someone else tagged; enemy guards need the enemy faction and count at 60 (ns.OnNoXPKill); enemy player kills dedupe by GUID or name without realm; families raised to what the kill log shows (name-based ones). PvP and dungeons survive a /reload (bgMatch, dungeonRun); wipe order uses this fight's deaths; W-146 needs a known killer outside battlegrounds; Blackrock Spire's halves told apart by bosses. Reputation (W-443..W-450) kept as a standing and points, never negative (saved raw values converted); attack power never below 0; Forever's auction house (AUCTION_HOUSE_AUCTION_CREATED) and bank tabs (C_Bank.PurchaseBankTab) counted; W-399 reads the durability figure's own 11 parts; breath and fatigue read back after a /reload; one death is drowning or fatigue, not both. Not changed: W-020 (VERIFIED) can read "PvP" on a Normal realm after an auto-flag; W-406/W-408/W-476 (talents) and W-426/W-427 (recipes) use Classic functions Forever's modern talent and professions UI doesn't, to confirm with /journey status in game. Checked outside the game: 80 + 37 new checks, every existing test passing.
- 2026-10-05: W-020 changed on request (it was `VERIFIED`; now `BUILT` until checked in game again; addon 0.6.3). An auto-flag (W-021) is now a PvP flag that comes on without /pvp in a contested or enemy zone within 10 seconds of arriving there, out of a fight and with no fight starting in the next 2 seconds, so on a Normal realm a flag from attacking an enemy or a guard, or from healing someone flagged, no longer makes the ruleset PvP; the zone's type comes from C_PvP.GetZonePVPInfo first. W-368 now counts sold, expired and cancelled auctions through the main tracker (#83), once each whether they came as a chat line or as Forever's notifications. A ruleset already saved as PvP from an earlier false auto-flag stays so (nothing tells it apart).
- 2026-10-05: Forever's API, from /journey status in game (addon 0.6.4). The client has none of GetNumTalentTabs and the other Classic talent functions, GetZonePVPInfo, UnitPVPRank, IsAutoRepeatSpell, GetContainerItemInfo, UseContainerItem or UseItemByName, so the talent stats (W-406, W-408, W-476, and W-234's role) read Forever's trait tree as its own talent window does (C_ClassTalents.GetActiveConfigID, C_Traits groups for the three trees, node ranks, TRAIT_CONFIG_UPDATED); the zone's PvP type (W-021, W-129, W-158, W-339, W-349) comes from C_PvP; W-183 reads the PvP rank from Forever's rank points faction (C_MajorFactions, 2800) with its title; bag items come from C_Container, and item use is heard through C_Container.UseContainerItem and C_Item.UseItemByName, one hook each, the C_ one where the client has it. Checked outside the game on a Forever-like setup (those functions removed, the modern ones standing in): 12 new checks, and every existing test. W-020 (and #101, #102, #83 in the journey spec) confirmed in game again after the earlier change.
- 2026-10-06: Fixes from an audit of every saved export (addon 0.6.8; each item's note says what changed). Forever's client gives most zones no PvP type, so where it gives none the zone's type is Classic's own, by the zone's map ID (W-021, W-129, W-158, W-339, W-349; W-020 is `VERIFIED` and not changed, but it counts W-021's auto-flags toward a PvP realm, and those can now happen on Forever). Emotes are counted through C_ChatInfo.PerformEmote, which Forever's client uses (W-302..W-310). Cooking is known on Forever's profession window, and the recipes each profession knows come from the Statistics pane too (W-426, W-427). Loot roll results also come from LOOT_ITEM_ROLL_WON and the loot history (W-246..W-250, W-252, W-253). Forever's dungeons are known by the names its client gives them, and three more have their final boss listed (W-192, W-193, W-195, W-197, W-207, W-230, W-231). The journey saved at a milestone waits for the ding's character sheet (W-383..W-391). All stay `BUILT` until checked in game. Checked outside the game (fengari, real saved data): 46 new checks and every existing test.
- 2026-10-06: Forever's new zones get a type (addon 0.6.9), from the client's own zone data (AreaTable.db2, read from the install): Mount Hyjal, Riverglades and Shen'dralas have no faction, like the old world's contested zones, so they're contested; Zephras Isle (both its maps) has the sanctuary flag, so it's a sanctuary. The same data confirms every old-world zone's side in the 0.6.8 table. W-021, W-129, W-158, W-339 and W-349 read them; all stay `BUILT`. Checked outside the game (fengari): the new zones' types and W-129's time in a sanctuary.
- 2026-10-07: Zone names (addon 0.6.10; see the Implementation notes in journey-tracking-spec.md): the stats by zone (W-128, W-154, W-419) and the inn you're bound at (W-325's place) get the zone instead of a building's name, and their entries under one move to its zone. W-072 still sees the Deeprun Tram, which has no map. All stay `BUILT`.
