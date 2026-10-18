-- Keep internal approval validation out of ordinary authenticated draft saves.
-- PostgreSQL may evaluate boolean predicates in any order; use PL/pgSQL branches.
CREATE OR REPLACE FUNCTION private.prepare_job_description()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare v_uid uuid:=(select auth.uid());v_admin boolean:=private.is_admin();
  v_draft boolean:=private.can_job_stage('DRAFT');v_final boolean:=private.can_job_stage('FINAL_REVIEW');
  v_publish boolean:=private.can_job_stage('PUBLISH');
begin
 if v_uid is null then raise exception 'Authentication required'; end if;
 new.job_code:=upper(btrim(new.job_code));new.title:=btrim(new.title);new.purpose:=btrim(new.purpose);
 if tg_op='INSERT' then
   if not v_draft then raise exception 'Draft creation permission required' using errcode='42501'; end if;
   new.created_by:=v_uid;new.updated_by:=v_uid;new.created_at:=now();new.updated_at:=now();new.revision:=1;
   new.status:='DRAFT';new.final_reviewed_at:=null;new.final_reviewed_by:=null;
 else
   if old.status='MANAGER_APPROVED' and new.status='MANAGER_APPROVED' and (new.title,new.purpose,new.content) is distinct from (old.title,old.purpose,old.content) then
     new.status:='DRAFT';new.final_reviewed_at:=null;new.final_reviewed_by:=null;new.manager_approved_by:=null;new.manager_approved_at:=null;
   end if;
   new.created_by:=old.created_by;new.created_at:=old.created_at;new.updated_by:=v_uid;new.updated_at:=now();new.revision:=old.revision+1;
   if old.status in ('IN_REVIEW','CHANGES_REQUESTED') and old.reviewer_id=v_uid and not (v_draft or v_final or v_publish) then
     new.job_code:=old.job_code;new.reviewer_id:=old.reviewer_id;
     if new.status not in ('IN_REVIEW','CHANGES_REQUESTED','MANAGER_APPROVED') then raise exception 'Reviewer cannot publish or archive'; end if;
     if new.status='CHANGES_REQUESTED' and char_length(btrim(coalesce(new.review_note,'')))<2 then raise exception 'A review note is required'; end if;
     if new.status='MANAGER_APPROVED' then new.manager_approved_by:=v_uid;new.manager_approved_at:=now(); end if;
   else
     if not (v_draft or v_final or v_publish) then raise exception 'Job stage permission required' using errcode='42501'; end if;
     if (new.job_code,new.title,new.family,new.job_level,new.reports_to_title,new.purpose,new.content,new.reviewer_id)
         is distinct from (old.job_code,old.title,old.family,old.job_level,old.reports_to_title,old.purpose,old.content,old.reviewer_id)
       and not (v_draft or (v_final and old.status='MANAGER_APPROVED')) then
       raise exception 'Draft or final review permission required' using errcode='42501';
     end if;
     if new.status is distinct from old.status then
       if new.status='IN_REVIEW' and v_draft and old.status in ('DRAFT','CHANGES_REQUESTED','PUBLISHED') then
         new.final_reviewed_at:=null;new.final_reviewed_by:=null;
       elsif new.status='CHANGES_REQUESTED' and (v_final or v_publish) and old.status in ('IN_REVIEW','MANAGER_APPROVED') then
         new.final_reviewed_at:=null;new.final_reviewed_by:=null;
       elsif new.status='MANAGER_APPROVED' and old.status in ('PUBLISHED','DRAFT') and v_draft then
         if not private.employee_change_covers_job(new,old) then raise exception 'Stage transition is not permitted' using errcode='42501'; end if;
         select r.manager_id,r.manager_decided_at into new.manager_approved_by,new.manager_approved_at from public.employee_job_change_requests r where r.job_description_id=new.id and r.status='APPLIED' and r.applied_revision=old.revision+1;
       elsif new.status='MANAGER_APPROVED' and (old.reviewer_id=v_uid or v_admin) and old.status in ('IN_REVIEW','CHANGES_REQUESTED') then
         new.manager_approved_by:=v_uid;new.manager_approved_at:=now();
       elsif new.status='DRAFT' and v_draft then
         new.final_reviewed_at:=null;new.final_reviewed_by:=null;
       elsif new.status='PUBLISHED' and v_publish and old.status='MANAGER_APPROVED' and old.final_reviewed_at is not null then
         new.published_by:=v_uid;new.published_at:=now();
         new.published_snapshot:=jsonb_build_object('job_code',new.job_code,'title',new.title,'family',new.family,
           'job_level',new.job_level,'reports_to_title',new.reports_to_title,'purpose',new.purpose,
           'content',new.content,'revision',new.revision,'published_at',now());
       elsif new.status='ARCHIVED' and v_publish then null;
       else raise exception 'Stage transition is not permitted' using errcode='42501'; end if;
     end if;
   end if;
   if new.final_reviewed_at is distinct from old.final_reviewed_at and new.final_reviewed_at is not null then
     if not v_final or old.status<>'MANAGER_APPROVED' then raise exception 'Final review permission required' using errcode='42501'; end if;
     if exists(select 1 from public.job_description_change_requests where job_description_id=old.id and status='PENDING' and action<>'COMMENT') then raise exception 'Resolve pending proposals first'; end if;
     new.final_reviewed_at:=now();new.final_reviewed_by:=v_uid;
   end if;
 end if;
 return new;
end $function$
;
CREATE OR REPLACE FUNCTION private.guard_job_authoring()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
begin
 if tg_op='INSERT' or (new.reports_to_job_id,new.reference_profile_id,new.reviewer_mode,new.reviewer_override_reason) is distinct from
  (old.reports_to_job_id,old.reference_profile_id,old.reviewer_mode,old.reviewer_override_reason) then
  if not private.can_job_stage('DRAFT') then raise exception 'صلاحية إعداد الوصف مطلوبة' using errcode='42501'; end if;
  if new.reviewer_mode='override' and (not private.is_admin() or char_length(btrim(coalesce(new.reviewer_override_reason,'')))<2) then
   raise exception 'تعيين البديل يتطلب مسؤول النظام وسببًا واضحًا' using errcode='42501';
  end if;
  if new.reports_to_job_id=new.id then raise exception 'لا يمكن أن تتبع الوظيفة نفسها'; end if;
 end if;
 if tg_op='UPDATE' then
  if old.final_reviewed_at is not null and new.status='MANAGER_APPROVED' and (new.title,new.purpose,new.content) is distinct from (old.title,old.purpose,old.content) then
   if not private.employee_change_covers_job(new,old) then raise exception 'أعد الوصف للتعديل قبل تغيير محتوى تمت مراجعته نهائيًا'; end if;
  end if;
  if old.status='PUBLISHED' and new.status='PUBLISHED' and (new.title,new.purpose,new.content) is distinct from (old.title,old.purpose,old.content) then
   raise exception 'افتح مسودة إصدار جديد قبل تعديل الوصف المنشور';
  end if;
  if new.status='IN_REVIEW' and old.status is distinct from new.status then
   new.reviewer_id:=private.resolve_job_direct_manager(new);
   new.submitted_at:=clock_timestamp();new.manager_approved_at:=null;new.manager_approved_by:=null;
  end if;
  if new.status='CHANGES_REQUESTED' and old.status is distinct from new.status and char_length(btrim(coalesce(new.review_note,'')))<2 then
   raise exception 'سبب الإعادة للتعديل مطلوب';
  end if;
 end if;
 return new;
end $function$
;
