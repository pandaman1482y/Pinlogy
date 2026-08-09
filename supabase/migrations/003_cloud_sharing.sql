-- Safe cloud sync and map sharing.

alter table public.users enable row level security;
create policy users_self_select on public.users for select using (auth.uid() = id);
create policy users_self_insert on public.users for insert with check (auth.uid() = id);
create policy users_self_update on public.users for update using (auth.uid() = id);

create table if not exists public.map_shares (
  id uuid primary key default gen_random_uuid(),
  map_id uuid not null references public.maps(id) on delete cascade,
  token text not null unique default encode(extensions.gen_random_bytes(9), 'hex'),
  role text not null check (role in ('viewer', 'editor')),
  expires_at timestamptz not null default (now() + interval '30 days'),
  created_by uuid not null references public.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.map_shares enable row level security;

create or replace function public.add_owner_as_map_member()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.map_members(map_id, user_id, role)
  values (new.id, new.owner_id, 'owner') on conflict (map_id, user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists maps_add_owner_member on public.maps;
create trigger maps_add_owner_member after insert on public.maps
for each row execute function public.add_owner_as_map_member();

insert into public.map_members(map_id, user_id, role)
select id, owner_id, 'owner' from public.maps
on conflict (map_id, user_id) do nothing;

create or replace function public.is_map_owner(target_map_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.maps where id = target_map_id and owner_id = auth.uid()
  );
$$;

create or replace function public.is_map_member(target_map_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.map_members
    where map_id = target_map_id and user_id = auth.uid()
  );
$$;

create policy maps_member_select on public.maps for select using (
  owner_id = auth.uid() or public.is_map_member(id)
);

create policy map_members_member_select on public.map_members for select using (
  user_id = auth.uid() or public.is_map_owner(map_id)
);

create policy map_places_member_select on public.map_places for select using (
  public.is_map_owner(map_id) or public.is_map_member(map_id)
);

create policy places_member_select on public.places for select using (
  owner_id = auth.uid() or exists (
    select 1 from public.map_places mp
    where mp.place_id = places.id and public.is_map_member(mp.map_id)
  )
);

create policy map_places_owner_all on public.map_places for all using (
  exists (select 1 from public.maps m where m.id = map_id and m.owner_id = auth.uid())
) with check (
  exists (select 1 from public.maps m where m.id = map_id and m.owner_id = auth.uid())
);

create or replace function public.create_map_share(
  target_map_id uuid,
  share_role text default 'viewer'
) returns text language plpgsql security definer set search_path = public as $$
declare new_token text;
begin
  if share_role not in ('viewer', 'editor') then raise exception 'invalid role'; end if;
  if not exists (select 1 from public.maps where id = target_map_id and owner_id = auth.uid()) then
    raise exception 'not map owner';
  end if;
  insert into public.map_shares(map_id, role, created_by)
  values (target_map_id, share_role, auth.uid()) returning token into new_token;
  return new_token;
end;
$$;

create or replace function public.accept_map_share(share_token text)
returns uuid language plpgsql security definer set search_path = public as $$
declare target public.map_shares%rowtype;
begin
  select * into target from public.map_shares
  where token = share_token and expires_at > now();
  if target.id is null then raise exception 'invalid or expired share code'; end if;
  insert into public.map_members(map_id, user_id, role)
  values (target.map_id, auth.uid(), target.role)
  on conflict (map_id, user_id) do update set role = excluded.role;
  return target.map_id;
end;
$$;

revoke all on function public.create_map_share(uuid, text) from public;
revoke all on function public.accept_map_share(text) from public;
revoke all on function public.is_map_owner(uuid) from public;
revoke all on function public.is_map_member(uuid) from public;
grant execute on function public.create_map_share(uuid, text) to authenticated;
grant execute on function public.accept_map_share(text) to authenticated;
grant execute on function public.is_map_owner(uuid) to authenticated;
grant execute on function public.is_map_member(uuid) to authenticated;
