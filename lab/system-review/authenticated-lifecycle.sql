begin;
update public.profiles set active=true,status='active' where id='2347fbff-372e-43d1-a2e4-094f5b3159bf';
update public.profiles set manager_id='2347fbff-372e-43d1-a2e4-094f5b3159bf' where id='eabb8105-e54d-45a3-90c8-15334698bbfc';
set local role authenticated;
select set_config('request.jwt.claim.sub','eabb8105-e54d-45a3-90c8-15334698bbfc',true);
do $$ declare t public.tasks%rowtype;begin
 t.id:=public.create_task_safe('اختبار دورة المهمة الذاتية','eabb8105-e54d-45a3-90c8-15334698bbfc',p_start_date=>current_date-3,p_due_date=>current_date-1);
 perform set_config('test.lifecycle',t.id::text,true);
 select * into t from public.tasks where id=t.id;
 if t.status<>'قيد الانتظار' then raise exception 'Unexpected initial state';end if;
 t:=public.update_task_safe(t.id,t.revision,'{"status":"قيد التنفيذ","progress":20}');
 begin perform public.update_task_safe(t.id,t.revision-1,'{"progress":50}');raise exception 'Stale update accepted';exception when others then if sqlerrm not like 'ATWAR_CONFLICT:%' then raise;end if;end;
 t:=public.update_task_safe(t.id,t.revision,'{"status":"بانتظار الاعتماد","progress":100}');
 if t.submitted_at is null then raise exception 'Submission timestamp absent';end if;
 begin perform public.update_task_safe(t.id,t.revision,'{"status":"مكتملة"}');raise exception 'Self approval accepted';exception when others then if sqlerrm not like 'ATWAR_TASK:%may approve' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub','2347fbff-372e-43d1-a2e4-094f5b3159bf',true);
do $$ declare t public.tasks%rowtype;begin
 select * into t from public.tasks where id=current_setting('test.lifecycle')::uuid;
 if t.id is null then raise exception 'Manager cannot see self task';end if;
 t:=public.update_task_safe(t.id,t.revision,'{"status":"مكتملة","progress":100}');
 if t.completed_at is null or t.status<>'مكتملة' then raise exception 'Approval failed';end if;
end $$;
select set_config('request.jwt.claim.sub','eabb8105-e54d-45a3-90c8-15334698bbfc',true);
do $$ declare t public.tasks%rowtype;begin
 select * into t from public.tasks where id=current_setting('test.lifecycle')::uuid;
 begin perform public.update_task_safe(t.id,t.revision,'{"title":"تغيير بعد الاكتمال"}');raise exception 'Completed task editable';exception when others then if sqlerrm='Completed task editable' then raise;end if;end;
end $$;
reset role;
rollback;
select 'PASS authenticated self-task lifecycle, stale revision, manager approval, immutable completion' result;
