import assert from 'node:assert/strict';
import {timeline} from '../assets/js/projects-core.mjs';
import {actionInbox,renderActionInbox,requestModel} from '../assets/js/workspace-core.mjs';
const RealDate=Date;
try{
 globalThis.Date=class extends RealDate{constructor(...args){super(...(args.length?args:['2026-10-08T22:30:00Z']));}};
 const task={id:'t',start_date:'2026-10-08',due_date:'2026-10-08',status:'قيد التنفيذ'};
 const project={start_date:'2026-10-08',due_date:'2026-10-10'};
 assert.equal(timeline([task],project).rows[0].late,true,'Saudi midnight must match workspace day');
 for(const status of ['مكتملة','بانتظار الاعتماد','ملغاة'])assert.equal(timeline([{...task,status}],project).rows[0].late,false);
 assert.equal(timeline([{...task,deleted_at:'now'}],project).rows[0].late,false);
 assert.equal(timeline([{...task,due_date:'2026-10-09'}],project).rows[0].late,false,'Due today is not late');
}finally{globalThis.Date=RealDate;}
const requests={actions:[{id:'new',title:'new',href:'#new',action:true,date:'2026-10-09'},{id:'old',title:'old',href:'#old',action:true,date:'2026-10-01'}],replaced:new Set(['replaced'])};
const decisions=[{id:'approval',title:'approval',status:'بانتظار الاعتماد',submitted_at:'2026-10-02',due_date:'2020-01-01'}, {id:'workflow',title:'<script>',task_type:'job_workflow',created_at:'2026-10-08',due_date:'2026-10-08'},{id:'urgent',title:'urgent',priority:'urgent',submitted_at:'2026-10-09'},{id:'replaced',title:'duplicate'}];
const rows=actionInbox(requests,decisions,'2026-10-09');
assert.deepEqual(rows.map(r=>r.id),['task:workflow','task:urgent','old','task:approval','new']);
assert.equal(rows.find(r=>r.id==='task:approval').deadline,null,'Execution deadline is not an approval SLA');
const html=renderActionInbox(rows,'2026-10-09');assert(html.includes('مراجعة متأخرة'));assert(html.includes('مدة انتظار الاعتماد: 7 يوم'));assert(html.includes('&lt;script&gt;'));assert(!html.includes('<script>'));
assert(!renderActionInbox([{id:'u',title:'unknown',href:'#',action:true,date:'invalid'}],'2026-10-09').includes('NaN'));
const age=renderActionInbox([{id:'x',title:'today',href:'#',action:true,date:'2026-10-08T22:00:00Z'}],'2026-10-09');assert(age.includes('عمر الطلب: اليوم'));
const unchanged=requestModel({profile:{id:'employee',role:'employee'},tasks:[{id:'self',assignee_id:'employee',creator_id:'employee',status:'مكتملة'}]});assert.equal(unchanged.actions.length,0);
console.log('Approved review improvements: Saudi midnight, cancellation/deletion exclusions, unified priorities, waiting age, deduplication and escaped rendering passed');
