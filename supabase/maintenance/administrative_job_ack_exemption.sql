create table private.hr_job_ack_exemptions(profile_id uuid not null references public.profiles(id),job_description_id uuid not null references public.job_descriptions(id),job_revision integer not null,import_id uuid not null references private.hr_imports(id),reason text not null,created_at timestamptz not null default now(),primary key(profile_id,job_description_id,job_revision));
alter table private.hr_job_ack_exemptions enable row level security;
revoke all on private.hr_job_ack_exemptions from public,anon,authenticated;
create policy hr_internal_only on private.hr_job_ack_exemptions for all to authenticated using(false)with check(false);
insert into private.hr_job_ack_exemptions(profile_id,job_description_id,job_revision,import_id,reason)
select e.profile_id,j.id,(j.published_snapshot->>'revision')::integer,i.id,'تحديث إداري للمرحلة الثانية بتوجيه الإدارة؛ لا يتطلب إقرار الموظف أو إرسال بريد.'
from private.hr_employees e join public.employee_job_assignments a on a.profile_id=e.profile_id join public.job_descriptions j on j.id=a.job_description_id cross join private.hr_imports i
where i.source_name='قاعدة البيانات.xlsx'and i.effective_from='2026-10-20'and j.published_snapshot is not null;
create function private.hr_job_ack_exemptions()returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,private as $$
begin
 if not private.current_user_is_active()then raise exception 'Active account required'using errcode='42501';end if;
 return(select coalesce(jsonb_agg(jsonb_build_object('profile_id',w.profile_id,'job_description_id',w.job_description_id,'job_revision',w.job_revision,'reason',w.reason)),'[]')from private.hr_job_ack_exemptions w where w.profile_id=auth.uid()or private.is_admin()or private.manages_user(w.profile_id));
end $$;
revoke all on function private.hr_job_ack_exemptions()from public,anon,authenticated;
grant execute on function private.hr_job_ack_exemptions()to authenticated;
create function public.job_administrative_exemptions()returns jsonb language sql security invoker set search_path=pg_catalog,private as $$select private.hr_job_ack_exemptions()$$;
revoke all on function public.job_administrative_exemptions()from public,anon;
grant execute on function public.job_administrative_exemptions()to authenticated;
create function private.guard_exempted_job_ack()returns trigger language plpgsql security definer set search_path=pg_catalog,public,private as $$
begin
 if exists(select 1 from private.hr_job_ack_exemptions where profile_id=new.profile_id and job_description_id=new.job_description_id and job_revision=new.job_revision)then raise exception 'هذا التحديث الإداري لا يتطلب إعادة إقرار أو إرسال بريد';end if;
 return new;
end $$;
revoke all on function private.guard_exempted_job_ack()from public,anon,authenticated;
create trigger administrative_job_ack_exemption before insert on public.job_description_acknowledgements for each row execute function private.guard_exempted_job_ack();
comment on table private.hr_job_ack_exemptions is 'Administrative waiver for one exact published revision. Never impersonates employee acceptance; future revisions follow the normal acknowledgement workflow.';
