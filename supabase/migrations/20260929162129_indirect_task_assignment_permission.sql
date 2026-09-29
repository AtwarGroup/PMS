-- Keep task visibility separate from the authority to assign indirect reports.
create or replace function private.can_assign_task_target_for(p_actor uuid,p_target uuid)
returns boolean language sql stable security definer set search_path='pg_catalog','public','private' as $$
 select exists (
   select 1 from public.profiles actor join public.profiles target on target.id=p_target
   where actor.id=p_actor and actor.active=true and actor.status='active'
     and target.active=true and target.status='active'
     and (actor.role='admin' or actor.id=target.id or
       (actor.role='manager' and (target.manager_id=actor.id or
         ('tasks.assign_indirect'=any(coalesce(actor.permissions,array[]::text[])) and
          exists (with recursive ancestry as (
            select id,manager_id,array[id]::uuid[] path from public.profiles where id=p_target
            union all
            select parent.id,parent.manager_id,a.path||parent.id from public.profiles parent
            join ancestry a on parent.id=a.manager_id
            where cardinality(a.path)<21 and not parent.id=any(a.path)
          ) select 1 from ancestry where id=p_actor and id<>p_target)
         ))))
 );
$$;
revoke all on function private.can_assign_task_target_for(uuid,uuid) from public,anon,authenticated;
create or replace function private.can_assign_task_target(p_target uuid)
returns boolean language sql stable security definer set search_path='pg_catalog','private' as $$
 select private.can_assign_task_target_for((select auth.uid()),p_target);
$$;
revoke all on function private.can_assign_task_target(uuid) from public,anon;
grant execute on function private.can_assign_task_target(uuid) to authenticated;

create or replace function public.admin_set_indirect_task_assignment(p_profile_id uuid,p_enabled boolean)
returns void language plpgsql security definer set search_path='pg_catalog','public','private' as $$
begin
 if not private.is_admin() then raise exception 'Administrator access required' using errcode='42501'; end if;
 if p_enabled is null then raise exception 'Enabled must be provided'; end if;
 update public.profiles set permissions=case when p_enabled
   then array(select distinct x from unnest(coalesce(permissions,array[]::text[])||array['tasks.assign_indirect']) x)
   else array_remove(coalesce(permissions,array[]::text[]),'tasks.assign_indirect') end
 where id=p_profile_id and (role='manager' or not p_enabled);
 if not found then raise exception 'Active manager profile required'; end if;
end $$;
revoke all on function public.admin_set_indirect_task_assignment(uuid,boolean) from public,anon;
grant execute on function public.admin_set_indirect_task_assignment(uuid,boolean) to authenticated;

-- Preserve the three managers who have already assigned tasks to indirect reports.
update public.profiles
set permissions=array(select distinct x from unnest(coalesce(permissions,array[]::text[])||array['tasks.assign_indirect']) x)
where role='manager' and active=true and full_name in ('أحمد اليافعي','محمد بن ماضي','محمد باسنبل');

alter policy tasks_insert_policy on public.tasks with check (
 private.current_user_is_active() and creator_id=(select auth.uid())
 and private.user_is_active(assignee_id) and revision=1
 and private.can_assign_task_target(assignee_id)
 and (private.is_admin() or status='قيد الانتظار')
);
alter policy recurring_templates_write_policy on public.recurring_task_templates with check (
 owner_id=(select auth.uid()) and (private.current_user_role()='manager' or private.is_admin())
 and private.can_assign_task_target(assignee_id)
);
alter policy recurring_templates_update_policy on public.recurring_task_templates
 with check ((owner_id=(select auth.uid()) or private.is_admin())
 and private.can_assign_task_target_for(owner_id,assignee_id));

-- SECURITY DEFINER RPCs bypass RLS, so check them as well.
do $$
declare v_name text; v_source text; v_new text; v_old text;
begin
 for v_name in select unnest(array['create_task_safe','import_tasks_safe','delegate_task_safe']) loop
   select pg_get_functiondef(p.oid) into v_source from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname=v_name;
   if v_name='create_task_safe' then
     v_old:='if not v_allowed then raise exception';
     v_new:='if v_allowed and not private.can_assign_task_target(p_assignee_id) then v_allowed:=false; end if; if not v_allowed then raise exception';
   elsif v_name='import_tasks_safe' then
     v_old:='if not v_allowed then raise exception';
     v_new:='if v_allowed and not private.can_assign_task_target(v_assignee) then v_allowed:=false; end if; if not v_allowed then raise exception';
   else
     v_old:='v_task.assignee_id=v_uid and private.manages_user(p_target_id)';
     v_new:='v_task.assignee_id=v_uid and private.can_assign_task_target(p_target_id)';
   end if;
   if v_source is null or strpos(v_source,v_old)=0 then raise exception 'Unexpected % function shape',v_name; end if;
   execute replace(v_source,v_old,v_new);
 end loop;
 select pg_get_functiondef(p.oid) into v_source from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='private' and p.proname='validate_task_workflow';
 v_old:='private.manages_user(new.assignee_id)';
 if v_source is null or strpos(v_source,v_old)=0 then raise exception 'Unexpected validate_task_workflow function shape'; end if;
 execute replace(v_source,v_old,'private.can_assign_task_target(new.assignee_id)');

 select pg_get_functiondef(p.oid) into v_source from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='private' and p.proname='materialize_recurring_tasks';
 v_old:='insert into public.tasks(title,description,task_type,status,priority,progress,creator_id,assignee_id';
 if v_source is null or strpos(v_source,v_old)=0 then raise exception 'Unexpected materialize_recurring_tasks function shape'; end if;
 v_new:='if not private.can_assign_task_target_for(r.owner_id,r.assignee_id) then update public.recurring_task_templates set active=false,updated_at=now() where id=r.id; continue; end if; '||v_old;
 execute replace(v_source,v_old,v_new);
end $$;
