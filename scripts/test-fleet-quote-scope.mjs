import assert from 'node:assert/strict';
import {currentFleetDB,ids,seedAssignedVehicle} from './fleet-v2-fixture.mjs';
const {db,rpc}=await currentFleetDB();
try {
 const car=await seedAssignedVehicle(db,rpc,'fleet',{p_id:null,p_revision:null,p_data:{plate:'SCOPE QA',vehicle_type:'سيارة اختبار النطاق',driver_id:ids.driver,active:true,odometer:100},p_reason:'بيانات معزولة لاختبار العروض'});
 const detail=(id,user='driver')=>rpc(user,'fleet_detail',{p_id:id});
 const command=async(id,action,data={},user='driver')=>rpc(user,'fleet_command',{p_id:id,p_revision:(await detail(id,user)).request.revision,p_action:action,p_data:data});
 const save=async(id,data)=>rpc('driver','fleet_request_save',{p_id:id,p_revision:(await detail(id)).request.revision,p_data:data});
 const upload=(id,kind,label)=>rpc('driver','fleet_upload',{p_request:id,p_kind:'quote_'+kind,p_name:label+'.pdf',p_mime:'application/pdf',p_base64:Buffer.from('%PDF-1.4 '+label).toString('base64')});
 async function draft(scope,count=2,extra={}) {
  const data={vehicle_id:car,accountant_id:ids.accountant,request_type:'repair',maintenance_kind:'tire',description:'اختبار عروض بنطاق صيانة محدد',fault_notes:'معاينة كاملة لتحديد تكلفة الصيانة',odometer:120,selected_quote:0,quotes:[],...extra};
  const id=await rpc('driver','fleet_request_save',{p_id:null,p_revision:null,p_data:data});
  for(let i=0;i<count;i++) {
   const q={supplier:'ورشة اختبار نطاق رقم '+i,phone:'0501234567',parts:scope==='labor'?0:250+i,labor:scope==='parts'?0:50,tax:0};
   if(scope)q.scope=scope;
   for(const kind of ['parts','labor'])if(!scope||scope==='parts_labor'||scope===kind)q[kind+'_file_id']=await upload(id,kind,scope+'-'+kind+'-'+i);
   data.quotes.push(q);
  }
  await save(id,data);return {id,data};
 }
 for(const scope of ['parts_labor','parts','labor',undefined]) {
  const {id}=await draft(scope);await command(id,'submit');
  const r=(await detail(id)).request;
  assert.equal(r.state,'manager_review');assert.equal(r.approved,scope==='labor'?50:scope==='parts'?250:300);
  await assert.rejects(()=>command(id,'approve',{},'outsider'),/denied/i);
  await command(id,'approve',{},'manager');assert.equal((await detail(id)).request.state,'repair');
 }
 const stripped=await draft('parts');stripped.data.quotes[0].labor=900;
 stripped.data.quotes[0].labor_file_id=crypto.randomUUID();await save(stripped.id,stripped.data);
 let q=(await detail(stripped.id)).request.quotes[0];assert.equal(q.labor,0);assert.equal(q.labor_file_id,undefined);
 const labor=await draft('labor');labor.data.quotes[0].parts=900;labor.data.quotes[0].parts_file_id=crypto.randomUUID();await save(labor.id,labor.data);
 q=(await detail(labor.id)).request.quotes[0];assert.equal(q.parts,0);assert.equal(q.parts_file_id,undefined);
 for(const scope of ['parts','labor','parts_labor']) {
  const missing=await draft(scope);const kind=scope==='labor'?'labor':'parts';
  delete missing.data.quotes[0][kind+'_file_id'];await save(missing.id,missing.data);
  await assert.rejects(()=>command(missing.id,'submit'),/أرفق عرض البند/);
  const duplicate=await draft(scope);duplicate.data.quotes[1][kind+'_file_id']=duplicate.data.quotes[0][kind+'_file_id'];await save(duplicate.id,duplicate.data);
  await assert.rejects(()=>command(duplicate.id,'submit'),/مرفق مستقل/);
  const foreign=await draft(scope);foreign.data.quotes[0][kind+'_file_id']=(await draft(scope)).data.quotes[0][kind+'_file_id'];await save(foreign.id,foreign.data);
  await assert.rejects(()=>command(foreign.id,'submit'),/أرفق عرض البند/);
 }
 const mixed=await draft('parts');mixed.data.quotes[1].scope='labor';mixed.data.quotes[1].labor=50;
 mixed.data.quotes[1].labor_file_id=await upload(mixed.id,'labor','mixed');await save(mixed.id,mixed.data);
 await assert.rejects(()=>command(mixed.id,'submit'),/نفس نطاق العمل/);
 const invalid=await draft('parts');invalid.data.quotes[0].scope='anything';await assert.rejects(()=>save(invalid.id,invalid.data),/ما يشمله العرض/);
 const one=await draft('parts',1);await assert.rejects(()=>command(one.id,'submit'),/2 عروض/);
 const emergency=await draft('labor',1,{request_type:'emergency',stops_vehicle:true,needs_tow:true});await command(emergency.id,'submit');assert.equal((await detail(emergency.id)).request.state,'fleet_review');
 const switchScope=await draft('parts_labor');for(const q of switchScope.data.quotes)q.scope='labor';await save(switchScope.id,switchScope.data);
 await command(switchScope.id,'submit');assert.equal((await detail(switchScope.id)).request.approved,50);
 const large=await draft('labor');for(const q of large.data.quotes)q.labor=301;await save(large.id,large.data);await command(large.id,'submit');assert.equal((await detail(large.id)).request.state,'fleet_review');
 console.log('PASS quotation scope: all three modes and historical quotes, conditional evidence, excluded amounts, scope changes, same-scope comparison, duplicates/foreign files, quote minimums, emergency route, 300/301 boundary and permissions.');
} finally {await db.close();}
