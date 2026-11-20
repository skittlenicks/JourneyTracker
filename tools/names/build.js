// Builds the English names of spells and items in every language Forever
// has, so the addon and the website can work with the English name whatever
// the client's language. Writes:
//   JourneyTracker/JourneyTrackerNames.lua  for the addon: spell IDs (one per
//       English name and translation) and items' English names by item ID
//   tools/import/names.json                 for the website: each language's
//       spell and item names, to the English name
//
// Usage: node tools/names/build.js <Forever build, like 1.60.1.70959>
// The tables come from wago.tools (its CSV export of the game's DB2 tables,
// by build and language) and are kept in tools/names/.cache.
//
// Which names: every spell a player can learn (SkillLineAbility), every
// spell and item the addon's code names in a string, a few common casts,
// every item whose name holds one of the words the addon looks for
// (ITEM_WORDS below: keep it in step with the code), and the spells and items
// players' saved journeys have held (seen-spells.txt, seen-items.txt: English
// game names, gathered from the uploads; triggered spells like each Arcane
// Missile, potions' and food's effects, Forever's new abilities).

const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..', '..');
const ADDON = path.join(ROOT, 'JourneyTracker');
const CACHE = path.join(__dirname, '.cache');
const LOCALES = ['deDE', 'esES', 'esMX', 'frFR', 'itIT', 'koKR', 'ptBR', 'ruRU', 'zhCN', 'zhTW'];

// Words the addon finds inside item names (JourneyTrackerClass, Economy,
// Professions, World, Iconic, PvP). Lists the code keeps in a table are read
// from it by name (ITEM_LISTS); these are the ones written inline.
const ITEM_WORDS = ['Healthstone', 'Soulstone', 'Spellstone', 'Firestone', 'Conjured', 'Poison', 'Bandage', 'Potion',
  'Fishing Pole', 'Target Dummy', 'Fortune', 'Mark of Honor', 'Green Hills of Stranglethorn - Page', 'Soul Shard',
  'Hearthstone'];
const ITEM_LISTS = { 'JourneyTrackerEconomy.lua': ['ENHANCERS', 'LOCKBOXES'],
  'JourneyTrackerProfessions.lua': ['EXPLOSIVES', 'GADGETS', 'POTIONS', 'CABLES', 'HALLOWS', 'PRESENTS'] };
// Words the addon finds inside cast names that aren't a learned spell
// (World: portals you click, meeting stones; Iconic: teleports and portals).
const SPELL_WORDS = ['Portal Effect', 'Teleport', 'Portal', 'Meeting Stone'];
// Casts that aren't a learned spell but show up among anyone's most cast.
const EXTRA_SPELLS = ['Opening', 'Opening - No Text', 'Attack', 'Auto Shot', 'Shoot', 'Food', 'Drink', 'Disenchant',
  'Hearthstone', 'Fishing', 'Herb Gathering', 'Mining', 'Skinning', 'Pick Lock', 'First Aid', 'Cooking'];

// ---- CSV (quoted fields may hold commas, quotes and line breaks) ----
function parseCSV(text) {
  const rows = [];
  let row = [], field = '', quoted = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quoted) {
      if (c === '"') {
        if (text[i + 1] === '"') { field += '"'; i++; } else quoted = false;
      } else field += c;
    } else if (c === '"') quoted = true;
    else if (c === ',') { row.push(field); field = ''; }
    else if (c === '\n') { row.push(field); rows.push(row); row = []; field = ''; }
    else if (c !== '\r') field += c;
  }
  if (field !== '' || row.length) { row.push(field); rows.push(row); }
  const head = rows.shift();
  return rows.filter((r) => r.length === head.length).map((r) => {
    const o = {};
    head.forEach((h, i) => { o[h] = r[i]; });
    return o;
  });
}

async function table(name, build, locale) {
  fs.mkdirSync(CACHE, { recursive: true });
  const file = path.join(CACHE, `${name}.${build}.${locale || 'enUS'}.csv`);
  if (!fs.existsSync(file)) {
    const url = `https://wago.tools/db2/${name}/csv?build=${build}` + (locale ? `&locale=${locale}` : '');
    const res = await fetch(url);
    if (!res.ok) throw new Error(`${url}: ${res.status}`);
    fs.writeFileSync(file, Buffer.from(await res.arrayBuffer()));
  }
  return parseCSV(fs.readFileSync(file, 'utf8'));
}

// Strings in the addon's code: "..." literals, and the lists named above.
function codeStrings() {
  const all = new Set();
  const lists = [];
  for (const f of fs.readdirSync(ADDON).filter((f) => f.endsWith('.lua') && f !== 'JourneyTrackerNames.lua')) {
    const src = fs.readFileSync(path.join(ADDON, f), 'utf8');
    for (const m of src.matchAll(/"((?:[^"\\\n]|\\.)*)"/g)) {
      const s = m[1].replace(/\\(.)/g, '$1');
      if (s.length >= 3 && /[A-Za-z]/.test(s)) all.add(s);
    }
    for (const name of ITEM_LISTS[f] || []) {
      const m = src.match(new RegExp(`local ${name}\\s*=\\s*\\{([^}]*)\\}`));
      if (!m) throw new Error(`${f}: no list ${name}`);
      for (const s of m[1].matchAll(/"([^"]+)"/g)) lists.push(s[1]);
    }
  }
  return { all, lists };
}

function luaString(s) { return '"' + s.replace(/\\/g, '\\\\').replace(/"/g, '\\"') + '"'; }

(async () => {
  const build = process.argv[2];
  if (!build) { console.log('Usage: node tools/names/build.js <Forever build>'); process.exit(1); }
  const { all: literals, lists } = codeStrings();

  // ---- Spells ----
  const spellName = {};                        // [locale][id] = name
  spellName.enUS = {};
  for (const r of await table('SpellName', build)) if (r.Name_lang) spellName.enUS[r.ID] = r.Name_lang;
  for (const loc of LOCALES) {
    spellName[loc] = {};
    for (const r of await table('SpellName', build, loc)) if (r.Name_lang) spellName[loc][r.ID] = r.Name_lang;
  }
  const idsOf = {};                            // English name -> every ID with it
  for (const [id, n] of Object.entries(spellName.enUS)) (idsOf[n] = idsOf[n] || []).push(Number(id));
  const learnable = new Set();
  for (const r of await table('SkillLineAbility', build)) if (spellName.enUS[r.Spell]) learnable.add(Number(r.Spell));

  // Named in the code first (they win a clash), then the extra casts, then
  // every learnable spell. A name's IDs are the learnable ones where it has
  // any, else all of them.
  const order = [], seen = new Set(), tracked = new Set();
  const add = (n, isTracked) => {
    if (seen.has(n)) return;
    seen.add(n); order.push(n);
    if (isTracked) tracked.add(n);
  };
  // (Within each, the name more spells carry first: the addon keeps the first
  // name a translation gets, and German "Angeln" is Fishing, Fish and
  // Fishing Poles alike.)
  const byCount = (a, b) => idsOf[b].length - idsOf[a].length || (a < b ? -1 : 1);
  const worded = Object.keys(idsOf).filter((n) => SPELL_WORDS.some((w) => n.includes(w)) && !/\b(OLD|TEST|NYI|DND)\b|\[/.test(n));
  for (const s of [...literals, ...EXTRA_SPELLS, ...worded].filter((s) => idsOf[s]).sort(byCount)) add(s, true);
  const learnedNames = [...new Set([...learnable].map((id) => spellName.enUS[id]))].sort(byCount);
  for (const n of learnedNames) add(n, false);
  const seenList = (file) => fs.readFileSync(path.join(__dirname, file), 'utf8').split('\n').filter(Boolean);
  for (const n of seenList('seen-spells.txt').filter((n) => idsOf[n]).sort(byCount)) add(n, false);

  // One ID for each different set of translations of a name (ranks share
  // theirs, so nearly always one), the most common first; at most 4.
  const spellRows = [];                        // [id, English]
  const spellIDsByName = {};
  for (const n of order) {
    const pool = idsOf[n].filter((id) => learnable.has(id));
    const ids = pool.length ? pool : idsOf[n];
    spellIDsByName[n] = ids;
    const groups = new Map();
    for (const id of ids.sort((a, b) => a - b)) {
      const key = LOCALES.map((l) => spellName[l][id] || '').join('\u0001');
      if (!groups.has(key)) groups.set(key, []);
      groups.get(key).push(id);
    }
    [...groups.values()].sort((a, b) => b.length - a.length).slice(0, 4).forEach((g) => spellRows.push([g[0], n]));
  }

  // ---- Items ----
  const itemName = { enUS: {} };
  for (const r of await table('ItemSparse', build)) if (r.Display_lang) itemName.enUS[r.ID] = r.Display_lang;
  const words = [...ITEM_WORDS, ...lists];
  const seenItems = new Set(seenList('seen-items.txt'));
  const itemRows = [];
  for (const [id, n] of Object.entries(itemName.enUS)) {
    if (literals.has(n) || seenItems.has(n) || words.some((w) => n.includes(w))) itemRows.push([Number(id), n]);
  }
  itemRows.sort((a, b) => a[0] - b[0]);
  for (const loc of LOCALES) {
    itemName[loc] = {};
    for (const r of await table('ItemSparse', build, loc)) if (r.Display_lang) itemName[loc][r.ID] = r.Display_lang;
  }

  // ---- The addon's file ----
  const lua = [];
  lua.push('-- JourneyTracker: English names of spells and items, made by tools/names/build.js');
  lua.push(`-- from Forever build ${build}. Don't edit by hand: run the script again.`);
  lua.push('--');
  lua.push('-- Spells: { ID, English name } pairs, one ID for each name (and each set of');
  lua.push('-- translations): the addon asks the game what each ID is called in its');
  lua.push('-- language and maps that back to English. Names the code uses come first.');
  lua.push('-- Items: English names by item ID, for the items the code matches by name.');
  lua.push('');
  lua.push('local ADDON_NAME, ns = ...');
  lua.push('');
  lua.push('ns.NAMES_SPELLS = {');
  for (let i = 0; i < spellRows.length; i += 4) {
    lua.push('    ' + spellRows.slice(i, i + 4).map(([id, n]) => `${id}, ${luaString(n)},`).join(' '));
  }
  lua.push('}');
  lua.push('');
  lua.push('ns.NAMES_ITEMS = {');
  for (let i = 0; i < itemRows.length; i += 4) {
    lua.push('    ' + itemRows.slice(i, i + 4).map(([id, n]) => `[${id}] = ${luaString(n)},`).join(' '));
  }
  lua.push('}');
  fs.writeFileSync(path.join(ADDON, 'JourneyTrackerNames.lua'), lua.join('\n') + '\n');

  // ---- The website's file: each language's names to English ----
  // (A translation two English names share goes to the one the code names,
  // then to the one more of its spells carry; a tie is left out.)
  const out = { build, spells: {}, items: {} };
  let clashes = 0;
  for (const loc of LOCALES) {
    const count = {};                          // [translation][English] = IDs
    for (const n of order) {
      for (const id of idsOf[n]) {
        const t = spellName[loc][id];
        if (!t || t === n) continue;
        const c = count[t] = count[t] || {};
        c[n] = (c[n] || 0) + 1;
      }
    }
    const s = {};
    for (const [t, c] of Object.entries(count)) {
      const names = Object.keys(c).sort((a, b) => (tracked.has(b) - tracked.has(a)) || c[b] - c[a]);
      const [first, second] = names;
      if (second && tracked.has(first) === tracked.has(second) && c[first] === c[second]) { clashes++; continue; }
      s[t] = first;
    }
    const it = {};
    for (const [id, n] of itemRows) {
      const t = itemName[loc][id];
      if (!t || t === n) continue;
      if (it[t] === undefined) it[t] = n; else if (it[t] !== n) it[t] = null;
    }
    for (const t of Object.keys(it)) if (it[t] === null) delete it[t];
    out.spells[loc] = s;
    out.items[loc] = it;
  }
  const json = JSON.stringify(out);
  fs.writeFileSync(path.join(ROOT, 'tools', 'import', 'names.json'), json + '\n');

  console.log(`spells: ${order.length} names (${tracked.size} named in the code), ${spellRows.length} IDs`);
  console.log(`items: ${itemRows.length} IDs`);
  console.log(`addon file: ${(fs.statSync(path.join(ADDON, 'JourneyTrackerNames.lua')).size / 1024).toFixed(0)} KB;` +
    ` website file: ${(json.length / 1024).toFixed(0)} KB; spell translations two names share: ${clashes}`);
})().catch((e) => { console.error(e.message); process.exit(1); });
