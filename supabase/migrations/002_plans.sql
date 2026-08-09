-- Plans / itinerary tables

create table if not exists public.plans (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.users(id) on delete cascade,
  title text not null,
  notes text not null default '',
  start_date date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.plan_stops (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references public.plans(id) on delete cascade,
  place_id uuid not null references public.places(id) on delete cascade,
  day_date date not null,
  sort_order int not null default 0,
  stay_minutes int,
  transit_to_next text,
  transit_minutes int,
  note text,
  created_at timestamptz not null default now()
);

create index if not exists idx_plans_owner on public.plans(owner_id);
create index if not exists idx_plan_stops_plan on public.plan_stops(plan_id);
create index if not exists idx_plan_stops_place on public.plan_stops(place_id);
create index if not exists idx_plan_stops_day on public.plan_stops(plan_id, day_date, sort_order);

alter table public.plans enable row level security;
alter table public.plan_stops enable row level security;

create policy plans_owner_all on public.plans
  for all using (auth.uid() = owner_id) with check (auth.uid() = owner_id);

create policy plan_stops_owner_all on public.plan_stops
  for all using (
    exists (
      select 1 from public.plans p
      where p.id = plan_id and p.owner_id = auth.uid()
    )
  ) with check (
    exists (
      select 1 from public.plans p
      where p.id = plan_id and p.owner_id = auth.uid()
    )
  );
