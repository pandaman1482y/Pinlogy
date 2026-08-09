-- Release hardening: nullable unscheduled stops and public map discovery/clone.
alter table public.plan_stops alter column day_date drop not null;

create or replace function public.list_public_maps()
returns table(id uuid, name text, description text, icon text, theme_color int, place_count bigint)
language sql security definer set search_path = public stable as $$
  select m.id, m.name, m.description, m.icon, m.theme_color, count(mp.id)
  from public.maps m left join public.map_places mp on mp.map_id = m.id
  where m.is_public = true
  group by m.id order by m.updated_at desc limit 100;
$$;

create or replace function public.clone_public_map(source_map_id uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare new_map_id uuid; source_place record; new_place_id uuid;
begin
  if not exists(select 1 from maps where id = source_map_id and is_public) then
    raise exception 'public map not found';
  end if;
  insert into maps(owner_id, name, description, icon, theme_color)
  select auth.uid(), name || '（コピー）', description, icon, theme_color from maps where id = source_map_id
  returning id into new_map_id;
  for source_place in
    select p.* from places p join map_places mp on mp.place_id = p.id where mp.map_id = source_map_id
  loop
    insert into places(owner_id, name, formal_name, address, prefecture, city, area,
      nearest_station, building, floor, category, latitude, longitude, external_place_id,
      save_reason, visit_status, visit_count, created_at, updated_at)
    values(auth.uid(), source_place.name, source_place.formal_name, source_place.address,
      source_place.prefecture, source_place.city, source_place.area, source_place.nearest_station,
      source_place.building, source_place.floor, source_place.category, source_place.latitude,
      source_place.longitude, source_place.external_place_id, source_place.save_reason,
      'wantToGo', 0, now(), now()) returning id into new_place_id;
    insert into map_places(map_id, place_id) values(new_map_id, new_place_id);
  end loop;
  return new_map_id;
end;
$$;

revoke all on function public.list_public_maps() from public;
revoke all on function public.clone_public_map(uuid) from public;
grant execute on function public.list_public_maps() to authenticated;
grant execute on function public.clone_public_map(uuid) to authenticated;
