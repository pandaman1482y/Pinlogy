-- A share-extension UUID changes for every share. Store a stable source key so
-- the same user's post cannot start or reserve two analyses concurrently.
alter table public.async_analysis_jobs
  add column if not exists source_key text,
  add column if not exists analysis_key text not null default 'default';

update public.async_analysis_jobs
set source_key = 'instagram:' ||
  (regexp_match(request_json->>'url',
    'instagram\.com/(?:share/)?(?:p|reel|reels|tv)/([A-Za-z0-9_-]{5,80})', 'i'))[1]
where source_key is null
  and request_json->>'url' ~* 'instagram\.com/(?:share/)?(?:p|reel|reels|tv)/[A-Za-z0-9_-]{5,80}';

update public.async_analysis_jobs
set source_key = 'tiktok:' ||
  (regexp_match(request_json->>'url', '/video/([0-9]{8,30})', 'i'))[1]
where source_key is null
  and request_json->>'url' ~* '/video/[0-9]{8,30}';

update public.async_analysis_jobs
set source_key = 'legacy:' || source_post_id
where source_key is null or btrim(source_key) = '';

alter table public.async_analysis_jobs
  alter column source_key set not null;

drop index if exists public.async_analysis_jobs_one_active_per_post;

with ranked_active_jobs as (
  select id,
    row_number() over (
      partition by device_hash, source_key
      order by updated_at desc, created_at desc, id desc
    ) as active_rank
  from public.async_analysis_jobs
  where status in ('pending', 'processing')
)
update public.async_analysis_jobs jobs
set status = 'cancelled', completed_at = now(), updated_at = now(),
  request_json = '{}'::jsonb, device_id = null, notification_token = null
from ranked_active_jobs ranked
where jobs.id = ranked.id and ranked.active_rank > 1;

create unique index if not exists async_analysis_jobs_one_active_per_source
  on public.async_analysis_jobs (device_hash, source_key)
  where status in ('pending', 'processing');

create index if not exists async_analysis_jobs_source_history
  on public.async_analysis_jobs (device_hash, source_key, updated_at desc);
