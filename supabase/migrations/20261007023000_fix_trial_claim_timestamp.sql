-- Keep the NULL assigned to account_deleted_at typed as timestamptz.
-- Without the explicit cast PostgreSQL can infer text for the INSERT source.
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
    if length(candidate_hash) <> 64 then
      raise exception 'invalid_trial_identity';
    end if;
    perform pg_advisory_xact_lock(hashtextextended(candidate_hash, 0));
    if exists (
      select 1
      from public.billing_trial_claims as claims
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

revoke all on function public.enforce_billing_trial_claim(text, uuid, text[]) from public;
grant execute on function public.enforce_billing_trial_claim(text, uuid, text[]) to service_role;

notify pgrst, 'reload schema';
