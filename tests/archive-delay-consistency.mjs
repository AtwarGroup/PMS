import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import {calcDelay,localDateISO} from '../assets/js/tasks-core.mjs';
process.env.TZ='Asia/Riyadh';
const page=readFileSync(new URL('../assets/js/tasks-page.js',import.meta.url),'utf8');
const source=page.slice(page.indexOf('function updateStats(){'),page.indexOf('async function exportToExcel(){'));
const nodes={};
const tasks=[
 {status:'مكتملة',start:'2026-09-30',end:'2026-09-30',actualEnd:'2026-09-30',submittedAt:Date.parse('2026-09-30T21:03:00Z'),completedAt:Date.parse('2026-09-30T21:04:00Z')},
 {status:'مكتملة',start:'2026-09-30',end:'2026-09-30',actualEnd:'2026-10-04',submittedAt:Date.parse('2026-09-30T09:00:00Z'),completedAt:Date.parse('2026-10-04T09:00:00Z')},
 {status:'مكتملة',start:'2026-09-30',end:'2026-10-01',actualEnd:'2026-09-30'}
];
vm.runInNewContext(source+'\nupdateStats();',{Date,tasks,calcDelay,localDateISO:d=>localDateISO(d||new Date('2026-10-01T09:00:00Z')),isCompletedArchiveView:()=>true,document:{getElementById:id=>nodes[id]??=( {})}});
assert.equal(nodes['stat-total'].textContent,3);
assert.equal(nodes['stat-completed'].textContent,2,'Completion month uses the local completion timestamp');
assert.equal(nodes['stat-progress'].textContent,2,'Approval waiting must not count as late work');
assert.equal(nodes['stat-pending'].textContent,1,'After-midnight submission must match the card delay');
console.log('Archive delay and local completion month regression passed');
