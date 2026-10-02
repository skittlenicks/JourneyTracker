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

-- Each character's latest snapshot. security_invoker makes the view obey
-- the table's row level security; without it, anyone holding the project's
-- public key could read every upload through the view. "nulls last" keeps
-- an upload with no export time from counting as the latest.
create view latest_uploads
with (security_invoker = on) as
select distinct on (character_id) *
from uploads
order by character_id, exported_at desc nulls last;
