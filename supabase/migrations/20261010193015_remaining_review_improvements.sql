-- Durable deletion intentions; object removal is performed exclusively through Storage API.
create table public.task_attachment_cleanup (
 id uuid primary key default gen_random_uuid(), attachment_id uuid not null unique,
 task_id uuid not null, storage_path text not null, requested_by uuid not null references public.profiles(id),
 requested_at timestamptz not null default now(), attempts integer not null default 0,
 last_error text, completed_at timestamptz
);
alter table public.task_attachment_cleanup enable row level security;
revoke all on public.task_attachment_cleanup from public,anon,authenticated;
grant select on public.task_attachment_cleanup to authenticated;
grant all on public.task_attachment_cleanup to service_role;
create index task_attachment_cleanup_requester on public.task_attachment_cleanup(requested_by);
create policy attachment_cleanup_read on public.task_attachment_cleanup for select to authenticated using(requested_by=(select auth.uid()) and private.current_user_is_active());
create function private.queue_attachment_cleanup() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.task_attachment_cleanup(attachment_id,task_id,storage_path,requested_by)
 values(old.id,old.task_id,old.storage_path,coalesce(auth.uid(),old.uploader_id)) on conflict(attachment_id) do nothing;
 return old;
end $$;
revoke all on function private.queue_attachment_cleanup() from public,anon,authenticated;
create trigger queue_attachment_cleanup after delete on public.task_attachments for each row execute function private.queue_attachment_cleanup();

-- Manager-only aggregation counts current published versions, never old acknowledgements.
create function private.job_acknowledgement_followup() returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); result jsonb; admin boolean;
begin
 if actor is null or not private.current_user_is_active() then raise exception 'Active account required' using errcode='42501';end if;
 admin:=private.is_admin();
 if not admin and not exists(select 1 from public.profiles where id=actor and role='manager') then raise exception 'Manager required' using errcode='42501';end if;
 select coalesce(jsonb_agg(jsonb_build_object('profile_id',p.id,'name',p.full_name,'job_id',j.id,'title',j.title,'revision',j.published_snapshot->>'revision',
 'accepted',exists(select 1 from public.job_description_acknowledgements k where k.profile_id=p.id and k.job_description_id=j.id and k.job_revision=(j.published_snapshot->>'revision')::integer and k.accepted_at>=a.assigned_at),
 'published',j.published_snapshot is not null,'review_due',r.due_on,'review_enabled',coalesce(r.enabled,false)) order by p.full_name),'[]'::jsonb) into result
 from public.profiles p left join public.employee_job_assignments a on a.profile_id=p.id
 left join public.job_descriptions j on j.id=a.job_description_id
 left join public.job_periodic_reviews r on r.job_description_id=j.id
 where p.active and p.status='active' and p.role<>'admin' and p.id<>actor and (admin or p.manager_id=actor);
 return result;
end $$;
revoke all on function private.job_acknowledgement_followup() from public,anon,authenticated;
grant execute on function private.job_acknowledgement_followup() to authenticated;
create function public.job_acknowledgement_followup() returns jsonb language sql security invoker set search_path='' as $$select private.job_acknowledgement_followup();$$;
revoke all on function public.job_acknowledgement_followup() from public,anon;
grant execute on function public.job_acknowledgement_followup() to authenticated;

create table public.approval_followup_settings (
 id boolean primary key default true check(id),enabled boolean not null default false,
 reminder_days integer not null default 2 check(reminder_days between 1 and 90),
 escalation_days integer not null default 5 check(escalation_days between 2 and 180 and escalation_days>reminder_days),
 revision integer not null default 1
);
insert into public.approval_followup_settings(id) values(true);
alter table public.approval_followup_settings enable row level security;
revoke all on public.approval_followup_settings from public,anon,authenticated;
grant select,update on public.approval_followup_settings to authenticated;
create policy followup_settings_read on public.approval_followup_settings for select to authenticated using(private.current_user_is_active());
create policy followup_settings_write on public.approval_followup_settings for update to authenticated using(private.is_admin()) with check(private.is_admin());
create table private.approval_followup_sent (
 task_id uuid not null references public.tasks(id) on delete cascade, submitted_at timestamptz not null,
 recipient_id uuid not null references public.profiles(id),stage text not null check(stage in ('reminder','escalation')),
 primary key(task_id,submitted_at,recipient_id,stage)
);
create index approval_followup_sent_recipient on private.approval_followup_sent(recipient_id);
alter table private.approval_followup_sent enable row level security;
revoke all on private.approval_followup_sent from public,anon,authenticated;
create function private.process_approval_followups(p_only_task uuid default null) returns integer language plpgsql security definer set search_path='' as $$
declare cfg public.approval_followup_settings%rowtype;t record; recipient uuid; escalated uuid; sent integer:=0; age integer;stage text;
begin
 if not pg_try_advisory_xact_lock(1010102026) then return 0;end if;
 select * into cfg from public.approval_followup_settings where id;
 if not cfg.enabled then return 0;end if;
 for t in select x.*,p.manager_id as assignee_manager,pr.manager_id as project_manager,pr.sponsor_id as project_sponsor,pr.status as project_status
 from public.tasks x join public.profiles p on p.id=x.assignee_id left join public.projects pr on pr.id=x.project_id
 where (p_only_task is null or x.id=p_only_task) and x.status='بانتظار الاعتماد' and x.deleted_at is null and x.submitted_at is not null and x.task_type<>'job_workflow'
 for update of x skip locked loop
  age:=(now() at time zone 'Asia/Riyadh')::date-(t.submitted_at at time zone 'Asia/Riyadh')::date;
  if age<cfg.reminder_days then continue;end if;
  if t.project_id is not null then
   if t.project_status in ('CLOSED','CANCELLED') then continue;end if;
   recipient:=case when t.assignee_id=t.project_manager then t.project_sponsor else t.project_manager end;
  else recipient:=case when coalesce(t.approval_commissioner_id,t.creator_id)<>t.assignee_id then coalesce(t.approval_commissioner_id,t.creator_id) else t.assignee_manager end;end if;
  if recipient is null or recipient=t.assignee_id or not exists(select 1 from public.profiles where id=recipient and active and status='active') then continue;end if;
  insert into private.approval_followup_sent values(t.id,t.submitted_at,recipient,'reminder') on conflict do nothing;
  if found then insert into public.notifications(recipient_id,task_id,type,title,message) values(recipient,t.id,'approval_reminder','تذكير بإجراء الاعتماد','تنتظر المهمة قرارك منذ '||age||' أيام: '||t.title);sent:=sent+1;end if;
  if age>=cfg.escalation_days then
   select manager_id into escalated from public.profiles where id=recipient;
   -- Escalation follows the reporting line only when the recipient already has task visibility.
   if escalated is not null and escalated<>recipient and escalated<>t.assignee_id and exists(select 1 from public.profiles e where e.id=escalated and e.active and e.status='active' and
     (e.role='admin' or t.creator_id=e.id or t.assignee_manager=e.id or t.delegated_by_id=e.id or (t.project_id is not null and exists(select 1 from public.project_members m where m.project_id=t.project_id and m.user_id=e.id)) or e.id in(t.project_manager,t.project_sponsor))) then
    -- Nonmembers cannot receive project task details, even when they supervise the assignee.
    if t.project_id is null or exists(select 1 from public.profiles e where e.id=escalated and e.role='admin') or escalated in(t.project_manager,t.project_sponsor) or exists(select 1 from public.project_members where project_id=t.project_id and user_id=escalated) then
     insert into private.approval_followup_sent values(t.id,t.submitted_at,escalated,'escalation') on conflict do nothing;
     if found then insert into public.notifications(recipient_id,task_id,type,title,message) values(escalated,t.id,'approval_escalation','تصعيد انتظار الاعتماد','تحتاج متابعة قرار اعتماد المهمة؛ مدة الانتظار '||age||' أيام: '||t.title);sent:=sent+1;end if;
    end if;
   end if;
  end if;
 end loop;
 return sent;
end $$;
revoke all on function private.process_approval_followups(uuid) from public,anon,authenticated;
select cron.schedule('atwar_approval_followups','25 * * * *','select private.process_approval_followups();');
