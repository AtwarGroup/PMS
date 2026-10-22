import assert from 'node:assert/strict';
import {createTestDB,ids,seedAssignedVehicle} from './fleet-test-db.mjs';
const {db,rpc}=await createTestDB();
try {
const args={p_id:null,p_revision:null,p_data:{plate:'REVIEW',vehicle_type:'اختبار',active:true,odometer:10,driver_id:ids.driver},p_reason:'اختبار المراجعة'};
await assert.rejects(()=>rpc('fleet','fleet_vehicle_save',args),/محضر تسليم/);
await assert.rejects(()=>rpc('fleet','fleet_import',{p_rows:[args.p_data],p_source_hash:'f'.repeat(64),p_dry_run:false}),/محضر تسليم/);
assert.equal((await db.query("select count(*)::int n from private.fleet_vehicles where plate='REVIEW'")).rows[0].n,0);
const car=await seedAssignedVehicle(db,rpc,'fleet',args);
const data={vehicle_id:car,kind:'return',employee_id:ids.driver,odometer:20,fuel_level:50,keys_count:1,spare_tire:true,tools:true,marks:[],no_marks:true,notes:''};
const token=crypto.randomUUID();
const saveArgs={p_token:token,p_id:null,p_revision:null,p_data:data};
const id=await rpc('fleet','fleet_handover_save_retry',saveArgs);
assert.equal(await rpc('fleet','fleet_handover_save_retry',saveArgs),id);
await assert.rejects(()=>rpc('admin','fleet_handover_save_retry',saveArgs),/تغير المحضر/);
await assert.rejects(()=>rpc('fleet','fleet_handover_save_retry',{...saveArgs,p_data:{...data,notes:'تغيير'}}),/تغير المحضر/);
assert.equal((await db.query('select count(*)::int n from private.fleet_handovers where vehicle_id=$1',[car])).rows[0].n,1);
const photoArgs={p_id:id,p_name:'photo.png',p_mime:'image/png',p_base64:'iVBORw0KGgo='};
const photo=await rpc('fleet','fleet_handover_upload',photoArgs);
assert.equal(await rpc('fleet','fleet_handover_upload',{...photoArgs,p_name:'retry.png'}),photo);
assert.equal((await db.query('select count(*)::int n from private.fleet_handover_photos where handover_id=$1',[id])).rows[0].n,1);
const hd=()=>rpc('fleet','fleet_handover_detail',{p_id:id});
const hc=async(user,action)=>rpc(user,'fleet_handover_command',{p_id:id,p_revision:(await hd()).handover.revision,p_action:action,p_reason:''});
async function request(){
 const d={vehicle_id:car,accountant_id:ids.accountant,description:'طلب مفتوح لاختبار العهدة',request_type:'repair',odometer:20,quotes:[],selected_quote:0};
 const rid=await rpc('driver','fleet_request_save',{p_id:null,p_revision:null,p_data:d});
 for(let i=0;i<3;i++)d.quotes.push({supplier:'مورد '+i,parts:500,labor:0,tax:0,file_id:await rpc('driver','fleet_upload',{p_request:rid,p_kind:'quote',p_name:'quote.pdf',p_mime:'application/pdf',p_base64:Buffer.from('%PDF-1.4 QA').toString('base64')})});
 await rpc('driver','fleet_request_save',{p_id:rid,p_revision:1,p_data:d});await rpc('driver','fleet_command',{p_id:rid,p_revision:2,p_action:'submit',p_data:{}});return rid;
}
const rid=await request();
await assert.rejects(()=>hc('fleet','submit'),/طلبات الصيانة المفتوحة/);
await assert.rejects(()=>rpc('fleet','fleet_handover_save',{p_id:id,p_revision:1,p_data:data}),/طلبات الصيانة المفتوحة/);
// Boundary 1: reminders; boundary 2: owner escalation; boundary 3: admin escalation.
await db.query("update private.fleet_requests set state_changed_at=now()-interval '7 days' where id=$1",[rid]);
await db.query('select private.process_fleet_workflow_alerts()');
let levels=(await db.query("select phase,recipient_id from private.fleet_workflow_deliveries where entity_id=$1 and phase like 'escalation_%'",[rid])).rows;
assert.deepEqual(levels.map(x=>x.phase),['escalation_1']);assert.equal(levels[0].recipient_id,ids.fleet);
await db.query("update private.fleet_requests set state_changed_at=now()-interval '10 days' where id=$1",[rid]);await db.query('select private.process_fleet_workflow_alerts()');
levels=(await db.query("select phase,recipient_id from private.fleet_workflow_deliveries where entity_id=$1 and phase='escalation_2'",[rid])).rows;
assert.equal(levels[0].recipient_id,ids.admin);
const count=(await db.query('select count(*)::int n from public.notifications')).rows[0].n;await db.query('select private.process_fleet_workflow_alerts()');assert.equal((await db.query('select count(*)::int n from public.notifications')).rows[0].n,count);
async function reject(r){const d=await rpc('fleet','fleet_detail',{p_id:r});await rpc('fleet','fleet_command',{p_id:r,p_revision:d.request.revision,p_action:'reject',p_data:{reason:'اختبار إقفال الطلب'}});}
await reject(rid);await hc('fleet','submit');
const rid2=await request();await assert.rejects(()=>hc('driver','accept'),/طلبات الصيانة المفتوحة/);
assert.equal((await rpc('fleet','fleet_vehicle_profile',{p_vehicle:car})).vehicle.driver_id,ids.driver);
await reject(rid2);await hc('driver','accept');assert.equal((await rpc('fleet','fleet_vehicle_profile',{p_vehicle:car})).vehicle.driver_id,null);
await assert.rejects(()=>rpc('fleet','fleet_escalation_settings_save',{p_revision:1,p_days:4}),/Administrator/);
await rpc('admin','fleet_escalation_settings_save',{p_revision:1,p_days:4});
await assert.rejects(()=>rpc('admin','fleet_escalation_settings_save',{p_revision:1,p_days:4}),/تحديث الإعدادات/);
assert.equal((await rpc('admin','fleet_operations_context')).settings.escalation_days,4);
console.log('PASS review: initial/import custody denial, open request save/submit/accept guards, lost-response draft retry, cross-actor token denial, photo deduplication, owner/admin escalation boundaries, deduplication and admin-only settings.');
}finally{await db.close();}
