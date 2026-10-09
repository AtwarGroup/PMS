create table public.task_followup_details (
 task_id uuid primary key references public.tasks(id) on delete cascade,
 blocked boolean not null default false,
 reason text not null default '' check (char_length(reason)<=1000),
 next_step text not null default '' check (char_length(next_step)<=1000),
 owner_role text not null default 'assignee' check (owner_role in ('assignee','creator')),
 follow_date date,
 revision integer not null default 1 check (revision>0),
 updated_at timestamptz not null default now(),
 updated_by uuid not null references public.profiles(id)
);
alter table public.task_followup_details enable row level security;
revoke all on public.task_followup_details from public,anon,authenticated;
grant select on public.task_followup_details to authenticated;
grant all on public.task_followup_details to service_role;
create policy task_followup_read on public.task_followup_details for select to authenticated using (private.can_view_task(task_id));

create function public.task_followup_context(p_task_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare t public.tasks%rowtype; f public.task_followup_details%rowtype;
begin
 if auth.uid() is null or not private.current_user_is_active() or not private.can_view_task(p_task_id) then raise exception 'Task is unavailable' using errcode='42501';end if;
 select * into t from public.tasks where id=p_task_id and deleted_at is null;
 select * into f from public.task_followup_details where task_id=p_task_id;
 return jsonb_build_object('followup',case when f.task_id is null then null else to_jsonb(f) end,'task_revision',t.revision,'can_edit',t.task_type<>'job_workflow' and t.status in ('قيد الانتظار','قيد التنفيذ') and private.can_edit_task_content(t.id));
end $$;

create function public.save_task_followup(
 p_task_id uuid,p_blocked boolean,p_reason text,p_next_step text,p_owner_role text,p_follow_date date,p_expected_revision integer,p_expected_task_revision integer
) returns jsonb language plpgsql security definer set search_path='' as $$
declare t public.tasks%rowtype; f public.task_followup_details%rowtype; actor uuid:=auth.uid(); actor_name text;
begin
 if actor is null or not private.current_user_is_active() then raise exception 'Active authenticated account required' using errcode='42501';end if;
 select * into t from public.tasks where id=p_task_id and deleted_at is null for update;
 if not found or not private.can_view_task(p_task_id) or not private.can_edit_task_content(p_task_id) or t.task_type='job_workflow' then raise exception 'Task follow-up cannot be edited' using errcode='42501';end if;
 if p_expected_task_revision is distinct from t.revision then raise exception 'ATWAR_CONFLICT: task changed; reload follow-up' using errcode='40001';end if;
 if p_blocked is null or p_owner_role is null or p_owner_role not in ('assignee','creator') or char_length(coalesce(p_reason,''))>1000 or char_length(coalesce(p_next_step,''))>1000 then raise exception 'Invalid follow-up fields' using errcode='22023';end if;
 select * into f from public.task_followup_details where task_id=p_task_id for update;
 if p_expected_revision is distinct from coalesce(f.revision,0) then raise exception 'ATWAR_CONFLICT: follow-up changed; reload' using errcode='40001';end if;
 insert into public.task_followup_details(task_id,blocked,reason,next_step,owner_role,follow_date,updated_by)
 values(p_task_id,p_blocked,btrim(coalesce(p_reason,'')),btrim(coalesce(p_next_step,'')),p_owner_role,p_follow_date,actor)
 on conflict(task_id) do update set blocked=excluded.blocked,reason=excluded.reason,next_step=excluded.next_step,owner_role=excluded.owner_role,follow_date=excluded.follow_date,updated_by=actor,updated_at=now(),revision=public.task_followup_details.revision+1 returning * into f;
 select full_name into actor_name from public.profiles where id=actor;
 insert into public.admin_audit_log(actor_id,actor_name_snapshot,action,target_type,target_id,detail)
 values(actor,actor_name,'TASK_FOLLOWUP','task',p_task_id::text,jsonb_build_object('blocked',f.blocked,'reason',f.reason,'next_step',f.next_step,'owner_role',f.owner_role,'follow_date',f.follow_date,'revision',f.revision));
 return jsonb_build_object('followup',to_jsonb(f),'task_revision',t.revision,'can_edit',true);
end $$;
revoke all on function public.task_followup_context(uuid) from public,anon,authenticated;
revoke all on function public.save_task_followup(uuid,boolean,text,text,text,date,integer,integer) from public,anon,authenticated;
grant execute on function public.task_followup_context(uuid) to authenticated;
grant execute on function public.save_task_followup(uuid,boolean,text,text,text,date,integer,integer) to authenticated;

