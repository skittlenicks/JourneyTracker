'use strict';
// GET /j/<share ID>: the recap page for one shared journey. A rewrite in
// site/deploy.ps1 sends /j/<share ID> here as ?id=<share ID>. The answer is
// the site's own index.html (deploy.ps1 puts a copy next to this file) with
// the upload's export in it, for the page to show, and a title and
// description of its own for link previews. An upload never changes, so
// Vercel's CDN keeps each page for a day.

const fs = require('fs');
const path = require('path');
const { uuidOfShareId } = require('./decode');

const PAGE = fs.readFileSync(path.join(__dirname, 'index.html'), 'utf8');
const SITE = 'https://www.journeytracker.dev';
const CLASSES = { WARRIOR: 'Warrior', PALADIN: 'Paladin', HUNTER: 'Hunter', ROGUE: 'Rogue', PRIEST: 'Priest',
  SHAMAN: 'Shaman', MAGE: 'Mage', WARLOCK: 'Warlock', DRUID: 'Druid' };
const RACES = { NightElf: 'Night Elf', Scourge: 'Undead' };

function attr(text) {
  return String(text).replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}
// The addon's duration format: 6d 12h 40m, 2h 51m, 9m 36s.
function dur(seconds) {
  const s = Math.round(Number(seconds) || 0);
  const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
  if (d) return `${d}d ${h}h ${m}m`;
  if (h) return `${h}h ${m}m`;
  return `${m}m ${s % 60}s`;
}

// The page with `shared` in it for the page script (window.JT_SHARED) and,
// for a journey, its own title and description. Every replacement is a
// function, so nothing in the data can act as a "$" pattern, and "<" is
// escaped in the JSON so no string in it can end the script.
function page(shared, meta) {
  let html = PAGE;
  if (meta) {
    html = html
      .replace(/<title>[^<]*<\/title>/, () => `<title>${attr(meta.title)}</title>`)
      .replace(/(<meta name="description" content=")[^"]*/, (all, start) => start + attr(meta.description))
      .replace(/(<meta property="og:title" content=")[^"]*/, (all, start) => start + attr(meta.title))
      .replace(/(<meta property="og:description" content=")[^"]*/, (all, start) => start + attr(meta.description));
  }
  const data = JSON.stringify(shared).replace(/</g, '\\u003c').replace(/\u2028/g, '\\u2028').replace(/\u2029/g, '\\u2029');
  const head = (meta ? `<meta property="og:url" content="${attr(meta.url)}">\n` : '') +
    '<meta name="robots" content="noindex">\n' + `<script>window.JT_SHARED = ${data};</script>`;
  return html.replace('<!--JT_SHARED-->', () => head);
}

function send(res, code, cache, html) {
  res.statusCode = code;
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.setHeader('Cache-Control', cache);
  res.end(html);
}

module.exports = async function share(req, res) {
  const id = String((req.query && req.query.id) || new URL(req.url, SITE).searchParams.get('id') || '');
  const uuid = uuidOfShareId(id);
  const missing = page({ missing: true });
  if (!uuid) return send(res, 404, 'public, max-age=0, s-maxage=3600', missing);
  if (!process.env.SUPABASE_URL || !process.env.SUPABASE_SERVICE_ROLE_KEY) {
    return send(res, 503, 'no-store', page({ error: true }));
  }
  try {
    const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
    const response = await fetch(process.env.SUPABASE_URL.replace(/\/+$/, '') + '/rest/v1/uploads?select=payload&limit=1&id=eq.' + uuid,
      { headers: { apikey: key, Authorization: 'Bearer ' + key } });
    if (!response.ok) throw new Error(`Supabase answered ${response.status}`);
    const rows = await response.json();
    if (!rows.length) return send(res, 404, 'public, max-age=0, s-maxage=60', missing);
    const payload = rows[0].payload || {}, c = payload.character || {};
    const name = (map, key) => (Object.prototype.hasOwnProperty.call(map, key) ? map[key] : null);
    const race = name(RACES, c.race) || String(c.race || '').replace(/([a-z])([A-Z])/g, '$1 $2');
    const who = `${race} ${name(CLASSES, c.class) || ''}`.trim() || 'A journey';
    const path = Array.isArray((payload.stats || {}).path) ? payload.stats.path : [];
    const zones = new Set(path.map((p) => p && p.zone).filter((z) => typeof z === 'string' && z !== 'Unknown'));
    const across = zones.size ? ` across ${zones.size} zone${zones.size === 1 ? '' : 's'}` : '';
    const meta = {
      title: `${who}, level ${Number(c.level) || '?'} · Journey Tracker`,
      description: `${dur(c.played)} of /played${across}: the route, the deaths, the quests and where this journey ranks.`,
      url: `${SITE}/j/${id}`,
    };
    return send(res, 200, 'public, max-age=300, s-maxage=86400, stale-while-revalidate=604800',
      page({ id, payload }, meta));
  } catch (err) {
    console.error('share failed:', err.message);
    return send(res, 503, 'no-store', page({ error: true }));
  }
};
