begin;
do $test$
declare a uuid:='797d5893-d44d-489c-9109-91da4882acfe';e uuid:='eabb8105-e54d-45a3-90c8-15334698bbfc';t uuid;t2 uuid;s jsonb;n uuid:=gen_random_uuid();bad boolean:=false;r jsonb;begin
 if has_function_privilege('anon','public.communication_trial_task_command(text,uuid,text,uuid,date)','execute') then raise exception 'anonymous grant';end if;
 perform set_config('request.jwt.claim.sub',a::text,true);
 select state into s from private.communication_trial_state where singleton;
 s:=jsonb_set(s,'{conversations}',coalesce(s->'conversations','[]')||jsonb_build_array(jsonb_build_object('id','bridge-qa','type','group','owner',a,'members',jsonb_build_array(a,e))));
 s:=jsonb_set(s,'{messages}',coalesce(s->'messages','[]')||jsonb_build_array(jsonb_build_object('id','bridge-qa-message','conversation','bridge-qa','body','اختبار ربط قابل للتراجع')));
 update private.communication_trial_state set state=s where singleton;
 t:=public.communication_trial_task_command('bridge-qa-message',null,'اختبار مؤقت',a,current_date+1);
 t2:=public.communication_trial_task_command('bridge-qa-message',null,'اختبار مؤقت',a,current_date+1);
 if t<>t2 or not exists(select 1 from public.tasks where id=t and creator_id=a and assignee_id=a) then raise exception 'task identity/idempotency';end if;
 if not exists(select 1 from private.communication_trial_task_links where task_id=t and message_id='bridge-qa-message') then raise exception 'missing link';end if;
 perform set_config('request.jwt.claim.sub',e::text,true);
 begin perform public.communication_trial_task_command('bridge-qa-message',t);exception when others then bad:=true;end;
 if not bad then raise exception 'employee read restricted task';end if;
 perform set_config('request.jwt.claim.sub',a::text,true);
 select state into s from private.communication_trial_state where singleton;
 s:=jsonb_set(s,'{notifications}',coalesce(s->'notifications','[]')||jsonb_build_array(jsonb_build_object('id',n,'user',e,'conversation','bridge-qa','message','bridge-qa-message','read',false)));
 update private.communication_trial_state set state=s where singleton;
 if not exists(select 1 from public.notifications where id=n and type='communication_trial' and message='افتح التواصل لقراءة الرسالة') then raise exception 'notification bridge failed';end if;
 perform set_config('request.jwt.claim.sub',e::text,true);
 r:=public.communication_trial_notification_open(n);if r->>'conversation'<>'bridge-qa' then raise exception 'route';end if;
 perform set_config('request.jwt.claim.sub',a::text,true);
 bad:=false;begin perform public.communication_trial_notification_open(n);exception when others then bad:=true;end;if not bad then raise exception 'cross-user notification';end if;
 perform set_config('request.jwt.claim.sub','',true);
 bad:=false;begin perform public.communication_trial_task_command('bridge-qa-message',t);exception when others then bad:=true;end;if not bad then raise exception 'anonymous task';end if;
end $test$;
rollback;
