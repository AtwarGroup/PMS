-- Private lookup exposes routing IDs only after both task access and conversation membership.
create index if not exists communication_task_links_task on private.communication_task_links(task_id);
create function private.communication_task_sources(p_task uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if auth.uid() is null or not private.communication_actor(auth.uid()) then return '[]'::jsonb;end if;
 if not ((private.can_view_task(p_task) or private.has_permission('tasks.read_all')) and exists(select 1 from public.tasks t where t.id=p_task and t.deleted_at is null and (t.project_id is null or private.project_access(t.project_id)))) then return '[]'::jsonb;end if;
 select coalesce(jsonb_agg(jsonb_build_object('conversation',x.conversation_id,'message',x.id)),'[]'::jsonb) into result from (
 select m.id,m.conversation_id from private.communication_task_links l join private.communication_messages m on m.id=l.message_id join private.communication_conversations c on c.id=m.conversation_id
 where l.task_id=p_task and c.payload->'members' @> jsonb_build_array(auth.uid()::text) order by (m.payload->>'seq')::bigint limit 5) x;
 return result;
end $$;
revoke all on function private.communication_task_sources(uuid) from public,anon;
grant execute on function private.communication_task_sources(uuid) to authenticated;
create function public.communication_task_sources(p_task uuid) returns jsonb language sql stable security invoker set search_path='' as $$ select private.communication_task_sources(p_task) $$;
revoke all on function public.communication_task_sources(uuid) from public,anon;
grant execute on function public.communication_task_sources(uuid) to authenticated;
