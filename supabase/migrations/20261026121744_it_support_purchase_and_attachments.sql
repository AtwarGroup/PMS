-- Staging first: approval only for purchases, and private ticket attachments.
update private.it_support_services set approval=false;
insert into private.it_support_services(key,label,kind,approval)values('purchase','طلب شراء أجهزة أو برامج','service',true);
create or replace function private.it_support_create(p_data jsonb)returns uuid language plpgsql security definer set search_path=pg_catalog,private,public as $$declare s private.it_support_settings;v private.it_support_services;b public.profiles;a uuid;i uuid;impact int:=(p_data->>'impact')::int;urgency int:=(p_data->>'urgency')::int;begin
perform private.require_module('it_support');select * into strict s from private.it_support_settings;
if s.specialist_id is null or s.supervisor_id is null then raise exception 'لم يكتمل إعداد مسؤول الدعم ومرجعيته';end if;
if not exists(select 1 from public.profiles where id=s.specialist_id and active and status='active'and(role='admin'or('it_support'=any(allowed_modules)and'it_support.operate'=any(permissions))))then raise exception 'أخصائي الدعم غير متاح؛ راجع المشرف';end if;
select * into strict v from private.it_support_services where key=p_data->>'service_key';select * into strict b from public.profiles where id=coalesce(nullif(p_data->>'beneficiary_id','')::uuid,auth.uid())and active and status='active';
if b.id<>auth.uid()and b.manager_id is distinct from auth.uid()then raise exception 'يمكنك تقديم الطلب لنفسك أو فريقك المباشر'using errcode='42501';end if;
if v.key='purchase' then a:=s.supervisor_id;if a=auth.uid()then a:=s.supervisor_id;end if;if a=auth.uid()then raise exception 'يجب أن يعتمد الطلب شخص آخر';end if;end if;
insert into private.it_support_tickets(requester_id,beneficiary_id,approver_id,specialist_id,supervisor_id,service_key,title,description,impact,urgency,priority,state)values(auth.uid(),b.id,a,s.specialist_id,s.supervisor_id,v.key,p_data->>'title',p_data->>'description',impact,urgency,case when impact=3 and urgency=3 then 1 when impact+urgency>=5 then 2 when impact+urgency>=3 then 3 else 4 end,case when v.key='purchase' then 'approval'else 'new'end)returning id into i;
insert into private.it_support_events(ticket_id,actor_id,action)values(i,auth.uid(),'created');perform private.it_support_notify(i);return i;end$$;
-- Release non-purchase requests already waiting for an approval.
insert into private.it_support_events(ticket_id,actor_id,action,note)select id,null,'approval_removed','إلغاء اعتماد الخدمات غير الشرائية حسب الإجراء المعتمد'from private.it_support_tickets where state='approval'and service_key<>'purchase';
update private.it_support_tickets set state='new',approver_id=null,state_since=now(),updated_at=now(),revision=revision+1 where state='approval'and service_key<>'purchase';
create or replace function private.it_support_configure(specialist uuid,supervisor uuid)returns void language plpgsql security definer set search_path=pg_catalog,private,public as $$begin
if not private.it_support_permission('it_support.supervise')or not exists(select 1 from public.profiles where id=auth.uid()and role='admin')then raise exception 'تحديد المسؤولين من إدارة المستخدمين والصلاحيات فقط'using errcode='42501';end if;
if specialist=supervisor or not exists(select 1 from public.profiles where id=specialist and active and status='active'and(role='admin'or('it_support'=any(allowed_modules)and'it_support.operate'=any(permissions))))or not exists(select 1 from public.profiles where id=supervisor and active and status='active'and(role='admin'or('it_support'=any(allowed_modules)and'it_support.supervise'=any(permissions))))then raise exception 'حدد أخصائيًا ومشرفًا مختلفين بصلاحيات معتمدة من إدارة الحسابات';end if;
update private.it_support_settings set specialist_id=specialist,supervisor_id=supervisor where singleton;end$$;

create table private.it_support_files(
 id uuid primary key default gen_random_uuid(),ticket_id uuid not null references private.it_support_tickets(id),
 uploader_id uuid not null references public.profiles(id),name text not null check(length(name)between 1 and 180),
 mime text not null,size_bytes bigint not null check(size_bytes between 1 and 10485760),path text not null unique,
 ready boolean not null default false,created_at timestamptz not null default now()
);
create index it_support_files_ticket_idx on private.it_support_files(ticket_id);
create index it_support_files_uploader_idx on private.it_support_files(uploader_id);
alter table private.it_support_files enable row level security;
revoke all on private.it_support_files from public,anon,authenticated;
create policy internal_only on private.it_support_files to authenticated using(false)with check(false);
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)values('it-support-files','it-support-files',false,10485760,array['image/jpeg','image/png','image/webp','application/pdf','text/plain','application/vnd.openxmlformats-officedocument.wordprocessingml.document','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet']);
create function private.it_support_file_prepare(p_ticket uuid,p_name text,p_mime text,p_size bigint)returns jsonb language plpgsql security definer set search_path=pg_catalog,private,public as $$
declare t private.it_support_tickets;f private.it_support_files;extension text:=lower(substring(p_name from '\.([^.]*)$'));begin
if not private.it_support_visible(p_ticket)then raise exception 'الطلب غير متاح'using errcode='42501';end if;
select * into strict t from private.it_support_tickets where id=p_ticket for update;
if t.state in('closed','cancelled','rejected')or not(auth.uid()in(t.requester_id,t.beneficiary_id)or private.it_support_permission('it_support.operate'))then raise exception 'لا يمكن إرفاق ملفات لهذا الطلب'using errcode='42501';end if;
if not coalesce((extension='pdf'and p_mime='application/pdf')or(extension in('jpg','jpeg')and p_mime='image/jpeg')or(extension='png'and p_mime='image/png')or(extension='webp'and p_mime='image/webp')or(extension='txt'and p_mime='text/plain')or(extension='docx'and p_mime='application/vnd.openxmlformats-officedocument.wordprocessingml.document')or(extension='xlsx'and p_mime='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'),false)then raise exception 'نوع الملف غير مدعوم';end if;
if p_size is null or p_size not between 1 and 10485760 or length(btrim(p_name))not between 1 and 180 then raise exception 'الحد الأقصى 10 MB للملف؛ تحقق من الاسم والحجم';end if;
if(select count(*)from private.it_support_files where ticket_id=t.id)>=20 then raise exception 'الحد الأقصى 20 مرفقًا لكل طلب';end if;
f.id:=gen_random_uuid();f.path:=t.id::text||'/'||f.id::text||'.'||extension;
insert into private.it_support_files(id,ticket_id,uploader_id,name,mime,size_bytes,path)values(f.id,t.id,auth.uid(),p_name,p_mime,p_size,f.path);
return jsonb_build_object('id',f.id,'path',f.path);end$$;
create function private.it_support_file_access(p_path text,p_write boolean)returns boolean language sql stable security definer set search_path=pg_catalog,private,public as $$
select exists(select 1 from private.it_support_files f join private.it_support_tickets t on t.id=f.ticket_id where f.path=p_path and private.it_support_visible(t.id)and case when p_write then f.uploader_id=auth.uid()and not f.ready and t.state not in('closed','cancelled','rejected')and(auth.uid()in(t.requester_id,t.beneficiary_id)or private.it_support_permission('it_support.operate'))else f.ready end)$$;
create policy it_support_file_insert on storage.objects for insert to authenticated with check(bucket_id='it-support-files'and private.it_support_file_access(name,true));
create policy it_support_file_read on storage.objects for select to authenticated using(bucket_id='it-support-files'and private.it_support_file_access(name,false));
create function private.it_support_file_finish(p_file uuid)returns void language plpgsql security definer set search_path=pg_catalog,private,public,storage as $$declare f private.it_support_files;begin
select * into strict f from private.it_support_files where id=p_file for update;
if not private.it_support_visible(f.ticket_id)or f.uploader_id<>auth.uid()then raise exception 'الملف غير متاح'using errcode='42501';end if;
if f.ready then return;end if;
if not exists(select 1 from storage.objects where bucket_id='it-support-files'and name=f.path and(metadata->>'size')::bigint=f.size_bytes and metadata->>'mimetype'=f.mime)then raise exception 'لم يكتمل رفع الملف؛ أعد المحاولة';end if;
update private.it_support_files set ready=true where id=f.id;
insert into private.it_support_events(ticket_id,actor_id,action,note)values(f.ticket_id,auth.uid(),'attachment',f.name);
perform private.it_support_notify(f.ticket_id);end$$;
create function private.it_support_file_abort(p_file uuid)returns void language plpgsql security definer set search_path=pg_catalog,private,public,storage as $$begin
if auth.uid()is null then raise exception 'يلزم تسجيل الدخول'using errcode='42501';end if;
delete from private.it_support_files f where id=p_file and uploader_id=auth.uid()and not ready and private.it_support_visible(ticket_id)and not exists(select 1 from storage.objects o where o.bucket_id='it-support-files'and o.name=f.path);end$$;
create function public.it_support_file_prepare(p_ticket uuid,p_name text,p_mime text,p_size bigint)returns jsonb language sql security invoker set search_path=pg_catalog,private as $$select private.it_support_file_prepare(p_ticket,p_name,p_mime,p_size)$$;
create function public.it_support_file_finish(p_file uuid)returns void language sql security invoker set search_path=pg_catalog,private as $$select private.it_support_file_finish(p_file)$$;
create function public.it_support_file_abort(p_file uuid)returns void language sql security invoker set search_path=pg_catalog,private as $$select private.it_support_file_abort(p_file)$$;
revoke all on function private.it_support_file_prepare(uuid,text,text,bigint),public.it_support_file_prepare(uuid,text,text,bigint),private.it_support_file_finish(uuid),public.it_support_file_finish(uuid),private.it_support_file_abort(uuid),public.it_support_file_abort(uuid),private.it_support_file_access(text,boolean)from public,anon,authenticated;
grant execute on function private.it_support_file_prepare(uuid,text,text,bigint),public.it_support_file_prepare(uuid,text,text,bigint),private.it_support_file_finish(uuid),public.it_support_file_finish(uuid),private.it_support_file_abort(uuid),public.it_support_file_abort(uuid),private.it_support_file_access(text,boolean)to authenticated;
create or replace function private.it_support_detail(p_id uuid)returns jsonb language plpgsql stable security definer set search_path=pg_catalog,private,public as $$begin if not private.it_support_visible(p_id)then raise exception 'الطلب غير متاح'using errcode='42501';end if;return jsonb_build_object('ticket',(select to_jsonb(t)from private.it_support_tickets t where id=p_id),'messages',(select coalesce(jsonb_agg(to_jsonb(m)||jsonb_build_object('actor_name',p.full_name)order by m.id),'[]')from private.it_support_messages m join public.profiles p on p.id=m.actor_id where ticket_id=p_id and(not internal or private.it_support_permission('it_support.operate')or private.it_support_permission('it_support.supervise'))),'files',(select coalesce(jsonb_agg(to_jsonb(f)-'uploader_id' order by f.created_at),'[]')from private.it_support_files f where ticket_id=p_id and ready),'events',case when exists(select 1 from public.profiles where id=auth.uid()and role='admin')then(select coalesce(jsonb_agg(to_jsonb(e)order by id),'[]')from private.it_support_events e where ticket_id=p_id)else '[]'::jsonb end);end$$;
