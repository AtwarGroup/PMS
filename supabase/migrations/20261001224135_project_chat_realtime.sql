-- Delivery uses the existing authenticated project-member SELECT policy.
-- No grants or policies change: each event remains subject to project_access.
do $$
begin
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='project_messages') then
  alter publication supabase_realtime add table public.project_messages;
 end if;
end $$;
