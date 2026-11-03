begin;
select set_config('request.jwt.claim.sub','719473c6-5354-4775-b6f4-c0239a86c385',true);
set local role authenticated;
do $test$
declare j public.job_descriptions%rowtype; before_content jsonb; r integer; original_reviewer uuid;
begin
 j:=public.create_job_description_draft(gen_random_uuid(),jsonb_build_object('title','اختبار مؤقت لصلاحية إعادة الوصف','reference_profile_id','eabb8105-e54d-45a3-90c8-15334698bbfc','purpose','وصف تجريبي للتحقق من صلاحية مسؤول النظام مع المحافظة على دورة المراجعة والاعتماد وسجل الإصدارات.','content',jsonb_build_object('responsibilities',jsonb_build_array('مهمة اختبار'),'authorities',jsonb_build_array('صلاحية اختبار'),'reports',jsonb_build_array(jsonb_build_object('name','تقرير اختبار')),'kpis',jsonb_build_array(jsonb_build_object('name','مؤشر اختبار','measure','تحقق موثق','target','وفق الخطة','source','سجل اختبار','weight',100)),'qualifications',jsonb_build_object('education','مؤهل مناسب'))));
 j:=public.submit_job_description_draft(j.id,j.revision);
 assert j.status='IN_REVIEW'; assert j.reviewer_id<>(select auth.uid());
 before_content:=j.content; r:=j.revision; original_reviewer:=j.reviewer_id;
 perform set_config('request.jwt.claim.sub','0904f58b-507b-482a-b0b5-ae5d7330c11a',true);
 begin perform public.return_job_description_for_changes(j.id,r,'محاولة مدير غير مراجع'); raise exception 'Unrelated manager must be denied'; exception when insufficient_privilege then null; end;
 perform set_config('request.jwt.claim.sub','719473c6-5354-4775-b6f4-c0239a86c385',true);
 begin perform public.return_job_description_for_changes(j.id,r-1,'تعارض إصدار'); raise exception 'Stale revision must fail'; exception when sqlstate 'PT409' then null; end;
 begin perform public.return_job_description_for_changes(j.id,r,''); raise exception 'Reason must be required'; exception when others then if sqlerrm not like '%سبب الإعادة مطلوب%' then raise; end if; end;
 j:=public.return_job_description_for_changes(j.id,r,'تحديث المؤشرات بتوجيه مسؤول النظام');
 assert j.status='CHANGES_REQUESTED' and j.content=before_content and j.published_snapshot is null;
 assert j.revision=r+1;
 assert exists(select 1 from public.job_description_versions v where v.job_description_id=j.id and v.revision=j.revision and v.actor_id=(select auth.uid()) and v.action='CHANGES_REQUESTED');
 j:=public.submit_job_description_draft(j.id,j.revision);
 assert j.status='IN_REVIEW' and j.reviewer_id=original_reviewer and j.final_reviewed_at is null;
end $test$;
reset role;
select 'PASS: admin return, manager denial, revision conflict, required reason, preserved content, audit history, mandatory rereview' result;
rollback;