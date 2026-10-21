import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';

const root=resolve(new URL('..',import.meta.url).pathname);
const read=file=>readFileSync(resolve(root,file),'utf8');
const team=read('team/index.html');
const employee=read('team/employee.html');
const tasks=read('assets/js/tasks-page.js');

const directory=read('admin/employees.html');
const page=read('assets/js/employee-master-page.mjs');
const teamContracts=[
 ['id="employeeHierarchy"','Employee workspace retains reporting hierarchy'],
 ['id="hierarchySummary"','Employee workspace provides organizational summary'],
 ['../team/employee.html','Employee workspace links published descriptions']
];
for(const [needle,message] of teamContracts)assert.ok((directory+page).includes(needle),message);
assert.ok(team.includes("location.replace('../admin/employees.html'"),'Old bookmarks redirect to the canonical employee workspace');
assert.ok(page.includes("rpc('employee_master_list')"),'One authorized employee source serves both views');
assert.ok(!page.includes("sb.from('profiles')"),'Employee directory must not reconstruct employees from login accounts');
assert.ok(!page.includes("sb.from('tasks')"),'Employee workspace must not duplicate task metrics');

assert.ok(tasks.includes('function renderManagerDashboard()'),'Task workspace must retain team task metrics');
assert.ok(tasks.includes("String(u.managerUid||'')===String(currentUser.uid)"),'Manager full-task view must remain limited to direct reports');
assert.ok(tasks.includes("String(task.createdByUid||'')===String(currentUser.uid||'')"),'Manager must retain visibility of tasks they created');
const employeePage=read('assets/js/team-employee-page.js');
assert.ok(employeePage.includes("sb.rpc('get_team_employee_job'"),'Employee profile route must delegate team authorization and published snapshot selection to the scoped RPC');
assert.ok(!employee.includes('target.manager_id===a.profile.id'),'Employee profile route must not reject permitted indirect descendants client-side');

console.log(`Phase-two team boundary audit passed: ${teamContracts.length+10} contracts.`);
