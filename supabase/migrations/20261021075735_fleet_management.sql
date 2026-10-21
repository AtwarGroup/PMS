-- Development only until reviewed. All business writes use checked commands; no public table writes.
insert into private.access_catalog(key,module,label,domain,operation,scopes,sort_order) values
 ('fleet.vehicles.read','إدارة الأسطول','عرض سجل السيارات',null,'read',array['all'],100),
 ('fleet.vehicles.write','إدارة الأسطول','إدارة السيارات وربط السائقين',null,'write',array['all'],101),
 ('fleet.approve','إدارة الأسطول','مسؤول الأسطول — الاعتماد والاستثناءات',null,'approve',array['all'],102),
 ('fleet.finance','إدارة الأسطول','المحاسب — الصرف والاستعاضة والتسوية',null,'finance',array['all'],103),
 ('fleet.requests.read','إدارة الأسطول','متابعة طلبات الصيانة',null,'read',array['team','all'],104);

create table private.fleet_vehicles(
 id uuid primary key default gen_random_uuid(),plate text not null unique check(length(btrim(plate)) between 2 and 30),
 vin text unique check(vin is null or length(vin) between 5 and 40),vehicle_type text not null check(length(btrim(vehicle_type)) between 2 and 100),
 model text not null default '' check(length(model)<=100),city text not null default '' check(length(city)<=100),
 driver_id uuid references private.hr_employees(id),active boolean not null default true,
 odometer integer not null default 0 check(odometer>=0),revision integer not null default 1,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create unique index fleet_plate_normalized_key on private.fleet_vehicles(upper(regexp_replace(plate,'\s','','g')));
create unique index fleet_vin_normalized_key on private.fleet_vehicles(upper(btrim(vin)))where vin is not null;
create index fleet_vehicle_driver_idx on private.fleet_vehicles(driver_id);
create table private.fleet_requests(
 id uuid primary key default gen_random_uuid(),number bigint generated always as identity unique,
 driver_id uuid not null references private.hr_employees(id),vehicle_id uuid not null references private.fleet_vehicles(id),
 accountant_id uuid not null references public.profiles(id),manager_id uuid references public.profiles(id),
 description text not null check(length(btrim(description)) between 3 and 4000),fault_notes text not null default '' check(length(fault_notes)<=4000),
 request_type text not null check(request_type in('repair','emergency','inspection','fuel')),
 odometer integer not null check(odometer>=0),quotes jsonb not null default '[]',selected_quote integer not null default 0,
 state text not null default 'draft' check(state in('draft','returned','quote_exception','manager_review','fleet_review','awaiting_advance','repair','increase_review','reimbursement','settlement','closed','rejected')),
 route text check(route in('small','large')),approved numeric(14,2) not null default 0 check(approved>=0),
 proposed_total numeric(14,2),increase_reason text,return_state text,exception_reason text,
 invoice_total numeric(14,2) check(invoice_total>0),invoice_id uuid,received_at timestamptz,
 advance numeric(14,2) not null default 0 check(advance>=0),snapshot jsonb,
 revision integer not null default 1,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),closed_at timestamptz);
create index fleet_request_driver_idx on private.fleet_requests(driver_id,number desc);
create index fleet_request_accountant_idx on private.fleet_requests(accountant_id,state);
create index fleet_request_manager_idx on private.fleet_requests(manager_id,state);
create index fleet_request_vehicle_idx on private.fleet_requests(vehicle_id,number desc);
create table private.fleet_files(
 id uuid primary key default gen_random_uuid(),request_id uuid not null references private.fleet_requests(id),
 kind text not null check(kind in('quote','invoice','payment','refund')),name text not null check(length(name) between 1 and 150),
 mime text not null check(mime in('application/pdf','image/jpeg','image/png')),bytes bytea not null check(octet_length(bytes) between 1 and 5242880),
 actor_id uuid not null references public.profiles(id),created_at timestamptz not null default now());
create index fleet_file_request_idx on private.fleet_files(request_id);
alter table private.fleet_requests add constraint fleet_invoice_fk foreign key(invoice_id) references private.fleet_files(id);
create table private.fleet_events(
 id bigint generated always as identity primary key,request_id uuid references private.fleet_requests(id),vehicle_id uuid references private.fleet_vehicles(id),
 actor_id uuid not null references public.profiles(id),action text not null,from_state text,to_state text,payload jsonb not null default '{}',created_at timestamptz not null default now());
create index fleet_event_request_idx on private.fleet_events(request_id,id);
create index fleet_event_vehicle_idx on private.fleet_events(vehicle_id,id);
create table private.fleet_payments(
 id uuid primary key default gen_random_uuid(),request_id uuid not null references private.fleet_requests(id),
 kind text not null check(kind in('advance','reimbursement','refund','topup','settle')),
 amount numeric(14,2) not null check(amount>=0),reference text not null check(length(btrim(reference)) between 3 and 200),
 evidence_id uuid references private.fleet_files(id),actor_id uuid not null references public.profiles(id),created_at timestamptz not null default now());
create index fleet_payment_request_idx on private.fleet_payments(request_id);
do $$declare t text;begin
 foreach t in array array['fleet_vehicles','fleet_requests','fleet_files','fleet_events','fleet_payments']loop
 execute format('alter table private.%I enable row level security',t);
 execute format('revoke all on private.%I from public,anon,authenticated',t);
 end loop;
end$$;
-- Read existing sources on each action: revocation is immediate, no JWT/permission projection cache.
create function private.fleet_has(p_key text,p_employee uuid default null)returns boolean language sql stable security definer set search_path=pg_catalog,public,private as $$
 select private.current_user_is_active() and (
 (private.is_admin() and p_key in('fleet.vehicles.read','fleet.vehicles.write','fleet.requests.read'))
 or exists(select 1 from private.access_direct_tasks d where d.profile_id=auth.uid() and p_key=any(d.permissions))
 or exists(select 1 from private.access_assignments a join private.access_roles r on r.id=a.role_id and r.active
 join private.access_role_rules g on g.role_id=r.id where a.profile_id=auth.uid() and g.permission=p_key
 and(g.scope='all' or (p_employee is not null and private.hr_in_team(p_employee)))))
$$;
create function private.fleet_owner()returns uuid language plpgsql stable security definer set search_path=pg_catalog,public,private as $$
declare ids uuid[];
begin
 select array_agg(p.id)into ids from public.profiles p where p.active and p.status='active' and(
 exists(select 1 from private.access_direct_tasks d where d.profile_id=p.id and 'fleet.approve'=any(d.permissions))
 or exists(select 1 from private.access_assignments a join private.access_roles r on r.id=a.role_id and r.active join private.access_role_rules g on g.role_id=r.id where a.profile_id=p.id and g.permission='fleet.approve'));
 if cardinality(ids) is distinct from 1 then raise exception 'يجب تعيين مسؤول أسطول واحد نشط من الحسابات والصلاحيات';end if;return ids[1];
end$$;
create function private.fleet_visible(r private.fleet_requests)returns boolean language sql stable security definer set search_path=pg_catalog,public,private as $$
 select private.current_user_is_active() and(
 exists(select 1 from private.hr_employees e where e.id=r.driver_id and e.profile_id=auth.uid())
 or coalesce(r.manager_id=auth.uid(),false) or(r.accountant_id=auth.uid() and private.fleet_has('fleet.finance'))
 or private.fleet_has('fleet.approve') or private.fleet_has('fleet.requests.read',r.driver_id))
$$;
create function private.fleet_snapshot()returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,private as $$
declare employee uuid;manage boolean;approve boolean;result jsonb;
begin
 if not private.current_user_is_active()then raise exception 'Authentication required' using errcode='42501';end if;
 select id into employee from private.hr_employees where profile_id=auth.uid();
 manage:=private.fleet_has('fleet.vehicles.write');approve:=private.fleet_has('fleet.approve');
 result:=jsonb_build_object('user_id',auth.uid(),'employee_id',employee,'can_manage',manage,'can_approve',approve,'can_finance',private.fleet_has('fleet.finance'),
 'vehicles',(select coalesce(jsonb_agg(to_jsonb(v)||jsonb_build_object('driver_name',e.full_name)order by v.plate),'[]')from private.fleet_vehicles v left join private.hr_employees e on e.id=v.driver_id where v.driver_id=employee or manage or approve or private.fleet_has('fleet.vehicles.read')),
 'employees',case when manage then(select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',full_name,'code',employee_code)order by full_name),'[]')from private.hr_employees)else '[]'::jsonb end,
 'accountants',(select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.full_name)order by p.full_name),'[]')from public.profiles p where p.active and p.status='active' and (
 exists(select 1 from private.access_direct_tasks d where d.profile_id=p.id and 'fleet.finance'=any(d.permissions))
 or exists(select 1 from private.access_assignments a join private.access_roles ar on ar.id=a.role_id and ar.active join private.access_role_rules g on g.role_id=ar.id where a.profile_id=p.id and g.permission='fleet.finance'))),
 'requests',(select coalesce(jsonb_agg(to_jsonb(r)||jsonb_build_object('driver_name',e.full_name,'plate',v.plate,'accountant_name',p.full_name) order by r.number desc),'[]')from private.fleet_requests r join private.hr_employees e on e.id=r.driver_id join private.fleet_vehicles v on v.id=r.vehicle_id join public.profiles p on p.id=r.accountant_id where private.fleet_visible(r)));
 return result;
end$$;
create function private.fleet_vehicle_save(p_id uuid,p_revision integer,p_data jsonb,p_reason text)returns uuid language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare v private.fleet_vehicles%rowtype;rid uuid:=coalesce(p_id,gen_random_uuid());b jsonb;
begin
 if not private.fleet_has('fleet.vehicles.write')then raise exception 'Vehicle management denied' using errcode='42501';end if;
 if length(btrim(coalesce(p_reason,'')))<3 then raise exception 'سبب التغيير مطلوب';end if;
 if p_id is not null then select * into strict v from private.fleet_vehicles where id=p_id for update;
 if v.revision is distinct from p_revision then raise exception 'تم تعديل السيارة، حدّث الصفحة' using errcode='40001';end if;b:=to_jsonb(v);
 if (v.driver_id is distinct from nullif(p_data->>'driver_id','')::uuid or v.active is distinct from(p_data->>'active')::boolean)and exists(select 1 from private.fleet_requests where vehicle_id=v.id and state not in('closed','rejected','draft','returned'))then raise exception 'أكمل الطلبات المفتوحة قبل نقل عهدة السيارة أو إيقافها';end if;
 end if;
 insert into private.fleet_vehicles(id,plate,vin,vehicle_type,model,city,driver_id,active,odometer)
 values(rid,btrim(p_data->>'plate'),nullif(upper(btrim(p_data->>'vin')),''),btrim(p_data->>'vehicle_type'),coalesce(p_data->>'model',''),coalesce(p_data->>'city',''),nullif(p_data->>'driver_id','')::uuid,coalesce((p_data->>'active')::boolean,true),coalesce((p_data->>'odometer')::integer,0))
 on conflict(id)do update set plate=excluded.plate,vin=excluded.vin,vehicle_type=excluded.vehicle_type,model=excluded.model,city=excluded.city,driver_id=excluded.driver_id,active=excluded.active,odometer=greatest(private.fleet_vehicles.odometer,excluded.odometer),revision=private.fleet_vehicles.revision+1,updated_at=now();
 insert into private.fleet_events(vehicle_id,actor_id,action,payload)values(rid,auth.uid(),'vehicle_saved',jsonb_build_object('before',b,'after',(select to_jsonb(x)from private.fleet_vehicles x where id=rid),'reason',p_reason));return rid;
end$$;
create function private.fleet_request_save(p_id uuid,p_revision integer,p_data jsonb)returns uuid language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare r private.fleet_requests%rowtype;e uuid;v private.fleet_vehicles%rowtype;rid uuid:=coalesce(p_id,gen_random_uuid());
begin
 if not private.current_user_is_active()then raise exception 'Authentication required' using errcode='42501';end if;
 select id into strict e from private.hr_employees where profile_id=auth.uid();
 if p_id is not null then select * into strict r from private.fleet_requests where id=p_id for update;
 if r.driver_id<>e or r.state not in('draft','returned')then raise exception 'لا يمكن تعديل الطلب في هذه المرحلة' using errcode='42501';end if;
 if r.revision is distinct from p_revision then raise exception 'تم تعديل الطلب، حدّث الصفحة' using errcode='40001';end if;end if;
 select * into strict v from private.fleet_vehicles where id=(p_data->>'vehicle_id')::uuid for update;
 if v.driver_id is distinct from e or not v.active then raise exception 'السيارة ليست مسجلة باسمك' using errcode='42501';end if;
 if (p_data->>'odometer')::integer<v.odometer then raise exception 'قراءة العداد أقل من السجل';end if;
 if not exists(select 1 from public.profiles p where p.id=(p_data->>'accountant_id')::uuid and p.id<>auth.uid() and p.active and p.status='active' and(
 exists(select 1 from private.access_direct_tasks d where d.profile_id=p.id and 'fleet.finance'=any(d.permissions))or exists(select 1 from private.access_assignments a join private.access_roles ar on ar.id=a.role_id and ar.active join private.access_role_rules g on g.role_id=ar.id where a.profile_id=p.id and g.permission='fleet.finance')))then raise exception 'اختر محاسبًا نشطًا مخولًا';end if;
 if jsonb_typeof(p_data->'quotes')is distinct from 'array' or jsonb_array_length(p_data->'quotes')>10 then raise exception 'Invalid quotes';end if;
 insert into private.fleet_requests(id,driver_id,vehicle_id,accountant_id,description,fault_notes,request_type,odometer,quotes,selected_quote)
 values(rid,e,v.id,(p_data->>'accountant_id')::uuid,p_data->>'description',coalesce(p_data->>'fault_notes',''),p_data->>'request_type',(p_data->>'odometer')::integer,p_data->'quotes',coalesce((p_data->>'selected_quote')::integer,0))
 on conflict(id)do update set vehicle_id=excluded.vehicle_id,accountant_id=excluded.accountant_id,description=excluded.description,fault_notes=excluded.fault_notes,request_type=excluded.request_type,odometer=excluded.odometer,quotes=excluded.quotes,selected_quote=excluded.selected_quote,exception_reason=null,revision=private.fleet_requests.revision+1,updated_at=now();
 insert into private.fleet_events(request_id,actor_id,action,from_state,to_state)values(rid,auth.uid(),'draft_saved',coalesce(r.state,'draft'),coalesce(r.state,'draft'));return rid;
end$$;
create function private.fleet_upload(p_request uuid,p_kind text,p_name text,p_mime text,p_base64 text)returns uuid language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare r private.fleet_requests%rowtype;rid uuid;v bytea;driver boolean;
begin
 select * into strict r from private.fleet_requests where id=p_request for update;
 if not private.current_user_is_active() or not private.fleet_visible(r)then raise exception 'Access denied' using errcode='42501';end if;
 driver:=exists(select 1 from private.hr_employees where id=r.driver_id and profile_id=auth.uid());
 if not((driver and ((p_kind='quote' and r.state in('draft','returned'))or(p_kind='invoice' and r.state='repair')))or(p_kind in('payment','refund')and r.accountant_id=auth.uid()and private.fleet_has('fleet.finance')and r.state in('awaiting_advance','reimbursement','settlement')))then raise exception 'Upload denied' using errcode='42501';end if;
 if length(p_base64)>6990510 then raise exception 'الحد الأعلى للمرفق 5 ميجابايت';end if;
 v:=decode(p_base64,'base64');
 if not((p_mime='application/pdf'and substring(v from 1 for 5)=decode('255044462d','hex'))or(p_mime='image/png'and substring(v from 1 for 8)=decode('89504e470d0a1a0a','hex'))or(p_mime='image/jpeg'and substring(v from 1 for 3)=decode('ffd8ff','hex')))then raise exception 'ملف PDF أو PNG أو JPEG صالح مطلوب';end if;
 if(select coalesce(sum(octet_length(bytes)),0)from private.fleet_files where request_id=p_request)+octet_length(v)>31457280 then raise exception 'الحد الإجمالي لمرفقات الطلب 30 ميجابايت';end if;
 insert into private.fleet_files(request_id,kind,name,mime,bytes,actor_id)values(p_request,p_kind,p_name,p_mime,v,auth.uid())returning id into rid;return rid;
end$$;
create function private.fleet_detail(p_id uuid)returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,private as $$
declare r private.fleet_requests%rowtype;
begin
 select * into strict r from private.fleet_requests where id=p_id;
 if not private.fleet_visible(r)then raise exception 'Access denied' using errcode='42501';end if;
 return jsonb_build_object('request',to_jsonb(r),'events',(select coalesce(jsonb_agg(to_jsonb(e)||jsonb_build_object('actor_name',p.full_name)order by e.id),'[]')from private.fleet_events e join public.profiles p on p.id=e.actor_id where e.request_id=p_id),
 'files',(select coalesce(jsonb_agg(to_jsonb(f)-'bytes' order by created_at),'[]')from private.fleet_files f where request_id=p_id),'payments',(select coalesce(jsonb_agg(to_jsonb(p)order by created_at),'[]')from private.fleet_payments p where request_id=p_id));
end$$;
create function private.fleet_download(p_id uuid)returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,private as $$
declare f private.fleet_files%rowtype;r private.fleet_requests%rowtype;
begin
 select * into strict f from private.fleet_files where id=p_id;select * into strict r from private.fleet_requests where id=f.request_id;
 if not private.fleet_visible(r)then raise exception 'Access denied' using errcode='42501';end if;
 return jsonb_build_object('name',f.name,'mime',f.mime,'base64',encode(f.bytes,'base64'));
end$$;
create function private.fleet_command(p_id uuid,p_revision integer,p_action text,p_data jsonb default '{}')returns jsonb language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare r private.fleet_requests%rowtype;prior text;driver boolean;owner uuid;quote jsonb;total numeric(14,2);q jsonb;eid uuid;diff numeric(14,2);pay_kind text;manager uuid;v private.fleet_vehicles%rowtype;
begin
 select * into strict r from private.fleet_requests where id=p_id for update;
 if not private.fleet_visible(r)then raise exception 'Access denied' using errcode='42501';end if;
 if r.revision is distinct from p_revision then raise exception 'تم تعديل الطلب، حدّث الصفحة' using errcode='40001';end if;
 prior:=r.state;driver:=exists(select 1 from private.hr_employees where id=r.driver_id and profile_id=auth.uid());
 if r.state in('closed','rejected')then raise exception 'الطلب مقفل للقراءة فقط';end if;
 if p_action='submit' and driver and r.state in('draft','returned')then
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
  if r.route='small' and(manager is null or manager=auth.uid())then raise exception 'يجب ربط المدير المباشر بحساب نشط';end if;
  r.manager_id:=manager;r.snapshot:=jsonb_build_object('vehicle',to_jsonb(v),'driver',(select jsonb_build_object('id',id,'name',full_name,'code',employee_code)from private.hr_employees where id=r.driver_id));
  r.state:=case when jsonb_array_length(r.quotes)<3 then 'quote_exception'when r.route='small'then 'manager_review'else 'fleet_review'end;
 elsif p_action='approve_exception' and r.state='quote_exception' and auth.uid()=private.fleet_owner() and not driver then
  if length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'سبب الاستثناء مطلوب';end if;
  r.exception_reason:=p_data->>'reason';r.state:=case when r.route='small'then 'manager_review'else 'fleet_review'end;
 elsif p_action='approve' and r.state='manager_review' and auth.uid()=r.manager_id and not driver then r.state:='repair';
 elsif p_action='approve' and r.state='fleet_review' and auth.uid()=private.fleet_owner() and not driver then
  r.state:=case when r.invoice_id is not null then 'reimbursement'else 'awaiting_advance'end;
 elsif p_action='request_increase' and r.state='repair' and driver then
  total:=(p_data->>'total')::numeric;
  if total is null or total<=r.approved or total>99999999 or length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'أدخل إجماليًا أعلى وسبب الزيادة قبل تنفيذها';end if;
  r.proposed_total:=total;r.increase_reason:=p_data->>'reason';r.state:='increase_review';
 elsif p_action='approve_increase' and r.state='increase_review' and auth.uid()=private.fleet_owner() and not driver then
  r.approved:=r.proposed_total;r.proposed_total:=null;
  if r.approved>300 then r.route:='large';end if;
  r.state:=case when r.route='large'then 'awaiting_advance'else 'repair'end;
 elsif p_action='decline_increase' and r.state='increase_review' and auth.uid()=private.fleet_owner() and not driver then
  if length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'سبب رفض الزيادة مطلوب';end if;
  r.proposed_total:=null;r.state:='repair';
 elsif p_action='confirm_repair' and r.state='repair' and driver then
  total:=(p_data->>'total')::numeric;eid:=(p_data->>'invoice_id')::uuid;
  if coalesce((p_data->>'received')::boolean,false)is not true then raise exception 'تأكيد استلام السيارة مطلوب';end if;
  if total is null or total<=0 or total>r.approved then raise exception 'الفاتورة يجب ألا تتجاوز المعتمد؛ اطلب اعتماد الزيادة قبل تنفيذها';end if;
  if not exists(select 1 from private.fleet_files where id=eid and request_id=r.id and kind='invoice')then raise exception 'أرفق الفاتورة';end if;
  r.invoice_total:=total;r.invoice_id:=eid;r.received_at:=now();r.state:=case when r.route='small'then 'fleet_review'else 'settlement'end;
 elsif p_action='confirm_advance' and r.state='awaiting_advance' and r.accountant_id=auth.uid() and private.fleet_has('fleet.finance') and not driver then
  diff:=r.approved-r.advance;
  if diff<=0 then raise exception 'لا توجد دفعة مستحقة';end if;
  pay_kind:='advance';r.advance:=r.approved;r.state:='repair';
 elsif p_action='settle' and r.state in('reimbursement','settlement')and r.accountant_id=auth.uid()and private.fleet_has('fleet.finance')and not driver then
  diff:=r.invoice_total-r.advance;
  pay_kind:=case when r.state='reimbursement'then 'reimbursement'when diff<0 then 'refund'when diff>0 then 'topup'else 'settle'end;
  r.state:='closed';r.closed_at:=now();
 elsif p_action in('return','reject')and r.state in('quote_exception','manager_review','fleet_review','increase_review','awaiting_advance','reimbursement','settlement')then
  if not((r.state='manager_review'and auth.uid()=r.manager_id and not driver)or(r.state in('quote_exception','fleet_review','increase_review')and auth.uid()=private.fleet_owner())or(r.state in('awaiting_advance','reimbursement','settlement')and r.accountant_id=auth.uid()and private.fleet_has('fleet.finance')and not driver))then raise exception 'Action denied' using errcode='42501';end if;
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
-- Reuse existing direct grants and administrative UI; no second permission store.
alter function private.access_direct_save(uuid,jsonb)rename to access_direct_save_before_fleet;
create function private.access_direct_save(p_profile uuid,p_rules jsonb)returns void language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare old_rules jsonb;legacy jsonb;
begin
 if not private.is_admin()then raise exception 'Administrator access required' using errcode='42501';end if;
 if p_rules is null or jsonb_typeof(p_rules)<>'array'then raise exception 'Invalid grants';end if;
 if exists(select 1 from jsonb_to_recordset(p_rules)x(permission text,scope text)left join private.access_catalog c on c.key=x.permission where c.key is null or x.scope is null or not x.scope=any(c.scopes))then raise exception 'Invalid permission or scope';end if;
 if exists(select 1 from jsonb_to_recordset(p_rules)x(permission text,scope text)where x.permission like 'fleet.%' and x.scope<>'all')then raise exception 'استخدم الأدوار لتحديد نطاق فريق في الأسطول';end if;
 select coalesce(jsonb_agg(value),'[]')into legacy from jsonb_array_elements(p_rules)where value->>'permission' not like 'fleet.%';
 perform private.access_direct_save_before_fleet(p_profile,legacy);
 select to_jsonb(d)into old_rules from private.access_direct_tasks d where profile_id=p_profile for update;
 insert into private.access_direct_tasks(profile_id)values(p_profile)on conflict do nothing;
 update private.access_direct_tasks set permissions=array(select key from(
 select unnest(permissions)key where true
 )x where key not like 'fleet.%')||array(select distinct value->>'permission'from jsonb_array_elements(p_rules)where value->>'permission' like 'fleet.%')where profile_id=p_profile;
 perform private.access_rebuild_tasks(p_profile);
 perform private.access_log('DIRECT_FLEET_GRANT',p_profile::text,old_rules,(select to_jsonb(d)from private.access_direct_tasks d where profile_id=p_profile));
end$$;
-- A direct grant uses all scope. Team follow-up is configured through reusable roles.
-- Existing employee vehicle data is a compatibility source, not a second fleet registry.
insert into private.fleet_vehicles(plate,vin,vehicle_type,driver_id)
 select btrim(plate),nullif(btrim(vin),''),coalesce(nullif(btrim(vehicle_type),''),'غير محدد'),employee_id from private.hr_vehicles h
 where nullif(btrim(plate),'')is not null and length(btrim(plate))between 2 and 30 and(vin is null or nullif(btrim(vin),'')is null or length(btrim(vin))between 5 and 40)
 and not exists(select 1 from private.hr_vehicles d where d.employee_id<>h.employee_id and(upper(regexp_replace(d.plate,'\s','','g'))=upper(regexp_replace(h.plate,'\s','','g'))or(nullif(btrim(h.vin),'')is not null and upper(btrim(d.vin))=upper(btrim(h.vin)))))
 on conflict do nothing;
-- Public wrappers are invokers; the private implementations are explicitly granted only as checked API entrypoints.
create function public.fleet_snapshot()returns jsonb language sql security invoker set search_path=pg_catalog,private as $$select private.fleet_snapshot()$$;
create function public.fleet_vehicle_save(p_id uuid,p_revision integer,p_data jsonb,p_reason text)returns uuid language sql security invoker set search_path=pg_catalog,private as $$select private.fleet_vehicle_save(p_id,p_revision,p_data,p_reason)$$;
create function public.fleet_request_save(p_id uuid,p_revision integer,p_data jsonb)returns uuid language sql security invoker set search_path=pg_catalog,private as $$select private.fleet_request_save(p_id,p_revision,p_data)$$;
create function public.fleet_upload(p_request uuid,p_kind text,p_name text,p_mime text,p_base64 text)returns uuid language sql security invoker set search_path=pg_catalog,private as $$select private.fleet_upload(p_request,p_kind,p_name,p_mime,p_base64)$$;
create function public.fleet_detail(p_id uuid)returns jsonb language sql security invoker set search_path=pg_catalog,private as $$select private.fleet_detail(p_id)$$;
create function public.fleet_download(p_id uuid)returns jsonb language sql security invoker set search_path=pg_catalog,private as $$select private.fleet_download(p_id)$$;
create function public.fleet_command(p_id uuid,p_revision integer,p_action text,p_data jsonb default '{}')returns jsonb language sql security invoker set search_path=pg_catalog,private as $$select private.fleet_command(p_id,p_revision,p_action,p_data)$$;
do $$declare f record;begin
 for f in select p.oid::regprocedure signature,n.nspname,p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in('private','public')and p.proname like 'fleet_%'loop
 execute format('revoke all on function %s from public,anon,authenticated',f.signature);
 if f.proname in('fleet_snapshot','fleet_vehicle_save','fleet_request_save','fleet_upload','fleet_detail','fleet_download','fleet_command')then execute format('grant execute on function %s to authenticated',f.signature);end if;
 end loop;
end$$;
revoke all on function private.access_direct_save_before_fleet(uuid,jsonb)from public,anon,authenticated;
revoke all on function private.access_direct_save(uuid,jsonb)from public,anon;
grant execute on function private.access_direct_save(uuid,jsonb)to authenticated;
-- The employee file displays canonical fleet assignments; vehicle edits move to the fleet command.
alter function private.hr_detail(uuid)rename to hr_detail_before_fleet;
create function private.hr_detail(p_id uuid)returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,private as $$
declare result jsonb;
begin
 result:=private.hr_detail_before_fleet(p_id)-'vehicles';
 if private.hr_allowed(p_id,'vehicles',false)then
 result:=result||jsonb_build_object('fleet_vehicles',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'plate',plate,'vin',vin,'vehicle_type',vehicle_type,'model',model,'active',active)order by plate),'[]')from private.fleet_vehicles where driver_id=p_id));
 end if;return result;
end$$;
alter function private.hr_save(uuid,text,integer,jsonb,date,text)rename to hr_save_before_fleet;
create function private.hr_save(p_id uuid,p_domain text,p_revision integer,p_payload jsonb,p_effective date,p_reason text)returns jsonb language plpgsql security definer set search_path=pg_catalog,public,private as $$
begin
 if p_domain='vehicles'then raise exception 'تُدار عهد السيارات من وحدة إدارة الأسطول' using errcode='42501';end if;
 return private.hr_save_before_fleet(p_id,p_domain,p_revision,p_payload,p_effective,p_reason);
end$$;
revoke all on function private.hr_detail_before_fleet(uuid),private.hr_save_before_fleet(uuid,text,integer,jsonb,date,text)from public,anon,authenticated;
revoke all on function private.hr_detail(uuid),private.hr_save(uuid,text,integer,jsonb,date,text)from public,anon;
grant execute on function private.hr_detail(uuid),private.hr_save(uuid,text,integer,jsonb,date,text)to authenticated;
-- Source-file imports are transactional, repeat-safe and support a real rollback dry run.
create table private.fleet_imports(source_hash text primary key check(source_hash~'^[a-f0-9]{64}$'),summary jsonb not null,actor_id uuid not null references public.profiles(id),created_at timestamptz not null default now());
alter table private.fleet_imports enable row level security;
revoke all on private.fleet_imports from public,anon,authenticated;
create function private.fleet_import(p_rows jsonb,p_source_hash text,p_dry_run boolean default true)returns jsonb language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare row jsonb;v private.fleet_vehicles%rowtype;result jsonb;added integer:=0;changed integer:=0;matches integer;
begin
 if not private.fleet_has('fleet.vehicles.write')then raise exception 'Vehicle management denied' using errcode='42501';end if;
 if p_source_hash is null or p_source_hash!~'^[a-f0-9]{64}$'or p_rows is null or jsonb_typeof(p_rows)<>'array'or jsonb_array_length(p_rows)not between 1 and 500 or p_dry_run is null then raise exception 'Invalid import';end if;
 perform pg_advisory_xact_lock(hashtext('fleet_import'));
 if exists(select 1 from private.fleet_imports where source_hash=p_source_hash)then raise exception 'تم استيراد هذا المصدر سابقًا';end if;
 if(select count(distinct upper(regexp_replace(value->>'plate','\s','','g')))from jsonb_array_elements(p_rows))<>jsonb_array_length(p_rows)then raise exception 'Duplicate source plates';end if;
 begin
  for row in select value from jsonb_array_elements(p_rows)loop
   select count(*)into matches from private.fleet_vehicles where upper(regexp_replace(plate,'\s','','g'))=upper(regexp_replace(row->>'plate','\s','','g'))or(vin is not null and upper(vin)=nullif(upper(btrim(row->>'vin')),''));
   if matches>1 then raise exception 'الهيكل واللوحة يشيران إلى سجلين مختلفين';end if;
   select * into v from private.fleet_vehicles where upper(regexp_replace(plate,'\s','','g'))=upper(regexp_replace(row->>'plate','\s','','g'))or(vin is not null and upper(vin)=nullif(upper(btrim(row->>'vin')),''));
   if v.id is null then added:=added+1;else
   if v.driver_id is not null and v.driver_id is distinct from nullif(row->>'driver_id','')::uuid then raise exception 'تعارض عهدة حالية: راجع ربط السائق قبل الاستيراد';end if;
   changed:=changed+1;end if;
   perform private.fleet_vehicle_save(v.id,v.revision,row,'استيراد ملف السيارات — '||p_source_hash);
  end loop;
  result:=jsonb_build_object('added',added,'updated',changed,'dry_run',p_dry_run,'total',jsonb_array_length(p_rows));
  insert into private.fleet_imports(source_hash,summary,actor_id)values(p_source_hash,result,auth.uid());
  if p_dry_run then raise exception using errcode='ZF001',message='dry run rollback';end if;
 exception when sqlstate 'ZF001'then null;
 end;
 return result;
end$$;
create function public.fleet_import(p_rows jsonb,p_source_hash text,p_dry_run boolean default true)returns jsonb language sql security invoker set search_path=pg_catalog,private as $$select private.fleet_import(p_rows,p_source_hash,p_dry_run)$$;
revoke all on function public.fleet_import(jsonb,text,boolean),private.fleet_import(jsonb,text,boolean)from public,anon;
grant execute on function public.fleet_import(jsonb,text,boolean),private.fleet_import(jsonb,text,boolean)to authenticated;
