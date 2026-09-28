begin;
create table public.job_stage_owners (
  stage text primary key check (stage in ('DRAFT','ASSIGN','FINAL_REVIEW','PUBLISH')),
  profile_id uuid not null references public.profiles(id),
  updated_by uuid references public.profiles(id),
  updated_at timestamptz not null default now()
);
alter table public.job_stage_owners enable row level security;
revoke all on public.job_stage_owners from public,anon;
grant select on public.job_stage_owners to authenticated;
create policy job_stage_owners_select on public.job_stage_owners for select to authenticated
using (private.is_admin() or profile_id=(select auth.uid()));
insert into public.job_stage_owners(stage,profile_id)
select stage,p.id from (values('DRAFT'),('ASSIGN'),('FINAL_REVIEW'),('PUBLISH')) stages(stage)
cross join lateral (select id from public.profiles where role='admin' and active=true and status='active' order by id limit 1) p;

create or replace function private.job_stage_owner(p_stage text)
returns uuid language sql stable security definer
set search_path='pg_catalog','public','private' as $$
 select profile_id from public.job_stage_owners where stage=p_stage limit 1
$$;
create or replace function private.can_job_stage(p_stage text)
returns boolean language sql stable security definer
set search_path='pg_catalog','public','private' as $$
 select coalesce(private.current_user_is_active() and
   (private.is_admin() or (select profile_id=(select auth.uid()) from public.job_stage_owners where stage=p_stage)),false)
$$;
revoke all on function private.job_stage_owner(text),private.can_job_stage(text) from public,anon;
grant execute on function private.can_job_stage(text) to authenticated;

create or replace function public.set_job_stage_owner(p_stage text,p_profile_id uuid)
returns public.job_stage_owners language plpgsql security definer
set search_path='pg_catalog','public','private' as $$
declare v_result public.job_stage_owners%rowtype;
begin
 if not private.is_admin() then raise exception 'Only system administrators assign job stage owners' using errcode='42501'; end if;
 if p_stage not in ('DRAFT','ASSIGN','FINAL_REVIEW','PUBLISH') then raise exception 'Invalid stage'; end if;
 if not exists(select 1 from public.profiles where id=p_profile_id and active=true and status='active') then raise exception 'Active account required'; end if;
 update public.job_stage_owners set profile_id=p_profile_id,updated_by=(select auth.uid()),updated_at=now()
 where stage=p_stage returning * into v_result;
 return v_result;
end $$;
revoke all on function public.set_job_stage_owner(text,uuid) from public,anon;
grant execute on function public.set_job_stage_owner(text,uuid) to authenticated;

create or replace function private.reassign_job_stage_task()
returns trigger language plpgsql security definer
set search_path='pg_catalog','public','private' as $$
declare v_phase text;v_name text;
begin
 if old.profile_id=new.profile_id then return new; end if;
 v_phase:=case new.stage when 'FINAL_REVIEW' then 'ADMIN_APPROVAL' when 'PUBLISH' then 'PUBLISH' end;
 if v_phase is null then return new; end if;
 select full_name into v_name from public.profiles where id=new.profile_id;
 update public.tasks t set assignee_id=new.profile_id,assignee_name_snapshot=v_name,
   title=case when new.stage='FINAL_REVIEW' then 'المراجعة النهائية للوصف الوظيفي: '||j.title else t.title end,
   revision=t.revision+1,updated_at=now()
 from private.job_workflow_tasks w join public.job_descriptions j on j.id=w.job_description_id
 where w.task_id=t.id and w.phase=v_phase
   and t.status<>'مكتملة' and t.deleted_at is null;
 update private.job_workflow_tasks w set recipient_id=new.profile_id
 from public.tasks t where t.id=w.task_id and w.phase=v_phase and t.status<>'مكتملة' and t.deleted_at is null;
 return new;
end $$;
revoke all on function private.reassign_job_stage_task() from public,anon,authenticated;
create trigger reassign_job_stage_task after update of profile_id on public.job_stage_owners
for each row execute function private.reassign_job_stage_task();

-- Separate final review from publication while preserving the current status model.
alter table public.job_descriptions add column final_reviewed_at timestamptz;
alter table public.job_descriptions add column final_reviewed_by uuid references public.profiles(id);
alter table private.job_workflow_tasks drop constraint job_workflow_tasks_phase_check;
alter table private.job_workflow_tasks add constraint job_workflow_tasks_phase_check
check (phase in ('MANAGER_REVIEW','ADMIN_APPROVAL','PUBLISH','EMPLOYEE_ACK'));

-- The publisher's task is distinct from final review.
create or replace function private.label_job_publish_task()
returns trigger language plpgsql security definer
set search_path='pg_catalog','public','private' as $$
declare v_title text;
begin
 if new.task_type='job_workflow' and new.legacy_metadata#>>'{job_workflow,phase}'='PUBLISH' then
   select title into v_title from public.job_descriptions where id=(new.legacy_metadata#>>'{job_workflow,job_id}')::uuid;
   new.title:='اعتماد ونشر الوصف الوظيفي: '||coalesce(v_title,new.title);
   new.description:='اكتملت المراجعة النهائية. افتح الوصف الوظيفي لاعتماد النسخة ونشرها.';
 end if;
 return new;
end $$;
revoke all on function private.label_job_publish_task() from public,anon,authenticated;
create trigger label_job_publish_task_before_insert before insert on public.tasks
for each row execute function private.label_job_publish_task();

create or replace function private.label_job_admin_approval_task()
returns trigger language plpgsql security definer
set search_path='pg_catalog','public','private' as $$
declare v_job public.job_descriptions%rowtype;v_reviewer text;
begin
 if new.task_type<>'job_workflow' or new.legacy_metadata#>>'{job_workflow,phase}'<>'ADMIN_APPROVAL' then return new; end if;
 select * into v_job from public.job_descriptions where id=(new.legacy_metadata#>>'{job_workflow,job_id}')::uuid;
 select full_name into v_reviewer from public.profiles where id=v_job.manager_approved_by;
 new.title:='المراجعة النهائية للوصف الوظيفي: '||v_job.title;
 new.description:='اكتملت مراجعة المدير'||case when nullif(btrim(coalesce(v_reviewer,'')),'') is null then '' else ' ('||v_reviewer||')' end||'. راجع الوصف والمقترحات، ثم أرسله لمسؤول الاعتماد والنشر.';
 return new;
end $$;

-- Future manager handoffs go to the configured final reviewer.
do $$
declare v_def text;
begin
 select pg_get_functiondef('private.sync_job_workflow_tasks()'::regprocedure) into v_def;
 if position($needle$perform private.ensure_job_workflow_task(new,'ADMIN_APPROVAL',v_cycle,v_admin);$needle$ in v_def)=0 then raise exception 'Workflow sync changed'; end if;
 v_def:=replace(v_def,$needle$perform private.ensure_job_workflow_task(new,'ADMIN_APPROVAL',v_cycle,v_admin);$needle$,
 $replacement$perform private.ensure_job_workflow_task(new,'ADMIN_APPROVAL',v_cycle,private.job_stage_owner('FINAL_REVIEW'));$replacement$);
 execute v_def;
end $$;

create or replace function private.sync_final_job_review()
returns trigger language plpgsql security definer
set search_path='pg_catalog','public','private' as $$
begin
 if old.final_reviewed_at is null and new.final_reviewed_at is not null and new.status='MANAGER_APPROVED' then
   perform private.close_job_workflow_tasks(new.id,'ADMIN_APPROVAL');
   perform private.ensure_job_workflow_task(new,'PUBLISH',coalesce(new.submitted_at::text,new.id::text),private.job_stage_owner('PUBLISH'));
 elsif old.status is distinct from new.status and new.status in ('IN_REVIEW','CHANGES_REQUESTED','DRAFT','PUBLISHED','ARCHIVED') then
   perform private.close_job_workflow_tasks(new.id,'PUBLISH');
 end if;
 return new;
end $$;
revoke all on function private.sync_final_job_review() from public,anon,authenticated;
create trigger job_final_review_task after update of final_reviewed_at,status on public.job_descriptions
for each row execute function private.sync_final_job_review();

-- Explicit operations for delegated users. The existing manager-review RPC
-- remains tied to the job's reviewer_id.
create or replace function public.finish_job_final_review(p_job_id uuid)
returns public.job_descriptions language plpgsql security definer
set search_path='pg_catalog','public','private' as $$
declare v_job public.job_descriptions%rowtype;
begin
 if not private.can_job_stage('FINAL_REVIEW') then raise exception 'Final review permission required' using errcode='42501'; end if;
 select * into v_job from public.job_descriptions where id=p_job_id for update;
 if not found or v_job.status<>'MANAGER_APPROVED' then raise exception 'Job is not awaiting final review'; end if;
 if v_job.final_reviewed_at is not null then return v_job; end if;
 if exists(select 1 from public.job_description_change_requests where job_description_id=p_job_id and status='PENDING' and action<>'COMMENT') then raise exception 'Resolve pending proposals first'; end if;
 update public.job_descriptions set final_reviewed_at=now(),final_reviewed_by=(select auth.uid()),updated_by=(select auth.uid())
 where id=p_job_id returning * into v_job;
 return v_job;
end $$;
revoke all on function public.finish_job_final_review(uuid) from public,anon;
grant execute on function public.finish_job_final_review(uuid) to authenticated;

create or replace function private.prepare_job_description()
returns trigger language plpgsql security invoker
set search_path='pg_catalog','public','private' as $$
declare v_uid uuid:=(select auth.uid());v_admin boolean:=private.is_admin();
  v_draft boolean:=private.can_job_stage('DRAFT');v_final boolean:=private.can_job_stage('FINAL_REVIEW');
  v_publish boolean:=private.can_job_stage('PUBLISH');
begin
 if v_uid is null then raise exception 'Authentication required'; end if;
 new.job_code:=upper(btrim(new.job_code));new.title:=btrim(new.title);new.purpose:=btrim(new.purpose);
 if tg_op='INSERT' then
   if not v_draft then raise exception 'Draft creation permission required' using errcode='42501'; end if;
   new.created_by:=v_uid;new.updated_by:=v_uid;new.created_at:=now();new.updated_at:=now();new.revision:=1;
   new.status:='DRAFT';new.final_reviewed_at:=null;new.final_reviewed_by:=null;
 else
   new.created_by:=old.created_by;new.created_at:=old.created_at;new.updated_by:=v_uid;new.updated_at:=now();new.revision:=old.revision+1;
   if old.status in ('IN_REVIEW','CHANGES_REQUESTED') and old.reviewer_id=v_uid and not (v_draft or v_final or v_publish) then
     new.job_code:=old.job_code;new.reviewer_id:=old.reviewer_id;
     if new.status not in ('IN_REVIEW','CHANGES_REQUESTED','MANAGER_APPROVED') then raise exception 'Reviewer cannot publish or archive'; end if;
     if new.status='CHANGES_REQUESTED' and char_length(btrim(coalesce(new.review_note,'')))<2 then raise exception 'A review note is required'; end if;
     if new.status='MANAGER_APPROVED' then new.manager_approved_by:=v_uid;new.manager_approved_at:=now(); end if;
   else
     if not (v_draft or v_final or v_publish) then raise exception 'Job stage permission required' using errcode='42501'; end if;
     if (new.job_code,new.title,new.family,new.job_level,new.reports_to_title,new.purpose,new.content,new.reviewer_id)
         is distinct from (old.job_code,old.title,old.family,old.job_level,old.reports_to_title,old.purpose,old.content,old.reviewer_id)
       and not (v_draft or (v_final and old.status='MANAGER_APPROVED')) then
       raise exception 'Draft or final review permission required' using errcode='42501';
     end if;
     if new.status is distinct from old.status then
       if new.status='IN_REVIEW' and v_draft and old.status in ('DRAFT','CHANGES_REQUESTED','PUBLISHED') then
         new.final_reviewed_at:=null;new.final_reviewed_by:=null;
       elsif new.status='CHANGES_REQUESTED' and v_final and old.status in ('IN_REVIEW','MANAGER_APPROVED') then
         new.final_reviewed_at:=null;new.final_reviewed_by:=null;
       elsif new.status='MANAGER_APPROVED' and (old.reviewer_id=v_uid or v_admin) and old.status in ('IN_REVIEW','CHANGES_REQUESTED') then
         new.manager_approved_by:=v_uid;new.manager_approved_at:=now();
       elsif new.status='DRAFT' and v_draft then
         new.final_reviewed_at:=null;new.final_reviewed_by:=null;
       elsif new.status='PUBLISHED' and v_publish and old.status='MANAGER_APPROVED' and old.final_reviewed_at is not null then
         new.published_by:=v_uid;new.published_at:=now();
         new.published_snapshot:=jsonb_build_object('job_code',new.job_code,'title',new.title,'family',new.family,
           'job_level',new.job_level,'reports_to_title',new.reports_to_title,'purpose',new.purpose,
           'content',new.content,'revision',new.revision,'published_at',now());
       elsif new.status='ARCHIVED' and v_publish then null;
       else raise exception 'Stage transition is not permitted' using errcode='42501'; end if;
     end if;
   end if;
   if new.final_reviewed_at is distinct from old.final_reviewed_at and new.final_reviewed_at is not null then
     if not v_final or old.status<>'MANAGER_APPROVED' then raise exception 'Final review permission required' using errcode='42501'; end if;
     if exists(select 1 from public.job_description_change_requests where job_description_id=old.id and status='PENDING' and action<>'COMMENT') then raise exception 'Resolve pending proposals first'; end if;
     new.final_reviewed_at:=now();new.final_reviewed_by:=v_uid;
   end if;
 end if;
 return new;
end $$;

-- Only a stage owner or an administrator sees the full working library.
alter policy job_descriptions_select_policy on public.job_descriptions using (
 private.can_view_published_job(id) or private.can_review_job(id)
 or private.can_job_stage('DRAFT') or private.can_job_stage('ASSIGN')
 or private.can_job_stage('FINAL_REVIEW') or private.can_job_stage('PUBLISH'));
alter policy job_descriptions_insert_policy on public.job_descriptions
 with check (private.can_job_stage('DRAFT') and created_by=(select auth.uid()) and updated_by=(select auth.uid()));
alter policy job_descriptions_update_policy on public.job_descriptions
 using (private.can_job_stage('DRAFT') or private.can_job_stage('FINAL_REVIEW') or private.can_job_stage('PUBLISH'))
 with check (private.can_job_stage('DRAFT') or private.can_job_stage('FINAL_REVIEW') or private.can_job_stage('PUBLISH'));

create or replace function private.prepare_employee_job_assignment()
returns trigger language plpgsql security invoker
set search_path='pg_catalog','public','private' as $$
declare v_uid uuid:=(select auth.uid());
begin
 if v_uid is null or not private.can_job_stage('ASSIGN') then
   raise exception 'Job assignment permission required' using errcode='42501';
 end if;
 if tg_op='INSERT' then new.assigned_by:=v_uid;new.assigned_at:=now();
 else new.assigned_by:=old.assigned_by;new.assigned_at:=old.assigned_at; end if;
 new.updated_by:=v_uid;new.updated_at:=now();return new;
end $$;
alter policy employee_job_assignments_select_policy on public.employee_job_assignments using (
 profile_id=(select auth.uid()) or private.can_job_stage('ASSIGN')
 or exists(select 1 from public.profiles p where p.id=employee_job_assignments.profile_id and p.manager_id=(select auth.uid())));
alter policy employee_job_assignments_insert_policy on public.employee_job_assignments
 with check (private.can_job_stage('ASSIGN') and assigned_by=(select auth.uid()) and updated_by=(select auth.uid()));
alter policy employee_job_assignments_update_policy on public.employee_job_assignments
 using (private.can_job_stage('ASSIGN')) with check (private.can_job_stage('ASSIGN') and updated_by=(select auth.uid()));
alter policy employee_job_assignments_delete_policy on public.employee_job_assignments
 using (private.can_job_stage('ASSIGN'));

alter policy job_change_requests_select_policy on public.job_description_change_requests
 using (private.can_job_stage('FINAL_REVIEW') or manager_id=(select auth.uid()));
alter policy job_change_requests_update_policy on public.job_description_change_requests
 using (private.can_job_stage('FINAL_REVIEW') or (manager_id=(select auth.uid()) and status='PENDING'))
 with check (private.can_job_stage('FINAL_REVIEW') or (manager_id=(select auth.uid()) and status='PENDING' and admin_decision_by is null and admin_decision_at is null));
-- Preserve the reviewer's proposal editing, while letting the delegated final
-- reviewer record final decisions through the existing trigger.
do $$
declare v_def text;v_old text:='elsif private.job_library_role()<>''admin'' then';
begin
 select pg_get_functiondef('private.prepare_job_change_request()'::regprocedure) into v_def;
 if position(v_old in v_def)=0 then raise exception 'Proposal trigger changed'; end if;
 v_def:=replace(v_def,v_old,'elsif not private.can_job_stage(''FINAL_REVIEW'') then');execute v_def;
end $$;

create or replace function public.job_stage_directory()
returns table(id uuid,full_name text,job_title text,role text,manager_id uuid,active boolean,status text)
language plpgsql stable security definer set search_path='pg_catalog','public','private' as $$
begin
 if not (private.can_job_stage('ASSIGN') or private.can_job_stage('DRAFT') or private.can_job_stage('FINAL_REVIEW'))
 then raise exception 'Job stage permission required' using errcode='42501'; end if;
 return query select p.id,p.full_name,p.job_title,p.role,p.manager_id,p.active,p.status
 from public.profiles p where p.active=true and p.status='active' order by p.full_name;
end $$;
revoke all on function public.job_stage_directory() from public,anon;
grant execute on function public.job_stage_directory() to authenticated;

commit;
