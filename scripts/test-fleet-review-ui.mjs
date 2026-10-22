import {chromium,expect} from '@playwright/test';
import assert from 'node:assert/strict';
import {startPreview} from './fleet-preview.mjs';
import {ids} from './fleet-test-db.mjs';
const app=await startPreview();let browser;
try{
 browser=await chromium.launch({headless:true,executablePath:process.env.FLEET_CHROMIUM_PATH||undefined,args:['--no-sandbox','--disable-dev-shm-usage',...JSON.parse(process.env.FLEET_CHROMIUM_ARGS||'[]')]});
 const p=await browser.newPage({viewport:{width:390,height:844}});const errors=[];p.on('pageerror',e=>errors.push(e.message));
 await p.route('**/*',r=>r.request().url().startsWith(app.url)||/^(data:|blob:)/.test(r.request().url())?r.continue():r.abort());
 const car=await app.rpc('fleet','fleet_vehicle_save',{p_id:null,p_revision:null,p_data:{plate:'REVIEW MOBILE',vehicle_type:'اختبار صور',active:true,odometer:10},p_reason:'اختبار معزول'});
 await p.goto(app.url+'/fleet/index.html?qa=fleet');await expect(p.locator('#fleetStatus')).toHaveText('');
 await p.locator('[data-tab=vehicles]').click();await p.locator('#vehicleRows tr').filter({hasText:'REVIEW MOBILE'}).getByRole('button',{name:'ملف السيارة'}).click();
 await expect(p.locator('.fleet-profile-section')).toHaveCount(4);await expect(p.locator('.fleet-profile-section[open]')).toHaveCount(0);await p.screenshot({path:'test-results/fleet-review-profile-mobile.png',fullPage:true});
 await p.getByRole('button',{name:'محضر تسليم للموظف'}).click();await p.locator('[name=employee_id]').selectOption(ids.driver);await p.locator('[name=no_marks]').check();
 const png=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/l9sAAAAASUVORK5CYII=','base64');
 const camera=p.locator('input[data-attachment-source=camera]');
 await camera.setInputFiles({name:'front.png',mimeType:'image/png',buffer:png});await camera.setInputFiles({name:'rear.png',mimeType:'image/png',buffer:Buffer.concat([png,Buffer.from('rear')])});
 assert.equal(await p.locator('[name=photos]').evaluate(e=>e.files.length),2);
 await p.getByRole('button',{name:'حذف front.png',exact:true}).click();assert.equal(await p.locator('[name=photos]').evaluate(e=>e.files.length),1);
 await camera.setInputFiles({name:'front.png',mimeType:'image/png',buffer:png});assert.equal(await p.locator('[name=photos]').evaluate(e=>e.files.length),2);
 let lostSave=false,lostPhoto=false;
 await p.route('**/__qa/rpc',async route=>{const body=route.request().postDataJSON();
  if((body.name==='fleet_handover_save_retry'&&!lostSave)||(body.name==='fleet_handover_upload'&&!lostPhoto)){
   if(body.name==='fleet_handover_save_retry')lostSave=true;else lostPhoto=true;
   await route.fetch();await route.fulfill({status:503,contentType:'application/json',body:JSON.stringify({error:{message:'انقطاع رد تجريبي بعد الحفظ'}})});
  }else await route.continue();
 });
 const save=p.locator('#handoverForm button[type=submit]');await save.click();await expect(p.locator('#dialogStatus')).toContainText('انقطاع رد');
 assert.equal((await app.db.query('select count(*)::int n from private.fleet_handovers where vehicle_id=$1',[car])).rows[0].n,1);
 await save.click();await expect(p.locator('#dialogStatus')).toContainText('استكمال الصور دون تكرار');await expect(p.locator('#handoverUploadStatus')).toContainText('تعذر التأكد');
 await save.click();await expect(p.locator('#fleetDialog')).not.toBeVisible();
 assert.equal((await app.db.query('select count(*)::int n from private.fleet_handovers where vehicle_id=$1',[car])).rows[0].n,1);
 assert.equal((await app.db.query('select count(*)::int n from private.fleet_handover_photos f join private.fleet_handovers h on h.id=f.handover_id where h.vehicle_id=$1',[car])).rows[0].n,2);
 await p.goto(app.url+'/fleet/index.html?qa=admin');await expect(p.locator('#fleetStatus')).toHaveText('');await p.locator('#workflowSettings').click();
 await p.locator('#escalationSettingsForm [name=escalation_days]').fill('4');await p.locator('#escalationSettingsForm button[type=submit]').click();await expect(p.locator('#fleetDialog')).not.toBeVisible();assert.equal((await app.rpc('admin','fleet_operations_context')).settings.escalation_days,4);
 assert.deepEqual(errors,[]);console.log('PASS review UI: mobile camera accumulation/removal, lost save/photo responses recover without duplicate records/files, compact vehicle profile and admin escalation settings.');
}finally{await browser?.close();await app.close();}
