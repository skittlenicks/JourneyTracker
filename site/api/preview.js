'use strict';
// Link preview images, 1200x630: a journey's card for its share page
// (card.js serves it as /j/<share ID>/card.png) and the site's own
// (build.ps1 saves it as /og.png). Each is drawn here as SVG and turned into
// a PNG by resvg, compiled to WebAssembly, with the page's own fonts
// (site/fonts, all under the SIL Open Font License; their licenses are next
// to them). Text is measured with the fonts' own glyph widths, so it wraps
// and shortens where the page would.
//
//   node preview.js <out.png> [<logo.png>]    the site's own image

const fs = require('fs');
const path = require('path');
const { Resvg, initWasm } = require('@resvg/resvg-wasm');

const W = 1200, H = 630;
// The page's colors (site/recap.template.html).
const C = { ground: '#120e09', panel: '#1b150e', rule: '#3b2d1b', ink: '#ece3cf', soft: '#b3a386',
  gold: '#f2b234', pale: '#ffe9a3', deep: '#c4660a', glow: '#2b2014', box: '#231a10' };
// site/fonts, or a function's own copy (site/deploy.ps1).
const FONTS = [path.join(__dirname, 'fonts'), path.join(__dirname, '..', 'fonts')].find((dir) => fs.existsSync(dir));
const FACES = {   // family, weight, style, file
  display: ['Marcellus', 400, 'normal', 'Marcellus-Regular.ttf'],
  body: ['Alegreya Sans', 400, 'normal', 'AlegreyaSans-Regular.ttf'],
  bodyMedium: ['Alegreya Sans', 500, 'normal', 'AlegreyaSans-Medium.ttf'],
  mono: ['IBM Plex Mono', 500, 'normal', 'IBMPlexMono-Medium.ttf'],
};

// ---- Glyph widths, from a TrueType font's head, hhea, hmtx and cmap tables ----
function metricsOf(buf) {
  const tables = {};
  for (let i = 0, n = buf.readUInt16BE(4); i < n; i++) {
    const at = 12 + 16 * i;
    tables[buf.toString('latin1', at, at + 4)] = buf.readUInt32BE(at + 8);
  }
  const unitsPerEm = buf.readUInt16BE(tables.head + 18);
  const longMetrics = buf.readUInt16BE(tables.hhea + 34);
  const advance = (glyph) => buf.readUInt16BE(tables.hmtx + 4 * Math.min(glyph, longMetrics - 1));
  // The Unicode character map (format 4: the Basic Multilingual Plane).
  let map = null;
  for (let i = 0, n = buf.readUInt16BE(tables.cmap + 2); i < n; i++) {
    const rec = tables.cmap + 4 + 8 * i, platform = buf.readUInt16BE(rec), encoding = buf.readUInt16BE(rec + 2);
    const sub = tables.cmap + buf.readUInt32BE(rec + 4);
    if (buf.readUInt16BE(sub) === 4 && (platform === 0 || (platform === 3 && encoding === 1))) { map = sub; break; }
  }
  const segs = buf.readUInt16BE(map + 6) / 2, ends = map + 14, starts = ends + 2 * segs + 2;
  const deltas = starts + 2 * segs, offsets = deltas + 2 * segs;
  function glyphOf(code) {
    for (let s = 0; s < segs; s++) {
      if (buf.readUInt16BE(ends + 2 * s) < code) continue;
      const start = buf.readUInt16BE(starts + 2 * s);
      if (start > code) return 0;
      const delta = buf.readUInt16BE(deltas + 2 * s), offset = buf.readUInt16BE(offsets + 2 * s);
      if (!offset) return (code + delta) & 0xffff;
      const g = buf.readUInt16BE(offsets + 2 * s + offset + 2 * (code - start));
      return g ? (g + delta) & 0xffff : 0;
    }
    return 0;
  }
  const cache = new Map();
  return function width(text, size) {
    let units = 0;
    for (const ch of text) {
      const code = ch.codePointAt(0);
      if (!cache.has(code)) cache.set(code, advance(code > 0xffff ? 0 : glyphOf(code)));
      units += cache.get(code);
    }
    return units / unitsPerEm * size;
  };
}

let ready = null;   // the fonts and resvg, once
function start() {
  if (!ready) {
    const fonts = {}, buffers = [];
    for (const [key, face] of Object.entries(FACES)) {
      const buf = fs.readFileSync(path.join(FONTS, face[3]));
      fonts[key] = { face, width: metricsOf(buf) };
      buffers.push(buf);
    }
    const wasm = fs.readFileSync(path.join(path.dirname(require.resolve('@resvg/resvg-wasm')), 'index_bg.wasm'));
    ready = initWasm(wasm).then(() => ({ fonts, buffers }));
  }
  return ready;
}

function xml(text) {
  return String(text).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);
}

// Drawing helpers, given the loaded fonts.
function painter(fonts) {
  // Text that fits in `max` px: as many lines as it takes (up to `lines`),
  // the last cut short with an ellipsis if it still doesn't fit.
  function wrap(text, font, size, max, lines, spacing) {
    const f = fonts[font], fits = (s) => f.width(s, size) + (spacing || 0) * s.length <= max;
    const out = [];
    let words = String(text).split(/\s+/).filter(Boolean);
    while (words.length && out.length < lines) {
      let line = words[0], used = 1;
      while (used < words.length && fits(line + ' ' + words[used])) line += ' ' + words[used++];
      words = words.slice(used);
      if (out.length === lines - 1 && words.length) line += ' ' + words.join(' ');
      if (!fits(line)) {
        while (line.length > 1 && !fits(line + '…')) line = line.slice(0, -1).trimEnd();
        line += '…';
        words = [];
      }
      out.push(line);
    }
    return out;
  }
  // <text> for one or more lines, `gap` px apart.
  function text(lines, x, y, font, size, fill, opts) {
    const o = opts || {}, f = fonts[font].face;
    const attrs = `font-family="${f[0]}" font-weight="${f[1]}" font-style="${f[2]}" font-size="${size}" fill="${fill}"` +
      (o.spacing ? ` letter-spacing="${o.spacing}"` : '') + (o.anchor ? ` text-anchor="${o.anchor}"` : '');
    return [].concat(lines).map((line, i) =>
      `<text x="${x}" y="${y + i * (o.gap || size * 1.2)}" ${attrs}>${xml(line)}</text>`).join('');
  }
  return { wrap, text, width: (s, font, size) => fonts[font].width(s, size) };
}

// The frame every card shares: the page's dark ground, a warm glow from the
// top, the gold border and the footer.
function frame(inner, logo) {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">` +
    '<defs><radialGradient id="glow" cx="50%" cy="0%" r="85%"><stop offset="0" stop-color="' + C.glow + '"/>' +
    `<stop offset="0.7" stop-color="${C.panel}"/><stop offset="1" stop-color="${C.panel}"/></radialGradient>` +
    '<clipPath id="round"><circle cx="112" cy="112" r="52"/></clipPath></defs>' +
    `<rect width="${W}" height="${H}" fill="${C.ground}"/>` +
    `<rect x="14" y="14" width="${W - 28}" height="${H - 28}" rx="22" fill="none" stroke="${C.rule}" stroke-width="2"/>` +
    `<rect x="24" y="24" width="${W - 48}" height="${H - 48}" rx="16" fill="url(#glow)" stroke="${C.gold}" stroke-width="2"/>` +
    (logo ? `<image href="data:image/png;base64,${logo.toString('base64')}" x="60" y="60" width="104" height="104" clip-path="url(#round)"/>` : '') +
    inner + '</svg>';
}
function footer(p) {
  return `<line x1="64" y1="556" x2="${W - 64}" y2="556" stroke="${C.rule}" stroke-width="2"/>` +
    p.text('JOURNEY TRACKER · WOW FOREVER', 64, 590, 'mono', 19, C.deep, { spacing: 2 }) +
    p.text('WWW.JOURNEYTRACKER.DEV', W - 64, 590, 'mono', 19, C.deep, { spacing: 2, anchor: 'end' });
}
// Three boxes across the middle, each drawn by `draw(x, y, w, h)`.
function boxes(count, draw) {
  const gap = 24, w = (W - 128 - gap * (count - 1)) / count, y = 256, h = 272;
  let out = '';
  for (let i = 0; i < count; i++) {
    const x = 64 + i * (w + gap);
    out += `<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="12" fill="${C.box}" stroke="${C.rule}" stroke-width="2"/>` +
      draw(x, y, w, h, i);
  }
  return out;
}

// A journey's card: who, level and time played, then its three best
// places (or, before it has any, its headline numbers).
//   { who, level, played, ranks: [{ big, who, detail, cohort }], stats: [[label, value]] }
async function journeyCard(card, logo) {
  const { fonts, buffers } = await start(), p = painter(fonts);
  let inner = p.text(p.wrap(card.who.toUpperCase(), 'mono', 22, 900, 1, 2), 196, 92, 'mono', 22, C.soft, { spacing: 2 }) +
    p.text(`Level ${card.level}`, 194, 170, 'display', 76, C.gold) +
    p.text(p.wrap(card.played, 'body', 30, 940, 1), 196, 214, 'body', 30, C.soft);
  if (card.ranks.length) {
    inner += boxes(card.ranks.length === 2 ? 2 : 3, (x, y, w, h, i) => {
      const r = card.ranks[i];
      if (!r) return '';
      const pad = 26, inside = w - 2 * pad;
      const cohort = p.wrap(r.cohort.toUpperCase(), 'mono', 15, inside, 1, 1.5);
      const who = p.wrap(r.who, 'bodyMedium', 28, inside, 2);
      const detail = p.wrap(r.detail.charAt(0).toUpperCase() + r.detail.slice(1), 'body', 23, inside, 2);
      return p.text(cohort, x + pad, y + 42, 'mono', 15, C.soft, { spacing: 1.5 }) +
        p.text(p.wrap(r.big, 'display', 60, inside, 1), x + pad, y + 102, 'display', 60, C.gold) +
        p.text(who, x + pad, y + 144, 'bodyMedium', 28, C.ink, { gap: 33 }) +
        p.text(detail, x + pad, y + h - 28 - (detail.length - 1) * 28, 'body', 23, C.soft, { gap: 28 });
    });
  } else {
    inner += boxes(Math.min(3, card.stats.length), (x, y, w, h, i) => {
      const s = card.stats[i];
      return p.text(p.wrap(s[1], 'display', 72, w - 52, 1), x + 26, y + 146, 'display', 72, C.gold) +
        p.text(p.wrap(s[0], 'body', 30, w - 52, 1), x + 26, y + 194, 'body', 30, C.soft);
    });
  }
  return render(frame(inner + footer(p), logo), buffers);
}

// The site's own card, for the home page.
async function siteCard(logo) {
  const { fonts, buffers } = await start(), p = painter(fonts);
  const FEATURES = [
    ['The road', 'Every zone in the order you reached it, on the map of Azeroth.'],
    ['Every death', 'Where it happened, what did it, and the run you went without one.'],
    ['Your place', 'Ranked against every other saved journey, stat by stat.'],
  ];
  const inner = p.text('A WOW FOREVER ADDON', 196, 92, 'mono', 22, C.soft, { spacing: 2 }) +
    p.text('Your road to 60', 194, 170, 'display', 76, C.pale) +
    p.text(p.wrap('It records the climb from level 1 to 60. Paste its export for the recap.', 'body', 30, 940, 1),
      196, 214, 'body', 30, C.soft) +
    boxes(3, (x, y, w, h, i) => p.text(FEATURES[i][0], x + 26, y + 78, 'display', 44, C.gold) +
      p.text(p.wrap(FEATURES[i][1], 'body', 28, w - 52, 3), x + 26, y + 130, 'body', 28, C.ink, { gap: 34 })) +
    footer(p);
  return render(frame(inner, logo), buffers);
}

function render(svg, fontBuffers) {
  const resvg = new Resvg(svg, { fitTo: { mode: 'original' }, font: { fontBuffers, defaultFontFamily: 'Alegreya Sans' } });
  return Buffer.from(resvg.render().asPng());
}

module.exports = { journeyCard, siteCard, W, H };

if (require.main === module) {
  const [out, logoFile] = process.argv.slice(2);
  siteCard(logoFile ? fs.readFileSync(logoFile) : null).then((png) => {
    fs.writeFileSync(out, png);
    console.log(`Wrote ${out} (${Math.round(png.length / 1024)} KB)`);
  }, (err) => { console.error(err); process.exit(1); });
}
