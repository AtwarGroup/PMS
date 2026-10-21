-- Fleet documents and configurable in-app reminders; no email dispatch.
create table private.fleet_alert_settings(kind text primary key check(kind in('authorization','registration','insurance','inspection')),days_before integer not null default 30 check(days_before between 0 and 3650),revision integer not null default 1,updated_by uuid references public.profiles(id),updated_at timestamptz not null default now());
insert into private.fleet_alert_settings(kind)values('authorization'),('registration'),('insurance'),('inspection');
create table private.fleet_documents(id uuid primary key default gen_random_uuid(),vehicle_id uuid not null references private.fleet_vehicles(id),kind text not null references private.fleet_alert_settings(kind),expires_on date not null,authorized_driver_id uuid references private.hr_employees(id),revision integer not null default 1,updated_by uuid not null references public.profiles(id),updated_at timestamptz not null default now(),unique(vehicle_id,kind));
create index fleet_document_expiry_idx on private.fleet_documents(expires_on,vehicle_id);
create table private.fleet_alert_deliveries(document_id uuid not null references private.fleet_documents(id),expires_on date not null,recipient_id uuid not null references public.profiles(id),phase text not null check(phase in('due','expired')),created_at timestamptz not null default now(),primary key(document_id,expires_on,recipient_id,phase));
alter table public.notifications add column fleet_vehicle_id uuid references private.fleet_vehicles(id);
create index notifications_fleet_vehicle_idx on public.notifications(fleet_vehicle_id)where fleet_vehicle_id is not null;
do $$declare t text;begin foreach t in array array['fleet_alert_settings','fleet_documents','fleet_alert_deliveries']loop execute format('alter table private.%I enable row level security',t);execute format('revoke all on private.%I from public,anon,authenticated',t);end loop;end$$;
create function private.fleet_document_visible(p_vehicle uuid)returns boolean language sql stable security definer set search_path=pg_catalog,public,private as $$
 select private.current_user_is_active()and exists(select 1 from private.fleet_vehicles v left join private.hr_employees e on e.id=v.driver_id left join private.hr_employees m on m.id=e.manager_id where v.id=p_vehicle and(private.fleet_has('fleet.vehicles.read')or private.fleet_has('fleet.vehicles.write')or private.fleet_has('fleet.approve')or e.profile_id=auth.uid()or m.profile_id=auth.uid()))
$$;
create function private.process_fleet_document_alerts()returns integer language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare owner_id uuid;d record;recipient uuid;phase_name text;n integer:=0;new_rows integer;today date:=timezone('Asia/Riyadh',now())::date;label text;
begin
 -- Serialize cron and date/settings edits, so retries and simultaneous scans cannot duplicate a notification.
 perform pg_advisory_xact_lock(hashtext('fleet_document_alerts'));
 begin owner_id:=private.fleet_owner();exception when raise_exception then return 0;end;
 for d in select doc.*,v.plate,e.profile_id driver_profile,m.profile_id manager_profile from private.fleet_documents doc join private.fleet_alert_settings s on s.kind=doc.kind join private.fleet_vehicles v on v.id=doc.vehicle_id and v.active left join private.hr_employees e on e.id=v.driver_id left join private.hr_employees m on m.id=e.manager_id where (doc.kind<>'authorization'or doc.authorized_driver_id=v.driver_id)and doc.expires_on<=today+s.days_before loop
  phase_name:=case when d.expires_on<today then 'expired'else 'due'end;
  label:=case d.kind when 'authorization'then 'تفويض السائق'when 'registration'then 'رخصة السير'when 'insurance'then 'التأمين'else 'الفحص الدوري'end;
  for recipient in select distinct p.id from public.profiles p where p.id=any(array[owner_id,d.driver_profile,d.manager_profile])and p.active and p.status='active'loop
   insert into private.fleet_alert_deliveries(document_id,expires_on,recipient_id,phase)values(d.id,d.expires_on,recipient,phase_name)on conflict do nothing;
   get diagnostics new_rows=row_count;
   if new_rows>0 then
    insert into public.notifications(recipient_id,type,title,message,fleet_vehicle_id)values(recipient,'FLEET_DOCUMENT',case when phase_name='expired'then 'وثيقة سيارة منتهية'else 'تنبيه انتهاء وثيقة سيارة'end,label||' — السيارة '||d.plate||' — تاريخ الانتهاء '||d.expires_on::text||case when phase_name='expired'then ' — انتهت الصلاحية'else ' — المتبقي '||(d.expires_on-today)::text||' يوم'end,d.vehicle_id);n:=n+1;
   end if;
  end loop;
 end loop;return n;
end$$;
create function private.fleet_documents_context()returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,private as $$
begin
 if not private.current_user_is_active()then raise exception 'Authentication required'using errcode='42501';end if;
 return jsonb_build_object('can_configure',private.is_admin(),'can_edit',private.fleet_has('fleet.vehicles.write'),
 'settings',(select jsonb_agg(to_jsonb(s)order by kind)from private.fleet_alert_settings s),
 'vehicles',(select coalesce(jsonb_agg(jsonb_build_object('id',v.id,'plate',v.plate,'driver_name',e.full_name,'active',v.active)order by plate),'[]')from private.fleet_vehicles v left join private.hr_employees e on e.id=v.driver_id where private.fleet_document_visible(v.id)),
 'documents',(select coalesce(jsonb_agg(to_jsonb(d)||jsonb_build_object('days_left',d.expires_on-timezone('Asia/Riyadh',now())::date,'days_before',s.days_before)order by d.expires_on),'[]')from private.fleet_documents d join private.fleet_alert_settings s on s.kind=d.kind where private.fleet_document_visible(d.vehicle_id)and(d.kind<>'authorization'or d.authorized_driver_id=(select driver_id from private.fleet_vehicles where id=d.vehicle_id))));
end$$;
create function private.fleet_document_save(p_vehicle uuid,p_kind text,p_expires date,p_revision integer,p_reason text)returns void language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare d private.fleet_documents%rowtype;b jsonb;
begin
 if not private.fleet_has('fleet.vehicles.write')then raise exception 'Vehicle management denied'using errcode='42501';end if;
 if p_kind is null or p_kind not in('authorization','registration','insurance','inspection')or p_expires is null or p_expires not between date '2000-01-01'and date '2200-12-31'or length(btrim(coalesce(p_reason,'')))<3 then raise exception 'بيانات الوثيقة وسبب التحديث مطلوبة';end if;
 perform 1 from private.fleet_vehicles where id=p_vehicle for update;if not found then raise exception 'Vehicle not found';end if;
 select * into d from private.fleet_documents where vehicle_id=p_vehicle and kind=p_kind for update;
 if(d.id is null and p_revision is not null)or(d.id is not null and d.revision is distinct from p_revision)then raise exception 'تم تحديث الوثيقة، حدّث الصفحة'using errcode='40001';end if;
 if p_kind='authorization'and(select driver_id from private.fleet_vehicles where id=p_vehicle)is null then raise exception 'اربط سائقًا بالسيارة قبل تسجيل التفويض';end if;
 b:=to_jsonb(d);
 insert into private.fleet_documents(vehicle_id,kind,expires_on,authorized_driver_id,updated_by)values(p_vehicle,p_kind,p_expires,case when p_kind='authorization'then(select driver_id from private.fleet_vehicles where id=p_vehicle)end,auth.uid())on conflict(vehicle_id,kind)do update set expires_on=excluded.expires_on,authorized_driver_id=excluded.authorized_driver_id,revision=private.fleet_documents.revision+1,updated_by=auth.uid(),updated_at=now();
 insert into private.fleet_events(vehicle_id,actor_id,action,payload)values(p_vehicle,auth.uid(),'document_saved',jsonb_build_object('before',b,'kind',p_kind,'expires_on',p_expires,'reason',p_reason));
 perform private.process_fleet_document_alerts();
end$$;
create function private.fleet_alert_setting_save(p_kind text,p_days integer,p_revision integer)returns void language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare s private.fleet_alert_settings%rowtype;
begin
 if not private.is_admin()then raise exception 'Administrator access required'using errcode='42501';end if;
 if p_days is null or p_days not between 0 and 3650 then raise exception 'حدد عدد أيام صحيحًا من 0 إلى 3650';end if;
 select * into strict s from private.fleet_alert_settings where kind=p_kind for update;
 if s.revision is distinct from p_revision then raise exception 'تم تحديث الإعداد، حدّث الصفحة'using errcode='40001';end if;
 update private.fleet_alert_settings set days_before=p_days,revision=revision+1,updated_by=auth.uid(),updated_at=now()where kind=p_kind;
 perform private.access_log('FLEET_ALERT_SETTING',p_kind,to_jsonb(s),jsonb_build_object('days_before',p_days));
 perform private.process_fleet_document_alerts();
end$$;
create function private.fleet_document_open(p_notification uuid)returns uuid language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare v uuid;
begin
 if not private.current_user_is_active()then raise exception 'Authentication required'using errcode='42501';end if;
 select fleet_vehicle_id into v from public.notifications where id=p_notification and recipient_id=auth.uid()and type='FLEET_DOCUMENT';
 if v is null or not private.fleet_document_visible(v)then raise exception 'الوثيقة غير متاحة لك حاليًا'using errcode='42501';end if;
 update public.notifications set read_at=coalesce(read_at,now())where id=p_notification and recipient_id=auth.uid();return v;
end$$;
create function public.fleet_documents_context()returns jsonb language sql security invoker set search_path=pg_catalog,private as $$select private.fleet_documents_context()$$;
create function public.fleet_document_save(p_vehicle uuid,p_kind text,p_expires date,p_revision integer,p_reason text)returns void language sql security invoker set search_path=pg_catalog,private as $$select private.fleet_document_save(p_vehicle,p_kind,p_expires,p_revision,p_reason)$$;
create function public.fleet_alert_setting_save(p_kind text,p_days integer,p_revision integer)returns void language sql security invoker set search_path=pg_catalog,private as $$select private.fleet_alert_setting_save(p_kind,p_days,p_revision)$$;
create function public.fleet_document_open(p_notification uuid)returns uuid language sql security invoker set search_path=pg_catalog,private as $$select private.fleet_document_open(p_notification)$$;
revoke all on function private.fleet_document_visible(uuid),private.process_fleet_document_alerts()from public,anon,authenticated;
do $$declare f record;begin for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in('private','public')and p.proname in('fleet_documents_context','fleet_document_save','fleet_alert_setting_save','fleet_document_open')loop execute format('revoke all on function %s from public,anon',f.sig);execute format('grant execute on function %s to authenticated',f.sig);end loop;end$$;
-- pg_cron uses UTC: 03:00 UTC = 06:00 Riyadh, regardless of whether anyone is logged in.
do $$begin if to_regnamespace('cron')is not null then execute $job$select cron.schedule('atwar_fleet_document_alerts','0 3 * * *','select private.process_fleet_document_alerts();')$job$;end if;end$$;
-- Import dates from the prepared source atomically with vehicles, including rollback-only previews.
alter function private.fleet_import(jsonb,text,boolean)rename to fleet_import_before_documents;
create function private.fleet_import(p_rows jsonb,p_source_hash text,p_dry_run boolean default true)returns jsonb language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare result jsonb;r jsonb;item record;v uuid;rev integer;
begin
 if not private.fleet_has('fleet.vehicles.write')then raise exception 'Vehicle management denied'using errcode='42501';end if;
 if p_dry_run is null then raise exception 'Invalid import';end if;
 begin
  result:=private.fleet_import_before_documents(p_rows,p_source_hash,false);
  for r in select value from jsonb_array_elements(p_rows)loop
   select id into strict v from private.fleet_vehicles where upper(regexp_replace(plate,'\s','','g'))=upper(regexp_replace(r->>'plate','\s','','g'));
   for item in select key,value from jsonb_each_text(coalesce(r->'documents','{}'))loop
    if item.key='authorization'and nullif(r->>'driver_id','')is null then continue;end if;
    select revision into rev from private.fleet_documents where vehicle_id=v and kind=item.key;
    perform private.fleet_document_save(v,item.key,item.value::date,rev,'استيراد تواريخ الوثائق من ملف السيارات المعتمد');
   end loop;
  end loop;
  result:=result||jsonb_build_object('dry_run',p_dry_run);
  if p_dry_run then raise exception using errcode='ZF002',message='documents preview rollback';end if;
 exception when sqlstate 'ZF002'then null;
 end;return result;
end$$;
revoke all on function private.fleet_import_before_documents(jsonb,text,boolean)from public,anon,authenticated;
revoke all on function private.fleet_import(jsonb,text,boolean)from public,anon;
grant execute on function private.fleet_import(jsonb,text,boolean)to authenticated;
