alter policy recurring_templates_update_policy on public.recurring_task_templates
using (owner_id=(select auth.uid()) or private.is_admin())
with check (
  (owner_id=(select auth.uid()) or private.is_admin())
  and private.user_is_active(assignee_id)
  and (private.is_admin() or assignee_id=(select auth.uid()) or (private.current_user_role()='manager' and private.manages_user(assignee_id)))
);
