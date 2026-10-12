-- Pseudonymous billing continuity; no recipes or profile data in these tables.
create table public.billing_identity_links (
  identity_hash text primary key check(length(identity_hash)=64),
  account_hash text not null references public.billing_accounts(device_hash),
  updated_at timestamptz not null default now()
);
create table public.billing_customer_links (
  customer_hash text primary key check(length(customer_hash)=64),
  account_hash text not null references public.billing_accounts(device_hash)
);
create table public.billing_contract_links (
  contract_hash text primary key check(length(contract_hash)=64),
  account_hash text not null references public.billing_accounts(device_hash),
  last_event_at timestamptz not null
);
insert into public.billing_customer_links select device_hash,device_hash from public.billing_accounts;
-- Used by webhook ordering; preserve usage even when an account is deleted.
alter table public.billing_accounts add column billing_event_at timestamptz;

alter table public.billing_identity_links enable row level security;
alter table public.billing_customer_links enable row level security;
alter table public.billing_contract_links enable row level security;
revoke all on public.billing_identity_links,public.billing_customer_links,public.billing_contract_links from public,anon,authenticated;
grant select,insert,update,delete on public.billing_identity_links,public.billing_customer_links,public.billing_contract_links to service_role;

create function public.bind_billing_identity(p_user_id uuid,p_user_hash text,p_identity_hashes text[])
returns text language plpgsql security definer set search_path=public as $$
declare h text; chosen text; linked_owner uuid; candidates text[];
begin
  if p_user_id is null or length(p_user_hash)<>64 or coalesce(cardinality(p_identity_hashes),0)=0 then
    raise exception 'invalid_billing_identity';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text,0));
  for h in select distinct unnest(p_identity_hashes) order by 1 loop
    if length(h)<>64 then raise exception 'invalid_billing_identity'; end if;
    perform pg_advisory_xact_lock(hashtextextended(h,0));
  end loop;
  select array_agg(distinct account_hash) into candidates from public.billing_identity_links
    where identity_hash=any(p_identity_hashes);
  if coalesce(cardinality(candidates),0)>1 then raise exception 'billing_identity_conflict'; end if;
  chosen:=coalesce(candidates[1],p_user_hash);
  select user_id into linked_owner from public.billing_accounts where device_hash=chosen for update;
  if linked_owner is not null and linked_owner<>p_user_id then raise exception 'billing_identity_in_use'; end if;
  insert into public.billing_accounts(device_hash,user_id) values(chosen,p_user_id)
    on conflict(device_hash) do update set user_id=excluded.user_id;
  insert into public.billing_identity_links(identity_hash,account_hash)
    select distinct unnest(p_identity_hashes),chosen
    on conflict(identity_hash) do update set updated_at=now();
  insert into public.billing_customer_links(customer_hash,account_hash) values(p_user_hash,chosen)
    on conflict(customer_hash) do update set account_hash=excluded.account_hash;
  return chosen;
end;$$;

-- Do not erase subscription usage/period/entitlement when removing the login.
create or replace function public.prepare_account_deletion(p_user_id uuid,p_identity_hashes text[])
returns text[] language plpgsql security definer set search_path=public as $$
declare account_hashes text[]; chosen text; reservation_id uuid;
begin
  if p_user_id is null or coalesce(cardinality(p_identity_hashes),0)=0 then raise exception 'invalid_deletion_identity'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text,0));
  perform pg_advisory_xact_lock(hashtextextended('billing_webhooks_v81',0));
  select coalesce(array_agg(device_hash),'{}'::text[]) into account_hashes
    from public.billing_accounts where user_id=p_user_id;
  if cardinality(account_hashes)>1 then raise exception 'billing_identity_conflict'; end if;
  chosen:=account_hashes[1];
  if chosen is not null then
    insert into public.billing_identity_links(identity_hash,account_hash)
      select distinct unnest(p_identity_hashes),chosen on conflict(identity_hash) do nothing;
  end if;
  insert into public.billing_trial_claims(identity_hash,current_user_id,account_deleted_at)
    select distinct unnest(p_identity_hashes),null::uuid,now()
    on conflict(identity_hash) do update set current_user_id=null,account_deleted_at=now(),last_seen_at=now();
  for reservation_id in select job_id from public.billing_credit_reservations
    where device_hash=any(account_hashes) and status='reserved' loop
    perform public.refund_billing_credit(reservation_id);
  end loop;
  delete from public.async_analysis_jobs where device_hash=any(account_hashes);
  delete from public.billing_device_links where user_id=p_user_id;
  update public.billing_accounts set user_id=null,free_limit=free_used,bonus_credits=0,updated_at=now()
    where user_id=p_user_id;
  -- Retain event IDs for deduplication, remove the deleted customer's raw payload.
  update public.revenuecat_webhook_events set payload='{}'::jsonb,app_user_id=null
    where app_user_id=p_user_id::text or position(p_user_id::text in payload::text)>0;
  return account_hashes;
end;$$;

-- All webhook mutation and event deduplication happen in one DB transaction.
create function public.apply_billing_webhook(
 p_event_id text,p_type text,p_customer_hash text,p_product text,p_payload jsonb,
 p_plan text,p_started_at timestamptz,p_expires_at timestamptz,p_event_at timestamptz,
 p_contract_hash text,p_from_hashes text[],p_to_hashes text[],p_bonus boolean
) returns void language plpgsql security definer set search_path=public as $$
declare target_hash text; source_hash text; h text; source_account public.billing_accounts;
 target_account public.billing_accounts; targets text[]; current_period text:=to_char(timezone('utc',now()),'YYYY-MM');
begin
  if p_event_id='' or p_event_at is null then raise exception 'invalid_webhook'; end if;
  -- A single lock also serializes transfers with other webhook events.
  perform pg_advisory_xact_lock(hashtextextended('billing_webhooks_v81',0));
  if exists(select 1 from public.revenuecat_webhook_events where event_id=p_event_id) then return; end if;
  if p_type='TRANSFER' then
    select array_agg(distinct coalesce(l.account_hash,h.hash)) into targets
      from unnest(p_to_hashes) as h(hash) left join public.billing_customer_links l on l.customer_hash=h.hash;
    -- Multiple aliases must resolve to one known canonical account.
    if coalesce(cardinality(targets),0)<>1 then raise exception 'transfer_target_unresolved'; end if;
    target_hash:=targets[1];
    insert into public.billing_accounts(device_hash) values(target_hash) on conflict do nothing;
    select * into target_account from public.billing_accounts where device_hash=target_hash for update;
    for source_hash in select distinct coalesce(l.account_hash,h.hash)
      from unnest(p_from_hashes) as h(hash) left join public.billing_customer_links l on l.customer_hash=h.hash
    loop
      if source_hash=target_hash then continue; end if;
      select * into source_account from public.billing_accounts where device_hash=source_hash for update;
      if not found then raise exception 'transfer_source_unresolved'; end if;
      if coalesce(source_account.billing_event_at,'-infinity')>p_event_at or
         coalesce(target_account.billing_event_at,'-infinity')>p_event_at then continue; end if;
      if source_account.plan in ('monthly','annual') and source_account.entitlement_expires_at>now() then
        -- Calendar-month allowance follows the purchased subscription; never re-grant it.
        update public.billing_accounts set
          plan=source_account.plan,entitlement_expires_at=source_account.entitlement_expires_at,
          subscription_started_at=source_account.subscription_started_at,credit_period=current_period,
          plan_limit=30,plan_used=
            (case when credit_period=current_period then plan_used else 0 end)+
            (case when source_account.credit_period=current_period then source_account.plan_used else 0 end),
          billing_event_at=p_event_at,updated_at=now() where device_hash=target_hash;
      end if;
      update public.billing_accounts set plan='free',entitlement_expires_at=null,plan_limit=0,plan_used=0,
        billing_event_at=p_event_at,updated_at=now() where device_hash=source_hash;
      update public.billing_credit_reservations set device_hash=target_hash
        where device_hash=source_hash and credit_source='plan';
      update public.billing_contract_links set account_hash=target_hash,last_event_at=p_event_at
        where account_hash=source_hash and last_event_at<=p_event_at;
    end loop;
  else
    if length(p_customer_hash)<>64 then raise exception 'invalid_customer'; end if;
    select account_hash into target_hash from public.billing_customer_links where customer_hash=p_customer_hash;
    target_hash:=coalesce(target_hash,p_customer_hash);
    if p_contract_hash is not null then
      select account_hash into source_hash from public.billing_contract_links where contract_hash=p_contract_hash;
      -- After a transfer, old-customer events apply to the contract's current owner.
      target_hash:=coalesce(source_hash,target_hash);
    end if;
    insert into public.billing_accounts(device_hash) values(target_hash) on conflict do nothing;
    select * into target_account from public.billing_accounts where device_hash=target_hash for update;
    if p_bonus then
      -- Event IDs are not purchase IDs. Deduplicate credits by store transaction as well.
      if p_contract_hash is null then raise exception 'purchase_transaction_missing'; end if;
      if not exists(select 1 from public.billing_contract_links where contract_hash=p_contract_hash) then
        perform public.add_billing_bonus(target_hash,20);
        insert into public.billing_contract_links values(p_contract_hash,target_hash,p_event_at);
      end if;
    elsif coalesce(target_account.billing_event_at,'-infinity')<=p_event_at then
      if p_plan in ('monthly','annual') and p_type in ('INITIAL_PURCHASE','RENEWAL','UNCANCELLATION','PRODUCT_CHANGE') then
        if p_contract_hash is null then raise exception 'subscription_transaction_missing'; end if;
        perform public.activate_billing_plan(target_hash,p_plan,p_started_at,p_expires_at);
        insert into public.billing_contract_links values(p_contract_hash,target_hash,p_event_at)
          on conflict(contract_hash) do update set account_hash=excluded.account_hash,last_event_at=excluded.last_event_at;
      elsif p_type in ('EXPIRATION','BILLING_ISSUE') and p_expires_at<=now() then
        -- Do not let expiration of an old contract expire a later active plan.
        if target_account.entitlement_expires_at is null or target_account.entitlement_expires_at<=p_expires_at then
          perform public.expire_billing_plan(target_hash);
        end if;
      end if;
      if (p_plan in ('monthly','annual') and p_type in ('INITIAL_PURCHASE','RENEWAL','UNCANCELLATION','PRODUCT_CHANGE'))
        or (p_type in ('EXPIRATION','BILLING_ISSUE') and p_expires_at<=now()
            and (target_account.entitlement_expires_at is null or target_account.entitlement_expires_at<=p_expires_at)) then
        update public.billing_accounts set billing_event_at=p_event_at where device_hash=target_hash;
      end if;
    end if;
  end if;
  insert into public.revenuecat_webhook_events(event_id,event_type,app_user_id,product_id,payload)
    values(p_event_id,p_type,null,p_product,p_payload);
end;$$;

revoke all on function public.bind_billing_identity(uuid,text,text[]) from public;
revoke all on function public.apply_billing_webhook(text,text,text,text,jsonb,text,timestamptz,timestamptz,timestamptz,text,text[],text[],boolean) from public;
grant execute on function public.bind_billing_identity(uuid,text,text[]) to service_role;
grant execute on function public.apply_billing_webhook(text,text,text,text,jsonb,text,timestamptz,timestamptz,timestamptz,text,text[],text[],boolean) to service_role;

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
  perform pg_advisory_xact_lock(hashtextextended('billing_webhooks_v81',0));
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
      update public.billing_identity_links set account_hash=p_user_hash where account_hash=source_hash;
      update public.billing_customer_links set account_hash=p_user_hash where account_hash=source_hash;
      update public.billing_contract_links set account_hash=p_user_hash where account_hash=source_hash;
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
      plan_limit = 0,
      updated_at = now()
    where device_hash = p_device_hash returning * into account;
  end if;
  return account;
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
      updated_at = now()
  where device_hash = p_device_hash;
end;
$$;


alter table public.billing_credit_reservations add column plan_period text;
update public.billing_credit_reservations set plan_period=to_char(timezone('utc',created_at),'YYYY-MM') where credit_source='plan';
create or replace function public.reserve_billing_credit(
  p_device_hash text, p_job_id uuid
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare account public.billing_accounts; source text;
begin
  perform pg_advisory_xact_lock(hashtextextended('billing_webhooks_v81',0));
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

  insert into public.billing_credit_reservations(job_id, device_hash, credit_source, plan_period)
  values (p_job_id, p_device_hash, source, case when source = 'plan' then account.credit_period else null end);
  return public.billing_status(p_device_hash) || jsonb_build_object('allowed', true);
end;
$$;

create or replace function public.refund_billing_credit(p_job_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare reservation public.billing_credit_reservations;
begin
  perform pg_advisory_xact_lock(hashtextextended('billing_webhooks_v81',0));
  select * into reservation from public.billing_credit_reservations
  where job_id = p_job_id for update;
  if reservation.status is distinct from 'reserved' then return; end if;

  if reservation.credit_source = 'plan' then
    update public.billing_accounts
    set plan_used = greatest(plan_used - 1, 0), updated_at = now()
    where device_hash = reservation.device_hash
      and credit_period = reservation.plan_period;
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
