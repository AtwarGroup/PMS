begin;

-- تاريخا المهمة مملوكان لمن أنشأها، بصرف النظر عن رتبة الموظف المكلّف بها.
create or replace function private.enforce_task_schedule_owner()
returns trigger
language plpgsql
security invoker
set search_path = 'pg_catalog','public','private'
as $$
declare
  v_uid uuid := (select auth.uid());
  v_role text;
begin
  if old.start_date is not distinct from new.start_date
     and old.due_date is not distinct from new.due_date then
    return new;
  end if;

  select p.role into v_role
  from public.profiles p
  where p.id=v_uid and p.active=true and p.status='active';

  if v_role='admin' or old.creator_id=v_uid then return new; end if;

  raise exception 'ATWAR_TASK_DATE_FORBIDDEN: only the task creator may change its schedule'
    using errcode='42501';
end
$$;

revoke all on function private.enforce_task_schedule_owner() from public,anon,authenticated;
drop trigger if exists enforce_task_schedule_owner_before_update on public.tasks;
create trigger enforce_task_schedule_owner_before_update
before update of start_date,due_date on public.tasks
for each row execute function private.enforce_task_schedule_owner();

create table if not exists public.job_description_acknowledgements (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete restrict,
  manager_id uuid references public.profiles(id) on delete set null,
  job_description_id uuid not null references public.job_descriptions(id) on delete restrict,
  job_revision integer not null check (job_revision>0),
  job_snapshot jsonb not null,
  employee_name_snapshot text not null,
  employee_email_snapshot text not null,
  manager_name_snapshot text,
  manager_email_snapshot text,
  acknowledgement_text text not null,
  acknowledgement_version text not null default 'ATWAR-JD-ACK-1',
  accepted_at timestamptz not null default now(),
  accepted_user_agent text,
  pdf_path text,
  pdf_sha256 text,
  email_status text not null default 'pending'
    check (email_status in ('pending','processing','sent','failed')),
  email_provider_id text,
  email_last_error text,
  emailed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(profile_id,job_description_id,job_revision),
  constraint job_ack_pdf_hash_check check (pdf_sha256 is null or pdf_sha256 ~ '^[0-9a-f]{64}$')
);

create index if not exists job_ack_profile_idx
  on public.job_description_acknowledgements(profile_id,accepted_at desc);
create index if not exists job_ack_manager_idx
  on public.job_description_acknowledgements(manager_id,accepted_at desc);
create index if not exists job_ack_job_idx
  on public.job_description_acknowledgements(job_description_id,job_revision);

alter table public.job_description_acknowledgements enable row level security;
revoke all on table public.job_description_acknowledgements from public,anon,authenticated;
grant select on table public.job_description_acknowledgements to authenticated;

drop policy if exists job_ack_select_policy on public.job_description_acknowledgements;
create policy job_ack_select_policy on public.job_description_acknowledgements
for select to authenticated using (
  profile_id=(select auth.uid())
  or manager_id=(select auth.uid())
  or private.job_library_role()='admin'
);

create or replace function public.acknowledge_job_description(
  p_job_description_id uuid,
  p_user_agent text default null
)
returns setof public.job_description_acknowledgements
language plpgsql
security definer
set search_path='pg_catalog','public','private'
as $$
declare
  v_uid uuid := (select auth.uid());
  v_profile public.profiles%rowtype;
  v_manager public.profiles%rowtype;
  v_job public.job_descriptions%rowtype;
  v_revision integer;
  v_statement constant text := 'أقر بأنني اطلعت على الوصف الوظيفي المعتمد، وأوافق على تنفيذ المهام والمسؤوليات والصلاحيات ومؤشرات الأداء الواردة فيه، وأتحمل مسؤولية الالتزام بها ضمن الأنظمة والسياسات والتوجيهات المعتمدة.';
  v_id uuid;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;

  select * into v_profile from public.profiles
  where id=v_uid and active=true and status='active';
  if not found then raise exception 'Active employee profile is required'; end if;

  if not private.can_view_published_job(p_job_description_id) then
    raise exception 'The published job description is not assigned to this employee'
      using errcode='42501';
  end if;

  select * into v_job from public.job_descriptions
  where id=p_job_description_id and published_at is not null and published_snapshot is not null;
  if not found then raise exception 'Published job description not found'; end if;

  begin
    v_revision:=coalesce(nullif(v_job.published_snapshot->>'revision','')::integer,v_job.revision);
  exception when invalid_text_representation then
    v_revision:=v_job.revision;
  end;
  v_revision:=greatest(coalesce(v_revision,1),1);

  if v_profile.manager_id is not null then
    select * into v_manager from public.profiles where id=v_profile.manager_id;
  end if;

  insert into public.job_description_acknowledgements(
    profile_id,manager_id,job_description_id,job_revision,job_snapshot,
    employee_name_snapshot,employee_email_snapshot,
    manager_name_snapshot,manager_email_snapshot,
    acknowledgement_text,accepted_user_agent
  ) values (
    v_uid,v_profile.manager_id,v_job.id,v_revision,v_job.published_snapshot,
    coalesce(nullif(btrim(v_profile.full_name),''),v_profile.email),lower(btrim(v_profile.email)),
    nullif(btrim(v_manager.full_name),''),lower(nullif(btrim(v_manager.email),'')),
    v_statement,nullif(left(coalesce(p_user_agent,''),500),'')
  )
  on conflict(profile_id,job_description_id,job_revision) do nothing
  returning id into v_id;

  if v_id is null then
    select id into v_id from public.job_description_acknowledgements
    where profile_id=v_uid and job_description_id=v_job.id and job_revision=v_revision;
  end if;

  return query select * from public.job_description_acknowledgements where id=v_id;
end
$$;

revoke all on function public.acknowledge_job_description(uuid,text) from public,anon;
grant execute on function public.acknowledge_job_description(uuid,text) to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('job-acknowledgements','job-acknowledgements',false,10485760,array['application/pdf'])
on conflict(id) do update set
  public=false,
  file_size_limit=excluded.file_size_limit,
  allowed_mime_types=excluded.allowed_mime_types;

comment on table public.job_description_acknowledgements is
  'Immutable employee acknowledgements tied to the exact published job-description revision.';

commit;
