import assert from 'node:assert/strict';
import {currentFleetDB,ids,seedAssignedVehicle} from './fleet-v2-fixture.mjs';
const {db,rpc}=await currentFleetDB();
try {
 const car=await seedAssignedVehicle(db,rpc,'fleet',{p_id:null,p_revision:null,p_data:{plate:'MULTI QA',vehicle_type:'سيارة اختبار الملفات',driver_id:ids.driver,active:true,odometer:10},p_reason:'اختبار معزول للمرفقات المتعددة'});
 const detail=id=>rpc('driver','fleet_detail',{p_id:id});
 const save=async(id,data)=>rpc('driver','fleet_request_save',{p_id:id,p_revision:(await detail(id)).request.revision,p_data:data});
 const upload=(id,kind,name)=>rpc('driver','fleet_upload',{p_request:id,p_kind:kind,p_name:name+'.pdf',p_mime:'application/pdf',p_base64:Buffer.from('%PDF-1.4 '+name).toString('base64')});
 const command=async(id,user,action,data={})=>rpc(user,'fleet_command',{p_id:id,p_revision:(await detail(id)).request.revision,p_action:action,p_data:data});
 async function draft(){const data={vehicle_id:car,accountant_id:ids.accountant,request_type:'repair',maintenance_kind:'tire',odometer:20,description:'طلب اختبار المرفقات المتعددة',fault_notes:'تفاصيل فحص السيارة قبل الصيانة',selected_quote:0,quotes:[]};const id=await rpc('driver','fleet_request_save',{p_id:null,p_revision:null,p_data:data});for(let i=0;i<2;i++){const q={scope:'parts_labor',supplier:'ورشة اختبار متعددة رقم '+i,phone:'0501234567',parts:100,labor:50,tax:0};for(const kind of ['parts','labor'])q[kind+'_file_ids']=[await upload(id,'quote_'+kind,id+kind+i+'a'),await upload(id,'quote_'+kind,id+kind+i+'b')];data.quotes.push(q);}await save(id,data);return {id,data};}
 const good=await draft();let row=(await detail(good.id)).request;assert.equal(row.quotes[0].parts_file_id,row.quotes[0].parts_file_ids[0]);await command(good.id,'driver','submit');await command(good.id,'manager','approve');
 const other=await draft();const foreign=other.data.quotes[0].parts_file_ids[1];
 const bad=await draft();bad.data.quotes[0].parts_file_ids[1]=foreign;await save(bad.id,bad.data);await assert.rejects(()=>command(bad.id,'driver','submit'),/لا يتبع الطلب/);
 const duplicate=await draft();duplicate.data.quotes[1].parts_file_ids[1]=duplicate.data.quotes[0].parts_file_ids[1];await save(duplicate.id,duplicate.data);await assert.rejects(()=>command(duplicate.id,'driver','submit'),/مرفق مستقل/);
 const wrong=await draft();wrong.data.quotes[0].parts_file_ids[1]=wrong.data.quotes[0].labor_file_ids[1];await save(wrong.id,wrong.data);await assert.rejects(()=>command(wrong.id,'driver','submit'),/البند المحدد/);
 const shape=await draft();shape.data.quotes[0].parts_file_ids='invalid';await assert.rejects(()=>save(shape.id,shape.data),/غير صالحة/);
 const excluded=await draft();for(const q of excluded.data.quotes)q.scope='parts';await save(excluded.id,excluded.data);row=(await detail(excluded.id)).request;assert.equal(row.quotes[0].labor_file_ids,undefined);assert.equal(row.quotes[0].labor,0);await command(excluded.id,'driver','submit');
 const invoices=[await upload(good.id,'invoice','invoice-a'),await upload(good.id,'invoice','invoice-b')];
 const photo=await rpc('driver','fleet_upload',{p_request:good.id,p_kind:'repair_photo',p_name:'repair.png',p_mime:'image/png',p_base64:'iVBORw0KGgo='});
 await assert.rejects(()=>command(good.id,'driver','confirm_repair',{total:150,received:true,invoice_id:invoices[0],invoice_ids:[invoices[0],foreign],repair_photo_id:photo,repair_photo_ids:[photo]}),/لا يتبع الطلب/);
 assert.equal((await detail(good.id)).request.state,'repair');
 await command(good.id,'driver','confirm_repair',{total:150,received:true,invoice_id:invoices[0],invoice_ids:invoices,repair_photo_id:photo,repair_photo_ids:[photo]});await command(good.id,'fleet','approve');
 const proof=[];for(let i=0;i<2;i++)proof.push(await rpc('accountant','fleet_upload',{p_request:good.id,p_kind:'payment',p_name:'proof'+i+'.pdf',p_mime:'application/pdf',p_base64:Buffer.from('%PDF-1.4 proof'+i).toString('base64')}));
 await assert.rejects(()=>command(good.id,'accountant','settle',{amount:150,reference:'1234',evidence_id:proof[0],evidence_ids:[proof[0],foreign]}),/لا يتبع الطلب/);
 await command(good.id,'accountant','settle',{amount:150,reference:'1234',evidence_id:proof[0],evidence_ids:proof});assert.equal((await detail(good.id)).request.state,'closed');
 const event=(await db.query("select payload from private.fleet_events where request_id=$1 and action='settle'",[good.id])).rows[0];assert.deepEqual(event.payload.evidence_ids,proof);
 await assert.rejects(()=>rpc('outsider','fleet_download',{p_id:invoices[1]}),/denied/i);
 console.log('PASS multiple quote/invoice/finance files, legacy primary IDs, typed/request-bound secondary files, duplicates, excluded scope, audit payload and unchanged settlement/access checks.');
}finally{await db.close();}
