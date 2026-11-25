'use strict';
// Where a saved journey places among everyone's, for its share page
// (share.js) and its preview image (card.js). Journeys are ranked within
// their milestone, every ten levels (site/model.js's milestoneOf): a level
// 34 journey among the level 30 ones, on its time to 30. Each character
// counts once per milestone, with its upload closest to it (the lowest
// level, then the one exported soonest after reaching it, then the latest),
// so a 60 shared at the level-up stands for its character rather than one
// shared weeks later. Each upload carries its profile, the numbers it's
// ranked on, in payload.ranked: site/model.js's saved(), worked out by
// upload.js when it was saved. So ranking a journey reads a few KB per
// character, not every export in full.
//
// Profiles are saved packed (pack): their values as one list in the order
// of KEYS, the rankings' keys, named by KEYS_ID, instead of ~470 named
// numbers, a third of the size. One saved before they were packed (values
// by name) still ranks, and is packed when its milestone's population is
// next worked out, a few per load.
//
// A milestone's population is every character's profile there, a few MB
// from Supabase, and Supabase bills what it sends. So the live site works
// it out once and shares it: /api/population (population.js) answers with
// it, compact and compressed, and Vercel's CDN keeps that answer for
// SHARED_FOR, then serves it while working out a fresh one. Share pages and
// preview images ask the CDN for it (sharedPopulation), so Supabase sends
// each population a few times a day rather than once a page. A new journey
// is still ranked fresh against it; it's only missing the journeys saved
// since. Its address carries a key made from the secret key (accessKey),
// and characters in it are only told apart by a keyed hash (whoOf), so
// neither the population nor any character's ID can be had from it. Where
// it can't be had (previews, tests, or the CDN failing), the population is
// read straight from Supabase (readPopulation). Either way each function
// instance keeps it for KEEP_FOR.
//
// Uploads without a profile (tools/import doesn't make them) or with one
// from an older MODEL or rankings list get theirs worked out from their
// export here and written back, a few per load, before each character's is
// chosen. An export it can't be worked out from gets a failed profile, so
// it's tried once per MODEL, not on every load. Each upload's summary
// (site/model.js's summaryOf, in payload.summary, for its character's page)
// is worked out and written back with its profile.

const crypto = require('crypto');
const JourneyModel = require('./model');
const RANKINGS = require('./rankings');

const SITE = 'https://www.journeytracker.dev';
const KEEP_FOR = 30 * 60 * 1000;   // ms a function instance keeps a population
const SHARED_FOR = 6 * 60 * 60;    // s the CDN keeps a shared population fresh
const SHARED_STALE = 2 * 24 * 60 * 60;   // s it may then serve it while making a fresh one
const SHARED_WAIT = 20 * 1000;     // ms to wait for the shared population
const PAGE = 1000;                 // rows per request, Supabase's cap
const MAKE_PER_LOAD = 25;          // profiles worked out per load
const MAKE_AT_ONCE = 5;            // exports read at once to work them out
const MAKE_FOR = 4000;             // ms a population may spend on them (big exports are slow)
const MILESTONES = [10, 20, 30, 40, 50, 60];   // the ones journeys are ranked at

// The keys profiles are ranked on, in the rankings' order: a packed
// profile's values are a list in this order. KEYS_ID names the list, so a
// profile packed against another one is never read against this one.
const KEYS = [...new Set(RANKINGS.map((r) => r.key))];
const KEYS_ID = crypto.createHash('sha256').update(KEYS.join('\n')).digest('hex').slice(0, 12);

// Uploads made to test the importer and the site don't count.
const TEST_VERSIONS = ['test', 'deploy-test'];

// One request to Supabase's REST API with the secret key.
async function supabase(path, options) {
  const url = process.env.SUPABASE_URL.replace(/\/+$/, '') + '/rest/v1/' + path;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  const response = await fetch(url, Object.assign({}, options, {
    headers: Object.assign({ apikey: key, Authorization: 'Bearer ' + key, 'Content-Type': 'application/json' },
      options && options.headers),
  }));
  if (!response.ok) throw new Error(`Supabase answered ${response.status}`);
  return response;
}

// A profile to save (site/model.js's saved()), its values packed into a
// list in the order of KEYS (null where it has none; none at the end).
function pack(profile) {
  const out = Object.assign({}, profile, { keys: KEYS_ID });
  const v = KEYS.map((k) => (typeof profile.values[k] === 'number' ? profile.values[k] : null));
  while (v.length && v[v.length - 1] === null) v.pop();
  out.v = v;
  delete out.values;
  return out;
}
// A saved profile as site/model.js ranks it, with its values by name. One
// saved before profiles were packed already is; one packed against another
// rankings list can't be read (null).
function unpack(ranked) {
  if (!ranked || typeof ranked !== 'object') return null;
  if (ranked.values) return ranked;
  if (ranked.keys !== KEYS_ID || !Array.isArray(ranked.v)) return null;
  const out = Object.assign({}, ranked, { values: {} });
  KEYS.forEach((k, i) => { if (typeof ranked.v[i] === 'number') out.values[k] = ranked.v[i]; });
  delete out.v;
  delete out.keys;
  return out;
}

// A decoded export's profile (ranked, packed), summary and how it did at
// its milestone for its guild's table (guildRow, share.js), to save with it.
function analyze(payload) {
  const journey = JourneyModel.journeyFromExport(payload);
  return { ranked: pack(JourneyModel.saved(JourneyModel.profileOf(journey, RANKINGS), RANKINGS)),
    summary: JourneyModel.summaryOf(journey), guildRow: journey.guildRow };
}
function profileOf(payload) {
  return unpack(analyze(payload).ranked);
}
// Whether a profile from this model is up to date: this one, or a newer
// one (a deployment still on an older model mustn't redo a newer one's).
function current(model) {
  return model >= JourneyModel.MODEL;
}
// Whether a listed upload's profile can be ranked on as it is: from this
// model (or newer) and, if packed, against these rankings.
function usableListed(r) {
  return current(r.model) && (r.keys == null || r.keys === KEYS_ID);
}

// Keys made from the secret key, so only the site's functions have them: the
// shared population's address (accessKey), and a character's stand-in in it
// (whoOf), enough to leave a journey's own character out of its rivals.
function keyed(what) {
  return crypto.createHmac('sha256', process.env.SUPABASE_SERVICE_ROLE_KEY || '').update(what);
}
function accessKey() {
  return keyed('population').digest('hex').slice(0, 32);
}
function whoOf(characterId) {
  return keyed('character ' + characterId).digest('base64url').slice(0, 16);
}

// Profiles and summaries for listed uploads that need them, written back
// with their export, a few exports read at a time. The rows get what the
// listing has of a profile (since, model, failed), the profile itself
// (ranked) and the summary. Given a time (`until`), no more are begun after
// it; the rest wait for another load.
async function makeProfiles(rows, until) {
  for (let i = 0; i < rows.length; i += MAKE_AT_ONCE) {
    if (until && Date.now() >= until) break;
    const batch = rows.slice(i, i + MAKE_AT_ONCE);
    const full = await (await supabase(`uploads?select=id,payload&id=in.(${batch.map((r) => r.id).join(',')})`)).json();
    await Promise.all(full.map(async ({ id, payload }) => {
      const row = batch.find((r) => r.id === id);
      try {
        Object.assign(payload, analyze(payload));
      } catch (err) {
        console.error(`profile for upload ${id}:`, err.message);
        payload.ranked = { model: JourneyModel.MODEL, failed: true, values: {}, trades: [] };
        delete payload.summary;
      }
      Object.assign(row, { ranked: payload.ranked, since: payload.ranked.since, model: payload.ranked.model,
        failed: payload.ranked.failed, keys: payload.ranked.keys, summary: payload.summary });
      try {
        await supabase(`uploads?id=eq.${id}`, { method: 'PATCH', headers: { Prefer: 'return=minimal' },
          body: JSON.stringify({ payload }) });
      } catch (err) {
        console.error(`saving the profile for upload ${id}:`, err.message);
      }
    }));
  }
}

// The levels that count toward a milestone: 30 is 30 to 39 (each ranked as
// it was at 30, site/model.js's asOfValues), 60 is 60 alone.
function levelsOf(milestone) {
  return milestone >= 60 ? [60, 60] : [milestone, milestone + 9];
}
// Which of a character's uploads stands for it at a milestone: the one
// closest to it, then the one exported soonest after reaching it (`since`,
// /played seconds, from its profile; unknown counts as last), then the
// latest. Sorts the better one first.
function closest(a, b) {
  const sa = typeof a.since === 'number' ? a.since : Infinity;
  const sb = typeof b.since === 'number' ? b.since : Infinity;
  return a.level - b.level || (sa < sb ? -1 : sa > sb ? 1 : 0) ||
    String(b.exported_at || '').localeCompare(String(a.exported_at || ''));
}

// At a milestone, each character's closest upload that has a profile, read
// from Supabase: [{ character_id, ranked }], ranked with its values by name
// (unpack). Their uploads are listed first, a few bytes each, and only the
// chosen ones' profiles are read.
async function readPopulation(milestone) {
  const [lo, hi] = levelsOf(milestone), listed = [];
  for (let from = 0; ; from += PAGE) {
    const page = await (await supabase('uploads?select=id,character_id,level,exported_at,since:payload->ranked->since' +
      ',model:payload->ranked->model,failed:payload->ranked->failed,keys:payload->ranked->keys' +
      `&addon_version=not.in.(${TEST_VERSIONS.join(',')})&level=gte.${lo}&level=lte.${hi}` +
      `&order=id&offset=${from}&limit=${PAGE}`)).json();
    listed.push(...page);
    if (page.length < PAGE) break;
  }
  // Older profiles are worked out again first (missing ones before the
  // rest), so that each character's uploads are compared on the same terms:
  // till then an older profile's `since` counts as unknown. An upload whose
  // profile failed stands for nobody.
  const todo = listed.filter((r) => !usableListed(r)).sort((a, b) => Number(a.model != null) - Number(b.model != null));
  const until = Date.now() + MAKE_FOR;
  if (todo.length) await makeProfiles(todo.slice(0, MAKE_PER_LOAD), until);
  const by = new Map();
  for (const r of listed) {
    if (r.failed) continue;
    if (!usableListed(r)) r.since = undefined;
    const best = by.get(r.character_id);
    if (!best || closest(r, best) < 0) by.set(r.character_id, r);
  }
  const rows = [...by.values()];
  // Chosen profiles saved before profiles were packed are packed now, with
  // what's left of this load's few, so they cost less to read next time.
  const spare = MAKE_PER_LOAD - Math.min(todo.length, MAKE_PER_LOAD);
  const loose = rows.filter((r) => r.ranked === undefined && r.keys == null && usableListed(r)).slice(0, spare);
  if (loose.length) await makeProfiles(loose, until);
  const unread = rows.filter((r) => r.ranked === undefined);
  for (let i = 0; i < unread.length; i += 200) {
    const chunk = unread.slice(i, i + 200);
    const got = await (await supabase('uploads?select=id,ranked:payload->ranked' +
      `&id=in.(${chunk.map((r) => r.id).join(',')})`)).json();
    const ranked = new Map(got.map((g) => [g.id, g.ranked]));
    chunk.forEach((r) => { r.ranked = ranked.get(r.id) || null; });
  }
  // An older profile still ranks until it's worked out again.
  return rows.map((r) => ({ character_id: r.character_id, ranked: unpack(r.ranked) }))
    .filter((r) => r.ranked && r.ranked.values && Array.isArray(r.ranked.trades));
}

// A population as /api/population shares it (population.js): for each
// character its stand-in and its profile but the values (people), and the
// values as one list per key, in the order of KEYS, with an entry for each
// person, null where they have none (cols). Compressed, the level 10s'
// (1,300 characters in Nov 2026) come to about 0.4 MB.
function compact(milestone, rows) {
  const people = rows.map((r) => {
    const p = Object.assign({}, r.ranked, { who: whoOf(r.character_id) });
    delete p.values;
    return p;
  });
  const cols = KEYS.map((k) => rows.map((r) => (typeof r.ranked.values[k] === 'number' ? r.ranked.values[k] : null)));
  return { model: JourneyModel.MODEL, keys: KEYS_ID, milestone, made: new Date().toISOString(), people, cols };
}
// The rivals from a shared population: [{ who, ranked }].
function expand(shared) {
  return shared.people.map((p, j) => {
    const ranked = Object.assign({}, p, { values: {} });
    delete ranked.who;
    KEYS.forEach((k, i) => { const x = shared.cols[i][j]; if (typeof x === 'number') ranked.values[k] = x; });
    return { who: p.who, ranked };
  });
}
// Where the shared population is asked for: the live site's CDN (or
// SHARED_SITE, for tests). Not a preview's, which wants a login.
function sharedSite() {
  return (process.env.SHARED_SITE || (process.env.VERCEL_ENV === 'production' ? SITE : '')).replace(/\/+$/, '');
}
// Its address for a milestone. This model and rankings list are in it, so a
// deployment never gets another's.
function sharedPath(milestone) {
  return `/api/population?m=${milestone}&v=${JourneyModel.MODEL}&r=${KEYS_ID}&k=${accessKey()}`;
}
async function sharedPopulation(milestone) {
  const response = await fetch(sharedSite() + sharedPath(milestone), { signal: AbortSignal.timeout(SHARED_WAIT) });
  if (!response.ok) throw new Error(`it answered ${response.status}`);
  const shared = await response.json();
  if (shared.model !== JourneyModel.MODEL || shared.keys !== KEYS_ID || shared.milestone !== milestone ||
      !Array.isArray(shared.people) || !Array.isArray(shared.cols) || shared.cols.length !== KEYS.length) {
    throw new Error("it isn't this model's");
  }
  return expand(shared);
}

// At a milestone, every character's profile there, each a journey's rival:
// [{ who, ranked }], `who` the character's stand-in (whoOf). The shared one
// where there is one, or else read from Supabase.
const kept = new Map();   // milestone -> { at, rows }
async function population(milestone) {
  const was = kept.get(milestone);
  if (was && Date.now() - was.at < KEEP_FOR) return was.rows;
  let rows = null;
  if (sharedSite()) {
    try {
      rows = await sharedPopulation(milestone);
    } catch (err) {
      console.error(`shared population ${milestone} failed:`, err.message);
    }
  }
  if (!rows) rows = (await readPopulation(milestone)).map((r) => ({ who: whoOf(r.character_id), ranked: r.ranked }));
  kept.set(milestone, { at: Date.now(), rows });
  return rows;
}

// Where an upload's journey places: its own profile (worked out fresh)
// against every other character's at its milestone. { places: { ranking
// id: [place, players] }, players: characters ranked, this one included,
// milestone }.
async function placesOf(characterId, profile) {
  const milestone = profile.milestone || 0;
  // Below 10 there's no milestone to compare at: no places.
  if (milestone < 10) return { places: {}, players: 0, milestone };
  const me = whoOf(characterId);
  const others = (await population(milestone)).filter((r) => r.who !== me).map((r) => r.ranked);
  return { places: JourneyModel.placesFor(profile, others, RANKINGS), players: others.length + 1, milestone };
}

// A saved upload, ready to show: its journey, its places ({ error: true }
// when they can't be worked out) and its best rankings, in the page's order.
async function journeyOf(payload, characterId) {
  const journey = JourneyModel.journeyFromExport(payload);
  const profile = JourneyModel.profileOf(journey, RANKINGS);
  let ranks;
  try {
    ranks = await placesOf(characterId, JourneyModel.saved(profile, RANKINGS));
  } catch (err) {
    console.error('ranking failed:', err.message);
    return { journey, ranks: { error: true }, picks: [] };
  }
  const all = RANKINGS.filter((r) => ranks.places[r.id])
    .map((r) => JourneyModel.standing(r, profile, ranks.places[r.id])).sort(JourneyModel.bestFirst);
  return { journey, ranks, picks: JourneyModel.picksFor(all, 9) };
}

// A journey's guildmates at its milestone (the guild code addon 0.6.13
// exports, never a name): each other character's upload there closest to
// it, as the rankings pick them, with how it did (payload.guildRow), its
// class and race. Null outside a guild, below 10, or with nobody else there.
async function guildOf(code, characterId, level) {
  const milestone = JourneyModel.milestoneOf(level);
  if (typeof code !== 'string' || !/^[0-9a-f]{16}$/.test(code) || milestone < 10) return null;
  const [lo, hi] = levelsOf(milestone);
  const rows = await (await supabase('uploads?select=id,character_id,level,exported_at,class,race,' +
    'since:payload->ranked->since,model:payload->ranked->model,row:payload->guildRow' +
    `&payload->>guild=eq.${code}&addon_version=not.in.(${TEST_VERSIONS.join(',')})` +
    `&level=gte.${lo}&level=lte.${hi}&limit=500`)).json();
  const by = new Map();
  for (const r of rows) {
    if (r.character_id === characterId || !r.row) continue;
    if (!current(r.model)) r.since = undefined;
    const best = by.get(r.character_id);
    if (!best || closest(r, best) < 0) by.set(r.character_id, r);
  }
  const mates = [...by.values()].map((r) => ({ classToken: r.class, race: r.race, level: r.level, row: r.row }));
  return mates.length ? { milestone, mates } : null;
}

module.exports = { supabase, analyze, profileOf, current, makeProfiles, placesOf, population, journeyOf, closest, guildOf,
  pack, unpack, readPopulation, compact, expand, sharedPath, accessKey, whoOf, RANKINGS, KEYS, KEYS_ID, MILESTONES,
  SHARED_FOR, SHARED_STALE };
