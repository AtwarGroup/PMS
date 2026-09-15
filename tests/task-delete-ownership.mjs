import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';

const root=resolve(new URL('..',import.meta.url).pathname);
const page=readFileSync(resolve(root,'assets/js/tasks-page.js'),'utf8');
const html=readFileSync(resolve(root,'tasks/index.html'),'utf8');
const sql=readFileSync(resolve(root,'supabase/migrations/20260915_restrict_manager_task_deletion.sql'),'utf8');

assert.match(page,/function canDeleteTask\(task\)/,'Delete permission must be evaluated against the selected task');
assert.match(page,/currentProfile\.role==='manager'[\s\S]*task\.status!=='مكتملة'[\s\S]*task\.createdByUid/,'A manager may delete only a non-completed task they created');
assert.match(page,/if\(!canDeleteTask\(locked\)\)throw/,'Deletion permission must be rechecked on the locked task');
assert.match(page,/لا يمكن للمدير حذف مهمة لم ينشئها/,'The denial must explain the ownership rule');
assert.doesNotMatch(page,/function canDeleteTasks\(\)/,'Role-only deletion permission must be retired');
assert.match(html,/tasks-page\.js\?v=1\.9\.18/,'The task page must invalidate the cached module');
assert.match(sql,/before update of deleted_at on public\.tasks/i,'Soft deletion must be protected in the database');
assert.match(sql,/before delete on public\.tasks/i,'Hard deletion must be protected in the database');
assert.match(sql,/v_task\.creator_id = v_uid/i,'The database must enforce creator ownership for managers');
assert.match(sql,/v_task\.status <> 'مكتملة'/,'Completed tasks must remain admin-only');
console.log('Task deletion ownership audit passed.');
