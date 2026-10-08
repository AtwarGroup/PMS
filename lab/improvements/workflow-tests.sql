begin;
select set_config('request.jwt.claim.sub','797d5893-d44d-489c-9109-91da4882acfe',true);
update public.profiles set active=true,status='active' where id='2347fbff-372e-43d1-a2e4-094f5b3159bf';
do $$ declare t uuid;begin t:=public.create_task_safe('مهمة اقتراح التحسين','eabb8105-e54d-45a3-90c8-15334698bbfc','اختبار مؤقت','normal',current_date,current_date+30,'');perform set_config('test.proposal_source',t::text,true);end $$;
select set_config('request.jwt.claim.sub','eabb8105-e54d-45a3-90c8-15334698bbfc',true);
set local role authenticated;
do $$ declare p uuid;payload jsonb;k uuid:=gen_random_uuid();begin
 payload:=jsonb_build_object('client_key',k,'title','أتمتة متابعة الطلبات','current_process','تجميع الطلبات يدويًا','problem','تكرار المتابعة اليومية','benefit','توفير الوقت وتقليل الأخطاء','source_task_id',current_setting('test.proposal_source'));
 p:=public.improvement_command(null,null,'submit',payload);perform set_config('test.proposal',p::text,true);
 if public.improvement_command(null,null,'submit',payload)<>p then raise exception 'Submit retry created duplicate';end if;
 begin perform public.improvement_command(null,null,'submit',payload||'{"title":"فكرة أخرى مختلفة"}');raise exception 'Changed retry accepted';exception when unique_violation then null;end;
 begin perform public.improvement_command(p,1,'decide','{"status":"STUDY","note":"مراجعة"}');raise exception 'Employee decision accepted';exception when insufficient_privilege then null;end;
 begin update public.improvement_proposals set status='ACCEPTED' where id=p;raise exception 'Direct update allowed';exception when insufficient_privilege then null;end;
 if (select count(*) from public.improvement_events where proposal_id=p)<>1 then raise exception 'Missing submission event';end if;
end $$;
select set_config('request.jwt.claim.sub','2347fbff-372e-43d1-a2e4-094f5b3159bf',true);
do $$ begin
 if exists(select 1 from public.improvement_proposals where id=current_setting('test.proposal')::uuid) then raise exception 'Unrelated manager can see proposal';end if;
 if exists(select 1 from public.improvement_events where proposal_id=current_setting('test.proposal')::uuid) then raise exception 'Event isolation failed';end if;
 begin perform public.improvement_execution(current_setting('test.proposal')::uuid);raise exception 'Execution scope leaked';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','797d5893-d44d-489c-9109-91da4882acfe',true);
do $$ declare p uuid:=current_setting('test.proposal')::uuid;t uuid;payload jsonb;begin
 begin perform public.improvement_command(p,1,'task',jsonb_build_object('assignee_id',auth.uid(),'start_date',current_date,'due_date',current_date+30));raise exception 'Unaccepted conversion allowed';exception when others then if sqlerrm='Unaccepted conversion allowed' then raise;end if;end;
 perform public.improvement_command(p,1,'decide','{"status":"STUDY","note":"قابلة للدراسة"}');
 begin perform public.improvement_command(p,1,'decide','{"status":"ACCEPTED","priority":"HIGH","note":"قابلة للتنفيذ"}');raise exception 'Stale revision accepted';exception when others then if sqlerrm not like 'ATWAR_CONFLICT:%' then raise;end if;end;
 begin perform public.improvement_command(p,2,'decide','{"status":"ACCEPTED","note":"قابلة للتنفيذ"}');raise exception 'Missing priority accepted';exception when others then if sqlerrm='Missing priority accepted' then raise;end if;end;
 perform public.improvement_command(p,2,'decide','{"status":"ACCEPTED","priority":"HIGH","note":"أولوية لتقليل الأخطاء"}');
 payload:=jsonb_build_object('assignee_id','2347fbff-372e-43d1-a2e4-094f5b3159bf','start_date',current_date,'due_date',current_date+30);
 t:=public.improvement_command(p,3,'task',payload);perform set_config('test.proposal_execution_task',t::text,true);
 if public.improvement_command(p,3,'task',payload)<>t then raise exception 'Conversion retry duplicate';end if;
 if (select task_id from public.improvement_proposals where id=p)<>t then raise exception 'Missing task link';end if;
 if (select count(*) from public.improvement_events where proposal_id=p)<>4 then raise exception 'Retry generated duplicate event';end if;
 begin perform public.improvement_command(p,4,'project','{}');raise exception 'Second execution allowed';exception when others then if sqlerrm='Second execution allowed' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub','eabb8105-e54d-45a3-90c8-15334698bbfc',true);
do $$ declare p uuid:=current_setting('test.proposal')::uuid;q uuid;begin
 if exists(select 1 from public.tasks where id=current_setting('test.proposal_execution_task')::uuid) then raise exception 'Proposal link granted task access';end if;
 if not exists(select 1 from public.notifications where improvement_id=p and recipient_id='eabb8105-e54d-45a3-90c8-15334698bbfc') then raise exception 'Missing requester notification';end if;
 if public.improvement_execution(p)->>'status'<>'قيد الانتظار' then raise exception 'Requester cannot follow execution';end if;
 q:=public.improvement_command(null,null,'submit',jsonb_build_object('client_key',gen_random_uuid(),'title','مشروع تحسين خدمة العملاء','current_process','إجراءات متابعة يدوية','problem','تأخر تحديث الطلبات','benefit','رفع جودة الخدمة'));perform set_config('test.project_proposal',q::text,true);
end $$;
select set_config('request.jwt.claim.sub','797d5893-d44d-489c-9109-91da4882acfe',true);
do $$ declare p uuid:=current_setting('test.project_proposal')::uuid;r uuid;begin
 perform public.improvement_command(p,1,'decide','{"status":"STUDY","note":"ندرس الإمكانية"}');
 perform public.improvement_command(p,2,'decide','{"status":"DEFERRED","note":"بانتظار توفر الموارد"}');
 perform public.improvement_command(p,3,'decide','{"status":"STUDY","note":"توفر فريق التنفيذ"}');
 perform public.improvement_command(p,4,'decide','{"status":"ACCEPTED","priority":"MEDIUM","note":"ننفذها ضمن مشروع"}');
 r:=public.improvement_command(p,5,'project',jsonb_build_object('manager_id','2347fbff-372e-43d1-a2e4-094f5b3159bf','sponsor_id',auth.uid(),'start_date',current_date,'due_date',current_date+30));
 if (select project_id from public.improvement_proposals where id=p)<>r then raise exception 'Missing project link';end if;
 perform public.cancel_task_safe(current_setting('test.proposal_execution_task')::uuid,'إلغاء للاختبار المؤقت');
end $$;
select set_config('request.jwt.claim.sub','eabb8105-e54d-45a3-90c8-15334698bbfc',true);
do $$ begin
 if not exists(select 1 from public.improvement_events where proposal_id=current_setting('test.proposal')::uuid and action='EXECUTION') then raise exception 'Execution event missing';end if;
 if not exists(select 1 from public.notifications where improvement_id=current_setting('test.proposal')::uuid and type='improvement_execution') then raise exception 'Execution notification missing';end if;
 if public.improvement_execution(current_setting('test.proposal')::uuid)->>'status'<>'ملغاة' then raise exception 'Cancelled execution not reflected';end if;
 if public.improvement_execution(current_setting('test.project_proposal')::uuid)->>'status'<>'PLANNING' then raise exception 'Project execution not reflected';end if;
end $$;
reset role;
update public.profiles set active=false,status='inactive' where id='eabb8105-e54d-45a3-90c8-15334698bbfc';
set local role authenticated;
do $$ begin
 if exists(select 1 from public.improvement_proposals) then raise exception 'Disabled account can read proposals';end if;
 begin perform public.improvement_execution(current_setting('test.proposal')::uuid);raise exception 'Disabled execution allowed';exception when insufficient_privilege then null;end;
end $$;
reset role;
rollback;
