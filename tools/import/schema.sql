-- Journey Tracker: the table and view tools/import writes to. Run once in
-- the Supabase dashboard: SQL Editor > New query > paste all of this > Run.

create table uploads (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz default now(),
  character_id uuid not null,
  exported_at timestamptz,
  addon_version text,
  schema_version int,
  class text,
  race text,
  faction text,
  level int,
  played_seconds int,
  payload jsonb not null
);

-- Row level security on and no policies yet: only the import script, which
-- uses the secret (service role) key, can read or write. The website will
-- get its own read access later.
alter table uploads enable row level security;

create index uploads_character_id_idx on uploads (character_id, exported_at desc);

-- One row per export: a character's export from the same moment again is a
-- duplicate. tools/import and site/api/upload.js look for one before
-- saving; this also stops two saves of it at once. (An export without a
-- time isn't held to it.) A table made before this was here gets it with:
--   create unique index uploads_character_export_idx on uploads (character_id, exported_at);
-- which fails if the table already has duplicates. To find them:
--   select character_id, exported_at, count(*) from uploads
--   group by 1, 2 having count(*) > 1;
-- and to keep only the first of each (their other share links stop working):
--   delete from uploads a using uploads b
--   where a.character_id = b.character_id and a.exported_at = b.exported_at
--     and (a.created_at, a.id) > (b.created_at, b.id);
create unique index uploads_character_export_idx on uploads (character_id, exported_at);

-- Each character's latest snapshot. security_invoker makes the view obey
-- the table's row level security; without it, anyone holding the project's
-- public key could read every upload through the view. "nulls last" keeps
-- an upload with no export time from counting as the latest.
create view latest_uploads
with (security_invoker = on) as
select distinct on (character_id) *
from uploads
order by character_id, exported_at desc nulls last;
