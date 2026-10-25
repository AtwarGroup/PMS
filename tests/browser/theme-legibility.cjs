// Visual regression for the reported entry-card contrast and task/header differences.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {chromium}=require(process.env.ATWAR_PLAYWRIGHT_MODULE||'playwright');
const root=path.resolve(__dirname,'../..');
(async()=>{const browser=await chromium.launch({headless:true,...(process.env.ATWAR_CHROMIUM_PATH?{executablePath:process.env.ATWAR_CHROMIUM_PATH}:{}),args:['--no-sandbox','--disable-dev-shm-usage','--no-zygote','--single-process','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});try{
 const page=await browser.newPage();await page.addInitScript(()=>localStorage.setItem('atwarSession',JSON.stringify({id:'visual-only',full_name:'حساب اختبار محلي',role:'admin'})));
 await page.route('**/*',route=>{const u=new URL(route.request().url()),f=path.join(root,decodeURIComponent(u.pathname));if(u.hostname!=='127.0.0.1')return route.fulfill({body:'',contentType:'text/javascript'});if(!f.startsWith(root+path.sep)||!fs.existsSync(f)||!fs.statSync(f).isFile())return route.fulfill({status:404,body:''});let body=fs.readFileSync(f);if(f.endsWith('.html')&&!u.pathname.includes('/fixtures/'))body=Buffer.from(body.toString().replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi,tag=>u.pathname==='/landing.html'||(/src=/.test(tag)&&/shell-components.js|ui-feedback.js/.test(tag))?tag:''));if(/\.m?js$/.test(f)&&!u.pathname.includes('/fixtures/')&&!/shell-components.js|ui-feedback.js|mobile-experience.mjs|systems-config.js/.test(f))return route.fulfill({body:'',contentType:'text/javascript'});return route.fulfill({body,contentType:f.endsWith('.html')?'text/html':f.endsWith('.css')?'text/css':'text/javascript'});});
 for(const width of [1920,1440,1024,768,390])for(const file of ['landing.html','workspace/index.html','tasks/index.html','recurring/index.html']){
  await page.setViewportSize({width,height:1000});await page.goto('http://127.0.0.1:8765/'+file);if(file==='tasks/index.html')await page.evaluate(()=>{document.getElementById('authLoadingScreen').style.setProperty('display','none','important');document.getElementById('appShell').classList.remove('hidden')});await page.waitForFunction(()=>getComputedStyle(document.body).fontSize===getComputedStyle(document.documentElement).getPropertyValue('--atwar-type-body').trim());
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth+2),false,`${file} overflow ${width}`);
  if(file==='landing.html'){
   await page.waitForFunction(()=>document.querySelectorAll('.app-card').length===4);
   const contrast=await page.locator('.app-card').evaluateAll(cards=>{const rgb=s=>s.match(/[\d.]+/g).map(Number);const lum=c=>{c=c.slice(0,3).map(v=>{v/=255;return v<=.04045?v/12.92:((v+.055)/1.055)**2.4});return c[0]*.2126+c[1]*.7152+c[2]*.0722};return cards.flatMap(card=>[...card.querySelectorAll('h3,p')].map(e=>{const rgba=rgb(getComputedStyle(card).backgroundColor),alpha=rgba[3]??1;const base=[13,53,98];const background=rgba.slice(0,3).map((v,i)=>v*alpha+base[i]*(1-alpha));const a=lum(rgb(getComputedStyle(e).color)),b=lum(background);return (Math.max(a,b)+.05)/(Math.min(a,b)+.05)}))});assert(contrast.every(c=>c>=4.5),`Entry text contrast ${contrast}`);
   assert.match(await page.locator('body').evaluate(e=>getComputedStyle(e).backgroundImage),/rgb\(7, 24, 47\).*rgb\(12, 39, 74\).*rgb\(13, 53, 98\)/,'Keep the original navy portal palette');
  }else{
   assert(await page.locator('.atwar-top-brand').isVisible(),`${file} missing shared identity`);
   if(width>1100)assert(await page.locator('.atwar-sidebar').isVisible(),`${file} sidebar missing`);
   const rect=await page.locator('.atwar-topbar').boundingBox();assert(rect.x>=-1&&rect.x+rect.width<=width+1,`${file} header width`);
   if(width===1920){const box=await page.locator('.atwar-content,.task-suite-page').first().boundingBox();assert(box.width>1500,`${file} unnecessarily narrow desktop content`)}
   if(width===390){assert(Math.abs(rect.y)<2,`${file} mobile header must start at top`);assert(Math.abs(rect.width-width)<2,`${file} mobile shell must fill viewport`);await page.locator('.atwar-mobile-menu').click();assert.equal(await page.locator('.atwar-mobile-menu').getAttribute('aria-expanded'),'true');assert(await page.locator('.atwar-sidebar').isVisible());await page.keyboard.press('Escape');assert.equal(await page.locator('.atwar-mobile-menu').getAttribute('aria-expanded'),'false');}
  }
  if(process.env.ATWAR_THEME_SCREENSHOTS){fs.mkdirSync(process.env.ATWAR_THEME_SCREENSHOTS,{recursive:true});await page.screenshot({path:path.join(process.env.ATWAR_THEME_SCREENSHOTS,file.replaceAll('/','_')+'-'+width+'.png')});}
 }
 console.log('PASS: entry card text contrast >=4.5, shared module identity, desktop sidebar/content width and mobile navigation at five viewport widths.');
}finally{await browser.close()}})().catch(e=>{console.error(e);process.exit(1)});
