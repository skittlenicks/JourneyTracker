'use strict';
// A character's saved journeys. Each upload has a share ID (decode.js), and
// any of a character's opens the character's page: /j/<share ID> shows its
// latest journey, the one at the highest level (then the last exported).
// The character's link is its first upload's share ID, so it stays the same
// as more are saved. /j/<link>/<level> is its journey at that level: the
// upload there closest to reaching it (ranks.js's closest), as the rankings
// pick it. upload.js answers with these paths; share.js and card.js read
// them. The character's own ID never leaves the server: with it, anyone
// could save made-up journeys as that character.

const { shareIdOf } = require('./decode');
const { supabase, current, closest, makeProfiles } = require('./ranks');
const JourneyModel = require('./model');

// A path's level: a whole level from 1 to 60, or none.
function levelOf(text) {
  const level = Number(text);
  return Number.isInteger(level) && level >= 1 && level <= 60 ? level : null;
}

function compare(a, b) {
  a = String(a || ''); b = String(b || '');
  return a < b ? -1 : a > b ? 1 : 0;
}
// Above 0 when upload a is newer than b: a higher level, then exported
// later, then saved later. (An export without a time counts as oldest.)
function newer(a, b) {
  return a.level - b.level || compare(a.exported_at, b.exported_at) || compare(a.created_at, b.created_at);
}
// Whether an upload is a saved milestone: the journey as it was at a tenth
// level, saved by the addon at the level-up (an "At 30" export), not one of now.
function isMilestone(r) {
  return r.level >= 10 && r.level % 10 === 0 && Number(r.milestone) === r.level;
}

// A character's uploads, first saved first: [{ id, level, exported_at,
// created_at, milestone, since, late, model, summary (if asked for) }]. An older
// profile's `since` is unknown until ranks.js works it out again.
async function uploadsOf(characterId, withSummaries) {
  const rows = await (await supabase('uploads?select=id,level,exported_at,created_at,milestone:payload->milestone' +
    ',since:payload->ranked->since,late:payload->ranked->late,model:payload->ranked->model' + (withSummaries ? ',summary:payload->summary' : '') +
    '&order=created_at.asc&limit=500&character_id=eq.' + encodeURIComponent(characterId))).json();
  rows.forEach((r) => { if (!current(r.model)) r.since = undefined; });
  return rows.sort((a, b) => compare(a.created_at, b.created_at) || compare(a.id, b.id));
}

// A character from its uploads: its link, latest upload and each upload's
// path. Null without any.
function characterFrom(characterId, rows) {
  if (!rows.length) return null;
  const link = shareIdOf(rows[0].id);
  const latest = rows.reduce((best, r) => (newer(r, best) > 0 ? r : best));
  return {
    characterId, rows, link, latest,
    pathOf: (r) => (r.id === latest.id ? `/j/${link}` : `/j/${link}/${r.level}`),
    // Its upload at a level, closest to reaching it.
    at: (level) => rows.filter((r) => r.level === level).sort(closest)[0] || null,
  };
}

// The character with the upload whose UUID this is, or null.
async function characterOf(uuid, withSummaries) {
  const found = await (await supabase('uploads?select=character_id&limit=1&id=eq.' + uuid)).json();
  if (!found.length) return null;
  return characterFrom(found[0].character_id, await uploadsOf(found[0].character_id, withSummaries));
}

// The journeys to link between on a page showing `shown`: the character's
// upload closest to each milestone (as the rankings pick them), its latest
// and this one, lowest level first.
function savesOf(character, shown) {
  const keep = new Map(), best = new Map();
  character.rows.forEach((r) => {
    const m = JourneyModel.milestoneOf(r.level), was = best.get(m);
    if (!was || closest(r, was) < 0) best.set(m, r);
  });
  best.forEach((r) => keep.set(r.id, r));
  keep.set(character.latest.id, character.latest);
  keep.set(shown.id, shown);
  return [...keep.values()].sort((a, b) => a.level - b.level || compare(a.exported_at, b.exported_at));
}

// Summaries for uploads without a current one, worked out from their
// exports and written back (ranks.js).
async function fillSummaries(rows) {
  const todo = rows.filter((r) => !(r.summary && r.summary.v >= JourneyModel.SUMMARY));
  if (todo.length) await makeProfiles(todo);
}

module.exports = { levelOf, newer, isMilestone, uploadsOf, characterFrom, characterOf, savesOf, fillSummaries };
