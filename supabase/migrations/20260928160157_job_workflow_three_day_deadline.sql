begin;

-- The generic task validator must accept only nested updates coming from
-- job-library/acknowledgement triggers. Direct task edits remain guarded.
do $$
declare v_definition text;v_old text := 'if current_setting(''app.migration_mode'',true)=''on'' then return new; end if;';
begin
  select pg_get_functiondef('private.validate_task_workflow()'::regprocedure) into v_definition;
  if position(v_old in v_definition)=0 then raise exception 'Task validator signature changed'; end if;
  v_definition:=replace(v_definition,v_old,
    'if new.task_type=''job_workflow'' and pg_trigger_depth()>1 then return new; end if;'||chr(10)||' '||v_old);
  execute v_definition;
end $$;

-- Three calendar days including the day the workflow step opens. Overdue
-- starts the following day, using the organization's Riyadh calendar.
create or replace function private.set_job_workflow_deadline()
returns trigger language plpgsql security definer
set search_path='pg_catalog','public','private' as $$
begin
  if new.task_type<>'job_workflow' then return new; end if;
  if tg_op='INSERT' then
    new.start_date:=(now() at time zone 'Asia/Riyadh')::date;
    new.due_date:=new.start_date+2;
  elsif old.status='مكتملة' and new.status='قيد الانتظار' then
    new.start_date:=(now() at time zone 'Asia/Riyadh')::date;
    new.due_date:=new.start_date+2;
  end if;
  return new;
end $$;
revoke all on function private.set_job_workflow_deadline() from public,anon,authenticated;
create trigger set_job_workflow_deadline_before_insert
before insert on public.tasks for each row execute function private.set_job_workflow_deadline();
create trigger set_job_workflow_deadline_before_reopen
before update of status on public.tasks for each row execute function private.set_job_workflow_deadline();

-- Initial workflow tasks already created without deadlines keep their
-- original start day, so genuinely late work is shown as overdue.
alter table public.tasks disable trigger enforce_task_schedule_owner_before_update;
alter table public.tasks disable trigger guard_job_workflow_task_before_change;
select set_config('app.migration_mode','on',true);
update public.tasks t set due_date=t.start_date+2,updated_at=now()
where t.task_type='job_workflow' and t.deleted_at is null
  and t.status<>'مكتملة' and t.start_date is not null and t.due_date is null;
select set_config('app.migration_mode','',true);
alter table public.tasks enable trigger guard_job_workflow_task_before_change;
alter table public.tasks enable trigger enforce_task_schedule_owner_before_update;

commit;
