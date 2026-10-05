'use strict';
// POST /api/upload: saves an export pasted on the website to Supabase's
// "uploads" table, the same way tools/import does: decoded and validated by
// tools/import/decode.js (site/deploy.ps1 puts a copy next to this file),
// skipped as a duplicate when that character's export from the same moment
// is already there. The journey's ranking profile goes with it, in
// payload.ranked (ranks.js). The secret key comes from the Vercel project's
// environment (SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY) and never leaves
// the server.
//
// Limits: the project's firewall lets each address make a few uploads an
// hour (see site/deploy.ps1), and once UPLOADS_PER_DAY new uploads (500
// unless the environment says otherwise) have come in over the last day,
// this stops taking new ones from anyone, so a flood can't fill the
// database. Duplicates don't count. A browser can only send one from the
// site's own pages (ORIGINS), so another site can't have its visitors'
// browsers send them.
//
// Request body: the export string ("JT1:..."), as text.
// Response: { status, message, share }: status is "saved", "duplicate",
// "rejected", "busy" or "error"; share is the upload's share ID, for its
// recap page at /j/<share>.

const { parseExport, shareIdOf } = require('./decode');
const { profileOf } = require('./ranks');

const MAX_BODY = 1024 * 1024; // characters; real exports are well under 200,000
const PER_DAY = Number(process.env.UPLOADS_PER_DAY) || 500;
// Pages that may upload: the site, its own previews on Vercel (project
// "journeytracker") and a copy run locally. A request without an Origin
// isn't from a page (tools, scripts).
const ORIGINS = [/^https:\/\/(www\.)?journeytracker\.dev$/, /^https:\/\/journeytracker(-[a-z0-9-]+)?\.vercel\.app$/,
  /^http:\/\/localhost(:\d+)?$/];

function reply(res, code, status, message, share) {
  res.statusCode = code;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.setHeader('Cache-Control', 'no-store');
  res.end(JSON.stringify(share ? { status, message, share } : { status, message }));
}

async function readBody(req) {
  if (typeof req.body === 'string') return req.body;
  if (Buffer.isBuffer(req.body)) return req.body.toString('utf8');
  if (req.body && typeof req.body.export === 'string') return req.body.export;
  let text = '';
  for await (const chunk of req) {
    text += chunk;
    if (text.length > MAX_BODY) break;
  }
  return text;
}

// One request to Supabase's REST API with the secret key. An answer that
// isn't OK throws, with its status as the error's.
async function supabase(path, options) {
  const url = process.env.SUPABASE_URL.replace(/\/+$/, '') + '/rest/v1/' + path;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  const response = await fetch(url, Object.assign({}, options, {
    headers: Object.assign({ apikey: key, Authorization: 'Bearer ' + key, 'Content-Type': 'application/json' },
      options && options.headers),
  }));
  if (!response.ok) throw Object.assign(new Error(`Supabase answered ${response.status}`), { status: response.status });
  return response;
}

// How many uploads came in over the last day, from everyone.
async function uploadsToday() {
  const since = new Date(Date.now() - 24 * 3600 * 1000).toISOString();
  const response = await supabase('uploads?select=id&limit=1&created_at=gte.' + encodeURIComponent(since),
    { headers: { Prefer: 'count=exact' } });
  return Number((response.headers.get('content-range') || '').split('/')[1]) || 0;
}

module.exports = async function upload(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return reply(res, 405, 'error', 'Send the export with POST.');
  }
  const origin = req.headers && req.headers.origin;
  if (origin && !ORIGINS.some((allowed) => allowed.test(origin))) {
    return reply(res, 403, 'rejected', 'Exports are saved from www.journeytracker.dev.');
  }
  if (!process.env.SUPABASE_URL || !process.env.SUPABASE_SERVICE_ROLE_KEY) {
    return reply(res, 500, 'error', "Saving isn't set up on this site yet.");
  }
  const text = (await readBody(req)).trim();
  if (text.length > MAX_BODY) return reply(res, 413, 'rejected', 'That export is too big to be real.');

  // An export that can't be read, or ranked (the numbers it's ranked on are
  // saved with it, see ranks.js), is turned away.
  let parsed;
  try {
    parsed = parseExport(text);
  } catch (err) {
    console.error('decode failed:', err.message);
    parsed = { ok: false, error: "That export couldn't be read." };
  }
  if (!parsed.ok) return reply(res, 400, 'rejected', parsed.error);
  const row = parsed.row;
  try {
    row.payload.ranked = profileOf(row.payload);
  } catch (err) {
    console.error('profile failed:', err.message);
    return reply(res, 400, 'rejected', "That export couldn't be read as a journey.");
  }

  try {
    const query = 'uploads?select=id&limit=1&character_id=eq.' + encodeURIComponent(row.character_id) +
      (row.exported_at ? '&exported_at=eq.' + encodeURIComponent(row.exported_at) : '&exported_at=is.null');
    const found = await (await supabase(query)).json();
    if (Array.isArray(found) && found.length) {
      return reply(res, 200, 'duplicate', 'This export was already saved.', shareIdOf(found[0].id));
    }
    if (await uploadsToday() >= PER_DAY) {
      return reply(res, 429, 'busy', 'Journey Tracker has taken all the uploads it can for today. Try again tomorrow.');
    }
    let saved;
    try {
      saved = await (await supabase('uploads?select=id', {
        method: 'POST', headers: { Prefer: 'return=representation' }, body: JSON.stringify(row),
      })).json();
    } catch (err) {
      // The same export, saved a moment ago by another request (the table
      // has one row per character and export time).
      if (err.status !== 409) throw err;
      const again = await (await supabase(query)).json();
      return reply(res, 200, 'duplicate', 'This export was already saved.', shareIdOf(again[0] && again[0].id));
    }
    return reply(res, 200, 'saved', 'Saved. It counts toward the rankings.', shareIdOf(saved[0] && saved[0].id));
  } catch (err) {
    console.error('upload failed:', err.message);
    return reply(res, 502, 'error', "Couldn't reach the database. Try again in a minute.");
  }
};
