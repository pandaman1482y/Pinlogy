-- Recipe app v1. Structured client state is kept in a private per-user
-- snapshot so iOS and Android can share one account without exposing data.
create table if not exists public.recipe_snapshots (
  owner_id uuid primary key references public.users(id) on delete cascade,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.recipe_snapshots enable row level security;

create policy recipe_snapshots_owner_all on public.recipe_snapshots
  for all
  using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

-- Analysis corrections are stored separately so users can delete their
-- recipe snapshot without losing an explicitly shared quality report.
create table if not exists public.recipe_analysis_feedback (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.users(id) on delete cascade,
  recipe_id text not null,
  feedback_type text not null,
  comment text,
  created_at timestamptz not null default now()
);

alter table public.recipe_analysis_feedback enable row level security;

create policy recipe_analysis_feedback_owner_all
  on public.recipe_analysis_feedback
  for all
  using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

create index if not exists idx_recipe_feedback_owner_created
  on public.recipe_analysis_feedback(owner_id, created_at desc);
