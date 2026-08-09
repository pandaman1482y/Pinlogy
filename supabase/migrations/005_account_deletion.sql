create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  target_user uuid := auth.uid();
begin
  if target_user is null then
    raise exception 'not authenticated';
  end if;
  delete from auth.users where id = target_user;
end;
$$;

revoke all on function public.delete_my_account() from public;
grant execute on function public.delete_my_account() to authenticated;
