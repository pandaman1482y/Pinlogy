-- RevenueCat-backed recipe analysis credits.
create table if not exists public.billing_accounts (
  device_hash text primary key check (length(device_hash) = 64),
  plan text not null default 'free' check (plan in ('free', 'monthly', 'annual')),
  entitlement_expires_at timestamptz,
  subscription_started_at timestamptz,
  credit_period text,
  included_limit integer not null default 3 check (included_limit >= 0),
  included_used integer not null default 0 check (included_used >= 0),
  bonus_credits integer not null default 0 check (bonus_credits >= 0),
  updated_at timestamptz not null default now()
);

create table if not exists public.billing_credit_reservations (
  job_id uuid primary key references public.async_analysis_jobs(id) on delete cascade,
  device_hash text not null references public.billing_accounts(device_hash) on delete cascade,
  credit_source text not null check (credit_source in ('included', 'bonus')),
  status text not null default 'reserved' check (status in ('reserved', 'committed', 'refunded')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.revenuecat_webhook_events (
  event_id text primary key,
  event_type text not null,
  app_user_id text,
  product_id text,
  payload jsonb not null,
  processed_at timestamptz not null default now()
);

alter table public.billing_accounts enable row level security;
alter table public.billing_credit_reservations enable row level security;
alter table public.revenuecat_webhook_events enable row level security;
revoke all on public.billing_accounts, public.billing_credit_reservations,
  public.revenuecat_webhook_events from public, anon, authenticated;

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
        included_limit = 30,
        included_used = 0,
        updated_at = now()
      where device_hash = p_device_hash returning * into account;
    end if;
  elsif account.plan <> 'free' or account.entitlement_expires_at is not null then
    update public.billing_accounts set
      plan = 'free', entitlement_expires_at = null,
      subscription_started_at = null, credit_period = 'lifetime',
      -- 無料3回は初回だけ。解約後に再付与せず、追加購入分だけを残す。
      included_limit = included_used, updated_at = now()
    where device_hash = p_device_hash returning * into account;
  end if;
  return account;
end;
$$;

create or replace function public.reserve_billing_credit(
  p_device_hash text, p_job_id uuid
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare account public.billing_accounts; source text; remaining integer;
begin
  if length(p_device_hash) <> 64 then return jsonb_build_object('allowed', false); end if;
  account := public.refresh_billing_period(p_device_hash);

  if exists(select 1 from public.billing_credit_reservations where job_id = p_job_id) then
    return public.billing_status(p_device_hash) || jsonb_build_object('allowed', true, 'reused', true);
  end if;

  if account.included_used < account.included_limit then
    update public.billing_accounts set included_used = included_used + 1, updated_at = now()
    where device_hash = p_device_hash;
    source := 'included';
  elsif account.bonus_credits > 0 then
    update public.billing_accounts set bonus_credits = bonus_credits - 1, updated_at = now()
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

create or replace function public.commit_billing_credit(p_job_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.billing_credit_reservations set status = 'committed', updated_at = now()
  where job_id = p_job_id and status = 'reserved';
end;
$$;

create or replace function public.refund_billing_credit(p_job_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare reservation public.billing_credit_reservations;
begin
  select * into reservation from public.billing_credit_reservations
  where job_id = p_job_id for update;
  if reservation.status is distinct from 'reserved' then return; end if;
  if reservation.credit_source = 'included' then
    update public.billing_accounts set included_used = greatest(included_used - 1, 0), updated_at = now()
    where device_hash = reservation.device_hash;
  else
    update public.billing_accounts set bonus_credits = bonus_credits + 1, updated_at = now()
    where device_hash = reservation.device_hash;
  end if;
  update public.billing_credit_reservations set status = 'refunded', updated_at = now()
  where job_id = p_job_id;
end;
$$;

create or replace function public.billing_status(p_device_hash text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare account public.billing_accounts; included_remaining integer;
begin
  account := public.refresh_billing_period(p_device_hash);
  included_remaining := greatest(account.included_limit - account.included_used, 0);
  return jsonb_build_object(
    'plan', account.plan,
    'included_remaining', included_remaining,
    'bonus_credits', account.bonus_credits,
    'remaining', included_remaining + account.bonus_credits,
    'entitlement_expires_at', account.entitlement_expires_at
  );
end;
$$;

create or replace function public.activate_billing_plan(
  p_device_hash text, p_plan text, p_started_at timestamptz, p_expires_at timestamptz
) returns void language plpgsql security definer set search_path = public as $$
begin
  if length(p_device_hash) <> 64 or p_plan not in ('monthly', 'annual') then
    raise exception 'invalid_billing_plan';
  end if;
  insert into public.billing_accounts(
    device_hash, plan, entitlement_expires_at, subscription_started_at,
    credit_period, included_limit, included_used
  ) values (
    p_device_hash, p_plan, p_expires_at, p_started_at,
    to_char(timezone('utc', now()), 'YYYY-MM'), 30, 0
  ) on conflict (device_hash) do update set
    plan = excluded.plan,
    entitlement_expires_at = excluded.entitlement_expires_at,
    subscription_started_at = coalesce(billing_accounts.subscription_started_at, excluded.subscription_started_at),
    credit_period = case
      when billing_accounts.credit_period is distinct from excluded.credit_period then excluded.credit_period
      else billing_accounts.credit_period end,
    included_limit = 30,
    included_used = case
      when billing_accounts.credit_period is distinct from excluded.credit_period then 0
      else billing_accounts.included_used end,
    updated_at = now();
end;
$$;

create or replace function public.expire_billing_plan(p_device_hash text)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.billing_accounts set plan = 'free', entitlement_expires_at = null,
    subscription_started_at = null, updated_at = now()
  where device_hash = p_device_hash;
end;
$$;

create or replace function public.add_billing_bonus(p_device_hash text, p_amount integer)
returns void language plpgsql security definer set search_path = public as $$
begin
  if length(p_device_hash) <> 64 or p_amount < 1 or p_amount > 1000 then
    raise exception 'invalid_bonus';
  end if;
  insert into public.billing_accounts(device_hash, bonus_credits)
  values (p_device_hash, p_amount)
  on conflict (device_hash) do update set
    bonus_credits = billing_accounts.bonus_credits + excluded.bonus_credits,
    updated_at = now();
end;
$$;

revoke all on function public.refresh_billing_period(text) from public;
revoke all on function public.reserve_billing_credit(text, uuid) from public;
revoke all on function public.commit_billing_credit(uuid) from public;
revoke all on function public.refund_billing_credit(uuid) from public;
revoke all on function public.billing_status(text) from public;
grant execute on function public.refresh_billing_period(text) to service_role;
grant execute on function public.reserve_billing_credit(text, uuid) to service_role;
grant execute on function public.commit_billing_credit(uuid) to service_role;
grant execute on function public.refund_billing_credit(uuid) to service_role;
grant execute on function public.billing_status(text) to service_role;
revoke all on function public.activate_billing_plan(text, text, timestamptz, timestamptz) from public;
revoke all on function public.expire_billing_plan(text) from public;
revoke all on function public.add_billing_bonus(text, integer) from public;
grant execute on function public.activate_billing_plan(text, text, timestamptz, timestamptz) to service_role;
grant execute on function public.expire_billing_plan(text) to service_role;
grant execute on function public.add_billing_bonus(text, integer) to service_role;
notify pgrst, 'reload schema';
