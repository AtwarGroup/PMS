create function public.communication_history(p_actor uuid,p_conversation text,p_before bigint default null) returns jsonb language plpgsql security definer set search_path='' as $f$
declare v jsonb;begin
 if not private.communication_actor(p_actor) or not exists(select 1 from private.communication_conversations where id=p_conversation and payload->'members' @> jsonb_build_array(p_actor::text)) then raise exception 'المحادثة غير متاحة';end if;
 select coalesce(jsonb_agg(payload order by (payload->>'seq')::bigint),'[]') into v from (select payload from private.communication_messages where conversation_id=p_conversation and (p_before is null or (payload->>'seq')::bigint<p_before) order by (payload->>'seq')::bigint desc limit 300) x;return v;end $f$;
create function public.communication_message(p_actor uuid,p_message text) returns jsonb language plpgsql security definer set search_path='' as $f$
declare v jsonb;begin
 if not private.communication_actor(p_actor) then raise exception 'التواصل غير متاح';end if;
 select m.payload into v from private.communication_messages m join private.communication_conversations c on c.id=m.conversation_id where m.id=p_message and c.payload->'members' @> jsonb_build_array(p_actor::text);
 if v is null then raise exception 'الرسالة غير متاحة';end if;return v;end $f$;
revoke all on function public.communication_history(uuid,text,bigint),public.communication_message(uuid,text) from public,anon,authenticated;
grant execute on function public.communication_history(uuid,text,bigint),public.communication_message(uuid,text) to service_role;
