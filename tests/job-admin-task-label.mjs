import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const sql=readFileSync(new URL('../supabase/migrations/20260928161324_clarify_job_admin_approval_tasks.sql',import.meta.url),'utf8');
assert.match(sql,/new\.title:='الاعتماد النهائي لدى مدير النظام: '/);
assert.match(sql,/v_job\.manager_approved_by/);
assert.match(sql,/w\.phase='ADMIN_APPROVAL'/);
assert.match(sql,/t\.status<>'مكتملة'/);
assert.doesNotMatch(sql,/set\s+assignee_id\s*=/i);
