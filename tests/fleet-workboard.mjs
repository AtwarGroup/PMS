import assert from 'node:assert/strict';
import {workItems,filterWorkItems} from '../assets/js/fleet-workboard.mjs';
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
