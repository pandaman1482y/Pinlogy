alter table public.places
  add column if not exists opening_time_minutes integer,
  add column if not exists closing_time_minutes integer,
  add column if not exists closed_weekdays integer[] not null default '{}';

alter table public.places
  drop constraint if exists places_opening_time_minutes_check,
  add constraint places_opening_time_minutes_check
    check (opening_time_minutes is null or opening_time_minutes between 0 and 1439),
  drop constraint if exists places_closing_time_minutes_check,
  add constraint places_closing_time_minutes_check
    check (closing_time_minutes is null or closing_time_minutes between 0 and 1439);
