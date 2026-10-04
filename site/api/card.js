'use strict';
// GET /j/<share ID>/card.png: a shared journey's link preview, the share
// page's card as an image (preview.js): who, level and time played, and its
// three best places. A rewrite in site/deploy.ps1 sends it here as
// ?id=<share ID>. Places change as more journeys are saved, so Vercel's CDN
// keeps each image for a day and then serves it while making a fresh one.

const fs = require('fs');
const path = require('path');
const { uuidOfShareId } = require('./decode');
const { supabase, journeyOf } = require('./ranks');
const { journeyCard } = require('./preview');
const JourneyModel = require('./model');

const LOGO = fs.readFileSync(path.join(__dirname, 'logo.png'));
const SITE = 'https://www.journeytracker.dev';

// What the card shows, the way the share page's card shows it. At a
// milestone, the time it took to get there; otherwise the time so far.
// Before a journey has places, three of its headline numbers, skipping any
// at 0 (but no deaths is worth showing).
function cardOf(J, picks) {
  const zones = J.path.length;
  const stats = [['Kills', J.kills], ['Deaths', J.deaths, true], ['Quests', J.quests.completed], ['Zones', zones],
    ['Dungeon bosses', J.bosses], ['Jumps', J.jumps]].filter((s) => s[1] > 0 || s[2]).slice(0, 3);
  const reached = J.atMilestone && J.milestone && J.playedTo;
  return {
    who: `${J.race} ${J.className}` + (J.faction ? ` · ${J.faction}` : ''),
    level: J.level,
    played: `${JourneyModel.dur(reached ? J.playedTo : J.played)} /played` +
      (reached && J.complete && J.daysTo ? ` over ${J.daysTo} day${J.daysTo === 1 ? '' : 's'}` : '') +
      (zones ? ` · ${zones} zone${zones === 1 ? '' : 's'}` : ''),
    ranks: picks.slice(0, 3).map((x) => ({ big: x.big, who: x.who, detail: x.detail, cohort: x.cohort })),
    stats: stats.map((s) => [s[0], JourneyModel.num(s[1])]),
  };
}

function fail(res, code) {
  res.statusCode = code;
  res.setHeader('Content-Type', 'text/plain; charset=utf-8');
  res.setHeader('Cache-Control', code === 404 ? 'public, max-age=0, s-maxage=3600' : 'no-store');
  res.end(code === 404 ? 'No such journey.' : 'Try again in a minute.');
}

module.exports = async function card(req, res) {
  const id = String((req.query && req.query.id) || new URL(req.url, SITE).searchParams.get('id') || '');
  const uuid = uuidOfShareId(id);
  if (!uuid) return fail(res, 404);
  if (!process.env.SUPABASE_URL || !process.env.SUPABASE_SERVICE_ROLE_KEY) return fail(res, 503);
  try {
    const rows = await (await supabase('uploads?select=character_id,payload&limit=1&id=eq.' + uuid)).json();
    if (!rows.length) return fail(res, 404);
    const { journey, ranks, picks } = await journeyOf(rows[0].payload || {}, rows[0].character_id);
    const png = await journeyCard(cardOf(journey, picks), LOGO);
    res.statusCode = 200;
    res.setHeader('Content-Type', 'image/png');
    res.setHeader('Cache-Control', ranks.error ? 'public, max-age=0, s-maxage=60' :
      'public, max-age=3600, s-maxage=86400, stale-while-revalidate=604800');
    return res.end(png);
  } catch (err) {
    console.error('card failed:', err.message);
    return fail(res, 503);
  }
};

module.exports.cardOf = cardOf;
