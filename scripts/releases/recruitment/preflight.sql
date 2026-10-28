-- Read-only preflight. Run before the upgrade inside the release transaction.
do $$begin
 if to_regclass('private.recruitment_requests') is null or to_regprocedure('private.recruitment_request_create(jsonb)') is null or to_regprocedure('private.recruitment_detail(uuid)') is null then raise exception 'Expected live recruitment baseline is missing';end if;
 if to_regclass('private.hr_employees') is null or to_regclass('private.hr_sections') is null then raise exception 'Employee/organization dependencies are missing';end if;
 if not exists(select 1 from information_schema.columns where table_schema='public'and table_name='job_descriptions'and column_name='content')then raise exception 'Job library content dependency is missing';end if;
end $$;
select 'recruitment_preflight_ok' as result;
