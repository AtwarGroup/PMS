import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const read = path => readFileSync(new URL(`../${path}`,import.meta.url),'utf8');
const page=read('assets/js/tasks-page.js');
const admin=read('admin/users.html');
const sql=read('supabase/migrations/20260929162129_indirect_task_assignment_permission.sql');

assert.match(page,/String\(u\.managerUid\|\|''\)===String\(currentUser\.uid\)/);
assert.match(page,/includes\('tasks\.assign_indirect'\) && isDescendantOf\(u,currentUser\.uid\)/);
assert.match(page,/includes\('tasks\.assign_indirect'\) && isDescendantOf\(target,currentUser\.uid\)/);
assert.match(admin,/admin_set_indirect_task_assignment/);
assert.match(sql,/private\.can_assign_task_target\(assignee_id\)/);
for(const fn of ['create_task_safe','import_tasks_safe','delegate_task_safe','validate_task_workflow','materialize_recurring_tasks'])
  assert.ok(sql.includes(fn),`${fn} must enforce the new permission`);
assert.match(sql,/recurring_templates_update_policy[\s\S]*can_assign_task_target_for\(owner_id,assignee_id\)/);
console.log('Indirect task assignment is separated from visibility and guarded across write paths.');
