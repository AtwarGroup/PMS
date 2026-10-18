begin;
alter table public.employee_job_change_requests drop constraint employee_job_change_requests_status_check;
alter table public.employee_job_change_requests add constraint employee_job_change_requests_status_check check(status in ('MANAGER_REVIEW','ADMIN_REVIEW','APPLIED','PUBLISHED','REJECTED','STALE','NEEDS_CHANGES','ARCHIVED'));
alter table public.employee_job_change_requests add column archived_at timestamptz, add column archive_reason text, add column archive_snapshot jsonb, add column replaced_by_job_id uuid references public.job_descriptions(id);
alter table public.job_description_change_requests drop constraint job_change_status_check;
alter table public.job_description_change_requests add constraint job_change_status_check check(status in ('PENDING','ACCEPTED','REJECTED','REVISED','ARCHIVED'));
alter table public.job_description_change_requests add column archived_at timestamptz, add column archive_snapshot jsonb;

-- Archived requests cannot re-enter approval, and active requests must match the current binding.
create function private.guard_employee_change_assignment() returns trigger language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare current_job uuid;
begin
 if tg_op='UPDATE' and old.status='ARCHIVED' then raise exception 'الطلب مؤرشف لانتهاء الربط السابق';end if;
 if new.status in ('MANAGER_REVIEW','ADMIN_REVIEW','NEEDS_CHANGES','STALE','APPLIED') then
  select coalesce(a.job_description_id,p.job_description_id) into current_job from public.profiles p left join public.employee_job_assignments a on a.profile_id=p.id where p.id=new.requester_id;
  if current_job is distinct from new.job_description_id then raise exception 'الوصف لم يعد مرتبطًا بالموظف؛ استخدم الربط الحالي';end if;
 end if;return new;
end $$;
revoke all on function private.guard_employee_change_assignment() from public,anon,authenticated;
create trigger guard_employee_change_assignment before insert or update on public.employee_job_change_requests for each row execute function private.guard_employee_change_assignment();

-- Assignment-stage owners may hide only internally cancelled workflow tasks.
do $$ declare d text;begin
 select pg_get_functiondef('private.enforce_task_delete_ownership()'::regprocedure) into d;
 if position('  if tg_op = ''UPDATE'' then' in d)=0 then raise exception 'Task guard patch target missing';end if;
 d:=replace(d,'  if tg_op = ''UPDATE'' then',$patch$  if tg_op='UPDATE' and pg_trigger_depth()>1 and old.task_type='job_workflow' and new.delete_reason='تم تغيير ربط الوصف الوظيفي' and private.can_job_stage('ASSIGN') then return new;end if;
  if tg_op = 'UPDATE' then$patch$);execute d;
 select pg_get_functiondef('private.sync_employee_job_change_tasks()'::regprocedure) into d;
 if position('begin' in d)=0 then raise exception 'Request task patch target missing';end if;
 d:=replace(d,'begin',$patch$begin
 if new.status='ARCHIVED' then
  update public.tasks set deleted_at=now(),delete_reason='تم تغيير ربط الوصف الوظيفي',revision=revision+1,updated_at=now()
   where id in(new.manager_task_id,new.admin_task_id) and status<>'مكتملة' and deleted_at is null;
  delete from public.notifications where task_id in(new.manager_task_id,new.admin_task_id);
  return new;
 end if;$patch$);execute d;
 select pg_get_functiondef('private.prepare_job_change_request()'::regprocedure) into d;
 d:=replace(d,'begin',$patch$begin
 if tg_op='UPDATE' and old.status='ARCHIVED' then raise exception 'المقترح مؤرشف';end if;
 if tg_op='UPDATE' and new.status='ARCHIVED' and (private.is_admin() or (pg_trigger_depth()>1 and private.can_job_stage('ASSIGN'))) then
  new.archived_at:=now();new.archive_snapshot:=to_jsonb(old);new.admin_decision_by:=null;new.admin_decision_at:=null;new.updated_at:=now();return new;
 end if;$patch$);execute d;
end $$;

create function private.archive_previous_employee_job(p_employee uuid,p_old_job uuid,p_new_job uuid,p_reason text)
returns void language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare r public.employee_job_change_requests%rowtype;j public.job_descriptions%rowtype; ids uuid[]; phase text;
begin
 if auth.uid() is not null and not(private.can_job_stage('ASSIGN') or private.is_admin()) then raise exception 'Job assignment permission required' using errcode='42501';end if;
 if p_old_job is null or p_old_job is not distinct from p_new_job then return;end if;
 select * into j from public.job_descriptions where id=p_old_job for update;
 if not found then return;end if;
 for r in select * from public.employee_job_change_requests where requester_id=p_employee and job_description_id=p_old_job and status<>'ARCHIVED' order by id for update loop
  ids:=array_append(ids,r.id);
  insert into public.employee_job_change_events(request_id,action,actor_id,note,snapshot) values(r.id,'أرشفة بسبب انتهاء الربط',auth.uid(),p_reason,to_jsonb(r));
  update public.employee_job_change_requests set archive_snapshot=to_jsonb(r),archived_at=now(),archive_reason=p_reason,replaced_by_job_id=p_new_job,status='ARCHIVED',approval_snapshot=null,prepared_snapshot=null,manager_decided_at=null,manager_note=null,admin_note=p_reason,version=version+1,updated_at=now() where id=r.id;
 end loop;
 -- A surviving linked proposal requires a new decision after part of its group is retired.
 for r in select * from public.employee_job_change_requests where status in ('MANAGER_REVIEW','ADMIN_REVIEW','NEEDS_CHANGES','STALE') and related_request_ids && ids order by id for update loop
  insert into public.employee_job_change_events(request_id,action,actor_id,note,snapshot) values(r.id,'تغير ربط طلب مرتبط',auth.uid(),p_reason,to_jsonb(r));
  update public.employee_job_change_requests set related_request_ids=array(select x from unnest(r.related_request_ids) x where not(x=any(ids))),status='NEEDS_CHANGES',approval_snapshot=null,prepared_snapshot=null,manager_decided_at=null,manager_note=null,admin_note='أُرشف طلب مرتبط بعد تغيير الربط؛ راجع التعديل قبل إعادة القرار.',version=version+1,updated_at=now() where id=r.id;
 end loop;
 perform private.close_job_workflow_tasks(p_old_job,'EMPLOYEE_ACK',p_employee,null,true);
 -- Shared descriptions keep the review that still belongs to their remaining employees.
 if not exists(select 1 from public.profiles p left join public.employee_job_assignments a on a.profile_id=p.id where coalesce(a.job_description_id,p.job_description_id)=p_old_job) then
  update public.job_description_change_requests set status='ARCHIVED',archived_at=now(),archive_snapshot=to_jsonb(job_description_change_requests) where job_description_id=p_old_job and status<>'ARCHIVED';
  update public.job_publication_schedules set status='CANCELLED',cancelled_by=auth.uid(),note=p_reason where job_description_id=p_old_job and status in ('PENDING','BLOCKED');
  update public.job_periodic_reviews set enabled=false,revision=revision+1,updated_at=now() where job_description_id=p_old_job and enabled;
  foreach phase in array array['MANAGER_REVIEW','ADMIN_APPROVAL','PUBLISH','FINAL_REVIEW','DRAFT_REVISION','PERIODIC_REVIEW'] loop
   perform private.close_job_workflow_tasks(p_old_job,phase,null,null,true);
  end loop;
  if j.status in ('IN_REVIEW','CHANGES_REQUESTED','MANAGER_APPROVED') then
   update public.job_descriptions set status='DRAFT',submitted_at=null,manager_approved_at=null,manager_approved_by=null,final_reviewed_at=null,final_reviewed_by=null,review_note=p_reason where id=p_old_job;
  end if;
 end if;
end $$;
revoke all on function private.archive_previous_employee_job(uuid,uuid,uuid,text) from public,anon,authenticated;

create function private.archive_replaced_job_assignment() returns trigger language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare next_job uuid;previous_job uuid;employee uuid;other_job uuid;
begin
 if tg_op='UPDATE' and new.job_description_id is not distinct from old.job_description_id then return new;end if;
 if tg_op='DELETE' then
  employee:=old.profile_id;previous_job:=old.job_description_id;
  select job_description_id into next_job from public.profiles where id=employee;
 else
  employee:=new.profile_id;next_job:=new.job_description_id;
  if tg_op='UPDATE' then previous_job:=old.job_description_id;
  else select job_description_id into previous_job from public.profiles where id=employee;end if;
 end if;
 for other_job in select previous_job where previous_job is not null
  union select job_description_id from public.employee_job_change_requests where requester_id=employee and status<>'ARCHIVED' and job_description_id is distinct from next_job
  union select w.job_description_id from private.job_workflow_tasks w join public.tasks t on t.id=w.task_id where w.phase='EMPLOYEE_ACK' and w.recipient_id=employee and w.job_description_id is distinct from next_job and t.deleted_at is null and t.status<>'مكتملة'
 loop
  perform private.archive_previous_employee_job(employee,other_job,next_job,'أُرشف الطلب وأُلغيت إجراءاته لانتهاء الربط السابق بالوصف الوظيفي.');
 end loop;
 if tg_op='DELETE' then return old;end if;return new;
end $$;
revoke all on function private.archive_replaced_job_assignment() from public,anon,authenticated;
create trigger archive_replaced_job_assignment after insert or update of job_description_id or delete on public.employee_job_assignments for each row execute function private.archive_replaced_job_assignment();

-- Legacy profile bindings are used only when the assignment table has no current binding.
create function private.archive_replaced_profile_job() returns trigger language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare j public.job_descriptions%rowtype;
begin
 if new.job_description_id is not distinct from old.job_description_id or exists(select 1 from public.employee_job_assignments where profile_id=new.id) then return new;end if;
 if not private.can_job_stage('ASSIGN') then raise exception 'Job assignment permission required' using errcode='42501';end if;
 perform private.archive_previous_employee_job(new.id,old.job_description_id,new.job_description_id,'أُرشف الطلب وأُلغيت إجراءاته بعد تغيير الربط في ملف الموظف.');
 select * into j from public.job_descriptions where id=new.job_description_id;
 if j.status<>'ARCHIVED' and j.published_snapshot is not null then perform private.ensure_job_workflow_task(j,'EMPLOYEE_ACK',j.published_snapshot->>'revision',new.id);end if;
 return new;
end $$;
revoke all on function private.archive_replaced_profile_job() from public,anon,authenticated;
create trigger archive_replaced_profile_job after update of job_description_id on public.profiles for each row execute function private.archive_replaced_profile_job();
do $qa$
declare a uuid;m uuid;e uuid;old_job uuid:=gen_random_uuid();new_job uuid:=gen_random_uuid();jid uuid;kpi jsonb;snap jsonb;rid uuid;new_rid uuid;req public.employee_job_change_requests%rowtype;v integer;
begin
 select id into a from public.profiles where email='e2e-admin@atwargroup.test' and active;
 select id into m from public.profiles where email='e2e-manager@atwargroup.test' and active;
 select id into e from public.profiles where email='e2e-employee@atwargroup.test' and active;
 if a is null or m is null or e is null then raise exception 'QA accounts required';end if;
 begin
  perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated')::text,true);
  kpi:=jsonb_build_object('name','QA lifecycle KPI','measure','QA formula','unit','%','target','95%','source','QA source','frequency','monthly','weight',100,'scale',(select jsonb_agg(jsonb_build_object('score',i,'label','QA '||i)) from generate_series(1,5) i));
  foreach jid in array array[old_job,new_job] loop
   insert into public.job_descriptions(id,job_code,title,family,job_level,purpose,content,reviewer_mode,reviewer_id,reference_profile_id)
   values(jid,'JOB-'||(900000000+floor(random()*99999999)::bigint)::text,'QA lifecycle assignment','QA','QA','QA purpose with enough detail to pass the complete description validation.',jsonb_build_object('responsibilities',jsonb_build_array(jsonb_build_object('text','QA responsibility')),'authorities',jsonb_build_array(jsonb_build_object('text','QA authority')),'kpis',jsonb_build_array(kpi),'reports',jsonb_build_array(jsonb_build_object('name','QA report')),'qualifications',jsonb_build_object('education','QA education')),'auto',m,e);
   update public.job_descriptions set status='IN_REVIEW' where id=jid;
   update public.job_descriptions set status='MANAGER_APPROVED' where id=jid;
   perform public.finish_job_final_review(jid);
   update public.job_descriptions set status='PUBLISHED' where id=jid;
  end loop;
  insert into public.employee_job_assignments(profile_id,job_description_id,assigned_by) values(e,old_job,a) on conflict(profile_id) do update set job_description_id=excluded.job_description_id;
  select published_snapshot into snap from public.job_descriptions where id=old_job;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',e,'role','authenticated')::text,true);
  rid:=public.submit_employee_job_change_structured(old_job,(snap->>'revision')::int,'KPIS','MODIFY',0,kpi||'{"target":"97%"}','QA lifecycle proposal','',gen_random_uuid());
  select version into v from public.employee_job_change_requests where id=rid;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',m,'role','authenticated')::text,true);
  perform public.review_employee_job_change(rid,v,'APPROVE','QA approval before reassignment');
  perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated')::text,true);
  update public.job_descriptions set status='IN_REVIEW' where id=old_job;
  update public.employee_job_assignments set job_description_id=new_job where profile_id=e;
  select * into req from public.employee_job_change_requests where id=rid;
  if req.status<>'ARCHIVED' or req.archive_snapshot->>'status'<>'ADMIN_REVIEW' or req.approval_snapshot is not null or req.manager_decided_at is not null or req.replaced_by_job_id<>new_job then raise exception 'QA FAILED: old approval not archived';end if;
  if (select status from public.job_descriptions where id=old_job)<>'DRAFT' then raise exception 'QA FAILED: old manager review still active';end if;
  if exists(select 1 from public.tasks where deleted_at is null and status<>'مكتملة' and legacy_metadata#>>'{job_workflow,job_id}'=old_job::text) then raise exception 'QA FAILED: old workflow task still active';end if;
  if not exists(select 1 from public.tasks where deleted_at is null and status<>'مكتملة' and legacy_metadata#>>'{job_workflow,job_id}'=new_job::text and legacy_metadata#>>'{job_workflow,phase}'='EMPLOYEE_ACK' and assignee_id=e) then raise exception 'QA FAILED: new acknowledgement missing';end if;
  if (select published_snapshot from public.job_descriptions where id=old_job)<>snap then raise exception 'QA FAILED: published source changed';end if;
  begin
   update public.employee_job_change_requests set status='MANAGER_REVIEW' where id=rid;
   raise exception 'QA FAILED: archived request reopened';
  exception when raise_exception or insufficient_privilege then if sqlerrm like 'QA FAILED:%' then raise;end if;end;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',e,'role','authenticated')::text,true);
  begin
   perform public.submit_employee_job_change_structured(old_job,(snap->>'revision')::int,'KPIS','MODIFY',0,kpi||'{"target":"99%"}','QA old role should fail','',gen_random_uuid());
   raise exception 'QA FAILED: request on old binding accepted';
  exception when raise_exception or insufficient_privilege then if sqlerrm like 'QA FAILED:%' then raise;end if;end;
  select published_snapshot into snap from public.job_descriptions where id=new_job;
  new_rid:=public.submit_employee_job_change_structured(new_job,(snap->>'revision')::int,'KPIS','MODIFY',0,kpi||'{"target":"99%"}','QA current role remains active','',gen_random_uuid());
  perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated')::text,true);
  update public.employee_job_assignments set job_description_id=new_job where profile_id=e;
  if (select status from public.employee_job_change_requests where id=new_rid)<>'MANAGER_REVIEW' then raise exception 'QA FAILED: same binding archived a current request';end if;
  -- A shared previous job keeps another employee acknowledgement and its content.
  insert into public.employee_job_assignments(profile_id,job_description_id,assigned_by) values(m,new_job,a) on conflict(profile_id) do update set job_description_id=excluded.job_description_id;
  update public.employee_job_assignments set job_description_id=old_job where profile_id=e;
  if (select status from public.job_descriptions where id=new_job)<>'PUBLISHED' then raise exception 'QA FAILED: shared description changed';end if;
  if not exists(select 1 from public.tasks where deleted_at is null and status<>'مكتملة' and assignee_id=m and legacy_metadata#>>'{job_workflow,job_id}'=new_job::text and legacy_metadata#>>'{job_workflow,phase}'='EMPLOYEE_ACK') then raise exception 'QA FAILED: another employee acknowledgement cancelled';end if;
  raise exception 'QA_ROLLBACK_ASSIGNMENT_LIFECYCLE';
 exception when raise_exception then if sqlerrm<>'QA_ROLLBACK_ASSIGNMENT_LIFECYCLE' then raise;end if;end;
 if exists(select 1 from public.job_descriptions where id in(old_job,new_job)) then raise exception 'QA cleanup failed';end if;
end $qa$;

commit;
