grant select on table public.blocked_social_sources to service_role;

notify pgrst, 'reload schema';
