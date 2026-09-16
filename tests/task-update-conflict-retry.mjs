import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';

const root=resolve(new URL('..',import.meta.url).pathname);
const compat=readFileSync(resolve(root,'assets/js/supabase-firebase-compat.js'),'utf8');
const page=readFileSync(resolve(root,'assets/js/tasks-page.js'),'utf8');
const html=readFileSync(resolve(root,'tasks/index.html'),'utf8');
const sql=readFileSync(resolve(root,'supabase/migrations/20260915_creator_delete_and_task_update_resilience.sql'),'utf8');

assert.match(compat,/for\(let attempt=0;attempt<2;attempt\+\+\)/,'Task transactions must retry once from a fresh server version');
assert.match(compat,/if\(conflict&&attempt===0\)continue/,'Only optimistic-concurrency conflicts may be retried');
assert.match(compat,/const rows=await visibleTasks\(\{id:key\}\)/,'Each retry must reload the authoritative task');
assert.match(page,/supabase-firebase-compat\.js\?v=1\.9\.20/,'The compatibility bridge cache must be invalidated');
assert.match(html,/tasks-page\.js\?v=1\.9\.23/,'The task page cache must be invalidated');
assert.match(sql,/v_task\.creator_id = v_uid/,'Database deletion must allow the authenticated creator');
assert.doesNotMatch(sql,/v_role = 'manager'[\s\S]*v_task\.creator_id/,'Creator deletion must not require manager role');
console.log('Task update conflict retry and creator deletion audit passed.');
