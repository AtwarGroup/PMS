import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const sql=readFileSync(new URL('../supabase/migrations/20260924223628_reclaim_delegated_task.sql',import.meta.url),'utf8');
const bridge=readFileSync(new URL('../assets/js/supabase-firebase-compat.js',import.meta.url),'utf8');
const page=readFileSync(new URL('../assets/js/tasks-page.js',import.meta.url),'utf8');
const html=readFileSync(new URL('../tasks/index.html',import.meta.url),'utf8');

assert.match(sql,/v_return := v_task\.delegated_by_id=p_target_id/,'Returning to the delegator must be distinguished from a new delegation');
assert.match(sql,/v_return and v_uid=p_target_id and private\.manages_user\(v_task\.assignee_id\)/,
  'The prior delegator may reclaim only a task delegated to their subordinate');
assert.match(sql,/delegated_by_id=case when v_delegation then v_uid else null end/,
  'Reclaim and administrative reassignment must end the active delegation');
assert.match(sql,/v_event := case when v_return then 'reclaimed'/,
  'The historical activity should record the return');
assert.match(bridge,/isDelegated:!!t\.delegated_by_id&&t\.delegated_by_id!==t\.assignee_id/,
  'The badge should represent an active delegation only');
assert.match(page,/supabase-firebase-compat\.js\?v=2\.5\.53/);
const pageVersion=html.match(/tasks-page\.js\?v=(\d+)\.(\d+)\.(\d+)/);
assert.ok(pageVersion,'Task page must have an explicit cache version');
assert.ok(Number(pageVersion[1])>2 || (Number(pageVersion[1])===2 && (Number(pageVersion[2])>5 || (Number(pageVersion[2])===5 && Number(pageVersion[3])>=53))), 'Task page must not revert to a version before the corrected script');
console.log('Delegation return and badge state audit passed.');

