-- Keep the one-time free allowance, subscription allowance and purchased
-- credits independent. Subscription credits are spent first, followed by the
-- free allowance and finally non-expiring purchased credits.
alter table public.billing_accounts
  add column if not exists free_limit integer not null default 3 check (free_limit >= 0),
  add column if not exists free_used integer not null default 0 check (free_used >= 0),
  add column if not exists plan_limit integer not null default 0 check (plan_limit >= 0),
  add column if not exists plan_used integer not null default 0 check (plan_used >= 0);

-- Migrate the old shared included balance. For active subscriptions the old
-- balance was the plan balance. The original free balance can no longer be
-- reconstructed, so pre-release subscribed accounts receive their three free
-- credits once during this migration.
update public.billing_accounts
set free_limit = case
      -- A subscribed Sandbox test can expire before any credit was used. The
      -- legacy expiry logic turned that untouched 3-credit trial into 0/0.
      when plan = 'free' and included_limit = 0 and included_used = 0 and user_id is not null
        then 3
      when plan = 'free' then included_limit
      else 3
    end,
    free_used = case when plan = 'free' then included_used else 0 end,
    plan_limit = case when plan in ('monthly', 'annual') then included_limit else 0 end,
    plan_used = case when plan in ('monthly', 'annual') then included_used else 0 end;

alter table public.billing_credit_reservations
  drop constraint if exists billing_credit_reservations_credit_source_check;

update public.billing_credit_reservations as reservations
set credit_source = case
  when reservations.credit_source = 'included' and accounts.plan in ('monthly', 'annual')
    then 'plan'
  when reservations.credit_source = 'included' then 'free'
  else reservations.credit_source
end
from public.billing_accounts as accounts
where accounts.device_hash = reservations.device_hash;

alter table public.billing_credit_reservations
  add constraint billing_credit_reservations_credit_source_check
  check (credit_source in ('plan', 'free', 'bonus'));

create or replace function public.refresh_billing_period(p_device_hash text)
returns public.billing_accounts
language plpgsql security definer set search_path = public as $$
declare
  account public.billing_accounts;
  current_period text := to_char(timezone('utc', now()), 'YYYY-MM');
begin
  insert into public.billing_accounts(device_hash)
  values (p_device_hash) on conflict (device_hash) do nothing;

  select * into account from public.billing_accounts
  where device_hash = p_device_hash for update;

  if account.plan in ('monthly', 'annual') and
     account.entitlement_expires_at is not null and
     account.entitlement_expires_at > now() then
    if account.credit_period is distinct from current_period then
      update public.billing_accounts set
        credit_period = current_period,
        plan_limit = 30,
        plan_used = 0,
        updated_at = now()
      where device_hash = p_device_hash returning * into account;
    end if;
  elsif account.plan <> 'free' or account.entitlement_expires_at is not null then
    update public.billing_accounts set
      plan = 'free',
      entitlement_expires_at = null,
      subscription_started_at = null,
      credit_period = 'lifetime',
      plan_limit = 0,
      plan_used = 0,
      updated_at = now()
    where device_hash = p_device_hash returning * into account;
  end if;
  return account;
end;
$$;

create or replace function public.reserve_billing_credit(
  p_device_hash text, p_job_id uuid
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare account public.billing_accounts; source text;
begin
  if length(p_device_hash) <> 64 then
    return jsonb_build_object('allowed', false);
  end if;
  account := public.refresh_billing_period(p_device_hash);

  if exists(select 1 from public.billing_credit_reservations where job_id = p_job_id) then
    return public.billing_status(p_device_hash) ||
      jsonb_build_object('allowed', true, 'reused', true);
  end if;

  if account.plan in ('monthly', 'annual') and account.plan_used < account.plan_limit then
    update public.billing_accounts
    set plan_used = plan_used + 1, updated_at = now()
    where device_hash = p_device_hash;
    source := 'plan';
  elsif account.free_used < account.free_limit then
    update public.billing_accounts
    set free_used = free_used + 1, updated_at = now()
    where device_hash = p_device_hash;
    source := 'free';
  elsif account.bonus_credits > 0 then
    update public.billing_accounts
    set bonus_credits = bonus_credits - 1, updated_at = now()
    where device_hash = p_device_hash;
    source := 'bonus';
  else
    return public.billing_status(p_device_hash) || jsonb_build_object('allowed', false);
  end if;

  insert into public.billing_credit_reservations(job_id, device_hash, credit_source)
  values (p_job_id, p_device_hash, source);
  return public.billing_status(p_device_hash) || jsonb_build_object('allowed', true);
end;
$$;

create or replace function public.refund_billing_credit(p_job_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare reservation public.billing_credit_reservations;
begin
  select * into reservation from public.billing_credit_reservations
  where job_id = p_job_id for update;
  if reservation.status is distinct from 'reserved' then return; end if;

  if reservation.credit_source = 'plan' then
    update public.billing_accounts
    set plan_used = greatest(plan_used - 1, 0), updated_at = now()
    where device_hash = reservation.device_hash;
  elsif reservation.credit_source = 'free' then
    update public.billing_accounts
    set free_used = greatest(free_used - 1, 0), updated_at = now()
    where device_hash = reservation.device_hash;
  else
    update public.billing_accounts
    set bonus_credits = bonus_credits + 1, updated_at = now()
    where device_hash = reservation.device_hash;
  end if;

  update public.billing_credit_reservations
  set status = 'refunded', updated_at = now()
  where job_id = p_job_id;
end;
$$;

create or replace function public.billing_status(p_device_hash text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  account public.billing_accounts;
  free_remaining integer;
  plan_remaining integer;
begin
  account := public.refresh_billing_period(p_device_hash);
  free_remaining := greatest(account.free_limit - account.free_used, 0);
  plan_remaining := case
    when account.plan in ('monthly', 'annual')
      then greatest(account.plan_limit - account.plan_used, 0)
    else 0
  end;
  return jsonb_build_object(
    'plan', account.plan,
    -- Compatibility for older app builds that displayed one included balance.
    'included_remaining', plan_remaining + free_remaining,
    'free_remaining', free_remaining,
    'plan_remaining', plan_remaining,
    'bonus_credits', account.bonus_credits,
    'remaining', plan_remaining + free_remaining + account.bonus_credits,
    'entitlement_expires_at', account.entitlement_expires_at
  );
end;
$$;

create or replace function public.activate_billing_plan(
  p_device_hash text, p_plan text, p_started_at timestamptz, p_expires_at timestamptz
) returns void language plpgsql security definer set search_path = public as $$
declare new_period text := to_char(timezone('utc', now()), 'YYYY-MM');
begin
  if length(p_device_hash) <> 64 or p_plan not in ('monthly', 'annual') then
    raise exception 'invalid_billing_plan';
  end if;
  insert into public.billing_accounts(
    device_hash, plan, entitlement_expires_at, subscription_started_at,
    credit_period, plan_limit, plan_used
  ) values (
    p_device_hash, p_plan, p_expires_at, p_started_at, new_period, 30, 0
  ) on conflict (device_hash) do update set
    plan = excluded.plan,
    entitlement_expires_at = excluded.entitlement_expires_at,
    subscription_started_at = coalesce(
      billing_accounts.subscription_started_at,
      excluded.subscription_started_at
    ),
    credit_period = new_period,
    plan_limit = 30,
    plan_used = case
      when billing_accounts.credit_period is distinct from new_period then 0
      else billing_accounts.plan_used
    end,
    updated_at = now();
end;
$$;

create or replace function public.expire_billing_plan(p_device_hash text)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.billing_accounts
  set plan = 'free',
      entitlement_expires_at = null,
      subscription_started_at = null,
      plan_limit = 0,
      plan_used = 0,
      updated_at = now()
  where device_hash = p_device_hash;
end;
$$;

create or replace function public.enforce_billing_trial_claim(
  p_account_hash text,
  p_user_id uuid,
  p_identity_hashes text[]
) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  candidate_hash text;
  already_claimed boolean := false;
begin
  if length(p_account_hash) <> 64 or p_user_id is null or
     coalesce(array_length(p_identity_hashes, 1), 0) = 0 then
    raise exception 'invalid_trial_identity';
  end if;

  for candidate_hash in
    select distinct source_hash
    from unnest(p_identity_hashes) as source(source_hash)
    order by source_hash
  loop
    if length(candidate_hash) <> 64 then raise exception 'invalid_trial_identity'; end if;
    perform pg_advisory_xact_lock(hashtextextended(candidate_hash, 0));
    if exists (
      select 1 from public.billing_trial_claims as claims
      where claims.identity_hash = candidate_hash
        and claims.current_user_id is distinct from p_user_id
    ) then
      already_claimed := true;
    end if;
  end loop;

  insert into public.billing_trial_claims(
    identity_hash, current_user_id, last_seen_at, account_deleted_at
  )
  select distinct source_hash, p_user_id, now(), null::timestamptz
  from unnest(p_identity_hashes) as source(source_hash)
  on conflict (identity_hash) do update set
    current_user_id = excluded.current_user_id,
    last_seen_at = now(),
    account_deleted_at = null;

  if already_claimed then
    update public.billing_accounts
    set free_limit = free_used, updated_at = now()
    where device_hash = p_account_hash;
  end if;
  return not already_claimed;
end;
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
        free_limit = greatest(target_account.free_limit, source_account.free_limit),
        free_used = greatest(target_account.free_used, source_account.free_used),
        plan_limit = greatest(target_account.plan_limit, source_account.plan_limit),
        plan_used = greatest(target_account.plan_used, source_account.plan_used),
        bonus_credits = target_account.bonus_credits + source_account.bonus_credits,
        user_id = p_user_id,
        updated_at = now()
      where device_hash = p_user_hash;

      update public.billing_credit_reservations
      set device_hash = p_user_hash, updated_at = now()
      where device_hash = source_hash;
      update public.billing_device_links
      set account_hash = p_user_hash, user_id = p_user_id
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

create or replace function public.prepare_account_deletion(
  p_user_id uuid,
  p_identity_hashes text[]
) returns text[]
language plpgsql security definer set search_path = public as $$
declare account_hashes text[];
begin
  if p_user_id is null or coalesce(array_length(p_identity_hashes, 1), 0) = 0 then
    raise exception 'invalid_deletion_identity';
  end if;
  select coalesce(array_agg(device_hash), '{}'::text[])
  into account_hashes from public.billing_accounts where user_id = p_user_id;

  update public.billing_trial_claims
  set current_user_id = null, last_seen_at = now(), account_deleted_at = now()
  where identity_hash = any(p_identity_hashes);
  delete from public.async_analysis_jobs where device_hash = any(account_hashes);
  delete from public.billing_device_links where user_id = p_user_id;
  update public.billing_accounts
  set user_id = null,
      plan = 'free',
      entitlement_expires_at = null,
      subscription_started_at = null,
      credit_period = 'deleted',
      free_limit = free_used,
      plan_limit = 0,
      plan_used = 0,
      bonus_credits = 0,
      updated_at = now()
  where user_id = p_user_id;
  return account_hashes;
end;
$$;

revoke all on function public.refresh_billing_period(text) from public;
revoke all on function public.reserve_billing_credit(text, uuid) from public;
revoke all on function public.refund_billing_credit(uuid) from public;
revoke all on function public.billing_status(text) from public;
revoke all on function public.activate_billing_plan(text, text, timestamptz, timestamptz) from public;
revoke all on function public.expire_billing_plan(text) from public;
revoke all on function public.enforce_billing_trial_claim(text, uuid, text[]) from public;
revoke all on function public.link_billing_account(text, uuid, text) from public;
revoke all on function public.prepare_account_deletion(uuid, text[]) from public;
grant execute on function public.refresh_billing_period(text) to service_role;
grant execute on function public.reserve_billing_credit(text, uuid) to service_role;
grant execute on function public.refund_billing_credit(uuid) to service_role;
grant execute on function public.billing_status(text) to service_role;
grant execute on function public.activate_billing_plan(text, text, timestamptz, timestamptz) to service_role;
grant execute on function public.expire_billing_plan(text) to service_role;
grant execute on function public.enforce_billing_trial_claim(text, uuid, text[]) to service_role;
grant execute on function public.link_billing_account(text, uuid, text) to service_role;
grant execute on function public.prepare_account_deletion(uuid, text[]) to service_role;
notify pgrst, 'reload schema';
