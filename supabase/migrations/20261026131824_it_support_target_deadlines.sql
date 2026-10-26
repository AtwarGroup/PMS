-- Approved targets: P1 4 elapsed hours; P2 8 working hours; P3 2 working days; P4 5 working days.
-- Working-calendar defaults are explicit and configurable independently of ownership.
alter table private.it_support_settings add column work_start time not null default '08:00',add column work_end time not null default '17:00',add column work_days int[] not null default array[0,1,2,3,4],add check(work_start<work_end),add check(cardinality(work_days)>0 and work_days<@array[0,1,2,3,4,5,6]);
alter table private.it_support_tickets add column sla_started_at timestamptz,add column due_at timestamptz;
create function private.it_support_due(p_start timestamptz,p_priority int)returns timestamptz language plpgsql stable security invoker set search_path=pg_catalog,private as $$
declare cfg private.it_support_settings;local_start timestamp;target_day date;cursor_at timestamp;finish timestamp;minutes_left numeric;available numeric;iterations int:=0;begin
if p_start is null then return null;end if;
if p_priority=1 then return p_start+interval '4 hours';end if;
if p_priority not between 2 and 4 then raise exception 'Invalid priority';end if;
select * into strict cfg from private.it_support_settings;
minutes_left:=case p_priority when 2 then 480 when 3 then extract(epoch from(cfg.work_end-cfg.work_start))/60*2 when 4 then extract(epoch from(cfg.work_end-cfg.work_start))/60*5 end;
local_start:=p_start at time zone 'Asia/Riyadh';target_day:=local_start::date;cursor_at:=local_start;
loop
iterations:=iterations+1;if iterations>3660 then raise exception 'Working calendar cannot produce deadline';end if;
if extract(dow from target_day)::int=any(cfg.work_days)and to_char(target_day,'MM-DD')not in('02-22','09-23')and not exists(select 1 from private.recruitment_holidays where recruitment_holidays.day=target_day)then
cursor_at:=greatest(cursor_at,target_day+cfg.work_start);finish:=target_day+cfg.work_end;available:=greatest(0,extract(epoch from(finish-cursor_at))/60);
if available>=minutes_left then return(cursor_at+minutes_left*interval '1 minute')at time zone 'Asia/Riyadh';end if;
minutes_left:=minutes_left-available;
end if;
target_day:=target_day+1;cursor_at:=target_day+cfg.work_start;
end loop;end$$;
revoke all on function private.it_support_due(timestamptz,int)from public,anon,authenticated;
create function private.it_support_deadline()returns trigger language plpgsql security invoker set search_path=pg_catalog,private as $$begin
if tg_op='INSERT'then new.sla_started_at:=case when new.state='approval'then null else new.created_at end;new.due_at:=private.it_support_due(new.sla_started_at,new.priority);
elsif old.sla_started_at is null and old.state='approval'and new.state='new'then new.sla_started_at:=now();new.due_at:=private.it_support_due(new.sla_started_at,new.priority);
end if;return new;end$$;
revoke all on function private.it_support_deadline()from public,anon,authenticated;
create trigger it_support_deadline before insert or update of state on private.it_support_tickets for each row execute function private.it_support_deadline();
-- Backfill existing eligible requests; never start a clock for unapproved purchases.
update private.it_support_tickets t set sla_started_at=case when service_key='purchase'then(select min(created_at)from private.it_support_events e where e.ticket_id=t.id and e.action='approve')else created_at end;
update private.it_support_tickets set due_at=private.it_support_due(sla_started_at,priority)where sla_started_at is not null;
create index it_support_tickets_due_idx on private.it_support_tickets(due_at)where state in('new','working','waiting_employee','waiting_vendor');
create function private.it_support_calendar(p_start time,p_end time,p_days int[])returns void language plpgsql security definer set search_path=pg_catalog,private,public as $$begin
if auth.uid()is null or not private.it_support_permission('it_support.supervise')or not exists(select 1 from public.profiles where id=auth.uid()and role='admin')then raise exception 'تقويم الدعم من إدارة المستخدمين والصلاحيات فقط'using errcode='42501';end if;
if p_start is null or p_end is null or p_start>=p_end or p_days is null or cardinality(p_days)=0 or not p_days<@array[0,1,2,3,4,5,6]or array_position(p_days,null)is not null then raise exception 'أيام وساعات العمل غير صالحة';end if;
update private.it_support_settings set work_start=p_start,work_end=p_end,work_days=array(select distinct unnest(p_days)order by 1);
end$$;
create function public.it_support_calendar(p_start time,p_end time,p_days int[])returns void language sql security invoker set search_path=pg_catalog,private as $$select private.it_support_calendar(p_start,p_end,p_days)$$;
revoke all on function private.it_support_calendar(time,time,int[]),public.it_support_calendar(time,time,int[])from public,anon,authenticated;
grant execute on function private.it_support_calendar(time,time,int[]),public.it_support_calendar(time,time,int[])to authenticated;
