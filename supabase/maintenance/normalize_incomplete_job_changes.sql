-- Technical repair only: no content decision, no job/KPI content edits.
-- Existing audit and task triggers archive the transition and close obsolete review tasks.
begin;
do $$
declare r public.employee_job_change_requests%rowtype; invalid boolean; note text; jobs_before text; source_before text;
begin
 select md5(string_agg(to_jsonb(j)::text,'|' order by id)) into jobs_before from public.job_descriptions j;
 select md5(string_agg(jsonb_build_array(id,job_description_id,requester_id,manager_id,section,action,item_index,original_value,proposed_value,reason,published_revision)::text,'|' order by id)) into source_before from public.employee_job_change_requests;
 for r in select * from public.employee_job_change_requests
   where status in ('MANAGER_REVIEW','ADMIN_REVIEW') for update loop
  invalid:=false;
  begin
   perform private.validate_job_change_value(r.section,r.action,r.original_value,r.proposed_value);
  exception when raise_exception then invalid:=true;
  end;
  if invalid then
   note:='تصحيح إجرائي: التعديل المطلوب غير مكتمل. حدد القسم والبند والتغيير المطلوب ثم أرسله لصاحب القرار. التعليقات السابقة محفوظة في سجل الطلب ولا تمثل اعتمادًا لتعديل غير محدد.';
  elsif r.status='ADMIN_REVIEW' and (r.manager_decided_at is null or r.approval_snapshot is distinct from
    jsonb_build_object('section',r.section,'action',r.action,'index',r.item_index,'original',r.original_value,'proposed',r.proposed_value,'impact',r.impact_note)) then
   note:='تصحيح إجرائي: لا يوجد اعتماد موثق للصيغة الحالية. راجع التغيير وأعد إرساله لصاحب القرار. التعليقات السابقة محفوظة في السجل.';
  else continue;
  end if;
  insert into public.employee_job_change_events(request_id,action,note,snapshot)
    values(r.id,'حفظ الطلب قبل تصحيح الحالة','حفظ الحالة والتعليقات السابقة قبل إعادة الطلب للاستكمال؛ لم يتخذ قرار محتوى.',to_jsonb(r));
  update public.employee_job_change_requests set status='NEEDS_CHANGES',
    manager_note=null,manager_decided_at=null,approval_snapshot=null,prepared_snapshot=null,
    admin_note=note,admin_decided_at=null,version=version+1,updated_at=now() where id=r.id;
 end loop;
 if jobs_before is distinct from (select md5(string_agg(to_jsonb(j)::text,'|' order by id)) from public.job_descriptions j) then raise exception 'Repair changed a job description';end if;
 if source_before is distinct from (select md5(string_agg(jsonb_build_array(id,job_description_id,requester_id,manager_id,section,action,item_index,original_value,proposed_value,reason,published_revision)::text,'|' order by id)) from public.employee_job_change_requests) then raise exception 'Repair changed request content or ownership';end if;
end $$;
commit;
