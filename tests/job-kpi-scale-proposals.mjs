import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
const read=p=>readFileSync(new URL('../'+p,import.meta.url),'utf8');
const ctx={window:{}};vm.runInNewContext(read('assets/js/job-kpi-proposals.js'),ctx);vm.runInNewContext(read('assets/js/job-document-view.js'),ctx);
const {find,catalog}=ctx.window.AtwarKpiProposals;
assert.equal(catalog.length,57);assert.equal(catalog.reduce((n,j)=>n+j.indicators.length,0),253);
for(const job of catalog)for(const row of job.indicators){
 assert.equal(row.scale.length,5);assert.deepEqual(Array.from(row.scale,s=>s.score),[1,2,3,4,5]);assert.ok(row.basis);for(const level of row.scale)assert.ok(level.label&&!/NaN|undefined/.test(level.label));
 const [name,target,measure]=JSON.parse(row.signature),item={name,target,measure,weight:20},before=JSON.stringify(item);
 assert.ok(find(item,{id:job.jobId}));assert.equal(find({...item,target:target+' changed'},{id:job.jobId}),null);assert.equal(find(item,{id:'other-job'}),null);
 const html=ctx.window.AtwarJobDocument.section('performance',{job:{id:job.jobId},content:{kpis:[item]}}).html;
 assert.ok(html.includes('حدود مقترحة للمراجعة والاعتماد'));assert.ok(!html.includes('حدود التقييم بانتظار الاعتماد'));assert.equal(JSON.stringify(item),before);
 const adopted={...item,scale:[1,2,3,4,5].map(score=>({score,label:'معتمد '+score}))};
 const adoptedHtml=ctx.window.AtwarJobDocument.section('performance',{job:{id:job.jobId},content:{kpis:[adopted]}}).html;assert.ok(adoptedHtml.includes('معتمد 5'));assert.ok(!adoptedHtml.includes('حدود مقترحة للمراجعة والاعتماد'));
}
const it=catalog.find(j=>j.jobCode==='JOB-056');assert.equal(it.indicators.length,4);assert.ok(it.indicators[0].scale[2].label.includes('95'));
const review=read('assets/js/job-review-page.js');assert.ok(review.includes(".eq('revision',job.revision)"));assert.ok(review.includes("status:'DRAFT'"));assert.ok(review.includes('scale_basis:proposal.basis'));
console.log('57 jobs / 253 proposed scales: exact matching, preserved weights, adopted-scale precedence, nonmutating display and draft adoption passed');
