-- Scope belongs to each quotation. Missing scope retains the historical both-items contract.
-- Excluded values are discarded before they can enter financial calculations.
create or replace function private.fleet_normalize_quote_scope() returns trigger
language plpgsql security invoker set search_path=pg_catalog,private as $$
declare q jsonb; scope text; normalized jsonb := '[]'::jsonb;
begin
 if new.workflow_version <> 2 then return new; end if;
 if jsonb_typeof(new.quotes) is distinct from 'array' then raise exception 'Invalid quotes'; end if;
 for q in select value from jsonb_array_elements(new.quotes) loop
  if jsonb_typeof(q) is distinct from 'object' then raise exception 'Invalid quote'; end if;
  scope := case when q ? 'scope' then q->>'scope' else 'parts_labor' end;
  if scope is null or scope not in ('parts_labor','parts','labor') then raise exception 'حدد ما يشمله العرض'; end if;
  if scope='parts' then q := (q - 'labor_file_id') || jsonb_build_object('labor',0); end if;
  if scope='labor' then q := (q - 'parts_file_id') || jsonb_build_object('parts',0); end if;
  normalized := normalized || jsonb_build_array(q);
 end loop;
 new.quotes := normalized;
 return new;
end $$;
revoke all on function private.fleet_normalize_quote_scope() from public,anon,authenticated;
create trigger fleet_normalize_quote_scope before insert or update of quotes on private.fleet_requests
for each row execute function private.fleet_normalize_quote_scope();

create or replace function private.fleet_request_validate(r private.fleet_requests) returns void
language plpgsql security definer set search_path=pg_catalog,private,public as $$
declare q jsonb; minimum integer; scope text; component text;
begin
 if length(btrim(r.description))<10 or length(btrim(r.fault_notes))<10 then raise exception 'النصوص إلزامية، 10 أحرف على الأقل'; end if;
 if r.request_type='repair' and coalesce(r.maintenance_kind,'') not in ('tire','battery','engine_flush','inspection_service') then raise exception 'حدد نوع الصيانة الدورية'; end if;
 minimum := case when r.request_type='emergency' and r.stops_vehicle and r.needs_tow then 1 else 2 end;
 if jsonb_typeof(r.quotes) is distinct from 'array' or jsonb_array_length(r.quotes)<minimum then raise exception 'يلزم توفير % عروض أسعار على الأقل',minimum; end if;
 if r.selected_quote not between 0 and jsonb_array_length(r.quotes)-1 then raise exception 'حدد العرض المختار'; end if;
 if (select count(distinct coalesce(value->>'scope','parts_labor')) from jsonb_array_elements(r.quotes))<>1 then raise exception 'يجب أن تغطي جميع العروض نفس نطاق العمل المطلوب'; end if;
 for q in select value from jsonb_array_elements(r.quotes) loop
  scope := coalesce(q->>'scope','parts_labor');
  if scope not in ('parts_labor','parts','labor') then raise exception 'حدد ما يشمله العرض'; end if;
  if length(btrim(coalesce(q->>'supplier','')))<10 or coalesce(q->>'phone','') !~ '^(05[0-9]{8}|[+]9665[0-9]{8})$' then raise exception 'اسم الورشة 10 أحرف على الأقل ورقم جوال سعودي صالح مطلوب'; end if;
  if q->>'parts' is null or q->>'labor' is null or q->>'tax' is null then raise exception 'جميع مبالغ العرض مطلوبة'; end if;
  foreach component in array array['parts','labor'] loop
   if scope='parts_labor' or scope=component then
    if not exists(select 1 from private.fleet_files where id=nullif(q->>(component||'_file_id'),'')::uuid and request_id=r.id and fleet_files.kind='quote_'||component) then
     raise exception 'أرفق عرض البند المطلوب لكل ورشة: %',case when component='parts' then 'قطع الغيار' else 'أجرة اليد' end;
    end if;
   elsif (q->>component)::numeric<>0 or nullif(q->>(component||'_file_id'),'') is not null then raise exception 'البند المستبعد لا يدخل في العرض';
   end if;
  end loop;
 end loop;
 foreach component in array array['parts','labor'] loop
  if exists(select 1 from jsonb_array_elements(r.quotes) x where coalesce(x->>'scope','parts_labor') in ('parts_labor',component)) then
   if (select count(distinct value->>(component||'_file_id')) from jsonb_array_elements(r.quotes) where coalesce(value->>'scope','parts_labor') in ('parts_labor',component)) <>
      (select count(*) from jsonb_array_elements(r.quotes) where coalesce(value->>'scope','parts_labor') in ('parts_labor',component)) then
    raise exception 'مرفق مستقل لكل ورشة مطلوب: %',case when component='parts' then 'قطع الغيار' else 'أجرة اليد' end;
   end if;
  end if;
 end loop;
end $$;
revoke all on function private.fleet_request_validate(private.fleet_requests) from public,anon,authenticated;

-- Remove only the unconditional parts-only assumptions; preserve current command,
-- state transitions, permissions, concurrency checks and financial reference fixes.
do $patch$
declare definition text; old_check text; new_check text;
begin
 select pg_get_functiondef('private.fleet_command(uuid,integer,text,jsonb)'::regprocedure) into definition;
 old_check := $old$if not exists(select 1 from private.fleet_files where id=(q->>'parts_file_id')::uuid and request_id=r.id and kind='quote_parts')then raise exception 'مرفق كل عرض مطلوب';end if;$old$;
 new_check := $new$if coalesce(q->>'scope','parts_labor')<>'labor' and not exists(select 1 from private.fleet_files where id=(q->>'parts_file_id')::uuid and request_id=r.id and kind='quote_parts')then raise exception 'مرفق كل عرض مطلوب';end if;$new$;
 if position(old_check in definition)=0 then raise exception 'Fleet attachment check differs; no changes applied'; end if;
 definition := replace(definition,old_check,new_check);
 old_check := $old$if(select count(distinct (value->>'parts_file_id')::uuid)from jsonb_array_elements(r.quotes))<>jsonb_array_length(r.quotes)then raise exception 'يجب إرفاق ملف مستقل لكل عرض سعر';end if;$old$;
 if position(old_check in definition)=0 then raise exception 'Fleet distinct attachment check differs; no changes applied'; end if;
 -- Conditional, request-bound distinct evidence is enforced by fleet_request_validate.
 definition := replace(definition,old_check,'');
 execute definition;
end $patch$;
