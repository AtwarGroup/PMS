process.on('uncaughtException',e=>{console.error(e.message,e.where||'',e.stack?.split('\n').slice(1,4).join('\n'));process.exit(1)});
import {createTestDB,ids} from './fleet-test-db.mjs';
import {readFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
const {db}=await createTestDB();
for(const f of ['20261026105140_it_support_foundation.sql','20261026121744_it_support_purchase_and_attachments.sql'])await db.exec(await readFile('supabase/migrations/'+f,'utf8'));
await db.exec('create table private.recruitment_holidays(day date primary key,label text)');
await db.exec(await readFile('supabase/migrations/20261026131824_it_support_target_deadlines.sql','utf8'));
await db.exec(await readFile('supabase/migrations/20261031231420_it_service_desk_v2.sql','utf8'));
await db.exec("update public.profiles set allowed_modules=array_append(allowed_modules,'it_support')");
for(const [u,perm]of [[ids.fleet,'operate'],[ids.manager,'supervise'],[ids.accountant,'accounting'],[ids.accountant2,'pay']])await db.query("update public.profiles set permissions=array[$2]where id=$1",[u,'it_support.'+perm]);

async function rpc(u,n,args=[]){await db.exec('begin');try{await db.exec('set local role authenticated');await db.query("select set_config('request.jwt.claims',$1,true)",[JSON.stringify({sub:u,role:'authenticated'})]);const r=await db.query(`select public.${n}(${args.map((_,i)=>'$'+(i+1)).join(',')}) result`,args);await db.exec('commit');return r.rows[0].result;}catch(e){await db.exec('rollback');throw e;}}
await db.exec(`update public.profiles p set full_name=h.full_name,employee_code=h.employee_code,department=d.name,job_title=t.title,join_date=h.join_date,manager_id=m.profile_id from private.hr_employees h join private.hr_departments d on d.id=h.department_id join private.hr_titles t on t.id=h.title_id left join private.hr_employees m on m.id=h.manager_id where p.id=h.profile_id`);
await rpc(ids.admin,'it_support_configure',[ids.fleet,ids.manager]);await rpc(ids.admin,'it_purchase_configure',[ids.accountant]);
const create=(p={})=>rpc(ids.driver,'it_support_create',[JSON.stringify({title:'طلب تجريبي للتحقق',description:'وصف تجريبي كاف للتحقق من سلامة دورة الطلب',service_key:'device_fault',priority:4,...p})]);
const detail=id=>rpc(ids.driver,'it_support_detail',[id]);
const action=async(u,id,a,d={note:'توضيح تجريبي للإجراء المطلوب'})=>rpc(u,'it_support_action',[id,(await detail(id)).ticket.revision,a,JSON.stringify(d)]);

for(const f of ['it-support-followup.sql','it-support-supervision.sql','it-support-resolved-reply-notice.sql'])await db.exec(await readFile('scripts/'+f,'utf8'));
const a=await create();await action(ids.fleet,a,'resolve',{note:'تم إصلاح المشكلة وإعادة تشغيل الخدمة'});
const notices=async()=>(await db.query('select * from private.it_support_solution_notices order by sent_at')).rows;
assert.equal((await notices()).length,1);assert.equal((await notices())[0].recipient_id,ids.driver);
let n=(await db.query("select * from public.notifications where it_support_ticket_id=$1 and title like 'تم تقديم الحل%'",[a])).rows;assert.equal(n.length,1);
const notification=n[0].id;await assert.rejects(rpc(ids.outsider,'it_support_notification_open',[notification]));assert.equal((await rpc(ids.driver,'it_support_notification_open',[notification])).ticket_id,a);assert((await db.query('select read_at from public.notifications where id=$1',[notification])).rows[0].read_at);
await action(ids.fleet,a,'comment',{note:'تأكد من عمل الخدمة بعد إعادة التشغيل'});assert.equal((await notices()).length,1);assert.equal((await db.query('select count(*) n from public.notifications where it_support_ticket_id=$1 and recipient_id=$2',[a,ids.driver])).rows[0].n,2);
assert.equal((await db.query('select private.it_support_solution_reminders() n')).rows[0].n,0);
await db.query("update private.it_support_tickets set resolved_at=now()-interval '25 hours' where id=$1",[a]);
assert.equal((await db.query('select private.it_support_solution_reminders() n')).rows[0].n,1);assert.equal((await db.query('select private.it_support_solution_reminders() n')).rows[0].n,0);assert.equal((await notices()).length,2);
await action(ids.driver,a,'reopen');assert.equal((await db.query('select private.it_support_solution_reminders() n')).rows[0].n,0);
await action(ids.fleet,a,'resolve',{note:'تمت معالجة المشكلة مرة أخرى بشكل كامل'});assert.equal((await notices()).length,3);await action(ids.driver,a,'close',{note:'تم التأكد من نجاح الحل',rating:4});assert.equal((await db.query('select private.it_support_solution_reminders() n')).rows[0].n,0);
await db.query("update private.it_support_tickets set created_at=now()-interval '10 hours',resolved_at=now()-interval '2 hours',sla_paused_seconds=3600 where id=$1",[a]);
const b=await create(),c=await create();await action(ids.fleet,b,'waiting_employee',{note:'يرجى إرسال تفاصيل الجهاز المستخدم'});await action(ids.fleet,c,'waiting_vendor',{note:'تحتاج المشكلة إلى دعم من المزود',escalation_to:'مزود الخدمة'});await db.query("update private.it_support_tickets set due_at=now()-interval '1 day'where id=any($1::uuid[])",[[b,c]]);
const p=await create({service_key:'purchase',quantity:1,quote_provider:'specialist'});
await assert.rejects(rpc(ids.driver,'it_support_supervisor_dashboard'));await assert.rejects(rpc(ids.fleet,'it_support_supervisor_dashboard'));
const dashboard=await rpc(ids.manager,'it_support_supervisor_dashboard');assert.equal(dashboard.summary.open,2);assert.equal(dashboard.summary.overdue,1);assert.equal(dashboard.summary.escalated,1);assert.equal(dashboard.summary.waiting_information,1);assert.equal(dashboard.summary.waiting_confirmation,0);assert.equal(dashboard.summary.average_resolution_hours,7);assert.equal(dashboard.summary.average_rating,4);assert.equal(dashboard.summary.rating_count,1);assert.equal(dashboard.queue.length,2);assert(!dashboard.queue.some(t=>t.id===p));assert(!dashboard.queue.some(t=>t.events||t.solution));assert.equal((await rpc(ids.admin,'it_support_supervisor_dashboard')).summary.overdue,1);
async function denied(sql){await db.exec('begin');try{await db.exec('set local role authenticated');await db.query("select set_config('request.jwt.claims',$1,true)",[JSON.stringify({sub:ids.driver,role:'authenticated'})]);await db.exec(sql);}finally{await db.exec('rollback');}}
await assert.rejects(denied('select private.it_support_solution_reminders()'),/permission denied/);await assert.rejects(denied('select * from private.it_support_solution_notices'),/permission denied/);
await db.query("update public.profiles set allowed_modules=array_remove(allowed_modules,'it_support')where id=$1",[ids.driver]);await assert.rejects(rpc(ids.driver,'it_support_notification_open',[notification]));
assert.equal((await db.query("select count(*) n from pg_proc p join pg_namespace s on s.oid=p.pronamespace where s.nspname='public'and p.proname in('it_support_supervisor_dashboard','it_support_notification_open')and(p.prosecdef or has_function_privilege('anon',p.oid,'execute'))")).rows[0].n,0);
// A specialist's own resolved request routes independent confirmation to the supervisor.
const own=await rpc(ids.fleet,'it_support_create',[JSON.stringify({title:'بلاغ خاص بأخصائي التقنية',description:'اختبار تأكيد الحل من طرف مستقل عن أخصائي التقنية',service_key:'device_fault',priority:4})]);
await rpc(ids.fleet,'it_support_action',[own,1,'resolve',JSON.stringify({note:'تم إصلاح العطل الخاص بأخصائي التقنية'})]);
assert.equal((await db.query('select recipient_id from private.it_support_solution_notices where ticket_id=$1',[own])).rows[0].recipient_id,ids.manager);
// Reminders do not bypass a disabled recipient or send sooner than the minimum interval.
await db.query("update private.it_support_tickets set resolved_at=now()-interval '25 hours'where id=$1",[own]);
await db.query("update public.profiles set active=false where id=$1",[ids.manager]);assert.equal((await db.query('select private.it_support_solution_reminders() n')).rows[0].n,0);await db.query("update public.profiles set active=true where id=$1",[ids.manager]);
assert.equal((await db.query('select private.it_support_solution_reminders() n')).rows[0].n,1);
assert.equal((await db.query('select private.it_support_solution_reminders() n')).rows[0].n,0);
console.log('PASS immediate solution notice, recipient routing, authenticated opening, reminder threshold/deduplication, stop on reopen/close, new resolution cycle, supervisor scope, accurate averages, purchase exclusion, private helper access and revoked module.');
await db.close();
