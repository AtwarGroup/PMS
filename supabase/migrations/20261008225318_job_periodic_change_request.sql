begin;
alter table public.job_periodic_reviews add column needs_changes boolean not null default false;
alter table public.job_periodic_review_events add column outcome text not null default 'NO_CHANGES' check(outcome in ('NO_CHANGES','CHANGES_REQUIRED'));
create or replace function private.finish_job_periodic_review_task() returns trigger language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare j public.job_descriptions%rowtype;owner uuid;
begin
 perform private.close_job_workflow_tasks(new.job_description_id,'PERIODIC_REVIEW');
 if new.outcome='CHANGES_REQUIRED' then
  select * into j from public.job_descriptions where id=new.job_description_id;
  owner:=private.job_stage_owner('DRAFT');
  if not exists(select 1 from public.profiles where id=owner and active=true and status='active') then raise exception 'حدد مسؤولًا نشطًا لإعداد الأوصاف قبل طلب التعديل';end if;
  perform private.ensure_job_workflow_task(j,'DRAFT_REVISION','periodic:'||new.id::text,owner);
 end if;return new;
end $$;
create function private.request_job_periodic_change(p_job_id uuid,p_expected_revision integer,p_published_revision integer,p_note text)
returns public.job_periodic_reviews language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare r public.job_periodic_reviews%rowtype;j public.job_descriptions%rowtype;
begin
 if auth.uid() is null or not private.current_user_is_active() then raise exception 'حساب نشط مطلوب' using errcode='42501';end if;
 select * into j from public.job_descriptions where id=p_job_id for update;
 select * into r from public.job_periodic_reviews where job_description_id=p_job_id for update;
 if not found or not r.enabled or r.needs_changes then raise exception 'لا توجد مراجعة دورية جاهزة لهذا الإجراء';end if;
 if r.reviewer_id<>auth.uid() and not private.can_job_stage('DRAFT') then raise exception 'هذا الإجراء لمسؤول المراجعة' using errcode='42501';end if;
 if p_expected_revision is null or r.revision<>p_expected_revision or p_published_revision is null or (j.published_snapshot->>'revision')::integer<>p_published_revision then raise exception 'تغير الوصف أو المراجعة؛ حدّث الصفحة' using errcode='40001';end if;
 if j.status<>'PUBLISHED' then raise exception 'أكمل دورة التعديل القائمة أولًا';end if;
 if length(btrim(coalesce(p_note,'')))<2 then raise exception 'وضح التعديلات المطلوبة';end if;
 insert into public.job_periodic_review_events(job_description_id,published_revision,reviewer_id,note,next_due_on,outcome) values(j.id,p_published_revision,auth.uid(),btrim(p_note),r.due_on,'CHANGES_REQUIRED');
 update public.job_periodic_reviews set needs_changes=true,revision=revision+1,updated_by=auth.uid(),updated_at=now() where job_description_id=j.id returning * into r;
 return r;
end $$;
create function public.request_job_periodic_change(p_job_id uuid,p_expected_revision integer,p_published_revision integer,p_note text) returns public.job_periodic_reviews language sql security invoker set search_path=pg_catalog,private as $$select private.request_job_periodic_change(p_job_id,p_expected_revision,p_published_revision,p_note)$$;
revoke all on function private.request_job_periodic_change(uuid,integer,integer,text),public.request_job_periodic_change(uuid,integer,integer,text) from public,anon;
grant execute on function private.request_job_periodic_change(uuid,integer,integer,text),public.request_job_periodic_change(uuid,integer,integer,text) to authenticated;
do $$ declare d text;begin
 select pg_get_functiondef('private.complete_job_periodic_review(uuid,integer,integer,text)'::regprocedure) into d;
 if position('not r.enabled' in d)=0 then raise exception 'Periodic review function changed';end if;
 d:=replace(d,'not r.enabled','not r.enabled or r.needs_changes');execute d;
 select pg_get_functiondef('private.sync_job_periodic_review_task()'::regprocedure) into d;
 d:=replace(d,'if new.enabled and','if new.enabled and not new.needs_changes and');execute d;
 select pg_get_functiondef('private.process_job_periodic_reviews()'::regprocedure) into d;
 d:=replace(d,'where enabled and due_on','where enabled and not needs_changes and due_on');execute d;
end $$;
create function private.reset_periodic_review_after_updated_publication() returns trigger language plpgsql security definer set search_path=pg_catalog,public,private as $$
begin
 if new.status='PUBLISHED' and old.status<>'PUBLISHED' then
  update public.job_periodic_reviews set needs_changes=false,due_on=((now() at time zone 'Asia/Riyadh')::date+make_interval(months=>interval_months))::date,revision=revision+1,updated_at=now()
  where job_description_id=new.id and needs_changes;
 end if;return new;
end $$;
create trigger reset_periodic_review_after_updated_publication after update of status on public.job_descriptions for each row execute function private.reset_periodic_review_after_updated_publication();
revoke all on function private.reset_periodic_review_after_updated_publication() from public,anon,authenticated;
-- The request task explains the actual review finding rather than an empty return note.
do $$ declare d text;begin
 select pg_get_functiondef('private.label_job_revision_task()'::regprocedure) into d;
 if position('return new;' in d)=0 then raise exception 'Revision task label changed';end if;
 d:=replace(d,'return new;',$patch$if new.task_type='job_workflow' and new.legacy_metadata#>>'{job_workflow,phase}'='DRAFT_REVISION' and new.legacy_metadata#>>'{job_workflow,cycle}' like 'periodic:%' then
 new.description:='طلب تحديث من المراجعة الدورية: '||coalesce((select e.note from public.job_periodic_review_events e where e.id=substring(new.legacy_metadata#>>'{job_workflow,cycle}' from 10)::uuid),'راجع سجل المراجعة');end if;return new;$patch$);execute d;
end $$;
commit;
