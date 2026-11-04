do $copy$ declare definition text;begin
 select pg_get_functiondef('private.fleet_visible(private.fleet_requests)'::regprocedure)into definition;execute replace(definition,'FUNCTION private.fleet_visible(','FUNCTION private.fleet_visible_before_corrections(');
 select pg_get_functiondef('private.fleet_request_listed(private.fleet_requests)'::regprocedure)into definition;execute replace(definition,'FUNCTION private.fleet_request_listed(','FUNCTION private.fleet_request_listed_before_corrections(');
 select pg_get_functiondef('private.fleet_handover_visible(private.fleet_handovers)'::regprocedure)into definition;execute replace(definition,'FUNCTION private.fleet_handover_visible(','FUNCTION private.fleet_handover_visible_before_corrections(');
 select pg_get_functiondef('private.fleet_handover_listed(private.fleet_handovers)'::regprocedure)into definition;execute replace(definition,'FUNCTION private.fleet_handover_listed(','FUNCTION private.fleet_handover_listed_before_corrections(');
 select pg_get_functiondef('private.fleet_snapshot()'::regprocedure)into definition;execute replace(definition,'FUNCTION private.fleet_snapshot(','FUNCTION private.fleet_snapshot_before_corrections(');
 select pg_get_functiondef('private.fleet_request_save(uuid,integer,jsonb)'::regprocedure)into definition;execute replace(definition,'FUNCTION private.fleet_request_save(','FUNCTION private.fleet_request_save_before_corrections(');
end $copy$;
-- Only designated operators may correct requests; finance remains a separate role.
create function private.fleet_can_correct() returns boolean language plpgsql stable security definer set search_path=pg_catalog,private,public as $$
begin
 if not private.current_user_is_active() or not private.module_allowed('fleet')then return false;end if;
 if private.is_admin()then return true;end if;
 return auth.uid()=private.fleet_owner();
end$$;
create function private.fleet_valid_accountant(p_id uuid) returns boolean language sql stable security definer set search_path=pg_catalog,private,public as $$
 select exists(select 1 from public.profiles p where p.id=p_id and p.role<>'admin' and p.active and p.status='active' and 'fleet'=any(p.allowed_modules) and(
 exists(select 1 from private.access_direct_tasks d where d.profile_id=p.id and 'fleet.finance'=any(d.permissions))or exists(select 1 from private.access_assignments a join private.access_roles r on r.id=a.role_id and r.active join private.access_role_rules g on g.role_id=r.id where a.profile_id=p.id and g.permission='fleet.finance')))
$$;
create or replace function private.fleet_visible(r private.fleet_requests)returns boolean language sql stable security definer set search_path=pg_catalog,private,public as $$select private.fleet_can_correct()or(private.current_user_is_active()and private.module_allowed('fleet')and private.fleet_supervised_owner()is not null)or private.fleet_visible_before_corrections(r)$$;
create or replace function private.fleet_request_listed(r private.fleet_requests)returns boolean language sql stable security definer set search_path=pg_catalog,private,public as $$select private.fleet_can_correct()or(private.current_user_is_active()and private.module_allowed('fleet')and private.fleet_supervised_owner()is not null)or private.fleet_request_listed_before_corrections(r)$$;
create or replace function private.fleet_handover_visible(h private.fleet_handovers)returns boolean language sql stable security definer set search_path=pg_catalog,private,public as $$select private.fleet_can_correct()or(private.current_user_is_active()and private.module_allowed('fleet')and private.fleet_supervised_owner()is not null)or private.fleet_handover_visible_before_corrections(h)$$;
create or replace function private.fleet_handover_listed(h private.fleet_handovers)returns boolean language sql stable security definer set search_path=pg_catalog,private,public as $$select private.fleet_can_correct()or(private.current_user_is_active()and private.module_allowed('fleet')and private.fleet_supervised_owner()is not null)or private.fleet_handover_listed_before_corrections(h)$$;
create or replace function private.fleet_snapshot()returns jsonb language plpgsql stable security definer set search_path=pg_catalog,private,public as $$declare result jsonb;begin
 perform private.require_module('fleet');result:=private.fleet_snapshot_before_corrections();
 return result||jsonb_build_object('can_correct',private.fleet_can_correct(),'accountants',(select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.full_name)order by p.full_name),'[]')from public.profiles p where private.fleet_valid_accountant(p.id)));
end$$;
create or replace function private.fleet_request_save(p_id uuid,p_revision integer,p_data jsonb)returns uuid language plpgsql security definer set search_path=pg_catalog,private,public as $$begin
 perform private.require_module('fleet');if not private.fleet_valid_accountant((p_data->>'accountant_id')::uuid)then raise exception 'اختر محاسبًا نشطًا مخولًا؛ مسؤول النظام ليس ضمن خيارات المحاسبين';end if;
 return private.fleet_request_save_before_corrections(p_id,p_revision,p_data);
end$$;
create function private.fleet_request_correct(p_id uuid,p_revision integer,p_data jsonb,p_reason text)returns jsonb language plpgsql security definer set search_path=pg_catalog,private,public as $$
declare r private.fleet_requests%rowtype; prior private.fleet_requests%rowtype;next_data jsonb;financial_changed boolean;key text;recipient uuid;result jsonb;
begin
 perform private.require_module('fleet');if not private.fleet_can_correct()then raise exception 'التعديل متاح لمسؤول النظام ومسؤول الأسطول فقط'using errcode='42501';end if;
 if char_length(btrim(coalesce(p_reason,'')))not between 3 and 1000 then raise exception 'سبب التعديل مطلوب، من 3 إلى 1000 حرف';end if;
 select * into strict r from private.fleet_requests where id=p_id for update;prior:=r;
 if r.revision is distinct from p_revision then raise exception 'تم تعديل الطلب، حدّث الصفحة'using errcode='40001';end if;
 if jsonb_typeof(p_data)is distinct from 'object'then raise exception 'بيانات التعديل غير صالحة';end if;
 for key in select jsonb_object_keys(p_data)loop if key<>all(array['accountant_id','description','fault_notes','odometer','request_type','maintenance_kind','stops_vehicle','needs_tow','quotes','selected_quote'])then raise exception 'هذا الحقل لا يعدل مباشرة: %',key;end if;end loop;
 next_data:=to_jsonb(r)||p_data;
 if char_length(btrim(coalesce(next_data->>'description','')))not between 10 and 4000 or char_length(btrim(coalesce(next_data->>'fault_notes','')))not between 10 and 4000 then raise exception 'تفاصيل الصيانة وسبب العطل مطلوبان، من 10 إلى 4000 حرف';end if;
 if not private.fleet_valid_accountant((next_data->>'accountant_id')::uuid)or(next_data->>'accountant_id')::uuid=(select profile_id from private.hr_employees where id=r.driver_id)then raise exception 'اختر محاسبًا نشطًا مستقلًا مخولًا';end if;
 if coalesce((next_data->>'odometer')::int,0)<=0 then raise exception 'قراءة العداد يجب أن تكون أكبر من صفر';end if;
 select * into r from jsonb_populate_record(r,p_data);
 financial_changed:=(r.request_type,r.maintenance_kind,r.stops_vehicle,r.needs_tow,r.quotes,r.selected_quote)is distinct from(prior.request_type,prior.maintenance_kind,prior.stops_vehicle,prior.needs_tow,prior.quotes,prior.selected_quote);
 if financial_changed and(prior.advance>0 or prior.invoice_id is not null or prior.state in('closed','rejected')or exists(select 1 from private.fleet_payments where request_id=r.id))then raise exception 'الطلب يتضمن صرفًا أو فاتورة أو انتهى؛ التغييرات المالية تعالج عبر إجراءات الزيادة والتسوية';end if;
 if r.request_type not in('repair','emergency')or jsonb_typeof(r.quotes)is distinct from 'array'or jsonb_array_length(r.quotes)>10 then raise exception 'نوع الطلب أو العروض غير صالحة';end if;
 if financial_changed then
  if r.workflow_version<>2 then raise exception 'يجب ترقية الطلب القديم إلى دورة العمل الحالية قبل تعديل العروض';end if;
  if r.request_type='repair'then r.stops_vehicle:=false;r.needs_tow:=false;else r.maintenance_kind:=null;end if;
 end if;
 update private.fleet_requests set accountant_id=r.accountant_id,description=btrim(r.description),fault_notes=btrim(r.fault_notes),odometer=r.odometer,request_type=r.request_type,maintenance_kind=r.maintenance_kind,stops_vehicle=r.stops_vehicle,needs_tow=r.needs_tow,quotes=r.quotes,selected_quote=r.selected_quote,
 state=case when financial_changed and prior.state not in('draft','returned')then 'draft'else prior.state end,approved=case when financial_changed then 0 else prior.approved end,revision=revision+1,updated_at=now()where id=p_id returning * into r;
 if financial_changed and prior.state not in('draft','returned')then result:=private.fleet_command(r.id,r.revision,'submit','{}');select * into strict r from private.fleet_requests where id=p_id;end if;
 insert into private.fleet_events(request_id,actor_id,action,from_state,to_state,payload)values(r.id,auth.uid(),'request_corrected',prior.state,case when prior.state is distinct from r.state then r.state else null end,jsonb_build_object('reason',btrim(p_reason),'before',to_jsonb(prior),'after',to_jsonb(r),'approval_restarted',financial_changed and prior.state not in('draft','returned')));
 if r.accountant_id is distinct from prior.accountant_id and r.state in('awaiting_advance','reimbursement','settlement')then perform private.fleet_workflow_notify('request',r.id,r.revision,r.accountant_id,'stage','أعيد إسناد طلب الصيانة #'||r.number||' إليك للصرف أو التسوية',r.vehicle_id);end if;
 return private.fleet_detail(r.id);
end$$;
create function public.fleet_request_correct(p_id uuid,p_revision integer,p_data jsonb,p_reason text)returns jsonb language sql security invoker set search_path=pg_catalog,private as $$select private.fleet_request_correct(p_id,p_revision,p_data,p_reason)$$;
-- Private helpers/renamed implementations cannot be called by clients.
revoke all on function private.fleet_can_correct(),private.fleet_valid_accountant(uuid),private.fleet_visible_before_corrections(private.fleet_requests),private.fleet_visible(private.fleet_requests),private.fleet_request_listed_before_corrections(private.fleet_requests),private.fleet_request_listed(private.fleet_requests),private.fleet_handover_visible_before_corrections(private.fleet_handovers),private.fleet_handover_visible(private.fleet_handovers),private.fleet_handover_listed_before_corrections(private.fleet_handovers),private.fleet_handover_listed(private.fleet_handovers),private.fleet_snapshot_before_corrections(),private.fleet_snapshot(),private.fleet_request_save_before_corrections(uuid,integer,jsonb),private.fleet_request_save(uuid,integer,jsonb),private.fleet_request_correct(uuid,integer,jsonb,text) from public,anon,authenticated;
-- Existing public invoker wrappers call these named private RPC implementations.
grant execute on function private.fleet_snapshot(),private.fleet_request_save(uuid,integer,jsonb),private.fleet_request_correct(uuid,integer,jsonb,text) to authenticated;
revoke all on function public.fleet_request_correct(uuid,integer,jsonb,text) from public,anon;
grant execute on function public.fleet_request_correct(uuid,integer,jsonb,text) to authenticated;
