'use strict';
// POST /api/upload: saves an export pasted on the website to Supabase's
// "uploads" table, the same way tools/import does: decoded and validated by
// tools/import/decode.js (site/deploy.ps1 puts a copy next to this file),
// skipped as a duplicate when that character's export from the same moment
// is already there. The journey's ranking profile and summary go with it,
// in payload.ranked and payload.summary (ranks.js). The secret key comes
// from the Vercel project's environment (SUPABASE_URL,
// SUPABASE_SERVICE_ROLE_KEY) and never leaves the server.
//
// A character's saves all go to its one page (character.js): the answer
// has the character's link and the path to the saved journey there, the
// link itself for its latest or /j/<link>/<level> for one at a level below.
//
// Limits: a character can be saved once every 30 minutes (EVERY), and its
// saved milestones (the addon's "At 30" exports) go through any time, once
// each, so a level-up's pop-up is never turned away. The project's firewall
// lets each address make a few uploads an hour (see site/deploy.ps1), and
// once UPLOADS_PER_DAY new uploads (500 unless the environment says
// otherwise) have come in over the last day, this stops taking new ones
// from anyone, so a flood can't fill the database. Duplicates don't count. A
// browser can only send one from the site's own pages (ORIGINS), so another
// site can't have its visitors' browsers send them.
//
// Request body: the export string ("JT1:..."), as text.
// Response: { status, message, share, path }: status is "saved",
// "duplicate", "wait", "rejected", "busy" or "error"; share is the
// character's link (a share ID) and path the page of the saved journey. A
// "wait" has the path of the character's page but no share, since nothing
// was saved.

const { parseExport } = require('./decode');
const { analyze } = require('./ranks');
const { uploadsOf, characterFrom, isMilestone } = require('./character');
const JourneyModel = require('./model');

const MAX_BODY = 1024 * 1024; // characters; real exports are well under 200,000
const PER_DAY = Number(process.env.UPLOADS_PER_DAY) || 500;
const EVERY = 30 * 60 * 1000; // ms between a character's saves
// Pages that may upload: the site, its own previews on Vercel (project
// "journeytracker") and a copy run locally. A request without an Origin
// isn't from a page (tools, scripts).
const ORIGINS = [/^https:\/\/(www\.)?journeytracker\.dev$/, /^https:\/\/journeytracker(-[a-z0-9-]+)?\.vercel\.app$/,
  /^http:\/\/localhost(:\d+)?$/];

function reply(res, code, status, message, more) {
  res.statusCode = code;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.setHeader('Cache-Control', 'no-store');
  res.end(JSON.stringify(Object.assign({ status, message }, more)));
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

// What a save says: the level it's ranked at (as you were there, for one
// exported past it), and the milestones up to it that the addon saw you
// reach but no journey here is ranked on everything at: its saved "At 20",
// or one exported at 20 that isn't late (site/model.js's rankedWhole).
// Each one pasted ranks you there.
function savedMessage(row, rows) {
  const m = JourneyModel.milestoneOf(row.level);
  if (m < 10) return 'Saved. Rankings start at level 10: the addon saves your journey as you reach it, ready to paste.';
  const whole = (r) => r.level % 10 === 0 && (isMilestone(r) || !r.late);
  const dings = (row.payload.levels && row.payload.levels.snapshots) || {};
  const missing = [];
  for (let l = 10; l <= m; l += 10) {
    if (!rows.some((r) => r.level === l && whole(r)) && (dings[l] || dings[String(l)])) missing.push(l);
  }
  let text = row.level === m && whole(rows[rows.length - 1]) ? `Saved. It's ranked among level ${m} journeys.` :
    `Saved. It's ranked as you were at level ${m}, among level ${m} journeys.`;
  if (missing.length) {
    const names = missing.map((l) => `“At ${l}”`);
    const list = names.length === 1 ? names[0] : names.slice(0, -1).join(', ') + ' and ' + names[names.length - 1];
    text += ` Paste ${list} from the addon's Export window too, to be ranked on everything at ` +
      (missing.length === 1 ? `level ${missing[0]}.` : 'those levels.');
  }
  return text;
}

// "12 minutes", rounded down (for how long ago) or up (for how long to wait).
function minutes(ms, up) {
  const n = Math.max(1, up ? Math.ceil(ms / 60000) : Math.floor(ms / 60000));
  return `${n} minute${n === 1 ? '' : 's'}`;
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
    Object.assign(row.payload, analyze(row.payload));
  } catch (err) {
    console.error('profile failed:', err.message);
    return reply(res, 400, 'rejected', "That export couldn't be read as a journey.");
  }

  try {
    let rows = await uploadsOf(row.character_id);
    // The same export: the character's from the same moment (or, without a
    // time, any other without one).
    const at = row.exported_at ? Date.parse(row.exported_at) : null;
    const sameExport = (r) => (at === null ? r.exported_at == null : Date.parse(r.exported_at) === at);
    const answer = (status, message, saved) => {
      const character = characterFrom(row.character_id, rows);
      return reply(res, 200, status, message, { share: character.link,
        path: character.pathOf(saved || character.latest) });
    };
    const duplicate = rows.find(sameExport);
    if (duplicate) return answer('duplicate', 'This export was already saved.', duplicate);

    const milestone = isMilestone({ level: row.level, milestone: row.payload.milestone }) &&
      !rows.some((r) => r.level === row.level && isMilestone(r));
    const last = rows.filter((r) => !isMilestone(r)).reduce((t, r) => Math.max(t, Date.parse(r.created_at) || 0), 0);
    const wait = last + EVERY - Date.now();
    if (!milestone && wait > 0) {
      const ago = Date.now() - last, character = characterFrom(row.character_id, rows);
      return reply(res, 429, 'wait', `This character was saved ${ago < 60000 ? 'a moment' : minutes(ago)} ago, ` +
        `and a character can be saved once every 30 minutes. Try again in ${minutes(wait, true)}.`,
      { path: character.pathOf(character.latest) });
    }
    if (await uploadsToday() >= PER_DAY) {
      return reply(res, 429, 'busy', 'Journey Tracker has taken all the uploads it can for today. Try again tomorrow.');
    }
    let saved;
    try {
      saved = await (await supabase('uploads?select=id,created_at', {
        method: 'POST', headers: { Prefer: 'return=representation' }, body: JSON.stringify(row),
      })).json();
    } catch (err) {
      // The same export, saved a moment ago by another request (the table
      // has one row per character and export time).
      if (err.status !== 409) throw err;
      rows = await uploadsOf(row.character_id);
      return answer('duplicate', 'This export was already saved.', rows.find(sameExport));
    }
    const mine = { id: saved[0] && saved[0].id, level: row.level, exported_at: row.exported_at,
      created_at: (saved[0] && saved[0].created_at) || new Date().toISOString(), milestone: row.payload.milestone,
      since: row.payload.ranked && row.payload.ranked.since, late: row.payload.ranked && row.payload.ranked.late };
    rows.push(mine);
    return answer('saved', savedMessage(row, rows), mine);
  } catch (err) {
    console.error('upload failed:', err.message);
    return reply(res, 502, 'error', "Couldn't reach the database. Try again in a minute.");
  }
};
