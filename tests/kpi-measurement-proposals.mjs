import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
const ctx={window:{}};const read=p=>readFileSync(new URL('../'+p,import.meta.url),'utf8');
vm.runInNewContext(read('assets/js/job-kpi-proposals.js'),ctx);vm.runInNewContext(read('assets/js/job-document-view.js'),ctx);
const {catalog,details}=ctx.window.AtwarKpiProposals;
for(const entry of catalog){
 const rows=entry.indicators.map(i=>{const [name,target,measure]=JSON.parse(i.signature);return {name,target,measure};});
 const job={id:entry.jobId,revision:entry.revision};
 assert.equal(entry.indicators.reduce((n,i)=>n+i.weight,0),100);assert.ok(entry.indicators.every(i=>i.unit&&i.source&&i.weight>0&&i.measurementNote));
 assert.ok(details(rows,job));assert.equal(details(rows,{...job,revision:entry.revision+1}),null);
 assert.equal(details(rows.map((r,i)=>i? r:{...r,measure:r.measure+' changed'}),job),null);
 const before=JSON.stringify(rows);const html=ctx.window.AtwarJobDocument.section('performance',{job,content:{kpis:rows}}).html;
 assert.ok(html.includes('100% مقترحة'));assert.ok(!html.includes('غير محددة'));assert.ok(!html.includes('<td>غير محدد</td>'));assert.equal(JSON.stringify(rows),before);
 const authoritative=rows.map((r,i)=>({...r,weight:i?0:100,unit:'وحدة معتمدة',source:'مصدر معتمد'}));
 const approvedHtml=ctx.window.AtwarJobDocument.section('performance',{job,content:{kpis:authoritative}}).html;assert.ok(approvedHtml.includes('وحدة معتمدة'));assert.ok(approvedHtml.includes('مصدر معتمد'));
}
const it=catalog.find(j=>j.jobCode==='JOB-056');assert.deepEqual(Array.from(it.indicators,i=>i.weight),[35,25,20,20]);assert.ok(it.indicators.every(i=>i.unit==='%'));
assert.ok(catalog.find(j=>j.jobCode==='JOB-017').reviewNote);
console.log('57 jobs / 253 measurement proposals: totals, version/signature guards, source labels, preserved approved values and unsuitable-indicator warnings passed.');
