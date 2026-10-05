# Journey Tracker

A World of Warcraft: Forever addon that records a character's journey from
level 1 to 60: time played, kills, deaths, quests, gold, travel, class stats
and more. Paste its export at [www.journeytracker.dev](https://www.journeytracker.dev)
for a "Wrapped"-style recap of your road to 60, with a link to share it and
where you rank among other players' saved journeys.

## Install

1. Download `JourneyTracker-<version>.zip` from
   [www.journeytracker.dev](https://www.journeytracker.dev).
2. Unzip it into your WoW Forever AddOns folder, so you end up with
   `World of Warcraft\_classic_beta_\Interface\AddOns\JourneyTracker`.
3. Restart the game. Type `/journey` (or `/jt`), or click the gold JT button
   on the minimap, to see your stats.

It records as you play. Each character's data is saved in the game's
`WTF\Account\<account>\<realm>\<character>\SavedVariables\JourneyTracker.lua`.

## Export your journey

1. Click **Export** at the bottom of the Journey Tracker window (or
   right-click the minimap button, or type `/journey export`). It won't open
   in the middle of a fight.
2. Press Ctrl+C to copy the text it shows.
3. Paste it at [www.journeytracker.dev](https://www.journeytracker.dev) and
   click **Show my journey**.

Every 10 levels the addon also keeps your journey as it was then, so you can
share your road to 30 after you've passed it: pick **At 30** in the export
window, or type `/journey export 30`.

## What's collected, and what isn't

An export contains:

- A random ID the addon makes up for the character, so exports of the same
  character can be told apart. It isn't based on your name or account.
- The character's class, race, faction, level, realm type (Normal, PvP,
  Roleplaying or Hardcore) and time played.
- Gameplay stats: kills, deaths and what killed you, quests, gold, loot,
  zones, travel, professions, spells and class stats.
- Where on each zone's map you spent your time, as rough squares, for the
  website's heat map.

It never contains:

- Your character's name or realm.
- Other players' names. Players you grouped with are only counted.
- Chat messages.

Nothing leaves the game by itself: addons can't reach the internet, so your
data stays in your saved variables until you copy an export and paste it
somewhere. Pasting it on the website saves it, so it counts toward the
rankings, and anyone you give its link to can see the recap.

## For developers

### Layout

| Folder | What it is |
| --- | --- |
| `JourneyTracker/` | The addon. This folder is what goes in `Interface\AddOns`. |
| `JourneyProbe/` | Dev-only test addon that logs what the game API exposes. Not for players. |
| `specs/` | What to track, with each item's status (`TODO`, `BUILT`, `VERIFIED`, `BLOCKED`, `SKIP`). Read the status rules in `specs/journey-tracking-spec.md` before changing code. |
| `build/` | `build.ps1` packages the addon into `dist/JourneyTracker-<version>.zip`. |
| `art/` | The JT logo and the maps. `make-logo.ps1` draws both the in-game icon (`JourneyTracker/JT.tga`) and the CurseForge logo (`curseforge-logo.png`). `build-maps.ps1` turns a wow.export export of the Forever client (kept in the git-ignored `art/export/`) into web maps (parchment and terrain zone maps, and minimap tiles of both continents, which the site no longer uses) and `maps.json`, every map's ID, continent and world rectangle. `worldmap.js` reads the game's own world map straight from a Forever install (`game-files.js` reads the game's files): Azeroth, both continents and each zone's highlight, into `art/export/worldmap/`, and `worldmap.json`. |
| `curseforge/` | The CurseForge page text: `summary.txt` and `description.md` (paste with the description editor set to Markdown), and `changelog.md` for each upload. |
| `tools/import/` | Node tool that decodes exports and inserts them into Supabase. |
| `site/` | The recap website, www.journeytracker.dev (run `art/build-maps.ps1` and `node art/worldmap.js "<WoW folder>"` first). `build.ps1 -Site` builds it into `dist/site` with the addon zip to download and the link preview image; `deploy.ps1` puts it on Vercel with its functions in `api/` (saving pasted exports, share pages, card images). `model.js` turns an export into a journey and ranks it on `rankings.js`; the page and the functions share both. Without `-Site`, `build.ps1` makes the one-file draft `dist/road-to-60.html`. |

### Common tasks

Package a release (version comes from `JourneyTracker/JourneyTracker.toc`):

```
powershell -ExecutionPolicy Bypass -File build\build.ps1
```

Import exports (see `tools/import/README.md` for setup):

```
cd tools/import
npm install
node import.js exports.txt --dry-run
node import.js exports.txt
npm test
```

Secrets (`.env` files, such as `tools/import/.env`), build output (`dist/`)
and the game's map art are git-ignored. `tools/import/.env.example` shows the
settings the import tool needs.

## License

MIT, see [LICENSE](LICENSE). The bundled libraries keep their own licenses:
LibDeflate (zlib License, see `JourneyTracker/Libs/LibDeflate/LICENSE.txt`)
and LibStub (public domain). The website's fonts are under the SIL Open Font
License (`site/fonts/`). World of Warcraft and its map art belong to Blizzard
Entertainment; the map art isn't in this repository.
