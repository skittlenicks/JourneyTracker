// An export from a game client in another language, with its spell and item
// names put into English, the way the addon saves them since 0.6.18: before
// then a German client saved "Feuerball" where an English one saved
// "Fireball", and the website (which looks for English names) found nothing.
// names.json (made by tools/names/build.js) has each language's names.
//
//   toEnglish(data) -> { locale, moved } and `data` changed in place, or
//                      { locale: null, moved: 0 } for an English export
//
// The language is the export's own (character.locale, from addon 0.6.18), or
// for an older export the one whose spell names most of its casts match. Only
// tables the class tracker keys by spell or item name are touched, and a name
// that isn't in the language's list stays as it is.

const NAMES = require('./names.json');

const SPELL_TABLES = ['casts', 'ranks', 'targets', 'interrupts', 'combo', 'healing', 'judgements'];
// [path] of item-keyed tables in each class's saved data (and ALL's).
const ITEM_TABLES = [['items'], ['obtained'], ['ammo', 'used'], ['ammo', 'bought'], ['pets', 'fed'],
  ['healthstonesUsed'], ['conjured', 'water'], ['conjured', 'food'], ['conjured', 'gems'], ['conjured', 'gemsUsed'],
  ['conjured', 'given'], ['poisons', 'appliedItems'], ['poisons', 'crafted'], ['pickpocket', 'items'],
  ['bandages'], ['potions', 'healing'], ['potions', 'mana'], ['potions', 'other'], ['healthstones'], ['food']];

function isTable(v) { return v !== null && typeof v === 'object' && !Array.isArray(v); }

function merge(into, from) {
  for (const [k, v] of Object.entries(from)) {
    if (typeof v === 'number' && typeof into[k] === 'number') into[k] += v;
    else if (isTable(v) && isTable(into[k])) merge(into[k], v);
    else if (into[k] === undefined) into[k] = v;
  }
}

// Move a table's keys through `map`; counts add up, tables merge, and with
// `keep` the entry already under the English name stays. How many moved.
function rekey(t, map, keep) {
  if (!isTable(t)) return 0;
  let moved = 0;
  for (const k of Object.keys(t)) {
    const english = Object.prototype.hasOwnProperty.call(map, k) ? map[k] : null;
    if (!english || english === k) continue;
    const v = t[k];
    delete t[k];
    moved++;
    const have = t[english];
    if (have === undefined) t[english] = v;
    else if (keep) continue;
    else if (typeof v === 'number' && typeof have === 'number') t[english] = have + v;
    else if (isTable(v) && isTable(have)) merge(have, v);
  }
  return moved;
}

function at(obj, path) {
  let t = obj;
  for (const p of path) { if (!isTable(t)) return undefined; t = t[p]; }
  return t;
}

// The export's language: its own, or the one most of its cast names belong to.
function localeOf(data) {
  const own = data && data.character && data.character.locale;
  if (typeof own === 'string') return NAMES.spells[own] ? own : null;
  const names = [];
  for (const store of Object.values(isTable(data && data.class) ? data.class : {})) {
    if (isTable(store) && isTable(store.casts)) names.push(...Object.keys(store.casts));
  }
  let best = null, bestHits = 0;
  for (const [loc, map] of Object.entries(NAMES.spells)) {
    const hits = names.filter((n) => Object.prototype.hasOwnProperty.call(map, n)).length;
    if (hits > bestHits) { best = loc; bestHits = hits; }
  }
  // (A few hits could be names two languages share; three or more is a language.)
  return bestHits >= 3 ? best : null;
}

function toEnglish(data) {
  const locale = localeOf(data);
  if (!locale) return { locale: null, moved: 0 };
  const spells = NAMES.spells[locale], items = NAMES.items[locale] || {};
  let moved = 0;
  for (const store of Object.values(isTable(data.class) ? data.class : {})) {
    if (!isTable(store)) continue;
    for (const key of SPELL_TABLES) moved += rekey(store[key], spells);
    for (const group of Object.values(isTable(store.time) ? store.time : {})) moved += rekey(group, spells);
    for (const s of Object.values(isTable(store.swaps) ? store.swaps : {})) {
      if (!isTable(s) || !isTable(s.pairs)) continue;
      const pairs = {};
      for (const [key, n] of Object.entries(s.pairs)) {
        const m = key.match(/^(.*?) > (.+)$/);
        const english = m ? (spells[m[1]] || m[1]) + ' > ' + (spells[m[2]] || m[2]) : key;
        if (english !== key) moved++;
        pairs[english] = (pairs[english] || 0) + (Number(n) || 0);
      }
      s.pairs = pairs;
    }
    moved += rekey(at(store, ['shards', 'used']), spells);
    moved += rekey(at(store, ['buffs', 'bySpell']), spells);
    for (const path of ITEM_TABLES) moved += rekey(at(store, path), items);
  }
  moved += rekey(at(data, ['stats', 'spells']), spells, true);
  return { locale, moved };
}

module.exports = { toEnglish, localeOf };
