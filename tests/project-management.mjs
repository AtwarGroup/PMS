import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import {renderProjectPreview} from '../scripts/project-preview.mjs';
import {weightedProgress,timeline,dependencyImpact,validDates} from '../assets/js/projects-core.mjs';
const a={id:'a',status:'مكتملة',progress:100,project_weight:3,start_date:'2026-10-01',due_date:'2026-10-03'},b={id:'b',status:'قيد التنفيذ',progress:40,project_weight:1,start_date:'2026-10-04',due_date:'2026-10-06'};
assert.equal(weightedProgress([a,b]),85);
assert.equal(weightedProgress([a,{...b,status:'بانتظار الاعتماد',progress:100}]),99);
assert.equal(weightedProgress([a,{...b,status:'مكتملة'}]),100);
assert.equal(weightedProgress([{...a,project_weight:1000},{...b,project_weight:.1,progress:100}]),99,'Rounding cannot make unapproved work complete');
assert.equal(weightedProgress([{...b,status:'ملغاة'}]),0);
assert.equal(weightedProgress([]),0);
assert.equal(weightedProgress([{...a,deleted_at:'now'},b]),40);
const plan=timeline([a,b],{start_date:'2026-10-01',due_date:'2026-10-10'},'week');
assert.equal(plan.days,10);assert.equal(plan.rows[0].left,0);assert.equal(plan.rows[0].width,30);assert.equal(plan.rows[1].left,30);assert.equal(plan.rows[1].width,30);
assert.deepEqual(dependencyImpact('a',[{task_id:'b',predecessor_id:'a'},{task_id:'c',predecessor_id:'b'},{task_id:'c',predecessor_id:'a'}],[a,b,{id:'c'}]).map(x=>x.id),['b','c']);
assert(validDates('2026-10-01','2026-10-02'));assert(!validDates('2026-02-31','2026-03-04'));assert(!validDates('2026-10-02','2026-10-01'));assert(!validDates('',null));
const source=readFileSync('assets/js/tasks-page.js','utf8');
const ctx={currentProfile:{role:'employee'},currentUser:{uid:'sponsor'},getUserByUid:()=>null,isExecutiveReadOnlyTask:()=>false};vm.createContext(ctx);
for(const name of ['taskApprovalRecipient','canApproveTask']){const start=source.indexOf(`function ${name}(`),end=source.indexOf('\n}',start)+2;vm.runInContext(source.slice(start,end),ctx);}
const task={projectId:'project',assignUid:'manager',createdByUid:'manager',approvalCommissionerUid:'sponsor'};
assert.equal(ctx.canApproveTask(task),true,'Sponsor approval is independent of hierarchy role');ctx.currentUser.uid='manager';assert.equal(ctx.canApproveTask(task),false,'Manager cannot approve their own project task');ctx.currentUser.uid='admin';ctx.currentProfile.role='admin';assert.equal(ctx.canApproveTask(task),false,'Admin UI cannot override designated project approver');
console.log('Project weighted progress, calendar geometry, transitive dependencies and task approval integration passed');
for(const view of ['overview','gantt','list','board','chat','files']){const html=renderProjectPreview(view);assert(!html.includes('NaN'));assert(html.includes('مشروع تجريبي'));if(view==='gantt'){assert(html.includes('project-bar'));assert(html.includes('التبعيات'));}if(view==='chat')assert(html.includes('تحويل إلى مهمة'));}
console.log('Project overview, Gantt, list, board, chat and files render checks passed');
