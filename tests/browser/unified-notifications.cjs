// Check every real content page with its actual shell/CSS, without business scripts or backend access.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {chromium}=require(process.env.ATWAR_PLAYWRIGHT_MODULE||'playwright');
const root=path.resolve(__dirname,'../..');
const walk=d=>fs.readdirSync(d,{withFileTypes:true}).flatMap(e=>['.git','node_modules','tests','assets','supabase','scripts'].includes(e.name)?[]:e.isDirectory()?walk(path.join(d,e.name)):e.name.endsWith('.html')?[path.join(d,e.name)]:[]);
(async()=>{const browser=await chromium.launch({headless:true,...(process.env.ATWAR_CHROMIUM_PATH?{executablePath:process.env.ATWAR_CHROMIUM_PATH}:{}),args:['--no-sandbox','--disable-dev-shm-usage','--no-zygote','--single-process','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});try{
const context=await browser.newContext();const page=await context.newPage();await page.context().addInitScript(()=>{
localStorage.setItem('atwarSession',JSON.stringify({id:'u1',full_name:'اختبار الإشعارات',role:'admin'}));
window.notificationFixture={total_unread:3,modules:{it_support:1,tasks:2},items:[{id:'it1',type:'IT_SUPPORT',module:'it_support',title:'طلب دعم للاختبار',message:'تفاصيل الاختبار',read_at:null,created_at:'2026-01-01T12:00:00Z',unread_count:2,unread_ids:['it1','it2']}]};
window.atwarGetSupabase=async()=>({auth:{getSession:async()=>({data:{session:{user:{id:'u1'}}}}),onAuthStateChange:()=>({data:{subscription:{unsubscribe(){}}}})},rpc:async(name)=>{if(name==='notification_overview')return window.notificationFail?{error:{message:'offline'}}:{data:JSON.parse(localStorage.getItem('notification-test-feed')||'null')||window.notificationFixture};if(name==='it_support_notification_open')return {data:{ticket_id:'ticket1',purchase:false}};return {data:true}},from:()=>({update(){return this},eq(){return this},is(){return this},lte(){return Promise.resolve({})},in(key,ids){localStorage.setItem('notification-test-read',JSON.stringify(ids));return Promise.resolve({})},select(){return this},maybeSingle(){return Promise.resolve({data:null})}})});
});
await page.context().route('**/*',route=>{const u=new URL(route.request().url()),f=path.join(root,decodeURIComponent(u.pathname));if(u.hostname!=='127.0.0.1')return route.fulfill({body:'',contentType:'text/plain'});if(!fs.existsSync(f)||!fs.statSync(f).isFile())return route.fulfill({status:404,body:''});if(f.endsWith('.js')||f.endsWith('.mjs')){if(!/\/(shell-components\.js|mobile-experience\.mjs|ui-feedback\.js)$/.test(u.pathname))return route.fulfill({body:'',contentType:'text/javascript'});}
let body=fs.readFileSync(f);if(f.endsWith('.html'))body=Buffer.from(body.toString().replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi,tag=>tag.includes('src=')&&(tag.includes('shell-components.js')||tag.includes('ui-feedback.js'))?tag:'').replace(/<meta[^>]*http-equiv=["']refresh["'][^>]*>/gi,''));return route.fulfill({body,contentType:f.endsWith('.html')?'text/html':f.endsWith('.css')?'text/css':/\.m?js$/.test(f)?'text/javascript':f.endsWith('.svg')?'image/svg+xml':'text/plain'});});

for(const url of ['home.html','tasks/index.html']){
 await page.setViewportSize({width:1440,height:900});await page.goto('http://127.0.0.1:8765/'+url);
 await page.evaluate(()=>{document.body.style.visibility='visible';document.getElementById('appShell')?.classList.remove('hidden');document.getElementById('authLoadingScreen')?.remove()});
 const bell=page.locator('[data-global-notification-button]');await page.waitForFunction(()=>window.AtwarNotifications?.snapshot?.total_unread===3);
 assert.equal(await page.locator('[data-global-notification-badge]').textContent(),'3',url);
 assert.equal(await page.locator('[data-notification-module=it_support] .atwar-module-badge').textContent(),'1',url);
 assert.equal(await page.locator('[data-notification-module=tasks] .atwar-module-badge').textContent(),'2',url);
 assert.equal(await page.locator('[data-notification-module=fleet] .atwar-module-badge:visible').count(),0,url);
 await bell.click();assert.equal(await bell.getAttribute('aria-expanded'),'true');await page.keyboard.press('Escape');assert.equal(await bell.getAttribute('aria-expanded'),'false');
 assert.equal(await page.locator('[data-global-notification-badge]').textContent(),'3','Opening bell must not mark notifications read');
 await page.evaluate(()=>{window.notificationFixture={total_unread:120,modules:{it_support:120},items:[]};return window.AtwarNotifications.refresh()});
 assert.equal(await page.locator('[data-notification-module=it_support] .atwar-module-badge').textContent(),'99+');
 await page.evaluate(()=>{window.notificationFixture={total_unread:0,modules:{},items:[]};return window.AtwarNotifications.refresh()});
 assert.equal(await page.locator('.atwar-module-badge:visible').count(),0);
 await page.evaluate(()=>{window.notificationFixture={total_unread:1,modules:{it_support:1},items:[{id:'it1',type:'IT_SUPPORT',module:'it_support',title:'طلب دعم للاختبار',created_at:'2030-01-01T12:00:00Z',unread_ids:['it1','it2'],unread_count:2}]};return window.AtwarNotifications.refresh()});
 assert.equal(await page.locator('[data-atwar-arrival]').count(),url==='home.html'?1:0,'Arrival shown once across page navigation');
 if(url==='home.html'){
  await page.locator('[aria-label="إغلاق التنبيه"]').click();await page.evaluate(()=>window.AtwarNotifications.refresh());assert.equal(await page.locator('[data-atwar-arrival]').count(),0,'Refreshing does not replay arrival');
 }
 for(const width of[1440,390,320]){
  await page.setViewportSize({width,height:900});if(width<700){await page.locator('.atwar-mobile-menu').click();await page.waitForTimeout(250)}
  const link=page.locator('[data-notification-module=it_support]');await link.waitFor({state:'visible'});
  const inside=await link.locator('.atwar-module-badge').evaluate(e=>{const r=e.getBoundingClientRect();return r.left>=0&&r.right<=innerWidth});assert(inside,`${url} badge at ${width}`);
  if(width<700)await page.locator('.atwar-mobile-close').click();
  await bell.click();const box=await page.locator('[data-global-notification-panel]').boundingBox();assert(box.x>=0&&box.x+box.width<=width+1,`${url} panel at ${width}`);await page.keyboard.press('Escape');
 }
}

const second=await page.context().newPage();await second.goto('http://127.0.0.1:8765/home.html');await second.waitForFunction(()=>window.AtwarNotifications?.snapshot);
const fresh=()=>{window.notificationFixture={total_unread:1,modules:{it_support:1},items:[{id:'fresh',type:'IT_SUPPORT',module:'it_support',title:'new cross tab',created_at:'2031-01-01T12:00:00Z',unread_ids:['fresh']}]};return window.AtwarNotifications.refresh()};
await Promise.all([page.evaluate(fresh),second.evaluate(fresh)]);
assert.equal(await page.locator('[data-atwar-arrival]').count()+await second.locator('[data-atwar-arrival]').count(),1,'Only one tab announces each arrival');
await page.evaluate(()=>{localStorage.setItem('notification-test-feed',JSON.stringify({total_unread:0,modules:{},items:[]}));window.atwarNotifyReadChange()});
await second.waitForFunction(()=>window.AtwarNotifications.snapshot.total_unread===0);await page.waitForFunction(()=>window.AtwarNotifications.snapshot.total_unread===0);
await second.close();await page.evaluate(()=>{localStorage.removeItem('notification-test-feed');window.notificationFixture={total_unread:1,modules:{it_support:1},items:[{id:'it1',type:'IT_SUPPORT',module:'it_support',title:'طلب دعم للاختبار',created_at:'2030-01-01T12:00:00Z',unread_ids:['it1','it2'],unread_count:2}]};return window.AtwarNotifications.refresh()});
assert.equal(await page.evaluate(async()=>window.atwarOpenNotificationRecord(await window.atwarGetSupabase(),{id:'missing',task_id:'missing'},'../',()=>{})),false,'Unavailable records must not be marked read');
assert.equal(await page.evaluate(()=>localStorage.getItem('notification-test-read')),null);
await page.evaluate(()=>{window.notificationFail=true;return window.AtwarNotifications.refresh()});assert.equal(await page.locator('[data-global-notification-badge]').textContent(),'1','A read error preserves the last confirmed count');await page.evaluate(()=>{window.notificationFail=false;return window.AtwarNotifications.refresh()});
await page.setViewportSize({width:1440,height:900});await page.locator('[data-global-notification-button]').click();
await page.locator('[data-global-notification-id=it1]').click();await page.waitForURL('**/it-support/index.html?request=ticket1');
assert.deepEqual(await page.evaluate(()=>JSON.parse(localStorage.getItem('notification-test-read'))),['it1','it2'],'Opening a grouped request marks every unread update, retaining records');
console.log('PASS unified notifications: identical task/global bell, sidebar grouping/counts/99+, no clearing on menu open, arrival dedupe, read-group routing and desktop/mobile layouts.');
}finally{await browser.close();}})().catch(e=>{console.error(e);process.exit(1)});
