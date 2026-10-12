-- Visitor counter. Read-only for clients; writes only through the security-definer functions.
create table if not exists public.visit_stats (
  day     date primary key,
  views   int not null default 0,
  uniques int not null default 0
);
alter table public.visit_stats enable row level security;
create policy visit_stats_read on public.visit_stats for select to anon, authenticated using (true);
grant select on public.visit_stats to anon, authenticated;

create or replace function public.visit_summary()
returns json language plpgsql security definer set search_path = '' as $$
declare d date := (now() at time zone 'Asia/Bangkok')::date;
begin
  return json_build_object(
    'today_views',    coalesce((select views   from public.visit_stats where day = d), 0),
    'today_uniques',  coalesce((select uniques from public.visit_stats where day = d), 0),
    'total_views',    coalesce((select sum(views) from public.visit_stats), 0)
  );
end $$;

-- Count one visit (client calls it once per browser session). p_new_day_visitor = first visit today from this browser.
create or replace function public.visit_hit(p_new_day_visitor boolean)
returns json language plpgsql security definer set search_path = '' as $$
declare d date := (now() at time zone 'Asia/Bangkok')::date;
begin
  insert into public.visit_stats(day, views, uniques)
  values (d, 1, case when p_new_day_visitor then 1 else 0 end)
  on conflict (day) do update
    set views   = public.visit_stats.views + 1,
        uniques = public.visit_stats.uniques + case when p_new_day_visitor then 1 else 0 end;
  return public.visit_summary();
end $$;

grant execute on function public.visit_summary() to anon, authenticated;
grant execute on function public.visit_hit(boolean) to anon, authenticated;
