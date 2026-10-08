begin;
-- Superseded pending acknowledgements are retired, never marked as acknowledged.
create function private.retire_old_job_ack_tasks()
returns trigger language plpgsql security definer set search_path='pg_catalog','public','private' as $$
begin
 if old.status<>'PUBLISHED' and new.status='PUBLISHED' then
  update public.tasks t set deleted_at=now(),delete_reason='استُبدلت مهمة الاطلاع بإصدار أحدث من الوصف الوظيفي',updated_at=now(),revision=t.revision+1
  from private.job_workflow_tasks w where w.task_id=t.id and w.job_description_id=new.id and w.phase='EMPLOYEE_ACK'
   and w.cycle_key<>new.published_snapshot->>'revision' and t.deleted_at is null and t.status<>'مكتملة';
 end if;return new;
end $$;
revoke all on function private.retire_old_job_ack_tasks() from public,anon,authenticated;
create trigger retire_old_job_ack_tasks after update of status on public.job_descriptions for each row execute function private.retire_old_job_ack_tasks();
-- Hold the published snapshot stable while its employee acknowledgement is recorded.
do $$ declare d text;begin
 select pg_get_functiondef('public.acknowledge_job_description(uuid,text)'::regprocedure) into d;
 if position('published_snapshot is not null;' in d)=0 then raise exception 'Acknowledgement function changed';end if;
 d:=replace(d,'published_snapshot is not null;','published_snapshot is not null for share;');execute d;
end $$;
commit;
