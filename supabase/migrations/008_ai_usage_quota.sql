-- A generous per-install safety ceiling. This is not a billing plan and does
-- not block normal use; it limits runaway clients and accidental retry loops.
create table if not exists public.ai_usage_daily (
  device_hash text not null,
  usage_date date not null default current_date,
  request_count integer not null default 0 check (request_count >= 0),
  updated_at timestamptz not null default now(),
  primary key (device_hash, usage_date)
);

alter table public.ai_usage_daily enable row level security;
revoke all on public.ai_usage_daily from public, anon, authenticated;

create or replace function public.consume_ai_quota(
  p_device_hash text,
  p_limit integer default 10
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  accepted_count integer;
begin
  if length(p_device_hash) <> 64 or p_limit < 1 or p_limit > 200 then
    return false;
  end if;

  insert into public.ai_usage_daily(device_hash, usage_date, request_count)
  values (p_device_hash, current_date, 1)
  on conflict (device_hash, usage_date) do update
    set request_count = ai_usage_daily.request_count + 1,
        updated_at = now()
    where ai_usage_daily.request_count < p_limit
  returning request_count into accepted_count;

  return accepted_count is not null and accepted_count <= p_limit;
end;
$$;

revoke all on function public.consume_ai_quota(text, integer) from public;
grant execute on function public.consume_ai_quota(text, integer) to service_role;

create index if not exists ai_usage_daily_cleanup_idx
  on public.ai_usage_daily(usage_date);
