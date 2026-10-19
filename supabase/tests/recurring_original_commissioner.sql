-- All fixtures, schedule changes, notifications and decisions roll back.
begin;
select set_config('qa.manager',id::text,true) from public.profiles where email='e2e-manager@atwargroup.test' and active;
select set_config('qa.employee',id::text,true) from public.profiles where email='e2e-employee@atwargroup.test' and active;
select set_config('request.jwt.claims',jsonb_build_object('sub',id,'role','authenticated')::text,true) from public.profiles where email='e2e-admin@atwargroup.test' and active;
-- Isolate the scheduler so no real due template is materialized, even transiently.
update public.recurring_task_templates set active=false where active;
insert into public.recurring_task_templates(owner_id,assignee_id,title,recurrence,interval_count,next_run_at,due_offset_days)
 values(current_setting('qa.manager')::uuid,current_setting('qa.employee')::uuid,'QA recurring original commissioner','weekly',1,now()-interval '1 minute',4);
set local role authenticated;
select public.run_recurring_tasks_safe();
do $qa$
declare t public.tasks%rowtype;
begin
 select * into strict t from public.tasks where title='QA recurring original commissioner';
 if t.creator_id<>current_setting('qa.manager')::uuid or t.approval_commissioner_id<>current_setting('qa.manager')::uuid or not t.completion_requires_approval then raise exception 'Scheduler replaced original manager with runner';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('qa.employee'),'role','authenticated')::text,true);
 update public.tasks set status='قيد التنفيذ' where id=t.id;
 update public.tasks set progress=100,status='بانتظار الاعتماد' where id=t.id;
 begin
  update public.tasks set status='مكتملة' where id=t.id;
  raise exception 'QA employee approved own commissioned task';
 exception when raise_exception then if sqlerrm='QA employee approved own commissioned task' then raise;end if;end;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('qa.manager'),'role','authenticated')::text,true);
 if not exists(select 1 from public.notifications where task_id=t.id and type='submitted' and recipient_id=current_setting('qa.manager')::uuid) then raise exception 'Approval notification did not reach original manager';end if;
 update public.tasks set status='مكتملة' where id=t.id returning * into t;
 if t.status<>'مكتملة' or t.approved_by_id<>current_setting('qa.manager')::uuid then raise exception 'Original manager could not approve';end if;
end $qa$;
rollback;