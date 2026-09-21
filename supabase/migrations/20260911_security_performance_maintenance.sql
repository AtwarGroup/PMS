begin;

-- Cache auth.uid() once per statement instead of recalculating it for every row.
alter policy profiles_select_policy on public.profiles
using (private.current_user_is_active() and (id=(select auth.uid()) or private.is_admin() or private.manages_user(id)));

alter policy tasks_insert_policy on public.tasks
with check (
  private.current_user_is_active() and creator_id=(select auth.uid())
  and private.user_is_active(assignee_id) and revision=1
  and (private.is_admin() or assignee_id=(select auth.uid()) or (private.current_user_role()='manager' and private.manages_user(assignee_id)))
  and (private.is_admin() or status='قيد الانتظار')
);

alter policy notifications_select_policy on public.notifications
using (private.current_user_is_active() and recipient_id=(select auth.uid()));
alter policy notifications_delete_policy on public.notifications
using (private.current_user_is_active() and recipient_id=(select auth.uid()));

alter policy follow_ups_select_policy on public.follow_ups
using (private.current_user_is_active() and owner_id=(select auth.uid()));
alter policy follow_ups_insert_policy on public.follow_ups
with check (private.current_user_is_active() and owner_id=(select auth.uid()));
alter policy follow_ups_update_policy on public.follow_ups
using (private.current_user_is_active() and owner_id=(select auth.uid()))
with check (private.current_user_is_active() and owner_id=(select auth.uid()));
alter policy follow_ups_delete_policy on public.follow_ups
using (private.current_user_is_active() and owner_id=(select auth.uid()));

alter policy quick_notes_select_policy on public.quick_notes
using (private.current_user_is_active() and owner_id=(select auth.uid()));
alter policy quick_notes_insert_policy on public.quick_notes
with check (private.current_user_is_active() and owner_id=(select auth.uid()));
alter policy quick_notes_update_policy on public.quick_notes
using (private.current_user_is_active() and owner_id=(select auth.uid()))
with check (private.current_user_is_active() and owner_id=(select auth.uid()));
alter policy quick_notes_delete_policy on public.quick_notes
using (private.current_user_is_active() and owner_id=(select auth.uid()));

alter policy task_attachments_insert_policy on public.task_attachments
with check (uploader_id=(select auth.uid()) and private.can_edit_task_content(task_id));
alter policy task_comments_insert_policy on public.task_comments
with check (author_id=(select auth.uid()) and private.can_view_task(task_id));
alter policy task_comments_update_policy on public.task_comments
using (author_id=(select auth.uid())) with check (author_id=(select auth.uid()));
alter policy task_comments_delete_policy on public.task_comments
using (author_id=(select auth.uid()) or private.is_admin());

alter policy recurring_templates_select_policy on public.recurring_task_templates
using (owner_id=(select auth.uid()) or private.is_admin());
alter policy recurring_templates_update_policy on public.recurring_task_templates
using (owner_id=(select auth.uid()) or private.is_admin())
with check (owner_id=(select auth.uid()) or private.is_admin());
alter policy recurring_templates_delete_policy on public.recurring_task_templates
using (owner_id=(select auth.uid()) or private.is_admin());
alter policy recurring_templates_write_policy on public.recurring_task_templates
with check (
  owner_id=(select auth.uid()) and (private.current_user_role()='manager' or private.is_admin())
  and private.user_is_active(assignee_id)
  and (private.is_admin() or assignee_id=(select auth.uid()) or private.manages_user(assignee_id))
);

-- These routines do not need to bypass RLS; execute with the caller's permissions.
alter function public.admin_update_profile_safe(uuid,text,text,text,text,text,uuid) security invoker;
alter function public.workspace_add_followup(text,date,text) security invoker;
alter function public.workspace_complete_followup(uuid) security invoker;
alter function public.workspace_delete_followup(uuid) security invoker;
alter function public.workspace_save_note(text) security invoker;

-- Retire the legacy hard-delete overload. The application uses the audited
-- two-argument soft-delete routine, including when the reason is empty.
revoke all on function public.delete_task_safe(uuid) from public, anon, authenticated;

commit;
