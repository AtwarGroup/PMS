-- Apply the same deletion boundary to task RPCs and attachment access checks.
create or replace function private.can_view_task(target_task uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.current_user_is_active() and exists(select 1 from public.tasks t where t.id=target_task and t.deleted_at is null and (t.project_id is null or private.project_access(t.project_id)) and (t.creator_id=auth.uid() or t.assignee_id=auth.uid() or t.delegated_by_id=auth.uid() or private.is_admin() or private.manages_user(t.assignee_id) or (t.project_id is not null and private.project_access(t.project_id))))
$$;
