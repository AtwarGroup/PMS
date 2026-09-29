-- Recurring template RLS invokes this helper for the template owner.
grant execute on function private.can_assign_task_target_for(uuid,uuid) to authenticated;
