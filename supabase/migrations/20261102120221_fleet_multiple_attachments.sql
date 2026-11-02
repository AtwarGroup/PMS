-- Multiple files reuse the protected request file store; scalar primary IDs remain compatible.
create or replace function private.fleet_normalize_quote_scope() returns trigger
language plpgsql security invoker set search_path=pg_catalog,private as $$
declare q jsonb; scope text; normalized jsonb := '[]'::jsonb; component text; files jsonb;
begin
 if new.workflow_version <> 2 then return new; end if;
 if jsonb_typeof(new.quotes) is distinct from 'array' then raise exception 'Invalid quotes'; end if;
 for q in select value from jsonb_array_elements(new.quotes) loop
  if jsonb_typeof(q) is distinct from 'object' then raise exception 'Invalid quote'; end if;
  scope := case when q ? 'scope' then q->>'scope' else 'parts_labor' end;
  if scope is null or scope not in ('parts_labor','parts','labor') then raise exception 'حدد ما يشمله العرض'; end if;
  if scope='parts' then q := (q - 'labor_file_id' - 'labor_file_ids') || jsonb_build_object('labor',0); end if;
  if scope='labor' then q := (q - 'parts_file_id' - 'parts_file_ids') || jsonb_build_object('parts',0); end if;
  foreach component in array array['parts','labor'] loop
   if q ? (component||'_file_ids') then
    files:=q->(component||'_file_ids');
    if jsonb_typeof(files) is distinct from 'array' then raise exception 'قائمة مرفقات العرض غير صالحة'; end if;
    q:=q-(component||'_file_id');
    if jsonb_array_length(files)>0 then q:=q||jsonb_build_object(component||'_file_id',files->>0); end if;
   end if;
  end loop;
  normalized := normalized || jsonb_build_array(q);
 end loop;
 new.quotes := normalized;
 return new;
end $$;
revoke all on function private.fleet_normalize_quote_scope() from public,anon,authenticated;

alter function private.fleet_request_validate(private.fleet_requests) rename to fleet_request_validate_single_attachment;
revoke all on function private.fleet_request_validate_single_attachment(private.fleet_requests) from public,anon,authenticated;
create function private.fleet_request_validate(r private.fleet_requests) returns void
language plpgsql security definer set search_path=pg_catalog,private,public as $$
declare q jsonb; component text; files jsonb; item text; seen uuid[];
begin
 perform private.fleet_request_validate_single_attachment(r);
 foreach component in array array['parts','labor'] loop
  seen:='{}'::uuid[];
  for q in select value from jsonb_array_elements(r.quotes) loop
   if coalesce(q->>'scope','parts_labor') not in('parts_labor',component) then continue; end if;
   files:=case when q ? (component||'_file_ids') then q->(component||'_file_ids') else jsonb_build_array(q->>(component||'_file_id')) end;
   if jsonb_typeof(files) is distinct from 'array' or jsonb_array_length(files)=0 then raise exception 'أرفق ملفات العرض المطلوبة'; end if;
   if (files->>0)::uuid is distinct from (q->>(component||'_file_id'))::uuid then raise exception 'المرفق الأساسي لا يطابق قائمة المرفقات'; end if;
   for item in select value from jsonb_array_elements_text(files) loop
    if item is null or not exists(select 1 from private.fleet_files f where f.id=item::uuid and f.request_id=r.id and f.kind='quote_'||component) then raise exception 'مرفق العرض لا يتبع الطلب أو البند المحدد'; end if;
    if item::uuid=any(seen) then raise exception 'مرفق مستقل لكل ورشة مطلوب، دون تكرار'; end if;
    seen:=array_append(seen,item::uuid);
   end loop;
  end loop;
 end loop;
end $$;
revoke all on function private.fleet_request_validate(private.fleet_requests) from public,anon,authenticated;

create function private.fleet_check_attachment_batch(p_request uuid,p_kind text,p_data jsonb,p_single text,p_array text) returns void
language plpgsql security invoker set search_path=pg_catalog,private as $$
declare item text; seen uuid[]:='{}'; files jsonb;
begin
 if not p_data ? p_array then return; end if;
 files:=p_data->p_array;
 if jsonb_typeof(files) is distinct from 'array' or jsonb_array_length(files)=0 then raise exception 'قائمة المرفقات غير صالحة'; end if;
 if (files->>0)::uuid is distinct from nullif(p_data->>p_single,'')::uuid then raise exception 'المرفق الأساسي لا يطابق قائمة المرفقات'; end if;
 for item in select value from jsonb_array_elements_text(files) loop
  if item is null or not exists(select 1 from private.fleet_files f where f.id=item::uuid and f.request_id=p_request and f.kind=p_kind) then raise exception 'المرفق لا يتبع الطلب أو النوع المحدد'; end if;
  if item::uuid=any(seen) then raise exception 'المرفقات مكررة'; end if;
  seen:=array_append(seen,item::uuid);
 end loop;
end $$;
revoke all on function private.fleet_check_attachment_batch(uuid,text,jsonb,text,text) from public,anon,authenticated;

alter function private.fleet_command(uuid,integer,text,jsonb) rename to fleet_command_single_attachment;
revoke all on function private.fleet_command_single_attachment(uuid,integer,text,jsonb) from public,anon,authenticated;
create function private.fleet_command(p_id uuid,p_revision integer,p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path=pg_catalog,private,public as $$
declare r private.fleet_requests%rowtype;
begin
 perform private.require_module('fleet');
 select * into strict r from private.fleet_requests where id=p_id for update;
 if not private.fleet_visible(r) then raise exception 'Access denied' using errcode='42501'; end if;
 if p_action='confirm_repair' then
  perform private.fleet_check_attachment_batch(r.id,'invoice',p_data,'invoice_id','invoice_ids');
  perform private.fleet_check_attachment_batch(r.id,'repair_photo',p_data,'repair_photo_id','repair_photo_ids');
 elsif p_action in('confirm_advance','settle') then
  perform private.fleet_check_attachment_batch(r.id,case when p_action='settle' and r.advance>r.invoice_total then 'refund' else 'payment' end,p_data,'evidence_id','evidence_ids');
 end if;
 -- Existing authorization, revision, state and financial checks remain authoritative.
 return private.fleet_command_single_attachment(p_id,p_revision,p_action,p_data);
end $$;
revoke all on function private.fleet_command(uuid,integer,text,jsonb) from public,anon;
grant execute on function private.fleet_command(uuid,integer,text,jsonb) to authenticated;
