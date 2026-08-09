-- Owner-controlled management for active map share links.

create or replace function public.revoke_map_share(share_token text)
returns void language plpgsql security definer set search_path = public as $$
begin
  delete from public.map_shares s
  using public.maps m
  where s.token = share_token
    and m.id = s.map_id
    and m.owner_id = auth.uid();
end;
$$;

create or replace function public.list_my_map_shares()
returns table(
  token text,
  map_id uuid,
  map_name text,
  expires_at timestamptz,
  created_at timestamptz
)
language sql security definer set search_path = public stable as $$
  select s.token, s.map_id, m.name, s.expires_at, s.created_at
  from public.map_shares s
  join public.maps m on m.id = s.map_id
  where m.owner_id = auth.uid() and s.expires_at > now()
  order by s.created_at desc;
$$;

revoke all on function public.revoke_map_share(text) from public;
revoke all on function public.list_my_map_shares() from public;
grant execute on function public.revoke_map_share(text) to authenticated;
grant execute on function public.list_my_map_shares() to authenticated;
