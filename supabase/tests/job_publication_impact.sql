begin;
select set_config('request.jwt.claim.sub','797d5893-d44d-489c-9109-91da4882acfe',true);
set local role authenticated;
do $$ declare j public.job_descriptions%rowtype; impact jsonb;begin
 select * into j from public.job_descriptions order by job_code limit 1;
 impact:=public.get_job_publication_impact(j.id,j.revision);
 assert (impact->>'linked_count')::integer=(impact->>'active_count')::integer+(impact->>'inactive_count')::integer;
 assert (impact->>'linked_count')::integer=(select count(*) from public.employee_job_assignments where job_description_id=j.id);
 begin perform public.get_job_publication_impact(j.id,j.revision-1);raise exception 'Expected conflict';exception when serialization_failure then null;end;
end $$;
select set_config('request.jwt.claim.sub','eabb8105-e54d-45a3-90c8-15334698bbfc',true);
do $$ begin
 begin perform public.get_job_publication_impact(gen_random_uuid(),1);raise exception 'Expected denial';exception when insufficient_privilege then null;end;
end $$;
rollback;
