-- Preserve all historical rows; retire the exemption mechanism without deleting data.
alter table private.hr_job_ack_exemptions rename to job_ack_exemption_revocations;
alter table private.job_ack_exemption_revocations
 add column revoked_at timestamptz not null default now(),
 add column revocation_reason text not null default 'تصحيح معتمد: إقرار الموظف مطلوب للجميع ولا يوجد إعفاء إداري';
revoke all on private.job_ack_exemption_revocations from public,anon,authenticated;
-- Empty compatibility view. CHECK OPTION rejects any future exemption insertion.
create view private.hr_job_ack_exemptions with (security_invoker=true) as
 select profile_id,job_description_id,job_revision,import_id,reason,created_at
 from private.job_ack_exemption_revocations where false with local check option;
revoke all on private.hr_job_ack_exemptions from public,anon,authenticated;
comment on view private.hr_job_ack_exemptions is 'Retired: employee consent cannot be waived. Historical records retained privately.';
-- Recompile legacy readers/guards against the empty compatibility view.
do $$
declare definition text;
begin
 for definition in
 select pg_get_functiondef(p.oid) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname in ('private','public') and p.prokind='f'
 and p.prosrc like '%hr_job_ack_exemptions%'
 loop execute definition; end loop;
end $$;
-- Personal requirements are scoped by the existing active-account private reader.
create or replace function public.job_administrative_exemptions()
returns jsonb language sql security invoker set search_path=pg_catalog,private
as $$select private.hr_job_ack_exemptions()$$;
revoke all on function public.job_administrative_exemptions() from public,anon;
grant execute on function public.job_administrative_exemptions() to authenticated;
