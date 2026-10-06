'use strict';
// GET /j/<share ID>/card.png: a character's link preview, its page's card
// as an image (preview.js): who, level and time played, and its three best
// places, for its latest journey (character.js); /j/<share ID>/<level>/card.png
// for its journey at that level. Rewrites in site/deploy.ps1 send them here
// as ?id=<share ID>[&at=<level>]. Places change as more journeys are saved,
// so Vercel's CDN keeps a level's image for a day and then serves it while
// making a fresh one. The latest changes with the character's next save:
// its page asks for it with ?v= the save's own, and the CDN keeps it ten
// minutes.

const fs = require('fs');
const path = require('path');
const { uuidOfShareId } = require('./decode');
const { supabase, journeyOf } = require('./ranks');
const { levelOf, characterOf } = require('./character');
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
  const url = new URL(req.url, SITE);
  const param = (k) => String((req.query && req.query[k]) || url.searchParams.get(k) || '');
  const uuid = uuidOfShareId(param('id'));
  if (!uuid) return fail(res, 404);
  if (!process.env.SUPABASE_URL || !process.env.SUPABASE_SERVICE_ROLE_KEY) return fail(res, 503);
  try {
    const character = await characterOf(uuid, false);
    if (!character) return fail(res, 404);
    const level = levelOf(param('at'));
    const shown = (level && character.at(level)) || character.latest;
    const rows = await (await supabase('uploads?select=payload&limit=1&id=eq.' + shown.id)).json();
    if (!rows.length) return fail(res, 404);
    const { journey, ranks, picks } = await journeyOf(rows[0].payload || {}, character.characterId);
    const png = await journeyCard(cardOf(journey, picks), LOGO);
    res.statusCode = 200;
    res.setHeader('Content-Type', 'image/png');
    res.setHeader('Cache-Control', ranks.error ? 'public, max-age=0, s-maxage=60' :
      shown.id === character.latest.id ? 'public, max-age=600, s-maxage=600, stale-while-revalidate=86400' :
      'public, max-age=3600, s-maxage=86400, stale-while-revalidate=604800');
    return res.end(png);
  } catch (err) {
    console.error('card failed:', err.message);
    return fail(res, 503);
  }
};

module.exports.cardOf = cardOf;
