import {createTestDB} from './fleet-test-db.mjs';
import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
process.on('uncaughtException',e=>{console.error(e.message,e.where||'');process.exit(1)});
const {db}=await createTestDB();
await db.exec("alter table public.job_descriptions add column published_snapshot jsonb;alter table public.job_descriptions add column purpose text;alter table public.job_descriptions add column content jsonb;create function auth.role() returns text language sql stable as $$select nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role'$$;");
for(const f of ['20261023142622_recruitment_foundation.sql','20261023142952_recruitment_salary_reference_metadata.sql','20261023143441_recruitment_resume_storage.sql','20261023150534_recruitment_public_upload_session.sql','20261023191845_recruitment_approved_workflow.sql','20261023194438_recruitment_batch_validation.sql'])await db.exec(await fs.readFile('supabase/migrations/'+f,'utf8'));
await db.exec(await fs.readFile('tests/fixtures/recruitment-live-functions.sql','utf8'));
const id=n=>'70000000-0000-4000-8000-'+String(n).padStart(12,'0');
const perms={2:['recruitment.approve'],3:['recruitment.development'],4:['recruitment.finance'],5:['recruitment.personnel'],6:['recruitment.manage']};
for(let n=1;n<=8;n++){
 await db.query("insert into public.profiles(id,email,full_name,role,allowed_modules,permissions)values($1,$2,$3,$4,array['recruitment'],$5)",[id(n),`release-${n}@example.test`,'حساب اختبار '+n,n===1?'admin':n>=7?'manager':'employee',perms[n]||[]]);
 await db.query("insert into private.hr_employees(id,employee_code,full_name,email,department_id,section_id,title_id,profile_id,manager_id,join_date,effective_from) values($1,$2,$3,$4,'10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000003',$1,$5,current_date,current_date)",[id(n),String(88000+n),'حساب اختبار '+n,`release-${n}@example.test`,n===8?id(7):null]);
}
await db.exec(`insert into public.job_descriptions(id,job_code,title,purpose,content,published_snapshot)values('20000000-0000-4000-8000-000000000001','QA-RELEASE','وظيفة اختبار','هدف تجريبي','{"qualifications":{"skills":"مهارات تجريبية"}}','{"title":"وظيفة اختبار","content":{"qualifications":{"skills":"مهارات تجريبية"}}}');insert into private.recruitment_salary_reference(id,title,grade,saudi_min,saudi_max,expat_min,expat_max,source_revision,benefits)values('20000000-0000-4000-8000-000000000002','وظيفة اختبار','T7',1000,20000,1000,20000,'fixture','{"text":"المزايا المعتمدة للاختبار"}');alter table private.recruitment_requests alter column number restart with 11;`);
await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:id(8),role:'authenticated'})]);
await db.query('select public.recruitment_request_create($1)',[JSON.stringify({job_id:'20000000-0000-4000-8000-000000000001',department_id:'10000000-0000-4000-8000-000000000001',section_id:'10000000-0000-4000-8000-000000000002',company:'بيانات تاريخية محفوظة',location:'جدة',headcount:1,reason:'احتياج اختباري محفوظ',route:'referral',target_date:'2027-01-01',hr_id:id(5),finance_id:id(4),approver_id:id(2),recruiter_id:id(6),development_id:id(3),department_approver_id:id(7),supervisor_id:id(8),request_type:'new',interviewer_ids:[id(8),id(7)],criteria:[{key:'technical',label:'التقييم الفني',weight:100}]})]);
const historical=(await db.query("select to_jsonb(r) value from private.recruitment_requests r where number=11")).rows[0].value;
await db.exec(await fs.readFile('scripts/releases/recruitment/preflight.sql','utf8'));
const sql=await fs.readFile('scripts/releases/recruitment/upgrade.sql','utf8');
for(let i=0;i<2;i++)await db.exec(sql);
const preserved=(await db.query("select to_jsonb(r)-'interview_manager_id' value from private.recruitment_requests r where number=11")).rows[0].value;assert.deepEqual(preserved,historical);
await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:id(1),role:'authenticated'})]);
const cfg=(await db.query('select public.recruitment_route_settings() c')).rows[0].c;
await db.query("select public.recruitment_route_settings('save',$1)",[JSON.stringify({revision:cfg.revision,approver_id:id(2),recruiter_id:id(6),development_id:id(3)})]);
for(const f of ['test-cycle.sql','test-email.sql'])await db.exec(await fs.readFile('scripts/releases/recruitment/'+f,'utf8'));
// Normalize existing grants into roles; effective access and unrelated grants must stay identical.
await db.query("insert into private.access_direct_tasks(profile_id,permissions)select id,permissions from public.profiles where id=any($1::uuid[])on conflict(profile_id)do update set permissions=excluded.permissions",[[id(2),id(3),id(6)]]);
await db.query("update private.access_direct_tasks set permissions=permissions||array['recruitment.personnel'] where profile_id=$1",[id(6)]);
await db.query('select private.access_rebuild_tasks($1)',[id(6)]);
const accessBefore=(await db.query("select id,permissions,allowed_modules from public.profiles order by id")).rows;
const roleSql=await fs.readFile('scripts/releases/recruitment/unify-access-roles.sql','utf8');
await db.exec(roleSql);await db.exec(roleSql);
assert.deepEqual((await db.query("select id,permissions,allowed_modules from public.profiles order by id")).rows,accessBefore);
assert.equal((await db.query("select count(*)::int n from private.access_assignments where profile_id=any($1::uuid[])",[[id(2),id(3),id(6)]])).rows[0].n,3);
const role=(await db.query("select * from private.access_roles where name='معتمد احتياجات وعروض التوظيف'")).rows[0];
await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:id(1),role:'authenticated'})]);
await db.query("select private.access_role_save($1,$2,$3,$4,false,$5)",[role.id,role.revision,role.name,role.description,JSON.stringify([{permission:'recruitment.approve',scope:'all'}])]);
assert.equal((await db.query("select 'recruitment.approve'=any(permissions) allowed from public.profiles where id=$1",[id(2)])).rows[0].allowed,false);
console.log('PASS role normalization: exact access preservation, repeat application, visible assignments and role revocation');
// Approved five-owner workflow supersedes the earlier simplified baseline.
await db.query("select private.access_role_save($1,$2,$3,$4,true,$5)",[role.id,role.revision+1,role.name,role.description,JSON.stringify([{permission:'recruitment.approve',scope:'all'}])]);
await db.exec(await fs.readFile('scripts/releases/recruitment/approved-workflow.sql','utf8'));
await db.exec(await fs.readFile('scripts/releases/recruitment/approved-workflow.sql','utf8'));
const five=(await db.query('select public.recruitment_route_settings() c')).rows[0].c;
await db.query("select public.recruitment_route_settings('save',$1)",[JSON.stringify({revision:five.revision,finance_id:id(4),hr_id:id(5),approver_id:id(2),recruiter_id:id(6),development_id:id(3)})]);
const approvedCycle=await fs.readFile('scripts/releases/recruitment/test-approved-cycle.sql','utf8');
await db.exec(approvedCycle);
const exceptionCycle=approvedCycle.replace("-- FINANCE_DECISION",`perform public.recruitment_request_action(r.id,(select revision from private.recruitment_requests where id=r.id),'reject','{"note":"عدم توفر موازنة معتمدة"}');
assert(select status='finance_exception'from private.recruitment_requests where id=r.id),'finance rejection must route automatically to CEO';
assert(select owner_id=ceo from private.recruitment_tasks where key='request:'||r.id),'finance exception task owner';
perform set_config('request.jwt.claims',jsonb_build_object('sub',ceo,'role','authenticated')::text,true);
perform public.recruitment_request_action(r.id,(select revision from private.recruitment_requests where id=r.id),'approve','{"note":"اعتماد استثناء الموازنة"}');
perform set_config('request.jwt.claims',jsonb_build_object('sub',finance,'role','authenticated')::text,true);
-- SKIP_FINANCE_APPROVE`)
.replace(" perform public.recruitment_request_action(r.id,(select revision from private.recruitment_requests where id=r.id),'approve','{\"note\":\"مراجعة الموازنة واعتمادها\",\"budget_checked\":true}');",'')
.replace('-- HR_DECISION',`perform public.recruitment_request_action(r.id,(select revision from private.recruitment_requests where id=r.id),'reject','{"note":"طلب استثناء الاحتياج والتوطين"}');
assert(select status='hr_exception'from private.recruitment_requests where id=r.id),'personnel rejection must route automatically to development';
perform set_config('request.jwt.claims',jsonb_build_object('sub',dev,'role','authenticated')::text,true);`)
.replace('-- OFFER_HR_DECISION',`perform public.recruitment_offer_action(o,'reject','طلب استثناء من مراجعة شؤون الموظفين');
assert(select state='development_review'from private.recruitment_offers where id=o),'offer rejection routes to development';
assert(select owner_id=dev from private.recruitment_tasks where key='offer:'||o),'offer exception task owner';
perform set_config('request.jwt.claims',jsonb_build_object('sub',dev,'role','authenticated')::text,true);`);
await db.exec(exceptionCycle);
const exceptionDenied=`begin;do $test$declare r private.recruitment_requests;stage text;actor uuid;begin
for stage in select unnest(array['finance_exception','hr_exception'])loop
select * into strict r from private.recruitment_requests where number=11;
r.id:=gen_random_uuid();r.public_token:=gen_random_uuid();r.number:=nextval(pg_get_serial_sequence('private.recruitment_requests','number'));r.revision:=1;r.status:=stage;r.created_by:='70000000-0000-4000-8000-000000000008';r.hr_id:='70000000-0000-4000-8000-000000000005';r.finance_id:='70000000-0000-4000-8000-000000000004';r.approver_id:='70000000-0000-4000-8000-000000000002';r.development_id:='70000000-0000-4000-8000-000000000003';r.recruiter_id:='70000000-0000-4000-8000-000000000006';r.route:='advertised';
insert into private.recruitment_requests overriding system value select r.*;
actor:=case stage when 'finance_exception'then r.approver_id else r.development_id end;
perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
perform public.recruitment_request_action(r.id,1,'reject','{"note":"عدم اعتماد الاستثناء للاختبار"}');
assert(select status='rejected'from private.recruitment_requests where id=r.id),'rejected exception must stop request';
assert not exists(select 1 from private.recruitment_batches where request_id=r.id),'no sourcing after rejected exception';
end loop;end $test$;rollback;`;
await db.exec(exceptionDenied);
const approveOffer=" perform public.recruitment_offer_action(o,'approve','اعتماد العرض التجريبي');";
const rejectedOffer=approvedCycle.split(approveOffer)[0]+`perform public.recruitment_offer_action(o,'reject','إعادة العرض للتعديل من الرئيس التنفيذي');
assert(select state='returned'from private.recruitment_offers where id=o),'rejected final offer returns for preparation';
perform set_config('request.jwt.claims',jsonb_build_object('sub',recruiter,'role','authenticated')::text,true);
denied:=false;begin perform public.recruitment_offer_action(o,'sent','محاولة إرسال عرض غير معتمد');exception when raise_exception or insufficient_privilege then denied:=true;end;assert denied,'cannot send rejected offer';
end $test$;rollback;`;
await db.exec(rejectedOffer);
const separateRoles=await fs.readFile('scripts/releases/recruitment/separate-approved-roles.sql','utf8');
await db.exec(separateRoles);await db.exec(separateRoles);
assert.equal((await db.query("select 'recruitment.personnel'=any(permissions) allowed from public.profiles where id=$1",[id(6)])).rows[0].allowed,false,'recruiter must lose personnel review grant');
for(const [n,name]of [[5,'مراجع شؤون الموظفين للتوظيف'],[4,'مراجع موازنة التوظيف']]){
 const rr=(await db.query('select id from private.access_roles where name=$1',[name])).rows[0].id;
 await db.query('select private.access_assign($1,$2,$3)',[id(n),[rr],[]]);
}
await db.exec(approvedCycle);
console.log('PASS independent recruitment/personnel/finance roles; exception rejection stops sourcing; CEO rejection prevents offer sending');
console.log('PASS approved workflow: finance then personnel then CEO, automatic budget/personnel exceptions, HR and department offer review, independent owners, queues, notifications and completion');
await db.exec('set role anon');await assert.rejects(db.query('select * from private.recruitment_email_outbox'));await db.exec('reset role');
console.log('PASS current-live schema upgrade, repeat application, unchanged history, three-role setup, full current recruitment workflow and email authorization');await db.close();
