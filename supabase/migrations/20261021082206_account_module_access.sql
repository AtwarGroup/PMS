-- Unit access is independent of record permissions. Existing accounts keep their access.
create table private.app_modules(key text primary key,label text not null,icon text not null,path text not null,ready boolean not null default true,position integer not null);
insert into private.app_modules values
('tasks','المهام','square-check-big','tasks/index.html',true,10),
('workspace','مساحتي','notebook-tabs','workspace/index.html',true,20),
('projects','إدارة المشاريع','chart-gantt','projects/index.html',true,30),
('policies','مكتبة السياسات','book-open-check','policies/index.html',true,40),
('communication','التواصل','messages-square','communication/index.html',true,50),
('employees','الموظفون','contact-round','admin/employees.html',true,60),
('job_library','مكتبة الوظائف','library-big','job-library/index.html',true,70),
('fleet','أسطول السيارات','truck','fleet/index.html',false,80);
alter table private.app_modules enable row level security;
revoke all on private.app_modules from public,anon,authenticated;
create policy modules_internal_only on private.app_modules to authenticated using(false)with check(false);
alter table public.profiles add column allowed_modules text[] not null default array['tasks','workspace','projects','policies','communication','employees','job_library'],add column module_revision integer not null default 1;
-- Keep the previous ready-unit default for older creation clients during rollout.
-- The activation form and Edge Function always submit the explicit checkbox selection.
create function private.module_allowed(p_module text)returns boolean language sql stable security definer set search_path=pg_catalog,public,private as $$
 select exists(select 1 from public.profiles p join private.app_modules m on m.key=p_module and m.ready where p.id=auth.uid()and p.active and p.status='active'and(p.role='admin'or p_module=any(p.allowed_modules)))
$$;
create function private.require_module(p_module text)returns void language plpgsql stable security definer set search_path=pg_catalog,private as $$
begin
 if not private.module_allowed(p_module) then raise exception 'ATWAR_MODULE_DENIED: لا تملك صلاحية استخدام هذه الوحدة' using errcode='42501';end if;
end$$;
create function private.validate_module_keys(p_modules text[])returns void language plpgsql stable security definer set search_path=pg_catalog,private as $$
begin
 if p_modules is null or cardinality(p_modules)>30 or exists(select 1 from unnest(p_modules)k where k is null or not exists(select 1 from private.app_modules m where m.key=k and m.ready))then raise exception 'وحدات الحساب غير صالحة'using errcode='22023';end if;
end$$;
create function private.guard_profile_modules()returns trigger language plpgsql security invoker set search_path=pg_catalog,public,private as $$
begin
 if tg_op='INSERT'or new.allowed_modules is distinct from old.allowed_modules then
  if current_user in('authenticated','anon')and not private.is_admin()then raise exception 'Administrator access required'using errcode='42501';end if;
  perform private.validate_module_keys(new.allowed_modules);
  new.allowed_modules:=array(select distinct k from unnest(new.allowed_modules)k order by k);
  if tg_op='UPDATE'then new.module_revision:=old.module_revision+1;end if;
 elsif tg_op='UPDATE'then new.module_revision:=old.module_revision+case when (new.role,new.active,new.status)is distinct from(old.role,old.active,old.status)then 1 else 0 end;end if;
 return new;
end$$;
create trigger guard_profile_modules before insert or update on public.profiles for each row execute function private.guard_profile_modules();
create function private.account_module_context()returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,private as $$
declare p public.profiles%rowtype;begin
 select * into p from public.profiles where id=auth.uid()and active and status='active';
 if not found then raise exception 'Authentication required'using errcode='42501';end if;
 return jsonb_build_object('profile_id',p.id,'role',p.role,'revision',p.module_revision,'allowed',case when p.role='admin'then array(select key from private.app_modules where ready order by position)else p.allowed_modules end,'catalog',(select jsonb_agg(to_jsonb(m)order by position)from private.app_modules m));
end$$;
create function public.account_module_context()returns jsonb language sql security invoker set search_path=pg_catalog,private as $$select private.account_module_context()$$;
create function private.account_access_save(p_profile uuid,p_role text,p_active boolean,p_modules text[],p_revision integer)returns void language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare p public.profiles%rowtype;begin
 if not private.is_admin()then raise exception 'Administrator access required'using errcode='42501';end if;
 perform private.validate_module_keys(p_modules);
 select * into strict p from public.profiles where id=p_profile for update;
 if p_revision is distinct from p.module_revision then raise exception 'تم تعديل الحساب. حدّث البيانات ثم أعد المحاولة.'using errcode='40001';end if;
 perform private.access_account_update(p_profile,p_role,p_active);
 update public.profiles set allowed_modules=p_modules where id=p_profile;
 if p.allowed_modules is distinct from array(select distinct k from unnest(p_modules)k order by k)then
 perform private.access_log('MODULE_ACCESS_CHANGED',p_profile::text,to_jsonb(p.allowed_modules),to_jsonb(p_modules));end if;
end$$;
create function public.account_access_save(p_profile uuid,p_role text,p_active boolean,p_modules text[],p_revision integer)returns void language sql security invoker set search_path=pg_catalog,private as $$select private.account_access_save(p_profile,p_role,p_active,p_modules,p_revision)$$;
-- Extend the current directory rather than create another account data source.
do $$declare d text;begin
 select pg_get_functiondef('private.access_admin_context()'::regprocedure)into d;
 d:=replace(d,'''permissions'',p.permissions','''permissions'',p.permissions,''allowed_modules'',p.allowed_modules,''module_revision'',p.module_revision');
 d:=replace(d,'''catalog'',','''module_catalog'',(select coalesce(jsonb_agg(to_jsonb(m)order by position),''[]'')from private.app_modules m),''catalog'',');
 execute d;
end$$;
-- Record-level boundaries also apply to definer RPCs and attachment access checks.
create function private.module_task_allowed(p_task uuid)returns boolean language sql stable security definer set search_path=pg_catalog,public,private as $$
 select exists(select 1 from public.tasks t where t.id=p_task and (private.module_allowed('tasks')or(t.project_id is not null and private.module_allowed('projects'))))
$$;
do $$declare f record;d text;b text;begin
 for f in select p.oid,p.proname,p.prosrc from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private'and p.proname in('can_view_task','can_modify_task','can_delete_task','policy_worker','policy_visible_version','hr_allowed')loop
 b:=case when f.proname like 'can_%_task'then 'private.module_task_allowed($1)'when f.proname like 'project_%'then 'private.module_allowed(''projects'')'when f.proname like 'policy_%'then 'private.module_allowed(''policies'')'else 'private.module_allowed(''employees'')'end;
 d:=pg_get_functiondef(f.oid);d:=replace(d,f.prosrc,'select '||b||' and ('||regexp_replace(f.prosrc,'[;\s]+$','','g')||')');execute d;
 end loop;
end$$;
-- Restrictive policies intersect existing ownership/membership policies, never replace them.
do $$declare t text;k text;begin
 foreach t in array array['tasks','subtasks','task_activity','task_comments','task_attachments','task_reschedule_requests','task_followup_details','recurring_task_templates','task_batches','task_batch_attachments','task_attachment_cleanup','quick_notes','follow_ups','improvement_proposals','improvement_events','projects','project_members','project_phases','project_dependencies','project_messages','project_events','project_risks','project_files','project_baselines','policies','policy_versions','policy_comments','policy_events']loop
 k:=case when t in('quick_notes','follow_ups','improvement_proposals','improvement_events')then 'workspace'when t='projects'or t like 'project_%'then 'projects'when t='policies'or t like 'policy_%'then 'policies'else 'tasks'end;
 if t='tasks'then execute 'create policy module_boundary on public.tasks as restrictive to authenticated using(private.module_task_allowed(id))with check(private.module_allowed(''tasks'')or(project_id is not null and private.module_allowed(''projects'')))';
 elsif k='tasks'then execute format('create policy module_boundary on public.%I as restrictive to authenticated using((select private.module_allowed(''tasks'')or private.module_allowed(''projects'')))with check((select private.module_allowed(''tasks'')or private.module_allowed(''projects'')))',t);
 else execute format('create policy module_boundary on public.%I as restrictive to authenticated using((select private.module_allowed(%L)))with check((select private.module_allowed(%L)))',t,k,k);end if;
 end loop;
end$$;
-- Guard existing RPC entry points while preserving their OIDs, arguments, defaults and original authorization.
-- A nested PL/pgSQL block keeps existing exception/declaration scopes intact.
do $guard$
declare f record;d text;b text;k text;hdr text;body text;begin
 for f in select p.*,l.lanname,n.nspname,pg_get_function_result(p.oid) result from pg_proc p join pg_namespace n on n.oid=p.pronamespace join pg_language l on l.oid=p.prolang where n.nspname='public'and p.prorettype<>'trigger'::regtype and has_function_privilege('authenticated',p.oid,'execute')and (
 p.proname=any(array['create_task_safe','import_tasks_safe','list_deleted_tasks','search_tasks_safe','set_task_sla','update_task_safe','cancel_task_safe','resolve_task_date_issue','restore_task_safe','run_recurring_tasks_safe','delete_task_safe','update_task_with_subtasks_safe','decide_task_reschedule','delegate_task_safe','task_followup_context','save_task_followup','request_task_reschedule','task_batch_directory','create_task_batch_safe','task_batch_report','record_executive_task_access','communication_task_command','communication_trial_task_command'])
 or p.proname like 'workspace_%'or p.proname in('improvement_command','improvement_execution')
 or p.proname like 'project_%'or p.proname='capture_project_baseline'
 or p.proname like 'policy_%'or p.proname like 'employee_master_%'or p.proname='get_team_employee_job'
 or p.proname in('communication_notification_open','communication_trial_notification_open','communication_assignees','communication_task_sources')
 or p.proname=any(array['get_job_publication_impact','cancel_job_effective_date','save_job_periodic_review','approve_job_effective_date','complete_job_periodic_review','request_job_periodic_change','job_administrative_exemptions','job_stage_directory','set_job_stage_owner','complete_job_description_review','finish_job_final_review','decide_employee_job_change','submit_employee_job_change','get_employee_job_change_source','submit_employee_job_change_structured','correct_employee_job_change','review_employee_job_change','link_employee_job_changes','review_employee_job_change_group','submit_job_description_draft','return_job_description_for_changes','decide_job_description_proposal','create_job_description_draft','save_job_description_draft','job_acknowledgement_followup']))loop
 k:=case when f.proname in('communication_notification_open','communication_trial_notification_open','communication_assignees','communication_task_sources')then 'communication'when f.proname like 'workspace_%'or f.proname like 'improvement_%'then 'workspace'when f.proname like 'project_%'or f.proname='capture_project_baseline'then 'projects'when f.proname like 'policy_%'then 'policies'when f.proname like 'employee_master_%'or f.proname='get_team_employee_job'then 'employees'when f.proname like '%job%'then 'job_library'else 'tasks'end;
 b:='PERFORM private.require_module('||quote_literal(k)||');';
 -- Project commands can operate their own task records; the row helper still checks membership.
 if k='tasks'and f.proname in('update_task_safe','update_task_with_subtasks_safe','delegate_task_safe','request_task_reschedule','save_task_followup','task_followup_context')then b:='IF NOT private.module_task_allowed($1)THEN PERFORM private.require_module(''tasks'');END IF;';end if;
 if f.proname in('communication_task_command','communication_trial_task_command')then b:=b||'PERFORM private.require_module(''communication'');';end if;
 d:=pg_get_functiondef(f.oid);hdr:=split_part(d,'AS $function$',1);
 if f.lanname='plpgsql'then body:='BEGIN '||b||E'\n'||regexp_replace(f.prosrc,'[;\s]+$','','g')||'; END';
 elsif f.lanname='sql'then
  hdr:=replace(hdr,'LANGUAGE sql','LANGUAGE plpgsql');
  if f.proretset then body:='BEGIN '||b||' RETURN QUERY '||regexp_replace(f.prosrc,'[;\s]+$','','g')||'; RETURN; END';
  elsif f.result='void'then body:='BEGIN '||b||' '||'PERFORM * FROM ('||regexp_replace(f.prosrc,'[;\s]+$','','g')||') AS module_result'||'; RETURN; END';
  else body:='BEGIN '||b||' RETURN ('||regexp_replace(f.prosrc,'[;\s]+$','','g')||'); END';end if;
 else raise exception 'Unsupported RPC language: %',f.proname;end if;
 execute hdr||'AS $function$'||body||'$function$';
 end loop;
end$guard$;
-- Communication's edge gateway checks this RPC before using its service client.
do $$declare f record;d text;begin
 for f in select p.oid,p.prosrc from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'and p.proname in('communication_status','communication_trial_status')loop
 d:=pg_get_functiondef(f.oid);execute replace(d,f.prosrc,'select private.module_allowed(''communication'') and ('||regexp_replace(f.prosrc,'[;\s]+$','','g')||')');end loop;
end$$;
revoke all on function private.module_allowed(text),private.require_module(text),private.validate_module_keys(text[]),private.guard_profile_modules(),private.account_module_context(),private.account_access_save(uuid,text,boolean,text[],integer),private.module_task_allowed(uuid)from public,anon,authenticated;
grant execute on function private.module_allowed(text),private.require_module(text),private.validate_module_keys(text[]),private.account_module_context(),private.account_access_save(uuid,text,boolean,text[],integer),private.module_task_allowed(uuid)to authenticated;
revoke all on function public.account_module_context(),public.account_access_save(uuid,text,boolean,text[],integer)from public,anon;
grant execute on function public.account_module_context(),public.account_access_save(uuid,text,boolean,text[],integer)to authenticated;
notify pgrst,'reload schema';

-- Storage and cross-module notifications retain the same boundary after revocation.
create policy module_boundary on storage.objects as restrictive to authenticated
using(case bucket_id when 'project-files'then private.module_allowed('projects')when 'task-attachments'then private.module_task_allowed(((storage.foldername(name))[1])::uuid)when 'task-batch-attachments'then private.module_allowed('tasks')else true end)
with check(case bucket_id when 'project-files'then private.module_allowed('projects')when 'task-attachments'then private.module_task_allowed(((storage.foldername(name))[1])::uuid)when 'task-batch-attachments'then private.module_allowed('tasks')else true end);
create policy module_boundary on public.notifications as restrictive to authenticated using(
 (task_id is null or private.module_task_allowed(task_id))and(project_id is null or private.module_allowed('projects'))and(improvement_id is null or private.module_allowed('workspace'))and(communication_conversation_id is null or private.module_allowed('communication'))and(communication_message_id is null or private.module_allowed('communication')));

-- A disabled library does not expose another employee's job or KPI record through profile APIs.
do $$declare f record;d text;gate text;begin
 for f in select p.oid,p.proname,p.prosrc from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private'and p.proname in('can_access_kpi_employee','can_review_job','can_job_stage')loop
 gate:=case when f.proname='can_access_kpi_employee'then '($1=auth.uid()or private.module_allowed(''employees''))'else 'private.module_allowed(''job_library'')'end;
 d:=pg_get_functiondef(f.oid);execute replace(d,f.prosrc,'select '||gate||' and ('||regexp_replace(f.prosrc,'[;\s]+$','','g')||')');end loop;
end$$;

create policy module_boundary on public.employee_job_assignments as restrictive to authenticated using(profile_id=auth.uid()or private.module_allowed('employees')or private.module_allowed('job_library'));
create policy module_boundary on public.job_description_versions as restrictive to authenticated using(private.module_allowed('job_library')or private.can_view_published_job(job_description_id));
create policy module_boundary on public.work_item_relations as restrictive to authenticated using((select private.module_allowed('workspace')or private.module_allowed('tasks')or private.module_allowed('projects')))with check((select private.module_allowed('workspace')or private.module_allowed('tasks')or private.module_allowed('projects')));
create policy module_boundary on public.work_relation_history as restrictive to authenticated using((select private.module_allowed('workspace')or private.module_allowed('tasks')or private.module_allowed('projects')));
