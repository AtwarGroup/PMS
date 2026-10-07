-- Preserve request history; close only requests invalidated by current task state.
DO $$
declare v_task uuid; r public.task_reschedule_requests%rowtype;
begin
 for v_task in select distinct t.id from public.tasks t join public.task_reschedule_requests q on q.task_id=t.id where q.status='PENDING' and (t.deleted_at is not null or t.status not in('قيد الانتظار','قيد التنفيذ') or t.assignee_id is distinct from q.requester_id or t.start_date is distinct from q.current_start_date or t.due_date is distinct from q.current_due_date) loop
 perform 1 from public.tasks where id=v_task for update;
 for r in update public.task_reschedule_requests q set status='CANCELLED',decided_at=now(),decision_note='أُلغي الطلب أثناء مراجعة النظام لتغيّر حالة المهمة أو مسؤولها أو تواريخها.' where q.task_id=v_task and q.status='PENDING' and exists(select 1 from public.tasks t where t.id=q.task_id and (t.deleted_at is not null or t.status not in('قيد الانتظار','قيد التنفيذ') or t.assignee_id is distinct from q.requester_id or t.start_date is distinct from q.current_start_date or t.due_date is distinct from q.current_due_date)) returning q.* loop
 insert into public.notifications(recipient_id,task_id,type,title,message) values(r.requester_id,r.task_id,'TASK_RESCHEDULE_CANCELLED','أُلغي طلب إعادة الجدولة','تغيّرت حالة المهمة أو مسؤولها أو تواريخها. يمكنك تقديم طلب جديد إذا كانت المهمة قابلة للتعديل.');
 end loop;
 end loop;
end $$;
