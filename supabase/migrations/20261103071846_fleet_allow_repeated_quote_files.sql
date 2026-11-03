-- Repeated quotation files are permitted; workshop review remains mandatory.
DO $patch$
DECLARE definition text; old_check text;
BEGIN
 SELECT pg_get_functiondef('private.fleet_command_legacy(uuid,integer,text,jsonb)'::regprocedure) INTO definition;
 old_check := $old$if(select count(distinct (value->>'file_id')::uuid)from jsonb_array_elements(r.quotes))<>jsonb_array_length(r.quotes)then raise exception 'يجب إرفاق ملف مستقل لكل عرض سعر';end if;$old$;
 IF position(old_check in definition)=0 THEN RAISE EXCEPTION 'Expected quotation check missing: fleet_command_legacy(uuid,integer,text,jsonb)'; END IF;
 EXECUTE replace(definition,old_check,'');
 SELECT pg_get_functiondef('private.fleet_request_validate_single_attachment(private.fleet_requests)'::regprocedure) INTO definition;
 old_check := $old$ foreach component in array array['parts','labor'] loop
  if exists(select 1 from jsonb_array_elements(r.quotes) x where coalesce(x->>'scope','parts_labor') in ('parts_labor',component)) then
   if (select count(distinct value->>(component||'_file_id')) from jsonb_array_elements(r.quotes) where coalesce(value->>'scope','parts_labor') in ('parts_labor',component)) <>
      (select count(*) from jsonb_array_elements(r.quotes) where coalesce(value->>'scope','parts_labor') in ('parts_labor',component)) then
    raise exception 'مرفق مستقل لكل ورشة مطلوب: %',case when component='parts' then 'قطع الغيار' else 'أجرة اليد' end;
   end if;
  end if;
 end loop;
$old$;
 IF position(old_check in definition)=0 THEN RAISE EXCEPTION 'Expected quotation check missing: fleet_request_validate_single_attachment(private.fleet_requests)'; END IF;
 EXECUTE replace(definition,old_check,'');
END $patch$;
create or replace function private.fleet_request_validate(r private.fleet_requests) returns void
language plpgsql security definer set search_path=pg_catalog,private,public as $$
declare q jsonb; component text; files jsonb; item text;
begin
 perform private.fleet_request_validate_single_attachment(r);
 foreach component in array array['parts','labor'] loop
  for q in select value from jsonb_array_elements(r.quotes) loop
   if coalesce(q->>'scope','parts_labor') not in('parts_labor',component) then continue; end if;
   files:=case when q ? (component||'_file_ids') then q->(component||'_file_ids') else jsonb_build_array(q->>(component||'_file_id')) end;
   if jsonb_typeof(files) is distinct from 'array' or jsonb_array_length(files)=0 then raise exception 'أرفق ملفات العرض المطلوبة'; end if;
   if (files->>0)::uuid is distinct from (q->>(component||'_file_id'))::uuid then raise exception 'المرفق الأساسي لا يطابق قائمة المرفقات'; end if;
   for item in select value from jsonb_array_elements_text(files) loop
    if item is null or not exists(select 1 from private.fleet_files f where f.id=item::uuid and f.request_id=r.id and f.kind='quote_'||component) then raise exception 'مرفق العرض لا يتبع الطلب أو البند المحدد'; end if;
   end loop;
  end loop;
 end loop;
end $$;
