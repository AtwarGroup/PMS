import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
const root=resolve(new URL('..',import.meta.url).pathname),read=f=>readFileSync(resolve(root,f),'utf8');
const sql=read('supabase/migrations/20260913_job_library_review_publication.sql');
const page=read('job-library/index.html')+read('assets/js/job-library-page.js'),profile=read('profile/job-description.html')+read('assets/js/job-profile-page.js');
const data=JSON.parse(read('job-library/data/atwar-job-library-v1.json'));
for(const [pattern,message] of [
  [/create table if not exists public\.job_descriptions/i,'Job library table is required'],
  [/create table if not exists public\.job_description_versions/i,'Immutable version history is required'],
  [/create table if not exists public\.job_description_comments/i,'Review comments are required'],
  [/alter table public\.job_descriptions enable row level security/i,'RLS must protect job descriptions'],
  [/private\.can_view_published_job\(id\)/i,'Employees must only read their own published description'],
  [/Reviewer cannot publish or archive/i,'Reviewers must not publish'],
  [/Manager approval is required before publication/i,'Publication must require manager approval'],
  [/published_snapshot:=jsonb_build_object/i,'Published version must remain stable while a new draft is reviewed'],
  [/job_descriptions_audit/i,'Every change must create an audit snapshot']
])assert.match(sql,pattern,message);
assert.doesNotMatch(sql,/user_metadata/i,'Authorization must not use editable user metadata');
assert.doesNotMatch(sql,/service_role/i,'Frontend migration must not expose service-role access');
assert.equal(data.jobs.length,56,'The reviewed library must contain all 56 jobs');
assert.equal(new Set(data.jobs.map(x=>x.job_code)).size,56,'Job codes must be unique');
assert.ok(data.jobs.every(x=>x.purpose&&x.content.responsibilities.length&&x.content.authorities.length),'Every job must have purpose, responsibilities and authorities');
assert.match(page,/إرسال للمدير/);assert.match(page,/موافقة المدير/);assert.match(page,/إعادة للتعديل/);assert.match(page,/اعتماد ونشر/);assert.match(page,/job_description_comments/);
assert.match(profile,/published_snapshot/,'Employee page must render only a published snapshot');
console.log(`Job-library governance audit passed: ${data.jobs.length} jobs, ${data.jobs.reduce((n,x)=>n+x.content.responsibilities.length,0)} responsibilities.`);
