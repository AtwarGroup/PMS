-- Enforce independent quotes, separation of duties and complete funding.
create or replace function private.fleet_command(p_id uuid,p_revision integer,p_action text,p_data jsonb default '{}')returns jsonb language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare r private.fleet_requests%rowtype;prior text;driver boolean;operator boolean;owner uuid;quote jsonb;total numeric(14,2);q jsonb;eid uuid;diff numeric(14,2);pay_kind text;manager uuid;v private.fleet_vehicles%rowtype;
begin
 perform private.require_module('fleet');
 select * into strict r from private.fleet_requests where id=p_id for update;
 if not private.fleet_visible(r)then raise exception 'Access denied' using errcode='42501';end if;
 if r.revision is distinct from p_revision then raise exception 'تم تعديل الطلب، حدّث الصفحة' using errcode='40001';end if;
 if p_action in('request_increase','confirm_repair') and (p_data->>'total')::numeric is distinct from round((p_data->>'total')::numeric,2) then raise exception 'المبالغ بمنزلتين عشريتين كحد أقصى';end if;
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
  if(select count(distinct (value->>'file_id')::uuid)from jsonb_array_elements(r.quotes))<>jsonb_array_length(r.quotes)then raise exception 'يجب إرفاق ملف مستقل لكل عرض سعر';end if;
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
  if r.route='large' and r.advance<r.approved then raise exception 'يجب صرف كامل المبلغ المعتمد قبل استكمال الإصلاح';end if;
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

