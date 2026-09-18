-- 同じ端末・同じ投稿でpending/processingジョブが複数存在すると、
-- 古い結果による失敗表示と別ジョブからの完了通知が前後してしまう。
-- 既存重複は最新だけ残し、以後はDB制約でも二重登録を防止する。
with ranked_active_jobs as (
  select
    id,
    row_number() over (
      partition by device_hash, source_post_id
      order by updated_at desc, created_at desc, id desc
    ) as active_rank
  from public.async_analysis_jobs
  where status in ('pending', 'processing')
)
update public.async_analysis_jobs as jobs
set
  status = 'cancelled',
  error_message = null,
  completed_at = now(),
  updated_at = now(),
  request_json = '{}'::jsonb,
  device_id = null,
  notification_token = null
from ranked_active_jobs as ranked
where jobs.id = ranked.id
  and ranked.active_rank > 1;

create unique index if not exists async_analysis_jobs_one_active_per_post
  on public.async_analysis_jobs (device_hash, source_post_id)
  where status in ('pending', 'processing');
