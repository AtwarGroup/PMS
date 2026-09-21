-- Keep operational task identity snapshots aligned with the canonical profile.
-- Historical activity/audit snapshots remain unchanged.

create or replace function private.sync_profile_task_identity()
returns trigger
language plpgsql
security definer
set search_path = 'pg_catalog', 'public', 'private'
as $$
begin
  if nullif(btrim(new.full_name),'') is not distinct from nullif(btrim(old.full_name),'') then
    return new;
  end if;

  update public.tasks
  set creator_name_snapshot = case when creator_id = new.id then new.full_name else creator_name_snapshot end,
      assignee_name_snapshot = case when assignee_id = new.id then new.full_name else assignee_name_snapshot end
  where creator_id = new.id or assignee_id = new.id;

  return new;
end;
$$;

revoke all on function private.sync_profile_task_identity() from public, anon, authenticated;

drop trigger if exists profiles_sync_task_identity on public.profiles;
create trigger profiles_sync_task_identity
after update of full_name on public.profiles
for each row execute function private.sync_profile_task_identity();

-- Repair existing operational snapshots without touching activity/audit history.
update public.tasks t
set assignee_name_snapshot = p.full_name
from public.profiles p
where p.id = t.assignee_id
  and nullif(btrim(t.assignee_name_snapshot),'') is distinct from nullif(btrim(p.full_name),'');

update public.tasks t
set creator_name_snapshot = p.full_name
from public.profiles p
where p.id = t.creator_id
  and nullif(btrim(t.creator_name_snapshot),'') is distinct from nullif(btrim(p.full_name),'');

-- Cover task-related foreign keys reported by the database advisor.
create index if not exists executive_task_access_log_viewer_id_idx
  on public.executive_task_access_log(viewer_id);
create index if not exists task_reschedule_requests_requester_id_idx
  on public.task_reschedule_requests(requester_id);
create index if not exists task_reschedule_requests_decided_by_idx
  on public.task_reschedule_requests(decided_by);
