-- Read-only snapshot of live recruitment function definitions, 2026-10-28. No records or credentials.
CREATE OR REPLACE FUNCTION public.recruitment_application_action(p_application uuid, p_action text, p_data jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'private'
AS $function$select private.recruitment_application_action(p_application,p_action,p_data)$function$
;
CREATE OR REPLACE FUNCTION private.recruitment_application_action(p_application uuid, p_action text, p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$declare a private.recruitment_applications;r private.recruitment_requests;target private.recruitment_requests;doc private.recruitment_documents;cid uuid;aid uuid;token uuid;u private.recruitment_candidate_updates;note text:=btrim(coalesce(p_data->>'note',''));begin
select * into strict a from private.recruitment_applications where id=p_application for update;select * into strict r from private.recruitment_requests where id=a.request_id;
if not private.recruitment_visible(r.id)then raise exception 'السجل غير متاح'using errcode='42501';end if;
if p_action='second_interview'and r.status='open'and auth.uid()=r.department_approver_id and a.stage in('screening','interview','assessment')then
if length(note)<5 then raise exception 'سبب المقابلة الثانية مطلوب';end if;update private.recruitment_applications set second_interview_reason=note where id=a.id;
elsif p_action='confirm_join'and auth.uid()=r.supervisor_id and r.status='open'and a.stage='accepted'then
if(p_data->>'join_date')::date>current_date or nullif(p_data->>'join_date','')is null or length(note)<3 then raise exception 'أكد الحضور وتاريخ المباشرة الفعلي';end if;update private.recruitment_applications set joining_confirmed_on=(p_data->>'join_date')::date,joining_confirmed_by=auth.uid()where id=a.id;
elsif p_action='internal_approve'and a.internal_employee_id is not null and auth.uid()=a.internal_manager_id and r.status='open'then update private.recruitment_applications set internal_approved=true where id=a.id;
elsif p_action='internal_final'and a.internal_employee_id is not null and a.internal_approved and a.selection_approved and auth.uid()=r.approver_id and private.recruitment_permission('recruitment.approve')and r.status='open'and a.stage='recommended'then
-- The existing employee's compensation and identity remain governed by employee records.
perform 1 from private.recruitment_requests where id=r.id for update;if(select count(*)from private.recruitment_applications where request_id=r.id and stage in('hired','accepted'))>=r.headcount then raise exception 'اكتمل العدد';end if;
if(p_data->>'join_date')::date>current_date or nullif(p_data->>'join_date','')is null then raise exception 'سجل تاريخ النقل الفعلي';end if;
insert into private.hr_titles(title,job_description_id)values(r.job_snapshot->>'title',r.job_id)on conflict(title)do nothing;
update private.hr_employees set department_id=r.department_id,section_id=r.section_id,manager_id=r.manager_id,title_id=(select id from private.hr_titles where title=r.job_snapshot->>'title')where id=a.internal_employee_id;
update private.recruitment_applications set stage='hired',employee_id=internal_employee_id,revision=revision+1 where id=a.id;if(select count(*)from private.recruitment_applications where request_id=r.id and stage='hired')>=r.headcount then update private.recruitment_requests set status='closed',published=false,revision=revision+1 where id=r.id;end if;
elsif auth.uid()=r.recruiter_id and private.recruitment_permission('recruitment.manage')then
if p_action='documents_exception'and a.stage='accepted'and r.status='open'then
if nullif(p_data->>'due_date','')is null or(p_data->>'due_date')::date<current_date or length(note)<5 then raise exception 'سجل مبرر الاستثناء وموعد الاستكمال';end if;
update private.recruitment_applications set documents_exception_due=(p_data->>'due_date')::date,documents_exception_reason=note where id=a.id;perform private.recruitment_task('documents:'||a.id,r.id,a.id,r.recruiter_id,'استكمال مستندات التعيين',1);update private.recruitment_tasks set due_at=((p_data->>'due_date')::date+time '17:00')at time zone 'Asia/Riyadh'where key='documents:'||a.id;
elsif p_action='postpone'and a.stage='accepted'and r.status='open'then
if length(note)<5 or nullif(p_data->>'start_date','')is null or(p_data->>'start_date')::date<current_date or p_data->>'coordinated'is distinct from 'true'then raise exception 'وثق التنسيق مع المدير المباشر والسبب والتاريخ الجديد';end if;update private.recruitment_offers set start_date=(p_data->>'start_date')::date where application_id=a.id and state='accepted';
elsif p_action='portal_link'and(r.status='open'or(a.stage='hired'and a.documents_exception_due is not null))then insert into private.recruitment_portal_links(application_id)values(a.id)returning id into token;return jsonb_build_object('token',token);
elsif p_action='document_prepare'then insert into private.recruitment_documents(candidate_id,application_id,kind)values(a.candidate_id,a.id,p_data->>'kind')returning file_token into token;return jsonb_build_object('file_token',token);
elsif p_action='document_review'then
select * into strict doc from private.recruitment_documents where id=(p_data->>'document_id')::uuid and application_id=a.id for update;
if p_data->>'state'not in('approved','rejected')or length(note)<3 then raise exception 'وثق مراجعة المستند';end if;
if p_data->>'state'='approved'and not exists(select 1 from storage.objects where bucket_id='recruitment-documents'and name=doc.file_token::text||'/document.pdf')then raise exception 'لم يرفع الملف بعد';end if;
update private.recruitment_documents set state=p_data->>'state',note=note,reviewed_by=auth.uid()where id=doc.id;
begin perform private.recruitment_check_documents(a.id);if not exists(select 1 from unnest(array['identity','passport','education','experience','address','iban']||case when r.job_snapshot->>'title'~'(سائق|مندوب)'then array['license']else '{}'::text[]end)k where not exists(select 1 from private.recruitment_documents d where d.application_id=a.id and d.kind=k and d.state='approved'))then update private.recruitment_tasks set done=true where key='documents:'||a.id;update private.recruitment_applications set documents_exception_due=null,documents_exception_reason=null where id=a.id;end if;exception when raise_exception then null;end;
elsif p_action='update_review'then
select * into strict u from private.recruitment_candidate_updates where id=(p_data->>'update_id')::uuid and application_id=a.id and state='pending'for update;
if p_data->>'state'not in('approved','rejected')or length(note)<3 then raise exception 'وثق مراجعة التغييرات';end if;
if p_data->>'state'='approved'then
update private.recruitment_candidate_updates set previous_data=(select jsonb_build_object('phone',phone,'city',city,'experience',experience,'resume_text',resume_text)from private.recruitment_candidates where id=a.candidate_id)where id=u.id;
perform private.recruitment_event(r.id,a.id,'candidate_previous','حفظت القيم السابقة قبل اعتماد التحديث');
update private.recruitment_candidates set phone=coalesce(nullif(u.data->>'phone',''),phone),city=coalesce(u.data->>'city',city),experience=coalesce(u.data->>'experience',experience),resume_text=coalesce(u.data->>'resume_text',resume_text)where id=a.candidate_id;end if;update private.recruitment_candidate_updates set state=p_data->>'state'where id=u.id;
elsif p_action='transfer'then
if p_data->>'consent'is distinct from 'true'or length(note)<5 then raise exception 'أكد موافقة المرشح وملاءمته للوظيفة الجديدة';end if;
if not private.recruitment_visible((p_data->>'target_request')::uuid)then raise exception 'الطلب الآخر غير متاح';end if;select * into strict target from private.recruitment_requests where id=(p_data->>'target_request')::uuid and status='open';
insert into private.recruitment_applications(request_id,candidate_id,source,referral_note)values(target.id,a.candidate_id,'إعادة ترشيح',note)returning id into aid;perform private.recruitment_event(target.id,aid,'candidate_transferred','الموافقة والملاءمة: '||note||'؛ التقييمات السابقة محفوظة في الملف الأصلي');return jsonb_build_object('application_id',aid);
elsif p_action='internal_link'and r.status='open'and a.stage='screening'then
if not exists(select 1 from private.hr_employees where id=(p_data->>'employee_id')::uuid and lower(email)=(select lower(email)from private.recruitment_candidates where id=a.candidate_id))then raise exception 'تحقق من مطابقة الموظف الحالي مع المرشح';end if;
if not exists(select 1 from public.profiles where id=(p_data->>'current_manager_id')::uuid and active and status='active'and(role='admin'or'recruitment'=any(allowed_modules)))then raise exception 'حدد مدير الإدارة الحالية المخول';end if;
update private.recruitment_applications set internal_employee_id=(p_data->>'employee_id')::uuid,internal_manager_id=(p_data->>'current_manager_id')::uuid where id=a.id;
else raise exception 'الإجراء غير متاح';end if;
else raise exception 'غير مخول بالإجراء'using errcode='42501';end if;
update private.recruitment_applications set revision=revision+1,updated_at=now()where id=a.id;perform private.recruitment_event(r.id,a.id,p_action,note);return '{}'::jsonb;end$function$
;
CREATE OR REPLACE FUNCTION public.recruitment_batch_action(p_request uuid, p_action text, p_data jsonb)
 RETURNS void
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'private'
AS $function$select private.recruitment_batch_action(p_request,p_action,p_data)$function$
;
CREATE OR REPLACE FUNCTION private.recruitment_batch_action(p_request uuid, p_action text, p_data jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$declare r private.recruitment_requests;b private.recruitment_batches;cnt int;begin
if not private.recruitment_visible(p_request)then raise exception 'السجل غير متاح'using errcode='42501';end if;if p_action='submit'then if jsonb_typeof(p_data->'application_ids')is distinct from 'array'then raise exception 'حدد مرشحي الدفعة';end if;perform 1 from private.recruitment_applications where request_id=p_request and id in(select value::uuid from jsonb_array_elements_text(p_data->'application_ids'))order by id for update;end if;select * into strict r from private.recruitment_requests where id=p_request for update;
if r.status<>'open'or r.route<>'advertised'then raise exception 'الدفعات لمسار البحث المفتوح فقط';end if;
select * into b from private.recruitment_batches where request_id=r.id order by number desc limit 1 for update;
if p_action='submit'and auth.uid()=r.recruiter_id and private.recruitment_permission('recruitment.manage')and b.state='sourcing'then
cnt:=jsonb_array_length(p_data->'application_ids');if cnt<>b.quota or(select count(distinct value)from jsonb_array_elements_text(p_data->'application_ids'))<>cnt then raise exception 'حدد % مرشحين جدد بالضبط',b.quota;end if;
if exists(select 1 from jsonb_array_elements_text(p_data->'application_ids')x where not exists(select 1 from private.recruitment_applications where id=x.value::uuid and request_id=r.id and batch_number is null and stage not in('hired','rejected','withdrawn','no_show')))then raise exception 'مرشح مكرر أو غير متاح';end if;
update private.recruitment_applications set batch_number=b.number where id in(select value::uuid from jsonb_array_elements_text(p_data->'application_ids'));
update private.recruitment_batches set state='review',submitted_at=now()where request_id=r.id and number=b.number;update private.recruitment_tasks set done=true where key='batch:'||r.id;perform private.recruitment_task('batch-review:'||r.id,r.id,null,r.department_approver_id,'تقييم دفعة المرشحين',3);
elsif p_action='none_selected'and auth.uid()=r.department_approver_id and b.state='review'then
if length(btrim(coalesce(p_data->>'note','')))<5 then raise exception 'وثق سبب عدم الاختيار';end if;
if exists(select 1 from private.recruitment_applications where request_id=r.id and batch_number=b.number and(stage<>'rejected'or rejection_reason is null))then raise exception 'سجل سبب رفض كل مرشح في الدفعة أولًا';end if;
update private.recruitment_batches set state='exhausted',note=p_data->>'note'where request_id=r.id and number=b.number;update private.recruitment_tasks set done=true where key='batch-review:'||r.id;
if b.number<3 then insert into private.recruitment_batches(request_id,number,quota)values(r.id,b.number+1,5);perform private.recruitment_task('batch:'||r.id,r.id,null,r.recruiter_id,'توفير ٥ مرشحين جدد',5);else perform private.recruitment_event(r.id,null,'sourcing_suspended','توقف توفير المرشحين بعد استنفاد الدفعات؛ يظل الطلب مفتوحًا');end if;
elsif p_action='resume'and auth.uid()=r.development_id and private.recruitment_permission('recruitment.development')and b.state='exhausted'and b.number>=3 then
if length(btrim(coalesce(p_data->>'note','')))<5 then raise exception 'وثق مراجعة المتطلبات والراتب والتقييم ومبرر الاستئناف';end if;
insert into private.recruitment_batches(request_id,number,quota,note)values(r.id,b.number+1,(p_data->>'quota')::int,p_data->>'note');perform private.recruitment_task('batch:'||r.id,r.id,null,r.recruiter_id,'دفعة إضافية معتمدة',5);
else raise exception 'الإجراء غير متاح'using errcode='42501';end if;perform private.recruitment_event(r.id,null,'batch_'||p_action,p_data->>'note');end$function$
;
CREATE OR REPLACE FUNCTION public.recruitment_calendar(p_action text, p_data jsonb)
 RETURNS void
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'private'
AS $function$select private.recruitment_calendar(p_action,p_data)$function$
;
CREATE OR REPLACE FUNCTION private.recruitment_calendar(p_action text, p_data jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$begin
if not private.recruitment_permission('recruitment.development')then raise exception 'إدارة تقويم العمل لمشرف تطوير الأعمال'using errcode='42501';end if;
if p_action='add'then insert into private.recruitment_holidays(day,label)values((p_data->>'day')::date,p_data->>'label')on conflict(day)do update set label=excluded.label;
elsif p_action='remove'then delete from private.recruitment_holidays where day=(p_data->>'day')::date;
else raise exception 'إجراء غير متاح';end if;
update private.recruitment_tasks set due_at=private.recruitment_work_due(started_at,case when key like 'batch-review:%'or key like 'referral:%'then 3 when key like 'batch:%'then coalesce((select case when b.number=1 then r.sourcing_days else 5 end from private.recruitment_batches b join private.recruitment_requests r on r.id=b.request_id where b.request_id=recruitment_tasks.request_id order by b.number desc limit 1),5)else 2 end)where not done and key not like 'documents:%';end$function$
;
CREATE OR REPLACE FUNCTION public.recruitment_candidate_add(p_request uuid, p_data jsonb)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'private'
AS $function$select private.recruitment_candidate_add(p_request,p_data)$function$
;
CREATE OR REPLACE FUNCTION private.recruitment_candidate_add(p_request uuid, p_data jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$declare r private.recruitment_requests;aid uuid;cid uuid;email_id uuid;begin
if not private.recruitment_visible(p_request)then raise exception 'السجل غير متاح'using errcode='42501';end if;select * into strict r from private.recruitment_requests where id=p_request for update;
if auth.uid()not in(r.created_by,r.recruiter_id)or r.status not in('draft','department_review','hr_review','finance_review','approval','open')then raise exception 'إضافة المرشحين غير متاحة'using errcode='42501';end if;
if(select count(*)from private.recruitment_candidates where identity_no=nullif(btrim(p_data->>'identity_no'),'')or(passport_no=upper(nullif(btrim(p_data->>'passport_no'),''))and passport_country=upper(nullif(btrim(p_data->>'passport_country'),''))))>1 then raise exception 'تعارض الهوية والجواز بين ملفين؛ راجع البيانات';end if;
select id into cid from private.recruitment_candidates where identity_no=nullif(btrim(p_data->>'identity_no'),'')or(passport_no=upper(nullif(btrim(p_data->>'passport_no'),''))and passport_country=upper(nullif(btrim(p_data->>'passport_country'),'')));
select id into email_id from private.recruitment_candidates where lower(email)=lower(btrim(p_data->>'email'));
if cid is not null and email_id is not null and cid<>email_id then raise exception 'تعارض الهوية مع البريد؛ راجع الملفين قبل المتابعة';end if;
if cid is not null then
insert into private.recruitment_applications(request_id,candidate_id,source,referral_note)values(r.id,cid,p_data->>'source',coalesce(p_data->>'referral_note',''))returning id into aid;perform private.recruitment_event(r.id,aid,'candidate_reused','ربط ملف المرشح الموجود حسب الهوية أو الجواز');
else
-- The legacy routine requires a review/open state. Its validation is retained here without altering request status.
if coalesce(p_data->>'email','')!~'^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'or coalesce(p_data->>'phone','')!~'^\+?[0-9 ()-]{8,20}$'or length(coalesce(p_data->>'resume_text',''))<10 then raise exception 'تحقق من بيانات المرشح';end if;
insert into private.recruitment_candidates(full_name,email,phone,city,saudi,experience,resume_text,identity_no,passport_no,passport_country)values(p_data->>'full_name',lower(btrim(p_data->>'email')),p_data->>'phone',coalesce(p_data->>'city',''),(p_data->>'saudi')::boolean,coalesce(p_data->>'experience',''),p_data->>'resume_text',nullif(btrim(p_data->>'identity_no'),''),upper(nullif(btrim(p_data->>'passport_no'),'')),upper(nullif(btrim(p_data->>'passport_country'),'')))on conflict(lower(email))do nothing returning id into cid;
if cid is null then cid:=email_id;update private.recruitment_candidates set identity_no=coalesce(identity_no,nullif(btrim(p_data->>'identity_no'),'')),passport_no=coalesce(passport_no,upper(nullif(btrim(p_data->>'passport_no'),''))),passport_country=coalesce(passport_country,upper(nullif(btrim(p_data->>'passport_country'),'')))where id=cid;end if;
insert into private.recruitment_applications(request_id,candidate_id,source,referral_note)values(r.id,cid,p_data->>'source',coalesce(p_data->>'referral_note',''))returning id into aid;perform private.recruitment_event(r.id,aid,'candidate_added',p_data->>'referral_note');end if;
if nullif(p_data->>'passport_no','')is not null and nullif(p_data->>'passport_country','')is null then raise exception 'حدد دولة إصدار الجواز';end if;
if r.route='referral'and r.status='open'then perform private.recruitment_task('referral:'||aid,r.id,aid,r.supervisor_id,'مراجعة مرشح الإدارة والمقابلة والقرار',3);end if;return aid;end$function$
;
CREATE OR REPLACE FUNCTION private.recruitment_candidate_add_v1(p_request uuid, p_data jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$
declare r private.recruitment_requests%rowtype;cid uuid;aid uuid;v_email text:=lower(btrim(p_data->>'email'));begin
 if not private.recruitment_visible(p_request)then raise exception 'السجل غير متاح'using errcode='42501';end if;select * into strict r from private.recruitment_requests where id=p_request for update;
 if not(private.recruitment_permission('recruitment.manage')or auth.uid()=r.created_by)then raise exception 'إضافة المرشحين غير متاحة'using errcode='42501';end if;
 if r.status not in('hr_review','finance_review','approval','open')then raise exception 'الطلب مغلق';end if;
 if coalesce(v_email,'')!~'^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'or coalesce(p_data->>'phone','')!~'^\+?[0-9 ()-]{8,20}$'then raise exception 'تحقق من البريد ورقم الجوال';end if;
 if coalesce(length(btrim(p_data->>'resume_text')),0)<10 or coalesce(length(btrim(p_data->>'source')),0)<2 then raise exception 'أكمل ملخص السيرة ومصدر المرشح';end if;
 insert into private.recruitment_candidates(full_name,email,phone,city,saudi,experience,resume_text)values(btrim(p_data->>'full_name'),v_email,btrim(p_data->>'phone'),coalesce(p_data->>'city',''),(p_data->>'saudi')::boolean,coalesce(p_data->>'experience',''),p_data->>'resume_text')on conflict(lower(email))do nothing returning id into cid;
 if cid is null then select id into cid from private.recruitment_candidates where lower(recruitment_candidates.email)=v_email;end if;
 insert into private.recruitment_applications(request_id,candidate_id,source,referral_note)values(r.id,cid,p_data->>'source',coalesce(p_data->>'referral_note',''))on conflict(request_id,candidate_id)do nothing returning id into aid;
 if aid is null then raise exception 'المرشح مسجل لهذا الشاغر بالفعل';end if;perform private.recruitment_event(r.id,aid,'candidate_added',p_data->>'referral_note');return aid;end$function$
;
CREATE OR REPLACE FUNCTION private.recruitment_check_documents(p_application uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private'
AS $function$declare a private.recruitment_applications;r private.recruitment_requests;required text[];begin
select * into strict a from private.recruitment_applications where id=p_application;select * into strict r from private.recruitment_requests where id=a.request_id;
required:=array['identity','passport','education','experience','address','iban'];if r.job_snapshot->>'title'~'(سائق|مندوب)'then required:=required||array['license'];end if;
if exists(select 1 from unnest(required)k where not exists(select 1 from private.recruitment_documents d join storage.objects o on o.bucket_id='recruitment-documents'and o.name=d.file_token::text||'/document.pdf'where d.application_id=a.id and d.kind=k and d.state='approved'))and(a.documents_exception_due is null or a.documents_exception_due<current_date or length(coalesce(a.documents_exception_reason,''))<5)then raise exception 'المستندات ناقصة؛ يلزم استكمالها أو استثناء مسؤول التوظيف بتاريخ استكمال';end if;end$function$
;
CREATE OR REPLACE FUNCTION public.recruitment_context()
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'private'
AS $function$select private.recruitment_context()||jsonb_build_object('audit_admin',private.is_admin())$function$
;
CREATE OR REPLACE FUNCTION private.recruitment_context()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$declare result jsonb;begin result:=private.recruitment_context_v1();return result||jsonb_build_object('salaries',case when private.recruitment_permission('recruitment.personnel')or private.recruitment_permission('recruitment.development')then(select coalesce(jsonb_agg(to_jsonb(s)order by title),'[]')from private.recruitment_salary_reference s)else result->'salaries'end,'personnel',private.recruitment_permission('recruitment.personnel'),'development',private.recruitment_permission('recruitment.development'),'holidays',(select coalesce(jsonb_agg(to_jsonb(h)order by day),'[]')from private.recruitment_holidays h),'people',(select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'full_name',p.full_name,'manage',p.role='admin'or'recruitment.manage'=any(p.permissions),'personnel',p.role='admin'or'recruitment.personnel'=any(p.permissions),'development',p.role='admin'or'recruitment.development'=any(p.permissions),'finance',p.role='admin'or'recruitment.finance'=any(p.permissions),'approve',p.role='admin'or'recruitment.approve'=any(p.permissions))order by full_name),'[]')from public.profiles p where p.active and p.status='active'and(p.role='admin'or'recruitment'=any(p.allowed_modules))));end$function$
;
CREATE OR REPLACE FUNCTION private.recruitment_context_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$
begin perform private.require_module('recruitment');
 return jsonb_build_object('user_id',auth.uid(),'manage',private.recruitment_permission('recruitment.manage'),'finance',private.recruitment_permission('recruitment.finance'),'approve',private.recruitment_permission('recruitment.approve'),
 'can_request',private.recruitment_permission('recruitment.manage')or private.current_user_role()='manager',
 'jobs',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'job_code',job_code,'title',published_snapshot->>'title','snapshot',published_snapshot) order by job_code),'[]')from public.job_descriptions where published_snapshot is not null),
 'salaries',case when private.recruitment_permission('recruitment.manage')or private.recruitment_permission('recruitment.finance')or private.recruitment_permission('recruitment.approve')then(select coalesce(jsonb_agg(to_jsonb(s)order by title),'[]')from private.recruitment_salary_reference s)else '[]'::jsonb end,
 'departments',(select coalesce(jsonb_agg(to_jsonb(d)order by name),'[]')from private.hr_departments d),'sections',(select coalesce(jsonb_agg(to_jsonb(s)order by name),'[]')from private.hr_sections s),
 'people',(select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'full_name',p.full_name,'manage',p.role='admin'or'recruitment.manage'=any(p.permissions),'finance',p.role='admin'or'recruitment.finance'=any(p.permissions),'approve',p.role='admin'or'recruitment.approve'=any(p.permissions))order by full_name),'[]')from public.profiles p where p.active and p.status='active'and(p.role='admin'or'recruitment'=any(p.allowed_modules))),
 'managers',(select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'full_name',e.full_name)order by full_name),'[]')from private.hr_employees e));end$function$
;
CREATE OR REPLACE FUNCTION public.recruitment_detail(p_request uuid)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'private'
AS $function$select private.recruitment_detail(p_request)$function$
;
CREATE OR REPLACE FUNCTION private.recruitment_detail(p_request uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$declare result jsonb;begin result:=private.recruitment_detail_v1(p_request);return result||jsonb_build_object('request',(select to_jsonb(r)from private.recruitment_requests r where id=p_request),'can_pay',true,'offers',(select coalesce(jsonb_agg(to_jsonb(o)order by o.created_at desc),'[]')from private.recruitment_offers o join private.recruitment_applications a on a.id=o.application_id where a.request_id=p_request),'batches',(select coalesce(jsonb_agg(to_jsonb(b)order by number),'[]')from private.recruitment_batches b where request_id=p_request),'documents',(select coalesce(jsonb_agg(to_jsonb(d)order by d.created_at desc),'[]')from private.recruitment_documents d join private.recruitment_applications a on a.id=d.application_id where a.request_id=p_request),'updates',(select coalesce(jsonb_agg(to_jsonb(u)order by u.created_at desc),'[]')from private.recruitment_candidate_updates u join private.recruitment_applications a on a.id=u.application_id where a.request_id=p_request),'tasks',(select coalesce(jsonb_agg(to_jsonb(t)order by t.due_at),'[]')from private.recruitment_tasks t where request_id=p_request and not done),'previous_interviews',(select coalesce(jsonb_agg(to_jsonb(i)||jsonb_build_object('candidate_id',a.candidate_id)),'[]')from private.recruitment_interviews i join private.recruitment_applications a on a.id=i.application_id where a.request_id<>p_request and exists(select 1 from private.recruitment_applications current_app where current_app.request_id=p_request and current_app.candidate_id=a.candidate_id)));end$function$
;
CREATE OR REPLACE FUNCTION private.recruitment_detail_v1(p_request uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$
declare r private.recruitment_requests%rowtype;pay boolean;begin
 if not private.recruitment_visible(p_request)then raise exception 'السجل غير متاح'using errcode='42501';end if;
 select * into strict r from private.recruitment_requests where id=p_request;
 pay:=private.recruitment_permission('recruitment.manage')or(auth.uid()=r.finance_id and private.recruitment_permission('recruitment.finance'))or(auth.uid()=r.approver_id and private.recruitment_permission('recruitment.approve'));
 return jsonb_build_object('request',case when pay then to_jsonb(r)else to_jsonb(r)-'salary_snapshot'-'salary_id'end,'can_pay',pay,
 'applications',(select coalesce(jsonb_agg(to_jsonb(a)||jsonb_build_object('candidate',to_jsonb(c))order by a.created_at),'[]')from private.recruitment_applications a join private.recruitment_candidates c on c.id=a.candidate_id where a.request_id=p_request),
 'interviews',(select coalesce(jsonb_agg(to_jsonb(i)order by i.scheduled_at desc),'[]')from private.recruitment_interviews i join private.recruitment_applications a on a.id=i.application_id where a.request_id=p_request),
 'offers',case when pay then(select coalesce(jsonb_agg(to_jsonb(o)order by o.created_at desc),'[]')from private.recruitment_offers o join private.recruitment_applications a on a.id=o.application_id where a.request_id=p_request)else '[]'::jsonb end,
 'events',(select coalesce(jsonb_agg(to_jsonb(e)order by e.id desc),'[]')from private.recruitment_events e where request_id=p_request and private.is_admin()));end$function$
;
CREATE OR REPLACE FUNCTION public.recruitment_document_allowed(p_name text, p_write boolean)
 RETURNS boolean
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'private'
AS $function$select private.recruitment_document_allowed(p_name,p_write)$function$
;
CREATE OR REPLACE FUNCTION private.recruitment_document_allowed(p_name text, p_write boolean)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$declare d private.recruitment_documents;r private.recruitment_requests;begin
if p_name!~'^[0-9a-f-]{36}/document.pdf$'then return false;end if;select * into d from private.recruitment_documents where file_token::text=split_part(p_name,'/',1);if not found then return false;end if;select r0.* into r from private.recruitment_requests r0 join private.recruitment_applications a on a.request_id=r0.id where a.id=d.application_id;
if not p_write then return private.recruitment_visible(r.id);end if;
return(r.status='open'or(r.status in('closed','cancelled')and exists(select 1 from private.recruitment_applications a where a.id=d.application_id and a.stage='hired'and a.documents_exception_due is not null)))and d.state='pending'and d.created_at>now()-interval '1 hour'and((private.recruitment_visible(r.id)and auth.uid()=r.recruiter_id)or exists(select 1 from private.recruitment_portal_links l where l.application_id=d.application_id and not l.revoked and l.expires_at>now()));end$function$
;
CREATE OR REPLACE FUNCTION private.recruitment_event(p_request uuid, p_application uuid, p_action text, p_note text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$declare recipient uuid;begin
insert into private.recruitment_events(request_id,application_id,actor_id,action,note)values(p_request,p_application,auth.uid(),p_action,left(coalesce(p_note,''),3000));select private.recruitment_owner(r)into recipient from private.recruitment_requests r where id=p_request;
if recipient is not null and recipient is distinct from auth.uid()then insert into public.notifications(recipient_id,type,title,message)values(recipient,'RECRUITMENT','متابعة التوظيف','يوجد تحديث على طلب التوظيف. افتح وحدة التوظيف للاطلاع على الإجراء.');end if;end$function$
;
CREATE OR REPLACE FUNCTION public.recruitment_interview_save(p_application uuid, p_data jsonb)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'private'
AS $function$select private.recruitment_interview_save(p_application,p_data)$function$
;
CREATE OR REPLACE FUNCTION private.recruitment_interview_save(p_application uuid, p_data jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$
declare a private.recruitment_applications%rowtype;r private.recruitment_requests%rowtype;iid uuid;total numeric;criterion jsonb;value numeric;owner uuid:=(p_data->>'interviewer_id')::uuid;begin
 select * into strict a from private.recruitment_applications where id=p_application for update;select * into strict r from private.recruitment_requests where id=a.request_id;
 if not private.recruitment_visible(r.id)then raise exception 'السجل غير متاح'using errcode='42501';end if;
 if coalesce((p_data->>'round')::int,1)=2 and (owner<>r.department_approver_id or a.second_interview_reason is null)then raise exception 'المقابلة الثانية بطلب مدير الإدارة وتقييمه';end if;
 if coalesce((p_data->>'round')::int,1)=1 and owner<>r.supervisor_id then raise exception 'المقابلة الأولى للمدير المباشر';end if;
 if owner not in(r.supervisor_id,r.department_approver_id) then raise exception 'التقييم للمدير المباشر، ولمدير الإدارة في المقابلة الثانية فقط';end if;
 if owner=r.department_approver_id and owner<>r.supervisor_id and a.second_interview_reason is null then raise exception 'يطلب مدير الإدارة المقابلة الثانية مع السبب أولًا';end if;
 if p_data->>'state'='completed' and auth.uid()<>owner then raise exception 'يسجل المدير تقييمه بنفسه'using errcode='42501';end if;
 if p_data->>'state'<>'completed'and auth.uid()not in(owner,r.recruiter_id)then raise exception 'التنسيق لمسؤول التوظيف أو المقابل'using errcode='42501';end if;
 if a.stage not in('screening','interview','assessment')or r.status<>'open'then raise exception 'المقابلة غير متاحة في هذه المرحلة';end if;
 if coalesce(length(btrim(p_data->>'notes')),0)<3 then raise exception 'سجل ملاحظات المقابلة';end if;
 if p_data->>'state'='completed'then
 if(p_data->>'scheduled_at')::timestamptz>now()then raise exception 'لا يمكن إكمال مقابلة مستقبلية';end if;
 total:=0;for criterion in select * from jsonb_array_elements(r.criteria)loop
 value:=(p_data->'scores'->>(criterion->>'key'))::numeric;if value is null or value<1 or value>5 then raise exception 'أكمل درجات جميع المعايير من 1 إلى 5';end if;total:=total+value*(criterion->>'weight')::numeric/5;end loop;
 if coalesce(p_data->>'recommendation','')not in('suitable','conditional','unsuitable')then raise exception 'حدد التوصية';end if;end if;
 if nullif(p_data->>'id','')is not null then
 select id into strict iid from private.recruitment_interviews where id=(p_data->>'id')::uuid and application_id=a.id and state='scheduled'and interviewer_id=owner for update;
 update private.recruitment_interviews set state=p_data->>'state',scores=p_data->'scores',criteria_snapshot=r.criteria,score=total,notes=p_data->>'notes',recommendation=nullif(p_data->>'recommendation','')where id=iid;
 else
 insert into private.recruitment_interviews(application_id,interviewer_id,scheduled_at,kind,state,scores,criteria_snapshot,score,notes,recommendation,recorded_by)values(a.id,owner,(p_data->>'scheduled_at')::timestamptz,p_data->>'kind',p_data->>'state',p_data->'scores',r.criteria,total,p_data->>'notes',nullif(p_data->>'recommendation',''),auth.uid())returning id into iid;end if;
 update private.recruitment_interviews set round=coalesce((p_data->>'round')::int,1)where id=iid;
 perform private.recruitment_event(r.id,a.id,'interview_'||(p_data->>'state'),p_data->>'notes');return iid;end$function$
;
CREATE OR REPLACE FUNCTION public.recruitment_join(p_application uuid, p_data jsonb)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'private'
AS $function$select private.recruitment_join(p_application,p_data)$function$
;
CREATE OR REPLACE FUNCTION private.recruitment_join(p_application uuid, p_data jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$
declare a private.recruitment_applications%rowtype;r private.recruitment_requests%rowtype;c private.recruitment_candidates%rowtype;o private.recruitment_offers%rowtype;eid uuid;tid uuid;join_on date:=(p_data->>'join_date')::date;begin
 if not private.recruitment_permission('recruitment.manage')then raise exception 'تأكيد المباشرة من اختصاص الموارد البشرية'using errcode='42501';end if;
 select * into strict a from private.recruitment_applications where id=p_application for update;select * into strict r from private.recruitment_requests where id=a.request_id for update;
 if auth.uid()<>r.recruiter_id then raise exception 'استكمال التسجيل لمسؤول التوظيف المحدد'using errcode='42501';end if;
 if a.joining_confirmed_on is null or a.joining_confirmed_on<>join_on then raise exception 'يجب أن يؤكد المدير المباشر الحضور وتاريخ المباشرة أولًا';end if;
 if a.internal_employee_id is not null then raise exception 'النقل الداخلي يعتمد من مساره المخصص';end if;
 if a.stage<>'accepted'or r.status<>'open'then raise exception 'المرشح لم يقبل العرض أو الاحتياج مغلق';end if;
 if join_on is null or join_on>current_date then raise exception 'تاريخ المباشرة الفعلي غير صحيح';end if;
 perform private.recruitment_check_documents(a.id);if length(btrim(coalesce(p_data->>'note','')))<3 then raise exception 'وثق مراجعة المباشرة';end if;
 if(select count(*)from private.recruitment_applications where request_id=r.id and stage='hired')>=r.headcount then raise exception 'اكتمل العدد المطلوب';end if;
 select * into strict c from private.recruitment_candidates where id=a.candidate_id;select * into strict o from private.recruitment_offers where application_id=a.id and state='accepted';
 select id into eid from private.hr_employees where lower(email)=lower(c.email);
 if eid is null then
 if coalesce(p_data->>'employee_code','')!~'^[0-9]+$'then raise exception 'أدخل الرقم الوظيفي';end if;
 insert into private.hr_titles(title,job_description_id)values(r.job_snapshot->>'title',r.job_id)on conflict(title)do nothing;
 select id into strict tid from private.hr_titles where title=r.job_snapshot->>'title';
 insert into private.hr_employees(employee_code,full_name,email,department_id,section_id,title_id,manager_id,join_date,effective_from)values(p_data->>'employee_code',c.full_name,c.email,r.department_id,r.section_id,tid,r.manager_id,join_on,join_on)returning id into eid;
 insert into private.hr_compensation(employee_id,basic,allowances,effective_from)values(eid,o.basic,o.housing+o.transport,join_on);
 else
 if coalesce(p_data->>'existing_employee_id','')<>eid::text then raise exception 'يوجد سجل موظف بهذا البريد؛ تحقق منه وأدخل معرفه للربط دون تعديل بياناته';end if;
 end if;
 update private.recruitment_tasks set done=true where application_id=a.id and key not like 'documents:%';
 update private.recruitment_applications set stage='hired',employee_id=eid,revision=revision+1,updated_at=now()where id=a.id;
 if(select count(*)from private.recruitment_applications where request_id=r.id and stage='hired')>=r.headcount then update private.recruitment_requests set status='closed',published=false,revision=revision+1,updated_at=now()where id=r.id;end if;
 if (select status from private.recruitment_requests where id=r.id)='closed' then insert into public.notifications(recipient_id,type,title,message)values(r.recruiter_id,'RECRUITMENT','اكتمل طلب التوظيف','أوقف الإعلان تلقائيًا؛ راجع الترشيحات المتبقية وأبلغ أصحابها.');end if;
 perform private.recruitment_event(r.id,a.id,'joined',p_data->>'note');return eid;end$function$
;
CREATE OR REPLACE FUNCTION public.recruitment_list()
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'private'
AS $function$select private.recruitment_list()$function$
;
CREATE OR REPLACE FUNCTION private.recruitment_list()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$declare result jsonb;begin result:=private.recruitment_list_v1();return result||jsonb_build_object('tasks',(select coalesce(jsonb_agg(to_jsonb(t)order by due_at),'[]')from private.recruitment_tasks t where not done and private.recruitment_visible(request_id)),'offer_queue',(select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'application_id',a.id,'request_id',r.id,'candidate_name',c.full_name,'job_title',r.job_snapshot->>'title','state',o.state,'version',o.version)),'[]')from private.recruitment_offers o join private.recruitment_applications a on a.id=o.application_id join private.recruitment_requests r on r.id=a.request_id join private.recruitment_candidates c on c.id=a.candidate_id where private.recruitment_visible(r.id)and((o.state='hr_review'and r.hr_id=auth.uid())or(o.state='development_review'and r.development_id=auth.uid())or(o.state='approval'and r.approver_id=auth.uid())or(o.state in('approved','returned','sent')and r.recruiter_id=auth.uid()))));end$function$
;
CREATE OR REPLACE FUNCTION private.recruitment_list_before_queues()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$
begin perform private.require_module('recruitment');return jsonb_build_object(
 'requests',(select coalesce(jsonb_agg(to_jsonb(r)-'salary_snapshot'-'salary_id' order by r.created_at desc),'[]')from private.recruitment_requests r where private.recruitment_visible(r.id)),
 'applications',(select coalesce(jsonb_agg((to_jsonb(a)-'resume_token')||jsonb_build_object('candidate_name',c.full_name,'job_title',r.job_snapshot->>'title')order by a.created_at desc),'[]')from private.recruitment_applications a join private.recruitment_candidates c on c.id=a.candidate_id join private.recruitment_requests r on r.id=a.request_id where private.recruitment_visible(r.id))
 );end$function$
;
CREATE OR REPLACE FUNCTION private.recruitment_list_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$
declare result jsonb;begin result:=private.recruitment_list_before_queues();return result||jsonb_build_object(
'interviews',(select coalesce(jsonb_agg(jsonb_build_object('id',i.id,'application_id',a.id,'request_id',r.id,'candidate_name',c.full_name,'job_title',r.job_snapshot->>'title','interviewer_id',i.interviewer_id,'scheduled_at',i.scheduled_at,'state',i.state)order by i.scheduled_at),'[]')from private.recruitment_interviews i join private.recruitment_applications a on a.id=i.application_id join private.recruitment_requests r on r.id=a.request_id join private.recruitment_candidates c on c.id=a.candidate_id where private.recruitment_visible(r.id)),
'offer_queue',(select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'application_id',a.id,'request_id',r.id,'candidate_name',c.full_name,'job_title',r.job_snapshot->>'title','state',o.state,'version',o.version)order by o.created_at),'[]')from private.recruitment_offers o join private.recruitment_applications a on a.id=o.application_id join private.recruitment_requests r on r.id=a.request_id join private.recruitment_candidates c on c.id=a.candidate_id where private.recruitment_visible(r.id)and((o.state='finance_review'and r.finance_id=auth.uid()and private.recruitment_permission('recruitment.finance'))or(o.state='approval'and r.approver_id=auth.uid()and private.recruitment_permission('recruitment.approve'))or(private.recruitment_permission('recruitment.manage')and o.state in('approved','sent'))))
);end$function$
;
CREATE OR REPLACE FUNCTION public.recruitment_offer_action(p_id uuid, p_action text, p_note text)
 RETURNS void
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'private'
AS $function$select private.recruitment_offer_action(p_id,p_action,p_note)$function$
;
CREATE OR REPLACE FUNCTION private.recruitment_offer_action(p_id uuid, p_action text, p_note text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$declare o private.recruitment_offers;a private.recruitment_applications;r private.recruitment_requests;n text;owner uuid;begin
select * into strict a from private.recruitment_applications where id=(select application_id from private.recruitment_offers where id=p_id)for update;select * into strict r from private.recruitment_requests where id=a.request_id for update;select * into strict o from private.recruitment_offers where id=p_id for update;
if not private.recruitment_visible(r.id)or r.status<>'open'or a.stage not in('offer','accepted')then raise exception 'السجل غير متاح'using errcode='42501';end if;
if length(btrim(coalesce(p_note,'')))<3 then raise exception 'وثق القرار أو الإرسال أو رد المرشح';end if;
owner:=case o.state when 'hr_review'then r.hr_id when 'development_review'then r.development_id when 'approval'then r.approver_id end;
if p_action in('approve','reject')and auth.uid()=owner and((o.state='hr_review'and private.recruitment_permission('recruitment.personnel'))or(o.state='development_review'and private.recruitment_permission('recruitment.development'))or(o.state='approval'and private.recruitment_permission('recruitment.approve')))then
n:=case when p_action='reject'then 'returned'when o.state='hr_review'then case when o.exception_required then 'development_review'else 'approval'end when o.state='development_review'then 'approval'else 'approved'end;
elsif auth.uid()=r.recruiter_id and private.recruitment_permission('recruitment.manage')then
if p_action='sent'and o.state='approved'then
if(select count(*)from private.recruitment_applications x where x.request_id=r.id and x.stage in('accepted','hired'))+(select count(*)from private.recruitment_offers x join private.recruitment_applications z on z.id=x.application_id where z.request_id=r.id and x.state='sent'and x.expires_on>=current_date)>=r.headcount then raise exception 'العروض السارية والقبول استوفت العدد المعتمد';end if;n:='sent';
elsif p_action='extend'and o.state='sent'then if(select count(*)from private.recruitment_applications x where x.request_id=r.id and x.stage in('accepted','hired'))+(select count(*)from private.recruitment_offers x join private.recruitment_applications z on z.id=x.application_id where z.request_id=r.id and x.id<>o.id and x.state='sent'and x.expires_on>=current_date)>=r.headcount then raise exception 'العروض السارية استوفت العدد؛ لا يمكن إحياء عرض منتهي';end if;update private.recruitment_offers set expires_on=greatest(expires_on,current_date)+7 where id=o.id;perform private.recruitment_event(r.id,a.id,'offer_extended',p_note);return;
elsif p_action in('accepted','declined','expired')and o.state='sent'then
if p_action='accepted'and o.expires_on<current_date then raise exception 'انتهت صلاحية العرض';end if;
if p_action='expired'and o.expires_on>=current_date then raise exception 'العرض لم تنته صلاحيته';end if;
if p_action='accepted'and a.internal_employee_id is not null then raise exception 'الترشيح الداخلي يعتمد من مسار النقل';end if;
if p_action='accepted'and(select count(*)from private.recruitment_applications where request_id=r.id and stage in('accepted','hired'))>=r.headcount then raise exception 'اكتمل العدد المطلوب';end if;n:=p_action;
else raise exception 'الإجراء غير متاح';end if;
else raise exception 'الإجراء لدى مسؤول المرحلة'using errcode='42501';end if;
update private.recruitment_offers set state=n,stage_started_at=now(),sent_at=case when n='sent'then now()else sent_at end,expires_on=case when n='sent'then (now()at time zone 'Asia/Riyadh')::date+7 else expires_on end where id=o.id;
if n='accepted'then update private.recruitment_applications set stage='accepted',revision=revision+1 where id=a.id;end if;
if n in('declined','expired','returned')then update private.recruitment_applications set stage='recommended',revision=revision+1 where id=a.id;end if;
if n in('declined','expired')then insert into public.notifications(recipient_id,type,title,message)values(r.recruiter_id,'RECRUITMENT','مراجعة المرشحين الاحتياطيين','راجع المرشحين المناسبين السابقين وأكد رغبتهم قبل توفير مرشحين جدد؛ لا تعاد الدفعات.');end if;
perform private.recruitment_event(r.id,a.id,'offer_'||n,p_note);end$function$
;
CREATE OR REPLACE FUNCTION private.recruitment_offer_clock()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$declare a private.recruitment_applications;r private.recruitment_requests;owner uuid;begin
if tg_op='INSERT'or new.state is distinct from old.state then select * into a from private.recruitment_applications where id=new.application_id;select * into r from private.recruitment_requests where id=a.request_id;update private.recruitment_tasks set done=true where key in('offer:'||new.id,'prepare:'||a.id);
owner:=case new.state when 'hr_review'then r.hr_id when 'development_review'then r.development_id when 'approval'then r.approver_id when 'returned'then r.recruiter_id when 'approved'then r.recruiter_id end;
if owner is not null then perform private.recruitment_task('offer:'||new.id,r.id,a.id,owner,'متابعة العرض الوظيفي',2);if owner is distinct from auth.uid()then insert into public.notifications(recipient_id,type,title,message)values(owner,'RECRUITMENT','عرض وظيفي بانتظار إجرائك','افتح وحدة التوظيف لمراجعة العرض أو استكماله.');end if;end if;end if;return new;end$function$
;
CREATE OR REPLACE FUNCTION public.recruitment_offer_create(p_application uuid, p_data jsonb)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'private'
AS $function$select private.recruitment_offer_create(p_application,p_data)$function$
;
CREATE OR REPLACE FUNCTION private.recruitment_offer_create(p_application uuid, p_data jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$declare a private.recruitment_applications;r private.recruitment_requests;c private.recruitment_candidates;s jsonb;amount numeric;vmin numeric;vmax numeric;oid uuid;benefits text;exception boolean;begin
select * into strict a from private.recruitment_applications where id=p_application for update;select * into strict r from private.recruitment_requests where id=a.request_id for update;
if not private.recruitment_visible(r.id)or auth.uid()<>r.recruiter_id or not private.recruitment_permission('recruitment.manage')then raise exception 'إعداد العرض لمسؤول التوظيف المحدد'using errcode='42501';end if;
if r.status<>'open'or a.stage not in('recommended','offer')or not a.selection_approved then raise exception 'اعتمد اختيار المرشح أولًا';end if;
if exists(select 1 from private.recruitment_offers where application_id=a.id and state in('sent','accepted'))then raise exception 'سجل رد المرشح أولًا';end if;
if exists(select 1 from private.recruitment_offers where application_id=a.id)and length(btrim(coalesce(p_data->>'change_reason','')))<5 then raise exception 'وثق مبرر تعديل العرض';end if;
select * into strict c from private.recruitment_candidates where id=a.candidate_id;s:=r.salary_snapshot;vmin:=(s->>case when c.saudi then 'saudi_min'else 'expat_min'end)::numeric;vmax:=(s->>case when c.saudi then 'saudi_max'else 'expat_max'end)::numeric;
if vmin is null or vmax is null then raise exception 'لا يوجد نطاق معتمد لهذه الفئة';end if;
amount:=(p_data->>'basic')::numeric+(p_data->>'housing')::numeric+(p_data->>'transport')::numeric;
benefits:=coalesce(s->'benefits'->>'text','');if benefits=''then raise exception 'يجب ربط مزايا الدرجة المعتمدة قبل إعداد العرض';end if;
exception:=amount<vmin or amount>vmax or coalesce(p_data->>'benefits',benefits)<>benefits;
if exception and length(btrim(coalesce(p_data->>'exception_reason','')))<5 then raise exception 'وثق مبرر استثناء الراتب أو المزايا';end if;
if(p_data->>'start_date')::date<current_date then raise exception 'تاريخ المباشرة غير صحيح';end if;
update private.recruitment_offers set state='superseded'where application_id=a.id and state not in('superseded','declined','expired');
insert into private.recruitment_offers(application_id,version,basic,housing,transport,start_date,expires_on,benefits,salary_snapshot,exception_reason,exception_required,created_by)values(a.id,(select coalesce(max(version),0)+1 from private.recruitment_offers where application_id=a.id),(p_data->>'basic')::numeric,(p_data->>'housing')::numeric,(p_data->>'transport')::numeric,(p_data->>'start_date')::date,current_date+7,coalesce(p_data->>'benefits',benefits),s,coalesce(p_data->>'exception_reason',''),exception,auth.uid())returning id into oid;
update private.recruitment_applications set stage='offer',revision=revision+1,updated_at=now()where id=a.id;perform private.recruitment_event(r.id,a.id,'offer_created',coalesce(p_data->>'change_reason','إعداد أول عرض'));return oid;end$function$
;
CREATE OR REPLACE FUNCTION private.recruitment_owner(r private.recruitment_requests)
 RETURNS uuid
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$select case r.status when 'department_review'then r.department_approver_id when 'hr_review'then r.hr_id when 'finance_review'then r.finance_id when 'approval'then r.approver_id when 'hr_exception'then r.development_id when 'finance_exception'then r.approver_id when 'cancellation_approval'then r.approver_id else r.recruiter_id end$function$
;
CREATE OR REPLACE FUNCTION private.recruitment_permission(p_key text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$
 select private.module_allowed('recruitment')and exists(select 1 from public.profiles where id=auth.uid()and(role='admin'or p_key=any(permissions)))
$function$
;
CREATE OR REPLACE FUNCTION public.recruitment_portal(p_token uuid, p_action text, p_data jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'private'
AS $function$select private.recruitment_portal(p_token,p_action,p_data)$function$
;
CREATE OR REPLACE FUNCTION private.recruitment_portal(p_token uuid, p_action text, p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$declare l private.recruitment_portal_links;a private.recruitment_applications;r private.recruitment_requests;token uuid;begin
select * into strict l from private.recruitment_portal_links where id=p_token and not revoked and expires_at>now();select * into strict a from private.recruitment_applications where id=l.application_id;select * into strict r from private.recruitment_requests where id=a.request_id and(status='open'or(status in('closed','cancelled')and a.stage='hired'and a.documents_exception_due is not null));
if length(coalesce(p_data::text,''))>20000 then raise exception 'البيانات تتجاوز الحد';end if;
if p_action='info'then return jsonb_build_object('title',r.job_snapshot->>'title','expires_at',l.expires_at);
elsif p_action='update'then
if coalesce(p_data->>'phone','')!~'^\+?[0-9 ()-]{8,20}$'or length(coalesce(p_data->>'resume_text',''))not between 10 and 10000 then raise exception 'تحقق من الجوال وملخص الخبرة';end if;
if(select count(*)from private.recruitment_candidate_updates where application_id=a.id and state='pending')>=5 then raise exception 'توجد تغييرات قيد المراجعة';end if;
insert into private.recruitment_candidate_updates(application_id,data)values(a.id,jsonb_build_object('phone',p_data->>'phone','city',left(p_data->>'city',100),'experience',left(p_data->>'experience',3000),'resume_text',p_data->>'resume_text'));
insert into public.notifications(recipient_id,type,title,message)values(r.recruiter_id,'RECRUITMENT','تحديث بيانات مرشح','توجد تغييرات من المرشح تنتظر مراجعتك واعتمادك.');
elsif p_action='document'then
if(select count(*)from private.recruitment_documents where application_id=a.id and created_at>now()-interval '1 day')>=30 then raise exception 'تم تجاوز عدد المرفقات';end if;
insert into private.recruitment_documents(candidate_id,application_id,kind)values(a.candidate_id,a.id,p_data->>'kind')returning file_token into token;
insert into public.notifications(recipient_id,type,title,message)values(r.recruiter_id,'RECRUITMENT','مستند مرشح للمراجعة','بدأ المرشح إضافة مستند جديد. راجع الملف بعد اكتمال الرفع.');return jsonb_build_object('file_token',token);
else raise exception 'إجراء غير متاح';end if;return jsonb_build_object('received',true);end$function$
;
CREATE OR REPLACE FUNCTION public.recruitment_public_apply(p_token uuid, p_data jsonb)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'private'
AS $function$select private.recruitment_public_apply(p_token,p_data)$function$
;
CREATE OR REPLACE FUNCTION private.recruitment_public_apply(p_token uuid, p_data jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$
declare r private.recruitment_requests%rowtype;cid uuid;aid uuid;ticket uuid;vemail text:=lower(btrim(p_data->>'email'));begin
 select * into strict r from private.recruitment_requests where public_token=p_token and status='open'and published and route='advertised'for update;
 if coalesce(p_data->>'consent','false')<>'true'or coalesce(vemail,'')!~'^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'or coalesce(p_data->>'phone','')!~'^\+?[0-9 ()-]{8,20}$'or coalesce(length(p_data->>'resume_text'),0)not between 30 and 10000 or length(p_data::text)>20000 then raise exception 'تحقق من البيانات والموافقة وملخص السيرة الذاتية';end if;
 if(select count(*)from private.recruitment_applications where request_id=r.id and created_at>now()-interval '1 day')>=300 then raise exception 'تعذر استقبال الطلب الآن، حاول لاحقًا';end if;
 insert into private.recruitment_candidates(full_name,email,phone,city,saudi,experience,resume_text)values(btrim(p_data->>'full_name'),vemail,p_data->>'phone',left(coalesce(p_data->>'city',''),100),(p_data->>'saudi')::boolean,left(coalesce(p_data->>'experience',''),3000),p_data->>'resume_text')on conflict(lower(email))do nothing returning id into cid;
 if cid is null then select id into cid from private.recruitment_candidates where lower(email)=vemail;end if;
 insert into private.recruitment_applications(request_id,candidate_id,source)values(r.id,cid,'صفحة التقديم')on conflict(request_id,candidate_id)do nothing returning id,resume_token into aid,ticket;
 if aid is not null then perform private.recruitment_event(r.id,aid,'public_application','طلب تقديم من صفحة الوظائف');end if;
 return coalesce(ticket,gen_random_uuid());end$function$
;
CREATE OR REPLACE FUNCTION public.recruitment_public_jobs(p_token uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'private'
AS $function$select private.recruitment_public_jobs(p_token)$function$
;
CREATE OR REPLACE FUNCTION private.recruitment_public_jobs(p_token uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$
 select coalesce(jsonb_agg(jsonb_build_object('token',r.public_token,'title',r.job_snapshot->>'title','company',r.company,'location',r.location,'advertisement',r.advertisement,'requirements',r.job_snapshot->'content'->'qualifications')order by r.created_at desc),'[]')from private.recruitment_requests r where r.status='open'and r.published and r.route='advertised'and(p_token is null or r.public_token=p_token)
$function$
;
CREATE OR REPLACE FUNCTION private.recruitment_reminders()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$declare t private.recruitment_tasks;recipient uuid;begin
for t in select * from private.recruitment_tasks where not done and due_at<now()for update skip locked loop
if not t.notified then insert into public.notifications(recipient_id,type,title,message)values(t.owner_id,'RECRUITMENT','تأخر إجراء توظيف',t.label||'؛ يرجى إنجاز الإجراء من وحدة التوظيف.');update private.recruitment_tasks set notified=true where key=t.key;end if;
if not t.escalated and private.recruitment_work_due(t.due_at,1)<now()then select recruiter_id into recipient from private.recruitment_requests where id=t.request_id;insert into public.notifications(recipient_id,type,title,message)values(recipient,'RECRUITMENT','متابعة تأخر التوظيف',t.label||'؛ استمر التأخير يوم عمل إضافيًا ويحتاج متابعتك.');update private.recruitment_tasks set escalated=true where key=t.key;end if;end loop;end$function$
;
CREATE OR REPLACE FUNCTION public.recruitment_request_action(p_id uuid, p_revision integer, p_action text, p_data jsonb)
 RETURNS void
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'private'
AS $function$select private.recruitment_request_action(p_id,p_revision,p_action,p_data)$function$
;
CREATE OR REPLACE FUNCTION private.recruitment_request_action(p_id uuid, p_revision integer, p_action text, p_data jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$declare r private.recruitment_requests;s private.recruitment_salary_reference;n text;note text:=btrim(coalesce(p_data->>'note',''));begin
if not private.recruitment_visible(p_id)then raise exception 'السجل غير متاح'using errcode='42501';end if;select * into strict r from private.recruitment_requests where id=p_id for update;if r.revision<>p_revision then raise exception 'تم تحديث الطلب؛ أعد التحميل'using errcode='PT409';end if;
if p_action='link_salary'and r.status in('draft','rejected')and auth.uid()in(r.created_by,r.recruiter_id,r.hr_id)then
select * into strict s from private.recruitment_salary_reference where id=(p_data->>'salary_id')::uuid;if length(note)<3 then raise exception 'وثق المطابقة';end if;update private.recruitment_requests set salary_id=s.id,salary_snapshot=to_jsonb(s) where id=r.id;
elsif p_action='submit'and r.status in('draft','rejected')and auth.uid()in(r.created_by,r.supervisor_id)then
if r.target_date<current_date then raise exception 'حدّث تاريخ المباشرة المستهدف';end if;
if r.job_id is null or r.salary_id is null or not exists(select 1 from public.job_descriptions where id=r.job_id and published_snapshot is not null)then raise exception 'اعتمد الوصف والدرجة ونطاق الراتب قبل بدء الموافقات';end if;
update private.recruitment_requests set status='department_review',rejected_stage=null,checks='{}'where id=r.id;
elsif p_action='edit'and r.status in('draft','rejected')and auth.uid()in(r.created_by,r.supervisor_id)then
if length(note)<3 then raise exception 'وثق سبب التعديل';end if;
update private.recruitment_requests set versions=versions||jsonb_build_array(to_jsonb(r)-'versions'),reason=coalesce(nullif(p_data->>'reason',''),reason),headcount=coalesce(nullif(p_data->>'headcount','')::int,headcount),target_date=coalesce(nullif(p_data->>'target_date','')::date,target_date),job_id=coalesce(nullif(p_data->>'job_id','')::uuid,job_id),status='draft',checks='{}',rejected_stage=null where id=r.id;
if nullif(p_data->>'job_id','')is not null then select * into s from private.recruitment_salary_reference where title=(select published_snapshot->>'title'from public.job_descriptions where id=(p_data->>'job_id')::uuid);update private.recruitment_requests set job_snapshot=(select published_snapshot from public.job_descriptions where id=(p_data->>'job_id')::uuid),salary_id=s.id,salary_snapshot=to_jsonb(s)where id=r.id;end if;
elsif p_action='exception'and r.status='rejected'and r.rejected_stage in('hr_review','finance_review')and auth.uid()in(r.created_by,r.supervisor_id)then
if length(note)<5 then raise exception 'مبرر طلب الاستثناء مطلوب';end if;update private.recruitment_requests set status=case r.rejected_stage when 'hr_review'then 'hr_exception'else 'finance_exception'end where id=r.id;
elsif p_action in('approve','reject')and r.status in('department_review','hr_review','finance_review','approval','hr_exception','finance_exception','cancellation_approval')then
if auth.uid()is distinct from private.recruitment_owner(r)then raise exception 'الإجراء لدى مسؤول المرحلة'using errcode='42501';end if;
if(r.status='hr_review'and not private.recruitment_permission('recruitment.personnel'))or(r.status='finance_review'and not private.recruitment_permission('recruitment.finance'))or(r.status='hr_exception'and not private.recruitment_permission('recruitment.development'))or(r.status in('approval','finance_exception','cancellation_approval')and not private.recruitment_permission('recruitment.approve'))then raise exception 'لا تملك صلاحية المرحلة'using errcode='42501';end if;
if length(note)<3 then raise exception 'وثق القرار';end if;
if r.status='cancellation_approval'then n:=case p_action when 'approve'then 'cancelled'else r.cancel_previous_state end;
elsif p_action='reject'then n:='rejected';
else
if r.status='hr_review'and(p_data->>'request_type_checked'is distinct from 'true'or p_data->>'saudization_checked'is distinct from 'true'or p_data->>'profession_checked'is distinct from 'true')then raise exception 'أكد نوع الطلب وخطة التوطين وأهلية المهنة';end if;
n:=case r.status when 'department_review'then 'hr_review'when 'hr_review'then 'finance_review'when 'hr_exception'then 'finance_review'when 'finance_review'then 'approval'when 'approval'then 'open'when 'finance_exception'then 'open'end;end if;
update private.recruitment_requests set status=n,rejected_stage=case when n='rejected'then r.status else rejected_stage end,checks=case when r.status='hr_review'and p_action='approve'then p_data else checks end,published=false where id=r.id;
if n='open'and r.route='referral'then perform private.recruitment_task('referral:'||a0.id,r.id,a0.id,r.supervisor_id,'مراجعة مرشح الإدارة والمقابلة والقرار',3)from private.recruitment_applications a0 where a0.request_id=r.id and a0.stage='screening';end if;
if n='open'and r.route='advertised'and not exists(select 1 from private.recruitment_batches where request_id=r.id)then insert into private.recruitment_batches(request_id,number,quota)values(r.id,1,10);perform private.recruitment_task('batch:'||r.id,r.id,null,r.recruiter_id,'توفير الدفعة الأولى: ١٠ مرشحين',r.sourcing_days);end if;
elsif p_action in('publish','unpublish')and r.status='open'and auth.uid()=r.recruiter_id and private.recruitment_permission('recruitment.manage')then
if r.route<>'advertised'then raise exception 'مرشح الإدارة لا يحتاج إعلانًا';end if;if p_action='publish'and length(btrim(coalesce(p_data->>'advertisement','')))<20 then raise exception 'أكمل الإعلان';end if;update private.recruitment_requests set published=p_action='publish',advertisement=coalesce(p_data->>'advertisement',advertisement)where id=r.id;
elsif p_action='cancel'and r.status not in('closed','cancelled','cancellation_approval')and auth.uid()=r.department_approver_id then
if length(note)<3 then raise exception 'مبرر الإلغاء مطلوب';end if;
update private.recruitment_requests set cancel_previous_state=r.status,status=case when exists(select 1 from private.recruitment_applications where request_id=r.id and stage in('accepted','hired'))then 'cancellation_approval'else 'cancelled'end,published=false where id=r.id;
elsif p_action='sourcing_days'and r.status='open'and auth.uid()=r.recruiter_id and private.recruitment_permission('recruitment.manage')then
if length(note)<5 then raise exception 'وثق مبرر الوظيفة التخصصية أو القيادية';end if;update private.recruitment_requests set sourcing_days=15 where id=r.id;update private.recruitment_tasks set due_at=private.recruitment_work_due(started_at,15)where key='batch:'||r.id and not done;insert into public.notifications(recipient_id,type,title,message)values(r.created_by,'RECRUITMENT','مدة توفير المرشحين','تم تحديد ١٥ يوم عمل للوظيفة التخصصية أو القيادية: '||note);
else raise exception 'الإجراء غير متاح'using errcode='42501';end if;
update private.recruitment_requests set revision=revision+1,updated_at=now()where id=r.id;perform private.recruitment_event(r.id,null,'request_'||p_action,note);end$function$
;
CREATE OR REPLACE FUNCTION private.recruitment_request_clock()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$begin
if tg_op='INSERT'or new.status is distinct from old.status then
new.stage_started_at:=now();update private.recruitment_tasks set done=true where request_id=new.id and key='request:'||new.id;
if new.status in('department_review','hr_review','finance_review','approval','hr_exception','finance_exception','cancellation_approval')then perform private.recruitment_task('request:'||new.id,new.id,null,private.recruitment_owner(new),'مراجعة طلب الاحتياج',2);end if;
if new.status in('closed','cancelled')then update private.recruitment_tasks set done=true where request_id=new.id and key not like 'documents:%';end if;
end if;return new;end$function$
;
CREATE OR REPLACE FUNCTION public.recruitment_request_create(p_data jsonb)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'private'
AS $function$select private.recruitment_request_create(p_data)$function$
;
CREATE OR REPLACE FUNCTION private.recruitment_request_create(p_data jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$declare rid uuid;j jsonb;s private.recruitment_salary_reference;v record;begin
perform private.require_module('recruitment');if nullif(p_data->>'linked_request_id','')is not null and not private.recruitment_visible((p_data->>'linked_request_id')::uuid)then raise exception 'الطلب السابق غير متاح';end if;if not(private.recruitment_permission('recruitment.manage')or private.current_user_role()='manager')then raise exception 'إنشاء الطلب للمشرف أو مسؤول التوظيف'using errcode='42501';end if;
for v in select * from(values('hr_id','recruitment.personnel'),('recruiter_id','recruitment.manage'),('finance_id','recruitment.finance'),('approver_id','recruitment.approve'),('development_id','recruitment.development'),('department_approver_id',null),('supervisor_id',null))x(field,permission)loop
if not exists(select 1 from public.profiles where id=nullif(p_data->>v.field,'')::uuid and active and status='active'and(role='admin'or('recruitment'=any(allowed_modules)and(v.permission is null or v.permission=any(permissions)))))then raise exception 'حدد مسؤولًا مخولًا لكل مرحلة: %',v.field;end if;end loop;
if not exists(select 1 from private.hr_sections where id=(p_data->>'section_id')::uuid and department_id=(p_data->>'department_id')::uuid)then raise exception 'القسم لا يتبع الإدارة';end if;
if nullif(p_data->>'job_id','')is not null then select published_snapshot into strict j from public.job_descriptions where id=(p_data->>'job_id')::uuid;select * into s from private.recruitment_salary_reference where title=j->>'title';end if;
if nullif(p_data->>'salary_id','')is not null and private.recruitment_permission('recruitment.manage')then select * into strict s from private.recruitment_salary_reference where id=(p_data->>'salary_id')::uuid;end if;
if jsonb_typeof(p_data->'criteria')is distinct from 'array'or jsonb_array_length(p_data->'criteria')not between 1 and 20 or(select sum((x->>'weight')::numeric)<>100 or count(distinct x->>'key')<>count(*)or bool_or(coalesce((x->>'weight')::numeric,0)<=0 or length(coalesce(x->>'label',''))<2)from jsonb_array_elements(p_data->'criteria')x)then raise exception 'معايير التقييم وأوزانها غير صحيحة';end if;
if length(btrim(coalesce(p_data->>'reason','')))<3 or length(btrim(coalesce(p_data->>'company','')))<2 or length(btrim(coalesce(p_data->>'location','')))<2 then raise exception 'أكمل بيانات الطلب';end if;
if exists(select 1 from jsonb_array_elements_text(coalesce(p_data->'interviewer_ids','[]'))x where not exists(select 1 from public.profiles where id=x.value::uuid and active and status='active'and(role='admin'or'recruitment'=any(allowed_modules))))then raise exception 'المشاركون يجب أن يكونوا مخولين';end if;
insert into private.recruitment_requests(created_by,job_id,job_snapshot,salary_id,salary_snapshot,department_id,section_id,manager_id,company,location,headcount,reason,route,target_date,hr_id,finance_id,approver_id,interviewer_ids,criteria,department_approver_id,supervisor_id,recruiter_id,development_id,request_type,linked_request_id)
values(auth.uid(),nullif(p_data->>'job_id','')::uuid,coalesce(j,jsonb_build_object('title',coalesce(nullif(p_data->>'draft_title',''),'وظيفة قيد الإعداد'))),s.id,to_jsonb(s),(p_data->>'department_id')::uuid,(p_data->>'section_id')::uuid,nullif(p_data->>'manager_id','')::uuid,p_data->>'company',p_data->>'location',(p_data->>'headcount')::int,p_data->>'reason',p_data->>'route',(p_data->>'target_date')::date,(p_data->>'hr_id')::uuid,(p_data->>'finance_id')::uuid,(p_data->>'approver_id')::uuid,array(select value::uuid from jsonb_array_elements_text(coalesce(p_data->'interviewer_ids','[]'))),p_data->'criteria',(p_data->>'department_approver_id')::uuid,(p_data->>'supervisor_id')::uuid,(p_data->>'recruiter_id')::uuid,(p_data->>'development_id')::uuid,p_data->>'request_type',nullif(p_data->>'linked_request_id','')::uuid)returning id into rid;
perform private.recruitment_event(rid,null,'request_created','حفظ مسودة احتياج');return rid;end$function$
;
CREATE OR REPLACE FUNCTION public.recruitment_resume_allowed(p_name text, p_write boolean)
 RETURNS boolean
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'private'
AS $function$select private.recruitment_resume_allowed(p_name,p_write)$function$
;
CREATE OR REPLACE FUNCTION private.recruitment_resume_allowed(p_name text, p_write boolean)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$
declare a private.recruitment_applications%rowtype;r private.recruitment_requests%rowtype;begin
 if p_name!~'^[0-9a-f-]{36}/resume.pdf$'then return false;end if;
 select * into a from private.recruitment_applications where resume_token=split_part(p_name,'/',1)::uuid;if not found then return false;end if;
 select * into strict r from private.recruitment_requests where id=a.request_id;
 if p_write and a.created_at>now()-interval '1 hour'and r.published and r.status='open'and r.route='advertised'then return true;end if;
 if auth.uid()is null then return false;end if;
 return private.recruitment_visible(r.id)and(not p_write or(private.recruitment_permission('recruitment.manage')or r.created_by=auth.uid()));end$function$
;
CREATE OR REPLACE FUNCTION public.recruitment_stage(p_application uuid, p_revision integer, p_stage text, p_note text)
 RETURNS void
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'private'
AS $function$select private.recruitment_stage(p_application,p_revision,p_stage,p_note)$function$
;
CREATE OR REPLACE FUNCTION private.recruitment_stage(p_application uuid, p_revision integer, p_stage text, p_note text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$declare a private.recruitment_applications;r private.recruitment_requests;begin
select * into strict a from private.recruitment_applications where id=p_application for update;select * into strict r from private.recruitment_requests where id=a.request_id;
if not private.recruitment_visible(r.id)or auth.uid()not in(r.recruiter_id,r.department_approver_id)then raise exception 'غير مخول بالقرار'using errcode='42501';end if;
if r.status<>'open'or a.stage in('hired','rejected','withdrawn','no_show')or a.revision<>p_revision then raise exception 'الطلب مغلق أو تم تحديثه';end if;
if length(btrim(coalesce(p_note,'')))<3 then raise exception 'سبب القرار مطلوب';end if;
if p_stage='rejected'and auth.uid()<>r.department_approver_id then raise exception 'رفض المرشح لمدير الإدارة مع توثيق السبب';end if;
if p_stage='recommended'and r.route='advertised'and a.batch_number is null then raise exception 'يلزم تقديم المرشح ضمن دفعة معتمدة قبل الاختيار';end if;
if p_stage='recommended'and auth.uid()<>r.department_approver_id then raise exception 'اعتماد اختيار المرشح لمدير الإدارة';end if;
if p_stage not in('rejected','withdrawn','no_show')and not((a.stage='screening'and p_stage='interview')or(a.stage='interview'and p_stage='assessment')or(a.stage='assessment'and p_stage='recommended'))then raise exception 'انتقال غير مسموح';end if;
if p_stage='no_show'and a.stage<>'accepted'then raise exception 'عدم المباشرة بعد القبول فقط';end if;
if p_stage in('assessment','recommended')and not exists(select 1 from private.recruitment_interviews where application_id=a.id and interviewer_id=r.supervisor_id and round=1 and state='completed')then raise exception 'يلزم تقييم المدير المباشر';end if;
if p_stage='recommended'and(a.second_interview_reason is not null and not exists(select 1 from private.recruitment_interviews where application_id=a.id and interviewer_id=r.department_approver_id and round=2 and state='completed'))then raise exception 'أكمل تقييم المقابلة الثانية';end if;
if p_stage='recommended'and exists(select 1 from private.recruitment_interviews where application_id=a.id and state='scheduled')then raise exception 'أكمل المقابلات المجدولة';end if;
update private.recruitment_applications set stage=p_stage,selection_approved=p_stage='recommended',rejection_reason=case when p_stage='rejected'then p_note else rejection_reason end,revision=revision+1,updated_at=now()where id=a.id;
if p_stage in('rejected','withdrawn','no_show')then update private.recruitment_tasks set done=true where application_id=a.id;update private.recruitment_offers set state='superseded'where application_id=a.id and state not in('declined','expired','superseded');end if;
if p_stage='recommended'then perform private.recruitment_task('prepare:'||a.id,r.id,a.id,r.recruiter_id,'إعداد العرض الوظيفي',2);update private.recruitment_tasks set done=true where key in('referral:'||a.id,'batch-review:'||r.id);end if;
perform private.recruitment_event(r.id,a.id,'stage_'||p_stage,p_note);end$function$
;
CREATE OR REPLACE FUNCTION private.recruitment_task(p_key text, p_request uuid, p_app uuid, p_owner uuid, p_label text, p_days integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private'
AS $function$begin insert into private.recruitment_tasks(key,request_id,application_id,owner_id,label,started_at,due_at)values(p_key,p_request,p_app,p_owner,p_label,now(),private.recruitment_work_due(now(),p_days))on conflict(key)do update set owner_id=excluded.owner_id,label=excluded.label,started_at=excluded.started_at,due_at=excluded.due_at,done=false,notified=false,escalated=false;end$function$
;
CREATE OR REPLACE FUNCTION private.recruitment_visible(p_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$
select private.module_allowed('recruitment')and exists(select 1 from private.recruitment_requests r where r.id=p_id and(private.recruitment_permission('recruitment.manage')or auth.uid()in(r.created_by,r.hr_id,r.finance_id,r.approver_id,r.department_approver_id,r.supervisor_id,r.recruiter_id,r.development_id)or auth.uid()=any(r.interviewer_ids)or exists(select 1 from private.recruitment_applications a where a.request_id=r.id and a.internal_manager_id=auth.uid())))$function$
;
CREATE OR REPLACE FUNCTION private.recruitment_work_due(p_start timestamp with time zone, p_days integer)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private'
AS $function$declare d timestamp:=p_start at time zone 'Asia/Riyadh';n int:=0;begin while n<p_days loop d:=d+interval '1 day';if extract(dow from d)not in(5,6)and to_char(d,'MM-DD')not in('02-22','09-23')and not exists(select 1 from private.recruitment_holidays where day=d::date)then n:=n+1;end if;end loop;return d at time zone 'Asia/Riyadh';end$function$
;
