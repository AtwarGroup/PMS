import assert from 'node:assert/strict';import{readFileSync}from'node:fs';import{resolve}from'node:path';
const root=resolve(new URL('..',import.meta.url).pathname),read=f=>readFileSync(resolve(root,f),'utf8');
const sql=read('supabase/migrations/20260914_job_review_proposals_and_forms.sql'),library=read('assets/js/job-library-page.js'),profile=read('assets/js/job-profile-page.js'),forms=read('admin/forms.html')+read('assets/js/forms-admin.js');
assert.match(sql,/using \(private\.job_library_role\(\)='admin'\)\s+with check \(private\.job_library_role\(\)='admin'\)/i,'Only administrators may change the master description');
assert.match(sql,/create table if not exists public\.job_description_change_requests/i);assert.match(sql,/alter table public\.job_description_change_requests enable row level security/i);assert.match(sql,/manager_id=\(select auth\.uid\(\)\)/i);
assert.match(sql,/create table if not exists public\.form_library/i);assert.match(sql,/create table if not exists public\.job_description_forms/i);assert.doesNotMatch(sql,/user_metadata|service_role/i);
assert.match(library,/اقتراح تعديل/);assert.match(library,/مقارنة مقترحات المدير/);assert.match(library,/قبول وتطبيق/);assert.match(library,/مصفوفة الصلاحيات/);assert.match(library,/دون تغيير النسخة الرئيسية/);
assert.match(profile,/مهامي الوظيفية/);assert.match(profile,/حدود صلاحيتي/);assert.match(profile,/بطاقة قياس مؤشرات الأداء/);assert.match(profile,/published_snapshot/);assert.match(forms,/ربط بالوظيفة/);
console.log('Protected manager proposals, permission matrix, employee view and forms directory audit passed.');
