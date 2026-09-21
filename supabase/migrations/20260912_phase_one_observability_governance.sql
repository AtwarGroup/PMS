begin;

create table if not exists public.app_error_logs (
  id bigint generated always as identity primary key,
  actor_id uuid references public.profiles(id) on delete set null,
  page_path text not null,
  error_type text not null default 'client_error',
  message text not null,
  stack text,
  user_agent text,
  created_at timestamptz not null default now()
);

alter table public.app_error_logs enable row level security;
revoke all on table public.app_error_logs from public, anon;
grant insert,select,delete on table public.app_error_logs to authenticated;
grant usage,select on sequence public.app_error_logs_id_seq to authenticated;

create policy app_error_logs_insert_own on public.app_error_logs
for insert to authenticated
with check (actor_id=(select auth.uid()) and char_length(message) between 1 and 2000);

create policy app_error_logs_admin_select on public.app_error_logs
for select to authenticated using (private.is_admin());

create policy app_error_logs_admin_delete on public.app_error_logs
for delete to authenticated using (private.is_admin());

create index if not exists app_error_logs_created_idx
on public.app_error_logs(created_at desc);
create index if not exists app_error_logs_actor_id_idx
on public.app_error_logs(actor_id);

grant select,update on public.email_notification_outbox to authenticated;
drop policy if exists email_notification_outbox_deny_clients
on public.email_notification_outbox;
create policy email_notification_outbox_admin_select
on public.email_notification_outbox for select to authenticated
using (private.is_admin());
create policy email_notification_outbox_admin_retry
on public.email_notification_outbox for update to authenticated
using (private.is_admin())
with check (private.is_admin());

commit;
