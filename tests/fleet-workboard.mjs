import assert from 'node:assert/strict';
import {workItems,filterWorkItems,isArchived,workboardItems} from '../assets/js/fleet-workboard.mjs';
const c={employee_id:'receiver',user_id:'user',team_employee_ids:['team'],employees:[{id:'sender',name:'المسلّم'}],requests:[{id:'m',number:1,driver_id:'team',state:'fleet_review',request_type:'repair',description:'صيانة',journey:{responsibles:[{name:'مسؤول الأسطول'}]}}],can_approve:true};
const data={handovers:[{id:'h',number:2,employee_id:'receiver',deliverer_id:'sender',employee_name:'المستلم',state:'fleet_review',workflow_version:2},{id:'s',number:3,employee_id:'other',deliverer_id:'receiver',state:'pending_sender'}]};
const items=workItems(c,data);
assert.equal(items.length,3);
assert.equal(items.find(r=>r.id==='h').action,false,'A receiving approver cannot approve own custody');
assert.equal(items.find(r=>r.id==='s').action,true,'Sender reviews the current custody stage');
assert.deepEqual(filterWorkItems(items,{kind:'maintenance'}).map(x=>x.id),['m']);
assert.deepEqual(filterWorkItems(items,{state:'handover:fleet_review'}).map(x=>x.id),['h'],'Same stage names do not merge unrelated processes');
assert.deepEqual(filterWorkItems(items,{scope:'team'}).map(x=>x.id),['m']);
assert.equal(filterWorkItems(items,{scope:'mine'}).length,2);
assert.equal(filterWorkItems(items,{query:'مسؤول الأسطول'}).length,2);
assert.equal(filterWorkItems(items,{scope:'done'}).length,0);
console.log('PASS unified list: mixed types, party scope, separate stage filters, responsible search and independent custody approvals.');

const financial=workItems(c,{...data,advances:[{id:'m',overdue:true}]}).find(x=>x.id==='m');assert.equal(financial.unsettledAdvance,true);assert.equal(financial.overdue,true);

const late=workItems(c,{...data,settings:{stage_days:3},overdue_requests:[{id:'m',journey:{state_since:'2026-10-01T00:00:00Z'}}]}).find(x=>x.id==='m');assert.equal(late.dueAt,Date.parse('2026-10-04T00:00:00Z'));assert.ok(late.delayDays>0);

const now=Date.parse('2026-10-27T12:00:00Z'),day=86400000;
for(const state of ['closed','accepted']){assert.equal(isArchived({done:true,state,completedAt:new Date(now-7*day+1).toISOString()},now),false);assert.equal(isArchived({done:true,state,completedAt:new Date(now-7*day).toISOString()},now),true);assert.equal(isArchived({done:true,state,completedAt:null},now),true);}
assert.equal(isArchived({done:true,state:'rejected'},now),true);assert.equal(isArchived({done:false,state:'repair'},now),false);

const ended=[{id:"recent",done:true,state:"closed",completedAt:new Date(now-day).toISOString()},{id:"older",done:true,state:"accepted",completedAt:new Date(now-8*day).toISOString()},{id:"rejected",done:true,state:"rejected"},{id:"cancelled",done:true,state:"cancelled"},{id:"open",done:false,state:"repair"}];
assert.deepEqual(workboardItems(ended,true,now).map(x=>x.id),["recent","older","rejected","cancelled"]);
assert.deepEqual(workboardItems(ended,false,now).map(x=>x.id),["recent","open"]);
