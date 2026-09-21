import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';

const root=resolve(new URL('..',import.meta.url).pathname);
const library=JSON.parse(readFileSync(resolve(root,'job-library/data/atwar-job-library-v1.json'),'utf8'));
const page=readFileSync(resolve(root,'assets/js/job-library-page.js'),'utf8');
const expected=new Map([
  ['JOB-002','أخصائي شؤون موظفين والشؤون القانونية'],
  ['JOB-035','مسؤول الشؤون الإدارية والعلاقات الحكومية'],
  ['JOB-055','منسق علاقات الموظفين'],
  ['JOB-057','أخصائي موارد بشرية']
]);

for(const [code,title] of expected){
  const job=library.jobs.find(x=>x.job_code===code);
  assert.ok(job,`${code} must exist`);
  assert.equal(job.title,title,`${code} must use the current HR title`);
  assert.equal(job.content.review_metadata.edition,'hr-current-review-2026-09',`${code} must carry the current HR edition`);
  assert.ok(job.content.responsibilities.length>=12,`${code} must have a complete responsibility set`);
  assert.equal(job.reports_to_title,'يُحدد من التنظيم الحالي عند ربط الموظف',`${code} must use organization-based manager assignment`);
}

assert.equal(new Set(library.jobs.map(x=>x.job_code)).size,57,'Job codes must remain unique');
assert.match(page,/currentEdition&&currentEdition===sourceEdition/,'Professional updates must skip unchanged jobs');
assert.match(page,/تحديثات المحتوى الجديدة فقط/,'The administrator must be warned that only changed content is updated');
console.log('Current HR roles and selective content-update audit passed.');
