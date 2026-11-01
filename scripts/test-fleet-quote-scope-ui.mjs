import {chromium,expect} from '@playwright/test';
import assert from 'node:assert/strict';
import {startPreview} from './fleet-preview.mjs';
import {ids} from './fleet-test-db.mjs';
const app=await startPreview();let browser;const errors=[];
try {
 browser=await chromium.launch({headless:true,args:['--no-sandbox','--disable-dev-shm-usage']});
 const p=await browser.newPage({viewport:{width:390,height:844}});p.on('pageerror',e=>errors.push(e.message));
 await p.route('**/*',r=>r.request().url().startsWith(app.url)||/^(data:|blob:)/.test(r.request().url())?r.continue():r.abort());
 for(const scope of ['parts_labor','parts','labor']) {
  await p.goto(app.url+'/fleet/index.html?qa=driver');await expect(p.locator('#fleetStatus')).toHaveText('');await p.locator('#newRequest').click();
  await p.locator('[name=accountant_id]').selectOption(ids.accountant);await p.locator('[name=maintenance_kind]').selectOption('tire');
  await p.locator('[name=odometer]').fill('12510');await p.locator('[name=description]').fill('طلب اختبار نطاق العرض '+scope);await p.locator('[name=fault_notes]').fill('معاينة صيانة لتحديد قطع الغيار وأجرة اليد');
  await expect(p.locator('[data-quote]').nth(2)).toHaveAttribute('data-included','false');
  for(let i=0;i<2;i++) {
   const q=p.locator('[data-quote]').nth(i);await expect(q.locator('[name=scope] option')).toHaveText(['قطع غيار وأجرة يد','قطع غيار فقط','أجرة يد فقط']);
   // A value entered before changing scope must never reach the approved total.
   await q.locator('[name=parts]').fill('100');await q.locator('[name=labor]').fill('50');await q.locator('[name=scope]').selectOption(scope);
   await q.locator('[name=supplier]').fill('ورشة اختبار واجهة رقم '+i);await q.locator('[name=phone]').fill('0501234567');
   for(const kind of ['parts','labor']) {
    const included=scope==='parts_labor'||scope===kind;
    if(included){await expect(q.locator(`[name=${kind}]`)).toBeVisible();await expect(q.locator(`[name=${kind}_file]`)).toHaveAttribute('required','');
     await q.locator(`[name=${kind}_file]`).setInputFiles({name:scope+kind+i+'.pdf',mimeType:'application/pdf',buffer:Buffer.from('%PDF-1.4 '+scope+kind+i)});
    }else{await expect(q.locator(`[name=${kind}]`)).toBeHidden();await expect(q.locator(`[name=${kind}]`)).toBeDisabled();await expect(q.locator(`[name=${kind}_file]`)).not.toHaveAttribute('required','');}
   }
   await expect(q.locator('[data-quote-total]')).toHaveText(scope==='parts'?'100.00':scope==='labor'?'50.00':'150.00');
  }
  assert.equal(await p.evaluate(()=>document.documentElement.scrollWidth>innerWidth+2),false);
  await p.getByRole('button',{name:'حفظ مسودة',exact:true}).click();await expect(p.locator('#fleetDialog')).not.toBeVisible();
  const row=(await app.db.query('select id,quotes from private.fleet_requests where description=$1',['طلب اختبار نطاق العرض '+scope])).rows[0];
  assert.equal(row.quotes[0].scope,scope);if(scope!=='parts_labor'){const excluded=scope==='parts'?'labor':'parts';assert.equal(row.quotes[0][excluded],0);assert.equal(row.quotes[0][excluded+'_file_id'],undefined);}
  await p.locator(`#fleetWorkRows [data-request="${row.id}"]`).click();await p.locator('[data-action=edit]').click();
  await expect(p.locator('[data-quote]').first().locator('[name=scope]')).toHaveValue(scope);
  // Saved evidence satisfies the selected scope without asking for another upload.
  for(const q of await p.locator('[data-quote][data-included=true]').all())for(const kind of ['parts','labor'])await expect(q.locator(`[name=${kind}_file]`)).not.toHaveAttribute('required','');
  await p.getByRole('button',{name:'إرسال الطلب للاعتماد',exact:true}).click();await expect(p.locator('#fleetDialog')).not.toBeVisible();
  assert.equal((await app.rpc('driver','fleet_detail',{p_id:row.id})).request.state,'manager_review');
 }
 assert.deepEqual(errors,[]);console.log('PASS scope UI: dropdown modes, hidden/disabled excluded fields, correct totals, optional third quote, mobile layout, draft persistence and submission with selected evidence only.');
}finally{await browser?.close();await app.close();}
