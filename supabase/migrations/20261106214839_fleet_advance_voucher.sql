-- Read-only document data. Existing request visibility remains authoritative.
create function private.fleet_voucher_data(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path=pg_catalog,private,public as $$
declare r private.fleet_requests%rowtype; result jsonb; chief text; finance text;
begin
 perform private.require_module('fleet');
 select * into strict r from private.fleet_requests where id=p_id;
 if not private.fleet_visible(r) or not (private.is_admin() or private.fleet_can_correct() or private.fleet_supervised_owner() is not null or (r.accountant_id=auth.uid() and private.fleet_has('fleet.finance'))) then raise exception 'Access denied' using errcode='42501';end if;
 select jsonb_build_object('employee_name',e.full_name,'employee_code',e.employee_code,'department',d.name,'plate',v.plate,'vehicle_type',v.vehicle_type,'model',v.model,'accountant_name',p.full_name) into result
 from private.hr_employees e left join private.hr_departments d on d.id=e.department_id join private.fleet_vehicles v on v.id=r.vehicle_id join public.profiles p on p.id=r.accountant_id where e.id=r.driver_id;
 -- Use the current shared financial role settings, without copying accounts.
 if to_regclass('private.it_support_settings') is not null then
 execute 'select p.full_name from private.it_support_settings s join public.profiles p on p.id=s.chief_accountant_id where p.active and p.status=''active''' into chief;
 end if;
 if to_regclass('private.recruitment_route_settings') is not null then
 execute 'select p.full_name from private.recruitment_route_settings s join public.profiles p on p.id=s.finance_id where p.active and p.status=''active''' into finance;
 end if;
 return coalesce(result,'{}')||jsonb_build_object('chief_accountant_name',chief,'finance_manager_name',finance,'detail',private.fleet_detail(p_id),'issued_at',now());
end$$;

-- Preserve the reimbursement RPC contract and its eligibility rules.
create or replace function private.fleet_reimbursement_voucher(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path=pg_catalog,private,public as $$
declare result jsonb;r private.fleet_requests%rowtype;
begin
 result:=private.fleet_voucher_data(p_id);
 select * into strict r from private.fleet_requests where id=p_id;
 if r.route is distinct from 'small' or r.state not in('reimbursement','closed') or r.invoice_total is null or r.invoice_total<=0 then raise exception 'نموذج الاستعاضة متاح بعد مراجعة الإصلاح والفاتورة';end if;
 return result;
end$$;
create function private.fleet_advance_voucher(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path=pg_catalog,private,public as $$
declare result jsonb;r private.fleet_requests%rowtype;
begin
 result:=private.fleet_voucher_data(p_id);
 select * into strict r from private.fleet_requests where id=p_id;
 if r.route is distinct from 'large' or not (
   (r.state='awaiting_advance' and r.approved>r.advance)
   or (r.advance>0 and exists(select 1 from private.fleet_payments where request_id=r.id and kind='advance' and amount>0))
 )then raise exception 'أمر الصرف المسبق متاح بعد اعتماد الطلب ووصوله لمرحلة الصرف';end if;
 return result||jsonb_build_object('voucher_kind','advance');
end$$;
create function public.fleet_advance_voucher(p_id uuid) returns jsonb language sql security invoker set search_path=pg_catalog,private as $$select private.fleet_advance_voucher(p_id)$$;
revoke all on function private.fleet_voucher_data(uuid) from public,anon,authenticated;
revoke all on function private.fleet_advance_voucher(uuid),public.fleet_advance_voucher(uuid) from public,anon;
grant execute on function private.fleet_advance_voucher(uuid),public.fleet_advance_voucher(uuid) to authenticated;
notify pgrst,'reload schema';
