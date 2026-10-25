import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {createTestDB,ids,seedAssignedVehicle} from './fleet-test-db.mjs';
const {db,rpc}=await createTestDB();
const migration='supabase/migrations/20261025163934_admin_only_action_history.sql';
const tables=['task_activity','policy_events','project_events','improvement_events','employee_job_change_events','job_periodic_review_events','work_relation_history','job_description_versions'];
async function as(user,sql,args=[]){await db.exec('begin;set local role authenticated');try{await db.query("select set_config('request.jwt.claims',$1,true)",[JSON.stringify({sub:ids[user],role:'authenticated'})]);const result=await db.query(sql,args);await db.exec('commit');return result.rows;}catch(e){await db.exec('rollback');throw e;}}
try{
 await db.exec('alter table public.job_descriptions add column published_snapshot jsonb;');
 for(const file of ['20261023142622_recruitment_foundation.sql','20261023142952_recruitment_salary_reference_metadata.sql','20261023143441_recruitment_resume_storage.sql','20261023150534_recruitment_public_upload_session.sql','20261023191845_recruitment_approved_workflow.sql','20261023194438_recruitment_batch_validation.sql'])await db.exec(await fs.readFile('supabase/migrations/'+file,'utf8'));
 for(const table of tables){await db.exec(`create table public.${table}(id int primary key);alter table public.${table} enable row level security;grant select on public.${table} to authenticated;create policy existing_record_visibility on public.${table} for select to authenticated using(true);insert into public.${table} values(1);`);}
 const car=await seedAssignedVehicle(db,rpc,'fleet',{p_id:null,p_revision:null,p_data:{plate:'AUDIT',vehicle_type:'اختبار',active:true,odometer:10,driver_id:ids.driver},p_reason:'اختبار خصوصية السجل'});
 const before=(await db.query('select count(*)::int n from private.fleet_events')).rows[0].n;
 await db.exec(await fs.readFile(migration,'utf8'));
 await db.exec(await fs.readFile(migration,'utf8')); // Safe deployment replay.
 for(const user of ['driver','manager','fleet','accountant','outsider'])for(const table of tables)assert.equal((await as(user,`select * from public.${table}`)).length,0,`${user} cannot read ${table}`);
 for(const table of tables){assert.equal((await as('admin',`select * from public.${table}`)).length,1);await db.exec(`insert into public.${table} values(2)`);assert.equal((await as('admin',`select * from public.${table}`)).length,2,'New history is still stored');}
 for(const user of ['driver','manager','fleet','accountant'])assert.equal((await rpc(user,'fleet_snapshot')).audit_admin,false,'Business permissions do not confer audit access');
 assert.equal((await rpc('admin','fleet_snapshot')).audit_admin,true);
 const adminProfile=await rpc('admin','fleet_vehicle_profile',{p_vehicle:car});assert(adminProfile.events.length>0);
 const driverProfile=await rpc('driver','fleet_vehicle_profile',{p_vehicle:car});assert.equal(driverProfile.events.length,0);assert.equal(driverProfile.vehicle.id,car,'Normal operational access remains');
 assert.equal((await db.query('select count(*)::int n from private.fleet_events')).rows[0].n,before,'No audit rows removed');
 assert.equal((await as('admin','select public.recruitment_context() value'))[0].value.audit_admin,true);
 await db.exec("update public.profiles set allowed_modules=array_append(allowed_modules,'recruitment')");
 for(const user of ['manager','driver'])assert.equal((await as(user,'select public.recruitment_context() value'))[0].value.audit_admin,false);
 const guards=await db.query("select proname from pg_proc where pronamespace='private'::regnamespace and proname in('fleet_detail_before_operations','fleet_vehicle_profile','hr_detail_before_fleet','recruitment_detail_v1') and prosrc like '%private.is_admin()%'");assert.equal(guards.rows.length,4,'Every private history aggregate is protected');
 console.log('PASS: 8 history tables across 6 account roles, active admin-only RPC flags, private aggregate guards, migration replay and audit retention.');
}finally{await db.close()}
