'use strict';
// GET /api/population?m=<milestone>&v=<model>&r=<rankings list>&k=<key>:
// every character's profile at a milestone (ranks.js's readPopulation),
// for share pages and preview images to rank journeys against, compact
// (ranks.js's compact) and compressed. Vercel's CDN keeps each answer for
// SHARED_FOR and then serves it while this works out a fresh one, so
// Supabase sends a population a few times a day, not once a page. Only the
// site's functions ask (ranks.js's sharedPopulation). Without the key made
// from the secret key, or for another model or rankings list, there's
// nothing here, and nothing is kept.

const crypto = require('crypto');
const zlib = require('zlib');
const ranks = require('./ranks');
const JourneyModel = require('./model');

function fail(res, code) {
  res.statusCode = code;
  res.setHeader('Content-Type', 'text/plain; charset=utf-8');
  res.setHeader('Cache-Control', 'no-store');
  res.end(code === 404 ? 'Not found.' : code === 409 ? 'Another version of the site.' : 'Try again in a minute.');
}

function rightKey(given) {
  const want = Buffer.from(ranks.accessKey()), got = Buffer.from(given);
  return got.length === want.length && crypto.timingSafeEqual(got, want);
}

module.exports = async function population(req, res) {
  const url = new URL(req.url, 'https://www.journeytracker.dev');
  const param = (k) => String((req.query && req.query[k]) || url.searchParams.get(k) || '');
  if (!process.env.SUPABASE_URL || !process.env.SUPABASE_SERVICE_ROLE_KEY) return fail(res, 503);
  if (!rightKey(param('k'))) return fail(res, 404);
  const milestone = Number(param('m'));
  if (!ranks.MILESTONES.includes(milestone)) return fail(res, 404);
  if (param('v') !== String(JourneyModel.MODEL) || param('r') !== ranks.KEYS_ID) return fail(res, 409);
  try {
    const shared = ranks.compact(milestone, await ranks.readPopulation(milestone));
    const body = zlib.gzipSync(JSON.stringify(shared));
    res.statusCode = 200;
    res.setHeader('Content-Type', 'application/json');
    res.setHeader('Content-Encoding', 'gzip');
    res.setHeader('Cache-Control',
      `public, max-age=0, s-maxage=${ranks.SHARED_FOR}, stale-while-revalidate=${ranks.SHARED_STALE}`);
    return res.end(body);
  } catch (err) {
    console.error(`population ${milestone} failed:`, err.message);
    return fail(res, 503);
  }
};
