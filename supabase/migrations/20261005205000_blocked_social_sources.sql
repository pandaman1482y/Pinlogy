-- Creator/post takedown registry. This is intentionally global: it prevents a
-- removed source from being imported again by another device/account.
create table if not exists public.blocked_social_sources (
  id uuid primary key default gen_random_uuid(),
  service text not null check (service in ('instagram', 'tiktok')),
  scope text not null check (scope in ('post', 'creator')),
  source_post_id text,
  owner_username_normalized text,
  original_url text,
  reason text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    (scope = 'post' and source_post_id is not null and owner_username_normalized is null)
    or
    (scope = 'creator' and owner_username_normalized is not null and source_post_id is null)
  )
);

create unique index if not exists blocked_social_sources_post_unique
  on public.blocked_social_sources (service, source_post_id)
  where scope = 'post' and active;

create unique index if not exists blocked_social_sources_creator_unique
  on public.blocked_social_sources (service, owner_username_normalized)
  where scope = 'creator' and active;

alter table public.blocked_social_sources enable row level security;

-- No client policy is created. Only service-role server functions and an
-- administrator using the Supabase dashboard may read or modify this table.
revoke all on table public.blocked_social_sources from anon, authenticated;

comment on table public.blocked_social_sources is
  'Global takedown list for SNS posts and creator usernames. Usernames may change.';

