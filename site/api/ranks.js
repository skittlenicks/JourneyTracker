'use strict';
// Where a saved journey places among everyone's, for its share page
// (share.js) and its preview image (card.js). Each character counts once,
// with its latest upload (Supabase's latest_uploads view), and each upload
// carries its profile, the numbers it's ranked on, in payload.ranked:
// site/model.js's saved(), worked out by upload.js when it was saved. So
// ranking a journey reads a few KB per character, not every export in full.
// The population is kept for a few minutes in each function instance.
//
// Uploads without a profile (tools/import doesn't make them) or with one
// from an older MODEL get theirs worked out from their export here and
// written back, a few per load.

const JourneyModel = require('./model');
const RANKINGS = require('./rankings');

const KEEP_FOR = 10 * 60 * 1000;   // ms a population is kept
const PAGE = 1000;                 // rows per request, Supabase's cap
const MAKE_PER_LOAD = 25;          // profiles worked out per load
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
function current(ranked) {
  return !!ranked && ranked.model === JourneyModel.MODEL && !!ranked.values && typeof ranked.values === 'object' &&
    Array.isArray(ranked.trades);
}

// Profiles for uploads that need one, written back with their export.
async function makeProfiles(rows) {
  const ids = rows.map((r) => r.id);
  const full = await (await supabase(`uploads?select=id,payload&id=in.(${ids.join(',')})`)).json();
  await Promise.all(full.map(async ({ id, payload }) => {
    const row = rows.find((r) => r.id === id);
    try {
      payload.ranked = row.ranked = profileOf(payload);
      await supabase(`uploads?id=eq.${id}`, { method: 'PATCH', headers: { Prefer: 'return=minimal' },
        body: JSON.stringify({ payload }) });
    } catch (err) {
      console.error(`profile for upload ${id}:`, err.message);
    }
  }));
}

// Every character's latest upload that has a profile: [{ character_id, ranked }].
let kept = null;
async function population() {
  if (kept && Date.now() - kept.at < KEEP_FOR) return kept.rows;
  const rows = [];
  for (let from = 0; ; from += PAGE) {
    const page = await (await supabase('latest_uploads?select=id,character_id,ranked:payload->ranked' +
      `&addon_version=not.in.(${TEST_VERSIONS.join(',')})&order=character_id&offset=${from}&limit=${PAGE}`)).json();
    rows.push(...page);
    if (page.length < PAGE) break;
  }
  // Missing profiles first: an older one still ranks in the meantime.
  const todo = rows.filter((r) => !current(r.ranked)).sort((a, b) => Number(!!a.ranked) - Number(!!b.ranked));
  if (todo.length) await makeProfiles(todo.slice(0, MAKE_PER_LOAD));
  kept = { at: Date.now(), rows: rows.filter((r) => r.ranked && r.ranked.values && Array.isArray(r.ranked.trades)) };
  return kept.rows;
}

// Where an upload's journey places: its own profile (worked out fresh)
// against every other character's latest. { places: { ranking id: [place,
// players] }, players: characters ranked, this one included }.
async function placesOf(characterId, profile) {
  const others = (await population()).filter((r) => r.character_id !== characterId).map((r) => r.ranked);
  return { places: JourneyModel.placesFor(profile, others, RANKINGS), players: others.length + 1 };
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

module.exports = { supabase, profileOf, placesOf, population, journeyOf, RANKINGS };
