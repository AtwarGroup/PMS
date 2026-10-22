-- Enforce the approved fleet owner, administrator and accountant responsibilities.

create or replace function private.fleet_has(p_key text,p_employee uuid default null)returns boolean language sql stable security definer set search_path=pg_catalog,public,private as $$
 select private.current_user_is_active() and (
 (private.is_admin() and p_key in('fleet.vehicles.read','fleet.vehicles.write','fleet.requests.read','fleet.approve','fleet.finance'))
 or exists(select 1 from private.access_direct_tasks d where d.profile_id=auth.uid() and p_key=any(d.permissions))
 or exists(select 1 from private.access_assignments a join private.access_roles r on r.id=a.role_id and r.active
 join private.access_role_rules g on g.role_id=r.id where a.profile_id=auth.uid() and g.permission=p_key
 and(g.scope='all' or (p_employee is not null and private.hr_in_team(p_employee)))))
$$;


create or replace function private.fleet_finance_only()returns boolean language sql stable security definer set search_path=pg_catalog,public,private as $$
 select private.fleet_has('fleet.finance')and not private.is_admin()and not private.fleet_has('fleet.approve')and not private.fleet_has('fleet.vehicles.write')and not private.fleet_has('fleet.vehicles.read')and not private.fleet_has('fleet.requests.read')
$$;
create or replace function private.fleet_can_request_for(p_employee uuid)returns boolean language sql stable security definer set search_path=pg_catalog,public,private as $$
 select private.current_user_is_active()and private.module_allowed('fleet')and exists(
 select 1 from private.hr_employees e left join public.profiles p on p.id=e.profile_id
 where e.id=p_employee and(private.is_admin()or private.fleet_has('fleet.approve')or
 (p.active and p.status='active'and(e.profile_id=auth.uid()or(not private.fleet_finance_only()and exists(select 1 from private.hr_employees m where m.id=e.manager_id and m.profile_id=auth.uid()))))))
$$;
revoke all on function private.fleet_finance_only(),private.fleet_can_request_for(uuid)from public,anon,authenticated;


create or replace function private.fleet_visible(r private.fleet_requests)returns boolean language sql stable security definer set search_path=pg_catalog,public,private as $$
 select private.current_user_is_active() and private.module_allowed('fleet') and case when private.fleet_finance_only()then exists(select 1 from private.hr_employees where id=r.driver_id and profile_id=auth.uid())or(r.accountant_id=auth.uid()and private.fleet_has('fleet.finance'))else(
 exists(select 1 from private.hr_employees e where e.id=r.driver_id and e.profile_id=auth.uid())
 or private.fleet_can_request_for(r.driver_id) or coalesce(r.manager_id=auth.uid(),false) or(r.accountant_id=auth.uid() and private.fleet_has('fleet.finance'))
 or private.fleet_has('fleet.approve') or private.fleet_has('fleet.requests.read',r.driver_id))
end
$$;

create or replace function private.fleet_snapshot()returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,private as $$
declare employee uuid;manage boolean;approve boolean;result jsonb;
begin
 perform private.require_module('fleet');
 if not private.current_user_is_active()then raise exception 'Authentication required' using errcode='42501';end if;
 select id into employee from private.hr_employees where profile_id=auth.uid();
 manage:=private.fleet_has('fleet.vehicles.write');approve:=private.fleet_has('fleet.approve');
 result:=jsonb_build_object('user_id',auth.uid(),'employee_id',employee,'can_manage',manage,'can_approve',approve,'can_finance',private.fleet_has('fleet.finance'),'is_admin',private.is_admin(),'can_operate',private.is_admin()or approve,'finance_only',private.fleet_finance_only(),
 'team_employee_ids',(select coalesce(jsonb_agg(e.id),'[]')from private.hr_employees e join private.hr_employees m on m.id=e.manager_id where m.profile_id=auth.uid()and e.profile_id is distinct from auth.uid()and not private.fleet_finance_only()),
 'can_oversee',manage or approve or private.fleet_has('fleet.finance')or private.fleet_has('fleet.requests.read')or private.fleet_has('fleet.vehicles.read'),
 'vehicles',(select coalesce(jsonb_agg(to_jsonb(v)||jsonb_build_object('driver_name',e.full_name,'can_request',private.fleet_can_request_for(v.driver_id))order by v.plate),'[]')from private.fleet_vehicles v left join private.hr_employees e on e.id=v.driver_id where private.fleet_can_request_for(v.driver_id) or manage or approve or private.fleet_has('fleet.vehicles.read')),
 'employees',case when manage then(select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',full_name,'code',employee_code)order by full_name),'[]')from private.hr_employees)else '[]'::jsonb end,
 'accountants',(select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.full_name)order by p.full_name),'[]')from public.profiles p where p.active and p.status='active' and (
 exists(select 1 from private.access_direct_tasks d where d.profile_id=p.id and 'fleet.finance'=any(d.permissions))
 or exists(select 1 from private.access_assignments a join private.access_roles ar on ar.id=a.role_id and ar.active join private.access_role_rules g on g.role_id=ar.id where a.profile_id=p.id and g.permission='fleet.finance'))),
 'requests',(select coalesce(jsonb_agg(to_jsonb(r)||jsonb_build_object('driver_name',e.full_name,'plate',v.plate,'accountant_name',p.full_name) order by r.number desc),'[]')from private.fleet_requests r join private.hr_employees e on e.id=r.driver_id join private.fleet_vehicles v on v.id=r.vehicle_id join public.profiles p on p.id=r.accountant_id where private.fleet_visible(r)));
 return result||jsonb_build_object(
 'can_create',exists(select 1 from jsonb_array_elements(result->'vehicles')v where(v->>'active')::boolean and(v->>'can_request')::boolean),
 'can_view_vehicles',manage or approve or private.fleet_has('fleet.vehicles.read')or jsonb_array_length(result->'vehicles')>0,
 'can_view_documents',manage or approve or private.fleet_has('fleet.vehicles.read')or jsonb_array_length(result->'vehicles')>0);

end$$;

create or replace function private.fleet_request_save(p_id uuid,p_revision integer,p_data jsonb)returns uuid language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare r private.fleet_requests%rowtype;e uuid;v private.fleet_vehicles%rowtype;rid uuid:=coalesce(p_id,gen_random_uuid());
begin
 perform private.require_module('fleet');
 if p_data->>'request_type' is null or p_data->>'request_type' not in('repair','emergency')then raise exception 'نوع الطلب يجب أن يكون صيانة أو عطل طارئ';end if;
 if not private.current_user_is_active()then raise exception 'Authentication required' using errcode='42501';end if;
 select id into e from private.hr_employees where profile_id=auth.uid();
 if p_id is not null then select * into strict r from private.fleet_requests where id=p_id for update;
 if not private.fleet_can_request_for(r.driver_id) or r.state not in('draft','returned')then raise exception 'لا يمكن تعديل الطلب في هذه المرحلة' using errcode='42501';end if;
 if r.revision is distinct from p_revision then raise exception 'تم تعديل الطلب، حدّث الصفحة' using errcode='40001';end if;end if;
 select * into strict v from private.fleet_vehicles where id=(p_data->>'vehicle_id')::uuid for update;
 if not private.fleet_can_request_for(v.driver_id) or not v.active then raise exception 'السيارة ليست مسجلة باسمك أو باسم أحد فريقك المباشر' using errcode='42501';end if;
 if p_id is not null and r.driver_id is distinct from v.driver_id then raise exception 'لا يمكن تغيير صاحب الطلب';end if;
 e:=v.driver_id;
 if (p_data->>'odometer')::integer<v.odometer then raise exception 'قراءة العداد أقل من السجل';end if;
 if not exists(select 1 from public.profiles p where p.id=(p_data->>'accountant_id')::uuid and p.id<>auth.uid() and p.id is distinct from(select profile_id from private.hr_employees where id=e)and p.active and p.status='active' and(
 exists(select 1 from private.access_direct_tasks d where d.profile_id=p.id and 'fleet.finance'=any(d.permissions))or exists(select 1 from private.access_assignments a join private.access_roles ar on ar.id=a.role_id and ar.active join private.access_role_rules g on g.role_id=ar.id where a.profile_id=p.id and g.permission='fleet.finance')))then raise exception 'اختر محاسبًا نشطًا مخولًا';end if;
 if jsonb_typeof(p_data->'quotes')is distinct from 'array' or jsonb_array_length(p_data->'quotes')>10 then raise exception 'Invalid quotes';end if;
 insert into private.fleet_requests(id,driver_id,vehicle_id,accountant_id,description,fault_notes,request_type,odometer,quotes,selected_quote)
 values(rid,e,v.id,(p_data->>'accountant_id')::uuid,p_data->>'description',coalesce(p_data->>'fault_notes',''),p_data->>'request_type',(p_data->>'odometer')::integer,p_data->'quotes',coalesce((p_data->>'selected_quote')::integer,0))
 on conflict(id)do update set vehicle_id=excluded.vehicle_id,accountant_id=excluded.accountant_id,description=excluded.description,fault_notes=excluded.fault_notes,request_type=excluded.request_type,odometer=excluded.odometer,quotes=excluded.quotes,selected_quote=excluded.selected_quote,exception_reason=null,revision=private.fleet_requests.revision+1,updated_at=now();
 insert into private.fleet_events(request_id,actor_id,action,from_state,to_state)values(rid,auth.uid(),'draft_saved',coalesce(r.state,'draft'),coalesce(r.state,'draft'));return rid;
end$$;

create or replace function private.fleet_upload(p_request uuid,p_kind text,p_name text,p_mime text,p_base64 text)returns uuid language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare r private.fleet_requests%rowtype;rid uuid;v bytea;driver boolean;
begin
 perform private.require_module('fleet');
 select * into strict r from private.fleet_requests where id=p_request for update;
 if not private.current_user_is_active() or not private.fleet_visible(r)then raise exception 'Access denied' using errcode='42501';end if;
 driver:=exists(select 1 from private.hr_employees where id=r.driver_id and profile_id=auth.uid())or(p_kind='quote'and private.fleet_can_request_for(r.driver_id))or private.is_admin()or private.fleet_has('fleet.approve');
 if not((driver and ((p_kind='quote' and r.state in('draft','returned'))or(p_kind='invoice' and r.state='repair')))or(p_kind in('payment','refund')and (r.accountant_id=auth.uid()or private.is_admin())and private.fleet_has('fleet.finance')and r.state in('awaiting_advance','reimbursement','settlement')))then raise exception 'Upload denied' using errcode='42501';end if;
 if length(p_base64)>6990510 then raise exception 'الحد الأعلى للمرفق 5 ميجابايت';end if;
 v:=decode(p_base64,'base64');
 if not((p_mime='application/pdf'and substring(v from 1 for 5)=decode('255044462d','hex'))or(p_mime='image/png'and substring(v from 1 for 8)=decode('89504e470d0a1a0a','hex'))or(p_mime='image/jpeg'and substring(v from 1 for 3)=decode('ffd8ff','hex')))then raise exception 'ملف PDF أو PNG أو JPEG صالح مطلوب';end if;
 if(select coalesce(sum(octet_length(bytes)),0)from private.fleet_files where request_id=p_request)+octet_length(v)>31457280 then raise exception 'الحد الإجمالي لمرفقات الطلب 30 ميجابايت';end if;
 insert into private.fleet_files(request_id,kind,name,mime,bytes,actor_id)values(p_request,p_kind,p_name,p_mime,v,auth.uid())returning id into rid;return rid;
end$$;

create or replace function private.fleet_command(p_id uuid,p_revision integer,p_action text,p_data jsonb default '{}')returns jsonb language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare r private.fleet_requests%rowtype;prior text;driver boolean;operator boolean;owner uuid;quote jsonb;total numeric(14,2);q jsonb;eid uuid;diff numeric(14,2);pay_kind text;manager uuid;v private.fleet_vehicles%rowtype;
begin
 perform private.require_module('fleet');
 select * into strict r from private.fleet_requests where id=p_id for update;
 if not private.fleet_visible(r)then raise exception 'Access denied' using errcode='42501';end if;
 if r.revision is distinct from p_revision then raise exception 'تم تعديل الطلب، حدّث الصفحة' using errcode='40001';end if;
 prior:=r.state;driver:=exists(select 1 from private.hr_employees where id=r.driver_id and profile_id=auth.uid());operator:=driver or private.is_admin()or private.fleet_has('fleet.approve');
 if r.state in('closed','rejected')then raise exception 'الطلب مقفل للقراءة فقط';end if;
 if p_action='submit' and private.fleet_can_request_for(r.driver_id) and r.state in('draft','returned')then
  if r.request_type not in('repair','emergency')then raise exception 'نوع الطلب يجب أن يكون صيانة أو عطل طارئ';end if;
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
   if not exists(select 1 from private.fleet_files where id=(q->>'file_id')::uuid and request_id=r.id and kind='quote')then raise exception 'مرفق كل عرض مطلوب';end if;
  end loop;
  if(select count(distinct lower(btrim(value->>'supplier')))from jsonb_array_elements(r.quotes))<>jsonb_array_length(r.quotes)then raise exception 'يجب أن تكون العروض من موردين مختلفين';end if;
  quote:=r.quotes->r.selected_quote;r.approved:=(quote->>'parts')::numeric+(quote->>'labor')::numeric+(quote->>'tax')::numeric;
  r.route:=case when r.approved<=300 then 'small'else 'large'end;
  select m.profile_id into manager from private.hr_employees e join private.hr_employees m on m.id=e.manager_id join public.profiles p on p.id=m.profile_id and p.active and p.status='active' where e.id=r.driver_id;
  if r.route='small' and(manager is null or(manager=auth.uid()and driver))then raise exception 'يجب ربط المدير المباشر بحساب نشط';end if;
  r.manager_id:=manager;r.snapshot:=jsonb_build_object('vehicle',to_jsonb(v),'driver',(select jsonb_build_object('id',id,'name',full_name,'code',employee_code)from private.hr_employees where id=r.driver_id));
  r.state:=case when jsonb_array_length(r.quotes)<3 then 'quote_exception'when r.route='small'then 'manager_review'else 'fleet_review'end;
 elsif p_action='approve_exception' and r.state='quote_exception' and (case when private.is_admin()then true else auth.uid()=private.fleet_owner()end) and not driver then
  if length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'سبب الاستثناء مطلوب';end if;
  r.exception_reason:=p_data->>'reason';r.state:=case when r.route='small'then 'manager_review'else 'fleet_review'end;
 elsif p_action='approve' and r.state='manager_review' and (auth.uid()=r.manager_id or private.is_admin()or private.fleet_has('fleet.approve')) and not driver then r.state:='repair';
 elsif p_action='approve' and r.state='fleet_review' and (case when private.is_admin()then true else auth.uid()=private.fleet_owner()end) and not driver then
  r.state:=case when r.invoice_id is not null then 'reimbursement'else 'awaiting_advance'end;
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
  if not((r.state='manager_review'and (auth.uid()=r.manager_id or private.is_admin()or private.fleet_has('fleet.approve')) and not driver)or(r.state in('quote_exception','fleet_review','increase_review')and (case when private.is_admin()then true else auth.uid()=private.fleet_owner()end))or(r.state in('awaiting_advance','reimbursement','settlement')and (r.accountant_id=auth.uid()or private.is_admin())and private.fleet_has('fleet.finance')and not driver))then raise exception 'Action denied' using errcode='42501';end if;
  if length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'سبب الإعادة أو الرفض مطلوب';end if;
  -- Financially active requests must be corrected and settled, never abandoned with an advance.
  if p_action='reject' and r.advance>0 then raise exception 'لا يمكن رفض طلب له عهدة مصروفة؛ أعده للتصحيح ثم سوّه';end if;
  if p_action='reject'then r.state:='rejected';
  elsif r.invoice_id is not null or r.advance>0 then r.state:='repair';r.invoice_id:=null;r.invoice_total:=null;r.received_at:=null;
  else r.state:='returned';end if;
 else raise exception 'الإجراء غير مسموح لهذه الحالة أو الصلاحية' using errcode='42501';
 end if;
 if pay_kind is not null then
  if nullif(p_data->>'amount','')::numeric is distinct from abs(diff)then raise exception 'المبلغ يجب أن يساوي المستحق تمامًا';end if;
  eid:=nullif(p_data->>'evidence_id','')::uuid;
  if diff<>0 and not exists(select 1 from private.fleet_files where id=eid and request_id=r.id and kind=case when diff<0 then 'refund'else 'payment'end)then raise exception 'مرفق إثبات الصرف أو استرداد المتبقي مطلوب';end if;
  insert into private.fleet_payments(request_id,kind,amount,reference,evidence_id,actor_id)values(r.id,pay_kind,abs(diff),p_data->>'reference',eid,auth.uid());
 end if;
 update private.fleet_requests set state=r.state,route=r.route,manager_id=r.manager_id,approved=r.approved,proposed_total=r.proposed_total,increase_reason=r.increase_reason,
 exception_reason=r.exception_reason,invoice_total=r.invoice_total,invoice_id=r.invoice_id,received_at=r.received_at,advance=r.advance,snapshot=r.snapshot,closed_at=r.closed_at,revision=revision+1,updated_at=now()where id=r.id;
 insert into private.fleet_events(request_id,vehicle_id,actor_id,action,from_state,to_state,payload)values(r.id,r.vehicle_id,auth.uid(),p_action,prior,r.state,p_data-'base64');
 if r.state='closed'then update private.fleet_vehicles set odometer=greatest(odometer,r.odometer),revision=revision+1,updated_at=now()where id=r.vehicle_id;end if;
 return private.fleet_detail(r.id);
end$$;

create or replace function private.fleet_document_visible(p_vehicle uuid)returns boolean language sql stable security definer set search_path=pg_catalog,public,private as $$
 select private.current_user_is_active()and private.module_allowed('fleet')and exists(select 1 from private.fleet_vehicles v left join private.hr_employees e on e.id=v.driver_id left join private.hr_employees m on m.id=e.manager_id where v.id=p_vehicle and(not private.fleet_finance_only()or e.profile_id=auth.uid())and(private.fleet_has('fleet.vehicles.read')or private.fleet_has('fleet.vehicles.write')or private.fleet_has('fleet.approve')or e.profile_id=auth.uid()or m.profile_id=auth.uid()))
$$;
