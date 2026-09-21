import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';

const root=resolve(new URL('..',import.meta.url).pathname);
const read=file=>readFileSync(resolve(root,file),'utf8');
const start=read('assets/js/start-page-config.js');
const home=read('home.html');
const tasks=read('tasks/index.html');
const taskJs=read('assets/js/tasks-page.js');
const team=read('team/index.html');
const workspace=read('workspace/index.html');
const notifications=read('notifications/index.html');
const myDay=read('my-day/index.html');
const approvals=read('approvals/index.html');
const completed=read('completed/index.html');
const source=[start,home,tasks,taskJs,team,workspace,notifications,myDay,approvals,completed].join('\n');

for(const role of ['employee','manager','admin'])assert.ok(start.includes(`${role}: 'home.html'`),`${role} must start on summary home`);
assert.ok(myDay.includes('tasks/index.html?scope=TODAY&amp;owner=me'),'Legacy My Day must redirect to canonical today tasks');
assert.ok(approvals.includes('tasks/index.html?scope=APPROVAL'),'Legacy approvals must redirect to canonical approvals');
assert.ok(completed.includes('tasks/index.html?scope=COMPLETED'),'Legacy completed page must redirect to canonical archive');
assert.ok(taskJs.includes("'OPEN','COMPLETED','OVERDUE','APPROVAL','TODAY'"),'Task page must own all task scopes');
assert.ok(!team.includes("sb.from('tasks')"),'Team page must remain free of task data');
assert.ok(workspace.includes('id="personalNote"')&&workspace.includes('id="workspaceFollowList"'),'Workspace must remain the personal notes and follow-up source');
assert.ok(notifications.includes('id="notifList"'),'Notification page must remain the full notification source');
for(const page of [tasks,team,workspace,notifications])assert.ok(page.includes('@media(')||page.includes('md:')||page.includes('xl:'),'Core Phase 2 pages must contain responsive behavior');
for(const duplicateId of ['homeNotesBody','homeAttentionBody','homeTodayBody'])assert.ok(!home.includes(duplicateId),`Home must not restore duplicate detail block ${duplicateId}`);
assert.ok(!/service[_-]?role/i.test(source),'Public Phase 2 client files must not expose a service-role key');

console.log('Phase-two closeout audit passed: role, route, ownership, responsive and secret-safety contracts verified.');
