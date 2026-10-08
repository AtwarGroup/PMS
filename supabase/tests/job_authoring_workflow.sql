-- Authenticated role tests. All synthetic data and task side effects are rolled back.
begin;
select set_config('request.jwt.claim.sub','797d5893-d44d-489c-9109-91da4882acfe',true);
set local role authenticated;
do $$
declare j public.job_descriptions%rowtype; again public.job_descriptions%rowtype; payload jsonb; request_id uuid:=gen_random_uuid();
begin
 payload:=jsonb_build_object('title','اختبار إعداد وصف جديد مؤقت','reference_profile_id','eabb8105-e54d-45a3-90c8-15334698bbfc','purpose','وصف تجريبي للتحقق من اكتمال دورة العمل وحماية الموافقات والإصدارات السابقة.','content',jsonb_build_object('responsibilities',jsonb_build_array(jsonb_build_object('text','المهمة الأولى'),jsonb_build_object('text','المهمة الثانية')),'authorities',jsonb_build_array(jsonb_build_object('text','صلاحية تجريبية')),'reports',jsonb_build_array(jsonb_build_object('name','تقرير تجريبي')),'kpis',jsonb_build_array(jsonb_build_object('name','مؤشر تجريبي','measure','عدد المنجز / الإجمالي','target','١٠٠٪','source','تقرير النظام','weight',100)),'qualifications',jsonb_build_object('education','مؤهل مناسب')));
 j:=public.create_job_description_draft(request_id,payload);
 assert j.status='DRAFT' and j.revision=1 and j.published_snapshot is null;
 again:=public.create_job_description_draft(request_id,payload);assert j.id=again.id and j.revision=again.revision;
 perform set_config('test.job_id',j.id::text,true);perform set_config('test.payload',payload::text,true);
 j:=public.save_job_description_draft(j.id,j.revision,payload);assert j.revision=2;
 begin perform public.save_job_description_draft(j.id,1,payload);raise exception 'Expected conflict';exception when serialization_failure then null;end;
 j:=public.submit_job_description_draft(j.id,j.revision);assert j.status='IN_REVIEW' and j.reviewer_id='2347fbff-372e-43d1-a2e4-094f5b3159bf'::uuid;
 perform set_config('test.revision',j.revision::text,true);
end $$;
select set_config('request.jwt.claim.sub','eabb8105-e54d-45a3-90c8-15334698bbfc',true);
do $$ begin
 begin perform public.create_job_description_draft(gen_random_uuid(),'{}');raise exception 'Employee creation should fail';exception when insufficient_privilege then null;end;
 begin perform public.return_job_description_for_changes(current_setting('test.job_id')::uuid,current_setting('test.revision')::integer,'إعادة غير مصرح بها');raise exception 'Unauthorized return should fail';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','2347fbff-372e-43d1-a2e4-094f5b3159bf',true);
do $$ declare j public.job_descriptions%rowtype;begin
 j:=public.return_job_description_for_changes(current_setting('test.job_id')::uuid,current_setting('test.revision')::integer,'استكمال متطلبات المراجعة التجريبية');assert j.status='CHANGES_REQUESTED';
end $$;
reset role;
do $$ begin
 assert exists(select 1 from private.job_workflow_tasks w join public.tasks t on t.id=w.task_id where w.job_description_id=current_setting('test.job_id')::uuid and w.phase='DRAFT_REVISION' and t.status<>'مكتملة' and t.deleted_at is null);
 assert not exists(select 1 from private.job_workflow_tasks w join public.tasks t on t.id=w.task_id where w.job_description_id=current_setting('test.job_id')::uuid and w.phase='MANAGER_REVIEW' and t.status<>'مكتملة' and t.deleted_at is null);
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','797d5893-d44d-489c-9109-91da4882acfe',true);
do $$ declare j public.job_descriptions%rowtype;begin
 select * into j from public.job_descriptions where id=current_setting('test.job_id')::uuid;
 j:=public.submit_job_description_draft(j.id,j.revision);
end $$;
select set_config('request.jwt.claim.sub','2347fbff-372e-43d1-a2e4-094f5b3159bf',true);
do $$ declare j public.job_descriptions%rowtype;r uuid;begin
 select * into j from public.job_descriptions where id=current_setting('test.job_id')::uuid;
 insert into public.job_description_change_requests(job_description_id,section,item_index,action,original_value,reason,manager_id)
 values(j.id,'RESPONSIBILITIES',0,'DELETE',j.content#>'{responsibilities,0}','حذف البند التجريبي الأول',(select auth.uid()));
 insert into public.job_description_change_requests(job_description_id,section,item_index,action,original_value,proposed_value,reason,manager_id)
 values(j.id,'RESPONSIBILITIES',1,'MODIFY',j.content#>'{responsibilities,1}','{"text":"المهمة الثانية بعد التعديل"}','تعديل البند التجريبي الثاني',(select auth.uid()));
 j:=public.complete_job_description_review(j.id);assert j.status='MANAGER_APPROVED';
end $$;
select set_config('request.jwt.claim.sub','797d5893-d44d-489c-9109-91da4882acfe',true);
do $$ declare j public.job_descriptions%rowtype;r uuid; old_snapshot jsonb; payload jsonb;begin
 select * into j from public.job_descriptions where id=current_setting('test.job_id')::uuid;
 begin perform public.finish_job_final_review(j.id);raise exception 'Pending changes should block';exception when others then if sqlerrm not like '%Resolve pending proposals first%' then raise;end if;end;
 select id into r from public.job_description_change_requests where job_description_id=j.id and action='DELETE';
 j:=public.decide_job_description_proposal(r,j.revision,'ACCEPTED');
 select id into r from public.job_description_change_requests where job_description_id=j.id and action='MODIFY';
 j:=public.decide_job_description_proposal(r,j.revision,'ACCEPTED');assert j.content#>>'{responsibilities,0,text}'='المهمة الثانية بعد التعديل';
 j:=public.finish_job_final_review(j.id);assert j.final_reviewed_at is not null;
 update public.job_descriptions set status='PUBLISHED' where id=j.id returning * into j;assert j.published_snapshot is not null;
 insert into public.employee_job_assignments(profile_id,job_description_id,assigned_by,updated_by) values('eabb8105-e54d-45a3-90c8-15334698bbfc',j.id,(select auth.uid()),(select auth.uid())) on conflict(profile_id) do update set job_description_id=excluded.job_description_id,updated_by=excluded.updated_by;
 old_snapshot:=j.published_snapshot;
 payload:=current_setting('test.payload')::jsonb||jsonb_build_object('title','عنوان مسودة جديدة');
 j:=public.save_job_description_draft(j.id,j.revision,payload);assert j.status='DRAFT' and j.published_snapshot=old_snapshot;
end $$;
select set_config('request.jwt.claim.sub','eabb8105-e54d-45a3-90c8-15334698bbfc',true);
do $$ declare a uuid;b uuid;begin
 select id into a from public.acknowledge_job_description(current_setting('test.job_id')::uuid,'rollback authoring test');
 select id into b from public.acknowledge_job_description(current_setting('test.job_id')::uuid,'rollback authoring test');assert a=b;
end $$;
select set_config('request.jwt.claim.sub','797d5893-d44d-489c-9109-91da4882acfe',true);
do $$ declare j public.job_descriptions%rowtype; payload jsonb;begin
 for i in 1..2 loop
  select * into j from public.job_descriptions where id=current_setting('test.job_id')::uuid;
  if j.status='PUBLISHED' then j:=public.save_job_description_draft(j.id,j.revision,current_setting('test.payload')::jsonb);end if;
  j:=public.submit_job_description_draft(j.id,j.revision);
  perform set_config('request.jwt.claim.sub','2347fbff-372e-43d1-a2e4-094f5b3159bf',true);j:=public.complete_job_description_review(j.id);
  perform set_config('request.jwt.claim.sub','797d5893-d44d-489c-9109-91da4882acfe',true);j:=public.finish_job_final_review(j.id);
  update public.job_descriptions set status='PUBLISHED' where id=j.id returning * into j;
 end loop;
end $$;
reset role;
do $$ declare c integer;begin
 select count(*) into c from private.job_workflow_tasks w join public.tasks t on t.id=w.task_id where w.job_description_id=current_setting('test.job_id')::uuid and w.phase='EMPLOYEE_ACK' and t.status<>'مكتملة' and t.deleted_at is null;
 assert c=1,'Latest revision must have exactly one pending acknowledgement task';
end $$;
select 'PASS: creation, retry, direct manager, role denial, return task, proposal reindex, publication and snapshot preservation' as result;
rollback;
