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

22. `TODO` `W-022` Murlocs slain
23. `TODO` `W-023` Most murlocs in a single combat (the classic murloc train)
24. `TODO` `W-024` Kobolds slain
25. `TODO` `W-025` Gnolls slain
26. `TODO` `W-026` Defias Brotherhood members slain
27. `TODO` `W-027` Harpies slain
28. `TODO` `W-028` Centaurs slain (Kolkar, Galak, Maraudine, Magram, Gelkis)
29. `TODO` `W-029` Quilboar slain (Razormane, Bristleback, Razorfen)
30. `TODO` `W-030` Trolls slain, any tribe
31. `TODO` `W-031` Ogres slain
32. `TODO` `W-032` Naga slain
33. `TODO` `W-033` Satyrs slain
34. `TODO` `W-034` Furbolgs slain
35. `TODO` `W-035` Troggs slain
36. `TODO` `W-036` Dark Iron dwarves slain
37. `TODO` `W-037` Scarlet Crusade members slain
38. `TODO` `W-038` Syndicate members slain
39. `TODO` `W-039` Venture Co. goblins slain
40. `TODO` `W-040` Bloodsail Buccaneers slain
41. `TODO` `W-041` Burning Blade cultists slain
42. `TODO` `W-042` Scourge undead slain
43. `TODO` `W-043` Spiders slain
44. `TODO` `W-044` Raptors slain
45. `TODO` `W-045` Crocolisks slain
46. `TODO` `W-046` Wolves and worgs slain
47. `TODO` `W-047` Boars slain
48. `TODO` `W-048` Bears slain
49. `TODO` `W-049` Gorillas slain
50. `TODO` `W-050` Scorpids slain
51. `TODO` `W-051` Kodos slain
52. `TODO` `W-052` Big cats slain (panthers, tigers, lions, nightsabers)
53. `TODO` `W-053` Whelps and dragonkin slain
54. `TODO` `W-054` Elementals slain
55. `TODO` `W-055` Demons slain
56. `TODO` `W-056` Yetis slain
57. `TODO` `W-057` Critters killed total (UnitCreatureType Critter)
58. `TODO` `W-058` Chickens killed
59. `TODO` `W-059` Rabbits and squirrels killed

## Alliance iconic
_Only active for Alliance characters. [probe] for anything keyed on a mob name._

60. `TODO` `W-060` Hogger: level and /played at first kill
61. `TODO` `W-061` Hogger: attempts (combats with Hogger) and deaths to Hogger
62. `TODO` `W-062` Princess (Elwynn boar) killed
63. `TODO` `W-063` Edwin VanCleef killed: level and /played at first kill
64. `TODO` `W-064` Kobold candle meme: Kobolds killed in Elwynn mines
65. `TODO` `W-065` Harvest Watchers (Westfall scarecrows) slain
66. `TODO` `W-066` Defias Pillagers and Defias Messengers slain in Westfall
67. `TODO` `W-067` Bellygrub (Redridge boar) killed
68. `TODO` `W-068` Blackrock orcs slain in Redridge
69. `TODO` `W-069` Stitches killed (Duskwood)
70. `TODO` `W-070` Mor'Ladim killed (Duskwood)
71. `TODO` `W-071` Worgen slain in Duskwood
72. `TODO` `W-072` Deeprun Tram rides
73. `TODO` `W-073` Times entered Ironforge, Stormwind, and Darnassus
74. `TODO` `W-074` Time AFK in Ironforge
75. `TODO` `W-075` Boat rides: Menethil to Auberdine, Menethil to Theramore, Auberdine to Rut'theran
76. `TODO` `W-076` Rut'theran portal uses to Darnassus
77. `TODO` `W-077` Times visited Southshore
78. `TODO` `W-078` Times visited Theramore
79. `TODO` `W-079` Times you entered Orgrimmar, Thunder Bluff, or Undercity (enemy capitals)
80. `TODO` `W-080` Horde players killed in Southshore or Hillsbrad [probe]
81. `TODO` `W-081` Racial mount bought: horse, ram, mechanostrider, or nightsaber
82. `TODO` `W-082` Level you left your starting zone
83. `TODO` `W-083` Dragonmaw orcs slain in the Wetlands

## Horde iconic
_Only active for Horde characters. [probe] for anything keyed on a mob name._

84. `TODO` `W-084` Mankrik's wife found (Lost in Battle quest): level and /played
85. `TODO` `W-085` Kolkar centaurs slain in the Barrens
86. `TODO` `W-086` Echeyakee killed (Barrens)
87. `TODO` `W-087` Lakota'mani killed (Barrens rare kodo)
88. `TODO` `W-088` Plainstriders slain in the Barrens
89. `TODO` `W-089` Barrens General chat messages seen (count only)
90. `TODO` `W-090` Barrens chat messages mentioning Chuck Norris (count only)
91. `TODO` `W-091` Alliance players killed in the Crossroads [probe]
92. `TODO` `W-092` Gamon slain in Orgrimmar
93. `TODO` `W-093` Zeppelin rides by route: Orgrimmar to Undercity, Orgrimmar to Grom'gol, Undercity to Grom'gol
94. `TODO` `W-094` Undercity elevator rides
95. `TODO` `W-095` Deaths falling from the Undercity elevator [probe]
96. `TODO` `W-096` Thunder Bluff elevator rides and falls off Thunder Bluff
97. `TODO` `W-097` Times entered Orgrimmar, Thunder Bluff, and Undercity
98. `TODO` `W-098` Time AFK in Orgrimmar
99. `TODO` `W-099` Times visited Tarren Mill
100. `TODO` `W-100` Alliance players killed in Tarren Mill or Hillsbrad [probe]
101. `TODO` `W-101` Times visited Grom'gol, Kargath, Hammerfall, and Stonard
102. `TODO` `W-102` Times you entered Stormwind, Ironforge, or Darnassus (enemy capitals)
103. `TODO` `W-103` Racial mount bought: wolf, kodo, raptor, or skeletal horse
104. `TODO` `W-104` Scorpids slain in Durotar
105. `TODO` `W-105` Scarlet Crusaders slain in Tirisfal
106. `TODO` `W-106` Worgen slain in Silverpine (Arugal's pack)
107. `TODO` `W-107` Times visited the Kodo Graveyard

## Neutral zone iconic
_[probe] for name-based kills. Zone/subzone detection via ZONE_CHANGED_NEW_AREA and GetSubZoneText._

108. `TODO` `W-108` Green Hills of Stranglethorn pages looted
109. `TODO` `W-109` Green Hills of Stranglethorn chapters completed
110. `TODO` `W-110` Nesingwary hunts: tigers, panthers, raptors slain in Stranglethorn
111. `TODO` `W-111` King Bangalash killed
112. `TODO` `W-112` Gurubashi Arena entries and Arena Master trinket looted
113. `TODO` `W-113` Deaths in Stranglethorn Vale
114. `TODO` `W-114` Time spent in Stranglethorn Vale (the gankfest)
115. `TODO` `W-115` Booty Bay visits and Booty Bay boat rides to Ratchet
116. `TODO` `W-116` Times killed by Booty Bay or other goblin town guards
117. `TODO` `W-117` Devilsaurs slain in Un'Goro
118. `TODO` `W-118` Deaths to Devilsaurs
119. `TODO` `W-119` Un'Goro crystals collected
120. `TODO` `W-120` Un'Goro pylons activated
121. `TODO` `W-121` A-Me 01 escorted
122. `TODO` `W-122` Gadgetzan water quests completed
123. `TODO` `W-123` Dark Portal visits (Blasted Lands)
124. `TODO` `W-124` Karazhan entrance visits (Deadwind Pass)
125. `TODO` `W-125` Onyxia's Lair entrance visits (Dustwallow)
126. `TODO` `W-126` Yetis slain in Winterspring
127. `TODO` `W-127` Desolace centaur faction kills (Magram vs Gelkis)
128. `TODO` `W-128` Zone you spent the most time in at each 10-level bracket
129. `TODO` `W-129` Time spent in contested zones vs friendly zones

## Rares and named mobs
_[probe] Use UnitClassification and nameplate/target info._

130. `TODO` `W-130` Rare spawns seen (targeted or nameplate) vs killed
131. `TODO` `W-131` Rare kills by zone
132. `TODO` `W-132` Named quest-boss mobs killed (mobs from 'Wanted' posters)
133. `TODO` `W-133` First rare you ever killed: name, level, zone
134. `TODO` `W-134` Rares that killed you
135. `TODO` `W-135` Elite mobs soloed (only you in combat, no group)
136. `TODO` `W-136` Elite deaths: times an elite killed you
137. `TODO` `W-137` Highest-level elite soloed
138. `TODO` `W-138` Mobs killed that were 5+ levels above you
139. `TODO` `W-139` Times you were attacked by a mob 10+ levels above you

## World PvP and ganking
_[probe] Player kills need target caching: UnitIsPlayer, UnitIsEnemy, UnitLevel, stealth state at combat start, UnitIsDeadOrGhost after combat. Store levels and classes only, never names._

140. `TODO` `W-140` Enemy players killed total (honorable or not)
141. `TODO` `W-141` Lowbies ganked: enemy players 10+ levels below you killed
142. `TODO` `W-142` Stealth ganks: lowbies killed where you opened from stealth (rogue/druid)
143. `TODO` `W-143` Biggest level gap in a gank (your level minus theirs)
144. `TODO` `W-144` Times you were ganked: killed by an enemy player 10+ levels above you
145. `TODO` `W-145` Biggest level gap when you got ganked
146. `TODO` `W-146` Times corpse camped: killed by the same enemy player class/level combo 3+ times within 10 minutes
147. `TODO` `W-147` Spirit healer rezzes taken to escape a camp
148. `TODO` `W-148` Fair fights won: enemy players within 3 levels killed
149. `TODO` `W-149` Fair fights lost
150. `TODO` `W-150` World PvP kills by enemy class
151. `TODO` `W-151` World PvP deaths by enemy class
152. `TODO` `W-152` Your PvP nemesis class (class that killed you most)
153. `TODO` `W-153` Your favorite PvP victim class
154. `TODO` `W-154` Zone with the most world PvP kills
155. `TODO` `W-155` Zone with the most world PvP deaths
156. `TODO` `W-156` Time spent PvP flagged (UnitIsPVP)
157. `TODO` `W-157` Times you flagged yourself for PvP
158. `TODO` `W-158` Times you accidentally flagged (attacked a flagged player or entered a hostile town)
159. `TODO` `W-159` Dishonorable kills (civilian NPCs killed)
160. `TODO` `W-160` Enemy guards killed
161. `TODO` `W-161` Times killed by enemy guards
162. `TODO` `W-162` Times you attacked an enemy town
163. `TODO` `W-163` Faction leaders killed (Thrall, Cairne, Sylvanas, Bolvar, Magni, Tyrande, etc.)
164. `TODO` `W-164` Enemy players killed while you were at less than 20% health (clutch wins)
165. `TODO` `W-165` Times you died to an enemy player while fighting a mob (third-partied)
166. `TODO` `W-166` Times you killed an enemy player who was fighting a mob
167. `TODO` `W-167` Times you used Feign Death, Vanish, or similar to escape an enemy player
168. `TODO` `W-168` Enemy players killed in their own capital
169. `TODO` `W-169` Kill streaks: most enemy players killed without dying

## Battlegrounds and duels
_Forever battlegrounds: Warsong Gulch (10v10, brackets from 10-19), Arathi Basin (15v15, from 20-29), Darkspear Islands (15v15, from 30-39), Alterac Valley (40v40, 51-60). No arenas. Use GetBattlefieldStatus, GetBattlefieldWinner, UPDATE_BATTLEFIELD_SCORE, and duel events._

170. `TODO` `W-170` Battlegrounds entered, by battleground (WSG, AB, Darkspear Islands, AV)
171. `TODO` `W-171` Battleground wins and losses, by battleground
172. `TODO` `W-172` Time spent in battlegrounds
173. `TODO` `W-173` Time spent in battleground queues
174. `TODO` `W-174` Battleground killing blows and honorable kills (from the scoreboard)
175. `TODO` `W-175` Battleground deaths
176. `TODO` `W-176` Flags captured and returned in Warsong Gulch
177. `TODO` `W-177` Bases assaulted and defended in Arathi Basin
178. `TODO` `W-178` Darkspear Islands objectives (whatever scoreboard columns it reports)
179. `TODO` `W-179` Alterac Valley towers and graveyards assaulted or defended, captains and generals killed
180. `TODO` `W-180` Battleground marks earned, by battleground (3 per win, 1 per loss)
181. `TODO` `W-181` Level brackets you played each battleground in
182. `TODO` `W-182` Honor earned while leveling
183. `TODO` `W-183` Highest seasonal PvP rank reached while leveling
184. `TODO` `W-184` XP earned in battlegrounds, if Forever grants it
185. `TODO` `W-185` Duels requested and accepted
186. `TODO` `W-186` Duels won and lost
187. `TODO` `W-187` Duels won and lost by opponent class
188. `TODO` `W-188` Duels fled (left the area)
189. `TODO` `W-189` Longest duel
190. `TODO` `W-190` Times someone challenged you to a duel

## Dungeons deep dive
_Forever keeps every Classic dungeon and adds 9 new ones. Use GetInstanceInfo and ENCOUNTER_START/END. Read boss names from the encounter events instead of hardcoding, since the new dungeons' full boss rosters aren't published yet and Forever may rename Classic bosses._

191. `TODO` `W-191` Runs per dungeon: Classic (RFC, WC, Deadmines, SFK, BFD, Stockade, Gnomeregan, RFK, SM wings, RFD, Uldaman, ZF, Maraudon, Temple of Atal'Hakkar, BRD, LBRS, UBRS, Dire Maul wings, Stratholme, Scholomance) and new (see below)
192. `TODO` `W-192` Clear time per dungeon run (enter to final boss)
193. `TODO` `W-193` Fastest clear per dungeon
194. `TODO` `W-194` Wipes per dungeon
195. `TODO` `W-195` Dungeon runs abandoned (left before final boss)
196. `TODO` `W-196` Every boss killed, keyed by the encounter name the game reports
197. `TODO` `W-197` First kill of each dungeon's final boss: level and /played
198. `TODO` `W-198` Hall of Thanes runs (13-18, beneath Ironforge)
199. `TODO` `W-199` Ruins of Lordaeron runs (15-20, Tirisfal Glades)
200. `TODO` `W-200` Excavation Site runs (24-29, Wetlands)
201. `TODO` `W-201` City of Dalaran runs (28-33, Alterac Mountains) and Shade of the Archmage kills
202. `TODO` `W-202` The Drowned City runs (35-40, Stranglethorn Vale)
203. `TODO` `W-203` Krol'dok Stronghold runs (40-45, Riverglades)
204. `TODO` `W-204` Alcaz Island Prison runs (48-53, Dustwallow Marsh)
205. `TODO` `W-205` Blackmaw Hold runs (55-60, Azshara)
206. `TODO` `W-206` Shaper's Terrace runs (58-60, Un'Goro Crater)
207. `TODO` `W-207` New Forever dungeons vs Classic dungeons: runs and time split
208. `TODO` `W-208` Scarlet Monastery runs per wing: Graveyard, Library, Armory, Cathedral
209. `TODO` `W-209` Dire Maul runs per wing and Stratholme runs per side
210. `TODO` `W-210` Herod killed
211. `TODO` `W-211` Mograine and Whitemane killed
212. `TODO` `W-212` Arugal killed (Shadowfang Keep)
213. `TODO` `W-213` Mr. Smite and Cookie killed (Deadmines)
214. `TODO` `W-214` Mutanus the Devourer killed and Naralex awakened (Wailing Caverns)
215. `TODO` `W-215` Aku'mai killed (Blackfathom Deeps)
216. `TODO` `W-216` Mekgineer Thermaplugg killed (Gnomeregan)
217. `TODO` `W-217` Charlga Razorflank killed (Razorfen Kraul)
218. `TODO` `W-218` Amnennar the Coldbringer killed (Razorfen Downs)
219. `TODO` `W-219` Archaedas killed (Uldaman)
220. `TODO` `W-220` Zul'Farrak graveyard stair event survived
221. `TODO` `W-221` Chief Ukorz Sandscalp killed (Zul'Farrak)
222. `TODO` `W-222` Princess Theradras killed (Maraudon)
223. `TODO` `W-223` Shade of Eranikus killed (Temple of Atal'Hakkar)
224. `TODO` `W-224` Emperor Dagran Thaurissan killed (BRD)
225. `TODO` `W-225` Times you were the last party member alive in a wipe
226. `TODO` `W-226` Times you died first in a wipe
227. `TODO` `W-227` Dungeon deaths by boss
228. `TODO` `W-228` Dungeon XP earned per run (Forever shifts XP toward quests, so this is interesting to compare)
229. `TODO` `W-229` Rare-quality boss drops looted per dungeon
230. `TODO` `W-230` Dungeon quests completed per dungeon
231. `TODO` `W-231` Times you ran a dungeon 5+ levels over (boosting or farming)
232. `TODO` `W-232` Times you were boosted through a dungeon by a much higher player [probe]
233. `TODO` `W-233` Party compositions run with (class counts only)
234. `TODO` `W-234` Tank, healer, or DPS role per run (by spec or self-assigned)
235. `TODO` `W-235` Times you hearthed out of a dungeon
236. `TODO` `W-236` Instance lockouts hit ('too many instances')
237. `TODO` `W-237` Times you released and corpse-ran into a dungeon
238. `TODO` `W-238` Dungeon you ran most at each 10-level bracket
239. `TODO` `W-239` Dungeon bosses defeated per Legacy bracket (15-25, 26-45, 46-60)

## Raids (post-launch, level 60)
_Raids open December 9, 2026: Onyxia's Lair (40-player), The Barrow Deeps (10-player), Hyjal Summit (20-player). Optional for a 1-60 recap, but cheap to add with the same encounter events._

240. `TODO` `W-240` Raid runs by raid
241. `TODO` `W-241` Raid bosses killed, by encounter name
242. `TODO` `W-242` Onyxia killed: /played and days after hitting 60
243. `TODO` `W-243` Raid wipes by boss
244. `TODO` `W-244` Time from hitting 60 to first raid boss kill
245. `TODO` `W-245` Deaths in raids, and deaths to Onyxia's Deep Breath and whelps

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
329. `TODO` `W-329` Boat rides total
330. `TODO` `W-330` Zeppelin rides total
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
375. `TODO` `W-375` Gold spent on mounts
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
468. `TODO` `W-468` First enemy player killed
469. `TODO` `W-469` First time killed by an enemy player
470. `TODO` `W-470` First trip to each capital city
471. `TODO` `W-471` First flight path taken
472. `TODO` `W-472` First boat or zeppelin ride
473. `TODO` `W-473` First mount summoned
474. `TODO` `W-474` First profession maxed for its bracket (75, 150, 225, 300)
475. `TODO` `W-475` First time hitting Exalted with any faction
476. `TODO` `W-476` First talent point
477. `TODO` `W-477` First class quest completed
478. `TODO` `W-478` First rare killed
479. `TODO` `W-479` First time in a battleground
480. `TODO` `W-480` First duel won
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
502. `TODO` `W-502` Full statistics baseline at first load, with level and /played
503. `TODO` `W-503` Statistics snapshot at every ding (diff only)
504. `TODO` `W-504` Statistics snapshot at every export
505. `TODO` `W-505` Statistics included in the export string
506. `TODO` `W-506` Lifetime totals backfill for players who installed mid-leveling
507. `TODO` `W-507` Cross-check: our kill, death, and quest counts vs Blizzard's for the same period
508. `TODO` `W-508` Combat stats our tracking can't see: total damage dealt and received, largest hit, largest heal, total healing

## Changelog
- 2026-10-01: Wrapped spec created, all items `TODO`. Revised for Forever content: new dungeons, raids, battlegrounds, and Forever exclusives.
- 2026-10-01: Section 1 (WoW Forever exclusives) done in JourneyTrackerWrapped.lua with the Track registry (count/time/max/first, maps capped at 200) and a [probe] feature flag. W-001..003, 006..012, 016, 017, 019..021 `BUILT`; W-004, 005, 018 `SKIP`; W-013..015 left `TODO` until the Legacy API is found.
- 2026-10-01: Camping (W-008..012) now shown on the Social page, since camping is a social mechanic; the WoW Forever page keeps the rest of section 1.
- 2026-10-01: VERIFIED in game: W-003, W-009, W-011, W-020.
- 2026-10-01: W-396 `SKIP`: built as journey #104 (gear worn the longest, by /played and by levels gained).
- 2026-10-01: Added the "Blizzard Statistics pane" section (W-501..W-508) and an architecture note on using Blizzard's statistics for lifetime totals. W-501 `BUILT`: `/journey statprobe` (dev only) in JourneyTrackerStats.lua. W-502..W-508 wait for the probe result.
