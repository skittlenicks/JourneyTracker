# Changelog

## 0.6.15

- **Who you met:** Journey Tracker now counts the players you group or trade with by race and class, so you can see how many Dwarf Shamans, Undead Paladins and other new Forever combinations crossed your path. It's on the Groups & Chat page. Each player counts once, and no names are kept: only a scrambled code, which never leaves the game.
- **Your PvP nemesis:** deaths to other players are now counted by race and class too, and Journey Tracker remembers the one player who killed you most, as "an Undead Rogue, 3 times", never by name. It's on the World PvP page.

### On the website

- **A picture for your stories:** every journey's page can now make a tall picture for Instagram, TikTok or Discord. Pick up to four of your stats and rankings, then download it or share it straight from your phone.
- **Who you met and your nemesis** show on your page, and there's a new ranking for meeting players of Forever's new race and class combinations.
- Rankings now show your place as a share, like "Top 4%", once 50 players are on a ranking instead of 100.

## 0.6.14

- **Quest XP counted right:** for some quests the XP reached Journey Tracker before the game said the quest was turned in, so about a fifth of quest XP was filed as "other", and so were many level-ups. It's now credited to the quest whichever comes first, and what was saved before is fixed once when you log in.
- **Herbs aren't treasure chests:** Forever calls herb gathering "Herbalism", and every herb you picked counted as a treasure chest. It doesn't any more, and the herbs come off your saved chest count.
- **Flying over a zone isn't visiting it:** the flight from Ironforge to Stormwind crosses Searing Gorge and Burning Steppes, and each crossing was saved as a stop on your route. Zones you only fly over are now left off your route, and where you land counts.
- **Loot gold:** your share of a group member's loot, and money from a very quick auto-loot, now count as gold from looting.
- **Camps set up** now shows the game's own count. Journey Tracker was missing most camps.
- **A fishing pole isn't your first two-hander** any more.
- **Asking your guild:** the Guild tab now says when you last asked and how many guildmates have answered, or that you can't ask during a fight or in a dungeon.

### On the website

- Journeys saved before this version get the same fixes where the data allows: the XP split, treasure chests, camps and the fishing pole. Routes saved before this version still include zones you flew over, since they don't say which stops were flights.
- The quest chapter no longer says the same thing twice.

## 0.6.13

- **Compare with your guild:** the new Guild tab, at the bottom of the window, puts you side by side with guildmates who run Journey Tracker 0.6.13 or later, at every 10 levels you or they have reached. For each one it shows how long it took to get there in /played and in days, the fastest and slowest level on the way, and gold, item level, health, attack or spell power, crit and professions at the level-up. Guildmates show up while they're online. Press **Ask the guild again** to check for more.
- **Names stay in the game:** the page shows guildmates by name, but names are only kept until you log out. They're never saved or exported.
- **Your choice:** sharing is on by default. Turn off **Compare with your guild** in Options and you stop sharing yours, but you still see guildmates who share theirs.
- **Options is a tab now:** it moved from the button row to the tabs at the bottom of the window, always the last one: Journey, Levels, Guild, Options.

### On the website

- **Your guild chapter:** a shared journey now shows guildmates who saved theirs at the same milestone, side by side with yours, and where you placed on time to get there. Like the rankings, a level 34 journey is compared at level 30. Guildmates show by race, class and level, never by name, once they've saved a journey from 0.6.13 on.
- To find your guildmates, exports from this version carry a code for your guild instead of its name. Turning off **Compare with your guild** leaves the code out.

## 0.6.12

- **Your emotes are your own:** opening the world map plays the /read emote, and Journey Tracker was counting every one, so for most players "read" was their favorite emote by far. Map reads aren't counted any more, and the ones counted so far are taken out.
- **No more "Unknown" on your route:** right after a loading screen the game briefly gives no zone name, and that moment was saved as a stop. It isn't any more.

### On the website

- Journeys saved before this version leave the map's reads out of their emotes too, and loading screens no longer count toward the zone-hopping ranking.

## 0.6.11

- **Told when there's an update:** Journey Tracker now says in chat when a newer version is out. Copies of the addon in your guild and group tell each other their version in hidden addon messages, never during a fight or in a dungeon, so you'll hear about an update once someone near you has it. It reminds you at each login until you update.
- **Dungeons on your route:** each dungeon and raid you go into is saved on your route, with where you went in, so the website can put it on the map.

### On the website

- **Dungeons and raids on the map:** your route now shows the dungeons and raids you ran, with square pins at their entrances, in the order you went. Classic dungeons and raids show on journeys saved before this version too. Forever's own dungeons show from 0.6.11 on, at the spot where you went in.
- **Fairer rankings:** players are compared at the same level. A journey shared at level 48 shows everything up to 48, but it's ranked as you were at 40, on what's known from then: the time it took, your kills, deaths and quests at 40, the game's Statistics as they stood, and the levels you did things at. For every ranking, paste the journey the addon saved when you reached 40 ("At 40" in the Export window). After you save, the website names any of those you haven't pasted yet. Rankings start at level 10.
- **Character sheet rankings:** your gear and stats at each milestone are ranked too: average item level, health, mana, attack power, spell power and crit chance, taken from your character sheet as you reached the level. Health, mana, power and crit are compared within your class.

## 0.6.10

- **Inns aren't zones any more:** inside some buildings, like the Lakeshire Inn and the Lion's Pride Inn, Forever gives the building's name as the zone's. Journey Tracker now records the zone you're really in, so time at the inn counts toward Redridge Mountains or Elwynn Forest, and your route no longer stops at the inn. What was already saved under an inn's name moves to its zone the next time you're in that inn, or at login if you've been there since 0.6.8.
- **No more "Unknown" zone** when the game briefly gives no zone name, often right after logging in: the zone the map shows is used instead.

## 0.6.9

- **Forever's new zones** now have a zone type, taken from the game's own zone data. Mount Hyjal, Riverglades and Shen'dralas are contested, and Zephras Isle is a sanctuary. Time there, and the PvP stats, count them instead of leaving them out.
- **Your whole route on the map, in any language:** zones you visited before 0.6.8 get their map too, so the website can place every stop of your route whatever language your game is in.

### On the website

- A zone on your route is placed on the map if any visit to it was saved with its map, not only the first.

## 0.6.8

Fixes for stats that weren't recording on WoW Forever, found by going through the journeys saved to the website.

- **Zone types:** Forever doesn't tell addons whether a zone is friendly, contested or hostile, so Journey Tracker now knows the old world's zones itself. Time in contested zones, PvP flags, deaths to guards and deaths in friendly towns now record. Forever's new zones aren't known yet.
- **Emotes:** /dance, /hug, /train and the rest are now counted by name, so your most used emote shows up.
- **Cooking and recipes:** what you cook counts in Forever's profession window. The recipes each profession knows also come from the game's Statistics, so ones learned before this version count.
- **Loot rolls:** Need, Greed and Pass, rolls won and lost, your highest and lowest roll, and blues won on Need now record, from Forever's loot history.
- **Forever's new dungeons** are recognized by the names Forever gives them, like "Excavation Site: Wetlands", so their runs, clear times and first final-boss kills record.
- **Saved every 10 levels:** the journey saved at each milestone now includes your character sheet from that level-up: stats, armor and gear.
- **A new character with an old name:** if you delete a character and make a new one with the same name, WoW hands the new one the old character's saved data. Journey Tracker now notices and starts a fresh journey, with a note in chat (sometimes asking you to /reload). The old journey is kept in the addon's backup, not deleted.
- **Food and drink:** cloth, maces and other things that aren't food, counted by versions before 0.6.4, are cleared out.

### On the website

- **Any language:** journeys saved with 0.6.8 read the same whatever language your game is in. Professions count toward rankings, and every zone has its place on the map. Older journeys from French, German and Spanish games get their professions counted too.
- **Loot rolls:** your Need and Greed counts come from the game's Statistics when those are higher, so rolls from before 0.6.8 count.

## 0.6.7

- **Hide the minimap button** if you'd rather not have it: untick "Show the button on the minimap" in Options, or type `/journey minimap`. The window still opens with `/journey` or `/jt`, and `/journey minimap` brings the button back. The setting is saved per character.

### On the website

New at [www.journeytracker.dev](https://www.journeytracker.dev) alongside this version. They work with any version of the addon.

- **One link per character:** paste a newer export as you level and your character's link shows it, instead of making a new one. Links you've already shared keep working and show your latest.
- **What changed:** your journey's page shows what changed since your last save: levels, /played, kills, deaths, quests, gold, new zones and the moments along the way.
- **Compare:** click Compare on a journey and paste a friend's link to see your runs side by side: the time each of you took to every ten levels, kills, deaths, quests and where each of you ranks.
- **Saving limit:** each character can be saved once every 30 minutes. The journeys the addon saves every 10 levels always go through.

## 0.6.6

- **Options** is now a button at the bottom of the window, next to Export and Print to Chat, instead of the last entry in the list on the left. It has the settings for the every-10-levels export pop-up and the screenshot at every level-up.
- **A screenshot at every level-up** is now on to start with. Turn it off with the Options button, or `/journey screenshots`.

## 0.6.5

- **Fixed the error at login**, "Journey Tracker has been blocked from an action only available to the Blizzard UI": WoW Forever doesn't let addons read the combat log, and Journey Tracker no longer asks for it.

## 0.6.4

### Made for WoW Forever

- **Talents** now come from Forever's talent tree: the points you spend, in order, your first talent point, your split across the three trees at 60, and your role in dungeons. Switching to your other spec isn't counted as spending points.
- **PvP rank** comes from Forever's rank system, with its title.
- **Zone stats** work on Forever: time in contested zones, accidental PvP flags, and deaths in friendly towns.
- **Auction house**: auctions posted, sold, expired and cancelled now count on Forever's auction house. Bank tabs you buy count too.
- **Wand time, items and bags**: wanding, using your hearthstone and gadgets, and bag checks all work on Forever.

### Fixes

- **Falls**: Slow Fall or Levitate cast mid-air, a loading screen while you're falling (a zeppelin, a portal, a summon), and drops as a ghost no longer count as falls or deadly falls.
- **Realm type**: on a Normal realm, getting flagged in a fight no longer marks your realm as PvP.
- **Travel**: flying over a dock no longer counts as a boat ride, and towns you fly over aren't visits. A /reload or relog in town doesn't count as a new visit.
- **Kills**: looting or skinning a corpse no longer counts the kill again, and kills someone else tagged aren't yours. Kills before this version now count toward creature families (murlocs, kobolds and the rest).
- **Dungeons and battlegrounds**: a /reload no longer loses the run you're in or counts the battleground again. Run times leave out time logged off, and battleground raids don't count as groups you joined.
- **Class stats**: buffs and heals on yourself count as on yourself, food and drink no longer includes maces, cloth or pet food, paladin aura time keeps going when you learn a spell, your pet doesn't "die" when you do, and class quests are still recognized after a server restart.
- **Reputation** below Neutral (Timbermaw Hold, for one) is recorded properly.
- **Everything else**: the XP that finishes a level counts for that level, profession trainers aren't class training, re-opened chests count once, two sales of the same item count as two, and many smaller counts are fixed.
- **Exports**: a single odd number can no longer get your export turned away by the website.

### Privacy

- **Most typed words** leave out whispers and never keep a name, yours or another player's. Exports carry only your top 10.
- Other players' names can't end up in the Legacy notes or the list of error messages.

### Other

- `/journey status` lists any game functions your client doesn't have, to help track down a stat that can't record.
- The add-on's info now lists its author and website.

## 0.6.1

- **Milestone pop-up**: every 10 levels, a small window offers to export your journey right away, while it's fresh. Turn it off in the new Options page.
- **Options page** (`/journey options`): the milestone pop-up, and an optional screenshot at every level-up.
- **Fair rankings at 60**: exports note how long after a milestone they were made, so a fresh 60 isn't ranked against one that's been 60 for weeks.
