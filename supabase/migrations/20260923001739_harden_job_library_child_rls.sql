begin;

-- Keep child-table visibility explicitly aligned with the job description access model.
-- This avoids relying only on the parent table's RLS side effect inside an EXISTS query.

drop policy if exists job_description_versions_select_policy
  on public.job_description_versions;

create policy job_description_versions_select_policy
  on public.job_description_versions
  for select
  to authenticated
  using (
    private.job_library_role() = 'admin'
    or exists (
      select 1
      from public.job_descriptions j
      where j.id = job_description_versions.job_description_id
        and (
          j.reviewer_id = (select auth.uid())
          or private.can_view_published_job(j.id)
        )
    )
  );

drop policy if exists job_description_forms_select_policy
  on public.job_description_forms;

create policy job_description_forms_select_policy
  on public.job_description_forms
  for select
  to authenticated
  using (
    private.job_library_role() = 'admin'
    or exists (
      select 1
      from public.job_descriptions j
      where j.id = job_description_forms.job_description_id
        and (
          j.reviewer_id = (select auth.uid())
          or private.can_view_published_job(j.id)
        )
    )
  );

commit;
