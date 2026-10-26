import {createTestDB,ids} from './fleet-test-db.mjs';
import {readFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
const {db}=await createTestDB();
await db.exec(await readFile('supabase/migrations/20261026105140_it_support_foundation.sql','utf8'));
await db.exec(await readFile('supabase/migrations/20261026121744_it_support_purchase_and_attachments.sql','utf8'));
await db.exec('create table private.recruitment_holidays(day date primary key,label text);');
await db.exec(await readFile('supabase/migrations/20261026131824_it_support_target_deadlines.sql','utf8'));
const due=async(start,p)=>(await db.query('select private.it_support_due($1,$2)as due',[start,p])).rows[0].due;
assert.equal(new Date(await due('2026-10-29T13:00:00Z',1)).toISOString(),'2026-10-29T17:00:00.000Z');
// Thursday 16:00 Riyadh -> one working hour Thursday + seven Sunday.
assert.equal(new Date(await due('2026-10-29T13:00:00Z',2)).toISOString(),'2026-11-01T12:00:00.000Z');
// Two full 9-hour working days, starting Sunday 08:00 Riyadh.
assert.equal(new Date(await due('2026-10-25T05:00:00Z',3)).toISOString(),'2026-10-26T14:00:00.000Z');
assert.equal(new Date(await due('2026-10-25T05:00:00Z',4)).toISOString(),'2026-10-29T14:00:00.000Z');
await db.exec("insert into private.recruitment_holidays values('2026-11-01','اختبار إجازة');");
assert.equal(new Date(await due('2026-10-29T13:00:00Z',2)).toISOString(),'2026-11-02T12:00:00.000Z');
await db.exec("update public.profiles set allowed_modules=array_append(allowed_modules,'it_support');");
async function rpc(user,name,args=[]){await db.exec('begin');try{await db.exec('set local role authenticated');await db.query("select set_config('request.jwt.claims',$1,true)",[JSON.stringify({sub:user,role:'authenticated'})]);const r=await db.query(`select public.${name}(${args.map((_,i)=>'$'+(i+1)).join(',')}) result`,args);await db.exec('commit');return r.rows[0].result;}catch(e){await db.exec('rollback');throw e;}}
await db.query("update public.profiles set permissions=array['it_support.operate']where id=$1",[ids.fleet]);
await db.query("update public.profiles set permissions=array['it_support.supervise']where id=$1",[ids.manager]);
await rpc(ids.admin,'it_support_configure',[ids.fleet,ids.manager]);
const data={title:'اختبار مهلة الدعم',description:'اختبار تاريخ آلي دون تواريخ من المتصفح',service_key:'device_fault',impact:3,urgency:3,due_at:'2099-01-01'};
const id=await rpc(ids.driver,'it_support_create',[JSON.stringify(data)]);
let t=(await rpc(ids.driver,'it_support_detail',[id])).ticket;
assert.equal(new Date(t.due_at)-new Date(t.created_at),4*3600000);
const purchase=await rpc(ids.driver,'it_support_create',[JSON.stringify({...data,service_key:'purchase'})]);
t=(await rpc(ids.driver,'it_support_detail',[purchase])).ticket;assert.equal(t.due_at,null);
await rpc(ids.manager,'it_support_action',[purchase,1,'approve',JSON.stringify({note:'اعتماد تجريبي للشراء'})]);
t=(await rpc(ids.driver,'it_support_detail',[purchase])).ticket;assert(t.due_at&&t.sla_started_at);
await rpc(ids.fleet,'it_support_action',[id,1,'resolve',JSON.stringify({note:'حل تجريبي للاختبار وإيقاف احتساب التأخر'})]);
const d=(await rpc(ids.driver,'it_support_detail',[id])).ticket;assert.equal(d.due_at,(await rpc(ids.driver,'it_support_detail',[id])).ticket.due_at);
await db.close();console.log('IT SLA: priorities, business hours/weekends/holidays, automatic dates and purchase approval start passed.');
