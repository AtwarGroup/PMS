create table private.hr_job_ack_exemptions(profile_id uuid not null references public.profiles(id),job_description_id uuid not null references public.job_descriptions(id),job_revision integer not null,import_id uuid not null references private.hr_imports(id),reason text not null,created_at timestamptz not null default now(),primary key(profile_id,job_description_id,job_revision));
alter table private.hr_job_ack_exemptions enable row level security;
revoke all on private.hr_job_ack_exemptions from public,anon,authenticated;
create policy hr_internal_only on private.hr_job_ack_exemptions for all to authenticated using(false)with check(false);
insert into private.hr_job_ack_exemptions(profile_id,job_description_id,job_revision,import_id,reason)
select e.profile_id,j.id,(j.published_snapshot->>'revision')::integer,i.id,'تحديث إداري للمرحلة الثانية بتوجيه الإدارة؛ لا يتطلب إقرار الموظف أو إرسال بريد.'
from private.hr_employees e join public.employee_job_assignments a on a.profile_id=e.profile_id join public.job_descriptions j on j.id=a.job_description_id cross join private.hr_imports i
where i.source_name='قاعدة البيانات.xlsx'and i.effective_from='2026-10-20'and j.published_snapshot is not null;
create function private.hr_job_ack_exemptions()returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,private as $$
begin
 if not private.current_user_is_active()then raise exception 'Active account required'using errcode='42501';end if;
 return(select coalesce(jsonb_agg(jsonb_build_object('profile_id',w.profile_id,'job_description_id',w.job_description_id,'job_revision',w.job_revision,'reason',w.reason)),'[]')from private.hr_job_ack_exemptions w where w.profile_id=auth.uid()or private.is_admin()or private.manages_user(w.profile_id));
end $$;
revoke all on function private.hr_job_ack_exemptions()from public,anon,authenticated;
grant execute on function private.hr_job_ack_exemptions()to authenticated;
create function public.job_administrative_exemptions()returns jsonb language sql security invoker set search_path=pg_catalog,private as $$select private.hr_job_ack_exemptions()$$;
revoke all on function public.job_administrative_exemptions()from public,anon;
grant execute on function public.job_administrative_exemptions()to authenticated;
create function private.guard_exempted_job_ack()returns trigger language plpgsql security definer set search_path=pg_catalog,public,private as $$
begin
 if exists(select 1 from private.hr_job_ack_exemptions where profile_id=new.profile_id and job_description_id=new.job_description_id and job_revision=new.job_revision)then raise exception 'هذا التحديث الإداري لا يتطلب إعادة إقرار أو إرسال بريد';end if;
 return new;
end $$;
revoke all on function private.guard_exempted_job_ack()from public,anon,authenticated;
create trigger administrative_job_ack_exemption before insert on public.job_description_acknowledgements for each row execute function private.guard_exempted_job_ack();
comment on table private.hr_job_ack_exemptions is 'Administrative waiver for one exact published revision. Never impersonates employee acceptance; future revisions follow the normal acknowledgement workflow.';

CREATE OR REPLACE FUNCTION private.queue_job_publication_email(p_job job_descriptions, p_profile_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare v_profile public.profiles%rowtype; v_revision integer;
begin
  if p_job.status='ARCHIVED' or p_job.published_snapshot is null then return; end if;
  select * into v_profile from public.profiles where id=p_profile_id and active=true and status='active';
  if not found or nullif(btrim(coalesce(v_profile.email,'')),'') is null then return; end if;
  v_revision:=coalesce((p_job.published_snapshot->>'revision')::integer,p_job.revision,1);
  if exists(select 1 from private.hr_job_ack_exemptions w where w.profile_id=p_profile_id and w.job_description_id=p_job.id and w.job_revision=v_revision) then return; end if;
  insert into public.job_publication_email_outbox(event_key,job_description_id,profile_id,recipient_email,job_revision,payload)
  values (
    p_job.id::text||':'||v_revision::text||':'||v_profile.id::text,
    p_job.id,v_profile.id,lower(btrim(v_profile.email)),v_revision,
    jsonb_build_object('employee_name',v_profile.full_name,'job_snapshot',p_job.published_snapshot)
  ) on conflict(event_key) do nothing;
end $function$
;
CREATE OR REPLACE FUNCTION private.ensure_job_workflow_task(p_job job_descriptions, p_phase text, p_cycle text, p_recipient uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare
  v_task uuid;
  v_actor uuid;
  v_title text;
  v_description text;
  v_name text;
  v_actor_name text;
begin
  if p_phase='EMPLOYEE_ACK' and exists(select 1 from private.hr_job_ack_exemptions w where w.profile_id=p_recipient and w.job_description_id=p_job.id and w.job_revision::text=p_cycle) then return; end if;
  if p_recipient is null or p_cycle is null then return; end if;

  select full_name into v_name
  from public.profiles
  where id=p_recipient and active=true and status='active';
  if not found then return; end if;

  if p_phase='EMPLOYEE_ACK' then
    update public.tasks t
       set deleted_at=coalesce(t.deleted_at,now()),
           delete_reason='استُبدلت المهمة بإصدار أحدث من الوصف الوظيفي',
           revision=t.revision+1,
           updated_at=now()
      from private.job_workflow_tasks w
     where w.task_id=t.id
       and w.job_description_id=p_job.id
       and w.phase='EMPLOYEE_ACK'
       and w.recipient_id=p_recipient
       and w.cycle_key<>p_cycle
       and t.deleted_at is null
       and t.status<>'مكتملة';
  end if;

  if p_phase='EMPLOYEE_ACK' and exists (
    select 1 from public.job_description_acknowledgements a
    where a.profile_id=p_recipient
      and a.job_description_id=p_job.id
      and a.job_revision=p_cycle::integer
  ) then return; end if;

  select w.task_id into v_task
  from private.job_workflow_tasks w
  where w.job_description_id=p_job.id
    and w.phase=p_phase
    and w.cycle_key=p_cycle
    and w.recipient_id=p_recipient;

  if v_task is not null then
    if p_phase in ('MANAGER_REVIEW','EMPLOYEE_ACK') then
      update public.tasks
         set status='قيد الانتظار',progress=0,completed_at=null,actual_end_date=null,
             deleted_at=null,delete_reason=null,updated_at=now(),revision=revision+1
       where id=v_task and (deleted_at is not null or status='مكتملة');
    end if;
    return;
  end if;

  v_actor:=coalesce(p_job.published_by,p_job.created_by,p_recipient);
  select full_name into v_actor_name from public.profiles where id=v_actor;

  v_title:=case p_phase
    when 'MANAGER_REVIEW' then 'مراجعة الوصف الوظيفي: '
    when 'ADMIN_APPROVAL' then 'اعتماد الوصف الوظيفي: '
    else 'الاطلاع والإقرار بالوصف الوظيفي: '
  end||p_job.title;

  v_description:=case when p_phase='EMPLOYEE_ACK'
    then 'افتح ملفك الوظيفي، واطلع على الوصف المنشور، ثم سجل إقرارك. لا تُغلق هذه المهمة يدويًا.'
    else 'افتح مكتبة الوظائف، وراجع الوصف واتخذ الإجراء المطلوب. تُغلق المهمة تلقائيًا عند انتقال حالة الوصف.'
  end;

  insert into public.tasks(
    title,description,task_type,creator_id,assignee_id,
    creator_name_snapshot,assignee_name_snapshot,status,priority,progress,start_date,legacy_metadata
  )
  values(
    v_title,v_description,'job_workflow',v_actor,p_recipient,
    v_actor_name,v_name,'قيد الانتظار','normal',0,current_date,
    jsonb_build_object('job_workflow',jsonb_build_object('job_id',p_job.id,'phase',p_phase,'cycle',p_cycle))
  )
  returning id into v_task;

  insert into private.job_workflow_tasks(task_id,job_description_id,phase,cycle_key,recipient_id)
  values(v_task,p_job.id,p_phase,p_cycle,p_recipient);
end
$function$
;
CREATE OR REPLACE FUNCTION private.job_acknowledgement_followup()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $function$
declare actor uuid:=auth.uid();result jsonb;admin boolean;
begin
 if actor is null or not private.current_user_is_active()then raise exception 'Active account required'using errcode='42501';end if;
 admin:=private.is_admin();
 if not admin and not exists(select 1 from public.profiles where id=actor and role='manager')then raise exception 'Manager required'using errcode='42501';end if;
 select coalesce(jsonb_agg(jsonb_build_object('profile_id',p.id,'name',p.full_name,'job_id',j.id,'title',j.title,'revision',j.published_snapshot->>'revision',
 'accepted',exists(select 1 from public.job_description_acknowledgements k where k.profile_id=p.id and k.job_description_id=j.id and k.job_revision=(j.published_snapshot->>'revision')::integer and k.accepted_at>=a.assigned_at),
 'waived',exists(select 1 from private.hr_job_ack_exemptions w where w.profile_id=p.id and w.job_description_id=j.id and w.job_revision=(j.published_snapshot->>'revision')::integer),
 'published',j.published_snapshot is not null,'review_due',r.due_on,'review_enabled',coalesce(r.enabled,false))order by p.full_name),'[]'::jsonb)into result
 from public.profiles p left join public.employee_job_assignments a on a.profile_id=p.id left join public.job_descriptions j on j.id=a.job_description_id left join public.job_periodic_reviews r on r.job_description_id=j.id
 where p.active and p.status='active' and p.role<>'admin'and p.id<>actor and(admin or p.manager_id=actor);
 return result;
end $function$;
