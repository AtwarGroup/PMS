create table public.task_batches(id uuid primary key,creator_id uuid not null references public.profiles(id),title text not null,request_payload jsonb not null,created_at timestamptz not null default now());
alter table public.tasks add column batch_id uuid references public.task_batches(id);
create unique index tasks_batch_assignee_unique on public.tasks(batch_id,assignee_id) where batch_id is not null;
create table public.task_batch_attachments(id uuid primary key default gen_random_uuid(),batch_id uuid not null references public.task_batches(id),uploader_id uuid not null references public.profiles(id),file_name text not null,storage_path text unique not null,size_bytes bigint not null check(size_bytes between 0 and 10485760),created_at timestamptz not null default now());
alter table public.task_batches enable row level security;
alter table public.task_batch_attachments enable row level security;
create policy task_batches_admin_read on public.task_batches for select to authenticated using(private.current_user_is_active() and private.is_admin());
create function private.can_read_task_batch(p_batch uuid) returns boolean language sql stable security definer set search_path=public,pg_temp as $$ select private.current_user_is_active() and exists(select 1 from public.tasks t where t.batch_id=p_batch and t.deleted_at is null and (private.can_view_task(t.id) or private.has_permission('tasks.read_all')) and (t.project_id is null or private.project_access(t.project_id))) $$;
create policy task_batch_files_read on public.task_batch_attachments for select to authenticated using(private.can_read_task_batch(batch_id));
grant select on public.task_batches,public.task_batch_attachments to authenticated;
revoke all on public.task_batches,public.task_batch_attachments from anon;
insert into storage.buckets(id,name,public,file_size_limit) values('task-batch-attachments','task-batch-attachments',false,10485760);
create policy task_batch_upload on storage.objects for insert to authenticated with check(bucket_id='task-batch-attachments' and private.current_user_is_active() and private.is_admin() and (storage.foldername(name))[1]=auth.uid()::text);
create policy task_batch_download on storage.objects for select to authenticated using(bucket_id='task-batch-attachments' and exists(select 1 from public.task_batch_attachments a where a.storage_path=name and private.can_read_task_batch(a.batch_id)));
create policy task_batch_orphan_cleanup on storage.objects for delete to authenticated using(bucket_id='task-batch-attachments' and private.current_user_is_active() and private.is_admin() and (storage.foldername(name))[1]=auth.uid()::text and not exists(select 1 from public.task_batch_attachments a where a.storage_path=name));
create function public.task_batch_directory() returns table(id uuid,full_name text,department text) language plpgsql stable security definer set search_path=public,pg_temp as $$ begin
if not (private.current_user_is_active() and private.is_admin()) then raise exception 'الإسناد الجماعي متاح لمسؤول النظام فقط' using errcode='42501';end if;
return query select p.id,p.full_name,p.department from public.profiles p where p.active and p.status='active' and private.can_assign_task_target(p.id) order by p.full_name;
end $$;
create function public.create_task_batch_safe(p_request_id uuid,p_title text,p_assignee_ids uuid[],p_description text default '',p_priority text default 'normal',p_start_date date default current_date,p_due_date date default null,p_notes text default '',p_attachments jsonb default '[]') returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare ids uuid[]; payload jsonb; prior jsonb; target uuid; task_id uuid; f jsonb; n int;
begin
if not (private.current_user_is_active() and private.is_admin()) then raise exception 'الإسناد الجماعي متاح لمسؤول النظام فقط' using errcode='42501'; end if;
select array_agg(x order by x) into ids from (select distinct unnest(p_assignee_ids) x) q;
n:=coalesce(cardinality(ids),0);
p_attachments:=coalesce(p_attachments,'[]'::jsonb);
if p_request_id is null or n<2 or n>250 or array_position(ids,null) is not null then raise exception 'اختر بين موظفين و250 موظفًا';end if;
if char_length(btrim(coalesce(p_title,''))) not between 1 and 200 or char_length(coalesce(p_description,''))>5000 or char_length(coalesce(p_notes,''))>5000 or p_priority is null or p_priority not in ('normal','important','urgent') or p_start_date is null or p_due_date is null or p_due_date<p_start_date then raise exception 'تحقق من بيانات المهمة وتواريخها';end if;
if jsonb_typeof(p_attachments)<>'array' or jsonb_array_length(p_attachments)>5 then raise exception 'الحد الأعلى خمسة مرفقات';end if;
payload:=jsonb_build_object('title',btrim(p_title),'ids',ids,'description',coalesce(p_description,''),'priority',p_priority,'start',p_start_date,'due',p_due_date,'notes',coalesce(p_notes,''),'files',p_attachments);
perform pg_advisory_xact_lock(hashtextextended(p_request_id::text,0));
select request_payload into prior from task_batches where id=p_request_id and creator_id=auth.uid();
if found then
if prior<>payload then raise exception 'تغيرت بيانات طلب سبق إنشاؤه';end if;
return jsonb_build_object('batch_id',p_request_id,'count',(select count(*) from tasks where batch_id=p_request_id),'replayed',true);end if;
foreach target in array ids loop
if not exists(select 1 from profiles where id=target and active and status='active') or not private.can_assign_task_target(target) then raise exception 'أحد الموظفين غير متاح للإسناد';end if;end loop;
for f in select value from jsonb_array_elements(p_attachments) loop
if char_length(coalesce(f->>'file_name','')) not between 1 and 255 or not (coalesce(f->>'size_bytes','') ~ '^[0-9]+$') or (f->>'size_bytes')::bigint>10485760 or split_part(f->>'storage_path','/',1)<>auth.uid()::text or split_part(f->>'storage_path','/',2)<>p_request_id::text or not exists(select 1 from storage.objects o where o.bucket_id='task-batch-attachments' and o.name=f->>'storage_path' and coalesce((o.metadata->>'size')::bigint,-1)=(f->>'size_bytes')::bigint) then raise exception 'أحد المرفقات لم يكتمل رفعه أو غير صالح';end if;end loop;
insert into task_batches(id,creator_id,title,request_payload) values(p_request_id,auth.uid(),btrim(p_title),payload);
foreach target in array ids loop
 task_id:=public.create_task_safe(p_title,target,p_description,p_priority,p_start_date,p_due_date,p_notes);
 update tasks set batch_id=p_request_id where id=task_id;
end loop;
insert into task_batch_attachments(batch_id,uploader_id,file_name,storage_path,size_bytes) select p_request_id,auth.uid(),f->>'file_name',f->>'storage_path',(f->>'size_bytes')::bigint from jsonb_array_elements(p_attachments) f;
return jsonb_build_object('batch_id',p_request_id,'count',n,'replayed',false);
end $$;
create function public.task_batch_report(p_batch_id uuid default null) returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$ begin
if not (private.current_user_is_active() and private.is_admin()) then raise exception 'متابعة الإسناد الجماعي متاحة لمسؤول النظام فقط' using errcode='42501';end if;
return (select coalesce(jsonb_agg(jsonb_build_object('id',b.id,'title',b.title,'created_at',b.created_at,'tasks',(select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'name',coalesce(p.full_name,t.assignee_name_snapshot),'status',t.status,'progress',t.progress,'due',t.due_date,'deleted',t.deleted_at is not null,'overdue',t.deleted_at is null and t.status in ('قيد الانتظار','قيد التنفيذ') and t.due_date<timezone('Asia/Riyadh',now())::date) order by t.assignee_name_snapshot),'[]'::jsonb) from tasks t left join profiles p on p.id=t.assignee_id where t.batch_id=b.id)) order by b.created_at desc),'[]'::jsonb) from (select * from task_batches where p_batch_id is null or id=p_batch_id order by created_at desc limit 50) b);
end $$;
revoke all on function public.task_batch_directory(),public.create_task_batch_safe(uuid,text,uuid[],text,text,date,date,text,jsonb),public.task_batch_report(uuid) from public,anon;
grant execute on function public.task_batch_directory(),public.create_task_batch_safe(uuid,text,uuid[],text,text,date,date,text,jsonb),public.task_batch_report(uuid) to authenticated;

create function private.protect_task_batch_link() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$ begin
if new.batch_id is distinct from old.batch_id then
if old.batch_id is not null or not private.is_admin() or not exists(select 1 from task_batches b where b.id=new.batch_id and b.creator_id=auth.uid() and b.request_payload->'ids' @> to_jsonb(array[new.assignee_id])) then raise exception 'ATWAR_TASK: batch link is protected';end if;
end if;return new;end $$;
create trigger tasks_protect_batch_link before update of batch_id on public.tasks for each row execute function private.protect_task_batch_link();
