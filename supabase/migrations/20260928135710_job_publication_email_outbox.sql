begin;

create table public.job_publication_email_outbox (
  id uuid primary key default gen_random_uuid(),
  event_key text not null unique,
  job_description_id uuid not null references public.job_descriptions(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  recipient_email text not null,
  job_revision integer not null,
  payload jsonb not null,
  status text not null default 'pending' check (status in ('pending','processing','sent','failed')),
  attempts integer not null default 0,
  next_attempt_at timestamptz not null default now(),
  provider_message_id text,
  last_error text,
  created_at timestamptz not null default now(),
  processed_at timestamptz,
  updated_at timestamptz not null default now()
);
create index job_publication_email_outbox_ready_idx on public.job_publication_email_outbox(status,next_attempt_at,created_at);
alter table public.job_publication_email_outbox enable row level security;
revoke all on public.job_publication_email_outbox from public, anon, authenticated;
grant select, insert, update on public.job_publication_email_outbox to service_role;

create function private.queue_job_publication_email(p_job public.job_descriptions,p_profile_id uuid)
returns void language plpgsql security definer set search_path='pg_catalog','public','private'
as $$
declare v_profile public.profiles%rowtype; v_revision integer;
begin
  if p_job.status<>'PUBLISHED' or p_job.published_snapshot is null then return; end if;
  select * into v_profile from public.profiles where id=p_profile_id and active=true and status='active';
  if not found or nullif(btrim(coalesce(v_profile.email,'')),'') is null then return; end if;
  v_revision:=coalesce((p_job.published_snapshot->>'revision')::integer,p_job.revision,1);
  insert into public.job_publication_email_outbox(event_key,job_description_id,profile_id,recipient_email,job_revision,payload)
  values (
    p_job.id::text||':'||v_revision::text||':'||v_profile.id::text,
    p_job.id,v_profile.id,lower(btrim(v_profile.email)),v_revision,
    jsonb_build_object('employee_name',v_profile.full_name,'job_snapshot',p_job.published_snapshot)
  ) on conflict(event_key) do nothing;
end $$;
revoke all on function private.queue_job_publication_email(public.job_descriptions,uuid) from public,anon,authenticated;

create function private.queue_job_publication_on_publish()
returns trigger language plpgsql security definer set search_path='pg_catalog','public','private'
as $$
declare v_profile_id uuid;
begin
  if old.status is distinct from 'PUBLISHED' and new.status='PUBLISHED' then
    for v_profile_id in select profile_id from public.employee_job_assignments where job_description_id=new.id loop
      perform private.queue_job_publication_email(new,v_profile_id);
    end loop;
  end if;
  return new;
end $$;
revoke all on function private.queue_job_publication_on_publish() from public,anon,authenticated;
create trigger job_publication_email_queue after update of status on public.job_descriptions
for each row execute function private.queue_job_publication_on_publish();

create function private.queue_job_publication_on_assignment()
returns trigger language plpgsql security definer set search_path='pg_catalog','public','private'
as $$
declare v_job public.job_descriptions%rowtype;
begin
  if tg_op='UPDATE' and old.job_description_id=new.job_description_id then return new; end if;
  select * into v_job from public.job_descriptions where id=new.job_description_id;
  perform private.queue_job_publication_email(v_job,new.profile_id);
  return new;
end $$;
revoke all on function private.queue_job_publication_on_assignment() from public,anon,authenticated;
create trigger job_assignment_publication_email_queue after insert or update of job_description_id on public.employee_job_assignments
for each row execute function private.queue_job_publication_on_assignment();

-- Existing published assignments receive one message for their current revision.
do $$ declare v_row record; begin
  for v_row in select j as job,a.profile_id from public.employee_job_assignments a
    join public.job_descriptions j on j.id=a.job_description_id where j.status='PUBLISHED' loop
    perform private.queue_job_publication_email(v_row.job,v_row.profile_id);
  end loop;
end $$;

commit;
