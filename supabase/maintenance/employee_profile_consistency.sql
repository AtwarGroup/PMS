-- Keep existing account editors from silently diverging from the employee master.
create function private.guard_hr_linked_profile()returns trigger language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare e record;
begin
 select h.*,d.name department,t.title,m.profile_id manager_profile into e from private.hr_employees h join private.hr_departments d on d.id=h.department_id join private.hr_titles t on t.id=h.title_id left join private.hr_employees m on m.id=h.manager_id where h.profile_id=new.id;
 if not found then return new;end if;
 if(new.full_name,new.employee_code,new.department,new.job_title,new.join_date,new.manager_id)is distinct from(e.full_name,e.employee_code,e.department,e.title,e.join_date,e.manager_profile)then raise exception 'عدّل بيانات الموظف والهيكل من سجل الموظفين للحفاظ على تطابق البيانات' using errcode='23514';end if;
 return new;
end $$;
revoke all on function private.guard_hr_linked_profile()from public,anon,authenticated;
create trigger profiles_hr_consistency before update of full_name,employee_code,department,job_title,join_date,manager_id on public.profiles for each row execute function private.guard_hr_linked_profile();

-- A later explicitly authorized account creation can attach to the existing record.
-- This hook creates neither Auth users nor invitations.
create function private.prepare_hr_profile_activation()returns trigger language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare e record;v_service boolean:=coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb->>'role'='service_role';
begin
 select h.*,d.name department,t.title,m.profile_id manager_profile into e from private.hr_employees h join private.hr_departments d on d.id=h.department_id join private.hr_titles t on t.id=h.title_id left join private.hr_employees m on m.id=h.manager_id where lower(h.email)=lower(new.email) and h.profile_id is null for update of h;
 if not found then return new;end if;
 if not coalesce(private.is_admin() or v_service,false) then raise exception 'Account activation requires administrator authorization'using errcode='42501';end if;
 if not exists(select 1 from auth.users where id=new.id and lower(email)=lower(e.email))then raise exception 'Account email does not match the employee record';end if;
 new.full_name:=e.full_name;new.employee_code:=e.employee_code;new.department:=e.department;new.job_title:=e.title;new.join_date:=e.join_date;new.manager_id:=e.manager_profile;
 if new.role<>'admin' and exists(select 1 from private.hr_employees where manager_id=e.id)then new.role:='manager';end if;
 return new;
end $$;
create function private.attach_hr_profile_activation()returns trigger language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare e private.hr_employees%rowtype;b jsonb;
begin
 select * into e from private.hr_employees where lower(email)=lower(new.email)and profile_id is null for update;
 if not found then return new;end if;
 b:=to_jsonb(e);update private.hr_employees set profile_id=new.id,revision=revision+1,updated_at=now()where id=e.id;
 insert into private.hr_history(employee_id,domain,before_data,after_data,effective_from,actor_id,reason)select id,'records',b,to_jsonb(h),timezone('Asia/Riyadh',now())::date,auth.uid(),'ربط حساب الدخول بسجل الموظف بعد تفعيله إداريًا'from private.hr_employees h where id=e.id;
 update public.profiles p set manager_id=new.id from private.hr_employees h where h.manager_id=e.id and h.profile_id=p.id and p.manager_id is distinct from new.id;
 return new;
end $$;
revoke all on function private.prepare_hr_profile_activation(),private.attach_hr_profile_activation()from public,anon,authenticated;
create trigger profiles_hr_prepare_activation before insert on public.profiles for each row execute function private.prepare_hr_profile_activation();
create trigger profiles_hr_attach_activation after insert on public.profiles for each row execute function private.attach_hr_profile_activation();
