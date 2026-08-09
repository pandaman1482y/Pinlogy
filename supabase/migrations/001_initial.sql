-- Pinlogy initial schema for Supabase / PostgreSQL
-- 有料APIキーはここに置かず、Edge Functions の secrets で管理してください。

create extension if not exists "pgcrypto";

create table if not exists public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.maps (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.users(id) on delete cascade,
  name text not null,
  description text not null default '',
  icon text not null default '📍',
  theme_color int not null default 15264748,
  is_public boolean not null default false,
  allows_collaboration boolean not null default false,
  last_latitude double precision,
  last_longitude double precision,
  last_zoom double precision,
  sort_settings jsonb,
  filter_settings jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.places (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.users(id) on delete cascade,
  name text not null,
  formal_name text,
  address text,
  prefecture text,
  city text,
  area text,
  nearest_station text,
  building text,
  floor text,
  category text,
  latitude double precision,
  longitude double precision,
  external_place_id text,
  save_reason text,
  user_memo text,
  recommended_items text,
  notes_from_post text,
  extracted_address text,
  evidence_summary text,
  confidence_percent int,
  visit_status text not null default 'wantToGo',
  visit_count int not null default 0,
  first_visited_at timestamptz,
  last_visited_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.map_places (
  id uuid primary key default gen_random_uuid(),
  map_id uuid not null references public.maps(id) on delete cascade,
  place_id uuid not null references public.places(id) on delete cascade,
  added_at timestamptz not null default now(),
  unique (map_id, place_id)
);

create table if not exists public.source_posts (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.users(id) on delete cascade,
  url text,
  service text,
  title text,
  body text,
  image_paths text[] not null default '{}',
  received_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.place_sources (
  id uuid primary key default gen_random_uuid(),
  place_id uuid not null references public.places(id) on delete cascade,
  source_post_id uuid not null references public.source_posts(id) on delete cascade,
  linked_at timestamptz not null default now(),
  unique (place_id, source_post_id)
);

create table if not exists public.analysis_jobs (
  id uuid primary key default gen_random_uuid(),
  source_post_id uuid not null references public.source_posts(id) on delete cascade,
  status text not null default 'pending',
  error_message text,
  result_json jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.tags (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.users(id) on delete cascade,
  name text not null,
  unique (owner_id, name)
);

create table if not exists public.place_tags (
  id uuid primary key default gen_random_uuid(),
  place_id uuid not null references public.places(id) on delete cascade,
  tag_id uuid not null references public.tags(id) on delete cascade,
  unique (place_id, tag_id)
);

create table if not exists public.map_members (
  id uuid primary key default gen_random_uuid(),
  map_id uuid not null references public.maps(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  role text not null default 'viewer',
  joined_at timestamptz not null default now(),
  unique (map_id, user_id)
);

create index if not exists idx_map_places_map on public.map_places(map_id);
create index if not exists idx_map_places_place on public.map_places(place_id);
create index if not exists idx_places_owner on public.places(owner_id);
create index if not exists idx_source_posts_owner on public.source_posts(owner_id);
create index if not exists idx_analysis_jobs_source on public.analysis_jobs(source_post_id);

alter table public.maps enable row level security;
alter table public.places enable row level security;
alter table public.map_places enable row level security;
alter table public.source_posts enable row level security;
alter table public.place_sources enable row level security;
alter table public.analysis_jobs enable row level security;
alter table public.tags enable row level security;
alter table public.place_tags enable row level security;
alter table public.map_members enable row level security;

-- 基本ポリシー例（所有者のみ）。共同編集は map_members を拡張して追加する。
create policy maps_owner_all on public.maps
  for all using (auth.uid() = owner_id) with check (auth.uid() = owner_id);

create policy places_owner_all on public.places
  for all using (auth.uid() = owner_id) with check (auth.uid() = owner_id);
