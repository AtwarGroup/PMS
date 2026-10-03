-- Run inside a transaction; caller rolls back all fixtures and notifications.
update public.recurring_task_templates set active=false;
select set_config('request.jwt.claim.sub',(select id::text from public.profiles where email='m.basunbul@tiradorstores.com'),true);
set local role authenticated;
insert into public.recurring_task_templates(owner_id,assignee_id,title,recurrence,interval_count,next_run_at,schedule_start_at,recurrence_rule)
select auth.uid(),p.id,'__recurrence_completion_test__','daily',2,now()-interval '1 minute',now()-interval '1 minute','{"mode":"completion","pattern":"day","endMode":"never"}' from public.profiles p where email='o.abdo@tiradorstores.com';
insert into public.recurring_task_templates(owner_id,assignee_id,title,recurrence,interval_count,next_run_at,schedule_start_at,recurrence_rule)
select auth.uid(),p.id,'__recurrence_count_test__','daily',1,now(),now(),'{"mode":"calendar","pattern":"day","endMode":"count","endCount":2}' from public.profiles p where email='o.abdo@tiradorstores.com';
insert into public.recurring_task_templates(owner_id,assignee_id,title,recurrence,interval_count,next_run_at)
select auth.uid(),p.id,'__recurrence_legacy_test__','monthly',1,now()-interval '1 minute' from public.profiles p where email='o.abdo@tiradorstores.com';
reset role;
do $$begin
 if private.materialize_recurring_tasks()<>3 then raise exception 'Expected three first tasks';end if;
 if private.materialize_recurring_tasks()<>0 then raise exception 'Duplicate creation';end if;
end $$;
set local role authenticated;
do $$begin
 begin perform public.run_recurring_tasks_safe();raise exception 'Manager run must fail';exception when others then if sqlerrm<>'Administrator permission required' then raise;end if;end;
 begin update public.recurring_task_templates set created_count=500 where title='__recurrence_count_test__';raise exception 'Counter protection failed';exception when others then if sqlerrm<>'Scheduler state cannot be edited' then raise;end if;end;
end $$;
reset role;
do $$begin
 if not exists(select 1 from public.recurring_task_templates where title='__recurrence_completion_test__' and waiting_for_completion and created_count=1) then raise exception 'Completion must wait';end if;
 if not exists(select 1 from public.recurring_task_templates r join public.tasks t on t.id=r.last_created_task_id where r.title='__recurrence_legacy_test__' and r.recurrence_rule is null and t.start_date=(now() at time zone 'Asia/Riyadh')::date) then raise exception 'Legacy schedule/date failed';end if;
end $$;
select set_config('request.jwt.claim.sub',(select id::text from public.profiles where email='o.abdo@tiradorstores.com'),true);
set local role authenticated;
update public.tasks set status='قيد التنفيذ' where title='__recurrence_completion_test__';
update public.tasks set status='بانتظار الاعتماد',progress=100 where title='__recurrence_completion_test__';
reset role;
do $$begin
 if not exists(select 1 from public.recurring_task_templates where title='__recurrence_completion_test__' and waiting_for_completion) then raise exception 'Submission incorrectly scheduled recurrence';end if;
end $$;
select set_config('request.jwt.claim.sub',(select id::text from public.profiles where email='m.basunbul@tiradorstores.com'),true);
set local role authenticated;
update public.tasks set status='مكتملة' where title='__recurrence_completion_test__';
reset role;
do $$begin
 if not exists(select 1 from public.recurring_task_templates r join public.tasks t on t.id=r.last_created_task_id where r.title='__recurrence_completion_test__' and not r.waiting_for_completion and r.next_run_at=t.completed_at+interval '2 days') then raise exception 'Approval must start completion delay';end if;
end $$;
update public.recurring_task_templates set next_run_at=now()-interval '1 second' where title='__recurrence_count_test__';
do $$begin
 if private.materialize_recurring_tasks()<>1 then raise exception 'Expected final count task';end if;
 if private.materialize_recurring_tasks()<>0 then raise exception 'Count exceeded';end if;
 if not exists(select 1 from public.recurring_task_templates where title='__recurrence_count_test__' and not active and created_count=2) then raise exception 'Count end not stopped';end if;
end $$;
insert into public.recurring_task_templates(owner_id,assignee_id,title,recurrence,interval_count,next_run_at,schedule_start_at,recurrence_rule)
select m.id,p.id,'__recurrence_expired_test__','daily',1,now()-interval '2 days',now()-interval '2 days',jsonb_build_object('mode','completion','pattern','day','endMode','date','endDate',((now() at time zone 'Asia/Riyadh')::date-1)::text) from public.profiles m cross join public.profiles p where m.email='m.basunbul@tiradorstores.com' and p.email='o.abdo@tiradorstores.com';
do $$begin
 if private.materialize_recurring_tasks()<>0 then raise exception 'Expired range created task';end if;
 if not exists(select 1 from public.recurring_task_templates where title='__recurrence_expired_test__' and not active and created_count=0) then raise exception 'Expired template not ended';end if;
end $$;
select set_config('request.jwt.claim.sub',(select id::text from public.profiles where email='helpdesk@tiradorstores.com'),true);
set local role authenticated;
do $$begin if public.run_recurring_tasks_safe()<>0 then raise exception 'Admin unexpected task';end if;end $$;
reset role;
select 'PASS admin-only execution, recurrence creation, approval, count/date ends, no duplicate, legacy, protected counters' result;
