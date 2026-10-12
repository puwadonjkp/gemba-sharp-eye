-- Gemba board storage: a tiny document store (path = "collection/id").
-- docs  : small shared documents (marks, findings, actions, layout, snapshots) -> realtime
-- blobs : photo payloads (large) -> NOT in realtime, fetched on demand

create table if not exists public.docs (
  path       text primary key,
  col        text not null,
  data       jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  constraint docs_path_fmt check (path ~ '^[A-Za-z0-9_-]{1,40}/[A-Za-z0-9_-]{1,200}$'),
  constraint docs_size check (pg_column_size(data) < 400000)
);
create index if not exists docs_col_idx on public.docs (col);

create table if not exists public.blobs (
  path       text primary key,
  col        text not null,
  data       jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  constraint blobs_path_fmt check (path ~ '^[A-Za-z0-9_-]{1,40}/[A-Za-z0-9_-]{1,200}$'),
  constraint blobs_size check (pg_column_size(data) < 600000)
);
create index if not exists blobs_col_idx on public.blobs (col);

-- Deep merge: objects merge key by key, everything else (incl. arrays) is replaced.
create or replace function public.jsonb_deep_merge(a jsonb, b jsonb)
returns jsonb language sql immutable set search_path = '' as $$
  select case
    when jsonb_typeof(a) = 'object' and jsonb_typeof(b) = 'object' then
      coalesce((
        select jsonb_object_agg(k, case
          when a ? k and b ? k then public.jsonb_deep_merge(a -> k, b -> k)
          when b ? k then b -> k
          else a -> k end)
        from (select jsonb_object_keys(a) as k union select jsonb_object_keys(b)) keys
      ), '{}'::jsonb)
    else b
  end
$$;

-- Atomic partial update. Returns false when the document does not exist yet.
create or replace function public.doc_merge(p_path text, p_data jsonb)
returns boolean language plpgsql set search_path = '' as $$
declare n int;
begin
  update public.docs
     set data = public.jsonb_deep_merge(data, p_data), updated_at = now()
   where path = p_path;
  get diagnostics n = row_count;
  return n > 0;
end $$;

alter table public.docs  enable row level security;
alter table public.blobs enable row level security;

-- Phase 1: anyone with the link can read and edit (testing mode).
-- Phase 2 (later): replace these policies with ones that require auth.
create policy docs_all  on public.docs  for all to anon, authenticated using (true) with check (true);
create policy blobs_all on public.blobs for all to anon, authenticated using (true) with check (true);

alter table public.docs replica identity full;
alter publication supabase_realtime add table public.docs;

grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on public.docs, public.blobs to anon, authenticated;
grant execute on function public.doc_merge(text, jsonb) to anon, authenticated;
