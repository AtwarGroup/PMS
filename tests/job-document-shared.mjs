import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
const read=path=>readFileSync(new URL('../'+path,import.meta.url),'utf8');
const sandbox={window:{}};vm.runInNewContext(read('assets/js/job-document-view.js'),sandbox);
const {section}=sandbox.window.AtwarJobDocument;
const context={profile:{department:'الإدارة'},manager:{full_name:'المدير'},job:{id:'job'},snapshot:{title:'الوظيفة',purpose:'الغرض',revision:3},content:{responsibilities:[{text:'مسؤولية <script>',output:'المخرج',evidence:'الدليل'}],reports:[{name:'تقرير',frequency:'شهري',recipient:'المدير'}],authorities:[{text:'الصلاحية',scope:'النطاق',limit:'الحد',escalation:'التصعيد'}],kpis:[{name:'المؤشر',weight:100,target:'99%',scale:[1,2,3,4,5].map(score=>({score,label:'حد '+score}))}],qualifications:{education:'المؤهل'}}};
const tasks=section('tasks',context).html;assert.ok(tasks.includes('&lt;script&gt;'));assert.ok(!tasks.includes('<script>'));assert.ok(tasks.includes('المخرج'));assert.ok(tasks.includes('تقرير'));
const authorities=section('authority',context).html;for(const text of ['النطاق','الحد','التصعيد'])assert.ok(authorities.includes(text));
const kpis=section('performance',context).html;assert.ok(kpis.includes('BALANCED SCORECARD FRAMEWORK'));assert.ok(kpis.includes('100%'));for(let score=1;score<=5;score++)assert.ok(kpis.includes('حد '+score));
assert.ok(section('description',context).html.includes('المدير'));
for(const path of ['profile/index.html','profile/job-description.html','team/employee.html','job-library/review.html']){assert.ok(read(path).includes('job-document.css?v=2.5.14'));assert.ok(read(path).includes('job-document-view.js?v=2.5.21'));assert.ok(read(path).includes('job-kpi-proposals.js?v=2.5.21'));}
for(const path of ['assets/js/team-employee-page.js','assets/js/job-profile-page.js','assets/js/job-review-page.js'])assert.ok(read(path).includes('AtwarJobDocument'));
assert.ok(read('assets/js/job-profile-page.js').includes("sb.rpc('acknowledge_job_description'"));
assert.ok(read('assets/js/job-review-page.js').includes('proposalActions(key,index)'));
console.log('Shared job document: route integration, escaped content, published metadata, reports, boundaries, weights and five levels passed');
