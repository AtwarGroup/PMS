-- Approved workflow: department -> finance -> personnel -> CEO -> recruitment.
-- Rejections route automatically to the designated exception owner.
begin;
alter table private.recruitment_offers drop constraint recruitment_offers_state_check;
alter table private.recruitment_offers add constraint recruitment_offers_state_check check(state in('hr_review','department_review','development_review','approval','approved','sent','accepted','declined','expired','superseded','returned'));
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
    for item in select * from (values('hr_id','recruitment.personnel'),('finance_id','recruitment.finance'),('approver_id','recruitment.approve'),('recruiter_id','recruitment.manage'),('development_id','recruitment.development')) t(field,permission) loop
      owner_id:=nullif(p_data->>item.field,'')::uuid;
      if not exists(select 1 from public.profiles p where p.id=owner_id and p.active and p.status='active' and (p.role='admin' or ('recruitment'=any(p.allowed_modules) and item.permission=any(p.permissions)))) then
        raise exception 'اختر مسؤولًا نشطًا ومخولًا لكل مرحلة: %',item.field using errcode='22023';
      end if;
    end loop;
    if (p_data->>'hr_id')=(p_data->>'recruiter_id') then raise exception 'شؤون الموظفين مستقلة عن إعداد العرض';end if;
    update private.recruitment_route_settings set hr_id=(p_data->>'hr_id')::uuid,finance_id=(p_data->>'finance_id')::uuid,
      approver_id=(p_data->>'approver_id')::uuid,recruiter_id=(p_data->>'recruiter_id')::uuid,
      development_id=(p_data->>'development_id')::uuid,revision=revision+1,updated_by=auth.uid(),updated_at=now()
      where singleton returning * into r;
  elsif p_action<>'get' then raise exception 'إجراء غير متاح'; end if;
  return to_jsonb(r)-'singleton';
end $function$;

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
      and p.role in('manager','admin')
    order by c.depth desc limit 1;
  if head is null then
    with recursive chain as (
      select e.*,0 depth,array[e.id] path from private.hr_employees e where e.id=employee.id
      union all select m.*,c.depth+1,c.path||m.id from chain c join private.hr_employees m on m.id=c.manager_id where not m.id=any(c.path)
    ) select c.profile_id into head from chain c join public.profiles p on p.id=c.profile_id
      where c.depth>0 and c.profile_id<>auth.uid() and p.active and p.status='active'
        and p.role in('manager','admin') order by c.depth limit 1;
  end if;

  if head is null then raise exception 'حدد معتمدًا أعلى مستقلًا عن مقدم الطلب في الهيكل أو إعدادات المسار'; end if;
  select jsonb_build_object('hr_id',s.hr_id,'finance_id',s.finance_id,'approver_id',s.approver_id,
    'recruiter_id',s.recruiter_id,'development_id',s.development_id,'department_approver_id',head,
    'supervisor_id',auth.uid(),'manager_id',employee.id) into route
    from private.recruitment_route_settings s where singleton;
  for item in select * from (values('hr_id','recruitment.personnel'),('finance_id','recruitment.finance'),('approver_id','recruitment.approve'),('recruiter_id','recruitment.manage'),('development_id','recruitment.development')) t(field,permission) loop
    if not exists(select 1 from public.profiles p where p.id=(route->>item.field)::uuid and p.active and p.status='active' and (p.role='admin' or ('recruitment'=any(p.allowed_modules) and item.permission=any(p.permissions)))) then
      raise exception 'إعدادات مسار التوظيف غير مكتملة أو صلاحية مسؤول المرحلة غير فعالة؛ راجع مسؤول النظام';
    end if;
  end loop;
  if not exists(select 1 from public.profiles p where p.id=head and p.active and p.status='active' and (p.role='admin' or 'recruitment'=any(p.allowed_modules)))then raise exception 'مدير الإدارة في الهيكل غير مخول لوحدة التوظيف؛ يلزم تفعيل وصوله دون تجاوز مرحلته';end if;
  return route || jsonb_build_object('interviewer_ids',(select jsonb_agg(x) from (select distinct unnest(array[auth.uid(),head]) x) owners));
exception when no_data_found or too_many_rows then
  raise exception 'يلزم ربط الحساب بملف موظف واحد قبل إنشاء الطلب' using errcode='42501';
end $function$;

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
for v in select * from(values('hr_id','recruitment.personnel'),('finance_id','recruitment.finance'),('recruiter_id','recruitment.manage'),('approver_id','recruitment.approve'),('development_id','recruitment.development'),('department_approver_id',null),('supervisor_id',null))x(field,permission)loop
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
perform private.recruitment_event(rid,null,'request_created','حفظ مسودة احتياج');return rid;end$function$;

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
 permission:=case field when 'hr_id'then 'recruitment.personnel'when 'finance_id'then 'recruitment.finance'when 'approver_id'then 'recruitment.approve'when 'recruiter_id'then 'recruitment.manage'when 'development_id'then 'recruitment.development'when 'department_approver_id'then 'manager'else null end;
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
  when t.key like 'offer:%'then coalesce((select case o.state when 'hr_review'then r.hr_id when 'department_review'then r.department_approver_id when 'development_review'then r.development_id when 'approval'then r.approver_id else r.recruiter_id end from private.recruitment_offers o where t.key='offer:'||o.id),t.owner_id)
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
if(r.status='hr_review'and not private.recruitment_permission('recruitment.personnel'))or(r.status='finance_review'and not private.recruitment_permission('recruitment.finance'))or(r.status='hr_exception'and not private.recruitment_permission('recruitment.development'))or(r.status in('approval','finance_exception','cancellation_approval')and not private.recruitment_permission('recruitment.approve'))then raise exception 'لا تملك صلاحية المرحلة'using errcode='42501';end if;
if length(note)<3 then raise exception 'وثق القرار';end if;
if r.status='cancellation_approval'then n:=case p_action when 'approve'then 'cancelled'else r.cancel_previous_state end;
elsif p_action='reject'then n:=case r.status when 'finance_review'then 'finance_exception'when 'hr_review'then 'hr_exception'else 'rejected'end;
else
if r.status='finance_review'and p_action='approve'and p_data->>'budget_checked' is distinct from 'true' then raise exception 'أكد مراجعة الموازنة';end if;
if r.status='hr_review'and(p_data->>'need_checked'is distinct from 'true'or p_data->>'vacancy_checked'is distinct from 'true'or p_data->>'request_type_checked'is distinct from 'true'or p_data->>'saudization_checked'is distinct from 'true'or p_data->>'profession_checked'is distinct from 'true')then raise exception 'أكد نوع الطلب وخطة التوطين وأهلية المهنة';end if;
n:=case r.status when 'department_review'then 'finance_review'when 'hr_review'then 'approval'when 'hr_exception'then 'approval'when 'finance_review'then 'hr_review'when 'approval'then 'open'when 'finance_exception'then 'hr_review'end;end if;
update private.recruitment_requests set status=n,rejected_stage=case when n='rejected'then r.status else rejected_stage end,checks=case when r.status in('hr_review','finance_review')and p_action='approve'then checks||p_data else checks end,published=false where id=r.id;
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
update private.recruitment_requests set revision=revision+1,updated_at=now()where id=r.id;perform private.recruitment_event(r.id,null,'request_'||p_action,note);end$function$;

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
update private.recruitment_offers set state='hr_review',stage_started_at=now() where id=oid;
update private.recruitment_applications set stage='offer',revision=revision+1,updated_at=now()where id=a.id;perform private.recruitment_event(r.id,a.id,'offer_created',coalesce(p_data->>'change_reason','إعداد أول عرض'));return oid;end$function$;

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
owner:=case o.state when 'hr_review'then r.hr_id when 'department_review'then r.department_approver_id when 'development_review'then r.development_id when 'approval'then r.approver_id end;
if p_action in('approve','reject')and auth.uid()=owner and((o.state='hr_review'and private.recruitment_permission('recruitment.personnel'))or(o.state='department_review'and auth.uid()=r.department_approver_id)or(o.state='development_review'and private.recruitment_permission('recruitment.development'))or(o.state='approval'and private.recruitment_permission('recruitment.approve')))then
n:=case when p_action='reject'then case when o.state='hr_review'then 'development_review'else 'returned'end when o.state='hr_review'then case when o.exception_required then 'development_review'else 'department_review'end when o.state='development_review'then 'department_review'when o.state='department_review'then 'approval'else 'approved'end;
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
perform private.recruitment_event(r.id,a.id,'offer_'||n,p_note);end$function$;

CREATE OR REPLACE FUNCTION private.recruitment_offer_clock()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$declare a private.recruitment_applications;r private.recruitment_requests;owner uuid;begin
if tg_op='INSERT'or new.state is distinct from old.state then select * into a from private.recruitment_applications where id=new.application_id;select * into r from private.recruitment_requests where id=a.request_id;update private.recruitment_tasks set done=true where key in('offer:'||new.id,'prepare:'||a.id);
owner:=case new.state when 'hr_review'then r.hr_id when 'department_review'then r.department_approver_id when 'development_review'then r.development_id when 'approval'then r.approver_id when 'returned'then r.recruiter_id when 'approved'then r.recruiter_id end;
if owner is not null then perform private.recruitment_task('offer:'||new.id,r.id,a.id,owner,'متابعة العرض الوظيفي',2);if owner is distinct from auth.uid()then insert into public.notifications(recipient_id,type,title,message)values(owner,'RECRUITMENT','عرض وظيفي بانتظار إجرائك','افتح وحدة التوظيف لمراجعة العرض أو استكماله.');end if;end if;end if;return new;end$function$;

CREATE OR REPLACE FUNCTION private.recruitment_list()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$declare result jsonb;begin result:=private.recruitment_list_v1();return result||jsonb_build_object('tasks',(select coalesce(jsonb_agg(to_jsonb(t)order by due_at),'[]')from private.recruitment_tasks t where not done and private.recruitment_visible(request_id)),'offer_queue',(select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'application_id',a.id,'request_id',r.id,'candidate_name',c.full_name,'job_title',r.job_snapshot->>'title','state',o.state,'version',o.version)),'[]')from private.recruitment_offers o join private.recruitment_applications a on a.id=o.application_id join private.recruitment_requests r on r.id=a.request_id join private.recruitment_candidates c on c.id=a.candidate_id where private.recruitment_visible(r.id)and((o.state='hr_review'and r.hr_id=auth.uid())or(o.state='department_review'and r.department_approver_id=auth.uid())or(o.state='development_review'and r.development_id=auth.uid())or(o.state='approval'and r.approver_id=auth.uid())or(o.state in('approved','returned','sent')and r.recruiter_id=auth.uid()))));end$function$;

CREATE OR REPLACE FUNCTION private.recruitment_detail(p_request uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$declare result jsonb;pay boolean;begin result:=private.recruitment_detail_v1(p_request);pay:=coalesce((result->>'can_pay')::boolean,false) or exists(select 1 from private.recruitment_requests where id=p_request and hr_id=auth.uid()and private.recruitment_permission('recruitment.personnel')) or exists(select 1 from private.recruitment_requests where id=p_request and department_approver_id=auth.uid()) or exists(select 1 from private.recruitment_requests where id=p_request and development_id=auth.uid() and private.recruitment_permission('recruitment.development'));return result||jsonb_build_object('request',(select case when pay then to_jsonb(r) else to_jsonb(r)-'salary_snapshot'-'salary_id' end from private.recruitment_requests r where id=p_request),'can_pay',pay,'offers',case when pay then(select coalesce(jsonb_agg(to_jsonb(o)order by o.created_at desc),'[]')from private.recruitment_offers o join private.recruitment_applications a on a.id=o.application_id where a.request_id=p_request)else '[]'::jsonb end,'batches',(select coalesce(jsonb_agg(to_jsonb(b)order by number),'[]')from private.recruitment_batches b where request_id=p_request),'documents',(select coalesce(jsonb_agg(to_jsonb(d)order by d.created_at desc),'[]')from private.recruitment_documents d join private.recruitment_applications a on a.id=d.application_id where a.request_id=p_request),'updates',(select coalesce(jsonb_agg(to_jsonb(u)order by u.created_at desc),'[]')from private.recruitment_candidate_updates u join private.recruitment_applications a on a.id=u.application_id where a.request_id=p_request),'tasks',(select coalesce(jsonb_agg(to_jsonb(t)order by t.due_at),'[]')from private.recruitment_tasks t where request_id=p_request and not done),'previous_interviews',(select coalesce(jsonb_agg(to_jsonb(i)||jsonb_build_object('candidate_id',a.candidate_id)),'[]')from private.recruitment_interviews i join private.recruitment_applications a on a.id=i.application_id where a.request_id<>p_request and exists(select 1 from private.recruitment_applications current_app where current_app.request_id=p_request and current_app.candidate_id=a.candidate_id)));end$function$;

commit;
