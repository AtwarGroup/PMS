begin;
-- Configuration revisions retire the prior pending task; hourly checks never change that revision.
do $$ declare d text;begin
 select pg_get_functiondef('private.sync_job_periodic_review_task()'::regprocedure) into d;
 if position('(old.reviewer_id,old.due_on,old.enabled)' in d)=0 then raise exception 'Periodic task function changed';end if;
 d:=replace(d,'(old.reviewer_id,old.due_on,old.enabled)','(old.reviewer_id,old.due_on,old.enabled,old.revision)');
 d:=replace(d,'(new.reviewer_id,new.due_on,new.enabled)','(new.reviewer_id,new.due_on,new.enabled,new.revision)');execute d;
end $$;
commit;
