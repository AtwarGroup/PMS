begin;

create table if not exists public.email_notification_outbox (
  id uuid primary key default gen_random_uuid(),
  event_key text not null unique,
  task_id uuid not null references public.tasks(id) on delete cascade,
  recipient_id uuid not null references public.profiles(id),
  recipient_email text not null,
  event_type text not null check (event_type in ('assigned','reassigned','returned')),
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'pending' check (status in ('pending','processing','sent','failed')),
  attempts integer not null default 0 check (attempts between 0 and 10),
  next_attempt_at timestamptz not null default now(),
  provider_message_id text,
  last_error text,
  created_at timestamptz not null default now(),
  processed_at timestamptz,
  updated_at timestamptz not null default now()
);

alter table public.email_notification_outbox enable row level security;
revoke all on table public.email_notification_outbox from public, anon, authenticated;
grant all on table public.email_notification_outbox to service_role;

create index if not exists email_notification_outbox_pending_idx
on public.email_notification_outbox(status,next_attempt_at,created_at)
where status in ('pending','failed');
create index if not exists email_notification_outbox_task_idx
on public.email_notification_outbox(task_id);
create index if not exists email_notification_outbox_recipient_idx
on public.email_notification_outbox(recipient_id);

create policy email_notification_outbox_deny_clients
on public.email_notification_outbox for all to authenticated
using (false) with check (false);

create or replace function private.queue_task_assignment_email()
returns trigger
language plpgsql
security definer
set search_path='pg_catalog','public','private'
as $$
declare
  v_event text;
  v_email text;
  v_name text;
  v_actor_name text;
  v_key text;
begin
  if current_setting('app.migration_mode',true)='on' then return new; end if;

  if tg_op='INSERT' then
    v_event:='assigned';
  elsif old.assignee_id is distinct from new.assignee_id then
    v_event:='reassigned';
  elsif old.status='بانتظار الاعتماد' and new.status='قيد التنفيذ' then
    v_event:='returned';
  else
    return new;
  end if;

  select p.email,p.full_name into v_email,v_name
  from public.profiles p
  where p.id=new.assignee_id and p.active=true and p.status='active';
  if nullif(btrim(coalesce(v_email,'')),'') is null then return new; end if;

  select p.full_name into v_actor_name from public.profiles p where p.id=auth.uid();
  v_actor_name:=coalesce(v_actor_name,new.creator_name_snapshot,'إدارة النظام');
  v_key:=new.id::text||':'||v_event||':'||new.assignee_id::text||':'||coalesce(new.revision,1)::text;

  insert into public.email_notification_outbox(
    event_key,task_id,recipient_id,recipient_email,event_type,payload
  ) values (
    v_key,new.id,new.assignee_id,lower(btrim(v_email)),v_event,
    jsonb_build_object(
      'task_id',new.id,'title',new.title,'description',coalesce(new.description,''),
      'priority',coalesce(new.priority,'normal'),'start_date',new.start_date,
      'due_date',new.due_date,'assignee_name',coalesce(v_name,new.assignee_name_snapshot,'الموظف'),
      'actor_name',v_actor_name
    )
  ) on conflict(event_key) do nothing;
  return new;
end
$$;

revoke all on function private.queue_task_assignment_email() from public, anon, authenticated;

drop trigger if exists trg_queue_task_assignment_email on public.tasks;
create trigger trg_queue_task_assignment_email
after insert or update of assignee_id,status on public.tasks
for each row execute function private.queue_task_assignment_email();

commit;
