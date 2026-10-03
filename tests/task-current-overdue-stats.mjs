import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import {calcDelay} from '../assets/js/tasks-core.mjs';
const source=readFileSync('assets/js/tasks-page.js','utf8');
const nodes=new Map();const ctx=vm.createContext({calcDelay:(...args)=>calcDelay(...args,new Date('2026-10-03T12:00:00')),tasks:[{status:'قيد الانتظار',end:'2026-10-01'},{status:'قيد التنفيذ',end:'2026-10-01'},{status:'بانتظار الاعتماد',end:'2026-10-01',submittedAt:Date.parse('2026-10-02T12:00:00')},{status:'مكتملة',end:'2026-10-01',actualEnd:'2026-10-02'},{status:'ملغاة',end:'2026-10-01'},{status:'قيد الانتظار',end:'2026-10-05'}],document:{getElementById(id){if(!nodes.has(id))nodes.set(id,{});return nodes.get(id)}},completedCountsByOwner:new Map([['x',4]]),isCompletedArchiveView:()=>false});
vm.runInContext(source.slice(source.indexOf('function isCurrentlyOverdue('),source.indexOf('async function exportToExcel()')),ctx);
assert.equal(ctx.isCurrentlyOverdue(ctx.tasks[2]),false,'Approval stage is excluded even when submission was late');assert.ok(calcDelay('2026-10-01',null,'بانتظار الاعتماد',Date.parse('2026-10-02T12:00:00'),[])>0,'Historical delay stays recorded');ctx.updateStats();assert.equal(nodes.get('stat-delayed').textContent,2);assert.equal(nodes.get('stat-approval').textContent,1);assert.equal(nodes.get('stat-total').textContent,4);assert.ok(source.includes("homeFilterValue==='OVERDUE' && !isCurrentlyOverdue(t)"));assert.ok(source.includes('const isOverdue=isCurrentlyOverdue;'));
console.log('Current overdue: pending/in-progress only, approval excluded, history retained and counters/filter/kanban share semantics.');
