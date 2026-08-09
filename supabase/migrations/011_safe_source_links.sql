-- A deliberately narrow projection for links shared with map members.
-- It cannot contain post text, OCR, analysis, notes, or image paths.

create table if not exists public.shared_source_links (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.users(id) on delete cascade,
  map_id uuid not null references public.maps(id) on delete cascade,
  place_id uuid not null references public.places(id) on delete cascade,
  source_post_id uuid not null,
  url text not null check (url ~ '^https://'),
  service text,
  title text,
  received_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (map_id, place_id, source_post_id)
);

create index if not exists idx_shared_source_links_map
  on public.shared_source_links(map_id);

alter table public.shared_source_links enable row level security;

create policy shared_source_links_owner_all on public.shared_source_links
  for all using (auth.uid() = owner_id) with check (
    auth.uid() = owner_id and public.is_map_owner(map_id)
  );

create policy shared_source_links_member_select on public.shared_source_links
  for select using (
    auth.uid() = owner_id or public.is_map_member(map_id)
  );
