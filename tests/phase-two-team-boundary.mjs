import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';

const root=resolve(new URL('..',import.meta.url).pathname);
const read=file=>readFileSync(resolve(root,file),'utf8');
const team=read('team/index.html');
const employee=read('team/employee.html');
const tasks=read('assets/js/tasks-page.js');

const teamContracts=[
  ['id="teamHierarchy"','Team page must retain the reporting hierarchy'],
  ['id="teamDirectorySummary"','Team page must provide an organizational summary'],
  ['manager_id','Team directory must be driven by direct-manager relationships'],
  ["select('id,email,full_name,job_title,department,role,manager_id,active,status')",'Team page must request only directory profile fields'],
  ['../tasks/index.html','Team page must link task follow-up to the canonical task workspace']
];

for(const [needle,message] of teamContracts)assert.ok(team.includes(needle),message);
for(const forbidden of ["sb.from('tasks')",'id="teamMetrics"','teamAttentionCount','teamCompletionRate']){
  assert.ok(!team.includes(forbidden),`Team page must not duplicate task metrics through ${forbidden}`);
}

assert.ok(tasks.includes('function renderManagerDashboard()'),'Task workspace must retain team task metrics');
assert.ok(tasks.includes("String(u.managerUid||'')===String(currentUser.uid)"),'Manager full-task view must remain limited to direct reports');
assert.ok(tasks.includes("String(task.createdByUid||'')===String(currentUser.uid||'')"),'Manager must retain visibility of tasks they created');
assert.ok(employee.includes("const allowed=['manager','admin'].includes(a.profile.role)"),'Employee profile route must defer descendant authorization to Supabase RLS');
assert.ok(!employee.includes('target.manager_id===a.profile.id'),'Employee profile route must not reject permitted indirect descendants client-side');

console.log(`Phase-two team boundary audit passed: ${teamContracts.length+10} contracts.`);
