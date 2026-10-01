create index if not exists tasks_approval_commissioner_id_idx on public.tasks(approval_commissioner_id);
alter policy project_files_add on public.project_files with check(private.project_access(project_id) and uploader_id=(select auth.uid()) and split_part(storage_path,'/',1)=project_id::text and split_part(storage_path,'/',2)=(select auth.uid())::text and exists(select 1 from public.projects where id=project_id and status not in('CLOSED','CANCELLED')) and exists(select 1 from storage.objects where bucket_id='project-files' and name=storage_path));
create function private.protect_project_task_delete() returns trigger language plpgsql set search_path='' as $$ begin if old.project_id is not null then raise exception 'مهام المشروع محفوظة في سجل المشروع ولا تحذف من إدارة المهام';end if;return old;end $$;
revoke all on function private.protect_project_task_delete() from public,anon,authenticated;
create trigger a_project_task_delete_guard before delete on public.tasks for each row execute function private.protect_project_task_delete();
do $$ declare s text;begin
 s:=pg_get_functiondef('private.guard_project_task_insert()'::regprocedure);
 s:=replace(s,$q$if new.status<>'قيد الانتظار'$q$, $q$if new.approved_at is not null or new.approved_by_id is not null or new.started_at is not null or new.submitted_at is not null or new.completed_at is not null or new.deleted_at is not null or new.cancelled_at is not null or new.delegated_by_id is not null then raise exception 'حقول إنشاء المهمة محمية';end if; if new.status<>'قيد الانتظار'$q$);execute s;
 s:=pg_get_functiondef('private.project_command(uuid,integer,text,jsonb)'::regprocedure);
 s:=replace(s,$q$if p_action='close' then$q$, $q$if p_action='close' then if exists(select 1 from public.project_risks where project_id=p.id and status='OPEN') then raise exception 'عالج العوائق المفتوحة قبل إغلاق المشروع';end if;$q$);
 execute s;
end $$;
