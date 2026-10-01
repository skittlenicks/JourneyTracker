JOURNEY TRACKER
===============

Journey Tracker keeps a record of your character's trip from level 1 to 60:
time played, kills, deaths, quests, gold, travel and lots more. Send it to me
now and then and it becomes part of a "Wrapped"-style recap.


INSTALL
-------
1. Unzip this file into your WoW Forever AddOns folder, so you end up with:
     World of Warcraft\_classic_beta_\Interface\AddOns\JourneyTracker
2. Restart WoW. (If you're updating and the game is already open, /reload
   is usually enough, but a restart always works.)
3. Type /journey to open your stats, or click the gold "JT" button on the
   minimap.


SEND ME YOUR DATA
-----------------
Nothing uploads by itself, so I only get your data when you send it.

1. Type /journey export (it won't work in the middle of a fight).
2. A window opens with a long block of text that's already selected.
   Press Ctrl+C to copy it.
3. Paste it to me in Discord. If it's long, Discord turns it into a file
   attachment. That's fine, just send it.

How often: every few levels or every few play sessions is plenty.
Sending the same export twice is fine; I'll only count it once.


RATHER SEND THE FILE?
---------------------
You can send me your saved data file instead. The game writes it when you
log out (or type /reload). Each character has its own file:

  World of Warcraft\_classic_beta_\WTF\Account\<account>\<realm>\<character>\SavedVariables\JourneyTracker.lua

<account> is your account name or a number, <realm> is your server and
<character> is your character's name.


WHAT'S COLLECTED
----------------
- Your character's class, race, faction, level and time played.
- Gameplay stats: kills, deaths, quests, gold, loot, zones, professions,
  spells you cast, and so on.
- A random ID made up by the addon, so I can tell your exports apart over
  time. It isn't based on your name or anything else about you.

WHAT'S NOT COLLECTED
--------------------
- Your character's name or realm, and other players' names.
- Chat messages.
- Anything outside the game. The addon can't see your computer or the
  internet, and it can't send anything anywhere by itself.


UPDATING
--------
Close WoW, delete the old JourneyTracker folder, unzip the new one in its
place, and start WoW again. Your data is kept: it lives in the WTF folder,
not in the addon folder.

For extra peace of mind before updating, type /journey backup. It saves a
second copy of your data alongside the original.


COMMANDS
--------
/journey           Open your stats (same as clicking the minimap button)
/journey export    Make a text export to send me
/journey backup    Save a backup copy of your data
/journey version   Show which version you have
