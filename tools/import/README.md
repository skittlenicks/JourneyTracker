# Journey Tracker import tool

Imports the export strings friends send you (`/journey export` in game) into
Supabase. Every import is a full snapshot and becomes a new row in `uploads`;
the `latest_uploads` view gives each character's current state.

## Setup (once)

1. Install Node.js 18 or newer (the LTS download from nodejs.org).
2. In this folder, run `npm install`.
3. Copy `.env.example` to `.env` and fill in `SUPABASE_URL` and
   `SUPABASE_SERVICE_ROLE_KEY` (Supabase dashboard > Project Settings > API).
   `.env` is git-ignored; never share the service role key.
4. Create the `uploads` table and `latest_uploads` view in Supabase.

## Importing

Paste exports into a text file, one per line. Blank lines and anything that
doesn't start with `JT` (chat text, "here's mine!") are ignored.

```
node import.js exports.txt             # decode, validate, insert
node import.js exports.txt --dry-run   # decode and validate only
node import.js exports.txt --print     # also print each decoded export
```

Each line is reported as `inserted`, `duplicate` (same character and export
time already in the table, or pasted twice in the file) or `rejected` with
the reason. A bad line never stops the rest of the batch.

## Code layout

- `decode.js`: decoding (`JT1:` + base64 + raw deflate + JSON), validation,
  and the mapping to an `uploads` row. Node built-ins only and no database
  code, so the website's paste page can reuse it as is.
- `import.js`: reads the file and does the Supabase work.

## Tests

```
npm test
```

Checks that export strings made by the addon's Lua encoder decode to exactly
`fixtures/testexport.expected.json`, and that bad strings are rejected.
`fixtures/testexport.txt` was made by running the addon's own encoder
(`JourneyTrackerSerialize.lua` + LibDeflate) outside the game. To check the
game client as well, type `/journey testexport` in game, copy the string into
`fixtures/testexport-ingame.txt` and run `npm test` again; every
`testexport*.txt` file is checked.
