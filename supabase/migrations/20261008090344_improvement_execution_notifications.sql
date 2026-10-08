create function private.notify_improvement_execution() returns trigger language plpgsql security definer set search_path='' as $$
declare p public.improvement_proposals%rowtype;v_actor uuid;v_name text;v_note text;
begin
 if new.status is not distinct from old.status and new.deleted_at is not distinct from old.deleted_at then return new;end if;
 v_note:=case when new.deleted_at is not null then 'حُذف إجراء التنفيذ المرتبط بالمقترح' else 'تحديث التنفيذ: '||case new.status when 'PLANNING' then 'تخطيط' when 'ACTIVE' then 'قيد التنفيذ' when 'PAUSED' then 'متوقف مؤقتًا' when 'CLOSED' then 'مكتمل ومعتمد' when 'CANCELLED' then 'ملغى' else new.status end end;
 for p in select * from public.improvement_proposals where (tg_table_name='tasks' and task_id=new.id) or (tg_table_name='projects' and project_id=new.id) loop
  v_actor:=coalesce(auth.uid(),p.decided_by,p.requester_id);select full_name into v_name from public.profiles where id=v_actor;
  insert into public.improvement_events(proposal_id,actor_id,actor_name,action,note) values(p.id,v_actor,coalesce(v_name,'تحديث النظام'),'EXECUTION',v_note);
  insert into public.notifications(recipient_id,improvement_id,type,title,message) values(p.requester_id,p.id,'improvement_execution','متابعة تنفيذ مقترحك: '||p.title,v_note);
 end loop;
 return new;
end $$;
revoke all on function private.notify_improvement_execution() from public,anon,authenticated;
create trigger improvement_task_execution after update of status,deleted_at on public.tasks for each row execute function private.notify_improvement_execution();
create trigger improvement_project_execution after update of status,deleted_at on public.projects for each row execute function private.notify_improvement_execution();
