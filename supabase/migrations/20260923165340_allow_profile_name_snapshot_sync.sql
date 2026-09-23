-- Synchronizing a profile name updates task display snapshots only. The task
-- workflow validator must not treat that internal synchronization as a user
-- edit to a task. Keep the bypass local to this trigger's task update.
create or replace function private.sync_profile_task_identity()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $function$
declare
  previous_migration_mode text;
begin
  if nullif(btrim(new.full_name), '') is not distinct from nullif(btrim(old.full_name), '') then
    return new;
  end if;

  previous_migration_mode := current_setting('app.migration_mode', true);
  perform set_config('app.migration_mode', 'on', true);
  update public.tasks
  set creator_name_snapshot = case when creator_id = new.id then new.full_name else creator_name_snapshot end,
      assignee_name_snapshot = case when assignee_id = new.id then new.full_name else assignee_name_snapshot end
  where creator_id = new.id or assignee_id = new.id;
  perform set_config('app.migration_mode', coalesce(previous_migration_mode, ''), true);
  return new;
end;
$function$;
