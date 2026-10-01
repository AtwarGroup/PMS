-- One-time republication explicitly authorized by the system owner.
-- Only KPI configuration changes enter previously published snapshots.
-- Existing grants, policies and normal workflow permissions are unchanged.
lock table public.job_descriptions in access exclusive mode;
alter table public.job_descriptions disable trigger job_descriptions_prepare;
create function private.republish_kpi_snapshot_ack_once() returns trigger language plpgsql
set search_path=pg_catalog,public,private as $ack$
declare a record;
begin
 if new.status='DRAFT' and new.published_snapshot is distinct from old.published_snapshot then
  for a in select profile_id from public.employee_job_assignments where job_description_id=new.id loop
   perform private.ensure_job_workflow_task(new,'EMPLOYEE_ACK',new.published_snapshot->>'revision',a.profile_id);
  end loop;
 end if;
 return new;
end $ack$;
create trigger republish_kpi_snapshot_ack_once after update on public.job_descriptions
for each row execute function private.republish_kpi_snapshot_ack_once();
do $republish$
declare j public.job_descriptions%rowtype; actor uuid; next_snapshot jsonb; next_status text;
 a record; republished_count integer:=0;
begin
 select p.id into actor from public.job_stage_owners s join public.profiles p on p.id=s.profile_id
 where s.stage='PUBLISH' and p.role='admin' and p.active and p.status='active';
 if actor is null then raise exception 'Active publication owner required'; end if;
 perform set_config('request.jwt.claim.sub',actor::text,true);
 for j in select * from public.job_descriptions where published_snapshot is not null and status<>'ARCHIVED' for update loop
  if jsonb_array_length(j.content->'kpis')<>jsonb_array_length(j.published_snapshot->'content'->'kpis')
   or (select jsonb_agg(jsonb_build_array(coalesce(k->>'name',k->>'text'),coalesce(k->>'target',''),coalesce(k->>'measure','')) order by n)
       from jsonb_array_elements(j.content->'kpis') with ordinality t(k,n))
   is distinct from (select jsonb_agg(jsonb_build_array(coalesce(k->>'name',k->>'text'),coalesce(k->>'target',''),coalesce(k->>'measure','')) order by n)
       from jsonb_array_elements(j.published_snapshot->'content'->'kpis') with ordinality t(k,n))
   then raise exception 'Published indicator mismatch: %',j.job_code; end if;
  if (select sum((k->>'weight')::numeric) from jsonb_array_elements(j.content->'kpis') k)<>100
   or exists(select 1 from jsonb_array_elements(j.content->'kpis') k where nullif(k->>'source','') is null or nullif(k->>'unit','') is null or jsonb_array_length(k->'scale')<>5)
   then raise exception 'Incomplete KPI configuration: %',j.job_code; end if;
  next_snapshot:=jsonb_set(j.published_snapshot,'{content,kpis}',j.content->'kpis')
    ||jsonb_build_object('revision',j.revision+1,'published_at',now());
  next_status:=case when (j.content-'kpis')=((j.published_snapshot->'content')-'kpis')
    and j.title=j.published_snapshot->>'title' and j.purpose=j.published_snapshot->>'purpose'
    and coalesce(j.family,'')=coalesce(j.published_snapshot->>'family','')
    and coalesce(j.job_level,'')=coalesce(j.published_snapshot->>'job_level','')
    and coalesce(j.reports_to_title,'')=coalesce(j.published_snapshot->>'reports_to_title','')
    then 'PUBLISHED' else j.status end;
  update public.job_descriptions set published_snapshot=next_snapshot,status=next_status,
    published_at=now(),published_by=actor,updated_at=now(),updated_by=actor,revision=j.revision+1,
    review_note=concat_ws(chr(10),nullif(review_note,''),'إعادة نشر المؤشرات المحدّثة للأوصاف المنشورة سابقًا بتوجيه صريح من صاحب النظام دون إعادة الموافقات؛ أي تعديلات أخرى تبقى في المسودة.')
   where id=j.id returning * into j;
  republished_count:=republished_count+1;
 end loop;
 if republished_count<>9 then raise exception 'Expected 9 previously published jobs, got %',republished_count; end if;
end $republish$;
alter table public.job_descriptions enable trigger job_descriptions_prepare;
drop trigger republish_kpi_snapshot_ack_once on public.job_descriptions;
drop function private.republish_kpi_snapshot_ack_once();
