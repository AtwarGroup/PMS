-- Existing templates keep their current schedule until explicitly edited.
alter table public.recurring_task_templates
 add column recurrence_rule jsonb,
 add column schedule_start_at timestamptz,
 add column created_count integer not null default 0 check (created_count>=0),
 add column waiting_for_completion boolean not null default false;

create or replace function private.next_recurring_occurrence(p_rule jsonb,p_kind text,p_interval integer,p_start timestamptz,p_after timestamptz)
returns timestamptz language plpgsql immutable security invoker set search_path='' as $$
declare
 a timestamp:=p_start at time zone 'Asia/Riyadh'; b timestamp:=p_after at time zone 'Asia/Riyadh';
 d date; base date:=a::date; candidate timestamp; result timestamptz;
 month_index integer; anchor_month integer; current_month integer; step integer;
 yr integer; mn integer; last_day integer; day_number integer; dow integer; diff integer; i integer;
begin
 if p_interval is null or p_interval<1 or p_interval>365 or p_kind not in ('daily','weekly','monthly','yearly') then raise exception 'Invalid recurrence interval'; end if;
 if p_kind in ('monthly','yearly') then
  anchor_month:=extract(year from a)::integer*12+extract(month from a)::integer-1;
  current_month:=extract(year from b)::integer*12+extract(month from b)::integer-1;
  step:=p_interval*case when p_kind='yearly' then 12 else 1 end;
  month_index:=case when p_kind='yearly' then extract(year from a)::integer*12+(p_rule->>'month')::integer-1 else anchor_month end;
  month_index:=month_index+greatest(0,floor((current_month-month_index)::numeric/step)::integer)*step;
  for i in 0..3 loop
   yr:=month_index/12; mn:=month_index%12+1;
   last_day:=extract(day from (make_date(yr,mn,1)+interval '1 month -1 day'))::integer;
   day_number:=least(coalesce((p_rule->>'day')::integer,extract(day from a)::integer),last_day);
   if p_rule->>'pattern'='ordinal' then
    dow:=(p_rule->>'weekday')::integer;
    if (p_rule->>'ordinal')::integer=-1 then day_number:=last_day-(extract(dow from make_date(yr,mn,last_day))::integer-dow+7)%7;
    else day_number:=1+(dow-extract(dow from make_date(yr,mn,1))::integer+7)%7+7*((p_rule->>'ordinal')::integer-1); end if;
   end if;
   candidate:=make_date(yr,mn,day_number)+a::time;
   exit when candidate>=a and candidate>b;
   candidate:=null;month_index:=month_index+step;
  end loop;
 else
  d:=greatest(base,b::date);
  for i in 0..p_interval*7+7 loop
   dow:=extract(dow from d)::integer;diff:=d-base;
   if (p_kind='weekly' and ((d-(base-extract(dow from base)::integer))/7)%p_interval=0 and (p_rule->'days') @> to_jsonb(array[dow]))
    or (p_kind='daily' and ((p_rule->>'pattern'='workdays' and (p_rule->'days') @> to_jsonb(array[dow])) or (p_rule->>'pattern'='day' and diff%p_interval=0))) then
    if d+a::time>b then candidate:=d+a::time;exit;end if;
   end if;
   d:=d+1;
  end loop;
 end if;
 if candidate is null then return null;end if;
 if p_rule->>'endMode'='date' and candidate::date>(p_rule->>'endDate')::date then return null;end if;
 result:=candidate at time zone 'Asia/Riyadh';return result;
end $$;
revoke all on function private.next_recurring_occurrence(jsonb,text,integer,timestamptz,timestamptz) from public,anon;
grant execute on function private.next_recurring_occurrence(jsonb,text,integer,timestamptz,timestamptz) to authenticated;

create or replace function private.validate_recurring_schedule()
returns trigger language plpgsql security invoker set search_path='' as $$
declare j jsonb:=new.recurrence_rule;v_next timestamptz;v_status text;v_completed timestamptz;
begin
 if current_user in ('authenticated','anon') then
  if tg_op='INSERT' and (new.created_count<>0 or new.waiting_for_completion or new.last_run_at is not null or new.last_created_task_id is not null)
   or tg_op='UPDATE' and (new.created_count is distinct from old.created_count or new.waiting_for_completion is distinct from old.waiting_for_completion or new.last_run_at is distinct from old.last_run_at or new.last_created_task_id is distinct from old.last_created_task_id)
  then raise exception 'Scheduler state cannot be edited';end if;
 end if;
 if j is null then return new;end if;
 if jsonb_typeof(j)<>'object' or coalesce(j->>'mode','') not in ('calendar','completion') or coalesce(j->>'endMode','') not in ('never','date','count') or new.schedule_start_at is null then raise exception 'Invalid recurrence settings';end if;
 if new.interval_count<1 or new.interval_count>365 or new.due_offset_days<0 or new.due_offset_days>365 then raise exception 'Invalid recurrence interval or deadline';end if;
 if j->>'endMode'='date' and ((j->>'endDate') is null or (j->>'endDate')::date<(new.schedule_start_at at time zone 'Asia/Riyadh')::date) then raise exception 'End date cannot precede start';end if;
 if j->>'endMode'='count' and (coalesce((j->>'endCount')::integer,0)<1 or (j->>'endCount')::integer>10000) then raise exception 'Invalid recurrence count';end if;
 if j->>'mode'='calendar' then
  if new.recurrence='daily' and coalesce(j->>'pattern','') not in ('day','workdays') then raise exception 'Invalid daily pattern';end if;
  if new.recurrence='weekly' or new.recurrence='daily' and j->>'pattern'='workdays' then
   if jsonb_typeof(j->'days') is distinct from 'array' or jsonb_array_length(j->'days')=0 then raise exception 'Select at least one weekday';end if;
   if exists(select 1 from jsonb_array_elements_text(j->'days') x where x::integer<0 or x::integer>6) then raise exception 'Invalid weekdays';end if;
  end if;
  if new.recurrence in ('monthly','yearly') then
   if coalesce(j->>'pattern','') not in ('day','ordinal') then raise exception 'Invalid monthly pattern';end if;
   if j->>'pattern'='day' and coalesce((j->>'day')::integer,0) not between 1 and 31 then raise exception 'Invalid day of month';end if;
   if j->>'pattern'='ordinal' and (coalesce((j->>'ordinal')::integer,0) not in (1,2,3,4,-1) or coalesce((j->>'weekday')::integer,-1) not between 0 and 6) then raise exception 'Invalid ordinal weekday';end if;
   if new.recurrence='yearly' and coalesce((j->>'month')::integer,0) not between 1 and 12 then raise exception 'Invalid month';end if;
  end if;
 end if;
 -- A scheduler update changes counters/next_run but never the rule/anchor.
 if tg_op='INSERT' or new.recurrence_rule is distinct from old.recurrence_rule or new.schedule_start_at is distinct from old.schedule_start_at or new.interval_count is distinct from old.interval_count or new.recurrence is distinct from old.recurrence then
  if j->>'endMode'='count' and (j->>'endCount')::integer<=new.created_count then raise exception 'Count must exceed tasks already created';end if;
  new.waiting_for_completion:=false;
  if j->>'mode'='calendar' then
   v_next:=private.next_recurring_occurrence(j,new.recurrence,new.interval_count,new.schedule_start_at,greatest(new.schedule_start_at-interval '1 second',now()-interval '1 second'));
   if v_next is null then raise exception 'No occurrences in this range';end if;
   new.next_run_at:=v_next;
  else
   new.next_run_at:=new.schedule_start_at;
   if new.last_created_task_id is not null then
    select status,completed_at into v_status,v_completed from public.tasks where id=new.last_created_task_id;
    if v_status='مكتملة' then
     new.next_run_at:=coalesce(v_completed,now())+case new.recurrence when 'daily' then make_interval(days=>new.interval_count) when 'weekly' then make_interval(days=>7*new.interval_count) when 'monthly' then make_interval(months=>new.interval_count) else make_interval(years=>new.interval_count) end;
    else new.waiting_for_completion:=true;end if;
   end if;
  end if;
 elsif current_user in ('authenticated','anon') and new.next_run_at is distinct from old.next_run_at then raise exception 'Edit the schedule start and recurrence settings instead';
 end if;
 return new;
end $$;
revoke all on function private.validate_recurring_schedule() from public,anon,authenticated;
create trigger validate_recurring_schedule before insert or update on public.recurring_task_templates for each row execute function private.validate_recurring_schedule();

create or replace function private.schedule_recurring_after_completion()
returns trigger language plpgsql security definer set search_path='' as $$
declare r public.recurring_task_templates%rowtype;v_next timestamptz;
begin
 if new.status is not distinct from old.status then return new;end if;
 for r in select * from public.recurring_task_templates where last_created_task_id=new.id and recurrence_rule->>'mode'='completion' for update loop
  if new.status='مكتملة' and new.deleted_at is null and r.waiting_for_completion then
   v_next:=coalesce(new.completed_at,now())+case r.recurrence when 'daily' then make_interval(days=>r.interval_count) when 'weekly' then make_interval(days=>7*r.interval_count) when 'monthly' then make_interval(months=>r.interval_count) else make_interval(years=>r.interval_count) end;
   update public.recurring_task_templates set next_run_at=v_next,waiting_for_completion=false,active=case when r.recurrence_rule->>'endMode'='date' and (v_next at time zone 'Asia/Riyadh')::date>(r.recurrence_rule->>'endDate')::date then false else active end,updated_at=now() where id=r.id;
  elsif old.status='مكتملة' and new.status<>'مكتملة' then
   update public.recurring_task_templates set waiting_for_completion=true,updated_at=now() where id=r.id;
  end if;
 end loop;return new;
end $$;
revoke all on function private.schedule_recurring_after_completion() from public,anon,authenticated;
create trigger schedule_recurring_after_completion after update of status on public.tasks for each row execute function private.schedule_recurring_after_completion();

create or replace function private.materialize_recurring_tasks()
returns integer language plpgsql security definer set search_path='public','private','pg_temp' as $$
declare r public.recurring_task_templates%rowtype;v_owner_name text;v_assignee_name text;v_id uuid;v_count integer:=0;v_next timestamptz;v_end boolean;v_today date:=(now() at time zone 'Asia/Riyadh')::date;
begin
 for r in select * from public.recurring_task_templates where active=true and not waiting_for_completion and next_run_at<=now() order by next_run_at for update skip locked loop
  if r.recurrence_rule is not null and ((r.recurrence_rule->>'endMode'='count' and r.created_count>=(r.recurrence_rule->>'endCount')::integer) or (r.recurrence_rule->>'endMode'='date' and v_today>(r.recurrence_rule->>'endDate')::date)) then
   update public.recurring_task_templates set active=false,updated_at=now() where id=r.id;continue;
  end if;
  select full_name into v_owner_name from public.profiles where id=r.owner_id and active=true and status='active';
  select full_name into v_assignee_name from public.profiles where id=r.assignee_id and active=true and status='active';
  if v_owner_name is null or v_assignee_name is null or not private.can_assign_task_target_for(r.owner_id,r.assignee_id) then
   update public.recurring_task_templates set active=false,updated_at=now() where id=r.id;continue;
  end if;
  insert into public.tasks(title,description,task_type,status,priority,progress,creator_id,assignee_id,creator_name_snapshot,assignee_name_snapshot,start_date,due_date,notes)
   values(r.title,coalesce(r.description,''),'recurring','قيد الانتظار',r.priority,0,r.owner_id,r.assignee_id,v_owner_name,v_assignee_name,v_today,v_today+greatest(r.due_offset_days,0),'') returning id into v_id;
  v_end:=false;
  if r.recurrence_rule is null then
   v_next:=r.next_run_at;
   loop
    v_next:=v_next+case r.recurrence when 'daily' then make_interval(days=>r.interval_count) when 'weekly' then make_interval(days=>7*r.interval_count) when 'monthly' then make_interval(months=>r.interval_count) when 'yearly' then make_interval(years=>r.interval_count) else interval '1 day' end;
    exit when v_next>now();
   end loop;
  elsif r.recurrence_rule->>'mode'='completion' then v_next:=r.next_run_at;
  else
   v_next:=private.next_recurring_occurrence(r.recurrence_rule,r.recurrence,r.interval_count,r.schedule_start_at,now());v_end:=v_next is null;
  end if;
  if r.recurrence_rule->>'endMode'='count' and r.created_count+1>=(r.recurrence_rule->>'endCount')::integer then v_end:=true;end if;
  update public.recurring_task_templates set last_run_at=now(),last_created_task_id=v_id,next_run_at=coalesce(v_next,r.next_run_at),created_count=created_count+1,waiting_for_completion=coalesce(r.recurrence_rule->>'mode'='completion',false) and not v_end,active=not v_end,updated_at=now() where id=r.id;
  v_count:=v_count+1;
 end loop;return v_count;
end $$;
-- Scheduler is private, invoked only by cron or the existing authenticated wrapper.
revoke all on function private.materialize_recurring_tasks() from public,anon,authenticated;

create index recurring_completion_task_idx on public.recurring_task_templates(last_created_task_id) where recurrence_rule->>'mode'='completion';
-- Reuse the existing job and increase precision without introducing duplicate jobs.
do $$declare v_job bigint;begin
 select jobid into v_job from cron.job where jobname='atwar_recurring_tasks_hourly';
 if v_job is not null then perform cron.alter_job(v_job,schedule:='*/5 * * * *');end if;
end $$;
