begin;
do $$ declare d text;begin
 select pg_get_functiondef('private.enforce_task_delete_ownership()'::regprocedure) into d;
 d:=replace(d,'and private.can_job_stage(''DRAFT'') then return new;','and (private.can_job_stage(''DRAFT'') or private.can_job_stage(''PUBLISH'')) then return new;');
 d:=replace(d,'v_task := old;',$patch$v_task := old;
 if tg_op='UPDATE' and pg_trigger_depth()>1 and old.task_type='job_workflow' and old.legacy_metadata#>>'{job_workflow,phase}'='DRAFT_REVISION' and old.legacy_metadata#>>'{job_workflow,cycle}' like 'periodic:%' and private.can_job_stage('PUBLISH') then return new;end if;$patch$);execute d;
end $$;
create function private.stop_archived_job_periodic_reviews() returns trigger language plpgsql security definer set search_path=pg_catalog,public,private as $$
begin
 if new.status='ARCHIVED' and old.status<>'ARCHIVED' then
  update public.job_periodic_reviews set enabled=false,revision=revision+1,updated_at=now() where job_description_id=new.id;
  update public.tasks t set deleted_at=now(),delete_reason='أرشفة الوصف أوقفت طلب التحديث الدوري',revision=t.revision+1,updated_at=now()
  from private.job_workflow_tasks w where w.task_id=t.id and w.job_description_id=new.id and w.phase='DRAFT_REVISION' and w.cycle_key like 'periodic:%' and t.deleted_at is null and t.status<>'مكتملة';
 end if;return new;
end $$;
create trigger stop_archived_job_periodic_reviews after update of status on public.job_descriptions for each row execute function private.stop_archived_job_periodic_reviews();
revoke all on function private.stop_archived_job_periodic_reviews() from public,anon,authenticated;
commit;
