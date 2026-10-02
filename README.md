# Journey Tracker

A World of Warcraft: Forever addon that records a character's journey from
level 1 to 60 (time played, kills, deaths, quests, gold, travel, class
stats and more) for a "Wrapped"-style recap. Players export their data from
the addon's window (or `/journey export`) and paste it at
www.journeytracker.dev, which saves it to Supabase, shows the recap with a
link to share and ranks it against every other saved journey. The import
tool loads exports sent by hand.

## Layout

| Folder | What it is |
| --- | --- |
| `JourneyTracker/` | The addon. This folder is what goes in `Interface\AddOns`. |
| `JourneyProbe/` | Dev-only test addon that logs what the game API exposes. Not for players. |
| `specs/` | What to track, with each item's status (`TODO`, `BUILT`, `VERIFIED`, `BLOCKED`, `SKIP`). Read the status rules in `specs/journey-tracking-spec.md` before changing code. |
| `build/` | `build.ps1` packages the addon into `dist/JourneyTracker-<version>.zip` for friends. |
| `art/` | The JT logo and zone maps. `make-logo.ps1` draws both the in-game icon (`JourneyTracker/JT.tga`) and the CurseForge logo (`curseforge-logo.png`). `build-maps.ps1` turns a wow.export export of the Forever client (kept in the git-ignored `art/export/`) into web maps (parchment and terrain zone maps, plus map tiles of both continents cut from the minimap, zoom 3 to 9) and `maps.json`, every map's ID, continent, world rectangle and place on the web map. |
| `curseforge/` | The CurseForge page text: `summary.txt` and `description.md` (paste with the description editor set to Markdown). |
| `tools/import/` | Node tool that decodes exports and inserts them into Supabase. |
| `site/` | The recap website, www.journeytracker.dev (run `art/build-maps.ps1` first). `build.ps1 -Site` builds it into `dist/site` with the addon zip to download and the link preview image; `deploy.ps1` puts it on Vercel with its functions in `api/` (saving pasted exports, share pages, card images). `model.js` turns an export into a journey and ranks it on `rankings.js`; the page and the functions share both. Without `-Site`, `build.ps1` makes the one-file draft `dist/road-to-60.html`. |

## Common tasks

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

## Data and privacy

Exports are anonymous: a random character ID, class, race, faction, level,
/played and gameplay stats. They never include the character's name or realm,
other players' names or chat messages. Secrets (`tools/import/.env`) and build
output (`dist/`) are git-ignored.
