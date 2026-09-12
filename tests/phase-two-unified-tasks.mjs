import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';

const root=resolve(new URL('..',import.meta.url).pathname);
const read=file=>readFileSync(resolve(root,file),'utf8');
const compat=read('assets/js/supabase-firebase-compat.js');
const tasksJs=read('assets/js/tasks-page.js');
const tasksHtml=read('tasks/index.html');
const completed=read('completed/index.html');
const approvals=read('approvals/index.html');
const shell=read('assets/js/shell-components.js');

const contracts=[
  [compat,"requestedScope==='COMPLETED'?q.eq('status','مكتملة'):q.neq('status','مكتملة')",'Supabase task query must separate active and completed scopes'],
  [tasksJs,"function isCompletedArchiveView()",'Task module must recognise completed archive scope'],
  [tasksJs,"id)?.addEventListener('change'",'Completed date filters must refresh the canonical task list'],
  [tasksJs,"location.href='index.html?scope=COMPLETED'",'Completed quick filter must open the completed scope'],
  [tasksJs,'adminReopenCompletedTask','Canonical task details must retain the admin reopen action'],
  [tasksHtml,'id="completedDateFilters"','Canonical task view must provide completed-date filters'],
  [completed,'../tasks/index.html?scope=COMPLETED','Legacy completed page must redirect to the canonical view'],
  [approvals,'tasks/index.html?scope=APPROVAL','Legacy approvals page must redirect to the canonical view'],
  [shell,'tasks/index.html?scope=COMPLETED','Navigation must link directly to the canonical completed scope']
];

for(const [source,needle,message] of contracts)assert.ok(source.includes(needle),message);
assert.equal((tasksHtml.match(/id="detailsPanel"/g)||[]).length,1,'Canonical task view must contain one task details panel');

console.log(`Phase-two unified task workspace audit passed: ${contracts.length+1} contracts.`);
