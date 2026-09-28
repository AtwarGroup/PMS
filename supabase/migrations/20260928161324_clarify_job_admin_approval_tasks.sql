begin;

create or replace function private.label_job_admin_approval_task()
returns trigger language plpgsql security definer
set search_path='pg_catalog','public','private' as $$
declare v_job public.job_descriptions%rowtype;v_reviewer text;
begin
  if new.task_type<>'job_workflow' or new.legacy_metadata#>>'{job_workflow,phase}'<>'ADMIN_APPROVAL' then return new; end if;
  select * into v_job from public.job_descriptions
  where id=(new.legacy_metadata#>>'{job_workflow,job_id}')::uuid;
  select full_name into v_reviewer from public.profiles where id=v_job.manager_approved_by;
  new.title:='الاعتماد النهائي لدى مدير النظام: '||v_job.title;
  new.description:='اكتملت مراجعة المدير'||case when nullif(btrim(coalesce(v_reviewer,'')),'') is null then '' else ' ('||v_reviewer||')' end||'. افتح الوصف الوظيفي للمراجعة النهائية والاعتماد أو إعادته للتعديل. تُغلق المهمة تلقائيًا عند اتخاذ القرار.';
  return new;
end $$;
revoke all on function private.label_job_admin_approval_task() from public,anon,authenticated;
create trigger label_job_admin_approval_task_before_insert
before insert on public.tasks for each row execute function private.label_job_admin_approval_task();

-- Update the two currently pending final-approval tasks without changing
-- their assignee, approval history or deadline.
select set_config('app.migration_mode','on',true);
alter table public.tasks disable trigger guard_job_workflow_task_before_change;
update public.tasks t set
 title='الاعتماد النهائي لدى مدير النظام: '||j.title,
 description='اكتملت مراجعة المدير'||case when nullif(btrim(coalesce(p.full_name,'')),'') is null then '' else ' ('||p.full_name||')' end||'. افتح الوصف الوظيفي للمراجعة النهائية والاعتماد أو إعادته للتعديل. تُغلق المهمة تلقائيًا عند اتخاذ القرار.',
 updated_at=now()
from private.job_workflow_tasks w
join public.job_descriptions j on j.id=w.job_description_id
left join public.profiles p on p.id=j.manager_approved_by
where t.id=w.task_id and w.phase='ADMIN_APPROVAL' and t.status<>'مكتملة' and t.deleted_at is null;
alter table public.tasks enable trigger guard_job_workflow_task_before_change;
select set_config('app.migration_mode','',true);

commit;
