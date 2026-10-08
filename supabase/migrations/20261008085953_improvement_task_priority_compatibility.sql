create or replace function private.improvement_command(p_id uuid,p_revision integer,p_action text,p_data jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare p public.improvement_proposals%rowtype;v_uid uuid:=auth.uid();v_name text;v_note text;v_status text;v_title text;v_description text;v_link uuid;v_key uuid;v_source uuid;v_start date;v_due date;
begin
 if v_uid is null or not private.current_user_is_active() then raise exception 'حسابك غير مفعل' using errcode='42501';end if;
 select full_name into v_name from public.profiles where id=v_uid;
 if p_action='submit' then
  v_key:=(p_data->>'client_key')::uuid;v_source:=nullif(p_data->>'source_task_id','')::uuid;
  if v_key is null then raise exception 'معرف الإرسال مطلوب';end if;
  perform pg_advisory_xact_lock(hashtextextended(v_uid::text||v_key::text,0));
  select * into p from public.improvement_proposals where requester_id=v_uid and client_key=v_key;
  if found then
   if p.title is distinct from btrim(p_data->>'title') or p.current_process is distinct from btrim(p_data->>'current_process') or p.problem is distinct from btrim(p_data->>'problem') or p.benefit is distinct from btrim(p_data->>'benefit') or p.source_task_id is distinct from v_source then raise exception 'تغيرت بيانات الإرسال؛ استخدم معرفًا جديدًا' using errcode='23505';end if;
   return p.id;
  end if;
  if v_source is not null and not ((private.can_view_task(v_source) or private.has_permission('tasks.read_all')) and exists(select 1 from public.tasks t where t.id=v_source and t.deleted_at is null and (t.project_id is null or private.project_access(t.project_id)))) then raise exception 'المهمة المرتبطة غير متاحة لك' using errcode='42501';end if;
  insert into public.improvement_proposals(client_key,requester_id,requester_name,title,current_process,problem,benefit,source_task_id) values(v_key,v_uid,v_name,btrim(p_data->>'title'),btrim(p_data->>'current_process'),btrim(p_data->>'problem'),btrim(p_data->>'benefit'),v_source) returning * into p;
  v_note:='تقديم المقترح';
 else
  if not private.is_admin() then raise exception 'دراسة المقترحات متاحة لمسؤول النظام' using errcode='42501';end if;
  select * into p from public.improvement_proposals where id=p_id for update;
  if not found then raise exception 'المقترح غير متاح';end if;
  if p_action in ('task','project') and (p.task_id is not null or p.project_id is not null) then
   if (p_action='task' and p.task_id is null) or (p_action='project' and p.project_id is null) then raise exception 'المقترح مرتبط بإجراء تنفيذ بالفعل';end if;
   return coalesce(p.task_id,p.project_id);
  end if;
  if p_revision is distinct from p.revision then raise exception 'ATWAR_CONFLICT: تغير المقترح؛ راجع آخر تحديث';end if;
  if p_action='decide' then
   if p.task_id is not null or p.project_id is not null then raise exception 'تابع التنفيذ من المهمة أو المشروع المرتبط';end if;
   v_status:=p_data->>'status';v_note:=btrim(p_data->>'note');
   if v_note is null or length(v_note) not between 2 and 2000 then raise exception 'توضيح القرار مطلوب (2–2000 حرف)';end if;
   if not ((v_status='STUDY' and p.status in ('SUBMITTED','DEFERRED','NOT_SUITABLE','ACCEPTED')) or (p.status='STUDY' and v_status in ('ACCEPTED','DEFERRED','NOT_SUITABLE'))) then raise exception 'انتقال غير صالح؛ ابدأ الدراسة أولًا';end if;
   if v_status='ACCEPTED' and coalesce(p_data->>'priority','') not in ('HIGH','MEDIUM','LOW') then raise exception 'حدد أولوية التنفيذ';end if;
   update public.improvement_proposals set status=v_status,priority=case when v_status='ACCEPTED' then p_data->>'priority' else null end,decision_note=v_note,decided_by=v_uid,revision=revision+1,updated_at=now() where id=p.id returning * into p;
  elsif p_action in ('task','project') then
   if p.status<>'ACCEPTED' then raise exception 'اعتمد المقترح قبل تحويله للتنفيذ';end if;
   v_start:=(p_data->>'start_date')::date;v_due:=(p_data->>'due_date')::date;
   if v_start is null or v_due is null or v_due<v_start then raise exception 'راجع تاريخي البداية والنهاية';end if;
   v_title:=p.title;v_description:=E'الإجراء الحالي:\n'||p.current_process||E'\n\nالمشكلة:\n'||p.problem||E'\n\nالفائدة المتوقعة:\n'||p.benefit;
   if p_action='task' then
    v_link:=public.create_task_safe(v_title,(p_data->>'assignee_id')::uuid,v_description,'normal',v_start,v_due,'المقترح: https://one.atwargroup.com/workspace/improvements.html?id='||p.id::text);
    update public.improvement_proposals set task_id=v_link,revision=revision+1,updated_at=now() where id=p.id;
   else
    v_link:=public.project_command(null,null,'create',jsonb_build_object('title',v_title,'objective',left(v_description,5000),'deliverables',p.benefit,'manager_id',p_data->>'manager_id','sponsor_id',p_data->>'sponsor_id','start_date',v_start,'due_date',v_due,'members','[]'::jsonb));
    update public.improvement_proposals set project_id=v_link,revision=revision+1,updated_at=now() where id=p.id;
   end if;
   v_note:=case p_action when 'task' then 'تحويل المقترح إلى مهمة تنفيذ' else 'تحويل المقترح إلى مشروع' end;
  else raise exception 'إجراء غير صالح';end if;
 end if;
 insert into public.improvement_events(proposal_id,actor_id,actor_name,action,note) values(p.id,v_uid,v_name,case when p_action='decide' then v_status else p_action end,v_note);
 if p_action='submit' then
  insert into public.notifications(recipient_id,improvement_id,type,title,message) select id,p.id,'improvement_submitted','مقترح جديد للتحسين والأتمتة',p.requester_name||': '||p.title from public.profiles where role='admin' and active and status='active' and id<>v_uid;
 else
  insert into public.notifications(recipient_id,improvement_id,type,title,message) values(p.requester_id,p.id,'improvement_updated','تحديث مقترحك: '||p.title,v_note);
 end if;
 return coalesce(v_link,p.id);
end $$;
