alter table public.tasks add column approval_commissioner_id uuid references public.profiles(id) on delete restrict;
select set_config('app.migration_mode','on',true);
update public.tasks set approval_commissioner_id=creator_id where task_type<>'job_workflow' and completion_requires_approval;
select set_config('app.migration_mode','off',true);
create or replace function private.classify_task_completion() returns trigger language plpgsql set search_path='' as $$
begin
 if tg_op='INSERT' then
   new.completion_requires_approval := coalesce(new.task_type='job_workflow',false) or new.creator_id is distinct from new.assignee_id;
   new.approval_commissioner_id := case when new.completion_requires_approval then new.creator_id else null end;
 else
   new.completion_requires_approval := old.completion_requires_approval or new.creator_id is distinct from new.assignee_id;
   new.approval_commissioner_id := case when old.completion_requires_approval then coalesce(old.approval_commissioner_id,old.creator_id)
     when new.creator_id is distinct from new.assignee_id then coalesce(auth.uid(),old.creator_id) else null end;
 end if;
 return new;
end $$;
CREATE OR REPLACE FUNCTION private.validate_task_workflow()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare v_role text; v_is_admin boolean; v_target_is_active boolean; v_target_allowed boolean; v_assignee_has_manager boolean;
begin
 if new.task_type='job_workflow' and pg_trigger_depth()>1 then return new; end if;
 if current_setting('app.migration_mode',true)='on' then return new; end if;
 if current_setting('app.soft_delete_mode',true)='on' then
   if new.id<>old.id or new.creator_id is distinct from old.creator_id or new.assignee_id is distinct from old.assignee_id or new.status is distinct from old.status or new.progress is distinct from old.progress then raise exception 'ATWAR_TASK: invalid soft-delete mutation'; end if;
   new.revision:=old.revision+1; return new;
 end if;
 if current_setting('app.cancel_mode',true)='on' then
   if new.id<>old.id or new.creator_id is distinct from old.creator_id or new.assignee_id is distinct from old.assignee_id or new.status<>'ملغاة' or old.status in('مكتملة','ملغاة') or new.cancelled_at is null or new.cancelled_by is null or nullif(btrim(coalesce(new.cancel_reason,'')),'') is null then raise exception 'ATWAR_TASK: invalid cancellation mutation'; end if;
   new.revision:=old.revision+1; return new;
 end if;
 if not private.current_user_is_active() then raise exception 'ATWAR_AUTH: inactive or unauthorized user'; end if;
 v_role:=private.current_user_role(); v_is_admin:=private.is_admin();
 if new.firebase_task_key is distinct from old.firebase_task_key then raise exception 'ATWAR_TASK: firebase_task_key is immutable'; end if;
 if new.legacy_id is distinct from old.legacy_id then raise exception 'ATWAR_TASK: legacy_id is immutable'; end if;
 if new.creator_id is distinct from old.creator_id then raise exception 'ATWAR_TASK: creator_id is immutable'; end if;
 if new.created_at is distinct from old.created_at then raise exception 'ATWAR_TASK: created_at is immutable'; end if;
 if new.creator_name_snapshot is distinct from old.creator_name_snapshot then raise exception 'ATWAR_TASK: creator snapshot is immutable'; end if;
 if new.deleted_at is distinct from old.deleted_at or new.deleted_by is distinct from old.deleted_by or new.delete_reason is distinct from old.delete_reason then raise exception 'ATWAR_TASK: delete fields are protected'; end if;
 if new.cancelled_at is distinct from old.cancelled_at or new.cancelled_by is distinct from old.cancelled_by or new.cancel_reason is distinct from old.cancel_reason then raise exception 'ATWAR_TASK: cancellation fields are protected'; end if;
 if new.approved_at is distinct from old.approved_at and not(old.status='بانتظار الاعتماد' and new.status='مكتملة') then raise exception 'ATWAR_TASK: approved_at cannot be changed directly'; end if;
 if new.approved_by_id is distinct from old.approved_by_id and not(old.status='بانتظار الاعتماد' and new.status='مكتملة') then raise exception 'ATWAR_TASK: approved_by_id cannot be changed directly'; end if;
 if new.returned_at is distinct from old.returned_at and not(old.status='بانتظار الاعتماد' and new.status='قيد التنفيذ') then raise exception 'ATWAR_TASK: returned_at cannot be changed directly'; end if;
 if new.returned_by_id is distinct from old.returned_by_id and not(old.status='بانتظار الاعتماد' and new.status='قيد التنفيذ') then raise exception 'ATWAR_TASK: returned_by_id cannot be changed directly'; end if;
 if new.reopened_at is distinct from old.reopened_at and not(old.status='مكتملة' and new.status='قيد التنفيذ') then raise exception 'ATWAR_TASK: reopened_at cannot be changed directly'; end if;
 if new.reopened_by_id is distinct from old.reopened_by_id and not(old.status='مكتملة' and new.status='قيد التنفيذ') then raise exception 'ATWAR_TASK: reopened_by_id cannot be changed directly'; end if;
 if new.reopen_reason is distinct from old.reopen_reason and not(old.status='مكتملة' and new.status='قيد التنفيذ') then raise exception 'ATWAR_TASK: reopen_reason cannot be changed directly'; end if;
 if auth.uid()=old.assignee_id and not v_is_admin and v_role<>'manager' and new.manager_notes is distinct from old.manager_notes then raise exception 'ATWAR_TASK: employee cannot modify manager notes'; end if;
 if new.assignee_id is distinct from old.assignee_id then
   if old.status not in('قيد الانتظار','قيد التنفيذ') then raise exception 'ATWAR_TASK: task cannot be reassigned in current status'; end if;
   if not v_is_admin and v_role<>'manager' then raise exception 'ATWAR_TASK: only manager/admin can reassign'; end if;
   select exists(select 1 from public.profiles p where p.id=new.assignee_id and p.active=true and p.status='active') into v_target_is_active;
   if not v_target_is_active then raise exception 'ATWAR_TASK: target assignee is not active'; end if;
   if v_is_admin then v_target_allowed:=true; else v_target_allowed:=new.assignee_id=auth.uid() or private.can_assign_task_target(new.assignee_id); end if;
   if not v_target_allowed then raise exception 'ATWAR_TASK: target assignee is outside manager hierarchy'; end if;
 end if;
 if new.status=old.status then
   if old.status='بانتظار الاعتماد' then raise exception 'ATWAR_TASK: task awaiting approval is read-only'; end if;
   if old.status='مكتملة' then raise exception 'ATWAR_TASK: completed task is read-only'; end if;
   if old.status='ملغاة' then raise exception 'ATWAR_TASK: cancelled task is read-only'; end if;
   if old.status not in('قيد الانتظار','قيد التنفيذ') then raise exception 'ATWAR_TASK: invalid editable state'; end if;
 elsif old.status='قيد الانتظار' and new.status='قيد التنفيذ' then
   if auth.uid()<>old.assignee_id and not v_is_admin then raise exception 'ATWAR_TASK: only assignee/admin can start task'; end if;
   if new.started_at is null then new.started_at:=now(); end if;
 elsif old.status='قيد التنفيذ' and new.status='بانتظار الاعتماد' then
   if auth.uid()<>old.assignee_id then raise exception 'ATWAR_TASK: only assignee can submit for approval'; end if;
   if new.progress<>100 then raise exception 'ATWAR_TASK: progress must be 100 before submission'; end if;
   new.submitted_at:=now();
 elsif old.status='بانتظار الاعتماد' and new.status='مكتملة' then
   if not(v_is_admin or (coalesce(old.approval_commissioner_id,old.creator_id)<>old.assignee_id and coalesce(old.approval_commissioner_id,old.creator_id)=auth.uid() and v_role='manager') or (coalesce(old.approval_commissioner_id,old.creator_id)=old.assignee_id and private.is_direct_manager(old.assignee_id))) then raise exception 'ATWAR_TASK: only task commissioner or admin may approve'; end if;
   if auth.uid()=old.assignee_id then raise exception 'ATWAR_TASK: assignee cannot approve own task'; end if;
   new.progress:=100; new.approved_at:=now(); new.approved_by_id:=auth.uid(); select full_name into new.approved_by_name_snapshot from public.profiles where id=auth.uid(); new.completed_at:=now(); if new.actual_end_date is null then new.actual_end_date:=current_date; end if;
 elsif old.status='بانتظار الاعتماد' and new.status='قيد التنفيذ' then
   if not(v_is_admin or (coalesce(old.approval_commissioner_id,old.creator_id)<>old.assignee_id and coalesce(old.approval_commissioner_id,old.creator_id)=auth.uid() and v_role='manager') or (coalesce(old.approval_commissioner_id,old.creator_id)=old.assignee_id and private.is_direct_manager(old.assignee_id))) then raise exception 'ATWAR_TASK: only task commissioner or admin may return task'; end if;
   if auth.uid()=old.assignee_id then raise exception 'ATWAR_TASK: assignee cannot return own task'; end if;
   if new.progress>95 then new.progress:=95; end if; new.returned_at:=now(); new.returned_by_id:=auth.uid(); select full_name into new.returned_by_name_snapshot from public.profiles where id=auth.uid(); new.actual_end_date:=null; new.completed_at:=null;
 elsif old.status='قيد التنفيذ' and new.status='مكتملة' then
   if auth.uid()<>old.assignee_id then raise exception 'ATWAR_TASK: only assignee may directly complete this task'; end if;
   if old.completion_requires_approval or old.creator_id<>old.assignee_id then raise exception 'ATWAR_TASK: commissioned task requires approval'; end if;
   new.progress:=100; new.completed_at:=now(); if new.actual_end_date is null then new.actual_end_date:=current_date; end if;
 elsif old.status='مكتملة' and new.status='قيد التنفيذ' then
   if not v_is_admin then raise exception 'ATWAR_TASK: only admin may reopen completed task'; end if;
   if new.reopen_reason is null or btrim(new.reopen_reason)='' then raise exception 'ATWAR_TASK: reopen reason is required'; end if;
   if new.progress>95 then new.progress:=95; end if; new.reopened_at:=now(); new.reopened_by_id:=auth.uid(); select full_name into new.reopened_by_name_snapshot from public.profiles where id=auth.uid(); new.completed_at:=null; new.actual_end_date:=null;
 else raise exception 'ATWAR_TASK: invalid status transition from % to %',old.status,new.status; end if;
 new.revision:=old.revision+1; return new;
end $function$;


CREATE OR REPLACE FUNCTION private.create_task_notification()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'auth'
AS $function$
declare v_manager_id uuid; v_creator_role text;
begin
 if current_setting('app.migration_mode',true)='on' then return new; end if;
 if tg_op='INSERT' then insert into public.notifications(recipient_id,task_id,type,title,message) values(new.assignee_id,new.id,'assigned','مهمة جديدة','تم إسناد مهمة جديدة إليك: '||new.title); return new; end if;
 if old.assignee_id is distinct from new.assignee_id then insert into public.notifications(recipient_id,task_id,type,title,message) values(new.assignee_id,new.id,'assigned','تم إسناد مهمة إليك','تم إسناد المهمة إليك: '||new.title); end if;
 if old.status is distinct from new.status then
   if old.status='قيد التنفيذ' and new.status='بانتظار الاعتماد' then
     if coalesce(new.approval_commissioner_id,new.creator_id)<>new.assignee_id then v_manager_id:=coalesce(new.approval_commissioner_id,new.creator_id);
     else select manager_id into v_manager_id from public.profiles where id=new.assignee_id; end if;
     if v_manager_id is not null and v_manager_id<>new.assignee_id then insert into public.notifications(recipient_id,task_id,type,title,message) values(v_manager_id,new.id,'submitted','مهمة بانتظار الاعتماد','تم إرسال المهمة للاعتماد: '||new.title); end if;
   elsif old.status='قيد التنفيذ' and new.status='مكتملة' then
     select manager_id into v_manager_id from public.profiles where id=new.assignee_id;
     if v_manager_id is not null and v_manager_id<>new.assignee_id then insert into public.notifications(recipient_id,task_id,type,title,message) values(v_manager_id,new.id,'completed','تم إكمال مهمة ذاتية','أكمل الموظف مهمة أنشأها لنفسه: '||new.title); end if;
   elsif new.status='ملغاة' then
     if new.assignee_id is distinct from auth.uid() then insert into public.notifications(recipient_id,task_id,type,title,message) values(new.assignee_id,new.id,'cancelled','تم إلغاء المهمة','تم إلغاء المهمة: '||new.title||case when new.cancel_reason is not null then ' — السبب: '||new.cancel_reason else '' end); end if;
   elsif old.status='بانتظار الاعتماد' and new.status='قيد التنفيذ' then insert into public.notifications(recipient_id,task_id,type,title,message) values(new.assignee_id,new.id,'returned','تمت إعادة المهمة','تمت إعادة المهمة للتنفيذ: '||new.title);
   elsif old.status='بانتظار الاعتماد' and new.status='مكتملة' then insert into public.notifications(recipient_id,task_id,type,title,message) values(new.assignee_id,new.id,'approved','تم اعتماد المهمة','تم اعتماد المهمة: '||new.title);
   elsif old.status='مكتملة' and new.status='قيد التنفيذ' then insert into public.notifications(recipient_id,task_id,type,title,message) values(new.assignee_id,new.id,'reopened','تمت إعادة فتح المهمة','تمت إعادة فتح المهمة: '||new.title);
   end if;
 end if;
 return new;
end $function$;


