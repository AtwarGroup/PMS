import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createTestDB,ids} from './fleet-test-db.mjs';
const {db}=await createTestDB();
try{
 await db.exec(`create table public.tasks(id uuid primary key,deleted_at timestamptz,revision integer default 1,task_type text default 'normal',status text default 'قيد التنفيذ');
 alter table public.admin_audit_log add column target_type text;
 create function private.can_view_task(uuid)returns boolean language sql as 'select true';
 create function private.can_edit_task_content(uuid)returns boolean language sql as 'select true';`);
 await db.exec(await readFile('supabase/migrations/20261009222609_task_followup_details.sql','utf8'));
 const before=(await db.query(`select p.oid,pg_get_functiondef(p.oid) definition,p.proacl::text acl,p.proowner from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in('public','private') and p.prokind='f' and p.prosrc like '%40001%'`)).rows;
 assert(before.length>10,'Real task, fleet, HR and account functions are covered');
 const sql=await readFile('supabase/migrations/20261026100805_business_conflict_http409.sql','utf8');
 await db.exec(sql);await db.exec(sql);
 for(const prior of before){const after=(await db.query('select pg_get_functiondef(oid) definition,proacl::text acl,proowner from pg_proc where oid=$1',[prior.oid])).rows[0];assert.equal(after.definition,prior.definition.replace(/errcode\s*=\s*'40001'/g,"errcode='PT409'"));assert.equal(after.acl,prior.acl);assert.equal(after.proowner,prior.proowner);}
 const task='99999999-0000-4000-8000-000000000001';
 await db.query('insert into public.tasks(id)values($1)',[task]);
 await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:ids.admin,role:'authenticated'})]);
 async function save(followRevision,taskRevision){return db.query("select public.save_task_followup($1,true,'reason','next','assignee',null,$2,$3) result",[task,followRevision,taskRevision]);}
 await assert.rejects(save(0,0),e=>e.code==='PT409'&&e.message.includes('ATWAR_CONFLICT: task changed'));
 assert.equal((await db.query('select count(*)::int n from public.task_followup_details')).rows[0].n,0);
 assert.equal((await save(0,1)).rows[0].result.followup.revision,1);
 await assert.rejects(save(0,1),e=>e.code==='PT409'&&e.message.includes('follow-up changed'));
 assert.equal((await save(1,1)).rows[0].result.followup.revision,2);
 console.log(`PASS: ${before.length} real functions preserve definition, ownership and grants; migration replay; stale task/follow-up return PT409 without writing; current revisions still save.`);
}finally{await db.close();}
