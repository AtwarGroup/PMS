create or replace FUNCTION public.request_task_reschedule(p_task_id uuid, p_start_date date, p_due_date date, p_reason text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare v_task public.tasks%rowtype; v_id uuid;
begin
  if auth.uid() is null or not private.current_user_is_active() then raise exception 'Active authenticated account required' using errcode='42501'; end if;
  select * into v_task from public.tasks where id=p_task_id and deleted_at is null for update;
  if not found or v_task.assignee_id is distinct from (select auth.uid()) or not private.can_view_task(v_task.id) then raise exception 'Only the current assignee may request rescheduling' using errcode='42501'; end if;
  if v_task.status not in('قيد الانتظار','قيد التنفيذ') then raise exception 'This task cannot be rescheduled in its current status'; end if;
  if v_task.creator_id=(select auth.uid()) then raise exception 'The task creator can edit the schedule directly'; end if;
  if p_start_date is null or p_due_date is null or p_due_date<p_start_date then raise exception 'Valid start and due dates required'; end if;
  insert into public.task_reschedule_requests(task_id,requester_id,task_creator_id,current_start_date,current_due_date,proposed_start_date,proposed_due_date,reason)
  values(v_task.id,(select auth.uid()),v_task.creator_id,v_task.start_date,v_task.due_date,p_start_date,p_due_date,btrim(p_reason))
  returning id into v_id;
  insert into public.notifications(recipient_id,type,title,message,task_id,created_at)
  values(v_task.creator_id,'TASK_RESCHEDULE_REQUEST','طلب إعادة جدولة',coalesce(v_task.assignee_name_snapshot,'الموظف')||' طلب إعادة جدولة: '||v_task.title,v_task.id,now());
  return v_id;
end $function$;
create or replace function public.decide_task_reschedule(p_request_id uuid,p_approve boolean,p_note text default null) returns void language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare r public.task_reschedule_requests%rowtype; t public.tasks%rowtype;
begin
 if auth.uid() is null or not private.current_user_is_active() then raise exception 'Active authenticated account required' using errcode='42501';end if;
 if p_approve is null then raise exception 'Approval decision is required';end if;
 if not p_approve and char_length(btrim(coalesce(p_note,'')))<2 then raise exception 'Rejection reason is required';end if;
 if char_length(coalesce(p_note,''))>1000 then raise exception 'Decision note is too long';end if;
 select * into r from public.task_reschedule_requests where id=p_request_id;
 if not found then raise exception 'Pending request not found';end if;
 -- Every exceptional action locks the task first, then its request.
 select * into t from public.tasks where id=r.task_id and deleted_at is null for update;
 if not found or not private.can_view_task(t.id) then raise exception 'Task is unavailable' using errcode='42501';end if;
 select * into r from public.task_reschedule_requests where id=p_request_id for update;
 if r.status<>'PENDING' then raise exception 'Pending request not found';end if;
 if r.task_creator_id is distinct from auth.uid() and not private.is_admin() then raise exception 'Only the task creator may decide' using errcode='42501';end if;
 if t.status not in('قيد الانتظار','قيد التنفيذ') or t.assignee_id is distinct from r.requester_id or t.creator_id is distinct from r.task_creator_id or t.start_date is distinct from r.current_start_date or t.due_date is distinct from r.current_due_date then raise exception 'ATWAR_CONFLICT: task or schedule changed; submit a new request' using errcode='40001';end if;
 update public.task_reschedule_requests set status=case when p_approve then 'APPROVED' else 'REJECTED' end,decided_by=auth.uid(),decision_note=nullif(btrim(coalesce(p_note,'')),''),decided_at=now() where id=p_request_id;
 if p_approve then update public.tasks set start_date=r.proposed_start_date,due_date=r.proposed_due_date,updated_at=now() where id=r.task_id;end if;
 insert into public.notifications(recipient_id,type,title,message,task_id,created_at) values(r.requester_id,'TASK_RESCHEDULE_DECISION',case when p_approve then 'تمت الموافقة على إعادة الجدولة' else 'تم رفض إعادة الجدولة' end,coalesce(p_note,''),r.task_id,now());
end $$;
create or replace function private.invalidate_task_reschedule() returns trigger language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare r public.task_reschedule_requests%rowtype;
begin
 if new.deleted_at is not null or new.status not in('قيد الانتظار','قيد التنفيذ') or new.assignee_id is distinct from old.assignee_id or new.start_date is distinct from old.start_date or new.due_date is distinct from old.due_date then
 for r in update public.task_reschedule_requests set status='CANCELLED',decided_at=now(),decided_by=auth.uid(),decision_note='أُلغي الطلب لتغيّر حالة المهمة أو مسؤولها أو تواريخها.' where task_id=new.id and status='PENDING' returning * loop
 insert into public.notifications(recipient_id,task_id,type,title,message) values(r.requester_id,new.id,'TASK_RESCHEDULE_CANCELLED','أُلغي طلب إعادة الجدولة','تغيّرت حالة المهمة أو مسؤولها أو تواريخها. يمكنك تقديم طلب جديد إذا كانت المهمة قابلة للتعديل.');
 end loop;
 end if;
 return new;
end $$;
create trigger tasks_invalidate_pending_reschedule after update of status,assignee_id,start_date,due_date,deleted_at on public.tasks for each row execute function private.invalidate_task_reschedule();
revoke all on function private.invalidate_task_reschedule() from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.cancel_task_safe(p_task_id uuid, p_reason text)
 RETURNS tasks
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare v_actor uuid:=auth.uid(); v_role text; v_name text; v_active boolean; v_task public.tasks%rowtype; v_allowed boolean:=false; v_previous_cancel_mode text;
begin
 if v_actor is null then raise exception 'Authentication required'; end if;
 if nullif(btrim(coalesce(p_reason,'')),'') is null then raise exception 'Cancellation reason is required'; end if;
 select role,full_name,active and status='active' into v_role,v_name,v_active from public.profiles where id=v_actor;
 if not coalesce(v_active,false) then raise exception 'Inactive user'; end if;
 if v_role not in('manager','admin') then raise exception 'Manager or admin permission required'; end if;
 select * into v_task from public.tasks where id=p_task_id and deleted_at is null for update;
 if not found then raise exception 'Task not found'; end if;
 if v_task.status in('مكتملة','ملغاة') then raise exception 'Completed/cancelled task cannot be cancelled'; end if;
 if v_role='admin' then v_allowed:=true; else v_allowed:=v_task.assignee_id=v_actor or v_task.creator_id=v_actor or private.is_direct_manager(v_task.assignee_id); end if;
 if not v_allowed then raise exception 'Task is outside your permitted scope'; end if;
 v_previous_cancel_mode:=current_setting('app.cancel_mode',true);
 perform set_config('app.cancel_mode','on',true);
 update public.tasks set status='ملغاة',cancelled_at=now(),cancelled_by=v_actor,cancel_reason=btrim(p_reason) where id=p_task_id returning * into v_task;
 perform set_config('app.cancel_mode',coalesce(v_previous_cancel_mode,'off'),true);
 insert into public.admin_audit_log(actor_id,actor_name_snapshot,action,target_type,target_id,detail) values(v_actor,v_name,'TASK_CANCEL','task',p_task_id::text,jsonb_build_object('reason',p_reason,'title',v_task.title));
 return v_task;
end $function$;
drop policy task_reschedule_select_policy on public.task_reschedule_requests;
create policy task_reschedule_select_policy on public.task_reschedule_requests for select to authenticated using(private.current_user_is_active() and private.can_view_task(task_id) and (requester_id=auth.uid() or task_creator_id=auth.uid() or private.is_admin()));
