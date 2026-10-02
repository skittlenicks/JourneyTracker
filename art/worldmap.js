'use strict';
// The game's own world map, read straight from a WoW Forever install, for the
// website's map of a journey:
//
//   art\export\worldmap\<UiMapID>.png              the world (947), Kalimdor
//                                                  (1414) and the Eastern
//                                                  Kingdoms (1415), 1002x668
//   art\export\worldmap\highlights\<UiMapID>.png   each zone's glow when you
//                                                  point at it on its continent
//   art\worldmap.json                              where each zone's glow is
//                                                  brightest (its middle)
//
// Forever has art of its own for these (newer files than Classic's), so the
// art is found the way the game finds it: UiMapXMapArt names each map's art,
// UiMapArtTile its 256px tiles (4 across, 3 down) and UiMapArt the zone's
// highlight. A highlight uses the top-left of its texture, shaped like the
// zone map's rectangle on the continent (its longer side spans the whole
// texture), stretched over that rectangle; the PNGs here are cropped to that
// part, so they fit the rectangle as they are. Zone rectangles come from
// art\maps.json (art\build-maps.ps1).
//
//   node art\worldmap.js "<World of Warcraft folder>" [product]
//
// product defaults to wow_classic_beta (WoW Forever). Like the rest of
// art\export, the PNGs are Blizzard's art and stay out of git.

const fs = require('fs');
const path = require('path');
const { GameFiles, readTable, decodeBLP, encodePNG } = require('./game-files');

// The map tables by FileDataID, with their layouts as of Forever 1.60.1
// (WoWDBDefs notation; a changed layout stops the script instead of
// misreading).
const TABLES = {
  UiMapXMapArt: [1957217, 0xEAE7DA2A, `
    $noninline,id$ID<32>
    PhaseID<32>
    UiMapArtID<32>
    $noninline,relation$UiMapID<32>`],
  UiMapArt: [1957202, 0x3AE7D144, `
    $noninline,id$ID<32>
    HighlightFileDataID<32>
    HighlightAtlasID<32>
    UiMapArtStyleID<32>`],
  UiMapArtTile: [1957210, 0x2DA5B77B, `
    $noninline,id$ID<32>
    RowIndex<u8>
    ColIndex<u8>
    LayerIndex<u8>
    FileDataID<32>
    $noninline,relation$UiMapArtID<32>`],
  UiMapArtStyleLayer: [1957208, 0x3F597F5A, `
    $noninline,id$ID<32>
    LayerIndex<u8>
    LayerWidth<u16>
    LayerHeight<u16>
    TileWidth<u16>
    TileHeight<u16>
    MinScale float
    MaxScale float
    AdditionalZoomSteps<32>
    $noninline,relation$UiMapArtStyleID<32>`],
};
const WORLD = 947, CONTINENTS = [1414, 1415];

const [install, product = 'wow_classic_beta'] = process.argv.slice(2);
if (!install) {
  console.log('Usage: node art\\worldmap.js "<World of Warcraft folder>" [product]');
  process.exit(1);
}
const out = path.join(__dirname, 'export', 'worldmap');
fs.mkdirSync(path.join(out, 'highlights'), { recursive: true });

const started = Date.now();
const game = new GameFiles(install, product);
console.log(`${game.build.Product} ${game.build.Version}: game files opened (${((Date.now() - started) / 1000).toFixed(1)}s)`);
const T = {};
for (const [name, [id, layout, definition]] of Object.entries(TABLES)) T[name] = readTable(game.read(id), layout, definition);
const maps = JSON.parse(fs.readFileSync(path.join(__dirname, 'maps.json'), 'utf8'));
const byId = new Map(maps.map((m) => [m.uiMapID, m]));

function artOf(uiMapID) {
  const link = T.UiMapXMapArt.find((r) => r.UiMapID === uiMapID && r.PhaseID === 0);
  return link && T.UiMapArt.find((a) => a.ID === link.UiMapArtID);
}

// A map's art, its tiles put together.
function stitch(uiMapID) {
  const art = artOf(uiMapID);
  const layer = T.UiMapArtStyleLayer.find((l) => l.UiMapArtStyleID === art.UiMapArtStyleID && l.LayerIndex === 0);
  const W = layer.LayerWidth, H = layer.LayerHeight, img = { width: W, height: H, data: Buffer.alloc(W * H * 4) };
  for (const t of T.UiMapArtTile.filter((t) => t.UiMapArtID === art.ID && t.LayerIndex === 0)) {
    const tile = decodeBLP(game.read(t.FileDataID));
    const x0 = t.ColIndex * layer.TileWidth, y0 = t.RowIndex * layer.TileHeight, n = Math.min(tile.width, W - x0);
    for (let y = 0; y < tile.height && y0 + y < H && n > 0; y++) {
      tile.data.copy(img.data, ((y0 + y) * W + x0) * 4, y * tile.width * 4, (y * tile.width + n) * 4);
    }
  }
  fs.writeFileSync(path.join(out, uiMapID + '.png'), encodePNG(img));
  return img;
}

// A zone's map rectangle on its continent, from 0 to 1 across and down.
function rectOn(continent, zone) {
  const c = continent.world, z = zone.world;
  return [(c.maxY - z.maxY) / (c.maxY - c.minY), (c.maxX - z.maxX) / (c.maxX - c.minX),
          (c.maxY - z.minY) / (c.maxY - c.minY), (c.maxX - z.minX) / (c.maxX - c.minX)];
}

const result = { build: `${game.build.Product} ${game.build.Version}`, art: [WORLD].concat(CONTINENTS), zones: {} };
const round = (v) => Math.round(v * 10000) / 10000;
for (const id of result.art) stitch(id);
for (const continentID of CONTINENTS) {
  const continent = byId.get(continentID), art = stitch(continentID);
  for (const zone of maps.filter((m) => m.parent === continentID && m.world && m.mapID === continent.mapID)) {
    const za = artOf(zone.uiMapID);
    if (!za || !za.HighlightFileDataID) continue;
    const [l, t, r, b] = rectOn(continent, zone);
    const w = (r - l) * art.width, h = (b - t) * art.height, longer = Math.max(w, h);
    const tex = decodeBLP(game.read(za.HighlightFileDataID));
    const cw = Math.max(1, Math.round(tex.width * w / longer)), ch = Math.max(1, Math.round(tex.height * h / longer));
    const crop = { width: cw, height: ch, data: Buffer.alloc(cw * ch * 4) };
    for (let y = 0; y < ch; y++) tex.data.copy(crop.data, y * cw * 4, y * tex.width * 4, (y * tex.width + cw) * 4);
    // Glows are drawn added to the map, so black is nothing: opaque, with
    // the glow in the color channels. Its middle: the brightest third,
    // weighted by brightness.
    let peak = 0;
    for (let i = 0; i < cw * ch; i++) peak = Math.max(peak, crop.data[i * 4], crop.data[i * 4 + 1], crop.data[i * 4 + 2]);
    let sx = 0, sy = 0, sw = 0;
    for (let y = 0; y < ch; y++) {
      for (let x = 0; x < cw; x++) {
        const o = (y * cw + x) * 4, v = Math.max(crop.data[o], crop.data[o + 1], crop.data[o + 2]);
        crop.data[o + 3] = 255;
        if (v > peak / 3) { sx += (x + 0.5) * v; sy += (y + 0.5) * v; sw += v; }
      }
    }
    fs.writeFileSync(path.join(out, 'highlights', zone.uiMapID + '.png'), encodePNG(crop));
    result.zones[zone.uiMapID] = { continent: continentID,
      center: [round(l + (sx / sw / cw) * (r - l)), round(t + (sy / sw / ch) * (b - t))] };
  }
}
const zoneLines = Object.entries(result.zones).map(([id, z]) => `    "${id}": ${JSON.stringify(z).replace(/,/g, ', ').replace(/:/g, ': ')}`);
fs.writeFileSync(path.join(__dirname, 'worldmap.json'), `{\n  "build": ${JSON.stringify(result.build)},\n  "art": [${result.art.join(', ')}],\n` +
  `  "zones": {\n${zoneLines.join(',\n')}\n  }\n}\n`);
console.log(`Wrote ${result.art.length} maps and ${Object.keys(result.zones).length} zone highlights to ${out}, and art\\worldmap.json ` +
  `(${((Date.now() - started) / 1000).toFixed(1)}s)`);
