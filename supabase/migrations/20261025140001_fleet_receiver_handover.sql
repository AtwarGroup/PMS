alter table private.fleet_handovers add column workflow_version integer not null default 1;
alter table private.fleet_handovers alter column workflow_version set default 2;
alter table private.fleet_handovers add column deliverer_id uuid references private.hr_employees(id),add column diagram_type text not null default 'sedan'check(diagram_type in('sedan','cargo')),add column sender_notes text not null default '',add column sender_reviewed_at timestamptz,add column notes_decision text check(notes_decision in('accepted','rejected')),add column decision_reason text,add column approved_by uuid references public.profiles(id),add column approved_at timestamptz;
alter table private.fleet_handovers drop constraint fleet_handovers_state_check;
alter table private.fleet_handovers add constraint fleet_handovers_state_check check(state in('draft','pending_driver','pending_sender','fleet_review','pending_receiver','accepted','disputed','cancelled'));
drop index private.fleet_handover_open_vehicle_idx;
create unique index fleet_handover_open_vehicle_idx on private.fleet_handovers(vehicle_id)where state in('pending_driver','pending_sender','fleet_review','pending_receiver');
create index fleet_handover_deliverer_idx on private.fleet_handovers(deliverer_id,created_at desc);
create index fleet_request_repair_photo_idx on private.fleet_requests(repair_photo_id)where repair_photo_id is not null;

alter function private.fleet_handover_visible(private.fleet_handovers)rename to fleet_handover_visible_legacy;
alter function private.fleet_handover_save(uuid,integer,jsonb)rename to fleet_handover_save_legacy;
alter function private.fleet_handover_command(uuid,integer,text,text)rename to fleet_handover_command_legacy;
alter function private.fleet_handover_detail(uuid)rename to fleet_handover_detail_legacy;
revoke all on function private.fleet_handover_visible_legacy(private.fleet_handovers),private.fleet_handover_save_legacy(uuid,integer,jsonb),private.fleet_handover_command_legacy(uuid,integer,text,text),private.fleet_handover_detail_legacy(uuid)from public,anon,authenticated;
create function private.fleet_handover_visible(h private.fleet_handovers)returns boolean language sql stable security definer set search_path=pg_catalog,private,public as $$
 select private.fleet_handover_visible_legacy(h)or(private.current_user_is_active()and private.module_allowed('fleet')and h.workflow_version=2 and exists(select 1 from private.hr_employees e where e.profile_id=auth.uid()and(e.id=h.employee_id or(e.id=h.deliverer_id and h.state<>'draft'))))
$$;
revoke all on function private.fleet_handover_visible(private.fleet_handovers)from public,anon,authenticated;
create function private.fleet_handover_options()returns jsonb language plpgsql stable security definer set search_path=pg_catalog,private,public as $$
declare employee uuid;
begin perform private.require_module('fleet');select id into employee from private.hr_employees where profile_id=auth.uid();
 return jsonb_build_object('can_start',employee is not null,'receiver_id',employee,'vehicles',case when employee is null then '[]'::jsonb else(select coalesce(jsonb_agg(jsonb_build_object('id',v.id,'plate',v.plate,'vehicle_type',v.vehicle_type,'model',v.model,'vin',v.vin,'odometer',v.odometer,'driver_id',v.driver_id,'driver_name',e.full_name)order by v.plate),'[]')from private.fleet_vehicles v left join private.hr_employees e on e.id=v.driver_id where v.active and v.driver_id is distinct from employee)end,'custodians',(select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'name',e.full_name,'code',e.employee_code)),'[]')from private.hr_employees e join public.profiles p on p.id=e.profile_id where e.id is distinct from employee and p.active and p.status='active'and(p.role='admin'or'fleet'=any(p.allowed_modules))and(p.role='admin'or exists(select 1 from private.access_direct_tasks d where d.profile_id=p.id and 'fleet.vehicles.write'=any(d.permissions))or exists(select 1 from private.access_assignments a join private.access_roles ar on ar.id=a.role_id and ar.active join private.access_role_rules rr on rr.role_id=ar.id where a.profile_id=p.id and rr.permission='fleet.vehicles.write'))));
end$$;
create function public.fleet_handover_options()returns jsonb language sql security invoker set search_path=pg_catalog,private as $$select private.fleet_handover_options()$$;
create function private.fleet_handover_guard(v private.fleet_vehicles)returns void language plpgsql security definer set search_path=pg_catalog,private as $$begin
 if not v.active then raise exception 'السيارة غير نشطة';end if;
 if exists(select 1 from private.fleet_requests where vehicle_id=v.id and state not in('draft','returned','closed','rejected'))then raise exception 'أكمل طلبات الصيانة المفتوحة قبل نقل العهدة';end if;
end$$;
create function private.fleet_handover_save(p_id uuid,p_revision integer,p_data jsonb)returns uuid language plpgsql security definer set search_path=pg_catalog,private,public as $$
declare h private.fleet_handovers%rowtype;v private.fleet_vehicles%rowtype;employee uuid;sender uuid;m jsonb;rid uuid:=coalesce(p_id,gen_random_uuid());
begin
 perform private.require_module('fleet');select id into employee from private.hr_employees where profile_id=auth.uid();if employee is null then raise exception 'اربط حسابك بسجل الموظفين لبدء الاستلام';end if;
 if p_id is not null then select * into strict h from private.fleet_handovers where id=p_id for update;
  if h.workflow_version=1 then return private.fleet_handover_save_legacy(p_id,p_revision,p_data);end if;
  if h.created_by<>auth.uid()or h.employee_id<>employee or h.state<>'draft'then raise exception 'تعديل المسودة للموظف المستلم فقط'using errcode='42501';end if;
  if h.revision is distinct from p_revision then raise exception 'تم تحديث المحضر'using errcode='40001';end if;
 end if;
 select * into strict v from private.fleet_vehicles where id=(p_data->>'vehicle_id')::uuid for update;perform private.fleet_handover_guard(v);
 if p_id is not null and v.id<>h.vehicle_id then raise exception 'لا يمكن تغيير السيارة في المحضر';end if;
 if v.driver_id=employee then raise exception 'السيارة في عهدتك بالفعل';end if;
 sender:=coalesce(v.driver_id,nullif(p_data->>'deliverer_id','')::uuid);
 if sender is null or sender=employee or not exists(select 1 from private.hr_employees e join public.profiles p on p.id=e.profile_id where e.id=sender and p.active and p.status='active'and(p.role='admin'or'fleet'=any(p.allowed_modules)))then raise exception 'اختر الموظف المسلّم صاحب حساب نشط';end if;
 if v.driver_id is null and not exists(select 1 from jsonb_array_elements(private.fleet_handover_options()->'custodians')x where(x->>'id')::uuid=sender)then raise exception 'السيارة دون سائق: الموظف المسلّم يجب أن يكون أمين عهدة مخولًا';end if;
 if p_data->>'diagram_type'is null or p_data->>'diagram_type'not in('sedan','cargo')then raise exception 'حدد هيكل السيارة';end if;
 if(p_data->>'odometer')::integer<v.odometer then raise exception 'قراءة العداد أقل من السجل';end if;
 if jsonb_typeof(p_data->'marks')is distinct from 'array'or jsonb_array_length(p_data->'marks')>40 then raise exception 'ملاحظات المعاينة غير صالحة';end if;
 for m in select value from jsonb_array_elements(p_data->'marks')loop
  if m->>'part'is null or m->>'part'not in('front_bumper','hood','windshield','roof','rear_window','trunk','rear_bumper','left_front_fender','left_front_door','left_rear_door','left_rear_fender','right_front_fender','right_front_door','right_rear_door','right_rear_fender','left_front_tire','left_rear_tire','right_front_tire','right_rear_tire','interior','other','cargo_roof','cargo_left','cargo_right','cargo_rear')or m->>'severity'is null or m->>'severity'not in('scratch','dent','broken','other')or length(btrim(coalesce(m->>'note','')))not between 10 and 500 then raise exception 'موضع الملاحظة ونوعها ووصف لا يقل عن 10 أحرف مطلوب';end if;
  if p_data->>'diagram_type'='cargo'and m->>'part'not in('front_bumper','hood','windshield','roof','left_front_door','right_front_door','left_front_tire','right_front_tire','left_rear_tire','right_rear_tire','cargo_roof','cargo_left','cargo_right','cargo_rear','interior','other')then raise exception 'موضع الملاحظة لا يخص هيكل نقل البضائع';end if;
  if p_data->>'diagram_type'='sedan'and m->>'part'like 'cargo_%'then raise exception 'موضع الملاحظة لا يخص هيكل السيدان';end if;
 end loop;
 if jsonb_array_length(p_data->'marks')>0 and coalesce((p_data->>'no_marks')::boolean,false)then raise exception 'لا يمكن تسجيل ملاحظات والإقرار بعدم وجودها';end if;
 insert into private.fleet_handovers(id,vehicle_id,employee_id,deliverer_id,kind,vehicle_revision,previous_driver_id,odometer,fuel_level,keys_count,spare_tire,tools,marks,no_marks,notes,created_by,diagram_type)
 values(rid,v.id,employee,sender,'issue',v.revision,v.driver_id,(p_data->>'odometer')::integer,(p_data->>'fuel_level')::integer,(p_data->>'keys_count')::integer,(p_data->>'spare_tire')::boolean,(p_data->>'tools')::boolean,p_data->'marks',coalesce((p_data->>'no_marks')::boolean,false),coalesce(p_data->>'notes',''),auth.uid(),p_data->>'diagram_type')
 on conflict(id)do update set deliverer_id=excluded.deliverer_id,vehicle_revision=excluded.vehicle_revision,previous_driver_id=excluded.previous_driver_id,odometer=excluded.odometer,fuel_level=excluded.fuel_level,keys_count=excluded.keys_count,spare_tire=excluded.spare_tire,tools=excluded.tools,marks=excluded.marks,no_marks=excluded.no_marks,notes=excluded.notes,diagram_type=excluded.diagram_type,revision=private.fleet_handovers.revision+1,updated_at=now();
 insert into private.fleet_events(vehicle_id,actor_id,action,payload)values(v.id,auth.uid(),'handover_draft',jsonb_build_object('handover_id',rid));return rid;
end$$;
create function private.fleet_handover_detail(p_id uuid)returns jsonb language plpgsql stable security definer set search_path=pg_catalog,private,public as $$
declare h private.fleet_handovers%rowtype;uid uuid:=auth.uid();sender uuid;receiver uuid;
begin perform private.require_module('fleet');select * into strict h from private.fleet_handovers where id=p_id;if h.workflow_version=1 then return private.fleet_handover_detail_legacy(p_id);end if;
 if not private.fleet_handover_visible(h)then raise exception 'Access denied'using errcode='42501';end if;
 select profile_id into sender from private.hr_employees where id=h.deliverer_id;select profile_id into receiver from private.hr_employees where id=h.employee_id;
 return jsonb_build_object('handover',to_jsonb(h)-'save_payload','employee_name',(select full_name from private.hr_employees where id=h.employee_id),'sender_name',(select full_name from private.hr_employees where id=h.deliverer_id),'plate',(select plate from private.fleet_vehicles where id=h.vehicle_id),'photos',(select coalesce(jsonb_agg(to_jsonb(f)-'bytes'order by created_at),'[]')from private.fleet_handover_photos f where handover_id=h.id),'can_edit',h.state='draft'and uid=receiver and h.created_by=uid,'can_sender_review',h.state='pending_sender'and uid=sender,'can_fleet_review',h.state='fleet_review'and uid<>sender and uid<>receiver and(private.is_admin()or uid=private.fleet_owner()),'can_final_ack',h.state='pending_receiver'and uid=receiver,'can_cancel',(h.state in('draft','pending_sender','fleet_review','pending_receiver','disputed'))and(uid=receiver or private.fleet_has('fleet.vehicles.write')));
end$$;
create function private.fleet_handover_command(p_id uuid,p_revision integer,p_action text,p_reason text default '')returns jsonb language plpgsql security definer set search_path=pg_catalog,private,public as $$
declare h private.fleet_handovers%rowtype;v private.fleet_vehicles%rowtype;sender uuid;receiver uuid;owner_id uuid;recipient uuid;prior text;
begin
 perform private.require_module('fleet');select * into strict h from private.fleet_handovers where id=p_id for update;if h.workflow_version=1 then return private.fleet_handover_command_legacy(p_id,p_revision,p_action,p_reason);end if;
 if not private.fleet_handover_visible(h)then raise exception 'Access denied'using errcode='42501';end if;
 if h.revision is distinct from p_revision then raise exception 'تم تحديث المحضر'using errcode='40001';end if;
 select profile_id into sender from private.hr_employees where id=h.deliverer_id;select profile_id into receiver from private.hr_employees where id=h.employee_id;prior:=h.state;
 if p_action='submit'and h.state='draft'and receiver=auth.uid()and h.created_by=auth.uid()then
  if jsonb_array_length(h.marks)=0 and not h.no_marks then raise exception 'أكد المعاينة أو سجل الملاحظات';end if;
  if not exists(select 1 from public.profiles where id=sender and active and status='active'and(role='admin'or'fleet'=any(allowed_modules)))then raise exception 'حساب الموظف المسلّم غير متاح';end if;
  select * into strict v from private.fleet_vehicles where id=h.vehicle_id for update;perform private.fleet_handover_guard(v);
  if v.revision<>h.vehicle_revision or v.driver_id is distinct from h.previous_driver_id then raise exception 'تغير سجل السيارة؛ حدّث المسودة';end if;
  if exists(select 1 from private.fleet_handovers where vehicle_id=v.id and id<>h.id and state in('pending_driver','pending_sender','fleet_review','pending_receiver'))then raise exception 'يوجد محضر قيد المراجعة لهذه السيارة؛ أكمله أو ألغِه أولًا';end if;
  h.state:='pending_sender';h.submitted_at:=now();h.snapshot:=jsonb_build_object('vehicle',to_jsonb(v),'employee',(select jsonb_build_object('name',full_name,'code',employee_code)from private.hr_employees where id=h.employee_id),'sender',(select jsonb_build_object('name',full_name,'code',employee_code)from private.hr_employees where id=h.deliverer_id),'prepared_by',(select full_name from public.profiles where id=auth.uid()));recipient:=sender;
 elsif p_action='sender_review'and h.state='pending_sender'and auth.uid()=sender then
  if length(btrim(p_reason))>0 and length(btrim(p_reason))not between 10 and 2000 then raise exception 'الملاحظة 10 أحرف على الأقل';end if;
  h.sender_notes:=p_reason;h.sender_reviewed_at:=now();h.state:='fleet_review';
  begin owner_id:=private.fleet_owner();exception when raise_exception then owner_id:=null;end;
  if owner_id in(sender,receiver)or owner_id is null then select id into owner_id from public.profiles where role='admin'and active and status='active'and id not in(sender,receiver)order by id limit 1;end if;
  if owner_id is null then raise exception 'يلزم مسؤول اعتماد مستقل عن المسلّم والمستلم';end if;recipient:=owner_id;
 elsif p_action in('approve_notes','reject_notes')and h.state='fleet_review'and auth.uid()not in(sender,receiver)and(private.is_admin()or auth.uid()=private.fleet_owner())then
  if p_action='reject_notes'and length(btrim(p_reason))not between 10 and 2000 then raise exception 'سبب رفض الملاحظات 10 أحرف على الأقل';end if;
  h.notes_decision:=case when p_action='approve_notes'then 'accepted'else 'rejected'end;h.decision_reason:=p_reason;h.snapshot:=h.snapshot||jsonb_build_object('approved_by',(select full_name from public.profiles where id=auth.uid()));h.approved_by:=auth.uid();h.approved_at:=now();h.state:='pending_receiver';recipient:=receiver;
 elsif p_action in('receive_final','reject_final')and h.state='pending_receiver'and auth.uid()=receiver then
  if p_action='reject_final'then
   if length(btrim(p_reason))not between 10 and 2000 then raise exception 'سبب الاعتراض النهائي 10 أحرف على الأقل';end if;h.state:='disputed';h.response:=p_reason;
  else
   select * into strict v from private.fleet_vehicles where id=h.vehicle_id for update;perform private.fleet_handover_guard(v);
   if v.revision<>h.vehicle_revision or v.driver_id is distinct from h.previous_driver_id or v.odometer>h.odometer then raise exception 'تغير سجل السيارة؛ يجب إعداد محضر جديد';end if;
   update private.fleet_vehicles set driver_id=h.employee_id,odometer=h.odometer,revision=revision+1,updated_at=now()where id=v.id;h.state:='accepted';
  end if;
  h.acknowledged_by:=auth.uid();h.acknowledged_at:=now();recipient:=sender;
 elsif p_action='cancel'and h.state in('draft','pending_sender','fleet_review','pending_receiver','disputed')and(auth.uid()=receiver or private.fleet_has('fleet.vehicles.write'))then
  if length(btrim(p_reason))not between 10 and 2000 then raise exception 'سبب الإلغاء 10 أحرف على الأقل';end if;h.state:='cancelled';h.response:=p_reason;recipient:=receiver;
 else raise exception 'الإجراء غير مسموح لهذه المرحلة أو الصلاحية'using errcode='42501';end if;
 update private.fleet_handovers set state=h.state,snapshot=h.snapshot,submitted_at=h.submitted_at,sender_notes=h.sender_notes,sender_reviewed_at=h.sender_reviewed_at,notes_decision=h.notes_decision,decision_reason=h.decision_reason,approved_by=h.approved_by,approved_at=h.approved_at,response=h.response,acknowledged_by=h.acknowledged_by,acknowledged_at=h.acknowledged_at,revision=revision+1,updated_at=now()where id=h.id;
 insert into private.fleet_events(vehicle_id,actor_id,action,from_state,to_state,payload)values(h.vehicle_id,auth.uid(),'handover_'||p_action,prior,h.state,jsonb_build_object('handover_id',h.id,'reason',p_reason));
 perform private.fleet_workflow_notify('handover',h.id,h.revision+1,recipient,'stage','محضر سيارة #'||h.number||' — إجراء مطلوب',h.vehicle_id);
 return private.fleet_handover_detail(h.id);
end$$;
-- Keep photo authorization tied to the receiver while a new inspection is a draft.
do $$declare p record;d text;begin
 for p in select oid from pg_proc where pronamespace='private'::regnamespace and proname in('fleet_handover_upload','fleet_handover_photo_delete')loop
 d:=pg_get_functiondef(p.oid);
 d:=replace(d,'not private.fleet_has(''fleet.vehicles.write'')or h.state<>''draft''or exists(select 1 from private.hr_employees where id=h.employee_id and profile_id=auth.uid())','((h.workflow_version=1 and (not private.fleet_has(''fleet.vehicles.write'')or exists(select 1 from private.hr_employees where id=h.employee_id and profile_id=auth.uid())))or(h.workflow_version=2 and h.created_by<>auth.uid())or h.state<>''draft'')');
 execute d;
 end loop;
end$$;
-- Retry wrapper preserves idempotency and delegates actual actor/phase authorization.
do $$declare d text;begin d:=pg_get_functiondef('private.fleet_handover_save_retry(uuid,uuid,integer,jsonb)'::regprocedure);d:=replace(d,'if not private.fleet_has(''fleet.vehicles.write'')then raise exception ''Vehicle management denied''using errcode=''42501'';end if;','');execute d;end$$;
-- Context includes a minimal vehicle chooser; no maintenance/finance record access is widened.
alter function private.fleet_operations_context()rename to fleet_operations_context_before_feedback;
revoke all on function private.fleet_operations_context_before_feedback()from public,anon,authenticated;
create function private.fleet_operations_context()returns jsonb language sql stable security definer set search_path=pg_catalog,private as $$select private.fleet_operations_context_before_feedback()||jsonb_build_object('handover_options',private.fleet_handover_options())$$;
revoke all on function private.fleet_handover_guard(private.fleet_vehicles)from public,anon,authenticated;
do $$declare p record;begin
 for p in select oid::regprocedure sig from pg_proc where pronamespace in('public'::regnamespace,'private'::regnamespace)and proname in('fleet_handover_options','fleet_handover_save','fleet_handover_detail','fleet_handover_command','fleet_operations_context')loop
 execute format('revoke all on function %s from public,anon',p.sig);execute format('grant execute on function %s to authenticated',p.sig);
 end loop;
end$$;

