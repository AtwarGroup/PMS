import {createTestDB,ids} from './fleet-test-db.mjs';
import {readFile} from 'node:fs/promises';
export async function createITTestDB(){
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

return {db,rpc,create,detail,action,ids};
}
