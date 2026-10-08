begin;
create table public.job_publication_schedules (
 id uuid primary key default gen_random_uuid(),job_description_id uuid not null references public.job_descriptions(id) on delete cascade,
 expected_revision integer not null,effective_date date not null,approved_by uuid not null references public.profiles(id),approved_at timestamptz not null default now(),
 status text not null default 'PENDING' check(status in ('PENDING','PUBLISHED','CANCELLED','BLOCKED')),
 released_at timestamptz,cancelled_by uuid references public.profiles(id),note text
);
create unique index job_publication_schedule_open on public.job_publication_schedules(job_description_id) where status in ('PENDING','BLOCKED');
create index job_publication_schedule_due on public.job_publication_schedules(effective_date) where status='PENDING';
alter table public.job_publication_schedules enable row level security;
revoke all on public.job_publication_schedules from public,anon,authenticated;
grant select on public.job_publication_schedules to authenticated;
revoke all on public.job_publication_schedules from anon;
create policy job_schedule_read on public.job_publication_schedules for select to authenticated using (
 private.current_user_is_active() and exists(select 1 from public.job_descriptions j where j.id=job_description_id));

-- The job row is the lock shared by approval, cancellation and scheduled release.
create function private.guard_job_scheduled_release() returns trigger language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare s public.job_publication_schedules%rowtype;
begin
 select * into s from public.job_publication_schedules where job_description_id=old.id and status in ('PENDING','BLOCKED');
 if found and not (s.status='PENDING' and new.status='PUBLISHED' and old.status='MANAGER_APPROVED' and old.revision=s.expected_revision
   and s.effective_date<=(now() at time zone 'Asia/Riyadh')::date and auth.uid()=s.approved_by
   and (to_jsonb(new)-'status'-'updated_by')=(to_jsonb(old)-'status'-'updated_by')) then
  raise exception 'ألغِ جدولة السريان أولًا قبل تغيير الوصف أو دورة مراجعته';
 end if;
 return new;
end $$;
create trigger a_guard_job_scheduled_release before update on public.job_descriptions for each row execute function private.guard_job_scheduled_release();
create function private.finish_job_scheduled_release() returns trigger language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare s public.job_publication_schedules%rowtype;
begin
 if new.status='PUBLISHED' and old.status<>'PUBLISHED' then
  select * into s from public.job_publication_schedules where job_description_id=new.id and status='PENDING';
  if found then
   new.published_snapshot:=new.published_snapshot||jsonb_build_object('effective_date',s.effective_date,'approved_at',s.approved_at,'approved_by',s.approved_by);
   update public.job_publication_schedules set status='PUBLISHED',released_at=now() where id=s.id;
  end if;
 end if;
 return new;
end $$;
create trigger zzz_finish_job_scheduled_release before update on public.job_descriptions for each row execute function private.finish_job_scheduled_release();

create function private.sync_job_schedule_approval_task() returns trigger language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare j public.job_descriptions%rowtype;
begin
 select * into j from public.job_descriptions where id=new.job_description_id;
 if tg_op='INSERT' then perform private.close_job_workflow_tasks(j.id,'PUBLISH');
 elsif new.status='CANCELLED' and old.status in ('PENDING','BLOCKED') and j.status='MANAGER_APPROVED' then
  perform private.ensure_job_workflow_task(j,'PUBLISH','reschedule:'||new.id::text,private.job_stage_owner('PUBLISH'));
 end if;return new;
end $$;
create trigger sync_job_schedule_approval_task after insert or update on public.job_publication_schedules for each row execute function private.sync_job_schedule_approval_task();
revoke all on function private.sync_job_schedule_approval_task() from public,anon,authenticated;

create function private.approve_job_effective_date(p_job_id uuid,p_expected_revision integer,p_effective_date date)
returns public.job_descriptions language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare j public.job_descriptions%rowtype;s public.job_publication_schedules%rowtype;today date:=(now() at time zone 'Asia/Riyadh')::date;
begin
 if auth.uid() is null or not private.current_user_is_active() or not private.can_job_stage('PUBLISH') then raise exception 'صلاحية الاعتماد والنشر مطلوبة' using errcode='42501';end if;
 select * into j from public.job_descriptions where id=p_job_id for update;
 if not found then raise exception 'الوصف غير موجود';end if;
 if p_expected_revision is null or j.revision<>p_expected_revision then raise exception 'تغير الوصف؛ حدّث الصفحة' using errcode='40001';end if;
 if j.status<>'MANAGER_APPROVED' or j.final_reviewed_at is null then raise exception 'أكمل المراجعة النهائية أولًا';end if;
 if p_effective_date is null or p_effective_date<today then raise exception 'تاريخ السريان يجب أن يكون اليوم أو بعده';end if;
 select * into s from public.job_publication_schedules where job_description_id=j.id and status in ('PENDING','BLOCKED');
 if found then
  if s.status='PENDING' and s.expected_revision=j.revision and s.effective_date=p_effective_date and s.approved_by=auth.uid() then return j;end if;
  raise exception 'توجد جدولة قائمة؛ ألغها قبل تغيير موعد السريان';
 end if;
 insert into public.job_publication_schedules(job_description_id,expected_revision,effective_date,approved_by) values(j.id,j.revision,p_effective_date,auth.uid());
 if p_effective_date=today then update public.job_descriptions set status='PUBLISHED' where id=j.id returning * into j;end if;
 return j;
end $$;
create function private.cancel_job_effective_date(p_schedule_id uuid,p_note text) returns void language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare s public.job_publication_schedules%rowtype;
begin
 if auth.uid() is null or not private.current_user_is_active() or not private.can_job_stage('PUBLISH') then raise exception 'صلاحية الاعتماد والنشر مطلوبة' using errcode='42501';end if;
 if length(btrim(coalesce(p_note,'')))<2 then raise exception 'اكتب سبب إلغاء الجدولة';end if;
 select * into s from public.job_publication_schedules where id=p_schedule_id;
 if not found then raise exception 'الجدولة غير موجودة';end if;
 perform 1 from public.job_descriptions where id=s.job_description_id for update;
 select * into s from public.job_publication_schedules where id=p_schedule_id for update;
 if s.status='CANCELLED' then return;end if;
 if s.status not in ('PENDING','BLOCKED') then raise exception 'بدأ السريان بالفعل؛ افتح مسودة جديدة عند الحاجة للتعديل';end if;
 update public.job_publication_schedules set status='CANCELLED',cancelled_by=auth.uid(),note=btrim(p_note) where id=s.id;
end $$;

create table public.job_periodic_reviews (
 job_description_id uuid primary key references public.job_descriptions(id) on delete cascade,
 reviewer_id uuid not null references public.profiles(id),due_on date not null,interval_months integer not null check(interval_months in (3,6,12)),
 enabled boolean not null default true,revision integer not null default 1,updated_by uuid not null references public.profiles(id),updated_at timestamptz not null default now(),last_checked_at timestamptz
);
create table public.job_periodic_review_events (
 id uuid primary key default gen_random_uuid(),job_description_id uuid not null references public.job_descriptions(id) on delete cascade,
 published_revision integer not null,reviewer_id uuid not null references public.profiles(id),reviewed_at timestamptz not null default now(),
 note text not null,next_due_on date not null
);
alter table public.job_periodic_reviews enable row level security;
alter table public.job_periodic_review_events enable row level security;
revoke all on public.job_periodic_reviews,public.job_periodic_review_events from public,anon,authenticated;
grant select on public.job_periodic_reviews,public.job_periodic_review_events to authenticated;
revoke all on public.job_periodic_reviews,public.job_periodic_review_events from anon;
create policy job_periodic_read on public.job_periodic_reviews for select to authenticated using(private.current_user_is_active() and exists(select 1 from public.job_descriptions j where j.id=job_description_id));
create policy job_periodic_events_read on public.job_periodic_review_events for select to authenticated using(private.current_user_is_active() and exists(select 1 from public.job_descriptions j where j.id=job_description_id));
create index job_periodic_due on public.job_periodic_reviews(due_on) where enabled;
create index job_periodic_events_history on public.job_periodic_review_events(job_description_id,reviewed_at desc);
alter table private.job_workflow_tasks drop constraint job_workflow_tasks_phase_check;
alter table private.job_workflow_tasks add constraint job_workflow_tasks_phase_check check(phase in ('MANAGER_REVIEW','ADMIN_APPROVAL','PUBLISH','EMPLOYEE_ACK','DRAFT_REVISION','PERIODIC_REVIEW'));

create function private.label_job_periodic_review_task() returns trigger language plpgsql security definer set search_path=pg_catalog,public,private as $$
begin
 if new.task_type='job_workflow' and new.legacy_metadata#>>'{job_workflow,phase}'='PERIODIC_REVIEW' then
  new.title:=replace(new.title,'الاطلاع والإقرار بالوصف الوظيفي: ','المراجعة الدورية للوصف الوظيفي: ');
  new.description:='راجع النسخة السارية من الوصف. سجّل «لا توجد تغييرات» أو افتح مسودة جديدة عند الحاجة. لا تُغلق هذه المهمة يدويًا.';
 end if;return new;
end $$;
create trigger label_job_periodic_review_task before insert on public.tasks for each row execute function private.label_job_periodic_review_task();
create function private.sync_job_periodic_review_task() returns trigger language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare j public.job_descriptions%rowtype;
begin
 select * into j from public.job_descriptions where id=new.job_description_id;
 if tg_op='UPDATE' and (old.reviewer_id,old.due_on,old.enabled) is distinct from (new.reviewer_id,new.due_on,new.enabled) then
  perform private.close_job_workflow_tasks(j.id,'PERIODIC_REVIEW',null,null,true);
 end if;
 if new.enabled and new.due_on<=(now() at time zone 'Asia/Riyadh')::date and j.status='PUBLISHED' and j.published_snapshot is not null then
  perform private.ensure_job_workflow_task(j,'PERIODIC_REVIEW',new.due_on::text||':'||new.revision::text,new.reviewer_id);
 end if;return new;
end $$;
create trigger sync_job_periodic_review_task after insert or update on public.job_periodic_reviews for each row execute function private.sync_job_periodic_review_task();
create function private.save_job_periodic_review(p_job_id uuid,p_expected_revision integer,p_reviewer_id uuid,p_due_on date,p_interval_months integer,p_enabled boolean)
returns public.job_periodic_reviews language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare r public.job_periodic_reviews%rowtype;
begin
 if auth.uid() is null or not private.current_user_is_active() or not private.can_job_stage('DRAFT') then raise exception 'صلاحية إعداد الأوصاف مطلوبة' using errcode='42501';end if;
 perform 1 from public.job_descriptions where id=p_job_id and published_snapshot is not null and status<>'ARCHIVED' for update;
 if not found then raise exception 'المراجعة الدورية لوصف له نسخة منشورة وسارية فقط';end if;
 if p_due_on is null or (p_enabled and p_due_on<(now() at time zone 'Asia/Riyadh')::date) or p_interval_months not in (3,6,12) or p_enabled is null then raise exception 'حدد موعدًا من اليوم أو بعده وفترة مراجعة مناسبة';end if;
 if not exists(select 1 from public.profiles where id=p_reviewer_id and active=true and status='active') then raise exception 'حدد مسؤول مراجعة بحساب نشط';end if;
 select * into r from public.job_periodic_reviews where job_description_id=p_job_id for update;
 if p_expected_revision is null or coalesce(r.revision,0)<>p_expected_revision then raise exception 'تغير إعداد المراجعة؛ حدّث الصفحة' using errcode='40001';end if;
 insert into public.job_periodic_reviews(job_description_id,reviewer_id,due_on,interval_months,enabled,updated_by)
 values(p_job_id,p_reviewer_id,p_due_on,p_interval_months,p_enabled,auth.uid()) on conflict(job_description_id) do update
 set reviewer_id=excluded.reviewer_id,due_on=excluded.due_on,interval_months=excluded.interval_months,enabled=excluded.enabled,revision=job_periodic_reviews.revision+1,updated_by=auth.uid(),updated_at=now() returning * into r;
 return r;
end $$;
create function private.complete_job_periodic_review(p_job_id uuid,p_expected_revision integer,p_published_revision integer,p_note text)
returns public.job_periodic_reviews language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare r public.job_periodic_reviews%rowtype;j public.job_descriptions%rowtype;next_date date;
begin
 if auth.uid() is null or not private.current_user_is_active() then raise exception 'حساب نشط مطلوب' using errcode='42501';end if;
 select * into j from public.job_descriptions where id=p_job_id for update;
 select * into r from public.job_periodic_reviews where job_description_id=p_job_id for update;
 if not found or not r.enabled then raise exception 'لا توجد مراجعة دورية مفعّلة';end if;
 if r.reviewer_id<>auth.uid() and not private.can_job_stage('DRAFT') then raise exception 'هذا الإجراء لمسؤول المراجعة' using errcode='42501';end if;
 if p_expected_revision is null or r.revision<>p_expected_revision or p_published_revision is null or (j.published_snapshot->>'revision')::integer<>p_published_revision then raise exception 'تغير الوصف أو المراجعة؛ حدّث الصفحة' using errcode='40001';end if;
 if j.status<>'PUBLISHED' then raise exception 'أكمل دورة التعديل أو السريان القائمة أولًا';end if;
 if length(btrim(coalesce(p_note,'')))<2 then raise exception 'أضف خلاصة المراجعة';end if;
 next_date:=(greatest(r.due_on,(now() at time zone 'Asia/Riyadh')::date)+make_interval(months=>r.interval_months))::date;
 insert into public.job_periodic_review_events(job_description_id,published_revision,reviewer_id,note,next_due_on) values(j.id,p_published_revision,auth.uid(),btrim(p_note),next_date);
 update public.job_periodic_reviews set due_on=next_date,revision=revision+1,updated_by=auth.uid(),updated_at=now() where job_description_id=j.id returning * into r;
 return r;
end $$;

-- Trigger context keeps workflow task mutations within the existing protected path.
create function private.finish_job_periodic_review_task() returns trigger language plpgsql security definer set search_path=pg_catalog,public,private as $$
begin perform private.close_job_workflow_tasks(new.job_description_id,'PERIODIC_REVIEW');return new;end $$;
create trigger finish_job_periodic_review_task after insert on public.job_periodic_review_events for each row execute function private.finish_job_periodic_review_task();

-- A delegated DRAFT owner may retire only periodic workflow tasks through nested protected operations.
do $$ declare d text;begin
 select pg_get_functiondef('private.enforce_task_delete_ownership()'::regprocedure) into d;
 if position('v_task := old;' in d)=0 then raise exception 'Task deletion guard changed';end if;
 d:=replace(d,'v_task := old;',E'v_task := old;\n    if tg_op=\'UPDATE\' and pg_trigger_depth()>1 and old.task_type=\'job_workflow\' and old.legacy_metadata#>>\'{job_workflow,phase}\'=\'PERIODIC_REVIEW\' and private.can_job_stage(\'DRAFT\') then return new;end if;');
 execute d;
end $$;

-- Internal scheduler: only the database owner may invoke it; no browser endpoint.
create function private.process_job_effective_dates() returns integer language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare s public.job_publication_schedules%rowtype;j public.job_descriptions%rowtype;count_released integer:=0;
 original_sub text:=current_setting('request.jwt.claim.sub',true);original_claims text:=current_setting('request.jwt.claims',true);
begin
 for s in select * from public.job_publication_schedules where status='PENDING' and effective_date<=(now() at time zone 'Asia/Riyadh')::date order by effective_date,id loop
  begin
   select * into j from public.job_descriptions where id=s.job_description_id for update;
   select * into s from public.job_publication_schedules where id=s.id for update;
   if s.status<>'PENDING' then continue;end if;
   perform set_config('request.jwt.claim.sub',s.approved_by::text,true);
   perform set_config('request.jwt.claims',jsonb_build_object('sub',s.approved_by,'role','authenticated')::text,true);
   if not private.current_user_is_active() or not private.can_job_stage('PUBLISH') then
    update public.job_publication_schedules set status='BLOCKED',note='تعذر بدء السريان لأن حساب المعتمد أو صلاحيته غير نشط. ألغِ الجدولة وأعد اعتمادها من صاحب الصلاحية الحالي.' where id=s.id;continue;
   end if;
   if j.status<>'MANAGER_APPROVED' or j.final_reviewed_at is null or j.revision<>s.expected_revision then
    update public.job_publication_schedules set status='BLOCKED',note='تغير الوصف أو دورة الموافقة؛ يلزم مراجعة الجدولة.' where id=s.id;continue;
   end if;
   update public.job_descriptions set status='PUBLISHED' where id=j.id;
   count_released:=count_released+1;
  exception when others then
   update public.job_publication_schedules set status='BLOCKED',note='تعذر بدء السريان. راجع مسؤول النظام وألغِ الجدولة لإعادة المحاولة.' where id=s.id;
  end;
 end loop;
 perform set_config('request.jwt.claim.sub',coalesce(original_sub,''),true);perform set_config('request.jwt.claims',coalesce(original_claims,''),true);
 return count_released;
end $$;
create function private.process_job_periodic_reviews() returns integer language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare r public.job_periodic_reviews%rowtype;total integer:=0;original_sub text:=current_setting('request.jwt.claim.sub',true);original_claims text:=current_setting('request.jwt.claims',true);
begin
 for r in select * from public.job_periodic_reviews where enabled and due_on<=(now() at time zone 'Asia/Riyadh')::date loop
  if not exists(select 1 from public.profiles where id=r.updated_by and active=true and status='active') then continue;end if;
  perform set_config('request.jwt.claim.sub',r.updated_by::text,true);perform set_config('request.jwt.claims',jsonb_build_object('sub',r.updated_by,'role','authenticated')::text,true);
  update public.job_periodic_reviews set last_checked_at=now() where job_description_id=r.job_description_id;
  total:=total+1;
 end loop;
 perform set_config('request.jwt.claim.sub',coalesce(original_sub,''),true);perform set_config('request.jwt.claims',coalesce(original_claims,''),true);
 return total;
end $$;

create function public.approve_job_effective_date(p_job_id uuid,p_expected_revision integer,p_effective_date date) returns public.job_descriptions language sql security invoker set search_path=pg_catalog,private as $$select private.approve_job_effective_date(p_job_id,p_expected_revision,p_effective_date)$$;
create function public.cancel_job_effective_date(p_schedule_id uuid,p_note text) returns void language sql security invoker set search_path=pg_catalog,private as $$select private.cancel_job_effective_date(p_schedule_id,p_note)$$;
create function public.save_job_periodic_review(p_job_id uuid,p_expected_revision integer,p_reviewer_id uuid,p_due_on date,p_interval_months integer,p_enabled boolean) returns public.job_periodic_reviews language sql security invoker set search_path=pg_catalog,private as $$select private.save_job_periodic_review(p_job_id,p_expected_revision,p_reviewer_id,p_due_on,p_interval_months,p_enabled)$$;
create function public.complete_job_periodic_review(p_job_id uuid,p_expected_revision integer,p_published_revision integer,p_note text) returns public.job_periodic_reviews language sql security invoker set search_path=pg_catalog,private as $$select private.complete_job_periodic_review(p_job_id,p_expected_revision,p_published_revision,p_note)$$;
revoke all on function private.guard_job_scheduled_release(),private.finish_job_scheduled_release(),private.label_job_periodic_review_task(),private.sync_job_periodic_review_task(),private.finish_job_periodic_review_task(),private.process_job_effective_dates(),private.process_job_periodic_reviews() from public,anon,authenticated;
revoke all on function private.approve_job_effective_date(uuid,integer,date),private.cancel_job_effective_date(uuid,text),private.save_job_periodic_review(uuid,integer,uuid,date,integer,boolean),private.complete_job_periodic_review(uuid,integer,integer,text),public.approve_job_effective_date(uuid,integer,date),public.cancel_job_effective_date(uuid,text),public.save_job_periodic_review(uuid,integer,uuid,date,integer,boolean),public.complete_job_periodic_review(uuid,integer,integer,text) from public,anon;
grant execute on function private.approve_job_effective_date(uuid,integer,date),private.cancel_job_effective_date(uuid,text),private.save_job_periodic_review(uuid,integer,uuid,date,integer,boolean),private.complete_job_periodic_review(uuid,integer,integer,text),public.approve_job_effective_date(uuid,integer,date),public.cancel_job_effective_date(uuid,text),public.save_job_periodic_review(uuid,integer,uuid,date,integer,boolean),public.complete_job_periodic_review(uuid,integer,integer,text) to authenticated;
select cron.schedule('atwar_job_effective_dates','*/5 * * * *','select private.process_job_effective_dates();');
select cron.schedule('atwar_job_periodic_reviews','10 * * * *','select private.process_job_periodic_reviews();');
commit;
