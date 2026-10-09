create table public.kpi_measurements (
 id uuid primary key,
 employee_id uuid not null references public.profiles(id),
 job_description_id uuid not null references public.job_descriptions(id),
 job_revision integer not null check(job_revision>0),
 indicator_index integer not null check(indicator_index>=0),
 indicator_snapshot jsonb not null check(jsonb_typeof(indicator_snapshot)='object'),
 period_start date not null,period_end date not null check(period_end>=period_start),
 result_text text not null check(char_length(btrim(result_text)) between 1 and 1000),
 source_text text not null default '' check(char_length(source_text)<=2000),
 evidence_url text not null default '' check(char_length(evidence_url)<=2000 and (evidence_url='' or evidence_url~*'^https?://[^[:space:]]+$')),
 evidence_note text not null default '' check(char_length(evidence_note)<=2000),
 notes text not null default '' check(char_length(notes)<=2000),
 task_id uuid references public.tasks(id),project_id uuid references public.projects(id),
 revision integer not null default 1 check(revision>0),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 updated_by uuid not null references public.profiles(id),
 unique(employee_id,job_description_id,job_revision,indicator_index,period_start,period_end)
);
create index kpi_measurements_employee_period_idx on public.kpi_measurements(employee_id,period_start desc,id);
create index kpi_measurements_job_idx on public.kpi_measurements(job_description_id);
create index kpi_measurements_actor_idx on public.kpi_measurements(updated_by);
create index kpi_measurements_task_idx on public.kpi_measurements(task_id) where task_id is not null;
create index kpi_measurements_project_idx on public.kpi_measurements(project_id) where project_id is not null;

create function private.can_access_kpi_employee(p_employee uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select private.current_user_is_active() and exists(select 1 from public.profiles p where p.id=p_employee and (p.id=auth.uid() or private.is_admin() or private.manages_user(p.id)));
$$;
revoke all on function private.can_access_kpi_employee(uuid) from public,anon,authenticated;
grant execute on function private.can_access_kpi_employee(uuid) to authenticated;
alter table public.kpi_measurements enable row level security;
revoke all on public.kpi_measurements from public,anon,authenticated;
grant select on public.kpi_measurements to authenticated;
grant all on public.kpi_measurements to service_role;
create policy kpi_measurement_read on public.kpi_measurements for select to authenticated using(private.can_access_kpi_employee(employee_id));

create function private.kpi_measurement_context(p_employee uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare employee public.profiles%rowtype;j public.job_descriptions%rowtype;j_id uuid;matches integer;
begin
 if auth.uid() is null or not private.can_access_kpi_employee(p_employee) then raise exception 'Employee is unavailable' using errcode='42501';end if;
 select * into employee from public.profiles where id=p_employee;
 select job_description_id into j_id from public.employee_job_assignments where profile_id=p_employee;
 j_id:=coalesce(j_id,employee.job_description_id);
 if j_id is null and nullif(employee.job_title,'') is not null then
  select count(*) into matches from public.job_descriptions where title=employee.job_title and published_snapshot is not null;
  if matches=1 then select id into j_id from public.job_descriptions where title=employee.job_title and published_snapshot is not null;end if;
 end if;
 if j_id is not null then select * into j from public.job_descriptions where id=j_id;end if;
 return jsonb_build_object('employee',jsonb_build_object('id',employee.id,'full_name',employee.full_name),'job',case when j.published_snapshot is not null then jsonb_build_object('id',j.id,'title',coalesce(j.published_snapshot->>'title',j.title),'revision',coalesce((j.published_snapshot->>'revision')::integer,j.revision),'indicators',coalesce(j.published_snapshot->'content'->'kpis','[]'::jsonb)) else null end);
end $$;
revoke all on function private.kpi_measurement_context(uuid) from public,anon,authenticated;
grant execute on function private.kpi_measurement_context(uuid) to authenticated;
create function public.kpi_measurement_context(p_employee uuid) returns jsonb language sql security invoker set search_path='' as $$ select private.kpi_measurement_context(p_employee);$$;
revoke all on function public.kpi_measurement_context(uuid) from public,anon,authenticated;
grant execute on function public.kpi_measurement_context(uuid) to authenticated;

create function private.save_kpi_measurement(p_id uuid,p_employee uuid,p_job_id uuid,p_job_revision integer,p_indicator_index integer,p_expected_revision integer,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare old_row public.kpi_measurements%rowtype;v public.kpi_measurements%rowtype;context jsonb;indicator jsonb;actor uuid:=auth.uid();actor_name text;start_day date;end_day date;linked_task uuid;linked_project uuid;
begin
 if actor is null or not private.can_access_kpi_employee(p_employee) then raise exception 'Measurement cannot be edited' using errcode='42501';end if;
 -- Serialize saves for this employee, including simultaneous creates for one period.
 perform id from public.profiles where id=p_employee for update;
 select * into old_row from public.kpi_measurements where id=p_id for update;
 if old_row.id is not null then
  if old_row.employee_id<>p_employee or old_row.job_description_id<>p_job_id or old_row.job_revision<>p_job_revision or old_row.indicator_index<>p_indicator_index then raise exception 'Measurement identity cannot change' using errcode='42501';end if;
  indicator:=old_row.indicator_snapshot;
 else
  context:=private.kpi_measurement_context(p_employee);
  if context->'job' is null or context->'job'='null'::jsonb or (context->'job'->>'id')::uuid is distinct from p_job_id or (context->'job'->>'revision')::integer is distinct from p_job_revision then raise exception 'ATWAR_CONFLICT: published job changed' using errcode='40001';end if;
  if p_indicator_index is null or p_indicator_index<0 or p_indicator_index>=jsonb_array_length(context->'job'->'indicators') then raise exception 'Invalid published indicator' using errcode='22023';end if;
  indicator:=context->'job'->'indicators'->p_indicator_index;
 end if;
 if p_expected_revision is distinct from coalesce(old_row.revision,0) then raise exception 'ATWAR_CONFLICT: measurement changed' using errcode='40001';end if;
 if p_id is null or p_data is null or jsonb_typeof(p_data)<>'object' then raise exception 'Invalid measurement data' using errcode='22023';end if;
 if exists(select 1 from jsonb_object_keys(p_data) k where k not in ('period_start','period_end','result_text','source_text','evidence_url','evidence_note','notes','task_id','project_id')) then raise exception 'Unsupported measurement field' using errcode='22023';end if;
 start_day:=(p_data->>'period_start')::date;end_day:=(p_data->>'period_end')::date;
 if start_day is null or end_day is null or end_day<start_day then raise exception 'Invalid measurement period' using errcode='22023';end if;
 linked_task:=nullif(p_data->>'task_id','')::uuid;linked_project:=nullif(p_data->>'project_id','')::uuid;
 if linked_task is not null and linked_task is distinct from old_row.task_id and not private.can_view_task(linked_task) then raise exception 'Linked task is unavailable' using errcode='42501';end if;
 if linked_project is not null and linked_project is distinct from old_row.project_id and not private.project_access(linked_project) then raise exception 'Linked project is unavailable' using errcode='42501';end if;
 if linked_task is not null and linked_project is not null and exists(select 1 from public.tasks t where t.id=linked_task and t.project_id is not null and t.project_id<>linked_project) then raise exception 'Linked task belongs to another project' using errcode='22023';end if;
 insert into public.kpi_measurements(id,employee_id,job_description_id,job_revision,indicator_index,indicator_snapshot,period_start,period_end,result_text,source_text,evidence_url,evidence_note,notes,task_id,project_id,updated_by)
 values(p_id,p_employee,p_job_id,p_job_revision,p_indicator_index,indicator,start_day,end_day,btrim(p_data->>'result_text'),btrim(coalesce(p_data->>'source_text','')),btrim(coalesce(p_data->>'evidence_url','')),btrim(coalesce(p_data->>'evidence_note','')),btrim(coalesce(p_data->>'notes','')),linked_task,linked_project,actor)
 on conflict(id) do update set period_start=excluded.period_start,period_end=excluded.period_end,result_text=excluded.result_text,source_text=excluded.source_text,evidence_url=excluded.evidence_url,evidence_note=excluded.evidence_note,notes=excluded.notes,task_id=excluded.task_id,project_id=excluded.project_id,updated_by=actor,updated_at=now(),revision=public.kpi_measurements.revision+1 returning * into v;
 select coalesce(full_name,'') into actor_name from public.profiles where id=actor;
 insert into public.admin_audit_log(actor_id,actor_name_snapshot,action,target_type,target_id,detail)
 values(actor,actor_name,'KPI_MEASUREMENT','kpi_measurement',v.id::text,jsonb_build_object('employee_id',p_employee,'previous',case when old_row.id is null then null else to_jsonb(old_row) end,'current',to_jsonb(v)));
 return to_jsonb(v);
exception when unique_violation then raise exception 'ATWAR_CONFLICT: measurement for this indicator and period already exists' using errcode='40001';
end $$;
revoke all on function private.save_kpi_measurement(uuid,uuid,uuid,integer,integer,integer,jsonb) from public,anon,authenticated;
grant execute on function private.save_kpi_measurement(uuid,uuid,uuid,integer,integer,integer,jsonb) to authenticated;
create function public.save_kpi_measurement(p_id uuid,p_employee uuid,p_job_id uuid,p_job_revision integer,p_indicator_index integer,p_expected_revision integer,p_data jsonb) returns jsonb
language sql security invoker set search_path='' as $$ select private.save_kpi_measurement(p_id,p_employee,p_job_id,p_job_revision,p_indicator_index,p_expected_revision,p_data);$$;
revoke all on function public.save_kpi_measurement(uuid,uuid,uuid,integer,integer,integer,jsonb) from public,anon,authenticated;
grant execute on function public.save_kpi_measurement(uuid,uuid,uuid,integer,integer,integer,jsonb) to authenticated;
