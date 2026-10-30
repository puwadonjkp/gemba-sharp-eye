-- Retention policy
--   KEEP FOREVER : saved days (marks, averages, actions) and the text/thumbnails of their findings
--   DELETE       : the full-size photos of a saved day once that day is older than N days (default 30)
-- The small thumbnails live inside the finding documents, so old cards still show a thumbnail
-- after the full-size photo is gone. Live findings/photos of the current board are never deleted by age.
-- Also tidies leftovers: half-saved snapshot pieces and live photos nobody references (older than 1 day).

create or replace function public.cleanup_old_data(p_days int default 30)
returns json language plpgsql security definer set search_path = '' as $$
declare
  cutoff_ms bigint := (extract(epoch from now()) * 1000)::bigint - p_days::bigint * 86400000;
  n_ph int; n_orph_find int; n_orph_ph int; n_live_orph int;
  old_ids text[];
begin
  select coalesce(array_agg(substring(path from position('/' in path) + 1)), '{}')
    into old_ids
    from public.docs
   where col = 'snapshots' and coalesce((data ->> 'ts')::bigint, 0) < cutoff_ms;

  -- full-size photos of saved days older than p_days (the saved day itself and its findings stay)
  delete from public.blobs b
   where b.col = 'snapphotos'
     and split_part(substring(b.path from position('/' in b.path) + 1), '__', 1) = any (old_ids);
  get diagnostics n_ph = row_count;

  -- pieces of a snapshot whose main document never got written (failed save), older than 1 day
  delete from public.docs d
   where d.col = 'snapfindings' and d.updated_at < now() - interval '1 day'
     and not exists (select 1 from public.docs s
                      where s.path = 'snapshots/' || split_part(substring(d.path from position('/' in d.path) + 1), '__', 1));
  get diagnostics n_orph_find = row_count;

  delete from public.blobs b
   where b.col = 'snapphotos' and b.updated_at < now() - interval '1 day'
     and not exists (select 1 from public.docs s
                      where s.path = 'snapshots/' || split_part(substring(b.path from position('/' in b.path) + 1), '__', 1));
  get diagnostics n_orph_ph = row_count;

  -- live photos that no live finding references any more (older than 1 day)
  delete from public.blobs b
   where b.col = 'photos' and b.updated_at < now() - interval '1 day'
     and not exists (
       select 1 from public.docs f, jsonb_array_elements(coalesce(f.data -> 'photos', '[]'::jsonb)) p
        where f.col = 'findings' and p ->> 'id' = substring(b.path from position('/' in b.path) + 1));
  get diagnostics n_live_orph = row_count;

  return json_build_object('days', p_days, 'snap_photos_deleted', n_ph,
                           'orphan_findings', n_orph_find, 'orphan_snap_photos', n_orph_ph, 'orphan_live_photos', n_live_orph);
end $$;
revoke all on function public.cleanup_old_data(int) from public, anon, authenticated;

-- Run every day at 03:00 Bangkok time (20:00 UTC).
create extension if not exists pg_cron;
do $$ begin perform cron.unschedule('gemba-cleanup'); exception when others then null; end $$;
select cron.schedule('gemba-cleanup', '0 20 * * *', $$select public.cleanup_old_data(30)$$);

-- TO CHANGE THE NUMBER OF DAYS LATER (example: 60), run this one statement:
--   select cron.alter_job((select jobid from cron.job where jobname = 'gemba-cleanup'),
--                         command := $$select public.cleanup_old_data(60)$$);
