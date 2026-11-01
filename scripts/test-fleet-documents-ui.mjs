import {chromium,expect} from '@playwright/test';
import assert from 'node:assert/strict';
import {mkdir} from 'node:fs/promises';
import {startPreview} from './fleet-preview.mjs';
import {ids,seedAssignedVehicle} from './fleet-test-db.mjs';
const app=await startPreview();let browser;
try {
 const cars={},dates={},errors=[];
 for(const days of [46,45,16,15,0,-1]) {
  const car=await seedAssignedVehicle(app.db,app.rpc,'fleet',{p_id:null,p_revision:null,p_data:{plate:'DOC '+days,vehicle_type:'سيارة اختبار الوثائق',driver_id:days===15?ids.outsider:ids.driver,active:true,odometer:10},p_reason:'بيانات معزولة لفحص فلاتر الوثائق'});
  cars[days]=car;dates[days]=(await app.db.query("select (timezone('Asia/Riyadh',now())::date+$1::int)::text d",[days])).rows[0].d;
  await app.rpc('fleet','fleet_document_save',{p_vehicle:car,p_kind:'insurance',p_expires:dates[days],p_revision:null,p_reason:'اختبار ألوان حدود انتهاء الوثائق'});
 }
 const far=(await app.db.query("select (timezone('Asia/Riyadh',now())::date+100)::text d")).rows[0].d;
 await app.rpc('fleet','fleet_document_save',{p_vehicle:cars[45],p_kind:'registration',p_expires:far,p_revision:null,p_reason:'تاريخ آخر لفحص تقاطع الفلاتر'});
 browser=await chromium.launch({headless:true,args:['--no-sandbox','--disable-dev-shm-usage']});
 const p=await browser.newPage({viewport:{width:1440,height:1000}});p.on('pageerror',e=>errors.push(e.message));
 await p.route('**/*',r=>r.request().url().startsWith(app.url)||/^(data:|blob:)/.test(r.request().url())?r.continue():r.abort());
 await p.goto(app.url+'/fleet/index.html?qa=fleet&view=documents');await expect(p.locator('#documents')).toBeVisible();await expect(p.locator('#documentRows tr')).toHaveCount(7);
 const row=days=>p.locator(`#documentRows [data-document-vehicle="${cars[days]}"]`);
 for(const [days,state] of [[46,'valid'],[45,'warning'],[16,'warning'],[15,'urgent'],[0,'urgent'],[-1,'expired']])await expect(row(days)).toHaveAttribute('data-document-state',state);
 for(const [days,color] of [[45,'rgb(255, 251, 235)'],[15,'rgb(255, 241, 242)'],[-1,'rgb(255, 228, 230)']])assert.equal(await row(days).locator('td').first().evaluate(e=>getComputedStyle(e).backgroundColor),color);
 await expect(row(0)).toContainText('تنتهي اليوم');await expect(row(-1)).toContainText('منتهية منذ 1 يوم');
 await p.locator('#documentState').selectOption('expired');await expect(p.locator('#documentRows tr')).toHaveCount(1);
 await p.locator('#clearDocumentFilters').click();await p.locator('#documentKind').selectOption('insurance');await expect(p.locator('#documents th[data-document-kind=registration]')).toBeHidden();await expect(p.locator('#documents th[data-document-kind=insurance]')).toBeVisible();
 await p.locator('#documentDateFrom').fill(dates[45]);await p.locator('#documentDateTo').fill(dates[45]);await p.locator('#documentDateTo').blur();await expect(p.locator('#documentRows tr')).toHaveCount(1);await expect(row(45)).toBeVisible();
 await p.locator('#documentDateFrom').fill(far);await p.locator('#documentDateTo').fill(far);await p.locator('#documentDateTo').blur();await expect(p.locator('#documentRows tr')).toHaveCount(0);await expect(p.locator('#documentEmpty')).toContainText('لا توجد وثائق تطابق');
 await p.locator('#documentDateFrom').fill(far);await p.locator('#documentDateTo').fill(dates[45]);await p.locator('#documentDateTo').blur();await expect(p.locator('#documentFilterStatus')).toContainText('«إلى»');
 await p.locator('#clearDocumentFilters').click();await expect(p.locator('#documentFilterStatus')).toHaveText('');await expect(p.locator('#documentRows tr')).toHaveCount(7);
 await p.locator('#documentVehicle').selectOption(cars[15]);await expect(p.locator('#documentRows tr')).toHaveCount(1);
 await p.locator('#refreshDocuments').click();await expect(p.locator('#documentVehicle')).toHaveValue(cars[15]);await expect(row(15)).toBeVisible();
 await p.locator('#clearDocumentFilters').click();await p.locator('#documentDriver').selectOption({label:'موظف خارج الفريق'});await expect(p.locator('#documentRows tr')).toHaveCount(1);await expect(row(15)).toBeVisible();
 await p.locator('#clearDocumentFilters').click();await p.locator('#documentSearch').fill('DOC ٤٥');await expect(p.locator('#documentRows tr')).toHaveCount(1);
 await p.locator('#clearDocumentFilters').click();await mkdir('test-results',{recursive:true});await p.locator('#documents').screenshot({path:'test-results/fleet-documents-desktop.png'});
 for(const width of [320,390]){await p.setViewportSize({width,height:844});assert.equal(await p.evaluate(()=>document.documentElement.scrollWidth>innerWidth+2),false);await p.locator('#documentState').selectOption('urgent');await expect(p.locator('#documentRows tr')).toHaveCount(2);await p.locator('#clearDocumentFilters').click();}
 await p.locator('#documents').screenshot({path:'test-results/fleet-documents-mobile.png'});
 await p.goto(app.url+'/fleet/index.html?qa=manager&view=documents');await expect(p.locator('#documents')).toBeVisible();await expect(p.locator('#documentSettings')).toBeHidden();await expect(p.locator('[data-documents]')).toHaveCount(0);await expect(p.locator(`#documentRows [data-document-vehicle="${cars[15]}"]`)).toHaveCount(0);
 await p.goto(app.url+'/fleet/index.html?qa=fleet&view=documents&vehicle='+cars[45]);await expect(p.locator('#documentVehicle')).toHaveValue(cars[45]);await expect(p.locator('#documentRows tr')).toHaveCount(1);await p.locator('#clearDocumentFilters').click();assert.equal(new URL(p.url()).searchParams.has('vehicle'),false);await expect(p.locator('#documentRows tr')).toHaveCount(7);
 assert.deepEqual(errors,[]);console.log('PASS document UI: row/cell urgency boundaries and colors, combined filters, inclusive dates and invalid ranges, refresh/reset/deep links, mobile widths and existing role boundaries.');
} finally {await browser?.close();await app.close();}
