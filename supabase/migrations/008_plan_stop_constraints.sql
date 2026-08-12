alter table public.plan_stops
  add column if not exists transit_buffer_minutes integer not null default 0
    check (transit_buffer_minutes between 0 and 180),
  add column if not exists reservation_time_minutes integer
    check (reservation_time_minutes between 0 and 1439),
  add column if not exists arrival_deadline_minutes integer
    check (arrival_deadline_minutes between 0 and 1439);
