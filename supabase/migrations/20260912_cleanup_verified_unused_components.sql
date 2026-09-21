begin;

-- The application uses only the audited two-argument soft-delete RPC.
-- This revoked legacy overload has no database dependencies or client references.
drop function if exists public.delete_task_safe(uuid);

-- Keep Realtime publication limited to tables with active subscribers.
alter publication supabase_realtime drop table public.quick_notes;
alter publication supabase_realtime drop table public.follow_ups;
alter publication supabase_realtime drop table public.task_comments;

-- Task details actively subscribe to activity changes.
alter publication supabase_realtime add table public.task_activity;

-- Trigger routines execute through their triggers only; clients never call them.
revoke all on function private.create_comment_notifications() from public, anon, authenticated;
revoke all on function private.log_task_attachment_activity() from public, anon, authenticated;
revoke all on function private.log_task_comment_activity() from public, anon, authenticated;
revoke all on function private.validate_task_dates() from public, anon, authenticated;
revoke all on function public.set_updated_at() from public, anon, authenticated;
revoke all on function public.sync_followup_legacy_columns() from public, anon, authenticated;
revoke all on function public.sync_quick_note_legacy_columns() from public, anon, authenticated;

commit;
