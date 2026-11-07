create table private.fleet_unassigned (
 id uuid primary key default gen_random_uuid(),
 vehicle_id uuid not null references private.fleet_vehicles(id),
 started_at timestamptz,
 enrolled_at timestamptz not null default now(),
 ended_at timestamptz,
 ended_reason text,
 location text,
 contact text,
 reason text check (reason in ('reserve','maintenance','reassign','sale_pending','for_sale')),
 listing text,
 next_action text,
 action_due date,
 check_due date not null default ((now() at time zone 'Asia/Riyadh')::date+7),
 verified_at timestamptz,
 issue text check (issue in ('loss','damage','unsafe')),
 issue_note text,
 revision integer not null default 1
);
create unique index fleet_unassigned_open_idx on private.fleet_unassigned(vehicle_id) where ended_at is null;
create table private.fleet_unassigned_checks (
 id uuid primary key default gen_random_uuid(),
 followup_id uuid not null references private.fleet_unassigned(id),
 actor_id uuid not null references public.profiles(id),
 checked_at timestamptz not null default now(),
 location text not null,
 note text not null,
 photo bytea not null check(octet_length(photo) between 4 and 1048576)
);
create index fleet_unassigned_checks_latest_idx on private.fleet_unassigned_checks(followup_id,checked_at desc);
create table private.fleet_unassigned_deliveries (
 followup_id uuid not null references private.fleet_unassigned(id),
 signal text not null,
 occurrence text not null,
 recipient uuid not null references public.profiles(id),
 primary key(followup_id,signal,occurrence,recipient)
);
alter table private.fleet_unassigned enable row level security;
alter table private.fleet_unassigned_checks enable row level security;
alter table private.fleet_unassigned_deliveries enable row level security;
revoke all on private.fleet_unassigned,private.fleet_unassigned_checks,private.fleet_unassigned_deliveries from public,anon,authenticated;
-- Legacy unassigned dates are unknown; enrollment is not a historic release date.
insert into private.fleet_unassigned(vehicle_id) select id from private.fleet_vehicles where driver_id is null;

create function private.fleet_unassigned_track() returns trigger language plpgsql security definer set search_path=pg_catalog,private as $$
begin
 if new.driver_id is null and (tg_op='INSERT' or old.driver_id is not null) then
  insert into private.fleet_unassigned(vehicle_id,started_at) values(new.id,now());
 elsif tg_op='UPDATE' and new.driver_id is not null and old.driver_id is null then
  update private.fleet_unassigned set ended_at=now(),ended_reason='assigned',revision=revision+1 where vehicle_id=new.id and ended_at is null;
 end if;
 return new;
end$$;
revoke all on function private.fleet_unassigned_track() from public,anon,authenticated;
create trigger fleet_unassigned_track after insert or update of driver_id on private.fleet_vehicles
for each row execute function private.fleet_unassigned_track();

create function private.fleet_unassigned_notify(p_id uuid,p_signal text,p_occurrence text,p_recipient uuid,p_title text)
returns void language plpgsql security definer set search_path=pg_catalog,private,public as $$
begin
 if not exists(select 1 from public.profiles where id=p_recipient and active and status='active' and (role='admin' or 'fleet'=any(allowed_modules))) then return; end if;
 insert into private.fleet_unassigned_deliveries values(p_id,p_signal,p_occurrence,p_recipient) on conflict do nothing;
 if found then
  insert into public.notifications(recipient_id,type,title,message,fleet_vehicle_id)
  select p_recipient,'FLEET_UNASSIGNED',p_title,'راجع قائمة السيارات غير المسندة في سجل السيارات.',vehicle_id from private.fleet_unassigned where id=p_id;
 end if;
end$$;
revoke all on function private.fleet_unassigned_notify(uuid,text,text,uuid,text) from public,anon,authenticated;

create function private.fleet_unassigned_escalation_date(p_due date) returns date
language plpgsql immutable set search_path=pg_catalog as $$
declare d date:=p_due; n integer:=0;
begin
 while n<2 loop
  d:=d+1;
  if extract(dow from d)<>5 then n:=n+1; end if;
 end loop;
 return d;
end$$;
revoke all on function private.fleet_unassigned_escalation_date(date) from public,anon,authenticated;

create function private.process_fleet_unassigned_alerts() returns void
language plpgsql security definer set search_path=pg_catalog,private,public as $$
declare owner_id uuid; supervisor uuid; row record; today date:=(now() at time zone 'Asia/Riyadh')::date;
begin
 begin owner_id:=private.fleet_owner(); exception when raise_exception then return; end;
 select m.profile_id into supervisor from private.hr_employees e join private.hr_employees m on m.id=e.manager_id where e.profile_id=owner_id;
 for row in
  select f.id,v.plate,s.signal,s.due
  from private.fleet_unassigned f join private.fleet_vehicles v on v.id=f.vehicle_id
  cross join lateral (values ('check',f.check_due),('action',f.action_due)) s(signal,due)
  where f.ended_at is null and s.due<today
 loop
  perform private.fleet_unassigned_notify(row.id,row.signal,row.due::text,owner_id,
   case row.signal when 'check' then 'تأخر التحقق من السيارة ' else 'تأخر إجراء السيارة ' end||row.plate);
  if today>private.fleet_unassigned_escalation_date(row.due) then
   perform private.fleet_unassigned_notify(row.id,row.signal||'_escalation',row.due::text,supervisor,
    case row.signal when 'check' then 'تصعيد: لم يتم التحقق من السيارة ' else 'تصعيد: إجراء متأخر للسيارة ' end||row.plate);
  end if;
 end loop;
end$$;
revoke all on function private.process_fleet_unassigned_alerts() from public,anon,authenticated;
do $$begin
 if to_regnamespace('cron') is not null then
  execute $job$select cron.schedule('atwar_fleet_unassigned_alerts','25 * * * *','select private.process_fleet_unassigned_alerts();')$job$;
 end if;
end$$;

create function private.fleet_unassigned_followup(p_operation text,p_vehicle uuid default null,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path=pg_catalog,private,public as $$
declare f private.fleet_unassigned%rowtype; v private.fleet_vehicles%rowtype;
 today date:=(now() at time zone 'Asia/Riyadh')::date; owner_id uuid; supervisor uuid;
 writable boolean; loc text; contact_info text; why text; listing_info text; action_text text; due date;
 issue_type text; issue_details text; note_text text; evidence bytea; release_note text;
begin
 perform private.require_module('fleet');
 writable:=private.fleet_can_correct();
 if not writable and private.fleet_supervised_owner() is null then
  raise exception 'متابعة السيارات غير المسندة غير متاحة لهذا الحساب' using errcode='42501';
 end if;
 if p_operation='list' then
  return jsonb_build_object('writable',writable,'today',today,'rows',coalesce((
   select jsonb_agg(to_jsonb(x) order by (x.issue is not null or x.verified_at is null or x.check_due<today or x.action_due<today) desc nulls last,x.started_at nulls first,x.plate)
   from (select f0.*,v0.plate,v0.vehicle_type,v0.model from private.fleet_unassigned f0 join private.fleet_vehicles v0 on v0.id=f0.vehicle_id where f0.ended_at is null) x
  ),'[]'::jsonb));
 end if;
 if p_operation='photo' then
  return (select jsonb_build_object('base64',encode(c.photo,'base64'),'note',c.note,'checked_at',c.checked_at)
   from private.fleet_unassigned_checks c join private.fleet_unassigned f0 on f0.id=c.followup_id
   where f0.vehicle_id=p_vehicle and f0.ended_at is null order by c.checked_at desc limit 1);
 end if;
 if not writable then raise exception 'التعديل متاح لمسؤول الأسطول أو مسؤول النظام' using errcode='42501'; end if;
 if p_operation not in('save','release','sold') or p_operation is null then raise exception 'إجراء غير معروف';end if;
 select * into strict v from private.fleet_vehicles where id=p_vehicle for update;
 select * into f from private.fleet_unassigned where vehicle_id=p_vehicle and ended_at is null for update;
 if p_operation='release' then
  if v.driver_id is null or (p_data->>'revision')::integer is distinct from v.revision then raise exception 'حدّث بيانات السيارة قبل فك الإسناد'; end if;
  release_note:=btrim(coalesce(p_data->>'release_note',''));
  if length(release_note) not between 5 and 500 then raise exception 'وثّق استلام السيارة من السائق ومرجع التسليم';end if;
  if exists(select 1 from private.fleet_requests where vehicle_id=v.id and state not in('closed','rejected')) or
     exists(select 1 from private.fleet_handovers where vehicle_id=v.id and state not in('draft','accepted','cancelled')) then
   raise exception 'أكمل طلبات الصيانة ومحاضر التسليم المفتوحة أولًا';
  end if;
  update private.fleet_vehicles set driver_id=null,revision=revision+1,updated_at=now() where id=v.id;
  select * into strict f from private.fleet_unassigned where vehicle_id=v.id and ended_at is null;
  insert into private.fleet_events(vehicle_id,actor_id,action,payload) values(v.id,auth.uid(),'driver_unassigned',jsonb_build_object('previous_driver_id',v.driver_id,'reason',release_note));
 elsif v.driver_id is not null or f.id is null or (p_data->>'revision')::integer is distinct from f.revision then
  raise exception 'تغيرت متابعة السيارة؛ حدّث السجل ثم أعد المحاولة' using errcode='40001';
 end if;
 loc:=nullif(btrim(p_data->>'location'),''); contact_info:=nullif(btrim(p_data->>'contact'),'');
 why:=p_data->>'reason'; listing_info:=nullif(btrim(p_data->>'listing'),'');
 action_text:=nullif(btrim(p_data->>'next_action'),''); due:=(p_data->>'action_due')::date;
 issue_type:=nullif(p_data->>'issue',''); issue_details:=nullif(btrim(p_data->>'issue_note'),'');
 note_text:=btrim(coalesce(p_data->>'note',''));
 if coalesce(length(loc),0)>300 or coalesce(length(contact_info),0)>200 or coalesce(length(listing_info),0)>500 or
    why is null or why not in('reserve','maintenance','reassign','sale_pending','for_sale') or
    (why='for_sale' and listing_info is null) or coalesce(length(action_text),0) not between 3 and 500 or due is null or
    (issue_type is not null and (issue_type not in('loss','damage','unsafe') or coalesce(length(issue_details),0) not between 5 and 500)) then
  raise exception 'استكمل سبب عدم الإسناد والإجراء وموعده، وبيانات العرض أو البلاغ عند انطباقها';
 end if;
 if p_data->>'photo' is not null then
  if length(p_data->>'photo')>1398104 then raise exception 'حجم الصورة أكبر من الحد المسموح';end if;
  evidence:=decode(p_data->>'photo','base64');
  if octet_length(evidence) not between 4 and 1048576 or substring(evidence from 1 for 3)<>decode('ffd8ff','hex') or
     loc is null or length(note_text) not between 5 and 500 then raise exception 'يلزم موقع مؤكد وصورة حديثة وملاحظة حالة واضحة';end if;
  insert into private.fleet_unassigned_checks(followup_id,actor_id,location,note,photo) values(f.id,auth.uid(),loc,note_text,evidence);
 end if;
 if f.issue is not null and issue_type is null and evidence is null then raise exception 'إغلاق البلاغ يتطلب توثيق المعالجة بصورة حديثة';end if;
 if p_operation='sold' then
  if f.reason is distinct from 'for_sale' or why is distinct from 'for_sale' or evidence is null then raise exception 'وثّق التسليم الفعلي للسيارة المعروضة للبيع بالصورة والملاحظة';end if;
  update private.fleet_vehicles set active=false,revision=revision+1,updated_at=now() where id=v.id;
 end if;
 update private.fleet_unassigned set location=loc,contact=contact_info,reason=why,listing=case when why='for_sale' then listing_info end,
  next_action=action_text,action_due=due,issue=issue_type,issue_note=case when issue_type is not null then issue_details end,
  verified_at=case when evidence is not null then now() when loc is distinct from f.location then null else f.verified_at end,
  check_due=case when evidence is not null then today+7 else f.check_due end,
  ended_at=case when p_operation='sold' then now() end,ended_reason=case when p_operation='sold' then 'sold' end,
  revision=revision+1 where id=f.id;
 insert into private.fleet_events(vehicle_id,actor_id,action,payload) values(v.id,auth.uid(),'unassigned_followup_saved',
  jsonb_build_object('followup_id',f.id,'old_action_due',f.action_due,'action_due',due,'reason',why,'verified',evidence is not null,'issue',issue_type));
 if p_operation='sold' then
  insert into private.fleet_events(vehicle_id,actor_id,action,payload) values(v.id,auth.uid(),'unassigned_sale_delivered',jsonb_build_object('reason',note_text));
 elsif issue_type is not null and (issue_type,issue_details) is distinct from (f.issue,f.issue_note) then
  begin owner_id:=private.fleet_owner();exception when raise_exception then owner_id:=null;end;
  select m.profile_id into supervisor from private.hr_employees e join private.hr_employees m on m.id=e.manager_id where e.profile_id=owner_id;
  perform private.fleet_unassigned_notify(f.id,'incident',f.revision::text,owner_id,'عاجل: بلاغ على السيارة '||v.plate);
  perform private.fleet_unassigned_notify(f.id,'incident',f.revision::text,supervisor,'عاجل: بلاغ على السيارة '||v.plate);
 end if;
 return jsonb_build_object('saved',true);
end$$;
create function public.fleet_unassigned_followup(p_operation text,p_vehicle uuid default null,p_data jsonb default '{}') returns jsonb
language sql security invoker set search_path=pg_catalog,private as $$
 select private.fleet_unassigned_followup(p_operation,p_vehicle,p_data);
$$;
revoke all on function public.fleet_unassigned_followup(text,uuid,jsonb),private.fleet_unassigned_followup(text,uuid,jsonb) from public,anon;
grant execute on function public.fleet_unassigned_followup(text,uuid,jsonb),private.fleet_unassigned_followup(text,uuid,jsonb) to authenticated;
notify pgrst,'reload schema';
