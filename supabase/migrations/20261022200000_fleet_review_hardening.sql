-- Fleet review fixes: custody boundaries, resumable writes and timed escalation.


create or replace function private.fleet_handover_save(p_id uuid,p_revision integer,p_data jsonb)returns uuid language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare h private.fleet_handovers%rowtype;v private.fleet_vehicles%rowtype;rid uuid:=coalesce(p_id,gen_random_uuid());m jsonb;employee uuid;
begin
 perform private.require_module('fleet');if not private.fleet_has('fleet.vehicles.write')then raise exception 'Vehicle management denied'using errcode='42501';end if;
 if p_id is not null then select * into strict h from private.fleet_handovers where id=p_id for update;if h.state<>'draft' or h.revision is distinct from p_revision then raise exception 'المحضر غير قابل للتعديل أو تم تحديثه'using errcode='40001';end if;end if;
 select * into strict v from private.fleet_vehicles where id=(p_data->>'vehicle_id')::uuid for update;
 if p_id is not null and h.vehicle_id<>v.id then raise exception 'لا يمكن تغيير السيارة في المحضر';end if;
 if exists(select 1 from private.fleet_requests where vehicle_id=v.id and state not in('closed','rejected','draft','returned'))then raise exception 'أكمل طلبات الصيانة المفتوحة قبل نقل العهدة';end if;
 if not v.active then raise exception 'السيارة موقوفة في السجل';end if;
 if p_data->>'kind' not in('issue','return')or p_data->>'kind' is null then raise exception 'حدد نوع المحضر';end if;
 employee:=case when p_data->>'kind'='return'then v.driver_id else (p_data->>'employee_id')::uuid end;
 if employee is null or not exists(select 1 from private.hr_employees where id=employee)then raise exception 'حدد الموظف المعني';end if;
 if exists(select 1 from private.hr_employees where id=employee and profile_id=auth.uid())then raise exception 'إعداد محضر سيارتك يتطلب مسؤولًا آخر';end if;
 if p_data->>'kind'='issue'and v.driver_id is not null then raise exception 'يجب استلام السيارة من عهدة السائق الحالي أولًا';end if;
 if (p_data->>'odometer')::integer<v.odometer then raise exception 'قراءة العداد أقل من السجل';end if;
 if jsonb_typeof(p_data->'marks')is distinct from 'array'or jsonb_array_length(p_data->'marks')>40 then raise exception 'ملاحظات المخطط غير صالحة';end if;
 for m in select value from jsonb_array_elements(p_data->'marks')loop
  if m->>'part' is null or m->>'part'not in('front_bumper','hood','windshield','roof','rear_window','trunk','rear_bumper','left_front_fender','left_front_door','left_rear_door','left_rear_fender','right_front_fender','right_front_door','right_rear_door','right_rear_fender','left_front_tire','left_rear_tire','right_front_tire','right_rear_tire','interior','other')or m->>'severity' is null or m->>'severity'not in('scratch','dent','broken','other')or length(btrim(coalesce(m->>'note','')))not between 3 and 500 then raise exception 'حدد موضع كل ملاحظة ونوعها ووصفها';end if;
 end loop;
 if jsonb_array_length(p_data->'marks')>0 and coalesce((p_data->>'no_marks')::boolean,false)then raise exception 'لا يمكن الإقرار بعدم وجود ملاحظات مع تسجيل ملاحظات';end if;
 insert into private.fleet_handovers(id,vehicle_id,employee_id,kind,vehicle_revision,previous_driver_id,odometer,fuel_level,keys_count,spare_tire,tools,marks,no_marks,notes,created_by)
 values(rid,v.id,employee,p_data->>'kind',v.revision,v.driver_id,(p_data->>'odometer')::integer,(p_data->>'fuel_level')::integer,(p_data->>'keys_count')::integer,(p_data->>'spare_tire')::boolean,(p_data->>'tools')::boolean,p_data->'marks',coalesce((p_data->>'no_marks')::boolean,false),coalesce(p_data->>'notes',''),auth.uid())
 on conflict(id)do update set employee_id=excluded.employee_id,kind=excluded.kind,vehicle_revision=excluded.vehicle_revision,previous_driver_id=excluded.previous_driver_id,odometer=excluded.odometer,fuel_level=excluded.fuel_level,keys_count=excluded.keys_count,spare_tire=excluded.spare_tire,tools=excluded.tools,marks=excluded.marks,no_marks=excluded.no_marks,notes=excluded.notes,revision=private.fleet_handovers.revision+1,updated_at=now();
 insert into private.fleet_events(vehicle_id,actor_id,action,payload)values(v.id,auth.uid(),'handover_draft',jsonb_build_object('handover_id',rid));return rid;
end$$;

create or replace function private.fleet_handover_command(p_id uuid,p_revision integer,p_action text,p_reason text default '')returns jsonb language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare h private.fleet_handovers%rowtype;v private.fleet_vehicles%rowtype;driver_profile uuid;prior text;recipient uuid;
begin
 perform private.require_module('fleet');select * into strict h from private.fleet_handovers where id=p_id for update;
 if not private.fleet_handover_visible(h)then raise exception 'Access denied'using errcode='42501';end if;
 if h.revision is distinct from p_revision then raise exception 'تم تحديث المحضر، حدّث الصفحة'using errcode='40001';end if;
 prior:=h.state;select profile_id into driver_profile from private.hr_employees where id=h.employee_id;
 if p_action='submit'and h.state='draft'and private.fleet_has('fleet.vehicles.write')then
  if jsonb_array_length(h.marks)=0 and not h.no_marks then raise exception 'سجل ملاحظات المخطط أو أكد عدم وجود ملاحظات ظاهرة';end if;
  if driver_profile is null or driver_profile=h.created_by or not exists(select 1 from public.profiles where id=driver_profile and active and status='active'and(role='admin'or'fleet'=any(allowed_modules)))then raise exception 'يلزم حساب أسطول نشط للموظف، مختلف عن معد المحضر';end if;
  select * into strict v from private.fleet_vehicles where id=h.vehicle_id for update;
  if exists(select 1 from private.fleet_requests where vehicle_id=v.id and state not in('closed','rejected','draft','returned'))then raise exception 'أكمل طلبات الصيانة المفتوحة قبل نقل العهدة';end if;
   if not v.active or v.driver_id is distinct from h.previous_driver_id or v.revision<>h.vehicle_revision then raise exception 'تغير سجل السيارة؛ حدّث مسودة المحضر';end if;
  h.state:='pending_driver';h.submitted_at:=now();
  h.snapshot:=jsonb_build_object('vehicle',to_jsonb(v),'employee',(select jsonb_build_object('name',full_name,'code',employee_code)from private.hr_employees where id=h.employee_id),'prepared_by',(select full_name from public.profiles where id=h.created_by));
 elsif p_action in('accept','dispute')and h.state='pending_driver'and driver_profile=auth.uid()and h.created_by<>auth.uid()then
  if p_action='dispute'then
   if length(btrim(coalesce(p_reason,'')))not between 3 and 1000 then raise exception 'سبب الاعتراض مطلوب';end if;h.state:='disputed';h.response:=p_reason;
  else
   select * into strict v from private.fleet_vehicles where id=h.vehicle_id for update;
   if exists(select 1 from private.fleet_requests where vehicle_id=v.id and state not in('closed','rejected','draft','returned'))then raise exception 'أكمل طلبات الصيانة المفتوحة قبل نقل العهدة';end if;
   if not v.active or v.driver_id is distinct from h.previous_driver_id or v.revision<>h.vehicle_revision or h.odometer<v.odometer then raise exception 'تغير سجل السيارة؛ يجب إعداد محضر جديد';end if;
   update private.fleet_vehicles set driver_id=case when h.kind='issue'then h.employee_id else null end,odometer=h.odometer,revision=revision+1,updated_at=now()where id=h.vehicle_id;
   h.state:='accepted';
  end if;
  h.acknowledged_by:=auth.uid();h.acknowledged_at:=now();
 elsif p_action='cancel'and h.state in('draft','pending_driver')and private.fleet_has('fleet.vehicles.write')then
  if length(btrim(coalesce(p_reason,'')))not between 3 and 1000 then raise exception 'سبب الإلغاء مطلوب';end if;h.state:='cancelled';h.response:=p_reason;
 else raise exception 'الإجراء غير مسموح لهذه الحالة أو الصلاحية'using errcode='42501';end if;
 update private.fleet_handovers set state=h.state,snapshot=h.snapshot,response=h.response,acknowledged_by=h.acknowledged_by,acknowledged_at=h.acknowledged_at,submitted_at=h.submitted_at,revision=revision+1,updated_at=now()where id=p_id;
 insert into private.fleet_events(vehicle_id,actor_id,action,from_state,to_state,payload)values(h.vehicle_id,auth.uid(),'handover_'||p_action,prior,h.state,jsonb_build_object('handover_id',h.id,'reason',p_reason));
 if h.state='pending_driver'then recipient:=driver_profile;else recipient:=h.created_by;end if;
 perform private.fleet_workflow_notify('handover',h.id,h.revision+1,recipient,'stage','محضر سيارة #'||h.number||case when h.state='pending_driver'then ' بانتظار إقرارك'else ' — تم تحديث الحالة'end,h.vehicle_id);
 return private.fleet_handover_detail(p_id);
end$$;

create or replace function private.fleet_handover_upload(p_id uuid,p_name text,p_mime text,p_base64 text)returns uuid language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare h private.fleet_handovers%rowtype;v bytea;rid uuid;
begin
 perform private.require_module('fleet');select * into strict h from private.fleet_handovers where id=p_id for update;
 if not private.fleet_has('fleet.vehicles.write')or h.state<>'draft'or exists(select 1 from private.hr_employees where id=h.employee_id and profile_id=auth.uid())then raise exception 'Upload denied'using errcode='42501';end if;
 if p_mime not in('image/png','image/jpeg')or p_mime is null or length(p_base64)>6990510 then raise exception 'صور PNG أو JPEG حتى 5 ميجابايت فقط';end if;
 v:=decode(p_base64,'base64');
 if not((p_mime='image/png'and substring(v from 1 for 8)=decode('89504e470d0a1a0a','hex'))or(p_mime='image/jpeg'and substring(v from 1 for 3)=decode('ffd8ff','hex')))then raise exception 'صورة صالحة مطلوبة';end if;
 select id into rid from private.fleet_handover_photos where handover_id=p_id and mime=p_mime and bytes=v limit 1;
 if rid is not null then return rid;end if;
 if(select coalesce(sum(octet_length(bytes)),0)from private.fleet_handover_photos where handover_id=p_id)+octet_length(v)>31457280 then raise exception 'الحد الإجمالي 30 ميجابايت';end if;
 insert into private.fleet_handover_photos(handover_id,name,mime,bytes,actor_id)values(p_id,p_name,p_mime,v,auth.uid())returning id into rid;return rid;
end$$;

create or replace function private.fleet_vehicle_save(p_id uuid,p_revision integer,p_data jsonb,p_reason text)returns uuid language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare v private.fleet_vehicles%rowtype;
begin perform private.require_module('fleet');if not private.fleet_has('fleet.vehicles.write')then raise exception 'Vehicle management denied'using errcode='42501';end if;
 if p_id is null and nullif(p_data->>'driver_id','')is not null then raise exception 'إسناد السيارة الجديدة يتطلب محضر تسليم وإقرار الموظف';end if;
 if p_id is not null then select * into strict v from private.fleet_vehicles where id=p_id for update;if v.driver_id is distinct from nullif(p_data->>'driver_id','')::uuid then raise exception 'تغيير العهدة يتطلب محضر تسليم واستلام';end if;end if;
 return private.fleet_vehicle_save_before_operations(p_id,p_revision,p_data,p_reason);
end$$;



-- Imports can update existing records, but cannot silently initialize a driver's custody.
-- All new assignments, including imported cars, require an acknowledged report.
alter table private.fleet_handovers add column save_token uuid unique,add column save_actor_id uuid references public.profiles(id),add column save_payload jsonb,add column saved_revision integer;
create function private.fleet_handover_save_retry(p_token uuid,p_id uuid,p_revision integer,p_data jsonb)returns uuid language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare h private.fleet_handovers%rowtype;rid uuid;
begin
 perform private.require_module('fleet');if not private.fleet_has('fleet.vehicles.write')then raise exception 'Vehicle management denied'using errcode='42501';end if;
 if p_token is null then raise exception 'معرف الحفظ مطلوب';end if;
 perform pg_advisory_xact_lock(hashtext(p_token::text));
 select * into h from private.fleet_handovers where save_token=p_token for update;
 if h.id is not null then
  if h.save_actor_id is distinct from auth.uid()or h.save_payload is distinct from p_data or h.state<>'draft'or h.revision<>h.saved_revision or(p_id is not null and p_id<>h.id)then raise exception 'تغير المحضر، افتحه من جديد قبل الحفظ'using errcode='40001';end if;
  return h.id;
 end if;
 rid:=private.fleet_handover_save(p_id,p_revision,p_data);
 update private.fleet_handovers set save_token=p_token,save_actor_id=auth.uid(),save_payload=p_data,saved_revision=revision where id=rid;
 return rid;
end$$;
create function public.fleet_handover_save_retry(p_token uuid,p_id uuid,p_revision integer,p_data jsonb)returns uuid language sql security invoker set search_path=pg_catalog,private as $$select private.fleet_handover_save_retry(p_token,p_id,p_revision,p_data)$$;
revoke all on function private.fleet_handover_save_retry(uuid,uuid,integer,jsonb),public.fleet_handover_save_retry(uuid,uuid,integer,jsonb)from public,anon;
grant execute on function private.fleet_handover_save_retry(uuid,uuid,integer,jsonb),public.fleet_handover_save_retry(uuid,uuid,integer,jsonb)to authenticated;
alter table private.fleet_workflow_settings add column escalation_days integer not null default 3 check(escalation_days between 1 and 365);
create function private.fleet_escalation_settings_save(p_revision integer,p_days integer)returns void language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare s private.fleet_workflow_settings%rowtype;
begin perform private.require_module('fleet');if not private.is_admin()then raise exception 'Administrator access required'using errcode='42501';end if;
 select * into strict s from private.fleet_workflow_settings for update;
 if s.revision is distinct from p_revision then raise exception 'تم تحديث الإعدادات، حدّث الصفحة'using errcode='40001';end if;
 update private.fleet_workflow_settings set escalation_days=p_days,revision=revision+1;
 perform private.access_log('FLEET_ESCALATION_SETTINGS','fleet',to_jsonb(s),jsonb_build_object('escalation_days',p_days));
end$$;
create function public.fleet_escalation_settings_save(p_revision integer,p_days integer)returns void language sql security invoker set search_path=pg_catalog,private as $$select private.fleet_escalation_settings_save(p_revision,p_days)$$;
revoke all on function private.fleet_escalation_settings_save(integer,integer),public.fleet_escalation_settings_save(integer,integer)from public,anon;
grant execute on function private.fleet_escalation_settings_save(integer,integer),public.fleet_escalation_settings_save(integer,integer)to authenticated;
alter function private.process_fleet_workflow_alerts()rename to process_fleet_workflow_alerts_before_review;
revoke all on function private.process_fleet_workflow_alerts_before_review()from public,anon,authenticated;
create function private.process_fleet_workflow_alerts()returns integer language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare s private.fleet_workflow_settings%rowtype;x record;recipient uuid;owner_id uuid;level_no integer;n integer;
begin
 perform pg_advisory_xact_lock(hashtext('fleet_workflow_alerts'));
 n:=private.process_fleet_workflow_alerts_before_review();select * into strict s from private.fleet_workflow_settings;
 begin owner_id:=private.fleet_owner();exception when raise_exception then owner_id:=null;end;
 for x in
  select 'request'kind,r.id,r.vehicle_id,r.revision,r.number,least(r.state_changed_at+make_interval(days=>s.stage_days),case when r.advance>0 then(select min(created_at)+make_interval(days=>s.advance_days)from private.fleet_payments p where p.request_id=r.id and p.kind='advance')end)due from private.fleet_requests r where r.state not in('draft','closed','rejected')
  union all select 'handover',h.id,h.vehicle_id,h.revision,h.number,h.submitted_at+make_interval(days=>s.handover_days)from private.fleet_handovers h where h.state='pending_driver'
 loop
  for level_no in 1..2 loop
   if now()<x.due+make_interval(days=>s.escalation_days*level_no)then continue;end if;
   for recipient in select p.id from public.profiles p where p.active and p.status='active'and(p.role='admin'or'fleet'=any(p.allowed_modules))and(case when level_no=1 and owner_id is not null then p.id=owner_id else p.role='admin'end)loop
    n:=n+private.fleet_workflow_notify(x.kind,x.id,x.revision,recipient,'escalation_'||level_no,'تصعيد متابعة '||case when x.kind='request'then 'طلب صيانة #'else 'محضر سيارة #'end||x.number||' — المستوى '||level_no,x.vehicle_id);
   end loop;
  end loop;
 end loop;return n;
end$$;
revoke all on function private.process_fleet_workflow_alerts()from public,anon,authenticated;
