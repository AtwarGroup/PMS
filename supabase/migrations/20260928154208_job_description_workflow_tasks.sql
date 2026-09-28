begin;

-- A workflow task is a view of the authoritative job-library step, never an
-- independently completable operational task.
create table private.job_workflow_tasks (
  task_id uuid primary key references public.tasks(id) on delete cascade,
  job_description_id uuid not null references public.job_descriptions(id) on delete cascade,
  phase text not null check (phase in ('MANAGER_REVIEW','ADMIN_APPROVAL','EMPLOYEE_ACK')),
  cycle_key text not null,
  recipient_id uuid not null references public.profiles(id),
  unique (job_description_id,phase,cycle_key,recipient_id)
);
create index job_workflow_tasks_job_phase_idx on private.job_workflow_tasks(job_description_id,phase);
revoke all on private.job_workflow_tasks from public,anon,authenticated;

create or replace function private.guard_job_workflow_task()
returns trigger language plpgsql security definer
set search_path='pg_catalog','public','private' as $$
begin
  if (coalesce(case when tg_op='DELETE' then old.task_type else new.task_type end,'')='job_workflow'
      or (tg_op='UPDATE' and old.task_type='job_workflow')) and pg_trigger_depth()<=1 then
    raise exception 'Complete job workflow tasks from the job library' using errcode='42501';
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end $$;
revoke all on function private.guard_job_workflow_task() from public,anon,authenticated;
create trigger guard_job_workflow_task_before_change
before insert or update or delete on public.tasks
for each row execute function private.guard_job_workflow_task();

create or replace function private.close_job_workflow_tasks(p_job_id uuid,p_phase text,p_recipient uuid default null,p_except_recipient uuid default null,p_hide boolean default false)
returns void language plpgsql security definer
set search_path='pg_catalog','public','private' as $$
begin
  update public.tasks t set
    status=case when p_hide then t.status else 'مكتملة' end,
    progress=case when p_hide then t.progress else 100 end,
    completed_at=case when p_hide then t.completed_at else coalesce(t.completed_at,now()) end,
    actual_end_date=case when p_hide then t.actual_end_date else coalesce(t.actual_end_date,current_date) end,
    deleted_at=case when p_hide then coalesce(t.deleted_at,now()) else t.deleted_at end,
    delete_reason=case when p_hide then 'تم تغيير ربط الوصف الوظيفي' else t.delete_reason end,
    revision=t.revision+1,updated_at=now()
  from private.job_workflow_tasks w
  where w.task_id=t.id and w.job_description_id=p_job_id and w.phase=p_phase
    and (p_recipient is null or w.recipient_id=p_recipient)
    and (p_except_recipient is null or w.recipient_id<>p_except_recipient)
    and t.deleted_at is null and t.status<>'مكتملة';
end $$;

create or replace function private.ensure_job_workflow_task(p_job public.job_descriptions,p_phase text,p_cycle text,p_recipient uuid)
returns void language plpgsql security definer
set search_path='pg_catalog','public','private' as $$
declare v_task uuid;v_actor uuid;v_title text;v_description text;v_name text;v_actor_name text;
begin
  if p_recipient is null or p_cycle is null then return; end if;
  select full_name into v_name from public.profiles where id=p_recipient and active=true and status='active';
  if not found then return; end if;
  if p_phase='EMPLOYEE_ACK' and exists (
    select 1 from public.job_description_acknowledgements a
    where a.profile_id=p_recipient and a.job_description_id=p_job.id and a.job_revision=p_cycle::integer
  ) then return; end if;
  select w.task_id into v_task from private.job_workflow_tasks w
  where w.job_description_id=p_job.id and w.phase=p_phase and w.cycle_key=p_cycle and w.recipient_id=p_recipient;
  if v_task is not null then
    if p_phase in ('MANAGER_REVIEW','EMPLOYEE_ACK') then
      update public.tasks set status='قيد الانتظار',progress=0,completed_at=null,actual_end_date=null,
        deleted_at=null,delete_reason=null,updated_at=now(),revision=revision+1
      where id=v_task and (deleted_at is not null or status='مكتملة');
    end if;
    return;
  end if;
  v_actor:=coalesce(p_job.published_by,p_job.created_by,p_recipient);
  select full_name into v_actor_name from public.profiles where id=v_actor;
  v_title:=case p_phase when 'MANAGER_REVIEW' then 'مراجعة الوصف الوظيفي: ' when 'ADMIN_APPROVAL' then 'اعتماد الوصف الوظيفي: ' else 'الاطلاع والإقرار بالوصف الوظيفي: ' end||p_job.title;
  v_description:=case when p_phase='EMPLOYEE_ACK' then 'افتح ملفك الوظيفي، واطلع على الوصف المنشور، ثم سجل إقرارك. لا تُغلق هذه المهمة يدويًا.' else 'افتح مكتبة الوظائف، وراجع الوصف واتخذ الإجراء المطلوب. تُغلق المهمة تلقائيًا عند انتقال حالة الوصف.' end;
  insert into public.tasks(title,description,task_type,creator_id,assignee_id,creator_name_snapshot,assignee_name_snapshot,
      status,priority,progress,start_date,legacy_metadata)
  values(v_title,v_description,'job_workflow',v_actor,p_recipient,v_actor_name,v_name,
      'قيد الانتظار','normal',0,current_date,
      jsonb_build_object('job_workflow',jsonb_build_object('job_id',p_job.id,'phase',p_phase,'cycle',p_cycle)))
  returning id into v_task;
  insert into private.job_workflow_tasks(task_id,job_description_id,phase,cycle_key,recipient_id)
  values(v_task,p_job.id,p_phase,p_cycle,p_recipient);
end $$;

create or replace function private.sync_job_workflow_tasks()
returns trigger language plpgsql security definer
set search_path='pg_catalog','public','private' as $$
declare v_admin uuid;v_cycle text;v_revision text;v_assignment record;
begin
  if tg_op='UPDATE' and new.status=old.status and new.reviewer_id is not distinct from old.reviewer_id then return new; end if;
  v_cycle:=coalesce(new.submitted_at::text,new.id::text);
  if new.status in ('IN_REVIEW','CHANGES_REQUESTED') then
    perform private.close_job_workflow_tasks(new.id,'ADMIN_APPROVAL');
    perform private.close_job_workflow_tasks(new.id,'MANAGER_REVIEW',null,new.reviewer_id);
    perform private.ensure_job_workflow_task(new,'MANAGER_REVIEW',v_cycle,new.reviewer_id);
  elsif new.status='MANAGER_APPROVED' then
    perform private.close_job_workflow_tasks(new.id,'MANAGER_REVIEW');
    select id into v_admin from public.profiles where id=new.created_by and role='admin' and active=true and status='active';
    if v_admin is null then select id into v_admin from public.profiles where role='admin' and active=true and status='active' order by id limit 1; end if;
    perform private.ensure_job_workflow_task(new,'ADMIN_APPROVAL',v_cycle,v_admin);
  elsif new.status='PUBLISHED' then
    perform private.close_job_workflow_tasks(new.id,'MANAGER_REVIEW');
    perform private.close_job_workflow_tasks(new.id,'ADMIN_APPROVAL');
    v_revision:=coalesce(new.published_snapshot->>'revision',new.revision::text);
    for v_assignment in select profile_id from public.employee_job_assignments where job_description_id=new.id loop
      perform private.ensure_job_workflow_task(new,'EMPLOYEE_ACK',v_revision,v_assignment.profile_id);
    end loop;
  elsif new.status in ('DRAFT','ARCHIVED') then
    perform private.close_job_workflow_tasks(new.id,'MANAGER_REVIEW');
    perform private.close_job_workflow_tasks(new.id,'ADMIN_APPROVAL');
  end if;
  return new;
end $$;

create or replace function private.sync_job_assignment_workflow_task()
returns trigger language plpgsql security definer
set search_path='pg_catalog','public','private' as $$
declare v_job public.job_descriptions%rowtype;v_revision text;
begin
  if tg_op='UPDATE' and old.job_description_id=new.job_description_id then return new; end if;
  if tg_op='UPDATE' then perform private.close_job_workflow_tasks(old.job_description_id,'EMPLOYEE_ACK',old.profile_id,null,true); end if;
  select * into v_job from public.job_descriptions where id=new.job_description_id;
  if v_job.status='PUBLISHED' and v_job.published_snapshot is not null then
    v_revision:=coalesce(v_job.published_snapshot->>'revision',v_job.revision::text);
    perform private.ensure_job_workflow_task(v_job,'EMPLOYEE_ACK',v_revision,new.profile_id);
  end if;
  return new;
end $$;

create or replace function private.complete_job_acknowledgement_task()
returns trigger language plpgsql security definer
set search_path='pg_catalog','public','private' as $$
begin
  update public.tasks t set status='مكتملة',progress=100,completed_at=now(),actual_end_date=current_date,
    revision=t.revision+1,updated_at=now()
  from private.job_workflow_tasks w where w.task_id=t.id and w.job_description_id=new.job_description_id
    and w.phase='EMPLOYEE_ACK' and w.cycle_key=new.job_revision::text and w.recipient_id=new.profile_id
    and t.deleted_at is null and t.status<>'مكتملة';
  return new;
end $$;

revoke all on function private.close_job_workflow_tasks(uuid,text,uuid,uuid,boolean) from public,anon,authenticated;
revoke all on function private.ensure_job_workflow_task(public.job_descriptions,text,text,uuid) from public,anon,authenticated;
revoke all on function private.sync_job_workflow_tasks() from public,anon,authenticated;
revoke all on function private.sync_job_assignment_workflow_task() from public,anon,authenticated;
revoke all on function private.complete_job_acknowledgement_task() from public,anon,authenticated;
create trigger job_workflow_status after update of status,reviewer_id on public.job_descriptions
for each row execute function private.sync_job_workflow_tasks();
create trigger job_workflow_assignment after insert or update of job_description_id on public.employee_job_assignments
for each row execute function private.sync_job_assignment_workflow_task();
create trigger job_workflow_ack after insert on public.job_description_acknowledgements
for each row execute function private.complete_job_acknowledgement_task();

-- Existing work is brought into the same queue once, without touching job
-- revisions or notifying employees who already acknowledged this revision.
alter table public.tasks disable trigger guard_job_workflow_task_before_change;
do $$
declare v_job public.job_descriptions%rowtype;v_admin uuid;v_assignment record;
begin
  for v_job in select * from public.job_descriptions
    where status in ('IN_REVIEW','CHANGES_REQUESTED','MANAGER_APPROVED','PUBLISHED') loop
    if v_job.status in ('IN_REVIEW','CHANGES_REQUESTED') then
      perform private.ensure_job_workflow_task(v_job,'MANAGER_REVIEW',coalesce(v_job.submitted_at::text,v_job.id::text),v_job.reviewer_id);
    elsif v_job.status='MANAGER_APPROVED' then
      select id into v_admin from public.profiles where id=v_job.created_by and role='admin' and active=true and status='active';
      if v_admin is null then select id into v_admin from public.profiles where role='admin' and active=true and status='active' order by id limit 1; end if;
      perform private.ensure_job_workflow_task(v_job,'ADMIN_APPROVAL',coalesce(v_job.submitted_at::text,v_job.id::text),v_admin);
    elsif v_job.status='PUBLISHED' and v_job.published_snapshot is not null then
      for v_assignment in select profile_id from public.employee_job_assignments where job_description_id=v_job.id loop
        perform private.ensure_job_workflow_task(v_job,'EMPLOYEE_ACK',coalesce(v_job.published_snapshot->>'revision',v_job.revision::text),v_assignment.profile_id);
      end loop;
    end if;
  end loop;
end $$;
alter table public.tasks enable trigger guard_job_workflow_task_before_change;

commit;
