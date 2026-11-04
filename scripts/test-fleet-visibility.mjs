import assert from 'node:assert/strict';
import {currentFleetDB,ids,seedAssignedVehicle} from './fleet-v2-fixture.mjs';
const {db,rpc}=await currentFleetDB();
try {
 const car=await seedAssignedVehicle(db,rpc,'fleet',{p_id:null,p_revision:null,p_data:{plate:'VISIBILITY QA',vehicle_type:'سيارة اختبار الخصوصية',driver_id:ids.driver,active:true,odometer:10},p_reason:'اختبار خصوصية الطلبات وسجل السيارات'});
 const detail=(actor,id)=>rpc(actor,'fleet_detail',{p_id:id});
 const snapshot=actor=>rpc(actor,'fleet_snapshot');
 async function draft(actor='driver'){
  const data={vehicle_id:car,accountant_id:ids.accountant,request_type:'repair',maintenance_kind:'tire',description:'طلب اختبار خصوصية ومتابعة الإجراءات',fault_notes:'اختبار الصلاحيات طوال دورة الطلب',odometer:20,selected_quote:0,quotes:[]};
  const id=await rpc(actor,'fleet_request_save',{p_id:null,p_revision:null,p_data:data});
  for(let i=0;i<2;i++){
   const q={scope:'parts',supplier:'ورشة اختبار خصوصية '+i,phone:'0501234567',parts:100,labor:0,tax:0};
   q.parts_file_id=await rpc(actor,'fleet_upload',{p_request:id,p_kind:'quote_parts',p_name:'quote.pdf',p_mime:'application/pdf',p_base64:Buffer.from('%PDF-1.4 shared').toString('base64')});data.quotes.push(q);
  }
  await rpc(actor,'fleet_request_save',{p_id:id,p_revision:(await detail(actor,id)).request.revision,p_data:data});return id;
 }
 const id=await draft();
 for(const actor of ['manager','accountant','accountant2','outsider']){
  assert(!(await snapshot(actor)).requests.some(r=>r.id===id),actor+' cannot list another employee unsent draft');
  await assert.rejects(()=>detail(actor,id),/Access denied/);
 }
 const own=(await detail('driver',id));assert(own.events.length>0);assert(own.events.every(e=>e.actor_name));
 const created=await draft('fleet');assert((await snapshot('fleet')).requests.some(r=>r.id===created),'Fleet-created draft remains accessible to creator');assert((await snapshot('driver')).requests.some(r=>r.id===created));
 const cmd=async(actor,action,data={})=>rpc(actor,'fleet_command',{p_id:id,p_revision:(await detail(actor,id)).request.revision,p_action:action,p_data:data});
 await cmd('driver','submit');
 for(const actor of ['driver','manager','fleet','accountant'])assert((await detail(actor,id)).events.length>0,actor+' sees history for an authorized submitted request');assert((await snapshot('manager')).requests.some(r=>r.id===id));assert(!(await snapshot('accountant')).requests.some(r=>r.id===id));assert((await snapshot('fleet')).requests.some(r=>r.id===id));
 for(const actor of ['outsider','accountant2']){assert(!(await snapshot(actor)).requests.some(r=>r.id===id));await assert.rejects(()=>detail(actor,id),/Access denied/);}
 await cmd('manager','approve');assert.equal((await detail('driver',id)).request.state,'repair');assert(!(await snapshot('accountant')).requests.some(r=>r.id===id),'Assigned accountant does not list requests before their financial action');assert(!(await snapshot('manager')).requests.some(r=>r.id===id),'Manager request leaves the queue after approval');assert((await snapshot('fleet')).requests.some(r=>r.id===id),'Fleet owner retains visibility during driver repair');
 const events=(await detail('driver',id)).events;assert(events.some(e=>e.action==='approve'&&e.actor_name));
 const invoice=await rpc('driver','fleet_upload',{p_request:id,p_kind:'invoice',p_name:'invoice.pdf',p_mime:'application/pdf',p_base64:Buffer.from('%PDF-1.4 invoice').toString('base64')});
 const photo=await rpc('driver','fleet_upload',{p_request:id,p_kind:'repair_photo',p_name:'repair.png',p_mime:'image/png',p_base64:'iVBORw0KGgo='});
 await cmd('driver','confirm_repair',{total:100,received:true,invoice_id:invoice,repair_photo_id:photo});
 assert((await snapshot('fleet')).requests.some(r=>r.id===id));assert(!(await snapshot('manager')).requests.some(r=>r.id===id));assert(!(await snapshot('accountant')).requests.some(r=>r.id===id));
 await cmd('fleet','approve');assert((await snapshot('fleet')).requests.some(r=>r.id===id));assert((await snapshot('accountant')).requests.some(r=>r.id===id));
 const proof=await rpc('accountant','fleet_upload',{p_request:id,p_kind:'payment',p_name:'proof.pdf',p_mime:'application/pdf',p_base64:Buffer.from('%PDF-1.4 proof').toString('base64')});
 await cmd('accountant','settle',{amount:100,reference:'1234',evidence_id:proof});assert.equal((await detail('driver',id)).request.state,'closed');

 const finance=await snapshot('accountant2');assert.equal(finance.finance_only,true);assert.equal(finance.can_view_vehicles,true);assert.equal(finance.can_view_documents,false);assert.equal(finance.can_create,false);assert(finance.vehicles.some(v=>v.id===car));assert(finance.vehicles.every(v=>!v.can_request));
 const profile=await rpc('accountant2','fleet_vehicle_profile',{p_vehicle:car});assert.equal(profile.vehicle.id,car);assert.equal(profile.documents.length,0);assert.equal(profile.requests.length,0);assert.equal(profile.events.length,0);assert.equal(profile.handovers.length,0);
 await assert.rejects(()=>rpc('accountant2','fleet_vehicle_save',{p_id:car,p_revision:profile.vehicle.revision,p_data:{...profile.vehicle,plate:'UNAUTHORIZED'},p_reason:'محاولة تعديل غير مصرح بها'}),/denied/i);
 await assert.rejects(()=>rpc('accountant2','fleet_vehicle_operation_save',{p_vehicle:car,p_revision:profile.vehicle.revision,p_status:'maintenance',p_reason:'تغيير غير مصرح لحالة السيارة'}),/denied/i);
 assert.equal((await rpc('accountant2','fleet_documents_context')).vehicles.length,0);
 await db.query("update public.profiles set allowed_modules=array['policies'] where id=$1",[ids.accountant2]);
 await assert.rejects(()=>snapshot('accountant2'),/ATWAR_MODULE_DENIED/);await assert.rejects(()=>rpc('accountant2','fleet_vehicle_profile',{p_vehicle:car}),/ATWAR_MODULE_DENIED/);
 console.log('PASS visibility/history: private drafts, own/created requests, manager/team and assigned-only accountant boundaries, request actor names, read-only accountant registry, hidden unrelated evidence/documents and immediate module revocation.');
} finally {await db.close();}
