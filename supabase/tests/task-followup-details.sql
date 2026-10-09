begin;
select set_config('atwar.test.actor',(select id::text from public.profiles where full_name='اختبار E2E - مدير'),true);
select set_config('atwar.test.outsider',(select id::text from public.profiles where full_name='اختبار E2E - موظف'),true);
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('atwar.test.actor'),true);
do $$
declare t uuid; c jsonb; r jsonb; rev integer;
begin
 t:=public.create_task_safe('E2E followup rollback',auth.uid(),'synthetic','normal',current_date,current_date+7,'');
 perform set_config('atwar.test.task',t::text,true);
 c:=public.task_followup_context(t);rev:=(c->>'task_revision')::integer;
 if (c->>'can_edit')::boolean is distinct from true then raise exception 'Expected editor access';end if;
 r:=public.save_task_followup(t,true,'سبب تجريبي','إجراء تجريبي','assignee',current_date+1,0,rev);
 if (r->'followup'->>'revision')::integer<>1 then raise exception 'Initial revision failed';end if;
 begin perform public.save_task_followup(t,false,'','','assignee',null,0,rev);raise exception 'Stale follow-up accepted';exception when serialization_failure then null;end;
 begin perform public.save_task_followup(t,false,'','','assignee',null,1,rev+1);raise exception 'Stale task accepted';exception when serialization_failure then null;end;
 begin perform public.save_task_followup(t,false,'','','invalid',null,1,rev);raise exception 'Invalid owner accepted';exception when invalid_parameter_value then null;end;
 begin update public.task_followup_details set reason='bypass' where task_id=t;raise exception 'Direct update accepted';exception when insufficient_privilege then null;end;
 r:=public.save_task_followup(t,false,'تم الحل','المتابعة العادية','creator',null,1,rev);
 if (r->'followup'->>'revision')::integer<>2 or (r->'followup'->>'blocked')::boolean then raise exception 'Resolution failed';end if;
end $$;
select set_config('request.jwt.claim.sub',current_setting('atwar.test.outsider'),true);
do $$declare t uuid:=current_setting('atwar.test.task')::uuid;begin
 if exists(select 1 from public.task_followup_details where task_id=t) then raise exception 'RLS leaked follow-up';end if;
 begin perform public.task_followup_context(t);raise exception 'Unauthorized read accepted';exception when insufficient_privilege then null;end;
 begin perform public.save_task_followup(t,false,'','','assignee',null,2,1);raise exception 'Unauthorized write accepted';exception when insufficient_privilege then null;end;
end $$;
select 'PASS follow-up permissions, RLS, save/resolve, validation, task and follow-up revision conflicts; all test data rolled back' as result;
rollback;