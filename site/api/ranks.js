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
// character, not every export in full. Each milestone's population is kept
// for a few minutes in each function instance.
//
// Uploads without a profile (tools/import doesn't make them) or with one
// from an older MODEL get theirs worked out from their export here and
// written back, a few per load, before each character's is chosen. An
// export it can't be worked out from gets a failed profile, so it's tried
// once per MODEL, not on every load.

const JourneyModel = require('./model');
const RANKINGS = require('./rankings');

const KEEP_FOR = 10 * 60 * 1000;   // ms a population is kept
const PAGE = 1000;                 // rows per request, Supabase's cap
const MAKE_PER_LOAD = 25;          // profiles worked out per load
const MAKE_AT_ONCE = 5;            // exports read at once to work them out
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

// A decoded export's profile.
function profileOf(payload) {
  const journey = JourneyModel.journeyFromExport(payload);
  return JourneyModel.saved(JourneyModel.profileOf(journey, RANKINGS), RANKINGS);
}
// Whether a profile from this model is up to date: this one, or a newer
// one (a deployment still on an older model mustn't redo a newer one's).
function current(model) {
  return model >= JourneyModel.MODEL;
}

// Profiles for listed uploads that need one, written back with their
// export, a few exports read at a time. The rows get what the listing has
// of a profile (since, model, failed) and the profile itself (ranked).
async function makeProfiles(rows) {
  for (let i = 0; i < rows.length; i += MAKE_AT_ONCE) {
    const batch = rows.slice(i, i + MAKE_AT_ONCE);
    const full = await (await supabase(`uploads?select=id,payload&id=in.(${batch.map((r) => r.id).join(',')})`)).json();
    await Promise.all(full.map(async ({ id, payload }) => {
      const row = batch.find((r) => r.id === id);
      try {
        payload.ranked = profileOf(payload);
      } catch (err) {
        console.error(`profile for upload ${id}:`, err.message);
        payload.ranked = { model: JourneyModel.MODEL, failed: true, values: {}, trades: [] };
      }
      Object.assign(row, { ranked: payload.ranked, since: payload.ranked.since, model: payload.ranked.model,
        failed: payload.ranked.failed });
      try {
        await supabase(`uploads?id=eq.${id}`, { method: 'PATCH', headers: { Prefer: 'return=minimal' },
          body: JSON.stringify({ payload }) });
      } catch (err) {
        console.error(`saving the profile for upload ${id}:`, err.message);
      }
    }));
  }
}

// The levels that count toward a milestone: 30 is 30 to 39, 60 is 60 alone.
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

// At a milestone, each character's closest upload that has a profile:
// [{ character_id, ranked }]. Their uploads are listed first, a few bytes
// each, and only the chosen ones' profiles are read.
const kept = new Map();   // milestone -> { at, rows }
async function population(milestone) {
  const was = kept.get(milestone);
  if (was && Date.now() - was.at < KEEP_FOR) return was.rows;
  const [lo, hi] = levelsOf(milestone), listed = [];
  for (let from = 0; ; from += PAGE) {
    const page = await (await supabase('uploads?select=id,character_id,level,exported_at,since:payload->ranked->since' +
      ',model:payload->ranked->model,failed:payload->ranked->failed' +
      `&addon_version=not.in.(${TEST_VERSIONS.join(',')})&level=gte.${lo}&level=lte.${hi}` +
      `&order=id&offset=${from}&limit=${PAGE}`)).json();
    listed.push(...page);
    if (page.length < PAGE) break;
  }
  // Older profiles are worked out again first (missing ones before the
  // rest), so that each character's uploads are compared on the same terms:
  // till then an older profile's `since` counts as unknown. An upload whose
  // profile failed stands for nobody.
  const todo = listed.filter((r) => !current(r.model)).sort((a, b) => Number(a.model != null) - Number(b.model != null));
  if (todo.length) await makeProfiles(todo.slice(0, MAKE_PER_LOAD));
  const by = new Map();
  for (const r of listed) {
    if (r.failed) continue;
    if (!current(r.model)) r.since = undefined;
    const best = by.get(r.character_id);
    if (!best || closest(r, best) < 0) by.set(r.character_id, r);
  }
  const rows = [...by.values()], unread = rows.filter((r) => r.ranked === undefined);
  for (let i = 0; i < unread.length; i += 200) {
    const chunk = unread.slice(i, i + 200);
    const got = await (await supabase('uploads?select=id,ranked:payload->ranked' +
      `&id=in.(${chunk.map((r) => r.id).join(',')})`)).json();
    const ranked = new Map(got.map((g) => [g.id, g.ranked]));
    chunk.forEach((r) => { r.ranked = ranked.get(r.id) || null; });
  }
  // An older profile still ranks until it's worked out again.
  const usable = rows.filter((r) => r.ranked && r.ranked.values && Array.isArray(r.ranked.trades));
  kept.set(milestone, { at: Date.now(), rows: usable });
  return usable;
}

// Where an upload's journey places: its own profile (worked out fresh)
// against every other character's at its milestone. { places: { ranking
// id: [place, players] }, players: characters ranked, this one included,
// milestone }.
async function placesOf(characterId, profile) {
  const milestone = profile.milestone || 0;
  const others = (await population(milestone)).filter((r) => r.character_id !== characterId).map((r) => r.ranked);
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

module.exports = { supabase, profileOf, current, placesOf, population, journeyOf, closest, RANKINGS };
