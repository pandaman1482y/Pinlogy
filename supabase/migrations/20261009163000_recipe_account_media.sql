-- Private per-account recipe images. The first path segment is always auth.uid().
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'recipe-user-media',
  'recipe-user-media',
  false,
  2097152,
  array['image/jpeg']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists recipe_user_media_owner_select on storage.objects;
create policy recipe_user_media_owner_select on storage.objects
  for select to authenticated
  using (
    bucket_id = 'recipe-user-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists recipe_user_media_owner_insert on storage.objects;
create policy recipe_user_media_owner_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'recipe-user-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists recipe_user_media_owner_update on storage.objects;
create policy recipe_user_media_owner_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'recipe-user-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'recipe-user-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists recipe_user_media_owner_delete on storage.objects;
create policy recipe_user_media_owner_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'recipe-user-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
