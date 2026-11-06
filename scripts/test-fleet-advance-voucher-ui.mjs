import {chromium,expect} from '@playwright/test';
import assert from 'node:assert/strict';
import {mkdir,writeFile} from 'node:fs/promises';
import {startPreview} from './fleet-preview.mjs';
import {ids} from './fleet-test-db.mjs';
import {paymentVoucherModel} from '../assets/js/fleet-reimbursement-pdf.mjs';
const app=await startPreview();let browser;
try{
 const privileges=(await app.db.query("select has_function_privilege('anon','public.fleet_advance_voucher(uuid)','execute') anonymous,has_function_privilege('authenticated','private.fleet_voucher_data(uuid)','execute') internal")).rows[0];assert.deepEqual(privileges,{anonymous:false,internal:false});
 const car=(await app.rpc('fleet','fleet_snapshot')).vehicles[0];
 const data={vehicle_id:car.id,accountant_id:ids.accountant,request_type:'repair',maintenance_kind:'tire',odometer:12510,description:'تغيير الإطارات التالفة للسيارة',fault_notes:'طلب صرف قبل الإصلاح بموجب العرض المعتمد',selected_quote:1,quotes:[]};
 const id=await app.rpc('driver','fleet_request_save',{p_id:null,p_revision:null,p_data:data});
 const detail=actor=>app.rpc(actor,'fleet_detail',{p_id:id});
 const cmd=async(actor,action,p_data={})=>app.rpc(actor,'fleet_command',{p_id:id,p_revision:(await detail(actor)).request.revision,p_action:action,p_data});
 const upload=(kind,name,actor='driver')=>app.rpc(actor,'fleet_upload',{p_request:id,p_kind:kind,p_name:name,p_mime:'application/pdf',p_base64:Buffer.from('%PDF-1.4 test '+name).toString('base64')});
 const voucher=()=>app.rpc('accountant','fleet_advance_voucher',{p_id:id});
 for(let i=0;i<2;i++)data.quotes.push({scope:'parts',supplier:'ورشة اختبار أمر الصرف المسبق '+i,phone:'0501234567',parts:400+i*100,labor:0,tax:0,parts_file_id:await upload('quote_parts','quote-'+i+'.pdf')});
 await app.rpc('driver','fleet_request_save',{p_id:id,p_revision:1,p_data:data});await assert.rejects(voucher);
 await cmd('driver','submit');await assert.rejects(voucher);await cmd('fleet','approve');
 for(const actor of ['driver','outsider','accountant2'])await assert.rejects(()=>app.rpc(actor,'fleet_advance_voucher',{p_id:id}),/denied/i);
 await assert.rejects(()=>app.rpc('accountant','fleet_reimbursement_voucher',{p_id:id}),/الاستعاضة/);
 let d=await voucher();assert.equal(d.voucher_kind,'advance');assert.equal(d.detail.request.invoice_id,null);assert.equal(paymentVoucherModel(d).amount,500);assert.equal(paymentVoucherModel(d).paid,false);assert.equal(d.detail.request.state,'awaiting_advance');
 const revision=d.detail.request.revision;await voucher();assert.equal((await detail('accountant')).request.revision,revision,'Downloading never changes financial workflow');
 browser=await chromium.launch({headless:true,args:['--no-sandbox','--disable-dev-shm-usage']});const p=await browser.newPage({viewport:{width:390,height:844}}),errors=[];p.on('pageerror',e=>errors.push(e.message));await p.route('**/*',r=>r.request().url().startsWith(app.url)||/^(data:|blob:)/.test(r.request().url())?r.continue():r.abort());
 const open=async(actor='accountant')=>{await p.goto(app.url+'/fleet/index.html?qa='+actor+'&request='+id);await expect(p.locator('#fleetDialog')).toBeVisible();await expect(p.locator('#fleetStatus')).toHaveText('');};
 await open();await expect(p.locator('[data-advance-pdf]')).toBeVisible();await expect(p.locator('[data-reimbursement-pdf]')).toHaveCount(0);await expect(p.locator('#dialogBody tbody tr')).toHaveCount(1);
 const download=async name=>{const waiting=p.waitForEvent('download');await p.locator('[data-advance-pdf]').click();const file=await waiting;assert.match(file.suggestedFilename(),/^fleet-advance-.*\.pdf$/);await file.saveAs('test-results/'+name+'.pdf');await expect(p.locator('#dialogStatus')).toHaveText('');};
 await mkdir('test-results',{recursive:true});await download('fleet-advance-pending');
 async function screenshot(data,name){const base64=await p.evaluate(async d=>{const {reimbursementCanvas}=await import('/assets/js/fleet-reimbursement-pdf.mjs');return (await reimbursementCanvas(d)).toDataURL('image/png').split(',')[1];},data);await writeFile('test-results/'+name+'.png',Buffer.from(base64,'base64'));}
 await screenshot(d,'fleet-advance-pending');
 const evidence=await upload('payment','advance.pdf','accountant');await cmd('accountant','confirm_advance',{amount:500,reference:'1234',evidence_id:evidence});
 d=await voucher();assert.equal(paymentVoucherModel(d).paid,true);assert.equal(paymentVoucherModel(d).amount,500);assert.equal(d.detail.request.state,'repair');await open();await download('fleet-advance-paid');await screenshot(d,'fleet-advance-paid');
 await cmd('driver','request_increase',{total:750,reason:'أعمال إضافية اكتشفت بعد فك الإطارات'});await cmd('fleet','approve_increase');
 d=await voucher();assert.equal(paymentVoucherModel(d).paid,false);assert.equal(paymentVoucherModel(d).amount,250,'Only the approved unpaid balance is requested, not 750 again');await open();await download('fleet-advance-balance');await screenshot(d,'fleet-advance-balance');
 for(const actor of ['admin','fleet']){await open(actor);await expect(p.locator('[data-advance-pdf]')).toBeVisible();}await open('driver');await expect(p.locator('[data-advance-pdf]')).toHaveCount(0);
 await app.db.query("update public.profiles set allowed_modules='{}' where id=$1",[ids.accountant]);await assert.rejects(voucher);
 assert.deepEqual(errors,[]);console.log('PASS advance PDF: approved-only finance stage, no invoice prerequisite, read-only document generation, access/anonymous/private-helper/module checks, original payment reprint and approved increase balance, Android-width downloads, existing reimbursement separation.');
}finally{await browser?.close();await app.close();}
