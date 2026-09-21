-- Cover foreign-key join columns reported by the Supabase performance advisor.
-- These indexes are additive and safe to apply repeatedly.

create index if not exists form_library_created_by_idx
  on public.form_library(created_by);
create index if not exists form_library_updated_by_idx
  on public.form_library(updated_by);
create index if not exists job_change_requests_admin_decision_by_idx
  on public.job_description_change_requests(admin_decision_by);
create index if not exists job_description_forms_form_id_idx
  on public.job_description_forms(form_id);
create index if not exists job_descriptions_created_by_idx
  on public.job_descriptions(created_by);
create index if not exists job_descriptions_manager_approved_by_idx
  on public.job_descriptions(manager_approved_by);
create index if not exists job_descriptions_published_by_idx
  on public.job_descriptions(published_by);
create index if not exists job_descriptions_updated_by_idx
  on public.job_descriptions(updated_by);
