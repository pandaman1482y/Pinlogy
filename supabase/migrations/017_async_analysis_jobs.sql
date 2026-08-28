-- Background analysis jobs are service-role only. Clients access them through
-- enqueue-analysis with a device-bound identifier instead of direct table access.
create table if not exists public.async_analysis_jobs (
  id uuid primary key default gen_random_uuid(),
  source_post_id text not null,
  device_hash text not null,
  device_id text,
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'completed', 'failed')),
  request_json jsonb not null,
  result_json jsonb,
  error_message text,
  notification_token text,
  notification_enabled boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz
);

create index if not exists idx_async_analysis_jobs_device
  on public.async_analysis_jobs(device_hash, updated_at desc);
create index if not exists idx_async_analysis_jobs_status
  on public.async_analysis_jobs(status, created_at);

alter table public.async_analysis_jobs enable row level security;

-- No anon/authenticated policies by design. Edge Functions use service_role.
