// Real shell and page CSS with business scripts removed. No backend requests are permitted.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {chromium}=require('playwright');
const root=path.resolve(__dirname,'../..');
(async()=>{
 const browser=await chromium.launch({headless:true,args:['--no-sandbox']});
 try{
  for(const width of [1440,412,390,360]){
   const page=await browser.newPage({viewport:{width,height:900}});
   let releaseParser;const parserBlocked=new Promise(resolve=>{releaseParser=resolve});
   const cssRequests=[];
   await page.route('**/*',async route=>{
    const url=new URL(route.request().url());
    if(url.hostname!=='127.0.0.1')return route.fulfill({body:'',contentType:'text/plain'});
    if(url.pathname==='/hold-parser.js'){await parserBlocked;return route.fulfill({body:'',contentType:'text/javascript'})}
    const file=path.join(root,url.pathname);
    if(url.pathname.endsWith('/app-theme.css'))cssRequests.push(url.href);
    if(!fs.existsSync(file)||!fs.statSync(file).isFile())return route.fulfill({status:404,body:''});
    if(url.pathname.endsWith('.html')){
     let html=fs.readFileSync(file,'utf8').replace(/<link\b[^>]*app-theme\.css[^>]*>/gi,'').replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi,tag=>tag.includes('src=')&&tag.includes('shell-components.js')?tag+'<script src="/hold-parser.js"></script>':'');
     return route.fulfill({body:html,contentType:'text/html'});
    }
    if(/\.m?js$/.test(url.pathname)&&!url.pathname.endsWith('/shell-components.js'))return route.fulfill({body:'',contentType:'text/javascript'});
    return route.fulfill({body:fs.readFileSync(file),contentType:url.pathname.endsWith('.css')?'text/css':url.pathname.endsWith('.js')?'text/javascript':'text/plain'});
   });
   const earlyTheme=page.waitForRequest(request=>new URL(request.url()).pathname.endsWith('/app-theme.css'));
   const navigation=page.goto('http://127.0.0.1:8765/tasks/index.html');
   try{
    await earlyTheme;
    assert.equal(await page.evaluate(()=>document.readyState),'loading','Theme request must start before parsing finishes');
   }finally{releaseParser()}
   await navigation;
   await page.waitForFunction(()=>document.readyState==='complete');
   assert.equal(await page.locator('link[data-atwar-app-theme]').count(),1);
   assert.equal(cssRequests.length,1,'Reordering CSS must not fetch a second version');
   assert.equal(await page.locator('link[data-atwar-typography]').count(),1);
   assert.equal(await page.evaluate(()=>getComputedStyle(document.body).fontSize===getComputedStyle(document.documentElement).getPropertyValue('--atwar-type-body').trim()),true,'Typography must remain after page styles');
   assert.equal(await page.evaluate(()=>getComputedStyle(document.documentElement).getPropertyValue('--atwar-blue-600').trim()),'#1769e0');
   await page.close();
  }
  console.log('PASS: canonical theme starts before DOMContentLoaded, loads once and preserves approved tokens at desktop/Android viewport widths.');
 }finally{await browser.close()}
})().catch(error=>{console.error(error);process.exit(1)});
