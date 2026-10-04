create table private.communication_control(singleton boolean primary key default true check(singleton),enabled boolean not null default false,version bigint not null default 0,seq bigint not null default 0);
insert into private.communication_control(singleton) values(true);
create table private.communication_conversations(id text primary key,payload jsonb not null,check(jsonb_typeof(payload->'members')='array'));
create table private.communication_messages(id text primary key,conversation_id text not null references private.communication_conversations(id),sender_id uuid not null references public.profiles(id),client_id text not null,payload jsonb not null,unique(sender_id,client_id));
create index communication_message_conversation on private.communication_messages(conversation_id,((payload->>'seq')::bigint));
create table private.communication_personal(user_id uuid primary key references public.profiles(id),payload jsonb not null default '{}');
create table private.communication_notifications(id uuid primary key,recipient_id uuid not null references public.profiles(id),conversation_id text not null references private.communication_conversations(id),payload jsonb not null);
create index communication_notification_recipient on private.communication_notifications(recipient_id);
create table private.communication_files(id uuid primary key,conversation_id text not null references private.communication_conversations(id),payload jsonb not null,check(octet_length(payload::text)<=14500000));
create table private.communication_task_links(message_id text primary key references private.communication_messages(id),task_id uuid not null references public.tasks(id),created_by uuid not null references public.profiles(id));
alter table private.communication_control enable row level security;
alter table private.communication_conversations enable row level security;
alter table private.communication_messages enable row level security;
alter table private.communication_personal enable row level security;
alter table private.communication_notifications enable row level security;
alter table private.communication_files enable row level security;
alter table private.communication_task_links enable row level security;
revoke all on private.communication_control,private.communication_conversations,private.communication_messages,private.communication_personal,private.communication_notifications,private.communication_files,private.communication_task_links from public,anon,authenticated;
create function private.communication_actor(p_actor uuid) returns boolean language sql stable security definer set search_path='' as $f$
select p_actor is not null and exists(select 1 from public.profiles p where p.id=p_actor and p.active is true and p.status='active') and exists(select 1 from private.communication_control where singleton and enabled)
$f$;
create function public.communication_status() returns boolean language sql stable security definer set search_path='' as $f$ select private.communication_actor(auth.uid()) $f$;
revoke all on function private.communication_actor(uuid),public.communication_status() from public,anon,authenticated;
grant execute on function public.communication_status() to authenticated;
create table public.communication_revisions(user_id uuid primary key references public.profiles(id),version bigint not null default 0);
alter table public.communication_revisions enable row level security;
revoke all on public.communication_revisions from public,anon,authenticated;
grant select on public.communication_revisions to authenticated;
create policy communication_revision_own on public.communication_revisions for select to authenticated using(user_id=(select auth.uid()) and (select public.communication_status()));
alter publication supabase_realtime add table public.communication_revisions;
create function public.communication_load(p_actor uuid) returns jsonb language plpgsql security definer set search_path='' as $f$
declare s jsonb; k text; ps record;begin
 if not private.communication_actor(p_actor) then raise exception 'التواصل غير متاح';end if;
 s:=jsonb_build_object('users',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',full_name,'role',role,'department',coalesce(department,''),'manager',manager_id)),'[]') from public.profiles where active is true and status='active'),'conversations',(select coalesce(jsonb_agg(payload),'[]') from private.communication_conversations where payload->'members' @> jsonb_build_array(p_actor::text)),'messages','[]'::jsonb,'tasks','[]'::jsonb,'notifications','[]'::jsonb,'seq',(select seq from private.communication_control where singleton));
 s:=jsonb_set(s,'{messages}',(select coalesce(jsonb_agg(m.payload order by (m.payload->>'seq')::bigint),'[]') from private.communication_conversations c cross join lateral (select payload from private.communication_messages where conversation_id=c.id order by (payload->>'seq')::bigint desc limit 300) m where c.payload->'members' @> jsonb_build_array(p_actor::text)));
 s:=jsonb_set(s,'{notifications}',(select coalesce(jsonb_agg(n.payload),'[]') from private.communication_notifications n join private.communication_conversations c on c.id=n.conversation_id where c.payload->'members' @> jsonb_build_array(p_actor::text)));
 foreach k in array array['reads','saved','favorites','muted','presence','devices','availability','preferences','following','threadReads'] loop s:=jsonb_set(s,array[k],'{}');end loop;
 for ps in select user_id,payload from private.communication_personal loop
  foreach k in array array['reads','saved','favorites','muted','presence','availability','preferences','following','threadReads'] loop
   if ps.payload ? k then s:=jsonb_set(s,array[k,ps.user_id::text],ps.payload->k);end if;
  end loop;
  s:=jsonb_set(s,'{devices}',(s->'devices')||coalesce(ps.payload->'devices','{}'));
 end loop;
 return jsonb_build_object('version',(select version from private.communication_control where singleton),'state',s,'users',s->'users');end $f$;
create function public.communication_save(p_actor uuid,p_version bigint,p_state jsonb,p_files jsonb,p_publish boolean default true) returns boolean language plpgsql security definer set search_path='' as $f$
declare x jsonb;k text;personal jsonb:='{}';devices jsonb;recipients uuid[]:=array[p_actor];c jsonb;begin
 if not private.communication_actor(p_actor) then raise exception 'التواصل غير متاح';end if;
 update private.communication_control set version=version+1,seq=greatest(seq,(p_state->>'seq')::bigint) where singleton and version=p_version;
 if not found then return false;end if;
 for x in select value from jsonb_array_elements(p_state->'conversations') loop
  if not (x->'members' @> jsonb_build_array(p_actor::text)) and not exists(select 1 from private.communication_conversations where id=x->>'id' and payload->>'owner'=p_actor::text) then raise exception 'عضوية غير متاحة';end if;
  if exists(select 1 from private.communication_conversations where id=x->>'id' and not(payload->'members' @> jsonb_build_array(p_actor::text))) then raise exception 'لا تملك المحادثة';end if;
  if not exists(select 1 from private.communication_conversations where id=x->>'id' and payload=x) then
   recipients:=recipients||array(select value::uuid from jsonb_array_elements_text(x->'members'));
   recipients:=recipients||coalesce((select array(select value::uuid from jsonb_array_elements_text(payload->'members')) from private.communication_conversations where id=x->>'id'),array[]::uuid[]);
  end if;
  insert into private.communication_conversations(id,payload) values(x->>'id',x) on conflict(id) do update set payload=excluded.payload where private.communication_conversations.payload is distinct from excluded.payload;
 end loop;
 for x in select value from jsonb_array_elements(p_state->'messages') loop
  select payload into c from private.communication_conversations where id=x->>'conversation';
  if not(c->'members' @> jsonb_build_array(p_actor::text)) then raise exception 'الرسالة خارج العضوية';end if;
  if not exists(select 1 from private.communication_messages where id=x->>'id' and payload=x) then recipients:=recipients||array(select value::uuid from jsonb_array_elements_text(c->'members'));end if;
  insert into private.communication_messages(id,conversation_id,sender_id,client_id,payload) values(x->>'id',x->>'conversation',(x->>'sender')::uuid,x->>'clientId',x) on conflict(id) do update set payload=excluded.payload where private.communication_messages.payload is distinct from excluded.payload;
 end loop;
 foreach k in array array['reads','saved','favorites','muted','presence','availability','preferences','following','threadReads'] loop if p_state->k ? p_actor::text then personal:=jsonb_set(personal,array[k],p_state->k->p_actor::text);end if;end loop;
 select coalesce(jsonb_object_agg(key,value),'{}') into devices from jsonb_each(p_state->'devices') where value->>'user'=p_actor::text;
 personal:=jsonb_set(personal,'{devices}',devices);
 insert into private.communication_personal(user_id,payload) values(p_actor,personal) on conflict(user_id) do update set payload=excluded.payload;
 for x in select value from jsonb_array_elements(p_state->'notifications') loop
  select payload into c from private.communication_conversations where id=x->>'conversation';
  if not private.communication_actor((x->>'user')::uuid) or not(c->'members' @> jsonb_build_array(x->>'user')) then continue;end if;
  insert into private.communication_notifications(id,recipient_id,conversation_id,payload) values((x->>'id')::uuid,(x->>'user')::uuid,x->>'conversation',x) on conflict(id) do update set payload=excluded.payload where private.communication_notifications.payload is distinct from excluded.payload;
  insert into public.notifications(id,recipient_id,type,title,message,communication_conversation_id,communication_message_id) values((x->>'id')::uuid,(x->>'user')::uuid,'communication','رسالة جديدة في التواصل','افتح التواصل لقراءة الرسالة',x->>'conversation',x->>'message') on conflict(id) do nothing;
  if (x->>'read')::boolean then update public.notifications set read_at=coalesce(read_at,now()) where id=(x->>'id')::uuid;end if;
 end loop;
 for x in select value from jsonb_array_elements(p_files) loop
  if not exists(select 1 from private.communication_conversations where id=x->>'conversation' and payload->'members' @> jsonb_build_array(p_actor::text)) then raise exception 'الملف خارج العضوية';end if;
  insert into private.communication_files(id,conversation_id,payload) values((x->>'id')::uuid,x->>'conversation',x->'file') on conflict(id) do nothing;
 end loop;
 if p_publish then
  insert into public.communication_revisions(user_id,version) select distinct u,1 from unnest(recipients) u where private.communication_actor(u) on conflict(user_id) do update set version=public.communication_revisions.version+1;
 end if;
 return true;end $f$;
create function public.communication_file(p_actor uuid,p_file uuid) returns jsonb language plpgsql security definer set search_path='' as $f$
declare v jsonb;begin
 if not private.communication_actor(p_actor) then raise exception 'التواصل غير متاح';end if;
 select f.payload into v from private.communication_files f join private.communication_conversations c on c.id=f.conversation_id where f.id=p_file and c.payload->'members' @> jsonb_build_array(p_actor::text);
 if v is null then raise exception 'الملف خارج العضوية';end if;return v;end $f$;
revoke all on function public.communication_load(uuid),public.communication_save(uuid,bigint,jsonb,jsonb,boolean),public.communication_file(uuid,uuid) from public,anon,authenticated;
grant execute on function public.communication_load(uuid),public.communication_save(uuid,bigint,jsonb,jsonb,boolean),public.communication_file(uuid,uuid) to service_role;
create function public.communication_task_command(p_message text,p_task uuid default null,p_title text default null,p_assignee uuid default null,p_due date default null) returns uuid language plpgsql security definer set search_path='' as $f$
declare m jsonb;c jsonb;v_task uuid;begin
 if not private.communication_actor(auth.uid()) then raise exception 'التواصل غير متاح';end if;
 perform 1 from private.communication_control where singleton for update;
 select payload into m from private.communication_messages where id=p_message;
 select payload into c from private.communication_conversations where id=m->>'conversation';
 if m is null or c is null or not (c->'members' @> jsonb_build_array(auth.uid()::text)) then raise exception 'الرسالة غير متاحة';end if;
 select task_id into v_task from private.communication_task_links where message_id=p_message;
 if v_task is null then
  if p_task is null then
   if p_due is null or nullif(btrim(p_title),'') is null or length(p_title)>180 then raise exception 'العنوان وتاريخ الاستحقاق مطلوبان';end if;
   v_task:=public.create_task_safe(p_title,p_assignee,coalesce(m->>'body',''),'normal',current_date,p_due,'أنشئت من رسالة في التواصل');
  else v_task:=p_task;end if;
  if not ((private.can_view_task(v_task) or private.has_permission('tasks.read_all')) and exists(select 1 from public.tasks t where t.id=v_task and t.deleted_at is null and (t.project_id is null or private.project_access(t.project_id)))) then raise exception 'المهمة غير متاحة';end if;
  insert into private.communication_task_links(message_id,task_id,created_by) values(p_message,v_task,auth.uid());
  update private.communication_messages set payload=jsonb_set(payload,'{task}',to_jsonb(v_task::text)) where id=p_message;
  update private.communication_control set version=version+1 where singleton;
  insert into public.communication_revisions(user_id,version) select value::uuid,1 from jsonb_array_elements_text(c->'members') where private.communication_actor(value::uuid) on conflict(user_id) do update set version=public.communication_revisions.version+1;
 else
  if not ((private.can_view_task(v_task) or private.has_permission('tasks.read_all')) and exists(select 1 from public.tasks t where t.id=v_task and t.deleted_at is null and (t.project_id is null or private.project_access(t.project_id)))) then raise exception 'المهمة غير متاحة';end if;
  if p_task is not null and p_task<>v_task then raise exception 'الرسالة مرتبطة بالفعل';end if;
 end if;
 return v_task;end $f$;
create function public.communication_notification_open(p_id uuid) returns jsonb language plpgsql security definer set search_path='' as $f$
declare n public.notifications;begin
 if not private.communication_actor(auth.uid()) then raise exception 'التواصل غير متاح';end if;
 perform 1 from private.communication_control where singleton for update;
 select * into n from public.notifications where id=p_id and recipient_id=auth.uid() and type='communication';
 if n.id is null or not exists(select 1 from private.communication_conversations where id=n.communication_conversation_id and payload->'members' @> jsonb_build_array(auth.uid()::text)) then raise exception 'المحادثة غير متاحة';end if;
 update public.notifications set read_at=now() where id=p_id;
 update private.communication_notifications set payload=jsonb_set(payload,'{read}','true') where id=p_id;
 update private.communication_control set version=version+1 where singleton;
 return jsonb_build_object('conversation',n.communication_conversation_id,'message',n.communication_message_id);end $f$;
revoke all on function public.communication_task_command(text,uuid,text,uuid,date),public.communication_notification_open(uuid) from public,anon;
grant execute on function public.communication_task_command(text,uuid,text,uuid,date),public.communication_notification_open(uuid) to authenticated;

create function public.communication_assignees() returns jsonb language plpgsql security definer set search_path='' as $f$ begin
 if not private.communication_actor(auth.uid()) then raise exception 'التواصل غير متاح';end if;
 return (select coalesce(jsonb_agg(id),'[]') from public.profiles where active and status='active' and (private.is_admin() or id=auth.uid() or private.manages_user(id)) and private.can_assign_task_target(id));end $f$;
revoke all on function public.communication_assignees() from public,anon;
grant execute on function public.communication_assignees() to authenticated;
