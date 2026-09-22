import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';

const root=resolve(new URL('..',import.meta.url).pathname);
const compat=readFileSync(resolve(root,'assets/js/supabase-firebase-compat.js'),'utf8');
const page=readFileSync(resolve(root,'assets/js/tasks-page.js'),'utf8');
const sql=readFileSync(resolve(root,'supabase/migrations/20260922143000_delegate_task_idempotency.sql'),'utf8');

assert.match(page,/if\(isReassigningTask\)return false/,'UI must reject concurrent delegation submissions');
assert.doesNotMatch(page,/prepared=await prepareTaskOperation\(task,'reassign'/,'Delegation must not pre-increment the task revision');
assert.match(compat,/const _delegationsInFlight=new Map\(\)/,'Identical delegation RPCs must be coalesced');
assert.match(compat,/if\(String\(cur\.assignUid\|\|''\)===targetId\)continue/,'Completed delegation replays must be skipped client-side');
assert.match(sql,/if v_task\.assignee_id=p_target_id and v_task\.delegated_by_id=v_uid then[\s\S]*return query/,'Completed delegation replays must be idempotent in PostgreSQL');
assert.ok(sql.indexOf('v_task.assignee_id=p_target_id')<sql.indexOf("v_task.revision<>p_expected_revision"),'Idempotency must be checked before stale revision rejection');

console.log('Delegation CPU loop guards passed.');
