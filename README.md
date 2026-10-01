# Journey Tracker

A World of Warcraft: Forever addon that records a character's journey from
level 1 to 60 (time played, kills, deaths, quests, gold, travel, class
stats and more) for a "Wrapped"-style recap. Players export their data with
`/journey export`; the import tool loads the exports into Supabase.

## Layout

| Folder | What it is |
| --- | --- |
| `JourneyTracker/` | The addon. This folder is what goes in `Interface\AddOns`. |
| `JourneyProbe/` | Dev-only test addon that logs what the game API exposes. Not for players. |
| `specs/` | What to track, with each item's status (`TODO`, `BUILT`, `VERIFIED`, `BLOCKED`, `SKIP`). Read the status rules in `specs/journey-tracking-spec.md` before changing code. |
| `build/` | `build.ps1` packages the addon into `dist/JourneyTracker-<version>.zip` for friends. |
| `tools/import/` | Node tool that decodes exports and inserts them into Supabase. |

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
