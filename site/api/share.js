'use strict';
// GET /j/<share ID>: the recap page for one shared journey. A rewrite in
// site/deploy.ps1 sends /j/<share ID> here as ?id=<share ID>. The answer is
// the site's own index.html (deploy.ps1 puts a copy next to this file) with
// the upload's export, its places among the saved journeys at its milestone
// (ranks.js) and links to the same character's other journeys in it, for
// the page to show, and a title, description and preview image (card.js)
// of its own for link previews. The export never changes, but its places
// do as more journeys are saved, so Vercel's CDN keeps each page for an
// hour and then serves it while making a fresh one.

const fs = require('fs');
const path = require('path');
const { uuidOfShareId, shareIdOf } = require('./decode');
const { supabase, journeyOf, closest } = require('./ranks');
const JourneyModel = require('./model');

const PAGE = fs.readFileSync(path.join(__dirname, 'index.html'), 'utf8');
const SITE = 'https://www.journeytracker.dev';

function attr(text) {
  return String(text).replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

// The page with `shared` in it for the page script (window.JT_SHARED) and,
// for a journey, its own title, description and preview image. Every
// replacement is a function, so nothing in the data can act as a "$"
// pattern, and "<" is escaped in the JSON so no string in it can end the
// script.
function page(shared, meta) {
  let html = PAGE;
  if (meta) {
    html = html
      .replace(/<title>[^<]*<\/title>/, () => `<title>${attr(meta.title)}</title>`)
      .replace(/(<meta name="description" content=")[^"]*/, (all, start) => start + attr(meta.description))
      .replace(/(<meta property="og:title" content=")[^"]*/, (all, start) => start + attr(meta.title))
      .replace(/(<meta property="og:description" content=")[^"]*/, (all, start) => start + attr(meta.description))
      .replace(/(<meta property="og:image" content=")[^"]*/, (all, start) => start + attr(meta.image))
      .replace(/(<meta property="og:image:alt" content=")[^"]*/, (all, start) => start + attr(meta.imageAlt));
  }
  const data = JSON.stringify(shared).replace(/</g, '\\u003c').replace(/\u2028/g, '\\u2028').replace(/\u2029/g, '\\u2029');
  const head = (meta ? `<meta property="og:url" content="${attr(meta.url)}">\n` : '') +
    '<meta name="robots" content="noindex">\n' + `<script>window.JT_SHARED = ${data};</script>`;
  return html.replace('<!--JT_SHARED-->', () => head);
}

// The character's journeys to link between: this one, its upload closest
// to each milestone (ranks.js) and its latest, lowest level first.
// [{ level, share, here }], or none when this is its only one.
async function journeysOf(upload) {
  const rows = await (await supabase('uploads?select=id,level,exported_at&order=exported_at.desc.nullslast&limit=500' +
    '&character_id=eq.' + encodeURIComponent(upload.character_id))).json();
  const keep = new Map([[upload.id, upload]]), best = new Map();
  rows.forEach((r) => {
    const m = JourneyModel.milestoneOf(r.level), was = best.get(m);
    if (!was || closest(r, was) < 0) best.set(m, r);
  });
  best.forEach((r) => keep.set(r.id, r));
  if (rows[0]) keep.set(rows[0].id, rows[0]);
  if (keep.size < 2) return [];
  return [...keep.values()]
    .sort((a, b) => a.level - b.level || String(a.exported_at || '').localeCompare(String(b.exported_at || '')))
    .map((r) => ({ level: r.level, share: shareIdOf(r.id), here: r.id === upload.id }));
}

function days(n) { return `${n} day${n === 1 ? '' : 's'}`; }

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
    const rows = await (await supabase('uploads?select=id,character_id,level,exported_at,payload&limit=1&id=eq.' +
      uuid)).json();
    if (!rows.length) return send(res, 404, 'public, max-age=0, s-maxage=60', missing);
    const upload = rows[0], payload = upload.payload || {};
    delete payload.ranked;   // the page works out its own numbers
    delete upload.payload;
    const [{ journey: J, ranks, picks }, journeys] = await Promise.all([journeyOf(payload, upload.character_id),
      journeysOf(upload).catch((err) => { console.error('journeys failed:', err.message); return []; })]);
    const who = `${J.race} ${J.className}`.trim() || 'A journey';
    const across = J.path.length ? ` across ${J.path.length} zone${J.path.length === 1 ? '' : 's'}` : '';
    const best = picks[0];
    // At a milestone, the time it took to get there: "Level 30 in 12 days,
    // 1d 4h /played" (the days when the tracker saw the start).
    const reached = J.atMilestone && J.milestone && J.playedTo;
    const meta = {
      title: (reached ? `${who}: the road to ${J.milestone}` : `${who}, level ${J.level || '?'}`) + ' · Journey Tracker',
      description: (reached ? `Level ${J.milestone} in ${J.daysTo ? days(J.daysTo) + ', ' : ''}` +
        `${JourneyModel.dur(J.playedTo)} /played${across}. ` : `${JourneyModel.dur(J.played)} of /played${across}. `) +
        (best ? `${best.big} ${best.who}${best.cohort === 'All players' ? '' :
          ` among ${best.cohort.replace(/^Level /, 'level ')}`}. ` : '') +
        'The route, the deaths, the quests and where this journey ranks.',
      url: `${SITE}/j/${id}`,
      image: `${SITE}/j/${id}/card.png`,
      imageAlt: `Journey Tracker card: ${who}, level ${J.level || '?'}` +
        (best ? `, ${best.big} ${best.who}` : '') + '.',
    };
    // Places go stale as journeys come in: an hour at the CDN, or a minute
    // when they couldn't be worked out.
    const cache = ranks.error ? 'public, max-age=0, s-maxage=60' :
      'public, max-age=300, s-maxage=3600, stale-while-revalidate=86400';
    return send(res, 200, cache, page({ id, payload, ranks, journeys }, meta));
  } catch (err) {
    console.error('share failed:', err.message);
    return send(res, 503, 'no-store', page({ error: true }));
  }
};
