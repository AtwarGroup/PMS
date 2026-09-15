import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';

const root = resolve(new URL('..', import.meta.url).pathname);
const read = file => readFileSync(resolve(root,file),'utf8');
const library = JSON.parse(read('job-library/data/atwar-job-library-v1.json'));
const reviewPage = read('job-library/review.html');
const reviewJs = read('assets/js/job-review-page.js');
const reviewCss = read('assets/css/job-review.css');
const indexJs = read('assets/js/job-library-page.js');

assert.equal(library.jobs.length,56,'Professional library must preserve all 56 jobs');
for (const job of library.jobs) {
  const content = job.content || {};
  assert.ok((job.purpose || '').trim().length >= 40,`${job.job_code} needs a clear purpose`);
  assert.ok(content.responsibilities.length >= 8,`${job.job_code} needs at least 8 responsibilities`);
  assert.ok(content.authorities.length >= 4,`${job.job_code} needs at least 4 authorities`);
  assert.ok(content.kpis.length >= 4,`${job.job_code} needs at least 4 KPIs`);
  assert.ok(content.reports.length >= 2,`${job.job_code} needs at least 2 reports/outputs`);
  assert.ok(content.qualifications?.education,`${job.job_code} needs qualifications`);
  assert.equal(content.review_metadata?.manager_source,'profiles.manager_id',`${job.job_code} must use the recorded direct manager`);
  const texts = content.responsibilities.map(item => String(typeof item === 'string' ? item : item.text || '').replace(/[\s.،؛]+/g,' ').trim());
  assert.equal(new Set(texts).size,texts.length,`${job.job_code} contains duplicate responsibilities`);
}

assert.match(reviewPage,/review-layout/,'Review must use a dedicated readable page');
assert.match(reviewPage,/مصفوفة الصلاحيات/);
assert.match(reviewJs,/manager_id/,'Manager source must use the profile relationship');
assert.match(reviewJs,/المدير المباشر المسجل في الصلاحيات/,'Manager source must be visible and explicit');
assert.match(reviewJs,/الحالة محالة لمسؤول النظام/,'Conflicting manager assignments must be escalated');
assert.match(reviewJs,/اقتراح تعديل/);
assert.match(reviewJs,/دون تغيير النسخة الرئيسية/);
assert.match(reviewJs,/النسخة المنشورة للموظف دون تغيير/);
assert.match(indexJs,/prepareProfessionalDrafts/,'Admin must explicitly prepare reviewed drafts');
assert.match(indexJs,/published_snapshot|النسخة المنشورة/,'Professional sync must preserve the published employee snapshot');
assert.doesNotMatch(reviewCss,/position:fixed[^}]*inset:0/,'The new review must not be a full-screen modal');

const responsibilities = library.jobs.reduce((sum,job) => sum + job.content.responsibilities.length,0);
console.log(`Professional job-library review passed: ${library.jobs.length} jobs, ${responsibilities} responsibilities.`);
