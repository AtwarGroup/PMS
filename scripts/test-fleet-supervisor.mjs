import assert from 'node:assert/strict';
import {currentFleetDB,ids,seedAssignedVehicle} from './fleet-v2-fixture.mjs';
const {db,rpc}=await currentFleetDB();
try {
 const car=await seedAssignedVehicle(db,rpc,'fleet',{p_id:null,p_revision:null,p_data:{plate:'SUPERVISOR QA',vehicle_type:'اختبار صلاحيات الإشراف',driver_id:ids.driver,active:true,odometer:10},p_reason:'اختبار مشرف مسؤول الأسطول'});
 const snap=u=>rpc(u,'fleet_snapshot');const detail=(u,id)=>rpc(u,'fleet_detail',{p_id:id});
 const listed=async(u,id)=>(await snap(u)).requests.some(r=>r.id===id);
 const grant=permissions=>rpc('admin','access_direct_save',{p_profile:ids.outsider,p_rules:permissions.map(permission=>({permission,scope:'all'}))});
 await db.query('update private.hr_employees set manager_id=$1 where profile_id=$2',[ids.outsider,ids.fleet]);
 async function draft(actor='driver',amount=400){
  const data={vehicle_id:car,accountant_id:ids.accountant,request_type:'repair',maintenance_kind:'tire',odometer:20,description:'اختبار متابعة مشرف مسؤول الأسطول',fault_notes:'صلاحية متابعة دون تنفيذ نيابة عن المسؤول',selected_quote:0,quotes:[]};
  const id=await rpc(actor,'fleet_request_save',{p_id:null,p_revision:null,p_data:data});
  const fid=await rpc(actor,'fleet_upload',{p_request:id,p_kind:'quote_parts',p_name:'quote.pdf',p_mime:'application/pdf',p_base64:Buffer.from('%PDF-1.4 supervisor').toString('base64')});
  data.quotes=[0,1].map(i=>({scope:'parts',supplier:'ورشة اختبار الإشراف '+i,phone:'0501234567',parts:amount,labor:0,tax:0,parts_file_id:fid}));
  await rpc(actor,'fleet_request_save',{p_id:id,p_revision:(await detail(actor,id)).request.revision,p_data:data});return id;
 }
 const cmd=async(u,id,a,data={})=>rpc(u,'fleet_command',{p_id:id,p_revision:(await detail(u,id)).request.revision,p_action:a,p_data:data});
 const own=await draft();assert(await listed('admin',own),'Admin sees an unrelated unsent draft');assert.equal(await listed('outsider',own),false);
 await grant(['fleet.requests.read','fleet.vehicles.read']);
 assert.equal((await snap('outsider')).supervised_owner_id,ids.fleet);
 assert.equal(await listed('outsider',own),false,'Supervisor does not see unrelated driver drafts');
 const fleetDraft=await draft('fleet');assert(await listed('outsider',fleetDraft),'Supervisor mirrors fleet-created draft');assert((await detail('outsider',fleetDraft)).events.length>0);
 await cmd('driver',own,'submit');assert(await listed('fleet',own));assert(await listed('outsider',own));
 const observer=await snap('outsider');assert.equal(observer.can_approve,false);assert.equal(observer.can_manage,false);assert.equal(observer.can_finance,false);
 await assert.rejects(()=>cmd('outsider',own,'approve'),/غير مسموح|denied/i);
 await assert.rejects(()=>rpc('outsider','fleet_upload',{p_request:own,p_kind:'quote_parts',p_name:'unauthorized.pdf',p_mime:'application/pdf',p_base64:Buffer.from('%PDF-1.4 bad').toString('base64')}),/denied/i);
 await cmd('fleet',own,'approve');assert.equal(await listed('outsider',own),false,'Observer queue follows owner handoff to accountant');assert(await listed('admin',own));assert(await listed('accountant',own));
 await grant([]);assert.equal((await snap('outsider')).supervised_owner_id,null);assert.equal(await listed('outsider',fleetDraft),false);await assert.rejects(()=>detail('outsider',fleetDraft),/denied/i);
 await grant(['fleet.requests.read','fleet.vehicles.read']);await db.query('update private.hr_employees set manager_id=null where profile_id=$1',[ids.fleet]);assert.equal((await snap('outsider')).supervised_owner_id,null);assert.equal(await listed('outsider',fleetDraft),false);
 await db.query('update private.hr_employees set manager_id=$1 where profile_id=$2',[ids.outsider,ids.fleet]);
 const handoverCar=await seedAssignedVehicle(db,rpc,'fleet',{p_id:null,p_revision:null,p_data:{plate:'SUPERVISOR HANDOVER',vehicle_type:'اختبار إشراف الاستلام',driver_id:ids.driver,active:true,odometer:10},p_reason:'سيارة معزولة لاختبار الإشراف'});
 const h=await rpc('fleet','fleet_handover_save',{p_id:null,p_revision:null,p_data:{vehicle_id:handoverCar,deliverer_id:ids.driver,diagram_type:'sedan',odometer:20,fuel_level:50,keys_count:1,spare_tire:true,tools:true,marks:[],no_marks:true,notes:''}});
 const hs=await rpc('outsider','fleet_operations_context');assert(hs.handovers.some(x=>x.id===h));const hd=await rpc('outsider','fleet_handover_detail',{p_id:h});assert.equal(hd.can_edit,false);assert.equal(hd.can_fleet_review,false);await assert.rejects(()=>rpc('outsider','fleet_handover_command',{p_id:h,p_revision:1,p_action:'submit',p_reason:''}),/غير مسموح/);
 await db.query("update public.profiles set allowed_modules=array['policies'] where id=$1",[ids.outsider]);await assert.rejects(()=>snap('outsider'),/ATWAR_MODULE_DENIED/);
 console.log('PASS admin all-stage/draft visibility, dynamic supervisor queue and history, read-only enforcement, unrelated drafts, owner handoff, permission/manager/module revocation and handover read-only access.');
}finally{await db.close();}
