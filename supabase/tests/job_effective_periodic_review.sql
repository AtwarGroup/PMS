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

set local role authenticated;
select set_config('request.jwt.claim.sub','797d5893-d44d-489c-9109-91da4882acfe',true);
do $$ declare j public.job_descriptions%rowtype; r public.job_periodic_reviews%rowtype; original_revision integer; snapshot jsonb;begin
 select * into j from public.job_descriptions where id=current_setting('test.job_id')::uuid;
 original_revision:=j.revision;snapshot:=j.published_snapshot;
 r:=public.save_job_periodic_review(j.id,0,'2347fbff-372e-43d1-a2e4-094f5b3159bf',(now() at time zone 'Asia/Riyadh')::date,6,true);
 perform set_config('test.periodic_revision',r.revision::text,true);
 assert j.revision=original_revision;
end $$;
reset role;
do $$ declare r public.job_periodic_reviews%rowtype;begin
 select * into r from public.job_periodic_reviews where job_description_id=current_setting('test.job_id')::uuid;
 r:=public.save_job_periodic_review(r.job_description_id,r.revision,r.reviewer_id,r.due_on,r.interval_months,r.enabled);
 perform set_config('test.periodic_revision',r.revision::text,true);
 assert (select count(*) from private.job_workflow_tasks w join public.tasks t on t.id=w.task_id where w.job_description_id=current_setting('test.job_id')::uuid and w.phase='PERIODIC_REVIEW' and t.deleted_at is null and t.status<>'مكتملة')=1;
 perform private.process_job_periodic_reviews();perform private.process_job_periodic_reviews();
 assert (select count(*) from private.job_workflow_tasks w join public.tasks t on t.id=w.task_id where w.job_description_id=current_setting('test.job_id')::uuid and w.phase='PERIODIC_REVIEW' and t.deleted_at is null and t.status<>'مكتملة')=1;
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','2347fbff-372e-43d1-a2e4-094f5b3159bf',true);
do $$ declare j public.job_descriptions%rowtype; r public.job_periodic_reviews%rowtype; after_job public.job_descriptions%rowtype;begin
 select * into j from public.job_descriptions where id=current_setting('test.job_id')::uuid;
 r:=public.complete_job_periodic_review(j.id,current_setting('test.periodic_revision')::integer,(j.published_snapshot->>'revision')::integer,'تمت المراجعة ولا توجد تغييرات؛ اختبار مؤقت');
 select * into after_job from public.job_descriptions where id=j.id;
 assert after_job.revision=j.revision and after_job.published_snapshot=j.published_snapshot and after_job.status='PUBLISHED';
 assert r.due_on>(now() at time zone 'Asia/Riyadh')::date;
 begin perform public.complete_job_periodic_review(j.id,1,(j.published_snapshot->>'revision')::integer,'إعادة مكررة');raise exception 'Expected stale review';exception when serialization_failure then null;end;
end $$;
do $$ declare j public.job_descriptions%rowtype;r public.job_periodic_reviews%rowtype;begin
 select * into j from public.job_descriptions where id=current_setting('test.job_id')::uuid;
 select * into r from public.job_periodic_reviews where job_description_id=j.id;
 r:=public.request_job_periodic_change(j.id,r.revision,(j.published_snapshot->>'revision')::integer,'تعديل مطلوب من المراجعة الدورية');assert r.needs_changes;
 begin perform public.complete_job_periodic_review(j.id,r.revision,(j.published_snapshot->>'revision')::integer,'لا تغييرات');raise exception 'Expected pending changes';exception when others then if sqlerrm not like '%لا توجد مراجعة%' then raise;end if;end;
end $$;
reset role;
do $$ begin assert exists(select 1 from private.job_workflow_tasks w join public.tasks t on t.id=w.task_id where w.job_description_id=current_setting('test.job_id')::uuid and w.phase='DRAFT_REVISION' and t.status<>'مكتملة' and t.deleted_at is null and t.description like '%تعديل مطلوب%');end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','797d5893-d44d-489c-9109-91da4882acfe',true);
do $$ declare j public.job_descriptions%rowtype;s public.job_publication_schedules%rowtype;snapshot jsonb;begin
 select * into j from public.job_descriptions where id=current_setting('test.job_id')::uuid;
 snapshot:=j.published_snapshot;
 j:=public.save_job_description_draft(j.id,j.revision,current_setting('test.payload')::jsonb||jsonb_build_object('title','عنوان مؤجل للسريان'));
 j:=public.submit_job_description_draft(j.id,j.revision);
 perform set_config('request.jwt.claim.sub','2347fbff-372e-43d1-a2e4-094f5b3159bf',true);j:=public.complete_job_description_review(j.id);
 perform set_config('request.jwt.claim.sub','797d5893-d44d-489c-9109-91da4882acfe',true);j:=public.finish_job_final_review(j.id);
 j:=public.approve_job_effective_date(j.id,j.revision,(now() at time zone 'Asia/Riyadh')::date+1);
 assert j.status='MANAGER_APPROVED' and j.published_snapshot=snapshot;
 j:=public.approve_job_effective_date(j.id,j.revision,(now() at time zone 'Asia/Riyadh')::date+1);
 select * into s from public.job_publication_schedules where job_description_id=j.id and status='PENDING';
 perform set_config('test.schedule_id',s.id::text,true);perform set_config('test.old_snapshot',snapshot::text,true);
 begin update public.job_descriptions set status='PUBLISHED' where id=j.id;raise exception 'Early publication should fail';exception when others then if sqlerrm not like '%ألغِ جدولة%' then raise;end if;end;
 begin perform public.save_job_description_draft(j.id,j.revision,current_setting('test.payload')::jsonb);raise exception 'Scheduled edit should fail';exception when others then if sqlerrm not like '%أعد الوصف%' and sqlerrm not like '%ألغِ جدولة%' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub','eabb8105-e54d-45a3-90c8-15334698bbfc',true);
do $$ declare a public.job_description_acknowledgements%rowtype;begin
 select * into a from public.acknowledge_job_description(current_setting('test.job_id')::uuid,'scheduled old snapshot test');
 assert a.job_snapshot=current_setting('test.old_snapshot')::jsonb;
 begin perform public.cancel_job_effective_date(current_setting('test.schedule_id')::uuid,'غير مسموح');raise exception 'Expected denial';exception when insufficient_privilege then null;end;
end $$;
reset role;
do $$ declare before_count integer;after_count integer;j public.job_descriptions%rowtype;begin
 select count(*) into before_count from private.job_workflow_tasks where job_description_id=current_setting('test.job_id')::uuid and phase='EMPLOYEE_ACK';
 perform private.process_job_effective_dates();
 select count(*) into after_count from private.job_workflow_tasks where job_description_id=current_setting('test.job_id')::uuid and phase='EMPLOYEE_ACK';assert before_count=after_count;
 -- Inactive approval account blocks release without changing the active snapshot.
 update public.job_publication_schedules set effective_date=(now() at time zone 'Asia/Riyadh')::date where id=current_setting('test.schedule_id')::uuid;
 update public.profiles set active=false,status='inactive' where id='797d5893-d44d-489c-9109-91da4882acfe';
 perform private.process_job_effective_dates();
 assert (select status from public.job_publication_schedules where id=current_setting('test.schedule_id')::uuid)='BLOCKED';
 assert (select published_snapshot from public.job_descriptions where id=current_setting('test.job_id')::uuid)=current_setting('test.old_snapshot')::jsonb;
 update public.profiles set active=true,status='active' where id='797d5893-d44d-489c-9109-91da4882acfe';
 perform set_config('request.jwt.claim.sub','797d5893-d44d-489c-9109-91da4882acfe',true);
 perform public.cancel_job_effective_date(current_setting('test.schedule_id')::uuid,'إلغاء تجريبي بعد توقف المعتمد');
 select * into j from public.job_descriptions where id=current_setting('test.job_id')::uuid;
 perform public.approve_job_effective_date(j.id,j.revision,(now() at time zone 'Asia/Riyadh')::date+1);
 perform set_config('test.schedule_id',(select id::text from public.job_publication_schedules where job_description_id=j.id and status='PENDING'),true);
 -- Simulate reaching midnight only for the synthetic schedule inside this rollback transaction.
 update public.job_publication_schedules set effective_date=(now() at time zone 'Asia/Riyadh')::date where id=current_setting('test.schedule_id')::uuid;
 perform private.process_job_effective_dates();perform private.process_job_effective_dates();
 select * into j from public.job_descriptions where id=current_setting('test.job_id')::uuid;
 assert j.status='PUBLISHED' and j.published_snapshot->>'title'='عنوان مؤجل للسريان';
 assert j.published_snapshot->>'effective_date'=((now() at time zone 'Asia/Riyadh')::date)::text;
 assert (select count(*) from private.job_workflow_tasks w join public.tasks t on t.id=w.task_id where w.job_description_id=j.id and w.phase='EMPLOYEE_ACK' and t.deleted_at is null and t.status<>'مكتملة')=1;
 assert (select status from public.job_publication_schedules where id=current_setting('test.schedule_id')::uuid)='PUBLISHED';
 assert not (select needs_changes from public.job_periodic_reviews where job_description_id=j.id);
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','2347fbff-372e-43d1-a2e4-094f5b3159bf',true);
do $$ declare j public.job_descriptions%rowtype;r public.job_periodic_reviews%rowtype;begin
 select * into j from public.job_descriptions where id=current_setting('test.job_id')::uuid;
 select * into r from public.job_periodic_reviews where job_description_id=j.id;
 perform public.request_job_periodic_change(j.id,r.revision,(j.published_snapshot->>'revision')::integer,'طلب تحديث تجريبي قبل الأرشفة');
end $$;
select set_config('request.jwt.claim.sub','797d5893-d44d-489c-9109-91da4882acfe',true);
update public.job_descriptions set status='ARCHIVED' where id=current_setting('test.job_id')::uuid;
reset role;
do $$ begin
 assert not (select enabled from public.job_periodic_reviews where job_description_id=current_setting('test.job_id')::uuid);
 assert not exists(select 1 from private.job_workflow_tasks w join public.tasks t on t.id=w.task_id where w.job_description_id=current_setting('test.job_id')::uuid and w.phase in ('PERIODIC_REVIEW','DRAFT_REVISION') and t.deleted_at is null and t.status<>'مكتملة');
end $$;
select 'PASS: periodic no-change preserves revision and snapshot, task dedup, future publication and acknowledgement protection, scheduled release idempotency' as result;
rollback;
