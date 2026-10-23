import assert from 'node:assert/strict';
import {createTestDB,ids,seedAssignedVehicle} from './fleet-test-db.mjs';
const {db,rpc}=await createTestDB();
try{
 const car=await seedAssignedVehicle(db,rpc,'fleet',{p_id:null,p_revision:null,p_data:{plate:'STORAGE',vehicle_type:'اختبار',active:true,driver_id:ids.driver,odometer:10},p_reason:'اختبار تخزين'});
 const data={vehicle_id:car,kind:'return',employee_id:ids.driver,odometer:20,fuel_level:50,keys_count:1,spare_tire:true,tools:true,marks:[],no_marks:true};
 const h=await rpc('fleet','fleet_handover_save_retry',{p_token:crypto.randomUUID(),p_id:null,p_revision:null,p_data:data});
 const args={p_id:h,p_name:'photo.png',p_mime:'image/png',p_base64:'iVBORw0KGgo='};
 const id=await rpc('fleet','fleet_handover_upload',args),before=await rpc('fleet','fleet_handover_photo',{p_id:id});
 await assert.rejects(()=>rpc('fleet','fleet_file_archive_complete',{p_id:id,p_kind:'handover',p_hash:before.hash}),/permission denied/);
 await assert.rejects(()=>db.query('select private.fleet_file_archive_complete($1,$2,$3)',[id,'handover',before.hash]),/Verified storage/);
 assert.equal((await rpc('fleet','fleet_handover_photo',{p_id:id})).base64,before.base64);
 await db.query("insert into storage.objects values('fleet-files',$1,$2)",['handover/'+id,JSON.stringify({size:before.size})]);
 await assert.rejects(()=>db.query('select private.fleet_file_archive_complete($1,$2,$3)',[id,'handover','wrong']),/Verified storage/);
 await db.exec('set role service_role');await db.query('select public.fleet_file_archive_complete($1,$2,$3)',[id,'handover',before.hash]);await db.exec('reset role');
 const after=await rpc('fleet','fleet_handover_photo',{p_id:id});assert.equal(after.stored,true);assert.equal(after.base64,null);assert.equal(after.hash,before.hash);assert.equal(after.size,before.size);
 assert.equal(await rpc('fleet','fleet_handover_upload',args),id,'Lost-response retry must deduplicate after offload');
 await assert.rejects(()=>rpc('outsider','fleet_handover_photo',{p_id:id}),/Access denied/);
 await db.query("update private.fleet_handover_photos set size_bytes=31457280 where id=$1",[id]).then(()=>assert.fail('size constraint')).catch(e=>assert.match(e.message,/check constraint/));
 console.log('PASS: private storage fallback, service-only completion, object/hash checks, byte removal, metadata preservation, post-offload deduplication and unauthorized download denial');
}finally{await db.close();}
