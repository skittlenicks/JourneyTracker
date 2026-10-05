'use strict';
// Decode and validate Journey Tracker export strings.
//
// Format 1: "JT1:" + base64( raw deflate( UTF-8 JSON ) ), made by the addon's
// JourneyTrackerSerialize.lua. Only Node built-ins are used and there's no
// database code here, so the website's upload function (site/api/upload.js)
// uses this file unchanged. The page itself decodes in the browser with the
// same rules (site/recap.template.html, decodeExport and checkExport).

const zlib = require('zlib');

const PREFIX = 'JT1:';
// Bytes after decompressing. A level 60's export is about 0.3-0.6 MB (the
// addon's size estimate for 150 to 600 hours of play), and the website
// holds a few of them at once, so this is several times that and no more.
const MAX_JSON = 4 * 1024 * 1024;
const MAX_DEPTH = 32; // tables inside tables; an export nests six deep
const EARLIEST = Date.UTC(2020, 0, 1) / 1000; // no export is older (seconds)
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const BASE64_RE = /^[A-Za-z0-9+/]+={0,2}$/;
// Stats that can legitimately be negative (e.g. killing a mob 3 levels
// below you is a level difference of -3).
const SIGNED_FIELDS = new Set(['diff']);

function fail(error, data) {
  return { ok: false, error, data };
}

// Export string -> { ok: true, data } or { ok: false, error }.
function decode(text) {
  const s = String(text || '').trim();
  if (!s.startsWith('JT')) return fail('not a Journey Tracker export');
  if (!s.startsWith(PREFIX)) {
    return fail(`unsupported format "${s.split(':')[0]}" (this tool reads ${PREFIX.slice(0, -1)})`);
  }
  // Chat clients sometimes wrap long pastes, so whitespace is ignored.
  const body = s.slice(PREFIX.length).replace(/\s+/g, '');
  if (!body || body.length % 4 !== 0 || !BASE64_RE.test(body)) {
    return fail('corrupted export: not valid base64 (was it cut off when pasting?)');
  }
  let json;
  try {
    // The website decodes exports from anyone, so a string that inflates to
    // something huge is refused rather than unpacked.
    json = zlib.inflateRawSync(Buffer.from(body, 'base64'), { maxOutputLength: MAX_JSON }).toString('utf8');
  } catch (err) {
    if (err.code === 'ERR_BUFFER_TOO_LARGE') return fail(`export too big: over ${MAX_JSON / 1024 / 1024} MB unpacked`);
    return fail('corrupted export: could not decompress (was it cut off when pasting?)');
  }
  try {
    return { ok: true, data: JSON.parse(json) };
  } catch (err) {
    return fail('corrupted export: not valid JSON after decompressing');
  }
}

// Path of the first negative number (outside SIGNED_FIELDS), or null; or
// TOO_DEEP, without looking further, where tables nest past MAX_DEPTH.
const TOO_DEEP = {};
function findNegative(value, path, depth, signed) {
  if (typeof value === 'number') return value < 0 && !signed ? path : null;
  if (value && typeof value === 'object') {
    if (depth >= MAX_DEPTH) return TOO_DEEP;
    for (const [key, child] of Object.entries(value)) {
      const found = findNegative(child, path ? `${path}.${key}` : key, depth + 1, signed || SIGNED_FIELDS.has(key));
      if (found) return found;
    }
  }
  return null;
}

// Decoded export -> list of problems (empty when it's valid).
function validate(data) {
  if (!data || typeof data !== 'object' || Array.isArray(data)) return ['export is not an object'];
  const errors = [];
  if (typeof data.characterId !== 'string') errors.push('missing characterId');
  else if (!UUID_RE.test(data.characterId)) errors.push(`characterId is not a valid UUID (${data.characterId})`);

  const c = data.character;
  if (!c || typeof c !== 'object') {
    errors.push('missing character info');
  } else {
    if (typeof c.class !== 'string' || !c.class) errors.push('missing class');
    if (!Number.isInteger(c.level)) errors.push('missing level');
    else if (c.level < 1 || c.level > 60) errors.push(`level out of range (${c.level})`);
  }
  if (typeof data.addonVersion !== 'string' || !data.addonVersion) errors.push('missing addon version');
  if (!Number.isInteger(data.schemaVersion) || data.schemaVersion < 1) errors.push('missing schemaVersion');
  // Seconds since 1970: from 2020 to two days from now (a clock set ahead).
  if (data.exportedAt !== undefined && !(Number.isFinite(data.exportedAt) && data.exportedAt > EARLIEST &&
      data.exportedAt < Date.now() / 1000 + 2 * 86400)) {
    errors.push('bad export timestamp');
  }
  const negative = findNegative(data, '', 0, false);
  if (negative === TOO_DEEP) errors.push(`tables nested more than ${MAX_DEPTH} deep`);
  else if (negative) errors.push(`negative number at ${negative}`);
  return errors;
}

// Decoded export -> a row for the Supabase "uploads" table.
function toRow(data) {
  const c = data.character || {};
  return {
    character_id: data.characterId,
    exported_at: Number.isFinite(data.exportedAt) ? new Date(data.exportedAt * 1000).toISOString() : null,
    addon_version: data.addonVersion,
    schema_version: data.schemaVersion,
    class: c.class ?? null,
    race: c.race ?? null,
    faction: c.faction ?? null,
    level: c.level,
    played_seconds: Number.isFinite(c.played) ? Math.floor(c.played) : null,
    payload: data,
  };
}

// Decode + validate in one step:
//   { ok: true, data, row } or { ok: false, error, data? }
function parseExport(text) {
  const decoded = decode(text);
  if (!decoded.ok) return decoded;
  const errors = validate(decoded.data);
  if (errors.length) return fail(errors.join('; '), decoded.data);
  // A payload's "ranked" is the website's own: the numbers the journey is
  // ranked on, which site/api/upload.js works out. An export can't bring one.
  delete decoded.data.ranked;
  return { ok: true, data: decoded.data, row: toRow(decoded.data) };
}

// One line about an export's Statistics pane data (W-505): the baseline's
// level and how many statistics the baseline and the latest snapshot hold.
function describeStatistics(data) {
  const s = data && data.statistics;
  if (!s || !s.latest) return 'no statistics';
  const count = (snapshot) => Object.keys((snapshot && snapshot.values) || {}).length;
  const parts = [];
  if (s.baseline) parts.push(`baseline at level ${s.baseline.level ?? '?'} (${count(s.baseline)} statistics)`);
  parts.push(`latest at level ${s.latest.level ?? '?'} (${count(s.latest)} statistics)`);
  const levels = Object.keys(s.levels || {}).length;
  if (levels) parts.push(`changes at ${levels} level-up${levels === 1 ? '' : 's'}`);
  return parts.join(', ');
}

// Share links (journeytracker.dev/j/<share ID>): an upload's ID, a random
// UUID, written as 22 URL-safe characters, and back.
function shareIdOf(uuid) {
  const hex = String(uuid || '').replace(/-/g, '');
  return /^[0-9a-f]{32}$/i.test(hex) ? Buffer.from(hex, 'hex').toString('base64url') : null;
}
function uuidOfShareId(shareId) {
  if (!/^[A-Za-z0-9_-]{22}$/.test(String(shareId || ''))) return null;
  const hex = Buffer.from(shareId, 'base64url').toString('hex');
  const uuid = `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
  return shareIdOf(uuid) === shareId ? uuid : null; // one link per upload
}

module.exports = { PREFIX, decode, validate, toRow, parseExport, describeStatistics, shareIdOf, uuidOfShareId };
