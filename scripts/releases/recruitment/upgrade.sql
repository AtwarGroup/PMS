begin;
-- Recruitment-only upgrade; no production user, request or candidate records are copied.
-- Apply inside the release transaction after a backup and successful dry-run.
-- Central recruitment owners. Apply to staging before publishing its UI.
create table if not exists private.recruitment_route_settings (
  singleton boolean primary key default true check (singleton),
  hr_id uuid references public.profiles(id),
  finance_id uuid references public.profiles(id),
  approver_id uuid references public.profiles(id),
  recruiter_id uuid references public.profiles(id),
  development_id uuid references public.profiles(id),
  revision integer not null default 1,
  updated_by uuid references public.profiles(id),
  updated_at timestamptz not null default now()
);
alter table private.recruitment_route_settings enable row level security;
revoke all on private.recruitment_route_settings from public,anon,authenticated;
insert into private.recruitment_route_settings(singleton) values(true) on conflict do nothing;

create table if not exists private.recruitment_email_outbox(
 id uuid primary key default gen_random_uuid(),offer_id uuid not null references private.recruitment_offers(id),event text not null check(event in('offer','reply')),recipient text not null,portal_token uuid not null,payload jsonb not null,state text not null default 'pending' check(state in('pending','sending','sent','failed')),claimed_at timestamptz,provider_id text,last_error text,created_at timestamptz not null default now(),sent_at timestamptz,unique(offer_id,event));
alter table private.recruitment_email_outbox enable row level security;
revoke all on private.recruitment_email_outbox from public,anon,authenticated;

alter table private.recruitment_requests add column if not exists interview_manager_id uuid references public.profiles(id);
alter table private.recruitment_offers add column if not exists candidate_expected_start_date date;
alter table private.recruitment_offers add column if not exists candidate_responded_at timestamptz;
alter table private.recruitment_offers add column if not exists document_terms jsonb not null default '{}'::jsonb;
alter table private.recruitment_offers add column if not exists coordinated_start_date date;

CREATE OR REPLACE FUNCTION private.recruitment_application_action(p_application uuid, p_action text, p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$declare a private.recruitment_applications;r private.recruitment_requests;target private.recruitment_requests;doc private.recruitment_documents;cid uuid;aid uuid;token uuid;u private.recruitment_candidate_updates;note text:=btrim(coalesce(p_data->>'note',''));begin
select * into strict a from private.recruitment_applications where id=p_application for update;select * into strict r from private.recruitment_requests where id=a.request_id;
if not private.recruitment_visible(r.id)then raise exception 'السجل غير متاح'using errcode='42501';end if;
if p_action='second_interview'and r.status='open'and auth.uid()=r.interview_manager_id and r.interview_manager_id<>r.approver_id and a.stage in('screening','interview','assessment')then
if length(note)<5 then raise exception 'سبب المقابلة الثانية مطلوب';end if;update private.recruitment_applications set second_interview_reason=note where id=a.id;
perform private.recruitment_task('second-interview:'||a.id,r.id,a.id,r.interview_manager_id,'إجراء المقابلة الثانية وتسجيل التقييم',3);
elsif p_action='confirm_join'and auth.uid()=r.supervisor_id and r.status='open'and a.stage='accepted'then
if(p_data->>'join_date')::date>current_date or nullif(p_data->>'join_date','')is null or length(note)<3 then raise exception 'أكد الحضور وتاريخ المباشرة الفعلي';end if;update private.recruitment_applications set joining_confirmed_on=(p_data->>'join_date')::date,joining_confirmed_by=auth.uid()where id=a.id;
elsif p_action='internal_approve'and a.internal_employee_id is not null and auth.uid()=a.internal_manager_id and auth.uid()=(select m.profile_id from private.hr_employees e join private.hr_employees m on m.id=e.manager_id where e.id=a.internal_employee_id) and r.status='open'then update private.recruitment_applications set internal_approved=true where id=a.id;
elsif p_action='internal_final'and a.internal_employee_id is not null and a.internal_approved and a.internal_manager_id=(select m.profile_id from private.hr_employees e join private.hr_employees m on m.id=e.manager_id where e.id=a.internal_employee_id) and a.selection_approved and auth.uid()=r.approver_id and private.recruitment_permission('recruitment.approve')and r.status='open'and a.stage='recommended'then
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
if length(note)<5 or nullif(p_data->>'start_date','')is null or(p_data->>'start_date')::date<current_date or p_data->>'coordinated'is distinct from 'true'then raise exception 'وثق التنسيق مع المدير المباشر والسبب والتاريخ الجديد';end if;update private.recruitment_offers set coordinated_start_date=(p_data->>'start_date')::date where application_id=a.id and state='accepted';
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
p_data:=p_data||jsonb_build_object('current_manager_id',(select m.profile_id from private.hr_employees e join private.hr_employees m on m.id=e.manager_id where e.id=(p_data->>'employee_id')::uuid));
if not exists(select 1 from public.profiles where id=(p_data->>'current_manager_id')::uuid and active and status='active'and(role='admin'or'recruitment'=any(allowed_modules)))then raise exception 'حدد مدير الإدارة الحالية المخول';end if;
update private.recruitment_applications set internal_employee_id=(p_data->>'employee_id')::uuid,internal_manager_id=(p_data->>'current_manager_id')::uuid,internal_approved=false where id=a.id;
else raise exception 'الإجراء غير متاح';end if;
else raise exception 'غير مخول بالإجراء'using errcode='42501';end if;
update private.recruitment_applications set revision=revision+1,updated_at=now()where id=a.id;perform private.recruitment_event(r.id,a.id,p_action,note);return '{}'::jsonb;end$function$
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
update private.recruitment_batches set state='review',submitted_at=now()where request_id=r.id and number=b.number;update private.recruitment_tasks set done=true where key='batch:'||r.id;perform private.recruitment_task('batch-review:'||r.id,r.id,null,r.supervisor_id,'تقييم دفعة المرشحين',3);
elsif p_action='none_selected'and auth.uid()=r.supervisor_id and b.state='review'then
if length(btrim(coalesce(p_data->>'note','')))<5 then raise exception 'وثق سبب عدم الاختيار';end if;
if exists(select 1 from private.recruitment_applications where request_id=r.id and batch_number=b.number and(stage<>'rejected'or rejection_reason is null))then raise exception 'سجل سبب رفض كل مرشح في الدفعة أولًا';end if;
update private.recruitment_batches set state='exhausted',note=p_data->>'note'where request_id=r.id and number=b.number;update private.recruitment_tasks set done=true where key='batch-review:'||r.id;
if b.number<3 then insert into private.recruitment_batches(request_id,number,quota)values(r.id,b.number+1,5);perform private.recruitment_task('batch:'||r.id,r.id,null,r.recruiter_id,'توفير ٥ مرشحين جدد',5);else perform private.recruitment_event(r.id,null,'sourcing_suspended','توقف توفير المرشحين بعد استنفاد الدفعات؛ يظل الطلب مفتوحًا');end if;
elsif p_action='resume'and auth.uid()=r.development_id and private.recruitment_permission('recruitment.development')and b.state='exhausted'and b.number>=3 then
if length(btrim(coalesce(p_data->>'note','')))<5 then raise exception 'وثق مراجعة المتطلبات والراتب والتقييم ومبرر الاستئناف';end if;
insert into private.recruitment_batches(request_id,number,quota,note)values(r.id,b.number+1,(p_data->>'quota')::int,p_data->>'note');perform private.recruitment_task('batch:'||r.id,r.id,null,r.recruiter_id,'دفعة إضافية معتمدة',5);
else raise exception 'الإجراء غير متاح'using errcode='42501';end if;perform private.recruitment_event(r.id,null,'batch_'||p_action,p_data->>'note');end$function$
;
CREATE OR REPLACE FUNCTION private.recruitment_context()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$declare result jsonb;begin result:=private.recruitment_context_v1();return result||jsonb_build_object('replacement_employees',(select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'full_name',e.full_name,'employee_code',e.employee_code) order by e.full_name),'[]'::jsonb) from private.hr_employees e join private.hr_employees m on m.id=e.manager_id where m.profile_id=auth.uid()),'route_admin',private.current_user_role()='admin','requester_org',(select jsonb_build_object('department_id',e.department_id,'department_name',d.name,'section_id',e.section_id,'section_name',s.name) from private.hr_employees e join private.hr_departments d on d.id=e.department_id join private.hr_sections s on s.id=e.section_id and s.department_id=e.department_id where e.profile_id=auth.uid()),'salaries',case when private.recruitment_permission('recruitment.personnel')or private.recruitment_permission('recruitment.development')then(select coalesce(jsonb_agg(to_jsonb(s)order by title),'[]')from private.recruitment_salary_reference s)else result->'salaries'end,'personnel',private.recruitment_permission('recruitment.personnel'),'development',private.recruitment_permission('recruitment.development'),'holidays',(select coalesce(jsonb_agg(to_jsonb(h)order by day),'[]')from private.recruitment_holidays h),'people',(select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'full_name',p.full_name,'manage',p.role='admin'or'recruitment.manage'=any(p.permissions),'personnel',p.role='admin'or'recruitment.personnel'=any(p.permissions),'development',p.role='admin'or'recruitment.development'=any(p.permissions),'finance',p.role='admin'or'recruitment.finance'=any(p.permissions),'approve',p.role='admin'or'recruitment.approve'=any(p.permissions))order by full_name),'[]')from public.profiles p where p.active and p.status='active'and(p.role='admin'or'recruitment'=any(p.allowed_modules))));end$function$
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
 'jobs',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'job_code',job_code,'title',case when title='مساعد أمين المستودع' then 'مساعد أمين مستودع' else title end,'salary_id',(select s.id from private.recruitment_salary_reference s where s.title=private.recruitment_salary_title(job_descriptions.title) or position(job_descriptions.title in s.title)>0 order by (s.title=private.recruitment_salary_title(job_descriptions.title)) desc limit 1),'snapshot',jsonb_build_object('title',case when title='مساعد أمين المستودع' then 'مساعد أمين مستودع' else title end,'purpose',purpose,'content',content,'job_code',job_code)) order by job_code),'[]')from public.job_descriptions where title not in ('نائب مدير المستودع','مدير معرض','مسؤول الشؤون المالية والمصرفية','سائق النقل والتوصيل','مشرف العمليات والتشغيل') ),
 'salaries',case when private.recruitment_permission('recruitment.manage')or private.recruitment_permission('recruitment.finance')or private.recruitment_permission('recruitment.approve')then(select coalesce(jsonb_agg(to_jsonb(s)order by title),'[]')from private.recruitment_salary_reference s)else '[]'::jsonb end,
 'departments',(select coalesce(jsonb_agg(to_jsonb(d)order by name),'[]')from private.hr_departments d),'sections',(select coalesce(jsonb_agg(to_jsonb(s)order by name),'[]')from private.hr_sections s),
 'people',(select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'full_name',p.full_name,'manage',p.role='admin'or'recruitment.manage'=any(p.permissions),'finance',p.role='admin'or'recruitment.finance'=any(p.permissions),'approve',p.role='admin'or'recruitment.approve'=any(p.permissions))order by full_name),'[]')from public.profiles p where p.active and p.status='active'and(p.role='admin'or'recruitment'=any(p.allowed_modules))),
 'managers',(select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'full_name',e.full_name)order by full_name),'[]')from private.hr_employees e));end$function$
;
CREATE OR REPLACE FUNCTION private.recruitment_detail(p_request uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$declare result jsonb;pay boolean;begin result:=private.recruitment_detail_v1(p_request);pay:=coalesce((result->>'can_pay')::boolean,false) or exists(select 1 from private.recruitment_requests where id=p_request and development_id=auth.uid() and private.recruitment_permission('recruitment.development'));return result||jsonb_build_object('request',(select case when pay then to_jsonb(r) else to_jsonb(r)-'salary_snapshot'-'salary_id' end from private.recruitment_requests r where id=p_request),'can_pay',pay,'offers',case when pay then(select coalesce(jsonb_agg(to_jsonb(o)order by o.created_at desc),'[]')from private.recruitment_offers o join private.recruitment_applications a on a.id=o.application_id where a.request_id=p_request)else '[]'::jsonb end,'batches',(select coalesce(jsonb_agg(to_jsonb(b)order by number),'[]')from private.recruitment_batches b where request_id=p_request),'documents',(select coalesce(jsonb_agg(to_jsonb(d)order by d.created_at desc),'[]')from private.recruitment_documents d join private.recruitment_applications a on a.id=d.application_id where a.request_id=p_request),'updates',(select coalesce(jsonb_agg(to_jsonb(u)order by u.created_at desc),'[]')from private.recruitment_candidate_updates u join private.recruitment_applications a on a.id=u.application_id where a.request_id=p_request),'tasks',(select coalesce(jsonb_agg(to_jsonb(t)order by t.due_at),'[]')from private.recruitment_tasks t where request_id=p_request and not done),'previous_interviews',(select coalesce(jsonb_agg(to_jsonb(i)||jsonb_build_object('candidate_id',a.candidate_id)),'[]')from private.recruitment_interviews i join private.recruitment_applications a on a.id=i.application_id where a.request_id<>p_request and exists(select 1 from private.recruitment_applications current_app where current_app.request_id=p_request and current_app.candidate_id=a.candidate_id)));end$function$
;
CREATE OR REPLACE FUNCTION private.recruitment_email_prepare(p_offer uuid, p_event text, p_token uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$
declare o private.recruitment_offers;a private.recruitment_applications;r private.recruitment_requests;c private.recruitment_candidates;link uuid;recipient text;outid uuid;begin
 select * into strict o from private.recruitment_offers where id=p_offer for update;
 select * into strict a from private.recruitment_applications where id=o.application_id;
 select * into strict r from private.recruitment_requests where id=a.request_id;
 select * into strict c from private.recruitment_candidates where id=a.candidate_id;
 if p_event='offer' then
 if auth.uid() is distinct from r.recruiter_id or not private.recruitment_permission('recruitment.manage') or o.state<>'sent' or r.status<>'open' or o.expires_on<(now()at time zone 'Asia/Riyadh')::date then raise exception 'إرسال العرض لمسؤول التوظيف وبعد اعتماده وإتاحته للمرشح' using errcode='42501';end if;
 if exists(select 1 from private.recruitment_offers where application_id=a.id and version>o.version) then raise exception 'لا يرسل عرض قديم';end if;
 if coalesce(o.document_terms->>'issuer','')not in('atwar','tirador')then raise exception 'أكمل جهة العرض وشروطه أولًا';end if;
 recipient:=c.email;
 elsif p_event='reply' then
 if not exists(select 1 from private.recruitment_portal_links where id=p_token and application_id=a.id and not revoked and expires_at>now())or o.state not in('accepted','declined')or o.candidate_responded_at is null then raise exception 'رابط أو إقرار غير متاح'using errcode='42501';end if;
 recipient:=(select email from public.profiles where id=r.recruiter_id);link:=p_token;
 else raise exception 'نوع الرسالة غير متاح';end if;
 select id into outid from private.recruitment_email_outbox where offer_id=o.id and event=p_event;
 if outid is not null then return outid;end if;
 if link is null then insert into private.recruitment_portal_links(application_id)values(a.id)returning id into link;end if;
 insert into private.recruitment_email_outbox(offer_id,event,recipient,portal_token,payload)values(o.id,p_event,recipient,link,jsonb_build_object('candidate',coalesce(o.document_terms->>'candidate_name',c.full_name),'title',coalesce(o.document_terms->>'position',r.job_snapshot->>'title'),'issuer',o.document_terms->>'issuer','version',o.version,'state',o.state,'expected_start_date',o.candidate_expected_start_date))returning id into outid;
 return outid;
end $function$
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
 if coalesce((p_data->>'round')::int,1)=2 and (r.interview_manager_id is null or owner=r.approver_id or owner<>r.interview_manager_id or a.second_interview_reason is null)then raise exception 'المقابلة الثانية بطلب مدير الإدارة وتقييمه';end if;
 if coalesce((p_data->>'round')::int,1)=1 and owner<>r.supervisor_id then raise exception 'المقابلة الأولى للمدير المباشر';end if;
 if owner is distinct from r.supervisor_id and owner is distinct from r.interview_manager_id then raise exception 'التقييم للمدير المباشر، ولمدير الإدارة في المقابلة الثانية فقط';end if;
 if owner=r.interview_manager_id and owner<>r.supervisor_id and a.second_interview_reason is null then raise exception 'يطلب مدير الإدارة المقابلة الثانية مع السبب أولًا';end if;
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
 if p_data->>'state'='completed' and a.stage in('screening','interview') and coalesce((p_data->>'round')::int,1)=1 then
update private.recruitment_tasks set done=true where application_id=a.id and key in('referral:'||a.id,'candidate-stage:'||a.id);
perform private.recruitment_task('candidate-stage:'||a.id,r.id,a.id,r.recruiter_id,'مراجعة اكتمال المقابلة ونقل المرشح إلى التقييم',2);
end if;
if p_data->>'state'='completed' and coalesce((p_data->>'round')::int,1)=2 then update private.recruitment_tasks set done=true where key='second-interview:'||a.id;end if;
if p_data->>'state'='scheduled' then
perform private.recruitment_task('interview:'||iid,r.id,a.id,owner,'إجراء المقابلة المجدولة وتسجيل نتيجتها',3);
else update private.recruitment_tasks set done=true where key='interview:'||iid;end if;
perform private.recruitment_event(r.id,a.id,'interview_'||(p_data->>'state'),p_data->>'notes');return iid;end$function$
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
if p_action='approve' and auth.uid()=o.created_by then raise exception 'اعتماد العرض يتطلب معتمدًا مستقلًا عن مُعدّه' using errcode='42501';end if;
owner:=case o.state when 'hr_review'then r.hr_id when 'development_review'then r.development_id when 'approval'then r.approver_id end;
if p_action in('approve','reject')and auth.uid()=owner and((o.state='hr_review'and private.recruitment_permission('recruitment.manage'))or(o.state='development_review'and private.recruitment_permission('recruitment.development'))or(o.state='approval'and private.recruitment_permission('recruitment.approve')))then
n:=case when p_action='reject'then 'returned'when o.state='hr_review'then case when o.exception_required then 'development_review'else 'approval'end when o.state='development_review'then 'approval'else 'approved'end;
elsif auth.uid()=r.recruiter_id and private.recruitment_permission('recruitment.manage')then
if p_action='sent'and o.state='approved'then
if coalesce(o.document_terms->>'issuer','') not in('atwar','tirador') then raise exception 'هذا العرض سابق للقالب الجديد؛ أنشئ نسخة مكتملة الشروط وارفعها للاعتماد قبل الإرسال';end if;
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

if jsonb_typeof(p_data->'document_terms') is distinct from 'object' then raise exception 'أكمل بيانات جهة العرض وشروطه';end if;
if coalesce(p_data#>>'{document_terms,issuer}','') not in('atwar','tirador') then raise exception 'اختر أطوار أو لوازم الأبواب تيرادور';end if;
if coalesce(p_data#>>'{document_terms,probation_days}','') !~ '^[0-9]{1,3}$' then raise exception 'حدد فترة التجربة بالأيام';end if;
if (p_data#>>'{document_terms,probation_days}')::int not between 0 and 180 then raise exception 'تحقق من فترة التجربة';end if;
if exists(select 1 from unnest(array['annual_leave','contract_duration','tickets','medical']) k where length(btrim(coalesce(p_data->'document_terms'->>k,''))) not between 2 and 120) then raise exception 'أكمل الإجازة ومدة العقد والتذاكر والتأمين';end if;
if nullif(p_data->>'start_date','') is null then raise exception 'حدد تاريخ المباشرة المقترح';end if;
amount:=(p_data->>'basic')::numeric+(p_data->>'housing')::numeric+(p_data->>'transport')::numeric;
benefits:=coalesce(s->'benefits'->>'text','');if benefits=''then raise exception 'يجب ربط مزايا الدرجة المعتمدة قبل إعداد العرض';end if;
exception:=amount<vmin or amount>vmax or coalesce(p_data->>'benefits',benefits)<>benefits;
if exception and length(btrim(coalesce(p_data->>'exception_reason','')))<5 then raise exception 'وثق مبرر استثناء الراتب أو المزايا';end if;
if(p_data->>'start_date')::date<current_date then raise exception 'تاريخ المباشرة غير صحيح';end if;
update private.recruitment_offers set state='superseded'where application_id=a.id and state not in('superseded','declined','expired');
insert into private.recruitment_offers(application_id,version,basic,housing,transport,start_date,expires_on,benefits,salary_snapshot,exception_reason,exception_required,created_by)values(a.id,(select coalesce(max(version),0)+1 from private.recruitment_offers where application_id=a.id),(p_data->>'basic')::numeric,(p_data->>'housing')::numeric,(p_data->>'transport')::numeric,(p_data->>'start_date')::date,current_date+7,coalesce(p_data->>'benefits',benefits),s,coalesce(p_data->>'exception_reason',''),exception,auth.uid())returning id into oid;
update private.recruitment_offers set document_terms=jsonb_build_object('issuer',p_data#>>'{document_terms,issuer}','probation_days',(p_data#>>'{document_terms,probation_days}')::int,'annual_leave',btrim(p_data#>>'{document_terms,annual_leave}'),'contract_duration',btrim(p_data#>>'{document_terms,contract_duration}'),'tickets',btrim(p_data#>>'{document_terms,tickets}'),'medical',btrim(p_data#>>'{document_terms,medical}'),'candidate_name',c.full_name,'identity_no',c.identity_no,'position',r.job_snapshot->>'title','location',r.location,'department',(select name from private.hr_departments where id=r.department_id)) where id=oid;
update private.recruitment_offers set state=case when exception then 'development_review' else 'approval' end,stage_started_at=now() where id=oid;
update private.recruitment_applications set stage='offer',revision=revision+1,updated_at=now()where id=a.id;perform private.recruitment_event(r.id,a.id,'offer_created',coalesce(p_data->>'change_reason','إعداد أول عرض'));return oid;end$function$
;
CREATE OR REPLACE FUNCTION private.recruitment_portal(p_token uuid, p_action text, p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$declare l private.recruitment_portal_links;a private.recruitment_applications;r private.recruitment_requests;token uuid;begin
select * into strict l from private.recruitment_portal_links where id=p_token and not revoked and expires_at>now();if p_action='offer_reply' then perform 1 from private.recruitment_applications where id=l.application_id for update; perform 1 from private.recruitment_requests where id=(select request_id from private.recruitment_applications where id=l.application_id) for update;end if;select * into strict a from private.recruitment_applications where id=l.application_id;select * into strict r from private.recruitment_requests where id=a.request_id and(status='open'or(status='closed'and a.stage='hired'and p_action in('info','offer'))or(status in('closed','cancelled')and a.stage='hired'and a.documents_exception_due is not null));
if length(coalesce(p_data::text,''))>20000 then raise exception 'البيانات تتجاوز الحد';end if;
if p_action='info'then return jsonb_build_object('title',r.job_snapshot->>'title','expires_at',l.expires_at);
elsif p_action='offer' then
return (select jsonb_build_object('offer_id',o.id,'version',o.version,'coordinated_start_date',o.coordinated_start_date,'document_terms',o.document_terms,'created_at',o.created_at,'sent_at',o.sent_at,'department',(select name from private.hr_departments where id=r.department_id),'identity_no',(select identity_no from private.recruitment_candidates where id=a.candidate_id),'company',r.company,'grade',o.salary_snapshot->>'grade','candidate',(select full_name from private.recruitment_candidates where id=a.candidate_id),'title',r.job_snapshot->>'title','location',r.location,'basic',o.basic,'housing',o.housing,'transport',o.transport,'total',o.total,'benefits',o.benefits,'start_date',o.start_date,'expires_on',o.expires_on,'state',o.state,'candidate_expected_start_date',o.candidate_expected_start_date,'candidate_responded_at',o.candidate_responded_at)
from private.recruitment_offers o where o.application_id=a.id and o.state in('sent','accepted','declined') and not exists(select 1 from private.recruitment_offers newer where newer.application_id=a.id and newer.version>o.version) order by o.version desc limit 1);
elsif p_action='offer_reply' then
declare o private.recruitment_offers; decision text:=p_data->>'decision'; expected date;begin
select * into strict o from private.recruitment_offers where id=nullif(p_data->>'offer_id','')::uuid and application_id=a.id for update;
if p_data->>'decision' is null or p_data->>'decision' not in('accepted','declined') or p_data->>'acknowledged' is distinct from 'true' then raise exception 'أكد قراءة العرض واختر الموافقة أو الاعتذار';end if;
if o.state=decision and o.candidate_responded_at is not null and (decision='declined' or o.candidate_expected_start_date=nullif(p_data->>'expected_start_date','')::date) then return jsonb_build_object('received',true,'decision',decision,'expected_start_date',o.candidate_expected_start_date);end if;
if a.internal_employee_id is not null or a.stage<>'offer' then raise exception 'المرشح غير متاح للرد على العرض';end if;
if o.state<>'sent' or o.expires_on<(now() at time zone 'Asia/Riyadh')::date or exists(select 1 from private.recruitment_offers newer where newer.application_id=a.id and newer.version>o.version) then raise exception 'العرض غير متاح للرد';end if;
if decision not in('accepted','declined') then raise exception 'اختر الموافقة أو الاعتذار';end if;
if decision='accepted' then
expected:=nullif(p_data->>'expected_start_date','')::date;
if expected is null or expected<(now() at time zone 'Asia/Riyadh')::date then raise exception 'حدد تاريخ مباشرة متوقعًا صالحًا';end if;
if (select count(*) from private.recruitment_applications x where x.request_id=r.id and x.stage in('accepted','hired'))>=r.headcount then raise exception 'اكتمل العدد المطلوب';end if;
end if;
update private.recruitment_offers set state=decision,candidate_expected_start_date=expected,candidate_responded_at=now(),stage_started_at=now() where id=o.id;
update private.recruitment_applications set stage=case when decision='accepted' then 'accepted' else 'recommended' end,revision=revision+1,updated_at=now() where id=a.id;
insert into public.notifications(recipient_id,type,title,message) values(r.recruiter_id,'RECRUITMENT','رد المرشح على العرض','استلم النظام رد المرشح على العرض في طلب التوظيف REC-'||r.number||'.');
perform private.recruitment_event(r.id,a.id,'offer_'||decision,'رد إلكتروني من المرشح على النسخة '||o.version||case when expected is not null then '؛ المباشرة المتوقعة: '||expected::text else '' end);
return jsonb_build_object('received',true,'decision',decision,'expected_start_date',expected);
end;
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
CREATE OR REPLACE FUNCTION private.recruitment_referral_access(p_path text, p_write boolean)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private'
AS $function$
select auth.uid() is not null and exists(select 1 from private.recruitment_requests r where private.recruitment_visible(r.id) and (not p_write or(auth.uid() in(r.created_by,r.recruiter_id) and r.status in('draft','rejected','open'))) and exists(select 1 from jsonb_array_elements(coalesce(r.job_snapshot->'referral_files','[]')) f where f->>'path'=p_path));$function$
;
CREATE OR REPLACE FUNCTION private.recruitment_referral_prepare(p_request uuid, p_name text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$
declare r private.recruitment_requests; t uuid:=gen_random_uuid(); f jsonb;begin
if not private.recruitment_visible(p_request) then raise exception 'السجل غير متاح';end if;
select * into strict r from private.recruitment_requests where id=p_request for update;
if auth.uid() not in(r.created_by,r.recruiter_id) or r.route<>'referral' or r.status not in('draft','rejected','open') then raise exception 'إرفاق السيرة غير متاح';end if;
f:=jsonb_build_object('name',left(p_name,200),'path',r.id::text||'/'||t::text||'.pdf');
update private.recruitment_requests set job_snapshot=job_snapshot||jsonb_build_object('referral_files',coalesce(job_snapshot->'referral_files','[]'::jsonb)||jsonb_build_array(f)) where id=r.id;
return f;end $function$
;
CREATE OR REPLACE FUNCTION private.recruitment_reminders()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$declare t private.recruitment_tasks;recipient uuid;r private.recruitment_requests;begin
for t in select * from private.recruitment_tasks where not done and due_at<now()for update skip locked loop
if not t.notified then insert into public.notifications(recipient_id,type,title,message)values(t.owner_id,'RECRUITMENT','تأخر إجراء توظيف',t.label||'؛ يرجى إنجاز الإجراء من وحدة التوظيف.');update private.recruitment_tasks set notified=true where key=t.key;end if;
if not t.escalated and private.recruitment_work_due(t.due_at,1)<now()then select * into r from private.recruitment_requests where id=t.request_id;
recipient:=case when t.owner_id is distinct from r.recruiter_id then r.recruiter_id when t.owner_id is distinct from r.development_id then r.development_id else r.approver_id end;
if recipient=t.owner_id or not exists(select 1 from public.profiles p where p.id=recipient and p.active and p.status='active' and (p.role='admin'or'recruitment'=any(p.allowed_modules)))then
select p.id into recipient from public.profiles p where p.role='admin'and p.active and p.status='active'and p.id<>t.owner_id order by p.id limit 1;end if;
if recipient is null or recipient=t.owner_id then continue;end if;insert into public.notifications(recipient_id,type,title,message)values(recipient,'RECRUITMENT','متابعة تأخر التوظيف',t.label||'؛ استمر التأخير يوم عمل إضافيًا ويحتاج متابعتك.');update private.recruitment_tasks set escalated=true where key=t.key;end if;end loop;end$function$
;
CREATE OR REPLACE FUNCTION private.recruitment_request_action(p_id uuid, p_revision integer, p_action text, p_data jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$declare r private.recruitment_requests;s private.recruitment_salary_reference;n text;replacement uuid;field text;permission text;old_owner uuid;note text:=btrim(coalesce(p_data->>'note',''));begin
if not private.recruitment_visible(p_id)then raise exception 'السجل غير متاح'using errcode='42501';end if;select * into strict r from private.recruitment_requests where id=p_id for update;if r.revision<>p_revision then raise exception 'تم تحديث الطلب؛ أعد التحميل'using errcode='PT409';end if;
if p_action='approve' and auth.uid()=r.created_by then raise exception 'لا يجوز اعتماد طلبك الشخصي؛ يلزم معتمد مستقل' using errcode='42501';end if;
if p_action='reassign' then
 if private.current_user_role() is distinct from 'admin' or r.status in('closed','cancelled') then raise exception 'إعادة الإسناد لمسؤول النظام وللطلبات غير المغلقة'using errcode='42501';end if;
 if length(note)<5 then raise exception 'وثق سبب إعادة الإسناد';end if;
 field:=p_data->>'field';replacement:=nullif(p_data->>'profile_id','')::uuid;
 permission:=case field when 'hr_id'then 'recruitment.manage'when 'finance_id'then 'recruitment.finance'when 'approver_id'then 'recruitment.approve'when 'recruiter_id'then 'recruitment.manage'when 'development_id'then 'recruitment.development'when 'department_approver_id'then 'manager'else null end;
 if permission is null then raise exception 'مرحلة الإسناد غير صحيحة';end if;
 if replacement is not distinct from r.created_by and field<>'recruiter_id' then raise exception 'المعتمد البديل يجب أن يكون مستقلًا عن مقدم الطلب';end if;
 if not exists(select 1 from public.profiles p where p.id=replacement and p.active and p.status='active' and (p.role='admin'or('recruitment'=any(p.allowed_modules)and(case when permission='manager'then p.role='manager'else permission=any(p.permissions)end))))then raise exception 'اختر بديلًا نشطًا ومخولًا لهذه المرحلة';end if;
 old_owner:=(to_jsonb(r)->>field)::uuid;
 if old_owner=replacement then raise exception 'المسؤول لم يتغير';end if;
 execute format('update private.recruitment_requests as req set %I=$1,versions=req.versions||jsonb_build_array(to_jsonb(req)-''versions'') where req.id=$2',field)using replacement,r.id;
 select * into strict r from private.recruitment_requests where id=p_id;
 update private.recruitment_requests set interviewer_ids=array(select distinct unnest(array[r.supervisor_id,r.interview_manager_id]))where id=p_id;
 update private.recruitment_tasks t set owner_id=case
  when t.key='request:'||r.id then private.recruitment_owner(r)
  when t.key like 'offer:%'then coalesce((select case o.state when 'hr_review'then r.hr_id when 'development_review'then r.development_id when 'approval'then r.approver_id else r.recruiter_id end from private.recruitment_offers o where t.key='offer:'||o.id),t.owner_id)
  when t.key like 'batch-review:%'then r.supervisor_id
when t.key like 'candidate-stage:%' then case when exists(select 1 from private.recruitment_applications a where a.id=t.application_id and a.stage='assessment') then r.supervisor_id else t.owner_id end
  when t.key like 'referral:%'then r.supervisor_id
  when t.key like 'prepare:%'or t.key like 'batch:%'or t.key like 'documents:%'then r.recruiter_id
  else t.owner_id end,notified=false,escalated=false where t.request_id=r.id and not t.done;
 insert into public.notifications(recipient_id,type,title,message)values(replacement,'RECRUITMENT','إعادة إسناد إجراء توظيف','تم إسناد دور إليك في الطلب REC-'||r.number||'؛ السبب: '||note);
 note:=note||'؛ المرحلة: '||case field when 'hr_id'then 'شؤون الموظفين'when 'finance_id'then 'المراجعة المالية'when 'approver_id'then 'الاعتماد النهائي'when 'recruiter_id'then 'مسؤول التوظيف'when 'development_id'then 'تطوير الأعمال'else 'مدير الإدارة'end||'؛ السابق: '||coalesce((select full_name from public.profiles where id=old_owner),'غير محدد')||'؛ الجديد: '||(select full_name from public.profiles where id=replacement);
elsif p_action='link_salary' and r.status in('draft','rejected')and auth.uid()in(r.created_by,r.recruiter_id,r.hr_id)then
select * into strict s from private.recruitment_salary_reference where id=(p_data->>'salary_id')::uuid;if length(note)<3 then raise exception 'وثق المطابقة';end if;update private.recruitment_requests set salary_id=s.id,salary_snapshot=to_jsonb(s) where id=r.id;
elsif p_action='submit'and r.status in('draft','rejected')and auth.uid()in(r.created_by,r.supervisor_id)then
if r.target_date<current_date then raise exception 'حدّث تاريخ المباشرة المستهدف';end if;
if r.job_id is null or not exists(select 1 from public.job_descriptions where id=r.job_id and title not in('نائب مدير المستودع','مدير معرض','مسؤول الشؤون المالية والمصرفية','سائق النقل والتوصيل','مشرف العمليات والتشغيل')) then raise exception 'اختر وظيفة حالية من قائمة الوظائف';end if;
if r.salary_id is null then
select * into s from private.recruitment_salary_reference where title=private.recruitment_salary_title(r.job_snapshot->>'title') or position(r.job_snapshot->>'title' in title)>0 order by(title=private.recruitment_salary_title(r.job_snapshot->>'title')) desc limit 1;
if s.id is null then raise exception 'اربط الوظيفة بمرجع سلم الرواتب المقترح قبل الإرسال';end if;
update private.recruitment_requests set salary_id=s.id,salary_snapshot=to_jsonb(s) where id=r.id;
end if;
update private.recruitment_requests set status='department_review',rejected_stage=null,checks='{}'where id=r.id;
elsif p_action='edit'and r.status in('draft','rejected')and auth.uid()in(r.created_by,r.supervisor_id)then
if length(note)<3 then raise exception 'وثق سبب التعديل';end if;
update private.recruitment_requests set versions=versions||jsonb_build_array(to_jsonb(r)-'versions'),reason=coalesce(nullif(p_data->>'reason',''),reason),headcount=coalesce(nullif(p_data->>'headcount','')::int,headcount),target_date=coalesce(nullif(p_data->>'target_date','')::date,target_date),job_id=coalesce(nullif(p_data->>'job_id','')::uuid,job_id),status='draft',checks='{}',rejected_stage=null where id=r.id;
if nullif(p_data->>'job_id','')is not null then
if not exists(select 1 from public.job_descriptions where id=(p_data->>'job_id')::uuid and title not in('نائب مدير المستودع','مدير معرض','مسؤول الشؤون المالية والمصرفية','سائق النقل والتوصيل','مشرف العمليات والتشغيل')) then raise exception 'اختر وظيفة حالية من قائمة الوظائف';end if;
select * into s from private.recruitment_salary_reference where title=private.recruitment_salary_title((select title from public.job_descriptions where id=(p_data->>'job_id')::uuid)) or position((select title from public.job_descriptions where id=(p_data->>'job_id')::uuid) in title)>0 order by(title=private.recruitment_salary_title((select title from public.job_descriptions where id=(p_data->>'job_id')::uuid))) desc limit 1;
update private.recruitment_requests set job_snapshot=(select jsonb_build_object('title',case when title='مساعد أمين المستودع' then 'مساعد أمين مستودع' else title end,'purpose',purpose,'content',content,'job_code',job_code) from public.job_descriptions where id=(p_data->>'job_id')::uuid)||(r.job_snapshot-'title'-'purpose'-'content'-'job_code'),salary_id=s.id,salary_snapshot=to_jsonb(s) where id=r.id;
end if;
elsif p_action='exception'and r.status='rejected'and r.rejected_stage in('hr_review','finance_review')and auth.uid()in(r.created_by,r.supervisor_id)then
if length(note)<5 then raise exception 'مبرر طلب الاستثناء مطلوب';end if;update private.recruitment_requests set status=case r.rejected_stage when 'hr_review'then 'hr_exception'else 'finance_exception'end where id=r.id;
elsif p_action in('approve','reject')and r.status in('department_review','hr_review','finance_review','approval','hr_exception','finance_exception','cancellation_approval')then
if auth.uid()is distinct from private.recruitment_owner(r)then raise exception 'الإجراء لدى مسؤول المرحلة'using errcode='42501';end if;
if(r.status='hr_review'and not private.recruitment_permission('recruitment.manage'))or(r.status='finance_review'and not private.recruitment_permission('recruitment.finance'))or(r.status='hr_exception'and not private.recruitment_permission('recruitment.development'))or(r.status in('approval','finance_exception','cancellation_approval')and not private.recruitment_permission('recruitment.approve'))then raise exception 'لا تملك صلاحية المرحلة'using errcode='42501';end if;
if length(note)<3 then raise exception 'وثق القرار';end if;
if r.status='cancellation_approval'then n:=case p_action when 'approve'then 'cancelled'else r.cancel_previous_state end;
elsif p_action='reject'then n:='rejected';
else
if r.status='hr_review'and(p_data->>'request_type_checked'is distinct from 'true'or p_data->>'saudization_checked'is distinct from 'true'or p_data->>'profession_checked'is distinct from 'true')then raise exception 'أكد نوع الطلب وخطة التوطين وأهلية المهنة';end if;
n:=case r.status when 'department_review'then 'hr_review'when 'hr_review'then 'approval'when 'hr_exception'then 'approval'when 'finance_review'then 'approval'when 'approval'then 'open'when 'finance_exception'then 'open'end;end if;
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
CREATE OR REPLACE FUNCTION private.recruitment_request_create(p_data jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$declare rid uuid;replacement jsonb;j jsonb;s private.recruitment_salary_reference;v record;org jsonb;begin
perform private.require_module('recruitment');
-- Canonical jobs only: merged and removed legacy titles cannot create new requests.
if exists(select 1 from public.job_descriptions where id=nullif(p_data->>'job_id','')::uuid and title in('نائب مدير المستودع','مدير معرض','مسؤول الشؤون المالية والمصرفية','سائق النقل والتوصيل','مشرف العمليات والتشغيل')) then
raise exception 'هذا المسمى أُلغي أو دُمج؛ اختر المسمى الحالي من قائمة الوظائف';
end if;if nullif(p_data->>'linked_request_id','')is not null and not private.recruitment_visible((p_data->>'linked_request_id')::uuid)then raise exception 'الطلب السابق غير متاح';end if;if not(private.recruitment_permission('recruitment.manage')or private.current_user_role()='manager')then raise exception 'إنشاء الطلب للمشرف أو مسؤول التوظيف'using errcode='42501';end if;

-- ORG_FROM_REQUESTER: never trust organization IDs supplied by the browser.
if (select count(*) from private.hr_employees where profile_id=auth.uid())<>1 then
  raise exception 'يلزم ربط الحساب بملف موظف واحد قبل إنشاء الطلب' using errcode='42501';
end if;
select jsonb_build_object('department_id',e.department_id,'section_id',e.section_id) into org
from private.hr_employees e join private.hr_sections org_section on org_section.id=e.section_id and org_section.department_id=e.department_id
where e.profile_id=auth.uid();
if org is null then raise exception 'أكمل الإدارة والقسم في ملف الموظف قبل إنشاء الطلب' using errcode='42501'; end if;
p_data := (p_data-'company') || org;
if p_data->>'request_type'='replacement' then
select jsonb_build_object('id',e.id,'full_name',e.full_name,'employee_code',e.employee_code) into replacement
from private.hr_employees e join private.hr_employees m on m.id=e.manager_id
where e.id=nullif(p_data->>'replacement_employee_id','')::uuid and m.profile_id=auth.uid();
if replacement is null then raise exception 'اختر الموظف المراد استبداله من الموظفين التابعين لك' using errcode='42501';end if;
end if;

-- CENTRAL_RECRUITMENT_ROUTE
p_data:=p_data || private.recruitment_resolve_route() || jsonb_build_object('criteria',jsonb_build_array(
 jsonb_build_object('key','experience','label','الخبرة المرتبطة بالوظيفة','weight',30),
 jsonb_build_object('key','technical','label',left(coalesce(nullif((select published_snapshot #>> '{content,qualifications,skills}' from public.job_descriptions where id=nullif(p_data->>'job_id','')::uuid),''),'المهارات الفنية المطلوبة'),250),'weight',40),
 jsonb_build_object('key','communication','label','التواصل والتعاون','weight',20),
 jsonb_build_object('key','readiness','label','الجاهزية لمتطلبات العمل','weight',10)));
for v in select * from(values('hr_id','recruitment.manage'),('recruiter_id','recruitment.manage'),('approver_id','recruitment.approve'),('development_id','recruitment.development'),('department_approver_id',null),('supervisor_id',null))x(field,permission)loop
if not exists(select 1 from public.profiles where id=nullif(p_data->>v.field,'')::uuid and active and status='active'and(role='admin'or('recruitment'=any(allowed_modules)and(v.permission is null or v.permission=any(permissions)))))then raise exception 'حدد مسؤولًا مخولًا لكل مرحلة: %',v.field;end if;end loop;
if not exists(select 1 from private.hr_sections where id=(p_data->>'section_id')::uuid and department_id=(p_data->>'department_id')::uuid)then raise exception 'القسم لا يتبع الإدارة';end if;
if nullif(p_data->>'job_id','')is not null then select jsonb_build_object('title',case when title='مساعد أمين المستودع' then 'مساعد أمين مستودع' else title end,'purpose',purpose,'content',content,'job_code',job_code) into strict j from public.job_descriptions where id=(p_data->>'job_id')::uuid;select * into s from private.recruitment_salary_reference where title=private.recruitment_salary_title(j->>'title') or position(j->>'title' in title)>0 order by (title=private.recruitment_salary_title(j->>'title')) desc limit 1;end if;
if nullif(p_data->>'salary_id','')is not null and private.recruitment_permission('recruitment.manage')then select * into strict s from private.recruitment_salary_reference where id=(p_data->>'salary_id')::uuid;end if;
if jsonb_typeof(p_data->'criteria')is distinct from 'array'or jsonb_array_length(p_data->'criteria')not between 1 and 20 or(select sum((x->>'weight')::numeric)<>100 or count(distinct x->>'key')<>count(*)or bool_or(coalesce((x->>'weight')::numeric,0)<=0 or length(coalesce(x->>'label',''))<2)from jsonb_array_elements(p_data->'criteria')x)then raise exception 'معايير التقييم وأوزانها غير صحيحة';end if;
if length(btrim(coalesce(p_data->>'reason','')))<3 or length(btrim(coalesce(p_data->>'location','')))<2 then raise exception 'أكمل بيانات الطلب';end if;
if exists(select 1 from jsonb_array_elements_text(coalesce(p_data->'interviewer_ids','[]'))x where not exists(select 1 from public.profiles where id=x.value::uuid and active and status='active'and(role='admin'or'recruitment'=any(allowed_modules))))then raise exception 'المشاركون يجب أن يكونوا مخولين';end if;
insert into private.recruitment_requests(created_by,job_id,job_snapshot,salary_id,salary_snapshot,department_id,section_id,manager_id,company,location,headcount,reason,route,target_date,hr_id,finance_id,approver_id,interviewer_ids,criteria,department_approver_id,supervisor_id,recruiter_id,development_id,request_type,linked_request_id)
values(auth.uid(),nullif(p_data->>'job_id','')::uuid,coalesce(j,jsonb_build_object('title',coalesce(nullif(p_data->>'draft_title',''),'وظيفة قيد الإعداد'))),s.id,to_jsonb(s),(p_data->>'department_id')::uuid,(p_data->>'section_id')::uuid,nullif(p_data->>'manager_id','')::uuid,'',p_data->>'location',(p_data->>'headcount')::int,p_data->>'reason',p_data->>'route',(p_data->>'target_date')::date,(p_data->>'hr_id')::uuid,(p_data->>'finance_id')::uuid,(p_data->>'approver_id')::uuid,array(select value::uuid from jsonb_array_elements_text(coalesce(p_data->'interviewer_ids','[]'))),p_data->'criteria',(p_data->>'department_approver_id')::uuid,(p_data->>'supervisor_id')::uuid,(p_data->>'recruiter_id')::uuid,(p_data->>'development_id')::uuid,p_data->>'request_type',nullif(p_data->>'linked_request_id','')::uuid)returning id into rid;
update private.recruitment_requests set job_snapshot=job_snapshot||jsonb_build_object('replacement_employee',replacement,'additional_requirements',left(coalesce(p_data->>'additional_requirements',''),3000),'nationality',left(coalesce(p_data->>'nationality','غير محددة'),100)) where id=rid;
update private.recruitment_requests set interview_manager_id=case when department_approver_id not in(approver_id,supervisor_id) then department_approver_id end,interviewer_ids=array(select x from unnest(array[supervisor_id,case when department_approver_id not in(approver_id,supervisor_id) then department_approver_id end]) x where x is not null) where id=rid;
perform private.recruitment_event(rid,null,'request_created','حفظ مسودة احتياج');return rid;end$function$
;
CREATE OR REPLACE FUNCTION private.recruitment_resolve_route()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$
declare route jsonb; employee private.hr_employees; head uuid; item record;
begin
  perform private.require_module('recruitment');
  if auth.uid() is null then raise exception 'يلزم تسجيل الدخول' using errcode='42501'; end if;
  select * into strict employee from private.hr_employees where profile_id=auth.uid();
  if exists(
    with recursive chain as (
      select e.id,e.manager_id,array[e.id] path,false cycle from private.hr_employees e where e.id=employee.id
      union all select m.id,m.manager_id,c.path||m.id,m.id=any(c.path)
      from chain c join private.hr_employees m on m.id=c.manager_id where not c.cycle
    ) select 1 from chain where cycle
  ) then raise exception 'توجد حلقة في التسلسل الإداري؛ راجع سجل الموظفين'; end if;
  with recursive chain as (
    select e.*,0 depth,array[e.id] path from private.hr_employees e where e.id=employee.id
    union all select m.*,c.depth+1,c.path||m.id from chain c join private.hr_employees m on m.id=c.manager_id
      where not m.id=any(c.path)
  ) select c.profile_id into head from chain c join public.profiles p on p.id=c.profile_id
    where c.profile_id<>auth.uid() and c.department_id=employee.department_id and p.active and p.status='active'
      and p.role in('manager','admin') and (p.role='admin' or 'recruitment'=any(p.allowed_modules))
    order by c.depth desc limit 1;
  if head is null then
    with recursive chain as (
      select e.*,0 depth,array[e.id] path from private.hr_employees e where e.id=employee.id
      union all select m.*,c.depth+1,c.path||m.id from chain c join private.hr_employees m on m.id=c.manager_id where not m.id=any(c.path)
    ) select c.profile_id into head from chain c join public.profiles p on p.id=c.profile_id
      where c.depth>0 and c.profile_id<>auth.uid() and p.active and p.status='active'
        and p.role in('manager','admin') and (p.role='admin' or 'recruitment'=any(p.allowed_modules)) order by c.depth limit 1;
  end if;
  if head is null then select approver_id into head from private.recruitment_route_settings where singleton and approver_id<>auth.uid(); end if;
  if head is null then raise exception 'حدد معتمدًا أعلى مستقلًا عن مقدم الطلب في الهيكل أو إعدادات المسار'; end if;
  select jsonb_build_object('hr_id',s.recruiter_id,'finance_id',coalesce(s.finance_id,s.approver_id),'approver_id',s.approver_id,
    'recruiter_id',s.recruiter_id,'development_id',s.development_id,'department_approver_id',head,
    'supervisor_id',auth.uid(),'manager_id',employee.id) into route
    from private.recruitment_route_settings s where singleton;
  for item in select * from (values('hr_id','recruitment.manage'),('approver_id','recruitment.approve'),('recruiter_id','recruitment.manage'),('development_id','recruitment.development')) t(field,permission) loop
    if not exists(select 1 from public.profiles p where p.id=(route->>item.field)::uuid and p.active and p.status='active' and (p.role='admin' or ('recruitment'=any(p.allowed_modules) and item.permission=any(p.permissions)))) then
      raise exception 'إعدادات مسار التوظيف غير مكتملة أو صلاحية مسؤول المرحلة غير فعالة؛ راجع مسؤول النظام';
    end if;
  end loop;
  return route || jsonb_build_object('interviewer_ids',(select jsonb_agg(x) from (select distinct unnest(array[auth.uid(),head]) x) owners));
exception when no_data_found or too_many_rows then
  raise exception 'يلزم ربط الحساب بملف موظف واحد قبل إنشاء الطلب' using errcode='42501';
end $function$
;
CREATE OR REPLACE FUNCTION private.recruitment_route_settings(p_action text DEFAULT 'get'::text, p_data jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$
declare r private.recruitment_route_settings; item record; owner_id uuid;
begin
  perform private.require_module('recruitment');
  if auth.uid() is null or private.current_user_role() is distinct from 'admin' then
    raise exception 'إعداد مسار التوظيف لمسؤول النظام فقط' using errcode='42501';
  end if;
  select * into strict r from private.recruitment_route_settings where singleton for update;
  if p_action='save' then
    if (p_data->>'revision')::integer is distinct from r.revision then
      raise exception 'تم تحديث إعدادات المسار؛ أعد تحميل الصفحة' using errcode='PT409';
    end if;
    for item in select * from (values('approver_id','recruitment.approve'),('recruiter_id','recruitment.manage'),('development_id','recruitment.development')) t(field,permission) loop
      owner_id:=nullif(p_data->>item.field,'')::uuid;
      if not exists(select 1 from public.profiles p where p.id=owner_id and p.active and p.status='active' and (p.role='admin' or ('recruitment'=any(p.allowed_modules) and item.permission=any(p.permissions)))) then
        raise exception 'اختر مسؤولًا نشطًا ومخولًا لكل مرحلة: %',item.field using errcode='22023';
      end if;
    end loop;
    update private.recruitment_route_settings set hr_id=(p_data->>'recruiter_id')::uuid,finance_id=coalesce(finance_id,(p_data->>'approver_id')::uuid),
      approver_id=(p_data->>'approver_id')::uuid,recruiter_id=(p_data->>'recruiter_id')::uuid,
      development_id=(p_data->>'development_id')::uuid,revision=revision+1,updated_by=auth.uid(),updated_at=now()
      where singleton returning * into r;
  elsif p_action<>'get' then raise exception 'إجراء غير متاح'; end if;
  return to_jsonb(r)-'singleton';
end $function$
;
CREATE OR REPLACE FUNCTION private.recruitment_salary_title(p_title text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$ select case p_title when 'أخصائي التجارة الإلكترونية' then 'أخصائي متجر إلكتروني، مصمم جرافيكس' when 'أخصائي دعم تقنية معلومات' then 'فني تركيبات، أخصائي دعم تقنية المعلومات، منسق خدمات مساندة' when 'أخصائي شؤون موظفين و شؤون قانونية' then 'أخصائي شؤون موظفين وشؤون قانونية' when 'أخصائي مشتريات دولية' then 'أخصائي مشتريات، مشتريات دولية، خدمات مساندة' when 'رئيس الحسابات' then 'رئيس حسابات، مشرف مشتريات ومخزون' when 'سكرتير تنفيذي' then 'سكرتير' when 'عامل تحميل وتنزيل' then 'عامل بوفيه ونظافة، خدمات عامة، تحميل' when 'عامل خدمات عامة' then 'عامل بوفيه ونظافة، خدمات عامة، تحميل' when 'محاسب الفروع والمعارض' then 'محاسب فرع، موردين ومخزون، عملاء وتحصيل، محاسب عام' when 'محاسب الموردين والمخزون' then 'محاسب فرع، موردين ومخزون، عملاء وتحصيل، محاسب عام' when 'محاسب حسابات العملاء والتحصيل' then 'محاسب فرع، موردين ومخزون، عملاء وتحصيل، محاسب عام' when 'محلل نظم ومطور تطبيقات' then 'محلل نظم معلومات ومطور تطبيقات، مبرمج تطبيقات' when 'مدير التسويق الرقمي' then 'مدير التسويق' when 'مدير مبيعات قطاع التجزئة' then 'مدير قطاع التجزئة، مدير قطاع التوزيع، مدير سلسلة الإمداد' when 'مدير مبيعات قطاع الجملة والتوزيع' then 'مدير قطاع التجزئة، مدير قطاع التوزيع، مدير سلسلة الإمداد' when 'مراقب حركة المخزون' then 'مراقب حركة مخزون' when 'مسؤول إدارة الموارد البشرية' then 'أخصائي موارد بشرية، إدارة مواهب، علاقات موظفين' when 'مسؤول الشؤون الإدارية والعلاقات الحكومية' then 'أخصائي الشؤون الإدارية والعلاقات الحكومية' when 'مساعد أمين المستودع' then 'مساعد بائع، مساعد أمين مستودع، مساعد فني تركيبات' when 'مشرف التركيبات والحلول الذكية' then 'مشرف تقنية معلومات؛ تخطيط؛ تسويق؛ تركيبات؛ حركة مخزون؛ مستودع؛ خدمات مساندة؛ حسابات؛ مشتريات' when 'مشرف العمليات والتشغيل' then 'مشرف العمليات اللوجستية والتركيبات، مشرف مستودعات' when 'مشرف المستودعات والتوصيل' then 'مشرف العمليات اللوجستية والتركيبات، مشرف مستودعات' when 'مشرف المشتريات والمخزون' then 'رئيس حسابات، مشرف مشتريات ومخزون' when 'مشرف تخطيط المخزون والطلب' then 'مشرف تقنية معلومات؛ تخطيط؛ تسويق؛ تركيبات؛ حركة مخزون؛ مستودع؛ خدمات مساندة؛ حسابات؛ مشتريات' when 'مشرف تطوير الأعمال' then 'مشرف تطوير أعمال، مساعد مدير المبيعات' when 'مشرف تقنية المعلومات' then 'مشرف تقنية معلومات؛ تخطيط؛ تسويق؛ تركيبات؛ حركة مخزون؛ مستودع؛ خدمات مساندة؛ حسابات؛ مشتريات' when 'منسق إدارة المواهب' then 'منسق موارد بشرية، إدارة مواهب، علاقات موظفين، شؤون إدارية، علاقات حكومية' when 'منسق الخدمات المساندة' then 'فني تركيبات، أخصائي دعم تقنية المعلومات، منسق خدمات مساندة' when 'منسق علاقات موظفين' then 'منسق موارد بشرية، إدارة مواهب، علاقات موظفين، شؤون إدارية، علاقات حكومية' when 'مصمم جرافيك' then 'أخصائي متجر إلكتروني، مصمم جرافيكس' when 'أخصائي موارد بشرية' then 'أخصائي موارد بشرية، إدارة مواهب، علاقات موظفين' else p_title end $function$
;
CREATE OR REPLACE FUNCTION private.recruitment_stage(p_application uuid, p_revision integer, p_stage text, p_note text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$declare a private.recruitment_applications;r private.recruitment_requests;begin
select * into strict a from private.recruitment_applications where id=p_application for update;select * into strict r from private.recruitment_requests where id=a.request_id;
if not private.recruitment_visible(r.id)or auth.uid()not in(r.recruiter_id,r.supervisor_id)then raise exception 'غير مخول بالقرار'using errcode='42501';end if;
if r.status<>'open'or a.stage in('hired','rejected','withdrawn','no_show')or a.revision<>p_revision then raise exception 'الطلب مغلق أو تم تحديثه';end if;
if length(btrim(coalesce(p_note,'')))<3 then raise exception 'سبب القرار مطلوب';end if;
if p_stage='rejected'and auth.uid()<>r.supervisor_id then raise exception 'رفض المرشح للمدير المباشر مع توثيق السبب';end if;
if p_stage='recommended'and r.route='advertised'and a.batch_number is null then raise exception 'يلزم تقديم المرشح ضمن دفعة معتمدة قبل الاختيار';end if;
if p_stage='recommended'and auth.uid()<>r.supervisor_id then raise exception 'اختيار المرشح للمدير المباشر';end if;
if p_stage not in('rejected','withdrawn','no_show')and not((a.stage='screening'and p_stage='interview')or(a.stage='interview'and p_stage='assessment')or(a.stage='assessment'and p_stage='recommended'))then raise exception 'انتقال غير مسموح';end if;
if p_stage in('interview','assessment','withdrawn','no_show') and auth.uid()<>r.recruiter_id then raise exception 'تنسيق مراحل المرشح لمسؤول التوظيف' using errcode='42501';end if;
if p_stage='no_show'and a.stage<>'accepted'then raise exception 'عدم المباشرة بعد القبول فقط';end if;
if p_stage in('assessment','recommended')and not exists(select 1 from private.recruitment_interviews where application_id=a.id and interviewer_id=r.supervisor_id and round=1 and state='completed')then raise exception 'يلزم تقييم المدير المباشر';end if;
if p_stage='recommended'and(a.second_interview_reason is not null and not exists(select 1 from private.recruitment_interviews where application_id=a.id and interviewer_id=r.interview_manager_id and round=2 and state='completed'))then raise exception 'أكمل تقييم المقابلة الثانية';end if;
if p_stage='recommended'and exists(select 1 from private.recruitment_interviews where application_id=a.id and state='scheduled')then raise exception 'أكمل المقابلات المجدولة';end if;
update private.recruitment_applications set stage=p_stage,selection_approved=p_stage='recommended',rejection_reason=case when p_stage='rejected'then p_note else rejection_reason end,revision=revision+1,updated_at=now()where id=a.id;
if p_stage in('rejected','withdrawn','no_show')then update private.recruitment_tasks set done=true where application_id=a.id;update private.recruitment_offers set state='superseded'where application_id=a.id and state not in('declined','expired','superseded');end if;
if p_stage='interview' then
update private.recruitment_tasks set done=true where application_id=a.id and key in('referral:'||a.id,'candidate-stage:'||a.id);
perform private.recruitment_task('candidate-stage:'||a.id,r.id,a.id,r.supervisor_id,'إجراء المقابلة الأولى وتسجيل التقييم',3);
elsif p_stage='assessment' then
update private.recruitment_tasks set done=true where application_id=a.id and key in('referral:'||a.id,'candidate-stage:'||a.id);
perform private.recruitment_task('candidate-stage:'||a.id,r.id,a.id,r.supervisor_id,'مراجعة التقييم واتخاذ قرار اختيار المرشح',3);
elsif p_stage='recommended' then
update private.recruitment_tasks set done=true where application_id=a.id and key in('referral:'||a.id,'candidate-stage:'||a.id);
end if;
if p_stage='recommended'then perform private.recruitment_task('prepare:'||a.id,r.id,a.id,r.recruiter_id,'إعداد العرض الوظيفي',2);update private.recruitment_tasks set done=true where key in('referral:'||a.id,'batch-review:'||r.id);end if;
perform private.recruitment_event(r.id,a.id,'stage_'||p_stage,p_note);end$function$
;
CREATE OR REPLACE FUNCTION public.recruitment_email_claim(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$
declare x private.recruitment_email_outbox;begin
 if auth.role() is distinct from 'service_role' then raise exception 'غير مخول'using errcode='42501';end if;
 select * into strict x from private.recruitment_email_outbox where id=p_id for update;
 if x.state='sent'then return jsonb_build_object('already_sent',true);end if;
 if x.state='sending'and x.claimed_at>now()-interval '5 minutes'then return jsonb_build_object('busy',true);end if;
 update private.recruitment_email_outbox set state='sending',claimed_at=now(),last_error=null where id=x.id;
 return to_jsonb(x);
end $function$
;
CREATE OR REPLACE FUNCTION public.recruitment_email_finish(p_id uuid, p_provider_id text DEFAULT NULL::text, p_error text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$ begin
 if auth.role() is distinct from 'service_role'then raise exception 'غير مخول'using errcode='42501';end if;
 update private.recruitment_email_outbox set state=case when p_provider_id is not null then 'sent'else 'failed'end,provider_id=p_provider_id,last_error=left(p_error,200),sent_at=case when p_provider_id is not null then now()end where id=p_id and state='sending';
end $function$
;
CREATE OR REPLACE FUNCTION public.recruitment_email_prepare(p_offer uuid, p_event text, p_token uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$ select private.recruitment_email_prepare(p_offer,p_event,p_token) $function$
;
CREATE OR REPLACE FUNCTION public.recruitment_referral_prepare(p_request uuid, p_name text)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'pg_catalog'
AS $function$select private.recruitment_referral_prepare(p_request,p_name)$function$
;
CREATE OR REPLACE FUNCTION public.recruitment_route_settings(p_action text DEFAULT 'get'::text, p_data jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$
  select private.recruitment_route_settings(p_action,p_data)
$function$
;
revoke all on function public.recruitment_application_action(p_application uuid, p_action text, p_data jsonb) from public,anon,authenticated,service_role;
revoke all on function private.recruitment_application_action(p_application uuid, p_action text, p_data jsonb) from public,anon,authenticated,service_role;
revoke all on function public.recruitment_batch_action(p_request uuid, p_action text, p_data jsonb) from public,anon,authenticated,service_role;
revoke all on function private.recruitment_batch_action(p_request uuid, p_action text, p_data jsonb) from public,anon,authenticated,service_role;
revoke all on function public.recruitment_calendar(p_action text, p_data jsonb) from public,anon,authenticated,service_role;
revoke all on function private.recruitment_calendar(p_action text, p_data jsonb) from public,anon,authenticated,service_role;
revoke all on function public.recruitment_candidate_add(p_request uuid, p_data jsonb) from public,anon,authenticated,service_role;
revoke all on function private.recruitment_candidate_add(p_request uuid, p_data jsonb) from public,anon,authenticated,service_role;
revoke all on function private.recruitment_candidate_add_v1(p_request uuid, p_data jsonb) from public,anon,authenticated,service_role;
revoke all on function private.recruitment_check_documents(p_application uuid) from public,anon,authenticated,service_role;
revoke all on function public.recruitment_context() from public,anon,authenticated,service_role;
revoke all on function private.recruitment_context() from public,anon,authenticated,service_role;
revoke all on function private.recruitment_context_v1() from public,anon,authenticated,service_role;
revoke all on function public.recruitment_detail(p_request uuid) from public,anon,authenticated,service_role;
revoke all on function private.recruitment_detail(p_request uuid) from public,anon,authenticated,service_role;
revoke all on function private.recruitment_detail_v1(p_request uuid) from public,anon,authenticated,service_role;
revoke all on function public.recruitment_document_allowed(p_name text, p_write boolean) from public,anon,authenticated,service_role;
revoke all on function private.recruitment_document_allowed(p_name text, p_write boolean) from public,anon,authenticated,service_role;
revoke all on function public.recruitment_email_claim(p_id uuid) from public,anon,authenticated,service_role;
revoke all on function public.recruitment_email_finish(p_id uuid, p_provider_id text, p_error text) from public,anon,authenticated,service_role;
revoke all on function public.recruitment_email_prepare(p_offer uuid, p_event text, p_token uuid) from public,anon,authenticated,service_role;
revoke all on function private.recruitment_email_prepare(p_offer uuid, p_event text, p_token uuid) from public,anon,authenticated,service_role;
revoke all on function private.recruitment_event(p_request uuid, p_application uuid, p_action text, p_note text) from public,anon,authenticated,service_role;
revoke all on function public.recruitment_interview_save(p_application uuid, p_data jsonb) from public,anon,authenticated,service_role;
revoke all on function private.recruitment_interview_save(p_application uuid, p_data jsonb) from public,anon,authenticated,service_role;
revoke all on function public.recruitment_join(p_application uuid, p_data jsonb) from public,anon,authenticated,service_role;
revoke all on function private.recruitment_join(p_application uuid, p_data jsonb) from public,anon,authenticated,service_role;
revoke all on function public.recruitment_list() from public,anon,authenticated,service_role;
revoke all on function private.recruitment_list() from public,anon,authenticated,service_role;
revoke all on function private.recruitment_list_before_queues() from public,anon,authenticated,service_role;
revoke all on function private.recruitment_list_v1() from public,anon,authenticated,service_role;
revoke all on function public.recruitment_offer_action(p_id uuid, p_action text, p_note text) from public,anon,authenticated,service_role;
revoke all on function private.recruitment_offer_action(p_id uuid, p_action text, p_note text) from public,anon,authenticated,service_role;
revoke all on function private.recruitment_offer_clock() from public,anon,authenticated,service_role;
revoke all on function public.recruitment_offer_create(p_application uuid, p_data jsonb) from public,anon,authenticated,service_role;
revoke all on function private.recruitment_offer_create(p_application uuid, p_data jsonb) from public,anon,authenticated,service_role;
revoke all on function private.recruitment_owner(r private.recruitment_requests) from public,anon,authenticated,service_role;
revoke all on function private.recruitment_permission(p_key text) from public,anon,authenticated,service_role;
revoke all on function public.recruitment_portal(p_token uuid, p_action text, p_data jsonb) from public,anon,authenticated,service_role;
revoke all on function private.recruitment_portal(p_token uuid, p_action text, p_data jsonb) from public,anon,authenticated,service_role;
revoke all on function public.recruitment_public_apply(p_token uuid, p_data jsonb) from public,anon,authenticated,service_role;
revoke all on function private.recruitment_public_apply(p_token uuid, p_data jsonb) from public,anon,authenticated,service_role;
revoke all on function public.recruitment_public_jobs(p_token uuid) from public,anon,authenticated,service_role;
revoke all on function private.recruitment_public_jobs(p_token uuid) from public,anon,authenticated,service_role;
revoke all on function private.recruitment_referral_access(p_path text, p_write boolean) from public,anon,authenticated,service_role;
revoke all on function public.recruitment_referral_prepare(p_request uuid, p_name text) from public,anon,authenticated,service_role;
revoke all on function private.recruitment_referral_prepare(p_request uuid, p_name text) from public,anon,authenticated,service_role;
revoke all on function private.recruitment_reminders() from public,anon,authenticated,service_role;
revoke all on function public.recruitment_request_action(p_id uuid, p_revision integer, p_action text, p_data jsonb) from public,anon,authenticated,service_role;
revoke all on function private.recruitment_request_action(p_id uuid, p_revision integer, p_action text, p_data jsonb) from public,anon,authenticated,service_role;
revoke all on function private.recruitment_request_clock() from public,anon,authenticated,service_role;
revoke all on function public.recruitment_request_create(p_data jsonb) from public,anon,authenticated,service_role;
revoke all on function private.recruitment_request_create(p_data jsonb) from public,anon,authenticated,service_role;
revoke all on function private.recruitment_resolve_route() from public,anon,authenticated,service_role;
revoke all on function public.recruitment_resume_allowed(p_name text, p_write boolean) from public,anon,authenticated,service_role;
revoke all on function private.recruitment_resume_allowed(p_name text, p_write boolean) from public,anon,authenticated,service_role;
revoke all on function public.recruitment_route_settings(p_action text, p_data jsonb) from public,anon,authenticated,service_role;
revoke all on function private.recruitment_route_settings(p_action text, p_data jsonb) from public,anon,authenticated,service_role;
revoke all on function private.recruitment_salary_title(p_title text) from public,anon,authenticated,service_role;
revoke all on function public.recruitment_stage(p_application uuid, p_revision integer, p_stage text, p_note text) from public,anon,authenticated,service_role;
revoke all on function private.recruitment_stage(p_application uuid, p_revision integer, p_stage text, p_note text) from public,anon,authenticated,service_role;
revoke all on function private.recruitment_task(p_key text, p_request uuid, p_app uuid, p_owner uuid, p_label text, p_days integer) from public,anon,authenticated,service_role;
revoke all on function private.recruitment_visible(p_id uuid) from public,anon,authenticated,service_role;
revoke all on function private.recruitment_work_due(p_start timestamp with time zone, p_days integer) from public,anon,authenticated,service_role;
grant execute on function public.recruitment_application_action(p_application uuid, p_action text, p_data jsonb) to service_role;
grant execute on function public.recruitment_application_action(p_application uuid, p_action text, p_data jsonb) to authenticated;
grant execute on function private.recruitment_application_action(p_application uuid, p_action text, p_data jsonb) to authenticated;
grant execute on function public.recruitment_batch_action(p_request uuid, p_action text, p_data jsonb) to service_role;
grant execute on function public.recruitment_batch_action(p_request uuid, p_action text, p_data jsonb) to authenticated;
grant execute on function private.recruitment_batch_action(p_request uuid, p_action text, p_data jsonb) to authenticated;
grant execute on function public.recruitment_calendar(p_action text, p_data jsonb) to service_role;
grant execute on function public.recruitment_calendar(p_action text, p_data jsonb) to authenticated;
grant execute on function private.recruitment_calendar(p_action text, p_data jsonb) to authenticated;
grant execute on function public.recruitment_candidate_add(p_request uuid, p_data jsonb) to service_role;
grant execute on function public.recruitment_candidate_add(p_request uuid, p_data jsonb) to authenticated;
grant execute on function private.recruitment_candidate_add(p_request uuid, p_data jsonb) to authenticated;
grant execute on function public.recruitment_context() to service_role;
grant execute on function public.recruitment_context() to authenticated;
grant execute on function private.recruitment_context() to authenticated;
grant execute on function public.recruitment_detail(p_request uuid) to service_role;
grant execute on function public.recruitment_detail(p_request uuid) to authenticated;
grant execute on function private.recruitment_detail(p_request uuid) to authenticated;
grant execute on function public.recruitment_document_allowed(p_name text, p_write boolean) to service_role;
grant execute on function public.recruitment_document_allowed(p_name text, p_write boolean) to authenticated;
grant execute on function public.recruitment_document_allowed(p_name text, p_write boolean) to anon;
grant execute on function private.recruitment_document_allowed(p_name text, p_write boolean) to authenticated;
grant execute on function private.recruitment_document_allowed(p_name text, p_write boolean) to anon;
grant execute on function public.recruitment_email_claim(p_id uuid) to service_role;
grant execute on function public.recruitment_email_finish(p_id uuid, p_provider_id text, p_error text) to service_role;
grant execute on function public.recruitment_email_prepare(p_offer uuid, p_event text, p_token uuid) to anon;
grant execute on function public.recruitment_email_prepare(p_offer uuid, p_event text, p_token uuid) to authenticated;
grant execute on function public.recruitment_email_prepare(p_offer uuid, p_event text, p_token uuid) to service_role;
grant execute on function private.recruitment_email_prepare(p_offer uuid, p_event text, p_token uuid) to anon;
grant execute on function private.recruitment_email_prepare(p_offer uuid, p_event text, p_token uuid) to authenticated;
grant execute on function public.recruitment_interview_save(p_application uuid, p_data jsonb) to service_role;
grant execute on function public.recruitment_interview_save(p_application uuid, p_data jsonb) to authenticated;
grant execute on function private.recruitment_interview_save(p_application uuid, p_data jsonb) to authenticated;
grant execute on function public.recruitment_join(p_application uuid, p_data jsonb) to service_role;
grant execute on function public.recruitment_join(p_application uuid, p_data jsonb) to authenticated;
grant execute on function private.recruitment_join(p_application uuid, p_data jsonb) to authenticated;
grant execute on function public.recruitment_list() to service_role;
grant execute on function public.recruitment_list() to authenticated;
grant execute on function private.recruitment_list() to authenticated;
grant execute on function public.recruitment_offer_action(p_id uuid, p_action text, p_note text) to service_role;
grant execute on function public.recruitment_offer_action(p_id uuid, p_action text, p_note text) to authenticated;
grant execute on function private.recruitment_offer_action(p_id uuid, p_action text, p_note text) to authenticated;
grant execute on function public.recruitment_offer_create(p_application uuid, p_data jsonb) to service_role;
grant execute on function public.recruitment_offer_create(p_application uuid, p_data jsonb) to authenticated;
grant execute on function private.recruitment_offer_create(p_application uuid, p_data jsonb) to authenticated;
grant execute on function public.recruitment_portal(p_token uuid, p_action text, p_data jsonb) to service_role;
grant execute on function public.recruitment_portal(p_token uuid, p_action text, p_data jsonb) to authenticated;
grant execute on function public.recruitment_portal(p_token uuid, p_action text, p_data jsonb) to anon;
grant execute on function private.recruitment_portal(p_token uuid, p_action text, p_data jsonb) to authenticated;
grant execute on function private.recruitment_portal(p_token uuid, p_action text, p_data jsonb) to anon;
grant execute on function public.recruitment_public_apply(p_token uuid, p_data jsonb) to service_role;
grant execute on function public.recruitment_public_apply(p_token uuid, p_data jsonb) to authenticated;
grant execute on function public.recruitment_public_apply(p_token uuid, p_data jsonb) to anon;
grant execute on function private.recruitment_public_apply(p_token uuid, p_data jsonb) to authenticated;
grant execute on function private.recruitment_public_apply(p_token uuid, p_data jsonb) to anon;
grant execute on function public.recruitment_public_jobs(p_token uuid) to service_role;
grant execute on function public.recruitment_public_jobs(p_token uuid) to authenticated;
grant execute on function public.recruitment_public_jobs(p_token uuid) to anon;
grant execute on function private.recruitment_public_jobs(p_token uuid) to authenticated;
grant execute on function private.recruitment_public_jobs(p_token uuid) to anon;
grant execute on function private.recruitment_referral_access(p_path text, p_write boolean) to authenticated;
grant execute on function public.recruitment_referral_prepare(p_request uuid, p_name text) to authenticated;
grant execute on function public.recruitment_referral_prepare(p_request uuid, p_name text) to service_role;
grant execute on function private.recruitment_referral_prepare(p_request uuid, p_name text) to authenticated;
grant execute on function public.recruitment_request_action(p_id uuid, p_revision integer, p_action text, p_data jsonb) to service_role;
grant execute on function public.recruitment_request_action(p_id uuid, p_revision integer, p_action text, p_data jsonb) to authenticated;
grant execute on function private.recruitment_request_action(p_id uuid, p_revision integer, p_action text, p_data jsonb) to authenticated;
grant execute on function public.recruitment_request_create(p_data jsonb) to service_role;
grant execute on function public.recruitment_request_create(p_data jsonb) to authenticated;
grant execute on function private.recruitment_request_create(p_data jsonb) to authenticated;
grant execute on function public.recruitment_resume_allowed(p_name text, p_write boolean) to service_role;
grant execute on function public.recruitment_resume_allowed(p_name text, p_write boolean) to authenticated;
grant execute on function public.recruitment_resume_allowed(p_name text, p_write boolean) to anon;
grant execute on function private.recruitment_resume_allowed(p_name text, p_write boolean) to authenticated;
grant execute on function private.recruitment_resume_allowed(p_name text, p_write boolean) to anon;
grant execute on function public.recruitment_route_settings(p_action text, p_data jsonb) to authenticated;
grant execute on function public.recruitment_route_settings(p_action text, p_data jsonb) to service_role;
grant execute on function private.recruitment_route_settings(p_action text, p_data jsonb) to authenticated;
grant execute on function public.recruitment_stage(p_application uuid, p_revision integer, p_stage text, p_note text) to service_role;
grant execute on function public.recruitment_stage(p_application uuid, p_revision integer, p_stage text, p_note text) to authenticated;
grant execute on function private.recruitment_stage(p_application uuid, p_revision integer, p_stage text, p_note text) to authenticated;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('recruitment-referrals','recruitment-referrals',false,5242880,array['application/pdf']) on conflict(id)do nothing;
drop policy if exists referral_read on storage.objects;
create policy referral_read on storage.objects for SELECT to authenticated using (((bucket_id = 'recruitment-referrals'::text) AND private.recruitment_referral_access(name, false))) ;
drop policy if exists referral_insert on storage.objects;
create policy referral_insert on storage.objects for INSERT to authenticated  with check (((bucket_id = 'recruitment-referrals'::text) AND private.recruitment_referral_access(name, true)));


commit;
