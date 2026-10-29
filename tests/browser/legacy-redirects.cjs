// Execute the actual legacy redirect documents; destination business scripts never run.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {chromium}=require('playwright');
const root=path.resolve(__dirname,'../..');
const cases=[
 ['approvals/index.html','/tasks/index.html?scope=APPROVAL'],
 ['completed/index.html','/tasks/index.html?scope=COMPLETED'],
 ['follow-up/index.html','/workspace/index.html'],
 ['index.html','/landing.html'],
 ['my-day/index.html','/tasks/index.html?scope=TODAY&owner=me'],
 ['team/index.html?q=synthetic#details','/admin/employees.html?q=synthetic#details']
];
(async()=>{
 const browser=await chromium.launch({headless:true,args:['--no-sandbox']});
 try{
  const page=await browser.newPage();let sourcePath='';
  await page.route('**/*',route=>{
   const url=new URL(route.request().url());
   if(url.hostname!=='127.0.0.1')return route.abort();
   if(url.pathname===sourcePath)return route.fulfill({body:fs.readFileSync(path.join(root,url.pathname)),contentType:'text/html'});
   return route.fulfill({body:'<!doctype html><html lang="ar"><head><title>Isolated destination</title></head><body><h1>وجهة اختبار معزولة</h1></body></html>',contentType:'text/html'});
  });
  for(const [source,target]of cases){
   sourcePath=new URL(source,'http://127.0.0.1:8765/').pathname;
   await page.goto('http://127.0.0.1:8765/'+source);
   await page.waitForURL('http://127.0.0.1:8765'+target);
   assert.equal(new URL(page.url()).pathname+new URL(page.url()).search+new URL(page.url()).hash,target);
   assert(await page.getByRole('heading',{name:'وجهة اختبار معزولة'}).isVisible());
  }
  console.log('PASS: all six application redirect routes; correct scope/owner and team query/hash retained; no backend or external traffic.');
 }finally{await browser.close()}
})().catch(error=>{console.error(error);process.exit(1)});
