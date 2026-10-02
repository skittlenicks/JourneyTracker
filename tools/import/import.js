#!/usr/bin/env node
'use strict';
// Import Journey Tracker exports into Supabase.
//
//   node import.js <file> [--dry-run] [--print] [--stats]
//
// <file> holds one or more export strings, one per line. Blank lines and
// lines that don't start with "JT" are ignored. Each valid export becomes a
// new row in "uploads" (a full snapshot); one already imported (same
// character and export time) is skipped as a duplicate. Statistics pane
// data rides along in payload like everything else.
//
//   --dry-run  decode and validate only, nothing is inserted (no .env needed)
//   --print    pretty-print each decoded export
//   --stats    print each export's Statistics pane data: baseline level and
//              how many statistics it holds

const fs = require('fs');
const path = require('path');
const { parseExport, describeStatistics } = require('./decode');

function usage() {
  console.log('Usage: node import.js <file> [--dry-run] [--print] [--stats]');
}

// "DRUID level 20", from whatever could be decoded.
function describe(data) {
  const c = data && data.character;
  if (!c) return '';
  return `${c.class || '?'} level ${c.level ?? '?'}`;
}

function connect() {
  let dotenv;
  let supabaseJs;
  try {
    dotenv = require('dotenv');
    supabaseJs = require('@supabase/supabase-js');
  } catch (err) {
    console.error('Missing packages: run "npm install" in tools/import first (or use --dry-run).');
    process.exit(1);
  }
  dotenv.config({ path: path.join(__dirname, '.env') });
  const { SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY } = process.env;
  if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
    console.error('Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in tools/import/.env '
      + '(copy .env.example), or use --dry-run.');
    process.exit(1);
  }
  return supabaseJs.createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });
}

async function isDuplicate(supabase, row) {
  let query = supabase.from('uploads').select('id').eq('character_id', row.character_id).limit(1);
  query = row.exported_at ? query.eq('exported_at', row.exported_at) : query.is('exported_at', null);
  const { data, error } = await query;
  if (error) throw new Error(`checking for duplicates: ${error.message}`);
  return data.length > 0;
}

async function main() {
  const args = process.argv.slice(2);
  const dryRun = args.includes('--dry-run');
  const print = args.includes('--print');
  const stats = args.includes('--stats');
  const file = args.find((a) => !a.startsWith('--'));
  if (!file) {
    usage();
    process.exit(1);
  }

  const lines = fs.readFileSync(file, 'utf8')
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.startsWith('JT'));
  if (lines.length === 0) {
    console.log('No export strings found (they start with "JT1:").');
    return;
  }

  const supabase = dryRun ? null : connect();
  const counts = { inserted: 0, duplicate: 0, rejected: 0, valid: 0, failed: 0 };
  const seen = new Set(); // character + export time already handled in this file

  for (const [i, line] of lines.entries()) {
    const label = `#${i + 1}`;
    const result = parseExport(line);
    if (!result.ok) {
      counts.rejected++;
      const who = describe(result.data);
      console.log(`${label} rejected${who ? ` (${who})` : ''}: ${result.error}`);
      continue;
    }
    const { row } = result;
    const who = describe(result.data);
    if (print) console.log(JSON.stringify(result.data, null, 2));
    if (stats) console.log(`${label} statistics: ${describeStatistics(result.data)}`);

    const key = `${row.character_id}|${row.exported_at}`;
    if (seen.has(key)) {
      counts.duplicate++;
      console.log(`${label} duplicate: ${who} (pasted twice in this file)`);
      continue;
    }
    seen.add(key);

    if (dryRun) {
      counts.valid++;
      console.log(`${label} valid: ${who}, exported ${row.exported_at || 'unknown'}`);
      continue;
    }
    try {
      if (await isDuplicate(supabase, row)) {
        counts.duplicate++;
        console.log(`${label} duplicate: ${who} (already imported)`);
        continue;
      }
      const { error } = await supabase.from('uploads').insert(row);
      if (error) throw new Error(error.message);
      counts.inserted++;
      console.log(`${label} inserted: ${who}`);
    } catch (err) {
      counts.failed++;
      console.log(`${label} failed: ${who}: ${err.message}`);
    }
  }

  const summary = dryRun
    ? `${counts.valid} valid, ${counts.duplicate} duplicate, ${counts.rejected} rejected (dry run, nothing inserted)`
    : `${counts.inserted} inserted, ${counts.duplicate} duplicate, ${counts.rejected} rejected`
      + (counts.failed ? `, ${counts.failed} failed` : '');
  console.log(`\nDone: ${summary}.`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
