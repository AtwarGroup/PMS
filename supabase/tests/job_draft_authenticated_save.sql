-- Exercise actual client ACLs, not only JWT claims under the postgres role.
-- Every fixture and workflow side effect is rolled back.
begin;
select set_config('request.jwt.claims',jsonb_build_object('sub',id,'role','authenticated')::text,true) from public.profiles where email='e2e-admin@atwargroup.test' and active;
select set_config('qa.manager_id',id::text,true) from public.profiles where email='e2e-manager@atwargroup.test' and active;
set local role authenticated;
do $qa$
declare j public.job_descriptions%rowtype; before_revision integer;
begin
 if current_user<>'authenticated' or auth.uid() is null then raise exception 'QA requires authenticated admin'; end if;
 insert into public.job_descriptions(job_code,title,family,job_level,purpose,content,reviewer_mode,reviewer_id,reviewer_override_reason)
 values('JOB-'||(900000000+floor(random()*99999999)::bigint)::text,'QA authenticated authoring','QA','QA','QA complete purpose for authenticated draft save and submission regression.',
 '{"responsibilities":[{"text":"QA responsibility"}],"authorities":[{"text":"QA authority"}],"reports":[{"name":"QA report"}],"qualifications":{"education":"QA education"},"kpis":[{"name":"QA KPI","measure":"QA measure","source":"QA source","target":"95%","weight":100}]}',
 'override',current_setting('qa.manager_id')::uuid,'QA isolated reviewer')
 returning * into j;
 before_revision:=j.revision;
 select * into j from public.save_job_description_draft(j.id,j.revision,to_jsonb(j));
 if j.revision<>before_revision+1 or j.status<>'DRAFT' then raise exception 'QA draft save failed'; end if;
 select * into j from public.submit_job_description_draft(j.id,j.revision);
 if j.status<>'IN_REVIEW' or j.reviewer_id<>current_setting('qa.manager_id')::uuid then raise exception 'QA submit failed'; end if;
 if has_function_privilege('authenticated','private.employee_change_covers_job(public.job_descriptions,public.job_descriptions)','EXECUTE') then raise exception 'QA private approval helper exposed'; end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('qa.manager_id'),'role','authenticated')::text,true);
 update public.job_descriptions set status='MANAGER_APPROVED' where id=j.id returning * into j;
 if j.status<>'MANAGER_APPROVED' or j.manager_approved_by<>auth.uid() then raise exception 'QA manager review failed'; end if;
end $qa$;
rollback;