import assert from 'node:assert/strict';
import {readFileSync,readdirSync,statSync} from 'node:fs';
import {resolve} from 'node:path';

const root=resolve(import.meta.dirname,'..');
const read=file=>readFileSync(resolve(root,file),'utf8');
const html=[];
function walk(dir){for(const name of readdirSync(dir)){if(['.git','node_modules'].includes(name))continue;const path=resolve(dir,name);if(statSync(path).isDirectory())walk(path);else if(path.endsWith('.html'))html.push(path)}}
walk(root);

const protectedPages=html.filter(file=>readFileSync(file,'utf8').includes('shell-components.js'));
for(const file of protectedPages){
  const source=readFileSync(file,'utf8');
  assert.match(source,/shell-components\.js\?v=2\.5\.8/,'Stale shell cache version: '+file);
  assert.match(source,/ui-feedback\.js\?v=2\.5\.2/,'Missing synchronous feedback: '+file);
  assert.match(source,/session-service\.js\?v=2\.5\.2/,'Missing synchronous session service: '+file);
  assert.match(source,/shared\.css\?v=2\.5\.2/,'Stale shared theme: '+file);
}

const tasks=read('assets/js/tasks-page.js');
const library=read('assets/js/job-library-page.js');
const review=read('assets/js/job-review-page.js');
const profile=read('profile/index.html');
const executive=read('tasks/executive.html');
const users=read('admin/users.html');
const shell=read('assets/js/shell-components.js');
const notificationMigration=read('supabase/migrations/20260921_notification_read_state.sql');

for(const source of [tasks,library,review]){
  assert.doesNotMatch(source,/(^|[^.\w])prompt\s*\(/m,'Native prompt remains in a primary workflow');
  assert.doesNotMatch(source,/(^|[^.\w])confirm\s*\(/m,'Native confirm remains in a primary workflow');
}
assert.match(review,/إرسال لمدير النظام للاعتماد/,'CEO/top reviewer handoff must be explicit');
assert.match(review,/MANAGER_APPROVED[\s\S]*بانتظار المراجعة النهائية والاعتماد/,'Manager handoff state must remain visible');
assert.match(profile,/data-inline-job="description"[\s\S]*data-inline-job="tasks"[\s\S]*data-inline-job="authority"[\s\S]*data-inline-job="performance"/,'Job profile content must remain inline');
assert.match(profile,/hashMode=\{[^}]*'\#job-profile':'description'[^}]*'\#job-performance':'performance'[^}]*\}\[location\.hash\][\s\S]*renderInlineJob\(hashMode/,'Job profile deep links must open every published section inline');
assert.match(read('profile/kpi.html'),/بطاقة الأداء المتوازن[\s\S]*المنظور المالي[\s\S]*المستفيدون[\s\S]*العمليات الداخلية[\s\S]*التعلم والنمو/,'KPI route must show the balanced scorecard');
assert.match(executive,/id="listView"[\s\S]*id="kanbanView"/,'Executive view must offer list and Kanban');
assert.match(users,/admin_set_executive_task_access[\s\S]*admin_update_profile_details/,'Account save must persist executive and profile fields');
assert.match(notificationMigration,/add column if not exists read_at[\s\S]*notifications_update_read_policy/,'Notifications must retain a protected read state');
assert.match(shell,/update\(\{read_at:new Date\(\)\.toISOString\(\)\}\)/,'Opening a notification must mark it read instead of deleting it');
assert.match(shell,/profile\/index\.html\?view=job#job-profile/,'Job assignment notifications must open the approved job view');
console.log(`Release 2.5.1 acceptance passed: ${protectedPages.length} protected pages.`);
