-- Keep only a non-reversible identity marker after account deletion so the
-- one-time free allowance cannot be claimed repeatedly.
create table if not exists public.billing_trial_claims (
  identity_hash text primary key check (length(identity_hash) = 64),
  current_user_id uuid,
  first_claimed_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  account_deleted_at timestamptz
);

alter table public.billing_trial_claims enable row level security;
revoke all on public.billing_trial_claims from public, anon, authenticated;
grant select, insert, update on public.billing_trial_claims to service_role;

create or replace function public.enforce_billing_trial_claim(
  p_account_hash text,
  p_user_id uuid,
  p_identity_hashes text[]
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  identity_hash text;
  already_claimed boolean := false;
begin
  if length(p_account_hash) <> 64 or p_user_id is null or
     coalesce(array_length(p_identity_hashes, 1), 0) = 0 then
    raise exception 'invalid_trial_identity';
  end if;

  -- Lock in a deterministic order so simultaneous first logins cannot both
  -- receive the free allowance.
  for identity_hash in
    select distinct value from unnest(p_identity_hashes) value order by value
  loop
    if length(identity_hash) <> 64 then
      raise exception 'invalid_trial_identity';
    end if;
    perform pg_advisory_xact_lock(hashtextextended(identity_hash, 0));
    if exists (
      select 1 from public.billing_trial_claims
      where billing_trial_claims.identity_hash = identity_hash
        and current_user_id is distinct from p_user_id
    ) then
      already_claimed := true;
    end if;
  end loop;

  insert into public.billing_trial_claims(
    identity_hash, current_user_id, last_seen_at, account_deleted_at
  )
  select distinct value, p_user_id, now(), null
  from unnest(p_identity_hashes) value
  on conflict (identity_hash) do update set
    current_user_id = excluded.current_user_id,
    last_seen_at = now(),
    account_deleted_at = null;

  if already_claimed then
    update public.billing_accounts
    set included_limit = case
          when plan = 'free' then included_used
          else included_limit
        end,
        updated_at = now()
    where device_hash = p_account_hash;
  end if;

  return not already_claimed;
end;
$$;

create or replace function public.prepare_account_deletion(
  p_user_id uuid,
  p_identity_hashes text[]
) returns text[]
language plpgsql
security definer
set search_path = public
as $$
declare
  account_hashes text[];
begin
  if p_user_id is null or coalesce(array_length(p_identity_hashes, 1), 0) = 0 then
    raise exception 'invalid_deletion_identity';
  end if;

  select coalesce(array_agg(device_hash), '{}'::text[])
  into account_hashes
  from public.billing_accounts
  where user_id = p_user_id;

  update public.billing_trial_claims
  set current_user_id = null,
      last_seen_at = now(),
      account_deleted_at = now()
  where identity_hash = any(p_identity_hashes);

  -- Remove user-owned analysis requests and notification tokens. Completed
  -- purchase event ledgers remain for idempotency and transaction auditing.
  delete from public.async_analysis_jobs
  where device_hash = any(account_hashes);

  delete from public.billing_device_links where user_id = p_user_id;

  -- Personal entitlement state and consumable balances are removed with the
  -- account. Store subscriptions themselves must be cancelled in the store.
  update public.billing_accounts
  set user_id = null,
      plan = 'free',
      entitlement_expires_at = null,
      subscription_started_at = null,
      credit_period = 'deleted',
      included_limit = included_used,
      bonus_credits = 0,
      updated_at = now()
  where user_id = p_user_id;

  return account_hashes;
end;
$$;

revoke all on function public.enforce_billing_trial_claim(text, uuid, text[]) from public;
revoke all on function public.prepare_account_deletion(uuid, text[]) from public;
grant execute on function public.enforce_billing_trial_claim(text, uuid, text[]) to service_role;
grant execute on function public.prepare_account_deletion(uuid, text[]) to service_role;

notify pgrst, 'reload schema';
