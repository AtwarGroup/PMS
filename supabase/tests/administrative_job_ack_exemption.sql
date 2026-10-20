begin;
do $qa$
declare w private.hr_job_ack_exemptions%rowtype;j public.job_descriptions%rowtype;n integer;tasks_before integer;future_revision integer;
begin
 select * into strict w from private.hr_job_ack_exemptions order by profile_id limit 1;
 select * into strict j from public.job_descriptions where id=w.job_description_id;
 select count(*)into n from public.job_publication_email_outbox;select count(*)into tasks_before from public.tasks;
 perform private.queue_job_publication_email(j,w.profile_id);
 perform private.ensure_job_workflow_task(j,'EMPLOYEE_ACK',w.job_revision::text,w.profile_id);
 if(select count(*)from public.job_publication_email_outbox)<>n or(select count(*)from public.tasks)<>tasks_before then raise exception 'Administrative revision created mail or acknowledgement task';end if;
 future_revision:=w.job_revision+1000;j.published_snapshot:=jsonb_set(j.published_snapshot,'{revision}',to_jsonb(future_revision));
 perform private.queue_job_publication_email(j,w.profile_id);
 if not exists(select 1 from public.job_publication_email_outbox where profile_id=w.profile_id and job_description_id=j.id and job_revision=future_revision)then raise exception 'Exemption incorrectly suppressed future revision';end if;
end $qa$;
select set_config('request.jwt.claims',jsonb_build_object('sub',p.id,'role','authenticated')::text,true)from public.profiles p join private.hr_employees e on e.profile_id=p.id where p.role='employee'and not exists(select 1 from private.hr_employees child where child.manager_id=e.id)order by p.id limit 1;
set local role authenticated;
do $client$
declare rows jsonb;w jsonb;denied boolean:=false;
begin
 rows:=public.job_administrative_exemptions();
 if jsonb_array_length(rows)<>1 or rows->0->>'profile_id'<>auth.uid()::text then raise exception 'Exemption visibility leaked beyond employee';end if;
 w:=rows->0;
 begin perform public.acknowledge_job_description((w->>'job_description_id')::uuid,'QA administrative exemption');exception when raise_exception then if sqlerrm like '%لا يتطلب%'then denied:=true;else raise;end if;end;
 if not denied then raise exception 'Administrative exemption impersonated employee acceptance';end if;
end $client$;
rollback;
