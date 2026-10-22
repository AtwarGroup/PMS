import {chromium,expect} from '@playwright/test';
import assert from 'node:assert/strict';
import {startPreview} from './fleet-preview.mjs';
import {ids} from './fleet-test-db.mjs';
const app=await startPreview();let browser;const errors=[];
try{
 browser=await chromium.launch({headless:true,executablePath:process.env.FLEET_CHROMIUM_PATH||undefined,args:['--no-sandbox','--disable-dev-shm-usage',...JSON.parse(process.env.FLEET_CHROMIUM_ARGS||'[]')]});
 const pages={};
 const pageFor=async actor=>{if(!pages[actor]){const p=await browser.newPage({viewport:{width:1440,height:1000}});p.on('pageerror',e=>errors.push(e.message));await p.route('**/*',r=>r.request().url().startsWith(app.url)||/^(data:|blob:)/.test(r.request().url())?r.continue():r.abort());pages[actor]=p;}await pages[actor].goto(app.url+'/fleet/index.html?qa='+actor);await expect(pages[actor].locator('#fleetStatus')).toHaveText('');return pages[actor];};
 const car=await app.rpc('fleet','fleet_vehicle_save',{p_id:null,p_revision:null,p_data:{plate:'UI HANDOVER 1',vehicle_type:'سيارة اختبار المحضر',active:true,odometer:100},p_reason:'سجل تجريبي معزول'});
 const profile=async p=>{await p.locator('[data-tab=vehicles]').click();await p.locator('#vehicleRows tr').filter({hasText:'UI HANDOVER 1'}).getByRole('button',{name:'ملف السيارة'}).click();await expect(p.locator('#dialogTitle')).toContainText('ملف السيارة');};
 let fleet=await pageFor('fleet');await profile(fleet);
 await fleet.getByRole('button',{name:'تحديث حالة التشغيل'}).click();await fleet.locator('#operationForm [name=status]').selectOption('maintenance');await fleet.locator('#operationForm [name=reason]').fill('دخول الورشة للفحص');await fleet.locator('#operationForm button[type=submit]').click();await expect(fleet.locator('#fleetDialog')).not.toBeVisible();
 await profile(fleet);await expect(fleet.locator('#dialogBody')).toContainText('تحت الصيانة');await expect(fleet.locator('#dialogBody')).toContainText('سجل التشغيل والتوقف');
 await fleet.getByRole('button',{name:'تحديث حالة التشغيل'}).click();await fleet.locator('#operationForm [name=status]').selectOption('available');await fleet.locator('#operationForm [name=reason]').fill('اكتمل الفحص وأصبحت متاحة');await fleet.locator('#operationForm button[type=submit]').click();await expect(fleet.locator('#fleetDialog')).not.toBeVisible();
 await profile(fleet);await fleet.getByRole('button',{name:'محضر تسليم للموظف'}).click();await fleet.locator('#handoverForm [name=employee_id]').selectOption(ids.driver);await fleet.locator('#handoverForm [name=odometer]').fill('110');
 await fleet.locator('#carSketch').getByRole('button',{name:'الصدام الأمامي',exact:true}).click();await fleet.locator('#markNote').fill('خدش صغير في الصدام الأمامي');await fleet.locator('#addMark').click();await expect(fleet.locator('#markRows')).toContainText('الصدام الأمامي');
 const png={name:'inspection.png',mimeType:'image/png',buffer:Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/l9sAAAAASUVORK5CYII=','base64')};
 await fleet.locator('#handoverForm [name=photos]').setInputFiles(png);await fleet.locator('#handoverForm [name=spare_tire]').check();await fleet.locator('#handoverForm [name=tools]').check();
 await fleet.screenshot({path:'test-results/fleet-handover-diagram-desktop.png',fullPage:true});
 await fleet.locator('#handoverForm button[type=submit]').click();await expect(fleet.locator('#fleetDialog')).not.toBeVisible();
 const openLatest=async p=>{await p.locator('[data-tab=handovers]').click();await p.locator('#handoverRows article').filter({hasText:'UI HANDOVER 1'}).first().getByRole('button',{name:'عرض المحضر'}).click();};
 await openLatest(fleet);await fleet.getByRole('button',{name:'إرسال لإقرار الموظف'}).click();await expect(fleet.locator('#fleetDialog')).not.toBeVisible();
 let driver=await pageFor('driver');await openLatest(driver);await expect(driver.locator('#handoverReport')).toContainText('خدش صغير');await expect(driver.locator('#submitHandover')).toHaveCount(0);
 await driver.getByRole('button',{name:'تأكيد المحضر وتحديث العهدة'}).click();await expect(driver.locator('#dialogStatus')).toContainText('يلزم تأكيد مراجعة');await driver.locator('#ackHandover [name=reviewed]').check();await driver.getByRole('button',{name:'تأكيد المحضر وتحديث العهدة'}).click();await expect(driver.locator('#fleetDialog')).not.toBeVisible();
 assert.equal((await app.rpc('driver','fleet_vehicle_profile',{p_vehicle:car})).vehicle.driver_id,ids.driver);
 await openLatest(driver);await driver.locator('#printHandover').click();const print=driver.frameLocator('#handoverPrintFrame');await expect(print.locator('h1')).toContainText('محضر تسليم');await expect(print.locator('.fleet-car-diagram')).toBeVisible();await expect(print.locator('.fleet-handover-print-photos img')).toHaveCount(1);
 await driver.locator('#closeDialog').click();
 fleet=await pageFor('fleet');await profile(fleet);await fleet.getByRole('button',{name:'محضر استلام من الموظف'}).click();await fleet.locator('#handoverForm [name=no_marks]').check();await fleet.locator('#handoverForm [name=odometer]').fill('120');await fleet.locator('#handoverForm button[type=submit]').click();await expect(fleet.locator('#fleetDialog')).not.toBeVisible();await openLatest(fleet);await fleet.getByRole('button',{name:'إرسال لإقرار الموظف'}).click();await expect(fleet.locator('#fleetDialog')).not.toBeVisible();
 driver=await pageFor('driver');await driver.setViewportSize({width:390,height:844});await openLatest(driver);await driver.locator('#disputeHandover').click();await driver.locator('#handoverReason [name=reason]').fill('توجد ملاحظة لم يتم تسجيلها');await driver.locator('#handoverReason button[type=submit]').click();await expect(driver.locator('#fleetDialog')).not.toBeVisible();
 assert.equal((await app.rpc('driver','fleet_vehicle_profile',{p_vehicle:car})).vehicle.driver_id,ids.driver);
 fleet=await pageFor('fleet');await fleet.setViewportSize({width:390,height:844});await profile(fleet);await fleet.getByRole('button',{name:'محضر استلام من الموظف'}).click();await fleet.locator('#handoverForm [name=no_marks]').check();await fleet.locator('#handoverForm [name=odometer]').fill('120');
 for(const width of [320,390]){await fleet.setViewportSize({width,height:844});assert.equal(await fleet.evaluate(()=>document.documentElement.scrollWidth>innerWidth+2),false);}
 await fleet.screenshot({path:'test-results/fleet-handover-diagram-mobile.png',fullPage:true});await fleet.locator('#handoverForm button[type=submit]').click();await expect(fleet.locator('#fleetDialog')).not.toBeVisible();await openLatest(fleet);await fleet.locator('#submitHandover').click();await expect(fleet.locator('#fleetDialog')).not.toBeVisible();
 driver=await pageFor('driver');await openLatest(driver);await driver.locator('#ackHandover [name=reviewed]').check();await driver.getByRole('button',{name:'تأكيد المحضر وتحديث العهدة'}).click();await expect(driver.locator('#fleetDialog')).not.toBeVisible();
 assert.equal((await app.rpc('fleet','fleet_vehicle_profile',{p_vehicle:car})).vehicle.driver_id,null);
 // Verify the journey and exception dashboard through the real RPC-backed page.
 const vehicle=(await app.rpc('driver','fleet_snapshot')).vehicles.find(v=>v.plate==='QA 1234');
 const data={vehicle_id:vehicle.id,accountant_id:ids.accountant,description:'طلب اختبار مراحل العمل',request_type:'repair',odometer:13000,quotes:[],selected_quote:0};
 const rid=await app.rpc('driver','fleet_request_save',{p_id:null,p_revision:null,p_data:data});
 for(let i=0;i<3;i++)data.quotes.push({supplier:'ورشة مراحل '+i,parts:400,labor:0,tax:0,file_id:await app.rpc('driver','fleet_upload',{p_request:rid,p_kind:'quote',p_name:'quote.pdf',p_mime:'application/pdf',p_base64:Buffer.from('%PDF-1.4 QA').toString('base64')})});
 await app.rpc('driver','fleet_request_save',{p_id:rid,p_revision:1,p_data:data});await app.rpc('driver','fleet_command',{p_id:rid,p_revision:2,p_action:'submit',p_data:{}});
 await app.db.query("update private.fleet_requests set state_changed_at=now()-interval '4 days'where id=$1",[rid]);
 fleet=await pageFor('fleet');await expect(fleet.locator('#fleetExceptions')).toContainText('طلبات تجاوزت مدة المرحلة');await fleet.locator('#fleetExceptions [data-request]').first().click();await expect(fleet.locator('.fleet-progress [aria-current=step]')).toContainText('مراجعة مسؤول الأسطول');await expect(fleet.locator('.fleet-journey-info')).toContainText('مسؤول الأسطول التجريبي');await fleet.locator('#closeDialog').click();
 const admin=await pageFor('admin');await admin.locator('#workflowSettings').click();await admin.locator('#workflowSettingsForm [name=stage_days]').fill('5');await admin.locator('#workflowSettingsForm button[type=submit]').click();await expect(admin.locator('#fleetDialog')).not.toBeVisible();assert.equal((await app.rpc('admin','fleet_operations_context')).settings.stage_days,5);
 const accountant=await pageFor('accountant2');await expect(accountant.locator('#newRequest')).toBeHidden();await expect(accountant.locator('#tab-handovers')).toBeHidden();
 assert.deepEqual(errors,[]);console.log('PASS UI: operational history, vehicle profile, annotated car diagram, photos, print report, independent acknowledgement/dispute/return, mobile layout, journey, scoped exceptions and admin reminder settings.');
}finally{await browser?.close();await app.close();}
