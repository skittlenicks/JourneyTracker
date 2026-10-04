# Journey Tracker

Journey Tracker keeps a detailed record of your character's road from level 1 to 60 in WoW Forever. It tracks your time, XP, kills, deaths, quests, gold, travel, gear and class, saves a snapshot every time you level up, and shows it all in an in-game window laid out like the classic quest log.

Type **/journey** (or **/jt**), or click the gold **JT** button on your minimap.

## What it tracks

**Time and pace**

- /played in total and for every single level, plus the date and time of every ding
- Play sessions: how many, average and longest, and the most levels you gained in one
- Time spent AFK, resting, dead, on flight paths and mounted
- XP per hour, your fastest and slowest levels, days played, and the hours of the day you play

**Leveling and quests**

- Where you were for every ding, and what pushed you over: a quest, a kill or exploring
- Your XP split between quests, kills and exploration, rested XP used, and solo vs grouped XP
- Quests completed per level and per zone, quests abandoned, gold from quests, and the quest you held the longest

**Combat and deaths**

- Kills per level, your most-killed mobs, elites, rares and creature types, and the highest-level mob you've killed compared to your own level
- Fights, your longest fight, time in combat, dungeon bosses and PvP honorable kills
- Every death: where it happened, what killed you, and how you came back (corpse run, spirit healer or a rez), plus your longest run of levels without dying
- Dungeon runs, time per run and deaths per dungeon

**Exploration and travel**

- Every zone in the order you reached it, subzones discovered, and time spent in each zone
- Hearthstone uses, flight paths found, flights taken, and distance traveled on the ground and by air
- Total distance fallen, and the longest fall you survived

**Gold, loot and gear**

- Gold earned and spent, and where it went: training, repairs, flights, vendors and the auction house
- Your gold at every level, your peak gold, and when you got your first mount
- Items looted by quality, your best item, and your first blue and first epic
- A snapshot of your gear every 10 levels, and the gear you wore the longest (by levels and by /played)

**Professions and skills**

- Professions learned and how they rose over time, items crafted and fish caught
- Herbs picked, ore mined and creatures skinned, and what they gave
- Every spell you learned and the level you learned it, and weapon skill-ups

**Your class**

- Stats for every class, such as time in each stance or form, seals and auras, totems dropped, pets tamed, soul shards, conjured food and water, ammo used and time in stealth
- For everyone: bandages, potions, food and drink, and an estimate of the healing you've done

**WoW Forever**

- Skyborne: your time on Zephras Isle and the faction you chose
- When you first reached Riverglades, Shen'dralas and Mount Hyjal, and new Forever quests vs Classic quests
- Camping: camps set up, time at campfires, camp buffs and camping objects crafted
- Map areas explored at each level, transmog changes, and your realm's ruleset

**Social**

- Time grouped vs solo, how many different players you've grouped with (a count, never names), the level you joined a guild, and how many times you jumped

## See your recap

Click **Export** at the bottom of the window (or right-click the minimap button, or type **/journey export**), press Ctrl+C, and paste it at **www.journeytracker.dev**. You get a Wrapped-style recap of your road to 60: your route across Azeroth, deaths, quests, gold, gear and where you rank, with a link to share it.

Every 10 levels, the addon saves your journey as it was when you got there. Share your road to 10, 20, 30 and on, even after you've passed it, and see how you rank against other players at the same level.

## Privacy

- Exports never include your character's name or realm, other players' names, or chat.
- Other players' names are never saved, and chat is never stored.
- Nothing leaves the game by itself. Addons can't reach the internet or the rest of your computer, so your data stays in your saved variables until you choose to share an export.
- Pasting an export on the website saves it so it counts toward the rankings. Anyone you give your recap's link to can see it, but never your name or realm.

## Good to know

- Stats are saved per character and kept when you update the addon.
- Tracking starts when you install it. On a character that's already leveling, everything from that point on is recorded, and the game's own Statistics pane fills in lifetime totals like quests completed, deaths and kills.
- **/journey backup** saves a second copy of your data, just in case.
- This is an early version, made during the WoW Forever beta. Some stats are still being checked in game, so bug reports and ideas are very welcome in the comments.

## Commands

- **/journey** or **/jt**: open the window
- **/journey export**: copy your stats to paste at www.journeytracker.dev (same as the Export button)
- **/journey export 30**: your journey as it was at level 30 (saved every 10 levels)
- **/journey backup**: save a backup copy of your data
- **/journey stats**: show what's been read from the game's Statistics pane
- **/journey version**: show which version you have
