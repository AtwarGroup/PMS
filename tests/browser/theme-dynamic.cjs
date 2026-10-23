// Current production renderers generate the fixtures. All content is synthetic; no backend is reachable.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {chromium}=require(process.env.ATWAR_PLAYWRIGHT_MODULE||'playwright');
const root=path.resolve(__dirname,'../..');
(async()=>{
 const browser=await chromium.launch({headless:true,...(process.env.ATWAR_CHROMIUM_PATH?{executablePath:process.env.ATWAR_CHROMIUM_PATH}:{}),args:['--no-sandbox','--disable-dev-shm-usage','--no-zygote','--single-process','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
 try{
  const page=await browser.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.route('**/*',route=>{
   const u=new URL(route.request().url());if(u.hostname!=='127.0.0.1')return route.fulfill({body:'',contentType:'text/javascript'});
   const file=path.join(root,decodeURIComponent(u.pathname));if(!file.startsWith(root+path.sep)||!fs.existsSync(file)||!fs.statSync(file).isFile())return route.fulfill({status:404,body:''});
   return route.fulfill({body:fs.readFileSync(file),contentType:file.endsWith('.html')?'text/html':file.endsWith('.css')?'text/css':'text/javascript'});
  });
  let states=0;
  async function check(label){
   const result=await page.evaluate(()=>({overflow:document.documentElement.scrollWidth>innerWidth+2,bodyFont:getComputedStyle(document.body).fontSize,bodyToken:getComputedStyle(document.documentElement).getPropertyValue('--atwar-type-body').trim(),token:getComputedStyle(document.documentElement).getPropertyValue('--atwar-blue-600').trim(),small:[...document.querySelectorAll('button,input,label,p,td,th')].filter(e=>{const r=e.getBoundingClientRect();return r.width>0&&r.height>0&&getComputedStyle(e).visibility!=='hidden'}).filter(e=>parseFloat(getComputedStyle(e).fontSize)<11).map(e=>({tag:e.tagName,cls:e.className,size:getComputedStyle(e).fontSize,text:e.textContent.slice(0,50)}))}));
   assert.equal(result.token,'#1769e0',label);assert.equal(result.bodyFont,result.bodyToken,label);assert.equal(result.overflow,false,label+' page overflow');assert.deepEqual(result.small,[],label+' unreadable control/body scale');assert.deepEqual(errors,[],label+' browser errors');
   if(process.env.ATWAR_THEME_SCREENSHOTS){fs.mkdirSync(process.env.ATWAR_THEME_SCREENSHOTS,{recursive:true});await page.screenshot({path:path.join(process.env.ATWAR_THEME_SCREENSHOTS,label.replace(/[^a-zA-Z0-9_-]/g,'_')+'.png')});}states++;
  }
  for(const width of [1440,390]){
   await page.setViewportSize({width,height:900});
   for(const [fixture,attribute] of [['daily-work','data-preview'],['libraries','data-preview'],['job-document','data-preview']]){
    await page.goto('http://127.0.0.1:8765/tests/fixtures/'+fixture+'.html');const values=await page.locator('['+attribute+']').evaluateAll(es=>[...new Set(es.map(e=>e.getAttribute('data-preview')))]);
    for(const value of values){await page.locator(`[${attribute}="${value}"]`).click();await check(`${fixture}-${value}-${width}`);}
   }
   await page.goto('http://127.0.0.1:8765/tests/fixtures/employee-changes.html');
   for(const view of ['library','reviews','assignments','requests']){await page.locator(`[data-view="${view}"]`).click();await check(`library-tab-${view}-${width}`);}
   for(const sample of ['filled','empty']){await page.locator(`[data-sample="${sample}"]`).click();await check(`change-requests-${sample}-${width}`);}
   await page.goto('http://127.0.0.1:8765/tests/fixtures/projects.html');
   const tabs=await page.locator('[data-tab]').evaluateAll(es=>[...new Set(es.map(e=>e.dataset.tab))]);
   for(const tab of tabs){await page.locator(`[data-tab="${tab}"]`).filter({visible:true}).first().click();await check(`project-${tab}-${width}`);}
   for(const view of ['chat','notes']){await page.locator(`[data-preview-view="${view}"]`).click();await check(`project-${view}-${width}`);}
  }
  console.log(`PASS: ${states} populated/empty library tabs, job sections, daily-work and project views on desktop/mobile; no backend, browser errors, page overflow or undersized body/control text.`);
 }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exit(1)});
