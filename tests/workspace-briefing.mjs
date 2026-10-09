import assert from 'node:assert/strict';
import {workspaceBriefing,renderBriefing} from '../assets/js/workspace-briefing.mjs';
import {requestModel,taskNextStep} from '../assets/js/workspace-core.mjs';
import {normalizeFollowup} from '../assets/js/task-followup-core.mjs';
const profile={id:'me',role:'manager'},base={assignee_id:'me',creator_id:'me',status:'قيد التنفيذ',task_type:'normal',title:'Task'};
const tasks=[
 {...base,id:'future',due_date:'2027-01-03',title:'<script>bad</script>'},
 {...base,id:'starts',start_date:'2027-01-01',due_date:'2027-01-20'},
 {...base,id:'today',due_date:'2026-12-29'},
 {...base,id:'far',due_date:'2027-01-06'},
 {...base,id:'waiting',status:'بانتظار الاعتماد',submitted_at:'2026-12-20',creator_id:'boss',creator_name_snapshot:'المدير'},
 {...base,id:'done',status:'مكتملة',due_date:'2027-01-02'},
 {...base,id:'deleted',deleted_at:'now',due_date:'2027-01-02'},
 {...base,id:'workflow',task_type:'job_workflow',due_date:'2027-01-02'},
 {...base,id:'team',assignee_id:'direct',creator_id:'other'},
 {...base,id:'unrelated',assignee_id:'other',creator_id:'other'}
];
const requests=requestModel({profile,tasks,reschedules:[{id:'pending',task_id:'future',requester_id:'me',task_creator_id:'boss',status:'PENDING',created_at:'2026-12-25'},{id:'closed',task_id:'future',requester_id:'me',task_creator_id:'boss',status:'APPROVED',created_at:'2026-12-25'}]});
const model=workspaceBriefing({profile,tasks,requests,day:'2026-12-29',directIds:['direct'],followups:[{task_id:'future',blocked:true,reason:'<img src=x>',next_step:'اتصل',owner_role:'creator',follow_date:'2026-12-30'},{task_id:'done',blocked:true},{task_id:'team',blocked:true},{task_id:'unrelated',blocked:true},{task_id:'today',blocked:false}]});
assert.equal(model.end,'2027-01-05');
assert.deepEqual(model.upcoming.map(t=>t.id),['starts','future']);
assert.deepEqual(model.waiting.map(r=>r.id),['waiting:waiting','schedule:pending']);
assert.deepEqual(model.blockers.map(r=>r.task.id),['future','team']);
assert.match(taskNextStep(tasks.find(t=>t.id==='waiting')),/المدير: مراجعة الإنجاز/);
assert.match(taskNextStep({...base,assignee_id:'me',status:'قيد الانتظار'}),/بدء التنفيذ/);
assert.equal(taskNextStep({...base,status:'مكتملة'}),'اكتمل العمل');
assert.equal(taskNextStep({...base,status:'بانتظار الاعتماد',project_id:'p',assignee_id:'pm'},null,{projects:[{id:'p',manager_id:'pm'}]}),'راعي المشروع: مراجعة الإنجاز');
const html=renderBriefing(model,{today:1,decisions:2,projects:1});assert.ok(!html.upcoming.includes('<script>'));assert.ok(!html.blockers.includes('<img'));assert.match(html.summary,/spaceWaitingPanel/);assert.match(html.blockers,/اتصل/);
assert.deepEqual(normalizeFollowup({reason:' سبب ',next_step:' عمل '}),{blocked:false,reason:'سبب',next_step:'عمل',owner_role:'assignee',follow_date:null});
assert.throws(()=>normalizeFollowup({follow_date:'2026-02-30'}),/غير صالح/);
assert.throws(()=>normalizeFollowup({owner_role:'admin'}));
assert.throws(()=>normalizeFollowup({reason:'x'.repeat(1001)}));
const large=renderBriefing({...model,upcoming:Array.from({length:12},(_,i)=>({...base,id:'u'+i,upcomingDate:'2027-01-01'}))});assert.equal((large.upcoming.match(/class="space-row"/g)||[]).length,12,'All upcoming items must remain reachable');
console.log('PASS briefing: personal/direct-team scope, year boundary, terminal exclusion, pending-only waits, next actor, escaping, optional follow-up validation and full list');
