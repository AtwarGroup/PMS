-- Recruitment records are private. Public APIs are invoker wrappers around checked private commands.
insert into private.app_modules values('recruitment','التوظيف','user-round-plus','recruitment/index.html',true,90);
insert into private.access_catalog(key,module,label,operation,scopes,sort_order) values
('recruitment.manage','التوظيف','إدارة التوظيف والمرشحين','manage',array['all'],100),
('recruitment.finance','التوظيف','مراجعة ميزانية التوظيف والعروض','finance',array['all'],101),
('recruitment.approve','التوظيف','اعتماد احتياجات وعروض التوظيف','approve',array['all'],102);
create table private.recruitment_salary_reference(id uuid primary key default gen_random_uuid(),title text not null unique,grade text not null,saudi_min numeric not null,saudi_max numeric not null,expat_min numeric,expat_max numeric,source_revision text not null,check(saudi_min>0 and saudi_max>=saudi_min),check((expat_min is null and expat_max is null)or(expat_min>0 and expat_max>=expat_min)));
create table private.recruitment_requests(
 id uuid primary key default gen_random_uuid(),number bigint generated always as identity unique,created_by uuid not null references public.profiles(id),
 job_id uuid not null references public.job_descriptions(id),job_snapshot jsonb not null,salary_id uuid references private.recruitment_salary_reference(id),salary_snapshot jsonb,
 department_id uuid not null references private.hr_departments(id),section_id uuid not null references private.hr_sections(id),manager_id uuid references private.hr_employees(id),company text not null,location text not null,
 headcount integer not null check(headcount between 1 and 100),reason text not null,route text not null check(route in('advertised','referral')),target_date date not null,
 hr_id uuid not null references public.profiles(id),finance_id uuid not null references public.profiles(id),approver_id uuid not null references public.profiles(id),interviewer_ids uuid[] not null default '{}',
 criteria jsonb not null, status text not null default 'hr_review' check(status in('hr_review','finance_review','approval','open','closed','rejected','cancelled')),
 published boolean not null default false,public_token uuid not null default gen_random_uuid(),advertisement text not null default '',
 revision integer not null default 1,created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create index recruitment_requests_creator_idx on private.recruitment_requests(created_by);
create index recruitment_requests_job_idx on private.recruitment_requests(job_id);
create index recruitment_requests_department_idx on private.recruitment_requests(department_id);
create index recruitment_requests_section_idx on private.recruitment_requests(section_id);
create index recruitment_requests_salary_idx on private.recruitment_requests(salary_id);
create index recruitment_requests_hr_idx on private.recruitment_requests(hr_id);
create index recruitment_requests_finance_idx on private.recruitment_requests(finance_id);
create index recruitment_requests_approver_idx on private.recruitment_requests(approver_id);
create index recruitment_requests_manager_idx on private.recruitment_requests(manager_id);
create unique index recruitment_requests_token_idx on private.recruitment_requests(public_token);
create table private.recruitment_candidates(id uuid primary key default gen_random_uuid(),full_name text not null check(length(btrim(full_name)) between 2 and 150),email text not null,phone text not null,city text not null default '',saudi boolean not null,experience text not null default '',resume_text text not null default '',created_at timestamptz not null default now());
create unique index recruitment_candidate_email_idx on private.recruitment_candidates(lower(email));
create table private.recruitment_applications(id uuid primary key default gen_random_uuid(),request_id uuid not null references private.recruitment_requests(id),candidate_id uuid not null references private.recruitment_candidates(id),source text not null,referral_note text not null default '',stage text not null default 'screening' check(stage in('screening','interview','assessment','recommended','offer','accepted','hired','rejected','withdrawn','no_show')),revision integer not null default 1,employee_id uuid references private.hr_employees(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now(),unique(request_id,candidate_id));
create index recruitment_app_candidate_idx on private.recruitment_applications(candidate_id);
create index recruitment_app_employee_idx on private.recruitment_applications(employee_id);
create table private.recruitment_interviews(id uuid primary key default gen_random_uuid(),application_id uuid not null references private.recruitment_applications(id),interviewer_id uuid not null references public.profiles(id),scheduled_at timestamptz not null,kind text not null check(kind in('hr','technical','previous')),state text not null check(state in('scheduled','completed','absent')),scores jsonb,criteria_snapshot jsonb,score numeric check(score between 20 and 100),notes text not null,recommendation text check(recommendation in('suitable','conditional','unsuitable')),recorded_by uuid not null references public.profiles(id),created_at timestamptz not null default now());
create index recruitment_interview_app_idx on private.recruitment_interviews(application_id);
create index recruitment_interview_owner_idx on private.recruitment_interviews(interviewer_id);
create index recruitment_interview_actor_idx on private.recruitment_interviews(recorded_by);
create table private.recruitment_offers(id uuid primary key default gen_random_uuid(),application_id uuid not null references private.recruitment_applications(id),version integer not null, basic numeric not null check(basic>0),housing numeric not null check(housing>=0),transport numeric not null check(transport>=0),total numeric generated always as(basic+housing+transport) stored,start_date date not null,expires_on date not null,benefits text not null,salary_snapshot jsonb not null,exception_reason text not null default '',state text not null default 'finance_review' check(state in('finance_review','approval','approved','sent','accepted','declined','expired','superseded')),created_by uuid not null references public.profiles(id),created_at timestamptz not null default now(),unique(application_id,version),check(expires_on>=created_at::date),check(basic+housing+transport<100000000));
create index recruitment_offer_creator_idx on private.recruitment_offers(created_by);
create unique index recruitment_offer_current_idx on private.recruitment_offers(application_id)where state not in('superseded','declined','expired');
create table private.recruitment_events(id bigint generated always as identity primary key,request_id uuid not null references private.recruitment_requests(id),application_id uuid references private.recruitment_applications(id),actor_id uuid references public.profiles(id),action text not null,note text not null default '',created_at timestamptz not null default now());
create index recruitment_events_req_idx on private.recruitment_events(request_id,id desc);
create index recruitment_events_app_idx on private.recruitment_events(application_id);
create index recruitment_events_actor_idx on private.recruitment_events(actor_id);
do $$declare t text;begin foreach t in array array['recruitment_salary_reference','recruitment_requests','recruitment_candidates','recruitment_applications','recruitment_interviews','recruitment_offers','recruitment_events']loop
 execute format('alter table private.%I enable row level security',t);execute format('revoke all on private.%I from public,anon,authenticated',t);execute format('create policy internal_only on private.%I to authenticated using(false) with check(false)',t);end loop;end$$;
create function private.recruitment_permission(p_key text)returns boolean language sql stable security definer set search_path=pg_catalog,private,public as $$
 select private.module_allowed('recruitment')and exists(select 1 from public.profiles where id=auth.uid()and(role='admin'or p_key=any(permissions)))
$$;
create function private.recruitment_visible(p_id uuid)returns boolean language sql stable security definer set search_path=pg_catalog,private,public as $$
 select private.module_allowed('recruitment')and exists(select 1 from private.recruitment_requests r where r.id=p_id and(private.recruitment_permission('recruitment.manage')or auth.uid()in(r.created_by,r.hr_id,r.finance_id,r.approver_id)or auth.uid()=any(r.interviewer_ids)))
$$;
create function private.recruitment_event(p_request uuid,p_application uuid,p_action text,p_note text)returns void language plpgsql security definer set search_path=pg_catalog,private,public as $$
declare recipient uuid;begin
 insert into private.recruitment_events(request_id,application_id,actor_id,action,note)values(p_request,p_application,auth.uid(),p_action,left(coalesce(p_note,''),3000));
 select case r.status when 'hr_review' then r.hr_id when 'finance_review' then r.finance_id when 'approval' then r.approver_id else r.hr_id end into recipient from private.recruitment_requests r where id=p_request;
 if recipient is distinct from auth.uid()then insert into public.notifications(recipient_id,type,title,message)values(recipient,'RECRUITMENT','متابعة التوظيف','يوجد تحديث على طلب التوظيف. افتح وحدة التوظيف للاطلاع على الإجراء.');end if;
end$$;
create function private.recruitment_context()returns jsonb language plpgsql stable security definer set search_path=pg_catalog,private,public as $$
begin perform private.require_module('recruitment');
 return jsonb_build_object('user_id',auth.uid(),'manage',private.recruitment_permission('recruitment.manage'),'finance',private.recruitment_permission('recruitment.finance'),'approve',private.recruitment_permission('recruitment.approve'),
 'can_request',private.recruitment_permission('recruitment.manage')or private.current_user_role()='manager',
 'jobs',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'job_code',job_code,'title',published_snapshot->>'title','snapshot',published_snapshot) order by job_code),'[]')from public.job_descriptions where published_snapshot is not null),
 'salaries',case when private.recruitment_permission('recruitment.manage')or private.recruitment_permission('recruitment.finance')or private.recruitment_permission('recruitment.approve')then(select coalesce(jsonb_agg(to_jsonb(s)order by title),'[]')from private.recruitment_salary_reference s)else '[]'::jsonb end,
 'departments',(select coalesce(jsonb_agg(to_jsonb(d)order by name),'[]')from private.hr_departments d),'sections',(select coalesce(jsonb_agg(to_jsonb(s)order by name),'[]')from private.hr_sections s),
 'people',(select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'full_name',p.full_name,'manage',p.role='admin'or'recruitment.manage'=any(p.permissions),'finance',p.role='admin'or'recruitment.finance'=any(p.permissions),'approve',p.role='admin'or'recruitment.approve'=any(p.permissions))order by full_name),'[]')from public.profiles p where p.active and p.status='active'and(p.role='admin'or'recruitment'=any(p.allowed_modules))),
 'managers',(select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'full_name',e.full_name)order by full_name),'[]')from private.hr_employees e));end$$;
create function private.recruitment_list()returns jsonb language plpgsql stable security definer set search_path=pg_catalog,private,public as $$
begin perform private.require_module('recruitment');return jsonb_build_object(
 'requests',(select coalesce(jsonb_agg(to_jsonb(r)-'salary_snapshot'-'salary_id' order by r.created_at desc),'[]')from private.recruitment_requests r where private.recruitment_visible(r.id)),
 'applications',(select coalesce(jsonb_agg(to_jsonb(a)||jsonb_build_object('candidate_name',c.full_name,'job_title',r.job_snapshot->>'title')order by a.created_at desc),'[]')from private.recruitment_applications a join private.recruitment_candidates c on c.id=a.candidate_id join private.recruitment_requests r on r.id=a.request_id where private.recruitment_visible(r.id))
 );end$$;
create function private.recruitment_detail(p_request uuid)returns jsonb language plpgsql stable security definer set search_path=pg_catalog,private,public as $$
declare r private.recruitment_requests%rowtype;pay boolean;begin
 if not private.recruitment_visible(p_request)then raise exception 'السجل غير متاح'using errcode='42501';end if;
 select * into strict r from private.recruitment_requests where id=p_request;
 pay:=private.recruitment_permission('recruitment.manage')or(auth.uid()=r.finance_id and private.recruitment_permission('recruitment.finance'))or(auth.uid()=r.approver_id and private.recruitment_permission('recruitment.approve'));
 return jsonb_build_object('request',case when pay then to_jsonb(r)else to_jsonb(r)-'salary_snapshot'-'salary_id'end,'can_pay',pay,
 'applications',(select coalesce(jsonb_agg(to_jsonb(a)||jsonb_build_object('candidate',to_jsonb(c))order by a.created_at),'[]')from private.recruitment_applications a join private.recruitment_candidates c on c.id=a.candidate_id where a.request_id=p_request),
 'interviews',(select coalesce(jsonb_agg(to_jsonb(i)order by i.scheduled_at desc),'[]')from private.recruitment_interviews i join private.recruitment_applications a on a.id=i.application_id where a.request_id=p_request),
 'offers',case when pay then(select coalesce(jsonb_agg(to_jsonb(o)order by o.created_at desc),'[]')from private.recruitment_offers o join private.recruitment_applications a on a.id=o.application_id where a.request_id=p_request)else '[]'::jsonb end,
 'events',(select coalesce(jsonb_agg(to_jsonb(e)order by e.id desc),'[]')from private.recruitment_events e where request_id=p_request));end$$;
create function private.recruitment_request_create(p_data jsonb)returns uuid language plpgsql security definer set search_path=pg_catalog,private,public as $$
declare j public.job_descriptions%rowtype;s private.recruitment_salary_reference%rowtype;rid uuid;person record;criteria jsonb:=p_data->'criteria';begin
 perform private.require_module('recruitment');if not(private.recruitment_permission('recruitment.manage')or private.current_user_role()='manager')then raise exception 'إنشاء الاحتياج متاح للمدير والموارد البشرية'using errcode='42501';end if;
 select * into strict j from public.job_descriptions where id=(p_data->>'job_id')::uuid and published_snapshot is not null;
 if nullif(p_data->>'salary_id','')is not null then
 if not private.recruitment_permission('recruitment.manage')then raise exception 'ربط السلم من اختصاص الموارد البشرية'using errcode='42501';end if;
 select * into strict s from private.recruitment_salary_reference where id=(p_data->>'salary_id')::uuid;
 else select * into s from private.recruitment_salary_reference where btrim(title)=btrim(j.published_snapshot->>'title');end if;
 for person in select * from(values('hr_id','recruitment.manage'),('finance_id','recruitment.finance'),('approver_id','recruitment.approve'))x(field,permission)loop
 if not exists(select 1 from public.profiles where id=(p_data->>person.field)::uuid and active and status='active'and(role='admin'or('recruitment'=any(allowed_modules)and person.permission=any(permissions))))then raise exception 'يرجى تحديد مسؤول مخول لكل مرحلة';end if;end loop;
 if not exists(select 1 from private.hr_sections where id=(p_data->>'section_id')::uuid and department_id=(p_data->>'department_id')::uuid)then raise exception 'القسم لا يتبع الإدارة';end if;
 if coalesce(length(btrim(p_data->>'reason')),0)<3 or coalesce(length(btrim(p_data->>'company')),0)<2 or coalesce(length(btrim(p_data->>'location')),0)<2 or(p_data->>'target_date')::date<current_date then raise exception 'أكمل المبررات والشركة والموقع وتاريخ المباشرة';end if;
 if jsonb_typeof(criteria)is distinct from 'array'or jsonb_array_length(criteria)not between 1 and 20 then raise exception 'حدد معايير التقييم';end if;
 if(select sum((x->>'weight')::numeric)<>100 or count(distinct x->>'key')<>count(*)or bool_or(coalesce(length(x->>'label'),0)<2 or coalesce(length(x->>'key'),0)<1 or coalesce((x->>'weight')::numeric,0)<=0)from jsonb_array_elements(criteria)x)then raise exception 'معايير التقييم وأوزانها غير صحيحة';end if;
 if exists(select 1 from jsonb_array_elements_text(coalesce(p_data->'interviewer_ids','[]'))x where not exists(select 1 from public.profiles where id=x.value::uuid and active and status='active'and(role='admin'or'recruitment'=any(allowed_modules))))then raise exception 'اختر أعضاء مقابلة بحسابات نشطة ومخولين بدخول التوظيف';end if;
 insert into private.recruitment_requests(created_by,job_id,job_snapshot,salary_id,salary_snapshot,department_id,section_id,manager_id,company,location,headcount,reason,route,target_date,hr_id,finance_id,approver_id,interviewer_ids,criteria)
 values(auth.uid(),j.id,j.published_snapshot,s.id,to_jsonb(s),(p_data->>'department_id')::uuid,(p_data->>'section_id')::uuid,nullif(p_data->>'manager_id','')::uuid,btrim(p_data->>'company'),btrim(p_data->>'location'),(p_data->>'headcount')::int,btrim(p_data->>'reason'),p_data->>'route',(p_data->>'target_date')::date,(p_data->>'hr_id')::uuid,(p_data->>'finance_id')::uuid,(p_data->>'approver_id')::uuid,array(select value::uuid from jsonb_array_elements_text(coalesce(p_data->'interviewer_ids','[]'))),criteria)returning id into rid;
 perform private.recruitment_event(rid,null,'request_created','طلب احتياج جديد');return rid;end$$;
create function private.recruitment_request_action(p_id uuid,p_revision integer,p_action text,p_data jsonb)returns void language plpgsql security definer set search_path=pg_catalog,private,public as $$
declare r private.recruitment_requests%rowtype;s private.recruitment_salary_reference%rowtype;next_state text;begin
 if not private.recruitment_visible(p_id)then raise exception 'السجل غير متاح'using errcode='42501';end if;select * into strict r from private.recruitment_requests where id=p_id for update;
 if r.revision<>p_revision then raise exception 'تم تحديث الطلب، حدّث الصفحة وأعد المحاولة'using errcode='40001';end if;
 if p_action='link_salary'and r.status='hr_review'and auth.uid()=r.hr_id and private.recruitment_permission('recruitment.manage')then
 select * into strict s from private.recruitment_salary_reference where id=(p_data->>'salary_id')::uuid;
 if coalesce(length(btrim(p_data->>'note')),0)<3 then raise exception 'وثق أساس مطابقة المسمى مع المرجع';end if;
 update private.recruitment_requests set salary_id=s.id,salary_snapshot=to_jsonb(s)where id=r.id;
 elsif p_action in('approve','reject')then
 if not((r.status='hr_review'and auth.uid()=r.hr_id and private.recruitment_permission('recruitment.manage'))or(r.status='finance_review'and auth.uid()=r.finance_id and private.recruitment_permission('recruitment.finance'))or(r.status='approval'and auth.uid()=r.approver_id and private.recruitment_permission('recruitment.approve')))then raise exception 'الإجراء لدى المسؤول المحدد للمرحلة'using errcode='42501';end if;
 if p_action='reject'then if coalesce(length(btrim(p_data->>'note')),0)<3 then raise exception 'سبب الرفض مطلوب';end if;next_state:='rejected';
 else if r.salary_id is null then raise exception 'يلزم ربط السلم المعتمد قبل الاعتماد';end if;next_state:=case r.status when 'hr_review'then 'finance_review'when 'finance_review'then 'approval'when 'approval'then 'open'end;end if;
 update private.recruitment_requests set status=next_state,published=false where id=r.id;
 elsif p_action='publish'and r.status='open'and r.route='advertised'and private.recruitment_permission('recruitment.manage')then
 if coalesce(length(btrim(p_data->>'advertisement')),0)<20 then raise exception 'أكمل نص الإعلان';end if;
 update private.recruitment_requests set advertisement=p_data->>'advertisement',published=true where id=r.id;
 elsif p_action='unpublish'and private.recruitment_permission('recruitment.manage')then update private.recruitment_requests set published=false where id=r.id;
 elsif p_action='cancel'and r.status not in('closed','cancelled')and private.recruitment_permission('recruitment.manage')then
 if coalesce(length(btrim(p_data->>'note')),0)<3 then raise exception 'سبب الإلغاء مطلوب';end if;
 if exists(select 1 from private.recruitment_applications where request_id=r.id and stage in('accepted','hired'))then raise exception 'توجد حالات قبول أو مباشرة؛ عالجها قبل إلغاء الاحتياج';end if;
 update private.recruitment_requests set status='cancelled',published=false where id=r.id;
 else raise exception 'الإجراء غير متاح';end if;
 update private.recruitment_requests set revision=revision+1,updated_at=now()where id=r.id;
 perform private.recruitment_event(r.id,null,'request_'||p_action,coalesce(p_data->>'note',''));end$$;
create function private.recruitment_candidate_add(p_request uuid,p_data jsonb)returns uuid language plpgsql security definer set search_path=pg_catalog,private,public as $$
declare r private.recruitment_requests%rowtype;cid uuid;aid uuid;v_email text:=lower(btrim(p_data->>'email'));begin
 if not private.recruitment_visible(p_request)then raise exception 'السجل غير متاح'using errcode='42501';end if;select * into strict r from private.recruitment_requests where id=p_request for update;
 if not(private.recruitment_permission('recruitment.manage')or auth.uid()=r.created_by)then raise exception 'إضافة المرشحين غير متاحة'using errcode='42501';end if;
 if r.status not in('hr_review','finance_review','approval','open')then raise exception 'الطلب مغلق';end if;
 if coalesce(v_email,'')!~'^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'or coalesce(p_data->>'phone','')!~'^\+?[0-9 ()-]{8,20}$'then raise exception 'تحقق من البريد ورقم الجوال';end if;
 if coalesce(length(btrim(p_data->>'resume_text')),0)<10 or coalesce(length(btrim(p_data->>'source')),0)<2 then raise exception 'أكمل ملخص السيرة ومصدر المرشح';end if;
 insert into private.recruitment_candidates(full_name,email,phone,city,saudi,experience,resume_text)values(btrim(p_data->>'full_name'),v_email,btrim(p_data->>'phone'),coalesce(p_data->>'city',''),(p_data->>'saudi')::boolean,coalesce(p_data->>'experience',''),p_data->>'resume_text')on conflict(lower(email))do nothing returning id into cid;
 if cid is null then select id into cid from private.recruitment_candidates where lower(recruitment_candidates.email)=v_email;end if;
 insert into private.recruitment_applications(request_id,candidate_id,source,referral_note)values(r.id,cid,p_data->>'source',coalesce(p_data->>'referral_note',''))on conflict(request_id,candidate_id)do nothing returning id into aid;
 if aid is null then raise exception 'المرشح مسجل لهذا الشاغر بالفعل';end if;perform private.recruitment_event(r.id,aid,'candidate_added',p_data->>'referral_note');return aid;end$$;
create function private.recruitment_interview_save(p_application uuid,p_data jsonb)returns uuid language plpgsql security definer set search_path=pg_catalog,private,public as $$
declare a private.recruitment_applications%rowtype;r private.recruitment_requests%rowtype;iid uuid;total numeric;criterion jsonb;value numeric;owner uuid:=(p_data->>'interviewer_id')::uuid;begin
 select * into strict a from private.recruitment_applications where id=p_application for update;select * into strict r from private.recruitment_requests where id=a.request_id;
 if not private.recruitment_visible(r.id)then raise exception 'السجل غير متاح'using errcode='42501';end if;
 if not(private.recruitment_permission('recruitment.manage')or auth.uid()=r.created_by or auth.uid()=any(r.interviewer_ids))then raise exception 'غير مخول بالتقييم'using errcode='42501';end if;
 if not private.recruitment_permission('recruitment.manage')and owner<>auth.uid()then raise exception 'سجل تقييمك الشخصي فقط';end if;
 if not(owner in(r.hr_id,r.created_by)or owner=any(r.interviewer_ids))then raise exception 'المقيم غير مرتبط بالشاغر';end if;
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
 perform private.recruitment_event(r.id,a.id,'interview_'||(p_data->>'state'),p_data->>'notes');return iid;end$$;
create function private.recruitment_stage(p_application uuid,p_revision integer,p_stage text,p_note text)returns void language plpgsql security definer set search_path=pg_catalog,private,public as $$
declare a private.recruitment_applications%rowtype;r private.recruitment_requests%rowtype;begin
 select * into strict a from private.recruitment_applications where id=p_application for update;select * into strict r from private.recruitment_requests where id=a.request_id;
 if not private.recruitment_visible(r.id)or not private.recruitment_permission('recruitment.manage')then raise exception 'إدارة المراحل من اختصاص الموارد البشرية'using errcode='42501';end if;
 if a.revision<>p_revision then raise exception 'تم تحديث المرشح؛ أعد التحميل'using errcode='40001';end if;
 if r.status<>'open'or a.stage in('hired','rejected','withdrawn','no_show')then raise exception 'الطلب أو التقديم مغلق';end if;
 if coalesce(length(btrim(p_note)),0)<3 then raise exception 'سبب الانتقال مطلوب';end if;
 if p_stage not in('rejected','withdrawn','no_show')and not((a.stage='screening'and p_stage='interview')or(a.stage='interview'and p_stage='assessment')or(a.stage='assessment'and p_stage='recommended'))then raise exception 'انتقال غير مسموح';end if;
 if p_stage='no_show'and a.stage<>'accepted'then raise exception 'عدم المباشرة بعد القبول فقط';end if;
 if p_stage in('assessment','recommended')and not exists(select 1 from private.recruitment_interviews where application_id=a.id and state='completed')then raise exception 'أكمل تقييم المقابلة أولًا';end if;
 if p_stage='recommended'and exists(select 1 from private.recruitment_interviews where application_id=a.id and state='scheduled')then raise exception 'أكمل المقابلات المجدولة أولًا';end if;
 if p_stage='recommended'and not exists(select 1 from private.recruitment_interviews where application_id=a.id and state='completed'and recommendation in('suitable','conditional'))then raise exception 'لا توجد توصية مناسبة للتعيين';end if;
 update private.recruitment_applications set stage=p_stage,revision=revision+1,updated_at=now()where id=a.id;
 if p_stage in('rejected','withdrawn','no_show')then update private.recruitment_offers set state='superseded'where application_id=a.id and state not in('declined','expired','superseded');end if;
 perform private.recruitment_event(r.id,a.id,'stage_'||p_stage,p_note);end$$;
create function private.recruitment_offer_create(p_application uuid,p_data jsonb)returns uuid language plpgsql security definer set search_path=pg_catalog,private,public as $$
declare a private.recruitment_applications%rowtype;r private.recruitment_requests%rowtype;c private.recruitment_candidates%rowtype;s jsonb;vmin numeric;vmax numeric;amount numeric;oid uuid;begin
 perform private.require_module('recruitment');if not private.recruitment_permission('recruitment.manage')then raise exception 'إعداد العرض من اختصاص الموارد البشرية'using errcode='42501';end if;
 select * into strict a from private.recruitment_applications where id=p_application for update;select * into strict r from private.recruitment_requests where id=a.request_id for update;select * into strict c from private.recruitment_candidates where id=a.candidate_id;
 if r.status<>'open'or a.stage not in('recommended','offer')then raise exception 'يلزم اجتياز التقييم والتوصية قبل العرض';end if;
 if exists(select 1 from private.recruitment_offers where application_id=a.id and state in('sent','accepted'))then raise exception 'سجل رد المرشح على العرض الحالي أولًا';end if;
 s:=r.salary_snapshot;vmin:=(s->>case when c.saudi then 'saudi_min'else 'expat_min'end)::numeric;vmax:=(s->>case when c.saudi then 'saudi_max'else 'expat_max'end)::numeric;
 if vmin is null or vmax is null then raise exception 'لا يوجد نطاق معتمد لهذه الفئة في الوظيفة';end if;
 amount:=(p_data->>'basic')::numeric+(p_data->>'housing')::numeric+(p_data->>'transport')::numeric;
 if(amount<vmin or amount>vmax)and coalesce(length(btrim(p_data->>'exception_reason')),0)<5 then raise exception 'العرض خارج النطاق؛ سجل مبرر الاستثناء لاعتماده';end if;
 if(p_data->>'start_date')::date<current_date or(p_data->>'expires_on')::date<current_date then raise exception 'تواريخ العرض غير صحيحة';end if;
 update private.recruitment_offers set state='superseded'where application_id=a.id and state not in('superseded','declined','expired');
 insert into private.recruitment_offers(application_id,version,basic,housing,transport,start_date,expires_on,benefits,salary_snapshot,exception_reason,created_by)values(a.id,(select coalesce(max(version),0)+1 from private.recruitment_offers where application_id=a.id),(p_data->>'basic')::numeric,(p_data->>'housing')::numeric,(p_data->>'transport')::numeric,(p_data->>'start_date')::date,(p_data->>'expires_on')::date,coalesce(p_data->>'benefits',''),s,coalesce(p_data->>'exception_reason',''),auth.uid())returning id into oid;
 update private.recruitment_applications set stage='offer',revision=revision+1,updated_at=now()where id=a.id;
 perform private.recruitment_event(r.id,a.id,'offer_created','تم إعداد نسخة عرض للاعتماد');return oid;end$$;
create function private.recruitment_offer_action(p_id uuid,p_action text,p_note text)returns void language plpgsql security definer set search_path=pg_catalog,private,public as $$
declare o private.recruitment_offers%rowtype;a private.recruitment_applications%rowtype;r private.recruitment_requests%rowtype;next_state text;begin
 -- Same lock order as creation and joining: application, request, offer.
 select * into strict a from private.recruitment_applications where id=(select application_id from private.recruitment_offers where id=p_id)for update;
 select * into strict r from private.recruitment_requests where id=a.request_id for update;select * into strict o from private.recruitment_offers where id=p_id for update;
 if not private.recruitment_visible(r.id)then raise exception 'السجل غير متاح'using errcode='42501';end if;
 if r.status<>'open'or a.stage not in('offer','accepted')then raise exception 'الطلب غير مفتوح';end if;
 if p_action='approve'and o.state='finance_review'and auth.uid()=r.finance_id and private.recruitment_permission('recruitment.finance')then next_state:='approval';
 elsif p_action='approve'and o.state='approval'and auth.uid()=r.approver_id and private.recruitment_permission('recruitment.approve')then next_state:='approved';
 elsif p_action='reject'and((o.state='finance_review'and auth.uid()=r.finance_id and private.recruitment_permission('recruitment.finance'))or(o.state='approval'and auth.uid()=r.approver_id and private.recruitment_permission('recruitment.approve')))then next_state:='declined';
 elsif p_action='sent'and o.state='approved'and private.recruitment_permission('recruitment.manage')then next_state:='sent';
 elsif p_action in('accepted','declined','expired')and o.state='sent'and private.recruitment_permission('recruitment.manage')then
 if p_action='expired'and o.expires_on>=current_date then raise exception 'العرض لم تنته صلاحيته بعد';end if;
 if p_action='accepted'and o.expires_on<current_date then raise exception 'انتهت صلاحية العرض؛ أصدر نسخة جديدة';end if;
 if p_action='accepted'and(select count(*)from private.recruitment_applications where request_id=r.id and stage in('accepted','hired'))>=r.headcount then raise exception 'اكتمل العدد المطلوب';end if;
 next_state:=p_action;
 else raise exception 'إجراء العرض غير متاح'using errcode='42501';end if;
 if coalesce(length(btrim(p_note)),0)<3 then raise exception 'وثق قرارك أو وسيلة الإرسال ورد المرشح';end if;
 update private.recruitment_offers set state=next_state where id=o.id;
 if next_state='accepted'then update private.recruitment_applications set stage='accepted',revision=revision+1,updated_at=now()where id=a.id;end if;
 if next_state in('declined','expired')then update private.recruitment_applications set stage='recommended',revision=revision+1,updated_at=now()where id=a.id;end if;
 perform private.recruitment_event(r.id,a.id,'offer_'||next_state,p_note);end$$;
create function private.recruitment_join(p_application uuid,p_data jsonb)returns uuid language plpgsql security definer set search_path=pg_catalog,private,public as $$
declare a private.recruitment_applications%rowtype;r private.recruitment_requests%rowtype;c private.recruitment_candidates%rowtype;o private.recruitment_offers%rowtype;eid uuid;tid uuid;join_on date:=(p_data->>'join_date')::date;begin
 if not private.recruitment_permission('recruitment.manage')then raise exception 'تأكيد المباشرة من اختصاص الموارد البشرية'using errcode='42501';end if;
 select * into strict a from private.recruitment_applications where id=p_application for update;select * into strict r from private.recruitment_requests where id=a.request_id for update;
 if a.stage<>'accepted'or r.status<>'open'then raise exception 'المرشح لم يقبل العرض أو الاحتياج مغلق';end if;
 if join_on is null or join_on>current_date then raise exception 'تاريخ المباشرة الفعلي غير صحيح';end if;
 if coalesce(p_data->>'documents_complete','false')<>'true'or coalesce(length(btrim(p_data->>'note')),0)<3 then raise exception 'أكد اكتمال المستندات وسجل محضر المباشرة';end if;
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
 update private.recruitment_applications set stage='hired',employee_id=eid,revision=revision+1,updated_at=now()where id=a.id;
 if(select count(*)from private.recruitment_applications where request_id=r.id and stage='hired')>=r.headcount then update private.recruitment_requests set status='closed',published=false,revision=revision+1,updated_at=now()where id=r.id;end if;
 perform private.recruitment_event(r.id,a.id,'joined',p_data->>'note');return eid;end$$;
-- Public projection deliberately excludes salary, internal notes and candidate information.
create function private.recruitment_public_jobs(p_token uuid default null)returns jsonb language sql stable security definer set search_path=pg_catalog,private,public as $$
 select coalesce(jsonb_agg(jsonb_build_object('token',r.public_token,'title',r.job_snapshot->>'title','company',r.company,'location',r.location,'advertisement',r.advertisement,'requirements',r.job_snapshot->'content'->'qualifications')order by r.created_at desc),'[]')from private.recruitment_requests r where r.status='open'and r.published and r.route='advertised'and(p_token is null or r.public_token=p_token)
$$;
-- Public intake accepts only a bounded resume summary. File upload is staff-only until an anti-abuse upload gateway is configured.
create function private.recruitment_public_apply(p_token uuid,p_data jsonb)returns void language plpgsql security definer set search_path=pg_catalog,private,public as $$
declare r private.recruitment_requests%rowtype;cid uuid;aid uuid;vv_email text:=lower(btrim(p_data->>'email'));begin
 select * into strict r from private.recruitment_requests where public_token=p_token and status='open'and published and route='advertised'for update;
 if coalesce(p_data->>'consent','false')<>'true'or coalesce(vemail,'')!~'^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'or coalesce(p_data->>'phone','')!~'^\+?[0-9 ()-]{8,20}$'or coalesce(length(p_data->>'resume_text'),0)not between 30 and 10000 or length(p_data::text)>20000 then raise exception 'تحقق من البيانات والموافقة وملخص السيرة الذاتية';end if;
 insert into private.recruitment_candidates(full_name,email,phone,city,saudi,experience,resume_text)values(btrim(p_data->>'full_name'),vemail,p_data->>'phone',left(coalesce(p_data->>'city',''),100),(p_data->>'saudi')::boolean,left(coalesce(p_data->>'experience',''),3000),p_data->>'resume_text')on conflict(lower(email))do nothing returning id into cid;
 if cid is null then select id into cid from private.recruitment_candidates where lower(email)=vemail;end if;
 insert into private.recruitment_applications(request_id,candidate_id,source)values(r.id,cid,'صفحة التقديم')on conflict(request_id,candidate_id)do nothing returning id into aid;
 -- Identical acknowledgement for new and duplicate applications; never disclose another person's profile.
 if aid is not null then perform private.recruitment_event(r.id,aid,'public_application','طلب تقديم من صفحة الوظائف');end if;end$$;
-- Export checked private routines through invoker wrappers, with explicit grants.
do $$declare f record;args text;params text;begin
 for f in select p.oid,p.proname,pg_get_function_identity_arguments(p.oid)identity_args,pg_get_function_arguments(p.oid)full_args,pg_get_function_result(p.oid)result,proargnames from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private'and p.proname in('recruitment_context','recruitment_list','recruitment_detail','recruitment_request_create','recruitment_request_action','recruitment_candidate_add','recruitment_interview_save','recruitment_stage','recruitment_offer_create','recruitment_offer_action','recruitment_join','recruitment_public_jobs','recruitment_public_apply')loop
 select coalesce(string_agg(quote_ident(x),','),'')into params from unnest(f.proargnames)x;
 execute format('create function public.%I(%s)returns %s language sql security invoker set search_path=pg_catalog,private as %L',f.proname,f.full_args,f.result,format('select private.%I(%s)',f.proname,params));
 execute format('revoke all on function private.%I(%s)from public,anon,authenticated',f.proname,f.identity_args);execute format('revoke all on function public.%I(%s)from public,anon,authenticated',f.proname,f.identity_args);
 execute format('grant execute on function private.%I(%s),public.%I(%s)to authenticated',f.proname,f.identity_args,f.proname,f.identity_args);
 if f.proname like 'recruitment_public_%%'then execute format('grant execute on function private.%I(%s),public.%I(%s)to anon',f.proname,f.identity_args,f.proname,f.identity_args);end if;
 end loop;
end$$;
revoke all on function private.recruitment_permission(text),private.recruitment_visible(uuid),private.recruitment_event(uuid,uuid,text,text)from public,anon,authenticated;
