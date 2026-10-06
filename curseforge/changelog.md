# Changelog

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
