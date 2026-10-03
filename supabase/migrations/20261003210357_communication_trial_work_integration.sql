-- Closed-pilot integration. Production task rules remain authoritative.
create table private.communication_trial_task_links(message_id text primary key,task_id uuid not null references public.tasks(id),created_by uuid not null references public.profiles(id),created_at timestamptz not null default now());
alter table private.communication_trial_task_links enable row level security;
revoke all on private.communication_trial_task_links from public,anon,authenticated;
create function public.communication_trial_task_command(p_message text,p_task uuid default null,p_title text default null,p_assignee uuid default null,p_due date default null) returns uuid language plpgsql security definer set search_path='' as $f$
declare s jsonb;m jsonb;c jsonb;i integer;v_task uuid;begin
 if not private.communication_trial_allowed() then raise exception 'التجربة غير متاحة';end if;
 select state into s from private.communication_trial_state where singleton for update;
 select value,(ordinality-1)::integer into m,i from jsonb_array_elements(s->'messages') with ordinality where value->>'id'=p_message;
 select value into c from jsonb_array_elements(s->'conversations') where value->>'id'=m->>'conversation';
 if m is null or c is null or not (c->'members' @> jsonb_build_array(auth.uid()::text)) then raise exception 'الرسالة غير متاحة';end if;
 select task_id into v_task from private.communication_trial_task_links where message_id=p_message;
 if v_task is not null then
  if not ((private.can_view_task(v_task) or private.has_permission('tasks.read_all')) and exists(select 1 from public.tasks t where t.id=v_task and t.deleted_at is null and (t.project_id is null or private.project_access(t.project_id)))) then raise exception 'المهمة غير متاحة';end if;
  if p_task is not null and p_task<>v_task then raise exception 'الرسالة مرتبطة بالفعل';end if;
  return v_task;
 end if;
 if p_task is null then
  if p_due is null or nullif(btrim(p_title),'') is null or length(p_title)>180 then raise exception 'العنوان وتاريخ الاستحقاق مطلوبان';end if;
  if not private.communication_trial_actor(p_assignee) then raise exception 'الإسناد في التجربة للحسابات التجريبية فقط';end if;
  v_task:=public.create_task_safe(p_title,p_assignee,coalesce(m->>'body',''),'normal',current_date,p_due,'أنشئت من رسالة في التواصل');
 else
  if not ((private.can_view_task(p_task) or private.has_permission('tasks.read_all')) and exists(select 1 from public.tasks t where t.id=p_task and t.deleted_at is null and (t.project_id is null or private.project_access(t.project_id)))) then raise exception 'المهمة غير متاحة';end if;
  v_task:=p_task;
 end if;
 insert into private.communication_trial_task_links(message_id,task_id,created_by) values(p_message,v_task,auth.uid());
 s:=jsonb_set(s,array['messages',i::text,'task'],to_jsonb(v_task::text));
 update private.communication_trial_state set state=s,version=version+1,updated_at=now() where singleton;
 return v_task;end $f$;
revoke all on function public.communication_trial_task_command(text,uuid,text,uuid,date) from public,anon;
grant execute on function public.communication_trial_task_command(text,uuid,text,uuid,date) to authenticated;
-- Only routing IDs are added to standard notifications; message contents stay private.
alter table public.notifications add column communication_conversation_id text, add column communication_message_id text;
create function private.communication_trial_notify() returns trigger language plpgsql security definer set search_path='' as $f$
declare n jsonb;c jsonb;begin
 for n in select nr.value from jsonb_array_elements(coalesce(new.state->'notifications','[]')) nr where not exists(select 1 from jsonb_array_elements(coalesce(old.state->'notifications','[]')) x where x->>'id'=nr.value->>'id') loop
  select value into c from jsonb_array_elements(new.state->'conversations') where value->>'id'=n->>'conversation';
  if private.communication_trial_actor((n->>'user')::uuid) and c->'members' @> jsonb_build_array(n->>'user') then
   insert into public.notifications(id,recipient_id,type,title,message,communication_conversation_id,communication_message_id) values((n->>'id')::uuid,(n->>'user')::uuid,'communication_trial','رسالة جديدة في التواصل','افتح التواصل لقراءة الرسالة',n->>'conversation',n->>'message') on conflict(id) do nothing;
  end if;
 end loop;
 update public.notifications p set read_at=coalesce(p.read_at,now()) where p.type='communication_trial' and exists(select 1 from jsonb_array_elements(coalesce(new.state->'notifications','[]')) x where x->>'id'=p.id::text and (x->>'read')::boolean);
 return new;end $f$;
revoke all on function private.communication_trial_notify() from public,anon,authenticated;
create trigger communication_trial_standard_notifications after update on private.communication_trial_state for each row execute function private.communication_trial_notify();
create function public.communication_trial_notification_open(p_id uuid) returns jsonb language plpgsql security definer set search_path='' as $f$
declare n public.notifications;begin
 if not private.communication_trial_allowed() then raise exception 'التجربة غير متاحة';end if;
 select * into n from public.notifications where id=p_id and recipient_id=auth.uid() and type='communication_trial';
 if n.id is null or not exists(select 1 from private.communication_trial_state s cross join lateral jsonb_array_elements(s.state->'conversations') c where s.singleton and c->>'id'=n.communication_conversation_id and c->'members' @> jsonb_build_array(auth.uid()::text)) then raise exception 'المحادثة غير متاحة';end if;
 update public.notifications set read_at=now() where id=p_id;
 return jsonb_build_object('conversation',n.communication_conversation_id,'message',n.communication_message_id,'notification',n.id);end $f$;
revoke all on function public.communication_trial_notification_open(uuid) from public,anon;
grant execute on function public.communication_trial_notification_open(uuid) to authenticated;
