import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';

const root=resolve(new URL('..',import.meta.url).pathname);
const read=file=>readFileSync(resolve(root,file),'utf8');
const workspace=read('workspace/index.html');
const notifications=read('notifications/index.html');
const shell=read('assets/js/shell-components.js');
const migration=read('supabase/migrations/20260912_phase_two_workspace_notification_unification.sql');
const taskIndexMigration=read('supabase/migrations/20260912_phase_two_followup_task_index.sql');
const guide=read('tasks/user-guide.html');

const contracts=[
  [workspace,'id="wfTask"','Follow-up form must offer an optional task reference'],
  [workspace,"p_task_id:taskId",'Workspace must submit only the selected task reference'],
  [workspace,"select('id,title,status,assignee_id')",'Workspace must read only the task fields needed for a link'],
  [workspace,'&scope=COMPLETED','Linked completed tasks must open in the completed scope'],
  [migration,'add column if not exists task_id uuid','Follow-ups must store a nullable task reference'],
  [migration,'foreign key (task_id) references public.tasks(id) on delete set null','Task references must preserve follow-ups if a task is removed'],
  [migration,'task_id is null or private.can_view_task(task_id)','RLS must allow links only to visible tasks'],
  [migration,'security invoker','Workspace RPC must execute with caller permissions'],
  [taskIndexMigration,'follow_ups_task_id_idx','Linked-task foreign key must have a covering index'],
  [shell,'window.atwarOpenNotificationRecord','Notification surfaces must share one source-opening function'],
  [shell,'&owner=${encodeURIComponent(task.assignee_id','Task notification links must preserve the task owner'],
  [shell,"task.status==='مكتملة'?'&scope=COMPLETED'",'Completed notifications must open the completed scope'],
  [notifications,"window.atwarOpenNotificationRecord(sb,n,'../',showError)",'Notification page must use the shared opening behavior'],
  [guide,'الارتباط يحفظ مرجع المهمة فقط','User guide must explain non-duplicating follow-up links']
];

for(const [source,needle,message] of contracts)assert.ok(source.includes(needle),message);
assert.ok(!workspace.includes("sb.from('tasks').select('*')"),'Workspace must not copy or load full task records');
assert.ok(!migration.includes('task_title'),'Follow-up schema must not duplicate task titles');

console.log(`Phase-two workspace and notifications audit passed: ${contracts.length+2} contracts.`);
