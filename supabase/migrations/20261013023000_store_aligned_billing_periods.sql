-- Store-confirmed cycles; usage belongs to a purchased contract, not a login.
create table public.billing_subscription_cycles (
  contract_hash text not null,
  started_at timestamptz not null,
  paid_expires_at timestamptz not null,
  access_expires_at timestamptz not null,
  account_hash text not null references public.billing_accounts(device_hash),
  plan text not null check (plan in ('monthly','annual')),
  last_event_at timestamptz not null,
  revoked boolean not null default false,
  primary key (contract_hash,started_at),
  check (paid_expires_at > started_at),
  check (access_expires_at >= paid_expires_at)
);
create index billing_subscription_cycles_owner on public.billing_subscription_cycles(account_hash);
create table public.billing_plan_period_usage (
  period_key text primary key,
  used integer not null default 0 check (used>=0),
  updated_at timestamptz not null default now()
);
alter table public.billing_accounts
  add column allowance_started_at timestamptz,
  add column allowance_expires_at timestamptz;
alter table public.billing_subscription_cycles enable row level security;
alter table public.billing_plan_period_usage enable row level security;
revoke all on public.billing_subscription_cycles,public.billing_plan_period_usage from public,anon,authenticated;
grant select,insert,update,delete on public.billing_subscription_cycles,public.billing_plan_period_usage to service_role;

-- Compute anniversaries from the original anchor, never by repeatedly adding a month.
-- Annual monthly anniversaries use Japan's calendar; monthly periods come from the store.
create function public.billing_allowance_window(
 p_plan text,p_start timestamptz,p_end timestamptz,p_now timestamptz
) returns table(period_start timestamptz,period_end timestamptz)
language plpgsql immutable set search_path=public as $$
declare anchor timestamp; local_now timestamp; n integer; boundary timestamptz;
begin
  if p_start is null or p_end is null or p_start>=p_end or p_now<p_start then return; end if;
  if p_plan='monthly' then
    period_start:=p_start; period_end:=p_end; return next; return;
  end if;
  if p_plan<>'annual' then return; end if;
  anchor:=p_start at time zone 'Asia/Tokyo';
  local_now:=least(p_now,p_end-interval '1 microsecond') at time zone 'Asia/Tokyo';
  n:=(extract(year from local_now)::integer-extract(year from anchor)::integer)*12
    +extract(month from local_now)::integer-extract(month from anchor)::integer;
  n:=greatest(n,0);
  boundary:=(anchor+make_interval(months=>n)) at time zone 'Asia/Tokyo';
  if boundary>p_now then n:=greatest(n-1,0); end if;
  period_start:=(anchor+make_interval(months=>n)) at time zone 'Asia/Tokyo';
  period_end:=least((anchor+make_interval(months=>n+1)) at time zone 'Asia/Tokyo',p_end);
  return next;
end;$$;

create function public.billing_period_key(p_contract text,p_start timestamptz)
returns text language sql immutable set search_path=public as $$
 select p_contract||':'||extract(epoch from p_start)::text
$$;

-- Preserve existing spent credits during the one-time change of period format.
-- Legacy monthly expiry is known, but its latest purchase date cannot be reconstructed.
-- Keep its remaining balance until a confirmed store cycle arrives; never guess a renewal.
do $$
declare a public.billing_accounts; w record; k text;
begin
  for a in select * from public.billing_accounts where plan in ('monthly','annual')
    and subscription_started_at is not null and entitlement_expires_at>now()
    and subscription_started_at<entitlement_expires_at loop
    insert into public.billing_subscription_cycles values(
      'legacy:'||a.device_hash,a.subscription_started_at,a.entitlement_expires_at,
      a.entitlement_expires_at,a.device_hash,a.plan,coalesce(a.billing_event_at,now()),false);
    select * into w from public.billing_allowance_window(a.plan,a.subscription_started_at,a.entitlement_expires_at,now());
    if w.period_start is null then continue; end if;
    k:=public.billing_period_key('legacy:'||a.device_hash,w.period_start);
    insert into public.billing_plan_period_usage(period_key,used) values(k,a.plan_used);
    update public.billing_credit_reservations set plan_period=k
      where device_hash=a.device_hash and credit_source='plan' and plan_period=a.credit_period;
    update public.billing_accounts set credit_period=k,allowance_started_at=w.period_start,
      allowance_expires_at=w.period_end where device_hash=a.device_hash;
  end loop;
end;$$;

-- Malformed/old active rows without an anchor still need an account-specific
-- usage key. They must not share the old YYYY-MM counter across customers.
do $$
declare a public.billing_accounts; k text;
begin
  for a in select * from public.billing_accounts where plan in ('monthly','annual')
    and (credit_period is null or credit_period not like 'legacy:%') loop
    k:='legacy:'||a.device_hash||':'||coalesce(a.credit_period,'unknown');
    insert into public.billing_plan_period_usage(period_key,used) values(k,a.plan_used);
    update public.billing_credit_reservations set plan_period=k
      where device_hash=a.device_hash and credit_source='plan' and plan_period is not distinct from a.credit_period;
    update public.billing_accounts set credit_period=k where device_hash=a.device_hash;
  end loop;
end;$$;

create or replace function public.refresh_billing_period(p_device_hash text)
returns public.billing_accounts language plpgsql security definer set search_path=public as $$
declare a public.billing_accounts; c public.billing_subscription_cycles; w record; k text; spent integer;
begin
  perform pg_advisory_xact_lock(hashtextextended('billing_webhooks_v81',0));
  insert into public.billing_accounts(device_hash) values(p_device_hash) on conflict do nothing;
  select * into a from public.billing_accounts where device_hash=p_device_hash for update;
  select * into c from public.billing_subscription_cycles
    where account_hash=p_device_hash and not revoked and started_at<=now() and access_expires_at>now()
    order by started_at desc,last_event_at desc limit 1;
  if found then
    select * into w from public.billing_allowance_window(c.plan,c.started_at,c.paid_expires_at,now());
    k:=public.billing_period_key(c.contract_hash,w.period_start);
    insert into public.billing_plan_period_usage(period_key) values(k) on conflict do nothing;
    select used into spent from public.billing_plan_period_usage where period_key=k;
    update public.billing_accounts set plan=c.plan,entitlement_expires_at=c.access_expires_at,
      subscription_started_at=c.started_at,credit_period=k,plan_limit=30,plan_used=spent,
      allowance_started_at=w.period_start,allowance_expires_at=w.period_end,updated_at=now()
      where device_hash=p_device_hash returning * into a;
  elsif a.plan in ('monthly','annual') and a.entitlement_expires_at>now() then
    -- A legacy row without usable purchase dates keeps its old balance, without a clock reset.
    null;
  elsif a.plan<>'free' or a.entitlement_expires_at is not null then
    update public.billing_accounts set plan='free',entitlement_expires_at=null,plan_limit=0,updated_at=now()
      where device_hash=p_device_hash returning * into a;
  end if;
  return a;
end;$$;

create function public.record_billing_cycle(
 p_account text,p_contract text,p_plan text,p_start timestamptz,p_end timestamptz,p_event_at timestamptz
) returns void language plpgsql security definer set search_path=public as $$
declare a public.billing_accounts; w record; k text; old_key text; old_used integer;
begin
  if length(p_contract)<>64 or p_plan not in ('monthly','annual') or p_start is null
    or p_end is null or p_start>=p_end then raise exception 'invalid_store_cycle'; end if;
  perform pg_advisory_xact_lock(hashtextextended('billing_webhooks_v81',0));
  insert into public.billing_accounts(device_hash) values(p_account) on conflict do nothing;
  select * into a from public.billing_accounts where device_hash=p_account for update;
  -- An overlapping legacy balance is adopted once, including any in-flight reservations.
  if p_start<=now() and p_end>now() and
     (a.credit_period like 'legacy:%' or a.credit_period ~ '^\d{4}-\d{2}$') then
    old_key:=a.credit_period; old_used:=a.plan_used;
    if exists(select 1 from public.billing_subscription_cycles where account_hash=p_account
      and contract_hash like 'legacy:%' and not revoked and started_at<p_end and paid_expires_at>p_start)
      or (a.entitlement_expires_at>p_start and a.credit_period like 'legacy:%') then
      select * into w from public.billing_allowance_window(p_plan,p_start,p_end,now());
      k:=public.billing_period_key(p_contract,w.period_start);
      insert into public.billing_plan_period_usage(period_key,used) values(k,old_used)
        on conflict(period_key) do update set used=greatest(billing_plan_period_usage.used,excluded.used);
      update public.billing_credit_reservations set plan_period=k
        where device_hash=p_account and credit_source='plan' and plan_period=old_key;
    end if;
  end if;
  insert into public.billing_subscription_cycles(contract_hash,started_at,paid_expires_at,access_expires_at,
    account_hash,plan,last_event_at) values(p_contract,p_start,p_end,p_end,p_account,p_plan,p_event_at)
    on conflict(contract_hash,started_at) do update set
      paid_expires_at=excluded.paid_expires_at,access_expires_at=excluded.access_expires_at,
      account_hash=excluded.account_hash,plan=excluded.plan,last_event_at=excluded.last_event_at,revoked=false
      where billing_subscription_cycles.last_event_at<=excluded.last_event_at;
  -- Do not fall back to a legacy entitlement after the verified contract has expired.
  update public.billing_subscription_cycles set revoked=true
    where account_hash=p_account and contract_hash like 'legacy:%' and started_at<p_end and paid_expires_at>p_start;
  perform public.refresh_billing_period(p_account);
end;$$;

-- Legacy RPC callers can no longer create a calendar-month grant without a contract.
create or replace function public.activate_billing_plan(
 p_device_hash text,p_plan text,p_started_at timestamptz,p_expires_at timestamptz
) returns void language plpgsql security definer set search_path=public as $$
begin raise exception 'store_cycle_required'; end;$$;

create or replace function public.expire_billing_plan(p_device_hash text)
returns void language plpgsql security definer set search_path=public as $$
begin
  perform pg_advisory_xact_lock(hashtextextended('billing_webhooks_v81',0));
  update public.billing_subscription_cycles set revoked=true
    where account_hash=p_device_hash and started_at<=now();
  update public.billing_accounts set plan='free',entitlement_expires_at=null,plan_limit=0,updated_at=now()
    where device_hash=p_device_hash;
end;$$;

create or replace function public.billing_status(p_device_hash text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare a public.billing_accounts; f integer; p integer; next_at timestamptz;
begin
  a:=public.refresh_billing_period(p_device_hash);
  f:=greatest(a.free_limit-a.free_used,0);
  p:=case when a.plan in ('monthly','annual') then greatest(a.plan_limit-a.plan_used,0) else 0 end;
  if a.plan in ('monthly','annual') and a.allowance_expires_at>now() then
    next_at:=a.allowance_expires_at;
  end if;
  return jsonb_build_object('plan',a.plan,'included_remaining',f+p,'free_remaining',f,
    'plan_remaining',p,'bonus_credits',a.bonus_credits,'remaining',f+p+a.bonus_credits,
    'entitlement_expires_at',a.entitlement_expires_at,'credit_period',a.credit_period,
    'allowance_started_at',a.allowance_started_at,'next_credit_reset_at',next_at,
    'credit_reset_requires_renewal',a.plan='monthly' or
      (a.plan='annual' and a.allowance_expires_at>=a.entitlement_expires_at));
end;$$;

create or replace function public.reserve_billing_credit(p_device_hash text,p_job_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare a public.billing_accounts; source text; spent integer;
begin
  perform pg_advisory_xact_lock(hashtextextended('billing_webhooks_v81',0));
  if length(p_device_hash)<>64 then return jsonb_build_object('allowed',false); end if;
  a:=public.refresh_billing_period(p_device_hash);
  if exists(select 1 from public.billing_credit_reservations where job_id=p_job_id) then
    return public.billing_status(p_device_hash)||jsonb_build_object('allowed',true,'reused',true);
  end if;
  if a.plan in ('monthly','annual') and a.plan_used<a.plan_limit then
    insert into public.billing_plan_period_usage(period_key,used) values(a.credit_period,a.plan_used)
      on conflict do nothing;
    update public.billing_plan_period_usage set used=used+1,updated_at=now()
      where period_key=a.credit_period and used<30 returning used into spent;
    if not found then return public.billing_status(p_device_hash)||jsonb_build_object('allowed',false); end if;
    update public.billing_accounts set plan_used=spent,updated_at=now() where device_hash=p_device_hash;
    source:='plan';
  elsif a.free_used<a.free_limit then
    update public.billing_accounts set free_used=free_used+1,updated_at=now() where device_hash=p_device_hash;
    source:='free';
  elsif a.bonus_credits>0 then
    update public.billing_accounts set bonus_credits=bonus_credits-1,updated_at=now() where device_hash=p_device_hash;
    source:='bonus';
  else return public.billing_status(p_device_hash)||jsonb_build_object('allowed',false);
  end if;
  insert into public.billing_credit_reservations(job_id,device_hash,credit_source,plan_period)
    values(p_job_id,p_device_hash,source,case when source='plan' then a.credit_period else null end);
  return public.billing_status(p_device_hash)||jsonb_build_object('allowed',true);
end;$$;

create or replace function public.refund_billing_credit(p_job_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare r public.billing_credit_reservations; spent integer;
begin
  perform pg_advisory_xact_lock(hashtextextended('billing_webhooks_v81',0));
  select * into r from public.billing_credit_reservations where job_id=p_job_id for update;
  if r.status is distinct from 'reserved' then return; end if;
  if r.credit_source='plan' then
    update public.billing_plan_period_usage set used=greatest(used-1,0),updated_at=now()
      where period_key=r.plan_period returning used into spent;
    update public.billing_accounts set plan_used=coalesce(spent,greatest(plan_used-1,0)),updated_at=now()
      where device_hash=r.device_hash and credit_period=r.plan_period;
  elsif r.credit_source='free' then
    update public.billing_accounts set free_used=greatest(free_used-1,0),updated_at=now() where device_hash=r.device_hash;
  else
    update public.billing_accounts set bonus_credits=bonus_credits+1,updated_at=now() where device_hash=r.device_hash;
  end if;
  update public.billing_credit_reservations set status='refunded',updated_at=now() where job_id=p_job_id;
end;$$;

create or replace function public.apply_billing_webhook(
 p_event_id text,p_type text,p_customer_hash text,p_product text,p_payload jsonb,
 p_plan text,p_started_at timestamptz,p_expires_at timestamptz,p_event_at timestamptz,
 p_contract_hash text,p_from_hashes text[],p_to_hashes text[],p_bonus boolean
) returns void language plpgsql security definer set search_path=public as $$
declare target_hash text; source_hash text; targets text[]; a public.billing_accounts;
 event_applies boolean; grace_at timestamptz; affected integer;
begin
  if p_event_id='' or p_event_at is null then raise exception 'invalid_webhook'; end if;
  perform pg_advisory_xact_lock(hashtextextended('billing_webhooks_v81',0));
  if exists(select 1 from public.revenuecat_webhook_events where event_id=p_event_id) then return; end if;
  if p_type='TRANSFER' then
    select array_agg(distinct coalesce(l.account_hash,h.hash)) into targets
      from unnest(p_to_hashes) as h(hash) left join public.billing_customer_links l on l.customer_hash=h.hash;
    if coalesce(cardinality(targets),0)<>1 then raise exception 'transfer_target_unresolved'; end if;
    target_hash:=targets[1];
    insert into public.billing_accounts(device_hash) values(target_hash) on conflict do nothing;
    select * into a from public.billing_accounts where device_hash=target_hash for update;
    for source_hash in select distinct coalesce(l.account_hash,h.hash)
      from unnest(p_from_hashes) as h(hash) left join public.billing_customer_links l on l.customer_hash=h.hash loop
      if source_hash=target_hash then continue; end if;
      if not exists(select 1 from public.billing_accounts where device_hash=source_hash) then
        raise exception 'transfer_source_unresolved'; end if;
      if coalesce(a.billing_event_at,'-infinity')>p_event_at or exists(
        select 1 from public.billing_accounts where device_hash=source_hash and billing_event_at>p_event_at) then continue; end if;
      update public.billing_subscription_cycles set account_hash=target_hash,last_event_at=greatest(last_event_at,p_event_at)
        where account_hash=source_hash and last_event_at<=p_event_at;
      update public.billing_contract_links set account_hash=target_hash,last_event_at=p_event_at
        where account_hash=source_hash and last_event_at<=p_event_at;
      update public.billing_credit_reservations set device_hash=target_hash
        where device_hash=source_hash and credit_source='plan';
      update public.billing_accounts set plan='free',entitlement_expires_at=null,plan_limit=0,plan_used=0,
        billing_event_at=p_event_at,updated_at=now() where device_hash=source_hash;
    end loop;
    update public.billing_accounts set billing_event_at=p_event_at where device_hash=target_hash
      and coalesce(billing_event_at,'-infinity')<=p_event_at;
    perform public.refresh_billing_period(target_hash);
  else
    if length(p_customer_hash)<>64 then raise exception 'invalid_customer'; end if;
    select account_hash into target_hash from public.billing_customer_links where customer_hash=p_customer_hash;
    target_hash:=coalesce(target_hash,p_customer_hash);
    if p_contract_hash is not null then
      select account_hash into source_hash from public.billing_contract_links where contract_hash=p_contract_hash;
      target_hash:=coalesce(source_hash,target_hash);
    end if;
    insert into public.billing_accounts(device_hash) values(target_hash) on conflict do nothing;
    select * into a from public.billing_accounts where device_hash=target_hash for update;
    event_applies:=coalesce(a.billing_event_at,'-infinity')<=p_event_at;
    if p_bonus then
      if p_contract_hash is null then raise exception 'purchase_transaction_missing'; end if;
      if not exists(select 1 from public.billing_contract_links where contract_hash=p_contract_hash) then
        perform public.add_billing_bonus(target_hash,20);
        insert into public.billing_contract_links values(p_contract_hash,target_hash,p_event_at);
      end if;
    elsif event_applies then
      if p_plan in ('monthly','annual') and p_type in ('INITIAL_PURCHASE','RENEWAL','UNCANCELLATION') then
        -- The purchased_at date may be in the future even though the event arrived now.
        perform public.record_billing_cycle(target_hash,p_contract_hash,p_plan,p_started_at,p_expires_at,p_event_at);
        insert into public.billing_contract_links values(p_contract_hash,target_hash,p_event_at)
          on conflict(contract_hash) do update set account_hash=excluded.account_hash,
            last_event_at=greatest(billing_contract_links.last_event_at,excluded.last_event_at);
        update public.billing_accounts set billing_event_at=p_event_at where device_hash=target_hash;
      elsif p_type='SUBSCRIPTION_EXTENDED' and p_expires_at is not null then
        update public.billing_subscription_cycles set paid_expires_at=greatest(paid_expires_at,p_expires_at),
          access_expires_at=greatest(access_expires_at,p_expires_at),last_event_at=p_event_at
          where contract_hash=p_contract_hash and started_at=p_started_at and not revoked and last_event_at<=p_event_at;
        get diagnostics affected=row_count;
        if affected>0 then update public.billing_accounts set billing_event_at=p_event_at where device_hash=target_hash; end if;
        perform public.refresh_billing_period(target_hash);
      elsif p_type='BILLING_ISSUE' then
        grace_at:=nullif(p_payload->>'grace_expires_at','')::timestamptz;
        if grace_at is not null then
          -- Grace preserves the existing period's balance; it never creates a paid renewal.
          update public.billing_subscription_cycles set access_expires_at=greatest(access_expires_at,grace_at),
            last_event_at=p_event_at where contract_hash=p_contract_hash and started_at=p_started_at
            and not revoked and last_event_at<=p_event_at;
          get diagnostics affected=row_count;
          if affected>0 then update public.billing_accounts set billing_event_at=p_event_at where device_hash=target_hash; end if;
        end if;
        perform public.refresh_billing_period(target_hash);
      elsif p_type='EXPIRATION' then
        -- Expiration of an older cycle must not revoke a later confirmed renewal.
        update public.billing_subscription_cycles set revoked=true,last_event_at=p_event_at
          where contract_hash=p_contract_hash and started_at=p_started_at and last_event_at<=p_event_at;
        if a.subscription_started_at=p_started_at and a.entitlement_expires_at<=coalesce(p_expires_at,now()) then
          update public.billing_accounts set plan='free',entitlement_expires_at=null,plan_limit=0,
            billing_event_at=p_event_at,updated_at=now() where device_hash=target_hash;
        end if;
        perform public.refresh_billing_period(target_hash);
      end if;
      -- PRODUCT_CHANGE is only a scheduled change; CANCELLATION alone does not end access.
    end if;
  end if;
  insert into public.revenuecat_webhook_events(event_id,event_type,app_user_id,product_id,payload)
    values(p_event_id,p_type,null,p_product,p_payload);
end;$$;

revoke all on function public.billing_allowance_window(text,timestamptz,timestamptz,timestamptz) from public;
revoke all on function public.billing_period_key(text,timestamptz) from public;
revoke all on function public.record_billing_cycle(text,text,text,timestamptz,timestamptz,timestamptz) from public;
grant execute on function public.billing_allowance_window(text,timestamptz,timestamptz,timestamptz) to service_role;
grant execute on function public.billing_period_key(text,timestamptz) to service_role;
grant execute on function public.record_billing_cycle(text,text,text,timestamptz,timestamptz,timestamptz) to service_role;

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
      update public.billing_subscription_cycles set account_hash=p_user_hash where account_hash=source_hash;
      delete from public.billing_accounts where device_hash = source_hash;
    end if;
  end if;

  insert into public.billing_device_links(device_hash, account_hash, user_id)
  values (p_device_hash, p_user_hash, p_user_id)
  on conflict (device_hash) do update set
    account_hash = excluded.account_hash,
    user_id = excluded.user_id,
    linked_at = now();
  perform public.refresh_billing_period(p_user_hash);
  return p_user_hash;
end;
$$;



notify pgrst, 'reload schema';
