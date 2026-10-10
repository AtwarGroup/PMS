alter table public.task_attachment_cleanup add constraint attachment_cleanup_task_folder check(storage_path like task_id::text||'/%' and storage_path !~ '(^|/)\.\.(/|$)');
