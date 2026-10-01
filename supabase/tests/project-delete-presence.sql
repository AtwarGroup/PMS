-- Real authorization/visibility tests. All fixtures and presence writes roll back.
begin;
select set_config('test.admin',(select id::text from public.profiles where role='admin' and active and status='active' limit 1),true);
select set_config('test.manager',(select id::text from public.profiles where role='manager' and active and status='active' limit 1),true);
select set_config('test.employee',(select id::text from public.profiles where role='employee' and active and status='active' order by id limit 1),true);
select set_config('test.outsider',(select id::text from public.profiles where role='employee' and active and status='active' order by id offset 1 limit 1),true);
set local role authenticated;
do $$ declare a uuid:=current_setting('test.admin')::uuid;m uuid:=current_setting('test.manager')::uuid;e uuid:=current_setting('test.employee')::uuid;o uuid:=current_setting('test.outsider')::uuid;p uuid;t uuid;r integer;rejected boolean;
begin
 perform set_config('request.jwt.claim.sub',a::text,true);
 p:=public.project_command(null,0,'create',jsonb_build_object('title','QA deletion rollback','manager_id',m,'sponsor_id',a,'start_date','2026-10-01','due_date','2026-12-31','members',jsonb_build_array(e)));
 perform set_config('request.jwt.claim.sub',m::text,true);
 t:=public.project_command(p,1,'task',jsonb_build_object('title','QA retained task','assignee_id',e,'start_date','2026-10-01','due_date','2026-10-03'));
 select revision into r from public.projects where id=p;
 rejected:=false;begin perform public.project_delete(p,r);exception when others then rejected:=true;end;if not rejected then raise exception 'QA manager deleted another creator project';end if;
 perform set_config('request.jwt.claim.sub',e::text,true);
 perform public.presence_ping();
 if not exists(select 1 from public.project_presence(p) where user_id=e and online) then raise exception 'QA heartbeat not online';end if;
 if exists(select 1 from public.project_presence(p) where user_id=o) then raise exception 'QA outsider presence leak';end if;
 rejected:=false;begin perform public.project_delete(p,r);exception when others then rejected:=true;end;if not rejected then raise exception 'QA member delete';end if;
 perform set_config('request.jwt.claim.sub',o::text,true);
 rejected:=false;begin perform public.project_presence(p);exception when others then rejected:=true;end;if not rejected then raise exception 'QA outsider read presence';end if;
 perform set_config('request.jwt.claim.sub',a::text,true);
 rejected:=false;begin perform public.project_delete(p,r-1);exception when others then rejected:=true;end;if not rejected then raise exception 'QA stale deletion';end if;
 perform public.project_delete(p,r);
 if exists(select 1 from public.projects where id=p) or exists(select 1 from public.tasks where id=t) then raise exception 'QA creator sees deleted content';end if;
 perform set_config('request.jwt.claim.sub',e::text,true);
 if private.can_view_task(t) or exists(select 1 from public.tasks where id=t) then raise exception 'QA assignee sees deleted task';end if;
 rejected:=false;begin perform public.project_command(p,0,'message','{"body":"deleted"}');exception when others then rejected:=true;end;if not rejected then raise exception 'QA deleted chat accepts message';end if;
end $$;
reset role;
do $$ declare p uuid;t uuid;begin
 select id into p from public.projects where title='QA deletion rollback' and deleted_at is not null;
 if p is null or not exists(select 1 from public.tasks where project_id=p) or not exists(select 1 from public.project_events where project_id=p and action='DELETE') then raise exception 'QA deletion lost audit';end if;
 update private.user_presence set last_seen=now()-interval '91 seconds' where user_id=current_setting('test.employee')::uuid;
end $$;
-- Check expiry on another project after resetting the test user's server timestamp.
set local role authenticated;
do $$ declare a uuid:=current_setting('test.admin')::uuid;m uuid:=current_setting('test.manager')::uuid;e uuid:=current_setting('test.employee')::uuid;p uuid;begin
 perform set_config('request.jwt.claim.sub',a::text,true);
 p:=public.project_command(null,0,'create',jsonb_build_object('title','QA presence expiry rollback','manager_id',m,'sponsor_id',a,'start_date','2026-10-01','due_date','2026-12-31','members',jsonb_build_array(e)));
 if exists(select 1 from public.project_presence(p) where user_id=e and online) then raise exception 'QA expired heartbeat still online';end if;
end $$;
rollback;
