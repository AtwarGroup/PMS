-- Vehicle operations, accountable handovers and in-app workflow alerts.
alter table private.fleet_requests add column state_changed_at timestamptz not null default now();
update private.fleet_requests r set state_changed_at=coalesce((select max(e.created_at)from private.fleet_events e where e.request_id=r.id and e.from_state is distinct from e.to_state and e.to_state=r.state),r.created_at);
alter table private.fleet_vehicles add column operational_status text not null default 'available' check(operational_status in('available','maintenance','stopped'));
alter table private.fleet_vehicles add column operational_since timestamptz not null default now();
alter table private.fleet_vehicles add column operational_reason text not null default '';
create table private.fleet_operation_periods(id uuid primary key default gen_random_uuid(),vehicle_id uuid not null references private.fleet_vehicles(id),status text not null check(status in('available','maintenance','stopped')),started_at timestamptz not null default now(),ended_at timestamptz,reason text not null,actor_id uuid not null references public.profiles(id),check(ended_at is null or ended_at>=started_at));
create index fleet_operation_vehicle_idx on private.fleet_operation_periods(vehicle_id,started_at desc);
create unique index fleet_operation_open_idx on private.fleet_operation_periods(vehicle_id)where ended_at is null;
create table private.fleet_workflow_settings(id boolean primary key default true check(id),stage_days integer not null default 3 check(stage_days between 1 and 365),advance_days integer not null default 7 check(advance_days between 1 and 365),handover_days integer not null default 3 check(handover_days between 1 and 365),revision integer not null default 1);
insert into private.fleet_workflow_settings(id)values(true);
create table private.fleet_handovers(
 id uuid primary key default gen_random_uuid(),number bigint generated always as identity unique,
 vehicle_id uuid not null references private.fleet_vehicles(id),employee_id uuid not null references private.hr_employees(id),kind text not null check(kind in('issue','return')),
 state text not null default 'draft' check(state in('draft','pending_driver','accepted','disputed','cancelled')),
 vehicle_revision integer not null,previous_driver_id uuid references private.hr_employees(id),odometer integer not null check(odometer>=0),fuel_level integer not null check(fuel_level in(0,25,50,75,100)),
 keys_count integer not null check(keys_count between 0 and 5),spare_tire boolean not null,tools boolean not null,
 marks jsonb not null default '[]' check(jsonb_typeof(marks)='array'),no_marks boolean not null default false,notes text not null default '' check(length(notes)<=2000),
 snapshot jsonb,created_by uuid not null references public.profiles(id),acknowledged_by uuid references public.profiles(id),acknowledged_at timestamptz,response text,
 revision integer not null default 1,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),submitted_at timestamptz);
create unique index fleet_handover_open_vehicle_idx on private.fleet_handovers(vehicle_id)where state in('draft','pending_driver');
create index fleet_handover_employee_idx on private.fleet_handovers(employee_id,created_at desc);
create table private.fleet_handover_photos(id uuid primary key default gen_random_uuid(),handover_id uuid not null references private.fleet_handovers(id),name text not null check(length(name)between 1 and 150),mime text not null check(mime in('image/png','image/jpeg')),bytes bytea not null check(octet_length(bytes)between 1 and 5242880),actor_id uuid not null references public.profiles(id),created_at timestamptz not null default now());
create index fleet_handover_photo_idx on private.fleet_handover_photos(handover_id);
create table private.fleet_workflow_deliveries(entity_type text not null,entity_id uuid not null,revision integer not null,recipient_id uuid not null references public.profiles(id),phase text not null,created_at timestamptz not null default now(),primary key(entity_type,entity_id,revision,recipient_id,phase));
alter table public.notifications add column fleet_request_id uuid references private.fleet_requests(id);
alter table public.notifications add column fleet_handover_id uuid references private.fleet_handovers(id);
create index notification_fleet_request_idx on public.notifications(fleet_request_id)where fleet_request_id is not null;
create index notification_fleet_handover_idx on public.notifications(fleet_handover_id)where fleet_handover_id is not null;
do $$declare t text;begin foreach t in array array['fleet_operation_periods','fleet_workflow_settings','fleet_handovers','fleet_handover_photos','fleet_workflow_deliveries']loop execute format('alter table private.%I enable row level security',t);execute format('revoke all on private.%I from public,anon,authenticated',t);end loop;end$$;

create function private.fleet_handover_visible(h private.fleet_handovers)returns boolean language sql stable security definer set search_path=pg_catalog,public,private as $$
 select private.current_user_is_active()and private.module_allowed('fleet')and(private.fleet_has('fleet.vehicles.write')or(h.state<>'draft'and exists(select 1 from private.hr_employees e where e.id=h.employee_id and e.profile_id=auth.uid()))or(h.state<>'draft'and not private.fleet_finance_only()and exists(select 1 from private.hr_employees e join private.hr_employees m on m.id=e.manager_id where e.id=h.employee_id and m.profile_id=auth.uid())))
$$;
create function private.fleet_request_responsibles(r private.fleet_requests)returns uuid[] language plpgsql stable security definer set search_path=pg_catalog,public,private as $$
declare driver uuid;owner_id uuid;wanted uuid[];
begin
 select profile_id into driver from private.hr_employees where id=r.driver_id;
 if r.state in('quote_exception','fleet_review','increase_review')then
  begin owner_id:=private.fleet_owner();exception when raise_exception then owner_id:=null;end;
  if owner_id is null or owner_id=driver then select array_agg(id)into wanted from public.profiles where role='admin'and id is distinct from driver;
  else wanted:=array[owner_id];end if;
 elsif r.state='manager_review'then wanted:=array[r.manager_id];
 elsif r.state in('awaiting_advance','reimbursement','settlement')then wanted:=array[r.accountant_id];
 elsif r.state in('returned','repair','draft')then wanted:=array[driver];
 else return '{}';end if;
 wanted:=array(select p.id from public.profiles p where p.id=any(wanted)and p.active and p.status='active'and(p.role='admin'or'fleet'=any(p.allowed_modules))and(r.state in('returned','repair','draft')or p.id is distinct from driver)and(r.state not in('awaiting_advance','reimbursement','settlement')or p.role='admin'or exists(select 1 from private.access_direct_tasks d where d.profile_id=p.id and 'fleet.finance'=any(d.permissions))or exists(select 1 from private.access_assignments a join private.access_roles ar on ar.id=a.role_id and ar.active join private.access_role_rules rr on rr.role_id=ar.id where a.profile_id=p.id and rr.permission='fleet.finance')));
 if cardinality(wanted)=0 then wanted:=array(select id from public.profiles where role='admin'and active and status='active'and(id is distinct from driver or r.state in('returned','repair','draft')));end if;
 return wanted;
end$$;
create function private.fleet_journey(r private.fleet_requests)returns jsonb language sql stable security definer set search_path=pg_catalog,public,private as $$
 select jsonb_build_object('state_since',r.state_changed_at,'waiting_days',floor(greatest(0,extract(epoch from(now()-r.state_changed_at))/86400))::integer,'responsibles',(select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.full_name)),'[]')from public.profiles p where p.id=any(private.fleet_request_responsibles(r))))
$$;
alter function private.fleet_snapshot()rename to fleet_snapshot_before_operations;
alter function private.fleet_detail(uuid)rename to fleet_detail_before_operations;
revoke all on function private.fleet_snapshot_before_operations(),private.fleet_detail_before_operations(uuid)from public,anon,authenticated;
create function private.fleet_snapshot()returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,private as $$
declare result jsonb;
begin
 perform private.require_module('fleet');result:=private.fleet_snapshot_before_operations();
 return result||jsonb_build_object('requests',(select coalesce(jsonb_agg(x.value||jsonb_build_object('journey',private.fleet_journey(r))order by r.number desc),'[]')from jsonb_array_elements(result->'requests')x join private.fleet_requests r on r.id=(x.value->>'id')::uuid));
end$$;
create function private.fleet_detail(p_id uuid)returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,private as $$
declare result jsonb;r private.fleet_requests%rowtype;
begin perform private.require_module('fleet');result:=private.fleet_detail_before_operations(p_id);select * into strict r from private.fleet_requests where id=p_id;return result||jsonb_build_object('journey',private.fleet_journey(r));end$$;

create function private.fleet_workflow_notify(p_type text,p_id uuid,p_revision integer,p_recipient uuid,p_phase text,p_title text,p_vehicle uuid)returns integer language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare n integer;
begin
 if p_recipient is null or not exists(select 1 from public.profiles where id=p_recipient and active and status='active'and(role='admin'or'fleet'=any(allowed_modules)))then return 0;end if;
 insert into private.fleet_workflow_deliveries(entity_type,entity_id,revision,recipient_id,phase)values(p_type,p_id,p_revision,p_recipient,p_phase)on conflict do nothing;get diagnostics n=row_count;
 if n>0 then insert into public.notifications(recipient_id,type,title,message,fleet_vehicle_id,fleet_request_id,fleet_handover_id)values(p_recipient,case when p_type='request'then 'FLEET_WORKFLOW'else 'FLEET_HANDOVER'end,p_title,'افتح السجل لمراجعة التفاصيل والإجراء المتاح لك.',p_vehicle,case when p_type='request'then p_id end,case when p_type='handover'then p_id end);end if;
 return n;
end$$;
create function private.fleet_request_stage_trigger()returns trigger language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare recipient uuid;driver uuid;
begin
 if TG_WHEN='BEFORE'then if new.state is distinct from old.state then new.state_changed_at:=now();end if;return new;end if;
 if new.state is distinct from old.state then
  foreach recipient in array private.fleet_request_responsibles(new)loop perform private.fleet_workflow_notify('request',new.id,new.revision,recipient,'stage','طلب صيانة #'||new.number||' بانتظار إجرائك',new.vehicle_id);end loop;
  select profile_id into driver from private.hr_employees where id=new.driver_id;
  if new.state in('closed','rejected')then perform private.fleet_workflow_notify('request',new.id,new.revision,driver,'stage',case when new.state='closed'then 'أُغلق طلب الصيانة #'else 'رُفض طلب الصيانة #'end||new.number,new.vehicle_id);end if;
 end if;return new;
end$$;
create trigger fleet_request_stage_before before update on private.fleet_requests for each row execute function private.fleet_request_stage_trigger();
create trigger fleet_request_stage_after after update on private.fleet_requests for each row execute function private.fleet_request_stage_trigger();

create function private.fleet_vehicle_operation_save(p_vehicle uuid,p_revision integer,p_status text,p_reason text)returns void language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare v private.fleet_vehicles%rowtype;
begin
 perform private.require_module('fleet');if not private.fleet_has('fleet.vehicles.write')then raise exception 'Vehicle management denied'using errcode='42501';end if;
 select * into strict v from private.fleet_vehicles where id=p_vehicle for update;
 if v.revision is distinct from p_revision then raise exception 'تم تحديث السيارة، حدّث الصفحة'using errcode='40001';end if;
 if p_status is null or p_status not in('available','maintenance','stopped')or length(btrim(coalesce(p_reason,'')))not between 3 and 1000 then raise exception 'حدد حالة التشغيل والسبب';end if;
 if p_status=v.operational_status then raise exception 'حالة التشغيل لم تتغير';end if;
 update private.fleet_operation_periods set ended_at=now()where vehicle_id=p_vehicle and ended_at is null;
 insert into private.fleet_operation_periods(vehicle_id,status,reason,actor_id)values(p_vehicle,p_status,p_reason,auth.uid());
 update private.fleet_vehicles set operational_status=p_status,operational_reason=p_reason,operational_since=now(),revision=revision+1,updated_at=now()where id=p_vehicle;
 insert into private.fleet_events(vehicle_id,actor_id,action,from_state,to_state,payload)values(p_vehicle,auth.uid(),'operation_status',v.operational_status,p_status,jsonb_build_object('reason',p_reason));
end$$;

create function private.fleet_handover_save(p_id uuid,p_revision integer,p_data jsonb)returns uuid language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare h private.fleet_handovers%rowtype;v private.fleet_vehicles%rowtype;rid uuid:=coalesce(p_id,gen_random_uuid());m jsonb;employee uuid;
begin
 perform private.require_module('fleet');if not private.fleet_has('fleet.vehicles.write')then raise exception 'Vehicle management denied'using errcode='42501';end if;
 if p_id is not null then select * into strict h from private.fleet_handovers where id=p_id for update;if h.state<>'draft' or h.revision is distinct from p_revision then raise exception 'المحضر غير قابل للتعديل أو تم تحديثه'using errcode='40001';end if;end if;
 select * into strict v from private.fleet_vehicles where id=(p_data->>'vehicle_id')::uuid for update;
 if p_id is not null and h.vehicle_id<>v.id then raise exception 'لا يمكن تغيير السيارة في المحضر';end if;
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
create function private.fleet_handover_detail(p_id uuid)returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,private as $$
declare h private.fleet_handovers%rowtype;
begin perform private.require_module('fleet');select * into strict h from private.fleet_handovers where id=p_id;if not private.fleet_handover_visible(h)then raise exception 'Access denied'using errcode='42501';end if;
 return jsonb_build_object('handover',to_jsonb(h),'employee_name',(select full_name from private.hr_employees where id=h.employee_id),'plate',(select plate from private.fleet_vehicles where id=h.vehicle_id),'photos',(select coalesce(jsonb_agg(to_jsonb(f)-'bytes'order by created_at),'[]')from private.fleet_handover_photos f where handover_id=p_id),'can_manage',private.fleet_has('fleet.vehicles.write'),'can_acknowledge',h.state='pending_driver'and h.created_by<>auth.uid()and exists(select 1 from private.hr_employees where id=h.employee_id and profile_id=auth.uid()));
end$$;
create function private.fleet_handover_upload(p_id uuid,p_name text,p_mime text,p_base64 text)returns uuid language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare h private.fleet_handovers%rowtype;v bytea;rid uuid;
begin
 perform private.require_module('fleet');select * into strict h from private.fleet_handovers where id=p_id for update;
 if not private.fleet_has('fleet.vehicles.write')or h.state<>'draft'or exists(select 1 from private.hr_employees where id=h.employee_id and profile_id=auth.uid())then raise exception 'Upload denied'using errcode='42501';end if;
 if p_mime not in('image/png','image/jpeg')or p_mime is null or length(p_base64)>6990510 then raise exception 'صور PNG أو JPEG حتى 5 ميجابايت فقط';end if;
 v:=decode(p_base64,'base64');
 if not((p_mime='image/png'and substring(v from 1 for 8)=decode('89504e470d0a1a0a','hex'))or(p_mime='image/jpeg'and substring(v from 1 for 3)=decode('ffd8ff','hex')))then raise exception 'صورة صالحة مطلوبة';end if;
 if(select coalesce(sum(octet_length(bytes)),0)from private.fleet_handover_photos where handover_id=p_id)+octet_length(v)>31457280 then raise exception 'الحد الإجمالي 30 ميجابايت';end if;
 insert into private.fleet_handover_photos(handover_id,name,mime,bytes,actor_id)values(p_id,p_name,p_mime,v,auth.uid())returning id into rid;return rid;
end$$;
create function private.fleet_handover_photo(p_id uuid)returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,private as $$
declare f private.fleet_handover_photos%rowtype;h private.fleet_handovers%rowtype;
begin perform private.require_module('fleet');select * into strict f from private.fleet_handover_photos where id=p_id;select * into strict h from private.fleet_handovers where id=f.handover_id;if not private.fleet_handover_visible(h)then raise exception 'Access denied'using errcode='42501';end if;return jsonb_build_object('name',f.name,'mime',f.mime,'base64',encode(f.bytes,'base64'));end$$;
create function private.fleet_handover_command(p_id uuid,p_revision integer,p_action text,p_reason text default '')returns jsonb language plpgsql security definer set search_path=pg_catalog,public,private as $$
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
  if not v.active or v.driver_id is distinct from h.previous_driver_id or v.revision<>h.vehicle_revision then raise exception 'تغير سجل السيارة؛ حدّث مسودة المحضر';end if;
  h.state:='pending_driver';h.submitted_at:=now();
  h.snapshot:=jsonb_build_object('vehicle',to_jsonb(v),'employee',(select jsonb_build_object('name',full_name,'code',employee_code)from private.hr_employees where id=h.employee_id),'prepared_by',(select full_name from public.profiles where id=h.created_by));
 elsif p_action in('accept','dispute')and h.state='pending_driver'and driver_profile=auth.uid()and h.created_by<>auth.uid()then
  if p_action='dispute'then
   if length(btrim(coalesce(p_reason,'')))not between 3 and 1000 then raise exception 'سبب الاعتراض مطلوب';end if;h.state:='disputed';h.response:=p_reason;
  else
   select * into strict v from private.fleet_vehicles where id=h.vehicle_id for update;
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

create function private.fleet_vehicle_profile(p_vehicle uuid)returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,private as $$
declare v private.fleet_vehicles%rowtype;
begin
 perform private.require_module('fleet');select * into strict v from private.fleet_vehicles where id=p_vehicle;
 if not private.fleet_document_visible(v.id)then raise exception 'Access denied'using errcode='42501';end if;
 return jsonb_build_object('vehicle',to_jsonb(v),'driver_name',(select full_name from private.hr_employees where id=v.driver_id),
 'documents',(select coalesce(jsonb_agg(to_jsonb(d)||jsonb_build_object('days_before',s.days_before)order by d.kind),'[]')from private.fleet_documents d join private.fleet_alert_settings s on s.kind=d.kind where d.vehicle_id=v.id and(d.kind<>'authorization'or d.authorized_driver_id=v.driver_id)),
 'requests',(select coalesce(jsonb_agg(to_jsonb(r)||jsonb_build_object('journey',private.fleet_journey(r))order by r.number desc),'[]')from private.fleet_requests r where r.vehicle_id=v.id and private.fleet_visible(r)),
 'handovers',(select coalesce(jsonb_agg(to_jsonb(h)-'snapshot'order by h.number desc),'[]')from private.fleet_handovers h where h.vehicle_id=v.id and private.fleet_handover_visible(h)),
 'operation_periods',(select coalesce(jsonb_agg(to_jsonb(o)||jsonb_build_object('actor_name',p.full_name)order by o.started_at desc),'[]')from private.fleet_operation_periods o join public.profiles p on p.id=o.actor_id where o.vehicle_id=v.id),
 'events',(select coalesce(jsonb_agg(to_jsonb(e)||jsonb_build_object('actor_name',p.full_name)order by e.id desc),'[]')from private.fleet_events e join public.profiles p on p.id=e.actor_id where e.vehicle_id=v.id and((e.request_id is null and e.action in('operation_status','vehicle_saved','document_saved'))or exists(select 1 from private.fleet_requests r where r.id=e.request_id and private.fleet_visible(r)))));
end$$;
create function private.fleet_operations_context()returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,private as $$
declare s private.fleet_workflow_settings%rowtype;
begin perform private.require_module('fleet');select * into strict s from private.fleet_workflow_settings;
 return jsonb_build_object('settings',to_jsonb(s),'can_configure',private.is_admin(),
 'overdue_requests',(select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'number',r.number,'state',r.state,'plate',v.plate,'journey',private.fleet_journey(r))order by r.state_changed_at),'[]')from private.fleet_requests r join private.fleet_vehicles v on v.id=r.vehicle_id where private.fleet_visible(r)and r.state not in('draft','closed','rejected')and r.state_changed_at<=now()-make_interval(days=>s.stage_days)),
 'advances',(select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'number',r.number,'plate',v.plate,'advance',r.advance,'since',a.since,'overdue',a.since<=now()-make_interval(days=>s.advance_days))order by a.since),'[]')from private.fleet_requests r join private.fleet_vehicles v on v.id=r.vehicle_id left join lateral(select min(created_at)since from private.fleet_payments p where p.request_id=r.id and p.kind='advance')a on true where private.fleet_visible(r)and r.advance>0 and r.state not in('closed','rejected')),
 'documents',(select coalesce(jsonb_agg(jsonb_build_object('vehicle_id',v.id,'plate',v.plate,'kind',d.kind,'expires_on',d.expires_on,'expired',d.expires_on<timezone('Asia/Riyadh',now())::date)order by d.expires_on),'[]')from private.fleet_documents d join private.fleet_vehicles v on v.id=d.vehicle_id join private.fleet_alert_settings ds on ds.kind=d.kind where v.active and private.fleet_document_visible(v.id)and(d.kind<>'authorization'or d.authorized_driver_id=v.driver_id)and d.expires_on<=timezone('Asia/Riyadh',now())::date+ds.days_before),
 'unassigned',(select coalesce(jsonb_agg(jsonb_build_object('id',v.id,'plate',v.plate)),'[]')from private.fleet_vehicles v where v.active and v.driver_id is null and private.fleet_document_visible(v.id)),
 'unavailable',(select coalesce(jsonb_agg(to_jsonb(v)order by v.operational_since),'[]')from private.fleet_vehicles v where v.active and v.operational_status<>'available'and private.fleet_document_visible(v.id)),
 'handovers',(select coalesce(jsonb_agg(x.data order by x.number desc),'[]')from(select h.number,to_jsonb(h)-'snapshot'||jsonb_build_object('plate',v.plate,'employee_name',e.full_name,'overdue',h.state='pending_driver'and h.submitted_at<=now()-make_interval(days=>s.handover_days))data from private.fleet_handovers h join private.fleet_vehicles v on v.id=h.vehicle_id join private.hr_employees e on e.id=h.employee_id where private.fleet_handover_visible(h)order by h.number desc limit 200)x));
end$$;
create function private.process_fleet_workflow_alerts()returns integer language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare r private.fleet_requests%rowtype;h private.fleet_handovers%rowtype;s private.fleet_workflow_settings%rowtype;recipient uuid;n integer:=0;
begin
 perform pg_advisory_xact_lock(hashtext('fleet_workflow_alerts'));select * into strict s from private.fleet_workflow_settings;
 for r in select * from private.fleet_requests where state not in('draft','closed','rejected')and state_changed_at<=now()-make_interval(days=>s.stage_days)loop
  foreach recipient in array private.fleet_request_responsibles(r)loop n:=n+private.fleet_workflow_notify('request',r.id,r.revision,recipient,'overdue','تذكير: طلب صيانة #'||r.number||' متأخر عن المدة المحددة',r.vehicle_id);end loop;
 end loop;
 for r in select q.* from private.fleet_requests q where q.advance>0 and q.state not in('closed','rejected')and exists(select 1 from private.fleet_payments p where p.request_id=q.id and p.kind='advance'and p.created_at<=now()-make_interval(days=>s.advance_days))loop
  -- Remind the current action owner plus the assigned accountant, without granting broader visibility.
  foreach recipient in array array_append(private.fleet_request_responsibles(r),r.accountant_id)loop n:=n+private.fleet_workflow_notify('request',r.id,r.revision,recipient,'advance','عهدة طلب الصيانة #'||r.number||' تحتاج متابعة التسوية',r.vehicle_id);end loop;
 end loop;
 for h in select * from private.fleet_handovers where state='pending_driver'and submitted_at<=now()-make_interval(days=>s.handover_days)loop
  select profile_id into recipient from private.hr_employees where id=h.employee_id;
  n:=n+private.fleet_workflow_notify('handover',h.id,h.revision,recipient,'overdue','تذكير بإقرار محضر السيارة #'||h.number,h.vehicle_id);
 end loop;return n;
end$$;
create function private.fleet_workflow_settings_save(p_revision integer,p_stage_days integer,p_advance_days integer,p_handover_days integer)returns void language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare s private.fleet_workflow_settings%rowtype;
begin perform private.require_module('fleet');if not private.is_admin()then raise exception 'Administrator access required'using errcode='42501';end if;
 select * into strict s from private.fleet_workflow_settings for update;
 if s.revision is distinct from p_revision then raise exception 'تم تحديث الإعدادات، حدّث الصفحة'using errcode='40001';end if;
 update private.fleet_workflow_settings set stage_days=p_stage_days,advance_days=p_advance_days,handover_days=p_handover_days,revision=revision+1;
 perform private.access_log('FLEET_WORKFLOW_SETTINGS','fleet',to_jsonb(s),jsonb_build_object('stage_days',p_stage_days,'advance_days',p_advance_days,'handover_days',p_handover_days));perform private.process_fleet_workflow_alerts();
end$$;
create function private.fleet_workflow_notification_visible(p_request uuid,p_handover uuid)returns boolean language plpgsql stable security definer set search_path=pg_catalog,public,private as $$
declare r private.fleet_requests%rowtype;h private.fleet_handovers%rowtype;
begin
 if not private.current_user_is_active()or not private.module_allowed('fleet')then return false;end if;
 if p_request is not null then select * into r from private.fleet_requests where id=p_request;return r.id is not null and private.fleet_visible(r);end if;
 if p_handover is not null then select * into h from private.fleet_handovers where id=p_handover;return h.id is not null and private.fleet_handover_visible(h);end if;return false;
end$$;
create function private.fleet_workflow_notification_open(p_notification uuid)returns jsonb language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare n public.notifications%rowtype;
begin perform private.require_module('fleet');select * into strict n from public.notifications where id=p_notification and recipient_id=auth.uid()and type in('FLEET_WORKFLOW','FLEET_HANDOVER');
 if not private.fleet_workflow_notification_visible(n.fleet_request_id,n.fleet_handover_id)then raise exception 'السجل غير متاح لك حاليًا'using errcode='42501';end if;
 update public.notifications set read_at=coalesce(read_at,now())where id=n.id;return jsonb_build_object('request_id',n.fleet_request_id,'handover_id',n.fleet_handover_id);
end$$;
-- Assignment changes use an acknowledged handover; initial records and approved imports remain supported.
alter function private.fleet_vehicle_save(uuid,integer,jsonb,text)rename to fleet_vehicle_save_before_operations;
revoke all on function private.fleet_vehicle_save_before_operations(uuid,integer,jsonb,text)from public,anon,authenticated;
create function private.fleet_vehicle_save(p_id uuid,p_revision integer,p_data jsonb,p_reason text)returns uuid language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare v private.fleet_vehicles%rowtype;
begin perform private.require_module('fleet');if not private.fleet_has('fleet.vehicles.write')then raise exception 'Vehicle management denied'using errcode='42501';end if;
 if p_id is not null then select * into strict v from private.fleet_vehicles where id=p_id for update;if v.driver_id is distinct from nullif(p_data->>'driver_id','')::uuid then raise exception 'تغيير العهدة يتطلب محضر تسليم واستلام';end if;end if;
 return private.fleet_vehicle_save_before_operations(p_id,p_revision,p_data,p_reason);
end$$;
-- All public endpoints remain invokers; implementation helpers are private and deny direct raw access.
create or replace function public.fleet_snapshot()returns jsonb language sql security invoker set search_path=pg_catalog,private as $$select private.fleet_snapshot()$$;
create or replace function public.fleet_detail(p_id uuid)returns jsonb language sql security invoker set search_path=pg_catalog,private as $$select private.fleet_detail(p_id)$$;
create or replace function public.fleet_vehicle_save(p_id uuid,p_revision integer,p_data jsonb,p_reason text)returns uuid language sql security invoker set search_path=pg_catalog,private as $$select private.fleet_vehicle_save(p_id,p_revision,p_data,p_reason)$$;
create or replace function public.fleet_operations_context()returns jsonb language sql security invoker set search_path=pg_catalog,private as $$select private.fleet_operations_context()$$;
create or replace function public.fleet_vehicle_profile(p_vehicle uuid)returns jsonb language sql security invoker set search_path=pg_catalog,private as $$select private.fleet_vehicle_profile(p_vehicle)$$;
create or replace function public.fleet_vehicle_operation_save(p_vehicle uuid,p_revision integer,p_status text,p_reason text)returns void language sql security invoker set search_path=pg_catalog,private as $$select private.fleet_vehicle_operation_save(p_vehicle,p_revision,p_status,p_reason)$$;
create or replace function public.fleet_handover_save(p_id uuid,p_revision integer,p_data jsonb)returns uuid language sql security invoker set search_path=pg_catalog,private as $$select private.fleet_handover_save(p_id,p_revision,p_data)$$;
create or replace function public.fleet_handover_detail(p_id uuid)returns jsonb language sql security invoker set search_path=pg_catalog,private as $$select private.fleet_handover_detail(p_id)$$;
create or replace function public.fleet_handover_upload(p_id uuid,p_name text,p_mime text,p_base64 text)returns uuid language sql security invoker set search_path=pg_catalog,private as $$select private.fleet_handover_upload(p_id,p_name,p_mime,p_base64)$$;
create or replace function public.fleet_handover_photo(p_id uuid)returns jsonb language sql security invoker set search_path=pg_catalog,private as $$select private.fleet_handover_photo(p_id)$$;
create or replace function public.fleet_handover_command(p_id uuid,p_revision integer,p_action text,p_reason text default '')returns jsonb language sql security invoker set search_path=pg_catalog,private as $$select private.fleet_handover_command(p_id,p_revision,p_action,p_reason)$$;
create or replace function public.fleet_workflow_settings_save(p_revision integer,p_stage_days integer,p_advance_days integer,p_handover_days integer)returns void language sql security invoker set search_path=pg_catalog,private as $$select private.fleet_workflow_settings_save(p_revision,p_stage_days,p_advance_days,p_handover_days)$$;
create or replace function public.fleet_workflow_notification_open(p_notification uuid)returns jsonb language sql security invoker set search_path=pg_catalog,private as $$select private.fleet_workflow_notification_open(p_notification)$$;
do $$declare f record;begin for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private'and(p.proname like 'fleet_%'or p.proname='process_fleet_workflow_alerts')loop execute format('revoke all on function %s from public,anon',f.sig);end loop;for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in('private','public')and p.proname in('fleet_snapshot','fleet_detail','fleet_vehicle_save','fleet_operations_context','fleet_vehicle_profile','fleet_vehicle_operation_save','fleet_handover_save','fleet_handover_detail','fleet_handover_upload','fleet_handover_photo','fleet_handover_command','fleet_workflow_settings_save','fleet_workflow_notification_open')loop execute format('revoke all on function %s from public,anon',f.sig);execute format('grant execute on function %s to authenticated',f.sig);end loop;end$$;
revoke all on function private.fleet_handover_visible(private.fleet_handovers),private.fleet_request_responsibles(private.fleet_requests),private.fleet_journey(private.fleet_requests),private.fleet_workflow_notify(text,uuid,integer,uuid,text,text,uuid),private.fleet_request_stage_trigger(),private.process_fleet_workflow_alerts()from authenticated;
revoke all on function private.fleet_workflow_notification_visible(uuid,uuid)from public,anon;grant execute on function private.fleet_workflow_notification_visible(uuid,uuid)to authenticated;
create policy fleet_workflow_boundary on public.notifications as restrictive to authenticated using((fleet_request_id is null and fleet_handover_id is null)or private.fleet_workflow_notification_visible(fleet_request_id,fleet_handover_id));
do $$begin if to_regnamespace('cron')is not null then execute $job$select cron.schedule('atwar_fleet_workflow_alerts','15 * * * *','select private.process_fleet_workflow_alerts();')$job$;end if;end$$;
create function private.fleet_handover_photo_delete(p_id uuid)returns void language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare h private.fleet_handovers%rowtype;f private.fleet_handover_photos%rowtype;
begin perform private.require_module('fleet');select * into strict f from private.fleet_handover_photos where id=p_id;select * into strict h from private.fleet_handovers where id=f.handover_id for update;
 if not private.fleet_has('fleet.vehicles.write')or h.state<>'draft'or exists(select 1 from private.hr_employees where id=h.employee_id and profile_id=auth.uid())then raise exception 'Action denied'using errcode='42501';end if;
 delete from private.fleet_handover_photos where id=p_id;
 insert into private.fleet_events(vehicle_id,actor_id,action,payload)values(h.vehicle_id,auth.uid(),'handover_photo_deleted',jsonb_build_object('handover_id',h.id,'photo_id',p_id));
end$$;
create function public.fleet_handover_photo_delete(p_id uuid)returns void language sql security invoker set search_path=pg_catalog,private as $$select private.fleet_handover_photo_delete(p_id)$$;
revoke all on function private.fleet_handover_photo_delete(uuid),public.fleet_handover_photo_delete(uuid)from public,anon;
grant execute on function private.fleet_handover_photo_delete(uuid),public.fleet_handover_photo_delete(uuid)to authenticated;

create index fleet_request_waiting_idx on private.fleet_requests(state_changed_at)where state not in('draft','closed','rejected');
create index fleet_handover_waiting_idx on private.fleet_handovers(submitted_at)where state='pending_driver';
