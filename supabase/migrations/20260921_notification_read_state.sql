begin;

alter table public.notifications
  add column if not exists read_at timestamptz;

create index if not exists notifications_recipient_unread_idx
  on public.notifications(recipient_id,created_at desc)
  where read_at is null;

revoke update on table public.notifications from anon;
grant update(read_at) on table public.notifications to authenticated;

drop policy if exists notifications_update_read_policy on public.notifications;
create policy notifications_update_read_policy
on public.notifications for update to authenticated
using (private.current_user_is_active() and recipient_id=(select auth.uid()))
with check (private.current_user_is_active() and recipient_id=(select auth.uid()));

commit;
