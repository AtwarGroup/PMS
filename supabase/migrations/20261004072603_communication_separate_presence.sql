create function public.communication_presence(p_actor uuid,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $f$
declare p jsonb;devices jsonb;viewing text;thread text;ms bigint:=floor(extract(epoch from clock_timestamp())*1000);device text:=p_data->>'device';begin
 if not private.communication_actor(p_actor) then raise exception 'التواصل غير متاح';end if;
 if device is null or device !~ '^[a-zA-Z0-9-]{8,100}$' then raise exception 'الجلسة غير صحيحة';end if;
 perform 1 from private.communication_control where singleton for update;
 select payload into p from private.communication_personal where user_id=p_actor;p:=coalesce(p,'{}');
 select coalesce(jsonb_object_agg(key,value),'{}') into devices from jsonb_each(coalesce(p->'devices','{}')) where ms-(value->>'seen')::bigint<86400000;
 if exists(select 1 from private.communication_conversations where id=p_data->>'viewing' and payload->'members' @> jsonb_build_array(p_actor::text)) then viewing:=p_data->>'viewing';end if;
 if viewing is not null and exists(select 1 from private.communication_messages where id=p_data->>'thread' and conversation_id=viewing) then thread:=p_data->>'thread';end if;
 devices:=devices||jsonb_build_object(p_actor::text||':'||device,jsonb_build_object('user',p_actor,'seen',ms,'active',least(ms,coalesce((p_data->>'active')::bigint,ms)),'viewing',viewing,'thread',thread));
 p:=jsonb_set(p,'{devices}',devices);
 insert into private.communication_personal(user_id,payload) values(p_actor,p) on conflict(user_id) do update set payload=excluded.payload;
 update private.communication_control set version=version+1 where singleton;
 return jsonb_build_object('ok',true);end $f$;
revoke all on function public.communication_presence(uuid,jsonb) from public,anon,authenticated;
grant execute on function public.communication_presence(uuid,jsonb) to service_role;
