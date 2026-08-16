-- 同じ端末・同じ入力の再解析でAI料金を二重に発生させない。
create table if not exists public.ai_analysis_cache (
  device_hash text not null,
  analysis_key text not null,
  result_json jsonb not null,
  expires_at timestamptz not null default (now() + interval '30 days'),
  created_at timestamptz not null default now(),
  primary key (device_hash, analysis_key)
);

create index if not exists ai_analysis_cache_expires_at_idx
  on public.ai_analysis_cache (expires_at);

alter table public.ai_analysis_cache enable row level security;
revoke all on table public.ai_analysis_cache from anon, authenticated;
grant select, insert, update, delete on table public.ai_analysis_cache to service_role;
