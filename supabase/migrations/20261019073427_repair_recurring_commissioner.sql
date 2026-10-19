-- Repair the misattributed recurring template and its still-open occurrences.
-- The scheduler already copies owner_id correctly; preserve completed historical records.
-- apply_migration executes atomically. The table lock keeps concurrent clients outside
-- the short interval where the immutable commissioner classifier is suspended.
set local lock_timeout='5s';
lock table public.tasks in access exclusive mode;
alter table public.tasks disable trigger tasks_classify_completion;
select set_config('app.migration_mode','on',true);
do $repair$
declare r public.recurring_task_templates%rowtype; manager public.profiles%rowtype; old_owner uuid; t public.tasks%rowtype; saved jsonb; n integer:=0;
begin
 select rt.* into strict r from public.recurring_task_templates rt join public.profiles a on a.id=rt.assignee_id
 where rt.title='تصفية مستحقات العهده' and a.full_name='صالح باصرة';
 select m.* into strict manager from public.profiles a join public.profiles m on m.id=a.manager_id where a.id=r.assignee_id and m.active and m.status='active' and m.role='manager';
 if manager.full_name<>'محمد باسنبل' then raise exception 'Unexpected manager; re-review repair'; end if;
 old_owner:=r.owner_id;
 if old_owner=manager.id then return; end if;
 if not exists(select 1 from public.profiles where id=old_owner and full_name='مسؤول النظام' and role='admin') then raise exception 'Unexpected template owner'; end if;
 if not private.can_assign_task_target_for(manager.id,r.assignee_id) then raise exception 'Manager assignment is not permitted'; end if;
 saved:=to_jsonb(r);
 update public.recurring_task_templates set owner_id=manager.id,updated_at=now() where id=r.id;
 for t in select * from public.tasks where task_type='recurring' and title=r.title and assignee_id=r.assignee_id and creator_id=old_owner and project_id is null and deleted_at is null and status in('قيد الانتظار','قيد التنفيذ','بانتظار الاعتماد') for update loop
  update public.tasks set creator_id=manager.id,creator_name_snapshot=manager.full_name,approval_commissioner_id=manager.id,completion_requires_approval=true,revision=revision+1,
   legacy_metadata=coalesce(legacy_metadata,'{}')||jsonb_build_object('recurring_commissioner_repair',jsonb_build_object('at',now(),'reason','تصحيح صاحب التكليف وجهة الاعتماد للقالب الدوري بناءً على طلب المدير','previous_task',to_jsonb(t),'previous_template',saved))
  where id=t.id;
  -- Move the existing actionable approval notification; no duplicate submission.
  update public.notifications set recipient_id=manager.id where task_id=t.id and recipient_id=old_owner and type='submitted';
  insert into public.task_activity(task_id,sequence_no,event_type,actor_id,actor_name_snapshot,detail,created_at)
  values(t.id,private.next_task_activity_sequence(t.id),'updated',old_owner,'مسؤول النظام','تم تصحيح صاحب التكليف وجهة الاعتماد إلى محمد باسنبل للقالب الدوري؛ لم تتغير حالة المهمة أو المواعيد.',now());
  if exists(select 1 from public.tasks x where x.id=t.id and
   (to_jsonb(x)-array['creator_id','creator_name_snapshot','approval_commissioner_id','completion_requires_approval','revision','updated_at','legacy_metadata']) is distinct from
   (to_jsonb(t)-array['creator_id','creator_name_snapshot','approval_commissioner_id','completion_requires_approval','revision','updated_at','legacy_metadata'])) then raise exception 'Unrelated task data changed';end if;
  n:=n+1;
 end loop;
 if n<>2 then raise exception 'Expected two open occurrences, found %; re-review repair',n;end if;
end $repair$;
select set_config('app.migration_mode','off',true);
alter table public.tasks enable trigger tasks_classify_completion;
