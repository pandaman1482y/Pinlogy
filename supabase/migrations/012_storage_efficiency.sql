-- Keep cloud storage and list queries bounded as Pinlogy grows.

alter table public.users
  add column if not exists is_anonymous boolean not null default true;

create index if not exists idx_maps_owner_updated
  on public.maps(owner_id, updated_at desc);
create index if not exists idx_places_owner_updated
  on public.places(owner_id, updated_at desc);
create index if not exists idx_plans_owner_updated
  on public.plans(owner_id, updated_at desc);
create index if not exists idx_maps_public_updated
  on public.maps(updated_at desc) where is_public = true;
create index if not exists idx_map_shares_expires
  on public.map_shares(expires_at);
create index if not exists idx_places_external_id
  on public.places(owner_id, external_place_id)
  where external_place_id is not null and external_place_id <> '';
create index if not exists idx_places_name_address
  on public.places(owner_id, lower(name), lower(coalesce(address, '')));

create or replace function public.cleanup_stale_cloud_data()
returns void language plpgsql security definer set search_path = public as $$
begin
  delete from public.map_shares where expires_at <= now();

  -- Anonymous application data can be recreated. Registered accounts are never removed.
  delete from public.users
  where is_anonymous = true
    and updated_at < now() - interval '180 days'
    and id <> auth.uid();
end;
$$;

revoke all on function public.cleanup_stale_cloud_data() from public;
grant execute on function public.cleanup_stale_cloud_data() to authenticated;

drop function if exists public.list_public_maps(integer, integer);
create function public.list_public_maps(
  page_limit int default 30,
  page_offset int default 0
)
returns table(id uuid, name text, description text, icon text, theme_color int, place_count bigint)
language sql security definer set search_path = public stable as $$
  select m.id, m.name, m.description, m.icon, m.theme_color, count(mp.id)
  from public.maps m
  left join public.map_places mp on mp.map_id = m.id
  where m.is_public = true
  group by m.id
  order by m.updated_at desc
  limit least(greatest(page_limit, 1), 50)
  offset greatest(page_offset, 0);
$$;

revoke all on function public.list_public_maps(int, int) from public;
grant execute on function public.list_public_maps(int, int) to authenticated;
