-- Equivalent task visibility with statement-scoped account checks and row-local ownership.
-- Keep deleted-record, project, module and active-account boundaries unchanged.
alter policy module_boundary on public.tasks using(
 (select private.module_allowed('tasks'))or(project_id is not null and(select private.module_allowed('projects')))
);
alter policy tasks_select_policy on public.tasks using(
 (
  (deleted_at is null and(select private.current_user_is_active())and(
   creator_id=(select auth.uid())or assignee_id=(select auth.uid())or delegated_by_id=(select auth.uid())or(select private.is_admin())
  ))or private.can_view_task(id)or(select private.has_permission('tasks.read_all'))
 )and(project_id is null or private.project_access(project_id))
);
