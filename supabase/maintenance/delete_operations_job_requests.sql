-- User-authorized removal of the Operations Director request and its dependent history.
-- Existing completed workflow tasks remain historical records; assignments are untouched.
with target as (
 select id from public.employee_job_change_requests
 where id='75e57dff-8ad4-4c18-ad1f-a9d06ff39ee6'
   and job_title='مدير العمليات' and status='NEEDS_CHANGES'
), removed_events as (
 delete from public.employee_job_change_events where request_id in (select id from target) returning request_id
)
delete from public.employee_job_change_requests
where id in (select id from target) and (select count(*) from removed_events)>=0
returning id,job_title;
