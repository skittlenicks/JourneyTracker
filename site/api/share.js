'use strict';
// GET /j/<share ID>: the recap page for one shared journey. A rewrite in
// site/deploy.ps1 sends /j/<share ID> here as ?id=<share ID>. The answer is
// the site's own index.html (deploy.ps1 puts a copy next to this file) with
// the upload's export and its places among every saved journey (ranks.js)
// in it, for the page to show, and a title, description and preview image
// (card.js) of its own for link previews. The export never changes, but its
// places do as more journeys are saved, so Vercel's CDN keeps each page for
// an hour and then serves it while making a fresh one.

const fs = require('fs');
const path = require('path');
const { uuidOfShareId } = require('./decode');
const { supabase, journeyOf } = require('./ranks');
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
    const rows = await (await supabase('uploads?select=character_id,payload&limit=1&id=eq.' + uuid)).json();
    if (!rows.length) return send(res, 404, 'public, max-age=0, s-maxage=60', missing);
    const payload = rows[0].payload || {};
    delete payload.ranked;   // the page works out its own numbers
    const { journey: J, ranks, picks } = await journeyOf(payload, rows[0].character_id);
    const who = `${J.race} ${J.className}`.trim() || 'A journey';
    const across = J.path.length ? ` across ${J.path.length} zone${J.path.length === 1 ? '' : 's'}` : '';
    const best = picks[0];
    const meta = {
      title: `${who}, level ${J.level || '?'} · Journey Tracker`,
      description: `${JourneyModel.dur(J.played)} of /played${across}. ` +
        (best ? `${best.big} ${best.who}${best.cohort === 'All players' ? '' : ` among ${best.cohort}`}. ` : '') +
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
    return send(res, 200, cache, page({ id, payload, ranks }, meta));
  } catch (err) {
    console.error('share failed:', err.message);
    return send(res, 503, 'no-store', page({ error: true }));
  }
};
