-- Link install-scoped billing state to an authenticated Supabase user.
alter table public.billing_accounts
  add column if not exists user_id uuid references auth.users(id) on delete set null;

create unique index if not exists billing_accounts_user_id_key
  on public.billing_accounts(user_id) where user_id is not null;

create table if not exists public.billing_device_links (
  device_hash text primary key check (length(device_hash) = 64),
  account_hash text not null references public.billing_accounts(device_hash) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  linked_at timestamptz not null default now()
);

create index if not exists billing_device_links_user_id_idx
  on public.billing_device_links(user_id);
alter table public.billing_device_links enable row level security;
revoke all on public.billing_device_links from public, anon, authenticated;

create or replace function public.resolve_billing_account_hash(p_device_hash text)
returns text language sql stable security definer set search_path = public as $$
  select coalesce(
    (select account_hash from public.billing_device_links where device_hash = p_device_hash),
    p_device_hash
  );
$$;

create or replace function public.link_billing_account(
  p_device_hash text, p_user_id uuid, p_user_hash text
) returns text
language plpgsql security definer set search_path = public as $$
declare
  source_account public.billing_accounts;
  target_account public.billing_accounts;
  source_hash text;
  linked_user_id uuid;
begin
  if length(p_device_hash) <> 64 or length(p_user_hash) <> 64 then
    raise exception 'invalid_billing_identity';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));
  select user_id into linked_user_id from public.billing_device_links
  where device_hash = p_device_hash;
  -- A device changing to a different signed-in account must never move the
  -- previous user's purchased credits into the new account.
  if linked_user_id is not null and linked_user_id <> p_user_id then
    source_hash := p_user_hash;
  else
    source_hash := public.resolve_billing_account_hash(p_device_hash);
  end if;

  insert into public.billing_accounts(device_hash, user_id)
  values (p_user_hash, p_user_id)
  on conflict (device_hash) do update set
    user_id = coalesce(billing_accounts.user_id, excluded.user_id);
  select * into target_account from public.billing_accounts
  where device_hash = p_user_hash for update;

  if source_hash <> p_user_hash then
    select * into source_account from public.billing_accounts
    where device_hash = source_hash for update;
    if found then
      update public.billing_accounts set
        plan = case
          when coalesce(source_account.entitlement_expires_at, '-infinity'::timestamptz) >
               coalesce(target_account.entitlement_expires_at, '-infinity'::timestamptz)
            then source_account.plan else target_account.plan end,
        entitlement_expires_at = case
          when source_account.entitlement_expires_at is null then target_account.entitlement_expires_at
          when target_account.entitlement_expires_at is null then source_account.entitlement_expires_at
          else greatest(target_account.entitlement_expires_at, source_account.entitlement_expires_at) end,
        subscription_started_at = case
          when source_account.subscription_started_at is null then target_account.subscription_started_at
          when target_account.subscription_started_at is null then source_account.subscription_started_at
          else least(target_account.subscription_started_at, source_account.subscription_started_at) end,
        credit_period = case
          when source_account.credit_period = target_account.credit_period then target_account.credit_period
          when source_account.entitlement_expires_at > now() then source_account.credit_period
          else target_account.credit_period end,
        included_limit = greatest(target_account.included_limit, source_account.included_limit),
        -- Never add free/included credits across devices.
        included_used = greatest(target_account.included_used, source_account.included_used),
        bonus_credits = target_account.bonus_credits + source_account.bonus_credits,
        user_id = p_user_id,
        updated_at = now()
      where device_hash = p_user_hash;

      update public.billing_credit_reservations
      set device_hash = p_user_hash, updated_at = now()
      where device_hash = source_hash;
      update public.billing_device_links set account_hash = p_user_hash, user_id = p_user_id
      where account_hash = source_hash;
      delete from public.billing_accounts where device_hash = source_hash;
    end if;
  end if;

  insert into public.billing_device_links(device_hash, account_hash, user_id)
  values (p_device_hash, p_user_hash, p_user_id)
  on conflict (device_hash) do update set
    account_hash = excluded.account_hash,
    user_id = excluded.user_id,
    linked_at = now();
  return p_user_hash;
end;
$$;

revoke all on function public.resolve_billing_account_hash(text) from public;
revoke all on function public.link_billing_account(text, uuid, text) from public;
grant execute on function public.resolve_billing_account_hash(text) to service_role;
grant execute on function public.link_billing_account(text, uuid, text) to service_role;
grant select, insert, update, delete on public.billing_device_links to service_role;
notify pgrst, 'reload schema';
