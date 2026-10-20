create function private.guard_hr_record_edit()returns trigger language plpgsql security definer set search_path=pg_catalog,public,private as $$
begin
 if new.title_id is distinct from old.title_id and old.profile_id is not null and exists(select 1 from public.employee_job_assignments a join private.hr_titles t on t.id=new.title_id where a.profile_id=old.profile_id and a.job_description_id is distinct from t.job_description_id)then
  raise exception 'حدّث ربط الوصف في مكتبة الوظائف أولًا، ثم حدّث المسمى هنا للحفاظ على تطابق الملف';
 end if;
 return new;
end $$;
revoke all on function private.guard_hr_record_edit()from public,anon,authenticated;
create trigger hr_employee_title_consistency before update of title_id on private.hr_employees for each row execute function private.guard_hr_record_edit();
