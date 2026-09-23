import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const read=file=>readFileSync(file,'utf8');
const shell=read('assets/js/shell-components.js');
const active=read('tasks/index.html');
const taskLogic=read('assets/js/tasks-page.js');
const executive=read('tasks/executive.html');
const recurring=read('recurring/index.html');
const completed=read('completed/index.html');
const profile=read('profile/index.html');
const workspace=read('workspace/index.html');
const users=read('admin/users.html');

assert.match(shell,/workspace\/index\.html[^\n]+مساحة عملي/,'مساحة عملي must remain in navigation');
assert.match(workspace,/ملاحظاتك ومتابعاتك الشخصية/,'workspace must be clearly personal');
assert.match(workspace,/دون تكرار إدارة المهام/,'workspace must state its non-duplicating scope');

assert.match(active,/setTaskViewMode\('LIST'\)/,'active tasks list view missing');
assert.match(active,/setTaskViewMode\('KANBAN'\)/,'active tasks kanban view missing');
assert.match(taskLogic,/let managerDashboardCollapsed=true/,'team overview must start collapsed');
assert.match(executive,/id="listView"/,'executive list view missing');
assert.match(executive,/id="kanbanView"/,'executive kanban view missing');
assert.match(executive,/minmax\(240px,380px\)/,'executive search must remain compact');
assert.match(recurring,/id="recurringListButton"/,'recurring list view missing');
assert.match(recurring,/id="recurringKanbanButton"/,'recurring kanban view missing');
assert.match(recurring,/atwarRecurringView/,'recurring view preference must persist');
assert.match(completed,/scope=COMPLETED/,'completed archive must use unified task workspace');

for(const mode of ['description','tasks','authority','performance'])assert.match(profile,new RegExp(`data-inline-job="${mode}"`),`inline profile mode ${mode} missing`);
assert.match(profile,/profileJobViewer/,'inline job viewer missing');
assert.match(users,/تم حفظ التغييرات بنجاح/,'admin save feedback missing');
assert.match(users,/manager_id/,'direct manager field missing');
assert.match(users,/join_date/,'additional employee data missing');

for(const file of ['tasks/index.html','tasks/executive.html','recurring/index.html','profile/index.html','workspace/index.html','admin/users.html']){
  const source=read(file);
  assert.doesNotMatch(source,/\?v=2\.5\.1/,`${file} still uses stale cache key`);
}
console.log('User requirements 2.5.2 audit passed.');
