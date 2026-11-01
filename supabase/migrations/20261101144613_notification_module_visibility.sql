-- One recipient-scoped feed for the bell, module badges and notification history.
-- SECURITY INVOKER deliberately preserves all notification/task RLS boundaries.
create or replace function public.notification_overview(p_limit integer default 30)
returns jsonb language sql stable security invoker
set search_path=pg_catalog,public,private as $$
with pool as materialized (
 select n.* from public.notifications n
 where n.recipient_id=(select auth.uid()) and private.current_user_is_active()
 and (n.read_at is null or n.id in (
  select r.id from public.notifications r where r.recipient_id=(select auth.uid()) and r.read_at is not null
  order by r.created_at desc,r.id desc limit greatest(1,least(coalesce(p_limit,30),100))
 ))
), classified as (
 select n.*,case
 when n.type like 'FLEET_%' then 'fleet'
 when n.type='IT_SUPPORT' then 'it_support'
 when n.type='RECRUITMENT' then 'recruitment'
 when n.project_id is not null then 'projects'
 when n.type in ('communication','communication_trial') then 'communication'
 when n.improvement_id is not null then 'workspace'
 when t.legacy_metadata->'job_workflow'->>'policy_id' is not null then 'policies'
 when t.legacy_metadata->'job_workflow'->>'phase'='EMPLOYEE_ACK' or n.type='JOB_DESCRIPTION_ASSIGNED' then 'profile'
 when t.legacy_metadata->'job_workflow'->>'job_id' is not null then 'job_library'
 when n.task_id is not null or n.type in ('overdue','overdue_summary','assigned','approval','approved','completed','updated','started','reopened','manager_note','TASK_ASSIGNED','TASK_DELEGATED','TASK_APPROVED','TASK_COMPLETED') then 'tasks'
 else 'home' end as module,
 coalesce(n.it_support_ticket_id::text,n.fleet_request_id::text,n.fleet_handover_id::text,n.fleet_vehicle_id::text,
 n.communication_conversation_id,n.project_id::text,n.improvement_id::text,n.task_id::text,n.id::text) as subject
 from pool n left join public.tasks t on t.id=n.task_id
), keyed as (select c.*,module||':'||subject as thread_key from classified c where module in ('home','profile') or private.module_allowed(module)),
grouped as (
 select thread_key,module,max(created_at) as last_at,count(*) filter(where read_at is null)::integer as unread_count,
 coalesce(jsonb_agg(id) filter(where read_at is null),'[]'::jsonb) as unread_ids
 from keyed group by thread_key,module
), latest as (
 select distinct on(thread_key) * from keyed order by thread_key,created_at desc,id desc
), items as (
 select (to_jsonb(l)-'subject')||jsonb_build_object('unread_ids',g.unread_ids,'unread_count',g.unread_count,
 'read_at',case when g.unread_count>0 then null else l.read_at end) as value,g.last_at,l.id
 from latest l join grouped g using(thread_key,module)
 order by g.last_at desc,l.id desc limit greatest(1,least(coalesce(p_limit,30),100))
), counts as (select module,count(*)::integer as total from grouped where unread_count>0 group by module)
select jsonb_build_object(
 'total_unread',(select count(*) from grouped where unread_count>0),
 'modules',coalesce((select jsonb_object_agg(module,total) from counts),'{}'::jsonb),
 'items',coalesce((select jsonb_agg(value order by last_at desc,id desc) from items),'[]'::jsonb))
$$;
revoke all on function public.notification_overview(integer) from public,anon;
grant execute on function public.notification_overview(integer) to authenticated;
