import assert from 'node:assert/strict';
import {readDashboardData,DASHBOARD_TASK_COLUMNS} from '../assets/js/dashboard-data.mjs';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import {canApproveRelationalTask} from '../assets/js/tasks-core.mjs';
import {readRelatedRows} from '../assets/js/paged-related-read.mjs';
const rows=Array.from({length:1371},(_,i)=>({id:String(i)}));let requests=[];
const selections=[];
const sb={from(table){let range=[0,499];const q={select(columns){selections.push({table,columns});return q},is(){return q},eq(){return q},lte(){return q},order(){return q},limit(){return q},range(a,b){range=[a,b];return q},then(resolve){requests.push(table);return Promise.resolve(resolve(table==='follow_ups'?{data:null,error:Error('offline')}:{data:rows.slice(range[0],range[1]+1),error:null}))}};return q}};
const result=await readDashboardData(sb,{id:'manager',role:'manager'});
assert.equal(result.tasks.data.length,1371);assert.equal(result.followups.data,null);assert(result.followups.error);assert.equal(result.projects.data.length,1371);
assert(selections.filter(x=>x.table==='tasks').every(x=>x.columns===DASHBOARD_TASK_COLUMNS));
const columns=DASHBOARD_TASK_COLUMNS.split(',');
assert(!columns.includes('description')&&!columns.includes('legacy_metadata'));
// Execute the actual home counters on full and projected records for all three roles.
const home=readFileSync(new URL('../home.html',import.meta.url),'utf8');
const counters=home.slice(home.indexOf(" setText('homeStatCompleted'"),home.indexOf(' const d=today()'));
const fixtures=['قيد الانتظار','قيد التنفيذ','بانتظار الاعتماد','مكتملة','ملغاة'].flatMap((status,i)=>[
 {id:`own${i}`,status,assignee_id:'me',creator_id:'me',due_date:'2000-01-01',completed_at:new Date().toISOString(),description:'private body',legacy_metadata:{large:'payload'}},
 {id:`team${i}`,status,assignee_id:'direct',creator_id:'me',delegated_by_id:'me',due_date:'2000-01-01',completed_at:new Date().toISOString()},
 {id:`project${i}`,status,assignee_id:'direct',creator_id:'other',project_id:'project',task_type:'task',approval_commissioner_id:'other'},
 {id:`job${i}`,status,assignee_id:'direct',creator_id:'me',task_type:'job_workflow'},
]);
for(const role of ['employee','manager','admin']){
 const run=rows=>{const values={};const p={id:'me',role},directIds=new Set(['direct']);const indicator=role==='employee'?rows.filter(t=>t.assignee_id===p.id):role==='manager'?rows.filter(t=>t.assignee_id===p.id||directIds.has(t.assignee_id)||t.creator_id===p.id||t.delegated_by_id===p.id):rows;
 vm.runInNewContext(counters,{Date,p,rows,indicator,directIds,projectsResult:{data:[{id:'project',manager_id:'me',sponsor_id:'sponsor'}]},canApproveRelationalTask,late:t=>!!t.due_date&&['قيد الانتظار','قيد التنفيذ'].includes(t.status)&&t.due_date<'2026-10-29',setText:(id,v)=>values[id]=v});return values;};
 assert.deepEqual(run(fixtures.map(t=>Object.fromEntries(columns.map(k=>[k,t[k]])))),run(fixtures),`${role}: projection must preserve real counter/approval behavior`);
}
requests=[];await readDashboardData(sb,{id:'driver',role:'employee'},()=>false);assert.deepEqual([...new Set(requests)],['announcements'],'Unavailable units must not read protected tables');
let chunks=[];
const related=await readRelatedRows(ids=>{chunks.push(ids);let range=[0,499];const q={order(){return q},range(a,b){range=[a,b];return q},then(resolve){return Promise.resolve(resolve({data:rows.filter(r=>ids.includes(String(Number(r.id)%201))).slice(range[0],range[1]+1),error:null}))}};return q;},Array.from({length:201},(_,i)=>String(i)));
assert.equal(related.length,1371);assert(chunks.every(c=>c.length<=100));
await assert.rejects(readRelatedRows(()=>({order(){return this},range(){return this},then(resolve){return Promise.resolve(resolve({data:null,error:Error('denied')}))}}),['x']),/denied/);
console.log('PASS: complete paged dashboard/related reads, source failure isolation, module boundaries and child-read failure propagation');
