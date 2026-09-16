import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';

const root=resolve(new URL('..',import.meta.url).pathname);
const page=readFileSync(resolve(root,'assets/js/tasks-page.js'),'utf8');
const html=readFileSync(resolve(root,'tasks/index.html'),'utf8');
const sql=readFileSync(resolve(root,'supabase/migrations/20260915_creator_delete_and_task_update_resilience.sql'),'utf8');

assert.match(page,/function canDeleteTask\(task\)/,'Delete permission must be evaluated against the selected task');
assert.match(page,/if\(currentProfile\.role==='admin'\)return true;[\s\S]*task\.status!=='مكتملة'[\s\S]*task\.createdByUid/,'Any creator may delete their own non-completed task while admin remains unrestricted');
assert.match(page,/if\(!canDeleteTask\(locked\)\)throw/,'Deletion permission must be rechecked on the locked task');
assert.match(page,/يمكنك حذف المهام التي أنشأتها بنفسك فقط/,'The denial must explain the ownership rule');
assert.doesNotMatch(page,/function canDeleteTasks\(\)/,'Role-only deletion permission must be retired');
assert.match(html,/tasks-page\.js\?v=1\.9\.23/,'The task page must invalidate the cached module');
assert.match(sql,/before update of deleted_at on public\.tasks/i,'Soft deletion must be protected in the database');
assert.match(sql,/before delete on public\.tasks/i,'Hard deletion must be protected in the database');
assert.match(sql,/v_task\.creator_id = v_uid/i,'The database must enforce creator ownership for non-admin users');
assert.match(sql,/v_task\.status <> 'مكتملة'/,'Completed tasks must remain admin-only');
assert.match(sql,/v_role not in \('employee','manager','admin'\)/,'The safe delete RPC must accept every active application role');
assert.match(sql,/v_task\.creator_id<>v_actor or v_task\.status='مكتملة'/,'The safe delete RPC must enforce creator ownership and completed-task protection');
assert.match(sql,/grant execute on function private\.can_delete_task\(uuid\) to authenticated/,'RLS must be able to evaluate the delete helper');
console.log('Task deletion ownership audit passed.');
