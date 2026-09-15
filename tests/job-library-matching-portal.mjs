import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';

const root=resolve(new URL('..',import.meta.url).pathname),read=file=>readFileSync(resolve(root,file),'utf8');
const library=JSON.parse(read('job-library/data/atwar-job-library-v1.json'));
const page=read('assets/js/job-library-page.js');
const systems=read('assets/js/systems-config.js');
const landing=read('landing.html');

const business=library.jobs.find(job=>job.job_code==='JOB-054');
const adminGov=library.jobs.find(job=>job.job_code==='JOB-035');
assert.ok(business.aliases.includes('مشرف تطوير الاعمال'),'Business-development title must match without hamza');
assert.ok(adminGov.aliases.includes('أختصاصي شئون إدارية وحكومية'),'Legacy profile spelling must map to the governed role');
assert.ok(adminGov.aliases.includes('أخصائي شؤون إدارية وحكومية'),'Correct spelling must map to the governed role');
assert.match(page,/normalizeArabic/,'Arabic titles must not rely on literal matching');
assert.match(page,/normalizeArabic\(title\)===profileTitle/,'Suggestions must compare normalized titles and aliases');
assert.match(systems,/https:\/\/app\.powerbi\.com\/home\?experience=power-bi/,'Power BI portal URL is required');
assert.match(systems,/target: '_blank'/,'External systems must open safely in a new tab');
assert.match(landing,/repeat\(4,minmax/,'Desktop portal must fit four system cards');
console.log('Arabic job-title matching and Power BI portal audit passed.');
