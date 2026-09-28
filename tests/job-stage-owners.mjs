import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const sql=readFileSync(new URL('../supabase/migrations/20260928164011_job_stage_owners.sql',import.meta.url),'utf8');
const users=readFileSync(new URL('../admin/users.html',import.meta.url),'utf8');
const review=readFileSync(new URL('../assets/js/job-review-page.js',import.meta.url),'utf8');
for(const stage of ['DRAFT','ASSIGN','FINAL_REVIEW','PUBLISH']){
  assert.match(sql,new RegExp(`'${stage}'`));
  assert.match(users,new RegExp(`'${stage}'`));
}
assert.match(sql,/private\.can_job_stage\('ASSIGN'\)/);
assert.match(sql,/private\.can_job_stage\('PUBLISH'\)/);
assert.match(sql,/new\.final_reviewed_at is not null/);
assert.match(sql,/create trigger reassign_job_stage_task/);
assert.match(review,/finish_job_final_review/);
assert.match(review,/job\.final_reviewed_at/);
