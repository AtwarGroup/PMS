import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
const root=resolve(new URL('..',import.meta.url).pathname);
const read=path=>readFileSync(resolve(root,path),'utf8');
const tasks=read('assets/js/tasks-page.js');
const compat=read('assets/js/supabase-firebase-compat.js');
const taskHtml=read('tasks/index.html');
const governance=read('supabase/migrations/20260920_task_governance_reschedule_executive_scope.sql');
const acknowledgement=read('supabase/migrations/20260917_task_date_ownership_and_job_acknowledgements.sql');
const profile=read('assets/js/job-profile-page.js');
const email=read('supabase/functions/send-job-acknowledgement/index.ts');
const library=read('assets/js/job-library-page.js');
const review=read('assets/js/job-review-page.js');
const roles=JSON.parse(read('job-library/data/approved-role-updates-2026-09-20.json'));
const shell=read('assets/js/shell-components.js');

assert.match(tasks,/field==='start'\|\|field==='end'[\s\S]{0,180}task\.createdByUid/,'Dates must be editable by creator, not by assignee role');
assert.match(acknowledgement,/old\.creator_id=v_uid/,'Database date guard must recognize the task creator');
assert.match(acknowledgement,/before update of start_date,due_date/,'Database trigger must cover both task dates');
assert.match(taskHtml,/requestSelectedTaskReschedule/,'Assignee must have a reschedule-request action');
assert.match(governance,/request_task_reschedule[\s\S]*v_task\.assignee_id<>\(select auth\.uid\(\)\)/s,'Only the current assignee may request rescheduling');
assert.match(governance,/decide_task_reschedule[\s\S]*task_creator_id<>\(select auth\.uid\(\)\)/s,'Task creator must own the rescheduling decision');
assert.match(tasks,/isDescendantOf\(target,currentUser\.uid\)/,'Managers may delegate within their reporting tree');
assert.match(compat,/rpc\('delegate_task_safe'/,'Delegation must use the protected database RPC');
assert.match(governance,/v_task\.assignee_id=v_uid and private\.manages_user\(p_target_id\)/,'Delegation must require assigned manager and subordinate target');

assert.match(profile,/type="checkbox"/,'Job acknowledgement must require a checkbox');
assert.match(profile,/acknowledge_job_description/,'Acknowledgement must be stored through the governed RPC');
assert.match(profile,/send-job-acknowledgement/,'Acknowledgement PDF must invoke the email function');
assert.match(email,/HR_EMAIL[\s\S]*hr@tiradorstores\.com/,'HR must receive the acknowledgement');
assert.match(email,/attachments:\[\{filename:/,'Email must contain the PDF attachment');
assert.match(acknowledgement,/unique\(profile_id,job_description_id,job_revision\)/,'One acknowledgement per employee and published revision is required');

assert.match(governance,/tasks\.read_all/,'Executive task access must be a separate permission');
assert.match(tasks,/isExecutiveReadOnlyTask/,'Executive cross-organization access must remain read-only');
assert.match(governance,/executive_task_access_log/,'Executive access must be audited');
assert.match(library,/me\.role!==['"]admin['"]&&current\.reviewer_id===me\.id/,'Any assigned non-admin reviewer may review');
assert.match(review,/job\.reviewer_id !== me\.id/,'Unassigned employees must remain excluded from review');

for(const title of ['المدير المالي','مشرف المشتريات والمخزون','مدير العمليات'])assert.ok(roles.jobs.some(job=>job.title===title),`${title} source update is required`);
assert.ok(roles.jobs.every(job=>job.content.responsibilities.length>=8),'Each approved role update must contain substantive responsibilities');
assert.match(shell,/favicon\.svg/,'Shared shell must install the ATWAR ONE favicon');
console.log('Task governance, job acknowledgement and approved-role update audit passed.');
