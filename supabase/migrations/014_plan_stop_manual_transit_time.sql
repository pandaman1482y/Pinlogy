alter table public.plan_stops
  add column if not exists transit_time_is_manual boolean not null default false;
