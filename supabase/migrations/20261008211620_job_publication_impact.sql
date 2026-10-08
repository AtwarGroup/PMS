-- Narrow privileged aggregation: publishers need complete counts even without ASSIGN access.
create function private.job_publication_impact(p_job_id uuid,p_expected_revision integer)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare j public.job_descriptions%rowtype; total bigint; active_count bigint;
begin
 if auth.uid() is null or not private.current_user_is_active() or not private.can_job_stage('PUBLISH') then
  raise exception 'صلاحية الاعتماد والنشر مطلوبة' using errcode='42501';
 end if;
 select * into j from public.job_descriptions where id=p_job_id;
 if not found then raise exception 'الوصف غير موجود';end if;
 if j.revision<>p_expected_revision then raise exception 'تغير الوصف؛ حدّث الصفحة وراجع أثر التعديل' using errcode='40001';end if;
 select count(*),count(*) filter(where p.active=true and p.status='active') into total,active_count
 from public.employee_job_assignments a join public.profiles p on p.id=a.profile_id where a.job_description_id=j.id;
 return jsonb_build_object('revision',j.revision,'linked_count',total,'active_count',active_count,
 'inactive_count',total-active_count,'published_revision',j.published_snapshot->'revision');
end $$;
revoke all on function private.job_publication_impact(uuid,integer) from public,anon;
grant execute on function private.job_publication_impact(uuid,integer) to authenticated;
create function public.get_job_publication_impact(p_job_id uuid,p_expected_revision integer)
returns jsonb language sql security invoker set search_path=pg_catalog,public,private as $$
 select private.job_publication_impact(p_job_id,p_expected_revision);
$$;
revoke all on function public.get_job_publication_impact(uuid,integer) from public,anon;
grant execute on function public.get_job_publication_impact(uuid,integer) to authenticated;
