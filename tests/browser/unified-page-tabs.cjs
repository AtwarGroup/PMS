// Check every real content page with its actual shell/CSS, without business scripts or backend access.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {chromium}=require(process.env.ATWAR_PLAYWRIGHT_MODULE||'playwright');
const root=path.resolve(__dirname,'../..');
const walk=d=>fs.readdirSync(d,{withFileTypes:true}).flatMap(e=>['.git','node_modules','tests','assets','supabase','scripts'].includes(e.name)?[]:e.isDirectory()?walk(path.join(d,e.name)):e.name.endsWith('.html')?[path.join(d,e.name)]:[]);
(async()=>{const browser=await chromium.launch({headless:true,...(process.env.ATWAR_CHROMIUM_PATH?{executablePath:process.env.ATWAR_CHROMIUM_PATH}:{}),args:['--no-sandbox','--disable-dev-shm-usage','--no-zygote','--single-process','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});try{
const page=await browser.newPage();await page.addInitScript(()=>localStorage.setItem('atwarSession',JSON.stringify({id:'visual-only',full_name:'حساب اختبار محلي',role:'admin'})));
await page.route('**/*',route=>{const u=new URL(route.request().url()),f=path.join(root,decodeURIComponent(u.pathname));if(u.hostname!=='127.0.0.1')return route.fulfill({body:'',contentType:'text/plain'});if(!fs.existsSync(f)||!fs.statSync(f).isFile())return route.fulfill({status:404,body:''});if(f.endsWith('.js')||f.endsWith('.mjs')){if(!/\/(shell-components\.js|mobile-experience\.mjs|ui-feedback\.js)$/.test(u.pathname))return route.fulfill({body:'',contentType:'text/javascript'});}
let body=fs.readFileSync(f);if(f.endsWith('.html'))body=Buffer.from(body.toString().replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi,tag=>tag.includes('src=')&&(tag.includes('shell-components.js')||tag.includes('ui-feedback.js'))?tag:'').replace(/<meta[^>]*http-equiv=["']refresh["'][^>]*>/gi,''));return route.fulfill({body,contentType:f.endsWith('.html')?'text/html':f.endsWith('.css')?'text/css':/\.m?js$/.test(f)?'text/javascript':f.endsWith('.svg')?'image/svg+xml':'text/plain'});});

const cases=[['tasks/index.html','.atwar-header-task-nav'],['tasks/index.html?scope=COMPLETED','.atwar-header-task-nav'],['recurring/index.html','.atwar-header-task-nav'],['tasks/executive.html','.atwar-header-task-nav'],['admin/employees.html','.hr-tabs'],['fleet/index.html','.fleet-tabs'],['fleet/completed.html','.fleet-tabs'],['recruitment/index.html','.rec-tabs'],['workspace/index.html','.space-tabs'],['job-library/index.html','.view-tabs']];
for(const width of [1440,390])for(const [url,selector] of cases){
 await page.setViewportSize({width,height:900});await page.goto('http://127.0.0.1:8765/'+url);
 await page.evaluate(()=>{document.body.style.visibility='visible';document.getElementById('appShell')?.classList.remove('hidden');document.getElementById('authLoadingScreen')?.remove()});
 const tabs=page.locator(selector);await tabs.waitFor({state:'visible'});
 const result=await tabs.evaluate(nav=>{const s=getComputedStyle(nav),r=nav.getBoundingClientRect(),control=[...nav.children].find(e=>e.matches('button,a')&&!e.hidden),c=getComputedStyle(control);return{shared:nav.classList.contains('atwar-tabs'),bg:s.backgroundColor,wrap:s.flexWrap,height:control.getBoundingClientRect().height,color:c.color,border:c.borderBottomWidth,inside:r.left>=-1&&r.right<=innerWidth+1,inHeader:!!nav.closest('atwar-header')}});
 assert(result.shared,url);assert.equal(result.bg,'rgb(234, 240, 247)',url);assert.equal(result.wrap,'nowrap',url);assert(result.height>=40,url);assert.equal(result.border,'0px',url);assert(result.inside,`${url} at ${width}`);assert(!result.inHeader,url);
 if(selector==='.atwar-header-task-nav'){
  assert.equal(await tabs.locator('[aria-current="page"]').count(),1,url);
  assert(await tabs.evaluate(nav=>nav.previousElementSibling.matches('.task-suite-hero')),url);
 }
 // Selection uses each module's own state attribute, and hidden permission tabs stay hidden.
 await tabs.evaluate(nav=>{for(const el of nav.children){el.classList.remove('active');el.removeAttribute('aria-current');el.removeAttribute('aria-pressed');el.setAttribute('aria-selected','false')}const button=nav.querySelector('button,a');button.setAttribute('aria-selected','true');const hidden=document.createElement('button');hidden.hidden=true;hidden.textContent='hidden permission test';nav.append(hidden)});
 await page.waitForFunction(selector=>getComputedStyle(document.querySelector(selector+' [aria-selected="true"]')).backgroundColor==='rgb(255, 255, 255)',selector);
 assert.equal(await tabs.locator('[hidden]').last().evaluate(e=>getComputedStyle(e).display),'none',url);
 await tabs.locator('[aria-selected="true"]').focus();
 assert.equal(await tabs.locator('[aria-selected="true"]').evaluate(e=>getComputedStyle(e).outlineStyle),'solid',url);
}
console.log('PASS: unified tabs on 10 real page routes at desktop/mobile, selected states, focus, hidden controls and task navigation placement.');
}finally{await browser.close();}})().catch(e=>{console.error(e);process.exit(1)});
