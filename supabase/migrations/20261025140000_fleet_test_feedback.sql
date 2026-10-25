-- New fleet workflow. Existing records retain their historical route and audit.
alter table private.fleet_requests add column workflow_version integer not null default 1;
alter table private.fleet_requests alter column workflow_version set default 2;
alter table private.fleet_requests add column maintenance_kind text check(maintenance_kind in('tire','battery','engine_flush','inspection_service')),add column needs_tow boolean not null default false,add column repair_photo_id uuid references private.fleet_files(id);
alter table private.fleet_requests add column if not exists stops_vehicle boolean not null default false;
alter table private.fleet_files drop constraint fleet_files_kind_check;
alter table private.fleet_files add constraint fleet_files_kind_check check(kind in('quote','quote_parts','quote_labor','invoice','repair_photo','payment','refund'));
alter function private.fleet_command(uuid,integer,text,jsonb)rename to fleet_command_legacy;
alter function private.fleet_request_save(uuid,integer,jsonb)rename to fleet_request_save_legacy;
revoke all on function private.fleet_command_legacy(uuid,integer,text,jsonb),private.fleet_request_save_legacy(uuid,integer,jsonb)from public,anon,authenticated;
create function private.fleet_request_validate(r private.fleet_requests)returns void language plpgsql security definer set search_path=pg_catalog,private,public as $$
declare q jsonb;fid uuid;minimum integer;
begin
 if length(btrim(r.description))<10 or length(btrim(r.fault_notes))<10 then raise exception 'النصوص إلزامية، 10 أحرف على الأقل';end if;
 if r.request_type='repair'and coalesce(r.maintenance_kind,'')not in('tire','battery','engine_flush','inspection_service')then raise exception 'حدد نوع الصيانة الدورية';end if;
 minimum:=case when r.request_type='emergency'and r.stops_vehicle and r.needs_tow then 1 else 2 end;
 if jsonb_array_length(r.quotes)<minimum then raise exception 'يلزم توفير % عروض أسعار على الأقل',minimum;end if;
 if r.selected_quote not between 0 and jsonb_array_length(r.quotes)-1 then raise exception 'حدد العرض المختار';end if;
 for q in select value from jsonb_array_elements(r.quotes)loop
  if length(btrim(coalesce(q->>'supplier','')))<10 or coalesce(q->>'phone','')!~'^(05[0-9]{8}|[+]9665[0-9]{8})$'then raise exception 'اسم الورشة 10 أحرف على الأقل ورقم جوال سعودي صالح مطلوب';end if;
  if q->>'parts' is null or q->>'labor'is null or q->>'tax'is null then raise exception 'جميع مبالغ العرض مطلوبة';end if;
  if not exists(select 1 from private.fleet_files where id=nullif(q->>'parts_file_id','')::uuid and request_id=r.id and kind='quote_parts')or not exists(select 1 from private.fleet_files where id=nullif(q->>'labor_file_id','')::uuid and request_id=r.id and kind='quote_labor')then raise exception 'أرفق عرض قطع الغيار وعرض أجرة اليد لكل ورشة';end if;
 end loop;
 if(select count(distinct value->>'labor_file_id')from jsonb_array_elements(r.quotes))<>jsonb_array_length(r.quotes)then raise exception 'مرفق أجرة يد مستقل لكل ورشة مطلوب';end if;
end$$;
revoke all on function private.fleet_request_validate(private.fleet_requests)from public,anon,authenticated;

create or replace function private.fleet_request_save(p_id uuid,p_revision integer,p_data jsonb)returns uuid language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare r private.fleet_requests%rowtype;e uuid;v private.fleet_vehicles%rowtype;rid uuid:=coalesce(p_id,gen_random_uuid());
begin
 perform private.require_module('fleet');
 if p_data->>'request_type' is null or p_data->>'request_type' not in('repair','emergency')then raise exception 'نوع الطلب يجب أن يكون صيانة أو عطل طارئ';end if;
 if not private.current_user_is_active()then raise exception 'Authentication required' using errcode='42501';end if;
 select id into e from private.hr_employees where profile_id=auth.uid();
 if p_id is not null then select * into strict r from private.fleet_requests where id=p_id for update;
 if r.workflow_version=1 and coalesce(p_data->>'upgrade_workflow','false')<>'true'then return private.fleet_request_save_legacy(p_id,p_revision,p_data);end if;
 if not private.fleet_can_request_for(r.driver_id) or r.state not in('draft','returned')then raise exception 'لا يمكن تعديل الطلب في هذه المرحلة' using errcode='42501';end if;
 if r.revision is distinct from p_revision then raise exception 'تم تعديل الطلب، حدّث الصفحة' using errcode='40001';end if;end if;
 select * into strict v from private.fleet_vehicles where id=(p_data->>'vehicle_id')::uuid for update;
 if not private.fleet_can_request_for(v.driver_id) or not v.active then raise exception 'السيارة ليست مسجلة باسمك أو باسم أحد فريقك المباشر' using errcode='42501';end if;
 if p_id is not null and r.driver_id is distinct from v.driver_id then raise exception 'لا يمكن تغيير صاحب الطلب';end if;
 e:=v.driver_id;
 if (p_data->>'odometer')::integer<v.odometer then raise exception 'قراءة العداد أقل من السجل';end if;
 if not exists(select 1 from public.profiles p where p.id=(p_data->>'accountant_id')::uuid and p.id<>auth.uid() and p.id is distinct from(select profile_id from private.hr_employees where id=e)and p.active and p.status='active' and(
 exists(select 1 from private.access_direct_tasks d where d.profile_id=p.id and 'fleet.finance'=any(d.permissions))or exists(select 1 from private.access_assignments a join private.access_roles ar on ar.id=a.role_id and ar.active join private.access_role_rules g on g.role_id=ar.id where a.profile_id=p.id and g.permission='fleet.finance')))then raise exception 'اختر محاسبًا نشطًا مخولًا';end if;
 if length(btrim(coalesce(p_data->>'description','')))<10 or length(btrim(coalesce(p_data->>'fault_notes','')))<10 then raise exception 'تفاصيل الصيانة وسبب العطل إلزاميان، 10 أحرف على الأقل';end if;
 if p_data->>'request_type'='repair'and coalesce(p_data->>'maintenance_kind','')not in('tire','battery','engine_flush','inspection_service')then raise exception 'حدد نوع الصيانة الدورية';end if;
 if p_data->>'request_type'='emergency'and(p_data->>'stops_vehicle'is null or((p_data->>'stops_vehicle')::boolean and p_data->>'needs_tow'is null))then raise exception 'حدد توقف السيارة والحاجة إلى سطحة';end if;
 if jsonb_typeof(p_data->'quotes')is distinct from 'array' or jsonb_array_length(p_data->'quotes')>10 then raise exception 'Invalid quotes';end if;
 insert into private.fleet_requests(id,driver_id,vehicle_id,accountant_id,description,fault_notes,request_type,odometer,quotes,selected_quote,maintenance_kind,stops_vehicle,needs_tow)
 values(rid,e,v.id,(p_data->>'accountant_id')::uuid,p_data->>'description',coalesce(p_data->>'fault_notes',''),p_data->>'request_type',(p_data->>'odometer')::integer,p_data->'quotes',coalesce((p_data->>'selected_quote')::integer,0),case when p_data->>'request_type'='repair'then p_data->>'maintenance_kind'end,case when p_data->>'request_type'='emergency'then(p_data->>'stops_vehicle')::boolean else false end,case when p_data->>'request_type'='emergency'and(p_data->>'stops_vehicle')::boolean then coalesce((p_data->>'needs_tow')::boolean,false)else false end)
 on conflict(id)do update set workflow_version=2,vehicle_id=excluded.vehicle_id,accountant_id=excluded.accountant_id,description=excluded.description,fault_notes=excluded.fault_notes,request_type=excluded.request_type,odometer=excluded.odometer,quotes=excluded.quotes,selected_quote=excluded.selected_quote,maintenance_kind=excluded.maintenance_kind,stops_vehicle=excluded.stops_vehicle,needs_tow=excluded.needs_tow,exception_reason=null,revision=private.fleet_requests.revision+1,updated_at=now();
 insert into private.fleet_events(request_id,actor_id,action,from_state,to_state)values(rid,auth.uid(),'draft_saved',coalesce(r.state,'draft'),coalesce(r.state,'draft'));return rid;
end$$;


create or replace function private.fleet_upload(p_request uuid,p_kind text,p_name text,p_mime text,p_base64 text)returns uuid language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare r private.fleet_requests%rowtype;rid uuid;v bytea;driver boolean;
begin
 perform private.require_module('fleet');
 select * into strict r from private.fleet_requests where id=p_request for update;
 if not private.current_user_is_active() or not private.fleet_visible(r)then raise exception 'Access denied' using errcode='42501';end if;
 driver:=exists(select 1 from private.hr_employees where id=r.driver_id and profile_id=auth.uid())or(p_kind in('quote','quote_parts','quote_labor')and private.fleet_can_request_for(r.driver_id))or private.is_admin()or private.fleet_has('fleet.approve');
 if not((driver and ((p_kind in('quote','quote_parts','quote_labor') and r.state in('draft','returned'))or(p_kind in('invoice','repair_photo') and r.state='repair')))or(p_kind in('payment','refund')and (r.accountant_id=auth.uid()or private.is_admin())and private.fleet_has('fleet.finance')and r.state in('awaiting_advance','reimbursement','settlement')))then raise exception 'Upload denied' using errcode='42501';end if;
 if length(p_base64)>6990510 then raise exception 'الحد الأعلى للمرفق 5 ميجابايت';end if;
 if p_kind='repair_photo'and p_mime not in('image/png','image/jpeg')then raise exception 'صورة الإصلاح PNG أو JPEG فقط';end if;
 v:=decode(p_base64,'base64');
 if not((p_mime='application/pdf'and substring(v from 1 for 5)=decode('255044462d','hex'))or(p_mime='image/png'and substring(v from 1 for 8)=decode('89504e470d0a1a0a','hex'))or(p_mime='image/jpeg'and substring(v from 1 for 3)=decode('ffd8ff','hex')))then raise exception 'ملف PDF أو PNG أو JPEG صالح مطلوب';end if;
 select id into rid from private.fleet_files where request_id=p_request and kind=p_kind and content_hash=encode(sha256(v),'hex')and size_bytes=octet_length(v)limit 1;if rid is not null then return rid;end if;
 if(select coalesce(sum(size_bytes),0)from private.fleet_files where request_id=p_request)+octet_length(v)>31457280 then raise exception 'الحد الإجمالي لمرفقات الطلب 30 ميجابايت';end if;
 insert into private.fleet_files(request_id,kind,name,mime,bytes,actor_id)values(p_request,p_kind,p_name,p_mime,v,auth.uid())returning id into rid;return rid;
end$$;


create or replace function private.fleet_command(p_id uuid,p_revision integer,p_action text,p_data jsonb default '{}')returns jsonb language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare r private.fleet_requests%rowtype;prior text;driver boolean;operator boolean;owner uuid;quote jsonb;total numeric(14,2);q jsonb;eid uuid;diff numeric(14,2);pay_kind text;manager uuid;v private.fleet_vehicles%rowtype;new_route text;
begin
 perform private.require_module('fleet');
 select * into strict r from private.fleet_requests where id=p_id for update;
 if not private.fleet_visible(r)then raise exception 'Access denied' using errcode='42501';end if;
 if r.revision is distinct from p_revision then raise exception 'تم تعديل الطلب، حدّث الصفحة' using errcode='40001';end if;
 if p_action in('request_increase','confirm_repair') and (p_data->>'total')::numeric is distinct from round((p_data->>'total')::numeric,2) then raise exception 'المبالغ بمنزلتين عشريتين كحد أقصى';end if;
 if r.workflow_version=1 then return private.fleet_command_legacy(p_id,p_revision,p_action,p_data);end if;
 prior:=r.state;driver:=exists(select 1 from private.hr_employees where id=r.driver_id and profile_id=auth.uid());operator:=driver or private.is_admin()or private.fleet_has('fleet.approve');
 if r.state in('closed','rejected')then raise exception 'الطلب مقفل للقراءة فقط';end if;
 if p_action='approve'and p_data ? 'selected_quote' then
  if r.state not in('manager_review','fleet_review')or r.invoice_id is not null or r.advance>0 or driver or not((r.state='manager_review'and(auth.uid()=r.manager_id or private.is_admin()or private.fleet_has('fleet.approve')))or(r.state='fleet_review'and(private.is_admin()or auth.uid()=private.fleet_owner())))then raise exception 'لا يمكن تغيير العرض في هذه المرحلة'using errcode='42501';end if;
  if(p_data->>'selected_quote')::integer not between 0 and jsonb_array_length(r.quotes)-1 then raise exception 'اختر عرضًا صالحًا';end if;
  r.selected_quote:=(p_data->>'selected_quote')::integer;quote:=r.quotes->r.selected_quote;
  r.approved:=(quote->>'parts')::numeric+(quote->>'labor')::numeric+(quote->>'tax')::numeric;
  r.route:=case when r.approved<=300 then 'small'else 'large'end;
  if r.route='small'and r.request_type='repair'and r.manager_id is null then raise exception 'يجب ربط المدير المباشر بحساب نشط';end if;
 end if;
 if p_action='approve'and r.state='manager_review'and r.route='large'and not driver and(auth.uid()=r.manager_id or private.is_admin()or private.fleet_has('fleet.approve'))then r.state:='fleet_review';
 elsif p_action='submit' and private.fleet_can_request_for(r.driver_id) and r.state in('draft','returned')then
  if r.request_type not in('repair','emergency')then raise exception 'نوع الطلب يجب أن يكون صيانة أو عطل طارئ';end if;
  perform private.fleet_request_validate(r);
  owner:=private.fleet_owner();
  select * into strict v from private.fleet_vehicles where id=r.vehicle_id for update;
  if not v.active or v.driver_id is distinct from r.driver_id then raise exception 'تم تغيير عهدة السيارة؛ راجع المسودة';end if;
  if r.odometer<v.odometer then raise exception 'قراءة العداد أقل من السجل';end if;
  if jsonb_array_length(r.quotes)=0 or r.selected_quote<0 or r.selected_quote>=jsonb_array_length(r.quotes)then raise exception 'أرفق عرضًا واحدًا على الأقل وحدد العرض المختار';end if;
  for q in select value from jsonb_array_elements(r.quotes)loop
   if length(btrim(coalesce(q->>'supplier','')))<2 or coalesce((q->>'parts')::numeric,-1)<0 or coalesce((q->>'labor')::numeric,-1)<0 or coalesce((q->>'tax')::numeric,-1)<0 then raise exception 'بيانات العرض غير مكتملة';end if;
   if exists(select 1 from unnest(array['parts','labor','tax'])k where (q->>k)::numeric<>round((q->>k)::numeric,2))then raise exception 'قيم العروض بمنزلتين عشريتين كحد أقصى';end if;
   total:=(q->>'parts')::numeric+(q->>'labor')::numeric+(q->>'tax')::numeric;
   if total<=0 or total>99999999 then raise exception 'قيمة العرض غير صالحة';end if;
   if not exists(select 1 from private.fleet_files where id=(q->>'parts_file_id')::uuid and request_id=r.id and kind='quote_parts')then raise exception 'مرفق كل عرض مطلوب';end if;
  end loop;
  if(select count(distinct lower(btrim(value->>'supplier')))from jsonb_array_elements(r.quotes))<>jsonb_array_length(r.quotes)then raise exception 'يجب أن تكون العروض من موردين مختلفين';end if;
  if(select count(distinct (value->>'parts_file_id')::uuid)from jsonb_array_elements(r.quotes))<>jsonb_array_length(r.quotes)then raise exception 'يجب إرفاق ملف مستقل لكل عرض سعر';end if;
  quote:=r.quotes->r.selected_quote;r.approved:=(quote->>'parts')::numeric+(quote->>'labor')::numeric+(quote->>'tax')::numeric;
  r.route:=case when r.approved<=300 then 'small'else 'large'end;
  select m.profile_id into manager from private.hr_employees e join private.hr_employees m on m.id=e.manager_id join public.profiles p on p.id=m.profile_id and p.active and p.status='active' where e.id=r.driver_id;
  if r.route='small' and manager is null then
   select e.profile_id into manager from private.fleet_designated_approvers a join private.hr_employees e on e.id=a.approver_employee_id join public.profiles p on p.id=e.profile_id and p.active and p.status='active' where a.driver_id=r.driver_id;
  end if;
  if r.route='small' and r.request_type<>'emergency' and(manager is null or(manager=auth.uid()and driver))then raise exception 'يجب ربط المدير المباشر بحساب نشط';end if;
  r.manager_id:=manager;r.snapshot:=jsonb_build_object('vehicle',to_jsonb(v),'driver',(select jsonb_build_object('id',id,'name',full_name,'code',employee_code)from private.hr_employees where id=r.driver_id));
  r.state:=case when r.request_type='emergency'then 'fleet_review'when r.route='small'then 'manager_review'else 'fleet_review'end;
 elsif p_action='approve_exception' and r.state='quote_exception' and (case when private.is_admin()then true else auth.uid()=private.fleet_owner()end) and not driver then
  if length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'سبب الاستثناء مطلوب';end if;
  r.exception_reason:=p_data->>'reason';r.state:=case when r.route='small'then 'manager_review'else 'fleet_review'end;
 elsif p_action='approve' and r.state='manager_review' and (auth.uid()=r.manager_id or private.is_admin()or private.fleet_has('fleet.approve')) and not driver then r.state:='repair';
 elsif p_action='approve' and r.state='fleet_review' and (case when private.is_admin()then true else auth.uid()=private.fleet_owner()end) and not driver then
  r.state:=case when r.invoice_id is not null then 'reimbursement'when r.route='small'and r.request_type='emergency'then 'repair'when r.route='small'then 'manager_review'else 'awaiting_advance'end;
 elsif p_action='request_increase' and r.state='repair' and operator then
  total:=(p_data->>'total')::numeric;
  if total is null or total<=r.approved or total>99999999 or length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'أدخل إجماليًا أعلى وسبب الزيادة قبل تنفيذها';end if;
  r.proposed_total:=total;r.increase_reason:=p_data->>'reason';r.state:='increase_review';
 elsif p_action='approve_increase' and r.state='increase_review' and (case when private.is_admin()then true else auth.uid()=private.fleet_owner()end) and not driver then
  r.approved:=r.proposed_total;r.proposed_total:=null;
  if r.approved>300 then r.route:='large';end if;
  r.state:=case when r.route='large'then 'awaiting_advance'else 'repair'end;
 elsif p_action='decline_increase' and r.state='increase_review' and (case when private.is_admin()then true else auth.uid()=private.fleet_owner()end) and not driver then
  if length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'سبب رفض الزيادة مطلوب';end if;
  r.proposed_total:=null;r.state:='repair';
 elsif p_action='confirm_repair' and r.state='repair' and operator then
  if r.route='large' and r.advance<r.approved then raise exception 'يجب صرف كامل المبلغ المعتمد قبل استكمال الإصلاح';end if;
  if not exists(select 1 from private.fleet_files where id=nullif(p_data->>'repair_photo_id','')::uuid and request_id=r.id and kind='repair_photo'and mime in('image/png','image/jpeg'))then raise exception 'أرفق صورة الإصلاح';end if;
  r.repair_photo_id:=(p_data->>'repair_photo_id')::uuid;
  total:=(p_data->>'total')::numeric;eid:=(p_data->>'invoice_id')::uuid;
  if coalesce((p_data->>'received')::boolean,false)is not true then raise exception 'تأكيد استلام السيارة مطلوب';end if;
  if total is null or total<=0 or total>r.approved then raise exception 'الفاتورة يجب ألا تتجاوز المعتمد؛ اطلب اعتماد الزيادة قبل تنفيذها';end if;
  if not exists(select 1 from private.fleet_files where id=eid and request_id=r.id and kind='invoice')then raise exception 'أرفق الفاتورة';end if;
  r.invoice_total:=total;r.invoice_id:=eid;r.received_at:=now();r.state:=case when r.route='small'then 'fleet_review'else 'settlement'end;
 elsif p_action='confirm_advance' and r.state='awaiting_advance' and (r.accountant_id=auth.uid()or private.is_admin()) and private.fleet_has('fleet.finance') and not driver then
  diff:=r.approved-r.advance;
  if diff<=0 then raise exception 'لا توجد دفعة مستحقة';end if;
  pay_kind:='advance';r.advance:=r.approved;r.state:='repair';
 elsif p_action='settle' and r.state in('reimbursement','settlement')and (r.accountant_id=auth.uid()or private.is_admin())and private.fleet_has('fleet.finance')and not driver then
  diff:=r.invoice_total-r.advance;
  pay_kind:=case when r.state='reimbursement'then 'reimbursement'when diff<0 then 'refund'when diff>0 then 'topup'else 'settle'end;
  r.state:='closed';r.closed_at:=now();
 elsif p_action in('return','reject')and r.state in('quote_exception','manager_review','fleet_review','increase_review','awaiting_advance','reimbursement','settlement')then
  if not((r.state='manager_review'and (auth.uid()=r.manager_id or private.is_admin()or private.fleet_has('fleet.approve')) and not driver)or(r.state in('quote_exception','fleet_review','increase_review')and (case when private.is_admin()then true else auth.uid()=private.fleet_owner()end)and not driver)or(r.state in('awaiting_advance','reimbursement','settlement')and (r.accountant_id=auth.uid()or private.is_admin())and private.fleet_has('fleet.finance')and not driver))then raise exception 'Action denied' using errcode='42501';end if;
  if length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'سبب الإعادة أو الرفض مطلوب';end if;
  -- Financially active requests must be corrected and settled, never abandoned with an advance.
  if p_action='reject' and r.advance>0 then raise exception 'لا يمكن رفض طلب له عهدة مصروفة؛ أعده للتصحيح ثم سوّه';end if;
  if p_action='reject'then r.state:='rejected';
  elsif r.invoice_id is not null or r.advance>0 then r.state:=case when r.route='large' and r.advance<r.approved then 'awaiting_advance'else 'repair'end;r.invoice_id:=null;r.invoice_total:=null;r.received_at:=null;
  else r.state:='returned';end if;
 else raise exception 'الإجراء غير مسموح لهذه الحالة أو الصلاحية' using errcode='42501';
 end if;
 if p_data ? 'reason'and length(btrim(coalesce(p_data->>'reason','')))<10 then raise exception 'الحد الأدنى للنص 10 أحرف';end if;
 if pay_kind is not null then
  if length(btrim(coalesce(p_data->>'reference','')))<10 then raise exception 'مرجع العملية 10 أحرف على الأقل';end if;
  if nullif(p_data->>'amount','')::numeric is distinct from abs(diff)then raise exception 'المبلغ يجب أن يساوي المستحق تمامًا';end if;
  eid:=nullif(p_data->>'evidence_id','')::uuid;
  if diff<>0 and not exists(select 1 from private.fleet_files where id=eid and request_id=r.id and kind=case when diff<0 then 'refund'else 'payment'end)then raise exception 'مرفق إثبات الصرف أو استرداد المتبقي مطلوب';end if;
  insert into private.fleet_payments(request_id,kind,amount,reference,evidence_id,actor_id)values(r.id,pay_kind,abs(diff),p_data->>'reference',eid,auth.uid());
 end if;
 update private.fleet_requests set selected_quote=r.selected_quote,repair_photo_id=case when r.invoice_id is null then null else r.repair_photo_id end,state=r.state,route=r.route,manager_id=r.manager_id,approved=r.approved,proposed_total=r.proposed_total,increase_reason=r.increase_reason,
 exception_reason=r.exception_reason,invoice_total=r.invoice_total,invoice_id=r.invoice_id,received_at=r.received_at,advance=r.advance,snapshot=r.snapshot,closed_at=r.closed_at,revision=revision+1,updated_at=now()where id=r.id;
 insert into private.fleet_events(request_id,vehicle_id,actor_id,action,from_state,to_state,payload)values(r.id,r.vehicle_id,auth.uid(),p_action,prior,r.state,p_data-'base64');
 if r.state='closed'then update private.fleet_vehicles set odometer=greatest(odometer,r.odometer),revision=revision+1,updated_at=now()where id=r.vehicle_id;end if;
 if to_regprocedure('private.fleet_sync_repair_status(uuid)')is not null then perform private.fleet_sync_repair_status(r.vehicle_id);end if;
 return private.fleet_detail(r.id);
end$$;


revoke all on function private.fleet_command(uuid,integer,text,jsonb),private.fleet_request_save(uuid,integer,jsonb),private.fleet_upload(uuid,text,text,text,text)from public,anon;
grant execute on function private.fleet_command(uuid,integer,text,jsonb),private.fleet_request_save(uuid,integer,jsonb),private.fleet_upload(uuid,text,text,text,text)to authenticated;

