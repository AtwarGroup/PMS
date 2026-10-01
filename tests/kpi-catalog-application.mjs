import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {applyCatalog,catalog,buildSql} from '../scripts/apply-kpi-catalog.mjs';
const jobs=catalog.map(e=>({job_code:e.jobCode,revision:10,kpis:e.indicators.map(p=>{const [name,target,measure]=JSON.parse(p.signature);return {name,target,measure,frequency:'شهري',weight:1};})}));
const original=JSON.stringify(jobs),result=applyCatalog(jobs);
assert.equal(result.length,57);assert.equal(result.reduce((n,j)=>n+j.kpis.length,0),253);
for(const [i,job] of result.entries()){
 assert.equal(job.kpis.reduce((n,k)=>n+k.weight,0),100);
 for(const [n,k] of job.kpis.entries()){
  const p=catalog[i].indicators[n];assert.equal(k.weight,p.weight);assert.equal(k.source,p.source);assert.equal(k.unit,p.unit);
  assert.equal(JSON.stringify(k.scale),JSON.stringify(p.scale));assert.equal(k.frequency,'شهري');assert.equal(k.measure,jobs[i].kpis[n].measure);
 }
}
assert.equal(JSON.stringify(jobs),original);
assert.throws(()=>applyCatalog(jobs.slice(1)),/coverage/);
const changed=structuredClone(jobs);changed[0].kpis[0].target+=' changed';assert.throws(()=>applyCatalog(changed),/mismatch/);
const sql=buildSql(jobs);assert.match(sql,/set local role authenticated/);assert.match(sql,/for update/);assert.match(sql,/ATWAR_CONFLICT/);assert.doesNotMatch(sql,/set published_snapshot|disable trigger|session_replication_role/);
for(const file of ['job-review-page.js','job-library-page.js']){
 const source=readFileSync(new URL('../assets/js/'+file,import.meta.url),'utf8');
 assert.doesNotMatch(source,/useMeasurementProposalsBtn|useScaleProposalsBtn|restoreApprovalBtn/);
}
console.log('Direct application: all 253 indicators, exact catalogue values, concurrency guard, unchanged measurement formulas and safe review routing passed.');
