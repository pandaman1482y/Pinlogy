grant select, insert, update on table public.users to authenticated;

notify pgrst, 'reload schema';
