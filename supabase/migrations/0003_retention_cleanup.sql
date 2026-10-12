-- Retention: saved days older than N days are deleted with their findings and photos.
-- Also removes orphans: unreferenced live photos and half-saved snapshot pieces (older than 1 day).
-- Live findings/photos of the current board are NEVER deleted by age.

create or replace function public.cleanup_old_data(p_days int default 15)
returns json language plpgsql security definer set search_path = '' as $$
declare
  cutoff_ms bigint := (extract(epoch from now()) * 1000)::bigint - p_days::bigint * 86400000;
  n_snap int; n_find int; n_ph int; n_orph_find int; n_orph_ph int; n_live_orph int;
  old_ids text[];
begin
  select coalesce(array_agg(substring(path from position('/' in path) + 1)), '{}')
    into old_ids
    from public.docs
   where col = 'snapshots' and coalesce((data ->> 'ts')::bigint, 0) < cutoff_ms;

  delete from public.docs d
   where d.col = 'snapfindings'
     and split_part(substring(d.path from position('/' in d.path) + 1), '__', 1) = any (old_ids);
  get diagnostics n_find = row_count;

  delete from public.blobs b
   where b.col = 'snapphotos'
     and split_part(substring(b.path from position('/' in b.path) + 1), '__', 1) = any (old_ids);
  get diagnostics n_ph = row_count;

  delete from public.docs d
   where d.col = 'snapshots' and substring(d.path from position('/' in d.path) + 1) = any (old_ids);
  get diagnostics n_snap = row_count;

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

  return json_build_object('days', p_days, 'snapshots', n_snap, 'snap_findings', n_find, 'snap_photos', n_ph,
                           'orphan_findings', n_orph_find, 'orphan_snap_photos', n_orph_ph, 'orphan_live_photos', n_live_orph);
end $$;
revoke all on function public.cleanup_old_data(int) from public, anon, authenticated;

-- Run every day at 03:00 Bangkok time (20:00 UTC). To change the retention, edit the number 15.
create extension if not exists pg_cron;
select cron.schedule('gemba-cleanup', '0 20 * * *', $$select public.cleanup_old_data(15)$$);
