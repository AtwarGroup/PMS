create or replace function public.create_task_batch_safe(p_request_id uuid,p_title text,p_assignee_ids uuid[],p_description text default '',p_priority text default 'normal',p_start_date date default current_date,p_due_date date default null,p_notes text default '',p_attachments jsonb default '[]') returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
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
insert into task_batch_attachments(batch_id,uploader_id,file_name,storage_path,size_bytes) select p_request_id,auth.uid(),j.value->>'file_name',j.value->>'storage_path',(j.value->>'size_bytes')::bigint from jsonb_array_elements(p_attachments) as j(value);
return jsonb_build_object('batch_id',p_request_id,'count',n,'replayed',false);
end $$;
