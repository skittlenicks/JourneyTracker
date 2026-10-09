'use strict';
// Each dungeon and raid's entrance, read straight from a WoW Forever install,
// for the website's route (a journey's stops in dungeons, pinned where you
// go in):
//
//   art\dungeons.json   [{ id, names, raid?, entrance?: { mapID, X, Y }, zone?, zones? }]
//
// `id` is the dungeon's map (Map.db2, what GetInstanceInfo gives as its
// instance ID), `names` the map's name and the names the game gives inside
// (what the addon saved as a stop's zone before 0.6.11). The entrance is
// the map's corpse position, where a ghost runs back to: a place in the
// world (X north, Y west, in yards, on the continent `mapID`), and `zone`
// the zone map it's on (art\maps.json). Forever's own dungeons have no
// corpse position in the game files (their server keeps it), so they list
// the zones they're in instead (`zones`, from wrapped-tracking-spec.md),
// for the spot the addon saw you go in from (0.6.11 on).
//
//   node art\dungeons.js "<World of Warcraft folder>" [product]
//
// after art\build-maps.ps1 (art\maps.json) and art\worldmap.js (the zones'
// highlights, whose shapes say which zone an entrance is in).

const fs = require('fs');
const path = require('path');
const { GameFiles, readTable, decodePNG } = require('./game-files');

// The tables by FileDataID, with their layouts as of Forever 1.60.1.
const TABLES = {
  Map: [1349477, 0xD43AFAC3, `
    $noninline,id$ID<32>
    Directory string
    MapName_lang string
    MapDescription0_lang string
    MapDescription1_lang string
    PvpShortDescription_lang string
    PvpLongDescription_lang string
    Corpse[2] float
    MapType<u8>
    InstanceType<8>
    ExpansionID<u8>
    AreaTableID<u16>
    LoadingScreenID<16>
    TimeOfDayOverride<16>
    ParentMapID<16>
    CosmeticParentMapID<16>
    TimeOffset<u8>
    MinimapIconScale float
    CorpseMapID<16>
    MaxPlayers<u8>
    WindSettingsID<16>
    ZmpFileDataID<32>
    WdtFileDataID<32>
    OceanLiquidTypeID<32>
    NavigationMaxDistance<32>
    PreloadFileDataID<32>
    Flags<32>[3]`],
  AreaTable: [1353545, 0x9995B797, `
    $noninline,id$ID<32>
    ZoneName string
    AreaName_lang string
    ContinentID<u16>
    ParentAreaID<u16>
    AreaBit<16>
    SoundProviderPref<u8>
    SoundProviderPrefUnderwater<u8>
    AmbienceID<u16>
    UwAmbience<u16>
    ZoneMusic<u16>
    UwZoneMusic<u16>
    ExplorationLevel<8>
    IntroSound<u16>
    UwIntroSound<u32>
    FactionGroupMask<u8>
    Ambient_multiplier float
    MountFlags<32>
    PvpCombatWorldStateID<32>
    WildBattlePetLevelMin<u8>
    WildBattlePetLevelMax<u8>
    WindSettingsID<u8>
    ContentTuningID<32>
    Flags<32>[2]
    LiquidTypeID<u16>[4]`],
};
// Forever's own dungeons and the zones they're in (wrapped-tracking-spec.md,
// W-198 to W-206), by uiMapID; matched to the game's maps by name, and kept
// by name for those this build doesn't have yet.
const FOREVER = [
  { names: ['The Hall of Thanes', 'Hall of Thanes'], zones: [1455, 1426] },   // beneath Ironforge
  { names: ['Ruins of Lordaeron'], zones: [1420, 1458] },                     // Tirisfal Glades
  { names: ['Excavation Site: Wetlands', 'Excavation Site'], zones: [1437] }, // Wetlands
  { names: ['City of Dalaran', 'Dalaran'], zones: [1416, 1424] },             // Alterac Mountains
  { names: ['The Drowned City'], zones: [1434] },                             // Stranglethorn Vale
  { names: ["Krol'dok Stronghold"], zones: [2548] },                          // Riverglades
  { names: ['Alcaz Island Prison'], zones: [1445] },                          // Dustwallow Marsh
  { names: ['Blackmaw Hold'], zones: [1447] },                                // Azshara
  { names: ["Shaper's Terrace"], zones: [1449] },                             // Un'Goro Crater
];

const [install, product = 'wow_classic_beta'] = process.argv.slice(2);
if (!install) {
  console.log('Usage: node art\\dungeons.js "<World of Warcraft folder>" [product]');
  process.exit(1);
}
const game = new GameFiles(install, product);
const T = {};
// (Some of their rows are encrypted, for content not out yet: read as empty.)
for (const [name, [id, layout, definition]] of Object.entries(TABLES)) {
  T[name] = readTable(game.read(id, { zeroEncrypted: true }), layout, definition);
}
const maps = JSON.parse(fs.readFileSync(path.join(__dirname, 'maps.json'), 'utf8'));
const zones = maps.filter((m) => m.type === 3 && m.world);
const zoneNames = new Set(zones.map((m) => m.name));

// The zone a dungeon's entrance is in: the zone of the area outside named
// after it (Razorfen Kraul's is an area of the Barrens), else the zone whose
// shape holds the entrance (zoneShaped), else the zone map it's on (zoneAt).
const areaByID = new Map(T.AreaTable.map((a) => [a.ID, a]));
const zoneByArea = new Map(zones.filter((m) => m.areaID).map((m) => [m.areaID, m.uiMapID]));
// (Where the area outside isn't named after the dungeon.)
const OUTSIDE = { Scholomance: 'Caer Darrow' };
function zoneOf(continent, names, X, Y) {
  const bare = (n) => n.replace(/^The /, '');
  const wanted = new Set(names.map(bare).concat(names.filter((n) => OUTSIDE[n]).map((n) => OUTSIDE[n])));
  for (const a of T.AreaTable) {
    if (a.ContinentID !== continent || !wanted.has(bare(a.AreaName_lang || ''))) continue;
    let top = a;
    for (let i = 0; i < 6 && top.ParentAreaID && areaByID.has(top.ParentAreaID); i++) top = areaByID.get(top.ParentAreaID);
    if (zoneByArea.has(top.ID)) return zoneByArea.get(top.ID);
  }
  return zoneShaped(continent, X, Y) || zoneAt(continent, X, Y);
}

// The zone whose shape on its continent holds a place: its highlight (the
// glow the world map gives a zone you point at, art\worldmap.js) covers the
// zone map's rectangle, lit where the zone is and black elsewhere.
//   1. A city: a zone map with no glow of its own, under half the size of
//      another that holds the place (the Stockade's Stormwind City, in
//      Elwynn Forest's).
//   2. The zone lit brightest there.
//   3. Lit nowhere (Scholomance's island in Darrowmere Lake): the zone lit
//      nearest it.
const highlights = path.join(__dirname, 'export', 'worldmap', 'highlights');
const shapes = new Map();
const LIT = 8;
function shapeOf(m) {
  const file = path.join(highlights, m.uiMapID + '.png');
  if (!shapes.has(m.uiMapID)) shapes.set(m.uiMapID, fs.existsSync(file) ? decodePNG(fs.readFileSync(file)) : null);
  return shapes.get(m.uiMapID);
}
function zoneShaped(mapID, X, Y) {
  const holds = (w) => X >= w.minX && X <= w.maxX && Y >= w.minY && Y <= w.maxY;
  const size = (w) => (w.maxX - w.minX) * (w.maxY - w.minY);
  const here = zones.filter((z) => z.mapID === mapID && holds(z.world));
  const city = here.filter((m) => !shapeOf(m) && here.some((o) => o !== m && size(m.world) < size(o.world) / 2));
  if (city.length) return city[0].uiMapID;
  let best = null, bestLight = LIT, nearest = null, nearestYards = Infinity;
  for (const m of here) {
    const img = shapeOf(m);
    if (!img) continue;
    const w = m.world, u = (w.maxY - Y) / (w.maxY - w.minY), v = (w.maxX - X) / (w.maxX - w.minX);
    const light = (px, py) => {
      const at = (py * img.width + px) * 4;
      return Math.max(img.data[at], img.data[at + 1], img.data[at + 2]);
    };
    const px = Math.min(img.width - 1, Math.floor(u * img.width)), py = Math.min(img.height - 1, Math.floor(v * img.height));
    if (light(px, py) > bestLight) { best = m.uiMapID; bestLight = light(px, py); }
    const yardsX = (w.maxY - w.minY) / img.width, yardsY = (w.maxX - w.minX) / img.height;
    for (let y = 0; y < img.height; y++) {
      for (let x = 0; x < img.width; x++) {
        if (light(x, y) <= LIT) continue;
        const d = Math.hypot((x - px) * yardsX, (y - py) * yardsY);
        if (d < nearestYards) { nearest = m.uiMapID; nearestYards = d; }
      }
    }
  }
  return best || nearest;
}

// The zone map a place in the world is on: the smallest that holds it, or
// the nearest (Blackrock Mountain is between two).
function zoneAt(mapID, X, Y) {
  let best = null, bestScore = Infinity;
  for (const m of zones.filter((z) => z.mapID === mapID)) {
    const w = m.world;
    const dx = Math.max(w.minX - X, 0, X - w.maxX), dy = Math.max(w.minY - Y, 0, Y - w.maxY);
    const score = (dx || dy) ? 1e12 + dx * dx + dy * dy : (w.maxX - w.minX) * (w.maxY - w.minY);
    if (score < bestScore) { best = m; bestScore = score; }
  }
  return best && best.uiMapID;
}

const out = [];
const foreverLeft = FOREVER.slice();
for (const m of T.Map) {
  if (!m.ID || (m.InstanceType !== 1 && m.InstanceType !== 2) || /test|unused/i.test(m.MapName_lang)) continue;
  // The names you see inside: the map's top-level areas, but not the zones
  // or seas some dungeons' maps also hold.
  const inside = T.AreaTable.filter((a) => a.ContinentID === m.ID && !a.ParentAreaID).map((a) => a.AreaName_lang)
    .filter((n) => n && !zoneNames.has(n) && !/sea$|unused|\*/i.test(n));
  const names = [...new Set([m.MapName_lang, ...inside])];
  const entry = { id: m.ID, names };
  if (m.InstanceType === 2) entry.raid = true;
  const [X, Y] = m.Corpse;
  if (m.CorpseMapID >= 0 && (X || Y)) {
    entry.entrance = { mapID: m.CorpseMapID, X: Math.round(X * 10) / 10, Y: Math.round(Y * 10) / 10 };
    entry.zone = zoneOf(m.CorpseMapID, names, X, Y);
  } else {
    const own = foreverLeft.find((f) => f.names.some((n) => names.includes(n)));
    if (!own) continue;   // no way to place it (a test map, or a season's)
    foreverLeft.splice(foreverLeft.indexOf(own), 1);
    entry.names = [...new Set([...names, ...own.names])];
    entry.zones = own.zones;
  }
  out.push(entry);
}
for (const f of foreverLeft) out.push({ names: f.names, zones: f.zones });   // not in this build yet

fs.writeFileSync(path.join(__dirname, 'dungeons.json'), JSON.stringify(out, null, 1).replace(/\n\s+(?=[\]\d-])/g, ' ') + '\n');
console.log(`${game.build.Product} ${game.build.Version}: ${out.filter((d) => d.entrance).length} entrances,`,
  `${out.filter((d) => d.zones).length} of Forever's dungeons by zone -> art\\dungeons.json`);
for (const d of out) {
  console.log(` ${d.id || '-'} ${d.names.join(' / ')}${d.raid ? ' (raid)' : ''}: ` +
    (d.entrance ? `${d.zone ? (maps.find((m) => m.uiMapID === d.zone) || {}).name : '?'} at ${d.entrance.X}, ${d.entrance.Y}` : `in ${d.zones.join(', ')}`));
}
