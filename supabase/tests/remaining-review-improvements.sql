begin;
select set_config('app.migration_mode','on',true);
select set_config('atwar.test.manager',(select id::text from public.profiles where full_name='اختبار E2E - مدير'),true);
select set_config('atwar.test.employee',(select id::text from public.profiles where full_name='اختبار E2E - موظف'),true);
select set_config('atwar.test.admin',(select id::text from public.profiles where full_name='اختبار E2E - مدير نظام'),true);
update public.profiles set manager_id=current_setting('atwar.test.admin')::uuid where id=current_setting('atwar.test.manager')::uuid;
select set_config('request.jwt.claim.sub',current_setting('atwar.test.manager'),true);
set local role authenticated;
do $$declare t uuid;f uuid;q uuid;begin
 t:=public.create_task_safe('QA cleanup rollback',auth.uid(),'synthetic','normal',current_date,current_date+7,'');
 perform set_config('atwar.test.task',t::text,true);
 insert into public.task_attachments(task_id,uploader_id,file_name,storage_path,size_bytes) values(t,auth.uid(),'QA.pdf',t::text||'/synthetic.pdf',10) returning id into f;
 delete from public.task_attachments where id=f;
 select id into q from public.task_attachment_cleanup where attachment_id=f and requested_by=auth.uid() and completed_at is null;
 if q is null then raise exception 'Deletion intent was lost';end if;
 begin update public.task_attachment_cleanup set completed_at=now() where id=q;raise exception 'Client bypass accepted';exception when insufficient_privilege then null;end;
 insert into public.task_attachments(task_id,uploader_id,file_name,storage_path,size_bytes) values(t,auth.uid(),'forged.pdf','another-task/forged.pdf',10) returning id into f;
 begin delete from public.task_attachments where id=f;raise exception 'Cross-task cleanup path accepted';exception when check_violation then null;end;
 if jsonb_typeof(public.job_acknowledgement_followup())<>'array' then raise exception 'Invalid manager aggregate';end if;
 if exists(select 1 from jsonb_array_elements(public.job_acknowledgement_followup()) r where (r->>'profile_id')::uuid not in(select id from public.profiles where manager_id=auth.uid())) then raise exception 'Manager scope leaked';end if;
 begin update public.approval_followup_settings set enabled=true where id; if found then raise exception 'Manager changed global config';end if;exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub',current_setting('atwar.test.employee'),true);
do $$begin
 if exists(select 1 from public.task_attachment_cleanup where task_id=current_setting('atwar.test.task')::uuid) then raise exception 'Cleanup queue leaked';end if;
 begin perform public.job_acknowledgement_followup();raise exception 'Employee aggregate access accepted';exception when insufficient_privilege then null;end;
end $$;
reset role;
-- Only synthetic rows are eligible during this test, and every write is rolled back.
update public.tasks set progress=100,status='بانتظار الاعتماد',assignee_id=current_setting('atwar.test.employee')::uuid,approval_commissioner_id=current_setting('atwar.test.manager')::uuid,submitted_at=now()-interval '6 days' where id=current_setting('atwar.test.task')::uuid;
update public.approval_followup_settings set enabled=true where id;
do $$declare n integer;begin
 n:=private.process_approval_followups(current_setting('atwar.test.task')::uuid);if n<>2 then raise exception 'Expected reminder and escalation, got %',n;end if;
 if private.process_approval_followups(current_setting('atwar.test.task')::uuid)<>0 then raise exception 'Duplicate notifications generated';end if;
 update public.tasks set submitted_at=now()-interval '1 day' where id=current_setting('atwar.test.task')::uuid;
 if private.process_approval_followups(current_setting('atwar.test.task')::uuid)<>0 then raise exception 'Premature reminder';end if;
 update public.tasks set submitted_at=now()-interval '7 days',status='مكتملة',completed_at=now(),actual_end_date=current_date where id=current_setting('atwar.test.task')::uuid;
 if private.process_approval_followups(current_setting('atwar.test.task')::uuid)<>0 then raise exception 'Closed task reminder';end if;
end $$;
select 'PASS durable cleanup intentions, queue isolation, client denial, manager-only scope, configuration protection, reminder/escalation idempotence, threshold and closed task exclusions; rolled back' as result;
rollback;
