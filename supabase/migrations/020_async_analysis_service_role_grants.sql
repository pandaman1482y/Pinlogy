-- Background analysis is written only by enqueue-analysis. RLS intentionally
-- exposes no client policy, while the Edge Function's service role receives
-- the SQL privileges required to create and update jobs.
grant usage on schema public to service_role;
grant select, insert, update, delete
  on table public.async_analysis_jobs
  to service_role;

