'use strict';
// The pages of saved journeys (character.js). Rewrites in site/deploy.ps1
// send them here:
//   /j/<share ID>            a character's page, its latest journey (?id=)
//   /j/<share ID>/<level>    its journey at that level (?id=&at=)
//   /j/<share ID>/vs/<share ID>  two characters' latest, side by side (?id=&vs=)
// The answer is the site's own index.html (deploy.ps1 puts a copy next to
// this file) with what the page shows in it (window.JT_SHARED): for a
// journey, its export, its places among the saved journeys at its
// milestone (ranks.js) and the character's other saves, each with its
// summary (site/model.js's summaryOf), for the page to link between and say
// what changed since; for two, each one's summary and best places. And a
// title, description and preview image (card.js) of its own for link
// previews. Places change as more journeys are saved, and a character's
// page as it saves more, so Vercel's CDN keeps a journey at a level for ten
// minutes, and the latest, which a new save replaces, for a minute (the
// page a save opens adds ?saved= to skip that). Then it serves the page
// while making a fresh one.

const fs = require('fs');
const path = require('path');
const { uuidOfShareId, shareIdOf } = require('./decode');
const { supabase, journeyOf } = require('./ranks');
const { levelOf, characterOf, savesOf, fillSummaries } = require('./character');
const JourneyModel = require('./model');

const PAGE = fs.readFileSync(path.join(__dirname, 'index.html'), 'utf8');
const SITE = 'https://www.journeytracker.dev';
const MISSING = 'public, max-age=0, s-maxage=60';
const MOVING = 'public, max-age=0, s-maxage=60, stale-while-revalidate=600';   // the latest
const SETTLED = 'public, max-age=300, s-maxage=600, stale-while-revalidate=86400';   // a level's
const RETRY = 'public, max-age=0, s-maxage=60';   // places that couldn't be worked out

function attr(text) {
  return String(text).replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

// The page with `shared` in it for the page script (window.JT_SHARED) and,
// for a journey, its own title, description and preview image. Every
// replacement is a function, so nothing in the data can act as a "$"
// pattern. The data goes in as a JSON string for JSON.parse, so the page
// reads it as this function does (in a script's object literal a
// "__proto__" key would set the object's prototype), and "<" is escaped in
// it so no string in it can end the script.
function page(shared, meta) {
  let html = PAGE;
  if (meta) {
    html = html
      .replace(/<title>[^<]*<\/title>/, () => `<title>${attr(meta.title)}</title>`)
      .replace(/(<meta name="description" content=")[^"]*/, (all, start) => start + attr(meta.description))
      .replace(/(<meta property="og:title" content=")[^"]*/, (all, start) => start + attr(meta.title))
      .replace(/(<meta property="og:description" content=")[^"]*/, (all, start) => start + attr(meta.description));
    if (meta.image) {
      html = html
        .replace(/(<meta property="og:image" content=")[^"]*/, (all, start) => start + attr(meta.image))
        .replace(/(<meta property="og:image:alt" content=")[^"]*/, (all, start) => start + attr(meta.imageAlt));
    }
  }
  const data = JSON.stringify(JSON.stringify(shared)).replace(/</g, '\\u003c').replace(/\u2028/g, '\\u2028')
    .replace(/\u2029/g, '\\u2029');
  const head = (meta ? `<meta property="og:url" content="${attr(meta.url)}">\n` : '') +
    '<meta name="robots" content="noindex">\n' + `<script>window.JT_SHARED = JSON.parse(${data});</script>`;
  return html.replace('<!--JT_SHARED-->', () => head);
}

function days(n) { return `${n} day${n === 1 ? '' : 's'}`; }

function send(res, code, cache, html) {
  res.statusCode = code;
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.setHeader('Cache-Control', cache);
  res.end(html);
}

// A character's page: its journey at `level` (its latest without one, or
// when that's the latest anyway).
async function characterPage(res, uuid, level) {
  const character = await characterOf(uuid, true);
  if (!character) return send(res, 404, MISSING, page({ missing: true }));
  const shown = (level && character.at(level)) || character.latest, latest = shown.id === character.latest.id;
  const got = await (await supabase('uploads?select=payload&limit=1&id=eq.' + shown.id)).json();
  if (!got.length) return send(res, 404, MISSING, page({ missing: true }));
  const payload = got[0].payload || {};
  delete payload.ranked;    // the page works out its own numbers
  delete payload.summary;
  // Shown to anyone, so not the character's own ID: the upload's, which the
  // page only checks is a UUID. And of the typed words only the top one,
  // all the page shows.
  payload.characterId = shown.id;
  const wrapped = JourneyModel.named(payload.wrapped);
  if (wrapped['W-292'] !== undefined) {
    const top = JourneyModel.topRows(wrapped['W-292'], 1)[0];
    wrapped['W-292'] = top ? { [top[0]]: top[1] } : {};
  }
  const saves = savesOf(character, shown);
  const [{ journey: J, ranks, picks }] = await Promise.all([journeyOf(payload, character.characterId),
    fillSummaries(saves.filter((r) => r !== shown)).catch((err) => console.error('summaries failed:', err.message))]);
  // The saves to link between (none when this is the only one), each with
  // its summary when it has one.
  const journeys = saves.length < 2 ? [] : saves.map((r) => ({
    level: r.level, path: character.pathOf(r), here: r === shown || undefined,
    latest: r === character.latest || undefined,
    summary: r === shown ? JourneyModel.summaryOf(J) : r.summary && r.summary.v >= JourneyModel.SUMMARY ? r.summary : null,
  }));
  const where = character.pathOf(shown);
  const who = `${J.race} ${J.className}`.trim() || 'A journey';
  const across = J.path.length ? ` across ${J.path.length} zone${J.path.length === 1 ? '' : 's'}` : '';
  const best = picks[0];
  // At a milestone, the time it took to get there: "Level 30 in 12 days,
  // 1d 4h /played" (the days when the tracker saw the start).
  const reached = J.atMilestone && J.milestone && J.playedTo;
  const meta = {
    title: (reached ? `${who}: the road to ${J.milestone}` : `${who}, level ${J.level || '?'}`) + ' · Journey Tracker',
    description: (reached ? `Level ${J.milestone} in ${J.complete && J.daysTo ? days(J.daysTo) + ', ' : ''}` +
      `${JourneyModel.dur(J.playedTo)} /played${across}. ` : `${JourneyModel.dur(J.played)} of /played${across}. `) +
      (best ? `${best.big} ${best.who}${best.cohort === 'All players' ? '' :
        ` among ${best.cohort.replace(/^Level /, 'level ')}`}. ` : '') +
      'The route, the deaths, the quests and where this journey ranks.',
    url: SITE + where,
    // The latest's picture changes with it, so its address does too: link
    // previews keep pictures by address.
    image: `${SITE}${where}/card.png` + (latest ? `?v=${shareIdOf(shown.id).slice(0, 8)}` : ''),
    imageAlt: `Journey Tracker card: ${who}, level ${J.level || '?'}` +
      (best ? `, ${best.big} ${best.who}` : '') + '.',
  };
  const cache = ranks.error ? RETRY : latest ? MOVING : SETTLED;
  return send(res, 200, cache, page({ id: shareIdOf(shown.id), link: character.link, path: where, latest,
    payload, ranks, journeys }, meta));
}

// Two characters' latest journeys, side by side: each one's summary and
// best places. Two links to the same character are its own page.
async function comparePage(res, uuids) {
  const characters = await Promise.all(uuids.map((uuid) => characterOf(uuid, false)));
  if (characters.some((c) => !c)) return send(res, 404, MISSING, page({ missing: true }));
  if (characters[0].characterId === characters[1].characterId) return characterPage(res, uuids[0], null);
  const got = await (await supabase('uploads?select=id,payload&id=in.(' +
    characters.map((c) => c.latest.id).join(',') + ')')).json();
  const sides = await Promise.all(characters.map(async (c) => {
    const row = got.find((g) => g.id === c.latest.id);
    if (!row) throw new Error('a latest upload went missing');
    const { journey: J, ranks, picks } = await journeyOf(row.payload || {}, c.characterId);
    return {
      link: c.link, path: `/j/${c.link}`, summary: JourneyModel.summaryOf(J),
      ranks: ranks.error ? { error: true } : { milestone: ranks.milestone, players: ranks.players },
      picks: picks.slice(0, 3).map((x) => ({ big: x.big, who: x.who, detail: x.detail, cohort: x.cohort, line: x.line })),
    };
  }));
  const where = `/j/${sides[0].link}/vs/${sides[1].link}`;
  const who = (s) => `${s.summary.race} ${s.summary.className}`.trim() || 'A journey';
  const meta = {
    title: `${who(sides[0])} vs ${who(sides[1])} · Journey Tracker`,
    description: `A level ${sides[0].summary.level} ${who(sides[0])} and a level ${sides[1].summary.level} ` +
      `${who(sides[1])}, side by side: how long each took to every ten levels, their kills, deaths and quests, ` +
      'and where each ranks.',
    url: SITE + where,
  };
  const cache = sides.some((s) => s.ranks.error) ? RETRY : MOVING;
  return send(res, 200, cache, page({ compare: true, path: where, sides }, meta));
}

module.exports = async function share(req, res) {
  const url = new URL(req.url, SITE);
  const param = (k) => String((req.query && req.query[k]) || url.searchParams.get(k) || '');
  const uuid = uuidOfShareId(param('id')), vs = param('vs') && uuidOfShareId(param('vs'));
  if (!uuid || vs === null) return send(res, 404, 'public, max-age=0, s-maxage=3600', page({ missing: true }));
  if (!process.env.SUPABASE_URL || !process.env.SUPABASE_SERVICE_ROLE_KEY) {
    return send(res, 503, 'no-store', page({ error: true }));
  }
  try {
    return await (vs ? comparePage(res, [uuid, vs]) : characterPage(res, uuid, levelOf(param('at'))));
  } catch (err) {
    console.error('share failed:', err.message);
    return send(res, 503, 'no-store', page({ error: true }));
  }
};
