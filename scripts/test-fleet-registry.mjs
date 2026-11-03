import assert from 'node:assert/strict';
import {currentFleetDB,ids} from './fleet-v2-fixture.mjs';
import {filterFleetVehicles} from '../assets/js/fleet-registry.mjs';
const {db,rpc}=await currentFleetDB();
try {
 const data={plate:'REG 123',vin:'VIN123',vehicle_type:'سيدان',model:'2025',city:'جدة',driver_id:null,active:true,odometer:10,registration_number:'٠٠١٢٣٤٥٦٧',owner_identity_number:'۰۰۱۲۳۴۵۶۷۸'};
 const save=(u,id,revision,p_data)=>rpc(u,'fleet_vehicle_save',{p_id:id,p_revision:revision,p_data,p_reason:'اختبار حفظ بيانات الاستمارة والمالك'});
 const id=await save('fleet',null,null,data);const row=async()=> (await db.query('select * from private.fleet_vehicles where id=$1',[id])).rows[0];let v=await row();assert.equal(v.registration_number,'001234567');assert.equal(v.owner_identity_number,'0012345678');
 assert.equal((await rpc('fleet','fleet_vehicle_profile',{p_vehicle:id})).vehicle.registration_number,'001234567');assert.equal((await rpc('accountant2','fleet_snapshot')).vehicles.find(x=>x.id===id).owner_identity_number,'0012345678');
 const old={...v};delete old.registration_number;delete old.owner_identity_number;await save('fleet',id,v.revision,old);v=await row();assert.equal(v.registration_number,'001234567');assert.equal(v.owner_identity_number,'0012345678','Older clients preserve identifiers');
 const event=(await db.query("select payload from private.fleet_events where vehicle_id=$1 and action='vehicle_saved' order by id desc limit 1",[id])).rows[0].payload;assert.equal(event.before.registration_number,'001234567');assert.equal(event.after.owner_identity_number,'0012345678');
 await assert.rejects(()=>save('accountant2',id,v.revision,{...v,registration_number:'55'}),/denied/i);await assert.rejects(()=>save('outsider',id,v.revision,v),/denied/i);
 await assert.rejects(()=>save('fleet',id,v.revision,{...v,owner_identity_number:'bad'}),/check constraint/);assert.equal((await row()).revision,v.revision);
 await assert.rejects(()=>save('fleet',id,v.revision,{...v,registration_number:'1'.repeat(31)}),/check constraint/);
 await assert.rejects(()=>save('fleet',id,v.revision-1,v),/حدّث الصفحة/);
 await save('fleet',id,v.revision,{...v,registration_number:'',owner_identity_number:null});assert.equal((await row()).registration_number,null);assert.equal((await row()).owner_identity_number,null);
 const rows=[{...data,id:'a',registration_number:'001234567',owner_identity_number:'0012345678',driver_id:ids.driver,driver_name:'أحمد السائق',operational_status:'maintenance'},{id:'b',plate:'REG 456',vehicle_type:'نقل',city:'الرياض',driver_id:null,active:false,operational_status:'stopped'}];
 for(const filters of [{query:'٠٠١٢٣٤٥٦٧'},{query:'0012345678'},{query:'VIN123'},{query:'REG123'},{city:'جدة',type:'سيدان',driver:ids.driver,active:'true',operation:'maintenance'}])assert.deepEqual(filterFleetVehicles(rows,filters).map(v=>v.id),['a']);
 assert.deepEqual(filterFleetVehicles(rows,{driver:'unassigned',active:'false',city:'الرياض'}).map(v=>v.id),['b']);assert.equal(filterFleetVehicles(rows,{city:'الرياض',active:'true'}).length,0);assert.equal(filterFleetVehicles(rows,{}).length,2);
 console.log('PASS registry identifiers: normalized text/leading zeros, optional legacy data, omitted-field preservation, authorized reads/writes, validation, audit, revision guards and combined scoped filters.');
}finally{await db.close();}
