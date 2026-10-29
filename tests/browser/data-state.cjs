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
  assert.deepEqual(errors,[]);
  console.log('PASS: isolated data states at desktop and 412/390/360 widths; safe text, accessible state, retry lock and rejected retry recovery.');
 }finally{await browser.close()}
})().catch(error=>{console.error(error);process.exit(1)});
