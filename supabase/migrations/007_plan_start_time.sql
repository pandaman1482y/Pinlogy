alter table public.plans
  add column if not exists start_time_minutes integer not null default 540
  check (start_time_minutes between 0 and 1439);
