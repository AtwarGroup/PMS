import {chromium,expect} from '@playwright/test';
import assert from 'node:assert/strict';
import {startPreview} from './fleet-preview.mjs';
import {ids} from './fleet-test-db.mjs';
const app=await startPreview();let browser;
try{
 const car=(await app.rpc('fleet','fleet_snapshot')).vehicles[0];
 const id=await app.rpc('driver','fleet_request_save',{p_id:null,p_revision:null,p_data:{vehicle_id:car.id,accountant_id:ids.accountant,request_type:'emergency',odometer:12510,stops_vehicle:true,needs_tow:true,description:'طلب اختبار تصحيح المحاسب المسؤول',fault_notes:'تفاصيل العطل لاختبار التعديل الإداري',quotes:[],selected_quote:0}});
 await app.db.query("update private.fleet_requests set accountant_id=$1,state='awaiting_advance',approved=919.9 where id=$2",[ids.admin,id]);
 browser=await chromium.launch({headless:true,args:['--no-sandbox','--disable-dev-shm-usage']});const p=await browser.newPage({viewport:{width:390,height:844}});const errors=[];p.on('pageerror',e=>errors.push(e.message));await p.route('**/*',r=>r.request().url().startsWith(app.url)||/^(data:|blob:)/.test(r.request().url())?r.continue():r.abort());
 const open=async actor=>{await p.goto(app.url+'/fleet/index.html?qa='+actor+'&request='+id);await expect(p.locator('#fleetDialog')).toBeVisible();};
 await open('admin');await p.locator('[data-correct-request]').click();await expect(p.locator('#correctionForm')).toBeVisible();assert.equal(await p.locator('#correctionForm [name=accountant_id] option').evaluateAll((options,id)=>options.some(o=>o.value===id),ids.admin),false);
 await p.locator('#correctionForm [name=accountant_id]').selectOption(ids.accountant2);await p.locator('#correctionForm [name=description]').fill('تم تعديل الطلب بواسطة مسؤول النظام');await p.locator('#correctionForm [name=reason]').fill('تصحيح اختيار المحاسب المسؤول');await p.locator('#correctionForm button[type=submit]').click();await expect(p.locator('#fleetDialog')).not.toBeVisible();
 const updated=(await app.rpc('admin','fleet_detail',{p_id:id})).request;assert.equal(updated.accountant_id,ids.accountant2);assert.equal(updated.state,'awaiting_advance');assert.equal(updated.approved,919.9);
 await open('fleet');await expect(p.locator('[data-correct-request]')).toBeVisible();await p.locator('[data-correct-request]').click();await expect(p.locator('#correctionForm [name=description]')).toHaveValue('تم تعديل الطلب بواسطة مسؤول النظام');assert.equal(await p.evaluate(()=>document.documentElement.scrollWidth>innerWidth+2),false);
 await open('driver');await expect(p.locator('[data-correct-request]')).toHaveCount(0);assert.deepEqual(errors,[]);console.log('PASS mobile admin correction saves and closes, accountant choices exclude admin, fleet owner edits all stages, driver cannot edit administratively.');
}finally{await browser?.close();await app.close();}
