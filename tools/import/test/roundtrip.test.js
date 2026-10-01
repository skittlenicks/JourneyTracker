'use strict';
// Round trip: export strings made by the addon's Lua encoder from its fixed
// fake data (/journey testexport) must decode to exactly
// fixtures/testexport.expected.json. Every fixtures/testexport*.txt file is
// checked, so a string copied from the game can sit next to the one made
// outside it.
//
//   npm test

const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');
const { decode, validate, parseExport } = require('../decode');

const FIXTURES = path.join(__dirname, '..', 'fixtures');
const expected = JSON.parse(fs.readFileSync(path.join(FIXTURES, 'testexport.expected.json'), 'utf8'));

function exportLine(file) {
  const text = fs.readFileSync(path.join(FIXTURES, file), 'utf8');
  const line = text.split(/\r?\n/).map((l) => l.trim()).find((l) => l.startsWith('JT'));
  assert.ok(line, `${file} has no line starting with JT`);
  return line;
}

const fixtureFiles = fs.readdirSync(FIXTURES).filter((f) => /^testexport.*\.txt$/.test(f));

test('there is at least one test export to check', () => {
  assert.ok(fixtureFiles.length > 0, 'add fixtures/testexport.txt (from /journey testexport)');
});

for (const file of fixtureFiles) {
  test(`${file} decodes to the expected test export`, () => {
    const result = decode(exportLine(file));
    assert.ok(result.ok, result.error);
    assert.deepStrictEqual(result.data, expected);
  });

  test(`${file} passes validation and maps to a row`, () => {
    const result = parseExport(exportLine(file));
    assert.ok(result.ok, result.error);
    assert.deepStrictEqual(validate(result.data), []);
    assert.strictEqual(result.row.character_id, expected.characterId);
    assert.strictEqual(result.row.exported_at, new Date(expected.exportedAt * 1000).toISOString());
    assert.strictEqual(result.row.class, 'DRUID');
    assert.strictEqual(result.row.level, 20);
    assert.strictEqual(result.row.played_seconds, 217453);
  });
}

test('bad strings are rejected, not thrown', () => {
  const good = fixtureFiles.length ? exportLine(fixtureFiles[0]) : 'JT1:AAAA';
  const cases = {
    'not an export': 'hello',
    'unknown format': 'JT9:AAAA',
    'cut off': good.slice(0, Math.floor(good.length / 2)),
    'not base64': 'JT1:@@@@',
    'not deflate': 'JT1:' + Buffer.from('not compressed').toString('base64'),
  };
  for (const [name, text] of Object.entries(cases)) {
    const result = parseExport(text);
    assert.strictEqual(result.ok, false, `${name} should be rejected`);
    assert.ok(result.error, `${name} should explain why`);
  }
});

test('validation catches bad fields', () => {
  const bad = JSON.parse(JSON.stringify(expected));
  bad.characterId = 'not-a-uuid';
  bad.character.level = 61;
  bad.stats.zero = -1;
  delete bad.addonVersion;
  const errors = validate(bad);
  assert.ok(errors.some((e) => e.includes('UUID')));
  assert.ok(errors.some((e) => e.includes('level out of range')));
  assert.ok(errors.some((e) => e.includes('negative number at stats.zero')));
  assert.ok(errors.some((e) => e.includes('addon version')));
});
