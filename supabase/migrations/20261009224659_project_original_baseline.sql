create table public.project_baselines (
 project_id uuid primary key references public.projects(id) on delete cascade,
 project_revision integer not null,
 project_snapshot jsonb not null check(jsonb_typeof(project_snapshot)='object'),
 task_snapshot jsonb not null check(jsonb_typeof(task_snapshot)='array'),
 captured_at timestamptz not null default now(),
 captured_by uuid not null references public.profiles(id),
 captured_by_name text not null
);
create index project_baselines_captured_by_idx on public.project_baselines(captured_by);
alter table public.project_baselines enable row level security;
revoke all on public.project_baselines from public,anon,authenticated;
grant select on public.project_baselines to authenticated;
grant all on public.project_baselines to service_role;
create policy project_baseline_read on public.project_baselines for select to authenticated using(private.project_access(project_id));

create function private.capture_project_baseline(p_id uuid,p_revision integer,p_task_revisions jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare p public.projects%rowtype; current_revisions jsonb; snapshot jsonb; actor_name text; actor uuid:=auth.uid();
begin
 if actor is null or not private.current_user_is_active() then raise exception 'Active account required' using errcode='42501';end if;
 select * into p from public.projects where id=p_id and deleted_at is null for update;
 if not found or not private.project_manage(p_id) then raise exception 'Project baseline cannot be captured' using errcode='42501';end if;
 if p.status in ('CLOSED','CANCELLED') then raise exception 'Project is read only' using errcode='42501';end if;
 if p_revision is distinct from p.revision then raise exception 'ATWAR_CONFLICT: project changed' using errcode='40001';end if;
 if exists(select 1 from public.project_baselines where project_id=p_id) then raise exception 'ATWAR_BASELINE_EXISTS: original baseline is already captured' using errcode='22023';end if;
 perform t.id from public.tasks t where t.project_id=p_id and t.deleted_at is null and t.status<>'ملغاة' and t.task_type<>'job_workflow' order by t.id for update;
 select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'revision',t.revision) order by t.id),'[]'::jsonb),
 coalesce(jsonb_agg(jsonb_build_object('id',t.id,'title',t.title,'start_date',t.start_date,'due_date',t.due_date,'assignee_id',t.assignee_id,'assignee_name_snapshot',t.assignee_name_snapshot,'project_phase_id',t.project_phase_id,'project_weight',t.project_weight,'project_milestone',t.project_milestone) order by t.id),'[]'::jsonb)
 into current_revisions,snapshot from public.tasks t where t.project_id=p_id and t.deleted_at is null and t.status<>'ملغاة' and t.task_type<>'job_workflow';
 if p_task_revisions is distinct from current_revisions then raise exception 'ATWAR_CONFLICT: project tasks changed' using errcode='40001';end if;
 select coalesce(full_name,'') into actor_name from public.profiles where id=actor;
 insert into public.project_baselines(project_id,project_revision,project_snapshot,task_snapshot,captured_by,captured_by_name)
 values(p_id,p.revision,jsonb_build_object('title',p.title,'start_date',p.start_date,'due_date',p.due_date,'objective',p.objective,'deliverables',p.deliverables),snapshot,actor,actor_name);
 update public.projects set revision=revision+1,updated_at=now() where id=p_id;
 insert into public.project_events(project_id,actor_id,actor_name,action,detail)
 values(p_id,actor,actor_name,'BASELINE_CAPTURED','تم تثبيت الخطة المرجعية الأصلية للمشروع ('||jsonb_array_length(snapshot)||' مهام).');
 return p_id;
end $$;
revoke all on function private.capture_project_baseline(uuid,integer,jsonb) from public,anon,authenticated;
grant execute on function private.capture_project_baseline(uuid,integer,jsonb) to authenticated;
create function public.capture_project_baseline(p_id uuid,p_revision integer,p_task_revisions jsonb)
returns uuid language sql security invoker set search_path='' as $$
 select private.capture_project_baseline(p_id,p_revision,p_task_revisions);
$$;
revoke all on function public.capture_project_baseline(uuid,integer,jsonb) from public,anon,authenticated;
grant execute on function public.capture_project_baseline(uuid,integer,jsonb) to authenticated;
