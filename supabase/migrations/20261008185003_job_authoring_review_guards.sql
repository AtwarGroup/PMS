begin;
-- The legacy route preserves existing assignments, never creates a new exception.
create function private.guard_job_review_reference()
returns trigger language plpgsql security invoker set search_path='pg_catalog','public','private' as $$
begin
 if tg_op='INSERT' and new.reviewer_mode='legacy' then raise exception 'الوصف الجديد يستخدم المدير المباشر أو بديلًا مسببًا'; end if;
 if tg_op='UPDATE' and new.reviewer_mode='legacy' then
  if old.reviewer_mode<>'legacy' or new.reviewer_id is distinct from old.reviewer_id then raise exception 'تغيير مرجعية المراجع يتطلب تحديد المدير المباشر أو بديلًا مسببًا'; end if;
 end if;
 return new;
end $$;
revoke all on function private.guard_job_review_reference() from public,anon,authenticated;
create trigger zz_guard_job_review_reference before insert or update on public.job_descriptions for each row execute function private.guard_job_review_reference();
-- A returned draft belongs to its preparer, not the manager who returned it.
do $$ declare d text;begin
 select pg_get_functiondef('private.prepare_job_change_request()'::regprocedure) into d;
 d:=replace(d,'j.status in(''IN_REVIEW'',''CHANGES_REQUESTED'')','j.status=''IN_REVIEW''');execute d;
end $$;
commit;
