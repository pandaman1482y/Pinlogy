-- Keep completed analysis payloads small. Full carousel images are stored in
-- a private bucket and exposed to the owning device through short-lived URLs.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'recipe-analysis-media',
  'recipe-analysis-media',
  false,
  2097152,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

alter table public.async_analysis_jobs
  drop constraint if exists async_analysis_jobs_status_check;

alter table public.async_analysis_jobs
  add constraint async_analysis_jobs_status_check
  check (status in ('pending', 'processing', 'completed', 'failed', 'cancelled'));
