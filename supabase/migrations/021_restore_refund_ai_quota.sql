-- Recreate the refund RPC in case an older migration was marked as applied
-- before the function reached the remote database. PostgREST must reload its
-- schema cache so the Edge Function can call the RPC immediately.
create or replace function public.refund_ai_quota(p_device_hash text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.ai_usage_daily
  set request_count = greatest(request_count - 1, 0),
      updated_at = now()
  where device_hash = p_device_hash
    and usage_date = current_date
    and request_count > 0;
end;
$$;

revoke all on function public.refund_ai_quota(text) from public;
grant usage on schema public to service_role;
grant execute on function public.refund_ai_quota(text) to service_role;

notify pgrst, 'reload schema';
