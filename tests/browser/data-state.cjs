// Isolated presentation contract: all external requests are blocked; no business scripts run.
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {chromium}=require('playwright');
const root=path.resolve(__dirname,'../..');
(async()=>{
 const browser=await chromium.launch({headless:true,args:['--no-sandbox']});
 try{
  const page=await browser.newPage();
  await page.route('**/*',route=>{
   const url=new URL(route.request().url());
   const allowed=['/assets/js/data-state.mjs','/assets/css/design-system.css','/assets/css/components.css'];
   if(url.hostname==='127.0.0.1'&&allowed.includes(url.pathname))return route.fulfill({body:fs.readFileSync(path.join(root,url.pathname)),contentType:url.pathname.endsWith('.mjs')?'text/javascript':'text/css'});
   return route.fulfill({body:'<!doctype html><html lang="ar" dir="rtl"><head><link rel="stylesheet" href="/assets/css/design-system.css"><link rel="stylesheet" href="/assets/css/components.css"></head><body><main id="host"></main></body></html>',contentType:'text/html'});
  });
  const errors=[];page.on('pageerror',error=>errors.push(error.message));
  await page.goto('http://127.0.0.1:8765/state-test');
  await page.evaluate(async()=>{window.renderState=(await import('/assets/js/data-state.mjs')).renderDataState});
  for(const width of [1440,412,390,360]){
   await page.setViewportSize({width,height:900});
   for(const state of ['loading','empty','error']){
    await page.evaluate(state=>window.renderState(document.getElementById('host'),{state,message:'<img src=x onerror=alert(1)>'}),state);
    assert.equal(await page.locator('#host img').count(),0);
    assert.equal(await page.locator('#host > div').getAttribute('aria-busy'),String(state==='loading'));
    assert.equal(await page.locator('#host > div').getAttribute('role'),state==='error'?'alert':'status');
    assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);
   }
  }
  await page.evaluate(()=>{
   window.retryCount=0;
   window.renderState(document.getElementById('host'),{state:'error',onRetry:()=>{window.retryCount++;return new Promise((resolve,reject)=>{window.rejectRetry=reject})}});
   const button=document.querySelector('#host button');button.click();button.dispatchEvent(new Event('click'));button.dispatchEvent(new Event('click'));
  });
  assert.equal(await page.evaluate(()=>window.retryCount),1);
  assert.equal(await page.locator('#host button').isDisabled(),true);
  await page.evaluate(()=>window.rejectRetry(new Error('Offline')));
  await page.waitForFunction(()=>!document.querySelector('#host button').disabled);
  assert.equal(await page.locator('#host > div').getAttribute('aria-busy'),'false');
  // Execute the actual notifications module against a delayed, read-only synthetic client.
  const notificationHTML=fs.readFileSync(path.join(root,'notifications/index.html'),'utf8');
  const moduleSource=notificationHTML.match(/<script type="module" id="notificationsSupabaseBinding">([\s\S]*?)<\/script>/)[1]
   .replace(/import \{renderDataState\} from [^;]+;/,'const renderDataState=window.renderState;');
  await page.evaluate(source=>{
   document.body.innerHTML='<section id="notifList"></section><div id="notifEmpty" style="display:none">فارغ</div><div id="notifNotice"></div>';
   window.notificationReads=0;
   window.atwarGetSupabase=async()=>({
    auth:{getSession:async()=>({data:{session:{user:{id:'isolated-user'}}}})},
    from(table){
     if(table==='profiles'){const query={select(){return query},eq(){return query},single:async()=>({data:{id:'isolated-user',role:'employee',active:true,status:'active'}})};return query}
     throw Error('Unexpected table');
    },
    rpc(name){if(name!=='notification_overview')throw Error('Unexpected RPC');window.notificationReads++;return new Promise(resolve=>{window.resolveNotifications=resolve})}
   });
   const AsyncFunction=Object.getPrototypeOf(async function(){}).constructor;
   window.notificationFixtureDone=new AsyncFunction(source)();
  },moduleSource);
  await page.waitForFunction(()=>typeof window.resolveNotifications==='function');
  assert.equal(await page.locator('#notifEmpty').isVisible(),false,'Empty result must not appear while the read is pending');
  assert.equal(await page.locator('#notifList [data-state="loading"]').count(),1);
  await page.evaluate(()=>window.resolveNotifications({error:{message:'offline'}}));
  await page.evaluate(()=>window.notificationFixtureDone);
  assert.equal(await page.locator('#notifList [data-state="error"]').count(),1);
  assert.equal(await page.locator('#notifEmpty').isVisible(),false);
  await page.locator('#notifList button').click();
  await page.waitForFunction(()=>window.notificationReads===2);
  assert.equal(await page.locator('#notifList [data-state="loading"]').count(),1);
  await page.evaluate(()=>window.resolveNotifications({data:{items:[],modules:{},total_unread:0},error:null}));
  await page.waitForFunction(()=>document.getElementById('notifEmpty').style.display==='block');
  assert.equal(await page.locator('#notifList [data-state]').count(),0);
  assert.deepEqual(errors,[]);
  console.log('PASS: isolated data states at desktop and 412/390/360 widths; safe text, accessible state, retry lock and rejected retry recovery. Actual notification module: slow read, failure, retry and successful empty read without premature empty result.');
 }finally{await browser.close()}
})().catch(error=>{console.error(error);process.exit(1)});
