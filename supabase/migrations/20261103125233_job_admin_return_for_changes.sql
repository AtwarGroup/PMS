create or replace function public.return_job_description_for_changes(p_job_id uuid,p_expected_revision integer,p_reason text)
returns public.job_descriptions language plpgsql security definer set search_path='pg_catalog','public','private' as $function$
begin
 perform private.require_module('job_library');
 declare j public.job_descriptions%rowtype;
 begin
  if not private.current_user_is_active() then raise exception 'حساب نشط مطلوب' using errcode='42501'; end if;
  select * into j from public.job_descriptions where id=p_job_id for update;
  if not found then raise exception 'الوصف غير متاح'; end if;
  if not (
   (j.status='IN_REVIEW' and (j.reviewer_id=(select auth.uid()) or exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin')))
   or (j.status='MANAGER_APPROVED' and (private.can_job_stage('FINAL_REVIEW') or private.can_job_stage('PUBLISH')))
  ) then raise exception 'لا تملك صلاحية إعادة هذا الوصف' using errcode='42501'; end if;
  if j.revision<>p_expected_revision then raise exception 'عدّل مستخدم آخر الوصف. أعد تحميل النسخة' using errcode='PT409'; end if;
  if char_length(btrim(coalesce(p_reason,'')))<2 then raise exception 'سبب الإعادة مطلوب'; end if;
  update public.job_descriptions set status='CHANGES_REQUESTED',review_note=btrim(p_reason),final_reviewed_at=null,final_reviewed_by=null where id=p_job_id returning * into j;
  return j;
 end;
end $function$;
revoke all on function public.return_job_description_for_changes(uuid,integer,text) from public,anon;
grant execute on function public.return_job_description_for_changes(uuid,integer,text) to authenticated;
