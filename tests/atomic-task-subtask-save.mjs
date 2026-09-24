import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const bridge=readFileSync(new URL('../assets/js/supabase-firebase-compat.js',import.meta.url),'utf8');
const migration=readFileSync(new URL('../supabase/migrations/20260923173302_atomic_task_subtask_save.sql',import.meta.url),'utf8');
const taskPage=readFileSync(new URL('../assets/js/tasks-page.js',import.meta.url),'utf8');
const html=readFileSync(new URL('../tasks/index.html',import.meta.url),'utf8');

assert.match(bridge,/subtasksChanged\s*\?await sb\.rpc\('update_task_with_subtasks_safe'/,
  'Changed subtasks must be saved in the same RPC as the task');
assert.doesNotMatch(bridge,/await reconcileSubtasks\(/,
  'A separate subtask write could leave a task partially saved');
assert.match(migration,/security invoker/i,'The combined RPC must preserve task and subtask RLS');
assert.match(migration,/v_task := public\.update_task_safe\(/,'The combined RPC must preserve revision and workflow checks');
assert.match(migration,/delete from public\.subtasks where task_id = p_task_id/,
  'Removed subtasks must be reconciled within the same transaction');
assert.match(taskPage,/supabase-firebase-compat\.js\?v=2\.5\.7/);
assert.match(html,/tasks-page\.js\?v=2\.5\.8/);
console.log('Atomic task and subtask save contract passed.');
